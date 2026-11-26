--!strict
--[[
	TrainingZone — zone d'entraînement (identifiant d'installation : « Training »).

	Niveau 1 : petit carré d'herbe avec des plots (cônes) en slalom.
	Niveau 2 : surface plus grande, mini-buts et mannequins d'entraînement.
	Niveau 3 : terrain d'entraînement délimité (lignes, clôture basse) + abri couvert.

	L'origine reçue est le centre de la zone, posé sur le sol du terrain de club.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local TrainingZone = {}

local C = WorldConfig.COLORS

-- Surface d'herbe (X, Z) par niveau ; le niveau 3 occupe toute l'empreinte.
local SURFACES = {
	[1] = Vector2.new(24, 24),
	[2] = Vector2.new(40, 30),
	[3] = Vector2.new(52, 36),
}

local function cone(model: Model, origin: CFrame, x: number, z: number)
	PartUtil.cylinder(model, origin, "Cone", 0.9, 1.2, Vector3.new(x, 0.3, z), C.Cone, Enum.Material.SmoothPlastic, {
		canCollide = false,
	})
end

local function miniGoal(model: Model, origin: CFrame, x: number, facing: number)
	local o = origin * CFrame.new(x, 0.3, 0) * CFrame.Angles(0, math.rad(facing), 0)
	local goal = PartUtil.model(model, "MiniGoal")
	local width, height = 6, 3
	for _, side in { -1, 1 } do
		PartUtil.block(goal, o, "Post", Vector3.new(0.3, height, 0.3), Vector3.new(0, 0, side * width / 2), C.Line, Enum.Material.Metal)
	end
	PartUtil.box(goal, o, "Crossbar", Vector3.new(0.3, 0.3, width + 0.3), Vector3.new(0, height - 0.15, 0), C.Line, Enum.Material.Metal)
	PartUtil.block(
		goal,
		o,
		"Net",
		Vector3.new(0.1, height * 0.8, width),
		Vector3.new(2, 0, 0),
		C.GoalNet,
		Enum.Material.Fabric,
		{ transparency = 0.55, castShadow = false }
	)
end

local function mannequin(model: Model, origin: CFrame, x: number, z: number)
	local m = PartUtil.model(model, "Mannequin")
	PartUtil.block(m, origin, "Base", Vector3.new(1.6, 0.3, 1.6), Vector3.new(x, 0.3, z), C.MetalDark, Enum.Material.Metal)
	PartUtil.block(m, origin, "Body", Vector3.new(1.6, 4, 0.6), Vector3.new(x, 0.6, z), C.Mannequin, Enum.Material.SmoothPlastic)
	PartUtil.ball(m, origin, "Head", 1.2, Vector3.new(x, 5.3, z), C.Mannequin, Enum.Material.SmoothPlastic)
end

function TrainingZone.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Training", { Facility = "Training", Level = level })
	PartUtil.anchor(model, origin, WorldConfig.LAYOUT.Training.footprint, 1)

	local surface = SURFACES[level] or SURFACES[1]
	PartUtil.block(
		model,
		origin,
		"Turf",
		Vector3.new(surface.X, 0.3, surface.Y),
		Vector3.zero,
		C.PitchGrassLight,
		Enum.Material.Grass
	)

	-- Slalom de plots (tous niveaux).
	for i = 0, 7 do
		cone(model, origin, -8.75 + i * 2.5, if i % 2 == 0 then -6 else -3)
	end

	if level >= 2 then
		miniGoal(model, origin, -surface.X / 2 + 3, 180)
		miniGoal(model, origin, surface.X / 2 - 3, 0)
		for i = 0, 3 do
			mannequin(model, origin, -6 + i * 4, 6)
		end
	end

	if level >= 3 then
		-- Lignes de délimitation et ligne médiane.
		local hx, hz = surface.X / 2 - 1, surface.Y / 2 - 1
		local y = 0.33
		local w = 0.3
		PartUtil.line(model, origin, "Line", Vector2.new(-hx, -hz), Vector2.new(hx, -hz), w, y, C.Line)
		PartUtil.line(model, origin, "Line", Vector2.new(-hx, hz), Vector2.new(hx, hz), w, y, C.Line)
		PartUtil.line(model, origin, "Line", Vector2.new(-hx, -hz), Vector2.new(-hx, hz), w, y, C.Line)
		PartUtil.line(model, origin, "Line", Vector2.new(hx, -hz), Vector2.new(hx, hz), w, y, C.Line)
		PartUtil.line(model, origin, "Line", Vector2.new(0, -hz), Vector2.new(0, hz), w, y, C.Line)

		-- Clôture basse autour de la zone (ouverte côté -X pour l'accès depuis l'allée).
		local fx, fz = WorldConfig.LAYOUT.Training.footprint.X / 2 - 0.5, WorldConfig.LAYOUT.Training.footprint.Y / 2 - 0.5
		local fenceH = 2.5
		local fence = { transparency = 0.1 }
		PartUtil.block(model, origin, "Fence", Vector3.new(2 * fx, fenceH, 0.3), Vector3.new(0, 0, -fz), C.MetalDark, Enum.Material.Metal, fence)
		PartUtil.block(model, origin, "Fence", Vector3.new(2 * fx, fenceH, 0.3), Vector3.new(0, 0, fz), C.MetalDark, Enum.Material.Metal, fence)
		PartUtil.block(model, origin, "Fence", Vector3.new(0.3, fenceH, 2 * fz), Vector3.new(fx, 0, 0), C.MetalDark, Enum.Material.Metal, fence)
		-- Côté -X : deux morceaux avec une ouverture au milieu.
		for _, sz in { -1, 1 } do
			PartUtil.block(
				model,
				origin,
				"Fence",
				Vector3.new(0.3, fenceH, fz - 3),
				Vector3.new(-fx, 0, sz * (fz + 3) / 2),
				C.MetalDark,
				Enum.Material.Metal,
				fence
			)
		end

		-- Abri couvert dans l'angle arrière droit (+X, +Z), hors de la surface de jeu.
		local shelter = PartUtil.model(model, "Shelter")
		local so = origin * CFrame.new(fx - 5.5, 0, fz - 1.6)
		for _, px in { -4.5, 4.5 } do
			PartUtil.block(shelter, so, "Post", Vector3.new(0.4, 4, 0.4), Vector3.new(px, 0, -0.6), C.Metal, Enum.Material.Metal)
		end
		PartUtil.block(shelter, so, "BackPanel", Vector3.new(9.4, 4, 0.3), Vector3.new(0, 0, 0.6), C.MetalDark, Enum.Material.Metal)
		PartUtil.block(shelter, so, "Roof", Vector3.new(10, 0.3, 2.4), Vector3.new(0, 4, 0), ctx.primary, Enum.Material.SmoothPlastic)
		PartUtil.block(shelter, so, "Bench", Vector3.new(8, 1.4, 0.8), Vector3.new(0, 0, 0.1), ctx.secondary, Enum.Material.SmoothPlastic)
	end
	return model
end

return TrainingZone
