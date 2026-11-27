--!strict
--[[
	CampusBuildings — modèles 3D des bâtiments du mode Création (lot 1) :
	centre e-sport, musée du club, bureau présidentiel, centre de récupération
	et place des champions. 3 niveaux chacun (Campus.lua).

	Repère : `origin` = centre de la parcelle au sol, déjà tourné selon le choix
	du joueur. L'entrée est côté -Z. Tout tient dans WorldConfig.CAMPUS_FOOTPRINT
	(46 × 46 studs) pour pouvoir tourner le bâtiment dans les 4 sens.
	Direction artistique : anthracite, verre teinté, or et couleurs du club.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))
local Props = require(script.Parent:WaitForChild("Props"))

type BuildContext = PartUtil.BuildContext
export type Extra = { trophies: { any }?, titles: number? }

local CampusBuildings = {}

local C = WorldConfig.COLORS
local TRIM = PartUtil.TRIM
local BRONZE = Color3.fromRGB(150, 104, 62)
local WATER = Color3.fromRGB(70, 170, 210)
local TIER_COLORS = {
	gold = Color3.fromRGB(212, 175, 55),
	silver = Color3.fromRGB(200, 204, 212),
	bronze = Color3.fromRGB(176, 112, 60),
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Panneau d'enseigne lumineuse (texte traduit) sur la façade avant.
local function sign(parent: Instance, origin: CFrame, key: string, width: number, pos: Vector3, color: Color3?)
	local s = PartUtil.frontSign(parent, origin, key, Vector2.new(width, 1.8), pos, color or C.Gold, TRIM)
	return s
end

-- Dalle de sol (béton clair) sous un bâtiment ou une place.
local function slab(parent: Instance, origin: CFrame, size: Vector2, material: Enum.Material?, color: Color3?)
	return PartUtil.block(parent, origin, "Slab", Vector3.new(size.X, 0.2, size.Y), Vector3.zero, color or Color3.fromRGB(205, 202, 194), material or Enum.Material.Pavement, {
		castShadow = false,
	})
end

-- Poste de jeu : bureau, écran lumineux, fauteuil gaming aux couleurs du club.
local function station(parent: Instance, origin: CFrame, pos: Vector3, ctx: BuildContext, glow: Color3)
	PartUtil.block(parent, origin, "Desk", v(3.2, 0.25, 1.6), pos + v(0, 2.6, 0), TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(parent, origin, "DeskLeg", v(3, 2.6, 0.2), pos + v(0, 0, 0.6), TRIM, Enum.Material.Metal))
	PartUtil.detail(PartUtil.block(parent, origin, "Monitor", v(2.4, 1.4, 0.15), pos + v(0, 2.95, 0.5), glow, Enum.Material.Neon, { canCollide = false }))
	PartUtil.detail(PartUtil.block(parent, origin, "GamingSeat", v(1.6, 0.4, 1.6), pos + v(0, 1.5, -1.6), ctx.primary, Enum.Material.Leather))
	PartUtil.detail(PartUtil.block(parent, origin, "GamingBack", v(1.6, 2.6, 0.35), pos + v(0, 1.9, -2.4), TRIM, Enum.Material.Leather))
end

-- Coupe sur socle (or, argent, bronze).
local function cup(parent: Instance, origin: CFrame, pos: Vector3, tier: string?, scale: number?)
	local s = scale or 1
	local color = TIER_COLORS[tier or "gold"] or TIER_COLORS.gold
	PartUtil.box(parent, origin, "TrophyCup", v(1.3, 0.8, 0.8) * s, pos + v(0, 0.65, 0) * s, color, Enum.Material.Metal, {
		shape = Enum.PartType.Cylinder,
		rotZ = 90,
		canCollide = false,
	})
	PartUtil.detail(PartUtil.ball(parent, origin, "TrophyBowl", 1.1 * s, pos + v(0, 1.6, 0) * s, color, Enum.Material.Metal))
end

-- Vitrine : socle sombre, cloche de verre et (si gagné) un trophée du club.
local function vitrine(parent: Instance, origin: CFrame, pos: Vector3, trophy: any?)
	PartUtil.block(parent, origin, "VitrineBase", v(2.4, 2.6, 2.4), pos, TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(parent, origin, "VitrineTrim", v(2.5, 0.12, 2.5), pos + v(0, 2.6, 0), C.Gold, Enum.Material.Metal))
	PartUtil.block(parent, origin, "VitrineGlass", v(2.2, 2.6, 2.2), pos + v(0, 2.72, 0), PartUtil.GLASS, Enum.Material.Glass, {
		transparency = 0.6,
		castShadow = false,
	})
	if trophy then
		cup(parent, origin, pos + v(0, 2.72, 0), trophy.tier, 0.9)
	end
end

-- Statue de joueur en bronze (bras levés ou ballon au pied) sur un socle en pierre.
local function statue(parent: Instance, origin: CFrame, pos: Vector3, pose: number, rotY: number?)
	local m = PartUtil.model(parent, "Statue")
	local o = origin * CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	PartUtil.block(m, o, "Plinth", v(3.6, 3, 3.6), v(0, 0, 0), Color3.fromRGB(176, 172, 164), Enum.Material.Granite)
	PartUtil.detail(PartUtil.block(m, o, "PlinthTrim", v(3.8, 0.25, 3.8), v(0, 3, 0), C.Gold, Enum.Material.Metal))
	local y = 3.25
	for _, side in { -1, 1 } do
		PartUtil.block(m, o, "Leg", v(0.7, 3, 0.8), v(side * 0.45, y, 0), BRONZE, Enum.Material.Metal)
	end
	PartUtil.block(m, o, "Torso", v(2, 2.6, 1), v(0, y + 3, 0), BRONZE, Enum.Material.Metal)
	PartUtil.ball(m, o, "Head", 1.3, v(0, y + 6.3, 0), BRONZE, Enum.Material.Metal)
	if pose == 1 then
		-- Bras levés (célébration) avec une coupe.
		for _, side in { -1, 1 } do
			PartUtil.box(m, o, "Arm", v(0.6, 2.6, 0.6), v(side * 1.25, y + 6.2, 0), BRONZE, Enum.Material.Metal, { rotZ = side * -20 })
		end
		PartUtil.detail(PartUtil.ball(m, o, "Trophy", 1.2, v(0, y + 8, 0), C.Gold, Enum.Material.Metal))
	else
		-- Bras le long du corps, ballon sous le pied.
		for _, side in { -1, 1 } do
			PartUtil.block(m, o, "Arm", v(0.6, 2.4, 0.6), v(side * 1.3, y + 3.1, 0), BRONZE, Enum.Material.Metal)
		end
		PartUtil.detail(PartUtil.ball(m, o, "Ball", 1.2, v(0.6, y + 0.6, -0.9), BRONZE, Enum.Material.Metal))
	end
	return m
end

-- Fontaine ronde : bassin, eau, colonne et vasques (tiers = 1 à 3).
local function fountain(parent: Instance, origin: CFrame, pos: Vector3, diameter: number, tiers: number)
	local m = PartUtil.model(parent, "Fountain")
	PartUtil.cylinder(m, origin, "Basin", diameter, 1.4, pos, Color3.fromRGB(200, 196, 188), Enum.Material.Limestone)
	PartUtil.cylinder(m, origin, "Water", diameter - 1.2, 0.2, pos + v(0, 1.25, 0), WATER, Enum.Material.Glass, { canCollide = false, transparency = 0.25 })
	PartUtil.cylinder(m, origin, "Column", 1.4, 3 + tiers * 1.6, pos + v(0, 1.4, 0), Color3.fromRGB(220, 216, 208), Enum.Material.Marble)
	for t = 1, tiers do
		local d = diameter * (0.55 - t * 0.12)
		PartUtil.cylinder(m, origin, "Bowl", d, 0.5, pos + v(0, 1.4 + t * 1.8, 0), Color3.fromRGB(220, 216, 208), Enum.Material.Marble)
		PartUtil.detail(PartUtil.cylinder(m, origin, "Jet", d * 0.7, 0.3, pos + v(0, 1.9 + t * 1.8, 0), WATER, Enum.Material.Glass, {
			canCollide = false,
			transparency = 0.3,
		}))
	end
	PartUtil.detail(PartUtil.cylinder(m, origin, "Spray", 0.8, 2.4, pos + v(0, 3.2 + tiers * 1.8, 0), Color3.fromRGB(220, 240, 255), Enum.Material.Glass, {
		canCollide = false,
		transparency = 0.45,
	}))
	return m
end

-- Transat de piscine.
local function lounger(parent: Instance, origin: CFrame, pos: Vector3)
	PartUtil.block(parent, origin, "Lounger", v(1.8, 0.5, 5), pos + v(0, 0.4, 0), Color3.fromRGB(236, 236, 232), Enum.Material.Fabric)
	PartUtil.detail(PartUtil.box(parent, origin, "LoungerBack", v(1.8, 0.4, 2), pos + v(0, 1.3, 2.4), Color3.fromRGB(236, 236, 232), Enum.Material.Fabric, { rotX = 40 }))
	PartUtil.detail(PartUtil.block(parent, origin, "LoungerFrame", v(1.9, 0.4, 5.1), pos, TRIM, Enum.Material.Metal))
end

--------------------------------------------------------------------------------
-- Centre e-sport : salle de jeu vitrée, postes alignés, écran géant, néons.
--------------------------------------------------------------------------------
function CampusBuildings.Esport(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Esport")
	local sizes = { v(24, 11, 18), v(32, 12, 22), v(38, 20, 26) }
	local size = sizes[level] or sizes[1]
	slab(model, origin, Vector2.new(size.X + 6, size.Z + 8))
	PartUtil.shell(model, origin, size, {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Metal,
		roofColor = C.Roof,
		windows = true,
		glassFront = true,
		accent = ctx.primary,
		doorWidth = 6,
		canopy = true,
		floors = if level >= 3 then 2 else nil,
	})
	sign(model, origin, "campus.Esport.sign", math.min(size.X * 0.6, 18), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4), ctx.secondary)
	-- Bandeau néon aux couleurs du club tout autour du toit.
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(model, origin, "NeonStrip", v(size.X + 0.4, 0.3, 0.2), v(0, 0.4 + size.Y - 2.8, side * (size.Z / 2 + 0.25)), ctx.primary, Enum.Material.Neon, { canCollide = false }))
	end
	-- Postes de jeu sur 2 rangées (4, 8 puis 12 postes).
	local perRow = level * 2
	local glow = Color3.fromRGB(90, 170, 255)
	for row = 0, 1 do
		for i = 0, perRow - 1 do
			local x = -size.X / 2 + 3 + i * (size.X - 6) / math.max(1, perRow - 1)
			station(model, origin, v(x, 0.4, -1 + row * 6), ctx, glow)
		end
	end
	-- Écran géant au fond de la salle.
	PartUtil.block(model, origin, "BigScreenFrame", v(size.X * 0.5 + 0.6, 5.6, 0.3), v(0, 3.6, size.Z / 2 - 0.9), TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(model, origin, "BigScreen", v(size.X * 0.5, 5, 0.2), v(0, 3.9, size.Z / 2 - 1.1), Color3.fromRGB(70, 120, 255), Enum.Material.Neon, { canCollide = false }))
	if level >= 2 then
		-- Scène des tournois devant l'écran.
		PartUtil.block(model, origin, "Stage", v(size.X * 0.5, 0.8, 4), v(0, 0.4, size.Z / 2 - 3.6), TRIM, Enum.Material.Metal)
	end
	if level >= 3 then
		-- Écran géant extérieur sur la façade et antenne satellite sur le toit.
		local top = 0.4 + size.Y + 0.6
		PartUtil.block(model, origin, "FacadeScreenFrame", v(12.6, 7.6, 0.4), v(size.X / 2 - 8, 9, -size.Z / 2 - 0.5), TRIM, Enum.Material.Metal, { canCollide = false })
		PartUtil.detail(PartUtil.block(model, origin, "FacadeScreen", v(12, 7, 0.2), v(size.X / 2 - 8, 9.3, -size.Z / 2 - 0.75), Color3.fromRGB(120, 80, 255), Enum.Material.Neon, { canCollide = false }))
		PartUtil.cylinder(model, origin, "DishMast", 0.6, 3, v(-size.X / 4, top, size.Z / 4), TRIM, Enum.Material.Metal)
		PartUtil.detail(PartUtil.box(model, origin, "Dish", v(0.5, 4, 4), v(-size.X / 4, top + 4, size.Z / 4), Color3.fromRGB(230, 230, 230), Enum.Material.Metal, {
			shape = Enum.PartType.Cylinder,
			rotZ = 30,
		}))
	end
	return model
