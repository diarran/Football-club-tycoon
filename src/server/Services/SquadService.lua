--[[
	SquadService
	Effectif réduit : génération des joueurs fictifs, recrutement simple,
	énergie et petite progression après les matchs.

	Centre de formation (installation « Academy ») : les recruteurs repèrent des
	jeunes à intervalle régulier, même hors ligne (calcul à partir de l'heure du
	dernier repérage). Le client demande seulement « signer le jeune n° X » :
	le serveur vérifie qu'il existe, que l'effectif a de la place et débite le
	prix fixé au moment du repérage. Les jeunes formés au club progressent plus
	vite après les matchs (effet youthGrowth).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local Staff = require(Shared.Staff)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)

local SquadService = {}

local rng = Random.new()

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- Crée un footballeur fictif. Les valeurs sont tirées côté serveur uniquement.
local function generateFootballer(
	data,
	position: string,
	ratingMin: number,
	ratingMax: number,
	potentialBonusMax: number?
)
	local rating = rng:NextInteger(ratingMin, ratingMax)
	local footballer = {
		id = data.nextPlayerId,
		name = pick(PlayerConfig.FirstNames) .. " " .. pick(PlayerConfig.LastNames),
		age = rng:NextInteger(PlayerConfig.AGE_MIN, PlayerConfig.AGE_MAX),
		position = position,
		rating = rating,
		potential = math.min(
			PlayerConfig.MAX_RATING,
			rating + rng:NextInteger(0, potentialBonusMax or PlayerConfig.POTENTIAL_BONUS_MAX)
		),
		energy = PlayerConfig.MAX_ENERGY,
		value = rating * 30,
		salary = rating * 2,
	}
	data.nextPlayerId += 1
	return footballer
end

-- Jeune repéré par le centre de formation (note modeste, fort potentiel).
local function generateProspect(data, academy)
	-- Recruteur du staff : jeunes un peu meilleurs (note et potentiel).
	local scoutBonus = Staff.Effect(data.staff, "prospectBonus")
	local rating = rng:NextInteger(academy.ratingMin, academy.ratingMax) + scoutBonus
	local potential = math.max(rating + 10, rng:NextInteger(academy.potentialMin, academy.potentialMax) + scoutBonus)
	local prospect = {
		id = data.nextPlayerId,
		name = pick(PlayerConfig.FirstNames) .. " " .. pick(PlayerConfig.LastNames),
		age = rng:NextInteger(PlayerConfig.PROSPECT_AGE_MIN, PlayerConfig.PROSPECT_AGE_MAX),
		position = pick(PlayerConfig.PROSPECT_POSITIONS),
		rating = rating,
		potential = math.min(PlayerConfig.MAX_RATING, potential),
		cost = academy.signCost,
	}
	data.nextPlayerId += 1
	return prospect
end

-- Poste le moins représenté, pour garder un effectif cohérent.
local function neededPosition(squad): string
	local counts = { GK = 0, DEF = 0, MID = 0, ATT = 0 }
	for _, footballer in squad do
		counts[footballer.position] = (counts[footballer.position] or 0) + 1
	end
	if counts.GK == 0 then
		return "GK"
	end
	local best, bestCount = "DEF", math.huge
	for _, position in { "DEF", "MID", "ATT" } do
		if counts[position] < bestCount then
			best, bestCount = position, counts[position]
		end
	end
	return best
end

-- Récupération d'énergie calculée à partir du temps écoulé.
function SquadService.RefreshEnergy(data)
	local now = os.time()
	local minutes = (now - (data.lastEnergyUpdate or now)) / 60
	if minutes <= 0 then
		return
	end
	local trainingLevel = data.buildings.Training or 1
	local multiplier = (Buildings.GetEffects("Training", trainingLevel).energyRecovery or 1)
		* Staff.Effect(data.staff, "energyRecovery") -- médecin du staff
	local gain = minutes * Config.ENERGY_RECOVERY_PER_MINUTE * multiplier
	for _, footballer in data.squad do
		footballer.energy = math.min(PlayerConfig.MAX_ENERGY, footballer.energy + gain)
	end
	data.lastEnergyUpdate = now
end

function SquadService.GetSquad(player: Player)
	local data = PlayerDataService.GetData(player)
	return data and data.squad or {}
end

function SquadService.TryRecruit(player: Player): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if #data.squad >= Config.MAX_SQUAD_SIZE then
		return false, Locale.TP(player, "error.squadFull", { max = Config.MAX_SQUAD_SIZE })
	end
	if not EconomyService.TrySpend(player, PlayerConfig.RECRUIT_COST, "recruit") then
		return false, Locale.TP(player, "error.notEnoughCoinsRecruit", { currency = Config.CURRENCY_NAME })
	end
	local footballer = generateFootballer(
		data,
		neededPosition(data.squad),
		PlayerConfig.RECRUIT_RATING_MIN,
		PlayerConfig.RECRUIT_RATING_MAX
	)
	table.insert(data.squad, footballer)
	PlayerDataService.MarkChanged(player)
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, "squad.recruited", {
			name = footballer.name,
			position = Locale.T(lang, "position." .. footballer.position),
			rating = footballer.rating,
		})
