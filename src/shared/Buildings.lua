--[[
	Buildings
	Définition des installations du club (document de conception, section 4).

	Nom et description affichés : clés « building.<id>.label » et
	« building.<id>.description » de Lang/fr.lua et Lang/en.lua (module Locale).

	Chaque installation a des niveaux. Le niveau 1 est possédé au départ.
	levels[n].cost = prix pour PASSER au niveau n (le niveau 1 est gratuit).
	Les effets sont lus par le serveur (billetterie, entraînement, etc.).

	Ajouter un niveau = ajouter une ligne dans levels : le serveur, l'interface
	et le simulateur d'économie (tools/economy-sim.js) le prennent en compte
	sans autre changement. Relancer le simulateur pour vérifier le rythme.
]]

local Buildings = {}

Buildings.Definitions = {
	Pitch = {
		id = "Pitch",
		order = 1,
		levels = {
			{ cost = 0, effects = { homeBonus = 0 } },
			{ cost = 2500, effects = { homeBonus = 1 } },
			{ cost = 7500, effects = { homeBonus = 2 } },
			{ cost = 16000, effects = { homeBonus = 3 } }, -- écrans géants
			{ cost = 32000, effects = { homeBonus = 4 } }, -- 4 écrans, panneaux LED
		},
	},
	Stands = {
		id = "Stands",
		order = 2,
		levels = {
			{ cost = 0, effects = { capacity = 200, ticketPrice = 1 } },
			{ cost = 3000, effects = { capacity = 500, ticketPrice = 1 } },
			{ cost = 8000, effects = { capacity = 1000, ticketPrice = 1 } },
			{ cost = 18000, effects = { capacity = 1600, ticketPrice = 1 } }, -- 4 tribunes couvertes
			{ cost = 36000, effects = { capacity = 2500, ticketPrice = 1 } }, -- grand stade, loges VIP
		},
	},
	Training = {
		id = "Training",
		order = 3,
		levels = {
			{ cost = 0, effects = { teamBonus = 0, energyRecovery = 1.0 } },
			{ cost = 2000, effects = { teamBonus = 1, energyRecovery = 1.25 } },
			{ cost = 6000, effects = { teamBonus = 2, energyRecovery = 1.5 } },
			{ cost = 14000, effects = { teamBonus = 3, energyRecovery = 1.75 } }, -- éclairage, mur de frappe
			{ cost = 28000, effects = { teamBonus = 4, energyRecovery = 2.0 } }, -- centre de performance
		},
	},
	Offices = {
		id = "Offices",
		order = 4,
		levels = {
			{ cost = 0, effects = { sponsorIncome = 50 } },
			{ cost = 2500, effects = { sponsorIncome = 150 } },
			{ cost = 7000, effects = { sponsorIncome = 250 } },
			{ cost = 15000, effects = { sponsorIncome = 400 } }, -- immeuble de 3 étages
			{ cost = 30000, effects = { sponsorIncome = 600 } }, -- siège du club, 4 étages
		},
	},
	LockerRoom = {
		id = "LockerRoom",
		order = 5,
		levels = {
			{ cost = 0, effects = {} },
			{ cost = 1500, effects = {} },
			{ cost = 4000, effects = {} },
			{ cost = 9000, effects = {} }, -- bain froid, tables de soin
			{ cost = 18000, effects = {} }, -- 2 étages, salle de récupération
		},
	},
	-- Boutique (document de conception, section 4 « Après MVP ») : ventes de
	-- maillots et d'écharpes, versées à chaque match joué.
	Shop = {
		id = "Shop",
		order = 6,
		levels = {
			{ cost = 0, effects = { shopIncome = 25 } }, -- kiosque
			{ cost = 4000, effects = { shopIncome = 100 } }, -- petite boutique
			{ cost = 10000, effects = { shopIncome = 200 } }, -- magasin vitré
			{ cost = 20000, effects = { shopIncome = 350 } }, -- grand magasin
			{ cost = 38000, effects = { shopIncome = 550 } }, -- boutique officielle
		},
	},
}

function Buildings.Get(id: string)
	return Buildings.Definitions[id]
end

function Buildings.MaxLevel(id: string): number
	local def = Buildings.Definitions[id]
	return def and #def.levels or 0
end

-- Renvoie les effets d'une installation à un niveau donné (table vide si inconnu).
function Buildings.GetEffects(id: string, level: number)
	local def = Buildings.Definitions[id]
	local data = def and def.levels[level]
	return data and data.effects or {}
end

-- Prix pour passer au niveau suivant, ou nil si le niveau max est atteint.
function Buildings.GetUpgradeCost(id: string, currentLevel: number): number?
	local def = Buildings.Definitions[id]
	if not def then
		return nil
	end
	local nextLevel = def.levels[currentLevel + 1]
	return nextLevel and nextLevel.cost or nil
end

-- Liste des installations triée pour l'affichage.
function Buildings.List()
	local list = {}
	for _, def in Buildings.Definitions do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- Niveaux de départ d'un nouveau club.
function Buildings.DefaultLevels()
	local levels = {}
	for id in Buildings.Definitions do
		levels[id] = 1
	end
	return levels
end

return Buildings
