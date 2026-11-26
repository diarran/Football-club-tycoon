--[[
	PlayerConfig
	Configuration des footballeurs (document de conception, section 5).
	Tous les noms sont fictifs.
]]

local PlayerConfig = {}

PlayerConfig.Positions = {
	GK = { id = "GK", label = "Gardien" },
	DEF = { id = "DEF", label = "Défenseur" },
	MID = { id = "MID", label = "Milieu" },
	ATT = { id = "ATT", label = "Attaquant" },
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

return PlayerConfig
