--[[
	FriendService
	Clubs entre amis (shared/Friends.lua).

	- Amitiés : le serveur demande à Roblox quels clubs présents sont dirigés
	  par des amis du joueur (IsFriendsWith, mis en cache). Le client reçoit
	  la liste dans l'instantané (snapshot.friends.clubIds) pour afficher
	  « Ami » dans le Classement et proposer un match amical.
	- Parrainage : quand un joueur arrive grâce à une invitation Roblox
	  (GetJoinData().ReferredByPlayerId), il reçoit un bonus de bienvenue
	  une seule fois par compte, et celui qui l'a invité reçoit une prime
	  une fois par ami (plafonnée). Si l'inviteur n'est pas sur ce serveur,
	  la prime est notée dans un DataStore et versée à sa prochaine arrivée.
	- Match amical : défi sans mise entre amis (ChallengeService). Petit
	  bonus pour chacun, limité par jour.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Daily = require(Shared.Daily)
local Friends = require(Shared.Friends)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local FriendService = {}

local friendCache = {} -- ["petitId:grandId"] = true / false

local function pairKey(a: Player, b: Player): string
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	return x .. ":" .. y
end

-- Points d'accès à Roblox, remplaçables par les tests.
function FriendService.IsFriendsWith(a: Player, b: Player): boolean
	local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
	return ok and result == true
end

function FriendService.ReadJoinData(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	return if ok then joinData else nil
end

-- Amitié déjà connue (aucune attente : utilisable dans l'instantané).
function FriendService.AreFriends(a: Player, b: Player): boolean
	if a == b then
		return false
	end
	return friendCache[pairKey(a, b)] == true
end

local function notify(player: Player, key: string, params)
	if player.Parent then
		Net.FireClient("Notify", player, Locale.TP(player, key, params), "success")
	end
end

-- Amitiés --------------------------------------------------------------

local function refreshFriendships(player: Player)
	for _, other in PlayerDataService.GetLoadedPlayers() do
		if other ~= player then
			local key = pairKey(player, other)
			if friendCache[key] == nil then
				local friends = FriendService.IsFriendsWith(player, other)
				if not player.Parent or not other.Parent then
					continue
				end
				friendCache[key] = friends
				if friends then
					PlayerDataService.MarkChanged(player)
					PlayerDataService.MarkChanged(other)
				end
			end
		end
	end
end

-- Parrainage -----------------------------------------------------------

local pendingStore = nil
local function getPendingStore()
	if not pendingStore then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(Friends.PENDING_STORE)
		end)
		pendingStore = ok and store or nil
	end
	return pendingStore
end

local function canUseStore(player: Player): boolean
	local profile = PlayerDataService.Get(player)
	return profile ~= nil and not profile.temporary
end

-- Prime de l'inviteur : une fois par ami, plafonnée.
local function creditInviter(inviter: Player, inviteeId: number): boolean
	local data = PlayerDataService.GetData(inviter)
	if not data then
		return false
	end
	local friends = data.friends
	local key = tostring(inviteeId)
	if inviteeId == inviter.UserId or friends.referred[key] or friends.rewardsGiven >= Friends.MAX_INVITER_REWARDS then
		return false
	end
	friends.referred[key] = true
	friends.rewardsGiven += 1
	EconomyService.Add(inviter, Friends.INVITER_REWARD, "parrainage")
	PlayerDataService.MarkChanged(inviter)
	notify(inviter, "friends.inviteReward", { coins = Friends.INVITER_REWARD })
	return true
end

-- Inviteur absent : la prime l'attend dans le DataStore.
local function queuePending(inviterId: number, inviteeId: number)
	local store = getPendingStore()
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(inviterId), function(list)
			list = if type(list) == "table" then list else {}
			if table.find(list, inviteeId) or #list >= Friends.MAX_PENDING then
				return nil
			end
			table.insert(list, inviteeId)
			return list
		end)
	end)
	if not ok then
		warn("[FriendService] Prime de parrainage non enregistrée : " .. tostring(err))
	end
end

-- Primes reçues pendant l'absence du joueur.
function FriendService.ClaimPending(player: Player)
	if not canUseStore(player) then
		return
	end
	local store = getPendingStore()
	if not store then
		return
	end
	local claimed = nil
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(player.UserId), function(list)
			if type(list) ~= "table" or #list == 0 then
				return nil
			end
			claimed = list
			return {}
		end)
	end)
	if not ok then
		warn("[FriendService] Primes de parrainage illisibles : " .. tostring(err))
		return
	end
	for _, inviteeId in claimed or {} do
		if type(inviteeId) == "number" then
			creditInviter(player, inviteeId)
		end
	end
