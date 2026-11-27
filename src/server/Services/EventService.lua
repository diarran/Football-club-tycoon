--[[
	EventService
	Événements de la semaine (règles et montants : shared/Events.lua).

	- Thème de la semaine (lundi 00:00 UTC) : bonus de FC Coins sur les matchs
	  (MatchService appelle EventService.MatchBonus) et points d'événement
	  (EventService.OnMatchPlayed).
	- Paliers : le joueur récupère ses récompenses avec RequestEventClaim
	  (accueil). Le dernier palier donne l'objet du thème (CosmeticService).
	  Un palier atteint mais pas récupéré est versé automatiquement à la
	  semaine suivante : rien n'est perdu.
	- Coupe du week-end : TournamentService multiplie ses récompenses par
	  Events.TournamentMultiplier et appelle EventService.AddCupPoints.

	Tout se calcule avec os.time() côté serveur : le client envoie seulement
	« récupérer », sans aucune valeur.
	Profil : data.events = { week, points, claimed } (claimed = paliers versés).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Events = require(Shared.Events)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local CosmeticService = require(script.Parent.CosmeticService)

local EventService = {}

local function notify(player: Player, key: string, params, kind: string?)
	if player.Parent then
		Net.FireClient("Notify", player, Locale.TP(player, key, params), kind or "success")
	end
end

-- Verse les paliers atteints et pas encore récupérés. Renvoie (FC Coins, objet).
local function payTiers(player: Player, data, theme): (number, string?)
	local state = data.events
	local reached = Events.TiersReached(state.points)
	local coins, cosmetic = 0, nil
	while state.claimed < reached do
		state.claimed += 1
		local tier = Events.TIERS[state.claimed]
		local amount = Events.TierCoins(state.claimed, data.club.division)
		if amount > 0 then
			EconomyService.Add(player, amount, ("event:%s:%d"):format(theme and theme.id or "?", state.claimed))
			coins += amount
		end
		if tier.cosmetic and theme and theme.cosmetic and not data.cosmetics.owned[theme.cosmetic] then
			if CosmeticService.GrantEvent(player, theme.cosmetic) then
				cosmetic = theme.cosmetic
			end
		end
	end
	return coins, cosmetic
end

-- Nouvelle semaine : paliers oubliés versés, puis points remis à zéro.
local function refresh(player: Player, data)
	local week = Events.Week(os.time())
	local state = data.events
	if state.week == week then
		return
	end
	if state.week >= 0 and state.claimed < Events.TiersReached(state.points) then
		local coins = payTiers(player, data, Events.ThemeForWeek(state.week))
		if coins > 0 then
			notify(player, "event.autoClaimed", { coins = coins })
		end
	end
	data.events = { week = week, points = 0, claimed = 0 }
	PlayerDataService.MarkChanged(player)
end

-- Bonus de FC Coins du thème pour un match (déjà compris dans le total).
-- income = { match, tickets, sponsor, shop } ; human = adversaire réel.
function EventService.MatchBonus(player: Player, data, income, goals: number, human: boolean): number
	refresh(player, data)
	return Events.MatchBonus(Events.Current(os.time()), income, goals, human, data.club.division)
end

-- Points d'événement d'un match. Renvoie les points gagnés.
function EventService.OnMatchPlayed(player: Player, outcome: string, goals: number, human: boolean): number
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	refresh(player, data)
	local points = Events.MatchPoints(Events.Current(os.time()), outcome, goals, human)
	return EventService.AddPoints(player, points)
end

function EventService.AddPoints(player: Player, points: number): number
	local data = PlayerDataService.GetData(player)
	if not data or type(points) ~= "number" or points ~= points or points <= 0 then
		return 0
	end
	refresh(player, data)
	local state = data.events
	local before = Events.TiersReached(state.points)
	state.points += math.floor(points)
	if Events.TiersReached(state.points) > before then
		notify(player, "event.tierReached", { tier = Events.TiersReached(state.points) })
	end
	PlayerDataService.MarkChanged(player)
	return math.floor(points)
end

-- Coupe du week-end : points selon le tour atteint (seulement le week-end).
function EventService.AddCupPoints(player: Player, place: string): number
	if not Events.IsWeekend(os.time()) then
		return 0
	end
	return EventService.AddPoints(player, Events.CUP_POINTS[place] or 0)
end

function EventService.TryClaim(player: Player): (boolean, string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	refresh(player, data)
	if data.events.claimed >= Events.TiersReached(data.events.points) then
		return false, Locale.TP(player, "event.error.nothing")
	end
	local coins, cosmetic = payTiers(player, data, Events.Current(os.time()))
	PlayerDataService.MarkChanged(player)
	local lang = Locale.ForPlayer(player)
	if cosmetic then
		return true, Locale.T(lang, "event.claimedCosmetic", { coins = coins, name = Locale.T(lang, "cosmetic." .. cosmetic) })
	end
	return true, Locale.T(lang, "event.claimed", { coins = coins })
end

-- Partie « event » de l'instantané envoyé au client (lecture seule).
function EventService.Snapshot(player: Player, data)
	local now = os.time()
	local week = Events.Week(now)
	local theme = Events.Current(now)
	local state = data.events
	local points = if state.week == week then state.points else 0
	local claimed = if state.week == week then state.claimed else 0
	local tiers = {}
	for index, tier in Events.TIERS do
		table.insert(tiers, {
			points = tier.points,
			coins = Events.TierCoins(index, data.club.division),
			cosmetic = if tier.cosmetic then theme.cosmetic else nil,
			claimed = index <= claimed,
			reached = points >= tier.points,
		})
	end
	local weekendStartsAt = Events.WeekendStartsAt(now)
	return {
		week = week,
		theme = theme.id,
		points = points,
		tiers = tiers,
		endsIn = math.max(0, Events.WeekEndsAt(week) - now),
		weekend = Events.IsWeekend(now),
		weekendIn = if weekendStartsAt then math.max(0, weekendStartsAt - now) else 0,
		cupMultiplier = Events.WEEKEND_CUP_MULTIPLIER,
		cosmeticOwned = data.cosmetics.owned[theme.cosmetic] == true,
	}
end

function EventService.OnPlayerReady(player: Player)
	local data = PlayerDataService.GetData(player)
	if data then
		refresh(player, data)
	end
end

function EventService.Init()
	PlayerDataService.AddSnapshotField("event", EventService.Snapshot)
	Net.Handle("RequestEventClaim", function(player)
		local ok, message = EventService.TryClaim(player)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
	end)
end

return EventService
