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
local Daily = require(Shared.Daily)
local Divisions = require(Shared.Divisions)
local Injuries = require(Shared.Injuries)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local Staff = require(Shared.Staff)
local Training = require(Shared.Training)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)
local DailyService = require(script.Parent.DailyService)

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
		xp = 0,
		trainedAt = 0,
		injuredUntil = 0,
		suspended = 0,
		yellows = 0,
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
	DailyService.Track(player, "recruit") -- mission du jour
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
		xp = 0,
		trainedAt = 0,
		injuredUntil = 0,
		suspended = 0,
		yellows = 0,
	})
	PlayerDataService.MarkChanged(player)
	DailyService.Track(player, "recruit") -- mission du jour
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
	-- Le nouveau joueur prend la place du partant dans la composition.
	if type(data.lineup) == "table" then
		local index = table.find(data.lineup, weakest.id)
		if index then
			data.lineup[index] = newcomer.id
		end
	end
	PlayerDataService.MarkChanged(player)
	DailyService.Track(player, "recruit") -- mission du jour
	local lang = Locale.ForPlayer(player)
	return true,
		Locale.T(lang, "squad.transferred", {
			name = newcomer.name,
			position = Locale.T(lang, "position." .. newcomer.position),
			rating = newcomer.rating,
			old = weakest.name,
		})
end

-- Entraînement et composition (shared/Training.lua) ---------------------------

-- Titulaires du club (tables de data.squad) disponibles maintenant : les
-- blessés et suspendus sont remplacés par les meilleurs remplaçants.
-- Utilisé par les matchs.
function SquadService.Starters(data)
	return Training.Starters(data.squad, data.lineup, os.time())
end

-- Places de titulaires vides (blessés / suspendus sans remplaçant disponible).
function SquadService.MissingStarters(data): number
	return Training.MissingStarters(data.squad, os.time())
end

-- Plus aucun joueur disponible et personne n'est blessé (que des suspendus) :
-- les suspensions sont levées pour ne jamais bloquer le club. Renvoie true si
-- quelqu'un peut jouer ensuite.
function SquadService.ClearSuspensionsIfStuck(data): boolean
	local now = os.time()
	for _, footballer in data.squad do
		if Injuries.IsInjured(footballer, now) then
			return false
		end
	end
	for _, footballer in data.squad do
		footballer.suspended = 0
	end
	return #SquadService.Starters(data) > 0
end

-- Minutes avant le retour du premier blessé.
function SquadService.NextReturnMinutes(data): number
	local now, best = os.time(), math.huge
	for _, footballer in data.squad do
		local left = Injuries.InjuryLeft(footballer, now)
		if left > 0 and left < best then
			best = left
		end
	end
	return if best == math.huge then 1 else math.ceil(best / 60)
end

-- Malus de force d'équipe dû aux titulaires absents (à ajouter au bonus).
function SquadService.MissingPenalty(data): number
	return SquadService.MissingStarters(data) * Injuries.MISSING_PENALTY
end

local function findFootballer(data, footballerId)
	if type(footballerId) ~= "number" then
		return nil
	end
	for _, footballer in data.squad do
		if footballer.id == footballerId then
			return footballer
		end
	end
	return nil
end

-- Complète les champs ajoutés avec l'entraînement (anciens profils, joueurs
-- abîmés) et vieillit l'effectif d'un an par saison écoulée.
function SquadService.RefreshTraining(data)
	for _, footballer in data.squad do
		local xp = tonumber(footballer.xp)
		footballer.xp = if xp and xp == xp and xp >= 0 and xp < Training.XP_PER_POINT then math.floor(xp) else 0
		local trainedAt = tonumber(footballer.trainedAt)
		footballer.trainedAt = if trainedAt and trainedAt == trainedAt then trainedAt else 0
		Injuries.Sanitize(footballer, os.time()) -- blessures et suspensions (anciens profils)
	end
	local season = Daily.SeasonId(os.time())
	local state = data.training
	if type(state.ageSeason) ~= "number" or state.ageSeason ~= state.ageSeason or state.ageSeason > season then
		state.ageSeason = season
	end
	local years = math.min(Training.MAX_AGE_STEPS, season - state.ageSeason)
	if years > 0 then
		for _, footballer in data.squad do
			footballer.age = (tonumber(footballer.age) or PlayerConfig.AGE_MIN) + years
		end
	end
	state.ageSeason = season
	data.lineup = Training.Normalize(data.squad, data.lineup)
