--!strict
--[[
	Shop — boutique du club (maillots, écharpes, souvenirs).

	Niveau 1 : kiosque en bois avec auvent rayé aux couleurs du club.
	Niveau 2 : petite boutique enduite, vitrine et auvent.
	Niveau 3 : magasin à façade vitrée, mannequins portant le maillot du club.
	Niveau 4 : grand magasin sur 2 étages.
	Niveau 5 : boutique officielle : maillot géant sur le toit, bandeau lumineux.

	Placée à gauche de l'entrée du club ; la porte donne sur l'avant (-Z), vers
	l'allée qui part du portique d'entrée.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Shop = {}

local C = WorldConfig.COLORS

-- Taille (largeur, hauteur des murs, profondeur) des niveaux 2 à 5.
local SIZES = {
	[2] = Vector3.new(16, 10, 10),
	[3] = Vector3.new(24, 11, 12),
	[4] = Vector3.new(30, 16, 14),
	[5] = Vector3.new(36, 18, 16),
}

-- Maillot simplifié (corps + manches) tourné vers l'avant (-Z), posé en `base`.
local function jersey(parent: Instance, origin: CFrame, base: Vector3, scale: number, ctx: BuildContext)
	local shirt = PartUtil.model(parent, "Jersey")
	local bodyW, bodyH = 2 * scale, 2.4 * scale
	PartUtil.block(shirt, origin, "Body", Vector3.new(bodyW, bodyH, 0.4 * scale), base, ctx.primary, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		PartUtil.box(
			shirt,
			origin,
			"Sleeve",
			Vector3.new(1.1 * scale, 0.7 * scale, 0.4 * scale),
			base + Vector3.new(side * (bodyW / 2 + 0.4 * scale), bodyH - 0.5 * scale, 0),
			ctx.primary,
			Enum.Material.Fabric,
			{ rotZ = side * -25 }
		)
	end
	-- Bande horizontale à la couleur secondaire.
	PartUtil.block(
		shirt,
		origin,
		"Stripe",
		Vector3.new(bodyW + 0.05, 0.5 * scale, 0.45 * scale),
		base + Vector3.new(0, bodyH * 0.45, 0),
		ctx.secondary,
		Enum.Material.Fabric
	)
end

-- Niveau 1 : kiosque (comptoir, montants, auvent rayé, présentoir de maillots).
local function buildKiosk(model: Model, origin: CFrame, ctx: BuildContext)
	local w, d = 10, 6
	PartUtil.block(model, origin, "Floor", Vector3.new(w, 0.4, d), Vector3.zero, C.WoodDark, Enum.Material.WoodPlanks)
	PartUtil.block(model, origin, "Counter", Vector3.new(w, 3, 1), Vector3.new(0, 0.4, -d / 2 + 0.5), C.Wood, Enum.Material.WoodPlanks)
	PartUtil.block(model, origin, "BackWall", Vector3.new(w, 7, 0.4), Vector3.new(0, 0.4, d / 2 - 0.2), C.Wood, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		PartUtil.block(model, origin, "Post", Vector3.new(0.4, 7, 0.4), Vector3.new(sx * (w / 2 - 0.2), 0.4, -d / 2 + 0.2), C.WoodDark, Enum.Material.WoodPlanks)
	end
	-- Auvent rayé : 5 bandes alternées, légèrement incliné vers l'avant.
	local stripes = 5
	for i = 0, stripes - 1 do
		PartUtil.box(
			model,
			origin,
			"Awning",
			Vector3.new(w / stripes, 0.3, d + 1.5),
			Vector3.new(-w / 2 + w / stripes * (i + 0.5), 7.8, -0.5),
			if i % 2 == 0 then ctx.primary else ctx.secondary,
			Enum.Material.Fabric,
			{ rotX = 8 }
		)
	end
	jersey(model, origin, Vector3.new(-2.5, 3.2, d / 2 - 0.6), 1, ctx)
	jersey(model, origin, Vector3.new(2.5, 3.2, d / 2 - 0.6), 1, ctx)
	return Vector3.new(w, 9, d)
end

function Shop.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Shop", { Facility = "Shop", Level = level })
	local size = SIZES[level]
	if level <= 1 or not size then
		local kiosk = buildKiosk(model, origin, ctx)
		PartUtil.anchor(model, origin, Vector2.new(kiosk.X, kiosk.Z), kiosk.Y)
		PartUtil.frontSign(
			model,
			origin,
			"world.shop",
			Vector2.new(6, 1.2),
			Vector3.new(0, 8.4, -4.6),
			C.SignText,
			C.SignBack
		)
		return model
	end
	PartUtil.anchor(model, origin, Vector2.new(size.X, size.Z), size.Y)

	local style: PartUtil.ShellStyle
	if level == 2 then
		style = {
			wallColor = C.Plaster,
			wallMaterial = Enum.Material.Plaster,
			roofColor = C.Roof,
			windows = true,
			accent = ctx.primary,
			roofOverhang = 0.5,
		}
	else
		style = {
			wallColor = if level >= 4 then C.Charcoal else C.Plaster,
			wallMaterial = if level >= 4 then Enum.Material.Metal else Enum.Material.SmoothPlastic,
			roofColor = C.Roof,
			windows = true,
			glassFront = true,
			accent = if level >= 4 then C.Gold else ctx.primary,
			canopy = level >= 4,
			roofOverhang = if level >= 5 then 1.5 else 1,
			doorWidth = if level >= 4 then 8 else 6,
			floors = if level >= 4 then 2 else nil,
		}
	end
	PartUtil.shell(model, origin, size, style)

	-- Présentoirs : un portant de maillots par tranche de 8 studs le long du fond.
	local racks = math.floor(size.X / 8)
	for i = 0, racks - 1 do
		local x = -size.X / 2 + 4 + i * 8
		PartUtil.block(model, origin, "Rack", Vector3.new(5, 0.4, 1), Vector3.new(x, 4.6, size.Z / 2 - 1.4), C.Metal, Enum.Material.Metal)
		jersey(model, origin, Vector3.new(x, 1.4, size.Z / 2 - 1.4), 1, ctx)
	end
	-- Niveau 2 : auvent au-dessus de la vitrine.
	if level == 2 then
		PartUtil.block(model, origin, "Canopy", Vector3.new(size.X - 2, 0.4, 2.5), Vector3.new(0, 8.6, -size.Z / 2 - 1.25), ctx.primary, Enum.Material.Fabric)
	end
	-- Niveau 3 et plus : mannequins en maillot derrière la vitrine.
	if level >= 3 then
		for _, sx in { -1, 1 } do
			local x = sx * (size.X / 4 + 1)
			PartUtil.block(model, origin, "MannequinBase", Vector3.new(1.4, 0.3, 1.4), Vector3.new(x, 0.4, -size.Z / 2 + 2), C.MetalDark, Enum.Material.Metal)
			jersey(model, origin, Vector3.new(x, 0.7, -size.Z / 2 + 2), 1.2, ctx)
			PartUtil.ball(model, origin, "MannequinHead", 1.2, Vector3.new(x, 4.3, -size.Z / 2 + 2), C.Plaster, Enum.Material.SmoothPlastic)
		end
	end
	-- Niveau 5 : maillot géant sur le toit et bandeau lumineux en façade.
	if level >= 5 then
		jersey(model, origin, Vector3.new(0, 0.4 + size.Y + 0.6, 0), 4, ctx)
		PartUtil.block(
			model,
			origin,
			"LightStrip",
			Vector3.new(size.X + 0.4, 0.5, 0.3),
			Vector3.new(0, 0.4 + size.Y / 2 - 0.6, -size.Z / 2 - 0.3),
			ctx.secondary,
			Enum.Material.Neon,
			{ canCollide = false }
		)
	end

	PartUtil.frontSign(
		model,
		origin,
		"world.shop",
		Vector2.new(math.min(size.X * 0.6, 18), 1.8),
		Vector3.new(0, 0.4 + size.Y - 1.8, -size.Z / 2 - 0.4),
		C.SignText,
		C.SignBack
	)
	return model
end

return Shop
