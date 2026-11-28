--!strict
--[[
	WorldBuilder — point d'entrée de la construction du monde.

	API (contrat avec ClubService / BuildingService) :

	  WorldBuilder.buildDistrict(parent: Instance?): Model
	      Construit le quartier partagé (sol, route, place, SpawnLocation,
	      emplacements numérotés) et, à côté, le centre-ville (Model « City »,
	      World/Downtown.lua). Parent par défaut : Workspace.
	      Idempotent : si le quartier existe déjà, il est renvoyé tel quel.

	  WorldBuilder.buildPlot(slotIndex: number, levels: Levels?, clubName: string?): Model
	      Construit le terrain de club n° slotIndex (1 à 6) dans Workspace,
	      sous le nom « Plot<slotIndex> ». DÉTRUIT d'abord l'ancien modèle du même
	      emplacement s'il existe. levels = { Pitch = 1, Stands = 2, … } ; toute
	      clé absente vaut 1, les valeurs sont bornées entre 1 et MAX_LEVEL.
	      Forme alternative acceptée : buildPlot(slotIndex, { clubName = "…", levels = {…} }).

	  WorldBuilder.buildPlot(slotIndex, levels, clubName, style: Style?)
	      style (facultatif) = personnalisation et trophées du club :
	      { colors, lighting, statue, kit = id d'objet de Cosmetics, decor = { [id] = true },
	        trophies = Trophies.Earned(...), titles = nombre de titres de D1 }.
	      Sans style : couleurs de l'emplacement et salle des trophées vide.

	  WorldBuilder.setFacilityLevel(plot: Model, facilityId: string, level: number): Model?
	      Détruit puis reconstruit UNIQUEMENT l'installation indiquée.

	  WorldBuilder.setClubName(plot: Model, clubName: string)
	      Met à jour les textes portant le nom du club (portique, bureaux niv.3, prompt).

	  WorldBuilder.getPlot(slotIndex) / WorldBuilder.destroyPlot(slotIndex)

	Structure d'un terrain (Model « PlotN ») :
	  Attributes : SlotIndex, ClubName, Level_Pitch, Level_Stands, …
	  PrimaryPart : « Ground » (sol du terrain).
	  « Spawn » : Part invisible, sans collision, juste derrière l'entrée (téléportation).
	  Enfants installations : Pitch, Stands, LockerRoom, Training, Offices, Shop, Academy, VIP
	  (+ Entrance, Paths, TrophyRoom, Landscape, Campus, et selon le style Statue et Decor).
	  « Campus » = zone du mode Création derrière le terrain (CampusZone.lua). Chaque installation est un Model avec les Attributes
	  Facility et Level et une PrimaryPart invisible « Root » (son empreinte au sol).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Brand = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Brand"))
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))
local World = script.Parent
local PartUtil = require(World:WaitForChild("PartUtil"))
local District = require(World:WaitForChild("District"))
local Pitch = require(World:WaitForChild("Pitch"))
local Stands = require(World:WaitForChild("Stands"))
local LockerRoom = require(World:WaitForChild("LockerRoom"))
local TrainingZone = require(World:WaitForChild("TrainingZone"))
local Offices = require(World:WaitForChild("Offices"))
local Shop = require(World:WaitForChild("Shop"))
local Academy = require(World:WaitForChild("Academy"))
local VipLounge = require(World:WaitForChild("VipLounge"))
local Entrance = require(World:WaitForChild("Entrance"))
local Prestige = require(World:WaitForChild("Prestige"))
local Landscape = require(World:WaitForChild("Landscape"))
local CampusZone = require(World:WaitForChild("CampusZone"))
local Downtown = require(World:WaitForChild("Downtown"))
local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cosmetics"))
local ClubIdentity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClubIdentity"))

type BuildContext = PartUtil.BuildContext
export type Levels = { [string]: number }
export type Style = {
	colors: string?,
	lighting: string?,
	statue: string?,
	kit: string?,
	decor: { [string]: any }?,
	trophies: { any }?,
	titles: number?,
	-- Identité choisie (ClubIdentity.Choices) : couleurs, motif, écusson.
	identity: { primary: Color3?, secondary: Color3?, pattern: string?, crest: number? }?,
	campus: any?, -- mode Création : data.campus (parcelles et bâtiments placés)
}
type FacilityBuilder = (parent: Instance, origin: CFrame, level: number, ctx: BuildContext) -> Model

