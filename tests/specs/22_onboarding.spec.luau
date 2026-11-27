-- Les 10 premières minutes : onglets débloqués petit à petit, onglet mis en
-- avant, objectifs de départ avec petite récompense (vérifiée par le serveur),
-- anciens profils, interface.
local S = H.boot(MODULES)
local Onboarding = S.Onboarding
local store = H.getStore(S.Config.DATASTORE_NAME)

local function snapshot(player)
	return S.PlayerDataService.BuildSnapshot(player)
end

local function finishTutorial(player, data)
	data.tutorial.completed = true
	S.PlayerDataService.MarkChanged(player)
	H.flush()
end

H.test("nouveau club : objectifs prêts, mais rien avant la fin du tutoriel", function()
	local p = H.join(1)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.onboarding.goal, 1, "premier objectif")
	H.eq(data.onboarding.done, false, "pas terminé")
	H.eq(snapshot(p).onboarding.current, nil, "aucun objectif pendant le tutoriel")
	local coins = data.coins
	H.fire(p, "RequestOnboardingClaim")
	H.eq(data.coins, coins, "rien versé")
	H.leave(p)
end)

H.test("onglets : Gestion après le tutoriel, Classement après 3 matchs, Prestige après 5", function()
	local p = H.join(2)
	local data = S.PlayerDataService.GetData(p)
	local snap = snapshot(p)
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Settings" } do
		H.ok(Onboarding.TabUnlocked(tab, snap), tab .. " toujours ouvert")
	end
	local ok, rule = Onboarding.TabUnlocked("Management", snap)
	H.eq(ok, false, "Gestion bloquée")
	H.eq(rule, "tutorial", "raison : tutoriel")
	ok, rule = Onboarding.TabUnlocked("Ranking", snap)
	H.eq(ok, false, "Classement bloqué")
	H.eq(rule, "matches", "raison : matchs")
	finishTutorial(p, data)
	data.club.stats.played = 3
	snap = snapshot(p)
	H.ok(Onboarding.TabUnlocked("Management", snap), "Gestion ouverte")
	H.ok(Onboarding.TabUnlocked("Ranking", snap), "Classement ouvert")
	H.eq(Onboarding.TabUnlocked("Prestige", snap), false, "Prestige encore bloqué")
	data.club.stats.played = 5
	H.ok(Onboarding.TabUnlocked("Prestige", snapshot(p)), "Prestige ouvert")
	-- Un club monté en D6 voit tout, même sans avoir fini le tutoriel.
	data.tutorial.completed = false
	data.club.stats.played = 0
	data.club.division = "D6"
	for _, tab in { "Management", "Ranking", "Prestige" } do
		H.ok(Onboarding.TabUnlocked(tab, snapshot(p)), tab .. " ouvert en D6")
	end
	H.leave(p)
end)

H.test("onglet mis en avant : celui de l'étape du tutoriel, puis celui de l'objectif", function()
	local p = H.join(3)
	local data = S.PlayerDataService.GetData(p)
	H.eq(Onboarding.FocusTab(snapshot(p), "FirstUpgrade"), "Stadium", "tutoriel : Stade")
	H.eq(Onboarding.FocusTab(snapshot(p), "FirstMatch"), "Matches", "tutoriel : Matchs")
	finishTutorial(p, data)
	H.eq(Onboarding.FocusTab(snapshot(p)), "Stadium", "objectif 1 : Stade")
	H.leave(p)
end)

H.test("objectif réussi : récompense exacte, une seule fois, vérifiée par le serveur", function()
	local p = H.join(4)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {} -- pas de prime de mission dans les montants exacts
	data.coins = 100000
	finishTutorial(p, data)
	H.fire(p, "RequestUpgrade", "Pitch")
	local goal = snapshot(p).onboarding.current
	H.eq(goal.id, "Upgrade", "objectif améliorations")
	H.eq(goal.progress, 1, "1 amélioration sur 2")
	H.eq(goal.ready, false, "pas encore réussi")
	local coins = data.coins
	H.fire(p, "RequestOnboardingClaim")
	H.eq(data.coins, coins, "refusé tant que ce n'est pas fait")
	H.advance(2)
	H.fire(p, "RequestUpgrade", "Stands")
	H.eq(snapshot(p).onboarding.current.ready, true, "réussi")
	coins = data.coins
	H.fire(p, "RequestOnboardingClaim")
	H.eq(data.coins, coins + 250, "+250 FC")
	H.ok((H.lastNotify(p) or ""):find("Objectif réussi", 1, true), "message de réussite")
	H.eq(data.onboarding.goal, 2, "objectif suivant")
	H.fire(p, "RequestOnboardingClaim")
	H.fire(p, "RequestOnboardingClaim", "x", 999)
	H.eq(data.coins, coins + 250, "pas de double paiement")
	H.leave(p)
end)

