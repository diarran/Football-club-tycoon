--[[
	TrafficController
	Vie du centre-ville côté client, sans aucun échange réseau :
	  - feux tricolores : allumés selon l'heure du serveur (City.LightState),
	    donc identiques chez tous les joueurs ;
	  - circulation : quelques voitures de PNJ font le tour des boulevards et du
	    rond-point, gardent leurs distances et s'arrêtent aux feux rouges.

	Optimisé pour le téléphone (même logique que les PNJ) : 12 voitures sur
	ordinateur, 5 sur téléphone, 40 % de ce nombre si « Détails du décor » est
	coupé ; tout s'arrête quand la caméra est loin de la ville ; voitures
	ancrées, sans collision (une dizaine de Parts chacune), mises à jour à
	30 images/s maximum (20 sur téléphone).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local City = require(Shared.City)
local CarModels = require(Shared.CarModels)

local TrafficController = {}

local SHAPES = { "hatch", "sedan", "sedan", "suv", "coupe", "hatch", "sedan", "sport" }
local COLORS = {
	Color3.fromRGB(236, 236, 236),
	Color3.fromRGB(22, 22, 26),
	Color3.fromRGB(170, 174, 182),
	Color3.fromRGB(30, 70, 170),
	Color3.fromRGB(150, 30, 34),
	Color3.fromRGB(60, 90, 70),
	Color3.fromRGB(200, 170, 120),
}
local LIGHT_ON = {
	red = Color3.fromRGB(255, 50, 40),
	yellow = Color3.fromRGB(255, 190, 40),
	green = Color3.fromRGB(60, 230, 100),
}
local LIGHT_OFF = Color3.fromRGB(40, 40, 42)

local path = {} -- { pos, len (cumul au début du segment), dir }
local loopLength = 0
local stops = {} -- abscisses (le long de la boucle) des lignes d'arrêt
local cars = {} -- { model, s, speed, parts, offsets }
local folder = nil
local signals = {} -- Parts « Signal » des feux
local lastLights = nil
local detailsOn = true
local active = false
local accumulator = 0
local initialized = false

local function isMobile(): boolean
	local ok, touch = pcall(function()
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end)
	return ok and touch == true
end

local function serverTime(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

local function buildPath()
	path, loopLength = {}, 0
	local points = City.TrafficLoop()
	for i, p in points do
		local q = points[i % #points + 1]
		local seg = q - p
		table.insert(path, { pos = p, len = loopLength, dir = seg.Unit, length = seg.Magnitude })
		loopLength += seg.Magnitude
	end
	-- Lignes d'arrêt : point du segment de la bonne voie qui coupe x = stop.x.
	stops = {}
	for _, stop in City.STOP_LINES do
		for _, seg in path do
			local laneOk = (stop.dir > 0 and seg.dir.X > 0.9) or (stop.dir < 0 and seg.dir.X < -0.9)
			if laneOk then
				local x0, x1 = seg.pos.X, seg.pos.X + seg.dir.X * seg.length
				if (stop.x - x0) * (stop.x - x1) <= 0 then
					table.insert(stops, seg.len + math.abs(stop.x - x0))
				end
			end
		end
	end
end

-- Position et direction (locales) à l'abscisse s de la boucle.
function TrafficController.Sample(s: number): (Vector3, Vector3)
	s = s % loopLength
	for i = #path, 1, -1 do
		local seg = path[i]
		if s >= seg.len then
			return seg.pos + seg.dir * (s - seg.len), seg.dir
		end
	end
	return path[1].pos, path[1].dir
end

local function forward(from: number, to: number): number
	return (to - from) % loopLength
end

local function placeCar(car)
	local pos, dir = TrafficController.Sample(car.s)
	local world = City.ToWorld(pos)
	car.model:PivotTo(CFrame.lookAt(world, world + dir))
end

local function spawnCar(index: number, count: number)
	local shape = SHAPES[(index - 1) % #SHAPES + 1]
	local color = COLORS[(index * 3 - 1) % #COLORS + 1]
	local model = CarModels.Build(shape, color, CFrame.new(), "TrafficCar")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if not detailsOn and d:GetAttribute("Detail") then
				d.Transparency = 1
			end
		end
	end
	model.Parent = folder
	local car = { model = model, s = (index - 1) * loopLength / count, speed = City.TRAFFIC_SPEED }
	placeCar(car)
	return car
end

local function clearCars()
	for _, car in cars do
		car.model:Destroy()
	end
	cars = {}
end

-- Nombre de voitures voulu pour cet appareil (recrée la file si besoin).
function TrafficController.Rebuild()
	if not folder then
		return
	end
	clearCars()
	local count = City.TrafficBudget(isMobile(), detailsOn)
	for i = 1, count do
		table.insert(cars, spawnCar(i, count))
	end
end

function TrafficController.SetDetails(enabled: boolean)
	detailsOn = enabled ~= false
	if folder then
		TrafficController.Rebuild()
	end
end

function TrafficController.Count(): number
	return #cars
end

-- Feux : recolore seulement quand l'état change.
function TrafficController.UpdateLights(t: number?)
	local now = t or serverTime()
	local main, cross = City.LightState("main", now), City.LightState("cross", now)
	local key = main .. cross
	if key == lastLights then
		return main, cross
	end
	lastLights = key
	for _, part in signals do
		local axis = part:GetAttribute("SignalAxis")
		local color = part:GetAttribute("SignalColor")
		local lit = (if axis == "main" then main else cross) == color
		part.Color = if lit then LIGHT_ON[color] else LIGHT_OFF
		part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	return main, cross
end

-- Un pas de circulation (dt secondes).
function TrafficController.Step(dt: number, t: number?)
	if #cars == 0 then
		return
	end
	local main = City.LightState("main", t or serverTime())
	local redForUs = main ~= "green"
	table.sort(cars, function(a, b)
		return a.s < b.s
	end)
	for i, car in cars do
		local ahead = cars[i % #cars + 1]
		local gap = if ahead == car then math.huge else forward(car.s, ahead.s)
		local target = City.TRAFFIC_SPEED
		if gap < City.TRAFFIC_GAP then
			target = 0
		elseif gap < City.TRAFFIC_GAP * 2 then
			target = City.TRAFFIC_SPEED * (gap - City.TRAFFIC_GAP) / City.TRAFFIC_GAP
		end
		if redForUs then
			for _, stopAt in stops do
				local d = forward(car.s, stopAt)
				if d < 30 and d > 0.5 then
					target = math.min(target, if d < 3 then 0 else City.TRAFFIC_SPEED * d / 30)
				end
			end
		end
		local rate = if target < car.speed then 30 else 10
		car.speed += math.clamp(target - car.speed, -rate * dt, rate * dt)
		car.s = (car.s + car.speed * dt) % loopLength
		placeCar(car)
	end
end

function TrafficController.IsActive(): boolean
	return active
end

local function cameraNear(): boolean
	local camera = workspace.CurrentCamera
	local pos = camera and camera.CFrame and camera.CFrame.Position
	if not pos then
		return false
	end
	return (pos - City.ORIGIN).Magnitude < City.TRAFFIC_RANGE
end

local function findSignals(city: Instance)
	signals = {}
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SignalColor") then
			table.insert(signals, d)
		end
	end
	lastLights = nil
end

function TrafficController.Attach(city: Instance)
	findSignals(city)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Traffic"
		folder.Parent = workspace
	end
	TrafficController.Rebuild()
	TrafficController.UpdateLights()
end

local function frame(dt: number)
	accumulator += dt
	local stepEvery = if isMobile() then 1 / 20 else 1 / 30
	if accumulator < stepEvery then
		return
	end
	local step = math.min(accumulator, 0.2)
	accumulator = 0
	if not folder then
		local city = workspace:FindFirstChild(City.NAME)
		if not city then
			return
		end
		TrafficController.Attach(city)
	end
	local near = cameraNear()
	if near ~= active then
		active = near
		folder.Parent = if near then workspace else nil
	end
	if not active then
		return
	end
	local t = serverTime()
	TrafficController.UpdateLights(t)
	TrafficController.Step(step, t)
end

function TrafficController.Init()
	if initialized then
		return
	end
	initialized = true
	buildPath()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(frame, dt)
		if not ok then
			warn("[Circulation] " .. tostring(err))
		end
	end)
end

-- Pour les tests : prépare la boucle sans brancher Heartbeat.
function TrafficController.Prepare()
	if loopLength == 0 then
		buildPath()
	end
	return loopLength, #stops
end

return TrafficController
