-- Coupe d'Europe des clubs : groupes de 8 clubs de vrais joueurs de tous les
-- serveurs (réservoir MemoryStore), 7 journées, demi-finale, finale, primes,
-- trophée, pannes du réservoir, anciens profils, onglet Matchs.
local S = H.boot(MODULES)
local Euro, EuroService, Divisions, Daily = S.EuroCup, S.EuroService, S.Divisions, S.Daily
local MatchService = S.MatchService
local p = H.join(1, "Europe")
local data = S.PlayerDataService.GetData(p)

local realSimulate = MatchService.Simulate
-- Score imposé à TOUS les matchs simulés (le reste vient de la vraie simulation).
local function forceScore(mine: number?, theirs: number?)
	if mine == nil then
		MatchService.Simulate = realSimulate
		return
	end
	MatchService.Simulate = function(home, away, weather)
		local score = realSimulate(home, away, weather)
		score.homeGoals, score.awayGoals = mine, theirs
		score.events = {}
		for i = 1, mine do
			table.insert(score.events, { minute = i, side = "home", scorer = "A" })
		end
		for i = 1, theirs do
			table.insert(score.events, { minute = 50 + i, side = "away", scorer = "B" })
		end
		return score
	end
end

local function snapshot()
	return EuroService.Snapshot(p, data)
end

local function nextMatch()
	H.advance(Euro.MATCH_SECONDS + 1)
end

local function toNextSeason()
	H.advance(Daily.SeasonEndsAt(Daily.SeasonId(os.time())) - os.time() + 5)
end

local function poolName()
	return Euro.POOL_PREFIX .. Euro.Edition(os.time())
end

-- Photo d'un club d'un autre serveur, déposée directement dans le réservoir.
local function foreignClub(userId: number, name: string, rating: number, division: string?)
	local squad = {}
	for i, position in { "GK", "DEF", "MID", "MID", "ATT" } do
		table.insert(squad, { n = "Joueur " .. i, p = position, r = rating })
	end
	local store = H.getMemoryStore(poolName())
	store.data[tostring(userId)] = { u = userId, n = name, d = division or "D2", s = squad, t = "Counter", b = 2 }
	store.expires[tostring(userId)] = os.time() + 86400
end

-- Repart d'une édition neuve au début d'une saison, dans la division voulue.
local function fresh(division: string)
	toNextSeason()
	data.club.division = division
	data.euro = nil
	snapshot()
end