H.test("les 6 objectifs à la suite : total versé, puis plus rien", function()
	local p = H.join(5)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	finishTutorial(p, data)
	local start = data.coins
	data.buildings.Pitch, data.buildings.Stands = 2, 2
	data.club.stats.wins = 3
	data.squad[1].trainedAt = 1
	local staffId = next(data.staff)
	data.staff[staffId] = 1
	table.insert(data.sponsors.contracts, { id = 999, sponsorId = "test", endsAt = os.time() + 3600 })
	data.club.division = "D6"
	local ids = {}
	for _ = 1, #Onboarding.GOALS do
		table.insert(ids, snapshot(p).onboarding.current.id)
		H.fire(p, "RequestOnboardingClaim")
	end
	H.eq(table.concat(ids, ","), "Upgrade,Win,Train,Staff,Sponsor,Promote", "ordre des objectifs")
	H.eq(data.coins, start + Onboarding.TotalRewards(), "total des récompenses")
	H.eq(Onboarding.TotalRewards(), 2450, "récompenses modestes")
	H.eq(data.onboarding.done, true, "terminé")
	H.ok((H.lastNotify(p) or ""):find("tous les objectifs", 1, true), "message final")
	H.eq(snapshot(p).onboarding.current, nil, "plus d'objectif")
	H.fire(p, "RequestOnboardingClaim")
	H.eq(data.coins, start + Onboarding.TotalRewards(), "plus rien à récupérer")
	H.leave(p)
end)

H.test("objectifs gardés après une déconnexion", function()
	local p = H.join(6)
	local data = S.PlayerDataService.GetData(p)
	finishTutorial(p, data)
	data.buildings.Pitch, data.buildings.Stands = 2, 2
	H.fire(p, "RequestOnboardingClaim")
	H.leave(p)
	H.advance(10)
	p = H.join(6)
	data = S.PlayerDataService.GetData(p)
	H.eq(data.onboarding.goal, 2, "objectif 2 conservé")
	H.leave(p)
end)

-- Profil enregistré avant cette mise à jour (sans champ « onboarding »).
local function oldProfile(userId: number, division: string, played: number)
	local p = H.join(userId)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	data.onboarding = nil
	data.tutorial = { step = 6, completed = true }
	data.club.division = division
	data.club.stats.played = played
	store.data["player_" .. userId] = { data = data, lock = nil }
end

H.test("ancien club installé : pas de récompenses de débutant, tous les onglets ouverts", function()
	oldProfile(901, "D4", 40)
	local p = H.join(901)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.onboarding.done, true, "objectifs déjà considérés comme faits")
	H.eq(data.club.division, "D4", "progression gardée")
	local snap = snapshot(p)
	H.eq(snap.onboarding.current, nil, "pas d'objectif")
	for _, tab in { "Management", "Ranking", "Prestige" } do
		H.ok(Onboarding.TabUnlocked(tab, snap), tab .. " ouvert")
	end
	H.leave(p)
end)

H.test("ancien club tout neuf (D7, 2 matchs) : reçoit les objectifs de départ", function()
	oldProfile(902, "D7", 2)
	local p = H.join(902)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.onboarding.done, false, "objectifs proposés")
	H.eq(snapshot(p).onboarding.current.id, "Upgrade", "premier objectif")
	H.leave(p)
end)

H.test("interface : cadenas, onglet en avant, bandeau d'objectif et bouton Récupérer", function()
	local p = H.join(10)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	local menuButton = nil
	for _, d in gui:GetDescendants() do
		if d.Name == "MenuButton" then
			menuButton = d
		end
	end
	H.ok(menuButton, "bouton du menu")
	H.advance(9) -- étape 1 validée après quelques secondes sur le terrain
	H.flush()
	H.eq(data.tutorial.step, 2, "étape « ouvre le menu »")
	H.eq(menuButton:GetAttribute("Focus"), true, "bouton du menu mis en avant")
	UI.SetMenuOpen(true)
	H.flush()
	local lockedTab = H.findText(gui, "🔒 Gestion", "TextButton")
	H.ok(lockedTab, "onglet Gestion avec cadenas")
	H.eq(lockedTab:GetAttribute("Locked"), true, "marqué bloqué")
	lockedTab.Activated:Fire()
	H.flush()
	H.ok(H.findText(gui, "s'ouvre à la fin du tutoriel"), "explication affichée")
	H.ok(H.findText(gui, "🔒 Classement", "TextButton"), "Classement avec cadenas")
	-- Fin du tutoriel : Gestion se débloque (annonce), objectif de départ affiché.
	finishTutorial(p, data)
	H.ok(H.findText(gui, "Nouvel onglet débloqué"), "annonce du déblocage")
	H.eq(H.findText(gui, "🔒 Gestion", "TextButton"), nil, "plus de cadenas sur Gestion")
	H.ok(H.findText(gui, "Objectif de départ 1/6"), "bandeau d'objectif")
	local stadium = H.findText(gui, "Stade", "TextButton")
	H.eq(stadium:GetAttribute("Focus"), true, "onglet Stade mis en avant")
	local claim = H.findText(gui, "Récupérer", "TextButton")
	H.ok(claim and not claim.Visible, "bouton caché tant que ce n'est pas fait")
	data.buildings.Pitch, data.buildings.Stands = 2, 2
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	claim = H.findText(gui, "Récupérer +250", "TextButton")
	H.ok(claim and claim.Visible, "bouton Récupérer visible")
	local coins = data.coins
	claim.Activated:Fire()
	H.flush()
	H.eq(data.coins, coins + 250, "récompense reçue par le bouton")
	H.ok(H.findText(gui, "Objectif de départ 2/6"), "objectif suivant affiché")
	H.leave(p)
end)

H.finish()
