--!strict
--[[
	Entrance — portique d'entrée du club.

	Deux piliers, une poutre avec le NOM DU CLUB (SurfaceGui sur les deux faces)
	et, au sommet, un emplacement d'écusson générique : un blason géométrique
	simple (carré + pointe en losange + ballon), aux couleurs du club.
	Aucun logo réel : l'écusson personnalisé pourra remplacer le Model « Crest ».

	Les TextLabels du nom s'appellent « ClubNameText » (voir WorldBuilder.setClubName).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Brand = require(Shared:WaitForChild("Brand"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local Entrance = {}

local C = WorldConfig.COLORS

local WIDTH = 26 -- distance entre l'extérieur des piliers
local PILLAR = 2.5
local HEIGHT = 12 -- hauteur sous la poutre

function Entrance.build(parent: Instance, origin: CFrame, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "Entrance", { Facility = "Entrance", Level = 1 })
	PartUtil.anchor(model, origin, WorldConfig.LAYOUT.Entrance.footprint, HEIGHT)

	local px = WIDTH / 2 - PILLAR / 2
	for _, side in { -1, 1 } do
		PartUtil.block(
			model,
			origin,
			"Pillar",
			Vector3.new(PILLAR, HEIGHT, PILLAR),
			Vector3.new(side * px, 0, 0),
			C.Concrete,
			Enum.Material.Concrete
		)
		-- Bannière verticale aux couleurs du club, côté route.
		PartUtil.block(
			model,
			origin,
			"Banner",
			Vector3.new(1.6, 7, 0.1),
			Vector3.new(side * px, 3.5, -PILLAR / 2 - 0.05),
			ctx.primary,
			Enum.Material.Fabric,
			{ canCollide = false }
		)
	end

	local beam = PartUtil.block(
		model,
		origin,
		"NameBeam",
		Vector3.new(WIDTH + 1, 3, 1.6),
		Vector3.new(0, HEIGHT, 0),
		C.SignBack,
		Enum.Material.SmoothPlastic
	)
	-- Nom affiché des deux côtés (Front = vers la route, Back = vers l'intérieur du club).
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local label = PartUtil.label(beam, face, string.upper(ctx.clubName), C.SignText)
		label.Name = "ClubNameText"
	end
	-- Liseré aux couleurs du club sous la poutre.
	PartUtil.block(
		model,
		origin,
		"BeamTrim",
		Vector3.new(WIDTH + 1, 0.4, 1.8),
		Vector3.new(0, HEIGHT - 0.4, 0),
		ctx.secondary,
		Enum.Material.SmoothPlastic
	)

	-- Écusson générique (emplacement réservé, formes simples).
	local crest = PartUtil.model(model, "Crest")
	local cy = HEIGHT + 3 + 1.8 -- la pointe du losange repose sur la poutre
	local shieldTop = PartUtil.block(crest, origin, "ShieldTop", Vector3.new(4.4, 3, 0.6), Vector3.new(0, cy, 0), ctx.primary, Enum.Material.SmoothPlastic)
	PartUtil.box(
		crest,
		origin,
		"ShieldPoint",
		Vector3.new(3.1, 3.1, 0.6),
		Vector3.new(0, cy + 0.6, 0),
		ctx.primary,
		Enum.Material.SmoothPlastic,
		{ rotZ = 45 }
	)
	PartUtil.block(crest, origin, "ShieldBand", Vector3.new(4.4, 0.7, 0.7), Vector3.new(0, cy + 2.3, 0), ctx.secondary, Enum.Material.SmoothPlastic)
	PartUtil.ball(crest, origin, "Ball", 1.6, Vector3.new(0, cy + 1.6, -0.5), C.Line, Enum.Material.SmoothPlastic)

	-- Sigle du club au dos de l'écusson (visible depuis l'intérieur du club).
	local tag = PartUtil.label(shieldTop, Enum.NormalId.Back, Brand.Tag(ctx.clubName), ctx.secondary)
	tag.Name = "ClubTagText"

	-- Écusson importé sur Roblox (voir shared/Brand.lua) : affiché devant le blason.
	local crestImage = Brand.CrestImage(ctx.crest or ctx.slotIndex)
	if crestImage then
		local imagePanel = PartUtil.box(
			crest,
			origin,
			"CrestImage",
			Vector3.new(5.5, 5.5, 0.1),
			Vector3.new(0, cy + 2, -1.5),
			ctx.primary,
			Enum.Material.SmoothPlastic,
			{ canCollide = false, transparency = 1, castShadow = false }
		)
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.LightInfluence = 0.2
		surface.Parent = imagePanel
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = crestImage
		image.Parent = surface
	end

	return model
end

return Entrance
