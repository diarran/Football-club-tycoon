--[[
	Daily
	Raisons de revenir chaque jour : récompense de connexion, missions du jour,
	revenus hors ligne et saisons de 7 jours (DailyService côté serveur).

	Toutes les heures viennent de l'horloge du SERVEUR (os.time(), en UTC) :
	le client ne fait qu'afficher. Le jour change à minuit UTC.

	Les montants sont multipliés par Daily.Scale(division) pour rester utiles
	du début (D7) à la fin de partie (D1). Équilibrés avec tools/economy-sim.js
	(docs/economy/README.md) : le relancer après chaque changement.

	Textes : clés « daily.* », « mission.* » et « season.* » de Locale.
]]

local Buildings = require(script.Parent.Buildings)
local Divisions = require(script.Parent.Divisions)

local Daily = {}

Daily.DAY_SECONDS = 86400

-- Multiplicateur des récompenses selon la division du club.
-- Suit à peu près le gain moyen d'un match dans chaque division.
Daily.SCALE = { D7 = 1, D6 = 1.3, D5 = 1.6, D4 = 2.5, D3 = 3.5, D2 = 5, D1 = 6.5 }

function Daily.Scale(divisionId: string): number
	return Daily.SCALE[divisionId] or 1
end

function Daily.Day(t: number): number
	return math.floor(t / Daily.DAY_SECONDS)
end

-- Secondes avant le prochain minuit UTC.
function Daily.SecondsToNextDay(t: number): number
	return (Daily.Day(t) + 1) * Daily.DAY_SECONDS - t
end