end

-- Centre de formation : ajoute les jeunes repérés depuis le dernier passage.
-- Renvoie le nombre de nouveaux jeunes. Appelé au chargement, régulièrement
-- et avant chaque signature ; ne dépend que de l'horloge du serveur.
function SquadService.RefreshProspects(data): number
	local academy = Buildings.GetEffects("Academy", data.buildings.Academy or 1)
	-- Recruteur du staff : repérage plus rapide.
	local perHour = (academy.scoutsPerHour or 0) * Staff.Effect(data.staff, "scoutSpeed")
	local state = data.academy
	local now = os.time()
	if perHour <= 0 then
		return 0
	end
	if (state.lastScoutAt or 0) <= 0 or state.lastScoutAt > now then
		state.lastScoutAt = now -- premier passage : le premier jeune arrive après un intervalle
		return 0
	end
	local interval = 3600 / perHour
	local due = math.floor((now - state.lastScoutAt) / interval)
	if due <= 0 then
		return 0
	end
	local free = math.max(0, (academy.prospectSlots or 0) - #state.prospects)
	local added = math.min(due, free)
	for _ = 1, added do
		table.insert(state.prospects, generateProspect(data, academy))
	end
	-- Liste pleine : on ne cumule pas d'avance, le compteur repart de maintenant.
	state.lastScoutAt = if due > added then now else state.lastScoutAt + due * interval
	return added
end

function SquadService.TrySignProspect(player: Player, prospectId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(prospectId) ~= "number" then
		return false, Locale.TP(player, "error.unknownProspect")
	end
	SquadService.RefreshProspects(data)
	local prospects = data.academy.prospects
	local index
	for i, prospect in prospects do
		if prospect.id == prospectId then
			index = i
			break
		end
	end
	if not index then
		return false, Locale.TP(player, "error.unknownProspect")
	end
	if #data.squad >= Config.MAX_SQUAD_SIZE then
		return false, Locale.TP(player, "error.squadFull", { max = Config.MAX_SQUAD_SIZE })
	end
	local prospect = prospects[index]
	if not EconomyService.TrySpend(player, prospect.cost, "academy") then
		return false, Locale.TP(player, "error.notEnoughCoinsRecruit", { currency = Config.CURRENCY_NAME })
	end
	-- Aucun yield entre le débit et le transfert.
	table.remove(prospects, index)
	table.insert(data.squad, {
		id = prospect.id,
		name = prospect.name,
		age = prospect.age,
		position = prospect.position,
		rating = prospect.rating,
		potential = prospect.potential,
		energy = PlayerConfig.MAX_ENERGY,
		value = prospect.rating * 30,
		salary = prospect.rating * 2,
		youth = true, -- formé au club : progression accélérée
	})
	PlayerDataService.MarkChanged(player)
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, "academy.signed", {
			name = prospect.name,
			position = Locale.T(lang, "position." .. prospect.position),
			potential = prospect.potential,
		})
end

-- Libère un joueur (pour faire de la place). L'effectif garde au moins
-- Config.STARTING_PLAYERS joueurs.
function SquadService.TryRelease(player: Player, footballerId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	if type(footballerId) ~= "number" then
		return false, Locale.TP(player, "error.unknownFootballer")
	end
	local index
	for i, footballer in data.squad do
		if footballer.id == footballerId then
			index = i
			break
		end
	end
	if not index then
		return false, Locale.TP(player, "error.unknownFootballer")
	end
	if #data.squad <= Config.STARTING_PLAYERS then
		return false, Locale.TP(player, "error.squadMinimum", { min = Config.STARTING_PLAYERS })
	end
	local footballer = table.remove(data.squad, index)
	PlayerDataService.MarkChanged(player)
	return true, Locale.TP(player, "squad.released", { name = footballer.name })
end

-- Après un match : fatigue et petite chance de progresser vers le potentiel.
-- Les jeunes formés au club ont la chance en plus du centre de formation.
-- Joueur le moins bien noté de l'effectif (celui que remplace un transfert).
function SquadService.GetWeakest(squad)
	local weakest = nil
	for _, footballer in squad do
		if not weakest or footballer.rating < weakest.rating then
			weakest = footballer
		end
	end
	return weakest
end

-- Transfert (effectif complet, à partir de la D5) : un joueur du niveau de la
-- division remplace le moins bien noté, au même poste pour garder l'équilibre.
-- Le nouveau joueur est toujours meilleur que celui qu'il remplace ; le
-- transfert est refusé (sans rien débiter) si la division n'a plus mieux.
function SquadService.TryTransfer(player: Player): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local division = Divisions.Get(data.club.division)
	local market = division and division.transfer
	if not market then
		return false, Locale.TP(player, "error.transferLocked")
	end
	if #data.squad < Config.MAX_SQUAD_SIZE then
		return false, Locale.TP(player, "error.transferSquadNotFull")
	end
	local weakest = SquadService.GetWeakest(data.squad)
	if weakest.rating >= market.ratingMax then
		return false, Locale.TP(player, "error.transferNoBetter")
	end
	if not EconomyService.TrySpend(player, market.cost, "transfer:" .. division.id) then
		return false, Locale.TP(player, "error.notEnoughCoinsTransfer", { currency = Config.CURRENCY_NAME })
	end
	local newcomer = generateFootballer(
		data,
		weakest.position,
		math.max(market.ratingMin, weakest.rating + 1),
		market.ratingMax,
		market.potentialBonusMax
	)
	local slot = table.find(data.squad, weakest)
	data.squad[slot] = newcomer
	PlayerDataService.MarkChanged(player)
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, "squad.transferred", {
			name = newcomer.name,
			position = Locale.T(lang, "position." .. newcomer.position),
			rating = newcomer.rating,
			old = weakest.name,
		})
end

function SquadService.ApplyMatchEffects(data)
	local trainingLevel = data.buildings.Training or 1
	local teamBonus = Buildings.GetEffects("Training", trainingLevel).teamBonus or 0
	local youthGrowth = Buildings.GetEffects("Academy", data.buildings.Academy or 1).youthGrowth or 0
	-- Entraîneur du staff : un peu plus de chance de progresser.
	local baseChance = 0.2 + 0.1 * teamBonus + Staff.Effect(data.staff, "growthBonus")
	for _, footballer in data.squad do
		footballer.energy = math.max(0, footballer.energy - Config.ENERGY_COST_PER_MATCH)
		local progressChance = if footballer.youth then baseChance + youthGrowth else baseChance
		if footballer.rating < footballer.potential and rng:NextNumber() < progressChance then
			footballer.rating += 1
			footballer.value = footballer.rating * 30
		end
	end
end

function SquadService.OnPlayerReady(_player: Player, profile)
	local data = profile.data
	if #data.squad == 0 then
		for _, position in PlayerConfig.STARTING_POSITIONS do
			table.insert(
				data.squad,
				generateFootballer(
					data,
					position,
					PlayerConfig.STARTING_RATING_MIN,
					PlayerConfig.STARTING_RATING_MAX
				)
			)
		end
	end
	SquadService.RefreshEnergy(data)
	SquadService.RefreshProspects(data)
end

function SquadService.Init()
	Net.Handle("RequestRecruit", function(player)
		local ok, message = SquadService.TryRecruit(player)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.BroadcastClubs()
		end
	end)
	Net.Handle("RequestTransfer", function(player)
		local ok, message = SquadService.TryTransfer(player)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.BroadcastClubs()
		end
	end)
	for _, name in { "RequestSignProspect", "RequestRelease" } do
		Net.Handle(name, function(player, id)
			local ok, message
			if name == "RequestSignProspect" then
				ok, message = SquadService.TrySignProspect(player, id)
			else
				ok, message = SquadService.TryRelease(player, id)
			end
			Net.FireClient("Notify", player, message, if ok then "success" else "error")
			if ok then
				ClubService.BroadcastClubs()
			end
		end)
	end
	-- Repérage en continu : prévient le joueur dès qu'un jeune arrive.
	task.spawn(function()
		while true do
			task.wait(PlayerConfig.SCOUT_CHECK_SECONDS)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local data = PlayerDataService.GetData(player)
				if data and SquadService.RefreshProspects(data) > 0 then
					PlayerDataService.MarkChanged(player)
					Net.FireClient("Notify", player, Locale.TP(player, "academy.newProspect"), "info")
				end
			end
		end
	end)
end

return SquadService
