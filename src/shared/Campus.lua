--[[
	Campus — mode Création : parcelles à débloquer derrière le club et
	bâtiments à placer librement dessus (comme dans les Sims).

	- 12 parcelles (grille de 4 × 3) derrière le terrain du club. Chacune se
	  débloque avec des FC Coins, à partir d'une division donnée.
	- Un catalogue de bâtiments, chacun disponible à partir d'une division.
	  Le joueur choisit la parcelle (libre et débloquée) et l'orientation
	  (0, 90, 180 ou 270°). Il peut ensuite le tourner, le déplacer (échange
	  si la parcelle visée est occupée) et l'améliorer (3 niveaux).
	- Chaque bâtiment donne un petit bonus utile (effets additionnés, lus par
	  le serveur seulement : Campus.Effect).

	Données du profil (data.campus) :
	  { parcels = { ["1"] = true, … }, placed = { [buildingId] = { parcel, level, rot } } }
	Les clés des parcelles sont des TEXTES ("1" à "12") : un DataStore Roblox
	n'enregistre pas correctement un tableau à trous ({ [1] = true, [5] = true }).
	Toujours passer par Campus.HasParcel / Campus.SetParcel.
	Noms affichés : clés « campus.<id>.label » et « campus.<id>.description » de Locale.
]]

local Divisions = require(script.Parent.Divisions)

local Campus = {}

Campus.MAX_LEVEL = 3
Campus.ROTATIONS = { 0, 90, 180, 270 }
Campus.MOVE_COOLDOWN = 3 -- secondes entre deux déplacements / rotations (anti-spam)

-- Parcelles : division minimale et prix (dans l'ordre de la grille : rangée 1
-- côté club, de gauche à droite, puis rangées 2 et 3).
Campus.Parcels = {
	{ division = "D6", cost = 2000 },
	{ division = "D6", cost = 4000 },
	{ division = "D5", cost = 8000 },
	{ division = "D5", cost = 12000 },
	{ division = "D4", cost = 20000 },
	{ division = "D4", cost = 26000 },
	{ division = "D3", cost = 35000 },
	{ division = "D3", cost = 42000 },
	{ division = "D2", cost = 55000 },
	{ division = "D2", cost = 65000 },
	{ division = "D1", cost = 80000 },
	{ division = "D1", cost = 100000 },
}

-- Catalogue. levels[n].cost = prix pour construire (n = 1) ou passer au niveau n.
-- Effets (additionnés entre bâtiments) :
--   matchIncome : FC Coins en plus par match ; ticketBonus : part de billetterie en plus ;
--   sponsorBonus : part des sponsors des bureaux en plus ; energyRecovery : récupération
--   d'énergie en plus (0.2 = +20 %) ; injuryReduction : blessures plus courtes ;
--   growthBonus : XP d'entraînement en plus (comme l'entraîneur du staff) ;
--   teamBonus : points de note ajoutés à l'équipe en match ;
--   upgradeDiscount : remise sur les améliorations du stade (0.1 = -10 %) ;
--   matchEnergy : énergie dépensée par match en moins (0.2 = -20 %).
Campus.Definitions = {
	Esport = {
		id = "Esport",
		order = 1,
		division = "D6",
		levels = {
			{ cost = 3000, effects = { matchIncome = 40 } },
			{ cost = 9000, effects = { matchIncome = 90 } },
			{ cost = 22000, effects = { matchIncome = 160 } },
		},
	},
	Museum = {
		id = "Museum",
		order = 2,
		division = "D6",
		levels = {
			{ cost = 4000, effects = { ticketBonus = 0.03 } },
			{ cost = 10000, effects = { ticketBonus = 0.06 } },
			{ cost = 24000, effects = { ticketBonus = 0.1 } },
		},
	},
	President = {
		id = "President",
		order = 3,
		division = "D5",
		levels = {
			{ cost = 6000, effects = { sponsorBonus = 0.1 } },
			{ cost = 15000, effects = { sponsorBonus = 0.2 } },
			{ cost = 32000, effects = { sponsorBonus = 0.3 } },
		},
	},
	Recovery = {
		id = "Recovery",
		order = 4,
		division = "D5",
		levels = {
			{ cost = 7000, effects = { energyRecovery = 0.15, injuryReduction = 0.1 } },
			{ cost = 16000, effects = { energyRecovery = 0.3, injuryReduction = 0.2 } },
			{ cost = 34000, effects = { energyRecovery = 0.5, injuryReduction = 0.3 } },
		},
	},
	Champions = {
		id = "Champions",
		order = 5,
		division = "D4",
		levels = {
			{ cost = 10000, effects = { matchIncome = 100 } },
			{ cost = 22000, effects = { matchIncome = 220 } },
			{ cost = 45000, effects = { matchIncome = 400 } },
		},
	},
	SportsComplex = {
		id = "SportsComplex",
		order = 6,
		division = "D4",
		levels = {
			{ cost = 14000, effects = { growthBonus = 0.02 } },
			{ cost = 30000, effects = { growthBonus = 0.04 } },
			{ cost = 60000, effects = { growthBonus = 0.06 } },
		},
	},
	IndoorPitch = {
		id = "IndoorPitch",
		order = 7,
		division = "D3",
		levels = {
			{ cost = 18000, effects = { teamBonus = 0.25 } },
			{ cost = 38000, effects = { teamBonus = 0.5 } },
			{ cost = 75000, effects = { teamBonus = 0.75 } },
		},
	},
	Security = {
		id = "Security",
		order = 8,
		division = "D3",
		levels = {
			{ cost = 16000, effects = { ticketBonus = 0.04 } },
			{ cost = 34000, effects = { ticketBonus = 0.07 } },
			{ cost = 68000, effects = { ticketBonus = 0.1 } },
		},
	},
	Workshop = {
		id = "Workshop",
		order = 9,
		division = "D2",
		levels = {
			{ cost = 25000, effects = { upgradeDiscount = 0.05 } },
			{ cost = 50000, effects = { upgradeDiscount = 0.1 } },
			{ cost = 95000, effects = { upgradeDiscount = 0.15 } },
		},
	},
	Depot = {
		id = "Depot",
		order = 10,
		division = "D2",
		levels = {
			{ cost = 22000, effects = { matchEnergy = 0.15 } },
			{ cost = 45000, effects = { matchEnergy = 0.3 } },
			{ cost = 90000, effects = { matchEnergy = 0.45 } },
		},
	},
}