local WorldBuilder = {}

-- Association identifiant d'installation -> fonction de construction.
local BUILDERS: { [string]: FacilityBuilder } = {
	Pitch = Pitch.build,
	Stands = Stands.build,
	LockerRoom = LockerRoom.build,
	Training = TrainingZone.build,
	Offices = Offices.build,
	Shop = Shop.build,
	Academy = Academy.build,
	VIP = VipLounge.build,
}

local C = WorldConfig.COLORS

--------------------------------------------------------------------------------
-- Outils internes
--------------------------------------------------------------------------------

local function clampLevel(value: any): number
	local n = tonumber(value)
	if n == nil then
		return 1
	end
	return math.clamp(math.floor(n), 1, WorldConfig.MAX_LEVEL)
end

-- Complète et borne la table des niveaux (clé absente = 1).
local function normalizeLevels(levels: Levels?): Levels
	local result: Levels = {}
	for _, id in WorldConfig.FACILITY_IDS do
		result[id] = clampLevel(if levels then levels[id] else nil)
	end
	return result
end

local function plotName(slotIndex: number): string
	return WorldConfig.PLOT_NAME_PREFIX .. tostring(slotIndex)
end

-- Objet de Cosmetics, seulement s'il appartient bien à la catégorie attendue.
local function cosmetic(id: any, category: string): any
	local item = Cosmetics.Get(id)
	if item and item.category == category then
		return item
	end
	return nil
end

-- Couleurs du club : palette achetée (attribut « Colors »), sinon identité
-- choisie (attributs ClubPrimary / ClubSecondary / Crest / Pattern), sinon
-- couleurs de l'emplacement (voir ClubIdentity.ResolveColors).
local function makeContext(slotIndex: number, clubName: string, colorsId: any, identity: any): BuildContext
	identity = identity or {}
	local primary, secondary = ClubIdentity.ResolveColors(slotIndex, cosmetic(colorsId, "colors"), identity)
	return {
		slotIndex = slotIndex,
		clubName = clubName,
		primary = primary,
		secondary = secondary,
		crest = if ClubIdentity.ValidCrest(identity.crest) then identity.crest else nil,
		pattern = if ClubIdentity.Pattern(identity.pattern) then identity.pattern else nil,
	}
end

