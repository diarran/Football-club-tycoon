--!strict
--[[
	Offices — bureaux du club (accès aux menus de gestion).

	Niveau 1 : petit bâtiment en briques avec une porte.
	Niveau 2 : bâtiment enduit plus grand, fenêtres, auvent au-dessus de l'entrée.
	Niveau 3 : immeuble moderne sur 2 étages, façade vitrée, enseigne au nom du club.
	Niveau 4 : immeuble de 3 étages, bandeau aux couleurs secondaires, salle de réunion.
	Niveau 5 : siège du club sur 4 étages, écusson géant sur le toit, antenne.

	Un ProximityPrompt « Gérer le club » (nommé ManageClubPrompt) est placé à la porte.
	Pour l'instant il ne déclenche RIEN : la logique sera branchée plus tard par
	le service de gestion (écouter prompt.Triggered côté serveur).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local Brand = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Brand"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Offices = {}

local C = WorldConfig.COLORS

local SIZES = {
	[1] = Vector3.new(18, 10, 14),
	[2] = Vector3.new(26, 12, 16),
	[3] = Vector3.new(34, 18, 18),
	[4] = Vector3.new(36, 24, 18),
	[5] = Vector3.new(38, 30, 18),
}

function Offices.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Offices", { Facility = "Offices", Level = level })
	local size = SIZES[level] or SIZES[1]
	PartUtil.anchor(model, origin, Vector2.new(size.X, size.Z), size.Y)

	local style: PartUtil.ShellStyle
	if level <= 1 then
		style = { wallColor = C.Brick, wallMaterial = Enum.Material.Brick, roofColor = C.ConcreteDark, windows = true }
	elseif level == 2 then
		style = {
			wallColor = C.Plaster,
			wallMaterial = Enum.Material.Plaster,
			roofColor = C.Roof,
			windows = true,
			accent = ctx.primary,
			roofOverhang = 1,
		}
	else
		style = {
			wallColor = C.Concrete,
			wallMaterial = Enum.Material.SmoothPlastic,
			roofColor = C.Roof,
			windows = true,
			glassFront = true,
			accent = ctx.primary,
			roofOverhang = 1.5,
			floors = if level >= 5 then 4 elseif level == 4 then 3 else 2,
			doorWidth = 6,
		}
	end
	local doorPos = PartUtil.shell(model, origin, size, style)

	-- Bureau intérieur (plateau + chaise).
	PartUtil.block(model, origin, "Desk", Vector3.new(6, 3, 2.5), Vector3.new(0, 0.4, size.Z / 2 - 3), C.WoodDark, Enum.Material.Wood)
	PartUtil.block(model, origin, "Chair", Vector3.new(2, 2.2, 2), Vector3.new(0, 0.4, size.Z / 2 - 5.5), ctx.primary, Enum.Material.Fabric)

	-- Niveau 2 : auvent au-dessus de la porte.
	if level == 2 then
		PartUtil.block(
			model,
			origin,
			"Canopy",
			Vector3.new(9, 0.4, 3),
			Vector3.new(0, 0.4 + 8.5, -size.Z / 2 - 1.5),
			ctx.primary,
			Enum.Material.SmoothPlastic
		)
	end
	-- Niveau 3 : « aileron » vertical aux couleurs du club sur l'angle avant.
	if level >= 3 then
		PartUtil.block(
			model,
			origin,
			"Fin",
			Vector3.new(1.2, size.Y + 3, 3),
			Vector3.new(size.X / 2 - 0.6, 0, -size.Z / 2 - 1.5),
			ctx.secondary,
			Enum.Material.SmoothPlastic
		)
	end

	-- Niveau 4 : table de réunion au premier étage.
	if level >= 4 then
		PartUtil.block(
			model,
			origin,
			"MeetingTable",
			Vector3.new(10, 3, 4),
			Vector3.new(-size.X / 4, 0.4 + size.Y / (if level >= 5 then 4 else 3), 0),
			C.WoodDark,
			Enum.Material.Wood
		)
	end
	-- Niveau 5 : écusson géant (disque + bord) sur le toit et antenne.
	if level >= 5 then
		local roofTop = 0.4 + size.Y + 0.6
		PartUtil.block(model, origin, "CrestStand", Vector3.new(1, 3, 1), Vector3.new(0, roofTop, 0), C.MetalDark, Enum.Material.Metal)
		PartUtil.box(
			model,
			origin,
			"CrestRim",
			Vector3.new(1, 9, 9),
			Vector3.new(0, roofTop + 7, 0),
			ctx.secondary,
			Enum.Material.SmoothPlastic,
			{ shape = Enum.PartType.Cylinder, rotY = 90 }
		)
		local crestDisc = PartUtil.box(
			model,
			origin,
			"Crest",
			Vector3.new(1.2, 7.4, 7.4),
			Vector3.new(0, roofTop + 7, 0),
			ctx.primary,
			Enum.Material.SmoothPlastic,
			{ shape = Enum.PartType.Cylinder, rotY = 90 }
		)
		-- Écusson importé (shared/Brand.lua) sur les deux faces du disque.
		local crestImage = Brand.CrestImage(ctx.slotIndex)
		if crestImage then
			for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
				local surface = Instance.new("SurfaceGui")
				surface.Name = "CrestImage" .. face.Name
				surface.Face = face
				surface.LightInfluence = 0.2
				surface.Parent = crestDisc
				local image = Instance.new("ImageLabel")
				image.BackgroundTransparency = 1
				image.Size = UDim2.fromScale(1, 1)
				image.Image = crestImage
				image.Parent = surface
			end
		end
		PartUtil.cylinder(model, origin, "Antenna", 0.4, 10, Vector3.new(size.X / 2 - 3, roofTop, size.Z / 2 - 3), C.Metal, Enum.Material.Metal)
	end

		local signText = if level >= 3 then string.upper(ctx.clubName) else "world.offices"
	local sign = PartUtil.frontSign(
		model,
		origin,
		signText,
		Vector2.new(math.min(size.X * 0.6, 16), 1.8),
		Vector3.new(0, 0.4 + size.Y - 1.8, -size.Z / 2 - 0.4),
		C.SignText,
		C.SignBack
	)
	if level >= 3 then
		-- Le texte suit le nom du club (voir WorldBuilder.setClubName).
		local text = sign:FindFirstChildWhichIsA("SurfaceGui")
		local label = text and text:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Name = "ClubNameText"
		end
	end

	-- Point d'interaction devant la porte. La logique viendra plus tard.
	local promptPart = PartUtil.box(
		model,
		origin,
		"PromptAnchor",
		Vector3.new(2, 2, 0.5),
		doorPos + Vector3.new(0, 3.5, -0.8),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ canCollide = false, transparency = 1, castShadow = false }
	)
	promptPart.CanQuery = false
	promptPart.CanTouch = false

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ManageClubPrompt"
	Locale.Tag(prompt, "world.manageClub", nil, "ActionText")
	prompt.ObjectText = ctx.clubName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart

	return model
end

return Offices
