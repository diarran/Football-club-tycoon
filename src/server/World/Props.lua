--!strict
--[[
	Props — mobilier urbain et végétation « semi-réalistes », partagés par le
	quartier (District) et les terrains de club (Landscape).

	Chaque fonction prend un CFrame d'origine et une position LOCALE (X, Z) au sol,
	comme PartUtil. Les petites pièces sont marquées « détail » (PartUtil.detail) :
	le client peut les masquer de loin ou sur les téléphones peu puissants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

local Props = {}

local C = WorldConfig.COLORS
local LEAVES = {
	Color3.fromRGB(58, 104, 48),
	Color3.fromRGB(72, 120, 56),
	Color3.fromRGB(86, 132, 60),
}

-- Petit générateur déterministe : même terrain = mêmes arbres à chaque construction.
local function hash(x: number, z: number): number
	local v = math.sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - math.floor(v)
end

-- Arbre feuillu : tronc + houppier en trois boules de verts différents.
function Props.tree(parent: Instance, origin: CFrame, x: number, z: number, scale: number?)
	local r = hash(x, z)
	local s = (scale or 1) * (0.85 + r * 0.35)
	local m = PartUtil.model(parent, "Tree")
	PartUtil.cylinder(m, origin, "Trunk", 1 * s, 7 * s, Vector3.new(x, 0, z), C.WoodDark, Enum.Material.Wood)
	local green = LEAVES[1 + math.floor(r * 3) % 3]
	PartUtil.ball(m, origin, "Leaves", 7.5 * s, Vector3.new(x, 9 * s, z), green, Enum.Material.LeafyGrass)
	PartUtil.ball(m, origin, "Leaves", 5.5 * s, Vector3.new(x + 2.2 * s, 7.6 * s, z + 1.2 * s), LEAVES[1 + (math.floor(r * 3) + 1) % 3], Enum.Material.LeafyGrass)
	PartUtil.detail(PartUtil.ball(m, origin, "Leaves", 5 * s, Vector3.new(x - 1.8 * s, 8 * s, z - 1.6 * s), LEAVES[1 + (math.floor(r * 3) + 2) % 3], Enum.Material.LeafyGrass))
	return m
end

-- Conifère (cône de trois disques) : varie la silhouette des rangées d'arbres.
function Props.conifer(parent: Instance, origin: CFrame, x: number, z: number, scale: number?)
	local s = (scale or 1) * (0.9 + hash(z, x) * 0.3)
	local m = PartUtil.model(parent, "Tree")
	PartUtil.cylinder(m, origin, "Trunk", 0.8 * s, 3 * s, Vector3.new(x, 0, z), C.WoodDark, Enum.Material.Wood)
	for i, d in { 6, 4.4, 2.6 } do
		local part = PartUtil.cylinder(m, origin, "Leaves", d * s, 3.4 * s, Vector3.new(x, (1.6 + i * 2.6) * s, z), Color3.fromRGB(46, 86, 50), Enum.Material.LeafyGrass)
		if i == 3 then
			PartUtil.detail(part)
		end
	end
	return m
end

-- Lampadaire moderne : mât anthracite, bras et tête LED (lumière la nuit).
function Props.lamp(parent: Instance, origin: CFrame, x: number, z: number, rotY: number?)
	local m = PartUtil.model(parent, "StreetLamp")
	local o = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	PartUtil.cylinder(m, o, "Pole", 0.45, 11, Vector3.new(0, 0.2, 0), PartUtil.TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(m, o, "Arm", Vector3.new(0.3, 0.3, 3), Vector3.new(0, 11, 1.3), PartUtil.TRIM, Enum.Material.Metal, { canCollide = false }))
	local head = PartUtil.block(m, o, "Lamp", Vector3.new(1.2, 0.25, 1.8), Vector3.new(0, 10.85, 2.6), PartUtil.WARM_LIGHT, Enum.Material.Neon, { canCollide = false })
	head.CastShadow = false
	local light = Instance.new("SpotLight")
	light.Name = "LampLight"
	light.Face = Enum.NormalId.Bottom
	light.Range = 22
	light.Angle = 100
	light.Brightness = 1.2
	light.Color = PartUtil.WARM_LIGHT
	light.Parent = head
	return m
end

-- Banc : assise et dossier en lattes de bois sur deux pieds en métal.
function Props.bench(parent: Instance, origin: CFrame, x: number, z: number, rotY: number?)
	local m = PartUtil.model(parent, "Bench")
	local o = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	PartUtil.block(m, o, "Seat", Vector3.new(5, 0.3, 1.5), Vector3.new(0, 1.4, 0), C.Wood, Enum.Material.WoodPlanks)
	PartUtil.detail(PartUtil.block(m, o, "Back", Vector3.new(5, 1.1, 0.2), Vector3.new(0, 1.9, 0.7), C.Wood, Enum.Material.WoodPlanks))
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(m, o, "Leg", Vector3.new(0.25, 1.4, 1.4), Vector3.new(side * 2.1, 0, 0), PartUtil.TRIM, Enum.Material.Metal))
	end
	return m
end

-- Jardinière en béton avec arbuste.
function Props.planter(parent: Instance, origin: CFrame, x: number, z: number)
	local m = PartUtil.model(parent, "Planter")
	PartUtil.block(m, origin, "Box", Vector3.new(3, 1.4, 3), Vector3.new(x, 0, z), Color3.fromRGB(150, 150, 148), Enum.Material.Concrete)
	PartUtil.detail(PartUtil.ball(m, origin, "Shrub", 3, Vector3.new(x, 2.4, z), LEAVES[2], Enum.Material.LeafyGrass))
	return m
end

-- Haie taillée (une seule Part, aussi longue que voulu).
function Props.hedge(parent: Instance, origin: CFrame, from: Vector2, to: Vector2, height: number?)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	local yaw = math.deg(math.atan2(-delta.Y, delta.X))
	return PartUtil.block(parent, origin, "Hedge", Vector3.new(length, height or 2.4, 2), Vector3.new(mid.X, 0, mid.Y), LEAVES[1], Enum.Material.LeafyGrass, {
		rotY = yaw,
	})
end

-- Mât et drapeau aux couleurs du club.
function Props.flag(parent: Instance, origin: CFrame, x: number, z: number, color: Color3, rotY: number?)
	local m = PartUtil.model(parent, "Flag")
	local o = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	PartUtil.cylinder(m, o, "FlagPole", 0.3, 14, Vector3.zero, Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(m, o, "Cloth", Vector3.new(4, 2.6, 0.08), Vector3.new(2.15, 10.8, 0), color, Enum.Material.Fabric, { canCollide = false }))
	return m
end

-- Voiture stationnée (berline simple) : caisse, habitacle vitré, 4 roues.
function Props.car(parent: Instance, origin: CFrame, x: number, z: number, rotY: number, color: Color3)
	local m = PartUtil.model(parent, "Car")
	local o = origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rotY), 0)
	PartUtil.block(m, o, "Body", Vector3.new(4.4, 1.6, 9), Vector3.new(0, 0.7, 0), color, Enum.Material.SmoothPlastic)
	PartUtil.block(m, o, "Cabin", Vector3.new(4, 1.4, 4.8), Vector3.new(0, 2.3, 0.4), Color3.fromRGB(30, 36, 44), Enum.Material.Glass, { transparency = 0.1, reflectance = 0.2 })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartUtil.detail(PartUtil.box(m, o, "Wheel", Vector3.new(0.7, 1.7, 1.7), Vector3.new(sx * 2.05, 0.85, sz * 2.9), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber, {
				shape = Enum.PartType.Cylinder,
			}))
		end
	end
	PartUtil.detail(PartUtil.block(m, o, "Lights", Vector3.new(3.6, 0.35, 0.1), Vector3.new(0, 1.6, -4.52), PartUtil.WARM_LIGHT, Enum.Material.Neon, { canCollide = false }))
	return m