H.test("règles : calendrier complet en 7 journées, primes, D3 minimum", function()
	local met = {}
	for round = 1, Euro.GROUP_ROUNDS do
		local seen = {}
		local fixtures = Euro.Fixtures(round)
		H.eq(#fixtures, 4, "4 matchs par journée")
		H.eq(fixtures[1][1], 1, "le club du joueur est dans le 1er match")
		for _, pair in fixtures do
			for _, index in pair do
				H.ok(not seen[index], "un seul match par club et par journée")
				seen[index] = true
			end
			local key = math.min(pair[1], pair[2]) .. "-" .. math.max(pair[1], pair[2])
			H.ok(not met[key], "jamais deux fois le même match : " .. key)
			met[key] = true
		end
	end
	local count = 0
	for _ in met do
		count += 1
	end
	H.eq(count, 28, "les 28 matchs du groupe")
	H.ok(not Euro.IsEligible("D7") and not Euro.IsEligible("D4"), "fermée avant la D3")
	H.ok(Euro.IsEligible("D3") and Euro.IsEligible("D1"), "ouverte de D3 à D1")
	H.eq(Euro.Reward("groupWin", "D1"), 450, "victoire de groupe en D1 (× 3)")
	H.ok(Euro.MaxReward("D1") <= 12000, "D1 : du même ordre que la Coupe nationale")
	H.eq(Euro.Edition(os.time()), Daily.SeasonId(os.time()), "une édition par saison")
end)

H.test("club de D7 : carte verrouillée, inscription refusée, rien publié", function()
	local euro = snapshot()
	H.ok(not euro.eligible, "pas encore ouverte")
	H.eq(euro.unlockDivision, "D3", "débloquée en D3")
	H.fire(p, "RequestEuroJoin")
	H.ok(H.lastNotify(p):find("D3"), "message clair")
	H.eq(data.euro.status, "idle", "pas inscrit")
	local store = H.memoryStores[poolName()]
	H.ok(store == nil or store.data["1"] == nil, "aucune photo d'un club de D7")
end)

H.test("inscription en D3 sans autres clubs : groupe de 8 complété par des clubs fictifs", function()
	fresh("D3")
	H.fire(p, "RequestEuroJoin")
	H.eq(data.euro.status, "group", "inscrit")
	H.eq(#data.euro.group, 8, "8 clubs")
	H.eq(data.euro.scope, "global", "réservoir commun lu")
	local store = H.getMemoryStore(poolName())
	H.ok(store.data["1"] ~= nil, "photo du club publiée pour les autres serveurs")
	H.eq(store.data["1"].n, data.club.name, "nom du club")
	H.ok(store.expires["1"] - os.time() <= 45 * 86400, "expiration permise")
	local euro = snapshot()
	H.eq(#euro.standings, 8, "classement de 8 lignes")
	H.ok(euro.opponent and euro.opponent.name, "1er adversaire affiché")
	H.eq(euro.round, 1, "journée 1")
	H.eq(euro.nextIn, 0, "jouable tout de suite")
	H.fire(p, "RequestEuroJoin")
	H.ok(H.lastNotify(p):find("déjà inscrit"), "pas de 2e inscription")
end)

H.test("clubs d'autres serveurs : les plus proches en force, photos abîmées ignorées", function()
	fresh("D2")
	local mine = Euro.Strength(EuroService.BuildSnapshot(p, data))
	for i = 1, 6 do
		foreignClub(1000 + i, "Club lointain " .. i, mine + i)
	end
	foreignClub(2000, "Club trop fort", 99)
	foreignClub(2001, "Club de D6", mine, "D6") -- pas encore en D3 : refusé
	local store = H.getMemoryStore(poolName())
	store.data["3000"] = { u = "x", n = 5 } -- photo illisible
	store.data["3001"] = { u = 3001, n = "Sans joueurs", d = "D1", s = {} }
	store.data["3002"] = { u = 3002, n = "Notes folles", d = "D1", s = { { n = "A", p = "ATT", r = 5000 } }, b = 999 }
	store.expires["3000"], store.expires["3001"], store.expires["3002"] = math.huge, math.huge, math.huge
	H.ok(EuroService.TryJoin(p), "inscrit")
	local names = {}
	local humans = 0
	for _, row in snapshot().standings do
		names[row.name] = true
		if row.human then
			humans += 1
		end
	end
	for i = 1, 6 do
		H.ok(names["Club lointain " .. i], "club réel proche n° " .. i)
	end
	H.ok(names["Notes folles"] or names["Club trop fort"], "7e club réel")
	H.ok(not names["Club de D6"], "club de D6 exclu")
	H.ok(not names["Sans joueurs"], "photo sans joueurs ignorée")
	H.eq(humans, 7, "7 clubs de vrais joueurs")
	for _, entry in data.euro.group do
		if entry.kind == "club" then
			H.ok(entry.snap.b <= 15, "bonus borné")
			for _, f in entry.snap.s do
				H.ok(f.r <= 99, "note bornée")
			end
		end
	end
	H.ok(snapshot().opponent.human ~= nil, "adversaire repéré comme vrai joueur")
end)

H.test("phase de groupe : 7 journées, attente de 30 min, primes exactes, match neutre", function()
	forceScore(2, 1)
	local coins = data.coins
	local energy = data.squad[1].energy
	local played, points = data.club.stats.played, data.club.divisionPoints
	H.fire(p, "RequestEuroMatch", "Pressing")
	local results = H.received(p, "MatchResult")
	local result = results[#results][1]
	H.eq(result.mode, "euro", "résultat européen")
	H.eq(result.outcome, "Win", "victoire")
	H.eq(result.coins, Euro.Reward("groupWin", "D2"), "prime de victoire")
	H.eq(data.coins, coins + result.coins, "versée une fois")
	H.eq(result.tactics.home, "Pressing", "style choisi joué")
	H.ok(result.replay and result.replay.homeGoals == 2, "replay 3D du même score")
	H.eq(data.squad[1].energy, energy, "pas d'énergie dépensée")
	H.eq(data.club.stats.played, played, "bilan de championnat inchangé")
	H.eq(data.club.divisionPoints, points, "pas de points de division")
	-- Les 3 autres matchs de la journée ont été joués aussi.
	for _, row in snapshot().standings do
		H.eq(row.p, 1, "1 match joué par chaque club : " .. row.name)
	end
	-- Délai.
	coins = data.coins
	H.fire(p, "RequestEuroMatch", "Balanced")
	H.eq(data.euro.round, 2, "trop tôt : refusé")
	H.eq(data.coins, coins, "aucune prime")
	H.ok(H.lastNotify(p):find("min"), "message d'attente")
	H.advance(Euro.MATCH_SECONDS - 60)
	H.ok(not EuroService.TryPlay(p, "Balanced"), "toujours trop tôt")
	H.advance(61)
	forceScore(1, 1)
	local draw = EuroService.TryPlay(p, "Balanced")
	H.eq(draw.outcome, "Draw", "nul possible en groupe")
	H.ok(not draw.penalties, "pas de tirs au but en groupe")
	H.eq(draw.coins, Euro.Reward("groupDraw", "D2"), "prime du nul")
	-- Bilan cohérent : autant de victoires que de défaites dans le groupe.
	local w, l, pts = 0, 0, 0
	for _, row in snapshot().standings do
		w += row.w
		l += row.l
		pts += row.pts
		H.eq(row.p, 2, "2 matchs joués : " .. row.name)
	end
	H.eq(w, l, "victoires = défaites")
	H.eq(pts, 4 * 3 + 4 * 2, "points distribués")
end)

H.test("qualifié, demi-finale, finale gagnée : coupe, trophée, plus de match", function()
	forceScore(3, 0)
	while data.euro.status == "group" do
		nextMatch()
		H.ok(EuroService.TryPlay(p, "Balanced"), "journée jouée")
	end
	H.eq(data.euro.status, "semi", "qualifié en demi-finale")
	local euro = snapshot()
	H.eq(euro.rank, 1, "1er du groupe")
	H.ok(euro.standings[1].me, "en tête du classement")
	H.ok(euro.opponent, "adversaire de demi-finale")
	H.eq(euro.standings[4].name, euro.opponent.name, "1er contre 4e")
	local coins = data.coins
	nextMatch()
	local semi = EuroService.TryPlay(p, "Balanced")
	H.eq(semi.stage, "semi", "demi-finale")
	H.eq(semi.coins, Euro.Reward("semiWin", data.club.division), "prime de demi-finale")
	H.eq(data.coins, coins + semi.coins, "versée")
	H.eq(data.euro.status, "final", "en finale")
	H.ok(snapshot().opponent, "adversaire de finale (vainqueur de l'autre demie)")
	local won = data.club.stats.euroWon or 0
	nextMatch()
	local final = EuroService.TryPlay(p, "Balanced")
	H.ok(final.champion, "Coupe d'Europe gagnée")
	H.eq(final.coins, Euro.Reward("finalWin", data.club.division), "prime de finale")
	H.eq(data.club.stats.euroWon, won + 1, "titre compté")
	local found = false
	for _, trophy in S.Trophies.Earned(data.club.division, data.club.stats, 0) do
		found = found or trophy.id == "euro_1"
	end
	H.ok(found, "trophée « Coupe d'Europe »")
	nextMatch()
	coins = data.coins
	local again, err = EuroService.TryPlay(p, "Balanced")
	H.ok(not again and err, "plus de match après le titre")
	H.eq(data.coins, coins, "aucune prime de plus")
	H.eq(snapshot().status, "champion", "affiché comme vainqueur")
	-- Toutes les primes de la semaine restent sous le maximum annoncé.
	local total = 0
	for _, entry in data.euro.history do
		total += entry.coins
	end
	H.ok(total <= Euro.MaxReward(data.club.division), "total ≤ maximum")
end)

H.test("dernier du groupe : éliminé, puis nouvelle édition le lundi", function()
	fresh("D3")
	H.ok(EuroService.TryJoin(p), "inscrit")
	forceScore(0, 2)
	while data.euro.status == "group" do
		nextMatch()
		H.ok(EuroService.TryPlay(p, "Balanced"), "journée jouée")
	end
	H.eq(data.euro.status, "out", "éliminé en groupe")
	H.ok(snapshot().rank > Euro.QUALIFIED, "hors des 4 premiers")
	nextMatch()
	H.ok(not EuroService.TryPlay(p, "Balanced"), "plus de match")
	toNextSeason()
	local euro = snapshot()
	H.eq(euro.status, "idle", "nouvelle édition : inscription à refaire")
	H.eq(#euro.history, 0, "historique vide")
end)

H.test("phase finale : un nul se règle aux tirs au but", function()
	forceScore(1, 1)
	local wins, losses = 0, 0
	for _ = 1, 16 do
		fresh("D3")
		H.ok(EuroService.TryJoin(p), "inscrit")
		data.euro.status = "semi"
		data.euro.knockout = { semi = 2, otherA = 3, otherB = 4, rank = 1 }
		local result = EuroService.TryPlay(p, "Balanced")
		H.ok(result.penalties, "tirs au but")
		if result.outcome == "Win" then
			wins += 1
			H.eq(data.euro.status, "final", "qualifié aux tirs au but")
			H.ok(data.euro.knockout.final == 3 or data.euro.knockout.final == 4, "adversaire de finale")
		else
			losses += 1
			H.eq(data.euro.status, "out", "éliminé aux tirs au but")
		end
	end
	H.ok(wins > 0 and losses > 0, ("les deux issues arrivent (%d / %d)"):format(wins, losses))
end)

H.test("réservoir en panne : groupe avec les clubs du serveur, sans erreur", function()
	fresh("D1")
	local q = H.join(2, "Voisin")
	local other = S.PlayerDataService.GetData(q)
	other.club.division = "D2"
	H.memoryAvailable = false
	local errors = #H.errors
	local ok = EuroService.TryJoin(p)
	H.ok(ok, "inscrit malgré la panne")
	H.eq(data.euro.scope, "server", "groupe du serveur")
	local found = false
	for _, row in snapshot().standings do
		found = found or (row.name == other.club.name and row.human)
	end
	H.ok(found, "club du voisin de serveur dans le groupe")
	H.eq(#H.errors, errors, "aucune erreur")
	forceScore(1, 0)
	H.ok(EuroService.TryPlay(p, "Balanced"), "le match se joue sans réservoir")
	H.memoryAvailable = true
	-- Panne d'une seule requête : même chose.
	fresh("D3")
	H.advance(Euro.POOL_CACHE_SECONDS + 1)
	H.getMemoryStore(poolName()).failNext = 5
	H.ok(EuroService.TryJoin(p), "inscrit malgré une requête refusée")
	H.getMemoryStore(poolName()).failNext = 0
	H.leave(q)
end)

H.test("budget : une lecture par minute pour tout le serveur, photos espacées", function()
	fresh("D3")
	H.advance(Euro.POOL_CACHE_SECONDS + 1)
	local store = H.getMemoryStore(poolName())
	local reads = store.reads
	H.ok(EuroService.TryJoin(p), "inscrit")
	local q = H.join(3, "Deuxième")
	local other = S.PlayerDataService.GetData(q)
	other.club.division = "D3"
	H.ok(EuroService.TryJoin(q), "2e club inscrit")
	H.eq(store.reads, reads + 1, "une seule lecture du réservoir")
	local writes = store.writes
	H.advance(10 * 60)
	H.eq(store.writes, writes, "pas de nouvelle photo avant 15 min")
	H.advance(6 * 60)
	H.ok(store.writes > writes and store.writes <= writes + 2, "une photo par club après 15 min")
	H.leave(q)
end)

H.test("anciens profils et valeurs abîmées : réparés sans perte", function()
	data.euro = nil
	H.eq(snapshot().status, "idle", "profil sans Coupe d'Europe")
	data.euro = { edition = data.euro.edition, status = "semi", round = "x", lastPlayedAt = math.huge, group = 4, history = 3 }
	local euro = snapshot()
	H.eq(euro.status, "idle", "groupe illisible : inscription à refaire")
	H.eq(euro.nextIn, 0, "heure invalide oubliée")
	H.ok(EuroService.TryJoin(p), "réinscription possible")
	data.euro.group[3] = { kind = "club", snap = { u = "?" } }
	H.eq(snapshot().status, "idle", "photo abîmée dans le profil : groupe refait")
	-- Un vrai ancien profil (avant cette version) se charge sans perte.
	local q = H.join(4, "Ancien")
	local old = S.PlayerDataService.GetData(q)
	old.euro = nil
	old.club.stats.euroWon = nil
	H.eq(EuroService.Snapshot(q, old).status, "idle", "ancien profil : inscription ouverte")
	H.ok(#S.Trophies.Earned(old.club.division, old.club.stats, 0) >= 0, "vitrine calculable")
	H.leave(q)
end)

H.test("onglet Matchs : inscription, classement, bouton, résultat puis attente", function()
	fresh("D3")
	forceScore(2, 0)
	data.tutorial.completed = true
	data.onboarding.done = true
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	H.clearSent() -- le client démarre avec le profil du moment
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.ok(H.findText(gui, "🌍 Coupe d'Europe des clubs"), "titre de la carte")
	H.click(gui, "Inscrire mon club à la Coupe d'Europe")
	H.eq(data.euro.status, "group", "inscrit depuis le bouton")
	H.flush()
	UI.OpenTab("Matches")
	H.ok(H.findText(gui, "Classement du groupe"), "classement affiché")
	H.ok(H.findText(gui, "Phase de groupe, journée 1/7 : contre "), "adversaire de la journée")
	H.click(gui, "Lancer le match européen")
	H.eq(data.euro.round, 2, "journée jouée depuis le bouton")
	H.frames(5)
	H.click(gui, "Passer") -- replay 3D, puis fenêtre de résultat
	H.ok(H.findText(gui, "+" ), "résultat affiché")
	H.click(gui, "Continuer")
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.ok(H.findText(gui, "Prochain match européen dans"), "attente affichée")
	H.ok(H.findText(gui, "✅ Groupe"), "match joué dans l'historique")
	forceScore()
end)

H.test("club de D7 dans l'onglet Matchs : carte verrouillée", function()
	data.club.division = "D7"
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.ok(H.findText(H.localPlayer.PlayerGui, "La Coupe d'Europe se débloque en"), "message de déblocage")
end)

H.finish()
