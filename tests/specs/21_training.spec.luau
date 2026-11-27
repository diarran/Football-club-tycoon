-- Entraînement des joueurs : séances (XP, prix, énergie, délai), note qui
-- monte jusqu'au potentiel, âge, composition (titulaires / remplaçants),
-- anciens profils et interface.
local S = H.boot(MODULES)
local Training = S.Training
local store = H.getStore(S.Config.DATASTORE_NAME)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)
data.missions.list = {} -- pas de prime de mission dans les débits exacts

local function footballer(id, position, rating, extra)
	local f = {
		id = id, name = "J" .. id, age = 25, position = position, rating = rating, potential = 99,
		energy = 100, value = rating * 30, salary = rating * 2, xp = 0, trainedAt = 0,
	}
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("nouveau club : XP à zéro, composition remplie, saison d'âge notée", function()
	H.eq(#data.squad, S.Config.STARTING_PLAYERS, "effectif de départ")
	for _, f in data.squad do
		H.eq(f.xp, 0, "XP de " .. f.name)
	end
	H.eq(#data.lineup, #data.squad, "tout l'effectif est titulaire")
	H.eq(data.training.ageSeason, S.Daily.SeasonId(os.time()), "saison d'âge")
end)

H.test("séance : prix selon la note, énergie, XP, puis délai de repos", function()
	local f = data.squad[1]
	f.rating, f.potential, f.age, f.energy, f.xp = 50, 70, 25, 100, 0
	data.coins = 5000
	local cost = Training.SessionCost(50)
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, 5000 - cost, "prix débité une fois")
	H.eq(f.xp, Training.SessionXp(f, 0, 0), "XP gagnée")
	H.eq(f.energy, 100 - Training.SESSION_ENERGY, "énergie dépensée")
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, 5000 - cost, "deuxième séance refusée pendant le repos")
	H.ok(H.lastNotify(p):find("reposer"), "message de repos")
	H.advance(Training.SESSION_COOLDOWN + 1)
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, 5000 - 2 * cost, "séance possible après le repos")
end)

H.test("séance refusée : joueur inconnu, fatigué, pas assez d'argent, au potentiel", function()
	local f = data.squad[2]
	f.rating, f.potential, f.trainedAt = 50, 70, 0
	data.coins = 5000
	for _, junk in { "abc", 424242, { 1 }, nil } do
		H.fire(p, "RequestTrain", junk)
	end
	H.eq(data.coins, 5000, "rien débité pour un joueur inconnu")
	f.energy = Training.MIN_ENERGY - 1
	data.lastEnergyUpdate = os.time()
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, 5000, "trop fatigué")
	f.energy = 100
	data.coins = Training.SessionCost(50) - 1
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, Training.SessionCost(50) - 1, "pas assez d'argent")
	data.coins = 5000
	f.rating = 70
	H.fire(p, "RequestTrain", f.id)
	H.eq(data.coins, 5000, "potentiel atteint : pas de séance")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("XP : la note monte tous les 100 XP, jamais au-delà du potentiel", function()
	local f = footballer(1, "MID", 60, { potential = 62 })
	H.eq(Training.AddXp(f, 90), 0, "pas encore")
	H.eq(Training.AddXp(f, 20), 1, "un point")
	H.eq(f.rating, 61, "note 61")
	H.eq(f.xp, 10, "reste d'XP gardé")
	H.eq(Training.AddXp(f, 500), 1, "bloqué au potentiel")
	H.eq(f.rating, 62, "note = potentiel")
	H.eq(f.xp, 0, "XP vidée au potentiel")
	H.eq(f.value, 62 * 30, "valeur mise à jour")
end)

H.test("jeunes plus rapides, vétérans plus lents ; zone et entraîneur aident", function()
	local young = footballer(1, "MID", 50, { age = 18 })
	local mid = footballer(2, "MID", 50, { age = 25 })
	local old = footballer(3, "MID", 50, { age = 35 })
	H.ok(Training.SessionXp(young) > Training.SessionXp(mid), "jeune")
	H.ok(Training.SessionXp(mid) > Training.SessionXp(old), "vétéran")
	H.ok(Training.SessionXp(mid, 4, 0) > Training.SessionXp(mid, 0, 0), "zone d'entraînement niveau 5")
	H.ok(Training.SessionXp(mid, 0, 0.08) > Training.SessionXp(mid, 0, 0), "entraîneur du staff")
	H.ok(Training.SessionCost(90) > Training.SessionCost(50), "les meilleurs coûtent plus cher")
end)

