--!strict
--[[
	Downtown — construit le centre-ville commerçant, une seule fois par serveur.

	Contenu : sol pavé, boulevard est-ouest dans le prolongement de la route du
	quartier, boulevard nord-sud, rond-point monumental avec ballon géant,
	deux carrefours avec feux tricolores et passages piétons, trottoirs,
	terre-pleins plantés, lampadaires, puis les bâtiments (CityBuildings).

	Les feux sont des Parts « Signal » (attribut SignalAxis = "main" ou "cross",
	SignalColor = "red" / "yellow" / "green") : c'est le client
	(TrafficController) qui les allume selon l'heure du serveur, sans réseau.
	Les petites pièces sont des « détails » (masquables sur téléphone).

	Plan et règles : ReplicatedStorage.Shared.City.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("City"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local World = script.Parent
local PartUtil = require(World:WaitForChild("PartUtil"))
local Props = require(World:WaitForChild("Props"))
local CityBuildings = require(World:WaitForChild("CityBuildings"))

local Downtown = {}

local C = WorldConfig.COLORS
local TRIM = PartUtil.TRIM
local PAVING = Color3.fromRGB(150, 148, 144)
local SIDEWALK = Color3.fromRGB(196, 192, 184)
local LANE_LINE = Color3.fromRGB(236, 236, 236)

local HALF_X = CityConfig.SIZE.X / 2
local HALF_Z = CityConfig.SIZE.Y / 2
local ROAD = CityConfig.BOULEVARD
local WALK = CityConfig.SIDEWALK
local RING = CityConfig.RING
local CROSS_X = CityConfig.CROSS_X
local CROSS_W = CityConfig.CROSS_WIDTH

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function asphalt(parent: Instance, origin: CFrame, size: Vector2, center: Vector2)
	return PartUtil.block(parent, origin, "Road", v(size.X, 0.15, size.Y), v(center.X, 0, center.Y), C.Asphalt, Enum.Material.Asphalt, {
		castShadow = false,
	})
end

local function sidewalk(parent: Instance, origin: CFrame, size: Vector2, center: Vector2)
	PartUtil.block(parent, origin, "Sidewalk", v(size.X, 0.3, size.Y), v(center.X, 0, center.Y), SIDEWALK, Enum.Material.Concrete, {
		castShadow = false,
	})
end

-- Pointillés le long de X (de x1 à x2) en z, ou le long de Z si alongZ.
local function dashes(parent: Instance, origin: CFrame, from: number, to: number, at: number, alongZ: boolean)
	local dash, gap = 7, 9
	local p = math.min(from, to) + 3
	local stop = math.max(from, to) - 3
	while p + dash <= stop do
		local center = p + dash / 2
		local size = if alongZ then v(0.45, 0.04, dash) else v(dash, 0.04, 0.45)
		local pos = if alongZ then v(at, 0.15, center) else v(center, 0.15, at)
		PartUtil.detail(PartUtil.block(parent, origin, "LaneMarking", size, pos, LANE_LINE, Enum.Material.SmoothPlastic, { canCollide = false }))
		p += dash + gap
	end
end

-- Passage piéton : bandes blanches en travers de la chaussée.
-- Bandes le long de X (on traverse selon Z) si acrossZ, sinon l'inverse.
local function crosswalk(parent: Instance, origin: CFrame, center: Vector2, width: number, acrossZ: boolean)
	local m = PartUtil.model(parent, "Crosswalk")
	local stripes = math.floor(width / 4)
	for i = 0, stripes - 1 do
		local offset = -width / 2 + 2 + i * 4
		local size = if acrossZ then v(5, 0.04, 2) else v(2, 0.04, 5)
		local pos = if acrossZ then v(center.X, 0.15, center.Y + offset) else v(center.X + offset, 0.15, center.Y)
		PartUtil.block(m, origin, "Stripe", size, pos, LANE_LINE, Enum.Material.SmoothPlastic, { canCollide = false, castShadow = false })
	end
	return m
end

-- Feu tricolore : mât, bras au-dessus de la chaussée, boîtier et 3 feux.
-- `axis` = route que ce feu règle ("main" = boulevard, "cross" = rue transversale).
-- `facing` = direction (degrés autour de Y) vers laquelle regardent les feux.
local function trafficLight(parent: Instance, origin: CFrame, x: number, z: number, facing: number, axis: string, arm: number)
	local m = PartUtil.model(parent, "TrafficLight", { SignalAxis = axis })
	local o = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(facing), 0)
	PartUtil.cylinder(m, o, "Pole", 0.6, 13, v(0, 0.3, 0), TRIM, Enum.Material.Metal)
	-- Bras au-dessus de la route (vers la droite du feu, côté chaussée).
	PartUtil.block(m, o, "Arm", v(arm, 0.4, 0.4), v(-arm / 2, 12.4, 0), TRIM, Enum.Material.Metal, { canCollide = false })
	local hx = -arm + 1.2
	PartUtil.block(m, o, "Housing", v(1.4, 4.2, 1), v(hx, 8.4, 0), Color3.fromRGB(26, 28, 32), Enum.Material.Metal, { canCollide = false })
	for i, color in { "red", "yellow", "green" } do
		local lamp = PartUtil.box(m, o, "Signal", v(0.9, 0.9, 0.2), v(hx, 12 - i * 1.2, -0.55), Color3.fromRGB(40, 40, 40), Enum.Material.SmoothPlastic, {
			canCollide = false,
			castShadow = false,
			shape = Enum.PartType.Block,
		})
		lamp:SetAttribute("SignalAxis", axis)
		lamp:SetAttribute("SignalColor", color)
	end
	-- Bouton piéton sur le mât (détail).
	PartUtil.detail(PartUtil.block(m, o, "PedButton", v(0.5, 0.8, 0.4), v(0, 3.6, -0.45), Color3.fromRGB(212, 175, 55), Enum.Material.Metal, { canCollide = false }))
	return m
end

-- Ballon géant du rond-point : sphère blanche, taches noires, socle noir et or.
local function giantBall(parent: Instance, origin: CFrame)
	local m = PartUtil.model(parent, "GiantBall")
	local island = CityConfig.ISLAND
	PartUtil.cylinder(m, origin, "Island", island * 2, 0.9, v(0, 0, 0), Color3.fromRGB(78, 126, 60), Enum.Material.Grass)
	PartUtil.cylinder(m, origin, "IslandCurb", island * 2 + 1.6, 0.6, v(0, 0, 0), C.Curb, Enum.Material.Concrete)
	PartUtil.cylinder(m, origin, "Plinth", 18, 4, v(0, 0.9, 0), Color3.fromRGB(30, 31, 35), Enum.Material.Granite)
	PartUtil.cylinder(m, origin, "PlinthTrim", 18.6, 0.5, v(0, 4.9, 0), C.Gold, Enum.Material.Metal)
	local d = 22
	local cy = 5.4 + d / 2
	PartUtil.ball(m, origin, "Ball", d, v(0, cy, 0), Color3.fromRGB(244, 244, 240), Enum.Material.SmoothPlastic)
	-- 12 taches (icosaèdre approché) légèrement enfoncées dans la sphère.
	local r = d / 2 - 2.5 -- taches enfoncées : elles ne dépassent que de 0,3 stud
	local patches = {
		v(0, 1, 0), v(0, -1, 0),
	}
	for i = 0, 4 do
		local a = math.rad(i * 72)
		table.insert(patches, v(math.cos(a) * 0.894, 0.447, math.sin(a) * 0.894))
		local b = math.rad(i * 72 + 36)
		table.insert(patches, v(math.cos(b) * 0.894, -0.447, math.sin(b) * 0.894))
	end
	for _, dir in patches do
		if dir.Y > -0.9 then -- la tache du dessous est cachée par le socle
			PartUtil.ball(m, origin, "Patch", 5.6, v(0, cy, 0) + dir * r, Color3.fromRGB(24, 24, 26), Enum.Material.SmoothPlastic)
		end
	end
	-- Projecteurs au pied du ballon (lumière la nuit).
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local spot = PartUtil.block(m, origin, "Uplight", v(1.2, 0.8, 1.2), v(math.cos(a) * 10.5, 0.9, math.sin(a) * 10.5), PartUtil.WARM_LIGHT, Enum.Material.Neon, {
			canCollide = false,
			castShadow = false,
		})
		if i % 2 == 0 then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Top
			light.Range = 30
			light.Angle = 60
			light.Brightness = 2
			light.Color = PartUtil.WARM_LIGHT
			light.Parent = spot
		end
	end
	for _, a in { 30, 150, 270 } do
		local rad = math.rad(a)
		Props.planter(m, origin, math.cos(rad) * 19, math.sin(rad) * 19)
	end
	return m
end

-- Terre-plein central planté (le long de X ou de Z).
local function median(parent: Instance, origin: CFrame, from: number, to: number, alongZ: boolean)
	local length = math.abs(to - from)
	local mid = (from + to) / 2
	local size = if alongZ then v(CityConfig.MEDIAN, 0.5, length) else v(length, 0.5, CityConfig.MEDIAN)
	local pos = if alongZ then v(0, 0, mid) else v(mid, 0, 0)
	PartUtil.block(parent, origin, "Median", size, pos, Color3.fromRGB(84, 128, 62), Enum.Material.Grass, { castShadow = false })
	local n = math.floor(length / 36)
	for i = 1, n do
		local t = math.min(from, to) + (i - 0.5) * length / n
		local x, z = if alongZ then 0 else t, if alongZ then t else 0
		if i % 2 == 0 then
			Props.lamp(parent, origin, x, z, if alongZ then 90 else 0)
		else
			Props.planter(parent, origin, x, z)
		end
	end
end

-- Construit tout le centre-ville sous `parent` et renvoie son Model.
function Downtown.build(parent: Instance): Model
	local existing = parent:FindFirstChild(CityConfig.NAME)
	if existing and existing:IsA("Model") then
		return existing
	end
	local model = PartUtil.model(nil, CityConfig.NAME, { Facility = "City" })
	local origin = CFrame.new(CityConfig.ORIGIN)

	local ground = PartUtil.box(model, origin, "Ground", v(CityConfig.SIZE.X, 2, CityConfig.SIZE.Y), v(0, -0.95, 0), PAVING, Enum.Material.Pavement)
	model.PrimaryPart = ground

	local roads = PartUtil.model(model, "Roads")
	-- Boulevard est-ouest (coupé par le rond-point) et nord-sud.
	local ewLength = HALF_X - RING + 2
	local nsLength = HALF_Z - RING + 2
	for _, side in { -1, 1 } do
		asphalt(roads, origin, Vector2.new(ewLength, ROAD), Vector2.new(side * (RING - 2 + ewLength / 2), 0))
		asphalt(roads, origin, Vector2.new(ROAD, nsLength), Vector2.new(0, side * (RING - 2 + nsLength / 2)))
		median(roads, origin, side * (RING + 8), side * (HALF_X - 6), false)
		median(roads, origin, side * (RING + 8), side * (HALF_Z - 6), true)
		-- Lignes entre les voies (pointillés) des deux côtés du terre-plein.
		for _, lane in { -1, 1 } do
			local at = lane * (CityConfig.MEDIAN / 2 + CityConfig.LANE)
			dashes(roads, origin, side * (RING + 4), side * (HALF_X - 2), at, false)
			dashes(roads, origin, side * (RING + 4), side * (HALF_Z - 2), at, true)
		end
	end
	-- Raccord avec la route centrale du quartier (bord ouest).
	asphalt(roads, origin, Vector2.new(8, ROAD), Vector2.new(-HALF_X - 4, 0))

	-- Rond-point : anneau de chaussée, îlot avec le ballon géant.
	local ring = PartUtil.cylinder(roads, origin, "Roundabout", RING * 2, 0.15, v(0, 0.01, 0), C.Asphalt, Enum.Material.Asphalt)
	ring.CastShadow = false
	PartUtil.arc(roads, origin, "RingMarking", Vector2.zero, (CityConfig.ISLAND + RING) / 2, 0, 360, 24, 0.4, 0.17, LANE_LINE)
	giantBall(model, origin)

	-- Rues transversales avec feux, en x = ±CROSS_X.
	local crossLength = HALF_Z - ROAD / 2
	for _, sx in { -1, 1 } do
		local x = sx * CROSS_X
		for _, sz in { -1, 1 } do
			asphalt(roads, origin, Vector2.new(CROSS_W, crossLength), Vector2.new(x, sz * (ROAD / 2 + crossLength / 2)))
			dashes(roads, origin, sz * (ROAD / 2 + WALK), sz * HALF_Z, x, true)
			-- Passage piéton de la rue transversale, au ras du boulevard.
			crosswalk(roads, origin, Vector2.new(x, sz * (ROAD / 2 + WALK / 2)), CROSS_W, false)
		end
		-- Passages piétons du boulevard, de chaque côté du carrefour.
		for _, side in { -1, 1 } do
			crosswalk(roads, origin, Vector2.new(x + side * (CROSS_W / 2 + 4), 0), ROAD, true)
		end
		-- Feux : deux pour le boulevard (un par sens), deux pour la rue.
		local cx, cz = CROSS_W / 2 + 2, ROAD / 2 + 2
		trafficLight(roads, origin, x - cx, cz, 90, "main", 14) -- vers l'est : regarde l'ouest
		trafficLight(roads, origin, x + cx, -cz, -90, "main", 14)
		trafficLight(roads, origin, x + cx, cz, 0, "cross", 9)
		trafficLight(roads, origin, x - cx, -cz, 180, "cross", 9)
	end
	-- Passages piétons aux entrées du rond-point.
	for _, side in { -1, 1 } do
		crosswalk(roads, origin, Vector2.new(side * (RING + 6), 0), ROAD, true)
		crosswalk(roads, origin, Vector2.new(0, side * (RING + 6)), ROAD, false)
	end

	-- Trottoirs : le long du boulevard (coupés par les rues) et du boulevard nord-sud.
	local walks = PartUtil.model(model, "Sidewalks")
	for _, sz in { -1, 1 } do
		local z = sz * (ROAD / 2 + WALK / 2)
		for _, sx in { -1, 1 } do
			local outer = { sx * HALF_X, sx * (CROSS_X + CROSS_W / 2) }
			local inner = { sx * (CROSS_X - CROSS_W / 2), sx * (RING + 8) }
			for _, seg in { outer, inner } do
				local len = math.abs(seg[1] - seg[2])
				sidewalk(walks, origin, Vector2.new(len, WALK), Vector2.new((seg[1] + seg[2]) / 2, z))
			end
			local x = sx * (ROAD / 2 + WALK / 2)
			local zLen = HALF_Z - RING - 8
			sidewalk(walks, origin, Vector2.new(WALK, zLen), Vector2.new(x, sz * (RING + 8 + zLen / 2)))
		end
		-- Lampadaires côté trottoir (un sur deux côtés pour limiter les lumières).
		for _, x in { -290, -100, 100, 290 } do
			Props.lamp(walks, origin, x, sz * (ROAD / 2 + WALK - 1.5), if sz > 0 then 180 else 0)
		end
	end

	CityBuildings.build(model, origin)

	model.Parent = parent
	return model
end

return Downtown
