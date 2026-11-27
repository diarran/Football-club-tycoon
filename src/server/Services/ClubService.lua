--[[
	ClubService
	Clubs présents sur le serveur : attribution des 6 terrains, nom du club,
	apparition du joueur sur son terrain et liste des clubs visitables.

	- Un joueur reçoit un seul terrain, sans doublon.
	- Visiter un club ne donne aucun droit dessus : toutes les actions ne
	  portent que sur le club du joueur qui les demande.
	- Si le module World/WorldBuilder existe (modèles du stade), il est utilisé
	  pour construire les terrains ; sinon des terrains simples sont créés.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local ClubNames = require(Shared.ClubNames)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Trophies = require(Shared.Trophies)
local PlayerDataService = require(script.Parent.PlayerDataService)

local ClubService = {}

local slots = {} -- [slotIndex] = Player
local slotByPlayer = {} -- [Player] = slotIndex
local plotModels = {} -- [slotIndex] = Model
local renaming = {} -- [Player] = true pendant un filtrage de nom
local rng = Random.new()

local WorldBuilder = nil

-- Terrains ---------------------------------------------------------------

local function slotPosition(slotIndex: number): Vector3
	local col = (slotIndex - 1) % Config.PLOT_COLUMNS
	local row = math.floor((slotIndex - 1) / Config.PLOT_COLUMNS)
	local size = Config.PLOT_SIZE
	local x = (col - (Config.PLOT_COLUMNS - 1) / 2) * (size.X + Config.PLOT_SPACING)
	local z = (row - 0.5) * (size.Z + Config.PLOT_SPACING)
	return Vector3.new(x, 0, z)
end

local function getPlotsFolder()
	local folder = workspace:FindFirstChild("Plots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Plots"
		folder.Parent = workspace
	end
	return folder
end

-- Terrain de secours, utilisé tant que WorldBuilder n'est pas disponible.
local function buildFallbackPlot(slotIndex: number, clubName: string?)
	local folder = getPlotsFolder()
	local existing = folder:FindFirstChild("Plot_" .. slotIndex)
	if existing then
		existing:Destroy()
	end

	local origin = slotPosition(slotIndex)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. slotIndex

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Config.PLOT_SIZE
	ground.Position = origin
	ground.Color = Color3.fromRGB(76, 140, 74)
	ground.Material = Enum.Material.Grass
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = model

	local spawnPart = Instance.new("Part")
	spawnPart.Name = "Spawn"
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.Transparency = 1
	spawnPart.Size = Vector3.new(6, 1, 6)
	spawnPart.Position = origin + Vector3.new(0, 1, Config.PLOT_SIZE.Z / 2 - 10)
	spawnPart.Parent = model

	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.Size = Vector3.new(12, 6, 1)
	sign.Position = origin + Vector3.new(0, 4, Config.PLOT_SIZE.Z / 2 - 2)
	sign.Color = Color3.fromRGB(30, 40, 60)
	sign.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 50)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 150
	billboard.Parent = sign
	local label = Instance.new("TextLabel")
	label.Name = "ClubName"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	if clubName then
		label.Text = clubName
	else
		Locale.Tag(label, "world.freePlot")
	end
	label.Parent = billboard

	model.PrimaryPart = ground
	model.Parent = folder
	return model
end

-- Personnalisation et trophées du club, lus par WorldBuilder (purement visuels).
local function styleOf(data)
	if not data then
		return nil
	end
	local equipped, owned = data.cosmetics.equipped, data.cosmetics.owned
	local decor = {}
	for id in owned do
		decor[id] = true
	end
	return {
		colors = equipped.colors,
		lighting = equipped.lighting,
		statue = equipped.statue,
		kit = equipped.kit,
		decor = decor, -- WorldBuilder ne garde que les décorations
		trophies = Trophies.Earned(data.club.division, data.club.stats, data.trophies.titles),
		titles = data.trophies.titles,
	}
end

local function buildPlot(slotIndex: number, levels, clubName: string?, data)
	levels = levels or Buildings.DefaultLevels() -- terrain libre : niveaux de départ
	local model
	if WorldBuilder then
		local ok, result = pcall(WorldBuilder.buildPlot, slotIndex, levels, clubName, styleOf(data))
		if ok and result then
			model = result
		else
			warn("[Club] WorldBuilder.buildPlot a échoué, terrain simple utilisé : " .. tostring(result))
		end
	end
	model = model or buildFallbackPlot(slotIndex, clubName)
	plotModels[slotIndex] = model
	return model
end

local function spawnCFrame(slotIndex: number): CFrame
	local model = plotModels[slotIndex]
	local spawnPart = model and model:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(slotPosition(slotIndex) + Vector3.new(0, 5, 0))
end

local function teleportToPlot(player: Player)
	local slotIndex = slotByPlayer[player]
	local character = player.Character
	if slotIndex and character then
		character:PivotTo(spawnCFrame(slotIndex))
	end
end

-- Liste des clubs -------------------------------------------------------

local function averageRating(squad): number
	if #squad == 0 then
		return 0
	end
	local total = 0
	for _, footballer in squad do
		total += footballer.rating
	end
	return math.floor(total / #squad + 0.5)
end

function ClubService.GetClubList()
	local list = {}
	for slotIndex, player in slots do
		local data = PlayerDataService.GetData(player)
		if data then
			table.insert(list, {
				id = "player:" .. player.UserId,
				ownerName = player.DisplayName,
				clubName = data.club.name,
				division = data.club.division,
				divisionPoints = data.club.divisionPoints,
				stats = table.clone(data.club.stats),
				rating = averageRating(data.squad),
				squadSize = #data.squad,
				tactic = data.tactic, -- dernier style joué (visible avant un match)
				slot = slotIndex,
				buildings = table.clone(data.buildings),
				trophies = #Trophies.Earned(data.club.division, data.club.stats, data.trophies.titles),
				titles = data.trophies.titles,
			})
		end
	end
	-- Classement : division la plus haute, puis points.
	table.sort(list, function(a, b)
		local da, db = Divisions.Get(a.division), Divisions.Get(b.division)
		if da.index ~= db.index then
			return da.index > db.index
		end
		return a.divisionPoints > b.divisionPoints
	end)
	return list
end

function ClubService.BroadcastClubs()
	Net.FireAllClients("ClubsUpdated", ClubService.GetClubList())
end

-- Joueurs ---------------------------------------------------------------

function ClubService.GetSlot(player: Player): number?
	return slotByPlayer[player]
end

-- Retrouve un joueur présent à partir d'un identifiant "player:<UserId>".
function ClubService.FindPlayerByClubId(clubId: string): Player?
	if type(clubId) ~= "string" then
		return nil
	end
	local userId = tonumber(clubId:match("^player:(%d+)$"))
	if not userId then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player and slotByPlayer[player] then
		return player
	end
	return nil
end

-- Reconstruit le terrain du joueur (après une amélioration, un renommage…).
function ClubService.RefreshPlot(player: Player)
	local slotIndex = slotByPlayer[player]
	local data = PlayerDataService.GetData(player)
	if slotIndex and data then
		buildPlot(slotIndex, data.buildings, data.club.name, data)
	end
end

function ClubService.OnPlayerReady(player: Player, profile)
	local data = profile.data
	if not data.club.name then
		data.club.name = ClubNames.Generate(rng)
	end

	-- Attribue le premier emplacement libre.
	local slotIndex = slotByPlayer[player]
	if not slotIndex then
		for index = 1, Config.MAX_CLUBS_PER_SERVER do
			if not slots[index] then
				slotIndex = index
				break
			end
		end
	end
	if not slotIndex then
		player:Kick(Locale.TP(player, "kick.serverFull", { max = Config.MAX_CLUBS_PER_SERVER }))
		return false
	end
	slots[slotIndex] = player
	slotByPlayer[player] = slotIndex
	player:SetAttribute("ClubSlot", slotIndex)
	player:SetAttribute("ClubName", data.club.name)

	buildPlot(slotIndex, data.buildings, data.club.name, data)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		-- Roblox place le personnage sur la SpawnLocation après CharacterAdded :
		-- on attend qu'il soit dans le Workspace, puis un court instant, sinon
		-- ce placement annule la téléportation (joueur bloqué sur la place).
		local deadline = os.clock() + 5
		while character.Parent == nil and os.clock() < deadline do
			task.wait(0.05)
		end
		task.wait(0.1)
		if player.Character == character then
			teleportToPlot(player)
		end
	end)
	if player.Character then
		teleportToPlot(player)
	end

	ClubService.BroadcastClubs()
	return true
end

function ClubService.OnPlayerLeaving(player: Player)
	local slotIndex = slotByPlayer[player]
	slotByPlayer[player] = nil
	renaming[player] = nil
	if slotIndex then
		slots[slotIndex] = nil
		buildPlot(slotIndex, nil, nil) -- remet un terrain libre
	end
	ClubService.BroadcastClubs()
end

-- Renommage -------------------------------------------------------------

local function filterName(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[Club] Filtrage du nom impossible : " .. tostring(result))
		return nil
	end
	return result
end

local function handleRename(player: Player, newName)
	-- Texte anormalement long (client modifié) : ignoré avant tout traitement.
	if type(newName) ~= "string" or #newName > 200 or renaming[player] then
		return
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	newName = newName:gsub("%s+", " "):match("^%s*(.-)%s*$")
	local length = utf8.len(newName)
	if not length or length < Config.CLUB_NAME_MIN_LENGTH or length > Config.CLUB_NAME_MAX_LENGTH then
		Net.FireClient(
			"Notify",
			player,
			Locale.TP(player, "club.nameLength", {
				min = Config.CLUB_NAME_MIN_LENGTH,
				max = Config.CLUB_NAME_MAX_LENGTH,
			}),
			"error"
		)
		return
	end

	renaming[player] = true
	local filtered = filterName(player, newName)
	renaming[player] = nil
	if not player.Parent then
		return
	end
	if not filtered or filtered ~= newName then
		Net.FireClient("Notify", player, Locale.TP(player, "club.nameRejected"), "error")
		return
	end

	data.club.name = filtered
	player:SetAttribute("ClubName", filtered)
	PlayerDataService.MarkChanged(player)
	ClubService.RefreshPlot(player)
	ClubService.BroadcastClubs()
	Net.FireClient("Notify", player, Locale.TP(player, "club.renamed", { name = filtered }), "success")
end

function ClubService.Init()
	local server = script.Parent.Parent
	local world = server:FindFirstChild("World")
	local builderModule = world and world:FindFirstChild("WorldBuilder")
	if builderModule then
		local ok, result = pcall(require, builderModule)
		if ok then
			WorldBuilder = result
		else
			warn("[Club] Impossible de charger WorldBuilder : " .. tostring(result))
		end
	end

	local districtBuilt = false
	if WorldBuilder and WorldBuilder.buildDistrict then
		local ok, err = pcall(WorldBuilder.buildDistrict)
		districtBuilt = ok
		if not ok then
			warn("[Club] WorldBuilder.buildDistrict a échoué : " .. tostring(err))
		end
	end
	if not districtBuilt and not workspace:FindFirstChild("DistrictGround") then
		-- Sol du quartier sportif de secours, pour ne pas tomber entre les terrains.
		local ground = Instance.new("Part")
		ground.Name = "DistrictGround"
		ground.Anchored = true
		ground.Size = Vector3.new(800, 2, 500)
		ground.Position = Vector3.new(0, -1.5, 0)
		ground.Color = Color3.fromRGB(120, 120, 125)
		ground.Material = Enum.Material.Concrete
		ground.Parent = workspace
	end

	-- Les 6 emplacements sont visibles dès le départ, même vides.
	for slotIndex = 1, Config.MAX_CLUBS_PER_SERVER do
		buildPlot(slotIndex, nil, nil)
	end

	Net.Handle("RequestRename", handleRename)
	-- Langue choisie dans les Paramètres : les messages du serveur la suivent.
	Net.Handle("RequestLanguage", function(player, lang)
		if Locale.IsSupported(lang) then
			player:SetAttribute("Language", lang)
		end
	end)
end

return ClubService
