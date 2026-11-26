-- Objectifs quotidiens et saisons : cadeau du jour (série de 7 jours), missions
-- du jour, revenus hors ligne, saisons de 7 jours. Horloge du serveur seulement.
local S = H.boot(MODULES)
local Daily, DailyService = S.Daily, S.DailyService
local store = H.getStore(S.Config.DATASTORE_NAME)

local function toMidnight(extra: number?)
	H.advance(Daily.SecondsToNextDay(os.time()) + (extra or 0))
end

-- Reconnexion après `seconds` hors ligne. Renvoie le joueur et son profil.
local function comeBack(userId: number, seconds: number)
	H.advance(seconds)
	local p = H.join(userId)
	H.advance(1)
	return p, S.PlayerDataService.GetData(p)
end

H.test("nouveau club : pas de cadeau en double le premier jour, missions tirées", function()
	local p = H.join(300)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.coins, S.Config.STARTING_COINS, "solde de départ inchangé")
	H.eq(data.daily.streak, 1, "jour 1 de la série")
	H.eq(#data.missions.list, Daily.MISSIONS_PER_DAY, "3 missions du jour")
	local ids = {}
	for _, m in data.missions.list do
		H.ok(not ids[m.id], "missions différentes")
		ids[m.id] = true
		H.ok(m.reward > 0 and m.target > 0, "objectif et prime")
	end
	H.leave(p)
end)

H.test("cadeau du jour : série sur 7 jours, gros cadeau le 7e, puis le cycle recommence", function()
	local p = H.join(301)
	H.leave(p)
	local expected = {}
	for day = 2, 8 do
		toMidnight(60)
		local back, data = comeBack(301, 0)
		local before = data.coins
		H.eq(data.daily.streak, day, "série jour " .. day)
		local cycle = Daily.CycleDay(day)
		table.insert(expected, cycle)
		local welcome = S.PlayerDataService.Get(back).welcome
		H.ok(welcome and welcome.daily, "cadeau dans le résumé d'arrivée")
		H.eq(welcome.daily.coins, Daily.StreakReward(day, "D7"), "montant du jour " .. cycle)
		-- Reconnexion le même jour : pas de second cadeau.
		H.leave(back)
		local again, data2 = comeBack(301, 30)
		H.eq(data2.daily.streak, day, "pas de second cadeau le même jour")
		H.ok(not (S.PlayerDataService.Get(again).welcome or {}).daily, "aucun cadeau en double")
		H.ok(data2.coins >= before, "rien de retiré")
		H.leave(again)
	end
	H.eq(expected[6], 7, "le 7e jour atteint")
	H.eq(expected[7], 1, "le cycle recommence au jour 1")
	H.ok(Daily.StreakReward(7, "D7") > Daily.StreakReward(6, "D7") * 1.5, "gros cadeau le 7e jour")
end)

H.test("jour manqué : la série repart au jour 1 sans rien retirer", function()
	local p, data = comeBack(301, 0)
	local streak = data.daily.streak
	H.ok(streak >= 2, "série en cours")
	H.leave(p)
	local coins = data.coins
	toMidnight(Daily.DAY_SECONDS + 60) -- un jour entier sans connexion
	local back, again = comeBack(301, 0)
	H.eq(again.daily.streak, 1, "série remise à 1")
	H.ok(again.coins >= coins, "aucune pénalité")
	H.leave(back)
end)

H.test("cadeau à minuit pour un joueur resté en ligne, avec nouvelles missions", function()
	local p = H.join(302)
	local data = S.PlayerDataService.GetData(p)
	local day = data.missions.day
	local coins = data.coins
	toMidnight(40) -- la vérification passe toutes les 30 s
	H.eq(data.missions.day, day + 1, "missions renouvelées à minuit UTC")
	H.eq(data.daily.streak, 2, "jour 2 sans se reconnecter")
	H.ok(data.coins >= coins + Daily.StreakReward(2, "D7"), "cadeau versé")
	local msg = H.lastNotify(p)
	H.ok(msg and msg:find("Cadeau du jour", 1, true), "notification : " .. tostring(msg))
	H.leave(p)
end)

