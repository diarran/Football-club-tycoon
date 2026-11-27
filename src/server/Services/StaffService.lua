--[[
	StaffService
	Staff du club et contrats de sponsoring (gestion simple).

	Staff : le client envoie seulement l'identifiant du poste. Le serveur
	vérifie le poste, lit le prix du niveau suivant dans Staff.lua et débite
	une seule fois, sans pause entre le débit et l'embauche.

	Sponsors : les offres sont tirées par le serveur et renouvelées toutes les
	Sponsors.REFRESH_SECONDS (calcul à partir de l'heure, même hors ligne).
	Le client demande « signer l'offre n° X » ou « arrêter le contrat n° X ».
	Après chaque match validé, MatchService appelle OnMatchPlayed : prime fixe
	de chaque contrat, progression de l'objectif, bonus unique, fin de contrat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Reputation = require(Shared.Reputation)
local Net = require(Shared.Net)
local Sponsors = require(Shared.Sponsors)
local Staff = require(Shared.Staff)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local StaffService = {}

local rng = Random.new()

-- Staff -------------------------------------------------------------------

function StaffService.TryHire(player: Player, staffId): (boolean, string)
	if type(staffId) ~= "string" or not Staff.Get(staffId) then
		return false, Locale.TP(player, "error.unknownStaff")
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local level = data.staff[staffId] or 0
	local cost = Staff.GetHireCost(staffId, level)
	if not cost then
		return false, Locale.TP(player, "error.staffMaxLevel")
	end
	if not EconomyService.TrySpend(player, cost, "staff:" .. staffId) then
		return false, Locale.TP(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	-- Aucun yield entre le débit et la montée de niveau.
	data.staff[staffId] = level + 1
	PlayerDataService.MarkChanged(player)
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, if level == 0 then "staff.hired" else "staff.promoted", {
			name = Locale.T(lang, "staff." .. staffId .. ".label"),
			level = level + 1,
		})
end

-- Sponsors ----------------------------------------------------------------

local function divisionTier(data): number
	local division = Divisions.Get(data.club.division)
	return division and division.tier or 7
end

-- Renouvelle les offres si le délai est passé. Renvoie true si elles ont changé.
function StaffService.RefreshOffers(data): boolean
	local state = data.sponsors
	local now = os.time()
	if (state.refreshAt or 0) > now and #state.offers > 0 then
		return false
	end
	table.clear(state.offers)
	for _ = 1, Sponsors.OFFER_COUNT do
		table.insert(state.offers, Sponsors.GenerateOffer(rng, state.nextId, data.club.division, data.trophies.titles))
		state.nextId += 1
	end
	state.refreshAt = now + Sponsors.REFRESH_SECONDS
	return true
end

function StaffService.TrySignSponsor(player: Player, offerId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(offerId) ~= "number" then
		return false, Locale.TP(player, "error.unknownSponsor")
	end
	StaffService.RefreshOffers(data)
	local state = data.sponsors
	local index
	for i, offer in state.offers do
		if offer.id == offerId then
			index = i
			break
		end
	end
	if not index then
		return false, Locale.TP(player, "error.unknownSponsor")
	end
	local maxActive = Sponsors.MaxActive(divisionTier(data))
	if #state.contracts >= maxActive then
		return false, Locale.TP(player, "error.sponsorSlotsFull", { max = maxActive })
	end
	local offer = table.remove(state.offers, index)
	offer.progress = 0
	offer.matchesLeft = offer.matches
	offer.completed = false
	table.insert(state.contracts, offer)
	PlayerDataService.MarkChanged(player)
	return true, Locale.TP(player, "sponsor.signed", { brand = offer.brand })
end

function StaffService.TryCancelSponsor(player: Player, contractId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(contractId) ~= "number" then
		return false, Locale.TP(player, "error.unknownSponsor")
	end
	for i, contract in data.sponsors.contracts do
		if contract.id == contractId then
			table.remove(data.sponsors.contracts, i)
			PlayerDataService.MarkChanged(player)
			return true, Locale.TP(player, "sponsor.cancelled", { brand = contract.brand })
		end
	end
	return false, Locale.TP(player, "error.unknownSponsor")
end

-- Part de l'argent des sponsors en plus grâce au directeur commercial.
function StaffService.SponsorMultiplier(data): number
	return 1 + Staff.Effect(data.staff, "sponsorBonus")
end

-- Prime fixe des contrats pour ce match (avant le boost de revenus).
-- La réputation du club l'augmente un peu (jusqu'à +10 %, Reputation.lua).
function StaffService.ContractIncome(data): number
	local total = 0
	for _, contract in data.sponsors.contracts do
		total += contract.perMatch
	end
	local score = type(data.reputation) == "table" and data.reputation.score or 0
	return math.floor(total * StaffService.SponsorMultiplier(data) * Reputation.SponsorMultiplier(score) + 0.5)
end

-- Après un match validé : progression des objectifs, bonus et fins de contrat.
-- Renvoie { bonuses = { { brand, coins } }, ended = { brand } }.
function StaffService.OnMatchPlayed(player: Player, data, outcome: string, goalsFor: number)
	local report = { bonuses = {}, ended = {} }
	local multiplier = StaffService.SponsorMultiplier(data)
	local contracts = data.sponsors.contracts
	for i = #contracts, 1, -1 do
		local contract = contracts[i]
		if not contract.completed then
			if contract.goal == "wins" and outcome == "Win" then
				contract.progress += 1
			elseif contract.goal == "goals" then
				contract.progress += math.max(0, goalsFor)
			elseif contract.goal == "unbeaten" and outcome ~= "Loss" then
				contract.progress += 1
			end
			if contract.progress >= contract.target then
				contract.progress = contract.target
				contract.completed = true
				local coins = math.floor(contract.bonus * multiplier + 0.5)
				EconomyService.Add(player, coins, "sponsorBonus:" .. contract.brand)
				table.insert(report.bonuses, { brand = contract.brand, coins = coins })
			end
		end
		contract.matchesLeft -= 1
		if contract.matchesLeft <= 0 then
			table.remove(contracts, i)
			table.insert(report.ended, contract.brand)
		end
	end
	return report
end

function StaffService.OnPlayerReady(_player: Player, profile)
	StaffService.RefreshOffers(profile.data)
end

function StaffService.Init()
	local handlers = {
		RequestHireStaff = StaffService.TryHire,
		RequestSignSponsor = StaffService.TrySignSponsor,
		RequestCancelSponsor = StaffService.TryCancelSponsor,
	}
	for name, handler in handlers do
		Net.Handle(name, function(player, id)
			local ok, message = handler(player, id)
			Net.FireClient("Notify", player, message, if ok then "success" else "error")
		end)
	end
	-- Renouvellement des offres pendant que le joueur est connecté.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local data = PlayerDataService.GetData(player)
				if data and StaffService.RefreshOffers(data) then
					PlayerDataService.MarkChanged(player)
					Net.FireClient("Notify", player, Locale.TP(player, "sponsor.newOffers"), "info")
				end
			end
		end
	end)
end

return StaffService
