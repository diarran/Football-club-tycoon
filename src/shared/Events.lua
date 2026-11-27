--[[
	Events
	Événements de la semaine : une raison de revenir chaque semaine
	(EventService côté serveur). Mêmes semaines que les saisons (Daily.lua) :
	du lundi 00:00 UTC au lundi suivant, horloge du SERVEUR uniquement.

	- Thème de la semaine : 4 thèmes tournent dans l'ordre (THEMES), un par
	  semaine. Chaque thème ajoute un petit bonus de FC Coins aux matchs
	  (rewards.event dans le résultat du match) et des points d'événement.
	- Points d'événement : gagnés en jouant des matchs pendant la semaine.
	  Trois paliers (TIERS) à récupérer dans l'accueil ; le dernier donne aussi
	  l'objet de personnalisation du thème (Cosmetics.EVENT), gagné en jouant,
	  jamais vendu (ni FC Coins ni Robux). Les points repartent de zéro lundi.
	- Coupe du week-end : le samedi et le dimanche (UTC), le tournoi du serveur
	  (TournamentService) devient la « Coupe du week-end » : récompenses
	  × WEEKEND_CUP_MULTIPLIER et points d'événement selon le tour atteint.

	Les montants en FC Coins sont multipliés par Daily.Scale(division).
	Équilibré avec tools/economy-sim.js : le relancer après chaque changement.
	Textes : clés « event.* » de Locale.
]]

local Daily = require(script.Parent.Daily)

local Events = {}

-- Thèmes, dans l'ordre de rotation.
-- ticketBonus : part de la billetterie ajoutée ; matchBonus : part de la
-- prime de match ajoutée (humanMatchBonus contre le club d'un vrai joueur) ;
-- revenueBonus : part des sponsors + boutique ajoutée ; goalPoints : points
-- d'événement en plus par but marqué ; humanPoints : multiplicateur des
-- points contre le club d'un vrai joueur. cosmetic : récompense du dernier palier.
Events.THEMES = {
	{ id = "tickets", ticketBonus = 0.5, cosmetic = "colors_event_tickets" },
	{ id = "derby", matchBonus = 0.5, humanMatchBonus = 1, humanPoints = 2, cosmetic = "kit_event_derby" },
	{ id = "goals", goalPoints = 1, goalCoins = 40, cosmetic = "statue_event_goal" },
	{ id = "fans", revenueBonus = 0.5, cosmetic = "lighting_event_fans" },
}

local themeById = {}
for index, theme in Events.THEMES do
	theme.index = index
	themeById[theme.id] = theme
end

function Events.GetTheme(id: any)
	return themeById[id]
end

-- Points d'événement par match (selon le résultat).
Events.MATCH_POINTS = { Win = 3, Draw = 2, Loss = 1 }

-- Paliers de la semaine : points à atteindre, FC Coins (× Daily.Scale).
-- Le dernier palier donne aussi l'objet du thème.
Events.TIERS = {
	{ points = 15, coins = 800 },
	{ points = 40, coins = 2000 },
	{ points = 80, coins = 3500, cosmetic = true },
}

-- Coupe du week-end (samedi et dimanche UTC).
Events.WEEKEND_CUP_MULTIPLIER = 1.5
Events.CUP_POINTS = { Winner = 15, Final = 8, Semi = 4, Quarter = 2 }

-- Semaine ---------------------------------------------------------------

function Events.Week(t: number): number
	return Daily.SeasonId(t)
end

function Events.ThemeForWeek(week: number)
	return Events.THEMES[(week % #Events.THEMES) + 1]
end

function Events.Current(t: number)
	return Events.ThemeForWeek(Events.Week(t))
end

function Events.WeekEndsAt(week: number): number
	return Daily.SeasonEndsAt(week)
end

-- Jour de la semaine : 1 = lundi … 7 = dimanche (UTC).
function Events.Weekday(t: number): number
	return ((Daily.Day(t) - Daily.Day(Daily.SEASON_EPOCH)) % 7) + 1
end

function Events.IsWeekend(t: number): boolean
	return Events.Weekday(t) >= 6
end

-- Début du prochain week-end (samedi 00:00 UTC), ou nil pendant le week-end.
function Events.WeekendStartsAt(t: number): number?
	if Events.IsWeekend(t) then
		return nil
	end
	return Events.WeekEndsAt(Events.Week(t)) - 2 * Daily.DAY_SECONDS
end

function Events.TournamentMultiplier(t: number): number
	return if Events.IsWeekend(t) then Events.WEEKEND_CUP_MULTIPLIER else 1
end

-- Montants ----------------------------------------------------------------

function Events.TierCoins(tierIndex: number, divisionId: string): number
	local tier = Events.TIERS[tierIndex]
	return if tier then math.floor(tier.coins * Daily.Scale(divisionId)) else 0
end

-- Bonus de FC Coins du thème pour un match.
-- income = { match, tickets, sponsor, shop } ; human = adversaire réel.
function Events.MatchBonus(theme, income, goals: number, human: boolean, divisionId: string): number
	if not theme then
		return 0
	end
	local bonus = 0
	if theme.ticketBonus then
		bonus += (income.tickets or 0) * theme.ticketBonus
	end
	if theme.matchBonus then
		local share = if human and theme.humanMatchBonus then theme.humanMatchBonus else theme.matchBonus
		bonus += (income.match or 0) * share
	end
	if theme.revenueBonus then
		bonus += ((income.sponsor or 0) + (income.shop or 0)) * theme.revenueBonus
	end
	if theme.goalCoins then
		bonus += math.max(0, goals) * theme.goalCoins * Daily.Scale(divisionId)
	end
	return math.floor(bonus)
end

-- Points d'événement pour un match.
function Events.MatchPoints(theme, outcome: string, goals: number, human: boolean): number
	local points = Events.MATCH_POINTS[outcome] or 0
	if theme and theme.goalPoints then
		points += math.max(0, goals) * theme.goalPoints
	end
	if theme and human and theme.humanPoints then
		points *= theme.humanPoints
	end
	return points
end

-- Nombre de paliers atteints avec `points`.
function Events.TiersReached(points: number): number
	local reached = 0
	for index, tier in Events.TIERS do
		if points >= tier.points then
			reached = index
		end
	end
	return reached
end

return Events
