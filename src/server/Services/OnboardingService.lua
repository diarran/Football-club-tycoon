--[[
	OnboardingService
	Objectifs de départ (shared/Onboarding.lua) : après le tutoriel, un
	objectif simple à la fois (améliorer, gagner, entraîner, embaucher,
	signer un sponsor, monter en D6), chacun avec une petite récompense.

	Le client demande la récompense (RequestOnboardingClaim, sans argument) ;
	le serveur vérifie lui-même l'objectif dans le profil et ne paie chaque
	objectif qu'une fois. Les récompenses ne sont pas versées automatiquement
	pour ne pas surprendre le joueur (et garder des soldes prévisibles).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local EconomyService = require(script.Parent.EconomyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local OnboardingService = {}

-- Renvoie "granted", "notReady" ou "none" (rien à récupérer), et la récompense.
function OnboardingService.Claim(player: Player): (string, number?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return "none", nil
	end
	local goal = Onboarding.CurrentGoal(data)
	if not goal then
		return "none", nil
	end
	if not goal.ready then
		return "notReady", nil
	end
	if goal.index >= #Onboarding.GOALS then
		data.onboarding.done = true
	end
	data.onboarding.goal = goal.index + 1
	EconomyService.Add(player, goal.reward, "objectif de départ " .. goal.id)
	PlayerDataService.MarkChanged(player)
	return "granted", goal.reward
end

function OnboardingService.Init()
	PlayerDataService.AddSnapshotField("onboarding", function(_, data)
		return {
			done = data.onboarding.done == true,
			current = Onboarding.CurrentGoal(data),
		}
	end)
	Net.Handle("RequestOnboardingClaim", function(player)
		local result, reward = OnboardingService.Claim(player)
		if result == "granted" then
			local data = PlayerDataService.GetData(player)
			local key = if data and data.onboarding.done then "onboarding.allDone" else "onboarding.claimed"
			Net.FireClient("Notify", player, Locale.TP(player, key, { coins = reward }), "success")
		end
	end)
end

return OnboardingService
