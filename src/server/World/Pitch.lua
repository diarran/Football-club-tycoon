--!strict
--[[
	Pitch — terrain principal du club.

	Niveau 1 : terrain amateur (pelouse à bandes de tonte, lignes, buts, drapeaux de coin).
	Niveau 2 : + bancs de touche abrités et panneaux publicitaires fictifs.
	Niveau 3 : + éclairage : 4 pylônes d'angle équipés de projecteurs (SpotLight).

	L'origine reçue est le centre du terrain, posé sur le sol du terrain de club.
	Le terrain est allongé selon X (longueur) ; -Z = côté entrée (bancs de touche).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Pitch = {}

local C = WorldConfig.COLORS
local GRASS = Enum.Material.Grass
local LINE_W = 0.4 -- épaisseur des lignes blanches
local LINE_Y = 0.43 -- hauteur des lignes (juste au-dessus des bandes de tonte)

-- Dimensions réglementaires réduites à l'échelle du terrain (≈ 0,95 stud par mètre).
local PENALTY_AREA = Vector2.new(16, 38) -- profondeur, largeur
local GOAL_AREA = Vector2.new(5.2, 17.4)
local PENALTY_SPOT = 10.5 -- distance depuis la ligne de but
local CIRCLE_RADIUS = 8.7
local GOAL_WIDTH = 16
local GOAL_HEIGHT = 6.5
local GOAL_DEPTH = 5

-- Pelouse : bande d'herbe extérieure + bandes de tonte alternées + lignes.
local function buildTurf(model: Model, origin: CFrame)
	local L, W = WorldConfig.PITCH_SIZE.X, WorldConfig.PITCH_SIZE.Y
	local runoff = WorldConfig.PITCH_RUNOFF

	PartUtil.block(
		model,
		origin,
		"Surround",
		Vector3.new(L + 2 * runoff, 0.3, W + 2 * runoff),
		Vector3.zero,
		C.PitchGrassDark,
		GRASS
	)

	local stripes = WorldConfig.PITCH_STRIPES
	local stripeLength = L / stripes
	for i = 0, stripes - 1 do
		local x = -L / 2 + stripeLength * (i + 0.5)
		local color = if i % 2 == 0 then C.PitchGrassLight else C.PitchGrassDark
		PartUtil.block(
			model,
			origin,
			"Stripe",
			Vector3.new(stripeLength, 0.35, W),
			Vector3.new(x, 0.05, 0),
			color,
			GRASS
		)
	end

	local hx, hz = L / 2, W / 2
	local white = C.Line
	local function line(a: Vector2, b: Vector2)
		PartUtil.line(model, origin, "Line", a, b, LINE_W, LINE_Y, white)
	end
	local function spot(x: number)
		PartUtil.box(
			model,
			origin,
			"Spot",
			Vector3.new(0.9, 0.05, 0.9),
			Vector3.new(x, LINE_Y, 0),
			white,
			Enum.Material.SmoothPlastic,
			{ canCollide = false, castShadow = false }
		)
	end

	-- Lignes de touche, lignes de but, ligne médiane.
	line(Vector2.new(-hx, -hz), Vector2.new(hx, -hz))
	line(Vector2.new(-hx, hz), Vector2.new(hx, hz))
	line(Vector2.new(-hx, -hz), Vector2.new(-hx, hz))
	line(Vector2.new(hx, -hz), Vector2.new(hx, hz))
	line(Vector2.new(0, -hz), Vector2.new(0, hz))

	-- Rond central et point central.
	PartUtil.arc(model, origin, "Line", Vector2.zero, CIRCLE_RADIUS, 0, 360, 16, LINE_W, LINE_Y, white)
	spot(0)

	-- Surfaces de réparation, surfaces de but, points et arcs de penalty (des deux côtés).
	local arcHalfAngle = math.deg(math.acos((PENALTY_AREA.X - PENALTY_SPOT) / CIRCLE_RADIUS))
	for _, side in { -1, 1 } do
		local goalX = side * hx
		local boxX = side * (hx - PENALTY_AREA.X)
		local pw = PENALTY_AREA.Y / 2
		line(Vector2.new(boxX, -pw), Vector2.new(boxX, pw))
		line(Vector2.new(goalX, -pw), Vector2.new(boxX, -pw))
		line(Vector2.new(goalX, pw), Vector2.new(boxX, pw))

		local sixX = side * (hx - GOAL_AREA.X)
		local gw = GOAL_AREA.Y / 2
		line(Vector2.new(sixX, -gw), Vector2.new(sixX, gw))
		line(Vector2.new(goalX, -gw), Vector2.new(sixX, -gw))
		line(Vector2.new(goalX, gw), Vector2.new(sixX, gw))

		local spotX = side * (hx - PENALTY_SPOT)
		spot(spotX)
		-- L'arc est tourné vers le centre du terrain (angle 0° si côté gauche, 180° si droit).
		local facing = if side < 0 then 0 else 180
		PartUtil.arc(
			model,
			origin,
			"Line",
			Vector2.new(spotX, 0),
			CIRCLE_RADIUS,
			facing - arcHalfAngle,
			facing + arcHalfAngle,
			5,
			LINE_W,
			LINE_Y,
			white
		)
	end
end

-- Un but : deux poteaux, une barre, filets simplifiés (semi-transparents).
local function buildGoal(model: Model, origin: CFrame, side: number)
	local hx = WorldConfig.PITCH_SIZE.X / 2
	-- Repère du but : centre de la ligne de but, axe +X local vers l'extérieur du terrain.
	local goalOrigin = origin * CFrame.new(side * hx, 0.4, 0) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
	local goal = PartUtil.model(model, "Goal")
	local white = C.GoalNet
	local metal = Enum.Material.Metal
	local post = 0.5
	local hw = GOAL_WIDTH / 2

	PartUtil.block(goal, goalOrigin, "Post", Vector3.new(post, GOAL_HEIGHT, post), Vector3.new(0, 0, -hw), white, metal)
	PartUtil.block(goal, goalOrigin, "Post", Vector3.new(post, GOAL_HEIGHT, post), Vector3.new(0, 0, hw), white, metal)
	PartUtil.box(
		goal,
		goalOrigin,
		"Crossbar",
		Vector3.new(post, post, GOAL_WIDTH + post),
		Vector3.new(0, GOAL_HEIGHT - post / 2, 0),
		white,
		metal
	)

	local net = { transparency = 0.55, castShadow = false }
	local netMat = Enum.Material.Fabric
	PartUtil.block(
		goal,
		goalOrigin,
		"NetBack",
		Vector3.new(0.1, GOAL_HEIGHT * 0.8, GOAL_WIDTH),
		Vector3.new(GOAL_DEPTH, 0, 0),
		white,
		netMat,
		net
	)
	PartUtil.block(
		goal,
		goalOrigin,
		"NetSide",
		Vector3.new(GOAL_DEPTH, GOAL_HEIGHT * 0.8, 0.1),
		Vector3.new(GOAL_DEPTH / 2, 0, -hw),
		white,
		netMat,
		net
	)
	PartUtil.block(
		goal,
		goalOrigin,
		"NetSide",
		Vector3.new(GOAL_DEPTH, GOAL_HEIGHT * 0.8, 0.1),
		Vector3.new(GOAL_DEPTH / 2, 0, hw),
		white,
		netMat,
		net
	)
	-- Filet supérieur légèrement incliné entre la barre et l'arrière.
	local topLength = math.sqrt(GOAL_DEPTH ^ 2 + (GOAL_HEIGHT * 0.2) ^ 2)
	local tilt = math.deg(math.atan2(GOAL_HEIGHT * 0.2, GOAL_DEPTH))
	PartUtil.box(
		goal,
		goalOrigin,
		"NetTop",
		Vector3.new(topLength, 0.1, GOAL_WIDTH),
		Vector3.new(GOAL_DEPTH / 2, GOAL_HEIGHT * 0.9, 0),
		white,
		netMat,
		{ transparency = 0.55, castShadow = false, rotZ = -tilt }
	)
end

-- Drapeaux de coin (poteau + fanion aux couleurs du club).
local function buildCornerFlags(model: Model, origin: CFrame, ctx: BuildContext)
	local hx, hz = WorldConfig.PITCH_SIZE.X / 2, WorldConfig.PITCH_SIZE.Y / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local base = Vector3.new(sx * hx, 0.4, sz * hz)
			PartUtil.cylinder(model, origin, "CornerPole", 0.2, 3.5, base, C.Line, Enum.Material.SmoothPlastic, {
				canCollide = false,
			})
			PartUtil.box(
				model,
				origin,
				"CornerFlag",
				Vector3.new(1.2, 0.8, 0.05),
				base + Vector3.new(sx * 0.6, 3.1, 0),
				ctx.primary,
				Enum.Material.Fabric,
				{ canCollide = false }
			)
		end
	end
end

-- Niveau 2 : banc de touche abrité (fond, siège, toit vitré, côtés).
local function buildDugout(model: Model, origin: CFrame, x: number, ctx: BuildContext)
	local z = -(WorldConfig.PITCH_SIZE.Y / 2 + 3.5)
	local dugout = PartUtil.model(model, "Dugout")
	local o = origin * CFrame.new(x, 0.3, z)
	local width, depth, height = 8, 3, 3.6
	PartUtil.block(dugout, o, "Floor", Vector3.new(width, 0.2, depth), Vector3.zero, C.ConcreteDark, Enum.Material.Concrete)
	PartUtil.block(
		dugout,
		o,
		"Back",
		Vector3.new(width, height, 0.3),
		Vector3.new(0, 0.2, -depth / 2),
		C.MetalDark,
		Enum.Material.Metal
	)
	PartUtil.block(
		dugout,
		o,
		"Bench",
		Vector3.new(width - 0.6, 1.4, 1.2),
		Vector3.new(0, 0.2, -depth / 2 + 0.75),
		ctx.primary,
		Enum.Material.SmoothPlastic
	)
	for _, side in { -1, 1 } do
		PartUtil.block(
			dugout,
			o,
			"Side",
			Vector3.new(0.2, height, depth),
			Vector3.new(side * (width / 2 - 0.1), 0.2, 0),
			C.Glass,
			Enum.Material.Glass,
			{ transparency = 0.5 }
		)
	end
	PartUtil.block(
		dugout,
		o,
		"Roof",
		Vector3.new(width + 0.4, 0.2, depth + 0.4),
		Vector3.new(0, 0.2 + height, 0),
		C.Glass,
		Enum.Material.Glass,
		{ transparency = 0.4 }
	)
end

-- Niveau 2 : panneaux publicitaires fictifs autour du terrain.
local function buildAdBoards(model: Model, origin: CFrame)
	local hx, hz = WorldConfig.PITCH_SIZE.X / 2, WorldConfig.PITCH_SIZE.Y / 2
	local offset = 4.5 -- distance aux lignes
	local height = 2.2
	local texts = WorldConfig.AD_TEXTS
	local index = 0

	-- face = face de la Part tournée vers le terrain.
	local function board(length: number, pos: Vector2, rotY: number, face: Enum.NormalId)
		index += 1
		local part = PartUtil.block(
			model,
			origin,
			"AdBoard",
			Vector3.new(length, height, 0.4),
			Vector3.new(pos.X, 0.3, pos.Y),
			C.AdBoard,
			Enum.Material.SmoothPlastic,
			{ rotY = rotY }
		)
		PartUtil.label(part, face, texts[(index - 1) % #texts + 1], C.SignText)
	end

	-- Côté opposé à l'entrée (+Z) : 4 panneaux.
	for i = 0, 3 do
		board(22, Vector2.new(-36 + i * 24, hz + offset), 0, Enum.NormalId.Front)
	end
	-- Côté entrée (-Z) : 2 panneaux qui laissent la place aux bancs.
	for _, sx in { -1, 1 } do
		board(26, Vector2.new(sx * 34, -(hz + offset)), 0, Enum.NormalId.Back)
	end
	-- Derrière les buts : 2 panneaux de chaque côté du but.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Avec rotY = 90 la face Front regarde vers -X.
			board(18, Vector2.new(sx * (hx + offset), sz * 20), 90, if sx > 0 then Enum.NormalId.Front else Enum.NormalId.Back)
		end
	end
end

-- Niveau 3 : 4 pylônes d'éclairage placés dans les angles libres entre tribunes.
local function buildFloodlights(model: Model, origin: CFrame)
	local px, pz = 62, 48 -- position des pylônes (angles du stade)
	local height = 32
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local tower = PartUtil.model(model, "Floodlight")
			local base = Vector3.new(sx * px, 0, sz * pz)
			PartUtil.block(tower, origin, "Footing", Vector3.new(3, 1, 3), base, C.Concrete, Enum.Material.Concrete)
			PartUtil.cylinder(tower, origin, "Pole", 1.4, height, base, C.Metal, Enum.Material.Metal)

			-- La tête du pylône vise le centre de son quart de terrain
			-- (portée max d'une SpotLight Roblox = 60 studs).
			local headPos = (origin * CFrame.new(base + Vector3.new(0, height + 2, 0))).Position
			local target = (origin * CFrame.new(sx * 25, 0, sz * 16)).Position
			local headCFrame = CFrame.lookAt(headPos, target)
			local frame = Instance.new("Part")
			frame.Name = "Frame"
			frame.Anchored = true
			frame.Size = Vector3.new(8, 5, 0.8)
			frame.CFrame = headCFrame
			frame.Color = C.MetalDark
			frame.Material = Enum.Material.Metal
			frame.Parent = tower

			local lamps = Instance.new("Part")
			lamps.Name = "Lamps"
			lamps.Anchored = true
			lamps.CanCollide = false
			lamps.Size = Vector3.new(7.2, 4.2, 0.2)
			lamps.CFrame = headCFrame * CFrame.new(0, 0, -0.5)
			lamps.Color = C.LightHead
			lamps.Material = Enum.Material.Neon
			lamps.Parent = tower

			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = 60
			spot.Angle = 70
			spot.Brightness = 4
			spot.Color = C.LightHead
			spot.Shadows = false
			spot.Parent = lamps
		end
	end
end

-- Construit le terrain au niveau demandé et renvoie son Model.
function Pitch.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Pitch", { Facility = "Pitch", Level = level })
	PartUtil.anchor(model, origin, WorldConfig.LAYOUT.Pitch.footprint, 1)

	buildTurf(model, origin)
	buildGoal(model, origin, -1)
	buildGoal(model, origin, 1)
	buildCornerFlags(model, origin, ctx)

	if level >= 2 then
		buildDugout(model, origin, -12, ctx)
		buildDugout(model, origin, 12, ctx)
		buildAdBoards(model, origin)
	end
	if level >= 3 then
		buildFloodlights(model, origin)
	end
	return model
end

return Pitch
