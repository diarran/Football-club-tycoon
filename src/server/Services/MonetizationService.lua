--[[
	MonetizationService
	Achats facultatifs en Robux, validés par le serveur (document de
	conception, section 9). Uniquement de l'apparence ; le boost de revenus
	reste coupé tant que Monetization.BOOST_ENABLED vaut false.

	Déroulement :
	1. Le client DEMANDE un achat (RequestBuyExclusive, avec une clé). Le serveur
	   vérifie que le produit a un ID, qu'il est ouvert et pas déjà possédé,
	   puis ouvre la fenêtre d'achat Roblox.
	2. Roblox appelle ProcessReceipt après le paiement. C'est le SEUL endroit
	   qui accorde un achat, quelle que soit la demande du client.

	Un reçu = un seul octroi :
	- chaque PurchaseId accordé est noté dans le profil (data.purchases.receipts) ;
	- on ne répond « accordé » (PurchaseGranted) à Roblox qu'après avoir écrit
	  le profil dans le DataStore. Si la sauvegarde échoue, on répond « pas
	  encore » (NotProcessedYet) : Roblox renverra le même reçu plus tard (même
	  sur un autre serveur, à la reconnexion), et le reçu déjà noté empêche
	  un second octroi ;
	- joueur absent ou profil pas encore chargé : « pas encore », rien n'est perdu.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local Locale = require(Shared.Locale)
local Monetization = require(Shared.Monetization)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local CosmeticService = require(script.Parent.CosmeticService)
local ClubService = require(script.Parent.ClubService)

local MonetizationService = {}

local Decision = Enum.ProductPurchaseDecision

-- Garde au plus Monetization.RECEIPTS_KEPT reçus (les plus récents).
local function pruneReceipts(purchases)
	local list = {}
	for id, at in purchases.receipts do
		table.insert(list, { id = id, at = if type(at) == "number" then at else 0 })
	end
	if #list <= Monetization.RECEIPTS_KEPT then
		return
	end
	table.sort(list, function(a, b)
		return a.at > b.at
	end)
	for i = Monetization.RECEIPTS_KEPT + 1, #list do
		purchases.receipts[list[i].id] = nil
	end
end

-- Accorde le contenu d'un produit. Aucun yield : rien ne peut s'intercaler.
local function grant(player: Player, data, product): boolean
	if product.cosmetic then
		return CosmeticService.GrantExclusive(player, product.cosmetic)
	elseif product.boost then
		local now = os.time()
		local boost = data.boost
		local start = math.max(now, boost.expiresAt or 0)
		local limit = now + Monetization.BOOST_MAX_MINUTES * 60
		boost.expiresAt = math.min(start + product.boost.minutes * 60, limit)
		boost.multiplier = product.boost.multiplier
		PlayerDataService.MarkChanged(player)
		return true
	end
	return false
end

-- Appelé par Roblox (aussi utilisé directement par les tests).
function MonetizationService.ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Decision.NotProcessedYet -- reviendra quand le joueur sera là
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return Decision.NotProcessedYet
	end
	local data = profile.data
	local purchaseId = tostring(info.PurchaseId)
	local purchases = data.purchases

	if purchases.receipts[purchaseId] == nil then
		local product = Monetization.ByProductId(info.ProductId)
		if not product then
			warn(("[Monetization] Produit inconnu ou fermé : %s (reçu %s)"):format(tostring(info.ProductId), purchaseId))
			return Decision.NotProcessedYet
		end
		if not grant(player, data, product) then
			return Decision.NotProcessedYet
		end
		-- Noté dans le même tour que l'octroi : un reçu rejoué ne redonne rien.
		purchases.receipts[purchaseId] = os.time()
		purchases.count += 1
		pruneReceipts(purchases)
		print(("[Monetization] Reçu %s accordé à %s (%s)"):format(purchaseId, player.Name, product.key))
		local lang = Locale.ForPlayer(player)
		local message = if product.cosmetic
			then Locale.T(lang, "shop.thanksItem", { name = Locale.T(lang, "cosmetic." .. product.cosmetic) })
			else Locale.T(lang, "shop.thanksBoost", { minutes = product.boost.minutes })
		Net.FireClient("Notify", player, message, "success")
		task.spawn(ClubService.RefreshPlot, player)
	end

	-- Accordé seulement une fois le profil (avec le reçu) écrit dans le DataStore.
	if not PlayerDataService.Save(player) then
		warn(("[Monetization] Sauvegarde du reçu %s échouée, Roblox le renverra"):format(purchaseId))
		return Decision.NotProcessedYet
	end
	return Decision.PurchaseGranted
end

-- Demande d'achat du client : vérifie puis ouvre la fenêtre Roblox.
function MonetizationService.TryPrompt(player: Player, key): (boolean, string?)
	local product = Monetization.Get(key)
	if not Monetization.IsAvailable(product) then
		return false, "error.shopUnavailable"
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "error.profileNotLoaded"
	end
	if product.cosmetic then
		local item = Cosmetics.Get(product.cosmetic)
		if not item or data.cosmetics.owned[item.id] then
			return false, "error.cosmeticOwned"
		end
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
	if not ok then
		warn("[Monetization] Fenêtre d'achat impossible : " .. tostring(err))
		return false, "error.shopUnavailable"
	end
	return true, nil
end

function MonetizationService.Init()
	-- Une erreur ne doit jamais faire perdre un achat : « pas encore », Roblox réessaiera.
	MarketplaceService.ProcessReceipt = function(info)
		local ok, decision = pcall(MonetizationService.ProcessReceipt, info)
		if ok then
			return decision
		end
		warn("[Monetization] Erreur pendant ProcessReceipt : " .. tostring(decision))
		return Decision.NotProcessedYet
	end
	Net.Handle("RequestBuyExclusive", function(player, key)
		local ok, errKey = MonetizationService.TryPrompt(player, key)
		if not ok then
			Net.FireClient("Notify", player, Locale.TP(player, errKey), "error")
		end
	end)
end

return MonetizationService
