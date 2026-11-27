--[[
	NationalCup
	Coupe nationale : une coupe à élimination directe par saison (7 jours,
	du lundi 00:00 UTC au lundi suivant, comme les saisons de Daily.lua).

	- 5 tours : 16es de finale, 8es, quarts, demies, finale.
	- Adversaires : clubs fictifs de TOUTES les divisions. Le 1er tour se joue
	  contre un club de la division du dessous, puis chaque tour monte d'une
	  division (OPPONENT_OFFSET). Un club de D7 peut donc finir contre un club
	  de D4 : battre un club d'une division plus haute est un « exploit »
	  (prime majorée, compteur pour la salle des trophées).
	- Un tour se joue quand le joueur le décide, au plus un tour toutes les
	  ROUND_SECONDS (temps réel). Tactique choisie dans l'onglet Matchs.
	- Match neutre : pas d'énergie dépensée, pas de points de division, pas
	  d'avantage du terrain. Un nul se règle aux tirs au but (50/50 serveur).
	- Primes par tour gagné : REWARDS[tour] × multiplicateur de la division du
	  club (+ GIANT_KILL_BONUS en cas d'exploit). Au plus 5 primes par semaine :
	  maximum 3 400 FC × multiplicateur (D1 : 10 200 FC, plus les exploits), soit peu face aux
	  matchs de la semaine (voir docs/economy/README.md).
	- Vainqueur : trophée « Coupe nationale » (stat cupsWon) dans la vitrine.

	Lu par le serveur (CupService) et par le client (affichage seulement).
	Textes : clés « cup.* » de Locale.
]]

local Daily = require(script.Parent.Daily)
local Divisions = require(script.Parent.Divisions)

local NationalCup = {}

-- Temps réel minimum entre deux tours joués par un même club.
NationalCup.ROUND_SECONDS = 20 * 60

-- Nom affiché : « cup.stage.<id> ».
NationalCup.STAGES = { "Round32", "Round16", "Quarter", "Semi", "Final" }

-- Écart de division de l'adversaire à chaque tour (en index de Divisions.List :
-- -1 = une division plus bas, +1 = une division plus haut).
NationalCup.OPPONENT_OFFSET = { -1, 0, 1, 2, 3 }

-- Prime de base par tour GAGNÉ (le dernier = coupe remportée).
NationalCup.REWARDS = { 200, 300, 500, 800, 1600 }

-- Exploit (victoire contre un club d'une division plus haute) : prime +50 %.
NationalCup.GIANT_KILL_BONUS = 0.5

function NationalCup.RoundCount(): number
	return #NationalCup.STAGES
end

-- Une édition par saison de 7 jours.
function NationalCup.Edition(t: number): number
	return Daily.SeasonId(t)
end

function NationalCup.EditionEndsAt(edition: number): number
	return Daily.SeasonEndsAt(edition)
end

-- Division de l'adversaire au tour `round` pour un club de `divisionId`.
function NationalCup.OpponentDivision(divisionId: string, round: number)
	local division = Divisions.Get(divisionId) or Divisions.List[1]
	local offset = NationalCup.OPPONENT_OFFSET[round] or 0
	local index = math.clamp(division.index + offset, 1, #Divisions.List)
	return Divisions.List[index]
end

-- Exploit : l'adversaire joue dans une division plus haute que le club.
function NationalCup.IsGiantKill(myDivisionId: string, opponentDivisionId: string): boolean
	local mine, theirs = Divisions.Get(myDivisionId), Divisions.Get(opponentDivisionId)
	return mine ~= nil and theirs ~= nil and theirs.index > mine.index
end

-- Prime d'un tour gagné (FC Coins entiers).
function NationalCup.Reward(round: number, divisionId: string, giantKill: boolean?): number
	local base = NationalCup.REWARDS[round]
	if not base then
		return 0
	end
	local division = Divisions.Get(divisionId)
	local multiplier = (division and division.rewardMultiplier or 1) * (if giantKill then 1 + NationalCup.GIANT_KILL_BONUS else 1)
	return math.floor(base * multiplier + 0.5)
end

-- Total maximum d'une édition (sans exploit), pour l'affichage.
function NationalCup.MaxReward(divisionId: string): number
	local total = 0
	for round in NationalCup.REWARDS do
		total += NationalCup.Reward(round, divisionId, false)
	end
	return total
end

return NationalCup
