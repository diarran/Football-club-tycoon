--!strict
--[[
	CampusFacilities — modèles 3D des bâtiments du mode Création (lot 2) :
	complexe sportif, terrain couvert, centre de sécurité, atelier technique
	et dépôt des véhicules. 3 niveaux chacun (Campus.lua).

	Même repère que CampusBuildings : `origin` = centre de la parcelle au sol,
	déjà tourné ; entrée côté -Z ; tout tient dans WorldConfig.CAMPUS_FOOTPRINT
	(46 × 46 studs). Les petits objets sont marqués « détail » (masquables).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))
local Props = require(script.Parent:WaitForChild("Props"))
local ModelLoader = require(script.Parent:WaitForChild("ModelLoader"))

type BuildContext = PartUtil.BuildContext

local CampusFacilities = {}

local C = WorldConfig.COLORS
local TRIM = PartUtil.TRIM
local CONCRETE = Color3.fromRGB(205, 202, 194)
local TURF = Color3.fromRGB(74, 150, 70)
local WHITE = Color3.fromRGB(240, 240, 236)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function sign(parent: Instance, origin: CFrame, key: string, width: number, pos: Vector3, color: Color3?)
	return PartUtil.frontSign(parent, origin, key, Vector2.new(width, 1.8), pos, color or C.Gold, TRIM)
end

local function slab(parent: Instance, origin: CFrame, size: Vector2, material: Enum.Material?, color: Color3?)
	return PartUtil.block(parent, origin, "Slab", Vector3.new(size.X, 0.2, size.Y), Vector3.zero, color or CONCRETE, material or Enum.Material.Pavement, {
		castShadow = false,
	})
end

-- Petit terrain de foot : pelouse, lignes blanches et deux buts.
local function miniPitch(parent: Instance, origin: CFrame, center: Vector3, size: Vector2, y: number?)
	local m = PartUtil.model(parent, "MiniPitch")
	local h = y or 0.2
	PartUtil.block(m, origin, "Turf", v(size.X, 0.1, size.Y), center + v(0, h, 0), TURF, Enum.Material.Grass, { castShadow = false })
	local line = h + 0.1
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(m, origin, "Line", v(size.X - 1, 0.04, 0.25), center + v(0, line, side * (size.Y / 2 - 0.6)), WHITE, Enum.Material.SmoothPlastic, { canCollide = false }))
		PartUtil.detail(PartUtil.block(m, origin, "Line", v(0.25, 0.04, size.Y - 1), center + v(side * (size.X / 2 - 0.6), line, 0), WHITE, Enum.Material.SmoothPlastic, { canCollide = false }))
		-- But : deux poteaux et une barre.
		local gz = side * (size.Y / 2 - 0.8)
		for _, px in { -2.2, 2.2 } do
			PartUtil.detail(PartUtil.block(m, origin, "GoalPost", v(0.25, 2.6, 0.25), center + v(px, line, gz), WHITE, Enum.Material.Metal))
		end
		PartUtil.detail(PartUtil.block(m, origin, "GoalBar", v(4.65, 0.25, 0.25), center + v(0, line + 2.6, gz), WHITE, Enum.Material.Metal))
	end
	PartUtil.detail(PartUtil.block(m, origin, "Line", v(size.X - 1, 0.04, 0.25), center + v(0, line, 0), WHITE, Enum.Material.SmoothPlastic, { canCollide = false }))
	return m
end

-- Grillage bas autour d'une zone.
local function fence(parent: Instance, origin: CFrame, center: Vector3, size: Vector2, height: number)
	for _, side in { -1, 1 } do
		PartUtil.block(parent, origin, "Fence", v(size.X, height, 0.15), center + v(0, 0, side * size.Y / 2), TRIM, Enum.Material.DiamondPlate, {
			transparency = 0.55,
			castShadow = false,
		})
		PartUtil.block(parent, origin, "Fence", v(0.15, height, size.Y), center + v(side * size.X / 2, 0, 0), TRIM, Enum.Material.DiamondPlate, {
			transparency = 0.55,
			castShadow = false,
		})
	end
end

-- Caméra de surveillance sur un mât.
local function camera(parent: Instance, origin: CFrame, pos: Vector3, rotY: number)
	local o = origin * CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0)
	PartUtil.detail(PartUtil.block(parent, o, "CameraPole", v(0.3, 5, 0.3), Vector3.zero, TRIM, Enum.Material.Metal))
	PartUtil.detail(PartUtil.block(parent, o, "Camera", v(0.7, 0.6, 1.4), v(0, 4.8, -0.5), WHITE, Enum.Material.Metal, { canCollide = false }))
	PartUtil.detail(PartUtil.block(parent, o, "CameraLed", v(0.2, 0.2, 0.05), v(0.2, 5.15, -1.22), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { canCollide = false }))
