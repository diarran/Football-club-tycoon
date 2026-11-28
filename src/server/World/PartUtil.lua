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
	crest: number?, -- écusson choisi (1 à 6), sinon celui de l'emplacement
	pattern: string?, -- motif du maillot choisi (ClubIdentity), sinon uni
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
	trim: Color3?, -- couleur des angles, de l'acrotère et des cadres (anthracite par défaut)
	canopy: boolean?, -- marquise au-dessus de la porte, avec deux appliques lumineuses
	roofUnits: boolean?, -- climatiseurs sur le toit (true par défaut si le bâtiment est assez large)
}

-- Finitions « semi-réalistes » communes à tous les bâtiments (direction artistique noir / or).
PartUtil.TRIM = Color3.fromRGB(38, 40, 45) -- anthracite : cadres, angles, acrotères
PartUtil.GLASS = Color3.fromRGB(110, 150, 172) -- verre teinté légèrement bleuté
PartUtil.SILL = Color3.fromRGB(196, 194, 188) -- appuis de fenêtre en pierre claire
PartUtil.WARM_LIGHT = Color3.fromRGB(255, 214, 160) -- appliques et lampadaires

-- Marque une Part comme « détail » : le client peut la masquer sur les terrains
-- éloignés ou si le joueur coupe l'option Détails (téléphones peu puissants).
-- Un détail ne projette pas d'ombre (coût de rendu en moins).
function PartUtil.detail(part: BasePart): BasePart
	part:SetAttribute("Detail", true)
	part.CastShadow = false
	return part
end

-- Fenêtre encadrée posée sur une façade : cadre sombre, verre teinté, meneaux et appui.
-- `center` = centre de la fenêtre sur la face extérieure du mur, `normal` = direction
-- vers l'extérieur (±X ou ±Z local). Renvoie le verre.
function PartUtil.window(parent: Instance, origin: CFrame, width: number, height: number, center: Vector3, normal: Vector3): BasePart
	local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X))
	local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z))
	local up = Vector3.new(0, 1, 0)
	local function size(a: number, h: number, depth: number): Vector3
		return along * a + up * h + across * depth
	end
	PartUtil.box(parent, origin, "WindowFrame", size(width + 0.5, height + 0.5, 0.1), center + normal * 0.05, PartUtil.TRIM, Enum.Material.Metal, { canCollide = false })
	local glass = PartUtil.box(parent, origin, "Window", size(width, height, 0.1), center + normal * 0.12, PartUtil.GLASS, Enum.Material.Glass, {
		canCollide = false,
		transparency = 0.25,
		reflectance = 0.12,
		castShadow = false,
	})
	local panes = math.clamp(math.floor(width / 4 + 0.5), 1, 6)
	for i = 1, panes - 1 do
		local offset = -width / 2 + width * i / panes
		PartUtil.detail(PartUtil.box(parent, origin, "Mullion", size(0.18, height, 0.12), center + along * offset + normal * 0.2, PartUtil.TRIM, Enum.Material.Metal, { canCollide = false }))
	end
	PartUtil.detail(
		PartUtil.box(parent, origin, "Sill", size(width + 0.8, 0.22, 0.4), center - up * (height / 2 + 0.36) + normal * 0.2, PartUtil.SILL, Enum.Material.Limestone, { canCollide = false })
	)
	return glass