-- Récompense de connexion -------------------------------------------------
-- Cycle de 7 jours : le 7e jour est le gros cadeau, puis le cycle recommence.
-- Un jour manqué fait repartir la série au jour 1 (rien n'est retiré).
Daily.STREAK_REWARDS = { 300, 400, 500, 650, 800, 1000, 2000 }

-- Position dans le cycle (1 à 7) pour une série de `streak` jours.
function Daily.CycleDay(streak: number): number
	return ((math.max(1, streak) - 1) % #Daily.STREAK_REWARDS) + 1
end

function Daily.StreakReward(streak: number, divisionId: string): number
	return math.floor(Daily.STREAK_REWARDS[Daily.CycleDay(streak)] * Daily.Scale(divisionId))
end

-- Missions du jour ----------------------------------------------------------
-- stat : compteur suivi par DailyService ; levels : { objectif, prime }.
-- needs : mission proposée seulement si elle est faisable pour ce club.
Daily.MISSIONS_PER_DAY = 3
Daily.MISSIONS = {
	{ id = "win", stat = "win", levels = { { 3, 500 }, { 5, 800 } } },
	{ id = "play", stat = "play", levels = { { 5, 400 }, { 8, 650 } } },
	{ id = "goals", stat = "goals", levels = { { 8, 450 }, { 12, 700 } } },
	{ id = "upgrade", stat = "upgrade", levels = { { 1, 400 } }, needs = "upgrade" },
	{ id = "recruit", stat = "recruit", levels = { { 1, 400 } }, needs = "recruit" },
}

local missionById = {}
for _, def in Daily.MISSIONS do
	missionById[def.id] = def
end

function Daily.GetMission(id: string)
	return missionById[id]
end

-- Petit générateur pseudo-aléatoire rejouable : mêmes missions pour un même
-- joueur le même jour, même après une reconnexion ou un changement de serveur.
local function seeded(seed: number)
	local state = (seed % 2147483646) + 1
	return function(n: number): number
		state = (state * 48271) % 2147483647
		return (state % n) + 1
	end
end

-- feasible(needs) -> boolean : la mission est-elle faisable pour ce club ?
function Daily.PickMissions(userId: number, day: number, divisionId: string, feasible)
	local pool = {}
	for _, def in Daily.MISSIONS do
		if not def.needs or feasible(def.needs) then
			table.insert(pool, def)
		end
	end
	local roll = seeded(userId * 7919 + day * 104729)
	local missions = {}
	while #missions < Daily.MISSIONS_PER_DAY and #pool > 0 do
		local def = table.remove(pool, roll(#pool))
		local level = def.levels[roll(#def.levels)]
		table.insert(missions, {
			id = def.id,
			target = level[1],
			reward = math.floor(level[2] * Daily.Scale(divisionId)),
			progress = 0,
			done = false,
		})
	end
	return missions
end

-- Revenus hors ligne -------------------------------------------------------
-- Les installations (billetterie, sponsors, boutique, VIP) rapportent une part
-- réduite pendant l'absence : l'équivalent de OFFLINE_MATCHES_PER_HOUR matchs
-- par heure, sans prime de match, plafonné à OFFLINE_MAX_SECONDS.
Daily.OFFLINE_MIN_SECONDS = 300
Daily.OFFLINE_MAX_SECONDS = 8 * 3600
Daily.OFFLINE_MATCHES_PER_HOUR = 0.5
Daily.OFFLINE_ATTENDANCE = 0.75 -- remplissage moyen des tribunes

-- Revenus des installations pour un match (sans la prime de match).
function Daily.FacilityIncome(buildings): number
	local function effects(id)
		return Buildings.GetEffects(id, buildings[id] or 1) or {}
	end
	local stands, vip = effects("Stands"), effects("VIP")
	local tickets = math.floor((stands.capacity or 0) * Daily.OFFLINE_ATTENDANCE * (stands.ticketPrice or 0))
	return tickets
		+ (effects("Offices").sponsorIncome or 0)
		+ (effects("Shop").shopIncome or 0)
		+ math.floor(tickets * (vip.ticketBonus or 0))
		+ (vip.vipIncome or 0)
end

-- FC Coins gagnés pendant `awaySeconds` d'absence.
function Daily.OfflineIncome(buildings, awaySeconds: number): (number, number)
	if type(awaySeconds) ~= "number" or awaySeconds ~= awaySeconds or awaySeconds < Daily.OFFLINE_MIN_SECONDS then
		return 0, 0
	end
	local counted = math.min(awaySeconds, Daily.OFFLINE_MAX_SECONDS)
	local coins = math.floor(Daily.FacilityIncome(buildings) * Daily.OFFLINE_MATCHES_PER_HOUR * counted / 3600)
	return coins, counted
end

-- Saisons ------------------------------------------------------------------
-- Une saison dure 7 jours, du lundi 00:00 UTC au lundi suivant. Les points de
-- saison sont les points de division gagnés en match pendant la saison.
-- Classement : le club contre les clubs fictifs de sa division, dont les
-- points montent pendant la semaine jusqu'à SEASON_TARGET × share.
Daily.SEASON_SECONDS = 7 * Daily.DAY_SECONDS
Daily.SEASON_EPOCH = 4 * Daily.DAY_SECONDS -- lundi 5 janvier 1970, 00:00 UTC
Daily.SEASON_TARGET = 200
Daily.SEASON_REWARDS = { 5000, 3000, 2000, 1200, 700, 400 } -- par place finale

function Daily.SeasonId(t: number): number
	return math.floor((t - Daily.SEASON_EPOCH) / Daily.SEASON_SECONDS)
end

function Daily.SeasonEndsAt(seasonId: number): number
	return Daily.SEASON_EPOCH + (seasonId + 1) * Daily.SEASON_SECONDS
end

function Daily.SeasonReward(rank: number, divisionId: string): number
	local base = Daily.SEASON_REWARDS[math.clamp(rank, 1, #Daily.SEASON_REWARDS)]
	return math.floor(base * Daily.Scale(divisionId))
end

-- Classement de la saison : clubs fictifs de la division + le club du joueur.
-- progress : part de la saison écoulée (0 à 1 ; 1 = classement final).
-- Renvoie (lignes triées, place du joueur). À égalité, le joueur passe devant.
function Daily.SeasonStandings(divisionId: string, myName: string, myPoints: number, progress: number)
	progress = math.clamp(progress, 0, 1)
	local rows = {}
	for _, rival in Divisions.GetRivals(divisionId) do
		local share = Divisions.RIVALS[rival.index].share
		table.insert(rows, { name = rival.name, points = math.floor(Daily.SEASON_TARGET * share * progress), me = false })
	end
	table.insert(rows, { name = myName, points = myPoints, me = true })
	table.sort(rows, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.me and not b.me
	end)
	local rank = 1
	for index, row in rows do
		if row.me then
			rank = index
		end
	end
	return rows, rank
end

function Daily.SeasonProgress(seasonId: number, t: number): number
	local start = Daily.SeasonEndsAt(seasonId) - Daily.SEASON_SECONDS
	return (t - start) / Daily.SEASON_SECONDS
end

return Daily
