--[[
	Divisions
	Progression sportive (document de conception, section 6) : D7 à D1.
	Seuils, notes et récompenses équilibrés avec tools/economy-sim.js
	(docs/economy/README.md). D7 → D5 reste le rythme du MVP (~40 min) ;
	D1 est l'objectif long terme (plusieurs dizaines d'heures de jeu).

	Tout est lu par le serveur pour valider les matchs : le client ne s'en
	sert que pour l'affichage.
]]

local Tactics = require(script.Parent.Tactics)

local Divisions = {}

-- pointsToPromote : points de division nécessaires pour monter (nil en D1).
-- Nom affiché : clé « division.label » de Locale (« Division {tier} »).
-- opponentRating : note moyenne des clubs fictifs de la division.
-- rewardMultiplier : multiplie la prime de match (Config.Rewards).
-- promotionReward : prime unique versée en arrivant dans cette division.
-- transfer : marché des transferts (effectif complet) : prix et notes des
--   joueurs proposés. Le transfert remplace le joueur le moins bien noté.
Divisions.List = {
	{ id = "D7", tier = 7, pointsToPromote = 15, opponentRating = 45, rewardMultiplier = 1, promotionReward = 0 },
	{ id = "D6", tier = 6, pointsToPromote = 36, opponentRating = 56, rewardMultiplier = 1, promotionReward = 500 },
	{
		id = "D5",
		tier = 5,
		pointsToPromote = 320,
		opponentRating = 62,
		rewardMultiplier = 1,
		promotionReward = 1500,
		transfer = { cost = 6000, ratingMin = 52, ratingMax = 60, potentialBonusMax = 4 },
	},
	{
		id = "D4",
		tier = 4,
		pointsToPromote = 650,
		opponentRating = 73,
		rewardMultiplier = 1.4,
		promotionReward = 10000,
		transfer = { cost = 15000, ratingMin = 58, ratingMax = 66, potentialBonusMax = 4 },
	},
	{
		id = "D3",
		tier = 3,
		pointsToPromote = 1000,
		opponentRating = 80,
		rewardMultiplier = 1.8,
		promotionReward = 25000,
		transfer = { cost = 30000, ratingMin = 65, ratingMax = 73, potentialBonusMax = 4 },
	},
	{
		id = "D2",
		tier = 2,
		pointsToPromote = 1500,
		opponentRating = 86,
		rewardMultiplier = 2.3,
		promotionReward = 50000,
		transfer = { cost = 50000, ratingMin = 72, ratingMax = 80, potentialBonusMax = 4 },
	},
	{
		id = "D1",
		tier = 1,
		pointsToPromote = nil,
		opponentRating = 92,
		rewardMultiplier = 3,
		promotionReward = 100000,
		transfer = { cost = 80000, ratingMin = 78, ratingMax = 86, potentialBonusMax = 4 },
	},
}

Divisions.STARTING_DIVISION = "D7"

-- Clubs fictifs de chaque division (adversaires quand il n'y a pas assez de
-- clubs humains, et lignes du classement de division).
-- offset : écart de note avec opponentRating ; share : part du seuil de montée
-- affichée comme points au classement ; le plus fort est en tête.
Divisions.RIVALS = {
	{ offset = 4, share = 0.85 },
	{ offset = 2, share = 0.65 },
	{ offset = 0, share = 0.45 },
	{ offset = -2, share = 0.3 },
	{ offset = -4, share = 0.15 },
}
Divisions.DEFAULT_RIVAL = 3 -- adversaire « ai » des anciennes versions
Divisions.RIVAL_REWARD_PER_POINT = 0.05 -- prime ±5 % par point d'écart de note
Divisions.MIN_OPPONENTS = 3 -- clubs fictifs ajoutés jusqu'à ce nombre d'adversaires
-- Points affichés pour les clubs fictifs de D1, qui n'a pas de seuil.
Divisions.TOP_REFERENCE_POINTS = 300

local PREFIXES = { "Racing", "Sporting", "Olympique", "Union", "Stade", "Athletic", "Inter", "Dynamo", "Real", "Atlético" }
local PLACES = {
	"Montclair",
	"Valrose",
	"Bellerive",
	"Hautefort",
	"Clairval",
	"Rochebrune",
	"Pontlevoy",
	"Mirabel",
	"Castelnau",
	"Beauséjour",
	"Fontbrune",
	"Sainte-Aure",
	"Port-Lune",
	"Vauclair",
}

local byId = {}
for index, division in Divisions.List do
	division.index = index
	byId[division.id] = division
end

function Divisions.Get(id: string)
	return byId[id]
end

-- Division supérieure, ou nil si c'est la plus haute.
function Divisions.GetNext(id: string)
	local division = byId[id]
	if not division then
		return nil
	end
	return Divisions.List[division.index + 1]
end

-- Club fictif n° rivalIndex d'une division : nom fixe, note, points affichés.
-- Pas de tirage au sort : le même club a toujours le même nom.
function Divisions.GetRival(divisionId: string, rivalIndex: number)
	local division = byId[divisionId]
	local rival = Divisions.RIVALS[rivalIndex]
	if not division or not rival then
		return nil
	end
	local seed = division.index * #Divisions.RIVALS + rivalIndex
	local name = PREFIXES[(seed * 7) % #PREFIXES + 1] .. " " .. PLACES[(seed * 5) % #PLACES + 1]
	local reference = division.pointsToPromote or Divisions.TOP_REFERENCE_POINTS
	return {
		id = ("ai:%d"):format(rivalIndex),
		index = rivalIndex,
		name = name,
		rating = division.opponentRating + rival.offset,
		points = math.floor(reference * rival.share),
		rewardFactor = 1 + rival.offset * Divisions.RIVAL_REWARD_PER_POINT,
		tactic = Tactics.RivalStyle(division.index, rivalIndex), -- style fixe, affiché avant le match
	}
end

function Divisions.GetRivals(divisionId: string)
	local list = {}
	for index in Divisions.RIVALS do
		table.insert(list, Divisions.GetRival(divisionId, index))
	end
	return list
end

-- Clubs fictifs proposés en match : le club de même niveau, puis un plus
-- faible, puis un plus fort, jusqu'à avoir MIN_OPPONENTS adversaires en
-- comptant les clubs humains présents. Toujours au moins un club fictif.
function Divisions.GetSuggestedRivals(divisionId: string, humanOpponents: number)
	local order = { Divisions.DEFAULT_RIVAL, Divisions.DEFAULT_RIVAL + 1, Divisions.DEFAULT_RIVAL - 1 }
	local count = math.clamp(Divisions.MIN_OPPONENTS - humanOpponents, 1, #order)
	local list = {}
	for i = 1, count do
		table.insert(list, Divisions.GetRival(divisionId, order[i]))
	end
	return list
end

-- « ai » ou « ai:<n> » -> numéro de club fictif valide, sinon nil.
function Divisions.ParseRivalId(opponentId: any): number?
	if opponentId == "ai" then
		return Divisions.DEFAULT_RIVAL
	end
	if type(opponentId) ~= "string" then
		return nil
	end
	local n = tonumber(opponentId:match("^ai:(%d)$"))
	if n and Divisions.RIVALS[n] then
		return n
	end
	return nil
end

return Divisions
