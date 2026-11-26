--[[
	Net
	Point unique pour les RemoteEvents / RemoteFunctions.

	- Le serveur crée les remotes au démarrage (Net.Setup()).
	- Le client les récupère avec Net.Get(nom).
	- Côté serveur, Net.Handle(nom, fonction) branche un gestionnaire protégé :
	  limitation de fréquence par joueur et erreurs isolées (pcall).

	Règle d'or : le client ne fait que DEMANDER. Le serveur vérifie tout
	(types, limites, coûts, permissions) avant d'agir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Net = {}

-- Client -> serveur (demandes d'action)
Net.Requests = {
	"RequestUpgrade", -- (buildingId: string)
	"RequestRecruit", -- ()
	"RequestMatch", -- (opponentId: string, tactic: string)
	"RequestRename", -- (newName: string)
	"RequestTutorialStep", -- (stepId: string) étapes purement informatives (menu ouvert…)
}

-- Serveur -> client (notifications)
Net.Events = {
	"ProfileUpdated", -- (snapshot) état complet du club du joueur
	"ClubsUpdated", -- (list) clubs présents sur le serveur
	"MatchResult", -- (result)
	"Notify", -- (message: string, kind: string)
}

-- Requêtes avec réponse (RemoteFunction)
Net.Functions = {
	"GetSnapshot", -- () -> snapshot
}

local FOLDER_NAME = "Remotes"

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup ne s'appelle que côté serveur")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local function ensure(className, name)
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in Net.Requests do
		ensure("RemoteEvent", name)
	end
	for _, name in Net.Events do
		ensure("RemoteEvent", name)
	end
	for _, name in Net.Functions do
		ensure("RemoteFunction", name)
	end
end

function Net.Get(name: string)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

-- Limitation de fréquence (serveur uniquement) ----------------------------
local buckets = {} -- [player][remoteName] = { windowStart, count }

local function allow(player: Player, name: string): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[name]
	if not bucket or now - bucket.windowStart >= Config.RATE_LIMIT_WINDOW_SECONDS then
		perPlayer[name] = { windowStart = now, count = 1 }
		return true
	end
	bucket.count += 1
	return bucket.count <= Config.RATE_LIMIT_MAX_REQUESTS
end

function Net.ForgetPlayer(player: Player)
	buckets[player] = nil
end

-- Branche un gestionnaire sur une demande client -> serveur.
function Net.Handle(name: string, handler: (Player, ...any) -> ())
	assert(RunService:IsServer(), "Net.Handle ne s'appelle que côté serveur")
	Net.Get(name).OnServerEvent:Connect(function(player, ...)
		if not allow(player, name) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[Net] Erreur dans %s pour %s : %s"):format(name, player.Name, tostring(err)))
		end
	end)
end

-- Branche une RemoteFunction côté serveur.
function Net.HandleFunction(name: string, handler: (Player, ...any) -> any)
	assert(RunService:IsServer(), "Net.HandleFunction ne s'appelle que côté serveur")
	Net.Get(name).OnServerInvoke = function(player, ...)
		if not allow(player, name) then
			return nil
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(("[Net] Erreur dans %s pour %s : %s"):format(name, player.Name, tostring(result)))
			return nil
		end
		return result
	end
end

function Net.FireClient(name: string, player: Player, ...)
	Net.Get(name):FireClient(player, ...)
end

function Net.FireAllClients(name: string, ...)
	Net.Get(name):FireAllClients(...)
end

return Net
