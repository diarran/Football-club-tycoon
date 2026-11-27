--!strict
--[[
	City — règles et plan du centre-ville commerçant (partagé client / serveur).

	Le centre-ville est à l'EST du quartier des clubs, au bout de la route
	centrale : grands boulevards à 4 voies, rond-point monumental avec un ballon
	géant, deux carrefours avec feux tricolores et passages piétons,
	concessionnaire auto, hôtel du club, banque, cafés, restaurants et tours
	couvertes de publicités.

	Ce module ne contient que des valeurs non sensibles : prix, vitesses, plan.
	Le serveur (CityService) vérifie tout ; le client ne fait qu'afficher.

	Repère du centre-ville : origine = centre du rond-point (City.ORIGIN),
	X vers l'est, Z vers le sud. On arrive du quartier par l'ouest (x négatif).
	Quand on roule vers l'est, la gauche est côté -Z (concessionnaire, hôtel)
	et la droite côté +Z (banque, cafés, tours d'affaires).
]]

local City = {}

--------------------------------------------------------------------------------
-- Plan
--------------------------------------------------------------------------------

-- Le quartier des clubs fait 900 studs de large (WorldConfig.DISTRICT_SIZE.X) :
-- son bord est est en x = 450. Le centre-ville commence juste après.
City.SIZE = Vector2.new(650, 600)
City.ORIGIN = Vector3.new(450 + City.SIZE.X / 2, 0, 0) -- (775, 0, 0)
City.NAME = "City"

-- Boulevards : 4 voies de 9 studs, terre-plein central de 4 studs, trottoirs de 10.
City.LANE = 9
City.MEDIAN = 4
City.BOULEVARD = 2 * City.LANE * 2 + City.MEDIAN -- 40 studs de chaussée
City.SIDEWALK = 10
-- Rond-point : anneau de chaussée entre ISLAND et RING (rayons).
City.ISLAND = 24
City.RING = 44
-- Rues transversales (2 voies) avec feux tricolores, en x = ±CROSS_X.
City.CROSS_X = 180
City.CROSS_WIDTH = 22

-- Voies de circulation (z local) : on roule à droite.
City.LANE_EAST = City.MEDIAN / 2 + City.LANE * 1.5 -- 15,5 : voie extérieure vers l'est
City.LANE_WEST = -City.LANE_EAST

-- Point d'arrivée en ville (bouton « Ville ») : trottoir à l'entrée ouest.
City.ARRIVAL = Vector3.new(-290, 3, City.BOULEVARD / 2 + City.SIDEWALK / 2)

-- Bâtiments principaux (centre au sol, en local) : la façade donne sur le boulevard.
City.PLACES = {
	Dealer = { x = -250, z = -78, size = Vector2.new(96, 56) }, -- concessionnaire (gauche)
	Hotel = { x = -250, z = -200, size = Vector2.new(56, 44) }, -- hôtel du club (derrière)
	Bank = { x = -250, z = 82, size = Vector2.new(60, 44) }, -- banque (droite)
}

-- Distance maximale (studs) entre le joueur et un guichet pour l'utiliser.
City.COUNTER_RANGE = 40

function City.ToWorld(localPos: Vector3): Vector3
	return City.ORIGIN + localPos
end

function City.ToLocal(worldPos: Vector3): Vector3
	return worldPos - City.ORIGIN
end

-- Le point est-il dans le centre-ville (avec une marge) ?
function City.IsInside(worldPos: Vector3, margin: number?): boolean
	local p = City.ToLocal(worldPos)
	local m = margin or 0
	return math.abs(p.X) <= City.SIZE.X / 2 + m and math.abs(p.Z) <= City.SIZE.Y / 2 + m
end

--------------------------------------------------------------------------------
-- Feux tricolores (même cycle chez tous les joueurs : heure du serveur)
--------------------------------------------------------------------------------

City.LIGHT_CYCLE = 26 -- secondes
City.LIGHT_MAIN_GREEN = 12 -- boulevard vert de 0 à 12 s, orange jusqu'à 15 s
City.LIGHT_YELLOW = 3

-- Couleur du feu ("green", "yellow" ou "red") pour le boulevard ("main")
-- ou la rue transversale ("cross") à l'instant t (secondes du serveur).
function City.LightState(axis: string, t: number): string
	local phase = t % City.LIGHT_CYCLE
	local mainGreen, yellow = City.LIGHT_MAIN_GREEN, City.LIGHT_YELLOW
	local crossStart = mainGreen + yellow
	local crossGreen = City.LIGHT_CYCLE - crossStart - yellow
	if axis == "main" then
		if phase < mainGreen then
			return "green"
		elseif phase < crossStart then
			return "yellow"
		end
		return "red"
	end
	if phase >= crossStart and phase < crossStart + crossGreen then
		return "green"
	elseif phase >= crossStart + crossGreen then
		return "yellow"
	end
	return "red"
end

--------------------------------------------------------------------------------
-- Circulation (voitures des PNJ, côté client uniquement)
--------------------------------------------------------------------------------

-- Même logique que les PNJ : peu de voitures sur téléphone, moins encore si
-- « Détails du décor » est coupé, et rien quand la caméra est loin de la ville.
City.TRAFFIC_DESKTOP = 12
City.TRAFFIC_MOBILE = 5
City.TRAFFIC_LOW_DETAIL = 0.4 -- part gardée si « Détails du décor » est coupé
City.TRAFFIC_RANGE = 700 -- distance caméra -> centre-ville au-delà de laquelle tout s'arrête
City.TRAFFIC_SPEED = 26 -- studs / s
City.TRAFFIC_GAP = 16 -- distance minimale avec la voiture de devant

-- Nombre de voitures de circulation pour un appareil donné.
function City.TrafficBudget(mobile: boolean, details: boolean): number
	local n = if mobile then City.TRAFFIC_MOBILE else City.TRAFFIC_DESKTOP
	if not details then
		n = math.max(1, math.floor(n * City.TRAFFIC_LOW_DETAIL + 0.5))
	end
	return n
end

-- Boucle de circulation (points en local, sens de marche) : voie est du
-- boulevard, demi-tour du rond-point côté sud, bout est, voie ouest, demi-tour
-- nord du rond-point, bout ouest. Les demi-cercles sont approchés par des segments.
function City.TrafficLoop(): { Vector3 }
	local points = {}
	local east, west = City.LANE_EAST, City.LANE_WEST
	local r = (City.ISLAND + City.RING) / 2 + 4 -- rayon de passage dans l'anneau
	local endX = City.SIZE.X / 2 - 14
	local function add(x: number, z: number)
		table.insert(points, Vector3.new(x, 0, z))
	end
	add(-endX, east)
	add(-City.RING - 2, east)
	-- Anneau par le sud (+Z), d'ouest en est : on garde l'îlot à gauche.
	for i = 1, 7 do
		local a = math.pi - i * math.pi / 8
		add(r * math.cos(a), r * math.sin(a))
	end
	add(City.RING + 2, east)
	add(endX, east)
	add(endX + 8, 0)
	add(endX, west)
	add(City.RING + 2, west)
	-- Anneau par le nord (-Z), d'est en ouest.
	for i = 1, 7 do
		local a = -i * math.pi / 8
		add(r * math.cos(a), r * math.sin(a))
	end
	add(-City.RING - 2, west)
	add(-endX, west)
	add(-endX - 8, 0)
	return points
end

-- Lignes d'arrêt des feux sur la boucle : { x, sens (1 = vers l'est) }.
City.STOP_LINES = {
	{ x = -City.CROSS_X - City.CROSS_WIDTH / 2 - 4, dir = 1 },
	{ x = City.CROSS_X - City.CROSS_WIDTH / 2 - 4, dir = 1 },
	{ x = City.CROSS_X + City.CROSS_WIDTH / 2 + 4, dir = -1 },
	{ x = -City.CROSS_X + City.CROSS_WIDTH / 2 + 4, dir = -1 },
}

