--!strict
--[[
	Landscape — aménagement paysager d'un terrain de club (purement visuel) :
	haies sur le pourtour, rangées d'arbres, lampadaires le long des allées,
	drapeaux du club à l'entrée et parking avec quelques voitures.

	Tout est placé dans les zones libres du plan (WorldConfig.LAYOUT) :
	bande arrière derrière le stade, bande gauche, bord des allées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local PartUtil = require(script.Parent:WaitForChild("PartUtil"))
local Props = require(script.Parent:WaitForChild("Props"))

type BuildContext = PartUtil.BuildContext

local Landscape = {}

local P = WorldConfig.LANDSCAPE

function Landscape.build(plot: Instance, origin: CFrame, ctx: BuildContext): Model
	local model = PartUtil.model(plot, "Landscape")
	for _, hedge in P.hedges do
		Props.hedge(model, origin, hedge[1], hedge[2])
	end
	for i, pos in P.trees do
		if i % 3 == 0 then
			Props.conifer(model, origin, pos.X, pos.Y)
		else
			Props.tree(model, origin, pos.X, pos.Y)
		end
	end
	for _, lamp in P.lamps do
		Props.lamp(model, origin, lamp.X, lamp.Y, lamp.Z)
	end
	for i, pos in P.flags do
		Props.flag(model, origin, pos.X, pos.Y, if i % 2 == 0 then ctx.secondary else ctx.primary, pos.Z)
	end
	for _, bench in P.benches do
		Props.bench(model, origin, bench.X, bench.Y, bench.Z)
	end
	local parking = P.parking
	Props.parking(model, origin, parking.center, parking.size, {
		ctx.primary,
		Color3.fromRGB(28, 28, 32),
		Color3.fromRGB(235, 235, 235),
		Color3.fromRGB(120, 124, 130),
	})
	return model
end

return Landscape
