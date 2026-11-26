--!strict
--[[
	PartUtil — petites fonctions utilitaires pour fabriquer le décor à partir de Parts.

	Toutes les positions passées à ces fonctions sont RELATIVES à un CFrame
	d'origine (le centre d'une installation, au niveau de son sol). On écrit donc
	« un mur à 5 studs à droite et 3 studs de haut » sans se soucier de l'endroit
	où se trouve le terrain dans le monde, ni de son orientation.

	Toutes les Parts créées sont ancrées (Anchored = true).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))

local PartUtil = {}

export type BoxOptions = {
	canCollide: boolean?, -- true par défaut
	transparency: number?,
	reflectance: number?,
	rotX: number?, -- rotations locales en degrés
	rotY: number?,
	rotZ: number?,
	castShadow: boolean?,
	shape: Enum.PartType?,
	className: string?, -- "Part" (défaut), "WedgePart", "SpawnLocation"…
}

-- Informations transmises à chaque module d'installation.
export type BuildContext = {
	slotIndex: number,
	clubName: string,
	primary: Color3, -- couleur principale du club
	secondary: Color3, -- couleur secondaire du club
}

-- Crée un Model nommé, avec des Attributes facultatifs.
function PartUtil.model(parent: Instance?, name: string, attributes: { [string]: any }?): Model
	local model = Instance.new("Model")
	model.Name = name
	if attributes then
		for key, value in attributes do
			model:SetAttribute(key, value)
		end
	end
	model.Parent = parent
	return model
end

-- Crée une Part (pavé) de taille `size`, centrée en `pos` relativement à `origin`.
function PartUtil.box(
	parent: Instance,
	origin: CFrame,
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material,
	opts: BoxOptions?
): BasePart
	local o: BoxOptions = opts or {}
	local part = Instance.new((o.className or "Part") :: any) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = if o.canCollide == nil then true else o.canCollide
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = o.transparency or 0
	part.Reflectance = o.reflectance or 0
	if o.castShadow ~= nil then
		part.CastShadow = o.castShadow
	end
	if o.shape and part:IsA("Part") then
		(part :: Part).Shape = o.shape
	end
	local rotation = CFrame.Angles(math.rad(o.rotX or 0), math.rad(o.rotY or 0), math.rad(o.rotZ or 0))
	part.CFrame = origin * CFrame.new(pos) * rotation
	part.Parent = parent
	return part
end

-- Pavé posé sur un sol : `base` = position du CENTRE DE LA BASE (Y = bas de la Part).
function PartUtil.block(
	parent: Instance,
	origin: CFrame,
	name: string,
	size: Vector3,
	base: Vector3,
	color: Color3,
	material: Enum.Material,
	opts: BoxOptions?
): BasePart
	return PartUtil.box(parent, origin, name, size, base + Vector3.new(0, size.Y / 2, 0), color, material, opts)
end

