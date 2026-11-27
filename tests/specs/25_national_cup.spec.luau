-- Coupe nationale : une coupe par saison, 5 tours contre des clubs fictifs de
-- toutes les divisions (exploits possibles), un tour toutes les 20 min,
-- primes versées par le serveur, trophée, anciens profils, onglet Matchs.
local S = H.boot(MODULES)
local Cup, CupService, Divisions, Daily = S.NationalCup, S.CupService, S.Divisions, S.Daily
local MatchService = S.MatchService
local p = H.join(1, "Coupe")
local data = S.PlayerDataService.GetData(p)

local realSimulate = MatchService.Simulate
-- Score imposé (le reste du résultat vient de la vraie simulation).
local function forceScore(mine: number?, theirs: number?)
	if mine == nil then
		MatchService.Simulate = realSimulate
		return
	end
	MatchService.Simulate = function(home, away)
		local score = realSimulate(home, away)
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
	return CupService.Snapshot(p, data)
end

local function nextRound()
	H.advance(Cup.ROUND_SECONDS + 1)
end

local function toNextSeason()
	H.advance(Daily.SeasonEndsAt(Daily.SeasonId(os.time())) - os.time() + 5)
end

-- Repart d'une coupe neuve au début d'une saison (pas de lundi en plein test).
local function freshCup(division: string?)
	toNextSeason()
	data.club.division = division or data.club.division
	data.cup = nil
	snapshot()
end

H.test("règles : 5 tours, adversaires d'une division de plus à chaque tour, primes croissantes", function()
	H.eq(Cup.RoundCount(), 5, "5 tours")
	H.eq(Cup.OpponentDivision("D5", 1).id, "D6", "1er tour : division du dessous")
	H.eq(Cup.OpponentDivision("D5", 2).id, "D5", "2e tour : même division")
	H.eq(Cup.OpponentDivision("D5", 5).id, "D2", "finale : 3 divisions plus haut")
	H.eq(Cup.OpponentDivision("D7", 1).id, "D7", "D7 : pas plus bas que D7")
	H.eq(Cup.OpponentDivision("D2", 5).id, "D1", "jamais au-dessus de D1")
	H.ok(Cup.IsGiantKill("D7", "D6"), "D6 contre D7 : exploit")
	H.ok(not Cup.IsGiantKill("D6", "D6"), "même division : pas d'exploit")
	H.ok(not Cup.IsGiantKill("D1", "D1"), "D1 : pas d'exploit possible")
	for round = 2, Cup.RoundCount() do
		H.ok(Cup.REWARDS[round] > Cup.REWARDS[round - 1], "prime croissante au tour " .. round)
	end
	H.eq(Cup.Reward(1, "D7", false), Cup.REWARDS[1], "D7 : prime de base")
	H.eq(Cup.Reward(1, "D1", false), math.floor(Cup.REWARDS[1] * 3 + 0.5), "D1 : × 3")
	H.eq(Cup.Reward(2, "D7", true), math.floor(Cup.REWARDS[2] * 1.5 + 0.5), "exploit : +50 %")
	H.eq(Cup.Reward(9, "D7", false), 0, "tour inconnu : rien")
	-- Équilibre : une édition entière en D1 reste petite face aux matchs (prime D1 = 1 200 FC).
	H.ok(Cup.MaxReward("D1") <= 12000, "D1 : au plus ~10 victoires de match par semaine")
	H.eq(Cup.Edition(os.time()), Daily.SeasonId(os.time()), "une édition par saison")
end)

