--!strict
--[[
	Academy — centre de formation du club (jeunes joueurs repérés par les recruteurs).

	Niveau 1 : cabane des recruteurs et petit carré d'herbe avec plots.
	Niveau 2 : bureau enduit et mini-terrain avec deux petits buts.
	Niveau 3 : bâtiment à façade vitrée, mini-terrain clôturé.
	Niveau 4 : internat sur 2 étages, mini-terrain éclairé.
	Niveau 5 : académie du club sur 3 étages, ballon géant sur le toit.

	Placé à gauche de la boutique ; la porte donne sur l'avant (-Z), vers l'allée.
	Bâtiment à gauche (-X), mini-terrain à droite (+X) dans l'empreinte 40 × 22.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Academy = {}

local C = WorldConfig.COLORS

-- Bâtiment (taille, décalage X) et mini-terrain (taille X/Z, centre X) par niveau.
local LEVELS = {
	[1] = { building = Vector3.new(10, 7, 8), bx = -10, field = Vector2.new(14, 10), fx = 9 },
	[2] = { building = Vector3.new(16, 9, 12), bx = -10, field = Vector2.new(16, 14), fx = 10 },
	[3] = { building = Vector3.new(20, 10, 14), bx = -9, field = Vector2.new(16, 14), fx = 11 },
	[4] = { building = Vector3.new(22, 15, 16), bx = -8, field = Vector2.new(15, 16), fx = 12 },
	[5] = { building = Vector3.new(22, 20, 18), bx = -8, field = Vector2.new(14, 18), fx = 12.5 },
}

-- Petit but (deux montants + barre) ouvert vers `facing` (+1 = +X, -1 = -X).
local function miniGoal(parent: Instance, origin: CFrame, x: number, facing: number)
	local goal = PartUtil.model(parent, "MiniGoal")
	for _, sz in { -1, 1 } do
		PartUtil.block(goal, origin, "Post", Vector3.new(0.3, 2.4, 0.3), Vector3.new(x, 0.3, sz * 2), C.Line, Enum.Material.Metal)
	end
	PartUtil.block(goal, origin, "Bar", Vector3.new(0.3, 0.3, 4.3), Vector3.new(x, 2.7, 0), C.Line, Enum.Material.Metal)
	PartUtil.block(goal, origin, "Net", Vector3.new(1.2, 2.4, 4), Vector3.new(x - facing * 0.75, 0.3, 0), C.GoalNet, Enum.Material.Fabric, { transparency = 0.5, canCollide = false })
end

-- Mini-terrain : herbe, lignes de touche, ligne médiane, buts selon le niveau.
local function miniField(parent: Instance, origin: CFrame, size: Vector2, level: number, ctx: BuildContext)
	local field = PartUtil.model(parent, "MiniField")
	PartUtil.block(field, origin, "Grass", Vector3.new(size.X, 0.3, size.Y), Vector3.zero, C.PitchGrassLight, Enum.Material.Grass, { castShadow = false })
	if level <= 1 then
		-- Plots d'entraînement en slalom.
		for i = 0, 3 do
			PartUtil.block(field, origin, "Cone", Vector3.new(0.6, 0.9, 0.6), Vector3.new(-4.5 + i * 3, 0.3, if i % 2 == 0 then -1.5 else 1.5), C.Cone, Enum.Material.SmoothPlastic, { canCollide = false })
		end
		return
	end
	local w, d = size.X, size.Y
	local lineY = 0.31
	for _, sz in { -1, 1 } do
		PartUtil.block(field, origin, "Line", Vector3.new(w - 1, 0.04, 0.2), Vector3.new(0, lineY, sz * (d / 2 - 0.5)), C.Line, Enum.Material.SmoothPlastic, { canCollide = false, castShadow = false })
	end
	PartUtil.block(field, origin, "Line", Vector3.new(0.2, 0.04, d - 1), Vector3.new(0, lineY, 0), C.Line, Enum.Material.SmoothPlastic, { canCollide = false, castShadow = false })
	miniGoal(field, origin, -w / 2 + 1, 1)
	miniGoal(field, origin, w / 2 - 1, -1)
	-- Niveau 3 et plus : clôture basse sur les longueurs, aux couleurs du club.
	if level >= 3 then
		for _, sz in { -1, 1 } do
			PartUtil.block(field, origin, "Fence", Vector3.new(w, 1.2, 0.2), Vector3.new(0, 0.3, sz * (d / 2 - 0.1)), ctx.primary, Enum.Material.Metal, { transparency = 0.2 })
		end
	end
	-- Niveau 4 et plus : deux mâts d'éclairage aux coins arrière.
	if level >= 4 then
		for _, sx in { -1, 1 } do
			PartUtil.block(field, origin, "LightPole", Vector3.new(0.4, 10, 0.4), Vector3.new(sx * (w / 2 - 0.5), 0.3, d / 2 - 0.5), C.MetalDark, Enum.Material.Metal)
			PartUtil.block(field, origin, "LightHead", Vector3.new(1.6, 0.8, 0.6), Vector3.new(sx * (w / 2 - 0.5), 10.3, d / 2 - 0.9), C.LightHead, Enum.Material.Neon, { canCollide = false })
		end
	end
end

function Academy.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Academy", { Facility = "Academy", Level = level })
	local spec = LEVELS[level] or LEVELS[1]
	local size = spec.building
	local height = size.Y + (if level >= 5 then 5 else 1)
	PartUtil.anchor(model, origin, Vector2.new(40, 22), height)

	local buildingOrigin = origin * CFrame.new(spec.bx, 0, 0)
	if level <= 1 then
		-- Cabane en bois des recruteurs.
		PartUtil.shell(model, buildingOrigin, size, {
			wallColor = C.Wood,
			wallMaterial = Enum.Material.WoodPlanks,
			roofColor = C.WoodDark,
			doorWidth = 3,
			windows = true,
			roofOverhang = 0.5,
		})
	else
		PartUtil.shell(model, buildingOrigin, size, {
			wallColor = if level >= 4 then C.Concrete elseif level == 3 then C.Plaster else C.Brick,
			wallMaterial = if level == 2 then Enum.Material.Brick else Enum.Material.SmoothPlastic,
			roofColor = C.Roof,
			windows = true,
			glassFront = level >= 3,
			accent = ctx.primary,
			roofOverhang = 1,
			doorWidth = if level >= 4 then 7 else 5,
			floors = if level >= 5 then 3 elseif level >= 4 then 2 else nil,
		})
	end
	-- Banc des recruteurs devant la façade, côté terrain.
	PartUtil.block(model, origin, "Bench", Vector3.new(4, 0.6, 1.2), Vector3.new(spec.bx + size.X / 2 - 2.5, 0.4, -size.Z / 2 - 1.2), C.Wood, Enum.Material.WoodPlanks)

	miniField(model, origin * CFrame.new(spec.fx, 0, 0), spec.field, level, ctx)

	-- Niveau 5 : ballon géant blanc sur le toit, posé sur un socle aux couleurs du club.
	if level >= 5 then
		PartUtil.block(model, buildingOrigin, "BallBase", Vector3.new(3, 1, 3), Vector3.new(0, 0.4 + size.Y + 0.6, 0), ctx.secondary, Enum.Material.Metal)
		PartUtil.ball(model, buildingOrigin, "GiantBall", 3.6, Vector3.new(0, 0.4 + size.Y + 3.4, 0), C.Line, Enum.Material.SmoothPlastic)
	end

	PartUtil.frontSign(
		model,
		buildingOrigin,
		"world.academy",
		Vector2.new(math.min(size.X * 0.8, 16), if level <= 1 then 1.2 else 1.8),
		Vector3.new(0, 0.4 + size.Y - (if level <= 1 then 1.2 else 1.8), -size.Z / 2 - 0.4),
		C.SignText,
		C.SignBack
	)
	return model
end

return Academy