end

-- Bus du club aux couleurs du club (posé sur le sol, avant vers -Z).
-- Si le modèle Blender est publié (Shared/Models.lua), on pose le vrai modèle détaillé.
local function bus(parent: Instance, origin: CFrame, x: number, z: number, rotY: number, ctx: BuildContext)
	local o = origin * CFrame.new(x, 0.2, z) * CFrame.Angles(0, math.rad(rotY), 0)
	local mesh = ModelLoader.Place("ClubBus", parent, o, v(5, 6.4, 17))
	if mesh then
		return mesh
	end
	local m = PartUtil.model(parent, "ClubBus")
	PartUtil.block(m, o, "Body", v(5, 5.4, 17), v(0, 0.9, 0), ctx.primary, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(m, o, "Stripe", v(5.05, 0.6, 17.05), v(0, 2.2, 0), ctx.secondary, Enum.Material.Metal, { canCollide = false }))
	for _, side in { -1, 1 } do
		PartUtil.block(m, o, "BusWindows", v(0.1, 1.8, 13.5), v(side * 2.52, 3.7, 1), Color3.fromRGB(28, 34, 42), Enum.Material.Glass, {
			canCollide = false,
			reflectance = 0.2,
		})
		for _, wz in { -5.5, 5.5 } do
			PartUtil.detail(PartUtil.box(m, o, "Wheel", v(0.8, 2, 2), v(side * 2.4, 1, wz), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber, {
				shape = Enum.PartType.Cylinder,
			}))
		end
	end
	PartUtil.block(m, o, "Windshield", v(4.6, 2.6, 0.1), v(0, 3.4, -8.52), Color3.fromRGB(28, 34, 42), Enum.Material.Glass, { canCollide = false, reflectance = 0.2 })
	PartUtil.detail(PartUtil.block(m, o, "Headlights", v(4, 0.4, 0.1), v(0, 1.6, -8.55), PartUtil.WARM_LIGHT, Enum.Material.Neon, { canCollide = false }))
	return m
end

-- Établi avec outils.
local function workbench(parent: Instance, origin: CFrame, pos: Vector3, ctx: BuildContext)
	PartUtil.block(parent, origin, "Workbench", v(5, 2.8, 2), pos, Color3.fromRGB(120, 92, 60), Enum.Material.Wood)
	PartUtil.detail(PartUtil.block(parent, origin, "ToolBoard", v(5, 3, 0.2), pos + v(0, 3.4, 0.9), Color3.fromRGB(70, 74, 82), Enum.Material.Metal, { canCollide = false }))
	PartUtil.detail(PartUtil.block(parent, origin, "ToolChest", v(1.6, 2.4, 1.4), pos + v(3.6, 0, 0), ctx.primary, Enum.Material.Metal))
	for i = -1, 1 do
		PartUtil.detail(PartUtil.block(parent, origin, "Tool", v(0.3, 1.4, 0.1), pos + v(i * 1.4, 4.4, 0.75), Color3.fromRGB(200, 60, 40), Enum.Material.Metal, { canCollide = false }))
	end
end

--------------------------------------------------------------------------------
-- Complexe sportif : terrains d'entraînement grillagés et vestiaire vitré.
--------------------------------------------------------------------------------
function CampusFacilities.SportsComplex(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "SportsComplex")
	slab(model, origin, Vector2.new(46, 46))
	-- Pavillon (vestiaires) côté entrée.
	local pw = 14 + level * 4
	local pavilion = v(pw, 9, 10)
	local po = origin * CFrame.new(0, 0, -15.3)
	PartUtil.shell(model, po, pavilion, {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Metal,
		roofColor = C.Roof,
		windows = true,
		glassFront = true,
		accent = ctx.primary,
		trim = C.Gold,
		doorWidth = 5,
		canopy = true,
	})
	sign(model, po, "campus.SportsComplex.sign", math.min(pw * 0.7, 18), v(0, 0.4 + pavilion.Y - 1.6, -pavilion.Z / 2 - 0.4))
	-- Terrains : 1 grand, puis 2, puis 3 (dont un à 5 avec projecteurs).
	if level == 1 then
		miniPitch(model, origin, v(0, 0, 6), Vector2.new(26, 24))
		fence(model, origin, v(0, 0.2, 6), Vector2.new(28, 26), 3)
	else
		local n = if level >= 3 then 3 else 2
		local width = (44 - (n - 1) * 1.5) / n
		for i = 1, n do
			local x = -22 + width / 2 + (i - 1) * (width + 1.5)
			miniPitch(model, origin, v(x, 0, 7), Vector2.new(width - 1, 26))
			fence(model, origin, v(x, 0.2, 7), Vector2.new(width - 0.4, 28), 3)
		end
	end
	if level >= 3 then
		-- Projecteurs aux quatre coins.
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local base = v(sx * 21.5, 0.2, 7 + sz * 13.5)
				PartUtil.block(model, origin, "FloodMast", v(0.5, 12, 0.5), base, TRIM, Enum.Material.Metal)
				PartUtil.detail(PartUtil.block(model, origin, "Floodlight", v(2.4, 1.2, 0.4), base + v(0, 12, 0), PartUtil.WARM_LIGHT, Enum.Material.Neon, { canCollide = false }))
			end
		end
	end
	-- Bancs le long de l'allée.
	for _, x in { -18, 18 } do
		Props.bench(model, origin, x, -8.6, 0)
	end
	return model
