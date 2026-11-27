--[[
	EuroService
	Coupe d'Europe des clubs entre vrais joueurs de tous les serveurs
	(règles et montants : shared/EuroCup.lua).

	Réservoir commun : MemoryStoreService, une SortedMap par édition
	(« EuroPool_v1_<semaine> »), clé = UserId, valeur = photo du club
	(EuroCup.SanitizeSnapshot). Chaque club de D3+ y publie sa photo à
	l'arrivée puis au plus toutes les 15 min ; un serveur lit au plus une
	liste par minute (cache partagé par ses joueurs). Les quotas MemoryStore
	(1 000 + 100 × joueurs requêtes par minute) restent très loin.

	Si MemoryStore est indisponible (Studio, panne) : le groupe est formé avec
	les clubs de ce serveur et des clubs fictifs, sans erreur pour le joueur.

	Profil : data.euro = {
		edition, status ("idle" | "group" | "semi" | "final" | "out" | "champion"),
		round (journée de groupe 1..7), lastPlayedAt, scope ("global" | "server"),
		group = { 8 × { kind = "me" } | { kind = "club", snap } | { kind = "ai", division, rival } },
		standings = { 8 × { p, w, d, l, gf, ga, pts } },
		knockout = { semi, otherA, otherB, final, rank },
		history = { { stage, opponent, myGoals, theirGoals, penalties, outcome, coins } },
	}
	Le groupe est figé à l'inscription : les photos ne changent plus de la
	semaine (pas de lecture réseau pendant les matchs).
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Divisions = require(Shared.Divisions)
local EuroCup = require(Shared.EuroCup)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Tactics = require(Shared.Tactics)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local MatchService = require(script.Parent.MatchService)
local SquadService = require(script.Parent.SquadService)

local EuroService = {}

local rng = Random.new()
local STATUSES = { idle = true, group = true, semi = true, final = true, out = true, champion = true }
local ACTIVE = { group = true, semi = true, final = true }

local joining = {} -- [player] = true pendant la formation du groupe (lecture réseau)
local lastPublish = {} -- [UserId] = os.time() de la dernière photo publiée
local poolCache = { edition = -1, at = -math.huge, list = {}, ok = false }

-- Photo du club ------------------------------------------------------------

function EuroService.BuildSnapshot(player: Player, data)
	local team = MatchService.ClubTeam(player)
	if not team then
		return nil
	end
	local squad = {}
	for _, footballer in team.squad do
		if #squad >= EuroCup.MAX_SNAPSHOT_PLAYERS then
			break
		end
		table.insert(squad, { n = footballer.name, p = footballer.position, r = footballer.rating })
	end
	return EuroCup.SanitizeSnapshot({
		u = player.UserId,
		n = data.club.name,
		d = data.club.division,
		s = squad,
		t = team.tactic,
		b = team.bonus,
	})
end

local function poolMap(edition: number)
	return MemoryStoreService:GetSortedMap(EuroCup.POOL_PREFIX .. edition)
end

-- Publie la photo du club (appel réseau : à lancer dans une tâche).
function EuroService.Publish(player: Player, force: boolean?): boolean
	local data = PlayerDataService.GetData(player)
	local profile = PlayerDataService.Get(player)
	if not data or (profile and profile.temporary) or not EuroCup.IsEligible(data.club.division) then
		return false
	end
	local now = os.time()
	if not force and now - (lastPublish[player.UserId] or -math.huge) < EuroCup.PUBLISH_SECONDS then
		return false
	end
	local snapshot = EuroService.BuildSnapshot(player, data)
	if not snapshot then
		return false
	end
	lastPublish[player.UserId] = now
	local edition = EuroCup.Edition(now)
	local expiration = math.max(60, EuroCup.EditionEndsAt(edition) - now + EuroCup.POOL_EXPIRATION_EXTRA)
	local ok, err = pcall(function()
		poolMap(edition):SetAsync(tostring(player.UserId), snapshot, expiration)
	end)
	if not ok then
		warn("[Euro] photo du club non publiée : " .. tostring(err))
	end
	return ok
end

-- Liste des clubs du réservoir (cache d'une minute pour tout le serveur).
local function readPool(edition: number)
	local now = os.time()
	if poolCache.edition == edition and now - poolCache.at < EuroCup.POOL_CACHE_SECONDS then
		return poolCache.list, poolCache.ok
	end
	local ok, items = pcall(function()
		return poolMap(edition):GetRangeAsync(Enum.SortDirection.Ascending, EuroCup.POOL_READ_COUNT)
	end)
	local list = {}
	if ok and type(items) == "table" then
		for _, item in items do
			local snapshot = type(item) == "table" and EuroCup.SanitizeSnapshot(item.value)
			if snapshot then
				table.insert(list, snapshot)
			end
		end
	elseif not ok then
		warn("[Euro] réservoir commun illisible : " .. tostring(items))
	end
	poolCache = { edition = edition, at = now, list = list, ok = ok }
	return list, ok
end

-- État du profil ------------------------------------------------------------

local function emptyStanding()
	return { p = 0, w = 0, d = 0, l = 0, gf = 0, ga = 0, pts = 0 }
end

local function validEntry(entry): boolean
	if type(entry) ~= "table" then
		return false
	end
	if entry.kind == "me" then
		return true
	elseif entry.kind == "club" then
		return EuroCup.SanitizeSnapshot(entry.snap) ~= nil
	elseif entry.kind == "ai" then
		return Divisions.GetRival(entry.division, entry.rival) ~= nil
	end
	return false
end

local function validGroup(euro): boolean
	if type(euro.group) ~= "table" or #euro.group ~= EuroCup.GROUP_SIZE or type(euro.standings) ~= "table" then
		return false
	end
	if type(euro.group[1]) ~= "table" or euro.group[1].kind ~= "me" then
		return false
	end
	for index = 1, EuroCup.GROUP_SIZE do
		if not validEntry(euro.group[index]) or type(euro.standings[index]) ~= "table" then
			return false
		end
	end
	return true
end

local function newEdition(edition: number)
	return {
		edition = edition,
		status = "idle",
		round = 1,
		lastPlayedAt = 0,
		scope = "global",
		group = {},
		standings = {},
		knockout = {},
		history = {},
	}
end

-- Nouvelle édition, ancien profil ou valeurs abîmées : état valide.
local function refresh(data): boolean
	local edition = EuroCup.Edition(os.time())
	local euro = data.euro
	if type(euro) ~= "table" or euro.edition ~= edition then
		data.euro = newEdition(edition)
		return true
	end
	local changed = false
	if not STATUSES[euro.status] then
		euro.status = "idle"
		changed = true
	end
	if type(euro.round) ~= "number" or euro.round ~= euro.round then
		euro.round = 1
		changed = true
	end
	euro.round = math.clamp(math.floor(euro.round), 1, EuroCup.GROUP_ROUNDS)
	if type(euro.lastPlayedAt) ~= "number" or euro.lastPlayedAt ~= euro.lastPlayedAt or euro.lastPlayedAt > os.time() then
		euro.lastPlayedAt = 0
		changed = true
	end
	if type(euro.history) ~= "table" then
		euro.history = {}
		changed = true
	end
	if type(euro.knockout) ~= "table" then
		euro.knockout = {}
		changed = true
	end
	if euro.status ~= "idle" and not validGroup(euro) then
		-- Groupe illisible : on repart de l'inscription (rien n'est perdu, les
		-- primes déjà versées restent acquises).
		data.euro = newEdition(edition)
		return true
	end
	if euro.status == "semi" and not euro.group[euro.knockout.semi or 0] then
		euro.status = "out"
		changed = true
	elseif euro.status == "final" and not euro.group[euro.knockout.final or 0] then
		euro.status = "out"
		changed = true
	end
	return changed
end

local function secondsUntilNextMatch(euro): number
	return math.max(0, EuroCup.MATCH_SECONDS - (os.time() - (euro.lastPlayedAt or 0)))
end

-- Équipes --------------------------------------------------------------------

local function snapshotTeam(snap)
	local squad = {}
	for _, footballer in snap.s do
		table.insert(squad, { name = footballer.n, position = footballer.p, rating = footballer.r, energy = 80 })
	end
	return {
		id = "euro:" .. snap.u,
		name = snap.n,
		squad = squad,
		tactic = Tactics.Sanitize(snap.t),
		bonus = snap.b or 0,
	}
end

local function entryTeam(player: Player, entry)
	if entry.kind == "me" then
		return MatchService.ClubTeam(player)
	elseif entry.kind == "club" then
		return snapshotTeam(EuroCup.SanitizeSnapshot(entry.snap))
	end
	return MatchService.RivalTeam(entry.division, entry.rival)
end

-- Infos affichées d'un club du groupe.
local function entryInfo(data, entry)
	if entry.kind == "me" then
		return { name = data.club.name, division = data.club.division, me = true }
	elseif entry.kind == "club" then
		local snap = EuroCup.SanitizeSnapshot(entry.snap)
		return {
			name = snap.n,
			division = snap.d,
			rating = EuroCup.Strength(snap),
			tactic = snap.t,
			human = true,
		}
	end
	local rival = Divisions.GetRival(entry.division, entry.rival)
	return { name = rival.name, division = entry.division, rating = rival.rating, tactic = rival.tactic, human = false }
end

-- Formation du groupe ----------------------------------------------------------

local function myStrength(player: Player, data): number
	local snap = EuroService.BuildSnapshot(player, data)
	return if snap then EuroCup.Strength(snap) else 0
end

-- Clubs de D3+ présents sur ce serveur (photo à jour, sans réseau).
local function serverClubs(except: Player)
	local list = {}
	for _, other in PlayerDataService.GetLoadedPlayers() do
		if other ~= except then
			local otherData = PlayerDataService.GetData(other)
			if otherData and EuroCup.IsEligible(otherData.club.division) then
				local snap = EuroService.BuildSnapshot(other, otherData)
				if snap then
					table.insert(list, snap)
				end
			end
		end
	end
	return list
end

-- Les 7 adversaires : clubs réels les plus proches en force, puis clubs fictifs.
function EuroService.BuildGroup(player: Player, data, pool)
	local mine = myStrength(player, data)
	local seen = { [player.UserId] = true }
	local candidates = {}
	for _, snap in pool do
		if not seen[snap.u] then
			seen[snap.u] = true
			table.insert(candidates, snap)
		end
	end
	table.sort(candidates, function(a, b)
		local da, db = math.abs(EuroCup.Strength(a) - mine), math.abs(EuroCup.Strength(b) - mine)
		if da ~= db then
			return da < db
		end
		return a.u < b.u
	end)
	local opponents = {}
	for index = 1, math.min(EuroCup.GROUP_SIZE - 1, #candidates) do
		table.insert(opponents, { kind = "club", snap = candidates[index] })
	end
	-- Complément : clubs fictifs de la division du club, puis de la voisine.
	local division = Divisions.Get(data.club.division) or Divisions.List[#Divisions.List]
	local neighbour = Divisions.List[division.index + 1] or Divisions.List[division.index - 1]
	local fill = {}
	for rival = 1, #Divisions.RIVALS do
		table.insert(fill, { kind = "ai", division = division.id, rival = rival })
	end
	for rival = 1, #Divisions.RIVALS do
		table.insert(fill, { kind = "ai", division = neighbour.id, rival = rival })
	end
	local fillIndex = 1
	while #opponents < EuroCup.GROUP_SIZE - 1 do
		table.insert(opponents, fill[fillIndex])
		fillIndex += 1
	end
	-- Ordre du calendrier tiré au sort.
	for i = #opponents, 2, -1 do
		local j = rng:NextInteger(1, i)
		opponents[i], opponents[j] = opponents[j], opponents[i]
	end
	local group = { { kind = "me" } }
	for _, entry in opponents do
		table.insert(group, entry)
	end
	return group
end

function EuroService.TryJoin(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, Locale.TP(player, "error.profileNotLoaded")
	end
	refresh(data)
	if not EuroCup.IsEligible(data.club.division) then
		return false, Locale.TP(player, "euro.error.locked", { division = EuroCup.UNLOCK_DIVISION })
	end
	if data.euro.status ~= "idle" then
		return false, Locale.TP(player, "euro.error.alreadyJoined")
	end
	if #data.squad == 0 then
		return false, Locale.TP(player, "error.emptySquad")
	end
	if joining[player] then
		return false, nil
	end
	joining[player] = true
	local edition = data.euro.edition
	-- Lecture réseau (peut attendre) : tout est revérifié ensuite.
	EuroService.Publish(player, true)
	local okPool, pool, global = pcall(readPool, edition)
	joining[player] = nil
	if not okPool then
		pool, global = {}, false
	end
	if PlayerDataService.GetData(player) ~= data or not player.Parent then
		return false, nil
	end
	refresh(data)
	if data.euro.edition ~= edition or data.euro.status ~= "idle" then
		return false, nil
	end
	local candidates = table.clone(pool)
	for _, snap in serverClubs(player) do
		table.insert(candidates, 1, snap) -- photo la plus récente d'abord
	end
	local group = EuroService.BuildGroup(player, data, candidates)
	local standings = {}
	for index = 1, EuroCup.GROUP_SIZE do
		standings[index] = emptyStanding()
	end
	data.euro.group = group
	data.euro.standings = standings
	data.euro.status = "group"
	data.euro.round = 1
	data.euro.scope = if global then "global" else "server"
	data.euro.knockout = {}
	PlayerDataService.MarkChanged(player)
	return true, nil
end

-- Classement ------------------------------------------------------------------

-- Index du groupe triés : points, différence de buts, buts marqués, puis ordre.
function EuroService.Ranking(standings)
	local order = {}
	for index = 1, #standings do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		local sa, sb = standings[a], standings[b]
		if sa.pts ~= sb.pts then
			return sa.pts > sb.pts
		end
		local ga, gb = sa.gf - sa.ga, sb.gf - sb.ga
		if ga ~= gb then
			return ga > gb
		end
		if sa.gf ~= sb.gf then
			return sa.gf > sb.gf
		end
		return a < b
	end)
	return order
end

local function record(standings, a: number, b: number, goalsA: number, goalsB: number)
	local sa, sb = standings[a], standings[b]
	sa.p += 1
	sb.p += 1
	sa.gf += goalsA
	sa.ga += goalsB
	sb.gf += goalsB
	sb.ga += goalsA
	if goalsA > goalsB then
		sa.w += 1
		sa.pts += 3
		sb.l += 1
	elseif goalsA < goalsB then
		sb.w += 1
		sb.pts += 3
		sa.l += 1
	else
		sa.d += 1
		sb.d += 1
		sa.pts += 1
		sb.pts += 1
	end
end

-- Match entre deux clubs du groupe qui ne sont pas le joueur.
local function simulateOthers(player: Player, euro, a: number, b: number)
	local teamA = entryTeam(player, euro.group[a])
	local teamB = entryTeam(player, euro.group[b])
	local score = MatchService.Simulate(teamA, teamB)
	return score.homeGoals, score.awayGoals
end

-- Match du joueur ------------------------------------------------------------------

function EuroService.TryPlay(player: Player, tactic)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, Locale.TP(player, "error.profileNotLoaded")
	end
	refresh(data)
	local euro = data.euro
	if euro.status == "idle" then
		return nil, Locale.TP(player, "euro.error.notJoined")
	elseif euro.status == "champion" then
		return nil, Locale.TP(player, "euro.error.champion")
	elseif euro.status == "out" then
		return nil, Locale.TP(player, "euro.error.out")
	end
	local wait = secondsUntilNextMatch(euro)
	if wait > 0 then
		return nil, Locale.TP(player, "euro.error.wait", { minutes = math.max(1, math.ceil(wait / 60)) })
	end
	if #data.squad == 0 then
		return nil, Locale.TP(player, "error.emptySquad")
	end
	-- Comme en championnat : pas de match sans titulaire disponible.
	if #SquadService.Starters(data) == 0 and not SquadService.ClearSuspensionsIfStuck(data) then
		return nil, Locale.TP(player, "injury.noneAvailable", { minutes = SquadService.NextReturnMinutes(data) })
	end
	if not Tactics.IsValid(tactic) then
		tactic = Tactics.Sanitize(data.tactic)
	end
	data.tactic = tactic

	local stage = euro.status
	local opponentIndex
	if stage == "group" then
		opponentIndex = EuroCup.Fixtures(euro.round)[1][2]
	elseif stage == "semi" then
		opponentIndex = euro.knockout.semi
	else
		opponentIndex = euro.knockout.final
	end
	local home = MatchService.ClubTeam(player)
	local away = entryTeam(player, euro.group[opponentIndex])
	if not home or not away then
		return nil, Locale.TP(player, "error.invalidOpponent")
	end
	local score = MatchService.Simulate(home, away)
	local myGoals, theirGoals = score.homeGoals, score.awayGoals
	local division = data.club.division
	local coins = 0
	local penalties = false
	local outcome
	local qualified, eliminated, champion = false, false, false
	local rank = nil

	if stage == "group" then
		record(euro.standings, 1, opponentIndex, myGoals, theirGoals)
		for index, pair in EuroCup.Fixtures(euro.round) do
			if index > 1 then
				local ga, gb = simulateOthers(player, euro, pair[1], pair[2])
				record(euro.standings, pair[1], pair[2], ga, gb)
			end
		end
		outcome = if myGoals > theirGoals then "Win" elseif myGoals < theirGoals then "Loss" else "Draw"
		if outcome == "Win" then
			coins += EuroCup.Reward("groupWin", division)
		elseif outcome == "Draw" then
			coins += EuroCup.Reward("groupDraw", division)
		end
		if euro.round >= EuroCup.GROUP_ROUNDS then
			local order = EuroService.Ranking(euro.standings)
			for position, index in order do
				if index == 1 then
					rank = position
				end
			end
			euro.knockout.rank = rank
			if rank <= EuroCup.QUALIFIED then
				qualified = true
				coins += EuroCup.Reward("qualified", division)
				local semiPairs = { { order[1], order[4] }, { order[2], order[3] } }
				for _, pair in semiPairs do
					if pair[1] == 1 or pair[2] == 1 then
						euro.knockout.semi = if pair[1] == 1 then pair[2] else pair[1]
					else
						euro.knockout.otherA, euro.knockout.otherB = pair[1], pair[2]
					end
				end
				euro.status = "semi"
			else
				eliminated = true
				euro.status = "out"
			end
		else
			euro.round += 1
		end
	else
		penalties = myGoals == theirGoals
		local won = if penalties then rng:NextNumber() < 0.5 else myGoals > theirGoals
		outcome = if won then "Win" else "Loss"
		if stage == "semi" then
			if won then
				coins += EuroCup.Reward("semiWin", division)
				local a, b = euro.knockout.otherA, euro.knockout.otherB
				local ga, gb = simulateOthers(player, euro, a, b)
				local winner = if ga > gb then a elseif gb > ga then b elseif rng:NextNumber() < 0.5 then a else b
				euro.knockout.final = winner
				euro.status = "final"
			else
				eliminated = true
				euro.status = "out"
			end
		else
			data.club.stats.euroFinals = (data.club.stats.euroFinals or 0) + 1
			if won then
				champion = true
				coins += EuroCup.Reward("finalWin", division)
				euro.status = "champion"
				data.club.stats.euroWon = (data.club.stats.euroWon or 0) + 1
			else
				eliminated = true
				euro.status = "out"
			end
		end
	end
	if coins > 0 then
		EconomyService.Add(player, coins, ("euro:%d:%s:%d"):format(euro.edition, stage, #euro.history + 1))
	end
	local opponentInfo = entryInfo(data, euro.group[opponentIndex])
	table.insert(euro.history, {
		stage = stage,
		round = if stage == "group" then #euro.history + 1 else nil,
		opponent = opponentIndex,
		myGoals = myGoals,
		theirGoals = theirGoals,
		penalties = penalties,
		outcome = outcome,
		coins = coins,
	})
	euro.lastPlayedAt = os.time()
	PlayerDataService.MarkChanged(player)

	-- Replay 3D : construit en dernier, il ne peut rien changer au résultat.
	local okReplay, replay = pcall(MatchService.BuildReplay, player, data, home, away, score)
	if not okReplay then
		warn("[Euro] replay non construit : " .. tostring(replay))
		replay = nil
	end
	return {
		mode = "euro",
		stage = stage,
		homeName = home.name,
		awayName = away.name,
		awayHuman = opponentInfo.human == true,
		homeGoals = myGoals,
		awayGoals = theirGoals,
		events = score.events,
		outcome = outcome,
		penalties = penalties,
		qualified = qualified,
		eliminated = eliminated,
		champion = champion,
		rank = rank,
		coins = coins,
		tactics = score.tactics,
		replay = replay,
	}
end

-- Instantané client ----------------------------------------------------------------

function EuroService.Snapshot(_player: Player, data)
	refresh(data)
	local euro = data.euro
	local division = data.club.division
	local result = {
		eligible = EuroCup.IsEligible(division),
		unlockDivision = EuroCup.UNLOCK_DIVISION,
		edition = euro.edition,
		status = euro.status,
		scope = euro.scope,
		round = euro.round,
		rounds = EuroCup.GROUP_ROUNDS,
		qualifiedCount = EuroCup.QUALIFIED,
		nextIn = if ACTIVE[euro.status] then secondsUntilNextMatch(euro) else 0,
		endsIn = math.max(0, EuroCup.EditionEndsAt(euro.edition) - os.time()),
		maxReward = EuroCup.MaxReward(division),
		euroWon = data.club.stats.euroWon or 0,
		standings = {},
		history = {},
	}
	if euro.status == "idle" then
		return result
	end
	for position, index in EuroService.Ranking(euro.standings) do
		local row = table.clone(euro.standings[index])
		local info = entryInfo(data, euro.group[index])
		row.position = position
		row.name = info.name
		row.division = info.division
		row.me = info.me == true
		row.human = info.human == true
		table.insert(result.standings, row)
	end
	for _, entry in euro.history do
		local info = euro.group[entry.opponent] and entryInfo(data, euro.group[entry.opponent])
		table.insert(result.history, {
			stage = entry.stage,
			name = if info then info.name else "?",
			human = info ~= nil and info.human == true,
			myGoals = entry.myGoals,
			theirGoals = entry.theirGoals,
			penalties = entry.penalties == true,
			outcome = entry.outcome,
			coins = entry.coins or 0,
		})
	end
	if ACTIVE[euro.status] then
		local index
		if euro.status == "group" then
			index = EuroCup.Fixtures(euro.round)[1][2]
			result.nextReward = EuroCup.Reward("groupWin", division)
		elseif euro.status == "semi" then
			index = euro.knockout.semi
			result.nextReward = EuroCup.Reward("semiWin", division)
		else
			index = euro.knockout.final
			result.nextReward = EuroCup.Reward("finalWin", division)
		end
		result.opponent = entryInfo(data, euro.group[index])
	end
	result.rank = euro.knockout.rank
	return result
end

function EuroService.OnPlayerReady(player: Player)
	task.spawn(EuroService.Publish, player, true)
end

function EuroService.OnPlayerLeaving(player: Player)
	joining[player] = nil
	lastPublish[player.UserId] = nil
end

function EuroService.Init()
	PlayerDataService.AddSnapshotField("euro", EuroService.Snapshot)
	Net.Handle("RequestEuroJoin", function(player)
		local ok, err = EuroService.TryJoin(player)
		if ok then
			Net.FireClient("Notify", player, Locale.TP(player, "euro.joined"), "success")
		elseif err then
			Net.FireClient("Notify", player, err, "error")
		end
	end)
	Net.Handle("RequestEuroMatch", function(player, tactic)
		local result, err = EuroService.TryPlay(player, tactic)
		if result then
			Net.FireClient("MatchResult", player, result)
		elseif err then
			Net.FireClient("Notify", player, err, "error")
		end
	end)
	-- Photos des clubs connectés, au plus une toutes les 15 min chacune.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local ok, err = pcall(EuroService.Publish, player)
				if not ok then
					warn("[Euro] " .. tostring(err))
				end
			end
		end
	end)
end

return EuroService
