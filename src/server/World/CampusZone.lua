--!strict
--[[
	CampusZone — zone du mode Création derrière un terrain de club :
	pelouse, boulevard, allées, et les 12 parcelles (WorldConfig.PARCELS) :
	  - verrouillée : bordure basse et panneau « À VENDRE » (prix, division) ;
	  - débloquée et libre : dalle claire et panneau « Parcelle libre » ;
	  - occupée : le bâtiment choisi par le joueur, tourné comme il l'a voulu.
	Les données viennent de data.campus (Campus.lua), lues par ClubService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Campus = require(Shared:WaitForChild("Campus"))
local Divisions = require(Shared:WaitForChild("Divisions"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))
local Props = require(script.Parent:WaitForChild("Props"))
local CampusBuildings = require(script.Parent:WaitForChild("CampusBuildings"))

type BuildContext = PartUtil.BuildContext

local CampusZone = {}

local C = WorldConfig.COLORS

-- Fonctions de construction par identifiant de bâtiment (Campus.Definitions).
CampusZone.BUILDERS = {
	Esport = CampusBuildings.Esport,
	Museum = CampusBuildings.Museum,
	President = CampusBuildings.President,
	Recovery = CampusBuildings.Recovery,
	Champions = CampusBuildings.Champions,
} :: { [string]: (Instance, CFrame, number, BuildContext, any?) -> Model }

local function tierOf(divisionId: string): number
	local division = Divisions.Get(divisionId)
	return if division then division.tier else 7
end

-- CFrame du centre (au sol) d'une parcelle, dans le repère du terrain.
function CampusZone.ParcelCFrame(plotCFrame: CFrame, index: number, rot: number?): CFrame
	local parcel = WorldConfig.PARCELS[index]
	return plotCFrame * CFrame.new(parcel.x, WorldConfig.PLOT_GROUND_TOP, parcel.z) * CFrame.Angles(0, math.rad(rot or 0), 0)
end

local function lockedParcel(parent: Instance, origin: CFrame, index: number)
	local size = WorldConfig.PARCEL_SIZE
	local m = PartUtil.model(parent, "Parcel" .. index, { Parcel = index, State = "locked" })
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(m, origin, "Curb", Vector3.new(size.X, 0.5, 0.6), Vector3.new(0, 0, side * (size.Y / 2 - 0.3)), C.Curb, Enum.Material.Concrete))
		PartUtil.detail(PartUtil.block(m, origin, "Curb", Vector3.new(0.6, 0.5, size.Y - 1.2), Vector3.new(side * (size.X / 2 - 0.3), 0, 0), C.Curb, Enum.Material.Concrete))
	end
	local rule = Campus.Parcels[index]
	PartUtil.block(m, origin, "SignPost", Vector3.new(0.5, 5, 0.5), Vector3.new(0, 0, -size.Y / 2 + 3), PartUtil.TRIM, Enum.Material.Metal)
	local panel = PartUtil.box(m, origin, "ForSale", Vector3.new(9, 3.4, 0.3), Vector3.new(0, 6.6, -size.Y / 2 + 3), PartUtil.TRIM, Enum.Material.Metal)
	local params = { index = index, cost = rule.cost, tier = tierOf(rule.division) }
	PartUtil.label(panel, Enum.NormalId.Front, "world.parcelForSale", C.Gold, nil, params)
	PartUtil.label(panel, Enum.NormalId.Back, "world.parcelForSale", C.Gold, nil, params)
	return m
end

local function freeParcel(parent: Instance, origin: CFrame, index: number)
	local size = WorldConfig.PARCEL_SIZE
	local m = PartUtil.model(parent, "Parcel" .. index, { Parcel = index, State = "free" })
	PartUtil.block(m, origin, "Pad", Vector3.new(size.X - 2, 0.1, size.Y - 2), Vector3.zero, Color3.fromRGB(196, 190, 176), Enum.Material.Pebble, { castShadow = false })
	local panel = PartUtil.box(m, origin, "FreeSign", Vector3.new(8, 2.4, 0.3), Vector3.new(0, 1.6, -size.Y / 2 + 3), PartUtil.TRIM, Enum.Material.Metal)
	PartUtil.label(panel, Enum.NormalId.Front, "world.parcelFree", Color3.new(1, 1, 1), nil, { index = index })
	return m
end

-- Construit la zone de création du terrain. `campus` = data.campus (ou nil pour un terrain libre).
-- `extra` = { trophies, titles } pour le musée, le bureau et la place des champions.
function CampusZone.build(plot: Instance, plotCFrame: CFrame, campus: any?, ctx: BuildContext, extra: any?): Model
	local model = PartUtil.model(plot, "Campus")
	local top = WorldConfig.PLOT_GROUND_TOP
	local back = WorldConfig.PLOT_SIZE.Y / 2
	local depth = WorldConfig.CAMPUS_DEPTH
	local width = WorldConfig.PLOT_SIZE.X
	local ground = plotCFrame * CFrame.new(0, top, 0)

	PartUtil.box(model, plotCFrame, "CampusGround", Vector3.new(width, 0.4, depth), Vector3.new(0, top - 0.2, back + depth / 2), C.PlotGrass, Enum.Material.Grass)
	-- Boulevard côté club, puis allées entre colonnes et entre rangées.
	local boulevard = WorldConfig.CAMPUS_BOULEVARD
	PartUtil.block(model, ground, "Boulevard", Vector3.new(width, 0.08, boulevard), Vector3.new(0, 0, back + boulevard / 2), C.Path, Enum.Material.Pavement, { castShadow = false })
	for _, x in { -62, 0, 62 } do
		PartUtil.block(model, ground, "Alley", Vector3.new(6, 0.08, depth - boulevard), Vector3.new(x, 0, back + boulevard + (depth - boulevard) / 2), C.Path, Enum.Material.Pavement, {
			castShadow = false,
		})
	end
	local parcelD = WorldConfig.PARCEL_SIZE.Y
	for row = 1, 2 do
		local z = back + boulevard + row * parcelD + (row - 0.5) * 6
		PartUtil.block(model, ground, "Alley", Vector3.new(width, 0.08, 6), Vector3.new(0, 0, z), C.Path, Enum.Material.Pavement, { castShadow = false })
	end
	-- Lampadaires le long du boulevard.
	for _, x in { -124, -62, 62, 124 } do
		Props.lamp(model, ground, x + (if x > 0 then -3 else 3), back + boulevard - 1, 180)
	end

	local data = if type(campus) == "table" then campus else Campus.Default()
	for index in WorldConfig.PARCELS do
		local origin = CampusZone.ParcelCFrame(plotCFrame, index)
		local id = Campus.BuildingOn(data, index)
		if id and Campus.HasParcel(data, index) and CampusZone.BUILDERS[id] then
			local entry = data.placed[id]
			local m = PartUtil.model(model, "Parcel" .. index, { Parcel = index, State = "built" })
			local building = CampusZone.BUILDERS[id](m, CampusZone.ParcelCFrame(plotCFrame, index, entry.rot), entry.level, ctx, extra)
			building:SetAttribute("CampusBuilding", id)
			building:SetAttribute("Level", entry.level)
			building:SetAttribute("Rotation", entry.rot)
		elseif Campus.HasParcel(data, index) then
			freeParcel(model, origin, index)
		else
			lockedParcel(model, origin, index)
		end
	end
	return model
end

return CampusZone
