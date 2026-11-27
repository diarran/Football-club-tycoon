--!strict
--[[
	WorldConfig — constantes du monde de Football Club Tycoon.

	Ce module est partagé (ReplicatedStorage.Shared.WorldConfig) : il ne contient
	que des valeurs non sensibles (tailles, positions, couleurs, niveaux).
	Toutes les distances sont en studs (un personnage Roblox mesure ~5 studs).

	Repère d'un terrain de club (« plot ») :
	  - origine = centre du terrain, au niveau du sol du quartier (Y = 0) ;
	  - l'axe X local va de gauche à droite quand on regarde le club depuis la route ;
	  - l'axe -Z local pointe vers l'AVANT du terrain (côté route centrale, entrée du club).
	Les terrains de la rangée du fond sont simplement tournés de 180° pour que leur
	entrée fasse toujours face à la route centrale.

	Pour modifier l'apparence : changer les valeurs ci-dessous puis relancer Play.
	Attention : les positions de Layout ont été choisies pour qu'aucune installation
	ne se chevauche, même au niveau 3. Si vous agrandissez une installation, vérifiez
	l'aperçu (node tools/world-preview.js) avant de valider.
]]

local WorldConfig = {}

--------------------------------------------------------------------------------
-- Démonstration
--------------------------------------------------------------------------------

-- Si true, le script World/WorldPreview.server.lua construit le quartier et les
-- 6 terrains avec des niveaux variés au lancement du jeu, MAIS seulement tant que
-- ServerScriptService.Server.Services.ClubService n'existe pas.
-- Passer à false pour désactiver complètement l'aperçu.
WorldConfig.PREVIEW_ON_START = true

--------------------------------------------------------------------------------
-- Installations et niveaux
--------------------------------------------------------------------------------

-- Identifiants des installations (contrat partagé avec BuildingService / ClubService).
WorldConfig.FACILITY_IDS = { "Pitch", "Stands", "LockerRoom", "Training", "Offices", "Shop", "Academy", "VIP" }

-- Noms affichés des installations : clés « building.<id>.label » de Locale.

-- Nombre de niveaux visuels par installation (doit suivre Buildings.lua).
WorldConfig.MAX_LEVEL = 5

-- Niveaux de départ d'un nouveau club (GDD §7 : stade 1, entraînement 1…).
WorldConfig.START_LEVELS = {
	Pitch = 1,
	Stands = 1,
	LockerRoom = 1,
	Training = 1,
	Offices = 1,
	Shop = 1,
	Academy = 1,
	VIP = 1,
}

