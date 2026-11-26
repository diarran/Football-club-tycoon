--[[
	WorldTextController
	Traduit les textes du décor 3D (panneaux, publicités, invite des Bureaux)
	dans la langue du joueur. Le serveur les écrit dans la langue par défaut
	et note leur clé (Locale.Tag) ; ici on les réécrit pour ce joueur seulement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))

local WorldTextController = {}

local player = Players.LocalPlayer

local function apply(instance: Instance)
	if instance:GetAttribute("TextKey") ~= nil then
		Locale.ApplyTag(instance, Locale.ForPlayer(player))
	end
end

function WorldTextController.RefreshAll()
	for _, descendant in workspace:GetDescendants() do
		apply(descendant)
	end
end

function WorldTextController.Init()
	WorldTextController.RefreshAll()
	workspace.DescendantAdded:Connect(apply)
end

return WorldTextController
