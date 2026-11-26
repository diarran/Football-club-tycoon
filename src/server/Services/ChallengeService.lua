--[[
	ChallengeService
	Défis entre deux clubs présents sur le serveur (document, section 3).

	1. Un joueur défie un autre club avec une mise choisie dans
	   Config.Challenge.STAKES (plafonnée).
	2. Le club défié accepte ou refuse ; sans réponse, le défi expire.
	3. À l'acceptation, le serveur vérifie que les deux clubs peuvent payer,
	   prélève les deux mises, simule un match neutre et verse le pot au
	   gagnant (nul : chacun est remboursé).

	Aucune monnaie n'est créée : le pot ne contient que les deux mises.
	Un défi ne touche ni l'énergie, ni la division, ni les statistiques de
	championnat. Seul le club défié peut accepter son défi.
	Anti-spam : un défi envoyé à la fois, délai entre deux envois, nombre de
	défis reçus limité, adversaire bloqué un moment après un refus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local MatchService = require(script.Parent.MatchService)

local ChallengeService = {}

local C = Config.Challenge
local challenges = {} -- [id] = { id, from, to, stake, expiresAt }
local lastSentAt = {} -- [Player] = os.clock()
local pairBlockedUntil = {} -- ["fromId:toId"] = os.clock()
local nextId = 0

local function isAllowedStake(stake): boolean
	for _, allowed in C.STAKES do
		if stake == allowed then
			return true
		end
	end
	return false
end

local function pairKey(from: Player, to: Player): string
	return from.UserId .. ":" .. to.UserId
end

-- Envoie à un joueur la liste de ses défis (reçus et envoyé).
local function sendState(player: Player)
	if not player.Parent then
		return
	end
	local now = os.clock()
	local state = { incoming = {}, outgoing = nil }
	for _, challenge in challenges do
		local entry = {
			id = challenge.id,
			stake = challenge.stake,
			expiresIn = math.max(0, math.ceil(challenge.expiresAt - now)),
		}
		if challenge.to == player then
			local data = PlayerDataService.GetData(challenge.from)
			entry.clubName = data and data.club.name or challenge.from.DisplayName
			entry.ownerName = challenge.from.DisplayName
			table.insert(state.incoming, entry)
		elseif challenge.from == player then
			local data = PlayerDataService.GetData(challenge.to)
			entry.clubName = data and data.club.name or challenge.to.DisplayName
			entry.ownerName = challenge.to.DisplayName
			state.outgoing = entry
		end
	end
	table.sort(state.incoming, function(a, b)
		return a.id < b.id
	end)
	Net.FireClient("ChallengeUpdated", player, state)
end

local function remove(challenge, reason: string?)
	if challenges[challenge.id] ~= challenge then
		return
	end
	challenges[challenge.id] = nil
	sendState(challenge.from)
	sendState(challenge.to)
	if reason and challenge.from.Parent then
		local data = PlayerDataService.GetData(challenge.to)
		Net.FireClient(
			"Notify",
			challenge.from,
			Locale.TP(challenge.from, reason, { club = data and data.club.name or challenge.to.DisplayName }),
			"info"
		)
	end
end

function ChallengeService.TrySend(player: Player, targetId, stake)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(stake) ~= "number" or not isAllowedStake(stake) then
		return false, Locale.TP(player, "challenge.error.invalidStake")
	end
	local target = ClubService.FindPlayerByClubId(targetId)
	local targetData = target and PlayerDataService.GetData(target)
	if not target or target == player or not targetData then
		return false, Locale.TP(player, "error.opponentUnavailable")
	end
	if #data.squad == 0 or #targetData.squad == 0 then
		return false, Locale.TP(player, "error.opponentUnavailable")
	end
	local now = os.clock()
	for _, challenge in challenges do
		if challenge.from == player then
			return false, Locale.TP(player, "challenge.error.alreadyPending")
		end
	end
	local waitLeft = C.SEND_COOLDOWN_SECONDS - (now - (lastSentAt[player] or -math.huge))
	if waitLeft > 0 then
		return false, Locale.TP(player, "challenge.error.cooldown", { seconds = math.ceil(waitLeft) })
	end
	if (pairBlockedUntil[pairKey(player, target)] or 0) > now then
		return false, Locale.TP(player, "challenge.error.recentlyRefused")
	end
	local incoming = 0
	for _, challenge in challenges do
		if challenge.to == target then
			incoming += 1
		end
	end
	if incoming >= C.MAX_INCOMING then
		return false, Locale.TP(player, "challenge.error.targetBusy")
	end
	if not EconomyService.CanAfford(player, stake) then
		return false, Locale.TP(player, "challenge.error.cannotAfford")
	end

	nextId += 1
	local challenge = { id = nextId, from = player, to = target, stake = stake, expiresAt = now + C.EXPIRE_SECONDS }
	challenges[challenge.id] = challenge
	lastSentAt[player] = now
	task.delay(C.EXPIRE_SECONDS, function()
		remove(challenge, "challenge.expired")
	end)
	sendState(player)
	sendState(target)
	Net.FireClient(
		"Notify",
		target,
		Locale.TP(target, "challenge.received", { club = data.club.name, stake = stake }),
		"info"
	)
	return true, Locale.TP(player, "challenge.sent", { club = targetData.club.name })
end

-- Le club défié accepte (accept = true) ou refuse.
function ChallengeService.TryRespond(player: Player, challengeId, accept)
	local challenge = type(challengeId) == "number" and challenges[challengeId] or nil
	if not challenge or challenge.to ~= player then
		return false, Locale.TP(player, "challenge.error.notFound")
	end
	if accept ~= true then
		pairBlockedUntil[pairKey(challenge.from, challenge.to)] = os.clock() + C.PAIR_COOLDOWN_SECONDS
		remove(challenge, "challenge.refused")
		return true, Locale.TP(player, "challenge.youRefused")
	end

	local challenger = challenge.from
	local home = challenger.Parent and MatchService.ClubTeam(challenger)
	local away = MatchService.ClubTeam(player)
	if not home or not away then
		remove(challenge)
		return false, Locale.TP(player, "error.opponentUnavailable")
	end
	local stake = challenge.stake
	-- Vérification puis double débit sans pause : impossible de payer deux fois.
	if not EconomyService.CanAfford(challenger, stake) then
		remove(challenge, "challenge.error.challengerCannotAfford")
		return false, Locale.TP(player, "challenge.error.challengerBroke")
	end
	if not EconomyService.CanAfford(player, stake) then
		return false, Locale.TP(player, "challenge.error.cannotAfford")
	end
	challenges[challenge.id] = nil
	EconomyService.TrySpend(challenger, stake, "challenge:stake")
	EconomyService.TrySpend(player, stake, "challenge:stake")

	local score = MatchService.Simulate(home, away)
	local winner = nil
	if score.homeGoals > score.awayGoals then
		winner = challenger
	elseif score.awayGoals > score.homeGoals then
		winner = player
	end
	if winner then
		EconomyService.Add(winner, stake * 2, "challenge:win")
		local stats = PlayerDataService.GetData(winner).club.stats
		stats.challengesWon += 1
	else
		EconomyService.Add(challenger, stake, "challenge:draw")
		EconomyService.Add(player, stake, "challenge:draw")
	end

	-- Chaque club reçoit le résultat de son point de vue.
	local function resultFor(viewer: Player, mine, theirs, myGoals, theirGoals, flip: boolean)
		local events = {}
		for _, event in score.events do
			local side = event.side
			if flip then
				side = if side == "home" then "away" else "home"
			end
			table.insert(events, { minute = event.minute, side = side, scorer = event.scorer })
		end
		local outcome = if winner == nil then "Draw" elseif winner == viewer then "Win" else "Loss"
		return {
			mode = "challenge",
			homeName = mine.name,
			awayName = theirs.name,
			homeGoals = myGoals,
			awayGoals = theirGoals,
			events = events,
			outcome = outcome,
			stake = stake,
			coinsChange = if outcome == "Win" then stake elseif outcome == "Loss" then -stake else 0,
		}
	end
	Net.FireClient("MatchResult", challenger, resultFor(challenger, home, away, score.homeGoals, score.awayGoals, false))
	Net.FireClient("MatchResult", player, resultFor(player, away, home, score.awayGoals, score.homeGoals, true))
	PlayerDataService.MarkChanged(challenger)
	PlayerDataService.MarkChanged(player)
	sendState(challenger)
	sendState(player)
	return true, nil
end

function ChallengeService.OnPlayerReady(player: Player)
	sendState(player)
end

function ChallengeService.OnPlayerLeaving(player: Player)
	for _, challenge in challenges do
		if challenge.from == player or challenge.to == player then
			remove(challenge, if challenge.to == player then "challenge.expired" else nil)
		end
	end
	lastSentAt[player] = nil
	for key in pairBlockedUntil do
		local a, b = key:match("^(%d+):(%d+)$")
		if tonumber(a) == player.UserId or tonumber(b) == player.UserId then
			pairBlockedUntil[key] = nil
		end
	end
end

-- Pour les tests : nombre de défis en attente.
function ChallengeService.PendingCount(): number
	local count = 0
	for _ in challenges do
		count += 1
	end
	return count
end

function ChallengeService.Init()
	local function reply(player, ok, message)
		if message then
			Net.FireClient("Notify", player, message, if ok then "success" else "error")
		end
	end
	Net.Handle("RequestChallenge", function(player, targetId, stake)
		reply(player, ChallengeService.TrySend(player, targetId, stake))
	end)
	Net.Handle("RequestChallengeResponse", function(player, challengeId, accept)
		reply(player, ChallengeService.TryRespond(player, challengeId, accept))
	end)
end

return ChallengeService
