--[[
	PlayerConfig
	Configuration des footballeurs (document de conception, section 5).
	Tous les noms sont fictifs.
]]

local PlayerConfig = {}

-- Nom affiché : clé « position.<id> » de Locale.
PlayerConfig.Positions = {
	GK = { id = "GK" },
	DEF = { id = "DEF" },
	MID = { id = "MID" },
	ATT = { id = "ATT" },
}

-- Postes de l'effectif de départ (3 joueurs).
PlayerConfig.STARTING_POSITIONS = { "GK", "MID", "ATT" }

PlayerConfig.FirstNames = {
	"Lucas",
	"Noé",
	"Yanis",
	"Hugo",
	"Malik",
	"Théo",
	"Enzo",
	"Sami",
	"Ilyes",
	"Jules",
	"Adam",
	"Nathan",
	"Rayan",
	"Léo",
	"Kylian",
	"Bastien",
}

PlayerConfig.LastNames = {
	"Moreau",
	"Delcourt",
	"Benali",
	"Fontaine",
	"Kerouac",
	"Marchetti",
	"Okafor",
	"Lemaire",
	"Rivière",
	"Duval",
	"Traoré",
	"Navarro",
	"Perrin",
	"Vasseur",
	"Garnier",
	"Mbaye",
}

PlayerConfig.AGE_MIN = 17
PlayerConfig.AGE_MAX = 33

-- Notes des joueurs générés (sur 100).
PlayerConfig.STARTING_RATING_MIN = 40
PlayerConfig.STARTING_RATING_MAX = 50
PlayerConfig.RECRUIT_RATING_MIN = 42
PlayerConfig.RECRUIT_RATING_MAX = 55
PlayerConfig.POTENTIAL_BONUS_MAX = 20
PlayerConfig.MAX_RATING = 99

PlayerConfig.MAX_ENERGY = 100

-- Prix d'un recrutement simple (valeur + premier salaire, simplifié).
PlayerConfig.RECRUIT_COST = 1500

-- Centre de formation : âge et postes des jeunes repérés ; le reste (note,
-- potentiel, prix, fréquence) dépend du niveau de l'installation (Buildings.lua).
PlayerConfig.PROSPECT_AGE_MIN = 16
PlayerConfig.PROSPECT_AGE_MAX = 18
PlayerConfig.PROSPECT_POSITIONS = { "GK", "DEF", "DEF", "MID", "MID", "ATT", "ATT" }
-- Fréquence (secondes) à laquelle le serveur vérifie l'arrivée de nouveaux jeunes.
PlayerConfig.SCOUT_CHECK_SECONDS = 30

return PlayerConfig
