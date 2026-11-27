--[[
	NpcController
	Personnages non joueurs (PNJ), entièrement côté client :
	  - supporters : entrent par le portique, vont à la Boutique ou au Musée
	    (quand le serveur annonce un achat, « +N » au-dessus d'eux), se promènent,
	    et rejoignent les tribunes les jours de match ;
	  - joueurs à l'entraînement (jongles, footing, tirs au but) ;
	  - gardiens de sécurité au portique (+ une ronde avec le Centre de sécurité) ;
	  - joueurs e-sport assis devant leurs PC (Centre e-sport) ;
	  - passants sur les trottoirs du quartier.

	Anti-lag :
	  - aucun PNJ n'existe sur le serveur : zéro réseau, zéro physique
	    (pièces ancrées, sans collision, sans ombre, sans requête) ;
	  - réserve de personnages réutilisés (jamais créés/détruits en boucle) ;
	  - budget total (Npc.Budget) : 40 sur ordinateur, 16 sur téléphone,
	    40 % de ça si Paramètres > « Détails du décor » est coupé ;
	  - seuls les 1 ou 2 terrains les plus proches de la caméra sont animés ;
	  - PNJ lointains animés 10 fois par seconde au lieu de 30 ;
	  - toutes les pièces déplacées d'un seul appel (workspace:BulkMoveTo).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Npc = require(Shared:WaitForChild("Npc"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Net = require(Shared:WaitForChild("Net"))

local NpcController = {}

local HIDDEN_Y = -500 -- personnages « rentrés » dans un bâtiment : sous le sol, sans rien coûter
local RESCAN_EVERY = 1
local LAYOUT_EVERY = 5
local POPUP_TIME = 2.2

local PRIORITY = { visitor = 5, matchday = 4, guard = 4, trainer = 3, gamer = 3, stroller = 1, pedestrian = 0 }

local SKINS = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(234, 190, 150),
	Color3.fromRGB(198, 140, 100),
	Color3.fromRGB(141, 85, 56),
	Color3.fromRGB(96, 60, 40),
}
local CLOTHES = {
	Color3.fromRGB(40, 60, 120),
	Color3.fromRGB(150, 40, 40),
	Color3.fromRGB(60, 120, 70),
	Color3.fromRGB(220, 220, 215),
	Color3.fromRGB(50, 50, 55),
	Color3.fromRGB(200, 160, 60),
	Color3.fromRGB(120, 80, 150),
	Color3.fromRGB(90, 140, 190),
}
local PANTS = { Color3.fromRGB(35, 40, 60), Color3.fromRGB(60, 60, 64), Color3.fromRGB(110, 90, 70), Color3.fromRGB(30, 30, 32) }
local GUARD_COLOR = Color3.fromRGB(28, 30, 36)
local GOLD = Color3.fromRGB(212, 175, 55)

local initialized = false
local folder: Instance? = nil
local detailsOn = true
local clock = 0
local rescanTimer = 0

local pool = {} -- personnages libres
local agents = {} -- PNJ actifs
local balls = {} -- ballons libres
local popups = {} -- { anchor, label, t } actifs
local freePopups = {}
local zones = {} -- [slot] = zone
local pending = {} -- arrivées échelonnées : { at, slot, kind, coins }
local pedestrians = 0

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function isMobile(): boolean
	local ok, touch = pcall(function()
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end)
	return ok and touch == true
end

local function pick(list)
	return list[math.random(1, #list)]
end

local function newPart(parent: Instance, name: string, size: Vector3, shape): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.CFrame = CFrame.new(0, HIDDEN_Y, 0)
	part.Parent = parent
	return part
end

local function plotCFrame(slot: number): CFrame
	return WorldConfig.getPlotCFrame(slot) * CFrame.new(0, WorldConfig.PLOT_GROUND_TOP, 0)
end

local function toWorld(zone, localPos: Vector3): Vector3
	return zone.cf * localPos
end

local function routeToWorld(zone, route): { Vector3 }
	local list = {}
	for i, point in route do
		list[i] = toWorld(zone, point)
	end
	return list
end

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

local function clubColors(slot: number, plot: Instance?)
	local id = plot and plot:GetAttribute("Colors")
	local item = id and Cosmetics.Get(id)
	if item and item.category == "colors" and item.primary then
		return item.primary, item.secondary
	end
	local colors = WorldConfig.CLUB_COLORS[slot] or WorldConfig.CLUB_COLORS[1]
	return colors.primary, colors.secondary
end

--------------------------------------------------------------------------------
-- Personnages (6 pièces) et ballons réutilisés
--------------------------------------------------------------------------------

local function newFigure()
	local model = Instance.new("Model")
	model.Name = "Npc"
	local fig = { model = model }
	fig.torso = newPart(model, "Torso", Vector3.new(2, 2.2, 1))
	fig.head = newPart(model, "Head", Vector3.new(1.3, 1.3, 1.3), Enum.PartType.Ball)
	fig.armL = newPart(model, "LeftArm", Vector3.new(0.8, 2.1, 0.8))
	fig.armR = newPart(model, "RightArm", Vector3.new(0.8, 2.1, 0.8))
	fig.legL = newPart(model, "LeftLeg", Vector3.new(0.9, 2.2, 0.9))
	fig.legR = newPart(model, "RightLeg", Vector3.new(0.9, 2.2, 0.9))
	fig.parts = { fig.torso, fig.head, fig.armL, fig.armR, fig.legL, fig.legR }
	return fig
end

local function dress(fig, shirt: Color3, pants: Color3, skin: Color3)
	fig.torso.Color = shirt
	fig.armL.Color = shirt
	fig.armR.Color = shirt
	fig.legL.Color = pants
	fig.legR.Color = pants
	fig.head.Color = skin
end

local function takeBall(): BasePart?
	local ball = table.remove(balls)
	if not ball and folder then
		ball = newPart(folder, "NpcBall", Vector3.new(1, 1, 1), Enum.PartType.Ball)
		ball.Color = Color3.new(1, 1, 1)
	end
	return ball
end

local function budget(): number
	return Npc.Budget(isMobile(), detailsOn)
end

local function release(agent)
	local index = table.find(agents, agent)
	if index then
		table.remove(agents, index)
	end
	if agent.zone and agent.zone.agents then
		local zi = table.find(agent.zone.agents, agent)
		if zi then
			table.remove(agent.zone.agents, zi)
		end
	end
	if agent.role == "pedestrian" then
		pedestrians -= 1
	end
	for _, part in agent.fig.parts do
		part.CFrame = CFrame.new(0, HIDDEN_Y, 0)
	end
	agent.fig.model.Parent = nil
	table.insert(pool, agent.fig)
	if agent.ball then
		agent.ball.CFrame = CFrame.new(0, HIDDEN_Y, 0)
		table.insert(balls, agent.ball)
		agent.ball = nil
	end
end

-- Un personnage pour un nouveau PNJ, ou nil si le budget est atteint
-- (un PNJ moins important peut céder sa place).
local function acquire(role: string, zone)
	local priority = PRIORITY[role] or 0
	if #agents >= budget() then
		local weakest, weakestPriority = nil, priority
		for _, other in agents do
			local p = PRIORITY[other.role] or 0
			if p < weakestPriority then
				weakest, weakestPriority = other, p
			end
		end
		if not weakest then
			return nil
		end
		release(weakest)
	end
	local fig = table.remove(pool) or newFigure()
	fig.model.Parent = folder
	local agent = {
		fig = fig,
		role = role,
		zone = zone,
		pos = Vector3.zero,
		dir = Vector3.new(0, 0, -1),
		phase = math.random() * 6,
		pose = "idle",
		acc = 0,
		hidden = false,
		speed = Npc.WALK_SPEED,
		wait = 0,
	}
	table.insert(agents, agent)
	if zone then
		table.insert(zone.agents, agent)
	end
	if role == "pedestrian" then
		pedestrians += 1
	end
	return agent
end

-- Suit `route` (positions monde) puis appelle onEnd(agent).
local function follow(agent, route, onEnd)
	agent.route = route
	agent.index = 2
	agent.pos = route[1]
	agent.onEnd = onEnd
	agent.hidden = false
	agent.pose = if agent.speed > Npc.WALK_SPEED + 1 then "run" else "walk"
end

--------------------------------------------------------------------------------
-- Comportements
--------------------------------------------------------------------------------

local function showPopup(position: Vector3, coins: number)
	if not folder then
		return
	end
	local popup = table.remove(freePopups)
	if not popup then
		local anchor = newPart(folder, "NpcCoins", Vector3.new(0.2, 0.2, 0.2))
		anchor.Transparency = 1
		local gui = Instance.new("BillboardGui")
		gui.Name = "Coins"
		gui.Size = UDim2.new(0, 90, 0, 34)
		gui.MaxDistance = 160
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Name = "Amount"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = GOLD
		label.TextStrokeTransparency = 0.3
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		popup = { anchor = anchor, label = label }
	end
	popup.label.Text = "+" .. tostring(coins)
	popup.label.TextTransparency = 0
	popup.base = position + Vector3.new(0, 7, 0)
	popup.anchor.CFrame = CFrame.new(popup.base)
	popup.t = 0
	table.insert(popups, popup)
end

local function newSupporter(zone, role: string)
	local agent = acquire(role, zone)
	if not agent then
		return nil
	end
	-- Une partie des supporters porte le maillot du club.
	local shirt = if math.random() < 0.5 then zone.primary else pick(CLOTHES)
	dress(agent.fig, shirt, pick(PANTS), pick(SKINS))
	return agent
end

local startStroll

-- Va acheter (Boutique) ou visiter (Musée), « +N », reste un moment, puis repart.
local function startVisit(zone, kind: string, coins: number)
	local route
	if kind == "museum" and zone.museum then
		route = Npc.CampusRoute(zone.museum.parcel, zone.museum.rot, math.random(-4, 4))
	end
	route = route or Npc.ShopRoute(math.random(-4, 4))
	local agent = newSupporter(zone, "visitor")
	if not agent then
		return false
	end
	local worldRoute = routeToWorld(zone, route)
	follow(agent, worldRoute, function(a)
		showPopup(a.pos, coins)
		a.pose = "cheer"
		a.wait = 1.2
		a.afterWait = function(b)
			b.hidden = true
			b.wait = 4 + math.random() * 4
			b.afterWait = function(c)
				follow(c, reversed(worldRoute), release)
			end
		end
	end)
	return true
end

startStroll = function(agent)
	local zone = agent.zone
	local route = routeToWorld(zone, Npc.StrollRoute(math.random(1, #Npc.STROLL_TARGETS), math.random(-5, 5)))
	follow(agent, route, function(a)
		a.pose = "idle"
		a.wait = 3 + math.random() * 5
		a.afterWait = function(b)
			follow(b, reversed(route), function(c)
				c.wait = 1 + math.random() * 3
				c.afterWait = startStroll
			end)
		end
	end)
end

local function startMatchday(zone)
	local agent = newSupporter(zone, "matchday")
	if not agent then
		return
	end
	dress(agent.fig, zone.primary, zone.secondary, pick(SKINS)) -- maillot du club les jours de match
	follow(agent, routeToWorld(zone, Npc.StadiumRoute(math.random(-5, 5))), release)
end

local function faceLocal(zone, localPos: Vector3, localDir: Vector3): Vector3
	return toWorld(zone, localPos + localDir) - toWorld(zone, localPos)
end

local function spawnGuards(zone)
	for _, spot in Npc.ENTRANCE_GUARDS do
		local agent = acquire("guard", zone)
		if not agent then
			return
		end
		dress(agent.fig, GUARD_COLOR, GUARD_COLOR, pick(SKINS))
		agent.pos = toWorld(zone, spot)
		agent.dir = faceLocal(zone, spot, Vector3.new(0, 0, -1))
		agent.pose = "guard"
		agent.static = true
	end
	if zone.security then
		local route = routeToWorld(zone, Npc.PATROL_ROUTE)
		local function patrol(a)
			follow(a, route, function(b)
				b.wait = 2
				b.pose = "guard"
				b.afterWait = patrol
			end)
		end
		for i = 1, 2 do
			local agent = acquire("guard", zone)
			if not agent then
				return
			end
			dress(agent.fig, GUARD_COLOR, GUARD_COLOR, pick(SKINS))
			if i == 2 then
				route = reversed(route)
			end
			patrol(agent)
		end
	end
end

local function spawnTrainers(zone)
	local center, half = Npc.TrainingField()
	local count = Npc.TrainingCount(zone.trainingLevel)
	local kinds = { "juggle", "run", "shoot", "run" }
	for i = 1, count do
		local agent = acquire("trainer", zone)
		if not agent then
			return
		end
		dress(agent.fig, zone.primary, zone.secondary, pick(SKINS))
		local kind = kinds[i]
		agent.trainer = kind
		if kind == "juggle" then
			local spot = center + Vector3.new(-half.X * 0.35, 0, -half.Y * 0.3)
			agent.pos = toWorld(zone, spot)
			agent.dir = faceLocal(zone, spot, Vector3.new(1, 0, 0))
			agent.pose = "juggle"
			agent.static = true
			agent.ball = takeBall()
		elseif kind == "run" then
			local ox, oz = half.X - 4, half.Y - 4
			if i == 4 then
				ox, oz = ox - 6, oz - 6
			end
			local loop = routeToWorld(zone, {
				center + Vector3.new(-ox, 0, -oz),
				center + Vector3.new(ox, 0, -oz),
				center + Vector3.new(ox, 0, oz),
				center + Vector3.new(-ox, 0, oz),
				center + Vector3.new(-ox, 0, -oz),
			})
			agent.speed = Npc.RUN_SPEED
			local function lap(a)
				follow(a, loop, lap)
			end
			lap(agent)
		else
			-- Tireur : élan vers le ballon, frappe vers le mini-but, retour.
			local from = center + Vector3.new(0, 0, 4)
			local spot = center + Vector3.new(half.X * 0.45, 0, 0)
			agent.goal = toWorld(zone, center + Vector3.new(half.X - 3, 1.2, 0))
			agent.ballSpot = toWorld(zone, spot) + Vector3.new(0, 0.5, 0)
			agent.ball = takeBall()
			if agent.ball then
				agent.ball.CFrame = CFrame.new(agent.ballSpot)
			end
			local runUp = routeToWorld(zone, { from, spot - Vector3.new(1.5, 0, 0) })
			local function shoot(a)
				a.speed = Npc.RUN_SPEED
				follow(a, runUp, function(b)
					b.pose = "kick"
					b.shotT = 0
					b.wait = 1.6
					b.afterWait = function(c)
						c.speed = Npc.WALK_SPEED
						follow(c, reversed(runUp), function(d)
							d.wait = 1
							d.afterWait = shoot
						end)
					end
				end)
			end
			shoot(agent)
		end
	end
end

local function spawnGamers(zone)
	local max = if isMobile() then 2 else 4
	for i, seat in zone.seats do
		if i > max then
			return
		end
		local agent = acquire("gamer", zone)
		if not agent then
			return
		end
		dress(agent.fig, pick(CLOTHES), pick(PANTS), pick(SKINS))
		agent.pos = seat.pos
		agent.dir = seat.dir
		agent.pose = "seated"
		agent.static = true
	end
end

local function spawnStrollers(zone)
	local count = if isMobile() then 1 else 3
	for _ = 1, count do
		local agent = newSupporter(zone, "stroller")
		if not agent then
			return
		end
		startStroll(agent)
		-- Départs décalés : pas tous au portique en même temps.
		agent.pos = agent.route[1]
		agent.wait = math.random() * 6
	end
end

--------------------------------------------------------------------------------
-- Zones (terrains proches de la caméra)
--------------------------------------------------------------------------------

-- Lit ce qui est construit sur le terrain (zone d'entraînement, mode Création).
local function readLayout(zone)
	local plot = zone.plot
	zone.trainingLevel = plot:GetAttribute("Level_Training") or 1
	zone.primary, zone.secondary = clubColors(zone.slot, plot)
	zone.museum, zone.security, zone.seats = nil, false, {}
	local campus = plot:FindFirstChild("Campus")
	if campus then
		for _, parcel in campus:GetChildren() do
			local index = parcel:GetAttribute("Parcel")
			if parcel:GetAttribute("State") == "built" and index then
				for _, building in parcel:GetChildren() do
					local id = building:GetAttribute("CampusBuilding")
					if id == "Museum" then
						zone.museum = { parcel = index, rot = building:GetAttribute("Rotation") or 0 }
					elseif id == "Security" then
						zone.security = true
					elseif id == "Esport" then
						for _, d in building:GetDescendants() do
							if d.Name == "GamingSeat" and d:IsA("BasePart") then
								local cf = d.CFrame
								local forward = (cf * Vector3.new(0, 0, 1)) - cf.Position
								table.insert(zone.seats, {
									pos = cf.Position + Vector3.new(0, 0.2 - 2.2, 0),
									dir = forward,
								})
							end
						end
					end
				end
			end
		end
	end
	local seats = #zone.seats
	return table.concat({
		tostring(zone.trainingLevel),
		tostring(zone.museum and zone.museum.parcel),
		tostring(zone.museum and zone.museum.rot),
		tostring(zone.security),
		tostring(seats),
		tostring(zone.primary),
	}, "|")
end

local function clearZone(zone)
	for i = #zone.agents, 1, -1 do
		release(zone.agents[i])
	end
end

local function populate(zone)
	spawnGuards(zone)
	spawnTrainers(zone)
	spawnGamers(zone)
	spawnStrollers(zone)
end

local function occupiedSlots(): { [number]: boolean }
	local slots = {}
	for _, player in Players:GetPlayers() do
		local slot = player:GetAttribute("ClubSlot")
		if type(slot) == "number" and WorldConfig.SLOTS[slot] then
			slots[slot] = true
		end
	end
	return slots
end

local function cameraPosition(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame and camera.CFrame.Position
end

local function managePedestrians(cameraPos: Vector3?)
	local lanes = Npc.SidewalkLanes()
	local halfLength = Npc.SidewalkHalfLength()
	local wanted = if isMobile() then Npc.PEDESTRIANS_MOBILE else Npc.PEDESTRIANS_DESKTOP
	if not detailsOn then
		wanted = math.floor(wanted / 2)
	end
	local nearRoad = cameraPos ~= nil and math.abs(cameraPos.Z) < Npc.PEDESTRIAN_RANGE
	if not nearRoad then
		wanted = 0
	end
	-- Trop loin de la caméra : on recycle.
	for i = #agents, 1, -1 do
		local agent = agents[i]
		if agent.role == "pedestrian" then
			if pedestrians > wanted or (cameraPos and math.abs(agent.pos.X - cameraPos.X) > Npc.PEDESTRIAN_RANGE + 40) then
				release(agent)
			end
		end
	end
	while nearRoad and pedestrians < wanted do
		local agent = acquire("pedestrian", nil)
		if not agent then
			return
		end
		dress(agent.fig, pick(CLOTHES), pick(PANTS), pick(SKINS))
		local z = pick(lanes)
		local x = math.clamp(cameraPos.X + math.random(-Npc.PEDESTRIAN_RANGE, Npc.PEDESTRIAN_RANGE), -halfLength, halfLength)
		local side = if math.random() < 0.5 then -1 else 1
		local y = 0.3
		follow(agent, { Vector3.new(x, y, z), Vector3.new(side * halfLength, y, z) }, function(a)
			follow(a, { a.pos, Vector3.new(-side * halfLength, y, z) }, function(b)
				release(b)
			end)
		end)
		agent.speed = Npc.WALK_SPEED * (0.75 + math.random() * 0.4)
	end
end

-- Choisit les terrains animés et ajuste le nombre de PNJ (appelé chaque seconde).
function NpcController.Rescan()
	if not folder then
		return
	end
	local cameraPos = cameraPosition()
	local maxZones = if isMobile() then Npc.MAX_ZONES_MOBILE else Npc.MAX_ZONES_DESKTOP
	local candidates = {}
	for slot in occupiedSlots() do
		local plot = workspace:FindFirstChild(WorldConfig.PLOT_NAME_PREFIX .. slot)
		if plot then
			local center = WorldConfig.getPlotCFrame(slot).Position
			local distance = if cameraPos then (center - cameraPos).Magnitude else 0
			if distance <= Npc.ZONE_RANGE then
				table.insert(candidates, { slot = slot, plot = plot, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local keep = {}
	for i = 1, math.min(maxZones, #candidates) do
		keep[candidates[i].slot] = candidates[i]
	end
	for slot, zone in zones do
		if not keep[slot] then
			clearZone(zone)
			zones[slot] = nil
		end
	end
	for slot, entry in keep do
		local zone = zones[slot]
		if zone and zone.plot ~= entry.plot then
			clearZone(zone) -- terrain reconstruit (amélioration, Création…)
			zones[slot] = nil
			zone = nil
		end
		if not zone then
			zone = { slot = slot, plot = entry.plot, cf = plotCFrame(slot), agents = {}, layoutTimer = 0 }
			zones[slot] = zone
			zone.signature = readLayout(zone)
			populate(zone)
		else
			zone.layoutTimer += RESCAN_EVERY
			if zone.layoutTimer >= LAYOUT_EVERY then
				zone.layoutTimer = 0
				local signature = readLayout(zone)
				if signature ~= zone.signature then
					zone.signature = signature
					clearZone(zone)
					populate(zone)
				end
			end
		end
	end
	-- Budget baissé (option Détails coupée) : les moins importants s'en vont.
	while #agents > budget() do
		local weakest, weakestPriority = nil, math.huge
		for _, agent in agents do
			local p = PRIORITY[agent.role] or 0
			if p < weakestPriority then
				weakest, weakestPriority = agent, p
			end
		end
		release(weakest)
	end
	managePedestrians(cameraPos)
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

local partsList, cframesList = {}, {}

local function push(part, cf)
	table.insert(partsList, part)
	table.insert(cframesList, cf)
end

local function limb(root: CFrame, x: number, y: number, angle: number, length: number): CFrame
	return root * CFrame.new(x, y, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -length / 2, 0)
end

local function poseAgent(agent)
	local fig = agent.fig
	if agent.hidden then
		if not agent.wasHidden then
			agent.wasHidden = true
			for _, part in fig.parts do
				push(part, CFrame.new(agent.pos.X, HIDDEN_Y, agent.pos.Z))
			end
		end
		return
	end
	agent.wasHidden = false
	local dir = Vector3.new(agent.dir.X, 0, agent.dir.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	local base = agent.pos
	local root = CFrame.lookAt(base, base + dir)
	local t = agent.phase
	local legL, legR, armL, armR = 0, 0, 0, 0
	local pose = agent.pose
	if pose == "walk" then
		local s = math.sin(t * 7) * 0.55
		legL, legR, armL, armR = s, -s, -s * 0.8, s * 0.8
	elseif pose == "run" then
		local s = math.sin(t * 11) * 0.95
		legL, legR, armL, armR = s, -s, -s, s
	elseif pose == "cheer" then
		armL, armR = math.pi * 0.9 + math.sin(t * 9) * 0.2, math.pi * 0.9 - math.sin(t * 9) * 0.2
	elseif pose == "guard" then
		-- Regarde à gauche et à droite, bras croisés devant lui.
		root = root * CFrame.Angles(0, math.sin(t * 0.6) * 0.35, 0)
		armL, armR = 0.5, 0.5
	elseif pose == "juggle" then
		local bounce = math.abs(math.sin(t * 3.2))
		legR = (1 - bounce) * 0.9
		armL, armR = 0.3, 0.3
		if agent.ball then
			push(agent.ball, root * CFrame.new(0.5, 0.6 + bounce * 3.4, -1.1))
		end
	elseif pose == "kick" then
		local k = math.clamp((agent.shotT or 0) / 0.35, 0, 1)
		legR = k * 1.3
		armL = -k * 0.6
	elseif pose == "seated" then
		legL, legR = math.pi / 2, math.pi / 2
		armL, armR = 1.25 + math.sin(t * 13) * 0.05, 1.25 + math.cos(t * 11) * 0.05
		root = root * CFrame.Angles(0, math.sin(t * 0.4) * 0.08, 0)
	end
	push(fig.torso, root * CFrame.new(0, 3.3, 0))
	push(fig.head, root * CFrame.new(0, 5.1, 0))
	push(fig.legL, limb(root, -0.5, 2.2, legL, 2.2))
	push(fig.legR, limb(root, 0.5, 2.2, legR, 2.2))
	push(fig.armL, limb(root, -1.4, 4.3, armL, 2.1))
	push(fig.armR, limb(root, 1.4, 4.3, armR, 2.1))
	-- Tir : le ballon part vers le but après la frappe, puis revient.
	if agent.trainer == "shoot" and agent.ball and agent.ballSpot then
		local shot = agent.shotT
		if pose == "kick" and shot and shot > 0.3 then
			local k = math.clamp((shot - 0.3) / 0.6, 0, 1)
			local p = agent.ballSpot + (agent.goal - agent.ballSpot) * k + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0)
			push(agent.ball, CFrame.new(p))
		else
			push(agent.ball, CFrame.new(agent.ballSpot))
		end
	end
end

local function advance(agent, dt: number)
	agent.phase += dt
	if agent.shotT then
		agent.shotT += dt
	end
	if agent.wait > 0 then
		agent.wait -= dt
		if agent.wait <= 0 then
			agent.wait = 0
			local after = agent.afterWait
			agent.afterWait = nil
			if after then
				after(agent)
			end
		end
		return
	end
	local route = agent.route
	if not route or agent.static then
		return
	end
	local remaining = agent.speed * dt
	while remaining > 0 and agent.route == route do
		local target = route[agent.index]
		if not target then
			agent.route = nil
			local onEnd = agent.onEnd
			agent.onEnd = nil
			agent.pose = if agent.pose == "walk" or agent.pose == "run" then "idle" else agent.pose
			if onEnd then
				onEnd(agent)
			end
			return
		end
		local delta = Vector3.new(target.X - agent.pos.X, 0, target.Z - agent.pos.Z)
		local distance = delta.Magnitude
		if distance < 0.05 then
			agent.pos = Vector3.new(target.X, target.Y, target.Z)
			agent.index += 1
		elseif distance <= remaining then
			agent.pos = Vector3.new(target.X, target.Y, target.Z)
			agent.dir = delta
			agent.index += 1
			remaining -= distance
		else
			local step = delta.Unit * remaining
			agent.pos = Vector3.new(agent.pos.X + step.X, target.Y, agent.pos.Z + step.Z)
			agent.dir = delta
			remaining = 0
		end
	end
end

function NpcController.Step(dt: number)
	clock += dt
	rescanTimer += dt
	if rescanTimer >= RESCAN_EVERY then
		rescanTimer = 0
		NpcController.Rescan()
	end
	-- Arrivées échelonnées (jours de match, visites).
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if clock >= entry.at then
			table.remove(pending, i)
			local zone = zones[entry.slot]
			if zone then
				if entry.kind == "matchday" then
					startMatchday(zone)
				else
					startVisit(zone, entry.kind, entry.coins)
				end
			end
		end
	end
	local cameraPos = cameraPosition()
	table.clear(partsList)
	table.clear(cframesList)
	for i = #agents, 1, -1 do
		local agent = agents[i]
		if agent then
			agent.acc += dt
			local near = cameraPos == nil or (agent.pos - cameraPos).Magnitude < Npc.NEAR_DISTANCE
			local rate = if near then Npc.NEAR_RATE else Npc.FAR_RATE
			if agent.acc >= rate then
				local elapsed = agent.acc
				agent.acc = 0
				advance(agent, elapsed)
				if table.find(agents, agent) then
					poseAgent(agent)
				end
			end
		end
	end
	for i = #popups, 1, -1 do
		local popup = popups[i]
		popup.t += dt
		if popup.t >= POPUP_TIME then
			table.remove(popups, i)
			push(popup.anchor, CFrame.new(0, HIDDEN_Y, 0))
			table.insert(freePopups, popup)
		else
			push(popup.anchor, CFrame.new(popup.base + Vector3.new(0, popup.t * 2, 0)))
			popup.label.TextTransparency = math.max(0, (popup.t - POPUP_TIME * 0.6) / (POPUP_TIME * 0.4))
		end
	end
	if #partsList > 0 then
		local bulk = workspace.BulkMoveTo
		if typeof(bulk) == "function" then
			local ok = pcall(bulk, workspace, partsList, cframesList, Enum.BulkMoveMode.FireCFrameChanged)
			if ok then
				return
			end
		end
		for i, part in partsList do
			part.CFrame = cframesList[i]
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Le serveur annonce un achat d'un supporter sur le terrain `slot`.
function NpcController.OnVisit(slot: any, kind: any, coins: any)
	if type(slot) ~= "number" or not zones[slot] then
		return -- terrain loin de la caméra : rien à montrer
	end
	local amount = math.max(0, math.floor(tonumber(coins) or 0))
	local visitKind = if kind == "museum" then "museum" else "shop"
	table.insert(pending, { at = clock + math.random() * 1.5, slot = slot, kind = visitKind, coins = amount })
end

-- Jour de match : une vague de supporters en maillot rejoint les tribunes.
function NpcController.MatchDay(slot: any)
	if type(slot) ~= "number" or not WorldConfig.SLOTS[slot] then
		return
	end
	local count = if isMobile() then 4 else 10
	if not detailsOn then
		count = math.ceil(count / 2)
	end
	for i = 1, count do
		table.insert(pending, { at = clock + i * 0.9, slot = slot, kind = "matchday" })
	end
end

-- Paramètres > « Détails du décor ».
function NpcController.SetDetailsEnabled(value: boolean)
	detailsOn = value ~= false
	NpcController.Rescan()
end

-- Diagnostic et tests : nombre de PNJ par rôle.
function NpcController.Stats()
	local byRole = {}
	for _, agent in agents do
		byRole[agent.role] = (byRole[agent.role] or 0) + 1
	end
	local zoneCount = 0
	for _ in zones do
		zoneCount += 1
	end
	return {
		total = #agents,
		budget = budget(),
		byRole = byRole,
		zones = zoneCount,
		popups = #popups,
		pooled = #pool,
		parts = #agents * 6,
	}
end

function NpcController.Agents()
	return agents
end

function NpcController.Init()
	if initialized then
		return
	end
	initialized = true
	local f = Instance.new("Folder")
	f.Name = "Npcs"
	f.Parent = workspace
	folder = f
	Net.Get("SupporterVisit").OnClientEvent:Connect(NpcController.OnVisit)
	if RunService.Heartbeat then
		RunService.Heartbeat:Connect(function(dt)
			local ok, err = pcall(NpcController.Step, dt)
			if not ok then
				warn("[PNJ] " .. tostring(err))
			end
		end)
	end
end

return NpcController
