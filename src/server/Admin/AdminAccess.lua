--[[
	AdminAccess (serveur uniquement)
	Dit si un joueur est administrateur et si un code admin est juste.
	Ne dépend d'aucun service, pour être utilisable partout côté serveur.
]]

local RunService = game:GetService("RunService")

local AdminConfig = require(script.Parent.AdminConfig)
local sha256 = require(script.Parent.Sha256)

local AdminAccess = {}

-- Majuscules, sans espaces ni tirets : « fc-2abc 3def » = « FC2ABC3DEF ».
function AdminAccess.Normalize(code: string): string
	return (string.upper(code):gsub("[%s%-]", ""))
end

function AdminAccess.IsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(AdminConfig.ADMIN_USER_IDS, player.UserId) then
		return true
	end
	local creatorId = game.CreatorId
	if type(creatorId) ~= "number" or creatorId <= 0 then
		return false
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == creatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, creatorId)
		return ok and rank == 255 -- 255 = propriétaire du groupe
	end
	return false
end

function AdminAccess.CheckCode(code: string): boolean
	return sha256(AdminConfig.SALT .. AdminAccess.Normalize(code)) == AdminConfig.CODE_SHA256
end

return AdminAccess
