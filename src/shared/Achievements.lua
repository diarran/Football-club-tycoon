--[[
	Achievements (succès)
	20 succès à débloquer en jouant (première victoire, montées D6 → D1,
	Coupe nationale, tournoi, 100 buts, un joueur noté 80…). Chacun donne
	une petite prime en FC Coins, à récupérer dans l'onglet Prestige.

	Les succès sont calculés à partir du profil : un ancien profil reçoit
	tout de suite ceux qu'il mérite (primes à récupérer). Une fois débloqué,
	un succès le reste, même si la condition n'est plus vraie (joueur vendu…).
	État serveur : data.achievements = { unlocked, claimed, badges }
	(AchievementService).

	BADGES ROBLOX : les 10 succès marqués « badge » donnent aussi un vrai
	badge Roblox, visible sur le profil du joueur. Les badges se créent dans
	le Creator Hub (voir GUIDE_BADGES.md), puis on colle leur numéro ci-dessous
	dans BADGE_IDS. Tant qu'un numéro vaut 0, ce badge n'est simplement pas
	donné : le succès et sa prime marchent quand même.

	Texte : clés « achievement.<id> » et « achievement.<id>.desc » de Locale.
]]

local Divisions = require(script.Parent.Divisions)
local Buildings = require(script.Parent.Buildings)
local Staff = require(script.Parent.Staff)

local Achievements = {}

-- >>> NUMÉROS DES BADGES ROBLOX (à remplir quand les badges sont créés) <<<
-- Exemple : first_win = 1234567890123456,
Achievements.BADGE_IDS = {
	first_win = 0,
	goals_100 = 0,
	promo_D5 = 0,
	promo_D3 = 0,
	promo_D1 = 0,
	cup_winner = 0,
	tournament_winner = 0,
	player_80 = 0,
	stadium_max = 0,
	d1_title = 0,
}

local function stat(name: string)
	return function(data)
		local club = data.club
		local stats = club and club.stats
		return (type(stats) == "table" and tonumber(stats[name])) or 0
	end
end

local function divisionReached(data): number
	local club = data.club
	local division = club and Divisions.Get(club.division)
	return division and division.index or 1
end

local function bestRating(data): number
	local best = 0
	for _, footballer in data.squad or {} do
		if type(footballer) == "table" and type(footballer.rating) == "number" then
			best = math.max(best, footballer.rating)
		end
	end
	return best
end

local function staffHired(data): number
	local count = 0
	for id in Staff.Definitions do
		local level = data.staff and data.staff[id]
		if type(level) == "number" and level > 0 then
			count += 1
		end
	end
	return count
end

local function buildingsMaxed(data): number
	local count = 0
	for id in Buildings.Definitions do
		local level = data.buildings and data.buildings[id]
		if type(level) == "number" and level >= Buildings.MaxLevel(id) then
			count += 1
		end
	end
	return count
end

local function prestigeItems(data): number
	local count = 0
	local owned = data.cosmetics and data.cosmetics.owned
	for id in (type(owned) == "table" and owned or {}) do
		if type(id) == "string" then
			count += 1
		end
	end
	return count
end

local function titles(data): number
	return (data.trophies and tonumber(data.trophies.titles)) or 0
end

local function countTable(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Succès, dans l'ordre d'affichage.
-- progress(data) lit le profil serveur ; target = valeur à atteindre ; reward en FC.
Achievements.LIST = {
	{ id = "first_win", progress = stat("wins"), target = 1, reward = 100 },
	{ id = "wins_10", progress = stat("wins"), target = 10, reward = 250 },
	{ id = "goals_100", progress = stat("goalsFor"), target = 100, reward = 500 },
	{ id = "challenge_winner", progress = stat("challengesWon"), target = 1, reward = 300 },
	{ id = "promo_D6", progress = divisionReached, target = 2, reward = 300 },
	{ id = "promo_D5", progress = divisionReached, target = 3, reward = 600 },
	{ id = "full_staff", progress = staffHired, target = countTable(Staff.Definitions), reward = 1000 },
	{ id = "first_cosmetic", progress = prestigeItems, target = 1, reward = 500 },
	{ id = "giant_kill", progress = stat("cupGiantKills"), target = 1, reward = 500 },
	{ id = "tournament_winner", progress = stat("tournamentsWon"), target = 1, reward = 1500 },
	{ id = "promo_D4", progress = divisionReached, target = 4, reward = 1200 },
	{ id = "wins_100", progress = stat("wins"), target = 100, reward = 1500 },
	{ id = "cup_winner", progress = stat("cupsWon"), target = 1, reward = 3000 },
	{ id = "season_winner", progress = stat("seasonsWon"), target = 1, reward = 2000 },
	{ id = "promo_D3", progress = divisionReached, target = 5, reward = 2500 },
	{ id = "player_80", progress = bestRating, target = 80, reward = 2000 },
	{ id = "promo_D2", progress = divisionReached, target = 6, reward = 5000 },
	{ id = "stadium_max", progress = buildingsMaxed, target = countTable(Buildings.Definitions), reward = 5000 },
	{ id = "promo_D1", progress = divisionReached, target = 7, reward = 10000 },
	{ id = "d1_title", progress = titles, target = 1, reward = 10000 },
}

local byId = {}
for _, def in Achievements.LIST do
	byId[def.id] = def
end

function Achievements.Get(id: any)
	return if type(id) == "string" then byId[id] else nil
end

-- Numéro du badge Roblox d'un succès, ou nil s'il n'y en a pas (encore).
function Achievements.BadgeId(id: string): number?
	local badgeId = tonumber(Achievements.BADGE_IDS[id])
	return if badgeId and badgeId > 0 then badgeId else nil
end

-- Le succès a-t-il un badge Roblox prévu (numéro rempli ou non) ?
function Achievements.HasBadgeSlot(id: string): boolean
	return Achievements.BADGE_IDS[id] ~= nil
end

function Achievements.TotalRewards(): number
	local total = 0
	for _, def in Achievements.LIST do
		total += def.reward
	end
	return total
end

-- Valeur actuelle (bornée à la cible) d'un succès pour ce profil.
function Achievements.Progress(def, data): number
	local ok, value = pcall(def.progress, data)
	if not ok or type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, def.target)
end

-- Condition remplie (sans tenir compte de l'état déjà enregistré) ?
function Achievements.IsMet(def, data): boolean
	return Achievements.Progress(def, data) >= def.target
end

return Achievements
