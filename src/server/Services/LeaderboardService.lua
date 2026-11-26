--[[
	LeaderboardService
	Classement mondial entre tous les serveurs (shared/Leaderboard.lua).

	- Écritures : les scores des joueurs présents sont envoyés dans des
	  OrderedDataStore, seulement s'ils ont changé, au plus une fois toutes les
	  Leaderboard.WRITE_INTERVAL secondes, et au départ du joueur.
	- Lectures : le serveur lit le haut de chaque tableau toutes les
	  Leaderboard.REFRESH_INTERVAL secondes et l'envoie à tous les joueurs
	  (LeaderboardUpdated). Les noms viennent de Roblox (UserService), en une
	  seule requête groupée, puis restent en cache.
	- Budgets : avant chaque requête, le serveur vérifie qu'il reste une marge
	  (Leaderboard.MIN_BUDGET) ; sinon il attend le tour suivant.
	- Sans DataStore (Studio sans accès aux API) : classement des clubs de ce
	  serveur seulement (scope = "server").
	- Panneau 3D sur la place centrale : top 10, un tableau après l'autre.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Leaderboard = require(Shared.Leaderboard)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local WorldConfig = require(Shared.WorldConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)

local LeaderboardService = {}

local stores = {} -- [nom] = OrderedDataStore
local storesAvailable = true
local written = {} -- [UserId] = { [nom du DataStore] = score écrit }
local lastWriteAt = {} -- [UserId] = os.clock() de la dernière écriture
local names = {} -- [UserId] = nom affiché (cache)
local clubNames = {} -- [UserId] = nom du club vu sur ce serveur
local cache = { scope = "global", boards = {}, updatedAt = 0 }
local refreshing = false
local boardModel = nil
local boardIndex = 1

-- Points d'accès à Roblox (remplaçables par les tests) -----------------------

function LeaderboardService.GetStore(name: string)
	if not storesAvailable then
		return nil
	end
	local store = stores[name]
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok or not result then
		storesAvailable = false
		return nil
	end
	stores[name] = result
	return result
end

-- Requêtes encore permises (math.huge si Roblox ne le dit pas).
function LeaderboardService.Budget(kind: string): number
	local ok, value = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType[kind])
	end)
	if ok and type(value) == "number" then
		return value
	end
	return math.huge
end

local function hasBudget(kind: string): boolean
	return LeaderboardService.Budget(kind) > Leaderboard.MIN_BUDGET
end

-- Noms Roblox, en une requête groupée (le reste du cache est réutilisé).
function LeaderboardService.FetchNames(userIds: { number })
	local result = {}
	local ok, infos = pcall(function()
		return game:GetService("UserService"):GetUserInfosByUserIdsAsync(userIds)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				result[info.Id] = info.DisplayName or info.Username
			end
		end
	end
	return result
end

-- Profils --------------------------------------------------------------------

local function usesStore(player: Player): boolean
	local profile = PlayerDataService.Get(player)
	return profile ~= nil and not profile.temporary and storesAvailable
end

local function rememberPlayer(player: Player, data)
	names[player.UserId] = player.DisplayName ~= "" and player.DisplayName or player.Name
	if data and type(data.club.name) == "string" then
		clubNames[player.UserId] = data.club.name
	end
end

-- Scores qui ont changé depuis la dernière écriture : { { name, score } }.
local function pendingWrites(player: Player, data)
	local now = os.time()
	local mine = written[player.UserId] or {}
	written[player.UserId] = mine
	local list = {}
	for _, board in Leaderboard.BOARDS do
		local score = Leaderboard.Score(board, data, now)
		local name = Leaderboard.StoreName(board, now)
		if mine[name] ~= score and (score > 0 or mine[name] ~= nil) then
			table.insert(list, { name = name, score = score })
		end
	end
	return list, mine
end

local function write(userId: number, list, mine): number
	local count = 0
	for _, entry in list do
		if not hasBudget("SetIncrementSortedAsync") then
			break
		end
		local store = LeaderboardService.GetStore(entry.name)
		if not store then
			break
		end
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), entry.score)
		end)
		if ok then
			mine[entry.name] = entry.score
			count += 1
		else
			warn("[Leaderboard] Score non enregistré : " .. tostring(err))
		end
	end
	return count
end

