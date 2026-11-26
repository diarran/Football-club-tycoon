--[[
	Divisions
	Progression sportive (document de conception, section 6).
	Le MVP couvre D7 à D5. D4 à D1 sont prévues pour plus tard.
	Seuils et notes équilibrés avec tools/economy-sim.js (docs/economy/README.md).
]]

local Divisions = {}

-- pointsToPromote : points de division nécessaires pour monter.
-- Nom affiché : clé « division.label » de Locale (« Division {tier} »).
-- opponentRating : note moyenne des adversaires d'entraînement (clubs IA).
Divisions.List = {
	{ id = "D7",tier = 7, pointsToPromote = 15, opponentRating = 45 },
	{ id = "D6",tier = 6, pointsToPromote = 36, opponentRating = 56 },
	{ id = "D5",tier = 5, pointsToPromote = nil, opponentRating = 62 },
}

Divisions.STARTING_DIVISION = "D7"

local byId = {}
for index, division in Divisions.List do
	division.index = index
	byId[division.id] = division
end

function Divisions.Get(id: string)
	return byId[id]
end

-- Division supérieure, ou nil si c'est la plus haute disponible.
function Divisions.GetNext(id: string)
	local division = byId[id]
	if not division then
		return nil
	end
	return Divisions.List[division.index + 1]
end

return Divisions
