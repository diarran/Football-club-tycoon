--[[
	CarController
	Conduite de SA voiture (CityService) : quand le personnage du joueur est
	assis sur le siège conducteur d'une voiture dont il est propriétaire, ce
	contrôleur lit les commandes du VehicleSeat (ZQSD / flèches au clavier,
	joystick sur téléphone et manette) et pilote les deux contraintes de la
	voiture : LinearVelocity (vitesse dans le plan) et AlignOrientation (cap).
	Le serveur a donné la propriété réseau au conducteur : le mouvement est
	fluide et se voit chez les autres joueurs.

	Un petit compteur de vitesse s'affiche pendant la conduite.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))

local player = Players.LocalPlayer

local CarController = {}

local REVERSE_SHARE = 0.35 -- vitesse maximale en marche arrière (part de la vitesse max)
local KMH = 1.1 -- conversion affichée : 1 stud/s ≈ 1,1 km/h

local state = { seat = nil, speed = 0, yaw = 0 }
local speedo = nil

local function T(key: string, params)
	return Locale.T(Locale.ForPlayer(player), key, params)
end

local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Siège conducteur de SA voiture occupé par le joueur, sinon nil.
function CarController.DrivenSeat()
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return nil
	end
	local model = seat.Parent
	if not model or model:GetAttribute("OwnerId") ~= player.UserId then
		return nil
	end
	return seat
end

-- Un pas de simulation (dt secondes) : vitesse, cap, contraintes. Renvoie la vitesse.
function CarController.Step(seat, dt: number): number
	local model = seat.Parent
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	local velocity = chassis and chassis:FindFirstChild("DriveVelocity")
	local align = chassis and chassis:FindFirstChild("DriveAlign")
	if not velocity or not align then
		return 0
	end
	if state.seat ~= seat then
		state.seat = seat
		state.speed = 0
		state.yaw = yawOf(chassis.CFrame)
	end
	local maxSpeed = model:GetAttribute("MaxSpeed") or 50
	local accel = model:GetAttribute("Accel") or 24
	local turn = math.rad(model:GetAttribute("Turn") or 90)
	local throttle = seat.ThrottleFloat or 0
	local steer = seat.SteerFloat or 0
	local speed = state.speed

	if throttle > 0 then
		local rate = if speed < 0 then accel * 2.5 else accel
		speed += rate * throttle * dt
	elseif throttle < 0 then
		local rate = if speed > 0 then accel * 2.5 else accel * 0.6
		speed += rate * throttle * dt
	else
		-- Roue libre : la voiture ralentit doucement.
		local drag = accel * 0.6 * dt
		speed = if math.abs(speed) <= drag then 0 else speed - drag * math.sign(speed)
	end
	speed = math.clamp(speed, -maxSpeed * REVERSE_SHARE, maxSpeed)

	-- On tourne d'autant mieux qu'on roule (pas de rotation à l'arrêt).
	local grip = math.clamp(math.abs(speed) / 14, 0, 1)
	state.yaw -= steer * turn * grip * dt * math.sign(speed)
	state.speed = speed

	local forward = Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
	velocity.PlaneVelocity = Vector2.new(forward.X * speed, forward.Z * speed)
	align.CFrame = CFrame.Angles(0, state.yaw, 0)
	return speed
end

function CarController.GetSpeed(): number
	return state.speed
end

local function update(dt: number)
	local seat = CarController.DrivenSeat()
	if not seat then
		if state.seat then
			state.seat = nil
			state.speed = 0
		end
		if speedo then
			speedo.Visible = false
		end
		return
	end
	local speed = CarController.Step(seat, dt)
	if speedo then
		speedo.Visible = true
		speedo.Text = T("city.speed", { speed = math.floor(math.abs(speed) * KMH + 0.5) })
	end
end

function CarController.Init(gui: Instance?)
	if gui then
		speedo = Instance.new("TextLabel")
		speedo.Name = "Speedometer"
		speedo.AnchorPoint = Vector2.new(0.5, 1)
		speedo.Position = UDim2.new(0.5, 0, 1, -16)
		speedo.Size = UDim2.fromOffset(150, 40)
		speedo.BackgroundColor3 = Color3.fromRGB(20, 21, 26)
		speedo.BackgroundTransparency = 0.2
		speedo.TextColor3 = Color3.fromRGB(212, 175, 55)
		speedo.Font = Enum.Font.GothamBold
		speedo.TextScaled = true
		speedo.Text = ""
		speedo.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = speedo
		speedo.Parent = gui
	end
	local signal = RunService.RenderStepped or RunService.Heartbeat
	signal:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			warn("[Voiture] " .. tostring(err))
		end
	end)
end

return CarController
