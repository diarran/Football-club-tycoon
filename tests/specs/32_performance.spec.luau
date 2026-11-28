-- Performances sur téléphone : décor allégé (contacts, rayons, ombres), budget de
-- Parts et de lumières par terrain au maximum (installations niveau 5 + mode
-- Création complet), projecteurs lointains éteints côté client.
local S = H.boot(MODULES)
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local WorldConfig = mock.run(MODULES.WorldConfig)
local Campus = mock.run(MODULES.Campus)
local PartUtil = mock.run(MODULES.PartUtil)

local PLOT_PARTS_MAX = 2400 -- mesuré : 2 189 au maximum (27/11)
local PLOT_SHADOWS_MAX = 1100 -- Parts qui projettent une ombre (mesuré : 963)
local PLOT_LIGHTS_MAX = 30 -- mesuré : 24

local players = {}
for i = 1, WorldConfig.MAX_PLOTS do
	local p = H.join(i)
	players[i] = p
	local data = S.PlayerDataService.GetData(p)
	data.coins = 1e9
	data.club.division = "D1"
	data.missions.list = {}
	for id in S.Buildings.Definitions do
		while data.buildings[id] < 5 do
			H.advance(1)
			H.fire(p, "RequestUpgrade", id)
		end
	end
	for parcel = 1, #Campus.Parcels do
		H.advance(Campus.MOVE_COOLDOWN + 1)
		H.fire(p, "RequestCampus", "unlock", parcel)
	end
	local n = 0
	for id in Campus.Definitions do
		n += 1
		H.advance(Campus.MOVE_COOLDOWN + 1)
		H.fire(p, "RequestCampus", "build", id, n, 0)
		for _ = 2, Campus.MAX_LEVEL do
			H.advance(Campus.MOVE_COOLDOWN + 1)
			H.fire(p, "RequestCampus", "upgrade", id)
		end
	end
end
H.advance(5)

local function needsTouch(part): boolean
	return part:IsA("Seat") or part:IsA("VehicleSeat") or part:IsA("SpawnLocation")
end

local function audit(root)
	local r = { parts = 0, shadows = 0, lights = 0, problems = {} }
	local function problem(text)
		if #r.problems < 5 then
			table.insert(r.problems, text)
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			r.parts += 1
			if d.CastShadow ~= false then
				r.shadows += 1
			end
			if d.Anchored == true and not needsTouch(d) then
				if d.CanTouch ~= false then
					problem("CanTouch : " .. d:GetFullName())
				end
				if d.CanCollide == false and d.CanQuery ~= false and not d:FindFirstChildWhichIsA("ProximityPrompt") then
					problem("CanQuery : " .. d:GetFullName())
				end
				if d:GetAttribute("Detail") == true and (d.CanCollide ~= false or d.CastShadow ~= false) then
					problem("détail qui bloque ou fait de l'ombre : " .. d:GetFullName())
				end
				if (d.Material == Enum.Material.Neon or d.Material == Enum.Material.Glass) and d.CastShadow ~= false then
					problem("néon/verre avec ombre : " .. d:GetFullName())
				end
				local s = d.Size
				if math.max(s.X, s.Y, s.Z) < PartUtil.SMALL_SHADOW and d.CastShadow ~= false then
					problem("petite pièce avec ombre : " .. d:GetFullName())
				end
			end
		elseif d:IsA("Light") then
			r.lights += 1
			if d.Shadows == true then
				problem("lumière avec ombres : " .. d:GetFullName())
			end
		end
	end
	return r
end

