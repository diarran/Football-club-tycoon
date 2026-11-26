--[[
	AdminService
	Code secret « argent illimité », réservé à l'administrateur du jeu.

	- Le joueur tape le code dans Paramètres ; le serveur vérifie TOUT :
	  administrateur (AdminAccess.IsAdmin) ET code juste (empreinte SHA-256).
	- Réponse identique pour un code faux et pour un joueur non admin :
	  aucune information n'est donnée à un tricheur.
	- Après plusieurs codes faux, le joueur est bloqué un moment.
	- Le même code active puis désactive le mode illimité. À la
	  désactivation, le solde d'avant l'activation est rendu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local AdminAccess = require(script.Parent.Parent.Admin.AdminAccess)
local AdminConfig = require(script.Parent.Parent.Admin.AdminConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

local AdminService = {}

local attempts = {} -- [Player] = { failures = n, lockedUntil = os.time() }

local function notify(player: Player, key: string, kind: string)
	Net.FireClient("Notify", player, Locale.TP(player, key), kind)
end

-- Renvoie "on", "off", "invalid" ou "locked".
function AdminService.SubmitCode(player: Player, code: any): string
	local state = attempts[player]
	if not state then
		state = { failures = 0, lockedUntil = 0 }
		attempts[player] = state
	end
	if os.time() < state.lockedUntil then
		return "locked"
	end

	local valid = type(code) == "string"
		and #code <= AdminConfig.MAX_CODE_LENGTH
		and AdminAccess.IsAdmin(player)
		and AdminAccess.CheckCode(code)
	local data = PlayerDataService.GetData(player)
	if not valid or not data then
		state.failures += 1
		if state.failures >= AdminConfig.MAX_ATTEMPTS then
			state.failures = 0
			state.lockedUntil = os.time() + AdminConfig.LOCK_SECONDS
			warn(("[Admin] %s bloqué après trop de codes faux"):format(player.Name))
		end
		return "invalid"
	end

	state.failures = 0
	local admin = data.admin
	if admin.unlimited then
		admin.unlimited = false
		data.coins = math.clamp(math.floor(admin.savedCoins), 0, Config.MAX_COINS)
		admin.savedCoins = 0
	else
		admin.unlimited = true
		admin.savedCoins = data.coins
		data.coins = Config.MAX_COINS
	end
	PlayerDataService.MarkChanged(player)
	print(("[Admin] Mode illimité %s pour %s"):format(if admin.unlimited then "activé" else "désactivé", player.Name))
	return if admin.unlimited then "on" else "off"
end

function AdminService.Init()
	Net.Handle("RequestAdminCode", function(player, code)
		local result = AdminService.SubmitCode(player, code)
		if result == "on" then
			notify(player, "admin.unlimitedOn", "success")
		elseif result == "off" then
			notify(player, "admin.unlimitedOff", "info")
		elseif result == "locked" then
			notify(player, "admin.locked", "error")
		else
			notify(player, "admin.invalid", "error")
		end
	end)
end

function AdminService.OnPlayerLeaving(player: Player)
	attempts[player] = nil
end

return AdminService