end

-- Séance d'entraînement d'un joueur : prix en FC Coins, énergie, délai.
function SquadService.TryTrain(player: Player, footballerId): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local footballer = findFootballer(data, footballerId)
	if not footballer then
		return false, Locale.TP(player, "error.unknownFootballer")
	end
	SquadService.RefreshEnergy(data)
	local injuryLeft = Injuries.InjuryLeft(footballer, os.time())
	if injuryLeft > 0 then
		return false,
			Locale.TP(player, "injury.cannotTrain", { name = footballer.name, minutes = math.ceil(injuryLeft / 60) })
	end
	if footballer.rating >= footballer.potential then
		return false, Locale.TP(player, "training.atPotential", { name = footballer.name })
	end
	local wait = Training.CooldownLeft(footballer, os.time())
	if wait > 0 then
		return false, Locale.TP(player, "training.cooldown", { name = footballer.name, seconds = math.ceil(wait) })
	end
	if footballer.energy < Training.MIN_ENERGY then
		return false, Locale.TP(player, "training.tired", { name = footballer.name, energy = Training.MIN_ENERGY })
	end
	local cost = Training.SessionCost(footballer.rating)
	if not EconomyService.TrySpend(player, cost, "training") then
		return false, Locale.TP(player, "error.notEnoughCoinsTraining", { currency = Config.CURRENCY_NAME })
	end
	local teamBonus = Buildings.GetEffects("Training", data.buildings.Training or 1).teamBonus or 0
	local xp = Training.SessionXp(footballer, teamBonus, Staff.Effect(data.staff, "growthBonus"))
	footballer.energy = math.max(0, footballer.energy - Training.SESSION_ENERGY)
	footballer.trainedAt = os.time()
	local gained = Training.AddXp(footballer, xp)
	PlayerDataService.MarkChanged(player)
	if gained > 0 then
		return true, Locale.TP(player, "training.levelUp", { name = footballer.name, rating = footballer.rating })
	end
	return true, Locale.TP(player, "training.done", { name = footballer.name, xp = xp })
end

