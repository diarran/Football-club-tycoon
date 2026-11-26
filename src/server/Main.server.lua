--[[
	Main (serveur)
	Point d'entrée du serveur. Le serveur est l'autorité du jeu : profil,
	clubs, économie, construction, effectif, simulation et validation.

	Ordre :
	1. Création des RemoteEvents (Net.Setup)
	2. Initialisation de chaque service
	3. Pour chaque joueur : chargement du profil, puis OnPlayerReady de chaque service
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.Setup()

local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local ClubService = require(Services.ClubService)
local TutorialService = require(Services.TutorialService)
local BuildingService = require(Services.BuildingService)
local SquadService = require(Services.SquadService)
local MatchService = require(Services.MatchService)

-- Ordre d'initialisation : les données d'abord, puis ce qui en dépend.
local ORDERED_SERVICES = {
	{ name = "PlayerDataService", module = PlayerDataService },
	{ name = "EconomyService", module = EconomyService },
	{ name = "ClubService", module = ClubService },
	{ name = "TutorialService", module = TutorialService },
	{ name = "BuildingService", module = BuildingService },
	{ name = "SquadService", module = SquadService },
	{ name = "MatchService", module = MatchService },
}

for _, entry in ORDERED_SERVICES do
	local ok, err = pcall(entry.module.Init)
	if not ok then
		warn(("[Main] Échec de l'initialisation de %s : %s"):format(entry.name, tostring(err)))
	end
end

local function onPlayerAdded(player: Player)
	local profile = PlayerDataService.Load(player)
	if not profile or not player.Parent then
		return
	end

	-- L'effectif est créé avant l'attribution du terrain pour que la liste
	-- des clubs affiche tout de suite une note correcte.
	SquadService.OnPlayerReady(player, profile)
	if not ClubService.OnPlayerReady(player, profile) then
		PlayerDataService.Release(player)
		return
	end

	PlayerDataService.MarkChanged(player)
	Net.FireClient("ClubsUpdated", player, ClubService.GetClubList())
	if profile.temporary then
		Net.FireClient(
			"Notify",
			player,
			"Mode test : la progression n'est pas sauvegardée (accès aux API Studio désactivé).",
			"info"
		)
	end
end

local function onPlayerRemoving(player: Player)
	ClubService.OnPlayerLeaving(player)
	PlayerDataService.Release(player)
	Net.ForgetPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Joueurs déjà présents (cas du test en solo dans Studio).
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[Main] Football Club Tycoon : serveur prêt.")
