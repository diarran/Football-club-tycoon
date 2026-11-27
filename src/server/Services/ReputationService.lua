--[[
	ReputationService
	Réputation du club et conférences de presse (règles : shared/Reputation.lua).

	Profil : data.reputation = {
		score,       -- 0 à 100 (-1 = pas encore calculée : ancienne sauvegarde)
		pending,     -- question en attente { id, topic, at } (id = 0 : aucune)
		buzz,        -- effet de la dernière réponse { kind, matches }
		sincePress,  -- matchs du championnat depuis la dernière conférence
		streak,      -- victoires d'affilée en championnat
		nextId, answered, provocative,
	}

	Le serveur décide seul quand une conférence a lieu ; le client répond
	seulement « humble », « ambitious », « provocative » ou « skip ».
	Les effets ne retirent jamais d'argent : au pire, rien ne se passe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local Reputation = require(Shared.Reputation)

local PlayerDataService = require(script.Parent.PlayerDataService)

local ReputationService = {}

local function tierOf(data): number
	local division = Divisions.Get(data.club.division)
	return division and division.tier or 7
end

local function standsOf(data): number
	return data.buildings and data.buildings.Stands or 1
end

-- Prépare data.reputation (ancien profil, valeurs abîmées) et renvoie l'état.
function ReputationService.Ensure(data)
	local state = data.reputation
	if type(state) ~= "table" then
		state = {}
		data.reputation = state
	end
	if type(state.pending) ~= "table" then
		state.pending = { id = 0, topic = "", at = 0 }
	end
	if type(state.buzz) ~= "table" then
		state.buzz = { kind = "", matches = 0 }
	end
	for _, field in { "sincePress", "streak", "nextId", "answered" } do
		if type(state[field]) ~= "number" or state[field] ~= state[field] then
			state[field] = if field == "nextId" then 1 elseif field == "sincePress" then Reputation.PRESS_GAP else 0
		end
	end
	if type(state.score) ~= "number" or state.score ~= state.score or state.score < 0 then
		state.score = Reputation.Initial(tierOf(data), standsOf(data))
	else
		state.score = Reputation.Clamp(state.score, tierOf(data), standsOf(data))
	end
	-- Question trop ancienne : elle disparaît sans conséquence.
	local pending = state.pending
	if (pending.id or 0) ~= 0 and (os.time() - (pending.at or 0) > Reputation.PRESS_EXPIRES or not Reputation.IsTopic(pending.topic)) then
		state.pending = { id = 0, topic = "", at = 0 }
	end
	return state
end

-- Ajoute (ou retire) des points de réputation, entre le plancher et le plafond.
function ReputationService.Add(data, delta: number): number
	local state = ReputationService.Ensure(data)
	local before = state.score
	state.score = Reputation.Clamp(before + delta, tierOf(data), standsOf(data))
	return state.score - before
end

-- Ouvre une conférence de presse si le sujet s'y prête.
local function openPress(data, topic: string?): boolean
	if not topic or not Reputation.IsTopic(topic) then
		return false
	end
	if not (data.tutorial and data.tutorial.completed) then
		return false -- pas de journalistes pendant le tutoriel
	end
	local state = ReputationService.Ensure(data)
	if state.sincePress < Reputation.PRESS_GAP and not Reputation.PriorityTopics[topic] then
		return false
	end
	state.pending = { id = state.nextId, topic = topic, at = os.time() }
	state.nextId += 1
	state.sincePress = 0
	return true
end

-- Bonus du buzz pour ce match du championnat (ajouté aux gains, jamais retiré).
-- incomes = { tickets, sponsor, contracts }
function ReputationService.MatchBonus(data, incomes): number
	local buzz = ReputationService.Ensure(data).buzz
	if (buzz.matches or 0) <= 0 then
		return 0
	end
	if buzz.kind == "fans" then
		return math.floor((incomes.tickets or 0) * Reputation.FANS_BUZZ + 0.5)
	elseif buzz.kind == "sponsors" then
		return math.floor(((incomes.sponsor or 0) + (incomes.contracts or 0)) * Reputation.SPONSOR_BUZZ + 0.5)
	end
	return 0
end

--[[
	Après un match du championnat (MatchService).
	match = { outcome, goalsFor, goalsAgainst, vsClub, promoted }
	Renvoie { delta, score, press } (press = true si une question attend).
]]
function ReputationService.OnLeagueMatch(_player: Player, data, match)
	local state = ReputationService.Ensure(data)
	local gains = Reputation.Gains
	local delta = gains[match.outcome] or 0
	local margin = (match.goalsFor or 0) - (match.goalsAgainst or 0)
	if match.outcome == "Win" then
		state.streak += 1
		if margin >= Reputation.BIG_MARGIN then
			delta += gains.bigWin
		end
		if match.vsClub then
			delta += gains.vsClub
		end
	else
		state.streak = 0
	end
	-- Réponse provocante : la presse attend le match suivant au tournant.
	if state.provocative then
		state.provocative = false
		if match.outcome == "Loss" then
			delta += gains.provocativeLoss
		end
	end
	-- Le plafond monte avec la division : la montée est comptée après.
	local applied = ReputationService.Add(data, delta)
	if match.promoted then
		applied += ReputationService.Add(data, gains.promotion)
	end
	if state.buzz.matches > 0 then
		state.buzz.matches -= 1
		if state.buzz.matches <= 0 then
			state.buzz = { kind = "", matches = 0 }
		end
	end
	state.sincePress += 1
	local press = openPress(data, Reputation.LeagueTopic({
		outcome = match.outcome,
		goalsFor = match.goalsFor,
		goalsAgainst = match.goalsAgainst,
		vsClub = match.vsClub,
		promoted = match.promoted,
		streak = state.streak,
	}))
	return { delta = applied, score = state.score, press = press }
end

-- Après un tour de Coupe nationale (CupService).
function ReputationService.OnCupRound(player: Player, data, won: boolean, giantKill: boolean, champion: boolean)
	if not won then
		return { delta = 0, score = ReputationService.Ensure(data).score, press = false }
	end
	local gains = Reputation.Gains
	local delta = gains.cupRound + (if giantKill then gains.cupGiant else 0) + (if champion then gains.cupChampion else 0)
	local applied = ReputationService.Add(data, delta)
	local topic = if champion then "cupChampion" elseif giantKill then "cupWin" else nil
	local press = openPress(data, topic)
	PlayerDataService.MarkChanged(player)
	return { delta = applied, score = data.reputation.score, press = press }
end

-- Tournoi du serveur gagné (TournamentService).
function ReputationService.OnTournamentWon(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	ReputationService.Add(data, Reputation.Gains.tournament)
	openPress(data, "tournament")
	PlayerDataService.MarkChanged(player)
end

-- Réponse du joueur : "humble", "ambitious", "provocative" ou "skip".
function ReputationService.TryAnswer(player: Player, answer): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	local state = ReputationService.Ensure(data)
	if (state.pending.id or 0) == 0 then
		return false, Locale.TP(player, "press.error.none")
	end
	if answer == "skip" then
		state.pending = { id = 0, topic = "", at = 0 }
		PlayerDataService.MarkChanged(player)
		return true, nil
	end
	if not Reputation.IsAnswer(answer) then
		return false, Locale.TP(player, "press.error.invalid")
	end
	local effect = Reputation.AnswerEffects[answer]
	state.pending = { id = 0, topic = "", at = 0 }
	state.answered += 1
	ReputationService.Add(data, effect.reputation)
	state.buzz = { kind = effect.buzz, matches = Reputation.BUZZ_MATCHES }
	state.provocative = answer == "provocative"
	if effect.buzz == "morale" then
		for _, footballer in data.squad do
			footballer.energy = math.min(PlayerConfig.MAX_ENERGY, (footballer.energy or 0) + Reputation.MORALE_ENERGY)
		end
	end
	PlayerDataService.MarkChanged(player)
	return true, Locale.TP(player, "press.done." .. effect.buzz, {
		matches = Reputation.BUZZ_MATCHES,
		percent = math.floor(
			(if effect.buzz == "fans" then Reputation.FANS_BUZZ else Reputation.SPONSOR_BUZZ) * 100 + 0.5
		),
		energy = Reputation.MORALE_ENERGY,
	})
end

-- Champ « reputation » de l'instantané client.
function ReputationService.Snapshot(_player: Player, data)
	local state = ReputationService.Ensure(data)
	local tier = tierOf(data)
	local pending = nil
	if state.pending.id ~= 0 then
		pending = {
			id = state.pending.id,
			topic = state.pending.topic,
			expiresIn = math.max(0, Reputation.PRESS_EXPIRES - (os.time() - state.pending.at)),
		}
	end
	return {
		score = state.score,
		level = Reputation.Level(state.score),
		cap = Reputation.Cap(tier),
		floor = Reputation.Floor(tier, standsOf(data)),
		sponsorPercent = math.floor((Reputation.SponsorMultiplier(state.score) - 1) * 100 + 0.5),
		buzz = if state.buzz.matches > 0 then { kind = state.buzz.kind, matches = state.buzz.matches } else nil,
		pending = pending,
	}
end

function ReputationService.OnPlayerReady(_player: Player, profile)
	ReputationService.Ensure(profile.data)
end

function ReputationService.Init()
	PlayerDataService.AddSnapshotField("reputation", ReputationService.Snapshot)
	Net.Handle("RequestPressAnswer", function(player, answer)
		local ok, message = ReputationService.TryAnswer(player, answer)
		if message then
			Net.FireClient("Notify", player, message, if ok then "success" else "error")
		end
	end)
end

return ReputationService
