--[[
	BuildingService
	Construction et amélioration des installations du club.

	Le client envoie seulement l'identifiant de l'installation. Le serveur
	vérifie qu'elle existe, qu'un niveau supérieur existe, lit le prix dans
	Buildings.lua et débite une seule fois.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local TutorialService = require(script.Parent.TutorialService)

local BuildingService = {}

function BuildingService.GetLevel(player: Player, buildingId: string): number
	local data = PlayerDataService.GetData(player)
	return data and data.buildings[buildingId] or 0
end

-- Effets cumulés utiles aux autres services (match, billetterie…).
function BuildingService.GetEffects(player: Player, buildingId: string)
	return Buildings.GetEffects(buildingId, BuildingService.GetLevel(player, buildingId))
end

function BuildingService.TryUpgrade(player: Player, buildingId): (boolean, string)
	if type(buildingId) ~= "string" or not Buildings.Get(buildingId) then
		return false, "Installation inconnue."
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Profil non chargé."
	end
	local level = data.buildings[buildingId] or 1
	local cost = Buildings.GetUpgradeCost(buildingId, level)
	if not cost then
		return false, "Niveau maximum déjà atteint."
	end
	if not EconomyService.TrySpend(player, cost, "upgrade:" .. buildingId) then
		return false, ("Il te manque des %s."):format(Config.CURRENCY_NAME)
	end
	-- Aucun yield entre le débit et la montée de niveau.
	data.buildings[buildingId] = level + 1
	PlayerDataService.MarkChanged(player)
	return true, ("%s : niveau %d !"):format(Buildings.Get(buildingId).label, level + 1)
end

function BuildingService.Init()
	Net.Handle("RequestUpgrade", function(player, buildingId)
		local ok, message = BuildingService.TryUpgrade(player, buildingId)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			TutorialService.Complete(player, "FirstUpgrade")
			ClubService.RefreshPlot(player)
			ClubService.BroadcastClubs()
		end
	end)
end

return BuildingService
