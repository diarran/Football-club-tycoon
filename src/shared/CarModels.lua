--!strict
--[[
	CarModels — silhouettes 3D des voitures (partagé : le serveur s'en sert pour
	les voitures des joueurs et la vitrine du concessionnaire, le client pour la
	circulation des PNJ).

	CarModels.Build(shape, color, cframe) renvoie un Model ANCRÉ :
	  - « Chassis » = PrimaryPart invisible (boîte de la caisse), au ras des roues ;
	  - caisse peinte, habitacle vitré, toit, 4 roues, phares, feux arrière,
	    aileron pour les sportives. 9 à 12 Parts seulement (budget téléphone).
	L'avant de la voiture est côté -Z (comme LookVector). `cframe` = centre au sol.
]]

local CarModels = {}

local GLASS = Color3.fromRGB(28, 34, 42)
local TIRE = Color3.fromRGB(22, 22, 24)
local RIM = Color3.fromRGB(190, 192, 198)
local HEAD = Color3.fromRGB(255, 244, 214)
local TAIL = Color3.fromRGB(200, 20, 24)
local GOLD = Color3.fromRGB(212, 175, 55)

-- length (Z), width (X), body = hauteur de caisse, cabin = { longueur, hauteur, décalage avant/arrière }
CarModels.SHAPES = {
	hatch = { length = 9, width = 4.6, body = 1.6, cabin = { 4.8, 1.5, 0.8 } },
	sedan = { length = 11, width = 4.8, body = 1.5, cabin = { 5.2, 1.4, 0.4 } },
	coupe = { length = 10.5, width = 4.8, body = 1.4, cabin = { 4.2, 1.2, 0.6 } },
	suv = { length = 11.5, width = 5.2, body = 2.1, cabin = { 6.4, 1.8, 0.8 } },
	sport = { length = 11, width = 5, body = 1.2, cabin = { 3.8, 1.05, 0.6 }, spoiler = true },
	super = { length = 11.5, width = 5.2, body = 1.1, cabin = { 3.4, 0.95, 0.4 }, spoiler = true, stripe = true },
}

CarModels.WHEEL = 2 -- diamètre des roues

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		for key, value in opts do
			(p :: any)[key] = value
		end
	end
	p.Parent = model
	return p
end

function CarModels.Dimensions(shape: string)
	return CarModels.SHAPES[shape] or CarModels.SHAPES.sedan
end

-- Construit la voiture (Model ancré, sans collision) centrée au sol en `cframe`.
function CarModels.Build(shape: string, color: Color3, cframe: CFrame, name: string?): Model
	local s = CarModels.Dimensions(shape)
	local model = Instance.new("Model")
	model.Name = name or "Car"
	model:SetAttribute("Shape", shape)
	local wheelR = CarModels.WHEEL / 2
	local bodyBottom = wheelR + 0.1
	local bodyY = bodyBottom + s.body / 2

	local chassis = part(model, "Chassis", Vector3.new(s.width, s.body, s.length), cframe * CFrame.new(0, bodyY, 0), color, Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CastShadow = false,
	})
	model.PrimaryPart = chassis

	part(model, "Body", Vector3.new(s.width, s.body, s.length), cframe * CFrame.new(0, bodyY, 0), color, Enum.Material.SmoothPlastic, {
		Reflectance = 0.08,
	})
	local cabinLen, cabinH, cabinShift = s.cabin[1], s.cabin[2], s.cabin[3]
	local cabinY = bodyBottom + s.body + cabinH / 2
	part(model, "Cabin", Vector3.new(s.width - 0.5, cabinH, cabinLen), cframe * CFrame.new(0, cabinY, cabinShift), GLASS, Enum.Material.Glass, {
		Transparency = 0.15,
		Reflectance = 0.25,
		CastShadow = false,
	})
	part(model, "Roof", Vector3.new(s.width - 0.7, 0.2, cabinLen - 0.8), cframe * CFrame.new(0, cabinY + cabinH / 2 + 0.1, cabinShift), color, Enum.Material.SmoothPlastic)

	local axle = s.length / 2 - 1.8
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local wheel = part(
				model,
				"Wheel",
				Vector3.new(0.8, CarModels.WHEEL, CarModels.WHEEL),
				cframe * CFrame.new(sx * (s.width / 2 - 0.3), wheelR, sz * axle),
				TIRE,
				Enum.Material.Rubber,
				{ Shape = Enum.PartType.Cylinder }
			)
			wheel:SetAttribute("Detail", true)
			wheel.CastShadow = false
		end
	end
	local front = -s.length / 2 - 0.05
	part(model, "Headlights", Vector3.new(s.width - 1, 0.35, 0.1), cframe * CFrame.new(0, bodyY + s.body * 0.15, front), HEAD, Enum.Material.Neon, { CastShadow = false })
	part(model, "Taillights", Vector3.new(s.width - 1, 0.3, 0.1), cframe * CFrame.new(0, bodyY + s.body * 0.15, -front), TAIL, Enum.Material.Neon, { CastShadow = false })
	if s.spoiler then
		local spoiler = part(model, "Spoiler", Vector3.new(s.width - 0.6, 0.15, 1.1), cframe * CFrame.new(0, bodyBottom + s.body + 0.6, s.length / 2 - 0.7), TIRE, Enum.Material.Metal)
		spoiler:SetAttribute("Detail", true)
	end
	if s.stripe then
		local stripe = part(model, "Stripe", Vector3.new(0.8, 0.05, s.length - 0.4), cframe * CFrame.new(0, bodyBottom + s.body + 0.02, 0), GOLD, Enum.Material.Metal)
		stripe:SetAttribute("Detail", true)
	end
	-- Jantes visibles sur les voitures de luxe (petites pièces = détail).
	if shape == "sport" or shape == "super" or shape == "suv" then
		for _, sx in { -1, 1 } do
			local rim = part(model, "Rim", Vector3.new(0.1, 1.2, 1.2), cframe * CFrame.new(sx * (s.width / 2 + 0.12), wheelR, -axle), RIM, Enum.Material.Metal, {
				Shape = Enum.PartType.Cylinder,
				CastShadow = false,
			})
			rim:SetAttribute("Detail", true)
		end
	end
	return model
end

return CarModels
