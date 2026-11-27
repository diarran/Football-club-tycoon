--[[
	DetailController
	Niveau de détail du décor côté client, pour garder le jeu fluide sur téléphone.

	Les petites pièces de décor (meneaux de fenêtres, climatiseurs, roues,
	feuillage secondaire…) portent l'attribut « Detail » (PartUtil.detail côté
	serveur). Ce contrôleur les masque uniquement pour ce joueur :
	  - sur les terrains éloignés de la caméra (ils ne se voient pas de loin) ;
	  - partout si le joueur coupe Paramètres > « Détails du décor ».
	Le masquage passe par LocalTransparencyModifier : rien n'est détruit, rien
	n'est envoyé au serveur, et une pièce masquée ne coûte plus rien à dessiner.
]]

local UserInputService = game:GetService("UserInputService")

local DetailController = {}

local UPDATE_EVERY = 1 -- secondes
local FAR_DESKTOP = 460 -- distance (studs) caméra -> centre d'un terrain au-delà de laquelle on masque
local FAR_MOBILE = 360

local enabled = true
local initialized = false
local groups = {} -- [Instance de premier niveau du Workspace] = { parts = {[BasePart]=true}, hidden = bool }
local elapsed = 0

local function isMobile(): boolean
	local ok, touch = pcall(function()
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end)
	return ok and touch == true
end

local function topLevel(instance: Instance): Instance?
	local current = instance
	while current.Parent and current.Parent ~= workspace do
		current = current.Parent
	end
	return if current.Parent == workspace then current else nil
end

local function setHidden(part, hidden: boolean)
	part.LocalTransparencyModifier = if hidden then 1 else 0
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or instance:GetAttribute("Detail") ~= true then
		return
	end
	local root = topLevel(instance)
	if not root then
		return
	end
	local group = groups[root]
	if not group then
		group = { parts = setmetatable({}, { __mode = "k" }), hidden = false }
		groups[root] = group
	end
	group.parts[instance] = true
	if group.hidden then
		setHidden(instance, true)
	end
end

local function centerOf(root: Instance): Vector3?
	if root:IsA("Model") then
		local ok, pivot = pcall(function()
			return root:GetPivot()
		end)
		if ok and pivot then
			return pivot.Position
		end
	elseif root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Recalcule quels groupes doivent être masqués (seulement les changements touchent les Parts).
function DetailController.Update()
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame and camera.CFrame.Position
	local far = if isMobile() then FAR_MOBILE else FAR_DESKTOP
	for root, group in groups do
		if root.Parent ~= workspace then
			groups[root] = nil
			continue
		end
		local hide = not enabled
		if not hide and cameraPos then
			local center = centerOf(root)
			hide = center ~= nil and (center - cameraPos).Magnitude > far
		end
		if hide ~= group.hidden then
			group.hidden = hide
			for part in group.parts do
				if part.Parent then
					setHidden(part, hide)
				else
					group.parts[part] = nil
				end
			end
		end
	end
end

-- Paramètres > « Détails du décor ».
function DetailController.SetEnabled(value: boolean)
	enabled = value ~= false
	DetailController.Update()
end

function DetailController.IsEnabled(): boolean
	return enabled
end

-- Nombre de pièces de détail actuellement masquées (tests, diagnostic).
function DetailController.HiddenCount(): number
	local count = 0
	for _, group in groups do
		if group.hidden then
			for part in group.parts do
				if part.Parent then
					count += 1
				end
			end
		end
	end
	return count
end

function DetailController.Init()
	if initialized then
		return
	end
	initialized = true
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)
	task.spawn(function()
		while true do
			task.wait(UPDATE_EVERY)
			elapsed += UPDATE_EVERY
			local ok, err = pcall(DetailController.Update)
			if not ok then
				warn("[Détails] " .. tostring(err))
			end
		end
	end)
end

return DetailController
