--[[
	TutorialService
	Tutoriel guidé des premières minutes (document de conception, section 8).

	L'étape en cours est sauvegardée dans le profil : après une déconnexion,
	le joueur reprend là où il s'était arrêté.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)
local PlayerDataService = require(script.Parent.PlayerDataService)

local TutorialService = {}

local function currentStep(data)
	if data.tutorial.completed then
		return nil
	end
	return TutorialSteps[data.tutorial.step]
end

-- Valide une étape si c'est bien l'étape en cours. Les étapes ne donnent
-- aucune monnaie : impossible de tricher pour gagner quelque chose ici.
function TutorialService.Complete(player: Player, stepId: string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local step = currentStep(data)
	if not step or step.id ~= stepId then
		return
	end
	if data.tutorial.step >= #TutorialSteps then
		data.tutorial.completed = true
	else
		data.tutorial.step += 1
	end
	PlayerDataService.MarkChanged(player)
end

function TutorialService.Init()
	Net.Handle("RequestTutorialStep", function(player, stepId)
		if type(stepId) ~= "string" then
			return
		end
		local data = PlayerDataService.GetData(player)
		local step = data and currentStep(data)
		if step and step.completedBy == "client" then
			TutorialService.Complete(player, stepId)
		end
	end)
end

return TutorialService