end

--------------------------------------------------------------------------------
-- Terrain couvert : grande halle fermée, toit cintré, pelouse intérieure.
--------------------------------------------------------------------------------
function CampusFacilities.IndoorPitch(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "IndoorPitch")
	local sizes = { v(30, 10, 34), v(36, 12, 38), v(42, 14, 42) }
	local size = sizes[level] or sizes[1]
	slab(model, origin, Vector2.new(size.X + 3, size.Z + 3))
	PartUtil.shell(model, origin, size, {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Metal,
		roofColor = C.Roof,
		windows = false,
		glassFront = true,
		accent = C.Gold,
		trim = C.Gold,
		doorWidth = 8,
		doorHeight = 8,
	})
	-- Toit cintré : arches métalliques et panneaux translucides.
	local top = 0.4 + size.Y
	local arches = 4 + level
	for i = 0, arches - 1 do
		local z = -size.Z / 2 + 1 + i * (size.Z - 2) / (arches - 1)
		for _, side in { -1, 1 } do
			PartUtil.block(model, origin, "RoofArch", v(size.X / 2 + 0.4, 0.5, 0.6), v(side * size.X / 4, top + 1.4, z), C.Gold, Enum.Material.Metal, {
				rotZ = side * -10,
				canCollide = false,
			})
		end
	end
	for _, side in { -1, 1 } do
		PartUtil.block(model, origin, "RoofPanel", v(size.X / 2 + 0.2, 0.2, size.Z), v(side * size.X / 4, top + 1.2, 0), Color3.fromRGB(200, 210, 220), Enum.Material.Glass, {
			rotZ = side * -10,
			transparency = 0.35,
			castShadow = false,
		})
	end
	sign(model, origin, "campus.IndoorPitch.sign", math.min(size.X * 0.6, 20), v(0, top - 1.6, -size.Z / 2 - 0.4))
	-- Pelouse intérieure (synthétique) et bandes LED aux couleurs du club.
	miniPitch(model, origin, v(0, 0.3, 1), Vector2.new(size.X - 4, size.Z - 8))
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(model, origin, "LedBoard", v(0.3, 1, size.Z - 10), v(side * (size.X / 2 - 1.2), 0.5, 1), ctx.primary, Enum.Material.Neon, { canCollide = false }))
	end
	if level >= 2 then
		-- Tribune intérieure le long d'un côté.
		for r = 0, level - 1 do
			PartUtil.block(model, origin, "Bleacher", v(1.6, 0.8 + r * 0.9, size.Z - 12), v(-size.X / 2 + 1.4 + r * 1.6, 0.4, 1), TRIM, Enum.Material.Concrete)
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Centre de sécurité : poste de contrôle, barrière, mur d'écrans, caméras.
--------------------------------------------------------------------------------
function CampusFacilities.Security(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Security")
	local sizes = { v(18, 9, 14), v(24, 10, 16), v(28, 16, 18) }
	local size = sizes[level] or sizes[1]
	slab(model, origin, Vector2.new(46, 46), Enum.Material.Asphalt, C.Asphalt)
	local bo = origin * CFrame.new(0, 0, 6)
	PartUtil.shell(model, bo, size, {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Metal,
		roofColor = C.Roof,
		windows = true,
		glassFront = true,
		accent = Color3.fromRGB(40, 110, 220),
		doorWidth = 4,
		canopy = true,
		floors = if level >= 3 then 2 else nil,
	})
	sign(model, bo, "campus.Security.sign", math.min(size.X * 0.7, 18), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4))
	-- Mur d'écrans de surveillance au fond (2, 4, 6 écrans).
	for i = 1, level * 2 do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		PartUtil.detail(PartUtil.block(model, bo, "MonitorWall", v(2.6, 1.6, 0.15), v(-3 + col * 3, 2.6 + row * 2, size.Z / 2 - 0.8), Color3.fromRGB(80, 200, 140), Enum.Material.Neon, {
			canCollide = false,
		}))
	end
	PartUtil.block(model, bo, "ControlDesk", v(9, 2.6, 2), v(0, 0.4, size.Z / 2 - 4), TRIM, Enum.Material.Metal)
	-- Guérite et barrière levante à l'entrée.
	PartUtil.block(model, origin, "Booth", v(4, 6, 4), v(-14, 0.2, -16), C.Charcoal, Enum.Material.Metal)
	PartUtil.block(model, origin, "BoothGlass", v(4.1, 2.4, 4.1), v(-14, 3, -16), PartUtil.GLASS, Enum.Material.Glass, { transparency = 0.3, castShadow = false })
	PartUtil.block(model, origin, "BoothRoof", v(5, 0.4, 5), v(-14, 6.2, -16), C.Gold, Enum.Material.Metal)
	PartUtil.block(model, origin, "BarrierPost", v(0.8, 3, 0.8), v(-11, 0.2, -16), WHITE, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(model, origin, "Barrier", v(12, 0.4, 0.3), v(-4.6, 2.6, -16), Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic, { canCollide = false }))
	-- Caméras aux angles (2, 4, 6).
	local spots = { v(-21, 0.2, -21), v(21, 0.2, -21), v(-21, 0.2, 21), v(21, 0.2, 21), v(21, 0.2, 0), v(-21, 0.2, 0) }
	for i = 1, level * 2 do
		camera(model, origin, spots[i], if spots[i].Z < 0 then 0 else 180)
	end
	if level >= 2 then
		Props.car(model, origin, 14, -14, 0, Color3.fromRGB(30, 34, 40))
	end
	if level >= 3 then
		-- Antenne radio sur le toit.
		PartUtil.cylinder(model, bo, "Antenna", 0.4, 7, v(size.X / 2 - 3, 0.4 + size.Y, 0), TRIM, Enum.Material.Metal)
	end
	return model
