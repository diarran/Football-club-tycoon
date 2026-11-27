--[[
	Tactics
	Styles de jeu choisis avant un match, façon pierre-feuille-ciseaux.

	Chaque style a un petit effet fixe (Config.Tactics : attaque / défense) et
	un cycle d'avantages :
	  Contre-attaque  bat  Offensif   (leur défense est montée, on file dans le dos)
	  Offensif        bat  Défensif   (on fait le siège de leur but)
	  Défensif        bat  Pressing   (leur pressing s'épuise contre notre bloc)
	  Pressing        bat  Contre-attaque (on récupère le ballon avant qu'ils partent)
	Équilibré ne bat personne et n'est battu par personne (choix sans risque).
	Les autres paires (Contre-attaque / Défensif, Offensif / Pressing) sont neutres.

	Le style qui a l'avantage gagne EDGE points d'attaque et de défense
	(MatchService.Simulate). Les clubs fictifs ont un style fixe, visible dans
	l'onglet Matchs, pour que le joueur puisse le contrer.

	Lu par le serveur (simulation) et par le client (affichage seulement).
]]

local Config = require(script.Parent.Config)

local Tactics = {}

-- Ordre d'affichage des boutons dans l'onglet Matchs.
Tactics.ORDER = { "Balanced", "Offensive", "Defensive", "Counter", "Pressing" }

-- style -> style qu'il bat
Tactics.BEATS = {
	Counter = "Offensive",
	Offensive = "Defensive",
	Defensive = "Pressing",
	Pressing = "Counter",
}

-- Bonus d'attaque ET de défense du style qui a l'avantage (points de note).
Tactics.EDGE = 2

-- Styles des clubs fictifs (Équilibré compris : pas toujours un avantage à prendre).
Tactics.RIVAL_STYLES = { "Offensive", "Defensive", "Counter", "Pressing", "Balanced" }

function Tactics.IsValid(id: any): boolean
	return type(id) == "string" and Config.Tactics[id] ~= nil
end

-- Style valide (ou le style par défaut).
function Tactics.Sanitize(id: any): string
	if Tactics.IsValid(id) then
		return id
	end
	return Config.DEFAULT_TACTIC
end

-- 1 si `mine` bat `theirs`, -1 si `theirs` bat `mine`, 0 sinon.
function Tactics.Matchup(mine: any, theirs: any): number
	mine, theirs = Tactics.Sanitize(mine), Tactics.Sanitize(theirs)
	if Tactics.BEATS[mine] == theirs then
		return 1
	elseif Tactics.BEATS[theirs] == mine then
		return -1
	end
	return 0
end

-- Style qui bat `theirs` (nil contre Équilibré : rien ne le bat).
function Tactics.CounterOf(theirs: any): string?
	theirs = Tactics.Sanitize(theirs)
	for style, beaten in Tactics.BEATS do
		if beaten == theirs then
			return style
		end
	end
	return nil
end

-- Style qui bat `mine` (nil pour Équilibré).
function Tactics.BeatenBy(mine: any): string?
	return Tactics.CounterOf(mine)
end

-- Modificateurs d'attaque et de défense d'une équipe qui joue `mine` contre `theirs`.
function Tactics.Modifiers(mine: any, theirs: any): (number, number)
	mine = Tactics.Sanitize(mine)
	local base = Config.Tactics[mine]
	local edge = Tactics.Matchup(mine, theirs) * Tactics.EDGE
	if edge < 0 then
		edge = 0 -- seul le gagnant du duel tactique reçoit un bonus
	end
	return base.attack + edge, base.defense + edge
end

-- Style fixe d'un club fictif, sans tirage : les 5 clubs d'une division ont
-- 5 styles différents, et le même club change de style d'une division à l'autre.
function Tactics.RivalStyle(divisionIndex: number, rivalIndex: number): string
	local count = #Tactics.RIVAL_STYLES
	local seed = math.floor(divisionIndex or 0) * 2 + math.floor(rivalIndex or 0)
	return Tactics.RIVAL_STYLES[(seed * 3) % count + 1]
end

return Tactics
