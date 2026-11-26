--[[
	Config
	Constantes communes au client et au serveur.

	Tout ce qui est ici est visible par les joueurs (ReplicatedStorage) :
	ne jamais y mettre de secret. Les valeurs économiques (solde de départ,
	primes, énergie) sont équilibrées avec le simulateur tools/economy-sim.js :
	le relancer après chaque changement (voir docs/economy/README.md).
]]

local Config = {}

-- Économie --------------------------------------------------------------
Config.CURRENCY_NAME = "FC Coins"
Config.STARTING_COINS = 2500
Config.MAX_COINS = 1e12 -- garde-fou contre les débordements

-- Monde -----------------------------------------------------------------
Config.MAX_CLUBS_PER_SERVER = 6
Config.PLOT_SIZE = Vector3.new(160, 1, 110)
Config.PLOT_SPACING = 40 -- espace entre deux terrains
Config.PLOT_COLUMNS = 3

-- Effectif --------------------------------------------------------------
Config.STARTING_PLAYERS = 3
Config.MAX_SQUAD_SIZE = 7 -- à fixer après le prototype de match

-- Matchs ----------------------------------------------------------------
Config.MATCH_COOLDOWN_SECONDS = 60
Config.HOME_ADVANTAGE = 3 -- points de note ajoutés au club hôte
Config.ENERGY_COST_PER_MATCH = 10
Config.ENERGY_RECOVERY_PER_MINUTE = 8

-- Nom affiché : clé « tactic.<id> » de Locale.
Config.Tactics = {
	Balanced = { attack = 0, defense = 0 },
	Offensive = { attack = 4, defense = -3 },
	Defensive = { attack = -3, defense = 4 },
}
Config.DEFAULT_TACTIC = "Balanced"

Config.Rewards = {
	Win = 400,
	Draw = 200,
	Loss = 100,
}
Config.DivisionPoints = {
	Win = 3,
	Draw = 1,
	Loss = 0,
}

-- Nom du club -----------------------------------------------------------
Config.CLUB_NAME_MIN_LENGTH = 3
Config.CLUB_NAME_MAX_LENGTH = 24

-- Sauvegarde ------------------------------------------------------------
Config.DATASTORE_NAME = "PlayerProfiles_v1"
Config.DATA_SCHEMA_VERSION = 1
Config.AUTOSAVE_INTERVAL_SECONDS = 120
Config.DATASTORE_RETRIES = 3

-- Réseau ----------------------------------------------------------------
-- Nombre maximum de requêtes par joueur et par fenêtre, pour chaque remote.
Config.RATE_LIMIT_WINDOW_SECONDS = 5
Config.RATE_LIMIT_MAX_REQUESTS = 8

return Config
