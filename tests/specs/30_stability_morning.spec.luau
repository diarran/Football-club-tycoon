-- Passe de stabilité après les nouveautés du 27/11 (PR #24 à #30) : entraînement
-- et composition, événements de la semaine, début de partie, tactiques,
-- blessures et suspensions, Coupe nationale. On vérifie qu'elles marchent
-- ENSEMBLE : longue session à 6, anciens profils, valeurs abîmées, coupe avec
-- des blessés, fenêtre de résultat et onglet Matchs sur téléphone.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local Injuries, Training, Tactics, Cup = S.Injuries, S.Training, S.Tactics, S.NationalCup

local function hasWarning(fragment: string): string?
	for _, w in H.warnings do
		if string.find(w, fragment, 1, true) then
			return w
		end
	end
	return nil
end

local function totalWrites(): number
	local total = 0
	for _, s in H.stores do
		total += s.writes
	end
	for _, s in H.orderedStores do
		total += s.writes
	end
	return total
end

-- Taille approximative du profil une fois enregistré (JSON) : Roblox accepte
-- 4 Mo par clé, on vise très en dessous pour que le profil ne grossisse pas.
local function encodedSize(value, depth: number?): number
	depth = depth or 0
	assert(depth < 20, "profil trop profond")
	local t = type(value)
	if t == "table" then
		local size = 2
		for k, v in value do
			size += #tostring(k) + 4 + encodedSize(v, depth + 1)
		end
		return size
	elseif t == "string" then
		return #value + 2
	end
	return #tostring(value)
end

-- Aucun joueur blessé ou suspendu parmi les titulaires, composition valide.
local function checkLineup(data, label: string)
	local now = os.time()
	local ids = {}
	for _, f in data.squad do
		ids[f.id] = true
	end
	for _, f in S.SquadService.Starters(data) do
		H.ok(Injuries.IsAvailable(f, now), label .. " : titulaire indisponible " .. tostring(f.name))
	end
	for _, id in Training.Normalize(data.squad, data.lineup) do
		H.ok(ids[id], label .. " : titulaire inconnu " .. tostring(id))
	end
	H.ok(#S.SquadService.Starters(data) <= Training.STARTERS, label .. " : 5 titulaires au plus")
end

H.test("longue session à 6 avec toutes les nouveautés : aucune erreur, profils sains", function()
	H.warnings = {}
	local players = {}
	for i = 1, 6 do
		players[i] = H.join(800 + i, "Matin" .. i)
	end
	H.flush()
	for _, p in players do
		S.PlayerDataService.GetData(p).coins = 300000
	end
	local writesBefore = totalWrites()
	local minutes = 45
	local rng = Random.new(42)
	for minute = 1, minutes do
		for i, p in players do
			local data = S.PlayerDataService.GetData(p)
			local tactic = Tactics.ORDER[(minute + i) % #Tactics.ORDER + 1]
			local action = (minute + i) % 7
			if action == 0 or action == 3 then
				H.fire(p, "RequestMatch", "ai:" .. ((minute % 5) + 1), tactic)
			elseif action == 1 then
				H.fire(p, "RequestCupMatch", tactic)
			elseif action == 2 then
				H.fire(p, "RequestTrain", data.squad[(minute % #data.squad) + 1].id)
			elseif action == 4 then
				local f = data.squad[(minute % #data.squad) + 1]
				H.fire(p, "RequestLineup", f.id, minute % 2 == 0)
			elseif action == 5 then
				H.fire(p, "RequestRecruit")
				H.fire(p, "RequestLineup", "auto")
			else
				H.fire(p, "RequestEventClaim")
				H.fire(p, "RequestOnboardingClaim")
				H.fire(p, "RequestHireStaff", "Doctor")
			end
			-- Blessures en plus (bien plus que la normale) pour tout mélanger.
			if rng:NextNumber() < 0.15 then
				local f = data.squad[rng:NextInteger(1, #data.squad)]
				f.injuredUntil = os.time() + rng:NextInteger(60, 600)
			end
			if rng:NextNumber() < 0.05 then
				data.squad[rng:NextInteger(1, #data.squad)].suspended = 1
			end
			checkLineup(data, "minute " .. minute)
		end
		H.advance(60)
	end
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	local bad = hasWarning("[Net] Erreur") or hasWarning("[Main]") or hasWarning("[Cup]")
	H.ok(not bad, "avertissement : " .. tostring(bad))
	local perMinute = (totalWrites() - writesBefore) / minutes
	H.ok(perMinute <= (60 + 10 * 6) / 4, ("écritures par minute : %.1f (limite 120)"):format(perMinute))
	for _, p in players do
		local data = S.PlayerDataService.GetData(p)
		H.ok(data.coins == data.coins and data.coins >= 0, "solde valide")
		H.ok(data.club.stats.played > 0, "matchs de championnat joués")
		H.ok(#data.cup.history >= 1, "au moins un tour de coupe joué")
		H.ok(data.cup.round >= 1 and data.cup.round <= Cup.RoundCount(), "tour de coupe valide")
		for _, f in data.squad do
			H.ok(f.suspended >= 0 and f.suspended <= Injuries.MAX_SUSPENSION, "suspension bornée")
			H.ok(f.yellows >= 0 and f.yellows < Injuries.YELLOWS_FOR_BAN, "cartons bornés")
			H.ok(f.rating <= f.potential, "note sous le potentiel")
		end
		local size = encodedSize(data)
		H.ok(size < 60000, ("profil de %d octets (limite visée 60 000)"):format(size))
	end
	for _, p in players do
		H.leave(p)
	end
	H.advance(10)
	for _, p in players do
		local record = store.data["player_" .. p.UserId]
		H.ok(record and record.data and type(record.data.cup) == "table", "profil enregistré avec la coupe")
	end
	H.eq(#H.errors, 0, "erreurs au départ : " .. tostring(H.errors[1]))
end)

-- Coupe, infirmerie et météo ------------------------------------------------------

local function cupReady(data)
	data.cup.lastPlayedAt = 0
end

H.test("coupe : tout l'effectif blessé -> tour reporté, pas d'élimination", function()
	local p = H.join(820, "Infirmerie")
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	S.CupService.Snapshot(p, data) -- tirage de l'édition
	cupReady(data)
	for _, f in data.squad do
		f.injuredUntil = os.time() + 5 * 60
	end
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(#H.received(p, "MatchResult"), before, "aucun match joué")
	H.eq(data.cup.status, "playing", "toujours en course")
	H.eq(data.cup.round, 1, "même tour")
	H.eq(#data.cup.history, 0, "aucun tour perdu")
	local message = H.lastNotify(p)
	H.ok(message and string.find(tostring(message), "blessés", 1, true), "message clair : " .. tostring(message))
	-- Les blessés reviennent : le tour se joue.
	H.advance(Injuries.MAX_MINUTES * 60 + 1)
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(#H.received(p, "MatchResult"), before + 1, "tour joué après le retour des blessés")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	H.leave(p)
end)

H.test("coupe : que des suspendus -> suspensions levées, le tour se joue", function()
	local p = H.join(821, "Suspendus")
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	S.CupService.Snapshot(p, data)
	cupReady(data)
	for _, f in data.squad do
		f.suspended = 1
	end
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(#H.received(p, "MatchResult"), before + 1, "tour joué")
	for _, f in data.squad do
		H.eq(f.suspended, 0, "suspension levée : " .. f.name)
	end
	H.leave(p)
end)

H.test("coupe : le blessé est remplacé ; pas de fatigue, blessure ni carton en coupe", function()
	local p = H.join(822, "Rotation")
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	S.CupService.Snapshot(p, data)
	cupReady(data)
	data.coins = 100000
	for _ = 1, 3 do
		H.fire(p, "RequestRecruit") -- des remplaçants
		H.advance(2)
	end
	H.ok(#data.squad > Training.STARTERS, "un remplaçant au moins")
	local injured = S.SquadService.Starters(data)[1]
	injured.injuredUntil = os.time() + 300
	local suspended = S.SquadService.Starters(data)[2]
	suspended.suspended = 1
	local seen, seenWeather
	local real = S.MatchService.Simulate
	S.MatchService.Simulate = function(home, away, weather)
		seen, seenWeather = home.squad, weather
		return real(home, away, weather)
	end
	local energy = {}
	for _, f in data.squad do
		energy[f] = f.energy
	end
	H.fire(p, "RequestCupMatch", "Pressing")
	S.MatchService.Simulate = real
	H.ok(seen, "match simulé")
	for _, f in seen do
		H.ok(f ~= injured, "le blessé ne joue pas")
		H.ok(f ~= suspended, "le suspendu ne joue pas")
	end
	H.eq(suspended.suspended, 1, "suspension purgée seulement en championnat")
	for _, f in data.squad do
		H.ok(f.energy >= energy[f], "pas de fatigue en coupe : " .. f.name)
	end
	H.eq(data.tactic, "Pressing", "dernier style gardé pour l'onglet Matchs")
	-- Météo du stade : la même qu'en championnat, jointe au résultat.
	local expected = mock.run(MODULES.Weather).Describe(os.time())
	H.eq(seenWeather, expected.kind, "météo du stade appliquée à la coupe")
	local results = H.received(p, "MatchResult")
	local result = results[#results][1]
	H.eq(result.mode, "cup", "résultat de coupe")
	H.ok(type(result.weather) == "table" and result.weather.kind == expected.kind, "météo dans le résultat")
	H.leave(p)
end)

-- Anciens profils et valeurs abîmées ------------------------------------------

-- Champs ajoutés après la version testée dans Studio le 26/11 (PR #23).
local NEW_FIELDS = { "lineup", "training", "tactic", "onboarding", "events", "cup" }
local NEW_FOOTBALLER_FIELDS = { "xp", "trainedAt", "injuredUntil", "suspended", "yellows" }

local function oldProfile(userId: number, division: string)
	local p = H.join(userId)
	H.flush()
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	for _, key in NEW_FIELDS do
		data[key] = nil
	end
	for _, f in data.squad do
		for _, key in NEW_FOOTBALLER_FIELDS do
			f[key] = nil
		end
	end
	data.club.stats.cupsWon = nil
	data.club.stats.cupGiantKills = nil
	data.club.division = division
	data.club.stats.played = 40
	data.coins = 54321
	store.data["player_" .. userId] = { data = data, lock = nil }
end

H.test("profil d'hier soir (avant #24) : tout se joue, rien n'est perdu", function()
	oldProfile(830, "D4")
	H.warnings = {}
	local p = H.join(830)
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	H.eq(data.club.division, "D4", "division gardée")
	H.eq(data.coins, 54321, "solde gardé")
	H.eq(data.onboarding.done, true, "joueur confirmé : pas d'objectifs de débutant")
	for _, f in data.squad do
		H.eq(f.injuredUntil, 0, "en forme : " .. f.name)
		H.eq(f.suspended, 0, "pas suspendu")
		H.eq(f.yellows, 0, "pas de carton")
		H.eq(f.xp, 0, "XP à zéro")
	end
	H.eq(Tactics.Sanitize(data.tactic), "Balanced", "style par défaut")
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.checkSerializable(snapshot, "instantané", false)
	H.eq(snapshot.cup.status, "playing", "coupe ouverte")
	-- Championnat, coupe, entraînement.
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Counter")
	H.fire(p, "RequestCupMatch", "Counter")
	H.eq(#H.received(p, "MatchResult"), before + 2, "match de championnat et de coupe joués")
	H.fire(p, "RequestTrain", data.squad[#data.squad].id)
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	local bad = hasWarning("[Net] Erreur") or hasWarning("[Main]")
	H.ok(not bad, "avertissement : " .. tostring(bad))
	H.leave(p)
end)

H.test("valeurs abîmées dans les nouveautés : remises d'aplomb au chargement", function()
	local p0 = H.join(831)
	H.flush()
	local data0 = H.deepCopy(S.PlayerDataService.GetData(p0))
	H.leave(p0)
	H.advance(5)
	data0.cup = "cassé"
	data0.tactic = 42
	data0.lineup = { 9999, "x", data0.squad[1].id, data0.squad[1].id }
	data0.onboarding = 5
	data0.events = { week = "?", points = -3 }
	data0.squad[1].injuredUntil = 1e12 -- horloge changée
	data0.squad[2].suspended = -5
	data0.squad[3].yellows = "beaucoup"
	data0.squad[3].xp = -50
	store.data["player_831"] = { data = data0, lock = nil }
	H.warnings = {}
	local p = H.join(831)
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	local now = os.time()
	H.ok(Injuries.InjuryLeft(data.squad[1], now) <= Injuries.MAX_MINUTES * 60, "blessure bornée")
	H.eq(data.squad[2].suspended, 0, "suspension remise à zéro")
	H.eq(data.squad[3].yellows, 0, "cartons remis à zéro")
	H.eq(data.squad[3].xp, 0, "XP remise à zéro")
	checkLineup(data, "composition abîmée")
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.checkSerializable(snapshot, "instantané", false)
	H.eq(type(data.cup), "table", "coupe recréée")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(#H.received(p, "MatchResult"), before + 2, "les deux matchs se jouent")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	H.leave(p)
end)

-- Téléphone : client ---------------------------------------------------------
-- (Client démarré en dernier : il ralentit beaucoup les longues avances d'horloge.)

H.test("téléphone : fenêtre de résultat chargée qui tient à l'écran, bouton Continuer visible", function()
	local p = H.join(840, "Telephone")
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new(667, 375)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	local scale = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChildWhichIsA("UIScale").Scale
	-- Match très chargé : 8 buts, toutes les primes, 4 événements d'infirmerie, montée.
	local events = {}
	for i = 1, 8 do
		table.insert(events, { minute = i * 10, side = if i % 3 == 0 then "away" else "home", scorer = "Joueur Numéro" .. i })
	end
	UI.ShowMatchResult({
		outcome = "Win",
		homeName = "Mon Super Club",
		awayName = "Les Rivaux",
		homeGoals = 6,
		awayGoals = 2,
		events = events,
		tactics = { home = "Counter", away = "Offensive", edge = 2 },
		rewards = { total = 5000, match = 2000, tickets = 1000, sponsor = 900, shop = 600, vip = 300, event = 200, contracts = 400 },
		eventPoints = 3,
		sponsorBonuses = { { brand = "Marque", coins = 300 } },
		infirmary = {
			events = {
				{ kind = "injury", name = "A", minutes = 8 },
				{ kind = "red", name = "B" },
				{ kind = "yellow", name = "C", banned = true },
			},
			returned = { "D" },
		},
		promoted = true,
		division = "D6",
		promotionReward = 1000,
	})
	H.flush()
	local popup = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChild("MatchResult")
	H.ok(popup and popup.Visible, "fenêtre affichée")
	-- Hauteur estimée (avant mise à l'échelle) : lignes de texte repliées + bouton.
	local width = math.min(520, 0.85 * 667 / scale) - 32
	local height, lines = 32, 0
	for _, child in popup:GetChildren() do
		if child.ClassName == "TextLabel" then
			local textWidth = (utf8.len(child.Text) or #child.Text) * child.TextSize * 0.55
			local rows = math.max(1, math.ceil(textWidth / width))
			height += rows * (child.TextSize + 6) + 6
			lines += 1
		elseif child.ClassName == "TextButton" then
			height += 44 + 6
		end
	end
	local available = (375 - 60) / scale -- barre du haut de Roblox
	H.ok(lines <= 13, ("lignes regroupées : %d"):format(lines))
	-- Plus haute que l'écran : la fenêtre est bornée et on la fait défiler.
	H.eq(popup.ClassName, "ScrollingFrame", "fenêtre qui défile")
	H.eq(popup.AutomaticCanvasSize, Enum.AutomaticSize.Y, "contenu qui défile")
	local limit = popup:FindFirstChildWhichIsA("UISizeConstraint")
	H.ok(limit and limit.MaxSize.Y <= available + 0.5, ("hauteur bornée à %d px (écran : %d px, contenu ~%d px)"):format(
		limit and limit.MaxSize.Y or -1,
		available,
		height
	))
	H.ok(H.findText(popup, "Continuer", "TextButton"), "bouton Continuer")
	H.ok(H.findText(popup, "⚽ Mon Super Club"), "buteurs regroupés par équipe")
	H.ok(H.findText(popup, "Infirmerie"), "infirmerie en un bloc")
	H.click(popup, "Continuer")
	H.ok(not popup.Visible, "fenêtre fermée")
	-- Retour sur grand écran : la fenêtre peut reprendre toute sa hauteur.
	camera.ViewportSize = Vector2.new(1920, 1080)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	UI.ShowMatchResult({ outcome = "Draw", homeName = "A", awayName = "B", homeGoals = 0, awayGoals = 0, events = {}, rewards = { total = 0, match = 0, tickets = 0, sponsor = 0 }, division = "D7", divisionPoints = 1 })
	H.ok(limit.MaxSize.Y > available, "plus de place sur PC")
	camera.ViewportSize = Vector2.new(667, 375)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("téléphone : onglet Matchs, le match de championnat avant la Coupe nationale", function()
	local gui = H.localPlayer:FindFirstChild("PlayerGui")
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.flush()
	local content
	for _, d in gui:GetDescendants() do
		if d.Name == "Content" then
			content = d
		end
	end
	H.ok(content, "contenu de l'onglet")
	local firstPlay, cupIndex
	for index, cardFrame in content:GetChildren() do
		if not firstPlay and H.findText(cardFrame, "Jouer", "TextButton") then
			firstPlay = index
		end
		if not cupIndex and H.findText(cardFrame, "🏆 Coupe nationale") then
			cupIndex = index
		end
	end
	H.ok(firstPlay, "bouton Jouer")
	H.ok(cupIndex, "carte de la coupe")
	H.ok(firstPlay < cupIndex, "Jouer avant la coupe (moins de défilement au téléphone)")
	for _, tab in { "Home", "Squad", "Matches" } do
		UI.OpenTab(tab)
		H.flush()
	end
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)