-- Capacité des tribunes par niveau (mêmes valeurs que Buildings.lua, utilisées par l'économie).
WorldConfig.STANDS_CAPACITY = {
	[1] = 200,
	[2] = 500,
	[3] = 1000,
	[4] = 1600,
	[5] = 2500,
}

--------------------------------------------------------------------------------
-- Quartier sportif partagé (District)
--------------------------------------------------------------------------------

WorldConfig.MAX_PLOTS = 6

-- Taille d'un terrain de club (X = largeur, Z = profondeur).
WorldConfig.PLOT_SIZE = Vector2.new(260, 200)

-- Espace entre deux terrains voisins d'une même rangée.
WorldConfig.PLOT_GAP = 20

-- Largeur du couloir central entre les deux rangées (route + trottoirs + place).
WorldConfig.CORRIDOR_WIDTH = 100

-- Largeur de la chaussée centrale et des trottoirs.
WorldConfig.ROAD_WIDTH = 24
WorldConfig.SIDEWALK_WIDTH = 10

-- Place centrale (carrée) avec le point d'apparition commun.
WorldConfig.PLAZA_SIZE = 90
WorldConfig.SPAWN_SIZE = 12

-- Marge de sol autour des terrains.
WorldConfig.DISTRICT_MARGIN = 40

-- Nom des objets créés dans Workspace.
WorldConfig.DISTRICT_NAME = "District"
WorldConfig.PLOT_NAME_PREFIX = "Plot"

-- Centre de chaque emplacement (X, Z) dans le monde + orientation.
-- Rangée avant (1 à 3) : Z négatif, tournée de 180° pour faire face à la route.
-- Rangée arrière (4 à 6) : Z positif, orientation normale.
local rowOffset = WorldConfig.CORRIDOR_WIDTH / 2 + WorldConfig.PLOT_SIZE.Y / 2 -- 150
local colStep = WorldConfig.PLOT_SIZE.X + WorldConfig.PLOT_GAP -- 280

WorldConfig.SLOTS = {
	{ x = -colStep, z = -rowOffset, yaw = 180 },
	{ x = 0, z = -rowOffset, yaw = 180 },
	{ x = colStep, z = -rowOffset, yaw = 180 },
	{ x = -colStep, z = rowOffset, yaw = 0 },
	{ x = 0, z = rowOffset, yaw = 0 },
	{ x = colStep, z = rowOffset, yaw = 0 },
}

-- Mode Création (Campus.lua) : zone de parcelles DERRIÈRE chaque terrain (+Z local),
-- de z = PLOT_SIZE.Y / 2 à z = PLOT_SIZE.Y / 2 + CAMPUS_DEPTH.
WorldConfig.CAMPUS_DEPTH = 176

-- Taille totale du sol du quartier (terrains + zones de création des deux rangées).
WorldConfig.DISTRICT_SIZE = Vector2.new(
	3 * WorldConfig.PLOT_SIZE.X + 2 * WorldConfig.PLOT_GAP + 2 * WorldConfig.DISTRICT_MARGIN, -- 900
	2 * (WorldConfig.PLOT_SIZE.Y + WorldConfig.CAMPUS_DEPTH) + WorldConfig.CORRIDOR_WIDTH + 2 * WorldConfig.DISTRICT_MARGIN -- 932
)

-- Renvoie le CFrame (centre au sol, orientation) de l'emplacement slotIndex (1 à 6).
function WorldConfig.getPlotCFrame(slotIndex: number): CFrame
	local slot = WorldConfig.SLOTS[slotIndex]
	assert(slot, "WorldConfig.getPlotCFrame : emplacement invalide " .. tostring(slotIndex))
	return CFrame.new(slot.x, 0, slot.z) * CFrame.Angles(0, math.rad(slot.yaw), 0)
end

--------------------------------------------------------------------------------
-- Disposition d'un terrain de club (coordonnées locales X, Z du centre)
--------------------------------------------------------------------------------

-- Terrain de football (surface de jeu, lignes comprises) : 100 × 64 studs.
WorldConfig.PITCH_SIZE = Vector2.new(100, 64)
-- Bande d'herbe entre les lignes et les tribunes.
WorldConfig.PITCH_RUNOFF = 7
-- Nombre de bandes de tonte (alternance de deux verts).
WorldConfig.PITCH_STRIPES = 10

-- Tribunes : profondeur et hauteur d'un rang.
WorldConfig.STAND_ROW_DEPTH = 2.5
WorldConfig.STAND_ROW_RISE = 1.5

-- Centres et empreintes au sol (X, Z) de chaque installation, au niveau max.
-- (L'empreinte sert à l'aperçu et à vérifier qu'il n'y a aucun chevauchement.)
WorldConfig.LAYOUT = {
	-- Le stade (terrain + tribunes) partage le même centre.
	Pitch = { x = -40, z = 10, footprint = Vector2.new(130, 104) }, -- pylônes et écrans d'angle compris
	Stands = { x = -40, z = 10, footprint = Vector2.new(158, 138) }, -- niveau 5 et toits compris
	LockerRoom = { x = 78, z = -18, footprint = Vector2.new(40, 26) }, -- débord du toit compris
	-- Zone d'entraînement : terrain 60 × 44 (TRAINING_FIELD) + centre de performance
	-- du niveau 5 à l'arrière (+Z) ; l'empreinte reste centrée sur le terrain.
	Training = { x = 88, z = 40, footprint = Vector2.new(60, 72) },
	Offices = { x = 82, z = -70, footprint = Vector2.new(44, 26) }, -- toit, auvent, aileron compris
	Shop = { x = -62, z = -74, footprint = Vector2.new(42, 22) }, -- boutique, à gauche de l'entrée
	Academy = { x = -107, z = -74, footprint = Vector2.new(40, 22) }, -- centre de formation, à gauche de la boutique
	VIP = { x = 30, z = -72, footprint = Vector2.new(30, 22) }, -- espace VIP, à droite de l'entrée, face au stade
	Entrance = { x = 0, z = -96, footprint = Vector2.new(30, 4) },
	-- Salle des trophées (toujours présente), entre la boutique et l'allée d'entrée.
	TrophyRoom = { x = -23, z = -73, footprint = Vector2.new(26, 20) },
	-- Statue achetée (Cosmetics), à droite de l'allée, devant l'espace VIP.
	Statue = { x = 10, z = -74, footprint = Vector2.new(7, 7) },
}

-- Aménagement paysager (World/Landscape.lua), en coordonnées locales du terrain.
-- Lampadaires, bancs et drapeaux : Vector3(x, z, orientation en degrés).
-- Les arbres laissent la place aux décorations achetables (Prestige.buildDecor) :
-- massifs de fleurs (z = 91), fontaine (95, 89), palmiers (x = ±125).
local trees = {}
for _, x in { -120, -104, -88, -72, -56, -40, -24, -8, 8, 24, 40, 56, 72, 120 } do
	table.insert(trees, Vector2.new(x, 95))
end
for _, z in { -55, -25, 5, 35, 65 } do
	table.insert(trees, Vector2.new(-124, z))
end
WorldConfig.LANDSCAPE = {
	hedges = {
		{ Vector2.new(-128, -84), Vector2.new(-128, 98) },
		{ Vector2.new(128, -84), Vector2.new(128, 98) },
		-- Haie du fond ouverte en x = 50 : passage vers la zone du mode Création.
		{ Vector2.new(-127, 98), Vector2.new(45, 98) },
		{ Vector2.new(55, 98), Vector2.new(127, 98) },
	},
	trees = trees,
	lamps = {
		Vector3.new(46, -60, 90),
		Vector3.new(46, -12, 90),
		Vector3.new(46, 36, 90),
		Vector3.new(-85, -92.5, 0),
		Vector3.new(-42, -92.5, 0),
		Vector3.new(55, -92.5, 0),
		Vector3.new(105, -92.5, 0),
		Vector3.new(120, -60, -90),
	},
	flags = { Vector3.new(-21, -95, 180), Vector3.new(-17, -95, 180), Vector3.new(17, -95, 0), Vector3.new(21, -95, 0) },
	benches = { Vector3.new(-80, 84, 180), Vector3.new(-20, 84, 180), Vector3.new(40, 84, 180) },
	parking = { center = Vector2.new(111, -43), size = Vector2.new(20, 20) },
}

-- Parcelles du mode Création : grille de 4 colonnes × 3 rangées derrière le terrain.
-- Chaque parcelle fait PARCEL_SIZE ; un bâtiment tient dans CAMPUS_FOOTPRINT (carré :
-- il peut être tourné dans les 4 sens). Boulevard de 10 studs côté club, allées de 6.
WorldConfig.PARCEL_SIZE = Vector2.new(56, 50)
WorldConfig.CAMPUS_FOOTPRINT = Vector2.new(46, 46)
WorldConfig.CAMPUS_BOULEVARD = 10
WorldConfig.PARCELS = {}
do
	local back = WorldConfig.PLOT_SIZE.Y / 2
	for row = 1, 3 do
		for col = 1, 4 do
			table.insert(WorldConfig.PARCELS, {
				x = -93 + (col - 1) * 62,
				z = back + WorldConfig.CAMPUS_BOULEVARD + WorldConfig.PARCEL_SIZE.Y / 2 + (row - 1) * (WorldConfig.PARCEL_SIZE.Y + 6),
			})
		end
	end
end

-- Taille du terrain de la zone d'entraînement (clôture du niveau 3), centré sur LAYOUT.Training.
WorldConfig.TRAINING_FIELD = Vector2.new(60, 44)

-- Point d'arrivée du joueur sur son terrain (juste derrière le portique d'entrée).
WorldConfig.PLOT_SPAWN = Vector3.new(0, 3, -86)

