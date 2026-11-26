--[[
	Divisions
	Progression sportive (document de conception, section 6).
	Le MVP couvre D7 à D5. D4 à D1 sont prévues pour plus tard.
]]

local Divisions = {}

-- pointsToPromote : points de division nécessaires pour monter.
-- opponentRating : note moyenne des adversaires d'entraînement (clubs IA).
Divisions.List = {
	{ id = "D7", label = "Division 7", tier = 7, pointsToPromote = 9, opponentRating = 45 },
	{ id = "D6", label = "Division 6", tier = 6, pointsToPromote = 12, opponentRating = 52 },
	{ id = "D5", label = "Division 5", tier = 5, pointsToPromote = nil, opponentRating = 58 },
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