end

-- Parking : enrobé, bordures, places marquées et quelques voitures.
-- `size` = (largeur X, profondeur Z) ; les places sont alignées le long de X.
function Props.parking(parent: Instance, origin: CFrame, center: Vector2, size: Vector2, cars: { Color3 })
	local m = PartUtil.model(parent, "Parking")
	PartUtil.block(m, origin, "Asphalt", Vector3.new(size.X, 0.12, size.Y), Vector3.new(center.X, 0, center.Y), C.Asphalt, Enum.Material.Asphalt, { castShadow = false })
	local bays = math.floor(size.X / 6)
	local row = size.Y / 2 - 5
	for i = 0, bays do
		local bx = center.X - size.X / 2 + 1 + i * (size.X - 2) / bays
		for _, side in { -1, 1 } do
			PartUtil.detail(PartUtil.block(m, origin, "BayLine", Vector3.new(0.25, 0.04, 9), Vector3.new(bx, 0.12, center.Y + side * row), C.Line, Enum.Material.SmoothPlastic, {
				canCollide = false,
			}))
		end
	end
	for i, color in cars do
		local slot = (i - 1) * 2 % bays
		local side = if i % 2 == 0 then 1 else -1
		local cx = center.X - size.X / 2 + 1 + (slot + 0.5) * (size.X - 2) / bays
		Props.car(m, origin, cx, center.Y + side * row, if side > 0 then 0 else 180, color)
	end
	return m
end

return Props
