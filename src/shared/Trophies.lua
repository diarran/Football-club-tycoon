--[[
	Trophies
	Salle des trophées : la vitrine du club se remplit avec les montées, les
	titres de champion de Division 1 et quelques records. Pur prestige : aucun
	trophée ne rapporte de FC Coins ni n'aide en match.

	Les trophées sont calculés à partir du profil (division, bilan, titres) :
	un ancien profil reçoit donc tout de suite ceux qu'il mérite.

	Titre de champion de D1 : la D1 n'a pas de montée. Chaque fois que le club
	y cumule TITLE_POINTS points (une « saison »), il gagne un titre et ses
	points repartent de zéro (TrophyService). TITLE_POINTS dépasse les points
	du meilleur club fictif de D1 (Divisions.TOP_REFERENCE_POINTS × 0,85).

	Nom affiché : clé « trophy.<id> » de Locale.
]]

local Divisions = require(script.Parent.Divisions)

local Trophies = {}

Trophies.TITLE_POINTS = 300

-- Nombre de titres de D1 affichés un par un dans la vitrine (au-delà : compteur).
Trophies.MAX_DISPLAYED_TITLES = 10

-- Records du bilan (club.stats). tier : "bronze", "silver" ou "gold".
Trophies.MILESTONES = {
	{ id = "wins_50", stat = "wins", value = 50, tier = "bronze" },
	{ id = "wins_250", stat = "wins", value = 250, tier = "silver" },
	{ id = "wins_1000", stat = "wins", value = 1000, tier = "gold" },
	{ id = "played_500", stat = "played", value = 500, tier = "bronze" },
	{ id = "played_2000", stat = "played", value = 2000, tier = "silver" },
	{ id = "goals_1000", stat = "goalsFor", value = 1000, tier = "silver" },
	{ id = "goals_5000", stat = "goalsFor", value = 5000, tier = "gold" },
	-- Défis et tournois entre clubs du serveur (compteurs de TournamentService).
	{ id = "challenges_10", stat = "challengesWon", value = 10, tier = "silver" },
	{ id = "tournaments_1", stat = "tournamentsWon", value = 1, tier = "gold" },
	{ id = "tournaments_10", stat = "tournamentsWon", value = 10, tier = "gold" },
	-- Saisons de 7 jours terminées à la 1re place (DailyService).
	{ id = "seasons_1", stat = "seasonsWon", value = 1, tier = "gold" },
	{ id = "seasons_5", stat = "seasonsWon", value = 5, tier = "gold" },
	-- Coupe nationale (CupService) : coupes gagnées et exploits contre plus fort.
	{ id = "cups_1", stat = "cupsWon", value = 1, tier = "gold" },
	{ id = "cups_5", stat = "cupsWon", value = 5, tier = "gold" },
	{ id = "giantKills_10", stat = "cupGiantKills", value = 10, tier = "silver" },
	-- Coupe d'Europe entre vrais joueurs (EuroService) : finales jouées et titres.
	{ id = "euroFinal_1", stat = "euroFinals", value = 1, tier = "silver" },
	{ id = "euro_1", stat = "euroWon", value = 1, tier = "gold" },
	{ id = "euro_5", stat = "euroWon", value = 5, tier = "gold" },
}

-- Liste des trophées gagnés par un club, dans l'ordre de la vitrine.
-- Chaque trophée : { id, kind = "promotion" | "title" | "milestone", tier, key, params }.
function Trophies.Earned(division: string, stats, titles: number?)
	local list = {}
	local current = Divisions.Get(division)
	local reached = current and current.index or 1
	for index = 2, reached do
		local d = Divisions.List[index]
		table.insert(list, {
			id = "promotion_" .. d.id,
			kind = "promotion",
			tier = if index == #Divisions.List then "gold" else "silver",
			key = "trophy.promotion",
			params = { tier = d.tier },
		})
	end
	titles = titles or 0
	for n = 1, titles do
		table.insert(list, { id = "title_" .. n, kind = "title", tier = "gold", key = "trophy.title", params = { n = n } })
	end
	stats = stats or {}
	for _, m in Trophies.MILESTONES do
		if (stats[m.stat] or 0) >= m.value then
			table.insert(list, { id = m.id, kind = "milestone", tier = m.tier, key = "trophy." .. m.stat, params = { value = m.value } })
		end
	end
	return list
end

-- Nombre total de trophées possibles hors titres (les titres sont illimités).
function Trophies.FixedCount(): number
	return (#Divisions.List - 1) + #Trophies.MILESTONES
end

return Trophies
