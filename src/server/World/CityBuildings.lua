--!strict
--[[
	CityBuildings — bâtiments du centre-ville (style semi-réaliste noir et or) :
	concessionnaire auto avec vitrine et parc de voitures, hôtel du club avec
	balcons et dépose-minute VIP, banque à colonnes, cafés sportifs et
	restaurants avec terrasse, tours d'affaires couvertes de publicités de foot.

	Chaque guichet utile (concessionnaire, banque, hôtel) a une Part invisible
	« Counter » (attribut CityCounter = "dealer" / "bank" / "hotel") avec un
	ProximityPrompt : le client ouvre la fenêtre correspondante (CityController).

	Repère : `origin` = centre du rond-point au sol (City.ORIGIN), plan dans
	ReplicatedStorage.Shared.City. Les façades donnent toujours sur le boulevard.
	Budget : ~1 300 Parts pour tout le centre-ville (rues comprises ≈ 1 900).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("City"))
local CarModels = require(Shared:WaitForChild("CarModels"))
local Locale = require(Shared:WaitForChild("Locale"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local World = script.Parent
local PartUtil = require(World:WaitForChild("PartUtil"))
local Props = require(World:WaitForChild("Props"))

local CityBuildings = {}

local C = WorldConfig.COLORS
local TRIM = PartUtil.TRIM
local GOLD = C.Gold
local GLASS = PartUtil.GLASS
local STONE = Color3.fromRGB(222, 216, 204)
local DARK_GLASS = Color3.fromRGB(54, 70, 84)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Repère d'un bâtiment : centre au sol en (x, z), façade (-Z local) tournée de `rotY`.
local function frame(origin: CFrame, x: number, z: number, rotY: number): CFrame
	return origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rotY), 0)
end

-- Façade vers le boulevard : côté -Z du boulevard => bâtiment tourné de 180°.
local function facingBoulevard(z: number): number
	return if z < 0 then 180 else 0
end

local function sign(parent: Instance, o: CFrame, key: string, size: Vector2, pos: Vector3, color: Color3?)
	return PartUtil.frontSign(parent, o, key, size, pos, color or GOLD, TRIM)
end

-- Guichet invisible avec son ProximityPrompt (texte traduit chez chaque joueur).
local function counter(parent: Instance, o: CFrame, pos: Vector3, kind: string)
	local part = PartUtil.box(parent, o, "Counter", v(4, 4, 4), pos + v(0, 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		canCollide = false,
		transparency = 1,
		castShadow = false,
	})
	part.CanQuery = false
	part.CanTouch = false
	part:SetAttribute("CityCounter", kind)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CityPrompt"
	prompt:SetAttribute("CityCounter", kind)
	Locale.Tag(prompt, "city." .. kind .. ".prompt", nil, "ActionText")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return part
end

-- Petit plateau tournant de vitrine (disque sombre bordé d'or).
local function turntable(parent: Instance, o: CFrame, pos: Vector3)
	PartUtil.cylinder(parent, o, "Turntable", 15, 0.4, pos, TRIM, Enum.Material.Marble)
	PartUtil.detail(PartUtil.cylinder(parent, o, "TurntableTrim", 15.4, 0.2, pos, GOLD, Enum.Material.Metal))
end

local function displayCar(parent: Instance, o: CFrame, car, pos: Vector3, rotY: number, color: Color3)
	local model = CarModels.Build(car.shape, color, o * CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0), "DisplayCar")
	model:SetAttribute("CarId", car.id)
	model.Parent = parent
	return model
end

--------------------------------------------------------------------------------
-- Concessionnaire auto
--------------------------------------------------------------------------------

local DISPLAY_COLORS = {
	Color3.fromRGB(236, 236, 236),
	Color3.fromRGB(30, 70, 170),
	Color3.fromRGB(22, 22, 26),
	Color3.fromRGB(170, 174, 182),
	Color3.fromRGB(190, 30, 40),
	GOLD,
}

local function dealer(parent: Instance, origin: CFrame)
	local place = CityConfig.PLACES.Dealer
	local m = PartUtil.model(parent, "Dealer", { CityPlace = "Dealer" })
	local o = frame(origin, place.x, place.z, facingBoulevard(place.z))
	local w, d = place.size.X, place.size.Y
	local h = 13
	PartUtil.shell(m, o, v(w, h, d), {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Concrete,
		roofColor = TRIM,
		doorWidth = 10,
		doorHeight = 9,
		glassFront = true,
		accent = GOLD,
		canopy = true,
		roofUnits = false,
	})
	-- Sol de showroom poli et grande enseigne lumineuse.
	PartUtil.block(m, o, "ShowroomFloor", v(w - 2, 0.1, d - 2), v(0, 0.4, 0), Color3.fromRGB(226, 224, 220), Enum.Material.Marble, { castShadow = false })
	sign(m, o, "city.dealer.sign", Vector2.new(40, 4), v(0, h + 3.2, -d / 2 + 0.4))
	-- Pylône d'enseigne au bord du trottoir.
	PartUtil.block(m, o, "Pylon", v(3, 16, 3), v(w / 2 - 4, 0, -d / 2 - 14), TRIM, Enum.Material.Metal)
	local pylonSign = PartUtil.box(m, o, "PylonSign", v(7, 4, 0.4), v(w / 2 - 4, 14, -d / 2 - 15.7), C.Charcoal, Enum.Material.SmoothPlastic, { canCollide = false })
	PartUtil.label(pylonSign, Enum.NormalId.Front, "city.dealer.short", GOLD)

	-- Vitrine : les 3 premières voitures dedans sur plateaux, les 3 suivantes dehors.
	for i, car in CityConfig.CARS do
		local color = DISPLAY_COLORS[(i - 1) % #DISPLAY_COLORS + 1]
		if i <= 3 then
			local x = -w / 2 + 16 + (i - 1) * ((w - 32) / 2)
			local pos = v(x, 0.5, 4)
			turntable(m, o, pos)
			displayCar(m, o, car, pos + v(0, 0.4, 0), 30 + i * 25, color)
		else
			local x = -w / 2 + 18 + (i - 4) * ((w - 36) / 2)
			displayCar(m, o, car, v(x, 0, -d / 2 - 8), 90, color)
		end
	end
	-- Parc extérieur : dalle et petites bornes dorées.
	PartUtil.block(m, o, "Lot", v(w, 0.12, 14), v(0, 0, -d / 2 - 8), Color3.fromRGB(70, 72, 78), Enum.Material.Asphalt, { castShadow = false })
	for i = 0, 5 do
		PartUtil.detail(PartUtil.cylinder(m, o, "Bollard", 0.6, 1.2, v(-w / 2 + 4 + i * (w - 8) / 5, 0.1, -d / 2 - 15.5), GOLD, Enum.Material.Metal))
	end
	counter(m, o, v(0, 0.4, -d / 2 + 6), "dealer")
	PartUtil.block(m, o, "Desk", v(8, 3.2, 2), v(0, 0.4, -d / 2 + 9), TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(m, o, "DeskTop", v(8.4, 0.2, 2.4), v(0, 3.6, -d / 2 + 9), GOLD, Enum.Material.Metal))
	return m
end

--------------------------------------------------------------------------------
-- Hôtel du club
--------------------------------------------------------------------------------

local function hotel(parent: Instance, origin: CFrame)
	local place = CityConfig.PLACES.Hotel
	local m = PartUtil.model(parent, "Hotel", { CityPlace = "Hotel" })
	local o = frame(origin, place.x, place.z, facingBoulevard(place.z))
	local w, d = place.size.X, place.size.Y
	local floors = 9
	local storey = 4.2
	local lobbyH = 8
	local h = lobbyH + floors * storey
	-- Rez-de-chaussée vitré (lobby) puis tour : façade en mur-rideau.
	PartUtil.shell(m, o, v(w, lobbyH, d), {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Concrete,
		roofColor = TRIM,
		doorWidth = 8,
		doorHeight = 6.5,
		glassFront = true,
		canopy = false,
		roofUnits = false,
	})
	local towerW, towerD = w - 8, d - 8
	local ty = lobbyH + 0.4
	PartUtil.block(m, o, "Tower", v(towerW, floors * storey, towerD), v(0, ty, 2), C.Graphite, Enum.Material.Concrete)
	PartUtil.block(m, o, "CurtainWall", v(towerW - 4, floors * storey - 1, 0.3), v(0, ty + 0.5, 2 - towerD / 2 - 0.1), DARK_GLASS, Enum.Material.Glass, {
		reflectance = 0.2,
		castShadow = false,
	})
	for _, side in { -1, 1 } do
		PartUtil.block(m, o, "SideGlass", v(0.3, floors * storey - 1, towerD - 6), v(side * (towerW / 2 + 0.1), ty + 0.5, 2), DARK_GLASS, Enum.Material.Glass, {
			reflectance = 0.2,
			castShadow = false,
		})
	end
	-- Balcons : une dalle par étage et un garde-corps vitré (détail).
	for f = 1, floors do
		local y = ty + f * storey - 0.3
		PartUtil.block(m, o, "Balcony", v(towerW - 2, 0.3, 2.4), v(0, y - storey + 0.3, 2 - towerD / 2 - 1.2), STONE, Enum.Material.Limestone, { castShadow = false })
		PartUtil.detail(PartUtil.block(m, o, "Railing", v(towerW - 2, 1.1, 0.15), v(0, y - storey + 0.6, 2 - towerD / 2 - 2.35), GLASS, Enum.Material.Glass, {
			canCollide = false,
			transparency = 0.5,
		}))
	end
	-- Couronne dorée et enseigne sur le toit.
	PartUtil.block(m, o, "Crown", v(towerW + 0.6, 1.2, towerD + 0.6), v(0, h + 0.4, 2), GOLD, Enum.Material.Metal)
	sign(m, o, "city.hotel.sign", Vector2.new(28, 4.5), v(0, h + 4, 2 - towerD / 2 + 1))
	-- Dépose-minute VIP : marquise, tapis rouge, boucle d'asphalte et voiturier.
	PartUtil.block(m, o, "DropOff", v(w, 0.14, 18), v(0, 0, -d / 2 - 9), C.Asphalt, Enum.Material.Asphalt, { castShadow = false })
	PartUtil.block(m, o, "Marquee", v(16, 0.6, 9), v(0, 7, -d / 2 - 4.5), TRIM, Enum.Material.Metal, { canCollide = false })
	PartUtil.detail(PartUtil.block(m, o, "MarqueeTrim", v(16.4, 0.3, 0.3), v(0, 7.6, -d / 2 - 9), GOLD, Enum.Material.Metal, { canCollide = false }))
	for _, side in { -1, 1 } do
		PartUtil.cylinder(m, o, "MarqueePost", 0.6, 7, v(side * 7.5, 0, -d / 2 - 8.6), GOLD, Enum.Material.Metal)
	end
	PartUtil.block(m, o, "RedCarpet", v(5, 0.06, 10), v(0, 0.14, -d / 2 - 5), C.Carpet, Enum.Material.Fabric, { canCollide = false, castShadow = false })
	displayCar(m, o, CityConfig.CARS[#CityConfig.CARS], v(-12, 0.14, -d / 2 - 9), 90, Color3.fromRGB(22, 22, 26))
	for _, x in { -w / 2 + 3, w / 2 - 3 } do
		Props.planter(m, o, x, -d / 2 - 2)
	end
	counter(m, o, v(0, 0.4, -d / 2 + 4), "hotel")
	PartUtil.block(m, o, "Reception", v(10, 3.2, 2), v(0, 0.4, -d / 2 + 8), TRIM, Enum.Material.Metal)
	PartUtil.detail(PartUtil.block(m, o, "ReceptionTop", v(10.4, 0.2, 2.4), v(0, 3.6, -d / 2 + 8), GOLD, Enum.Material.Metal))
	return m
end

--------------------------------------------------------------------------------
-- Banque
--------------------------------------------------------------------------------

local function bank(parent: Instance, origin: CFrame)
	local place = CityConfig.PLACES.Bank
	local m = PartUtil.model(parent, "Bank", { CityPlace = "Bank" })
	local o = frame(origin, place.x, place.z, facingBoulevard(place.z))
	local w, d = place.size.X, place.size.Y
	local h = 18
	PartUtil.shell(m, o, v(w, h, d), {
		wallColor = STONE,
		wallMaterial = Enum.Material.Limestone,
		roofColor = TRIM,
		doorWidth = 8,
		doorHeight = 10,
		windows = true,
		floors = 2,
		trim = TRIM,
		roofUnits = false,
	})
	-- Portique : emmarchement, 6 colonnes, entablement noir et frise dorée.
	PartUtil.block(m, o, "Steps", v(w - 6, 0.8, 8), v(0, 0, -d / 2 - 4), STONE, Enum.Material.Limestone)
	for i = 0, 5 do
		local x = -w / 2 + 6 + i * (w - 12) / 5
		PartUtil.cylinder(m, o, "Column", 2.2, h - 1.6, v(x, 0.8, -d / 2 - 6), Color3.fromRGB(236, 232, 222), Enum.Material.Marble)
	end
	PartUtil.block(m, o, "Entablature", v(w - 4, 2.2, 9), v(0, h - 0.8, -d / 2 - 4.5), TRIM, Enum.Material.Granite)
	PartUtil.detail(PartUtil.block(m, o, "Frieze", v(w - 3.6, 0.35, 9.4), v(0, h + 1.4, -d / 2 - 4.5), GOLD, Enum.Material.Metal))
	local plate = PartUtil.box(m, o, "BankName", v(26, 1.8, 0.3), v(0, h + 0.3, -d / 2 - 9.1), TRIM, Enum.Material.SmoothPlastic, { canCollide = false })
	PartUtil.label(plate, Enum.NormalId.Front, "city.bank.sign", GOLD)
	counter(m, o, v(0, 0.4, -d / 2 + 4), "bank")
	for _, x in { -12, 0, 12 } do
		PartUtil.block(m, o, "Teller", v(8, 3.6, 1.5), v(x, 0.4, d / 2 - 8), C.WoodDark, Enum.Material.Wood)
	end
	PartUtil.detail(PartUtil.block(m, o, "Vault", v(8, 9, 1), v(0, 0.4, d / 2 - 1.4), Color3.fromRGB(150, 152, 158), Enum.Material.DiamondPlate))
	return m
end

--------------------------------------------------------------------------------
-- Cafés sportifs et restaurants
--------------------------------------------------------------------------------

local SHOPS = {
	{ key = "city.shop.cafe", x = -125, z = 52, awning = Color3.fromRGB(30, 90, 50) },
	{ key = "city.shop.grill", x = -80, z = 52, awning = Color3.fromRGB(150, 30, 34) },
	{ key = "city.shop.pizza", x = -115, z = -52, awning = Color3.fromRGB(196, 120, 30) },
	{ key = "city.shop.brasserie", x = 85, z = 52, awning = Color3.fromRGB(30, 50, 120) },
	{ key = "city.shop.burger", x = 130, z = 52, awning = Color3.fromRGB(40, 40, 44) },
	{ key = "city.shop.juice", x = 105, z = -52, awning = Color3.fromRGB(60, 150, 140) },
}

local function terraceTable(parent: Instance, o: CFrame, x: number, z: number, color: Color3)
	PartUtil.cylinder(parent, o, "TableTop", 2.6, 0.15, v(x, 2.6, z), C.Plaster, Enum.Material.Marble)
	PartUtil.detail(PartUtil.cylinder(parent, o, "TableLeg", 0.3, 2.6, v(x, 0, z), TRIM, Enum.Material.Metal))
	PartUtil.detail(PartUtil.cylinder(parent, o, "ParasolPole", 0.2, 4.4, v(x, 2.75, z), TRIM, Enum.Material.Metal, { canCollide = false }))
	PartUtil.detail(PartUtil.cylinder(parent, o, "Parasol", 5, 0.25, v(x, 7.1, z), color, Enum.Material.Fabric, { canCollide = false }))
end

local function shop(parent: Instance, origin: CFrame, def)
	local m = PartUtil.model(parent, "Shop", { CityPlace = "Shop" })
	local o = frame(origin, def.x, def.z, facingBoulevard(def.z))
	local w, h, d = 28, 9, 18
	PartUtil.shell(m, o, v(w, h, d), {
		wallColor = C.Charcoal,
		wallMaterial = Enum.Material.Brick,
		roofColor = TRIM,
		doorWidth = 5,
		glassFront = true,
		accent = def.awning,
		canopy = false,
		roofUnits = false,
	})
	-- Store-banne rayé (3 bandes) et enseigne.
	for i = -1, 1 do
		local color = if i == 0 then C.Plaster else def.awning
		PartUtil.box(m, o, "Awning", v(w / 3, 0.25, 4), v(i * w / 3, 7.4, -d / 2 - 2), color, Enum.Material.Fabric, { canCollide = false, rotX = -12 })
	end
	sign(m, o, def.key, Vector2.new(20, 2.2), v(0, h + 1.8, -d / 2 + 0.3))
	-- Terrasse (petites pièces = détails, sauf les plateaux).
	for _, x in { -8, 8 } do
		terraceTable(m, o, x, -d / 2 - 6.5, def.awning)
	end
	-- Écran géant dans la vitrine : on y regarde les matchs.
	PartUtil.detail(PartUtil.box(m, o, "MatchScreen", v(7, 4, 0.2), v(-8, 4.5, -d / 2 + 1.2), Color3.fromRGB(70, 150, 90), Enum.Material.Neon, { canCollide = false }))
	return m
end

--------------------------------------------------------------------------------
-- Tours d'affaires couvertes de publicités
--------------------------------------------------------------------------------

local AD_KEYS = { "city.ad.derby", "city.ad.boots", "city.ad.tv", "city.ad.drink", "FC COINS", "city.ad.academy" }

local TOWERS = {
	{ x = 250, z = -95, h = 112, w = 34 },
	{ x = 255, z = 105, h = 92, w = 32 },
	{ x = 110, z = -175, h = 74, w = 30 },
	{ x = 115, z = 190, h = 84, w = 30 },
	{ x = -95, z = 195, h = 62, w = 28 },
	{ x = -105, z = -195, h = 66, w = 28 },
	{ x = 255, z = -225, h = 58, w = 30 },
}

local function tower(parent: Instance, origin: CFrame, def, index: number)
	local m = PartUtil.model(parent, "Tower", { CityPlace = "Tower" })
	local o = frame(origin, def.x, def.z, facingBoulevard(def.z))
	local w, h = def.w, def.h
	PartUtil.block(m, o, "Podium", v(w + 6, 6, w + 6), v(0, 0, 0), C.Charcoal, Enum.Material.Granite)
	PartUtil.block(m, o, "Lobby", v(w - 2, 5.4, 0.3), v(0, 0.3, -(w + 6) / 2 - 0.1), GLASS, Enum.Material.Glass, { transparency = 0.3, castShadow = false })
	-- Noyau en béton derrière le mur-rideau : la tour paraît pleine, même vue de près.
	PartUtil.block(m, o, "Core", v(w - 3, h - 6, w - 3), v(0, 6, 0), C.Graphite, Enum.Material.Concrete)
	PartUtil.block(m, o, "Shaft", v(w, h - 6.4, w), v(0, 6, 0), DARK_GLASS, Enum.Material.Glass, { reflectance = 0.22, transparency = 0.15 })
	-- Ailettes verticales anthracite aux 4 coins et couronne dorée.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartUtil.block(m, o, "Fin", v(1.6, h - 6, 1.6), v(sx * (w / 2), 6, sz * (w / 2)), TRIM, Enum.Material.Metal)
		end
	end
	-- Bandeaux d'étage tous les 12 studs (détails).
	local y = 18
	while y < h - 4 do
		PartUtil.detail(PartUtil.block(m, o, "FloorBand", v(w + 0.4, 0.6, w + 0.4), v(0, y, 0), C.Graphite, Enum.Material.Metal, { canCollide = false }))
		y += 12
	end
	PartUtil.block(m, o, "Crown", v(w + 1, 2, w + 1), v(0, h, 0), GOLD, Enum.Material.Metal)
	PartUtil.detail(PartUtil.cylinder(m, o, "Antenna", 0.6, 14, v(0, h + 2, 0), TRIM, Enum.Material.Metal))
	-- Deux grands panneaux publicitaires : façade (côté boulevard) et côté.
	local face = PartUtil.box(m, o, "AdBoard", v(w - 6, 16, 0.6), v(0, h * 0.62, -w / 2 - 0.6), C.AdBoard, Enum.Material.SmoothPlastic, { canCollide = false })
	PartUtil.label(face, Enum.NormalId.Front, AD_KEYS[(index - 1) % #AD_KEYS + 1], GOLD)
	local side = PartUtil.box(m, o, "AdBoard", v(0.6, 12, w - 8), v(w / 2 + 0.6, h * 0.4, 0), C.AdBoard, Enum.Material.SmoothPlastic, { canCollide = false })
	PartUtil.label(side, Enum.NormalId.Right, AD_KEYS[index % #AD_KEYS + 1], C.SignText)
	-- Liseré lumineux autour du panneau de façade.
	PartUtil.detail(PartUtil.box(m, o, "AdGlow", v(w - 5, 0.4, 0.4), v(0, h * 0.62 - 8.4, -w / 2 - 0.7), GOLD, Enum.Material.Neon, { canCollide = false }))
	return m
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local TREES = {
	{ -160, -42 }, { -300, 45 }, { -205, 45 }, { -160, -120 }, { -160, 130 },
	{ 60, -110 }, { 160, -110 }, { 60, 120 }, { 170, 120 }, { 300, -45 }, { 300, 45 },
	{ 200, -45 }, { 210, 45 }, { -60, -110 }, { -60, 130 },
}

function CityBuildings.build(parent: Instance, origin: CFrame)
	local folder = PartUtil.model(parent, "Buildings")
	dealer(folder, origin)
	hotel(folder, origin)
	bank(folder, origin)
	for _, def in SHOPS do
		shop(folder, origin, def)
	end
	for i, def in TOWERS do
		tower(folder, origin, def, i)
	end
	local green = PartUtil.model(folder, "Trees")
	for _, t in TREES do
		Props.tree(green, origin, t[1], t[2], 1.1)
	end
	for _, t in { { -150, 40 }, { -60, 40 }, { 60, 40 }, { 150, 40 } } do
		Props.bench(green, origin, t[1], t[2], 0)
		Props.bench(green, origin, t[1], -t[2], 180)
	end
	return folder
end

return CityBuildings