-- Cylindre vertical (poteau, pylône, fontaine…) posé au sol en `base`.
function PartUtil.cylinder(
	parent: Instance,
	origin: CFrame,
	name: string,
	diameter: number,
	height: number,
	base: Vector3,
	color: Color3,
	material: Enum.Material,
	opts: BoxOptions?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = if opts and opts.canCollide ~= nil then opts.canCollide else true
	part.Transparency = if opts and opts.transparency then opts.transparency else 0
	-- Un cylindre Roblox est orienté selon son axe X : on le tourne de 90° sur Z.
	part.Size = Vector3.new(height, diameter, diameter)
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = origin * CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = parent
	return part
end

-- Boule (ballon, sculpture…) centrée en `pos`.
function PartUtil.ball(
	parent: Instance,
	origin: CFrame,
	name: string,
	diameter: number,
	pos: Vector3,
	color: Color3,
	material: Enum.Material
): BasePart
	return PartUtil.box(parent, origin, name, Vector3.new(diameter, diameter, diameter), pos, color, material, {
		shape = Enum.PartType.Ball,
	})
end

-- Ligne au sol entre deux points (X, Z) locaux, à la hauteur `y`.
-- Sert aux marquages du terrain et de la route. Sans collision.
function PartUtil.line(
	parent: Instance,
	origin: CFrame,
	name: string,
	from: Vector2,
	to: Vector2,
	width: number,
	y: number,
	color: Color3
): BasePart
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	-- Angle autour de Y : la Part est allongée sur son axe X local.
	local yaw = math.deg(math.atan2(-delta.Y, delta.X))
	return PartUtil.box(
		parent,
		origin,
		name,
		Vector3.new(length + width, 0.05, width),
		Vector3.new(mid.X, y, mid.Y),
		color,
		Enum.Material.SmoothPlastic,
		{ canCollide = false, rotY = yaw, castShadow = false }
	)
end

-- Arc de cercle au sol approché par `segments` lignes droites.
-- Angles en degrés, 0° = axe +X local, sens trigonométrique vers +Z.
function PartUtil.arc(
	parent: Instance,
	origin: CFrame,
	name: string,
	center: Vector2,
	radius: number,
	startDeg: number,
	endDeg: number,
	segments: number,
	width: number,
	y: number,
	color: Color3
)
	local step = (endDeg - startDeg) / segments
	for i = 0, segments - 1 do
		local a1 = math.rad(startDeg + step * i)
		local a2 = math.rad(startDeg + step * (i + 1))
		local p1 = center + Vector2.new(math.cos(a1), math.sin(a1)) * radius
		local p2 = center + Vector2.new(math.cos(a2), math.sin(a2)) * radius
		PartUtil.line(parent, origin, name, p1, p2, width, y, color)
	end
end

-- Ajoute un texte (SurfaceGui + TextLabel) sur une face d'une Part.
-- `text` peut être une clé de Locale (ex. "world.offices") : le texte est alors
-- traduit dans la langue de chaque joueur (params remplit les {noms}).
function PartUtil.label(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	textColor: Color3,
	backgroundColor: Color3?,
	params: { [string]: any }?
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0.2
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if backgroundColor then 0 else 1
	label.BackgroundColor3 = backgroundColor or Color3.new(0, 0, 0)
	label.BorderSizePixel = 0
	if Locale.Strings[Locale.DEFAULT][text] then
		Locale.Tag(label, text, params)
	else
		label.Text = text
	end
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	-- Petite marge intérieure pour que le texte ne touche pas les bords.
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	return label
end

-- Pièce invisible servant de PrimaryPart (empreinte au sol de l'installation).
-- BuildingService peut s'en servir pour placer une interface ou une caméra.
function PartUtil.anchor(model: Model, origin: CFrame, footprint: Vector2, height: number): BasePart
	local root = PartUtil.box(
		model,
		origin,
		"Root",
		Vector3.new(footprint.X, height, footprint.Y),
		Vector3.new(0, height / 2, 0),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ canCollide = false, transparency = 1, castShadow = false }
	)
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root
	return root
end

export type ShellStyle = {
	wallColor: Color3,
	wallMaterial: Enum.Material,
	roofColor: Color3,
	doorWidth: number?,
	doorHeight: number?,
	windows: boolean?, -- bandeaux vitrés sur les côtés et l'arrière
	glassFront: boolean?, -- façade avant entièrement vitrée (style moderne)
	accent: Color3?, -- bandeau de couleur en haut des murs
	roofOverhang: number?,
	floors: number?, -- nombre d'étages (planchers intermédiaires ; un bandeau vitré par étage dès 3)
}

-- Bâtiment creux simple (sol, 4 murs, ouverture de porte, toit plat).
-- Repère : centre du bâtiment au sol, porte sur la face avant (-Z).
-- `size` = largeur (X), hauteur des murs (Y), profondeur (Z).
-- Renvoie la position locale du bas de la porte (centre de l'ouverture).
function PartUtil.shell(parent: Instance, origin: CFrame, size: Vector3, style: ShellStyle): Vector3
	local w, h, d = size.X, size.Y, size.Z
	local t = 0.6 -- épaisseur des murs
	local floorH = 0.4
	local dw = style.doorWidth or 5
	local dh = math.min(style.doorHeight or 7.5, h - 1)
	local wallColor, wallMat = style.wallColor, style.wallMaterial
	local glass = Color3.fromRGB(150, 200, 230)

	PartUtil.block(parent, origin, "Floor", Vector3.new(w, floorH, d), Vector3.zero, Color3.fromRGB(150, 150, 146), Enum.Material.Concrete)
	PartUtil.block(parent, origin, "WallBack", Vector3.new(w, h, t), Vector3.new(0, floorH, d / 2 - t / 2), wallColor, wallMat)
	for _, side in { -1, 1 } do
		PartUtil.block(
			parent,
			origin,
			"WallSide",
			Vector3.new(t, h, d - 2 * t),
			Vector3.new(side * (w / 2 - t / 2), floorH, 0),
			wallColor,
			wallMat
		)
	end

	-- Façade avant : deux pans de chaque côté de la porte + linteau.
	local pierWidth = (w - dw) / 2
	local frontColor = if style.glassFront then glass else wallColor
	local frontMat = if style.glassFront then Enum.Material.Glass else wallMat
	local frontOpts: BoxOptions? = if style.glassFront then { transparency = 0.35 } else nil
	for _, side in { -1, 1 } do
		PartUtil.block(
			parent,
			origin,
			"WallFront",
			Vector3.new(pierWidth, h, t),
			Vector3.new(side * (dw / 2 + pierWidth / 2), floorH, -d / 2 + t / 2),
			frontColor,
			frontMat,
			frontOpts
		)
	end
	PartUtil.block(
		parent,
		origin,
		"Lintel",
		Vector3.new(dw, h - dh, t),
		Vector3.new(0, floorH + dh, -d / 2 + t / 2),
		wallColor,
		wallMat
	)

	-- Bandeaux vitrés : un seul jusqu'à 2 étages, un par étage à partir de 3.
	local floors = style.floors or 1
	local bands = if floors >= 3 then floors else 1
	for band = 1, if style.windows then bands else 0 do
		local storey = h / bands
		local winH = storey * 0.32
		local winY = floorH + (band - 1) * storey + storey * 0.42
		for _, side in { -1, 1 } do
			PartUtil.block(
				parent,
				origin,
				"Window",
				Vector3.new(0.1, winH, d * 0.6),
				Vector3.new(side * (w / 2 + 0.05), winY, 0),
				glass,
				Enum.Material.Glass,
				{ transparency = 0.2 }
			)
		end
		PartUtil.block(
			parent,
			origin,
			"Window",
			Vector3.new(w * 0.7, winH, 0.1),
			Vector3.new(0, winY, d / 2 + 0.05),
			glass,
			Enum.Material.Glass,
			{ transparency = 0.2 }
		)
		if not style.glassFront then
			for _, side in { -1, 1 } do
				PartUtil.block(
					parent,
					origin,
					"Window",
					Vector3.new(pierWidth * 0.6, winH, 0.1),
					Vector3.new(side * (dw / 2 + pierWidth / 2), winY, -d / 2 - 0.05),
					glass,
					Enum.Material.Glass,
					{ transparency = 0.2 }
				)
			end
		end
	end

	for level = 1, floors - 1 do
		PartUtil.block(
			parent,
			origin,
			"MidFloor",
			Vector3.new(w - 2 * t, 0.4, d - 2 * t),
			Vector3.new(0, floorH + h * level / floors, 0),
			Color3.fromRGB(200, 200, 196),
			Enum.Material.Concrete
		)
	end

	if style.accent then
		PartUtil.block(
			parent,
			origin,
			"Accent",
			Vector3.new(w + 0.3, 0.8, d + 0.3),
			Vector3.new(0, floorH + h - 0.8, 0),
			style.accent,
			Enum.Material.SmoothPlastic
		)
	end

	local overhang = style.roofOverhang or 0.5
	PartUtil.block(
		parent,
		origin,
		"Roof",
		Vector3.new(w + 2 * overhang, 0.6, d + 2 * overhang),
		Vector3.new(0, floorH + h, 0),
		style.roofColor,
		Enum.Material.Concrete
	)

	-- Porte ouverte (battant plaqué contre l'intérieur) : on peut entrer librement.
	PartUtil.block(
		parent,
		origin,
		"Door",
		Vector3.new(0.3, dh, dw - 0.2),
		Vector3.new(-dw / 2 + 0.15, floorH, -d / 2 + t + (dw - 0.2) / 2),
		Color3.fromRGB(92, 64, 44),
		Enum.Material.WoodPlanks
	)

	return Vector3.new(0, floorH, -d / 2)
end

-- Panneau rectangulaire avec texte, collé sur la façade avant (-Z) d'un bâtiment.
function PartUtil.frontSign(
	parent: Instance,
	origin: CFrame,
	text: string,
	size: Vector2,
	pos: Vector3,
	textColor: Color3,
	backColor: Color3
): BasePart
	local sign = PartUtil.box(
		parent,
		origin,
		"Sign",
		Vector3.new(size.X, size.Y, 0.3),
		pos,
		backColor,
		Enum.Material.SmoothPlastic,
		{ canCollide = false }
	)
	PartUtil.label(sign, Enum.NormalId.Front, text, textColor)
	return sign
end

-- Compte les BaseParts d'un objet (utile pour surveiller le budget mobile).
function PartUtil.countParts(root: Instance): number
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return PartUtil
