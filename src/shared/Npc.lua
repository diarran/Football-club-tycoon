--!strict
--[[
	Npc — réglages et trajets des personnages non joueurs (PNJ).

	Les PNJ sont 100 % côté client (NpcController) : le serveur n'en crée aucun,
	rien ne passe sur le réseau image par image. Le serveur (SupporterService)
	décide seulement de l'ARGENT rapporté par les supporters et prévient les
	clients d'une visite (« SupporterVisit ») pour qu'ils l'animent.

	Coordonnées des trajets : repère local d'un terrain (WorldConfig) ;
	X = gauche/droite, Z = profondeur (-Z = entrée côté route). Y est ignoré.
]]

local WorldConfig = require(script.Parent:WaitForChild("WorldConfig"))

local Npc = {}

--------------------------------------------------------------------------------
-- Budget anti-lag
--------------------------------------------------------------------------------

-- Nombre maximum de PNJ affichés en même temps (tous terrains + rue).
Npc.BUDGET_DESKTOP = 40
Npc.BUDGET_MOBILE = 16
-- Paramètres > « Détails du décor » coupé : on garde ce pourcentage du budget.
Npc.DETAIL_OFF_FACTOR = 0.4
-- Terrains animés : seulement ceux proches de la caméra (au plus 2 sur ordinateur, 1 sur téléphone).
Npc.ZONE_RANGE = 330
Npc.MAX_ZONES_DESKTOP = 2
Npc.MAX_ZONES_MOBILE = 1
-- Au-delà de cette distance de la caméra, un PNJ est animé 10 fois par seconde au lieu de 30.
Npc.NEAR_DISTANCE = 120
Npc.NEAR_RATE = 1 / 30
Npc.FAR_RATE = 1 / 10
-- Passants de la rue : seulement autour de la caméra.
Npc.PEDESTRIANS_DESKTOP = 10
Npc.PEDESTRIANS_MOBILE = 4
Npc.PEDESTRIAN_RANGE = 200