-- Écrit les scores qui ont changé. force = sans attendre l'intervalle.
-- background = écritures lancées à part (départ : la sauvegarde du profil
-- ne doit pas attendre le classement). Renvoie le nombre d'écritures faites.
function LeaderboardService.Flush(player: Player, force: boolean?, background: boolean?): number
	local data = PlayerDataService.GetData(player)
	if not data or not usesStore(player) then
		return 0
	end
	local userId = player.UserId
	if not force and lastWriteAt[userId] and os.clock() - lastWriteAt[userId] < Leaderboard.WRITE_INTERVAL then
		return 0
	end
	rememberPlayer(player, data)
	lastWriteAt[userId] = os.clock()
	local list, mine = pendingWrites(player, data)
	if #list == 0 then
		return 0
	end
	if background then
		task.spawn(write, userId, list, mine)
		return #list
	end
	return write(userId, list, mine)
end

-- Lectures -------------------------------------------------------------------

-- Haut d'un tableau : liste de { userId, score }, ou nil en cas d'échec.
local function readTop(board: string, now: number)
	if not hasBudget("GetSortedAsync") then
		return nil
	end
	local store = LeaderboardService.GetStore(Leaderboard.StoreName(board, now))
	if not store then
		return nil
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, Leaderboard.TOP):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		warn("[Leaderboard] Lecture impossible : " .. tostring(page))
		return nil
	end
	local rows = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		local score = tonumber(entry.value)
		if userId and score and score > 0 then
			table.insert(rows, { userId = math.floor(userId), score = math.floor(score) })
		end
	end
	return rows
end

-- Sans DataStore : clubs de ce serveur.
local function localTop(board: string, now: number)
	local rows = {}
	for _, player in PlayerDataService.GetLoadedPlayers() do
		local data = PlayerDataService.GetData(player)
		if data then
			rememberPlayer(player, data)
			local score = Leaderboard.Score(board, data, now)
			if score > 0 then
				table.insert(rows, { userId = player.UserId, score = score })
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	while #rows > Leaderboard.TOP do
		table.remove(rows)
	end
	return rows
end

local function anyPlayerUsesStore(): boolean
	for _, player in PlayerDataService.GetLoadedPlayers() do
		if usesStore(player) then
			return true
		end
	end
	return false
end

local function decorate(rows)
	local missing = {}
	for _, row in rows do
		if not names[row.userId] then
			table.insert(missing, row.userId)
		end
	end
	if #missing > 0 then
		for userId, name in LeaderboardService.FetchNames(missing) do
			names[userId] = name
		end
	end
	for rank, row in rows do
		row.rank = rank
		row.name = names[row.userId] or ("#" .. row.userId)
		row.club = clubNames[row.userId]
	end
	return rows
end

local function updateBoard3D() end -- défini plus bas

-- Relit les tableaux et les envoie à tout le monde.
function LeaderboardService.Refresh()
	if refreshing then
		return
	end
	refreshing = true
	local ok, err = pcall(function()
		local now = os.time()
		local global = anyPlayerUsesStore()
		local boards = {}
		for _, board in Leaderboard.BOARDS do
			local rows
			if global then
				rows = readTop(board, now)
				if rows then
					rows = decorate(rows)
				else
					-- Lecture refusée (budget, panne) : on garde l'ancien tableau.
					rows = if cache.scope == "global" then cache.boards[board] or {} else {}
				end
			else
				rows = decorate(localTop(board, now))
			end
			boards[board] = rows
		end
		cache = { scope = if global then "global" else "server", boards = boards, updatedAt = now }
	end)
	refreshing = false
	if not ok then
		warn("[Leaderboard] Rafraîchissement impossible : " .. tostring(err))
		return
	end
	Net.FireAllClients("LeaderboardUpdated", LeaderboardService.GetState())
	for _, player in PlayerDataService.GetLoadedPlayers() do
		PlayerDataService.MarkChanged(player)
	end
	updateBoard3D()
end

function LeaderboardService.GetState()
	local boards = {}
	for board, rows in cache.boards do
		local list = {}
		for index = 1, math.min(#rows, Leaderboard.SHOWN) do
			local row = rows[index]
			list[index] = { rank = row.rank, userId = row.userId, name = row.name, club = row.club, score = row.score }
		end
		boards[board] = list
	end
	return { scope = cache.scope, boards = boards, updatedAt = cache.updatedAt }
end

-- Champ de l'instantané : scores du joueur et sa place s'il est dans le haut.
function LeaderboardService.Snapshot(player: Player, data)
	local now = os.time()
	local out = { scores = {}, ranks = {} }
	for _, board in Leaderboard.BOARDS do
		out.scores[board] = Leaderboard.Score(board, data, now)
		for _, row in cache.boards[board] or {} do
			if row.userId == player.UserId then
				out.ranks[board] = row.rank
				break
			end
		end
	end
	return out
end

-- Panneau 3D -----------------------------------------------------------------

local function newLabel(parent: Instance, name: string, y: number, height: number, size: number, color: Color3)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 20, 0, y)
	text.Size = UDim2.new(1, -40, 0, height)
	text.Font = Enum.Font.GothamBold
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	text.Parent = parent
	return text
