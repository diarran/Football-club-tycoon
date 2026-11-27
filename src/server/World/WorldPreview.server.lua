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
	  terrains 1 à 5 = toutes les installations au niveau 1 à 5, terrain 6 = niveau 1.
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

-- Personnalisation et trophées de démonstration : le club de niveau 5 a tout
-- (couleurs, éclairage, statue, tenue, décorations, salle des trophées pleine).
local Trophies = require(ReplicatedStorage.Shared:WaitForChild("Trophies"))
local DEMO_STYLES = {
	[3] = { colors = "colors_royal", kit = "kit_stripes", decor = { decor_flags = true, decor_flowers = true }, trophies = Trophies.Earned("D5", { wins = 60, played = 120 }, 0) },
	[5] = {
		colors = "colors_prestige",
		lighting = "lighting_gold",
		statue = "statue_legend",
		kit = "kit_sash",
		decor = { decor_flags = true, decor_flowers = true, decor_palms = true, decor_fountain = true, decor_arch = true, decor_walk = true },
		trophies = Trophies.Earned("D1", { wins = 1200, played = 2100, goalsFor = 5200 }, 12),
		titles = 12,
		-- Mode Création : les 10 bâtiments au niveau 3, tournés dans plusieurs sens.
		campus = {
			parcels = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true, ["10"] = true, ["11"] = true, ["12"] = true },
			placed = {
				Champions = { parcel = 2, level = 3, rot = 0 },
				Museum = { parcel = 1, level = 3, rot = 0 },
				President = { parcel = 3, level = 3, rot = 0 },
				Esport = { parcel = 4, level = 3, rot = 270 },
				Recovery = { parcel = 6, level = 3, rot = 180 },
				SportsComplex = { parcel = 5, level = 3, rot = 0 },
				IndoorPitch = { parcel = 7, level = 3, rot = 0 },
				Security = { parcel = 8, level = 3, rot = 90 },
				Workshop = { parcel = 9, level = 3, rot = 0 },
				Depot = { parcel = 10, level = 3, rot = 0 },
			},
		},
	},
	[4] = {
		campus = {
			parcels = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true },
			placed = {
				Esport = { parcel = 1, level = 1, rot = 0 },
				Museum = { parcel = 2, level = 2, rot = 0 },
				SportsComplex = { parcel = 3, level = 1, rot = 0 },
				IndoorPitch = { parcel = 4, level = 1, rot = 0 },
				Security = { parcel = 5, level = 1, rot = 0 },
				Workshop = { parcel = 6, level = 1, rot = 0 },
				Depot = { parcel = 7, level = 2, rot = 0 },
			},
		},
	},
}

WorldBuilder.buildDistrict()
for slotIndex = 1, WorldConfig.MAX_PLOTS do
	local level = if slotIndex <= WorldConfig.MAX_LEVEL then slotIndex else 1
	local plot = WorldBuilder.buildPlot(slotIndex, uniformLevels(level), DEMO_CLUBS[slotIndex], DEMO_STYLES[slotIndex])
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
