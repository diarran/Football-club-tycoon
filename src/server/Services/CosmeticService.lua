--[[
	CosmeticService
	Dépenses de fin de partie (document de conception, section 9) :
	personnalisation visuelle du club et salle des trophées.

	- Le client envoie seulement l'identifiant d'un objet. Le serveur vérifie
	  qu'il existe, qu'il n'est pas déjà acheté, que le club remplit la
	  condition (division, titres), lit le prix dans Cosmetics.lua et débite une
	  seule fois, sans pause entre le débit et l'ajout.
	- Aucun objet ne change un match : seule l'apparence du terrain change.
	- Trophées : après chaque changement du profil, le service vérifie les
	  nouveaux trophées (montées, records) et les titres de champion de D1
	  (Trophies.TITLE_POINTS points cumulés en D1 = un titre, puis les points
	  repartent de zéro). Le terrain est reconstruit pour remplir la vitrine.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Trophies = require(Shared.Trophies)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)

local CosmeticService = {}

local TOP_DIVISION = Divisions.List[#Divisions.List].id

local function itemName(lang: string, item): string
	return Locale.T(lang, "cosmetic." .. item.id)
end

function CosmeticService.TryBuy(player: Player, itemId): (boolean, string)
	local item = Cosmetics.Get(itemId)
	if not item or item.robux then
		-- Les objets exclusifs ne s'achètent qu'en Robux (MonetizationService).
		return false, Locale.TP(player, "error.unknownCosmetic")
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local lang = Locale.ForPlayer(player)
	if data.cosmetics.owned[item.id] then
		return false, Locale.T(lang, "error.cosmeticOwned")
	end
	local unlocked, reason = Cosmetics.IsUnlocked(item, data.club.division, data.trophies.titles)
	if not unlocked then
		if reason == "titles" then
			return false, Locale.T(lang, "error.cosmeticNeedsTitles", { titles = item.requires.titles })
		end
		local division = Divisions.Get(item.requires.division)
		return false, Locale.T(lang, "error.cosmeticNeedsDivision", { division = Locale.T(lang, "division.label", { tier = division.tier }) })
	end
	if not EconomyService.TrySpend(player, item.cost, "cosmetic:" .. item.id) then
		return false, Locale.T(lang, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	-- Aucun yield entre le débit et l'ajout.
	data.cosmetics.owned[item.id] = true
	if Cosmetics.SINGLE[item.category] then
		data.cosmetics.equipped[item.category] = item.id
	end
	PlayerDataService.MarkChanged(player)
	return true, Locale.T(lang, "cosmetic.bought", { name = itemName(lang, item) })
end

-- Objet exclusif payé en Robux : ajouté et porté, sans débit ni condition.
-- Appelé seulement par MonetizationService après un reçu Roblox. Aucun yield.
function CosmeticService.GrantExclusive(player: Player, itemId: string): boolean
	local item = Cosmetics.Get(itemId)
	local data = PlayerDataService.GetData(player)
	if not item or not item.robux or not data then
		return false
	end
	data.cosmetics.owned[item.id] = true
	if Cosmetics.SINGLE[item.category] then
		data.cosmetics.equipped[item.category] = item.id
	end
	PlayerDataService.MarkChanged(player)
	return true
end

-- itemId = "default" : retour à l'apparence d'origine de la catégorie.
function CosmeticService.TryEquip(player: Player, category, itemId): (boolean, string)
	if not Cosmetics.IsCategory(category) or not Cosmetics.SINGLE[category] then
		return false, Locale.TP(player, "error.unknownCosmetic")
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local lang = Locale.ForPlayer(player)
	if itemId == "default" then
		data.cosmetics.equipped[category] = nil
		PlayerDataService.MarkChanged(player)
		return true, Locale.T(lang, "cosmetic.defaultEquipped")
	end
	local item = Cosmetics.Get(itemId)
	if not item or item.category ~= category then
		return false, Locale.T(lang, "error.unknownCosmetic")
	end
	if not data.cosmetics.owned[item.id] then
		return false, Locale.T(lang, "error.cosmeticNotOwned")
	end
	data.cosmetics.equipped[category] = item.id
	PlayerDataService.MarkChanged(player)
	return true, Locale.T(lang, "cosmetic.equipped", { name = itemName(lang, item) })
end

-- Titres de D1 et nouveaux trophées. Renvoie le nombre de nouveaux trophées.
function CosmeticService.CheckTrophies(player: Player): number
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	local club = data.club
	if club.division == TOP_DIVISION and club.divisionPoints >= Trophies.TITLE_POINTS then
		local titles = math.floor(club.divisionPoints / Trophies.TITLE_POINTS)
		data.trophies.titles += titles
		club.divisionPoints -= titles * Trophies.TITLE_POINTS
	end
	local earned = Trophies.Earned(club.division, club.stats, data.trophies.titles)
	local fresh = #earned - data.trophies.seen
	if fresh < 0 then
		-- Profil corrigé à la main (support) : la vitrine suit, sans annonce.
		data.trophies.seen = #earned
		ClubService.RefreshPlot(player)
		return 0
	elseif fresh == 0 then
		return 0
	end
	data.trophies.seen = #earned
	local lang = Locale.ForPlayer(player)
	local message
	if fresh == 1 then
		local trophy = earned[#earned]
		-- Le dernier gagné n'est pas toujours en fin de liste : on annonce le plus prestigieux.
		for _, t in earned do
			if t.kind == "title" and t.params.n == data.trophies.titles then
				trophy = t
			end
		end
		message = Locale.T(lang, "trophy.new", { name = Locale.T(lang, trophy.key, trophy.params) })
	else
		message = Locale.T(lang, "trophy.newMany", { count = fresh })
	end
	Net.FireClient("Notify", player, message, "success")
	PlayerDataService.MarkChanged(player)
	ClubService.RefreshPlot(player)
	ClubService.BroadcastClubs()
	return fresh
end

function CosmeticService.Init()
	Net.Handle("RequestBuyCosmetic", function(player, itemId)
		local ok, message = CosmeticService.TryBuy(player, itemId)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.RefreshPlot(player)
		end
	end)
	Net.Handle("RequestEquipCosmetic", function(player, category, itemId)
		local ok, message = CosmeticService.TryEquip(player, category, itemId)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.RefreshPlot(player)
		end
	end)
	PlayerDataService.OnChanged(function(player)
		CosmeticService.CheckTrophies(player)
	end)
end

return CosmeticService