H.test("composition : 5 titulaires, un gardien d'abord, les meilleurs ensuite", function()
	local squad = {
		footballer(1, "ATT", 70), footballer(2, "ATT", 68), footballer(3, "MID", 66),
		footballer(4, "DEF", 64), footballer(5, "DEF", 62), footballer(6, "GK", 40), footballer(7, "MID", 30),
	}
	local ids = Training.Normalize(squad, {})
	H.eq(#ids, Training.STARTERS, "5 titulaires")
	H.eq(ids[1], 6, "le gardien joue")
	H.ok(not table.find(ids, 7) and not table.find(ids, 5), "les moins bons sur le banc")
	local kept = Training.Normalize(squad, { 7, 999, 7 })
	H.eq(kept[1], 7, "choix du joueur gardé")
	H.eq(#kept, 5, "complété, sans doublon ni inconnu")
end)

H.test("faire jouer / mettre sur le banc : toujours 5 titulaires, gardien protégé", function()
	data.squad = {
		footballer(101, "GK", 50), footballer(102, "DEF", 50), footballer(103, "MID", 50),
		footballer(104, "ATT", 55), footballer(105, "ATT", 52), footballer(106, "MID", 45), footballer(107, "GK", 44),
	}
	data.lineup = {}
	S.SquadService.RefreshTraining(data)
	H.eq(#data.lineup, 5, "5 titulaires")
	H.ok(not table.find(data.lineup, 106), "106 remplaçant")
	H.fire(p, "RequestLineup", 106, true)
	H.ok(table.find(data.lineup, 106), "106 entre")
	H.ok(not table.find(data.lineup, 103), "il remplace le milieu")
	H.eq(#data.lineup, 5, "toujours 5")
	H.fire(p, "RequestLineup", 106, false)
	H.ok(table.find(data.lineup, 103), "le milieu revient")
	H.fire(p, "RequestLineup", 105, true) -- déjà titulaire
	H.eq(#data.lineup, 5, "rien ne change")
	H.fire(p, "RequestLineup", 101, false) -- gardien sur le banc : l'autre gardien entre
	H.ok(table.find(data.lineup, 107), "le gardien remplaçant entre")
	H.fire(p, "RequestLineup", "auto")
	H.ok(table.find(data.lineup, 101) and not table.find(data.lineup, 107), "composition auto : le meilleur gardien")
	for _, junk in { { "x", true }, { 101, "oui" }, { 999, true } } do
		H.fire(p, "RequestLineup", junk[1], junk[2])
	end
	H.eq(#data.lineup, 5, "valeurs du client ignorées")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("match : seuls les titulaires jouent, se fatiguent et gagnent de l'XP", function()
	data.lineup = { 101, 102, 103, 104, 105 }
	for _, f in data.squad do
		f.energy, f.xp = 100, 0
	end
	data.lastEnergyUpdate = os.time()
	local result = play()
	H.ok(result, "match joué")
	for _, event in result.events do
		if event.side == "home" then
			H.ok(event.scorer ~= "J106" and event.scorer ~= "J107", "un remplaçant ne marque pas")
		end
	end
	local bench = data.squad[6]
	H.eq(bench.xp, 0, "pas d'XP pour un remplaçant")
	local starter = data.squad[1]
	H.ok(starter.xp > 0 or starter.rating > 50, "XP pour un titulaire")
end)

H.test("transfert : le nouveau joueur prend la place du partant dans la composition", function()
	data.club.division = "D5"
	data.coins = 1e6
	-- Le match d'avant peut avoir blessé ou suspendu quelqu'un (tirage au hasard).
	for _, f in data.squad do
		f.injuredUntil = 0
		f.suspended = 0
	end
	local weakest = S.SquadService.GetWeakest(data.squad)
	S.SquadService.TrySetStarter(p, weakest.id, true)
	H.ok(table.find(data.lineup, weakest.id), "le moins bon est titulaire")
	local ok = S.SquadService.TryTransfer(p)
	H.ok(ok, "transfert fait")
	H.ok(not table.find(data.lineup, weakest.id), "le partant n'est plus titulaire")
	H.eq(#S.SquadService.Starters(data), 5, "5 titulaires")
	data.club.division = "D7"
end)

H.test("âge : +1 an par nouvelle saison, au plus 2 ans d'un coup", function()
	local ages = {}
	for i, f in data.squad do
		ages[i] = f.age
	end
	H.advance(7 * 24 * 3600 + 60)
	S.SquadService.RefreshTraining(data)
	for i, f in data.squad do
		H.eq(f.age, ages[i] + 1, "un an de plus")
	end
	S.SquadService.RefreshTraining(data)
	H.eq(data.squad[1].age, ages[1] + 1, "pas deux fois la même saison")
	H.advance(10 * 7 * 24 * 3600)
	S.SquadService.RefreshTraining(data)
	H.eq(data.squad[1].age, ages[1] + 1 + Training.MAX_AGE_STEPS, "long retour plafonné")
end)

H.test("ancien profil sans entraînement : chargé, XP à zéro, pas de vieillissement", function()
	local q = H.join(2)
	local old = H.deepCopy(S.PlayerDataService.GetData(q))
	H.leave(q)
	H.advance(5)
	old.lineup, old.training = nil, nil
	for _, f in old.squad do
		f.xp, f.trainedAt = nil, nil
	end
	old.squad[1].xp = "abîmé"
	local ages = {}
	for i, f in old.squad do
		ages[i] = f.age
	end
	store.data["player_2"] = { data = old, lock = nil }
	H.advance(30 * 24 * 3600)
	H.warnings = {}
	q = H.join(2)
	H.flush()
	local d = S.PlayerDataService.GetData(q)
	H.ok(d, "profil chargé")
	for i, f in d.squad do
		H.eq(f.xp, 0, "XP à zéro")
		H.eq(f.trainedAt, 0, "jamais entraîné")
		H.eq(f.age, ages[i], "âge inchangé au retour")
	end
	H.eq(#d.lineup, #d.squad, "composition créée")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	H.leave(q)
end)

H.test("interface : boutons Entraîner et Faire jouer dans l'onglet Effectif", function()
	data.squad = {
		footballer(201, "GK", 50), footballer(202, "DEF", 50), footballer(203, "MID", 50),
		footballer(204, "ATT", 55), footballer(205, "ATT", 52), footballer(206, "MID", 45),
	}
	data.lineup = {}
	S.SquadService.RefreshTraining(data)
	data.coins = 50000
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Squad")
	H.flush()
	H.ok(H.findText(gui, "Composition de l'équipe"), "carte de composition")
	H.ok(H.findText(gui, "XP 0 / 100"), "barre d'XP")
	local before = data.coins
	H.click(gui, "Entraîner")
	H.flush()
	H.ok(data.coins < before, "séance payée depuis l'interface")
	H.click(gui, "Faire jouer")
	H.flush()
	H.ok(table.find(data.lineup, 206), "le remplaçant entre depuis l'interface")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)
