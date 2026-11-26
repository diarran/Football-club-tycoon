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
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local TutorialService = require(script.Parent.TutorialService)
local DailyService = require(script.Parent.DailyService)

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
		return false, Locale.TP(player, "error.unknownBuilding")
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local level = data.buildings[buildingId] or 1
	local cost = Buildings.GetUpgradeCost(buildingId, level)
	if not cost then
		return false, Locale.TP(player, "error.maxLevel")
	end
	if not EconomyService.TrySpend(player, cost, "upgrade:" .. buildingId) then
		return false, Locale.TP(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	-- Aucun yield entre le débit et la montée de niveau.
	data.buildings[buildingId] = level + 1
	PlayerDataService.MarkChanged(player)
	DailyService.Track(player, "upgrade")
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, "building.upgraded", {
			name = Locale.T(lang, "building." .. buildingId .. ".label"),
			level = level + 1,
		})
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
