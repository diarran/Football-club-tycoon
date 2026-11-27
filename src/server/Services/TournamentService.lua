--[[
	TournamentService
	Tournoi du serveur (document, section 3) : mini-tournoi périodique à
	élimination directe, avec des matchs simulés par le serveur.

	Cycle : attente → inscriptions (Config.Tournament.REGISTRATION_SECONDS)
	→ quarts, demies, finale (un tour toutes les ROUND_SECONDS) → attente.
	Les places libres sont complétées par des clubs fictifs de la division
	médiane des inscrits. Sans inscrit, le tournoi est simplement annulé.

	- Inscription gratuite, une seule par club, seulement pendant les inscriptions.
	- Matchs neutres : pas d'énergie dépensée, pas de points de division.
	  Un nul se règle aux tirs au but (tirage 50/50 par le serveur).
	- Récompenses fixes (Config.Tournament.Rewards) × multiplicateur de la
	  division du club, versées une fois par tournoi : au plus un tournoi
	  toutes les INTERVAL_SECONDS, donc pas de monnaie infinie.
	- Un club qui quitte le serveur est éliminé et ne reçoit rien.

	Pour la salle des trophées : TournamentService.OnTournamentWon(fonction)
	appelle fonction(player, info) à chaque tournoi gagné, avec
	info = { tournamentId, clubName, division, entrants, finalScore, at }.
	Le total est aussi gardé dans data.club.stats.tournamentsWon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Events = require(Shared.Events)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local MatchService = require(script.Parent.MatchService)
local ReputationService = require(script.Parent.ReputationService)
local EventService = require(script.Parent.EventService)

local TournamentService = {}

local T = Config.Tournament
local rng = Random.new()

local state = {
	id = 0,
	phase = "waiting", -- "waiting" | "registration" | "running"
	endsAt = 0, -- fin de la phase en cours (os.clock), pour l'affichage
	entrants = {}, -- { key, name, player?, divisionId?, rivalIndex? }
	alive = {},
	rounds = {}, -- { { stage, matches = { … } } }
	lastWinner = nil, -- { clubName, ownerName }
}
local wonListeners = {}

local function stageFor(count: number): string
	if count <= 2 then
		return "Final"
	elseif count <= 4 then
		return "Semi"
	end
	return "Quarter"
end

local function publicState()
	local entrants = {}
	for _, entrant in state.entrants do
		table.insert(entrants, { id = entrant.key, name = entrant.name, human = entrant.player ~= nil })
	end
	return {
		id = state.id,
		phase = state.phase,
		secondsLeft = math.max(0, math.ceil(state.endsAt - os.clock())),
		size = T.SIZE,
		entrants = entrants,
		rounds = state.rounds,
		lastWinner = state.lastWinner,
		weekendCup = Events.IsWeekend(os.time()),
		cupMultiplier = Events.TournamentMultiplier(os.time()),
	}
end

local function broadcast()
	Net.FireAllClients("TournamentUpdated", publicState())
end

local function notify(player: Player?, key: string, params)
	if player and player.Parent then
		Net.FireClient("Notify", player, Locale.TP(player, key, params), "success")
	end
end

-- Récompense d'un club humain encore présent ; renvoie le montant versé.
local function reward(entrant, place: string): number
	local player = entrant.player
	local data = player and player.Parent and PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	local division = Divisions.Get(data.club.division)
	-- Coupe du week-end (samedi et dimanche UTC) : récompenses majorées
	-- et points d'événement selon le tour atteint (Events.lua).
	local amount = math.floor(
		T.Rewards[place] * (division and division.rewardMultiplier or 1) * Events.TournamentMultiplier(os.time()) + 0.5
	)
	EconomyService.Add(player, amount, "tournament:" .. place)
	EventService.AddCupPoints(player, place)
	return amount
end

local scheduleNext -- déclaré plus bas

local function teamFor(entrant)
	if entrant.player then
		if not entrant.player.Parent then
			return nil
		end
		return MatchService.ClubTeam(entrant.player)
	end
	return MatchService.RivalTeam(entrant.divisionId, entrant.rivalIndex)
end

local function finish(champion, finalScore: string)
	state.phase = "waiting"
	local player = champion.player
	if player and player.Parent then
		local data = PlayerDataService.GetData(player)
		local amount = reward(champion, "Winner")
		if data then
			data.club.stats.tournamentsWon += 1
			ReputationService.OnTournamentWon(player)
			PlayerDataService.MarkChanged(player)
			local info = {
				tournamentId = state.id,
				clubName = data.club.name,
				division = data.club.division,
				entrants = #state.entrants,
				finalScore = finalScore,
				at = os.time(),
			}
			for _, listener in wonListeners do
				task.spawn(listener, player, info)
			end
		end
		notify(player, "tournament.youWon", { coins = amount })
	end
	state.lastWinner = { clubName = champion.name, ownerName = if player then player.DisplayName else nil }
	scheduleNext(T.INTERVAL_SECONDS)
end

local function playRound(tournamentId: number)
	if state.id ~= tournamentId or state.phase ~= "running" then
		return
	end
	local stage = stageFor(#state.alive)
	local round = { stage = stage, matches = {} }
	local winners = {}
	for index = 1, #state.alive, 2 do
		local home, away = state.alive[index], state.alive[index + 1]
		local match = { homeName = home.name, awayName = away.name, homeGoals = 0, awayGoals = 0 }
		local homeTeam, awayTeam = teamFor(home), teamFor(away)
		local winner
		if homeTeam and awayTeam then
			local score = MatchService.Simulate(homeTeam, awayTeam)
			match.homeGoals, match.awayGoals = score.homeGoals, score.awayGoals
			if score.homeGoals == score.awayGoals then
				match.penalties = true
				winner = if rng:NextNumber() < 0.5 then home else away
			else
				winner = if score.homeGoals > score.awayGoals then home else away
			end
		else
			-- Club parti : forfait (l'autre se qualifie).
			match.forfeit = true
			winner = if homeTeam or not awayTeam then home else away
		end
		match.winnerName = winner.name
		table.insert(round.matches, match)
		table.insert(winners, winner)
		local loser = if winner == home then away else home
		local amount = reward(loser, stage)
		if amount > 0 then
			notify(loser.player, "tournament.eliminated", { stage = Locale.TP(loser.player, "tournament.stage." .. stage), coins = amount })
		end
		if stage == "Final" then
			finish(winner, ("%d-%d"):format(match.homeGoals, match.awayGoals))
		elseif winner.player then
			notify(winner.player, "tournament.qualified", { stage = Locale.TP(winner.player, "tournament.stage." .. stage) })
		end
	end
	table.insert(state.rounds, round)
	state.alive = winners
	if state.phase == "running" then
		state.endsAt = os.clock() + T.ROUND_SECONDS
		task.delay(T.ROUND_SECONDS, playRound, tournamentId)
	end
	broadcast()
end

-- Clubs fictifs pour compléter le tableau : division médiane des inscrits,
-- puis les divisions voisines si besoin. Noms uniques.
local function fillers(humans, needed: number)
	local indexes = {}
	for _, entrant in humans do
		table.insert(indexes, Divisions.Get(entrant.divisionId).index)
	end
	table.sort(indexes)
	local center = indexes[math.ceil(#indexes / 2)]
	local list, used = {}, {}
	for _, entrant in humans do
		used[entrant.name] = true
	end
	for offset = 0, #Divisions.List do
		for _, index in { center - offset, center + offset } do
			local division = Divisions.List[index]
			if division then
				for _, rival in Divisions.GetRivals(division.id) do
					if #list < needed and not used[rival.name] then
						used[rival.name] = true
						table.insert(list, {
							key = ("ai:%s:%d"):format(division.id, rival.index),
							name = rival.name,
							divisionId = division.id,
							rivalIndex = rival.index,
						})
					end
				end
			end
			if offset == 0 then
				break
			end
		end
		if #list >= needed then
			break
		end
	end
	return list
end

local function closeRegistration(tournamentId: number)
	if state.id ~= tournamentId or state.phase ~= "registration" then
		return
	end
	local humans = {}
	for _, entrant in state.entrants do
		if entrant.player and entrant.player.Parent then
			table.insert(humans, entrant)
		end
	end
	if #humans == 0 then
		state.entrants = {}
		scheduleNext(T.INTERVAL_SECONDS)
		broadcast()
		return
	end
	local entrants = table.clone(humans)
	for _, filler in fillers(humans, T.SIZE - #humans) do
		table.insert(entrants, filler)
	end
	-- Tirage au sort du tableau.
	for i = #entrants, 2, -1 do
		local j = rng:NextInteger(1, i)
		entrants[i], entrants[j] = entrants[j], entrants[i]
	end
	state.entrants = entrants
	state.alive = table.clone(entrants)
	state.rounds = {}
	state.phase = "running"
	playRound(tournamentId)
end

local function openRegistration()
	state.id += 1
	state.phase = "registration"
	state.entrants = {}
	state.alive = {}
	state.rounds = {}
	state.endsAt = os.clock() + T.REGISTRATION_SECONDS
	task.delay(T.REGISTRATION_SECONDS, closeRegistration, state.id)
	-- Le client affiche lui-même l'annonce en recevant le nouvel état.
	broadcast()
end

function scheduleNext(delaySeconds: number)
	state.phase = "waiting"
	state.endsAt = os.clock() + delaySeconds
	local id = state.id
	task.delay(delaySeconds, function()
		if state.id == id and state.phase == "waiting" then
			openRegistration()
		end
	end)
end

function TournamentService.TryJoin(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if state.phase ~= "registration" then
		return false, Locale.TP(player, "tournament.error.closed")
	end
	local key = "player:" .. player.UserId
	for _, entrant in state.entrants do
		if entrant.key == key then
			return false, Locale.TP(player, "tournament.error.alreadyIn")
		end
	end
	if #state.entrants >= T.SIZE then
		return false, Locale.TP(player, "tournament.error.full")
	end
	if #data.squad == 0 then
		return false, Locale.TP(player, "error.emptySquad")
	end
	table.insert(state.entrants, { key = key, name = data.club.name, player = player, divisionId = data.club.division })
	broadcast()
	return true, Locale.TP(player, "tournament.joined")
end

-- Abonnement pour la salle des trophées (et autres) : fn(player, info).
function TournamentService.OnTournamentWon(fn)
	table.insert(wonListeners, fn)
end

function TournamentService.GetState()
	return publicState()
end

function TournamentService.OnPlayerReady(player: Player)
	Net.FireClient("TournamentUpdated", player, publicState())
end

function TournamentService.OnPlayerLeaving(player: Player)
	if state.phase == "registration" then
		for index, entrant in state.entrants do
			if entrant.player == player then
				table.remove(state.entrants, index)
				broadcast()
				break
			end
		end
	end
	-- Pendant le tournoi : forfait au prochain match (teamFor renvoie nil).
end

function TournamentService.Init()
	scheduleNext(T.FIRST_DELAY_SECONDS)
	Net.Handle("RequestTournamentJoin", function(player)
		local ok, message = TournamentService.TryJoin(player)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
	end)
end

return TournamentService