Npc.WALK_SPEED = 7 -- studs par seconde (un peu moins vite qu'un joueur)
Npc.RUN_SPEED = 13

-- Nombre de PNJ pour un budget donné.
function Npc.Budget(mobile: boolean, details: boolean): number
	local base = if mobile then Npc.BUDGET_MOBILE else Npc.BUDGET_DESKTOP
	if not details then
		base = math.floor(base * Npc.DETAIL_OFF_FACTOR)
	end
	return math.max(4, base)
end

--------------------------------------------------------------------------------
-- Argent des supporters (décidé par le serveur seulement)
--------------------------------------------------------------------------------

-- Toutes les VISIT_INTERVAL secondes, pour chaque club présent sur le serveur :
-- un supporter achète à la Boutique, et un autre visite le Musée s'il est construit.
Npc.VISIT_INTERVAL = 45
-- Résumé envoyé au joueur toutes les SUMMARY_EVERY visites.
Npc.SUMMARY_EVERY = 8

-- FC Coins d'un achat à la Boutique (niveau 1 à 5) : 5, 7, 9, 11, 13.
function Npc.ShopSpend(shopLevel: number): number
	local level = math.clamp(math.floor(tonumber(shopLevel) or 1), 1, WorldConfig.MAX_LEVEL)
	return 3 + 2 * level
end

-- FC Coins d'une visite du Musée (niveau 1 à 3) : 10, 14, 18 ; 0 sans musée.
function Npc.MuseumSpend(museumLevel: number): number
	local level = math.floor(tonumber(museumLevel) or 0)
	if level <= 0 then
		return 0
	end
	return 6 + 4 * math.min(level, 3)
end

--------------------------------------------------------------------------------
-- Trajets (repère local du terrain)
--------------------------------------------------------------------------------

local function p(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

local HALF_Z = WorldConfig.PLOT_SIZE.Y / 2 -- 100

-- Point d'arrivée depuis la rue (devant le portique d'entrée), avec un léger décalage.
function Npc.StreetPoint(offset: number?): Vector3
	return p((offset or 0), -HALF_Z - 3)
end

-- Entrée -> porte de la Boutique (Megastore).
function Npc.ShopRoute(offset: number?): { Vector3 }
	local o = offset or 0
	return { Npc.StreetPoint(o), p(o * 0.5, -92), p(-4, -88), p(-62, -88), p(-62, -85) }
end

-- Entrée -> tribunes (passage sous la tribune sud).
function Npc.StadiumRoute(offset: number?): { Vector3 }
	local o = offset or 0
	return { Npc.StreetPoint(o), p(o * 0.5, -88), p(o * 0.3, -40), p(o * 0.3, -30) }
end

-- Petites balades sans achat (salle des trophées, espace VIP, statue).
Npc.STROLL_TARGETS = {
	{ p(-23, -88), p(-23, -80) }, -- salle des trophées
	{ p(30, -88), p(30, -84) }, -- espace VIP
	{ p(10, -86), p(12, -82) }, -- statue
	{ p(-62, -88), p(-62, -85) }, -- vitrine de la boutique
}

function Npc.StrollRoute(index: number, offset: number?): { Vector3 }
	local o = offset or 0
	local target = Npc.STROLL_TARGETS[((index - 1) % #Npc.STROLL_TARGETS) + 1]
	return { Npc.StreetPoint(o), p(o * 0.5, -92), p(o * 0.3, -88), target[1], target[2] }
end

-- Point devant la porte d'un bâtiment du mode Création (porte = face avant -Z
-- du bâtiment, tournée de `rot` degrés comme CampusZone.ParcelCFrame).
function Npc.CampusDoor(parcelIndex: number, rot: number?): Vector3?
	local parcel = WorldConfig.PARCELS[parcelIndex]
	if not parcel then
		return nil
	end
	local theta = math.rad(tonumber(rot) or 0)
	local d = 27
	return p(parcel.x - d * math.sin(theta), parcel.z - d * math.cos(theta))
end

-- Entrée -> allée latérale -> boulevard du mode Création -> porte du bâtiment.
function Npc.CampusRoute(parcelIndex: number, rot: number?, offset: number?): { Vector3 }?
	local parcel = WorldConfig.PARCELS[parcelIndex]
	local door = Npc.CampusDoor(parcelIndex, rot)
	if not parcel or not door then
		return nil
	end
	local o = offset or 0
	local boulevardZ = HALF_Z + WorldConfig.CAMPUS_BOULEVARD / 2
	local route = { Npc.StreetPoint(o), p(o * 0.5, -88), p(50, -88), p(50, boulevardZ) }
	-- Allée devant la parcelle (le boulevard pour la 1re rangée).
	local frontZ = parcel.z - WorldConfig.PARCEL_SIZE.Y / 2 - 3
	local backZ = parcel.z + WorldConfig.PARCEL_SIZE.Y / 2 + 3
	local sideX = parcel.x + (if parcel.x < 0 then 31 else -31) -- allée entre deux colonnes
	if math.abs(frontZ - boulevardZ) > 4 then
		table.insert(route, p(sideX, boulevardZ))
		table.insert(route, p(sideX, frontZ))
	end
	local dx, dz = door.X - parcel.x, door.Z - parcel.z
	if dz < -10 then
		table.insert(route, p(parcel.x, frontZ)) -- porte côté allée : tout droit
	elseif math.abs(dx) > 10 then
		local x = parcel.x + (if dx > 0 then 31 else -31)
		table.insert(route, p(x, frontZ))
		table.insert(route, p(x, parcel.z))
	else
		table.insert(route, p(sideX, frontZ))
		table.insert(route, p(sideX, backZ))
		table.insert(route, p(parcel.x, backZ))
	end
	table.insert(route, door)
	return route
end

--------------------------------------------------------------------------------
-- Postes fixes (repère local du terrain)
--------------------------------------------------------------------------------

-- Gardiens de sécurité du portique (face à la route).
Npc.ENTRANCE_GUARDS = { p(-9, -95), p(9, -95) }
-- Ronde des gardiens supplémentaires quand le Centre de sécurité est construit.
Npc.PATROL_ROUTE = { p(50, -84), p(50, 40), p(50, 96), p(50, 40) }

-- Zone d'entraînement : centre et demi-taille du terrain (WorldConfig.TRAINING_FIELD).
function Npc.TrainingField(): (Vector3, Vector2)
	local layout = WorldConfig.LAYOUT.Training
	return p(layout.x, layout.z), Vector2.new(WorldConfig.TRAINING_FIELD.X / 2, WorldConfig.TRAINING_FIELD.Y / 2)
end

-- Nombre de joueurs à l'entraînement selon le niveau de la zone (1 à 5) : 2, 3, 3, 4, 4.
function Npc.TrainingCount(level: number): number
	local l = math.clamp(math.floor(tonumber(level) or 1), 1, WorldConfig.MAX_LEVEL)
	return 2 + math.floor(l / 2)
end

-- Passants : trottoirs de la route centrale du quartier (coordonnées MONDE).
function Npc.SidewalkLanes(): { number }
	local z = WorldConfig.ROAD_WIDTH / 2 + WorldConfig.SIDEWALK_WIDTH / 2
	return { -z - 2, -z + 2, z - 2, z + 2 }
end

function Npc.SidewalkHalfLength(): number
	return WorldConfig.DISTRICT_SIZE.X / 2 - 30
end

return Npc
