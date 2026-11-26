--[[
	TutorialController
	Affiche l'objectif du tutoriel en cours et signale au serveur les
	étapes informatives (menu ouvert, effectif consulté…).
	Le serveur garde l'étape en mémoire : le tutoriel reprend après une
	déconnexion. Le bandeau peut être masqué dans les Paramètres.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)

local TutorialController = {}

local banner, textLabel
local currentStepId = nil
local visible = true
local discoverScheduled = false

function TutorialController.Init(screenGui: ScreenGui)
	banner = Instance.new("Frame")
	banner.Name = "Tutorial"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 12)
	banner.Size = UDim2.new(0.5, 0, 0, 0)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.BackgroundColor3 = Color3.fromRGB(46, 170, 90)
	banner.BackgroundTransparency = 0.1
	banner.Visible = false
	banner.Parent = screenGui

	local cornerRadius = Instance.new("UICorner")
	cornerRadius.CornerRadius = UDim.new(0, 10)
	cornerRadius.Parent = banner
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = banner
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(260, 0)
	constraint.Parent = banner

	textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.new(1, 0, 0, 0)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextSize = 18
	textLabel.TextWrapped = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Parent = banner
end

local function refreshVisibility()
	banner.Visible = visible and currentStepId ~= nil
end

function TutorialController.SetVisible(value: boolean)
	visible = value
	refreshVisibility()
end

-- Appelé à chaque mise à jour du profil.
function TutorialController.Update(profile)
	local tutorial = profile and profile.tutorial
	if not tutorial or tutorial.completed then
		currentStepId = nil
		refreshVisibility()
		return
	end
	local step = TutorialSteps[tutorial.step]
	currentStepId = step and step.id
	textLabel.Text = step and ("Objectif %d/%d · %s"):format(tutorial.step, #TutorialSteps, step.text) or ""
	refreshVisibility()

	-- Étape 1 : validée après quelques secondes passées sur son terrain.
	if currentStepId == "DiscoverPlot" and not discoverScheduled then
		discoverScheduled = true
		task.delay(8, function()
			TutorialController.Signal("DiscoverPlot")
		end)
	end
end

-- Signale une étape informative au serveur, si c'est l'étape en cours.
function TutorialController.Signal(stepId: string)
	if currentStepId == stepId then
		Net.Get("RequestTutorialStep"):FireServer(stepId)
	end
end

return TutorialController
