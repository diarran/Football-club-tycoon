--[[
	Sponsors
	Contrats de sponsoring : le club choisit 1 contrat (2 à partir de la D4)
	parmi 3 offres fictives. Chaque contrat verse une prime fixe à chaque match
	et un bonus unique si l'objectif est atteint avant la fin du contrat
	(par exemple « gagner 5 matchs »). Les offres se renouvellent toutes les
	REFRESH_SECONDS (même hors ligne).

	Montants selon la division ; le prestige (titres de champion de D1) les
	augmente un peu. Les offres sont tirées par le serveur (StaffService) :
	le client ne fait que demander « signer l'offre n° X ».
	Équilibré avec tools/economy-sim.js (docs/economy/README.md).
]]

local Sponsors = {}

Sponsors.OFFER_COUNT = 3
Sponsors.REFRESH_SECONDS = 4 * 3600 -- nouvelles offres toutes les 4 heures
Sponsors.SECOND_SLOT_TIER = 4 -- 2ᵉ contrat à partir de la D4
Sponsors.PRESTIGE_BONUS_PER_TITLE = 0.05 -- +5 % par titre de champion de D1…
Sponsors.PRESTIGE_BONUS_MAX = 0.25 -- … au plus +25 %

-- Prime fixe de base par match, selon la division.
Sponsors.BASE_PER_MATCH = {
	D7 = 25,
	D6 = 40,
	D5 = 60,
	D4 = 90,
	D3 = 120,
	D2 = 160,
	D1 = 200,
}

-- Objectifs possibles. stat : compteur suivi pendant le contrat.
-- target : objectif tiré entre min et max ; matches : durée du contrat ;
-- bonusMatches : le bonus vaut « prime par match × bonusMatches ».
-- Texte affiché : clé « sponsor.goal.<id> » de Locale.
Sponsors.Goals = {
	{ id = "wins", min = 4, max = 8, matchesPerTarget = 2.5, bonusMatches = 5 },
	{ id = "goals", min = 10, max = 20, matchesPerTarget = 1, bonusMatches = 4 },
	{ id = "unbeaten", min = 5, max = 10, matchesPerTarget = 1.8, bonusMatches = 5 },
}

-- Noms de marques inventés (jamais traduits).
Sponsors.Brands = {
	"Brixo",
	"Zentra",
	"Solano",
	"Orbis",
	"Kalmo",
	"Vireo",
	"Ferrox",
	"Lumo",
	"Pixforge",
	"Atlavo",
	"Nebulix",
	"Cobaltis",
	"Quarzo",
	"Tundrak",
	"Helixa",
	"Marvo",
}

function Sponsors.MaxActive(divisionTier: number): number
	return if divisionTier <= Sponsors.SECOND_SLOT_TIER then 2 else 1
end

function Sponsors.PrestigeMultiplier(titles: number?): number
	local bonus = math.min(Sponsors.PRESTIGE_BONUS_MAX, (titles or 0) * Sponsors.PRESTIGE_BONUS_PER_TITLE)
	return 1 + math.max(0, bonus)
end

function Sponsors.GetGoal(id: string)
	for _, goal in Sponsors.Goals do
		if goal.id == id then
			return goal
		end
	end
	return nil
end

-- Tire une offre. rng : Random du serveur ; id : numéro unique dans le profil.
function Sponsors.GenerateOffer(rng, id: number, divisionId: string, titles: number?)
	local base = Sponsors.BASE_PER_MATCH[divisionId] or Sponsors.BASE_PER_MATCH.D7
	-- Chaque offre a son style : prime fixe plus haute OU objectif plus payant.
	local fixedShare = rng:NextNumber(0.8, 1.2)
	local perMatch = math.floor(base * fixedShare * Sponsors.PrestigeMultiplier(titles) / 5 + 0.5) * 5
	local goal = Sponsors.Goals[rng:NextInteger(1, #Sponsors.Goals)]
	local target = rng:NextInteger(goal.min, goal.max)
	local bonus = math.floor(perMatch * goal.bonusMatches * (2.2 - fixedShare) * target / goal.max / 50 + 0.5) * 50
	return {
		id = id,
		brand = Sponsors.Brands[rng:NextInteger(1, #Sponsors.Brands)],
		perMatch = perMatch,
		goal = goal.id,
		target = target,
		bonus = math.max(50, bonus),
		matches = math.max(target, math.ceil(target * goal.matchesPerTarget) + 4),
	}
end

return Sponsors
