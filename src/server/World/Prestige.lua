--!strict
--[[
	Prestige — salle des trophées et personnalisation visuelle d'un terrain de club.

	Tout est purement visuel (aucun effet sur les matchs). Les objets viennent
	de Shared/Cosmetics.lua et les trophées de Shared/Trophies.lua.

	- buildTrophyRoom : pavillon vitré à gauche de l'entrée, toujours présent.
	  Les trophées s'alignent sur deux étagères (montées, titres, records) ;
	  deux mannequins portent la tenue choisie. Visible par tous les visiteurs.
	- buildStatue : statue choisie, sur un socle devant l'entrée du stade.
	- buildDecor : décorations achetées (drapeaux, massifs, palmiers, fontaine,
	  arche lumineuse, allée des étoiles), placées hors des installations.
	- applyLighting / applyKit : recolorent les projecteurs et les mannequins
	  d'entraînement déjà construits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Trophies = require(Shared:WaitForChild("Trophies"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Prestige = {}

local C = WorldConfig.COLORS

local TIER_COLORS = {
	gold = Color3.fromRGB(212, 175, 55),
	silver = Color3.fromRGB(196, 200, 206),
	bronze = Color3.fromRGB(176, 112, 60),
}

-- Tenue : { pattern, shirt, detail } (couleurs du club par défaut).
export type Kit = { pattern: string, shirt: Color3, detail: Color3 }

function Prestige.resolveKit(item: any, ctx: BuildContext): Kit
	return {
		pattern = if item and item.pattern then item.pattern else "plain",
		shirt = if item and item.shirt then item.shirt else ctx.primary,
		detail = if item and item.detail then item.detail else ctx.secondary,
	}
end

-- Mannequin en tenue (maillot à motif, short, tête) posé en (x, z) du repère `origin`.
local function kitMannequin(parent: Instance, origin: CFrame, x: number, z: number, kit: Kit)
	local m = PartUtil.model(parent, "KitMannequin")
	local base = Vector3.new(x, 0, z)
	PartUtil.cylinder(m, origin, "Stand", 1.6, 0.4, base, C.MetalDark, Enum.Material.Metal)
	PartUtil.block(m, origin, "Shorts", Vector3.new(1.8, 1.2, 0.8), base + Vector3.new(0, 1.6, 0), kit.detail, Enum.Material.Fabric)
	PartUtil.block(m, origin, "Shirt", Vector3.new(2, 2.2, 0.9), base + Vector3.new(0, 2.8, 0), kit.shirt, Enum.Material.Fabric)
	local front = -0.47 -- face avant du maillot (-Z)
	local function strip(name: string, size: Vector3, pos: Vector3, rotZ: number?)
		PartUtil.box(m, origin, name, size, base + pos, kit.detail, Enum.Material.Fabric, { canCollide = false, rotZ = rotZ, castShadow = false })
	end
	if kit.pattern == "stripes" then
		strip("Stripe", Vector3.new(0.35, 2.2, 0.06), Vector3.new(-0.5, 3.9, front))
		strip("Stripe", Vector3.new(0.35, 2.2, 0.06), Vector3.new(0.5, 3.9, front))
	elseif kit.pattern == "hoops" then
		strip("Hoop", Vector3.new(2.02, 0.35, 0.92), Vector3.new(0, 3.4, 0))
		strip("Hoop", Vector3.new(2.02, 0.35, 0.92), Vector3.new(0, 4.3, 0))
	elseif kit.pattern == "sash" then
		strip("Sash", Vector3.new(0.45, 2.6, 0.06), Vector3.new(0, 3.9, front), 40)
	elseif kit.pattern == "halves" then
		strip("Half", Vector3.new(1, 2.2, 0.92), Vector3.new(0.5, 3.9, 0))
	end
	PartUtil.ball(m, origin, "Head", 1.1, base + Vector3.new(0, 5.5, 0), C.Plaster, Enum.Material.SmoothPlastic)
	return m
end

-- Coupe : socle et coupe aux couleurs du rang (or, argent, bronze).
local function trophyCup(parent: Instance, origin: CFrame, pos: Vector3, tier: string, big: boolean)
	local color = TIER_COLORS[tier] or TIER_COLORS.silver
	local s = if big then 1.4 else 1
	PartUtil.block(parent, origin, "TrophyBase", Vector3.new(0.9, 0.35, 0.9) * s, pos, C.WoodDark, Enum.Material.Wood)
	PartUtil.box(parent, origin, "TrophyCup", Vector3.new(0.8, 1.3, 0.8) * s, pos + Vector3.new(0, 1, 0) * s, color, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, rotZ = 90 })
end

-- Salle des trophées. `trophies` = Trophies.Earned(...) ; `titles` = nombre de titres de D1.
function Prestige.buildTrophyRoom(parent: Instance, origin: CFrame, trophies: { any }, titles: number, kit: Kit, ctx: BuildContext): Model
	local layout = WorldConfig.LAYOUT.TrophyRoom
	local model = PartUtil.model(parent, "TrophyRoom", { Facility = "TrophyRoom", Level = 1, Trophies = #trophies })
	local size = Vector3.new(24, 9, 15)
	PartUtil.anchor(model, origin, layout.footprint, size.Y + 1)
	local room = origin * CFrame.new(0, 0, 1.5)
	PartUtil.shell(model, room, size, {
		wallColor = C.Plaster,
		wallMaterial = Enum.Material.SmoothPlastic,
		roofColor = C.Roof,
		glassFront = true,
		accent = ctx.primary,
		roofOverhang = 0.5,
		doorWidth = 5,
	})
	PartUtil.frontSign(model, room, "world.trophyRoom", Vector2.new(16, 1.6), Vector3.new(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4), C.SignText, C.SignBack)

	-- Deux étagères le long du mur du fond, éclairées par le bandeau au plafond.
	local backZ = size.Z / 2 - 1.6
	local shelfWidth = size.X - 3
	local perShelf = 12
	for row = 1, 2 do
		local y = 0.4 + row * 2.6 - 1.2
		PartUtil.block(model, room, "Shelf", Vector3.new(shelfWidth, 0.3, 2), Vector3.new(0, y - 0.3, backZ), C.WoodDark, Enum.Material.Wood)
	end
	local shown = 0
	local titleShown = 0
	for _, trophy in trophies do
		if trophy.kind == "title" then
			titleShown += 1
			if titleShown > Trophies.MAX_DISPLAYED_TITLES then
				continue
			end
		end
		if shown >= perShelf * 2 then
			break
		end
		local row = math.floor(shown / perShelf) + 1
		local col = shown % perShelf
		local x = -shelfWidth / 2 + (col + 0.5) * (shelfWidth / perShelf)
		local y = 0.4 + row * 2.6 - 1.2
		trophyCup(model, room, Vector3.new(x, y, backZ), trophy.tier, trophy.kind == "title")
		shown += 1
	end

	-- Plaque du palmarès sur le mur du fond : nombre de trophées et de titres.
	local plaque = PartUtil.box(
		model,
		room,
		"Plaque",
		Vector3.new(10, 1.4, 0.2),
		Vector3.new(0, 0.4 + 6.9, size.Z / 2 - 0.75),
		C.SignBack,
		Enum.Material.SmoothPlastic,
		{ canCollide = false }
	)
	PartUtil.label(plaque, Enum.NormalId.Front, "world.trophyCount", C.Gold, nil, { count = #trophies, titles = titles })

	-- Tenue du club : deux mannequins derrière la vitrine.
	for _, sx in { -1, 1 } do
		kitMannequin(model, room, sx * 8.5, -size.Z / 2 + 2.5, kit)
	end
	return model
end

-- Statue devant l'entrée du stade. `item` = objet « statue » de Cosmetics.
function Prestige.buildStatue(parent: Instance, origin: CFrame, item: any, ctx: BuildContext): Model
	local layout = WorldConfig.LAYOUT.Statue
	local model = PartUtil.model(parent, "Statue", { Facility = "Statue", Level = 1, Cosmetic = item.id })
	PartUtil.anchor(model, origin, layout.footprint, 10)
	local color: Color3 = item.color or C.Concrete
	local material = (Enum.Material :: any)[item.material or "SmoothPlastic"] or Enum.Material.SmoothPlastic
	PartUtil.block(model, origin, "Plinth", Vector3.new(5, 1.6, 5), Vector3.zero, C.Concrete, Enum.Material.Concrete)
	PartUtil.block(model, origin, "PlinthTrim", Vector3.new(5.4, 0.3, 5.4), Vector3.new(0, 1.6, 0), ctx.primary, Enum.Material.SmoothPlastic)
	local top = 1.9
	if item.id == "statue_ball" then
		PartUtil.ball(model, origin, "Ball", 4, Vector3.new(0, top + 2, 0), color, material)
	elseif item.id == "statue_boot" then
		PartUtil.block(model, origin, "BootSole", Vector3.new(1.8, 0.6, 4), Vector3.new(0, top, 0), color, material)
		PartUtil.block(model, origin, "BootUpper", Vector3.new(1.8, 2.6, 2), Vector3.new(0, top + 0.6, 1), color, material)
		PartUtil.box(model, origin, "BootToe", Vector3.new(1.8, 1.4, 2.2), Vector3.new(0, top + 1.2, -0.9), color, material, { rotX = -20 })
	elseif item.id == "statue_cup" then
		PartUtil.cylinder(model, origin, "CupFoot", 3, 1, Vector3.new(0, top, 0), color, material)
		PartUtil.cylinder(model, origin, "CupStem", 1, 2.4, Vector3.new(0, top + 1, 0), color, material)
		PartUtil.ball(model, origin, "CupBowl", 4, Vector3.new(0, top + 5, 0), color, material)
		for _, sx in { -1, 1 } do
			PartUtil.box(model, origin, "CupHandle", Vector3.new(0.6, 2.4, 0.6), Vector3.new(sx * 2.4, top + 5, 0), color, material, { rotZ = sx * 25 })
		end
	else
		-- Silhouette humaine : joueur, entraîneur ou légende (bras levé pour la légende).
		PartUtil.block(model, origin, "Legs", Vector3.new(1.6, 2.6, 0.9), Vector3.new(0, top, 0), color, material)
		PartUtil.block(model, origin, "Body", Vector3.new(2.2, 2.6, 1.1), Vector3.new(0, top + 2.6, 0), color, material)
		PartUtil.ball(model, origin, "Head", 1.3, Vector3.new(0, top + 5.9, 0), color, material)
		if item.id == "statue_striker" or item.id == "statue_event_goal" then
			PartUtil.ball(model, origin, "Ball", 1.1, Vector3.new(0.9, top + 0.55, -1), color, material)
		elseif item.id == "statue_legend" then
			PartUtil.box(model, origin, "Arm", Vector3.new(0.6, 2.6, 0.6), Vector3.new(1.5, top + 5.8, 0), color, material, { rotZ = -15 })
			PartUtil.ball(model, origin, "Cup", 1, Vector3.new(1.9, top + 7.4, 0), color, material)
		end
	end
	return model
end

-- Décorations achetées. `origin` = centre du terrain ; `owned` = { [id] = true }.
function Prestige.buildDecor(parent: Instance, origin: CFrame, owned: { [string]: any }, ctx: BuildContext): Model?
	if next(owned) == nil then
		return nil
	end
	local top = WorldConfig.PLOT_GROUND_TOP
	local model = PartUtil.model(parent, "Decor")
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, top + y, z)
	end

	if owned.decor_flags then
		-- Mâts et drapeaux aux couleurs du club le long de la route (de part et d'autre de l'entrée).
		for _, x in { -120, -95, -70, -45, -25, 25, 45, 70, 95, 120 } do
			PartUtil.cylinder(model, origin, "FlagPole", 0.4, 12, v(x, 0, -96), C.Metal, Enum.Material.Metal)
			PartUtil.box(model, origin, "Flag", Vector3.new(3.2, 2, 0.1), v(x + 1.8, 10.8, -96), if x % 2 == 0 then ctx.primary else ctx.secondary, Enum.Material.Fabric, { canCollide = false })
		end
	end
	if owned.decor_flowers then
		-- Massifs de fleurs derrière le stade.
		for i, x in { -115, -85, -55, -25, 5, 35 } do
			PartUtil.block(model, origin, "FlowerBed", Vector3.new(8, 0.6, 3), v(x, 0, 91), C.Brick, Enum.Material.Brick)
			PartUtil.block(model, origin, "Flowers", Vector3.new(7.4, 0.5, 2.4), v(x, 0.6, 91), if i % 2 == 0 then ctx.primary else Color3.fromRGB(240, 200, 60), Enum.Material.Grass, { canCollide = false })
		end
	end
	if owned.decor_palms then
		local spots = { { -125, -40 }, { -125, -10 }, { -125, 20 }, { -125, 50 }, { 124, -45 }, { 124, -20 } }
		for _, p in spots do
			PartUtil.cylinder(model, origin, "PalmTrunk", 1.2, 14, v(p[1], 0, p[2]), C.Wood, Enum.Material.Wood)
			for _, rot in { 0, 60, 120 } do
				PartUtil.box(model, origin, "PalmLeaf", Vector3.new(7, 0.3, 1.6), v(p[1], 14, p[2]), Color3.fromRGB(60, 140, 60), Enum.Material.Grass, { canCollide = false, rotY = rot, rotZ = 8 })
			end
		end
	end
	if owned.decor_fountain then
		local x, z = 95, 89
		PartUtil.cylinder(model, origin, "FountainBasin", 14, 1.2, v(x, 0, z), C.Concrete, Enum.Material.Concrete)
		PartUtil.cylinder(model, origin, "FountainWater", 12.6, 0.2, v(x, 1.1, z), C.Water, Enum.Material.Glass, { canCollide = false, transparency = 0.2 })
		PartUtil.cylinder(model, origin, "FountainColumn", 1.6, 4, v(x, 1.2, z), C.Concrete, Enum.Material.Marble)
		PartUtil.ball(model, origin, "FountainBall", 2.4, v(x, 6.4, z), ctx.primary, Enum.Material.SmoothPlastic)
	end
	if owned.decor_arch then
		-- Arche lumineuse au-dessus de l'allée, entre l'entrée et le stade.
		for _, sx in { -1, 1 } do
			PartUtil.block(model, origin, "ArchPost", Vector3.new(1.2, 10, 1.2), v(sx * 6.5, 0, -84), ctx.primary, Enum.Material.Metal)
		end
		local beam = PartUtil.box(model, origin, "ArchBeam", Vector3.new(14.2, 1.6, 1.2), v(0, 10.8, -84), ctx.secondary, Enum.Material.Neon, { canCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.5
		light.Color = ctx.secondary
		light.Parent = beam
	end
	if owned.decor_walk then
		-- Allée des étoiles : étoiles dorées au sol, de l'entrée au stade.
		for z = -91, -63, 4 do
			PartUtil.box(model, origin, "Star", Vector3.new(2.2, 0.06, 2.2), v(0, 0.08, z), C.Gold, Enum.Material.Neon, { canCollide = false, rotY = 45, castShadow = false })
		end
	end
	return model
end

local LIGHT_PARTS = { Lamps = true, LightHead = true, Lamp = true }

-- Recolore les projecteurs (Parts lumineuses et SpotLight) d'un terrain.
function Prestige.applyLighting(plot: Instance, color: Color3)
	for _, d in plot:GetDescendants() do
		if d:IsA("SpotLight") then
			d.Color = color
		elseif d:IsA("BasePart") and LIGHT_PARTS[d.Name] then
			d.Color = color
		end
	end
end

-- Les mannequins d'entraînement portent le maillot du club.
function Prestige.applyKit(plot: Instance, kit: Kit)
	for _, d in plot:GetDescendants() do
		if d:IsA("Model") and d.Name == "Mannequin" then
			local body = d:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				body.Color = kit.shirt
			end
		end
	end
end

return Prestige
