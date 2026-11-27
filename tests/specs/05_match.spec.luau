-- Matchs simulés : calculés et validés uniquement par le serveur.
local S = H.boot(MODULES)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

local function play(opponent, tactic)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", opponent or "ai", tactic or "Balanced")
	local results = H.received(p, "MatchResult")
	if #results > before then
		return results[#results][1]
	end
	return nil
end

H.test("match contre l'IA : score, événements et récompenses cohérents", function()
	local coins = data.coins
	local result = play("ai", "Offensive")
	H.ok(result, "résultat reçu")
	H.ok(result.homeGoals >= 0 and result.awayGoals >= 0, "scores positifs")
	H.eq(#result.events, result.homeGoals + result.awayGoals, "un événement par but")
	local expectedOutcome = if result.homeGoals > result.awayGoals then "Win" elseif result.homeGoals == result.awayGoals then "Draw" else "Loss"
	H.eq(result.outcome, expectedOutcome, "issue")
	H.eq(result.rewards.match, S.Config.Rewards[expectedOutcome], "prime de match")
	H.eq(data.coins, coins + result.rewards.total + (result.missionReward or 0), "récompense versée une fois")
	H.eq(data.club.stats.played, 1, "match compté")
	H.eq(data.club.divisionPoints, S.Config.DivisionPoints[expectedOutcome], "points de division")
	H.eq(data.tactic, "Offensive", "tactique retenue")
end)

H.test("délai entre deux matchs imposé par le serveur", function()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local played = data.club.stats.played
	H.advance(5)
	H.fire(p, "RequestMatch", "ai", "Balanced")
	H.eq(data.club.stats.played, played, "second match refusé")
	local msg, kind = H.lastNotify(p)
	H.eq(kind, "error", "notification d'erreur")
	H.ok(msg:find("prochain match"), "message du délai")
end)

H.test("le client ne peut pas envoyer de score ni de récompense", function()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local coins = data.coins
	H.fire(p, "RequestMatch", "ai", "Balanced", { homeGoals = 99, outcome = "Win", reward = 1e9 })
	local result = H.received(p, "MatchResult")
	result = result[#result][1]
	H.ok(result.homeGoals < 99, "score calculé par le serveur")
	H.eq(data.coins, coins + result.rewards.total + (result.missionReward or 0), "récompense calculée par le serveur")
	H.ok(result.rewards.total < 5000, "récompense raisonnable")
end)

H.test("valeurs client invalides pour un match : refusées sans effet", function()
	local played = data.club.stats.played
	local coins = data.coins
	for _, opponent in { nil, 42, {}, "player:abc", "player:" .. p.UserId, "player:999999", "AI", string.rep("x", 5000) } do
		H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
		H.fire(p, "RequestMatch", opponent, "Balanced")
	end
	H.eq(data.club.stats.played, played, "aucun match joué")
	H.eq(data.coins, coins, "aucune récompense")
end)

H.test("tactique invalide : la tactique enregistrée est utilisée", function()
	data.tactic = "Defensive"
	local result = play("ai", "TricheTotale")
	H.ok(result, "match joué")
	H.eq(data.tactic, "Defensive", "tactique inchangée")
end)

H.test("match contre un autre club : ses données ne sont jamais modifiées", function()
	local q = H.join(2)
	local other = S.PlayerDataService.GetData(q)
	local snapshot = H.deepCopy(other)
	local result = play("player:2", "Balanced")
	H.ok(result, "match joué contre un autre club")
	H.eq(result.awayName, other.club.name, "adversaire")
	H.eq(other.coins, snapshot.coins, "solde adverse")
	H.eq(other.club.stats.played, snapshot.club.stats.played, "statistiques adverses")
	H.eq(other.club.divisionPoints, snapshot.club.divisionPoints, "points adverses")
	for i, f in snapshot.squad do
		H.eq(other.squad[i].energy, f.energy, "énergie du joueur adverse " .. i)
		H.eq(other.squad[i].rating, f.rating, "note du joueur adverse " .. i)
	end
	H.leave(q)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "player:2", "Balanced")
	local _, kind = H.lastNotify(p)
	H.eq(kind, "error", "club parti : match refusé")
end)

H.test("montée D7 → D1 validée par le serveur, une division à la fois, D1 est le plafond", function()
	-- Renvoie le solde juste avant le dernier match joué.
	local function playUntilWin()
		for _ = 1, 200 do
			local before, division, coins = data.club.stats.wins, data.club.division, data.coins
			play("ai", "Offensive")
			-- S'arrête aussi à la montée : 3 nuls d'affilée suffisent pour monter.
			if data.club.stats.wins > before or data.club.division ~= division then
				return coins
			end
		end
		error("aucune victoire en 200 matchs")
	end
	local saved = {}
	for i, f in data.squad do
		saved[i] = f.rating
		f.rating = 99 -- équipe très forte : le test porte sur les règles de montée
	end
	data.club.division = "D7"
	for index = 1, #S.Divisions.List - 1 do
		local division = S.Divisions.List[index]
		local nextDivision = S.Divisions.List[index + 1]
		H.eq(data.club.division, division.id, "division de départ " .. division.id)
		data.club.divisionPoints = division.pointsToPromote - 3
		local coins = playUntilWin()
		H.eq(data.club.division, nextDivision.id, "montée en " .. nextDivision.id)
		H.eq(data.club.divisionPoints, 0, "points remis à zéro")
		local result = H.received(p, "MatchResult")
		result = result[#result][1]
		H.ok(result.promoted, "montée annoncée")
		H.eq(result.promotionReward, nextDivision.promotionReward, "prime de montée " .. nextDivision.id)
		H.eq(data.coins, coins + result.rewards.total + nextDivision.promotionReward + (result.missionReward or 0), "prime de montée versée une fois")
	end
	H.eq(data.club.division, "D1", "D1 atteinte")
	data.club.divisionPoints = 100000
	local coins = playUntilWin()
	H.eq(data.club.division, "D1", "pas de division au-delà de D1")
	local result = H.received(p, "MatchResult")
	result = result[#result][1]
	H.ok(not result.promoted, "pas de montée en D1")
	H.eq(data.coins, coins + result.rewards.total + (result.missionReward or 0), "pas de prime de montée en D1")
	for i, f in data.squad do
		f.rating = saved[i]
	end
	data.club.division = "D7"
	data.club.divisionPoints = 0
end)

H.test("les matchs fatiguent les joueurs et l'énergie remonte avec le temps", function()
	for _, f in data.squad do
		-- les matchs précédents ont pu blesser ou suspendre un joueur (Injuries.lua)
		f.energy, f.injuredUntil, f.suspended = 100, 0, 0
	end
	play("ai", "Balanced")
	H.eq(data.squad[1].energy, 100 - S.Config.ENERGY_COST_PER_MATCH, "fatigue après match")
	H.advance(10 * 60)
	S.SquadService.RefreshEnergy(data)
	H.eq(data.squad[1].energy, 100, "récupération (plafonnée à 100)")
end)

H.test("simulation équilibrée : la meilleure équipe gagne plus souvent", function()
	local function team(rating)
		return {
			squad = {
				{ name = "A", position = "GK", rating = rating, energy = 100 },
				{ name = "B", position = "DEF", rating = rating, energy = 100 },
				{ name = "C", position = "MID", rating = rating, energy = 100 },
				{ name = "D", position = "ATT", rating = rating, energy = 100 },
			},
			tactic = "Balanced",
			bonus = 0,
		}
	end
	local strong, weak = team(70), team(45)
	local wins, losses, goals = 0, 0, 0
	for _ = 1, 2000 do
		local r = S.MatchService.Simulate(strong, weak)
		goals += r.homeGoals + r.awayGoals
		if r.homeGoals > r.awayGoals then
			wins += 1
		elseif r.homeGoals < r.awayGoals then
			losses += 1
		end
	end
	H.ok(wins > losses * 3, ("victoires %d / défaites %d"):format(wins, losses))
	local avg = goals / 2000
	H.ok(avg > 1 and avg < 8, "buts par match : " .. avg)
end)
