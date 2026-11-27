--[[
	harness.luau — banc de test des services serveur, hors de Roblox Studio.

	Assemblé par tests/run-tests.js APRÈS tools/roblox-mock.luau (fausse API de
	base : Instance, Vector3, CFrame…) et AVANT les modules du jeu. Il ajoute :

	- une horloge et un ordonnanceur simulés (os.time, os.clock, task.*) ;
	- Players, DataStoreService (en mémoire), RunService, HttpService, TextService ;
	- des RemoteEvent / RemoteFunction qui enregistrent ce que le serveur envoie ;
	- de petites fonctions de test : H.test, H.eq, H.ok…

	Variable fournie par le fichier assemblé : mock.
]]

local H = {}
local realOs = os
local realPrint = print
H.realPrint = realPrint -- sortie directe (rapports du simulateur)

------------------------------------------------------------------ journal
-- Les print/warn du jeu sont gardés en mémoire et affichés seulement en cas d'échec.
H.logs = {}
H.warnings = {}
local function log(kind: string, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local line = table.concat(parts, " ")
	table.insert(H.logs, kind .. " " .. line)
	if kind == "[warn]" then
		table.insert(H.warnings, line)
	end
end
H.print = function(...)
	log("[print]", ...)
end
H.warn = function(...)
	log("[warn]", ...)
end

------------------------------------------------------------------ horloge et tâches
local EPOCH = 1_750_000_000
local now = 0.0 -- secondes écoulées depuis le début du test
H.os = setmetatable({
	time = function()
		return EPOCH + math.floor(now)
	end,
	clock = function()
		return now
	end,
}, { __index = realOs })

local sleeping = {} -- { co, wake }
local deferred = {} -- { co, args }
H.errors = {} -- erreurs survenues dans des tâches (gestionnaires, boucles…)

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(H.errors, tostring(err))
		log("[error]", err)
	end
end

local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(seconds: number?, fn, ...)
	local co = coroutine.create(fn)
	local args = table.pack(...)
	table.insert(sleeping, { co = co, wake = now + (seconds or 0), args = args })
	return co
end

local function runDeferred()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		assert(guard < 10000, "boucle infinie de task.defer")
		local item = table.remove(deferred, 1)
		resume(item.co, table.unpack(item.args, 1, item.args.n))
	end
end

-- Avance l'horloge et réveille les tâches dont l'heure est venue.
function H.advance(seconds: number)
	local target = now + seconds
	runDeferred()
	while true do
		local bestIndex, best = nil, nil
		for index, item in sleeping do
			if item.wake <= target and (not best or item.wake < best.wake) then
				bestIndex, best = index, item
			end
		end
		if not best then
			break
		end
		table.remove(sleeping, bestIndex)
		now = math.max(now, best.wake)
		if best.args then
			resume(best.co, table.unpack(best.args, 1, best.args.n))
		else
			resume(best.co, now - best.started)
		end
		runDeferred()
	end
	now = target
end

-- Termine le travail en attente « dans la même image » (task.defer).
function H.flush()
	H.advance(0)
end

function task.wait(seconds: number?)
	seconds = math.max(seconds or 0, 1 / 60)
	if coroutine.isyieldable() then
		table.insert(sleeping, { co = coroutine.running(), wake = now + seconds, started = now })
		return coroutine.yield()
	end
	-- Thread principal du test : on fait simplement avancer le temps.
	H.advance(seconds)
	return seconds
end
H.task = task

------------------------------------------------------------------ Random (rejouable)
local Random = {}
Random.__index = Random
function Random.new(_seed: number?)
	return setmetatable({}, Random)
end
function Random:NextInteger(a: number, b: number): number
	return math.random(a, b)
end
function Random:NextNumber(a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + math.random() * (hi - lo)
end
H.Random = Random

------------------------------------------------------------------ signaux
local Signal = {}
Signal.__index = Signal
-- queueWhenEmpty : comme OnClientEvent dans Roblox, les messages reçus avant
-- le premier Connect sont gardés puis livrés à la connexion.
function H.newSignal(queueWhenEmpty: boolean?)
	return setmetatable({ handlers = {}, queue = if queueWhenEmpty then {} else nil }, Signal)
end
function Signal:Connect(fn)
	local entry = { fn = fn }
	table.insert(self.handlers, entry)
	if self.queue and #self.queue > 0 then
		local pending = self.queue
		self.queue = {}
		for _, args in pending do
			task.spawn(fn, table.unpack(args, 1, args.n))
		end
	end
	return {
		Connected = true,
		Disconnect = function()
			local index = table.find(self.handlers, entry)
			if index then
				table.remove(self.handlers, index)
			end
		end,
	}
end
function Signal:Fire(...)
	if self.queue and #self.handlers == 0 then
		table.insert(self.queue, table.pack(...))
		return
	end
	for _, entry in table.clone(self.handlers) do
		task.spawn(entry.fn, ...)
	end
end

------------------------------------------------------------------ données sérialisables
-- Imite les règles de Roblox (RemoteEvent / DataStore) : pas de fonction, pas de
-- table mixte (tableau + clés texte), clés texte ou entières uniquement.
local function checkSerializable(value, path: string, forDataStore: boolean)
	local kind = type(value)
	if kind == "function" or kind == "thread" or kind == "userdata" then
		error(("valeur non transmissible (%s) à %s"):format(kind, path), 0)
	end
	if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
		if forDataStore then
			error(("nombre invalide (%s) à %s"):format(tostring(value), path), 0)
		end
	end
	if kind ~= "table" then
		return
	end
	if getmetatable(value) ~= nil then
		if forDataStore then
			error(("objet Roblox non sauvegardable à %s"):format(path), 0)
		end
		return -- Instance : autorisée dans un RemoteEvent
	end
	local hasArray, hasString = false, false
	for key, child in value do
		if type(key) == "string" then
			hasString = true
		elseif type(key) == "number" and key == math.floor(key) and key >= 1 then
			hasArray = true
		else
			error(("clé invalide (%s) à %s"):format(tostring(key), path), 0)
		end
		checkSerializable(child, path .. "." .. tostring(key), forDataStore)
	end
	if hasArray and hasString then
		error(("table mixte (tableau + clés texte) à %s"):format(path), 0)
	end
	if hasArray and #value == 0 then
		error(("tableau à trous à %s"):format(path), 0)
	end
end
H.checkSerializable = checkSerializable

local function deepCopy(value)
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end
H.deepCopy = deepCopy

------------------------------------------------------------------ Instances spécialisées
local env = mock.env
local game = env.game
env.UDim2.fromOffset = env.UDim2.fromOffset or function(x, y)
	return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
end
local baseNew = env.Instance.new

H.sent = {} -- [player] = { { name, args } }
H.broadcasts = {} -- { { name, args } }

local GUI_CLASSES = {
	ScreenGui = true, Frame = true, ScrollingFrame = true, TextLabel = true, TextButton = true,
	TextBox = true, ImageLabel = true, ImageButton = true, BillboardGui = true, SurfaceGui = true,
	Camera = true,
}
local GUI_EVENTS = { "Activated", "MouseButton1Click", "MouseEnter", "MouseLeave", "FocusLost", "InputBegan", "Changed" }

local function newInstance(className: string)
	local inst = baseNew(className)
	if className == "RemoteEvent" then
		inst.OnServerEvent = H.newSignal()
		inst.OnClientEvent = H.newSignal(true)
		local function toClient(self, player, args)
			if player == H.localPlayer then
				local copy = deepCopy(args)
				self.OnClientEvent:Fire(table.unpack(copy, 1, copy.n))
			end
		end
		inst.FireClient = function(self, player, ...)
			local args = table.pack(...)
			for i = 1, args.n do
				checkSerializable(args[i], self.Name .. "[" .. i .. "]", false)
			end
			H.sent[player] = H.sent[player] or {}
			table.insert(H.sent[player], { name = self.Name, args = deepCopy(args) })
			toClient(self, player, args)
		end
		inst.FireAllClients = function(self, ...)
			local args = table.pack(...)
			for i = 1, args.n do
				checkSerializable(args[i], self.Name .. "[" .. i .. "]", false)
			end
			table.insert(H.broadcasts, { name = self.Name, args = deepCopy(args) })
			for _, player in H.Players:GetPlayers() do
				H.sent[player] = H.sent[player] or {}
				table.insert(H.sent[player], { name = self.Name, args = deepCopy(args) })
			end
			toClient(self, H.localPlayer, args)
		end
		-- Côté client (H.localPlayer) : la demande part vers le serveur, copiée.
		inst.FireServer = function(self, ...)
			local args = deepCopy(table.pack(...))
			self.OnServerEvent:Fire(H.localPlayer, table.unpack(args, 1, args.n))
		end
	elseif className == "RemoteFunction" then
		inst.InvokeServer = function(self, ...)
			assert(self.OnServerInvoke, "OnServerInvoke absent pour " .. self.Name)
			return deepCopy(self.OnServerInvoke(H.localPlayer, ...))
		end
	elseif GUI_CLASSES[className] then
		for _, eventName in GUI_EVENTS do
			inst[eventName] = H.newSignal()
		end
		local changed = {}
		inst.GetPropertyChangedSignal = function(_self, prop)
			changed[prop] = changed[prop] or H.newSignal()
			return changed[prop]
		end
	elseif className == "Model" then
		inst.PivotTo = function(self, cf)
			self._pivot = cf
		end
	elseif className == "Sound" then
		inst.SoundId = ""
		inst.IsPlaying = false
		inst.Volume = 0.5
		inst.Play = function(self)
			self.IsPlaying = true
			H.soundLog[#H.soundLog + 1] = self.Name
		end
		inst.Stop = function(self)
			self.IsPlaying = false
		end
		inst.Pause = function(self)
			self.IsPlaying = false
		end
		inst.Resume = function(self)
			self.IsPlaying = true
		end
	elseif className == "ParticleEmitter" then
		inst.Emit = function(self, count)
			H.emitted[self] = (H.emitted[self] or 0) + count
		end
	end
	return inst
end
H.Instance = { new = newInstance }

------------------------------------------------------------------ services
game.JobId = "serveur-test-A"
local closeHandlers = {}
game.BindToClose = function(_self, fn)
	table.insert(closeHandlers, fn)
end

local RunService = game:GetService("RunService")
H.studio = false
RunService.IsServer = function()
	return true
end
RunService.IsClient = function()
	return false
end
RunService.IsStudio = function()
	return H.studio
end
-- Signal image par image : les tests l'envoient à la main (H.frames).
RunService.Heartbeat = H.newSignal()
function H.frames(count: number, dt: number?)
	for _ = 1, count do
		RunService.Heartbeat:Fire(dt or 1 / 30)
	end
	H.flush()
end

local guid = 0
game:GetService("HttpService").GenerateGUID = function(_self, _braces)
	guid += 1
	return "guid-" .. guid
end

-- Filtrage de texte : tout mot contenant « interdit » est remplacé par des #.
H.filterFails = false
game:GetService("TextService").FilterStringAsync = function(_self, text, _userId, _context)
	if H.filterFails then
		error("Filtrage indisponible")
	end
	return {
		GetNonChatStringForBroadcastAsync = function()
			return (text:gsub("%w*interdit%w*", function(word)
				return string.rep("#", #word)
			end))
		end,
	}
end

-- DataStore en mémoire. Les valeurs sont copiées à l'entrée et à la sortie, comme
-- si elles passaient par le réseau, et vérifiées comme le fait Roblox.
H.datastoreAvailable = true
H.stores = {} -- [nom] = { data = {}, failNext = 0, writes = 0 }
local function getStore(name: string)
	local s = H.stores[name]
	if not s then
		s = { data = {}, failNext = 0, writes = 0 }
		H.stores[name] = s
	end
	return s
end
H.getStore = getStore
H.datastoreLatency = 0 -- secondes d'attente simulées pour chaque requête
local function maybeFail(s)
	if H.datastoreLatency > 0 and coroutine.isyieldable() then
		task.wait(H.datastoreLatency)
	end
	if s.failNext > 0 then
		s.failNext -= 1
		error("502: API Services rejected request (simulé)", 0)
	end
end
game:GetService("DataStoreService").GetDataStore = function(_self, name)
	if not H.datastoreAvailable then
		error("You must publish this place to the web to access DataStore.", 0)
	end
	local s = getStore(name)
	return {
		GetAsync = function(_, key)
			maybeFail(s)
			return deepCopy(s.data[key])
		end,
		SetAsync = function(_, key, value)
			maybeFail(s)
			checkSerializable(value, key, true)
			s.data[key] = deepCopy(value)
			s.writes += 1
		end,
		UpdateAsync = function(_, key, transform)
			maybeFail(s)
			local result = transform(deepCopy(s.data[key]))
			if result == nil then
				return nil -- mise à jour annulée
			end
			checkSerializable(result, key, true)
			s.data[key] = deepCopy(result)
			s.writes += 1
			return deepCopy(result)
		end,
	}
end

-- DataStore ordonné en mémoire (classement mondial) : entiers seulement,
-- tri décroissant ou croissant, une page de pageSize lignes.
H.orderedStores = {} -- [nom] = { data = {}, failNext = 0, writes = 0, reads = 0 }
H.requestBudget = {} -- [type de requête] = nombre (absent = illimité)
local function getOrdered(name: string)
	local s = H.orderedStores[name]
	if not s then
		s = { data = {}, failNext = 0, writes = 0, reads = 0 }
		H.orderedStores[name] = s
	end
	return s
end
H.getOrderedStore = getOrdered
game:GetService("DataStoreService").GetOrderedDataStore = function(_self, name)
	if not H.datastoreAvailable then
		error("You must publish this place to the web to access DataStore.", 0)
	end
	local s = getOrdered(name)
	return {
		SetAsync = function(_, key, value)
			maybeFail(s)
			assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore : entier attendu")
			s.data[key] = value
			s.writes += 1
		end,
		GetAsync = function(_, key)
			maybeFail(s)
			return s.data[key]
		end,
		GetSortedAsync = function(_, ascending, pageSize)
			maybeFail(s)
			s.reads += 1
			assert(pageSize >= 1 and pageSize <= 100, "pageSize entre 1 et 100")
			local list = {}
			for key, value in s.data do
				table.insert(list, { key = key, value = value })
			end
			table.sort(list, function(a, b)
				if a.value ~= b.value then
					return if ascending then a.value < b.value else a.value > b.value
				end
				return a.key < b.key
			end)
			local page = {}
			for i = 1, math.min(pageSize, #list) do
				page[i] = list[i]
			end
			return { GetCurrentPage = function()
				return page
			end, IsFinished = true }
		end,
	}
end
game:GetService("DataStoreService").GetRequestBudgetForRequestType = function(_self, requestType)
	local name = if type(requestType) == "table" then requestType.Name else tostring(requestType)
	return H.requestBudget[name] or 1000
end
-- Noms Roblox (UserService) : « Pseudo<id> ». H.userInfoCalls compte les requêtes.
H.userInfoCalls = 0
game:GetService("UserService").GetUserInfosByUserIdsAsync = function(_self, ids)
	H.userInfoCalls += 1
	local out = {}
	for _, id in ids do
		table.insert(out, { Id = id, Username = "user" .. id, DisplayName = "Pseudo" .. id })
	end
	return out
end

-- Joueurs.
local Players = game:GetService("Players")
H.Players = Players
Players.PlayerAdded = H.newSignal()
Players.PlayerRemoving = H.newSignal()
Players.GetPlayers = function(self)
	local list = {}
	for _, child in self:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end
Players.GetPlayerByUserId = function(self, userId)
	for _, player in self:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

-- Déconnexion : PlayerRemoving puis retrait du joueur (comme Roblox).
function H.leave(player)
	if player.Parent ~= Players then
		return
	end
	Players.PlayerRemoving:Fire(player)
	player.Parent = nil
	H.flush()
end

-- Connexion d'un joueur (PlayerAdded, puis chargement du profil).
-- localeId : langue du compte Roblox (par défaut "fr-fr" : les tests vérifient les textes français).
function H.join(userId: number, name: string?, localeId: string?)
	local player = baseNew("Player")
	player.LocaleId = localeId or "fr-fr"
	player.Name = name or ("Joueur" .. userId)
	player.DisplayName = player.Name
	player.UserId = userId
	player.CharacterAdded = H.newSignal()
	player.Kick = function(self, message)
		self.kickMessage = message or ""
		task.defer(H.leave, self)
	end
	player.Parent = Players
	Players.PlayerAdded:Fire(player)
	H.flush()
	return player
end

-- Fermeture du serveur (BindToClose).
function H.shutdown()
	for _, fn in closeHandlers do
		fn()
	end
	H.flush()
end

------------------------------------------------------------------ client (joueur local)
H.localPlayer = nil
local camera = newInstance("Camera")
camera.Name = "Camera"
camera.ViewportSize = env.Vector2.new(1280, 720)
camera.CFrame = env.CFrame.new()
camera.Parent = env.workspace
env.workspace.CurrentCamera = camera
env.workspace.DescendantAdded = env.workspace.DescendantAdded or H.newSignal()

-- Sons : une adresse « se charge » sauf si elle figure dans H.missingSounds.
H.soundLog = {} -- noms des Sound joués, dans l'ordre
H.emitted = {} -- [ParticleEmitter] = particules émises
H.missingSounds = {}
game:GetService("ContentProvider").PreloadAsync = function(_self, list, callback)
	for _, item in list do
		local id = item.SoundId or ""
		local okId = id ~= "" and not H.missingSounds[id]
		if callback then
			callback(id, if okId then env.Enum.AssetFetchStatus.Success else env.Enum.AssetFetchStatus.Failure)
		end
	end
end

-- Types de valeurs des effets (particules) : simples tables.
H.NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
H.NumberSequence = { new = function(v) return { value = v } end }
H.ColorSequence = { new = function(v) return { value = v } end }
H.ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }

H.TweenInfo = {
	new = function(...)
		return { args = table.pack(...) }
	end,
}
game:GetService("TweenService").Create = function(_self, target, _info, goals)
	return {
		Completed = H.newSignal(),
		Play = function(tween)
			for key, value in goals do
				target[key] = value -- l'animation est terminée tout de suite
			end
			tween.Completed:Fire(env.Enum.PlaybackState.Completed)
		end,
		Cancel = function() end,
	}
end

-- Démarre le vrai client (Main.client.lua) pour un joueur déjà connecté.
function H.startClient(modules, player)
	H.localPlayer = player
	H.Players.LocalPlayer = player
	-- Messages envoyés à ce joueur avant le démarrage du client : mis en attente
	-- comme le fait Roblox, puis livrés quand le client se branche.
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	for _, msg in H.sent[player] or {} do
		local r = remotes:FindFirstChild(msg.name)
		r.OnClientEvent:Fire(table.unpack(deepCopy(msg.args), 1, msg.args.n))
	end
	local playerGui = newInstance("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	task.spawn(mock.run, modules.Client_Main)
	H.flush()
	return playerGui
end

-- Cherche dans l'interface le premier élément dont le texte contient `prefix`.
function H.findText(root, prefix: string, className: string?)
	for _, d in root:GetDescendants() do
		local text = d.Text
		if type(text) == "string" and text:find(prefix, 1, true) and (not className or d.ClassName == className) then
			return d
		end
	end
	return nil
end

function H.click(root, prefix: string)
	local b = H.findText(root, prefix, "TextButton")
	assert(b, "bouton introuvable : " .. prefix)
	b.Activated:Fire()
	H.flush()
end

------------------------------------------------------------------ côté « client »
local function remote(name: string)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	assert(folder, "Remotes absents : Net.Setup n'a pas été appelé")
	local r = folder:FindFirstChild(name)
	assert(r, "Remote inconnu : " .. name)
	return r
end

-- Simule un client qui envoie une demande (les arguments sont copiés comme sur le réseau).
function H.fire(player, name: string, ...)
	local args = table.pack(...)
	remote(name).OnServerEvent:Fire(player, table.unpack(deepCopy(args), 1, args.n))
	H.flush()
end

function H.invoke(player, name: string, ...)
	local handler = remote(name).OnServerInvoke
	assert(handler, "Pas de OnServerInvoke pour " .. name)
	local result = handler(player, ...)
	H.flush()
	return deepCopy(result)
end

-- Messages reçus par un joueur, filtrés par nom de remote.
function H.received(player, name: string)
	local out = {}
	for _, msg in H.sent[player] or {} do
		if msg.name == name then
			table.insert(out, msg.args)
		end
	end
	return out
end

function H.lastNotify(player)
	local list = H.received(player, "Notify")
	local last = list[#list]
	return last and last[1], last and last[2]
end

function H.clearSent()
	table.clear(H.sent)
	table.clear(H.broadcasts)
end

------------------------------------------------------------------ assertions
local results = { passed = 0, failed = 0, failures = {} }
local currentTest = nil

local function describe(v): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function H.eq(actual, expected, label: string?)
	if actual ~= expected then
		error(("%s : attendu %s, obtenu %s"):format(label or "valeur", describe(expected), describe(actual)), 2)
	end
end

function H.ok(condition, label: string?)
	if not condition then
		error((label or "condition fausse"), 2)
	end
end

function H.test(name: string, fn)
	currentTest = name
	local errorsBefore = #H.errors
	local ok, err = pcall(fn)
	H.flush()
	if ok and #H.errors > errorsBefore then
		ok, err = false, "erreur dans une tâche du serveur : " .. H.errors[#H.errors]
	end
	if ok then
		results.passed += 1
		realPrint("  ✔ " .. name)
	else
		results.failed += 1
		table.insert(results.failures, name)
		realPrint("  ✘ " .. name)
		realPrint("      " .. tostring(err))
		local from = math.max(1, #H.logs - 15)
		for i = from, #H.logs do
			realPrint("      | " .. H.logs[i])
		end
	end
	currentTest = nil
end

function H.finish()
	realPrint(("@@RESULT %d %d"):format(results.passed, results.failed))
end

------------------------------------------------------------------ démarrage du serveur
-- Lance le vrai script serveur Main.server.lua (et WorldPreview, comme Roblox).
function H.boot(modules)
	task.spawn(mock.run, modules.WorldPreview)
	mock.run(modules.Main)
	H.flush()
	return {
		PlayerDataService = mock.run(modules.PlayerDataService),
		EconomyService = mock.run(modules.EconomyService),
		ClubService = mock.run(modules.ClubService),
		BuildingService = mock.run(modules.BuildingService),
		SquadService = mock.run(modules.SquadService),
		MatchService = mock.run(modules.MatchService),
		ChallengeService = mock.run(modules.ChallengeService),
		TournamentService = mock.run(modules.TournamentService),
		StaffService = mock.run(modules.StaffService),
		Staff = mock.run(modules.Staff),
		Sponsors = mock.run(modules.Sponsors),
		DailyService = mock.run(modules.DailyService),
		Daily = mock.run(modules.Daily),
		TutorialService = mock.run(modules.TutorialService),
		CosmeticService = mock.run(modules.CosmeticService),
		Cosmetics = mock.run(modules.Cosmetics),
		Trophies = mock.run(modules.Trophies),
		Config = mock.run(modules.Config),
		Buildings = mock.run(modules.Buildings),
		Divisions = mock.run(modules.Divisions),
		PlayerConfig = mock.run(modules.PlayerConfig),
		Training = mock.run(modules.Training),
		Onboarding = mock.run(modules.Onboarding),
		OnboardingService = mock.run(modules.OnboardingService),
	}
end

H.Players = Players
H.game = game
return H
