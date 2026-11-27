--[[
	CupService
	Coupe nationale (règles et montants : shared/NationalCup.lua).

	- Une édition par saison (lundi 00:00 UTC). Au changement de saison, la
	  coupe repart du 1er tour, même si l'édition précédente n'était pas finie.
	- Le joueur lance le tour suivant avec RequestCupMatch(tactic) : le serveur
	  vérifie l'édition, le délai entre deux tours (NationalCup.ROUND_SECONDS),
	  l'effectif, puis simule le match contre le club fictif tiré au sort.
	- Le prochain adversaire est tiré dès le tour précédent (et gardé dans le
	  profil) : le joueur voit son nom, sa division et son style avant de jouer.
	- Match neutre (MatchService.ClubTeam / RivalTeam / Simulate) : pas
	  d'énergie, pas de points de division. Nul : tirs au but 50/50.
	- Prime versée par le serveur à chaque tour gagné, une seule fois (le tour
	  avance aussitôt). Coupe gagnée : stat cupsWon (trophée de la vitrine).

	Profil : data.cup = { edition, round, status, lastPlayedAt, opponent = {
	division, rival }, history = { … } }. status : "playing" | "out" | "champion".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local NationalCup = require(Shared.NationalCup)
local Net = require(Shared.Net)
local Tactics = require(Shared.Tactics)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local MatchService = require(script.Parent.MatchService)
local ReputationService = require(script.Parent.ReputationService)

local CupService = {}

local rng = Random.new()
local STATUSES = { playing = true, out = true, champion = true }

local function drawOpponent(data, round: number)
	local division = NationalCup.OpponentDivision(data.club.division, round)
	return { division = division.id, rival = rng:NextInteger(1, #Divisions.RIVALS) }
end

local function validOpponent(opponent): boolean
	return type(opponent) == "table"
		and Divisions.Get(opponent.division) ~= nil
		and type(opponent.rival) == "number"
		and Divisions.RIVALS[opponent.rival] ~= nil
end

-- Nouvelle édition, ou profil abîmé / ancien : remis dans un état valide.
local function refresh(data): boolean
	local edition = NationalCup.Edition(os.time())
	local cup = data.cup
	if type(cup) ~= "table" or cup.edition ~= edition then
		data.cup = {
			edition = edition,
			round = 1,
			status = "playing",
			lastPlayedAt = 0,
			opponent = drawOpponent(data, 1),
			history = {},
		}
		return true
	end
	local changed = false
	if type(cup.round) ~= "number" or cup.round ~= cup.round or cup.round < 1 or cup.round > NationalCup.RoundCount() then
		cup.round = math.clamp(math.floor(tonumber(cup.round) or 1), 1, NationalCup.RoundCount())
		changed = true
	end
	cup.round = math.floor(cup.round)
	if not STATUSES[cup.status] then
		cup.status = "playing"
		changed = true
	end
	if type(cup.lastPlayedAt) ~= "number" or cup.lastPlayedAt ~= cup.lastPlayedAt or cup.lastPlayedAt > os.time() then
		cup.lastPlayedAt = 0
		changed = true
	end
	if type(cup.history) ~= "table" then
		cup.history = {}
		changed = true
	end
	if cup.status == "playing" and not validOpponent(cup.opponent) then
		cup.opponent = drawOpponent(data, cup.round)
		changed = true
	end
	return changed
end

local function secondsUntilNextRound(cup): number
	return math.max(0, NationalCup.ROUND_SECONDS - (os.time() - (cup.lastPlayedAt or 0)))
end

-- Joue le tour en cours. Renvoie (résultat, nil) ou (nil, message d'erreur).
function CupService.TryPlay(player: Player, tactic)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, Locale.TP(player, "error.profileNotLoaded")
	end
	refresh(data)
	local cup = data.cup
	if cup.status == "champion" then
		return nil, Locale.TP(player, "cup.error.champion")
	elseif cup.status == "out" then
		return nil, Locale.TP(player, "cup.error.out")
	end
	local wait = secondsUntilNextRound(cup)
	if wait > 0 then
		return nil, Locale.TP(player, "cup.error.wait", { minutes = math.max(1, math.ceil(wait / 60)) })
	end
	if #data.squad == 0 then
		return nil, Locale.TP(player, "error.emptySquad")
	end
	if not Tactics.IsValid(tactic) then
		tactic = Tactics.Sanitize(data.tactic)
	end
	data.tactic = tactic

	local round = cup.round
	local opponent = cup.opponent
	local home = MatchService.ClubTeam(player)
	local away = MatchService.RivalTeam(opponent.division, opponent.rival)
	if not home or not away then
		return nil, Locale.TP(player, "error.invalidOpponent")
	end
	local score = MatchService.Simulate(home, away)
	local penalties = score.homeGoals == score.awayGoals
	local won = if penalties then rng:NextNumber() < 0.5 else score.homeGoals > score.awayGoals
	local giantKill = won and NationalCup.IsGiantKill(data.club.division, opponent.division)
	local coins = 0
	if won then
		coins = NationalCup.Reward(round, data.club.division, giantKill)
		EconomyService.Add(player, coins, ("cup:%d:%d"):format(cup.edition, round))
	end

	table.insert(cup.history, {
		round = round,
		division = opponent.division,
		rival = opponent.rival,
		myGoals = score.homeGoals,
		theirGoals = score.awayGoals,
		penalties = penalties,
		won = won,
		giantKill = giantKill,
		coins = coins,
	})
	cup.lastPlayedAt = os.time()
	local stats = data.club.stats
	if giantKill then
		stats.cupGiantKills = (stats.cupGiantKills or 0) + 1
	end
	local champion = false
	if not won then
		cup.status = "out"
		cup.opponent = { division = "", rival = 0 }
	elseif round >= NationalCup.RoundCount() then
		champion = true
		cup.status = "champion"
		cup.opponent = { division = "", rival = 0 }
		stats.cupsWon = (stats.cupsWon or 0) + 1
	else
		cup.round = round + 1
		cup.opponent = drawOpponent(data, cup.round)
	end
	-- Réputation : tour gagné, exploit, coupe gagnée (conférence de presse possible).
	local reputation = ReputationService.OnCupRound(player, data, won, giantKill, champion)
	PlayerDataService.MarkChanged(player)

	local stage = NationalCup.STAGES[round]

	-- Replay 3D : construit en dernier, il ne peut rien changer au résultat.
	local okReplay, replay = pcall(MatchService.BuildReplay, player, data, home, away, score)
	if not okReplay then
		warn("[Cup] replay non construit : " .. tostring(replay))
		replay = nil
	end
	return {
		mode = "cup",
		stage = stage,
		round = round,
		homeName = home.name,
		awayName = away.name,
		homeGoals = score.homeGoals,
		awayGoals = score.awayGoals,
		events = score.events,
		outcome = if won then "Win" else "Loss",
		penalties = penalties,
		giantKill = giantKill,
		champion = champion,
		coins = coins,
		tactics = score.tactics,
		reputation = reputation,
		replay = replay,
	}
end

-- Champ « cup » de l'instantané client.
function CupService.Snapshot(_player: Player, data)
	refresh(data)
	local cup = data.cup
	local now = os.time()
	local opponent = nil
	if cup.status == "playing" and validOpponent(cup.opponent) then
		local rival = Divisions.GetRival(cup.opponent.division, cup.opponent.rival)
		opponent = {
			name = rival.name,
			division = cup.opponent.division,
			rating = rival.rating,
			tactic = rival.tactic,
			giantKill = NationalCup.IsGiantKill(data.club.division, cup.opponent.division),
		}
	end
	local history = {}
	for _, entry in cup.history do
		local rival = Divisions.GetRival(entry.division, entry.rival)
		table.insert(history, {
			stage = NationalCup.STAGES[entry.round] or "Round32",
			name = if rival then rival.name else "?",
			division = entry.division,
			myGoals = entry.myGoals,
			theirGoals = entry.theirGoals,
			penalties = entry.penalties == true,
			won = entry.won == true,
			giantKill = entry.giantKill == true,
			coins = entry.coins or 0,
		})
	end
	return {
		edition = cup.edition,
		round = cup.round,
		stage = NationalCup.STAGES[cup.round],
		status = cup.status,
		nextIn = if cup.status == "playing" then secondsUntilNextRound(cup) else 0,
		endsIn = math.max(0, NationalCup.EditionEndsAt(cup.edition) - now),
		opponent = opponent,
		nextReward = if cup.status == "playing" then NationalCup.Reward(cup.round, data.club.division, false) else 0,
		maxReward = NationalCup.MaxReward(data.club.division),
		history = history,
		cupsWon = data.club.stats.cupsWon or 0,
	}
end

function CupService.Init()
	PlayerDataService.AddSnapshotField("cup", CupService.Snapshot)
	Net.Handle("RequestCupMatch", function(player, tactic)
		local result, err = CupService.TryPlay(player, tactic)
		if result then
			Net.FireClient("MatchResult", player, result)
		elseif err then
			Net.FireClient("Notify", player, err, "error")
		end
	end)
end

return CupService
