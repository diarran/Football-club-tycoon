-- Blessures, cartons et suspensions : risque rare (plus fort quand le joueur
-- est fatigué), durée courte en minutes réelles, médecin du staff, joueurs
-- indisponibles écartés de la composition (remplacés automatiquement),
-- suspension purgée en un match, jamais de blocage, anciens profils, interface.
local S = H.boot(MODULES)
local Injuries = S.Injuries
local Training = S.Training
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)
data.missions.list = {}

local function footballer(id, position, rating, extra)
	local f = {
		id = id, name = "J" .. id, age = 25, position = position, rating = rating, potential = 99,
		energy = 100, value = rating * 30, salary = rating * 2, xp = 0, trainedAt = 0,
		injuredUntil = 0, suspended = 0, yellows = 0,
	}
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

-- Faux générateur : renvoie toujours les mêmes valeurs (tirage forcé).
local function fixedRng(number, integer)
	return {
		NextNumber = function()
			return number
		end,
		NextInteger = function(_, a, _b)
			return integer or a
		end,
	}
end

local function sevenPlayers()
	data.squad = {
		footballer(1, "GK", 50), footballer(2, "DEF", 50), footballer(3, "MID", 50),
		footballer(4, "ATT", 60), footballer(5, "ATT", 58), footballer(6, "ATT", 40), footballer(7, "MID", 35),
	}
	data.lineup = {}
	S.SquadService.RefreshTraining(data)
end

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

local function healAll()
	for _, f in data.squad do
		f.injuredUntil, f.suspended, f.yellows = 0, 0, 0
	end
end

H.test("règles : risque plus fort quand fatigué, blessure courte, médecin utile", function()
	H.eq(Injuries.InjuryChance(100), Injuries.BASE_CHANCE, "en forme : risque de base")
	H.ok(Injuries.InjuryChance(10) > 3 * Injuries.InjuryChance(100), "fatigué : risque bien plus fort")
	H.ok(Injuries.InjuryChance(0) <= 0.07, "même épuisé, le risque reste rare")
	H.eq(Injuries.Duration(10, 0), 600, "10 minutes réelles")
	H.ok(Injuries.MAX_MINUTES <= 15, "jamais plus d'un quart d'heure")
	local previous = math.huge
	for level = 0, S.Staff.MaxLevel("Doctor") do
		local reduction = S.Staff.Effect({ Doctor = level }, "injuryReduction")
		local seconds = Injuries.Duration(10, reduction)
		H.ok(seconds < previous, "médecin niveau " .. level .. " : blessure plus courte")
		previous = seconds
	end
	H.eq(Injuries.Duration(10, S.Staff.Effect({ Doctor = 4 }, "injuryReduction")), 240, "médecin max : 10 min -> 4 min")
end)

H.test("tirages : blessure, carton rouge, cartons jaunes cumulés", function()
	local now = os.time()
	local f = footballer(50, "MID", 50)
	local event = Injuries.Roll(fixedRng(0, 8), f, 100, 0, now)
	H.eq(event.kind, "injury", "blessure")
	H.eq(f.injuredUntil, now + 8 * 60, "8 minutes")
	H.ok(not Injuries.IsAvailable(f, now), "indisponible")
	H.ok(Injuries.IsAvailable(f, now + 8 * 60), "rétabli à l'heure dite")

	f = footballer(51, "MID", 50)
	event = Injuries.Roll(fixedRng(Injuries.BASE_CHANCE + 0.001), f, 100, 0, now)
	H.eq(event.kind, "red", "carton rouge")
	H.eq(f.suspended, 1, "suspendu 1 match")

	f = footballer(52, "MID", 50)
	local yellowRoll = Injuries.BASE_CHANCE + Injuries.RED_CHANCE + 0.001
	event = Injuries.Roll(fixedRng(yellowRoll), f, 100, 0, now)
	H.eq(event.kind, "yellow", "carton jaune")
	H.ok(not event.banned and f.suspended == 0 and f.yellows == 1, "1er jaune : pas de suspension")
	event = Injuries.Roll(fixedRng(yellowRoll), f, 100, 0, now)
	H.ok(event.banned and f.suspended == 1 and f.yellows == 0, "2e jaune : suspendu, compteur remis à zéro")

	f = footballer(53, "MID", 50)
	H.eq(Injuries.Roll(fixedRng(0.99), f, 100, 0, now), nil, "le plus souvent : rien")
end)