end

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
	local wallColor = style.wallColor
	-- Le plastique lisse fait « jouet » : les murs passent en enduit (Plaster).
	local wallMat = if style.wallMaterial == Enum.Material.SmoothPlastic then Enum.Material.Plaster else style.wallMaterial
	local trim = style.trim or PartUtil.TRIM
	local glass = PartUtil.GLASS

	-- Socle en granit sombre, un peu plus large que le bâtiment.
	PartUtil.block(parent, origin, "Floor", Vector3.new(w + 0.8, floorH, d + 0.8), Vector3.zero, Color3.fromRGB(92, 92, 96), Enum.Material.Granite)
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
	local frontOpts: BoxOptions? = if style.glassFront then { transparency = 0.35, reflectance = 0.1 } else nil
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
	-- Chaque fenêtre a un cadre sombre, des meneaux et un appui (PartUtil.window).
	local floors = style.floors or 1
	local bands = if floors >= 3 then floors else 1
	for band = 1, if style.windows then bands else 0 do
		local storey = h / bands
		local winH = storey * 0.32
		local winY = floorH + (band - 1) * storey + storey * 0.42 + winH / 2
		for _, side in { -1, 1 } do
			PartUtil.window(parent, origin, d * 0.6, winH, Vector3.new(side * w / 2, winY, 0), Vector3.new(side, 0, 0))
		end
		PartUtil.window(parent, origin, w * 0.7, winH, Vector3.new(0, winY, d / 2), Vector3.new(0, 0, 1))
		if not style.glassFront then
			for _, side in { -1, 1 } do
				PartUtil.window(parent, origin, pierWidth * 0.6, winH, Vector3.new(side * (dw / 2 + pierWidth / 2), winY, -d / 2), Vector3.new(0, 0, -1))
			end
		end
	end

	-- Façade vitrée : meneaux verticaux tous les 4 studs et une traverse au niveau de la porte.
	if style.glassFront then
		for _, side in { -1, 1 } do
			local bars = math.max(1, math.floor(pierWidth / 4))
			for i = 1, bars do
				local x = side * (dw / 2 + pierWidth * i / (bars + 1))
				PartUtil.detail(PartUtil.block(parent, origin, "Mullion", Vector3.new(0.2, h, 0.15), Vector3.new(x, floorH, -d / 2 - 0.08), trim, Enum.Material.Metal, { canCollide = false }))
			end
			PartUtil.detail(
				PartUtil.block(parent, origin, "Transom", Vector3.new(pierWidth, 0.2, 0.15), Vector3.new(side * (dw / 2 + pierWidth / 2), floorH + dh, -d / 2 - 0.08), trim, Enum.Material.Metal, { canCollide = false })
			)
		end
	end

	-- Angles du bâtiment soulignés (pilastres anthracite légèrement en saillie).
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartUtil.block(parent, origin, "Corner", Vector3.new(t + 0.4, h, t + 0.4), Vector3.new(sx * (w / 2 - t / 2), floorH, sz * (d / 2 - t / 2)), trim, Enum.Material.Metal)
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
			Enum.Material.Metal
		)
	end

	local overhang = style.roofOverhang or 0.5
	local roofY = floorH + h
	PartUtil.block(
		parent,
		origin,
		"Roof",
		Vector3.new(w + 2 * overhang, 0.6, d + 2 * overhang),
		Vector3.new(0, roofY, 0),
		style.roofColor,
		Enum.Material.Concrete
	)
	-- Acrotère (petit muret autour du toit) en métal anthracite.
	local rw, rd = w + 2 * overhang, d + 2 * overhang
	for _, side in { -1, 1 } do
		PartUtil.detail(PartUtil.block(parent, origin, "Parapet", Vector3.new(rw, 0.9, 0.4), Vector3.new(0, roofY + 0.6, side * (rd / 2 - 0.2)), trim, Enum.Material.Metal))
		PartUtil.detail(PartUtil.block(parent, origin, "Parapet", Vector3.new(0.4, 0.9, rd - 0.8), Vector3.new(side * (rw / 2 - 0.2), roofY + 0.6, 0), trim, Enum.Material.Metal))
	end
	-- Climatiseurs sur le toit (bâtiments assez larges).
	if style.roofUnits ~= false and w >= 16 and d >= 10 then
		for i, x in { -w / 4, w / 4 - 2 } do
			PartUtil.detail(
				PartUtil.block(parent, origin, "RoofUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(x, roofY + 0.6, d / 4 - i), Color3.fromRGB(170, 172, 176), Enum.Material.DiamondPlate)
			)
		end
	end

	-- Marquise au-dessus de la porte et appliques lumineuses de chaque côté.
	if style.canopy then
		local cy = floorH + dh + 0.3
		PartUtil.block(parent, origin, "Canopy", Vector3.new(dw + 3, 0.35, 2.4), Vector3.new(0, cy, -d / 2 - 1.2), trim, Enum.Material.Metal, { canCollide = false })
		PartUtil.detail(
			PartUtil.block(parent, origin, "CanopyTrim", Vector3.new(dw + 3, 0.18, 0.12), Vector3.new(0, cy + 0.08, -d / 2 - 2.46), style.accent or Color3.fromRGB(212, 175, 55), Enum.Material.Metal, { canCollide = false })
		)
		for _, side in { -1, 1 } do
			PartUtil.detail(
				PartUtil.block(parent, origin, "WallLight", Vector3.new(0.35, 1.1, 0.2), Vector3.new(side * (dw / 2 + 0.9), floorH + dh * 0.55, -d / 2 - 0.1), PartUtil.WARM_LIGHT, Enum.Material.Neon, { canCollide = false })
			)
		end
	end

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

-- Allège un décor fini pour les téléphones (appelé une fois après chaque construction) :
--   - personne n'utilise l'événement Touched sur le décor : CanTouch coupé partout
--     (sauf sièges et points d'apparition, qui en ont besoin) ;
--   - une pièce qu'on traverse n'a pas besoin d'être visée par les rayons : CanQuery coupé ;
--   - les détails (masquables) ne bloquent plus le joueur ni la caméra ;
--   - pas d'ombre pour les petites pièces, le néon (il éclaire) et le verre.
-- Les pièces non ancrées (véhicules, personnages) ne sont pas touchées.
PartUtil.SMALL_SHADOW = 1.5 -- studs : en dessous (plus grande dimension), pas d'ombre

local function needsTouch(part: BasePart): boolean
	return part:IsA("Seat") or part:IsA("VehicleSeat") or part:IsA("SpawnLocation")
end

local function hasPrompt(part: BasePart): boolean
	return part:FindFirstChildWhichIsA("ProximityPrompt") ~= nil or part:FindFirstChildWhichIsA("ClickDetector") ~= nil
end

function PartUtil.optimize(root: Instance?): number
	if not root then
		return 0
	end
	local changed = 0
	local list = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, part in list do
		if not part:IsA("BasePart") or part.Anchored ~= true or needsTouch(part) then
			continue
		end
		changed += 1
		part.CanTouch = false
		if part:GetAttribute("Detail") == true then
			part.CanCollide = false
			part.CastShadow = false
		end
		if part.CanCollide == false and not hasPrompt(part) then
			part.CanQuery = false
		end
		local size = part.Size
		if
			math.max(size.X, size.Y, size.Z) < PartUtil.SMALL_SHADOW
			or part.Material == Enum.Material.Neon
			or part.Material == Enum.Material.Glass
		then
			part.CastShadow = false
		end
	end
	return changed
end

return PartUtil
