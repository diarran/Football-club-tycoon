-- Succès : 20 succès calculés à partir du profil, primes à récupérer une
-- seule fois, anciens profils servis tout de suite, badges Roblox donnés
-- seulement quand leur numéro est rempli, interface (Prestige + accueil).
local S = H.boot(MODULES)
local Achievements = mock.run(MODULES.Achievements)
local AchievementService = mock.run(MODULES.AchievementService)
local store = H.getStore(S.Config.DATASTORE_NAME)

local function snapshot(player)
	return S.PlayerDataService.BuildSnapshot(player).achievements
end

local function changed(player)
	S.PlayerDataService.MarkChanged(player)
	H.flush()
end

-- Faux BadgeService : enregistre les appels, peut échouer.
local function fakeBadges()
	local fake = { calls = {}, fail = false, owned = {} }
	function fake:AwardBadgeAsync(userId, badgeId)
		table.insert(fake.calls, { userId, badgeId })
		if fake.fail then
			error("HTTP 500")
		end
		if fake.owned[badgeId] then
			return false
		end
		fake.owned[badgeId] = true
		return true
	end
	function fake:UserHasBadgeAsync(_, badgeId)
		return fake.owned[badgeId] == true
	end
	return fake
end

H.test("liste : 20 succès, textes FR/EN, 10 badges prévus, primes modestes", function()
	H.eq(#Achievements.LIST, 20, "20 succès")
	local badges = 0
	for id in Achievements.BADGE_IDS do
		badges += 1
		H.ok(Achievements.Get(id), "badge relié à un succès : " .. id)
		H.eq(Achievements.BadgeId(id), nil, "aucun numéro rempli par défaut : " .. id)
	end
	H.eq(badges, 10, "10 badges Roblox prévus")
	local seen = {}
	for _, def in Achievements.LIST do
		H.ok(not seen[def.id], "identifiant unique " .. def.id)
		seen[def.id] = true
		H.ok(def.reward > 0 and def.reward <= 10000, "prime raisonnable " .. def.id)
		for _, lang in { "fr", "en" } do
			for _, key in { "achievement." .. def.id, "achievement." .. def.id .. ".desc" } do
				local text = S.Locale.T(lang, key)
				H.ok(text ~= key and text ~= "", lang .. " : " .. key)
			end
		end
	end
	H.eq(Achievements.TotalRewards(), 47750, "total des primes")
end)

H.test("nouveau club : rien de débloqué, rien à récupérer", function()
	local p = H.join(1)
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	local snap = snapshot(p)
	H.eq(snap.total, 20, "20 succès affichés")
	H.eq(snap.unlocked, 0, "aucun débloqué")
	H.eq(snap.ready, 0, "rien à récupérer")
	H.eq(snap.list[1].id, "first_win", "première victoire en tête")
	H.eq(snap.list[1].progress, 0, "0/1")
	local coins = data.coins
	H.fire(p, "RequestAchievementClaim")
	H.eq(data.coins, coins, "rien versé")
	H.leave(p)
end)

H.test("première victoire (vrai match) : débloquée, prime versée une seule fois", function()
	local p = H.join(2)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.tutorial.completed = true
	H.flush()
	-- Vrais matchs contre l'IA, rejoués jusqu'à la première victoire.
	local tries = 0
	while data.club.stats.wins == 0 and tries < 40 do
		tries += 1
		H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
		for _, f in data.squad do
			f.energy = 100
		end
		H.fire(p, "RequestMatch", "ai", "Balanced")
		H.flush()
	end
	H.ok(data.club.stats.wins >= 1, "victoire obtenue")
	H.ok(data.achievements.unlocked.first_win, "succès débloqué")
	local snap = snapshot(p)
	H.eq(snap.ready, 1, "une prime à récupérer")
	local coins = data.coins
	H.fire(p, "RequestAchievementClaim")
	H.eq(data.coins, coins + 100, "prime de 100 FC versée")
	H.ok((H.lastNotify(p) or ""):find("succès", 1, true), "message de réussite")
	H.eq(data.achievements.claimed.first_win, true, "noté récupéré")
	local after = data.coins
	H.fire(p, "RequestAchievementClaim")
	H.fire(p, "RequestAchievementClaim", "first_win", 999)
	H.eq(data.coins, after, "pas de double paiement")
	H.eq(snapshot(p).ready, 0, "plus rien à récupérer")
	H.leave(p)
end)

H.test("plusieurs succès d'un coup : primes additionnées", function()
	local p = H.join(3)
	local data = S.PlayerDataService.GetData(p)
	data.club.stats.wins = 10
	data.club.stats.goalsFor = 100
	data.club.division = "D5"
	changed(p)
	local snap = snapshot(p)
	H.eq(snap.unlocked, 5, "victoire, 10 victoires, 100 buts, D6, D5")
	local coins = data.coins
	H.fire(p, "RequestAchievementClaim")
	H.eq(data.coins, coins + 100 + 250 + 500 + 300 + 600, "total exact")
	H.leave(p)
end)

H.test("un succès débloqué le reste (joueur vendu, note qui baisse)", function()
	local p = H.join(4)
	local data = S.PlayerDataService.GetData(p)
	data.squad[1].rating = 81
	changed(p)
	H.ok(data.achievements.unlocked.player_80, "star débloquée")
	data.squad[1].rating = 50
	changed(p)
	local entry
	for _, e in snapshot(p).list do
		if e.id == "player_80" then
			entry = e
		end
	end
	H.eq(entry.unlocked, true, "toujours débloqué")
	H.eq(entry.progress, 80, "affiché complet")
	H.leave(p)
end)

H.test("ancien profil : succès mérités donnés tout de suite, primes à récupérer", function()
	local p = H.join(5)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	data.achievements = nil
	data.club.division = "D3"
	data.club.stats.wins = 120
	data.club.stats.goalsFor = 400
	data.club.stats.cupsWon = 1
	data.trophies.titles = 0
	store.data["player_5"] = { data = data, lock = nil }
	H.warnings = {}
	p = H.join(5)
	H.flush()
	local live = S.PlayerDataService.GetData(p)
	local snap = snapshot(p)
	for _, id in { "first_win", "wins_10", "wins_100", "goals_100", "promo_D6", "promo_D5", "promo_D4", "promo_D3", "cup_winner" } do
		H.ok(live.achievements.unlocked[id], "débloqué : " .. id)
	end
	H.eq(live.achievements.unlocked.promo_D2, nil, "D2 pas encore")
	H.eq(snap.ready, snap.unlocked, "toutes les primes à récupérer")
	H.eq(#H.warnings, 0, "aucun avertissement")
	H.leave(p)
end)

H.test("sauvegarde : succès et primes récupérées gardés après reconnexion", function()
	local p = H.join(6)
	local data = S.PlayerDataService.GetData(p)
	data.club.stats.wins = 1
	changed(p)
	H.fire(p, "RequestAchievementClaim")
	H.leave(p)
	H.advance(5)
	p = H.join(6)
	H.flush()
	data = S.PlayerDataService.GetData(p)
	H.ok(data.achievements.unlocked.first_win, "débloqué gardé")
	H.eq(data.achievements.claimed.first_win, true, "récupéré gardé")
	local coins = data.coins
	H.fire(p, "RequestAchievementClaim")
	H.eq(data.coins, coins, "pas payé deux fois")
	H.leave(p)
end)

H.test("profil abîmé : champ des succès réparé sans erreur", function()
	local p = H.join(7)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	data.achievements = { unlocked = "oups", claimed = 12 }
	store.data["player_7"] = { data = data, lock = nil }
	p = H.join(7)
	H.flush()
	local live = S.PlayerDataService.GetData(p)
	H.eq(type(live.achievements.unlocked), "table", "débloqués réparés")
	H.eq(type(live.achievements.claimed), "table", "récupérés réparés")
	H.eq(type(live.achievements.badges), "table", "badges réparés")
	H.eq(snapshot(p).total, 20, "liste affichée")
	H.leave(p)
end)

H.test("badges : aucun appel sans numéro, donné une fois avec numéro, nouvel essai après échec", function()
	local fake = fakeBadges()
	local original = AchievementService.GetBadgeService
	AchievementService.GetBadgeService = function()
		return fake
	end
	local p = H.join(8)
	local data = S.PlayerDataService.GetData(p)
	data.club.stats.wins = 1
	changed(p)
	H.eq(#fake.calls, 0, "aucun badge tant que le numéro vaut 0")

	Achievements.BADGE_IDS.first_win = 111
	changed(p)
	H.eq(#fake.calls, 1, "badge demandé à Roblox")
	H.eq(fake.calls[1][1], 8, "bon joueur")
	H.eq(fake.calls[1][2], 111, "bon badge")
	H.eq(data.achievements.badges.first_win, true, "noté donné")
	changed(p)
	H.eq(#fake.calls, 1, "pas redemandé")

	-- Échec de Roblox : pas noté, pas de nouvel essai dans la même partie.
	Achievements.BADGE_IDS.goals_100 = 222
	fake.fail = true
	data.club.stats.goalsFor = 100
	changed(p)
	H.eq(#fake.calls, 2, "un essai")
	H.eq(data.achievements.badges.goals_100, nil, "pas noté donné")
	changed(p)
	H.eq(#fake.calls, 2, "pas d'essai en boucle")
	H.leave(p)
	H.advance(5)
	fake.fail = false
	p = H.join(8)
	H.flush()
	data = S.PlayerDataService.GetData(p)
	H.eq(#fake.calls, 3, "nouvel essai à la partie suivante")
	H.eq(data.achievements.badges.goals_100, true, "donné cette fois")

	-- Badge déjà possédé sur Roblox (profil recréé) : noté donné aussi.
	Achievements.BADGE_IDS.promo_D5 = 333
	fake.owned[333] = true
	data.club.division = "D5"
	changed(p)
	H.eq(data.achievements.badges.promo_D5, true, "déjà possédé : noté")
	H.leave(p)

	Achievements.BADGE_IDS.first_win = 0
	Achievements.BADGE_IDS.goals_100 = 0
	Achievements.BADGE_IDS.promo_D5 = 0
	AchievementService.GetBadgeService = original
end)

H.test("interface : rappel sur l'accueil, annonce, liste dans Prestige, bouton Récupérer", function()
	local p = H.join(9)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.tutorial.completed = true
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.flush()
	H.eq(H.findText(gui, "Voir mes succès", "TextButton"), nil, "pas de rappel sans prime")
	data.club.stats.wins = 1
	changed(p)
	H.ok(H.findText(gui, "Succès débloqué : Première victoire"), "annonce du succès")
	H.ok(H.findText(gui, "1 succès débloqués ont une récompense"), "rappel sur l'accueil")
	local open = H.findText(gui, "Voir mes succès", "TextButton")
	H.ok(open, "bouton vers les succès")
	open.Activated:Fire()
	H.flush()
	H.ok(H.findText(gui, "Succès : 1/20"), "compteur dans Prestige")
	H.ok(H.findText(gui, "Récompense à récupérer : 100 FC"), "ligne prête")
	H.ok(H.findText(gui, "Progression : 1/10"), "progression des 10 victoires")
	local claim = H.findText(gui, "Récupérer 100 FC", "TextButton")
	H.ok(claim, "bouton Récupérer")
	local coins = data.coins
	claim.Activated:Fire()
	H.flush()
	H.eq(data.coins, coins + 100, "prime reçue par le bouton")
	H.ok(H.findText(gui, "Récompense déjà récupérée"), "ligne marquée récupérée")
	H.eq(H.findText(gui, "Récupérer 100 FC", "TextButton"), nil, "bouton parti")
	H.leave(p)
end)

H.finish()