-- Plafonds de sécurité des effets additionnés.
local CAPS = { ticketBonus = 0.5, sponsorBonus = 0.6, energyRecovery = 1, injuryReduction = 0.5, matchIncome = 2000, growthBonus = 0.1, teamBonus = 1, upgradeDiscount = 0.3, matchEnergy = 0.6 }

local function number(value, default: number): number
	return if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then value else default
end

local function divisionIndex(id): number
	local division = Divisions.Get(id)
	return if division then division.index else 1
end

function Campus.Get(id)
	return Campus.Definitions[id]
end

-- Catalogue trié pour l'affichage.
function Campus.List()
	local list = {}
	for _, def in Campus.Definitions do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- La division du club permet-elle `requiredDivision` ? (D7 = 1 … D1 = 7)
function Campus.DivisionAllows(clubDivision, requiredDivision): boolean
	return divisionIndex(clubDivision) >= divisionIndex(requiredDivision)
end

-- Profil neuf.
function Campus.Default()
	return { parcels = {}, placed = {} }
end

-- Répare / complète data.campus (anciens profils, valeurs abîmées). Renvoie la table propre.
function Campus.Sanitize(campus)
	if type(campus) ~= "table" then
		campus = Campus.Default()
	end
	local parcels = {}
	if type(campus.parcels) == "table" then
		for key, value in campus.parcels do
			local index = tonumber(key)
			if value == true and index and Campus.Parcels[index] then
				parcels[tostring(index)] = true
			end
		end
	end
	local placed, used = {}, {}
	if type(campus.placed) == "table" then
		for id, entry in campus.placed do
			local def = Campus.Definitions[id]
			local parcel = type(entry) == "table" and tonumber(entry.parcel)
			if def and parcel and parcels[tostring(parcel)] and not used[parcel] then
				local level = math.clamp(math.floor(number(entry.level, 1)), 1, #def.levels)
				local rot = number(entry.rot, 0) % 360
				if not table.find(Campus.ROTATIONS, rot) then
					rot = 0
				end
				placed[id] = { parcel = parcel, level = level, rot = rot }
				used[parcel] = true
			end
		end
	end
	campus.parcels = parcels
	campus.placed = placed
	return campus
end

-- La parcelle n° index est-elle débloquée ? (accepte aussi d'anciennes clés numériques)
function Campus.HasParcel(campus, index: number): boolean
	local parcels = type(campus) == "table" and campus.parcels
	return type(parcels) == "table" and (parcels[tostring(index)] == true or parcels[index] == true)
end

function Campus.SetParcel(campus, index: number)
	campus.parcels[tostring(index)] = true
end

-- Bâtiment posé sur une parcelle (id) ou nil.
function Campus.BuildingOn(campus, parcel: number): string?
	if type(campus) ~= "table" or type(campus.placed) ~= "table" then
		return nil
	end
	for id, entry in campus.placed do
		if entry.parcel == parcel then
			return id
		end
	end
	return nil
end

-- Niveau d'un bâtiment (0 = pas construit).
function Campus.Level(campus, id: string): number
	local entry = type(campus) == "table" and type(campus.placed) == "table" and campus.placed[id]
	return if type(entry) == "table" then number(entry.level, 0) else 0
end

-- Prix de la prochaine étape (construction ou amélioration), ou nil au maximum.
function Campus.NextCost(campus, id: string): number?
	local def = Campus.Definitions[id]
	if not def then
		return nil
	end
	local step = def.levels[Campus.Level(campus, id) + 1]
	return step and step.cost or nil
end

-- Effet additionné de tous les bâtiments posés (0 si aucun).
function Campus.Effect(campus, effect: string): number
	local total = 0
	if type(campus) == "table" and type(campus.placed) == "table" then
		for id, entry in campus.placed do
			local def = Campus.Definitions[id]
			local step = def and type(entry) == "table" and def.levels[number(entry.level, 0)]
			if step then
				total += number(step.effects[effect], 0)
			end
		end
	end
	return math.min(total, CAPS[effect] or math.huge)
end

-- Prix d'une amélioration du stade après la remise de l'atelier technique.
function Campus.DiscountedCost(campus, cost: number): number
	return math.max(1, math.floor(cost * (1 - Campus.Effect(campus, "upgradeDiscount")) + 0.5))
end

-- Nombre de parcelles débloquées.
function Campus.ParcelCount(campus): number
	local n = 0
	if type(campus) == "table" and type(campus.parcels) == "table" then
		for _ in campus.parcels do
			n += 1
		end
	end
	return n
end

return Campus
