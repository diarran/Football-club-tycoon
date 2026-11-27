--[[
	ClubIdentity
	Identité du club choisie par le joueur : couleur principale, couleur
	secondaire, motif du maillot et écusson. Purement visuel (aucun effet sur
	les matchs), vérifié par le serveur (CosmeticService).

	Où ça se voit : les 22 joueurs du replay 3D, les tribunes (sièges,
	drapeaux), tout le terrain du club, les mannequins et l'écusson du HUD.

	Priorité (le dernier choix gagne) :
	- un objet Prestige « couleurs » ou « tenue » porté passe devant l'identité ;
	- choisir une couleur ou un motif ici retire l'objet porté de la catégorie
	  (il reste possédé et se remet dans l'onglet Prestige).

	Profil : data.identity = { primary, secondary, pattern, crest, patterns }
	- primary / secondary : id d'une couleur de COLORS, "" = couleurs de l'emplacement ;
	- pattern : id d'un motif de PATTERNS ("plain" par défaut) ;
	- crest : numéro d'écusson (1 à CREST_COUNT), 0 = celui de l'emplacement ;
	- patterns : motifs achetés en FC Coins ({ [id] = true }).
	Les anciens profils reçoivent ces valeurs par défaut : rien ne change pour eux.

	Les couleurs et motifs exclusifs (Robux, événements) ne sont PAS ici : ils
	restent réservés à leurs objets (Cosmetics.EXCLUSIVE / EVENT).
]]

local Cosmetics = require(script.Parent.Cosmetics)
local Divisions = require(script.Parent.Divisions)
local WorldConfig = require(script.Parent.WorldConfig)

local ClubIdentity = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Nom affiché : clé « identity.color.<id> » de Locale.
ClubIdentity.COLORS = {
	{ id = "red", color = rgb(200, 40, 50) },
	{ id = "white", color = rgb(245, 245, 245) },
	{ id = "blue", color = rgb(30, 80, 180) },
	{ id = "yellow", color = rgb(250, 210, 40) },
	{ id = "green", color = rgb(30, 140, 80) },
	{ id = "purple", color = rgb(110, 40, 150) },
	{ id = "orange", color = rgb(240, 140, 30) },
	{ id = "black", color = rgb(20, 20, 24) },
	{ id = "gold", color = rgb(240, 200, 60) },
	{ id = "sky", color = rgb(40, 170, 210) },
	{ id = "navy", color = rgb(20, 40, 90) },
	{ id = "maroon", color = rgb(120, 25, 40) },
	{ id = "grey", color = rgb(150, 155, 160) },
	{ id = "pink", color = rgb(240, 130, 170) },
}

-- Motifs du maillot. Nom affiché : clé « identity.pattern.<id> ».
-- Déblocage : gratuit, division atteinte (requires), achat en FC Coins (cost)
-- ou tenue Prestige possédée (kit = id de Cosmetics).
ClubIdentity.PATTERNS = {
	{ id = "plain" },
	{ id = "halves" },
	{ id = "band", requires = { division = "D5" } },
	{ id = "pinstripes", cost = 15000 },
	{ id = "chevron", cost = 40000, requires = { division = "D4" } },
	{ id = "stripes", kit = "kit_stripes" },
	{ id = "hoops", kit = "kit_hoops" },
	{ id = "sash", kit = "kit_sash" },
}

ClubIdentity.CREST_COUNT = 6
ClubIdentity.DEFAULT_PATTERN = "plain"

local colorById = {}
for _, entry in ClubIdentity.COLORS do
	colorById[entry.id] = entry.color
end
local patternById = {}
for _, entry in ClubIdentity.PATTERNS do
	patternById[entry.id] = entry
end

function ClubIdentity.Color(id: any): Color3?
	if type(id) ~= "string" then
		return nil
	end
	return colorById[id]
end

function ClubIdentity.Pattern(id: any)
	if type(id) ~= "string" then
		return nil
	end
	return patternById[id]
end

function ClubIdentity.ValidCrest(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= ClubIdentity.CREST_COUNT
end

-- Le motif est-il utilisable par ce profil ? Renvoie (ok, raison) avec
-- raison = "division", "coins" (à acheter) ou "kit" (tenue Prestige à acheter).
function ClubIdentity.PatternUnlocked(pattern, division: string?, owned, bought): (boolean, string?)
	if not pattern then
		return false, nil
	end
	if pattern.kit then
		if owned and owned[pattern.kit] then
			return true, nil
		end
		return false, "kit"
	end
	local req = pattern.requires
	if req and req.division then
		local current = Divisions.Get(division)
		local needed = Divisions.Get(req.division)
		if needed and (not current or current.index < needed.index) then
			return false, "division"
		end
	end
	if pattern.cost and not (bought and bought[pattern.id]) then
		return false, "coins"
	end
	return true, nil
end

-- Choix d'identité « propres » (couleurs et motif seulement si valides),
-- passés à WorldBuilder dans le style du terrain.
function ClubIdentity.Choices(data)
	local identity = data and data.identity
	if type(identity) ~= "table" then
		return {}
	end
	local pattern = ClubIdentity.Pattern(identity.pattern)
	local ok = pattern ~= nil
		and ClubIdentity.PatternUnlocked(pattern, data.club and data.club.division, data.cosmetics and data.cosmetics.owned, identity.patterns)
	return {
		primary = ClubIdentity.Color(identity.primary),
		secondary = ClubIdentity.Color(identity.secondary),
		pattern = if ok then pattern.id else nil,
		crest = if ClubIdentity.ValidCrest(identity.crest) then identity.crest else nil,
	}
end

-- Couleurs principale / secondaire : objet Prestige porté, sinon identité,
-- sinon couleurs de l'emplacement. Les deux couleurs restent différentes.
function ClubIdentity.ResolveColors(slotIndex: number?, colorsItem, choices): (Color3, Color3)
	local base = WorldConfig.CLUB_COLORS[slotIndex or 1] or WorldConfig.CLUB_COLORS[1]
	if colorsItem and colorsItem.category == "colors" and colorsItem.primary then
		return colorsItem.primary, colorsItem.secondary
	end
	choices = choices or {}
	local primary = choices.primary or base.primary
	local secondary = choices.secondary or base.secondary
	if primary == secondary then
		secondary = if base.secondary ~= primary then base.secondary else base.primary
	end
	return primary, secondary
end

-- Tenue complète { pattern, shirt, detail } : tenue Prestige portée, sinon
-- motif de l'identité aux couleurs du club.
function ClubIdentity.ResolveKit(kitItem, primary: Color3, secondary: Color3, pattern: string?)
	if kitItem and kitItem.category == "kit" then
		return {
			pattern = kitItem.pattern or ClubIdentity.DEFAULT_PATTERN,
			shirt = kitItem.shirt or primary,
			detail = kitItem.detail or secondary,
		}
	end
	return { pattern = pattern or ClubIdentity.DEFAULT_PATTERN, shirt = primary, detail = secondary }
end

-- Tout ce qu'il faut pour dessiner le club à partir d'un profil (serveur).
function ClubIdentity.Resolve(data, slotIndex: number?)
	local equipped = data and data.cosmetics and data.cosmetics.equipped or {}
	local choices = ClubIdentity.Choices(data)
	local colorsItem = Cosmetics.Get(equipped.colors)
	if colorsItem and colorsItem.category ~= "colors" then
		colorsItem = nil
	end
	local kitItem = Cosmetics.Get(equipped.kit)
	if kitItem and kitItem.category ~= "kit" then
		kitItem = nil
	end
	local primary, secondary = ClubIdentity.ResolveColors(slotIndex, colorsItem, choices)
	local kit = ClubIdentity.ResolveKit(kitItem, primary, secondary, choices.pattern)
	return {
		primary = primary,
		secondary = secondary,
		kit = kit,
		crest = choices.crest or slotIndex or 1,
	}
end

-- Couleur en { r, g, b } (0-255) pour le réseau, et retour.
function ClubIdentity.ToArray(color: Color3)
	return {
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
	}
end

function ClubIdentity.FromArray(array: any, fallback: Color3): Color3
	if type(array) == "table" and type(array[1]) == "number" and type(array[2]) == "number" and type(array[3]) == "number" then
		return Color3.fromRGB(math.clamp(array[1], 0, 255), math.clamp(array[2], 0, 255), math.clamp(array[3], 0, 255))
	end
	return fallback
end

-- Tenue pour le réseau (replay) : { pattern, shirt = {r,g,b}, detail = {r,g,b} }.
function ClubIdentity.KitToNet(kit)
	return { pattern = kit.pattern, shirt = ClubIdentity.ToArray(kit.shirt), detail = ClubIdentity.ToArray(kit.detail) }
end

-- Motifs que le replay et les mannequins savent dessiner (les autres = uni).
ClubIdentity.DRAWN = { plain = true, halves = true, band = true, pinstripes = true, chevron = true, stripes = true, hoops = true, sash = true }

return ClubIdentity
