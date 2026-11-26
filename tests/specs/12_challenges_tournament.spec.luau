-- Défis entre clubs et tournoi du serveur : tout est validé par le serveur,
-- les mises ne créent pas de monnaie et les tournois sont bornés dans le temps.
local S = H.boot(MODULES)
local C, TC = S.Config.Challenge, S.Config.Tournament
local Challenge, Tournament = S.ChallengeService, S.TournamentService

local a = H.join(1, "Alice")
local b = H.join(2, "Bruno")
local da = S.PlayerDataService.GetData(a)
local db = S.PlayerDataService.GetData(b)

local function lastChallengeState(player)
	local list = H.received(player, "ChallengeUpdated")
	return list[#list] and list[#list][1]
end

local function incomingId(player)
	local s = lastChallengeState(player)
	return s and s.incoming[1] and s.incoming[1].id
end

-- Laisse passer les délais anti-spam entre deux tests.
local function settle()
	H.advance(math.max(C.SEND_COOLDOWN_SECONDS, C.PAIR_COOLDOWN_SECONDS, C.EXPIRE_SECONDS) + 1)
end

H.test("défi accepté : mises prélevées, pot au gagnant, aucune monnaie créée", function()
	da.coins, db.coins = 5000, 5000
	H.fire(a, "RequestChallenge", "player:2", 500)
	local id = incomingId(b)
	H.ok(id, "Bruno voit le défi")
	H.eq(lastChallengeState(a).outgoing.stake, 500, "Alice voit son défi en attente")
	H.eq(da.coins, 5000, "rien n'est prélevé avant l'acceptation")
	local played = da.club.stats.played
	H.fire(b, "RequestChallengeResponse", id, true)
	local ra = H.received(a, "MatchResult")
	local rb = H.received(b, "MatchResult")
	ra, rb = ra[#ra][1], rb[#rb][1]
	H.eq(ra.mode, "challenge", "résultat de défi")
	H.eq(ra.homeGoals, rb.awayGoals, "même score vu des deux côtés")
	H.eq(da.coins + db.coins, 10000, "total des deux clubs inchangé")
	H.eq(da.coins, 5000 + ra.coinsChange, "solde d'Alice")
	H.eq(db.coins, 5000 + rb.coinsChange, "solde de Bruno")
	H.eq(ra.coinsChange, -rb.coinsChange, "gain = perte de l'autre")
	H.eq(da.club.stats.played, played, "le défi ne compte pas en championnat")
	H.eq(Challenge.PendingCount(), 0, "défi terminé")
end)

H.test("défi refusé : aucun débit, Alice prévenue, même adversaire bloqué un moment", function()
	settle()
	local ca, cb = da.coins, db.coins
	H.fire(a, "RequestChallenge", "player:2", 100)
	H.fire(b, "RequestChallengeResponse", incomingId(b), false)
	H.eq(da.coins, ca, "solde d'Alice")
	H.eq(db.coins, cb, "solde de Bruno")
	local msg = H.lastNotify(a)
	H.ok(msg:find("refusé"), "Alice sait que c'est refusé : " .. tostring(msg))
	H.advance(C.SEND_COOLDOWN_SECONDS + 1)
	H.fire(a, "RequestChallenge", "player:2", 100)
	H.eq(Challenge.PendingCount(), 0, "nouveau défi bloqué juste après un refus")
	H.advance(C.PAIR_COOLDOWN_SECONDS)
	H.fire(a, "RequestChallenge", "player:2", 100)
	H.eq(Challenge.PendingCount(), 1, "possible après le délai")
end)

H.test("défi sans réponse : expire tout seul", function()
	H.advance(C.EXPIRE_SECONDS + 1)
	H.eq(Challenge.PendingCount(), 0, "défi expiré")
	H.eq(#lastChallengeState(b).incoming, 0, "plus affiché chez Bruno")
	local msg = H.lastNotify(a)
	H.ok(msg:find("expiré"), "Alice prévenue")
end)

H.test("valeurs client invalides : mise hors liste, cible absente ou soi-même", function()
	settle()
	local ca = da.coins
	for _, stake in { 1001, 5000, -100, 0.5, 99, "100", {}, 0 / 0, math.huge, nil } do
		H.fire(a, "RequestChallenge", "player:2", stake)
	end
	for _, target in { "player:1", "player:999", "ai", 2, nil, string.rep("x", 3000) } do
		H.fire(a, "RequestChallenge", target, 100)
	end
	H.eq(Challenge.PendingCount(), 0, "aucun défi créé")
	H.eq(da.coins, ca, "solde inchangé")
end)

H.test("seul le club défié peut répondre ; anti-spam des envois", function()
	settle()
	local c = H.join(3, "Chloé")
	H.fire(a, "RequestChallenge", "player:2", 100)
	local id = incomingId(b)
	H.fire(a, "RequestChallengeResponse", id, true) -- Alice ne peut pas accepter pour Bruno
	H.fire(c, "RequestChallengeResponse", id, true) -- ni un autre joueur
	H.fire(b, "RequestChallengeResponse", "1", true) -- identifiant au mauvais format
	H.eq(Challenge.PendingCount(), 1, "toujours en attente")
	H.fire(a, "RequestChallenge", "player:3", 100)
	H.eq(Challenge.PendingCount(), 1, "un seul défi envoyé à la fois")
	H.leave(c)
	H.fire(b, "RequestChallengeResponse", id, false)
end)

H.test("nombre de défis reçus limité pour un même club", function()
	settle()
	local others = {}
	for i = 1, C.MAX_INCOMING + 1 do
		local q = H.join(10 + i)
		table.insert(others, q)
		H.fire(q, "RequestChallenge", "player:2", 0)
	end
	H.eq(#lastChallengeState(b).incoming, C.MAX_INCOMING, "défis reçus plafonnés")
	for _, q in others do
		H.leave(q)
	end
	H.eq(Challenge.PendingCount(), 0, "défis annulés au départ des joueurs")
end)

H.test("mise impossible à payer : refusée, et annulée sans débit si le solde a baissé", function()
	settle()
	da.coins = 50
	H.fire(a, "RequestChallenge", "player:2", 100)
	H.eq(Challenge.PendingCount(), 0, "pas assez pour envoyer")
	da.coins = 1000
	H.fire(a, "RequestChallenge", "player:2", 1000)
	local id = incomingId(b)
	da.coins = 10 -- Alice a dépensé entre-temps
	local cb = db.coins
	H.fire(b, "RequestChallengeResponse", id, true)
	H.eq(da.coins, 10, "rien prélevé chez Alice")
	H.eq(db.coins, cb, "rien prélevé chez Bruno")
	H.eq(Challenge.PendingCount(), 0, "défi annulé")
end)

H.test("200 défis à 2 joueurs : la somme des soldes ne change jamais", function()
	da.coins, db.coins = 1000000, 1000000
	for i = 1, 200 do
		settle()
		local from, to = if i % 2 == 0 then a else b, if i % 2 == 0 then b else a
		H.fire(from, "RequestChallenge", "player:" .. to.UserId, C.STAKES[#C.STAKES])
		H.fire(to, "RequestChallengeResponse", incomingId(to), true)
	end
	H.eq(da.coins + db.coins, 2000000, "aucune monnaie créée ni détruite")
	H.ok(da.club.stats.challengesWon + db.club.stats.challengesWon > 50, "défis gagnés comptés")
end)

-- Tournoi --------------------------------------------------------------------

local function waitPhase(phase)
	for _ = 1, 200 do
		if Tournament.GetState().phase == phase then
			return
		end
		H.advance(5)
	end
	error("phase jamais atteinte : " .. phase)
end

local won = {}
Tournament.OnTournamentWon(function(player, info)
	table.insert(won, { player = player, info = info })
end)

H.test("inscription : seulement pendant l'ouverture, une fois par club", function()
	waitPhase("waiting")
	H.fire(a, "RequestTournamentJoin")
	H.eq(#Tournament.GetState().entrants, 0, "fermé hors inscriptions")
	waitPhase("registration")
	H.fire(a, "RequestTournamentJoin")
	H.fire(a, "RequestTournamentJoin")
	H.eq(#Tournament.GetState().entrants, 1, "une seule inscription")
	H.fire(b, "RequestTournamentJoin")
	H.eq(#Tournament.GetState().entrants, 2, "Bruno inscrit")
end)

H.test("tournoi à 2 joueurs : 8 clubs, 3 tours, un vainqueur, récompenses bornées", function()
	local ca, cb = da.coins, db.coins
	local energyA, pointsA = da.squad[1].energy, da.club.divisionPoints
	local before = #won
	waitPhase("running")
	local s = Tournament.GetState()
	H.eq(#s.entrants, TC.SIZE, "tableau complété par des clubs fictifs")
	local names = {}
	for _, e in s.entrants do
		H.ok(not names[e.name], "nom unique : " .. e.name)
		names[e.name] = true
	end
	waitPhase("waiting")
	s = Tournament.GetState()
	H.eq(#s.rounds, 3, "quarts, demies, finale")
	H.eq(#s.rounds[1].matches, 4, "4 quarts")
	H.eq(#s.rounds[3].matches, 1, "une finale")
	local champion = s.rounds[3].matches[1].winnerName
	H.eq(s.lastWinner.clubName, champion, "vainqueur annoncé")
	local mult = S.Divisions.Get(da.club.division).rewardMultiplier
	local gainA, gainB = da.coins - ca, db.coins - cb
	H.ok(gainA >= TC.Rewards.Quarter * mult and gainA <= TC.Rewards.Winner * mult, "gain d'Alice dans les bornes : " .. gainA)
	H.ok(gainB >= TC.Rewards.Quarter and gainB <= TC.Rewards.Winner * 3, "gain de Bruno dans les bornes : " .. gainB)
	H.eq(da.squad[1].energy >= energyA, true, "pas d'énergie dépensée")
	H.eq(da.club.divisionPoints, pointsA, "pas de points de division")
	if champion == da.club.name or champion == db.club.name then
		H.eq(#won, before + 1, "événement « tournoi gagné » envoyé")
		local event = won[#won]
		H.eq(event.info.clubName, champion, "club vainqueur dans l'événement")
		H.eq(S.PlayerDataService.GetData(event.player).club.stats.tournamentsWon, 1, "trophée compté")
	else
		H.eq(#won, before, "club fictif vainqueur : pas d'événement")
	end
end)

H.test("sans inscrit : le tournoi est annulé et le suivant reprogrammé", function()
	waitPhase("registration")
	waitPhase("waiting")
	H.eq(#Tournament.GetState().rounds, 0, "aucun match joué")
	waitPhase("registration")
	H.ok(true, "nouvelles inscriptions plus tard")
end)

H.test("club qui part pendant le tournoi : forfait, aucune récompense", function()
	local c = H.join(4, "Chloé")
	local dc = S.PlayerDataService.GetData(c)
	H.fire(c, "RequestTournamentJoin")
	H.fire(a, "RequestTournamentJoin")
	waitPhase("running")
	local name = dc.club.name
	H.leave(c)
	waitPhase("waiting")
	local rounds = Tournament.GetState().rounds
	for index = 2, #rounds do
		for _, m in rounds[index].matches do
			if m.homeName == name or m.awayName == name then
				H.ok(m.forfeit, "club parti : forfait")
				H.ok(m.winnerName ~= name, "club parti : jamais qualifié")
			end
		end
	end
	H.ok(Tournament.GetState().lastWinner.clubName ~= name, "club parti : ne gagne pas")
end)

H.test("50 tournois de suite : gains totaux bornés par le temps", function()
	da.club.division = "D1"
	local start = da.coins
	for _ = 1, 50 do
		waitPhase("registration")
		H.fire(a, "RequestTournamentJoin")
		waitPhase("waiting")
	end
	local maxPer = TC.Rewards.Winner * S.Divisions.Get("D1").rewardMultiplier
	H.ok(da.coins - start <= 50 * maxPer, "au plus une récompense par tournoi")
	H.ok(da.coins - start >= 50 * TC.Rewards.Quarter, "chaque participation récompensée")
end)

H.test("écran Matchs : tournoi, mise et bouton Défier ; acceptation depuis l'interface", function()
	settle()
	waitPhase("registration")
	local gui = H.startClient(MODULES, b)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.flush()
	H.ok(H.findText(gui, "Tournoi du serveur"), "carte du tournoi")
	H.click(gui, "S'inscrire")
	H.ok(H.findText(gui, "Ton club est inscrit"), "inscription affichée")
	H.ok(H.findText(gui, "Défier · "), "bouton Défier sur le club d'Alice")
	H.click(gui, "1000")
	H.ok(H.findText(gui, "Défier · 1000"), "mise choisie")
	da.coins, db.coins = 3000, 3000
	H.fire(a, "RequestChallenge", "player:2", 250)
	H.flush()
	H.ok(H.findText(gui, "Défi lancé par"), "défi reçu affiché")
	H.click(gui, "Accepter")
	H.eq(da.coins + db.coins, 6000, "défi joué via l'interface, total conservé")
	H.ok(H.findText(gui, "Continuer"), "résultat affiché")
end)