-- Fait entrer un remplaçant (starter = true) ou met un titulaire sur le banc.
-- La composition garde toujours Training.STARTERS joueurs (ou tout l'effectif).
function SquadService.TrySetStarter(player: Player, footballerId, starter): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local footballer = findFootballer(data, footballerId)
	if not footballer or type(starter) ~= "boolean" then
		return false, Locale.TP(player, "error.unknownFootballer")
	end
	if #data.squad <= Training.STARTERS then
		return false, Locale.TP(player, "lineup.everyonePlays", { count = Training.STARTERS })
	end
	local now = os.time()
	if starter and not Injuries.IsAvailable(footballer, now) then
		if Injuries.IsInjured(footballer, now) then
			return false,
				Locale.TP(player, "injury.cannotPlay", {
					name = footballer.name,
					minutes = math.ceil(Injuries.InjuryLeft(footballer, now) / 60),
				})
		end
		return false, Locale.TP(player, "suspension.cannotPlay", { name = footballer.name })
	end
	local starters = Training.Starters(data.squad, data.lineup, now)
	local set = {}
	for _, s in starters do
		set[s.id] = true
	end
	if set[footballer.id] == starter then
		return true, "" -- déjà fait
	end
	local outId, inId
	if starter then
		-- Sort le titulaire le moins bien noté au même poste, sinon le moins bien noté
		-- (on ne sort le seul gardien que pour un autre gardien).
		local samePosition, anyPosition
		local keepers = 0
		for _, s in starters do
			keepers += if s.position == "GK" then 1 else 0
		end
		for _, s in starters do
			if s.position == footballer.position and (not samePosition or s.rating < samePosition.rating) then
				samePosition = s
			end
			local protected = s.position == "GK" and keepers <= 1
			if not protected and (not anyPosition or s.rating < anyPosition.rating) then
				anyPosition = s
			end
		end
		local out = samePosition or anyPosition or starters[#starters]
		if not out then
			data.lineup = { footballer.id }
			PlayerDataService.MarkChanged(player)
			return true, Locale.TP(player, "lineup.auto")
		end
		outId, inId = out.id, footballer.id
	else
		-- Entre le meilleur remplaçant au même poste, sinon le meilleur remplaçant.
		local samePosition, anyPosition
		for _, b in data.squad do
			if not set[b.id] and Injuries.IsAvailable(b, now) then
				if b.position == footballer.position and (not samePosition or b.rating > samePosition.rating) then
					samePosition = b
				end
				if not anyPosition or b.rating > anyPosition.rating then
					anyPosition = b
				end
			end
		end
		local incoming = samePosition or anyPosition
		if not incoming then
			return false, Locale.TP(player, "lineup.noSubstitute")
		end
		outId, inId = footballer.id, incoming.id
	end
	local lineup = {}
	for _, s in starters do
		table.insert(lineup, if s.id == outId then inId else s.id)
	end
	data.lineup = lineup
	PlayerDataService.MarkChanged(player)
	local inName, outName
	for _, f in data.squad do
		if f.id == inId then
			inName = f.name
		elseif f.id == outId then
			outName = f.name
		end
	end
	return true, Locale.TP(player, "lineup.swapped", { inName = inName, outName = outName })
end

-- Composition automatique : les meilleurs joueurs, avec un gardien.
function SquadService.TryAutoLineup(player: Player): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	data.lineup = Training.Normalize(data.squad, {})
	PlayerDataService.MarkChanged(player)
	return true, Locale.TP(player, "lineup.auto")
end

-- Après un match : les titulaires se fatiguent et gagnent de l'XP (les jeunes
-- formés au club ont en plus le bonus du centre de formation). Les remplaçants
-- se reposent. Puis blessures et cartons (Injuries.lua) : les suspendus qui
-- n'ont pas joué purgent un match. Renvoie le rapport de l'infirmerie :
-- { events = { ... }, returned = { noms des suspendus qui peuvent rejouer } }.
function SquadService.ApplyMatchEffects(data, starters)
	local trainingLevel = data.buildings.Training or 1
	local teamBonus = Buildings.GetEffects("Training", trainingLevel).teamBonus or 0
	local youthGrowth = Buildings.GetEffects("Academy", data.buildings.Academy or 1).youthGrowth or 0
	-- Entraîneur du staff : un peu plus d'XP.
	local baseChance = 0.2 + 0.1 * teamBonus + Staff.Effect(data.staff, "growthBonus")
	local now = os.time()
	starters = starters or SquadService.Starters(data)
	local played = {}
	for _, footballer in starters do
		played[footballer] = true
	end
	local report = { events = {}, returned = {} }
	-- Suspensions purgées : le joueur n'a pas joué ce match.
	for _, footballer in data.squad do
		if not played[footballer] and Injuries.IsSuspended(footballer) and Injuries.ServeSuspension(footballer) then
			table.insert(report.returned, footballer.name)
		end
	end
	local reduction = Staff.Effect(data.staff, "injuryReduction") -- médecin du staff
	for _, footballer in starters do
		local energyBefore = footballer.energy
		footballer.energy = math.max(0, footballer.energy - Config.ENERGY_COST_PER_MATCH)
		local chance = if footballer.youth then baseChance + youthGrowth else baseChance
		Training.AddXp(footballer, Training.MatchXp(footballer, chance))
		local event = Injuries.Roll(rng, footballer, energyBefore, reduction, now)
		if event then
			table.insert(report.events, event)
		end
	end
	return report
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
	SquadService.RefreshTraining(data)
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
	Net.Handle("RequestTrain", function(player, id)
		local ok, message = SquadService.TryTrain(player, id)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
	end)
	Net.Handle("RequestLineup", function(player, id, starter)
		local ok, message
		if id == "auto" then
			ok, message = SquadService.TryAutoLineup(player)
		else
			ok, message = SquadService.TrySetStarter(player, id, starter)
		end
		if message ~= "" then
			Net.FireClient("Notify", player, message, if ok then "success" else "error")
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