end

--------------------------------------------------------------------------------
-- Musée du club : marbre et or, vitrines avec les vrais trophées du club, photos.
--------------------------------------------------------------------------------
function CampusBuildings.Museum(parent: Instance, origin: CFrame, level: number, ctx: BuildContext, extra: Extra?): Model
	local model = PartUtil.model(parent, "Museum")
	local sizes = { v(26, 11, 20), v(32, 12, 24), v(40, 15, 28) }
	local size = sizes[level] or sizes[1]
	local trophies = (extra and extra.trophies) or {}
	slab(model, origin, Vector2.new(size.X + 6, size.Z + 10), Enum.Material.Marble, Color3.fromRGB(226, 222, 214))
	PartUtil.shell(model, origin, size, {
		wallColor = Color3.fromRGB(232, 230, 224),
		wallMaterial = Enum.Material.Marble,
		roofColor = C.Roof,
		windows = false,
		glassFront = true,
		accent = C.Gold,
		trim = C.Gold,
		doorWidth = 6,
	})
	sign(model, origin, "campus.Museum.sign", math.min(size.X * 0.6, 20), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4))
	-- Vitrines (4, 8, 12) en deux rangées : un vrai trophée du club dans chacune, si gagné.
	local count = level * 4
	local perRow = count / 2
	for i = 1, count do
		local row = if i <= perRow then 0 else 1
		local col = (i - 1) % perRow
		local x = -size.X / 2 + 4 + col * (size.X - 8) / math.max(1, perRow - 1)
		vitrine(model, origin, v(x, 0.4, -2 + row * 7), trophies[i])
	end
	-- Photos encadrées sur le mur du fond (cadre doré, image aux couleurs du club).
	for i = 0, level + 1 do
		local x = -size.X / 2 + 4 + i * (size.X - 8) / (level + 1)
		PartUtil.block(model, origin, "PhotoFrame", v(3.2, 2.4, 0.15), v(x, 4.5, size.Z / 2 - 0.75), C.Gold, Enum.Material.Metal, { canCollide = false })
		PartUtil.detail(PartUtil.block(model, origin, "Photo", v(2.8, 2, 0.1), v(x, 4.7, size.Z / 2 - 0.85), if i % 2 == 0 then ctx.primary else Color3.fromRGB(70, 74, 82), Enum.Material.SmoothPlastic, {
			canCollide = false,
		}))
	end
	if level >= 2 then
		-- Colonnade de marbre devant l'entrée.
		for _, x in { -9, -5, 5, 9 } do
			PartUtil.cylinder(model, origin, "Column", 1.4, size.Y, v(x, 0.2, -size.Z / 2 - 3), Color3.fromRGB(236, 234, 228), Enum.Material.Marble)
		end
		PartUtil.block(model, origin, "Portico", v(22, 1, 5), v(0, 0.2 + size.Y, -size.Z / 2 - 2.5), Color3.fromRGB(236, 234, 228), Enum.Material.Marble)
	end
	if level >= 3 then
		-- Fronton triangulaire et trophée géant au centre de la salle.
		for _, side in { -1, 1 } do
			PartUtil.block(model, origin, "Pediment", v(5, 3, 11), v(side * 5.5, 1.2 + size.Y, -size.Z / 2 - 2.5), Color3.fromRGB(236, 234, 228), Enum.Material.Marble, {
				className = "WedgePart",
				-- Le côté haut d'un WedgePart est à +Z : on le tourne vers le centre.
				rotY = -side * 90,
			})
		end
		PartUtil.block(model, origin, "GiantPlinth", v(3, 1.6, 3), v(0, 0.4, 5.5), TRIM, Enum.Material.Marble)
		cup(model, origin, v(0, 2, 5.5), "gold", 2.2)
	end
	return model
