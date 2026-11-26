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

-- Valide une étape. Les étapes ne donnent aucune monnaie : impossible de
-- tricher pour gagner quelque chose ici.
-- - Étape « client » (informative) : acceptée seulement si c'est l'étape en cours.
-- - Étape « server » (vraie action : amélioration, match) : acceptée aussi si
--   elle est plus loin dans le tutoriel. Le joueur qui agit avant d'y être invité
--   avance directement, au lieu de devoir refaire l'action plus tard.
function TutorialService.Complete(player: Player, stepId: string)
	local data = PlayerDataService.GetData(player)
	if not data or not currentStep(data) then
		return
	end
	local index = nil
	for i, step in TutorialSteps do
		if step.id == stepId then
			index = i
			break
		end
	end
	local current = data.tutorial.step
	if not index or index < current then
		return
	end
	if index > current and TutorialSteps[index].completedBy ~= "server" then
		return
	end
	if index >= #TutorialSteps then
		data.tutorial.completed = true
	else
		data.tutorial.step = index + 1
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
		-- Le client ne peut valider que l'étape informative en cours, jamais une étape serveur.
		if step and step.completedBy == "client" and step.id == stepId then
			TutorialService.Complete(player, stepId)
		end
	end)
end

return TutorialService
