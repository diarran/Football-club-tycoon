--[[
	CommunityService
	Bonus unique pour avoir rejoint le groupe Roblox du jeu (Community).
	Le client demande, le serveur vérifie l'appartenance au groupe auprès
	de Roblox et n'accorde le bonus qu'une seule fois par profil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Community = require(ReplicatedStorage.Shared.Community)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local CommunityService = {}

local function isMember(player: Player): boolean
	local ok, member = pcall(function()
		return player:IsInGroupAsync(Community.GROUP_ID)
	end)
	if not ok then
		ok, member = pcall(player.IsInGroup, player, Community.GROUP_ID)
	end
	return ok and member == true
end

-- Renvoie "granted", "already", "notMember" ou "disabled".
function CommunityService.ClaimGroupReward(player: Player): string
	if not Community.GroupEnabled() then
		return "disabled"
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return "disabled"
	end
	if data.community.groupRewardClaimed then
		return "already"
	end
	if not isMember(player) then
		return "notMember"
	end
	-- Revérifié après l'attente (deux demandes rapides, joueur parti).
	data = PlayerDataService.GetData(player)
	if not data or data.community.groupRewardClaimed then
		return "already"
	end
	data.community.groupRewardClaimed = true
	EconomyService.Add(player, Community.GROUP_REWARD, "groupe Roblox")
	return "granted"
end

function CommunityService.Init()
	Net.Handle("RequestGroupReward", function(player)
		local result = CommunityService.ClaimGroupReward(player)
		if result == "granted" then
			Net.FireClient(
				"Notify",
				player,
				Locale.TP(player, "community.groupThanks", { coins = Community.GROUP_REWARD }),
				"success"
			)
		elseif result == "notMember" then
			Net.FireClient("Notify", player, Locale.TP(player, "community.groupNotMember"), "info")
		end
	end)
end

return CommunityService
