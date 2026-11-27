--[[
	CampusService
	Mode Création : débloquer des parcelles, y placer des bâtiments, les
	tourner, les déplacer et les améliorer (règles dans Campus.lua).

	Le client envoie seulement : RequestCampus(action, ...) avec
	  "unlock", parcel            débloquer une parcelle
	  "build", buildingId, parcel, rot   construire un bâtiment sur une parcelle libre
	  "upgrade", buildingId       niveau suivant
	  "rotate", buildingId        tourner d'un quart de tour
	  "move", buildingId, parcel  déplacer (échange si la parcelle est occupée)
	Le serveur vérifie tout (division, prix lu dans Campus.lua, parcelle à soi,
	libre…) et débite une seule fois, sans pause entre le débit et le changement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Campus = require(Shared.Campus)
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)

local CampusService = {}

local lastMove = setmetatable({}, { __mode = "k" }) -- [Player] = os.clock() du dernier déplacement

local function parcelIndex(value): number?
	local n = tonumber(value)
	if n and n == math.floor(n) and Campus.Parcels[n] then
		return n
	end
	return nil
end

local function label(player: Player, id: string): string
	return Locale.TP(player, "campus." .. id .. ".label")
end

local function campusOf(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, nil
	end
	data.campus = Campus.Sanitize(data.campus)
	return data, data.campus
end

function CampusService.TryUnlock(player: Player, parcelValue): (boolean, string)
	local data, campus = campusOf(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local parcel = parcelIndex(parcelValue)
	if not parcel then
		return false, Locale.TP(player, "campus.error.unknownParcel")
	end
	if Campus.HasParcel(campus, parcel) then
		return false, Locale.TP(player, "campus.error.alreadyUnlocked")
	end
	local rule = Campus.Parcels[parcel]
	if not Campus.DivisionAllows(data.club.division, rule.division) then
		return false, Locale.TP(player, "campus.error.division", { division = rule.division })
	end
	if not EconomyService.TrySpend(player, rule.cost, "campus:parcel" .. parcel) then
		return false, Locale.TP(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	Campus.SetParcel(campus, parcel)
	return true, Locale.TP(player, "campus.unlocked", { parcel = parcel })
end

function CampusService.TryBuild(player: Player, id, parcelValue, rotValue): (boolean, string)
	local data, campus = campusOf(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local def = type(id) == "string" and Campus.Get(id)
	if not def then
		return false, Locale.TP(player, "campus.error.unknownBuilding")
	end
	if campus.placed[id] then
		return false, Locale.TP(player, "campus.error.alreadyBuilt")
	end
	if not Campus.DivisionAllows(data.club.division, def.division) then
		return false, Locale.TP(player, "campus.error.division", { division = def.division })
	end
	local parcel = parcelIndex(parcelValue)
	if not parcel or not Campus.HasParcel(campus, parcel) then
		return false, Locale.TP(player, "campus.error.parcelLocked")
	end
	if Campus.BuildingOn(campus, parcel) then
		return false, Locale.TP(player, "campus.error.parcelTaken")
	end
	local rot = tonumber(rotValue) or 0
	if not table.find(Campus.ROTATIONS, rot) then
		rot = 0
	end
	local cost = def.levels[1].cost
	if not EconomyService.TrySpend(player, cost, "campus:build:" .. id) then
		return false, Locale.TP(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	campus.placed[id] = { parcel = parcel, level = 1, rot = rot }
	return true, Locale.TP(player, "campus.built", { name = label(player, id) })
end

function CampusService.TryUpgrade(player: Player, id): (boolean, string)
	local data, campus = campusOf(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local entry = type(id) == "string" and campus.placed[id]
	if not entry then
		return false, Locale.TP(player, "campus.error.notBuilt")
	end
	local cost = Campus.NextCost(campus, id)
	if not cost then
		return false, Locale.TP(player, "error.maxLevel")
	end
	if not EconomyService.TrySpend(player, cost, "campus:upgrade:" .. id) then
		return false, Locale.TP(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
	end
	entry.level += 1
	return true, Locale.TP(player, "campus.upgraded", { name = label(player, id), level = entry.level })
end

local function moveAllowed(player: Player): boolean
	local now = os.clock()
	if lastMove[player] and now - lastMove[player] < Campus.MOVE_COOLDOWN then
		return false
	end
	lastMove[player] = now
	return true
end

function CampusService.TryRotate(player: Player, id): (boolean, string)
	local data, campus = campusOf(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local entry = type(id) == "string" and campus.placed[id]
	if not entry then
		return false, Locale.TP(player, "campus.error.notBuilt")
	end
	if not moveAllowed(player) then
		return false, Locale.TP(player, "campus.error.tooFast")
	end
	entry.rot = (entry.rot + 90) % 360
	return true, Locale.TP(player, "campus.rotated", { name = label(player, id) })
end

function CampusService.TryMove(player: Player, id, parcelValue): (boolean, string)
	local data, campus = campusOf(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local entry = type(id) == "string" and campus.placed[id]
	if not entry then
		return false, Locale.TP(player, "campus.error.notBuilt")
	end
	local parcel = parcelIndex(parcelValue)
	if not parcel or not Campus.HasParcel(campus, parcel) then
		return false, Locale.TP(player, "campus.error.parcelLocked")
	end
	if parcel == entry.parcel then
		return false, Locale.TP(player, "campus.error.sameParcel")
	end
	if not moveAllowed(player) then
		return false, Locale.TP(player, "campus.error.tooFast")
	end
	-- Parcelle occupée : les deux bâtiments échangent leur place.
	local other = Campus.BuildingOn(campus, parcel)
	if other then
		campus.placed[other].parcel = entry.parcel
	end
	entry.parcel = parcel
	return true, Locale.TP(player, "campus.moved", { name = label(player, id), parcel = parcel })
end

local ACTIONS = {
	unlock = function(player, a)
		return CampusService.TryUnlock(player, a)
	end,
	build = CampusService.TryBuild,
	upgrade = CampusService.TryUpgrade,
	rotate = CampusService.TryRotate,
	move = CampusService.TryMove,
}

-- Point d'entrée unique (aussi utilisé par les tests).
function CampusService.Handle(player: Player, action, ...): (boolean, string)
	local fn = type(action) == "string" and ACTIONS[action]
	if not fn then
		return false, Locale.TP(player, "campus.error.unknownAction")
	end
	return fn(player, ...)
end

-- Instantané client : copie propre du campus.
function CampusService.Snapshot(_, data)
	local campus = Campus.Sanitize(data.campus)
	local placed = {}
	for id, entry in campus.placed do
		placed[id] = table.clone(entry)
	end
	return { parcels = table.clone(campus.parcels), placed = placed }
end

function CampusService.Init()
	PlayerDataService.AddSnapshotField("campus", CampusService.Snapshot)
	Net.Handle("RequestCampus", function(player, action, a, b, c)
		local ok, message = CampusService.Handle(player, action, a, b, c)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			PlayerDataService.MarkChanged(player)
			ClubService.RefreshPlot(player)
		end
	end)
end

return CampusService
