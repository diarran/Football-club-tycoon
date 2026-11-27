--[[
	WeatherController
	Ciel du quartier côté client : cycle jour/nuit, projecteurs allumés la nuit,
	pluie, vent ou neige selon la météo du moment (Weather.lua).

	- La météo et l'heure viennent de l'heure du serveur : tous les joueurs voient
	  la même chose, et c'est la même météo que celle qui compte dans les matchs.
	- Léger pour téléphone : mise à jour 2 fois par seconde, un seul émetteur de
	  particules (moitié moins de particules sur écran tactile), projecteurs
	  éteints le jour (moins de lumières à calculer).
	- Paramètres > « Effets météo » : coupe la pluie, la neige et le brouillard.
	  Le jour/nuit et les projecteurs restent (ils ne coûtent presque rien).
	- Pendant un replay : projecteurs plus forts, allumés aussi par mauvais temps.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Weather = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weather"))

local WeatherController = {}

local UPDATE_EVERY = 0.5
local LIGHT_PARTS = { Lamps = true, LightHead = true, Lamp = true } -- projecteurs et lampadaires
local MATCH_BRIGHTNESS = 1.5 -- projecteurs plus forts pendant un match de nuit
local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_AMBIENT = Color3.fromRGB(70, 74, 96) -- assez clair pour voir le terrain la nuit

local effectsEnabled = true
local matchMode = false
local initialized = false
local lights = setmetatable({}, { __mode = "k" }) -- [Light] = luminosité d'origine
local lightCount = 0
local current = { kind = nil, night = nil, lightsOn = nil, rate = -1 }
local emitterPart = nil
local emitter = nil
local original = nil -- réglages de Lighting avant la météo (restaurés quand on coupe)
local overrideTime = nil -- tests : heure imposée
local elapsed = 0

local function now(): number
	if overrideTime then
		return overrideTime
	end
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function isMobile(): boolean
	local ok, touch = pcall(function()
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end)
	return ok and touch == true
end

-- Projecteurs -------------------------------------------------------------

local function isFloodlight(instance: Instance): boolean
	if not (instance:IsA("SpotLight") or instance:IsA("PointLight")) then
		return false
	end
	local parent = instance.Parent
	return parent ~= nil and LIGHT_PARTS[parent.Name] == true
end

local function applyLight(light, on: boolean)
	light.Enabled = on
	local base = lights[light] or 1
	light.Brightness = if on and matchMode then base * MATCH_BRIGHTNESS else base
end

local function track(instance: Instance)
	if lights[instance] == nil and isFloodlight(instance) then
		lights[instance] = instance.Brightness or 1
		lightCount += 1
		if current.lightsOn ~= nil then
			applyLight(instance, current.lightsOn)
		end
	end
end

local function scanLights()
	for _, d in workspace:GetDescendants() do
		track(d)
	end
end

local function lightsWanted(kind: string, night: boolean): boolean
	if night then
		return true
	end
	-- Match par temps gris : on allume aussi les projecteurs.
	return matchMode and (kind == "Rain" or kind == "Snow" or kind == "Cloudy")
end

-- Particules ----------------------------------------------------------------

local function getEmitter()
	if emitter and emitterPart and emitterPart.Parent then
		return emitter
	end
	local part = Instance.new("Part")
	part.Name = "WeatherCloud"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(120, 1, 120)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Precipitation"
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 0.6
	e.Parent = part
	part.Parent = workspace.CurrentCamera or workspace
	emitterPart, emitter = part, e
	return e
end

-- Réglages des particules pour chaque météo (purement visuel).
local function styleEmitter(e, kind: string)
	if kind == "Rain" then
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Speed = NumberRange.new(55, 65)
		e.Lifetime = NumberRange.new(1, 1.2)
		e.Size = NumberSequence.new(0.12)
		e.Squash = NumberSequence.new(3)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
		e.Transparency = NumberSequence.new(0.35)
		e.SpreadAngle = Vector2.new(4, 4)
		e.Acceleration = Vector3.new(4, 0, 0)
	elseif kind == "Snow" then
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Speed = NumberRange.new(6, 9)
		e.Lifetime = NumberRange.new(5, 6)
		e.Size = NumberSequence.new(0.35)
		e.Squash = NumberSequence.new(0)
		e.Orientation = Enum.ParticleOrientation.FacingCamera
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		e.Transparency = NumberSequence.new(0.1)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(1.5, 0, 0.5)
	else -- Vent : quelques poussières qui filent à l'horizontale
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Speed = NumberRange.new(4, 6)
		e.Lifetime = NumberRange.new(3, 4)
		e.Size = NumberSequence.new(0.25)
		e.Squash = NumberSequence.new(0)
		e.Orientation = Enum.ParticleOrientation.FacingCamera
		e.Color = ColorSequence.new(Color3.fromRGB(210, 200, 170))
		e.Transparency = NumberSequence.new(0.5)
		e.SpreadAngle = Vector2.new(10, 10)
		e.Acceleration = Vector3.new(30, 0, 6)
	end
end

local function saveOriginal()
	if original then
		return
	end
	original = {
		FogEnd = Lighting.FogEnd or 100000,
		FogColor = Lighting.FogColor or Color3.fromRGB(192, 192, 192),
		Brightness = Lighting.Brightness or 2,
	}
end

local function applySky(kind: string)
	saveOriginal()
	if effectsEnabled and (kind == "Rain" or kind == "Snow") then
		Lighting.FogEnd = if kind == "Snow" then 450 else 650
		Lighting.FogColor = if kind == "Snow" then Color3.fromRGB(225, 230, 240) else Color3.fromRGB(150, 160, 175)
		Lighting.Brightness = original.Brightness * 0.75
	elseif effectsEnabled and kind == "Cloudy" then
		Lighting.FogEnd = original.FogEnd
		Lighting.FogColor = original.FogColor
		Lighting.Brightness = original.Brightness * 0.85
	else
		Lighting.FogEnd = original.FogEnd
		Lighting.FogColor = original.FogColor
		Lighting.Brightness = original.Brightness
	end
end

-- Mise à jour -----------------------------------------------------------------

function WeatherController.Update(force: boolean?)
	local t = now()
	local kind = Weather.At(t)
	local night = Weather.IsNight(t)

	Lighting.ClockTime = Weather.ClockTime(t)
	if force or night ~= current.night then
		Lighting.OutdoorAmbient = if night then NIGHT_AMBIENT else DAY_AMBIENT
	end

	local lightsOn = lightsWanted(kind, night)
	if force or lightsOn ~= current.lightsOn then
		current.lightsOn = lightsOn
		for light in lights do
			if light.Parent then
				applyLight(light, lightsOn)
			end
		end
	end

	local rate = if effectsEnabled then Weather.ParticleRate(kind, isMobile()) else 0
	if force or kind ~= current.kind or rate ~= current.rate then
		applySky(kind)
		local e = getEmitter()
		if rate > 0 then
			styleEmitter(e, kind)
		end
		e.Rate = rate
		e.Enabled = rate > 0
		current.rate = rate
	end
	current.kind, current.night = kind, night

	-- Le nuage de particules suit la caméra (au-dessus d'elle).
	if emitterPart and current.rate > 0 then
		local camera = workspace.CurrentCamera
		if camera and camera.CFrame then
			local p = camera.CFrame.Position
			emitterPart.CFrame = CFrame.new(p.X, p.Y + 40, p.Z)
		end
	end
end

function WeatherController.SetEffectsEnabled(enabled: boolean)
	effectsEnabled = enabled ~= false
	WeatherController.Update(true)
end

-- Replay d'un match : projecteurs plus forts (et allumés par temps gris).
function WeatherController.SetMatchMode(on: boolean)
	matchMode = on == true
	WeatherController.Update(true)
end

function WeatherController.Init()
	if initialized then
		return
	end
	initialized = true
	scanLights()
	local added = workspace.DescendantAdded
	if added then
		added:Connect(track) -- terrains reconstruits (amélioration du stade)
	end
	WeatherController.Update(true)
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= UPDATE_EVERY then
			elapsed = 0
			WeatherController.Update(false)
		end
	end)
end

-- Tests : impose une heure (nil = heure du serveur).
function WeatherController.SetTimeOverride(t: number?)
	overrideTime = t
	WeatherController.Update(true)
end

function WeatherController.Debug()
	local enabledLights = 0
	for light in lights do
		if light.Enabled then
			enabledLights += 1
		end
	end
	return {
		kind = current.kind,
		night = current.night,
		lightsOn = current.lightsOn,
		rate = current.rate,
		lightCount = lightCount,
		enabledLights = enabledLights,
		effectsEnabled = effectsEnabled,
		matchMode = matchMode,
		emitter = emitter,
	}
end

return WeatherController
