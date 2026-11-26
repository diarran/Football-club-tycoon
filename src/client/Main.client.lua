--[[
	Main (client)
	Point d'entrée du client : HUD, menus, caméra, tutoriel.
	Le client affiche l'état reçu du serveur et envoie des demandes ;
	il ne décide jamais d'un prix, d'un solde ou d'un résultat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Controllers = script.Parent:WaitForChild("Controllers")
local UIController = require(Controllers.UIController)
local CameraController = require(Controllers.CameraController)
local TutorialController = require(Controllers.TutorialController)
local WorldTextController = require(Controllers.WorldTextController)

UIController.Init()
CameraController.Init()
TutorialController.Init(UIController.GetScreenGui())
WorldTextController.Init()

-- Liens entre les contrôleurs ---------------------------------------------

UIController.OnMenuOpened = function()
	CameraController.EnterManagementView()
	TutorialController.Signal("OpenMenu")
end

UIController.OnMenuClosed = function()
	CameraController.ExitManagementView()
end

UIController.OnTabOpened = function(tabId)
	if tabId == "Squad" then
		TutorialController.Signal("CheckSquad")
	end
end

UIController.OnMatchResultClosed = function()
	TutorialController.Signal("SeeRewards")
end

UIController.OnSettingChanged = function(settingId, value)
	if settingId == "managementCamera" then
		CameraController.SetEnabled(value)
	elseif settingId == "showTutorial" then
		TutorialController.SetVisible(value)
	end
end

UIController.OnLanguageChanged = function()
	TutorialController.RefreshLanguage()
	WorldTextController.RefreshAll()
end

-- Messages du serveur ------------------------------------------------------

local function onProfile(profile)
	UIController.SetProfile(profile)
	TutorialController.Update(profile)
end

Net.Get("ProfileUpdated").OnClientEvent:Connect(onProfile)
Net.Get("ClubsUpdated").OnClientEvent:Connect(UIController.SetClubs)
Net.Get("MatchResult").OnClientEvent:Connect(UIController.ShowMatchResult)
Net.Get("Notify").OnClientEvent:Connect(UIController.Notify)
Net.Get("ChallengeUpdated").OnClientEvent:Connect(UIController.SetChallenges)
Net.Get("TournamentUpdated").OnClientEvent:Connect(UIController.SetTournament)

-- État initial (si le profil était déjà chargé avant ce script).
task.spawn(function()
	local ok, snapshot = pcall(function()
		return Net.Get("GetSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		onProfile(snapshot)
	end
end)