-- Hauteur du dessus du sol du terrain de club (au-dessus du sol du quartier).
WorldConfig.PLOT_GROUND_TOP = 0.2

--------------------------------------------------------------------------------
-- Palette de couleurs (style semi-réaliste, moderne)
--------------------------------------------------------------------------------

WorldConfig.COLORS = {
	-- Sols
	DistrictGrass = Color3.fromRGB(86, 128, 66),
	PlotGrass = Color3.fromRGB(96, 140, 72),
	PitchGrassLight = Color3.fromRGB(88, 163, 74),
	PitchGrassDark = Color3.fromRGB(70, 140, 60),
	Asphalt = Color3.fromRGB(58, 60, 66),
	Sidewalk = Color3.fromRGB(190, 186, 178),
	Paving = Color3.fromRGB(214, 206, 190),
	Curb = Color3.fromRGB(230, 230, 230),
	Path = Color3.fromRGB(200, 196, 188),

	-- Marquages
	Line = Color3.fromRGB(245, 245, 245),
	RoadMarking = Color3.fromRGB(240, 220, 120),

	-- Matériaux de construction
	Wood = Color3.fromRGB(150, 110, 70),
	WoodDark = Color3.fromRGB(110, 78, 50),
	Concrete = Color3.fromRGB(176, 176, 172),
	ConcreteDark = Color3.fromRGB(128, 128, 126),
	Metal = Color3.fromRGB(160, 164, 170),
	MetalDark = Color3.fromRGB(70, 74, 80),
	Glass = Color3.fromRGB(150, 200, 230),
	Brick = Color3.fromRGB(170, 96, 72),
	Plaster = Color3.fromRGB(236, 232, 222),
	Roof = Color3.fromRGB(64, 68, 76),
	Door = Color3.fromRGB(92, 64, 44),

	-- Équipement
	GoalNet = Color3.fromRGB(240, 240, 240),
	Cone = Color3.fromRGB(255, 140, 30),
	Mannequin = Color3.fromRGB(40, 90, 200),
	AdBoard = Color3.fromRGB(30, 34, 44),
	LightHead = Color3.fromRGB(255, 250, 225),
	Water = Color3.fromRGB(80, 150, 200),
	SignText = Color3.fromRGB(255, 255, 255),
	SignBack = Color3.fromRGB(24, 30, 40),
	Gold = Color3.fromRGB(212, 175, 55),
	Carpet = Color3.fromRGB(170, 24, 40),

	-- Direction artistique « noir et or » (bâtiments haut de gamme).
	Charcoal = Color3.fromRGB(44, 46, 52),
	Graphite = Color3.fromRGB(64, 67, 74),
}

