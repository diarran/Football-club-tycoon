--[[
	EconomyService
	Seul endroit qui modifie le solde de FC Coins.

	- Les montants viennent TOUJOURS de la configuration serveur, jamais du client.
	- TrySpend vérifie et débite en une seule opération sans pause (pas de yield),
	  donc deux demandes rapides ne peuvent pas débiter deux fois le même solde.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EconomyService = {}

local function isValidAmount(amount): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge
end

function EconomyService.Init() end

function EconomyService.GetBalance(player: Player): number
	local data = PlayerDataService.GetData(player)
	return data and data.coins or 0
end

function EconomyService.CanAfford(player: Player, amount: number): boolean
	return isValidAmount(amount) and EconomyService.GetBalance(player) >= amount
end

-- Ajoute des FC Coins. reason sert au suivi (équilibrage, détection d'abus).
function EconomyService.Add(player: Player, amount: number, reason: string): boolean
	local data = PlayerDataService.GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	amount = math.floor(amount)
	data.coins = math.min(data.coins + amount, Config.MAX_COINS)
	PlayerDataService.MarkChanged(player)
	print(("[Economy] +%d %s pour %s (%s)"):format(amount, Config.CURRENCY_NAME, player.Name, reason))
	return true
end

-- Débite si le solde suffit. Renvoie true si le débit a eu lieu.
function EconomyService.TrySpend(player: Player, amount: number, reason: string): boolean
	local data = PlayerDataService.GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	amount = math.floor(amount)
	if data.coins < amount then
		return false
	end
	data.coins -= amount
	PlayerDataService.MarkChanged(player)
	print(("[Economy] -%d %s pour %s (%s)"):format(amount, Config.CURRENCY_NAME, player.Name, reason))
	return true
end

return EconomyService
