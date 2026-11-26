--!strict
--[[
	VipLounge — espace VIP du club (loges et salon des invités de marque).

	Niveau 1 : tente d'accueil, tapis rouge et cordons dorés.
	Niveau 2 : salon VIP enduit, bandeau doré.
	Niveau 3 : salon à façade vitrée avec terrasse sur le toit.
	Niveau 4 : club house sur 2 étages, terrasse avec parasols.
	Niveau 5 : pavillon prestige : bandeau lumineux doré, couronne sur le toit.

	Placé à droite de l'entrée, face au stade ; la porte donne sur l'avant (-Z)
	et le tapis rouge descend jusqu'à l'allée. Empreinte 30 × 22.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local VipLounge = {}

local C = WorldConfig.COLORS

-- Taille du bâtiment (largeur, hauteur des murs, profondeur) par niveau.
local SIZES = {
	[1] = Vector3.new(12, 7, 8),
	[2] = Vector3.new(18, 9, 12),
	[3] = Vector3.new(22, 10, 14),
	[4] = Vector3.new(26, 15, 16),
	[5] = Vector3.new(27, 18, 16),
}
-- Le bâtiment est reculé de BACK_SHIFT pour laisser la place au tapis rouge.
local BACK_SHIFT = 1.5
local FRONT_EDGE = -11 -- bord avant de l'empreinte

-- Tapis rouge de la porte jusqu'au bord de l'empreinte, cordons dorés de chaque côté.
local function redCarpet(parent: Instance, origin: CFrame, frontZ: number, width: number)
	local length = frontZ - FRONT_EDGE
	if length <= 0.5 then
		return
	end
	local midZ = (frontZ + FRONT_EDGE) / 2
	PartUtil.block(parent, origin, "RedCarpet", Vector3.new(width, 0.1, length), Vector3.new(0, 0, midZ), C.Carpet, Enum.Material.Fabric, { castShadow = false })
	for _, sx in { -1, 1 } do
		local x = sx * (width / 2 + 0.6)
		for _, z in { frontZ - 0.5, FRONT_EDGE + 0.5 } do
			PartUtil.block(parent, origin, "RopePost", Vector3.new(0.4, 2.2, 0.4), Vector3.new(x, 0, z), C.Gold, Enum.Material.Metal)
		end
		PartUtil.box(parent, origin, "Rope", Vector3.new(0.2, 0.2, length - 1), Vector3.new(x, 1.8, midZ), C.Carpet, Enum.Material.Fabric, { canCollide = false })
	end
end

-- Parasol carré (mât + toile) posé en `base`.
local function parasol(parent: Instance, origin: CFrame, base: Vector3, color: Color3)
	PartUtil.block(parent, origin, "ParasolPole", Vector3.new(0.3, 3.2, 0.3), base, C.MetalDark, Enum.Material.Metal)
	PartUtil.block(parent, origin, "ParasolTop", Vector3.new(4, 0.3, 4), base + Vector3.new(0, 3.2, 0), color, Enum.Material.Fabric, { canCollide = false })
end

-- Terrasse sur le toit : garde-corps vitré et, dès le niveau 4, parasols.
local function roofTerrace(parent: Instance, origin: CFrame, size: Vector3, level: number, ctx: BuildContext)
	local top = 0.4 + size.Y + 0.6
	local w, d = size.X - 1, size.Z - 1
	for _, sz in { -1, 1 } do
		PartUtil.block(parent, origin, "Railing", Vector3.new(w, 1.4, 0.2), Vector3.new(0, top, sz * d / 2), C.Glass, Enum.Material.Glass, { transparency = 0.5 })
	end
	for _, sx in { -1, 1 } do
		PartUtil.block(parent, origin, "Railing", Vector3.new(0.2, 1.4, d), Vector3.new(sx * w / 2, top, 0), C.Glass, Enum.Material.Glass, { transparency = 0.5 })
	end
	if level >= 4 then
		for _, sx in { -1, 1 } do
			parasol(parent, origin, Vector3.new(sx * w / 4, top, -d / 4), if sx < 0 then ctx.primary else ctx.secondary)
		end
	end
end

-- Niveau 1 : tente d'accueil (plancher, 4 mâts, toit aux couleurs du club, liseré doré).
local function buildTent(model: Model, origin: CFrame, size: Vector3, ctx: BuildContext)
	local w, h, d = size.X, size.Y, size.Z
	PartUtil.block(model, origin, "Floor", Vector3.new(w, 0.4, d), Vector3.zero, C.WoodDark, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartUtil.block(model, origin, "Post", Vector3.new(0.4, h, 0.4), Vector3.new(sx * (w / 2 - 0.2), 0.4, sz * (d / 2 - 0.2)), C.Plaster, Enum.Material.Metal)
		end
	end
	PartUtil.block(model, origin, "BackDrop", Vector3.new(w, h, 0.2), Vector3.new(0, 0.4, d / 2 - 0.1), ctx.primary, Enum.Material.Fabric)
	PartUtil.block(model, origin, "TentRoof", Vector3.new(w + 0.6, 0.6, d + 0.6), Vector3.new(0, 0.4 + h, 0), C.Plaster, Enum.Material.Fabric)
	PartUtil.block(model, origin, "GoldTrim", Vector3.new(w + 0.8, 0.3, d + 0.8), Vector3.new(0, 0.4 + h - 0.3, 0), C.Gold, Enum.Material.Metal, { canCollide = false })
	-- Comptoir d'accueil et deux fauteuils.
	PartUtil.block(model, origin, "Desk", Vector3.new(4, 2.6, 1.2), Vector3.new(0, 0.4, 1), C.WoodDark, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		PartUtil.block(model, origin, "Armchair", Vector3.new(1.6, 1.4, 1.6), Vector3.new(sx * 3.8, 0.4, 0.5), C.Carpet, Enum.Material.Fabric)
	end
end

function VipLounge.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "VIP", { Facility = "VIP", Level = level })
	local size = SIZES[level] or SIZES[1]
	local height = size.Y + (if level >= 3 then 4 else 1.5)
	PartUtil.anchor(model, origin, Vector2.new(30, 22), height)

	local buildingOrigin = origin * CFrame.new(0, 0, BACK_SHIFT)
	local frontZ = BACK_SHIFT - size.Z / 2
	if level <= 1 then
		buildTent(model, buildingOrigin, size, ctx)
	else
		PartUtil.shell(model, buildingOrigin, size, {
			wallColor = if level >= 4 then C.ConcreteDark else C.Plaster,
			wallMaterial = if level >= 4 then Enum.Material.Slate else Enum.Material.Plaster,
			roofColor = C.Roof,
			windows = true,
			glassFront = level >= 3,
			accent = C.Gold,
			roofOverhang = if level >= 4 then 1 else 0.5,
			doorWidth = if level >= 4 then 6 else 4,
			floors = if level >= 4 then 2 else nil,
		})
		-- Auvent doré au-dessus de la porte.
		PartUtil.block(model, buildingOrigin, "Canopy", Vector3.new(8, 0.4, 2), Vector3.new(0, 8, -size.Z / 2 - 1), C.Gold, Enum.Material.Metal, { canCollide = false })
	end
	redCarpet(model, origin, frontZ, if level >= 4 then 5 else 3.5)

	if level >= 3 then
		roofTerrace(model, buildingOrigin, size, level, ctx)
	end
	-- Niveau 5 : bandeau lumineux doré et couronne sur le toit.
	if level >= 5 then
		PartUtil.block(model, buildingOrigin, "LightStrip", Vector3.new(size.X + 0.4, 0.5, 0.3), Vector3.new(0, 0.4 + size.Y / 2 - 0.6, -size.Z / 2 - 0.3), C.Gold, Enum.Material.Neon, { canCollide = false })
		local crownBase = Vector3.new(0, 0.4 + size.Y + 0.6, size.Z / 4)
		PartUtil.block(model, buildingOrigin, "CrownBand", Vector3.new(4, 1, 1), crownBase, C.Gold, Enum.Material.Metal)
		for i = -1, 1 do
			PartUtil.block(model, buildingOrigin, "CrownPoint", Vector3.new(0.8, if i == 0 then 2.2 else 1.6, 0.8), crownBase + Vector3.new(i * 1.6, 1, 0), C.Gold, Enum.Material.Metal)
		end
	end

	PartUtil.frontSign(
		model,
		buildingOrigin,
		"world.vip",
		Vector2.new(math.min(size.X * 0.6, 14), if level <= 1 then 1.2 else 1.8),
		Vector3.new(0, if level <= 1 then 0.4 + size.Y + 1.3 else 0.4 + size.Y - 1.8, -size.Z / 2 - 0.4),
		C.Gold,
		C.SignBack
	)
	return model
end

return VipLounge