-- Identité relue sur un terrain déjà construit (reconstruction d'une installation).
local function identityFromPlot(plot: Model)
	local function color(name: string): Color3?
		local value = plot:GetAttribute(name)
		return if typeof(value) == "Color3" then value else nil
	end
	return {
		primary = color("IdentityPrimary"),
		secondary = color("IdentitySecondary"),
		crest = plot:GetAttribute("Crest"),
		pattern = plot:GetAttribute("Pattern"),
	}
end

-- CFrame d'origine d'une installation (centre, posé sur le sol du terrain).
local function facilityOrigin(slotIndex: number, layoutKey: string): CFrame
	local layout = WorldConfig.LAYOUT[layoutKey]
	return WorldConfig.getPlotCFrame(slotIndex) * CFrame.new(layout.x, WorldConfig.PLOT_GROUND_TOP, layout.z)
end

local function buildFacility(plot: Model, slotIndex: number, facilityId: string, level: number, ctx: BuildContext): Model
	local builder = BUILDERS[facilityId]
	local model = builder(plot, facilityOrigin(slotIndex, facilityId), level, ctx)
	model.Name = facilityId
	plot:SetAttribute("Level_" .. facilityId, level)
	return model
end

-- Sol du terrain, allées internes et point d'arrivée « Spawn ».
local function buildGround(plot: Model, slotIndex: number)
	local origin = WorldConfig.getPlotCFrame(slotIndex)
	local size = WorldConfig.PLOT_SIZE
	local top = WorldConfig.PLOT_GROUND_TOP

	local ground = PartUtil.box(
		plot,
		origin,
		"Ground",
		Vector3.new(size.X, 0.4, size.Y),
		Vector3.new(0, top - 0.2, 0),
		C.PlotGrass,
		Enum.Material.Grass
	)
	plot.PrimaryPart = ground

	-- Allées (coordonnées locales du terrain, voir WorldConfig.LAYOUT).
	local paths = PartUtil.model(plot, "Paths")
	local function path(x1: number, z1: number, x2: number, z2: number, width: number)
		local length = math.max(math.abs(x2 - x1), math.abs(z2 - z1))
		local alongX = math.abs(x2 - x1) > math.abs(z2 - z1)
		local sizeV = if alongX then Vector3.new(length, 0.08, width) else Vector3.new(width, 0.08, length)
		PartUtil.block(
			paths,
			origin,
			"Path",
			sizeV,
			Vector3.new((x1 + x2) / 2, top, (z1 + z2) / 2),
			C.Path,
			Enum.Material.Pavement,
			{ castShadow = false }
		)
	end
	local half = size.Y / 2
	path(0, -half, 0, -29, 10) -- entrée -> bord du terrain (passe sous les tribunes sud)
	path(5, -88, 100, -88, 6) -- allée des bureaux
	path(82, -85, 82, -80, 6) -- porte des bureaux
	path(50, -85, 50, 43, 6) -- allée latérale (vestiaires, entraînement)
	path(53, -30, 78, -30, 4) -- porte des vestiaires
	path(53, 40, 58, 40, 4) -- accès entraînement
	path(-5, -88, -62, -88, 6) -- allée de la boutique
	path(-62, -86, -62, -84, 4) -- porte de la boutique
	path(-62, -88, -107, -88, 6) -- allée du centre de formation
	path(-107, -88, -107, -85, 4) -- porte du centre de formation
	path(30, -88, 30, -83, 4) -- porte de l'espace VIP
	path(-23, -88, -23, -79, 4) -- porte de la salle des trophées
	path(111, -85, 111, -53, 5) -- accès au parking
	path(50, 43, 50, 100, 6) -- vers la zone du mode Création (derrière le terrain)

	local spawn = PartUtil.box(
		plot,
		origin,
		"Spawn",
		Vector3.new(6, 1, 6),
		WorldConfig.PLOT_SPAWN,
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ canCollide = false, transparency = 1, castShadow = false }
	)
	spawn.CanQuery = false
	spawn.CanTouch = false
end

-- Salle des trophées, statue, décorations, éclairage et tenue (purement visuels).
local function buildPrestige(plot: Model, slotIndex: number, look: Style, ctx: BuildContext)
	local kit = ClubIdentity.ResolveKit(cosmetic(look.kit, "kit"), ctx.primary, ctx.secondary, ctx.pattern)
	Prestige.buildTrophyRoom(plot, facilityOrigin(slotIndex, "TrophyRoom"), look.trophies or {}, look.titles or 0, kit, ctx)
	local statue = cosmetic(look.statue, "statue")
	if statue then
		Prestige.buildStatue(plot, facilityOrigin(slotIndex, "Statue"), statue, ctx)
	end
	local decor = {}
	for id in look.decor or {} do
		if cosmetic(id, "decor") then
			decor[id] = true
		end
	end
	Prestige.buildDecor(plot, WorldConfig.getPlotCFrame(slotIndex), decor, ctx)
	local lighting = cosmetic(look.lighting, "lighting")
	if lighting then
		Prestige.applyLighting(plot, if lighting.club then ctx.primary else lighting.color)
	end
	Prestige.applyKit(plot, kit)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function WorldBuilder.buildDistrict(parent: Instance?): Model
	local target: Instance = parent or Workspace
	local existing = target:FindFirstChild(WorldConfig.DISTRICT_NAME)
	if existing and existing:IsA("Model") then
		return existing
	end
	local district = District.build(target)
	-- Centre-ville commerçant à l'est du quartier (concessionnaire, hôtel, banque…).
	-- Une erreur ici ne doit jamais empêcher les clubs de s'installer.
	local ok, err = pcall(Downtown.build, target)
	if not ok then
		warn("[World] Centre-ville non construit : " .. tostring(err))
	end
	return district
end

function WorldBuilder.getPlot(slotIndex: number): Model?
	local existing = Workspace:FindFirstChild(plotName(slotIndex))
	if existing and existing:IsA("Model") then
		return existing
	end
	return nil
end

function WorldBuilder.destroyPlot(slotIndex: number)
	local existing = Workspace:FindFirstChild(plotName(slotIndex))
	if existing then
		existing:Destroy()
	end
end

