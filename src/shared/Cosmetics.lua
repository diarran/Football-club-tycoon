--[[
	Cosmetics
	Personnalisation visuelle du club, achetée en FC Coins (document de
	conception, section 9 : dépenses de fin de partie SANS avantage sportif).

	Rien ici ne change un match : seules l'apparence du terrain de club et la
	vitrine des visiteurs changent. Les prix sont élevés pour garder des
	objectifs longtemps après la Division 1 (voir tools/economy-sim.js).

	Catégories :
	- colors   : couleurs du club (sièges, portique, bancs, écrans…), une à la fois ;
	- lighting : couleur des projecteurs du stade et de l'entraînement, une à la fois ;
	- statue   : statue devant l'entrée du stade, une à la fois ;
	- kit      : tenue fictive des mannequins (salle des trophées, entraînement), une à la fois ;
	- decor    : décorations du stade, toutes affichées une fois achetées.

	Condition d'achat (requires) : division atteinte et/ou nombre de titres de
	champion de Division 1 (voir Trophies.lua).
	Nom affiché : clés « cosmetic.<id> » et « cosmeticCategory.<catégorie> » de Locale.
	Tout est vérifié par le serveur (CosmeticService) : le client ne fait qu'afficher.
]]

local Divisions = require(script.Parent.Divisions)

local Cosmetics = {}