end

-- Renvoie l'UserId de l'inviteur, ou nil.
local function referrerOf(player: Player): number?
	local joinData = FriendService.ReadJoinData(player)
	if type(joinData) ~= "table" then
		return nil
	end
	local id = joinData.ReferredByPlayerId
	if type(id) ~= "number" or id ~= id or id <= 0 or id == math.huge or id == player.UserId then
		return nil
	end
	return math.floor(id)
end

-- Renvoie true si le joueur vient d'être accueilli grâce à une invitation.
function FriendService.HandleReferral(player: Player): boolean
	local data = PlayerDataService.GetData(player)
	local inviterId = referrerOf(player)
	if not data or not inviterId or data.friends.welcomeClaimed then
		return false
	end
	-- Un seul parrain par compte : l'invité n'est compté qu'une fois.
	data.friends.welcomeClaimed = true
	EconomyService.Add(player, Friends.INVITEE_WELCOME, "bienvenue parrainage")
	PlayerDataService.MarkChanged(player)
	notify(player, "friends.welcome", { coins = Friends.INVITEE_WELCOME })

	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and PlayerDataService.GetData(inviter) then
		creditInviter(inviter, player.UserId)
	elseif canUseStore(player) then
		task.spawn(queuePending, inviterId, player.UserId)
	end
	return true
end

-- Matchs amicaux -------------------------------------------------------

local function friendlyCountToday(data): number
	if data.friends.friendlyDay ~= Daily.Day(os.time()) then
		return 0
	end
	return data.friends.friendlyCount
end

-- Bonus d'un match amical (0 si la limite du jour est atteinte).
function FriendService.GrantFriendlyBonus(player: Player): number
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	local count = friendlyCountToday(data)
	if count >= Friends.FRIENDLY_BONUS_PER_DAY then
		return 0
	end
	data.friends.friendlyDay = Daily.Day(os.time())
	data.friends.friendlyCount = count + 1
	EconomyService.Add(player, Friends.FRIENDLY_BONUS, "match amical")
	return Friends.FRIENDLY_BONUS
end

function FriendService.Snapshot(player: Player, data)
	local clubIds = {}
	for _, other in PlayerDataService.GetLoadedPlayers() do
		if FriendService.AreFriends(player, other) then
			table.insert(clubIds, "player:" .. other.UserId)
		end
	end
	return {
		clubIds = clubIds,
		friendlyLeft = math.max(0, Friends.FRIENDLY_BONUS_PER_DAY - friendlyCountToday(data)),
		rewardsGiven = data.friends.rewardsGiven,
	}
end

-- Cycle de vie ---------------------------------------------------------

function FriendService.OnPlayerReady(player: Player)
	FriendService.HandleReferral(player)
	task.spawn(FriendService.ClaimPending, player)
	task.spawn(refreshFriendships, player)
end

function FriendService.OnPlayerLeaving(player: Player)
	-- Les amis restants ne voient plus ce club dans leur liste.
	for _, other in PlayerDataService.GetLoadedPlayers() do
		if other ~= player and FriendService.AreFriends(player, other) then
			PlayerDataService.MarkChanged(other)
		end
	end
	local id = player.UserId
	for key in friendCache do
		local a, b = key:match("^(-?%d+):(-?%d+)$")
		if tonumber(a) == id or tonumber(b) == id then
			friendCache[key] = nil
		end
	end
end

function FriendService.Init()
	PlayerDataService.AddSnapshotField("friends", FriendService.Snapshot)
end

return FriendService