-- Couleurs de club par emplacement (fictives) : principale + secondaire.
-- Utilisées pour les sièges, le portique, l'écusson, les bancs.
WorldConfig.CLUB_COLORS = {
	{ primary = Color3.fromRGB(200, 40, 50), secondary = Color3.fromRGB(245, 245, 245) }, -- rouge / blanc
	{ primary = Color3.fromRGB(30, 80, 180), secondary = Color3.fromRGB(250, 210, 40) }, -- bleu / jaune
	{ primary = Color3.fromRGB(30, 140, 80), secondary = Color3.fromRGB(245, 245, 245) }, -- vert / blanc
	{ primary = Color3.fromRGB(110, 40, 150), secondary = Color3.fromRGB(240, 170, 40) }, -- violet / orange
	{ primary = Color3.fromRGB(20, 20, 24), secondary = Color3.fromRGB(240, 200, 60) }, -- noir / or
	{ primary = Color3.fromRGB(40, 170, 210), secondary = Color3.fromRGB(20, 40, 90) }, -- ciel / marine
}

-- Textes des panneaux publicitaires (tous fictifs, aucune marque réelle).
-- Clés Locale des textes (« FC COINS » reste tel quel dans toutes les langues).
WorldConfig.AD_TEXTS = {
	"FC COINS",
	"world.ad.yourAdHere",
	"world.ad.bakery",
	"world.ad.drivingSchool",
	"world.ad.cheer",
	"world.ad.chipShop",
}

-- Nom affiché quand aucun nom de club n'est fourni.
WorldConfig.DEFAULT_CLUB_NAME = "Club Amateur"

return WorldConfig