Cosmetics.CATEGORIES = { "colors", "lighting", "statue", "kit", "decor" }
-- Catégories où un seul objet est porté à la fois (les autres s'additionnent).
Cosmetics.SINGLE = { colors = true, lighting = true, statue = true, kit = true }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- cost : prix en FC Coins ; requires = { division = "D4", titles = 3 }.
Cosmetics.List = {
	-- Couleurs du club : primary / secondary remplacent celles de l'emplacement.
	{ id = "colors_royal", category = "colors", cost = 25000, requires = { division = "D5" }, primary = rgb(30, 60, 170), secondary = rgb(245, 245, 245) },
	{ id = "colors_emerald", category = "colors", cost = 60000, requires = { division = "D4" }, primary = rgb(20, 130, 80), secondary = rgb(225, 185, 60) },
	{ id = "colors_sunset", category = "colors", cost = 120000, requires = { division = "D3" }, primary = rgb(235, 120, 30), secondary = rgb(110, 20, 40) },
	{ id = "colors_ocean", category = "colors", cost = 250000, requires = { division = "D2" }, primary = rgb(30, 170, 170), secondary = rgb(15, 35, 80) },
	{ id = "colors_midnight", category = "colors", cost = 500000, requires = { division = "D1" }, primary = rgb(25, 25, 35), secondary = rgb(190, 195, 205) },
	{ id = "colors_prestige", category = "colors", cost = 900000, requires = { division = "D1", titles = 2 }, primary = rgb(212, 175, 55), secondary = rgb(20, 20, 24) },

	-- Éclairage : couleur des projecteurs (visible dès que le stade en a, niveau 3).
	-- club = true : couleur principale du club.
	{ id = "lighting_warm", category = "lighting", cost = 40000, requires = { division = "D4" }, color = rgb(255, 205, 140) },
	{ id = "lighting_cool", category = "lighting", cost = 100000, requires = { division = "D3" }, color = rgb(190, 220, 255) },
	{ id = "lighting_club", category = "lighting", cost = 350000, requires = { division = "D1" }, club = true },
	{ id = "lighting_gold", category = "lighting", cost = 900000, requires = { division = "D1", titles = 3 }, color = rgb(255, 200, 70) },
	{ id = "lighting_aurora", category = "lighting", cost = 1600000, requires = { division = "D1", titles = 6 }, color = rgb(150, 110, 255) },

	-- Statues (devant l'entrée du stade). material/color : rendu de la statue.
	{ id = "statue_ball", category = "statue", cost = 60000, requires = { division = "D4" }, color = rgb(235, 235, 235), material = "SmoothPlastic" },
	{ id = "statue_boot", category = "statue", cost = 200000, requires = { division = "D3" }, color = rgb(205, 127, 50), material = "Metal" },
	{ id = "statue_striker", category = "statue", cost = 500000, requires = { division = "D2" }, color = rgb(150, 155, 160), material = "Marble" },
	{ id = "statue_coach", category = "statue", cost = 900000, requires = { division = "D1" }, color = rgb(120, 90, 60), material = "Metal" },
	{ id = "statue_legend", category = "statue", cost = 1500000, requires = { division = "D1", titles = 4 }, color = rgb(212, 175, 55), material = "Metal" },
	{ id = "statue_cup", category = "statue", cost = 2500000, requires = { division = "D1", titles = 10 }, color = rgb(230, 190, 60), material = "Neon" },

	-- Tenues fictives : maillot, short et motif (aucune marque réelle).
	-- pattern : "plain", "stripes", "hoops", "sash" ou "halves".
	{ id = "kit_stripes", category = "kit", cost = 30000, requires = { division = "D5" }, pattern = "stripes" },
	{ id = "kit_hoops", category = "kit", cost = 80000, requires = { division = "D4" }, pattern = "hoops" },
	{ id = "kit_sash", category = "kit", cost = 250000, requires = { division = "D2" }, pattern = "sash" },
	{ id = "kit_retro", category = "kit", cost = 600000, requires = { division = "D1" }, pattern = "halves", shirt = rgb(240, 230, 200), detail = rgb(120, 30, 40) },
	{ id = "kit_gold", category = "kit", cost = 1200000, requires = { division = "D1", titles = 3 }, pattern = "plain", shirt = rgb(212, 175, 55), detail = rgb(20, 20, 24) },
	{ id = "kit_galaxy", category = "kit", cost = 2000000, requires = { division = "D1", titles = 8 }, pattern = "hoops", shirt = rgb(40, 20, 90), detail = rgb(160, 120, 255) },

	-- Décorations du stade (toutes affichées une fois achetées).
	{ id = "decor_flags", category = "decor", cost = 20000, requires = { division = "D6" } },
	{ id = "decor_flowers", category = "decor", cost = 35000, requires = { division = "D5" } },
	{ id = "decor_palms", category = "decor", cost = 150000, requires = { division = "D4" } },
	{ id = "decor_fountain", category = "decor", cost = 400000, requires = { division = "D2" } },
	{ id = "decor_arch", category = "decor", cost = 800000, requires = { division = "D1", titles = 1 } },
	{ id = "decor_walk", category = "decor", cost = 1500000, requires = { division = "D1", titles = 5 } },
}

-- Objets exclusifs, achetés en Robux (voir Monetization.lua et MonetizationService).
-- Ils ne sont PAS dans Cosmetics.List : jamais vendus en FC Coins, hors du
-- catalogue Prestige et du simulateur d'économie. Purement visuels eux aussi.
Cosmetics.EXCLUSIVE = {
	{ id = "colors_vip_neon", category = "colors", robux = true, requires = {}, primary = rgb(255, 40, 150), secondary = rgb(20, 230, 230) },
	{ id = "lighting_vip_ruby", category = "lighting", robux = true, requires = {}, color = rgb(255, 60, 80) },
	{ id = "statue_vip_crystal", category = "statue", robux = true, requires = {}, color = rgb(170, 220, 255), material = "Glass" },
	{ id = "kit_vip_carbon", category = "kit", robux = true, requires = {}, pattern = "stripes", shirt = rgb(30, 30, 34), detail = rgb(0, 200, 255) },
}

local byId = {}
for index, item in Cosmetics.List do
	item.order = index
	byId[item.id] = item
end
for index, item in Cosmetics.EXCLUSIVE do
	item.order = #Cosmetics.List + index
	byId[item.id] = item
end

function Cosmetics.Get(id: any)
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function Cosmetics.IsCategory(category: any): boolean
	return type(category) == "string" and table.find(Cosmetics.CATEGORIES, category) ~= nil
end

function Cosmetics.ByCategory(category: string)
	local list = {}
	for _, item in Cosmetics.List do
		if item.category == category then
			table.insert(list, item)
		end
	end
	return list
end

function Cosmetics.TotalCost(): number
	local total = 0
	for _, item in Cosmetics.List do
		total += item.cost
	end
	return total
end

-- L'objet peut-il être acheté par un club de cette division avec `titles`
-- titres de champion ? Renvoie (ok, raison) ; raison = "division" ou "titles".
function Cosmetics.IsUnlocked(item, divisionId: string, titles: number): (boolean, string?)
	local req = item.requires or {}
	local current = Divisions.Get(divisionId)
	local needed = req.division and Divisions.Get(req.division)
	if needed and (not current or current.index < needed.index) then
		return false, "division"
	end
	if req.titles and (titles or 0) < req.titles then
		return false, "titles"
	end
	return true, nil
end

return Cosmetics
