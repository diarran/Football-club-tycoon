--!strict
--[[
	WorldPreview — APERÇU DE DÉMONSTRATION du quartier et des 6 terrains.

	À quoi ça sert : voir tout de suite le rendu dans Roblox Studio (bouton Play)
	avant que la vraie logique de jeu existe.

	Ce script ne fait RIEN si l'une de ces conditions est remplie :
	  1. WorldConfig.PREVIEW_ON_START vaut false (ReplicatedStorage.Shared.WorldConfig) ;
	  2. le module ServerScriptService.Server.Services.ClubService existe :
	     dans ce cas c'est ClubService qui construit le quartier et les terrains
	     (via WorldBuilder), et l'aperçu s'efface pour éviter une double construction.

	Terrains de démonstration (noms de clubs fictifs) :
	  terrain 1 = tout au niveau 1, terrain 2 = niveau 2, terrain 3 = niveau 3,
	  terrains 4 à 6 = niveau 1.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

-- On laisse passer une frame pour que tous les scripts/modules soient en place.
task.wait()

local function clubServiceExists(): boolean
	local server = ServerScriptService:FindFirstChild("Server")
	local services = server and server:FindFirstChild("Services")
	return services ~= nil and services:FindFirstChild("ClubService") ~= nil
end

if not WorldConfig.PREVIEW_ON_START then
	return
end
if clubServiceExists() then
	return
end

local DEMO_CLUBS = {
	"FC Brumeval",
	"AS Pontclar",
	"Olympique Mirabrume",
	"Sporting Clairbois",
	"Racing Valombre",
	"Union Ferlac",
}

local function uniformLevels(level: number): { [string]: number }
	local levels = {}
	for _, id in WorldConfig.FACILITY_IDS do
		levels[id] = level
	end
	return levels
end

WorldBuilder.buildDistrict()
for slotIndex = 1, WorldConfig.MAX_PLOTS do
	local level = if slotIndex <= 3 then slotIndex else 1
	local plot = WorldBuilder.buildPlot(slotIndex, uniformLevels(level), DEMO_CLUBS[slotIndex])
	print(
		string.format(
			"[WorldPreview] Terrain %d « %s » (niveau %d) : %d Parts",
			slotIndex,
			DEMO_CLUBS[slotIndex],
			level,
			WorldBuilder.countParts(plot)
		)
	)
end
