--[[
	ClubNames
	Génération de noms de clubs fictifs.
	Tous les noms doivent rester fictifs : aucun vrai club, aucune marque.
]]

local ClubNames = {}

ClubNames.Prefixes = {
	"AS",
	"FC",
	"US",
	"Racing",
	"Sporting",
	"Olympique",
	"Stade",
	"Union",
	"Athletic",
	"Real",
}

ClubNames.Places = {
	"Vallorne",
	"Brisemont",
	"Lacroix-Verte",
	"Port-Aurel",
	"Haute-Rive",
	"Saint-Calmin",
	"Montclair",
	"Bellefond",
	"Roche-Dorée",
	"Valmeuse",
	"Ferlac",
	"Chênebourg",
}

ClubNames.Suffixes = {
	"",
	"",
	"",
	"FC",
	"Club",
	"United",
	"Étoile",
}

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

-- Renvoie un nom de club aléatoire, par exemple « Racing Montclair United ».
function ClubNames.Generate(rng: Random?): string
	local random = rng or Random.new()
	local parts = { pick(ClubNames.Prefixes, random), pick(ClubNames.Places, random) }
	local suffix = pick(ClubNames.Suffixes, random)
	if suffix ~= "" and suffix ~= parts[1] then
		table.insert(parts, suffix)
	end
	return table.concat(parts, " ")
end

return ClubNames
