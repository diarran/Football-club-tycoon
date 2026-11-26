--[[
	MatchService
	Matchs simulés à la demande (document de conception, section 6).

	Le client demande un match contre un adversaire avec une tactique.
	Le serveur valide l'adversaire, le délai entre deux matchs et la tactique,
	puis calcule seul le score, les événements, les récompenses et la division.

	Adversaires possibles :
	- "player:<UserId>" : un autre club présent sur le serveur. Son effectif est
	  seulement lu : le match ne modifie jamais ses données.
	- "ai" : un club amical généré au niveau de la division du joueur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local ClubNames = require(Shared.ClubNames)
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local SquadService = require(script.Parent.SquadService)
local TutorialService = require(script.Parent.TutorialService)

local MatchService = {}

local rng = Random.new()
local AI_SQUAD_SIZE = 5

-- Outils ----------------------------------------------------------------

local function poisson(lambda: number): number
	local limit, k, p = math.exp(-lambda), 0, 1
	repeat
		k += 1
		p *= rng:NextNumber()
	until p <= limit
	return k - 1
end

local function average(list, field: string): number
	if #list == 0 then
		return 0
	end
	local total = 0
	for _, item in list do
		total += item[field]
	end
	return total / #list
end

-- Malus si l'effectif n'a pas les postes clés.
local function positionPenalty(squad): number
	local has = {}
	for _, footballer in squad do
		has[footballer.position] = true
	end
	local penalty = 0
	if not has.GK then
		penalty += 5
	end
	if not has.ATT then
		penalty += 3
	end
	if not has.DEF then
		penalty += 2
	end
	if not has.MID then
		penalty += 2
	end
	return penalty
end

-- Calcule la force d'une équipe : note globale, postes, forme, tactique, bonus.
local function teamStrength(team)
	local base = average(team.squad, "rating") - positionPenalty(team.squad)
	local energyModifier = (average(team.squad, "energy") - 70) / 10
	local tactic = Config.Tactics[team.tactic] or Config.Tactics[Config.DEFAULT_TACTIC]
	local overall = base + energyModifier + team.bonus
	return {
		attack = overall + tactic.attack,
		defense = overall + tactic.defense,
	}
end

local function expectedGoals(attack: number, defense: number): number
	return math.clamp(1.35 + (attack - defense) / 12, 0.2, 4)
end

local function pickScorer(squad)
	local weights = { ATT = 5, MID = 3, DEF = 1, GK = 0 }
	local total = 0
	for _, footballer in squad do
		total += weights[footballer.position] or 1
	end
	if total == 0 then
		return squad[1] and squad[1].name or "?"
	end
	local roll = rng:NextNumber() * total
	for _, footballer in squad do
		roll -= weights[footballer.position] or 1
		if roll <= 0 then
			return footballer.name
		end
	end
	return squad[#squad].name
end

local function buildAiTeam(divisionId: string)
	local division = Divisions.Get(divisionId)
	local squad = {}
	local positions = { "GK", "DEF", "DEF", "MID", "ATT" }
	for index = 1, AI_SQUAD_SIZE do
		table.insert(squad, {
			-- Nom fictif fixe (pas de tirage : ne change pas les résultats des matchs).
			name = PlayerConfig.FirstNames[index] .. " " .. PlayerConfig.LastNames[#PlayerConfig.LastNames + 1 - index],
			position = positions[index],
			rating = division.opponentRating + rng:NextInteger(-3, 3),
			energy = 80,
		})
	end
	return {
		id = "ai",
		name = ClubNames.Generate(rng),
		squad = squad,
		tactic = Config.DEFAULT_TACTIC,
		bonus = 0,
	}
end

-- Simulation ------------------------------------------------------------

function MatchService.Simulate(home, away)
	local homeStrength = teamStrength(home)
	local awayStrength = teamStrength(away)
	local homeGoals = poisson(expectedGoals(homeStrength.attack, awayStrength.defense))
	local awayGoals = poisson(expectedGoals(awayStrength.attack, homeStrength.defense))

	local events = {}
	for _ = 1, homeGoals do
		table.insert(
			events,
			{ minute = rng:NextInteger(1, 90), side = "home", scorer = pickScorer(home.squad) }
		)
	end
	for _ = 1, awayGoals do
		table.insert(
			events,
			{ minute = rng:NextInteger(1, 90), side = "away", scorer = pickScorer(away.squad) }
		)
	end
	table.sort(events, function(a, b)
		return a.minute < b.minute
	end)

	return { homeGoals = homeGoals, awayGoals = awayGoals, events = events }
end

-- Demande de match ------------------------------------------------------

function MatchService.TryStartMatch(player: Player, opponentId, tactic)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(opponentId) ~= "string" then
		return nil, Locale.TP(player, "error.invalidOpponent")
	end
	if type(tactic) ~= "string" or not Config.Tactics[tactic] then
		tactic = data.tactic
	end

	local now = os.time()
	local waitLeft = Config.MATCH_COOLDOWN_SECONDS - (now - data.lastMatchAt)
	if waitLeft > 0 then
		return nil, Locale.TP(player, "error.matchCooldown", { seconds = waitLeft })
	end
	if #data.squad == 0 then
		return nil, Locale.TP(player, "error.emptySquad")
	end

	-- Adversaire
	local away
	if opponentId == "ai" then
		away = buildAiTeam(data.club.division)
	else
		local opponent = ClubService.FindPlayerByClubId(opponentId)
		if not opponent or opponent == player then
			return nil, Locale.TP(player, "error.opponentUnavailable")
		end
		local opponentData = PlayerDataService.GetData(opponent)
		if not opponentData or #opponentData.squad == 0 then
			return nil, Locale.TP(player, "error.opponentUnavailable")
		end
		local trainingBonus = Buildings.GetEffects("Training", opponentData.buildings.Training or 1).teamBonus
			or 0
		away = {
			id = opponentId,
			name = opponentData.club.name,
			squad = table.clone(opponentData.squad), -- lecture seule
			tactic = opponentData.tactic,
			bonus = trainingBonus,
		}
	end

	-- Équipe du joueur (club hôte)
	SquadService.RefreshEnergy(data)
	data.tactic = tactic
	local homeBonus = Config.HOME_ADVANTAGE
		+ (Buildings.GetEffects("Pitch", data.buildings.Pitch or 1).homeBonus or 0)
		+ (Buildings.GetEffects("Training", data.buildings.Training or 1).teamBonus or 0)
	local home = {
		id = "player:" .. player.UserId,
		name = data.club.name,
		squad = data.squad,
		tactic = tactic,
		bonus = homeBonus,
	}

	local score = MatchService.Simulate(home, away)
	data.lastMatchAt = now

	-- Résultat et récompenses (calculés ici, jamais par le client)
	local outcome = if score.homeGoals > score.awayGoals
		then "Win"
		elseif score.homeGoals == score.awayGoals then "Draw"
		else "Loss"

	local stands = Buildings.GetEffects("Stands", data.buildings.Stands or 1)
	local offices = Buildings.GetEffects("Offices", data.buildings.Offices or 1)
	local attendance = 0.6 + rng:NextNumber() * 0.3
	local tickets = math.floor((stands.capacity or 0) * attendance * (stands.ticketPrice or 0))
	local sponsor = offices.sponsorIncome or 0
	local shop = Buildings.GetEffects("Shop", data.buildings.Shop or 1).shopIncome or 0
	local matchReward = Config.Rewards[outcome]
	local totalReward = matchReward + tickets + sponsor + shop
	EconomyService.Add(player, totalReward, "match:" .. outcome)

	local stats = data.club.stats
	stats.played += 1
	stats.goalsFor += score.homeGoals
	stats.goalsAgainst += score.awayGoals
	if outcome == "Win" then
		stats.wins += 1
	elseif outcome == "Draw" then
		stats.draws += 1
	else
		stats.losses += 1
	end

	-- Division : chaque match validé rapporte des points ; la montée est vérifiée ici.
	local previousDivision = data.club.division
	data.club.divisionPoints += Config.DivisionPoints[outcome]
	local division = Divisions.Get(data.club.division)
	local promoted = false
	if division.pointsToPromote and data.club.divisionPoints >= division.pointsToPromote then
		local nextDivision = Divisions.GetNext(data.club.division)
		if nextDivision then
			data.club.division = nextDivision.id
			data.club.divisionPoints = 0
			promoted = true
		end
	end

	SquadService.ApplyMatchEffects(data)
	PlayerDataService.MarkChanged(player)
	TutorialService.Complete(player, "FirstMatch")
	ClubService.BroadcastClubs()

	return {
		homeName = home.name,
		awayName = away.name,
		homeGoals = score.homeGoals,
		awayGoals = score.awayGoals,
		events = score.events,
		outcome = outcome,
		rewards = { match = matchReward, tickets = tickets, sponsor = sponsor, shop = shop, total = totalReward },
		divisionPoints = data.club.divisionPoints,
		division = data.club.division,
		promoted = promoted,
		previousDivision = previousDivision,
	}
end

function MatchService.Init()
	Net.Handle("RequestMatch", function(player, opponentId, tactic)
		local result, err = MatchService.TryStartMatch(player, opponentId, tactic)
		if result then
			Net.FireClient("MatchResult", player, result)
		else
			Net.FireClient("Notify", player, err, "error")
		end
	end)
end

return MatchService