--------------------------------------------------------------------------------
-- Concessionnaire : voitures à acheter avec l'argent du club
--------------------------------------------------------------------------------

-- speed = vitesse maximale (studs / s ; un joueur à pied fait 16),
-- accel = studs / s², turn = vitesse de rotation (degrés / s à pleine vitesse).
-- shape : silhouette du modèle 3D (CarModels).
City.CARS = {
	{ id = "Citadine", price = 0, division = "D7", speed = 48, accel = 22, turn = 95, shape = "hatch" },
	{ id = "Berline", price = 12000, division = "D6", speed = 62, accel = 26, turn = 90, shape = "sedan" },
	{ id = "Coupe", price = 45000, division = "D5", speed = 76, accel = 32, turn = 92, shape = "coupe" },
	{ id = "Suv", price = 90000, division = "D4", speed = 70, accel = 28, turn = 80, shape = "suv" },
	{ id = "Sport", price = 220000, division = "D3", speed = 92, accel = 40, turn = 95, shape = "sport" },
	{ id = "Super", price = 600000, division = "D1", speed = 112, accel = 48, turn = 100, shape = "super" },
}
City.DEFAULT_CAR = "Citadine"

-- Peintures (gratuites) : couleur du club ou teintes « premium ».
City.PAINTS = {
	{ id = "club" }, -- couleur principale du club
	{ id = "black", color = Color3.fromRGB(22, 22, 26) },
	{ id = "gold", color = Color3.fromRGB(212, 175, 55) },
	{ id = "white", color = Color3.fromRGB(236, 236, 236) },
	{ id = "red", color = Color3.fromRGB(190, 30, 40) },
	{ id = "blue", color = Color3.fromRGB(30, 70, 170) },
	{ id = "silver", color = Color3.fromRGB(170, 174, 182) },
}
City.DEFAULT_PAINT = "club"

