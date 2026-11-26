--[[
	PlayerDataService
	Chargement, sauvegarde, versionnement et récupération des profils.

	- Un profil par joueur, stocké dans un DataStore Roblox (jamais dans GitHub).
	- Verrou de session : un profil n'est ouvert que par un seul serveur à la fois,
	  pour éviter qu'un départ rapide puis un retour sur un autre serveur
	  n'écrase la progression.
	- Version de schéma + migrations pour faire évoluer les profils.
	- Sauvegarde automatique, à la déconnexion et à la fermeture du serveur.
	- Dans Studio sans accès aux API, le jeu fonctionne avec un profil
	  temporaire (non sauvegardé) et l'indique dans la sortie.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Buildings = require(Shared.Buildings)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Trophies = require(Shared.Trophies)

local PlayerDataService = {}

local LOCK_TIMEOUT_SECONDS = Config.AUTOSAVE_INTERVAL_SECONDS * 3
local LOAD_ATTEMPTS = 5
local LOAD_RETRY_DELAY = 4

local store = nil -- DataStore, ou nil si indisponible (Studio sans accès API)
local profiles = {} -- [Player] = { data, temporary, loadedAt }
local pendingSnapshot = {} -- [Player] = true quand un envoi est prévu
local releasing = {} -- [UserId] = nombre de sauvegardes de départ en cours
local RELEASE_WAIT_SECONDS = 60
local changeListeners = {} -- fonctions appelées avant chaque envoi d'instantané
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

-- Profil par défaut -----------------------------------------------------

local function defaultData()
	return {
		schemaVersion = Config.DATA_SCHEMA_VERSION,
		coins = Config.STARTING_COINS,
		club = {
			name = nil, -- généré par ClubService au premier chargement
			division = Divisions.STARTING_DIVISION,
			divisionPoints = 0,
			stats = { played = 0, wins = 0, draws = 0, losses = 0, goalsFor = 0, goalsAgainst = 0 },
		},
		buildings = Buildings.DefaultLevels(),
		squad = {}, -- rempli par SquadService au premier chargement
		nextPlayerId = 1,
		-- Centre de formation : jeunes repérés en attente de signature (SquadService).
		academy = { prospects = {}, lastScoutAt = 0 },
		tactic = Config.DEFAULT_TACTIC,
		-- Personnalisation achetée (CosmeticService) : owned = { [id] = true },
		-- equipped = { [catégorie] = id } pour les catégories à objet unique.
		cosmetics = { owned = {}, equipped = {} },
		-- Salle des trophées : titres de champion de D1, trophées déjà annoncés.
		trophies = { titles = 0, seen = 0 },
		tutorial = { step = 1, completed = false },
		lastMatchAt = 0,
		lastEnergyUpdate = os.time(),
		createdAt = os.time(),
	}
end

-- Complète un profil existant avec les champs manquants (ajoutés plus tard).
local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			data[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			reconcile(data[key], value)
		end
	end
end

-- Migrations : MIGRATIONS[n] transforme un profil version n en version n + 1.
local MIGRATIONS = {
	-- [1] = function(data) ... data.schemaVersion = 2 end,
}

local function migrate(data)
	local version = data.schemaVersion or 1
	while version < Config.DATA_SCHEMA_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			warn(("[PlayerData] Migration %d -> %d manquante"):format(version, version + 1))
			break
		end
		step(data)
		version += 1
		data.schemaVersion = version
	end
	reconcile(data, defaultData())
	-- Nouvelles installations ajoutées après la création du profil.
	for id in Buildings.Definitions do
		if type(data.buildings[id]) ~= "number" then
			data.buildings[id] = 1
		end
	end
	return data
end

-- DataStore -------------------------------------------------------------

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function withRetries(label: string, fn)
	local lastErr
	for attempt = 1, Config.DATASTORE_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[PlayerData] %s : tentative %d échouée (%s)"):format(label, attempt, tostring(result)))
		task.wait(2 ^ attempt)
	end
	return false, lastErr
end

-- Ouvre le profil et pose le verrou de session. Renvoie (data, raison).
local function openProfile(player: Player)
	local key = keyFor(player)
	for _ = 1, LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local ok, record = withRetries("Chargement " .. key, function()
			return store:UpdateAsync(key, function(current)
				current = current or { data = nil, lock = nil }
				local lock = current.lock
				-- Dans Studio, on ignore les verrous pour pouvoir relancer un test immédiatement.
				local foreign = lock and lock.jobId ~= jobId and not RunService:IsStudio()
				if foreign and os.time() - (lock.time or 0) < LOCK_TIMEOUT_SECONDS then
					lockedElsewhere = true
					return nil -- n'écrit rien
				end
				current.lock = { jobId = jobId, time = os.time() }
				return current
			end)
		end)
		if not ok then
			return nil, "datastore"
		end
		if not lockedElsewhere and record then
			return migrate(record.data or defaultData()), nil
		end
		task.wait(LOAD_RETRY_DELAY)
		if not player.Parent then
			return nil, "left"
		end
	end
	return nil, "locked"
end

local function writeProfile(player: Player, data, release: boolean): boolean
	local key = keyFor(player)
	local ok = withRetries("Sauvegarde " .. key, function()
		return store:UpdateAsync(key, function(current)
			current = current or {}
			local lock = current.lock
			if lock and lock.jobId ~= jobId and not RunService:IsStudio() then
				-- Un autre serveur a repris le profil : ne pas l'écraser.
				return nil
			end
			if not lock and not release then
				-- Profil déjà libéré (joueur parti) : une sauvegarde tardive ne doit
				-- pas reposer le verrou, sinon le joueur serait bloqué ailleurs.
				return nil
			end
			current.data = data
			current.lock = if release then nil else { jobId = jobId, time = os.time() }
			return current
		end)
	end)
	return ok
end

-- API -------------------------------------------------------------------

function PlayerDataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
		-- Vérifie l'accès (dans Studio, il faut activer « Enable Studio Access to API Services »).
		local probeOk, probeErr = pcall(function()
			return store:GetAsync("__probe")
		end)
		if not probeOk then
			store = nil
			warn(
				"[PlayerData] DataStore indisponible, profils temporaires utilisés : " .. tostring(probeErr)
			)
		end
	else
		warn("[PlayerData] DataStore indisponible, profils temporaires utilisés : " .. tostring(result))
	end

	-- Sauvegarde automatique.
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL_SECONDS)
			for player in profiles do
				task.spawn(PlayerDataService.Save, player, false)
			end
		end
	end)

	-- Fermeture du serveur : tout sauvegarder avant l'arrêt.
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				PlayerDataService.Save(player, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	Net.HandleFunction("GetSnapshot", function(player)
		return PlayerDataService.BuildSnapshot(player)
	end)
end

-- Charge le profil d'un joueur. Renvoie le profil, ou nil si le joueur a été expulsé/est parti.
function PlayerDataService.Load(player: Player)
	if profiles[player] then
		return profiles[player]
	end

	-- Retour rapide sur le même serveur : attendre la fin de la sauvegarde de
	-- départ, sinon on relirait une ancienne version du profil.
	local waitUntil = os.clock() + RELEASE_WAIT_SECONDS
	while releasing[player.UserId] and os.clock() < waitUntil do
		task.wait(0.2)
	end
	if not player.Parent then
		return nil
	end

	local data, reason
	local temporary = false
	if store then
		data, reason = openProfile(player)
	else
		data, temporary = defaultData(), true
	end

	if not data then
		if reason == "locked" then
			player:Kick(Locale.TP(player, "kick.sessionLocked"))
		elseif reason == "datastore" then
			player:Kick(Locale.TP(player, "kick.loadFailed"))
		end
		return nil
	end

	if not player.Parent then
		-- Parti pendant le chargement : libérer le verrou.
		if store then
			writeProfile(player, data, true)
		end
		return nil
	end

	local profile = { data = data, temporary = temporary, loadedAt = os.time() }
	profiles[player] = profile
	if temporary then
		print(("[PlayerData] Profil temporaire pour %s (non sauvegardé)."):format(player.Name))
	end
	return profile
end

function PlayerDataService.Get(player: Player)
	return profiles[player]
end

function PlayerDataService.GetData(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function PlayerDataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile.temporary or not store then
		return true
	end
	if profile.releasing and not release then
		return true -- la sauvegarde de départ s'en occupe
	end
	return writeProfile(player, profile.data, release == true)
end

-- À appeler quand le joueur quitte : sauvegarde finale + libération du verrou.
function PlayerDataService.Release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.releasing = true
	local userId = player.UserId
	releasing[userId] = (releasing[userId] or 0) + 1
	local ok, err = pcall(PlayerDataService.Save, player, true)
	releasing[userId] -= 1
	if releasing[userId] <= 0 then
		releasing[userId] = nil
	end
	profiles[player] = nil
	pendingSnapshot[player] = nil
	if not ok then
		warn("[PlayerData] Sauvegarde de départ impossible : " .. tostring(err))
	end
end

-- Copie de l'état envoyée au client (lecture seule côté client).
function PlayerDataService.BuildSnapshot(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil
	end
	local now = os.time()
	return {
		coins = data.coins,
		club = table.clone(data.club),
		buildings = table.clone(data.buildings),
		squad = data.squad,
		prospects = data.academy.prospects,
		tactic = data.tactic,
		tutorial = table.clone(data.tutorial),
		cosmetics = { owned = table.clone(data.cosmetics.owned), equipped = table.clone(data.cosmetics.equipped) },
		trophies = Trophies.Earned(data.club.division, data.club.stats, data.trophies.titles),
		titles = data.trophies.titles,
		matchCooldown = math.max(0, Config.MATCH_COOLDOWN_SECONDS - (now - data.lastMatchAt)),
		temporary = profiles[player].temporary,
	}
end

-- Signale un changement : un instantané est envoyé au client (regroupé par image).
function PlayerDataService.MarkChanged(player: Player)
	if pendingSnapshot[player] then
		return
	end
	pendingSnapshot[player] = true
	task.defer(function()
		pendingSnapshot[player] = nil
		if player.Parent and profiles[player] then
			for _, listener in changeListeners do
				local ok, err = pcall(listener, player, profiles[player].data)
				if not ok then
					warn("[PlayerData] Erreur dans un suivi de changement : " .. tostring(err))
				end
			end
		end
		if player.Parent and profiles[player] then
			Net.FireClient("ProfileUpdated", player, PlayerDataService.BuildSnapshot(player))
		end
	end)
end

-- Branche une fonction(player, data) appelée après chaque changement du profil
-- (regroupé par image), juste avant l'envoi de l'instantané au client.
function PlayerDataService.OnChanged(listener)
	table.insert(changeListeners, listener)
end

function PlayerDataService.GetLoadedPlayers()
	local list = {}
	for player in profiles do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

return PlayerDataService
