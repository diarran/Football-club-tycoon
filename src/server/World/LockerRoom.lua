--!strict
--[[
	LockerRoom — vestiaires du club.

	Niveau 1 : petit bâtiment simple en enduit blanc, un banc intérieur.
	Niveau 2 : plus grand, en béton, fenêtres et bandeau aux couleurs du club.
	Niveau 3 : bâtiment moderne à façade vitrée, casiers et bancs aux couleurs du club.

	La porte donne sur l'avant (-Z), vers l'allée qui mène à l'entrée du club.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))

type BuildContext = PartUtil.BuildContext

local LockerRoom = {}

local C = WorldConfig.COLORS

-- Taille (largeur, hauteur des murs, profondeur) par niveau.
local SIZES = {
	[1] = Vector3.new(16, 9, 12),
	[2] = Vector3.new(24, 10, 16),
	[3] = Vector3.new(32, 11, 18),
}

function LockerRoom.build(parent: Instance, origin: CFrame, level: number, ctx: BuildContext): Model
	local model = PartUtil.model(parent, "LockerRoom", { Facility = "LockerRoom", Level = level })
	local size = SIZES[level] or SIZES[1]
	PartUtil.anchor(model, origin, Vector2.new(size.X, size.Z), size.Y)

	local style: PartUtil.ShellStyle
	if level <= 1 then
		style = { wallColor = C.Plaster, wallMaterial = Enum.Material.Plaster, roofColor = C.ConcreteDark }
	elseif level == 2 then
		style = {
			wallColor = C.Concrete,
			wallMaterial = Enum.Material.Concrete,
			roofColor = C.Roof,
			windows = true,
			accent = ctx.primary,
		}
	else
		style = {
			wallColor = C.Plaster,
			wallMaterial = Enum.Material.SmoothPlastic,
			roofColor = C.Roof,
			windows = true,
			glassFront = true,
			accent = ctx.primary,
			roofOverhang = 2,
			doorWidth = 6,
		}
	end
	PartUtil.shell(model, origin, size, style)

	-- Mobilier intérieur : bancs le long des murs latéraux.
	local benches = if level >= 3 then 3 else level
	local benchLength = size.Z * 0.6
	for i = 1, benches do
		local x = -size.X / 2 + 1.6 + (i - 1) * 2.2
		PartUtil.block(
			model,
			origin,
			"Bench",
			Vector3.new(1.4, 1.6, benchLength),
			Vector3.new(x, 0.4, 0),
			if level >= 2 then ctx.primary else C.Wood,
			if level >= 2 then Enum.Material.SmoothPlastic else Enum.Material.WoodPlanks
		)
	end
	-- Niveau 3 : rangée de casiers contre le mur du fond.
	if level >= 3 then
		PartUtil.block(
			model,
			origin,
			"Lockers",
			Vector3.new(size.X * 0.6, 6, 1.4),
			Vector3.new(4, 0.4, size.Z / 2 - 1.3),
			ctx.secondary,
			Enum.Material.Metal
		)
	end

	PartUtil.frontSign(
		model,
		origin,
		"world.lockerRoom",
		Vector2.new(math.min(size.X * 0.5, 12), 1.6),
		Vector3.new(0, 0.4 + size.Y - 1.6, -size.Z / 2 - 0.4),
		C.SignText,
		C.SignBack
	)
	return model
end

return LockerRoom