end

--------------------------------------------------------------------------------
-- Bureau présidentiel : grand bureau, fauteuils, trophées, terrasse.
--------------------------------------------------------------------------------
function CampusBuildings.President(parent: Instance, origin: CFrame, level: number, ctx: BuildContext, extra: Extra?): Model
	local model = PartUtil.model(parent, "President")
	local sizes = { v(24, 12, 18), v(30, 16, 22), v(34, 24, 24) }
	local size = sizes[level] or sizes[1]
	slab(model, origin, Vector2.new(size.X + 8, size.Z + 10), Enum.Material.Pavement, Color3.fromRGB(210, 206, 198))
	PartUtil.shell(model, origin, size, {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Metal,
		roofColor = C.Roof,
		windows = true,
		glassFront = true,
		accent = C.Gold,
		doorWidth = 6,
		canopy = true,
		floors = level,
	})
	sign(model, origin, "campus.President.sign", math.min(size.X * 0.6, 18), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4))
	-- Bardage bois chaleureux sur un angle de la façade (comme sur la planche).
	PartUtil.block(model, origin, "WoodCladding", v(4, size.Y, 0.3), v(-size.X / 2 + 2.3, 0.4, -size.Z / 2 - 0.2), C.Wood, Enum.Material.WoodPlanks)
	-- Bureau du président : plateau bois sombre bordé d'or, fauteuil cuir, 2 fauteuils visiteurs.
	local dz = size.Z / 2 - 5
	PartUtil.block(model, origin, "Desk", v(8, 3, 3), v(0, 0.4, dz), C.WoodDark, Enum.Material.Wood)
	PartUtil.detail(PartUtil.block(model, origin, "DeskTrim", v(8.2, 0.15, 3.2), v(0, 3.4, dz), C.Gold, Enum.Material.Metal))
	PartUtil.block(model, origin, "ChairSeat", v(2.6, 1.6, 2.4), v(0, 0.4, dz + 2.8), Color3.fromRGB(60, 34, 24), Enum.Material.Leather)
	PartUtil.detail(PartUtil.block(model, origin, "ChairBack", v(2.6, 3.6, 0.6), v(0, 2, dz + 4.1), Color3.fromRGB(60, 34, 24), Enum.Material.Leather))
	for _, x in { -2.5, 2.5 } do
		PartUtil.block(model, origin, "Armchair", v(2.4, 1.6, 2.4), v(x, 0.4, dz - 3.4), ctx.primary, Enum.Material.Leather)
		PartUtil.detail(PartUtil.block(model, origin, "ArmchairBack", v(2.4, 2.2, 0.5), v(x, 1.6, dz - 4.6), ctx.primary, Enum.Material.Leather))
	end
	PartUtil.block(model, origin, "Rug", v(12, 0.06, 9), v(0, 0.4, dz - 1), C.Carpet, Enum.Material.Carpet, { canCollide = false, castShadow = false })
	-- Armoire à trophées contre le mur du fond (trophées réels du club).
	local trophies = (extra and extra.trophies) or {}
	PartUtil.block(model, origin, "Cabinet", v(10, 6, 1.4), v(-size.X / 2 + 7, 0.4, size.Z / 2 - 1.3), C.WoodDark, Enum.Material.Wood)
	for i = 1, math.min(#trophies, 2 + level * 2) do
		local x = -size.X / 2 + 3 + ((i - 1) % 4) * 2.6
		local y = 2.4 + math.floor((i - 1) / 4) * 2.4
		cup(model, origin, v(x, y, size.Z / 2 - 2.2), trophies[i].tier, 0.7)
	end
	if level >= 2 then
		-- Terrasse vitrée au 1er étage.
		local y = 0.4 + size.Y / level
		PartUtil.block(model, origin, "Balcony", v(size.X * 0.6, 0.4, 3), v(0, y, -size.Z / 2 - 1.5), TRIM, Enum.Material.Metal)
		PartUtil.detail(PartUtil.block(model, origin, "BalconyGlass", v(size.X * 0.6, 1.6, 0.15), v(0, y + 0.4, -size.Z / 2 - 2.95), PartUtil.GLASS, Enum.Material.Glass, {
			transparency = 0.5,
		}))
	end
	if level >= 3 then
		-- Héliport sur le toit et grandes lettres dorées « FC » en façade.
		local top = 0.4 + size.Y + 0.6
		PartUtil.cylinder(model, origin, "Helipad", 14, 0.4, v(0, top, 2), Color3.fromRGB(60, 62, 68), Enum.Material.Asphalt)
		PartUtil.detail(PartUtil.block(model, origin, "HelipadH", v(0.8, 0.1, 5), v(-1.4, top + 0.4, 2), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic))
		PartUtil.detail(PartUtil.block(model, origin, "HelipadH", v(0.8, 0.1, 5), v(1.4, top + 0.4, 2), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic))
		PartUtil.detail(PartUtil.block(model, origin, "HelipadH", v(2, 0.1, 0.8), v(0, top + 0.4, 2), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic))
		local letters = PartUtil.box(model, origin, "FCLetters", v(6, 4, 0.4), v(size.X / 2 - 5, size.Y - 5, -size.Z / 2 - 0.5), TRIM, Enum.Material.Metal, { canCollide = false })
		PartUtil.label(letters, Enum.NormalId.Front, "FC", C.Gold)
	end
	return model
end

--------------------------------------------------------------------------------
-- Centre de récupération : piscine, bains chauds et froids, transats, pergola.
--------------------------------------------------------------------------------
function CampusBuildings.Recovery(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Recovery")
	slab(model, origin, Vector2.new(44, 44), Enum.Material.CeramicTiles, Color3.fromRGB(222, 218, 208))
	-- Bâtiment des soins au fond de la parcelle.
	local sizes = { v(14, 9, 10), v(26, 10, 12), v(34, 12, 14) }
	local size = sizes[level] or sizes[1]
	local back = origin * CFrame.new(0, 0, 22 - size.Z / 2 - 0.5)
	PartUtil.shell(model, back, size, {
		wallColor = Color3.fromRGB(226, 222, 212),
		wallMaterial = Enum.Material.Limestone,
		roofColor = C.Roof,
		windows = true,
		glassFront = level >= 2,
		accent = ctx.primary,
		doorWidth = 5,
	})
	sign(model, back, "campus.Recovery.sign", math.min(size.X * 0.6, 16), v(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4), ctx.primary)
	-- Piscine : margelle, eau, lignes d'eau (niveau 3).
	local poolSizes = { Vector2.new(16, 8), Vector2.new(20, 10), Vector2.new(26, 12) }
	local pool = poolSizes[level] or poolSizes[1]
	local pz = -6
	PartUtil.block(model, origin, "PoolEdge", v(pool.X + 2, 0.5, pool.Y + 2), v(0, 0, pz), Color3.fromRGB(236, 232, 224), Enum.Material.Limestone)
	PartUtil.block(model, origin, "PoolWater", v(pool.X, 0.2, pool.Y), v(0, 0.42, pz), WATER, Enum.Material.Glass, { canCollide = false, transparency = 0.15, castShadow = false })
	if level >= 3 then
		for i = 1, 3 do
			PartUtil.detail(PartUtil.block(model, origin, "LaneLine", v(pool.X - 1, 0.12, 0.2), v(0, 0.62, pz - pool.Y / 2 + i * pool.Y / 4), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, {
				canCollide = false,
			}))
		end
	end
	-- Transats le long de la piscine.
	local loungers = level * 2 + 2
	for i = 0, loungers - 1 do
		local x = -pool.X / 2 + 1 + i * (pool.X - 2) / math.max(1, loungers - 1)
		lounger(model, origin, v(x, 0.2, pz - pool.Y / 2 - 4.5))
	end
	-- Bains : bain chaud rond (niveau 2) puis bain froid (niveau 3).
	if level >= 2 then
		PartUtil.cylinder(model, origin, "HotTub", 7, 1.2, v(pool.X / 2 + 5.5, 0.2, pz + 2), Color3.fromRGB(236, 232, 224), Enum.Material.Limestone)
		PartUtil.cylinder(model, origin, "HotTubWater", 6, 0.2, v(pool.X / 2 + 5.5, 1.3, pz + 2), Color3.fromRGB(120, 200, 220), Enum.Material.Glass, {
			canCollide = false,
			transparency = 0.15,
		})
		-- Pergola en bois au-dessus des transats.
		for _, x in { -pool.X / 2, pool.X / 2 } do
			PartUtil.block(model, origin, "PergolaPost", v(0.6, 8, 0.6), v(x, 0.2, pz - pool.Y / 2 - 7.5), C.Wood, Enum.Material.Wood)
		end
		for i = 0, 5 do
			PartUtil.detail(PartUtil.block(model, origin, "PergolaBeam", v(0.4, 0.4, 5), v(-pool.X / 2 + i * pool.X / 5, 8.2, pz - pool.Y / 2 - 5), C.Wood, Enum.Material.Wood))
		end
		PartUtil.block(model, origin, "PergolaRail", v(pool.X + 0.6, 0.5, 0.5), v(0, 7.8, pz - pool.Y / 2 - 7.5), C.Wood, Enum.Material.Wood)
	end
	if level >= 3 then
		PartUtil.block(model, origin, "ColdBath", v(5, 1.2, 4), v(-pool.X / 2 - 4.5, 0.2, pz + 2), Color3.fromRGB(236, 232, 224), Enum.Material.Limestone)
		PartUtil.block(model, origin, "ColdBathWater", v(4, 0.2, 3), v(-pool.X / 2 - 4.5, 1.3, pz + 2), Color3.fromRGB(170, 220, 240), Enum.Material.Ice, { canCollide = false })
		Props.planter(model, origin, -20, -19)
		Props.planter(model, origin, 20, -19)
	end
	return model
end

--------------------------------------------------------------------------------
-- Place des champions : dalle en pierre, fontaine, statues, trophée géant, arche.
--------------------------------------------------------------------------------
function CampusBuildings.Champions(parent: Instance, origin: CFrame, level: number, ctx: BuildContext, extra: Extra?): Model
	local model = PartUtil.model(parent, "Champions")
	slab(model, origin, Vector2.new(44, 44), Enum.Material.Cobblestone, Color3.fromRGB(196, 190, 178))
	PartUtil.block(model, origin, "Inlay", v(18, 0.06, 18), v(0, 0.2, 0), Color3.fromRGB(150, 146, 140), Enum.Material.Granite, { canCollide = false, castShadow = false })
	fountain(model, origin, v(0, 0.2, 0), 10 + level * 2, level)
	-- Bancs et lampadaires aux quatre coins.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Props.bench(model, origin, sx * 15, sz * 9, if sx > 0 then 90 else -90)
			if level >= 2 then
				Props.lamp(model, origin, sx * 19, sz * 19, if sz > 0 then 180 else 0)
			end
		end
	end
	if level >= 2 then
		-- Statues de joueurs en bronze (2 puis 4) tournées vers la fontaine.
		local spots = { v(-12, 0.2, 14), v(12, 0.2, 14), v(-12, 0.2, -14), v(12, 0.2, -14) }
		for i = 1, (if level >= 3 then 4 else 2) do
			statue(model, origin, spots[i], i % 2, if spots[i].Z > 0 then 180 else 0)
		end
		-- Massifs fleuris aux couleurs du club.
		for _, sx in { -1, 1 } do
			PartUtil.block(model, origin, "FlowerBed", v(3, 0.8, 12), v(sx * 20.5, 0.2, 0), Color3.fromRGB(140, 136, 130), Enum.Material.Granite)
			PartUtil.detail(PartUtil.block(model, origin, "Flowers", v(2.4, 0.6, 11.4), v(sx * 20.5, 1, 0), ctx.primary, Enum.Material.LeafyGrass, { canCollide = false }))
		end
	end
	if level >= 3 then
		-- Arche d'entrée « FC » en pierre et trophée géant doré sur colonne.
		for _, sx in { -1, 1 } do
			PartUtil.block(model, origin, "ArchPillar", v(2.4, 12, 2.4), v(sx * 6, 0.2, -21), Color3.fromRGB(210, 204, 192), Enum.Material.Limestone)
		end
		local beam = PartUtil.block(model, origin, "ArchBeam", v(14.4, 2.6, 2.4), v(0, 12.2, -21), Color3.fromRGB(210, 204, 192), Enum.Material.Limestone)
		PartUtil.label(beam, Enum.NormalId.Front, "FC", C.Gold)
		PartUtil.cylinder(model, origin, "TrophyColumn", 2, 8, v(0, 0.2, 18), Color3.fromRGB(220, 216, 208), Enum.Material.Marble)
		cup(model, origin, v(0, 8.2, 18), "gold", 2.6)
		local count = extra and extra.trophies and #extra.trophies or 0
		local plaque = PartUtil.block(model, origin, "Plaque", v(6, 2, 0.3), v(0, 3, 16.9), TRIM, Enum.Material.Metal, { canCollide = false })
		PartUtil.label(plaque, Enum.NormalId.Front, "campus.Champions.plaque", C.Gold, nil, { count = count })
	end
	return model
end

return CampusBuildings
