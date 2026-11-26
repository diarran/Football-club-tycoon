--[[
	Buildings
	Définition des installations du club (document de conception, section 4).

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
		label = "Terrain principal",
		description = "Lieu des matchs et identité du club.",
		order = 1,
		levels = {
			{ cost = 0, effects = { homeBonus = 0 } },
			{ cost = 2500, effects = { homeBonus = 1 } },
			{ cost = 7500, effects = { homeBonus = 2 } },
		},
	},
	Stands = {
		id = "Stands",
		label = "Tribunes",
		description = "Capacité d'accueil et revenus de billetterie.",
		order = 2,
		levels = {
			{ cost = 0, effects = { capacity = 200, ticketPrice = 1 } },
			{ cost = 3000, effects = { capacity = 500, ticketPrice = 1 } },
			{ cost = 8000, effects = { capacity = 1000, ticketPrice = 1 } },
		},
	},
	Training = {
		id = "Training",
		label = "Zone d'entraînement",
		description = "Améliore la progression et l'énergie des joueurs.",
		order = 3,
		levels = {
			{ cost = 0, effects = { teamBonus = 0, energyRecovery = 1.0 } },
			{ cost = 2000, effects = { teamBonus = 1, energyRecovery = 1.25 } },
			{ cost = 6000, effects = { teamBonus = 2, energyRecovery = 1.5 } },
		},
	},
	Offices = {
		id = "Offices",
		label = "Bureaux",
		description = "Accès aux menus de gestion et aux sponsors.",
		order = 4,
		levels = {
			{ cost = 0, effects = { sponsorIncome = 50 } },
			{ cost = 2500, effects = { sponsorIncome = 150 } },
		},
	},
	LockerRoom = {
		id = "LockerRoom",
		label = "Vestiaires",
		description = "Amélioration visuelle du club (progression future).",
		order = 5,
		levels = {
			{ cost = 0, effects = {} },
			{ cost = 1500, effects = {} },
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