-- Une voiture sortie disparaît après ce délai sans conducteur.
City.CAR_IDLE_DESPAWN = 300
City.CAR_SPAWN_COOLDOWN = 5

local carById = {}
for i, car in City.CARS do
	car.order = i
	carById[car.id] = car
end
local paintById = {}
for _, paint in City.PAINTS do
	paintById[paint.id] = paint
end

function City.GetCar(id: any)
	return if type(id) == "string" then carById[id] else nil
end

function City.GetPaint(id: any)
	return if type(id) == "string" then paintById[id] else nil
end

--------------------------------------------------------------------------------
-- Banque : prêt et placement
--------------------------------------------------------------------------------

-- Montant maximal d'un prêt et d'un placement, selon la division.
City.LOAN_MAX = { D7 = 3000, D6 = 8000, D5 = 20000, D4 = 50000, D3 = 120000, D2 = 250000, D1 = 500000 }
City.LOAN_FEE = 0.1 -- 10 % de frais : on rend 110 % de la somme empruntée
City.LOAN_REPAY_SHARE = 0.25 -- part de chaque gain de match prélevée tant que le prêt n'est pas soldé
City.INVEST_MAX = { D7 = 5000, D6 = 15000, D5 = 40000, D4 = 90000, D3 = 180000, D2 = 300000, D1 = 450000 }
City.INVEST_RATE = 0.05 -- +5 % ...
City.INVEST_SECONDS = 4 * 3600 -- ... après 4 heures (le compteur repart à chaque dépôt)
City.INVEST_STEPS = 4 -- un dépôt = un quart du plafond (ou ce qu'il reste)

function City.LoanMax(division: any): number
	return City.LOAN_MAX[division] or City.LOAN_MAX.D7
end

function City.InvestMax(division: any): number
	return City.INVEST_MAX[division] or City.INVEST_MAX.D7
end

-- Somme à rendre pour un emprunt de `amount`.
function City.LoanDue(amount: number): number
	return math.floor(amount * (1 + City.LOAN_FEE) + 0.5)
end

-- Valeur du placement à l'instant `now` (intérêts seulement après INVEST_SECONDS).
function City.InvestValue(bank, now: number): number
	local amount = bank.invest or 0
	if amount <= 0 then
		return 0
	end
	if now - (bank.investAt or now) >= City.INVEST_SECONDS then
		return math.floor(amount * (1 + City.INVEST_RATE) + 0.5)
	end
	return amount
end

--------------------------------------------------------------------------------
-- Hôtel du club : « mise au vert » avant les matchs
--------------------------------------------------------------------------------

-- Toute l'équipe récupère son énergie au maximum. Prix selon la division.
City.HOTEL_PRICE = { D7 = 400, D6 = 900, D5 = 2000, D4 = 4000, D3 = 7000, D2 = 11000, D1 = 16000 }
City.HOTEL_COOLDOWN = 45 * 60

function City.HotelPrice(division: any): number
	return City.HOTEL_PRICE[division] or City.HOTEL_PRICE.D7
end

--------------------------------------------------------------------------------
-- Données du joueur (data.city)
--------------------------------------------------------------------------------

function City.Default()
	return {
		cars = { [City.DEFAULT_CAR] = true }, -- clés texte : sans risque pour le DataStore
		car = City.DEFAULT_CAR,
		paint = City.DEFAULT_PAINT,
		bank = { loan = 0, invest = 0, investAt = 0 },
		hotelAt = 0,
	}
end

local function goodNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function nonNegative(v: any): number
	return if goodNumber(v) and v > 0 then math.floor(v) else 0
end

-- Répare / complète data.city (anciens profils, valeurs abîmées). Renvoie la table propre.
function City.Sanitize(city)
	local clean = City.Default()
	if type(city) ~= "table" then
		return clean
	end
	if type(city.cars) == "table" then
		for id, owned in city.cars do
			if owned == true and carById[id] then
				clean.cars[id] = true
			end
		end
	end
	if type(city.car) == "string" and clean.cars[city.car] then
		clean.car = city.car
	end
	if City.GetPaint(city.paint) then
		clean.paint = city.paint
	end
	local bank = type(city.bank) == "table" and city.bank or {}
	clean.bank.loan = nonNegative(bank.loan)
	clean.bank.invest = nonNegative(bank.invest)
	clean.bank.investAt = nonNegative(bank.investAt)
	clean.hotelAt = nonNegative(city.hotelAt)
	return clean
end

return City