end

--------------------------------------------------------------------------------
-- Atelier technique : garage à portes sectionnelles, établis, outils, chariot.
--------------------------------------------------------------------------------
function CampusFacilities.Workshop(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Workshop")
	local sizes = { v(24, 10, 20), v(30, 11, 24), v(38, 13, 28) }
	local size = sizes[level] or sizes[1]
	slab(model, origin, Vector2.new(size.X + 6, size.Z + 12), Enum.Material.Concrete)
	PartUtil.shell(model, origin, size, {
		wallColor = Color3.fromRGB(84, 88, 96),
		wallMaterial = Enum.Material.CorrodedMetal,
		roofColor = C.Roof,
		windows = false, -- façade occupée par les portes de garage
		accent = C.Gold,
		doorWidth = 8,
		doorHeight = 8,
		roofUnits = true,
	})
	sign(model, origin, "campus.Workshop.sign", math.min(size.X * 0.6, 18), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4))
	-- Portes sectionnelles striées (1, 2, 3) sur la façade, à côté de l'entrée.
	for i = 1, level do
		local x = if i == 1 then -size.X / 2 + 5.5 elseif i == 2 then size.X / 2 - 5.5 else -size.X / 2 + 12
		PartUtil.block(model, origin, "GarageDoor", v(6, 7, 0.3), v(x, 0.4, -size.Z / 2 - 0.2), Color3.fromRGB(200, 200, 196), Enum.Material.Metal)
		for s = 1, 5 do
			PartUtil.detail(PartUtil.block(model, origin, "DoorRib", v(6, 0.12, 0.1), v(x, 0.4 + s * 1.2, -size.Z / 2 - 0.4), Color3.fromRGB(150, 150, 146), Enum.Material.Metal, {
				canCollide = false,
			}))
		end
	end
	-- Établis le long du mur du fond.
	for i = 1, level + 1 do
		local x = -size.X / 2 + 4 + (i - 1) * (size.X - 8) / math.max(1, level)
		workbench(model, origin, v(x, 0.4, size.Z / 2 - 1.8), ctx)
	end
	-- Pont élévateur avec une voiture (niveau 2+), tondeuse de pelouse du club.
	if level >= 2 then
		PartUtil.block(model, origin, "LiftPost", v(0.6, 6, 0.6), v(-4, 0.4, 0), C.Gold, Enum.Material.Metal)
		PartUtil.block(model, origin, "LiftPost", v(0.6, 6, 0.6), v(4, 0.4, 0), C.Gold, Enum.Material.Metal)
		Props.car(model, origin * CFrame.new(0, 3, 0), 0, 0, 90, ctx.primary)
	end
	PartUtil.block(model, origin, "Mower", v(2.6, 1.4, 3.6), v(size.X / 2 - 4, 0.4, -2), Color3.fromRGB(60, 140, 60), Enum.Material.Metal)
	if level >= 3 then
		-- Chariot élévateur et réserve de palettes.
		PartUtil.block(model, origin, "Forklift", v(2.6, 2.6, 4), v(-size.X / 2 + 4, 0.4, -4), Color3.fromRGB(230, 170, 30), Enum.Material.Metal)
		PartUtil.detail(PartUtil.block(model, origin, "ForkMast", v(2, 6, 0.3), v(-size.X / 2 + 4, 0.4, -6.2), TRIM, Enum.Material.Metal))
		for i = 0, 2 do
			PartUtil.detail(PartUtil.block(model, origin, "Pallet", v(3, 1.2, 3), v(size.X / 2 - 4, 0.4 + i * 1.2, 5), Color3.fromRGB(160, 120, 70), Enum.Material.WoodPlanks))
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Dépôt des véhicules : hangar ouvert, bus du club, minibus, borne de recharge.
--------------------------------------------------------------------------------
function CampusFacilities.Depot(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Depot")
	slab(model, origin, Vector2.new(46, 46), Enum.Material.Asphalt, C.Asphalt)
	-- Hangar : poteaux, toit et mur du fond (plus profond à chaque niveau).
	local width = 22 + level * 6
	local depth = 24
	local height = 9 + level
	local cz = 6
	PartUtil.block(model, origin, "BackWall", v(width, height, 0.6), v(0, 0.2, cz + depth / 2), C.Charcoal, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		PartUtil.block(model, origin, "SideWall", v(0.6, height, depth), v(side * width / 2, 0.2, cz), C.Charcoal, Enum.Material.Metal)
	end
	PartUtil.block(model, origin, "HangarRoof", v(width + 2, 0.8, depth + 3), v(0, 0.2 + height, cz - 1), C.Roof, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(model, origin, "RoofTrim", v(width + 2.2, 0.5, 0.3), v(0, height + 0.4, cz - depth / 2 - 2.6), C.Gold, Enum.Material.Metal, { canCollide = false }))
	local front = origin * CFrame.new(0, 0, cz - depth / 2 - 2.5)
	sign(model, front, "campus.Depot.sign", 14, v(0, 0.2 + height - 1.2, -0.3))
	-- Marquage au sol des places.
	local bays = level + 1
	for i = 0, bays do
		local x = -width / 2 + 1 + i * (width - 2) / bays
		PartUtil.detail(PartUtil.block(model, origin, "BayLine", v(0.3, 0.04, depth - 4), v(x, 0.2, cz), C.Line, Enum.Material.SmoothPlastic, { canCollide = false }))
	end
	-- Véhicules : bus du club, puis minibus, puis second bus.
	local bayW = (width - 2) / bays
	local function bayX(i: number): number
		return -width / 2 + 1 + bayW * (i - 0.5)
	end
	bus(model, origin, bayX(1), cz + 1, 0, ctx)
	if level >= 2 then
		Props.car(model, origin, bayX(2), cz - 3, 0, WHITE)
	end
	if level >= 3 then
		bus(model, origin, bayX(bays), cz + 1, 0, ctx)
	end
	-- Borne de recharge et lavage à l'extérieur.
	PartUtil.block(model, origin, "Charger", v(1.2, 3.2, 0.8), v(18, 0.2, -16), WHITE, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(model, origin, "ChargerLed", v(0.8, 0.4, 0.05), v(18, 2.6, -16.42), Color3.fromRGB(60, 220, 120), Enum.Material.Neon, { canCollide = false }))
	if level >= 2 then
		-- Portique de lavage : deux montants, une traverse et deux brosses.
		for _, side in { -1, 1 } do
			PartUtil.block(model, origin, "WashPost", v(0.8, 7, 1.2), v(-15 + side * 4, 0.2, -16), ctx.primary, Enum.Material.Metal)
			PartUtil.detail(PartUtil.cylinder(model, origin, "WashBrush", 1.4, 5.6, v(-15 + side * 2.6, 0.4, -16), Color3.fromRGB(60, 120, 220), Enum.Material.Fabric))
		end
		PartUtil.block(model, origin, "WashBeam", v(8.8, 0.8, 1.2), v(-15, 7.2, -16), ctx.primary, Enum.Material.Metal)
	end
	return model
end

return CampusFacilities
