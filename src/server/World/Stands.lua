--!strict
--[[
	Stands — tribunes autour du terrain principal.

	Niveau 1 : petit gradin en bois sur un côté (côté opposé à l'entrée).
	Niveau 2 : tribunes en béton sur les deux grands côtés, sièges colorés.
	Niveau 3 : tribunes sur les 4 côtés ; grands côtés plus hauts et couverts d'un toit.
	Niveau 4 : les 4 tribunes sont couvertes, virages plus hauts, loges vitrées en tribune nord.
	Niveau 5 : grand stade : tribunes plus hautes partout, loges VIP sur les deux grands côtés.

	La capacité de chaque niveau est définie dans WorldConfig.STANDS_CAPACITY et
	recopiée dans l'attribut « Capacity » du Model.

	L'origine reçue est le centre du terrain (le même que Pitch).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Stands = {}

local C = WorldConfig.COLORS
local ROW_D = WorldConfig.STAND_ROW_DEPTH
local ROW_H = WorldConfig.STAND_ROW_RISE

type StandSpec = {
	length: number,
	rows: number,
	segments: number, -- nombre de blocs de sièges séparés par des escaliers
	roof: boolean,
	vip: boolean?, -- loges vitrées en haut de la tribune
}

-- Repère d'une tribune : X = longueur, +Z = vers l'arrière (on monte en s'éloignant du terrain).
-- `side` : "North" (+Z), "South" (-Z, côté entrée), "East" (+X), "West" (-X).
local function standFrame(origin: CFrame, side: string): CFrame
	local hx = WorldConfig.PITCH_SIZE.X / 2 + WorldConfig.PITCH_RUNOFF
	local hz = WorldConfig.PITCH_SIZE.Y / 2 + WorldConfig.PITCH_RUNOFF
	if side == "North" then
		return origin * CFrame.new(0, 0, hz)
	elseif side == "South" then
		return origin * CFrame.new(0, 0, -hz) * CFrame.Angles(0, math.pi, 0)
	elseif side == "East" then
		return origin * CFrame.new(hx, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	else
		return origin * CFrame.new(-hx, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	end
end

-- Tribune en béton : gradins pleins + rangées de sièges (+ toit éventuel).
local function concreteStand(parent: Instance, frame: CFrame, name: string, spec: StandSpec, ctx: BuildContext)
	local stand = PartUtil.model(parent, name)
	local aisle = 2
	local segLength = (spec.length - aisle * (spec.segments - 1)) / spec.segments

	for row = 0, spec.rows - 1 do
		local topY = (row + 1) * ROW_H
		local z = (row + 0.5) * ROW_D
		-- Gradin : bloc plein du sol jusqu'au dessus du rang.
		PartUtil.block(
			stand,
			frame,
			"Tier",
			Vector3.new(spec.length, topY, ROW_D),
			Vector3.new(0, 0, z),
			if row % 2 == 0 then C.Concrete else C.ConcreteDark,
			Enum.Material.Concrete
		)
		-- Sièges : un rang sur trois à la couleur secondaire pour un motif « supporters ».
		local seatColor = if row % 3 == 2 then ctx.secondary else ctx.primary
		for s = 0, spec.segments - 1 do
			local x = -spec.length / 2 + segLength / 2 + s * (segLength + aisle)
			PartUtil.block(
				stand,
				frame,
				"Seat",
				Vector3.new(segLength, 0.6, 1),
				Vector3.new(x, topY, z - 0.3),
				seatColor,
				Enum.Material.SmoothPlastic
			)
			PartUtil.block(
				stand,
				frame,
				"SeatBack",
				Vector3.new(segLength, 1.2, 0.2),
				Vector3.new(x, topY, z + 0.3),
				seatColor,
				Enum.Material.SmoothPlastic
			)
		end
	end

	if spec.vip then
		-- Rangée de loges vitrées posée sur les derniers rangs, bandeau aux couleurs du club.
		local depth = spec.rows * ROW_D
		local topY = spec.rows * ROW_H
		local vipLength = spec.length * 0.6
		PartUtil.block(
			stand,
			frame,
			"VipBox",
			Vector3.new(vipLength, 4, 3),
			Vector3.new(0, topY, depth - 1.5),
			C.Glass,
			Enum.Material.Glass,
			{ transparency = 0.3 }
		)
		PartUtil.block(
			stand,
			frame,
			"VipBand",
			Vector3.new(vipLength + 0.4, 0.8, 3.2),
			Vector3.new(0, topY + 4, depth - 1.5),
			ctx.secondary,
			Enum.Material.SmoothPlastic
		)
	end

	if spec.roof then
		local depth = spec.rows * ROW_D
		local topY = spec.rows * ROW_H
		local roofY = topY + 9
		local columns = 5
		for i = 0, columns - 1 do
			local x = -spec.length / 2 + 2 + i * (spec.length - 4) / (columns - 1)
			PartUtil.block(
				stand,
				frame,
				"RoofColumn",
				Vector3.new(1, roofY, 1),
				Vector3.new(x, 0, depth + 0.5),
				C.Metal,
				Enum.Material.Metal
			)
		end
		-- Toit légèrement incliné vers le terrain, débordant au-dessus des premiers rangs.
		PartUtil.box(
			stand,
			frame,
			"Roof",
			Vector3.new(spec.length + 2, 0.6, depth + 3),
			Vector3.new(0, roofY + 0.3, depth / 2 - 0.5),
			C.Roof,
			Enum.Material.Metal,
			{ rotX = -4 }
		)
		PartUtil.box(
			stand,
			frame,
			"RoofFascia",
			Vector3.new(spec.length + 2, 1.4, 0.4),
			Vector3.new(0, roofY - 0.4, -2),
			ctx.primary,
			Enum.Material.SmoothPlastic
		)
	end
	return stand
end

-- Gradin en bois sur pieds (niveau 1).
local function woodenBleacher(parent: Instance, frame: CFrame, length: number, rows: number)
	local stand = PartUtil.model(parent, "Bleacher")
	for row = 0, rows - 1 do
		local y = (row + 1) * ROW_H
		local z = (row + 0.5) * ROW_D
		PartUtil.block(stand, frame, "Plank", Vector3.new(length, 0.4, 1.4), Vector3.new(0, y - 0.4, z - 0.3), C.Wood, Enum.Material.WoodPlanks)
		PartUtil.block(stand, frame, "FootBoard", Vector3.new(length, 0.3, 0.9), Vector3.new(0, y - ROW_H + 0.2, z + 0.6 - ROW_D / 2), C.WoodDark, Enum.Material.WoodPlanks)
	end
	-- Supports triangulaires (WedgePart : face haute à l'arrière, pente vers le terrain).
	local depth = rows * ROW_D
	local height = rows * ROW_H - 0.4
	for _, x in { -length / 2 + 0.5, 0, length / 2 - 0.5 } do
		PartUtil.block(
			stand,
			frame,
			"Support",
			Vector3.new(0.6, height, depth),
			Vector3.new(x, 0, depth / 2),
			C.WoodDark,
			Enum.Material.WoodPlanks,
			{ className = "WedgePart" }
		)
	end
	-- Rambarde arrière.
	PartUtil.block(stand, frame, "Rail", Vector3.new(length, 0.3, 0.3), Vector3.new(0, rows * ROW_H + 2.5, depth - 0.2), C.WoodDark, Enum.Material.WoodPlanks)
	for _, x in { -length / 2 + 0.2, length / 2 - 0.2 } do
		PartUtil.block(stand, frame, "RailPost", Vector3.new(0.3, 2.8, 0.3), Vector3.new(x, rows * ROW_H - 0.4, depth - 0.2), C.WoodDark, Enum.Material.WoodPlanks)
	end
end

-- Construit les tribunes au niveau demandé et renvoie leur Model.
function Stands.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Stands", {
		Facility = "Stands",
		Level = level,
		Capacity = WorldConfig.STANDS_CAPACITY[level] or 0,
	})
	PartUtil.anchor(model, origin, WorldConfig.LAYOUT.Stands.footprint, 1)

	local L = WorldConfig.PITCH_SIZE.X
	local W = WorldConfig.PITCH_SIZE.Y

	if level <= 1 then
		woodenBleacher(model, standFrame(origin, "North"), 40, 4)
	elseif level == 2 then
		local spec: StandSpec = { length = 90, rows = 6, segments = 4, roof = false }
		concreteStand(model, standFrame(origin, "North"), "StandNorth", spec, ctx)
		concreteStand(model, standFrame(origin, "South"), "StandSouth", spec, ctx)
	else
		-- Les grands côtés font exactement la longueur du terrain : les angles restent
		-- libres pour les pylônes d'éclairage et les écrans géants du terrain.
		local long: StandSpec, short: StandSpec
		local northVip, southVip = false, false
		if level == 3 then
			long = { length = L, rows = 8, segments = 4, roof = true }
			short = { length = W, rows = 6, segments = 3, roof = false }
		elseif level == 4 then
			long = { length = L, rows = 9, segments = 4, roof = true }
			short = { length = W, rows = 7, segments = 3, roof = true }
			northVip = true
		else
			-- Moins de blocs de sièges par rang pour rester dans le budget mobile.
			long = { length = L, rows = 10, segments = 3, roof = true }
			short = { length = W, rows = 8, segments = 2, roof = true }
			northVip, southVip = true, true
		end
		local north = table.clone(long)
		north.vip = northVip
		local south = table.clone(long)
		south.vip = southVip
		concreteStand(model, standFrame(origin, "North"), "StandNorth", north, ctx)
		concreteStand(model, standFrame(origin, "South"), "StandSouth", south, ctx)
		concreteStand(model, standFrame(origin, "East"), "StandEast", short, ctx)
		concreteStand(model, standFrame(origin, "West"), "StandWest", short, ctx)
	end
	return model
end

return Stands