end

function LeaderboardService.BuildBoard()
	if boardModel and boardModel.Parent then
		return boardModel
	end
	local model = Instance.new("Model")
	model.Name = "GlobalLeaderboard"
	local base = Leaderboard.BOARD_POSITION
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(base + offset)
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local metal = Color3.fromRGB(45, 48, 56)
	part("PostLeft", Vector3.new(0.8, 16, 0.8), Vector3.new(-9, 8, 0), metal, Enum.Material.Metal)
	part("PostRight", Vector3.new(0.8, 16, 0.8), Vector3.new(9, 8, 0), metal, Enum.Material.Metal)
	local panel = part("Panel", Vector3.new(18, 11, 0.6), Vector3.new(0, 10, 0), Color3.fromRGB(18, 28, 40), Enum.Material.SmoothPlastic)
	model.PrimaryPart = panel

	-- Face +Z : tournée vers le point d'apparition (centre de la place).
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local title = newLabel(gui, "Title", 14, 60, 48, Color3.fromRGB(255, 205, 60))
	title.TextXAlignment = Enum.TextXAlignment.Center
	Locale.Tag(title, "leaderboard.boardTitle")
	local subtitle = newLabel(gui, "Subtitle", 76, 36, 30, Color3.fromRGB(170, 190, 210))
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	for index = 1, Leaderboard.BOARD_ROWS do
		newLabel(gui, "Row" .. index, 118 + (index - 1) * 31, 30, 26, Color3.fromRGB(235, 240, 245))
	end

	local district = workspace:FindFirstChild(WorldConfig.DISTRICT_NAME)
	model.Parent = district or workspace
	boardModel = model
	return model
end

updateBoard3D = function()
	local model = boardModel
	if not model or not model.Parent then
		return
	end
	local gui = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Screen")
	if not gui then
		return
	end
	local board = Leaderboard.BOARDS[boardIndex]
	Locale.Tag(
		gui.Subtitle,
		if cache.scope == "global" then "leaderboard.tab." .. board else "leaderboard.boardServer",
		{ board = Locale.T(Locale.DEFAULT, "leaderboard.tab." .. board) }
	)
	local rows = cache.boards[board] or {}
	for index = 1, Leaderboard.BOARD_ROWS do
		local text = gui:FindFirstChild("Row" .. index)
		local row = rows[index]
		if text then
			if row then
				local key, params = Leaderboard.ValueText(board, row.score)
				params.rank = index
				params.name = row.club or row.name
				Locale.Tag(text, key .. "Row", params)
			else
				Locale.Untag(text)
				text.Text = if index == 1 then "—" else ""
			end
		end
	end
end

function LeaderboardService.ShowBoard(index: number)
	boardIndex = ((index - 1) % #Leaderboard.BOARDS) + 1
	updateBoard3D()
end

function LeaderboardService.GetBoardModel()
	return boardModel
end

-- Cycle de vie ---------------------------------------------------------------

function LeaderboardService.OnPlayerReady(player: Player)
	rememberPlayer(player, PlayerDataService.GetData(player))
	Net.FireClient("LeaderboardUpdated", player, LeaderboardService.GetState())
end

function LeaderboardService.OnPlayerLeaving(player: Player)
	LeaderboardService.Flush(player, true, true)
	written[player.UserId] = nil
	lastWriteAt[player.UserId] = nil
end

function LeaderboardService.Init()
	PlayerDataService.AddSnapshotField("leaderboard", LeaderboardService.Snapshot)
	local ok, err = pcall(LeaderboardService.BuildBoard)
	if not ok then
		warn("[Leaderboard] Panneau 3D impossible : " .. tostring(err))
	end
	updateBoard3D()
	-- Écritures : chaque joueur à son rythme (au plus une fois par intervalle).
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local done, problem = pcall(LeaderboardService.Flush, player)
				if not done then
					warn("[Leaderboard] " .. tostring(problem))
				end
			end
		end
	end)
	-- Lectures.
	task.delay(Leaderboard.FIRST_REFRESH, function()
		while true do
			LeaderboardService.Refresh()
			task.wait(Leaderboard.REFRESH_INTERVAL)
		end
	end)
	-- Panneau 3D : un tableau après l'autre.
	task.spawn(function()
		while true do
			task.wait(Leaderboard.ROTATE_SECONDS)
			LeaderboardService.ShowBoard(boardIndex + 1)
		end
	end)
	-- Fermeture du serveur : dernières écritures (sans délai).
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			pcall(LeaderboardService.Flush, player, true)
		end
	end)
end

return LeaderboardService
