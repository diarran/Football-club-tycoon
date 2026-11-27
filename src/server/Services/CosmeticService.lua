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
local ClubIdentity = require(Shared.ClubIdentity)
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Trophies = require(Shared.Trophies)
local WorldConfig = require(Shared.WorldConfig)

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
	if not item or item.robux or item.event then
		-- Les objets exclusifs ne s'achètent qu'en Robux (MonetizationService) ;
		-- ceux des événements se gagnent en jouant (EventService).
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

-- Objet d'un événement de la semaine : ajouté et porté, sans débit.
-- Appelé seulement par EventService au dernier palier. Aucun yield.
function CosmeticService.GrantEvent(player: Player, itemId: string): boolean
	local item = Cosmetics.Get(itemId)
	local data = PlayerDataService.GetData(player)
	if not item or not item.event or not data then
		return false
	end
	data.cosmetics.owned[item.id] = true
	if Cosmetics.SINGLE[item.category] then
		data.cosmetics.equipped[item.category] = item.id
	end
	PlayerDataService.MarkChanged(player)
	task.spawn(ClubService.RefreshPlot, player)
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

-- Identité du club (ClubIdentity) ---------------------------------------

local function identityOf(data)
	return data.identity
end

-- Change une partie de l'identité. field = "primary" / "secondary" (id de
-- couleur ou "default"), "pattern" (id de motif débloqué), "crest" (1 à 6, ou
-- 0 = écusson de l'emplacement), ou "reset" (tout revient à l'origine).
-- Choisir des couleurs (ou un motif) retire l'objet Prestige porté de la
-- catégorie, pour que le choix se voie tout de suite.
function CosmeticService.TrySetIdentity(player: Player, field, value): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local lang = Locale.ForPlayer(player)
	local identity = identityOf(data)
	if field == "reset" then
		identity.primary, identity.secondary = "", ""
		identity.pattern = ClubIdentity.DEFAULT_PATTERN
		identity.crest = 0
		data.cosmetics.equipped.colors = nil
		data.cosmetics.equipped.kit = nil
		PlayerDataService.MarkChanged(player)
		return true, Locale.T(lang, "identity.resetDone")
	elseif field == "primary" or field == "secondary" then
		local id = if value == "default" then "" else value
		if id ~= "" and not ClubIdentity.Color(id) then
			return false, Locale.T(lang, "error.identityInvalid")
		end
		local slot = ClubService.GetSlot(player)
		local choices = ClubIdentity.Choices(data)
		choices[field] = ClubIdentity.Color(id)
		local base = WorldConfig.CLUB_COLORS[slot or 1] or WorldConfig.CLUB_COLORS[1]
		local primary = choices.primary or base.primary
		local secondary = choices.secondary or base.secondary
		if primary == secondary then
			return false, Locale.T(lang, "error.identitySameColors")
		end
		identity[field] = id
		data.cosmetics.equipped.colors = nil
		PlayerDataService.MarkChanged(player)
		return true, Locale.T(lang, "identity.colorsDone")
	elseif field == "pattern" then
		local pattern = ClubIdentity.Pattern(value)
		if not pattern then
			return false, Locale.T(lang, "error.identityInvalid")
		end
		local ok, reason = ClubIdentity.PatternUnlocked(pattern, data.club.division, data.cosmetics.owned, identity.patterns)
		if not ok then
			return false, Locale.T(lang, "error.patternLocked." .. (reason or "kit"))
		end
		identity.pattern = pattern.id
		data.cosmetics.equipped.kit = nil
		PlayerDataService.MarkChanged(player)
		return true, Locale.T(lang, "identity.patternDone", { name = Locale.T(lang, "identity.pattern." .. pattern.id) })
	elseif field == "crest" then
		if value ~= 0 and not ClubIdentity.ValidCrest(value) then
			return false, Locale.T(lang, "error.identityInvalid")
		end
		identity.crest = value
		PlayerDataService.MarkChanged(player)
		return true, Locale.T(lang, "identity.crestDone")
	end
	return false, Locale.T(lang, "error.identityInvalid")
end

-- Achète un motif en FC Coins (une seule fois), puis le porte.
function CosmeticService.TryBuyPattern(player: Player, patternId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local lang = Locale.ForPlayer(player)
	local pattern = ClubIdentity.Pattern(patternId)
	if not pattern or not pattern.cost then
		return false, Locale.T(lang, "error.identityInvalid")
	end
	local identity = identityOf(data)
	if identity.patterns[pattern.id] then
		return false, Locale.T(lang, "error.cosmeticOwned")
	end
	local ok, reason = ClubIdentity.PatternUnlocked(pattern, data.club.division, data.cosmetics.owned, { [pattern.id] = true })
	if not ok then
		return false, Locale.T(lang, "error.patternLocked." .. (reason or "kit"))
	end
	if not EconomyService.TrySpend(player, pattern.cost, "pattern:" .. pattern.id) then
		return false, Locale.T(lang, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	-- Aucun yield entre le débit et l'ajout.
	identity.patterns[pattern.id] = true
	identity.pattern = pattern.id
	data.cosmetics.equipped.kit = nil
	PlayerDataService.MarkChanged(player)
	return true, Locale.T(lang, "identity.patternBought", { name = Locale.T(lang, "identity.pattern." .. pattern.id) })
end

-- Identité envoyée au client : choix bruts, couleurs et tenue résolues.
local function identitySnapshot(player: Player, data)
	local identity = identityOf(data)
	local look = ClubIdentity.Resolve(data, ClubService.GetSlot(player))
	return {
		choice = {
			primary = identity.primary,
			secondary = identity.secondary,
			pattern = identity.pattern,
			crest = identity.crest,
		},
		patterns = table.clone(identity.patterns),
		primary = ClubIdentity.ToArray(look.primary),
		secondary = ClubIdentity.ToArray(look.secondary),
		kit = ClubIdentity.KitToNet(look.kit),
		crest = look.crest,
	}
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
	local function afterIdentity(player, ok, message)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.RefreshPlot(player)
			ClubService.BroadcastClubs()
		end
	end
	Net.Handle("RequestSetIdentity", function(player, field, value)
		afterIdentity(player, CosmeticService.TrySetIdentity(player, field, value))
	end)
	Net.Handle("RequestBuyPattern", function(player, patternId)
		afterIdentity(player, CosmeticService.TryBuyPattern(player, patternId))
	end)
	PlayerDataService.AddSnapshotField("identity", identitySnapshot)
	PlayerDataService.OnChanged(function(player)
		CosmeticService.CheckTrophies(player)
	end)
end

return CosmeticService
