--[[
	MatchService
	Matchs simulés à la demande (document de conception, section 6).

	Le client demande un match contre un adversaire avec une tactique.
	Le serveur valide l'adversaire, le délai entre deux matchs et la tactique,
	puis calcule seul le score, les événements, les récompenses et la division.

	Adversaires possibles :
	- "player:<UserId>" : un autre club présent sur le serveur. Son effectif est
	  seulement lu : le match ne modifie jamais ses données.
	- "ai:<n>" : un club fictif de la division du joueur (Divisions.GetRival),
	  plus ou moins fort ; la prime de match suit sa note. "ai" = club de même niveau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local ClubIdentity = require(Shared.ClubIdentity)
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local MatchReplay = require(Shared.MatchReplay)
local Monetization = require(Shared.Monetization)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local Staff = require(Shared.Staff)
local Tactics = require(Shared.Tactics)
local Weather = require(Shared.Weather)
local WorldConfig = require(Shared.WorldConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local SquadService = require(script.Parent.SquadService)
local TutorialService = require(script.Parent.TutorialService)
local StaffService = require(script.Parent.StaffService)
local DailyService = require(script.Parent.DailyService)
local EventService = require(script.Parent.EventService)

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

-- Calcule la force d'une équipe : note globale, postes, forme, bonus, et
-- tactique face à celle de l'adversaire (pierre-feuille-ciseaux, Tactics.lua)
-- et météo du stade (Weather.lua : +1 au style avantagé, pour les deux équipes).
local function teamStrength(team, opponentTactic, weather)
	local base = average(team.squad, "rating") - positionPenalty(team.squad)
	local energyModifier = (average(team.squad, "energy") - 70) / 10
	local attackMod, defenseMod = Tactics.Modifiers(team.tactic, opponentTactic)
	local weatherAttack, weatherDefense = Weather.Modifiers(weather, Tactics.Sanitize(team.tactic))
	local overall = base + energyModifier + team.bonus
	return {
		attack = overall + attackMod + weatherAttack,
		defense = overall + defenseMod + weatherDefense,
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

local function buildAiTeam(divisionId: string, rivalIndex: number)
	local rival = Divisions.GetRival(divisionId, rivalIndex)
	local squad = {}
	local positions = { "GK", "DEF", "DEF", "MID", "ATT" }
	for index = 1, AI_SQUAD_SIZE do
		table.insert(squad, {
			-- Nom fictif fixe (pas de tirage : ne change pas les résultats des matchs).
			name = PlayerConfig.FirstNames[index] .. " " .. PlayerConfig.LastNames[#PlayerConfig.LastNames + 1 - index],
			position = positions[index],
			rating = rival.rating + rng:NextInteger(-3, 3),
			energy = 80,
		})
	end
	return {
		id = rival.id,
		name = rival.name,
		squad = squad,
		tactic = rival.tactic or Config.DEFAULT_TACTIC, -- style fixe du club fictif
		bonus = 0,
		rewardFactor = rival.rewardFactor,
	}
end

-- Équipe d'un club du serveur pour un match neutre (défi, tournoi) : bonus
-- d'entraînement seulement, pas d'avantage du terrain. Lecture seule.
function MatchService.ClubTeam(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data or #data.squad == 0 then
		return nil
	end
	SquadService.RefreshEnergy(data)
	return {
		id = "player:" .. player.UserId,
		name = data.club.name,
		squad = SquadService.Starters(data), -- titulaires (lecture seule)
		tactic = Tactics.Sanitize(data.tactic),
		bonus = (Buildings.GetEffects("Training", data.buildings.Training or 1).teamBonus or 0)
			+ Staff.Effect(data.staff, "teamBonus")
			- SquadService.MissingPenalty(data), -- blessés / suspendus sans remplaçant
	}
end

function MatchService.RivalTeam(divisionId: string, rivalIndex: number)
	return buildAiTeam(divisionId, rivalIndex)
end

-- Simulation ------------------------------------------------------------

-- `weather` (facultatif) : météo du stade (Weather.At). Sans météo, aucun effet.
function MatchService.Simulate(home, away, weather)
	local homeStrength = teamStrength(home, away.tactic, weather)
	local awayStrength = teamStrength(away, home.tactic, weather)
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

	return {
		homeGoals = homeGoals,
		awayGoals = awayGoals,
		events = events,
		-- Duel tactique (affichage) : 1 = l'équipe à domicile avait l'avantage.
		tactics = {
			home = Tactics.Sanitize(home.tactic),
			away = Tactics.Sanitize(away.tactic),
			edge = Tactics.Matchup(home.tactic, away.tactic),
		},
	}
end

-- Replay 3D (purement visuel) --------------------------------------------

local replaySeed = 0

-- Couleur principale d'un club, en { r, g, b } (0-255) pour le réseau.
local colorArray = ClubIdentity.ToArray

-- Identité résolue d'un club (couleurs, tenue) : objet Prestige, identité ou emplacement.
local function clubLook(data, slotIndex: number?)
	return ClubIdentity.Resolve(data, slotIndex)
end

-- Couleur d'un club fictif : une couleur de la palette, différente de l'hôte.
local function rivalColor(rivalId: any, homeColor: Color3)
	local palette = WorldConfig.CLUB_COLORS
	local hash = 0
	for i = 1, #tostring(rivalId) do
		hash = (hash * 31 + string.byte(tostring(rivalId), i)) % 9973
	end
	for offset = 0, #palette - 1 do
		local candidate = palette[(hash + offset) % #palette + 1].primary
		if candidate ~= homeColor then
			return candidate
		end
	end
	return Color3.new(1, 1, 1)
end

-- Construit le replay APRÈS le calcul du résultat : il ne lit que le score déjà
-- décidé et utilise son propre générateur (MatchReplay), jamais `rng`.
function MatchService.BuildReplay(player: Player, data, home, away, score, opponentData, opponentSlot)
	replaySeed += 1
	local slotIndex = ClubService.GetSlot(player)
	local homeLook = clubLook(data, slotIndex)
	local homeColor = homeLook.kit.shirt
	local awayKit
	if opponentData then
		awayKit = clubLook(opponentData, opponentSlot).kit
	else
		local rival = rivalColor(away.id, homeColor)
		awayKit = { pattern = "plain", shirt = rival, detail = Color3.new(0.95, 0.95, 0.95) }
	end
	if awayKit.shirt == homeColor then
		-- Même maillot : l'équipe à l'extérieur joue en blanc.
		awayKit = { pattern = "plain", shirt = Color3.new(0.95, 0.95, 0.95), detail = homeLook.kit.detail }
	end
	local awayColor = awayKit.shirt
	return {
		slotIndex = slotIndex,
		hostUserId = player.UserId,
		homeName = home.name,
		awayName = away.name,
		homeGoals = score.homeGoals,
		awayGoals = score.awayGoals,
		homeColor = colorArray(homeColor),
		awayColor = colorArray(awayColor),
		-- Tenues complètes (motif, maillot, détails) des deux équipes.
		homeKit = ClubIdentity.KitToNet(homeLook.kit),
		awayKit = ClubIdentity.KitToNet(awayKit),
		crowdLevel = data.buildings.Stands or 1,
		homeTactic = Tactics.Sanitize(home.tactic),
		awayTactic = Tactics.Sanitize(away.tactic),
		timeline = MatchReplay.Build(
			score.events,
			os.time() + player.UserId + replaySeed * 7919,
			{ home = home.tactic, away = away.tactic }
		),
	}
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
	if not Tactics.IsValid(tactic) then
		tactic = Tactics.Sanitize(data.tactic) -- ancienne sauvegarde ou valeur inconnue : style par défaut
	end

	local now = os.time()
	local waitLeft = Config.MATCH_COOLDOWN_SECONDS - (now - data.lastMatchAt)
	if waitLeft > 0 then
		return nil, Locale.TP(player, "error.matchCooldown", { seconds = waitLeft })
	end
	if #data.squad == 0 then
		return nil, Locale.TP(player, "error.emptySquad")
	end
	if #SquadService.Starters(data) == 0 and not SquadService.ClearSuspensionsIfStuck(data) then
		-- Tout l'effectif est blessé ou suspendu (très rare) : on attend quelques minutes.
		return nil, Locale.TP(player, "injury.noneAvailable", { minutes = SquadService.NextReturnMinutes(data) })
	end

	-- Adversaire
	local away, opponentData, opponentSlot
	local rivalIndex = Divisions.ParseRivalId(opponentId)
	if rivalIndex then
		away = buildAiTeam(data.club.division, rivalIndex)
	else
		local opponent = ClubService.FindPlayerByClubId(opponentId)
		if not opponent or opponent == player then
			return nil, Locale.TP(player, "error.opponentUnavailable")
		end
		opponentData = PlayerDataService.GetData(opponent)
		opponentSlot = ClubService.GetSlot(opponent)
		if not opponentData or #opponentData.squad == 0 then
			return nil, Locale.TP(player, "error.opponentUnavailable")
		end
		local trainingBonus = (Buildings.GetEffects("Training", opponentData.buildings.Training or 1).teamBonus or 0)
			+ Staff.Effect(opponentData.staff, "teamBonus")
			- SquadService.MissingPenalty(opponentData)
		away = {
			id = opponentId,
			name = opponentData.club.name,
			squad = SquadService.Starters(opponentData), -- titulaires, lecture seule
			tactic = Tactics.Sanitize(opponentData.tactic),
			bonus = trainingBonus,
		}
	end

	-- Équipe du joueur (club hôte)
	SquadService.RefreshEnergy(data)
	data.tactic = tactic
	local homeBonus = Config.HOME_ADVANTAGE
		+ (Buildings.GetEffects("Pitch", data.buildings.Pitch or 1).homeBonus or 0)
		+ (Buildings.GetEffects("Training", data.buildings.Training or 1).teamBonus or 0)
		+ Staff.Effect(data.staff, "teamBonus") -- entraîneur du staff
		- SquadService.MissingPenalty(data) -- blessés / suspendus sans remplaçant
	local home = {
		id = "player:" .. player.UserId,
		name = data.club.name,
		squad = SquadService.Starters(data), -- titulaires choisis (onglet Effectif)
		tactic = tactic,
		bonus = homeBonus,
	}

	-- Météo du stade au coup d'envoi (la même que celle que voit le joueur).
	local weather = Weather.Describe(now)
	local score = MatchService.Simulate(home, away, weather.kind)
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
	-- Sponsors des bureaux (+ part du directeur commercial du staff).
	local sponsor = math.floor((offices.sponsorIncome or 0) * StaffService.SponsorMultiplier(data) + 0.5)
	-- Contrats de sponsoring signés : prime fixe par match.
	local contracts = StaffService.ContractIncome(data)
	local shop = Buildings.GetEffects("Shop", data.buildings.Shop or 1).shopIncome or 0
	-- Espace VIP : bonus sur la billetterie + revenu fixe des loges.
	local vipEffects = Buildings.GetEffects("VIP", data.buildings.VIP or 1)
	local vip = math.floor(tickets * (vipEffects.ticketBonus or 0)) + (vipEffects.vipIncome or 0)
	local currentDivision = Divisions.Get(data.club.division)
	local matchReward = math.floor(
		Config.Rewards[outcome] * currentDivision.rewardMultiplier * (away.rewardFactor or 1) + 0.5
	)
	-- Événement de la semaine : petit bonus selon le thème (Events.lua).
	local eventBonus = EventService.MatchBonus(player, data, {
		match = matchReward,
		tickets = tickets,
		sponsor = sponsor,
		shop = shop,
	}, score.homeGoals, opponentData ~= nil)
	local totalReward = matchReward + tickets + sponsor + shop + vip + contracts + eventBonus
	-- Boost de revenus acheté en Robux : coupé par défaut (Monetization.BOOST_ENABLED).
	totalReward = math.floor(totalReward * Monetization.BoostMultiplier(data, os.time()))
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
	-- Une seule montée par match ; les points restent à 0 dans la nouvelle division.
	local promoted, promotionReward = false, 0
	if currentDivision.pointsToPromote and data.club.divisionPoints >= currentDivision.pointsToPromote then
		local nextDivision = Divisions.GetNext(data.club.division)
		if nextDivision then
			data.club.division = nextDivision.id
			data.club.divisionPoints = 0
			promoted = true
			promotionReward = nextDivision.promotionReward or 0
			if promotionReward > 0 then
				EconomyService.Add(player, promotionReward, "promotion:" .. nextDivision.id)
			end
		end
	end

	-- Objectifs des contrats de sponsoring (bonus unique versé ici).
	local sponsorReport = StaffService.OnMatchPlayed(player, data, outcome, score.homeGoals)

	-- Fatigue, XP, blessures, cartons et suspensions (titulaires de ce match).
	local infirmary = SquadService.ApplyMatchEffects(data, home.squad)
	-- Saison et missions du jour (primes versées par DailyService).
	DailyService.AddSeasonPoints(player, Config.DivisionPoints[outcome])
	local missionReward = DailyService.Track(player, "play")
		+ (if outcome == "Win" then DailyService.Track(player, "win") else 0)
		+ DailyService.Track(player, "goals", score.homeGoals)
	local eventPoints = EventService.OnMatchPlayed(player, outcome, score.homeGoals, opponentData ~= nil)
	PlayerDataService.MarkChanged(player)
	TutorialService.Complete(player, "FirstMatch")
	ClubService.BroadcastClubs()

	-- Replay 3D : construit en dernier, il ne peut rien changer à ce qui précède.
	local okReplay, replay = pcall(MatchService.BuildReplay, player, data, home, away, score, opponentData, opponentSlot)
	if not okReplay then
		warn("[Match] replay non construit : " .. tostring(replay))
		replay = nil
	end
	if replay then
		replay.weather = weather.kind -- ambiance du replay (pluie, neige, match de nuit)
		replay.night = weather.night
	end

	return {
		homeName = home.name,
		awayName = away.name,
		homeGoals = score.homeGoals,
		awayGoals = score.awayGoals,
		events = score.events,
		outcome = outcome,
		tactics = score.tactics,
		weather = weather,
		rewards = {
			match = matchReward,
			tickets = tickets,
			sponsor = sponsor,
			shop = shop,
			vip = vip,
			contracts = contracts,
			event = eventBonus,
			total = totalReward,
		},
		sponsorBonuses = sponsorReport.bonuses,
		sponsorsEnded = sponsorReport.ended,
		promotionReward = promotionReward,
		missionReward = missionReward,
		eventPoints = eventPoints,
		divisionPoints = data.club.divisionPoints,
		division = data.club.division,
		promoted = promoted,
		previousDivision = previousDivision,
		replay = replay,
		infirmary = infirmary,
	}
end

function MatchService.Init()
	Net.Handle("RequestMatch", function(player, opponentId, tactic)
		local result, err = MatchService.TryStartMatch(player, opponentId, tactic)
		if result then
			Net.FireClient("MatchResult", player, result)
			-- Les visiteurs présents peuvent regarder le replay (leur client
			-- vérifie qu'ils sont près du terrain avant de l'afficher).
			if result.replay and result.replay.slotIndex then
				for _, other in Players:GetPlayers() do
					if other ~= player then
						Net.FireClient("MatchReplay", other, result.replay)
					end
				end
			end
		else
			Net.FireClient("Notify", player, err, "error")
		end
	end)
end

return MatchService
