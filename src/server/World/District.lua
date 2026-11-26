--!strict
--[[
	District — le quartier sportif partagé du serveur.

	Contenu : grand sol herbeux, route centrale avec marquage, trottoirs, place
	centrale pavée avec le point d'apparition commun (SpawnLocation), sculptures
	« ballon », bancs et lampadaires, délimitation des 6 emplacements de club
	(bordures + panneaux numérotés), allées vers chaque entrée, arbres.

	Disposition : 2 rangées de 3 emplacements, de part et d'autre de la route
	(voir WorldConfig.SLOTS). Le quartier est centré sur l'origine du monde.

	Le dossier « Slots » contient une Part invisible par emplacement (Slot1…Slot6),
	placée au centre de l'emplacement avec son orientation : pratique pour les
	services qui veulent savoir où se trouve un terrain sans le reconstruire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

local District = {}

local C = WorldConfig.COLORS

local function tree(parent: Instance, origin: CFrame, x: number, z: number)
	local t = PartUtil.model(parent, "Tree")
	PartUtil.cylinder(t, origin, "Trunk", 1.2, 7, Vector3.new(x, 0, z), C.WoodDark, Enum.Material.Wood)
	PartUtil.ball(t, origin, "Leaves", 8, Vector3.new(x, 9.5, z), Color3.fromRGB(62, 112, 52), Enum.Material.Grass)
end

local function lamp(parent: Instance, origin: CFrame, x: number, z: number)
	local m = PartUtil.model(parent, "StreetLamp")
	PartUtil.cylinder(m, origin, "Pole", 0.5, 12, Vector3.new(x, 0.2, z), C.MetalDark, Enum.Material.Metal)
	local head = PartUtil.box(
		m,
		origin,
		"Lamp",
		Vector3.new(1.6, 0.8, 1.6),
		Vector3.new(x, 12.6, z),
		C.LightHead,
		Enum.Material.Neon,
		{ canCollide = false }
	)
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 1.5
	light.Color = C.LightHead
	light.Parent = head
end

local function bench(parent: Instance, origin: CFrame, x: number, z: number, rotY: number)
	local m = PartUtil.model(parent, "Bench")
	local o = origin * CFrame.new(x, 0.2, z) * CFrame.Angles(0, math.rad(rotY), 0)
	PartUtil.block(m, o, "Seat", Vector3.new(6, 1.6, 1.6), Vector3.zero, C.Wood, Enum.Material.WoodPlanks)
	PartUtil.block(m, o, "Back", Vector3.new(6, 1.6, 0.3), Vector3.new(0, 1.6, 0.65), C.Wood, Enum.Material.WoodPlanks)
end

-- Bordure rectangulaire (4 Parts) autour d'un emplacement.
local function slotBorder(parent: Instance, slotCFrame: CFrame)
	local sx, sz = WorldConfig.PLOT_SIZE.X / 2, WorldConfig.PLOT_SIZE.Y / 2
	local w = 1.2
	local h = 0.5
	local color, mat = C.Curb, Enum.Material.Concrete
	PartUtil.block(parent, slotCFrame, "Border", Vector3.new(2 * sx + 2 * w, h, w), Vector3.new(0, 0, -sz - w / 2), color, mat)
	PartUtil.block(parent, slotCFrame, "Border", Vector3.new(2 * sx + 2 * w, h, w), Vector3.new(0, 0, sz + w / 2), color, mat)
	PartUtil.block(parent, slotCFrame, "Border", Vector3.new(w, h, 2 * sz), Vector3.new(-sx - w / 2, 0, 0), color, mat)
	PartUtil.block(parent, slotCFrame, "Border", Vector3.new(w, h, 2 * sz), Vector3.new(sx + w / 2, 0, 0), color, mat)
end

-- Panneau numéroté planté devant l'emplacement, à droite de l'allée d'accès.
local function slotSign(parent: Instance, slotCFrame: CFrame, index: number)
	local sz = WorldConfig.PLOT_SIZE.Y / 2
	-- Dans le repère du slot, -Z pointe vers la route : le panneau est hors du terrain.
	local base = Vector3.new(14, 0, -sz - 4)
	local sign = PartUtil.model(parent, "SlotSign" .. index)
	PartUtil.block(sign, slotCFrame, "Post", Vector3.new(0.6, 5, 0.6), base, C.MetalDark, Enum.Material.Metal)
	local panel = PartUtil.box(
		sign,
		slotCFrame,
		"Panel",
		Vector3.new(7, 3.2, 0.4),
		base + Vector3.new(0, 6.4, 0),
		C.SignBack,
		Enum.Material.SmoothPlastic
	)
	local text = "TERRAIN " .. index
	PartUtil.label(panel, Enum.NormalId.Front, text, C.SignText)
	PartUtil.label(panel, Enum.NormalId.Back, text, C.SignText)
end

-- Construit le quartier sous `parent` et renvoie son Model.
function District.build(parent: Instance): Model
	local model = PartUtil.model(nil, WorldConfig.DISTRICT_NAME, { Facility = "District" })
	local origin = CFrame.new()
	local size = WorldConfig.DISTRICT_SIZE
	local halfX = size.X / 2

	-- Sol : son dessus est à Y = 0,05 (légèrement au-dessus d'une éventuelle
	-- « Baseplate » Roblox dont le dessus est à Y = 0, pour éviter le scintillement).
	local ground = PartUtil.box(
		model,
		origin,
		"Ground",
		Vector3.new(size.X, 2, size.Y),
		Vector3.new(0, -0.95, 0),
		C.DistrictGrass,
		Enum.Material.Grass
	)
	model.PrimaryPart = ground

	-- Route centrale (coupée par la place) + trottoirs.
	local road = WorldConfig.ROAD_WIDTH
	local walk = WorldConfig.SIDEWALK_WIDTH
	local plaza = WorldConfig.PLAZA_SIZE
	local segLength = halfX - plaza / 2
	for _, side in { -1, 1 } do
		local cx = side * (plaza / 2 + segLength / 2)
		PartUtil.block(model, origin, "Road", Vector3.new(segLength, 0.15, road), Vector3.new(cx, 0, 0), C.Asphalt, Enum.Material.Asphalt)
		for _, sz in { -1, 1 } do
			PartUtil.block(
				model,
				origin,
				"Sidewalk",
				Vector3.new(segLength, 0.3, walk),
				Vector3.new(cx, 0, sz * (road / 2 + walk / 2)),
				C.Sidewalk,
				Enum.Material.Concrete
			)
		end
		-- Marquage central en pointillés.
		local dash, gap = 6, 8
		local x = plaza / 2 + 4
		while x + dash < halfX - 2 do
			PartUtil.box(
				model,
				origin,
				"RoadMarking",
				Vector3.new(dash, 0.05, 0.5),
				Vector3.new(side * (x + dash / 2), 0.17, 0),
				C.RoadMarking,
				Enum.Material.SmoothPlastic,
				{ canCollide = false, castShadow = false }
			)
			x += dash + gap
		end
	end

	-- Place centrale.
	local plazaModel = PartUtil.model(model, "Plaza")
	PartUtil.block(plazaModel, origin, "Paving", Vector3.new(plaza, 0.3, plaza), Vector3.zero, C.Paving, Enum.Material.Pebble)
	PartUtil.block(
		plazaModel,
		origin,
		"SpawnRing",
		Vector3.new(WorldConfig.SPAWN_SIZE + 4, 0.35, WorldConfig.SPAWN_SIZE + 4),
		Vector3.zero,
		C.ConcreteDark,
		Enum.Material.Concrete
	)
	local spawn = PartUtil.block(
		plazaModel,
		origin,
		"SpawnLocation",
		Vector3.new(WorldConfig.SPAWN_SIZE, 0.4, WorldConfig.SPAWN_SIZE),
		Vector3.zero,
		C.Paving,
		Enum.Material.Marble,
		{ className = "SpawnLocation" }
	) :: SpawnLocation
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0 -- pas de bouclier ForceField à l'apparition

	-- Deux sculptures « ballon » sur socle, de part et d'autre du point d'apparition.
	for _, sx in { -1, 1 } do
		local x = sx * 28
		PartUtil.cylinder(plazaModel, origin, "Pedestal", 8, 3, Vector3.new(x, 0.3, 0), C.Concrete, Enum.Material.Concrete)
		PartUtil.cylinder(
			plazaModel,
			origin,
			"Basin",
			7,
			0.3,
			Vector3.new(x, 3.3, 0),
			C.Water,
			Enum.Material.Glass,
			{ transparency = 0.3 }
		)
		PartUtil.ball(plazaModel, origin, "BallSculpture", 5, Vector3.new(x, 6.1, 0), C.Line, Enum.Material.Marble)
	end
	-- Lampadaires aux 4 coins et bancs autour de la place.
	local corner = plaza / 2 - 4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			lamp(plazaModel, origin, sx * corner, sz * corner)
			bench(plazaModel, origin, sx * 14, sz * 18, if sz > 0 then 0 else 180)
		end
	end

	-- Emplacements des clubs : bordures, panneaux, allées, repères invisibles.
	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model
	local walkwayStart = road / 2 + walk -- bord extérieur du trottoir
	for index = 1, WorldConfig.MAX_PLOTS do
		local slotCFrame = WorldConfig.getPlotCFrame(index)
		slotBorder(model, slotCFrame)
		slotSign(model, slotCFrame, index)

		-- Allée entre le trottoir (ou la place) et l'entrée du terrain.
		local slot = WorldConfig.SLOTS[index]
		local startZ = if math.abs(slot.x) < plaza / 2 then plaza / 2 else walkwayStart
		local endZ = WorldConfig.CORRIDOR_WIDTH / 2
		local zSign = if slot.z < 0 then -1 else 1
		PartUtil.block(
			model,
			origin,
			"Walkway",
			Vector3.new(10, 0.25, endZ - startZ),
			Vector3.new(slot.x, 0, zSign * (startZ + endZ) / 2),
			C.Path,
			Enum.Material.Concrete
		)

		local marker = PartUtil.box(
			slotsFolder,
			slotCFrame,
			"Slot" .. index,
			Vector3.new(4, 1, 4),
			Vector3.new(0, 0.5, 0),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			{ canCollide = false, transparency = 1, castShadow = false }
		)
		marker.CanQuery = false
		marker.CanTouch = false
		marker:SetAttribute("SlotIndex", index)
	end

	-- Arbres sur les bandes d'herbe entre trottoirs et terrains (en évitant les allées).
	local verge = (walkwayStart + WorldConfig.CORRIDOR_WIDTH / 2) / 2
	local x = -halfX + 20
	while x <= halfX - 20 do
		local clear = math.abs(x) > plaza / 2 + 4
		for _, slot in WorldConfig.SLOTS do
			if math.abs(x - slot.x) < 22 then
				clear = false
			end
		end
		if clear then
			tree(model, origin, x, verge)
			tree(model, origin, x, -verge)
		end
		x += 40
	end

	model.Parent = parent
	return model
end

return District