H.test("rare : moins de 3 % de blessures par joueur et par match en forme", function()
	data.squad = {}
	for i = 1, 5 do
		table.insert(data.squad, footballer(100 + i, if i == 1 then "GK" else "MID", 50))
	end
	data.lineup = {}
	local injuries, cards, tiredInjuries = 0, 0, 0
	for _ = 1, 400 do
		healAll()
		for _, f in data.squad do
			f.energy = 100
		end
		for _, event in S.SquadService.ApplyMatchEffects(data).events do
			injuries += if event.kind == "injury" then 1 else 0
			cards += if event.kind ~= "injury" then 1 else 0
		end
		healAll()
		for _, f in data.squad do
			f.energy = 5
		end
		for _, event in S.SquadService.ApplyMatchEffects(data).events do
			tiredInjuries += if event.kind == "injury" then 1 else 0
		end
	end
	local rate = injuries / 2000
	H.ok(rate > 0.002 and rate < 0.03, ("taux de blessure en forme : %.3f"):format(rate))
	H.ok(tiredInjuries > injuries * 2, ("fatigués : %d blessures contre %d"):format(tiredInjuries, injuries))
	H.ok(cards / 2000 < 0.1, ("cartons : %.3f par joueur et par match"):format(cards / 2000))
end)

H.test("composition : blessé et suspendu remplacés, puis de retour automatiquement", function()
	sevenPlayers()
	local now = os.time()
	H.ok(table.find(data.lineup, 4), "le meilleur attaquant est titulaire")
	data.squad[4].injuredUntil = now + 300
	data.squad[2].suspended = 1
	local ids = Training.Normalize(data.squad, data.lineup, now)
	H.eq(#ids, 5, "toujours 5 titulaires")
	H.ok(not table.find(ids, 4) and not table.find(ids, 2), "blessé et suspendu écartés")
	H.ok(table.find(ids, 6) and table.find(ids, 7), "les remplaçants entrent")
	H.ok(table.find(data.lineup, 4), "la composition voulue est gardée")
	H.ok(table.find(Training.Normalize(data.squad, data.lineup, now + 301), 4), "rétabli : il reprend sa place")
	H.eq(Training.MissingStarters(data.squad, now), 0, "aucune place vide")
end)

H.test("match : les indisponibles ne jouent pas, la suspension est purgée", function()
	sevenPlayers()
	local injured, banned = data.squad[4], data.squad[2]
	injured.injuredUntil = os.time() + 10 * 60
	banned.suspended = 1
	local result = play()
	H.ok(result, "match joué")
	H.eq(injured.energy, 100, "le blessé ne s'est pas fatigué")
	H.eq(banned.energy, 100, "le suspendu ne s'est pas fatigué")
	H.eq(data.squad[6].energy, 100 - S.Config.ENERGY_COST_PER_MATCH, "le remplaçant a joué")
	H.eq(banned.suspended, 0, "suspension purgée")
	H.ok(table.find(result.infirmary.returned, banned.name), "annoncé dans le résultat")
	H.ok(Injuries.IsInjured(injured, os.time()), "blessure toujours en cours")
	H.advance(10 * 60)
	healAll()
	local after = play()
	H.ok(after, "match suivant")
	H.eq(injured.energy, 100 - S.Config.ENERGY_COST_PER_MATCH, "rétabli : il rejoue")
end)

H.test("petit effectif : l'équipe joue à moins avec un petit malus", function()
	data.squad = { footballer(1, "GK", 50), footballer(2, "DEF", 50), footballer(3, "ATT", 50) }
	data.lineup = {}
	S.SquadService.RefreshTraining(data)
	H.eq(S.SquadService.MissingPenalty(data), 0, "au complet : pas de malus")
	data.squad[3].injuredUntil = os.time() + 300
	H.eq(S.SquadService.MissingStarters(data), 1, "1 place vide")
	H.eq(S.SquadService.MissingPenalty(data), Injuries.MISSING_PENALTY, "malus léger")
	local result = play()
	H.ok(result, "le match se joue quand même")
	H.eq(data.squad[3].energy, 100, "le blessé reste au repos")
end)

H.test("jamais bloqué : tous blessés = attente courte, tous suspendus = suspensions levées", function()
	data.squad = { footballer(1, "GK", 50), footballer(2, "DEF", 50), footballer(3, "ATT", 50) }
	data.lineup = {}
	local now = os.time()
	data.squad[1].injuredUntil = now + 10 * 60
	data.squad[2].injuredUntil = now + 3 * 60 + S.Config.MATCH_COOLDOWN_SECONDS + 1 -- play() avance l'horloge
	data.squad[3].suspended = 1
	H.eq(play(), nil, "match refusé")
	H.ok(H.lastNotify(p):find("blessés ou suspendus"), "message clair")
	H.ok(H.lastNotify(p):find("3 min"), "temps du premier retour")
	healAll()
	for _, f in data.squad do
		f.suspended = 1
	end
	-- Pas de nouveau carton pendant ce match : on vérifie seulement la levée.
	local yellow, red = S.Injuries.YELLOW_CHANCE, S.Injuries.RED_CHANCE
	S.Injuries.YELLOW_CHANCE, S.Injuries.RED_CHANCE = 0, 0
	local result = play()
	S.Injuries.YELLOW_CHANCE, S.Injuries.RED_CHANCE = yellow, red
	H.ok(result, "que des suspendus : le match se joue")
	for _, f in data.squad do
		H.eq(f.suspended, 0, "suspensions levées")
	end
end)

H.test("refus : entraîner un blessé, faire jouer un indisponible, banc sans remplaçant", function()
	sevenPlayers()
	data.coins = 5000
	local hurt = data.squad[6]
	hurt.injuredUntil = os.time() + 300
	H.fire(p, "RequestTrain", hurt.id)
	H.eq(data.coins, 5000, "séance refusée, rien débité")
	H.ok(H.lastNotify(p):find("blessé"), "message de blessure")
	H.fire(p, "RequestLineup", hurt.id, true)
	H.ok(not table.find(data.lineup, hurt.id), "blessé jamais titulaire")
	data.squad[7].suspended = 1
	H.fire(p, "RequestLineup", 7, true)
	H.ok(H.lastNotify(p):find("suspendu"), "message de suspension")
	local before = table.clone(data.lineup)
	H.fire(p, "RequestLineup", 3, false) -- aucun remplaçant disponible
	H.ok(H.lastNotify(p):find("Aucun remplaçant"), "refus clair")
	H.eq(#data.lineup, #before, "composition inchangée")
	H.fire(p, "RequestLineup", "auto")
	H.eq(#Training.Normalize(data.squad, data.lineup, os.time()), 5, "composition auto : 5 joueurs disponibles")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("médecin embauché : blessures réelles plus courtes", function()
	data.staff.Doctor = 4
	sevenPlayers()
	local now = os.time()
	local longest = 0
	for _ = 1, 600 do
		healAll()
		for _, f in data.squad do
			f.energy = 0
		end
		for _, event in S.SquadService.ApplyMatchEffects(data).events do
			if event.kind == "injury" then
				longest = math.max(longest, event.minutes)
			end
		end
	end
	H.ok(longest > 0, "des blessures ont eu lieu")
	H.ok(longest <= math.ceil(Injuries.MAX_MINUTES * 0.4), "médecin max : au plus " .. longest .. " min")
	data.staff.Doctor = 0
	H.ok(now == os.time(), "aucun temps écoulé")
end)

H.test("ancien profil : joueurs sans blessure ni carton, valeurs abîmées corrigées", function()
	data.squad = {
		{ id = 1, name = "Vieux", age = 25, position = "GK", rating = 40, potential = 50, energy = 100, value = 0, salary = 0 },
		footballer(2, "ATT", 40, { injuredUntil = os.time() + 999999, suspended = 42, yellows = "x" }),
		footballer(3, "DEF", 40, { injuredUntil = 0 / 0, suspended = -1 }),
	}
	S.SquadService.RefreshTraining(data)
	local now = os.time()
	H.eq(data.squad[1].injuredUntil, 0, "ancien joueur en forme")
	H.eq(data.squad[1].suspended, 0, "pas suspendu")
	H.ok(Injuries.InjuryLeft(data.squad[2], now) <= Injuries.MAX_MINUTES * 60, "blessure ramenée au maximum")
	H.eq(data.squad[2].suspended, Injuries.MAX_SUSPENSION, "suspension bornée")
	H.eq(data.squad[2].yellows, 0, "cartons invalides remis à zéro")
	H.ok(Injuries.IsAvailable(data.squad[3], now), "valeurs invalides : disponible")
	H.ok(play(), "match joué")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("interface : blessé et suspendu bien visibles dans l'onglet Effectif, infirmerie du résultat", function()
	sevenPlayers()
	data.squad[4].injuredUntil = os.time() + 7 * 60
	data.squad[2].suspended = 1
	data.squad[3].yellows = 1
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Squad")
	H.flush()
	H.ok(H.findText(gui, "🤕 Blessé · de retour dans 7 min"), "blessure et temps de retour")
	H.ok(H.findText(gui, "🟥 Suspendu · 1 match"), "suspension")
	H.ok(H.findText(gui, "🟨 1 carton jaune"), "carton jaune en cours")
	H.ok(H.findText(gui, "J4 · Indisponible"), "marqué indisponible")
	H.ok(H.findText(gui, "Blessures et cartons"), "explication")
	UI.ShowMatchResult({
		outcome = "Win", homeName = "A", awayName = "B", homeGoals = 1, awayGoals = 0, events = {},
		rewards = { total = 10, match = 10, tickets = 0, sponsor = 0, shop = 0, vip = 0 },
		division = "D7", divisionPoints = 3,
		infirmary = {
			events = { { kind = "injury", name = "Paul", minutes = 6 }, { kind = "red", name = "Léo" } },
			returned = { "Max" },
		},
	})
	H.flush()
	H.ok(H.findText(gui, "Infirmerie"), "titre infirmerie")
	H.ok(H.findText(gui, "🤕 Paul est blessé : absent 6 min"), "blessure annoncée")
	H.ok(H.findText(gui, "🟥 Léo : carton rouge"), "carton rouge annoncé")
	H.ok(H.findText(gui, "✅ Max a purgé"), "retour de suspension")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)
