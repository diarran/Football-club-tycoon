--[[
	Leaderboard
	Classement mondial : tous les serveurs du jeu (OrderedDataStore Roblox).

	Trois tableaux :
	- week     : points de division gagnés cette semaine (saison de 7 jours,
	             remise à zéro chaque lundi 00:00 UTC, comme Daily) ;
	- club     : niveau du club, tous les temps (division, puis points) ;
	- trophies : nombre de trophées de la salle des trophées.

	Les scores viennent uniquement des données du serveur (jamais du client).
	Budgets DataStore : chaque serveur écrit au plus une fois toutes les
	WRITE_INTERVAL secondes par joueur et par tableau (seulement si le score a
	changé) et lit les 3 tableaux toutes les REFRESH_INTERVAL secondes. Il garde
	toujours une réserve de requêtes (MIN_BUDGET) pour ne jamais gêner le jeu.
	Sans DataStore (Studio sans accès aux API), le classement montre seulement
	les clubs de ce serveur.
]]

local Divisions = require(script.Parent.Divisions)
local Trophies = require(script.Parent.Trophies)
local Daily = require(script.Parent.Daily)

local Leaderboard = {}

Leaderboard.BOARDS = { "week", "club", "trophies" }
Leaderboard.TOP = 50 -- lignes lues dans chaque tableau
Leaderboard.SHOWN = 20 -- lignes affichées dans le menu (léger sur téléphone)
Leaderboard.BOARD_ROWS = 10 -- lignes du panneau 3D de la place
Leaderboard.WRITE_INTERVAL = 120
Leaderboard.REFRESH_INTERVAL = 120
Leaderboard.FIRST_REFRESH = 5
Leaderboard.ROTATE_SECONDS = 12 -- le panneau 3D change de tableau
Leaderboard.MIN_BUDGET = 4 -- requêtes laissées de côté à chaque minute
Leaderboard.STORE_PREFIX = "Leaderboard_v1_"

-- Panneau 3D : sur la place centrale, face au point d'apparition.
Leaderboard.BOARD_POSITION = Vector3.new(-30, 0, -36)

local CLUB_LEVEL = 1000000 -- club : division × 1 000 000 + points (plafonnés)

function Leaderboard.IsBoard(id: any): boolean
	return type(id) == "string" and table.find(Leaderboard.BOARDS, id) ~= nil
end

-- Nom du DataStore ordonné d'un tableau. Le tableau de la semaine change de
-- nom à chaque saison : le classement repart de zéro sans rien effacer.
function Leaderboard.StoreName(board: string, now: number): string
	if board == "week" then
		return Leaderboard.STORE_PREFIX .. "week_" .. Daily.SeasonId(now)
	end
	return Leaderboard.STORE_PREFIX .. board
end

local function wholeNumber(value: any): number
	local n = tonumber(value) or 0
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- Score d'un profil (données du serveur) pour un tableau. Toujours un entier ≥ 0.
function Leaderboard.Score(board: string, data, now: number): number
	if type(data) ~= "table" or type(data.club) ~= "table" then
		return 0
	end
	if board == "week" then
		local season = data.season
		if type(season) ~= "table" or season.id ~= Daily.SeasonId(now) then
			return 0
		end
		return wholeNumber(season.points)
	elseif board == "club" then
		local division = Divisions.Get(data.club.division) or Divisions.Get(Divisions.STARTING_DIVISION)
		local level = #Divisions.List + 1 - division.tier -- D7 = 1 … D1 = 7
		return level * CLUB_LEVEL + math.min(wholeNumber(data.club.divisionPoints), CLUB_LEVEL - 1)
	elseif board == "trophies" then
		local titles = if type(data.trophies) == "table" then data.trophies.titles else 0
		return #Trophies.Earned(data.club.division, data.club.stats, wholeNumber(titles))
	end
	return 0
end

-- Score du tableau « club » -> division (« D3 ») et points, pour l'affichage.
function Leaderboard.DecodeClub(score: number): (string, number)
	score = wholeNumber(score)
	local level = math.clamp(score // CLUB_LEVEL, 1, #Divisions.List)
	local division = Divisions.List[level]
	return division.id, score % CLUB_LEVEL
end

-- Texte de la valeur d'une ligne, sous forme de clé Locale + paramètres.
function Leaderboard.ValueText(board: string, score: number)
	if board == "club" then
		local division, points = Leaderboard.DecodeClub(score)
		local def = Divisions.Get(division)
		return "leaderboard.value.club", { tier = def and def.tier or 7, points = points }
	end
	return "leaderboard.value." .. board, { value = wholeNumber(score) }
end

return Leaderboard