H.test("missions : progression par les vraies actions, prime versée une seule fois", function()
	local p = H.join(303)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {
		{ id = "play", target = 2, reward = 400, progress = 0, done = false },
		{ id = "upgrade", target = 1, reward = 400, progress = 0, done = false },
		{ id = "goals", target = 1000, reward = 450, progress = 0, done = false },
	}
	data.coins = 100000
	H.fire(p, "RequestMatch", "ai:3", "Balanced")
	H.eq(data.missions.list[1].progress, 1, "1 match compté")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = data.coins
	H.fire(p, "RequestMatch", "ai:3", "Balanced")
	local result = H.received(p, "MatchResult")
	result = result[#result][1]
	H.ok(data.missions.list[1].done, "mission accomplie")
	H.ok(result.missionReward >= 400, "prime dans le résultat du match")
	H.eq(data.coins, before + result.rewards.total + result.missionReward + (result.promotionReward or 0), "prime versée une fois")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "ai:3", "Balanced")
	result = H.received(p, "MatchResult")
	H.eq(result[#result][1].missionReward, data.missions.list[3].progress >= 1000 and 450 or 0, "pas de seconde prime")
	-- Amélioration : mission accomplie, notification.
	before = data.coins
	local cost = S.Buildings.GetUpgradeCost("Pitch", data.buildings.Pitch)
	H.fire(p, "RequestUpgrade", "Pitch")
	H.ok(data.missions.list[2].done, "mission amélioration")
	H.eq(data.coins, before - cost + 400, "prix débité et prime versée")
	-- Le client ne peut rien valider lui-même.
	H.fire(p, "RequestTutorialStep", "mission")
	H.eq(data.missions.list[3].done, false, "mission de buts toujours en cours")
	H.leave(p)
end)

H.test("missions : mêmes missions après reconnexion, faisables pour le club", function()
	local p = H.join(304)
	local data = S.PlayerDataService.GetData(p)
	local first = {}
	for _, m in data.missions.list do
		table.insert(first, m.id .. m.target)
	end
	H.leave(p)
	local back, again = comeBack(304, 120)
	for i, m in again.missions.list do
		H.eq(m.id .. m.target, first[i], "même mission " .. i)
	end
	-- Club au maximum partout, effectif complet en D7 : ni amélioration ni recrue proposées.
	for id in S.Buildings.Definitions do
		again.buildings[id] = S.Buildings.MaxLevel(id)
	end
	while #again.squad < S.Config.MAX_SQUAD_SIZE do
		table.insert(again.squad, table.clone(again.squad[1]))
	end
	for day = 1, 20 do
		for _, m in Daily.PickMissions(304, day, "D7", function(needs)
			return needs ~= "upgrade" and needs ~= "recruit"
		end) do
			H.ok(m.id ~= "upgrade" and m.id ~= "recruit", "mission faisable")
		end
	end
	H.leave(back)
end)

H.test("revenus hors ligne : part réduite des installations, plafond 8 h, écran d'arrivée", function()
	local p = H.join(305)
	local data = S.PlayerDataService.GetData(p)
	data.buildings.Stands, data.buildings.Offices = 3, 3
	H.leave(p)
	local perMatch = Daily.FacilityIncome({ Stands = 3, Offices = 3 })
	H.ok(perMatch > 0, "revenus des installations")
	-- 2 heures d'absence (sans changer de jour UTC pour isoler le calcul).
	local hours = math.min(2, (Daily.SecondsToNextDay(os.time()) - 120) / 3600)
	local back, again = comeBack(305, hours * 3600)
	local welcome = S.PlayerDataService.Get(back).welcome
	H.ok(welcome and welcome.offline, "résumé « Pendant ton absence… »")
	local expected = Daily.OfflineIncome({ Stands = 3, Offices = 3 }, welcome.offline.away)
	H.eq(welcome.offline.coins, expected, "montant calculé par le serveur")
	H.ok(expected < perMatch * hours * 2, "part réduite")
	local snap = H.invoke(back, "GetSnapshot")
	H.eq(snap.daily.welcome.offline.coins, expected, "résumé envoyé au client")
	H.leave(back)
	-- Absence de 3 jours : seules 8 heures comptent.
	local _, capped = Daily.OfflineIncome({ Stands = 3, Offices = 3 }, 3 * Daily.DAY_SECONDS)
	H.eq(capped, Daily.OFFLINE_MAX_SECONDS, "plafond de 8 h")
	local back2 = comeBack(305, 3 * Daily.DAY_SECONDS)
	local w2 = S.PlayerDataService.Get(back2).welcome
	H.eq(w2.offline.seconds, Daily.OFFLINE_MAX_SECONDS, "8 h comptées")
	H.eq(w2.offline.coins, Daily.OfflineIncome({ Stands = 3, Offices = 3 }, Daily.OFFLINE_MAX_SECONDS), "montant plafonné")
	H.leave(back2)
	-- Reconnexions rapides : rien de plus.
	local back3, d3 = comeBack(305, 60)
	H.ok(not (S.PlayerDataService.Get(back3).welcome or {}).offline, "pas de revenu pour 1 minute")
	H.leave(back3)
	H.eq(Daily.OfflineIncome({}, -500), 0, "horloge incohérente : rien")
	H.eq(Daily.OfflineIncome({}, 0 / 0), 0, "valeur invalide : rien")
	H.ok(d3, "profil chargé")
end)

H.test("saison : points des matchs, classement contre les clubs fictifs, prime et trophée", function()
	local p = H.join(306)
	local data = S.PlayerDataService.GetData(p)
	local seasonId = data.season.id
	H.eq(seasonId, Daily.SeasonId(os.time()), "saison en cours")
	H.fire(p, "RequestMatch", "ai:3", "Balanced")
	local result = H.received(p, "MatchResult")
	result = result[#result][1]
	H.eq(data.season.points, S.Config.DivisionPoints[result.outcome], "points de saison")
	local snap = H.invoke(p, "GetSnapshot")
	H.eq(#snap.daily.season.rows, #S.Divisions.RIVALS + 1, "classement de 6 clubs")
	-- Fin de saison avec assez de points pour la 1re place.
	data.season.points = Daily.SEASON_TARGET
	H.leave(p)
	local coins = data.coins
	H.advance(Daily.SeasonEndsAt(seasonId) - os.time() + 60)
	local back, again = comeBack(306, 0)
	H.eq(again.season.id, seasonId + 1, "nouvelle saison")
	H.eq(again.season.points, 0, "points remis à zéro")
	H.eq(again.club.stats.seasonsWon, 1, "saison gagnée")
	H.eq(again.seasonLast.rank, 1, "1re place")
	H.eq(again.seasonLast.reward, Daily.SeasonReward(1, "D7"), "prime de la 1re place")
	H.ok(again.coins >= coins + Daily.SeasonReward(1, "D7"), "prime versée")
	local found = false
	for _, t in S.Trophies.Earned(again.club.division, again.club.stats, again.trophies.titles) do
		found = found or t.id == "seasons_1"
	end
	H.ok(found, "trophée de champion de la saison")
	H.leave(back)
	-- Saison sans aucun match : pas de prime.
	local id = again.season.id
	H.advance(Daily.SeasonEndsAt(id) - os.time() + 60)
	local back2, d2 = comeBack(306, 0)
	H.eq(d2.seasonLast.id, seasonId, "pas de prime sans avoir joué")
	H.eq(d2.club.stats.seasonsWon, 1, "pas de titre gratuit")
	H.leave(back2)
end)

H.test("classement de saison : clubs fictifs qui avancent dans la semaine, égalité au joueur", function()
	local rows, rank = Daily.SeasonStandings("D5", "Moi", 0, 0)
	H.eq(rank, 1, "début de saison : tout le monde à 0")
	rows, rank = Daily.SeasonStandings("D5", "Moi", 0, 1)
	H.eq(rank, 6, "sans points : dernier")
	local top = math.floor(Daily.SEASON_TARGET * S.Divisions.RIVALS[1].share)
	rows, rank = Daily.SeasonStandings("D5", "Moi", top, 1)
	H.eq(rank, 1, "égalité : le joueur passe devant")
	H.eq(rows[1].name, "Moi", "ligne du joueur")
	H.ok(Daily.SeasonReward(1, "D1") > Daily.SeasonReward(6, "D1"), "prime selon la place")
end)

H.test("ancien profil sans ces champs : complété sans cadeau ni revenu imprévu", function()
	store.data["player_307"] = {
		data = {
			schemaVersion = 1,
			coins = 5000,
			club = { name = "FC Ancien", division = "D6", divisionPoints = 3, stats = { played = 4, wins = 2, draws = 1, losses = 1, goalsFor = 6, goalsAgainst = 4 } },
			buildings = { Pitch = 2 },
			squad = {},
		},
	}
	local p = H.join(307)
	local data = S.PlayerDataService.GetData(p)
	H.ok(data.daily and data.season and data.missions, "champs ajoutés")
	H.eq(data.club.stats.seasonsWon, 0, "compteur de saisons")
	H.eq(#data.missions.list, 3, "missions du jour")
	H.eq(data.coins, 5000, "solde intact")
	H.leave(p)
	H.ok(store.data["player_307"].data.lastSeenAt, "heure de départ sauvegardée")
end)

H.test("écran d'accueil : cadeau, missions, saison et fenêtre « Pendant ton absence… »", function()
	local p = H.join(308, "Écran")
	local data = S.PlayerDataService.GetData(p)
	H.leave(p)
	toMidnight(60)
	local back = H.join(308, "Écran")
	data = S.PlayerDataService.GetData(back)
	data.buildings.Stands = 2
	local gui = H.startClient(MODULES, back)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	H.ok(H.findText(gui, "Pendant ton absence"), "fenêtre d'arrivée")
	H.ok(H.findText(gui, "Cadeau du jour 2 / 7"), "cadeau du jour affiché")
	H.click(gui, "Super")
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, "Missions du jour"), "missions affichées")
	H.ok(H.findText(gui, "Saison de la semaine"), "saison affichée")
	H.ok(H.findText(gui, "Classement :"), "place au classement")
	H.leave(back)
end)

H.finish()
