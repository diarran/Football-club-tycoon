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

local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.Setup()

local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local ClubService = require(Services.ClubService)
local TutorialService = require(Services.TutorialService)
local OnboardingService = require(Services.OnboardingService)
local BuildingService = require(Services.BuildingService)
local SquadService = require(Services.SquadService)
local MatchService = require(Services.MatchService)
local CosmeticService = require(Services.CosmeticService)
local MonetizationService = require(Services.MonetizationService)
local ChallengeService = require(Services.ChallengeService)
local TournamentService = require(Services.TournamentService)
local AdminService = require(Services.AdminService)
local CommunityService = require(Services.CommunityService)
local StaffService = require(Services.StaffService)
local DailyService = require(Services.DailyService)
local EventService = require(Services.EventService)
local FriendService = require(Services.FriendService)
local LeaderboardService = require(Services.LeaderboardService)
local CupService = require(Services.CupService)
local ReputationService = require(Services.ReputationService)

-- Ordre d'initialisation : les données d'abord, puis ce qui en dépend.
local ORDERED_SERVICES = {
	{ name = "PlayerDataService", module = PlayerDataService },
	{ name = "EconomyService", module = EconomyService },
	{ name = "ClubService", module = ClubService },
	{ name = "TutorialService", module = TutorialService },
	{ name = "OnboardingService", module = OnboardingService },
	{ name = "BuildingService", module = BuildingService },
	{ name = "SquadService", module = SquadService },
	{ name = "StaffService", module = StaffService },
	{ name = "MatchService", module = MatchService },
	{ name = "CosmeticService", module = CosmeticService },
	{ name = "MonetizationService", module = MonetizationService },
	{ name = "ChallengeService", module = ChallengeService },
	{ name = "TournamentService", module = TournamentService },
	{ name = "AdminService", module = AdminService },
	{ name = "CommunityService", module = CommunityService },
	{ name = "DailyService", module = DailyService },
	{ name = "EventService", module = EventService },
	{ name = "FriendService", module = FriendService },
	{ name = "LeaderboardService", module = LeaderboardService },
	{ name = "CupService", module = CupService },
	{ name = "ReputationService", module = ReputationService },
}

for _, entry in ORDERED_SERVICES do
	local ok, err = pcall(entry.module.Init)
	if not ok then
		warn(("[Main] Échec de l'initialisation de %s : %s"):format(entry.name, tostring(err)))
	end
end

-- Étape protégée : une erreur dans un service est signalée dans la sortie
-- sans bloquer l'arrivée du joueur (sinon il resterait sans terrain ni menu).
local function step(label: string, fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[Main] %s a échoué : %s"):format(label, tostring(result)))
		return false, nil
	end
	return true, result
end

local function onPlayerAdded(player: Player)
	local loaded, profile = step("PlayerDataService.Load", PlayerDataService.Load, player)
	if not loaded or not profile or not player.Parent then
		return
	end

	-- L'effectif est créé avant l'attribution du terrain pour que la liste
	-- des clubs affiche tout de suite une note correcte.
	step("SquadService.OnPlayerReady", SquadService.OnPlayerReady, player, profile)
	step("StaffService.OnPlayerReady", StaffService.OnPlayerReady, player, profile)
	step("ReputationService.OnPlayerReady", ReputationService.OnPlayerReady, player, profile)
	local ready, assigned = step("ClubService.OnPlayerReady", ClubService.OnPlayerReady, player, profile)
	if not ready or not assigned then
		-- Sans terrain, le joueur ne peut pas jouer : profil libéré (sauvegardé)
		-- et message clair plutôt qu'un écran vide.
		ClubService.OnPlayerLeaving(player)
		PlayerDataService.Release(player)
		if ready == false and player.Parent then
			player:Kick(Locale.TP(player, "kick.loadFailed"))
		end
		return
	end
	if not player.Parent then
		return -- parti pendant l'installation : onPlayerRemoving s'en occupe
	end

	PlayerDataService.MarkChanged(player)
	step("ClubsUpdated", Net.FireClient, "ClubsUpdated", player, ClubService.GetClubList())
	step("ChallengeService.OnPlayerReady", ChallengeService.OnPlayerReady, player)
	step("TournamentService.OnPlayerReady", TournamentService.OnPlayerReady, player)
	-- Récompense du jour, missions, revenus hors ligne, fin de saison.
	step("DailyService.OnPlayerReady", DailyService.OnPlayerReady, player)
	step("EventService.OnPlayerReady", EventService.OnPlayerReady, player)
	-- Amis présents, bonus d'invitation (parrainage Roblox).
	step("FriendService.OnPlayerReady", FriendService.OnPlayerReady, player)
	-- Classement mondial : état actuel envoyé au joueur.
	step("LeaderboardService.OnPlayerReady", LeaderboardService.OnPlayerReady, player)
	if profile.temporary then
		Net.FireClient(
			"Notify",
			player,
			Locale.TP(player, "notify.testMode"),
			"info"
		)
	end
end

local function onPlayerRemoving(player: Player)
	-- Chaque étape est protégée : la sauvegarde finale doit toujours avoir lieu.
	step("ChallengeService.OnPlayerLeaving", ChallengeService.OnPlayerLeaving, player)
	step("TournamentService.OnPlayerLeaving", TournamentService.OnPlayerLeaving, player)
	step("FriendService.OnPlayerLeaving", FriendService.OnPlayerLeaving, player)
	step("LeaderboardService.OnPlayerLeaving", LeaderboardService.OnPlayerLeaving, player)
	step("ClubService.OnPlayerLeaving", ClubService.OnPlayerLeaving, player)
	step("AdminService.OnPlayerLeaving", AdminService.OnPlayerLeaving, player)
	step("PlayerDataService.Release", PlayerDataService.Release, player)
	Net.ForgetPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Joueurs déjà présents (cas du test en solo dans Studio).
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[Main] Football Club Tycoon : serveur prêt.")