function WorldBuilder.buildPlot(slotIndex: number, levelsOrOptions: { [string]: any }?, clubName: string?, style: Style?): Model
	assert(
		typeof(slotIndex) == "number" and WorldConfig.SLOTS[slotIndex] ~= nil,
		"WorldBuilder.buildPlot : slotIndex doit être entre 1 et " .. WorldConfig.MAX_PLOTS
	)

	-- Accepte buildPlot(i, levels, nom) ou buildPlot(i, { levels = …, clubName = … }).
	local levels: Levels? = levelsOrOptions :: any
	local name = clubName
	if levelsOrOptions and (typeof(levelsOrOptions.levels) == "table" or typeof(levelsOrOptions.clubName) == "string") then
		levels = levelsOrOptions.levels
		name = name or levelsOrOptions.clubName
		style = style or levelsOrOptions.style
	end
	local look: Style = style or {}
	local finalName: string = if name and name ~= "" then name else WorldConfig.DEFAULT_CLUB_NAME
	local finalLevels = normalizeLevels(levels)

	WorldBuilder.destroyPlot(slotIndex)

	-- On assemble le modèle hors du Workspace, puis on le publie d'un coup (réplication plus légère).
	local plot = PartUtil.model(nil, plotName(slotIndex), {
		SlotIndex = slotIndex,
		ClubName = finalName,
		Colors = if cosmetic(look.colors, "colors") then look.colors else nil,
	})
	local identity = look.identity or {}
	local ctx = makeContext(slotIndex, finalName, look.colors, identity)
	-- Identité gardée sur le terrain (reconstruction d'une installation, tests).
	plot:SetAttribute("IdentityPrimary", identity.primary)
	plot:SetAttribute("IdentitySecondary", identity.secondary)
	plot:SetAttribute("Crest", ctx.crest)
	plot:SetAttribute("Pattern", ctx.pattern)
	plot:SetAttribute("ClubPrimary", ctx.primary)
	plot:SetAttribute("ClubSecondary", ctx.secondary)

	buildGround(plot, slotIndex)
	Landscape.build(plot, WorldConfig.getPlotCFrame(slotIndex) * CFrame.new(0, WorldConfig.PLOT_GROUND_TOP, 0), ctx)
	Entrance.build(plot, facilityOrigin(slotIndex, "Entrance"), ctx)
	for _, id in WorldConfig.FACILITY_IDS do
		buildFacility(plot, slotIndex, id, finalLevels[id], ctx)
	end
	buildPrestige(plot, slotIndex, look, ctx)
	CampusZone.build(plot, WorldConfig.getPlotCFrame(slotIndex), look.campus, ctx, { trophies = look.trophies or {}, titles = look.titles or 0 })

	plot.Parent = Workspace
	return plot
end

function WorldBuilder.setFacilityLevel(plot: Model, facilityId: string, level: number): Model?
	if BUILDERS[facilityId] == nil then
		warn("WorldBuilder.setFacilityLevel : installation inconnue " .. tostring(facilityId))
		return nil
	end
	local slotIndex = plot:GetAttribute("SlotIndex")
	if typeof(slotIndex) ~= "number" then
		warn("WorldBuilder.setFacilityLevel : le Model n'est pas un terrain (attribut SlotIndex manquant)")
		return nil
	end
	local clubName = plot:GetAttribute("ClubName")
	local ctx = makeContext(slotIndex, if typeof(clubName) == "string" then clubName else WorldConfig.DEFAULT_CLUB_NAME, plot:GetAttribute("Colors"), identityFromPlot(plot))

	local old = plot:FindFirstChild(facilityId)
	if old then
		old:Destroy()
	end
	return buildFacility(plot, slotIndex, facilityId, clampLevel(level), ctx)
end

function WorldBuilder.setClubName(plot: Model, clubName: string)
	plot:SetAttribute("ClubName", clubName)
	for _, descendant in plot:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant.Name == "ClubNameText" then
			descendant.Text = string.upper(clubName)
		elseif descendant:IsA("TextLabel") and descendant.Name == "ClubTagText" then
			descendant.Text = Brand.Tag(clubName)
		elseif descendant:IsA("ProximityPrompt") and descendant.Name == "ManageClubPrompt" then
			descendant.ObjectText = clubName
		end
	end
end

-- Nombre de Parts d'un modèle (suivi du budget mobile).
WorldBuilder.countParts = PartUtil.countParts

return WorldBuilder
