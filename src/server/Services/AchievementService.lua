--[[
	AchievementService
	Succès (shared/Achievements.lua) : débloqués automatiquement dès que le
	profil remplit la condition, primes en FC Coins à récupérer avec un
	bouton (RequestAchievementClaim, sans argument : tout ce qui est prêt).

	- Vérification après chaque changement du profil (PlayerDataService.OnChanged),
	  donc aussi à l'arrivée du joueur : un ancien profil reçoit tout de suite
	  les succès qu'il mérite.
	- Aucune notification serveur : le client annonce lui-même un nouveau
	  succès en comparant deux instantanés (les autres messages ne sont pas
	  remplacés).
	- Badges Roblox : donnés par BadgeService quand le numéro du badge est
	  rempli dans Achievements.BADGE_IDS. Un badge n'est noté « donné » que si
	  Roblox l'a accepté ; en cas d'échec, nouvel essai à la prochaine partie.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local AchievementService = {}

-- Badges déjà tentés pendant cette partie : [Player] = { [id] = true }.
local attempted = setmetatable({}, { __mode = "k" })

local function state(data)
	local s = data.achievements
	if type(s) ~= "table" then
		s = { unlocked = {}, claimed = {}, badges = {} }
		data.achievements = s
	end
	for _, field in { "unlocked", "claimed", "badges" } do
		if type(s[field]) ~= "table" then
			s[field] = {}
		end
	end
	return s
end

-- Service des badges (remplaçable dans les tests).
function AchievementService.GetBadgeService()
	return game:GetService("BadgeService")
end

local function awardBadge(player: Player, id: string, badgeId: number)
	local service = AchievementService.GetBadgeService()
	-- AwardBadgeAsync (nom actuel), sinon AwardBadge (ancien nom).
	local ok, awarded = pcall(function()
		return service:AwardBadgeAsync(player.UserId, badgeId)
	end)
	if not ok then
		ok, awarded = pcall(function()
			return service:AwardBadge(player.UserId, badgeId)
		end)
	end
	if ok and not awarded then
		-- Déjà possédé (profil recréé…) : on le note aussi comme donné.
		local hasOk, has = pcall(function()
			return service:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		awarded = hasOk and has == true
	end
	if not ok then
		warn(("[Achievements] Badge %s non donné à %s : %s"):format(id, player.Name, tostring(awarded)))
		return
	end
	if awarded then
		local data = PlayerDataService.GetData(player)
		if data then
			state(data).badges[id] = true
		end
	end
end

-- Donne les badges Roblox des succès débloqués (numéro rempli, pas encore donnés).
function AchievementService.AwardBadges(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local s = state(data)
	local tried = attempted[player]
	if not tried then
		tried = {}
		attempted[player] = tried
	end
	for _, def in Achievements.LIST do
		local badgeId = Achievements.BadgeId(def.id)
		if badgeId and s.unlocked[def.id] and not s.badges[def.id] and not tried[def.id] then
			tried[def.id] = true
			task.spawn(awardBadge, player, def.id, badgeId)
		end
	end
end

-- Débloque les succès dont la condition est remplie. Renvoie la liste des nouveaux.
function AchievementService.Evaluate(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return {}
	end
	local s = state(data)
	local fresh = {}
	for _, def in Achievements.LIST do
		if not s.unlocked[def.id] and Achievements.IsMet(def, data) then
			s.unlocked[def.id] = os.time()
			table.insert(fresh, def.id)
		end
	end
	AchievementService.AwardBadges(player)
	return fresh
end

-- Verse les primes de tous les succès débloqués et pas encore récupérés.
-- Renvoie le total versé et le nombre de succès concernés.
function AchievementService.Claim(player: Player): (number, number)
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0, 0
	end
	local s = state(data)
	local total, count = 0, 0
	for _, def in Achievements.LIST do
		if s.unlocked[def.id] and not s.claimed[def.id] then
			s.claimed[def.id] = true
			total += def.reward
			count += 1
		end
	end
	if total > 0 then
		EconomyService.Add(player, total, ("succès (%d)"):format(count))
		PlayerDataService.MarkChanged(player)
	end
	return total, count
end

-- Instantané client : liste dans l'ordre, nombre de primes prêtes.
function AchievementService.Snapshot(data)
	local s = state(data)
	local list, unlockedCount, ready = {}, 0, 0
	for _, def in Achievements.LIST do
		local unlocked = s.unlocked[def.id] ~= nil
		local claimed = s.claimed[def.id] == true
		if unlocked then
			unlockedCount += 1
			if not claimed then
				ready += 1
			end
		end
		table.insert(list, {
			id = def.id,
			reward = def.reward,
			target = def.target,
			progress = if unlocked then def.target else Achievements.Progress(def, data),
			unlocked = unlocked,
			claimed = claimed,
			badge = Achievements.HasBadgeSlot(def.id),
		})
	end
	return { list = list, unlocked = unlockedCount, total = #Achievements.LIST, ready = ready }
end

function AchievementService.Init()
	PlayerDataService.AddSnapshotField("achievements", function(_, data)
		return AchievementService.Snapshot(data)
	end)
	PlayerDataService.OnChanged(function(player)
		AchievementService.Evaluate(player)
	end)
	Net.Handle("RequestAchievementClaim", function(player)
		local total, count = AchievementService.Claim(player)
		if count > 0 then
			Net.FireClient("Notify", player, Locale.TP(player, "achievement.claimed", { coins = total, count = count }), "success")
		end
	end)
end

return AchievementService
