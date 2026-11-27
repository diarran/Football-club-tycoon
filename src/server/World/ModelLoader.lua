--!strict
--[[
	ModelLoader — charge une fois les modèles Blender publiés sur Roblox
	(numéros dans Shared/Models.lua) et les garde en mémoire.

	Le chargement (InsertService:LoadAsset) attend le réseau : il est lancé en
	arrière-plan au démarrage (Preload) et la construction du monde ne l'attend
	jamais. ModelLoader.Place renvoie nil tant que le modèle n'est pas prêt ou
	si le numéro est vide : l'appelant construit alors sa version en Parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))

local ModelLoader = {}

local cache: { [string]: Model } = {}

local function load(key: string, onReady: (() -> ())?)
	local id = Models.Id(key)
	if not id then
		return
	end
	local ok, result = pcall(function()
		return game:GetService("InsertService"):LoadAsset(id)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(("[ModelLoader] Modèle %s (%d) introuvable : version en blocs gardée (%s)"):format(key, id, tostring(result)))
		return
	end
	local model = result:FindFirstChildWhichIsA("Model") or result
	if model:IsA("Model") then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy() -- sécurité : jamais de code venu d'un modèle
			end
		end
		model.Parent = nil
		cache[key] = model
		if onReady then
			onReady()
		end
	end
end

-- Lance le chargement de tous les modèles renseignés, sans attendre.
-- `onReady` est appelé après chaque modèle chargé (pour reconstruire les terrains).
function ModelLoader.Preload(onReady: (() -> ())?)
	for key in Models.ASSET_IDS do
		if Models.Id(key) then
			task.spawn(load, key, onReady)
		end
	end
end

function ModelLoader.IsReady(key: string): boolean
	return cache[key] ~= nil
end

-- Pose une copie du modèle `key` dans `parent`, mise à l'échelle pour tenir dans
-- `size` (studs) et posée au sol en `cframe`. nil si le modèle n'est pas prêt.
function ModelLoader.Place(key: string, parent: Instance, cframe: CFrame, size: Vector3): Model?
	local source = cache[key]
	if not source then
		return nil
	end
	local copy = source:Clone()
	local _, extents = copy:GetBoundingBox()
	local scale = math.min(size.X / extents.X, size.Y / extents.Y, size.Z / extents.Z)
	if scale > 0 and scale < math.huge then
		copy:ScaleTo(copy:GetScale() * scale)
	end
	local box, newExtents = copy:GetBoundingBox()
	-- Bas du modèle posé sur `cframe`, centré.
	copy:PivotTo(cframe * CFrame.new(0, newExtents.Y / 2, 0) * (box:Inverse() * copy:GetPivot()))
	copy.Name = key
	copy.Parent = parent
	return copy
end

return ModelLoader
