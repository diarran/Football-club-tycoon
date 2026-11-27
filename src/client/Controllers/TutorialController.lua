--[[
	TutorialController
	Affiche l'objectif du tutoriel en cours et signale au serveur les
	étapes informatives (menu ouvert, effectif consulté…).
	Le serveur garde l'étape en mémoire : le tutoriel reprend après une
	déconnexion. Le bandeau peut être masqué dans les Paramètres.

	Après le tutoriel, le même bandeau montre l'objectif de départ en cours
	(shared/Onboarding.lua) et, quand il est réussi, un bouton pour
	récupérer sa récompense (vérifiée par le serveur).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)

local TutorialController = {}

local player = game:GetService("Players").LocalPlayer

-- Noms des boutons et onglets cités dans les étapes (même langue que l'interface).
local STEP_PARAMS = {
	OpenMenu = { menu = "hud.menuButton" },
	CheckSquad = { tab = "tab.Squad" },
	FirstUpgrade = { tab = "tab.Stadium" },
	FirstMatch = { tab = "tab.Matches" },
}

local function stepText(lang: string, stepIndex: number, step): string
	local params = {}
	for name, key in STEP_PARAMS[step.id] or {} do
		params[name] = Locale.T(lang, key)
	end
	return Locale.T(lang, "tutorial.progress", {
		step = stepIndex,
		total = #TutorialSteps,
		text = Locale.T(lang, "tutorial." .. step.id, params),
	})
end

local banner, textLabel, claimButton
local currentStepId = nil
local currentGoal = nil -- objectif de départ affiché (instantané « onboarding.current »)
local visible = true
local discoverScheduled = false
local lastProfile = nil

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
	textLabel.LayoutOrder = 1
	textLabel.Parent = banner

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = banner

	claimButton = Instance.new("TextButton")
	claimButton.Name = "OnboardingClaim"
	claimButton.LayoutOrder = 2
	claimButton.Size = UDim2.new(0, 220, 0, 44)
	claimButton.BackgroundColor3 = Color3.fromRGB(245, 196, 66)
	claimButton.Font = Enum.Font.GothamBold
	claimButton.TextSize = 18
	claimButton.TextScaled = true
	claimButton.Text = ""
	claimButton.TextColor3 = Color3.fromRGB(18, 24, 38)
	claimButton.Visible = false
	claimButton.Parent = banner
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = claimButton
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 18
	textSize.MinTextSize = 10
	textSize.Parent = claimButton
	claimButton.Activated:Connect(function()
		Net.Get("RequestOnboardingClaim"):FireServer()
	end)
end

-- Texte de l'objectif de départ : « Objectif de départ 2/6 · Gagne 3 matchs (1/3) · +300 FC ».
local function goalText(lang: string, goal): string
	return Locale.T(lang, "onboarding.progress", {
		step = goal.index,
		total = goal.total,
		text = Locale.T(lang, "onboarding.goal." .. goal.id, {
			n = goal.target,
			tab = Locale.T(lang, "tab." .. goal.tab),
		}),
		progress = goal.progress,
		target = goal.target,
		coins = goal.reward,
	})
end

local function refreshVisibility()
	banner.Visible = visible and (currentStepId ~= nil or currentGoal ~= nil)
end

function TutorialController.SetVisible(value: boolean)
	visible = value
	refreshVisibility()
end

-- Appelé à chaque mise à jour du profil.
function TutorialController.Update(profile)
	local tutorial = profile and profile.tutorial
	lastProfile = profile
	if not tutorial or tutorial.completed then
		currentStepId = nil
		local onboarding = profile and profile.onboarding
		currentGoal = if type(onboarding) == "table" and type(onboarding.current) == "table"
			then onboarding.current
			else nil
		local lang = Locale.ForPlayer(player)
		if currentGoal then
			textLabel.Text = goalText(lang, currentGoal)
			claimButton.Visible = currentGoal.ready == true
			claimButton.Text = Locale.T(lang, "onboarding.claim", { coins = currentGoal.reward })
			-- Objectif réussi : bandeau doré pour attirer l'œil.
			banner.BackgroundColor3 = if currentGoal.ready then Color3.fromRGB(200, 140, 30) else Color3.fromRGB(46, 170, 90)
		end
		refreshVisibility()
		return
	end
	currentGoal = nil
	claimButton.Visible = false
	banner.BackgroundColor3 = Color3.fromRGB(46, 170, 90)
	local step = TutorialSteps[tutorial.step]
	currentStepId = step and step.id
	textLabel.Text = if step then stepText(Locale.ForPlayer(player), tutorial.step, step) else ""
	refreshVisibility()

	-- Étape 1 : validée après quelques secondes passées sur son terrain.
	if currentStepId == "DiscoverPlot" and not discoverScheduled then
		discoverScheduled = true
		task.delay(8, function()
			TutorialController.Signal("DiscoverPlot")
		end)
	end
end

-- Langue changée dans les Paramètres : réaffiche l'étape en cours.
function TutorialController.RefreshLanguage()
	if lastProfile then
		TutorialController.Update(lastProfile)
	end
end

-- Signale une étape informative au serveur, si c'est l'étape en cours.
function TutorialController.Signal(stepId: string)
	if currentStepId == stepId then
		Net.Get("RequestTutorialStep"):FireServer(stepId)
	end
end

return TutorialController
