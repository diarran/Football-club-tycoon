--[[
	DailyService
	Donner envie de revenir chaque jour (règles et montants : shared/Daily.lua).

	- Récompense de connexion : versée automatiquement une fois par jour UTC,
	  à l'arrivée ou à minuit si le joueur est en ligne. Série sur 7 jours.
	- Missions du jour : 3 missions tirées pour le joueur, renouvelées à minuit
	  UTC. Les services appellent DailyService.Track quand une action réussit ;
	  la prime est versée dès qu'une mission est accomplie.
	- Revenus hors ligne : à l'arrivée, part réduite des revenus des
	  installations pendant l'absence (plafond 8 h). L'heure de départ
	  (data.lastSeenAt) est écrite par le serveur à chaque sauvegarde.
	- Saisons de 7 jours : points de saison, classement contre les clubs
	  fictifs de la division, prime de fin de saison et trophée pour le titre.

	Tout se calcule avec os.time() côté serveur : le client n'envoie rien.
	Un résumé « Pendant ton absence… » est joint à l'instantané (welcome).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Daily = require(Shared.Daily)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local DailyService = {}

local CHECK_INTERVAL_SECONDS = 30 -- vérification du changement de jour en ligne
local welcomeCounter = 0

local function notify(player: Player, key: string, params)
	if player.Parent then
		Net.FireClient("Notify", player, Locale.TP(player, key, params), "success")
	end
end

local function canUpgrade(data): boolean
	for id in Buildings.Definitions do
		if (data.buildings[id] or 1) < Buildings.MaxLevel(id) then
			return true
		end
	end
	return false
end

local function canRecruit(data): boolean
	if #data.squad < Config.MAX_SQUAD_SIZE then
		return true
	end
	local division = Divisions.Get(data.club.division)
	return division ~= nil and division.transfer ~= nil
end

-- Fin de saison : classement final, prime, trophée du titre.
local function closeSeason(player: Player, data, currentId: number)
	local season = data.season
	local summary = nil
	if season.id < currentId and season.points > 0 then
		local division = Divisions.Get(season.division) and season.division or data.club.division
		local _, rank = Daily.SeasonStandings(division, data.club.name or "", season.points, 1)
		local reward = Daily.SeasonReward(rank, division)
		EconomyService.Add(player, reward, "season:" .. season.id .. ":" .. rank)
		if rank == 1 then
			data.club.stats.seasonsWon += 1
		end
		summary = { rank = rank, reward = reward, points = season.points }
		data.seasonLast = { id = season.id, rank = rank, reward = reward, points = season.points }
	end
	data.season = { id = currentId, points = 0, division = data.club.division }
	return summary
end

-- Met à jour jour et saison. Renvoie un résumé de ce qui a été versé.
-- login = true à l'arrivée du joueur (revenus hors ligne comptés).
function DailyService.Refresh(player: Player, login: boolean?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil
	end
	local now = os.time()
	local today = Daily.Day(now)
	local summary = {}
	local changed = false

	-- Revenus hors ligne (une seule fois, à l'arrivée).
	if login then
		local away = now - (data.lastSeenAt or now)
		local coins, counted = Daily.OfflineIncome(data.buildings, away)
		if coins > 0 then
			EconomyService.Add(player, coins, "offline")
			summary.offline = { coins = coins, seconds = counted, away = away }
		end
		data.lastSeenAt = now
		changed = true
	end

	-- Saison terminée ?
	local seasonId = Daily.SeasonId(now)
	if data.season.id ~= seasonId then
		summary.season = closeSeason(player, data, seasonId)
		changed = true
	end

	-- Récompense du jour.
	local daily = data.daily
	if daily.lastClaimDay < today then
		daily.streak = if daily.lastClaimDay == today - 1 then daily.streak + 1 else 1
		daily.lastClaimDay = today
		local coins = Daily.StreakReward(daily.streak, data.club.division)
		EconomyService.Add(player, coins, "daily:" .. Daily.CycleDay(daily.streak))
		summary.daily = { coins = coins, day = Daily.CycleDay(daily.streak), streak = daily.streak }
		changed = true
	end

	-- Nouvelles missions.
	if data.missions.day ~= today then
		data.missions = {
			day = today,
			list = Daily.PickMissions(player.UserId, today, data.club.division, function(needs)
				if needs == "upgrade" then
					return canUpgrade(data)
				elseif needs == "recruit" then
					return canRecruit(data)
				end
				return true
			end),
		}
		changed = true
	end

	if changed then
		PlayerDataService.MarkChanged(player)
	end
	if summary.offline or summary.daily or summary.season then
		return summary
	end
	return nil
end

-- Une action réussie : stat = "win" | "play" | "goals" | "upgrade" | "recruit".
-- Renvoie les FC Coins versés pour les missions accomplies par cette action.
function DailyService.Track(player: Player, stat: string, amount: number?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	DailyService.Refresh(player)
	amount = amount or 1
	local paid = 0
	for _, mission in data.missions.list do
		local def = Daily.GetMission(mission.id)
		if def and def.stat == stat and not mission.done and amount > 0 then
			mission.progress = math.min(mission.target, mission.progress + amount)
			if mission.progress >= mission.target then
				mission.done = true
				EconomyService.Add(player, mission.reward, "mission:" .. mission.id)
				paid += mission.reward
				local lang = Locale.ForPlayer(player)
				notify(player, "mission.done", {
					mission = Locale.T(lang, "mission." .. mission.id, { n = mission.target }),
					coins = mission.reward,
				})
			end
		end
	end
	PlayerDataService.MarkChanged(player)
	return paid
end

-- Points de saison gagnés en match (mêmes points que la division).
function DailyService.AddSeasonPoints(player: Player, points: number)
	local data = PlayerDataService.GetData(player)
	if not data or type(points) ~= "number" or points <= 0 then
		return
	end
	DailyService.Refresh(player)
	data.season.points += math.floor(points)
	data.season.division = data.club.division
end

-- Partie « objectifs » de l'instantané envoyé au client (lecture seule).
function DailyService.Snapshot(player: Player, data)
	local now = os.time()
	local season = data.season
	local progress = Daily.SeasonProgress(season.id, now)
	local rows, rank = Daily.SeasonStandings(data.club.division, data.club.name or "", season.points, progress)
	local missions = {}
	for _, mission in data.missions.list do
		table.insert(missions, table.clone(mission))
	end
	local profile = PlayerDataService.Get(player)
	local nextStreak = if data.daily.lastClaimDay == Daily.Day(now) then data.daily.streak + 1 else 1
	return {
		streak = data.daily.streak,
		cycleDay = Daily.CycleDay(data.daily.streak),
		nextReward = Daily.StreakReward(nextStreak, data.club.division),
		missions = missions,
		resetIn = Daily.SecondsToNextDay(now),
		season = {
			id = season.id,
			points = season.points,
			rank = rank,
			rows = rows,
			endsIn = math.max(0, Daily.SeasonEndsAt(season.id) - now),
			reward = Daily.SeasonReward(rank, data.club.division),
			last = data.seasonLast,
		},
		welcome = profile and profile.welcome,
	}
end

-- À l'arrivée : tout ce qui s'est passé pendant l'absence.
function DailyService.OnPlayerReady(player: Player)
	local summary = DailyService.Refresh(player, true)
	local profile = PlayerDataService.Get(player)
	if summary and profile then
		welcomeCounter += 1
		summary.id = welcomeCounter
		profile.welcome = summary
		PlayerDataService.MarkChanged(player)
	end
	return summary
end

function DailyService.Init()
	PlayerDataService.AddSnapshotField("daily", DailyService.Snapshot)
	-- Minuit UTC pendant que le joueur est en ligne : nouvelles missions,
	-- récompense du jour, fin de saison.
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL_SECONDS)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local ok, summary = pcall(DailyService.Refresh, player)
				if ok and summary then
					if summary.daily then
						notify(player, "daily.claimed", { coins = summary.daily.coins, day = summary.daily.day })
					end
					if summary.season then
						notify(player, "season.ended", { rank = summary.season.rank, coins = summary.season.reward })
					end
				end
			end
		end
	end)
end

return DailyService