H.test("nouveau club : coupe prête au 1er tour, adversaire visible avec son style", function()
	local cup = snapshot()
	H.eq(cup.status, "playing", "en lice")
	H.eq(cup.round, 1, "1er tour")
	H.eq(cup.stage, "Round32", "16es de finale")
	H.eq(cup.nextIn, 0, "jouable tout de suite")
	H.ok(cup.opponent and cup.opponent.division == "D7", "adversaire de D7")
	local rival = Divisions.GetRival(data.cup.opponent.division, data.cup.opponent.rival)
	H.eq(cup.opponent.name, rival.name, "nom du club fictif")
	H.eq(cup.opponent.tactic, rival.tactic, "style affiché = style du club")
	H.eq(#cup.history, 0, "aucun tour joué")
	H.ok(cup.endsIn > 0 and cup.endsIn <= Daily.SEASON_SECONDS, "fin de l'édition")
end)

H.test("tour gagné : prime exacte, tour suivant tiré, match neutre, replay 3D", function()
	forceScore(2, 0)
	local coins = data.coins
	local energy = data.squad[1].energy
	local played, points = data.club.stats.played, data.club.divisionPoints
	local opponent = table.clone(data.cup.opponent)
	H.fire(p, "RequestCupMatch", "Pressing")
	local results = H.received(p, "MatchResult")
	local result = results[#results][1]
	H.eq(result.mode, "cup", "résultat de coupe")
	H.eq(result.outcome, "Win", "victoire")
	H.eq(result.coins, Cup.Reward(1, data.club.division, false), "prime du 1er tour")
	H.eq(data.coins, coins + result.coins, "prime versée une fois")
	H.eq(result.tactics.home, "Pressing", "style choisi joué")
	H.eq(result.tactics.away, Divisions.GetRival(opponent.division, opponent.rival).tactic, "style du club fictif")
	H.ok(result.replay and result.replay.homeGoals == 2, "replay 3D du même score")
	H.eq(data.squad[1].energy, energy, "pas d'énergie dépensée")
	H.eq(data.club.stats.played, played, "bilan de championnat inchangé")
	H.eq(data.club.divisionPoints, points, "pas de points de division")
	local cup = snapshot()
	H.eq(cup.round, 2, "8es de finale")
	H.ok(cup.opponent ~= nil, "nouvel adversaire tiré")
	H.eq(#cup.history, 1, "tour enregistré")
	H.ok(cup.history[1].won, "victoire enregistrée")
end)

H.test("délai : un seul tour toutes les 20 min, sans prime en double", function()
	forceScore(1, 0)
	local coins = data.coins
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(data.cup.round, 2, "tour refusé")
	H.eq(data.coins, coins, "aucune prime")
	H.ok(H.lastNotify(p):find("20 min") or H.lastNotify(p):find("min"), "message d'attente")
	H.ok(snapshot().nextIn > 0, "compte à rebours")
	H.advance(Cup.ROUND_SECONDS - 60)
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(data.cup.round, 2, "toujours trop tôt")
	H.advance(61)
	H.fire(p, "RequestCupMatch", "Balanced")
	H.eq(data.cup.round, 3, "tour joué après 20 min")
end)

H.test("exploit : battre un club d'une division plus haute rapporte +50 % et compte", function()
	freshCup("D5")
	forceScore(3, 1)
	H.eq(data.cup.opponent.division, "D6", "1er tour contre D6")
	local kills = data.club.stats.cupGiantKills
	for _ = 1, 2 do
		nextRound()
		H.ok(CupService.TryPlay(p, "Balanced"), "tour joué")
	end
	H.eq(data.cup.opponent.division, "D4", "quarts contre D4")
	H.ok(snapshot().opponent.giantKill, "exploit annoncé avant le match")
	local coins = data.coins
	nextRound()
	local result = CupService.TryPlay(p, "Balanced")
	H.ok(result.giantKill, "exploit")
	H.eq(result.coins, Cup.Reward(3, "D5", true), "prime majorée")
	H.eq(data.coins, coins + result.coins, "prime versée")
	H.eq(data.club.stats.cupGiantKills, kills + 1, "exploit compté")
end)

H.test("finale gagnée : coupe, trophée dans la vitrine, plus de match cette semaine", function()
	forceScore(2, 1)
	local won = data.club.stats.cupsWon
	while data.cup.status == "playing" do
		nextRound()
		H.ok(CupService.TryPlay(p, "Balanced"), "tour joué")
	end
	H.eq(data.cup.status, "champion", "vainqueur")
	H.eq(data.club.stats.cupsWon, won + 1, "coupe comptée")
	local found = false
	for _, trophy in S.Trophies.Earned(data.club.division, data.club.stats, 0) do
		found = found or trophy.id == "cups_1"
	end
	H.ok(found, "trophée « Coupe nationale »")
	nextRound()
	local coins = data.coins
	local result, err = CupService.TryPlay(p, "Balanced")
	H.ok(not result and err, "plus de tour après la finale")
	H.eq(data.coins, coins, "aucune prime de plus")
	H.eq(snapshot().status, "champion", "affiché comme vainqueur")
end)

H.test("défaite : éliminé jusqu'au lundi, puis nouvelle édition au 1er tour", function()
	freshCup("D6")
	forceScore(0, 2)
	local coins = data.coins
	local result = CupService.TryPlay(p, "Balanced")
	H.eq(result.outcome, "Loss", "défaite")
	H.eq(result.coins, 0, "pas de prime")
	H.eq(data.coins, coins, "solde inchangé")
	H.eq(data.cup.status, "out", "éliminé")
	nextRound()
	H.ok(not CupService.TryPlay(p, "Balanced"), "plus de match")
	toNextSeason()
	local cup = snapshot()
	H.eq(cup.status, "playing", "nouvelle édition")
	H.eq(cup.round, 1, "retour au 1er tour")
	H.eq(#cup.history, 0, "tableau vide")
end)

H.test("match nul : tirs au but, un seul qualifié", function()
	forceScore(1, 1)
	local wins, losses = 0, 0
	for _ = 1, 20 do
		freshCup("D6")
		local result = CupService.TryPlay(p, "Balanced")
		H.ok(result.penalties, "tirs au but")
		if result.outcome == "Win" then
			wins += 1
			H.eq(data.cup.round, 2, "qualifié aux tirs au but")
		else
			losses += 1
			H.eq(data.cup.status, "out", "éliminé aux tirs au but")
		end
	end
	H.ok(wins > 0 and losses > 0, ("les deux issues arrivent (%d / %d)"):format(wins, losses))
end)

H.test("anciens profils et valeurs abîmées : coupe réparée, le tour se joue", function()
	forceScore(2, 0)
	data.cup = nil
	H.eq(snapshot().round, 1, "profil sans coupe")
	data.cup = { edition = data.cup.edition, round = 99, status = "??", lastPlayedAt = math.huge, opponent = "x", history = 3 }
	local cup = snapshot()
	H.eq(cup.round, 5, "tour borné")
	H.eq(cup.status, "playing", "statut réparé")
	H.ok(cup.opponent ~= nil, "adversaire retiré au sort")
	H.eq(cup.nextIn, 0, "heure invalide oubliée")
	H.ok(CupService.TryPlay(p, "Triche"), "style inconnu accepté comme Équilibré")
	H.eq(data.tactic, "Balanced", "style réparé")
	-- Un vrai ancien profil (sans champ cup ni compteurs) se charge sans perte.
	local q = H.join(2, "Ancien")
	local old = S.PlayerDataService.GetData(q)
	old.cup = nil
	old.club.stats.cupsWon = nil
	H.ok(CupService.Snapshot(q, old).status == "playing", "ancien profil : coupe ouverte")
	H.eq(#S.Trophies.Earned(old.club.division, old.club.stats, 0), #S.Trophies.Earned(old.club.division, old.club.stats, 0), "vitrine calculable")
	H.leave(q)
end)

H.test("onglet Matchs : carte de la coupe, bouton, résultat puis attente", function()
	freshCup("D7")
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
	H.ok(H.findText(gui, "🏆 Coupe nationale"), "titre de la carte")
	H.ok(H.findText(gui, "16es de finale : contre "), "adversaire du tour")
	H.click(gui, "Lancer le match de coupe")
	H.eq(data.cup.round, 2, "tour joué depuis le bouton")
	H.frames(5)
	H.click(gui, "Passer") -- replay 3D, puis fenêtre de résultat
	H.ok(H.findText(gui, "Qualifié !"), "résultat affiché")
	H.click(gui, "Continuer")
	UI.SetMenuOpen(true) -- le replay a refermé le menu
	UI.OpenTab("Matches")
	H.ok(H.findText(gui, "Prochain tour possible dans"), "attente affichée")
	H.ok(H.findText(gui, "✅ 16es de finale"), "tour joué dans le tableau")
	forceScore()
end)

H.finish()