H.test("terrain au maximum (niveau 5 + 10 bâtiments niveau 3) : budget de Parts, d'ombres et de lumières", function()
	for slot = 1, WorldConfig.MAX_PLOTS do
		local plot = WorldBuilder.getPlot(slot)
		H.ok(plot, "terrain " .. slot)
		H.ok(plot:FindFirstChild("Campus"), "zone Création construite")
		local r = audit(plot)
		H.ok(r.parts <= PLOT_PARTS_MAX, ("au plus %d Parts (%d)"):format(PLOT_PARTS_MAX, r.parts))
		H.ok(r.shadows <= PLOT_SHADOWS_MAX, ("au plus %d Parts avec ombre (%d)"):format(PLOT_SHADOWS_MAX, r.shadows))
		H.ok(r.lights <= PLOT_LIGHTS_MAX, ("au plus %d lumières (%d)"):format(PLOT_LIGHTS_MAX, r.lights))
		H.eq(#r.problems, 0, "décor allégé : " .. table.concat(r.problems, " / "))
	end
	H.eq(#H.errors, 0, "aucune erreur serveur")
end)

H.test("quartier et installation reconstruite : allégés aussi", function()
	local district = workspace:FindFirstChild(WorldConfig.DISTRICT_NAME)
	H.ok(district, "quartier")
	local r = audit(district)
	H.eq(#r.problems, 0, "quartier allégé : " .. table.concat(r.problems, " / "))
	local plot = WorldBuilder.getPlot(1)
	local model = WorldBuilder.setFacilityLevel(plot, "Stands", 3)
	H.ok(model, "stade reconstruit")
	H.eq(#audit(model).problems, 0, "installation reconstruite allégée")
end)

H.test("optimize : ne touche ni aux sièges, ni aux pièces mobiles, ni aux invites", function()
	local folder = Instance.new("Folder")
	local seat = Instance.new("Seat")
	seat.Anchored = true
	seat.Parent = folder
	local loose = Instance.new("Part")
	loose.Anchored = false
	loose.Parent = folder
	local door = Instance.new("Part")
	door.Anchored = true
	door.CanCollide = false
	door.Size = Vector3.new(4, 8, 1)
	door.Parent = folder
	Instance.new("ProximityPrompt").Parent = door
	PartUtil.optimize(folder)
	H.ok(seat.CanTouch ~= false, "siège : on peut toujours s'asseoir")
	H.ok(loose.CanTouch ~= false, "pièce mobile intacte")
	H.eq(door.CanTouch, false, "porte : pas de contact")
	H.ok(door.CanQuery ~= false, "porte avec invite : toujours visable")
	H.eq(PartUtil.optimize(nil), 0, "rien à faire sans modèle")
end)

H.test("client : la nuit, les projecteurs loin de la caméra restent éteints", function()
	local p = players[1]
	H.startClient(MODULES, p)
	local WeatherCtl = mock.run(MODULES.Client_WeatherController)
	local Weather = mock.run(MODULES.Weather)
	local camera = workspace.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = workspace
		workspace.CurrentCamera = camera
	end
	camera.CFrame = CFrame.new(0, 20, 0)
	local function lamp(x)
		local part = Instance.new("Part")
		part.Name = "Lamps"
		part.Anchored = true
		part.Position = Vector3.new(x, 10, 0)
		local spot = Instance.new("SpotLight")
		spot.Brightness = 3
		spot.Parent = part
		part.Parent = workspace
		workspace.DescendantAdded:Fire(part)
		workspace.DescendantAdded:Fire(spot)
		return spot
	end
	local near, far = lamp(100), lamp(2000)
	WeatherCtl.Init()
	local night
	for i = 0, 5000 do
		local t = 1_782_864_000 + i * Weather.SLOT_SECONDS + 30
		if Weather.IsNight(t) and Weather.At(t) == "Clear" then
			night = t
			break
		end
	end
	WeatherCtl.SetTimeOverride(night)
	H.eq(near.Enabled, true, "projecteur proche allumé la nuit")
	H.eq(far.Enabled, false, "projecteur lointain éteint (rien à dessiner)")
	camera.CFrame = CFrame.new(1950, 20, 0)
	WeatherCtl.Update(false)
	H.eq(far.Enabled, true, "on s'approche : il s'allume")
	H.eq(near.Enabled, false, "l'autre, désormais loin, s'éteint")
	WeatherCtl.SetTimeOverride(nil)
end)
