--[[
	SquadService
	Effectif réduit : génération des joueurs fictifs, recrutement simple,
	énergie et petite progression après les matchs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)

local SquadService = {}

local rng = Random.new()

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- Crée un footballeur fictif. Les valeurs sont tirées côté serveur uniquement.
local function generateFootballer(data, position: string, ratingMin: number, ratingMax: number)
	local rating = rng:NextInteger(ratingMin, ratingMax)
	local footballer = {
		id = data.nextPlayerId,
		name = pick(PlayerConfig.FirstNames) .. " " .. pick(PlayerConfig.LastNames),
		age = rng:NextInteger(PlayerConfig.AGE_MIN, PlayerConfig.AGE_MAX),
		position = position,
		rating = rating,
		potential = math.min(
			PlayerConfig.MAX_RATING,
			rating + rng:NextInteger(0, PlayerConfig.POTENTIAL_BONUS_MAX)
		),
		energy = PlayerConfig.MAX_ENERGY,
		value = rating * 30,
		salary = rating * 2,
	}
	data.nextPlayerId += 1
	return footballer
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
	local multiplier = Buildings.GetEffects("Training", trainingLevel).energyRecovery or 1
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

-- Après un match : fatigue et petite chance de progresser vers le potentiel.
function SquadService.ApplyMatchEffects(data)
	local trainingLevel = data.buildings.Training or 1
	local teamBonus = Buildings.GetEffects("Training", trainingLevel).teamBonus or 0
	local progressChance = 0.2 + 0.1 * teamBonus
	for _, footballer in data.squad do
		footballer.energy = math.max(0, footballer.energy - Config.ENERGY_COST_PER_MATCH)
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
end

function SquadService.Init()
	Net.Handle("RequestRecruit", function(player)
		local ok, message = SquadService.TryRecruit(player)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			ClubService.BroadcastClubs()
		end
	end)
end

return SquadService
