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
local MatchReplayController = require(Controllers.MatchReplayController)
local SoundController = require(Controllers.SoundController)
local WeatherController = require(Controllers.WeatherController)

-- Chaque contrôleur démarre séparément : si l'un échoue (caméra, tutoriel…),
-- le menu et le HUD restent utilisables et l'erreur s'affiche dans la sortie.
local function start(label: string, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[Client] %s a échoué : %s"):format(label, tostring(err)))
	end
end

UIController.Init() -- indispensable : sans lui, rien ne s'affiche
start("CameraController", CameraController.Init)
start("TutorialController", TutorialController.Init, UIController.GetScreenGui())
start("WorldTextController", WorldTextController.Init)
start("WeatherController", WeatherController.Init)
start("SoundController", function()
	SoundController.Init()
	-- Son de clic sur tous les boutons (menus, replay, tutoriel…).
	local playerGui = UIController.GetScreenGui().Parent
	if playerGui then
		SoundController.HookButtons(playerGui)
	end
end)

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
	elseif settingId == "volume" then
		SoundController.SetVolume(value)
	elseif settingId == "music" then
		SoundController.SetMusicEnabled(value)
	elseif settingId == "weatherEffects" then
		WeatherController.SetEffectsEnabled(value)
	end
end

UIController.OnLanguageChanged = function()
	TutorialController.RefreshLanguage()
	WorldTextController.RefreshAll()
end

-- Ambiance du replay 3D : public, clameur et son de but.
MatchReplayController.OnStart = function(crowdLevel, spectator)
	SoundController.StartMatch(crowdLevel, spectator)
	pcall(WeatherController.SetMatchMode, true) -- projecteurs du match
end
MatchReplayController.OnGoal = function()
	SoundController.Goal()
end
MatchReplayController.OnEnd = function()
	SoundController.EndMatch()
	pcall(WeatherController.SetMatchMode, false)
end

-- Messages du serveur ------------------------------------------------------

local function onProfile(profile)
	UIController.SetProfile(profile)
	TutorialController.Update(profile)
end

Net.Get("ProfileUpdated").OnClientEvent:Connect(onProfile)
Net.Get("ClubsUpdated").OnClientEvent:Connect(UIController.SetClubs)
-- Match : d'abord le replay 3D sur le terrain du club, puis la fenêtre de
-- résultat (tout de suite si le replay ne peut pas se lancer, ou pour un défi).
Net.Get("MatchResult").OnClientEvent:Connect(function(result)
	if type(result) == "table" and result.replay then
		UIController.SetMenuOpen(false)
		local started = MatchReplayController.Play(result.replay, {
			onDone = function()
				UIController.ShowMatchResult(result)
			end,
		})
		if started then
			return
		end
	end
	UIController.ShowMatchResult(result)
end)
-- Match d'un autre club : les visiteurs proches du terrain le regardent.
Net.Get("MatchReplay").OnClientEvent:Connect(function(replay)
	MatchReplayController.Play(replay, { spectator = true })
end)
Net.Get("Notify").OnClientEvent:Connect(function(message, kind)
	UIController.Notify(message, kind)
	if kind == "success" then
		SoundController.Play("Piece")
	end
end)
Net.Get("ChallengeUpdated").OnClientEvent:Connect(UIController.SetChallenges)
Net.Get("TournamentUpdated").OnClientEvent:Connect(UIController.SetTournament)
Net.Get("LeaderboardUpdated").OnClientEvent:Connect(UIController.SetLeaderboard)

-- État initial (si le profil était déjà chargé avant ce script).
task.spawn(function()
	local ok, snapshot = pcall(function()
		return Net.Get("GetSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		onProfile(snapshot)
	end
end)
