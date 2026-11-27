--[[
	Staff
	Staff du club (gestion simple) : quatre postes, chacun avec 4 niveaux.
	Le niveau 0 = poste vacant. Chaque niveau s'achète une fois en FC Coins
	(pas de salaire) et donne un petit effet clair et modéré.

	Tout est lu par le serveur (StaffService, MatchService, SquadService) ;
	le client ne s'en sert que pour l'affichage.
	Équilibré avec tools/economy-sim.js (docs/economy/README.md).

	Nom affiché : clés « staff.<id>.label » et « staff.<id>.effect » de Locale.
]]

local Staff = {}

-- Effets possibles :
--   teamBonus : points de note ajoutés à l'équipe en match (entraîneur)
--   growthBonus : chance de progression en plus après chaque match (entraîneur)
--   scoutSpeed : multiplie le rythme de repérage du centre de formation (recruteur)
--   prospectBonus : points de note et de potentiel en plus pour les jeunes repérés
--   energyRecovery : multiplie la récupération d'énergie (médecin)
--   injuryReduction : part de la durée des blessures en moins (médecin, Injuries.lua)
--   sponsorBonus : part en plus sur l'argent des sponsors (directeur commercial)
Staff.Definitions = {
	Coach = {
		id = "Coach",
		order = 1,
		levels = {
			{ cost = 4000, effects = { teamBonus = 0.25, growthBonus = 0.02 } },
			{ cost = 12000, effects = { teamBonus = 0.5, growthBonus = 0.04 } },
			{ cost = 30000, effects = { teamBonus = 0.75, growthBonus = 0.06 } },
			{ cost = 60000, effects = { teamBonus = 1, growthBonus = 0.08 } },
		},
	},
	Scout = {
		id = "Scout",
		order = 2,
		levels = {
			{ cost = 3000, effects = { scoutSpeed = 1.15, prospectBonus = 1 } },
			{ cost = 9000, effects = { scoutSpeed = 1.3, prospectBonus = 2 } },
			{ cost = 22000, effects = { scoutSpeed = 1.45, prospectBonus = 3 } },
			{ cost = 45000, effects = { scoutSpeed = 1.6, prospectBonus = 4 } },
		},
	},
	Doctor = {
		id = "Doctor",
		order = 3,
		levels = {
			{ cost = 2500, effects = { energyRecovery = 1.1, injuryReduction = 0.15 } },
			{ cost = 8000, effects = { energyRecovery = 1.2, injuryReduction = 0.3 } },
			{ cost = 20000, effects = { energyRecovery = 1.35, injuryReduction = 0.45 } },
			{ cost = 40000, effects = { energyRecovery = 1.5, injuryReduction = 0.6 } },
		},
	},
	Commercial = {
		id = "Commercial",
		order = 4,
		levels = {
			{ cost = 5000, effects = { sponsorBonus = 0.05 } },
			{ cost = 14000, effects = { sponsorBonus = 0.1 } },
			{ cost = 32000, effects = { sponsorBonus = 0.15 } },
			{ cost = 65000, effects = { sponsorBonus = 0.2 } },
		},
	},
}

-- Valeur d'un effet quand le poste est vacant.
local NEUTRAL = {
	teamBonus = 0,
	growthBonus = 0,
	scoutSpeed = 1,
	prospectBonus = 0,
	energyRecovery = 1,
	injuryReduction = 0,
	sponsorBonus = 0,
}

function Staff.Get(id: string)
	return Staff.Definitions[id]
end

-- Liste triée (ordre d'affichage).
function Staff.List()
	local list = {}
	for _, def in Staff.Definitions do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

function Staff.MaxLevel(id: string): number
	local def = Staff.Definitions[id]
	return def and #def.levels or 0
end

-- Prix du niveau suivant, ou nil si le poste est au maximum (ou inconnu).
function Staff.GetHireCost(id: string, currentLevel: number): number?
	local def = Staff.Definitions[id]
	local nextLevel = def and def.levels[currentLevel + 1]
	return nextLevel and nextLevel.cost or nil
end

-- Profil par défaut : tous les postes vacants.
function Staff.DefaultLevels()
	local levels = {}
	for id in Staff.Definitions do
		levels[id] = 0
	end
	return levels
end

-- Valeur d'un effet pour un niveau de staff ({ [id] = niveau }).
function Staff.Effect(levels, effect: string): number
	for id, def in Staff.Definitions do
		local level = type(levels) == "table" and levels[id] or 0
		local entry = type(level) == "number" and def.levels[level]
		if entry and entry.effects[effect] ~= nil then
			return entry.effects[effect]
		end
	end
	return NEUTRAL[effect] or 0
end

return Staff
