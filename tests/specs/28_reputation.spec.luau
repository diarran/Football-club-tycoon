-- Réputation du club (0 à 100) et conférences de presse : score, plancher et
-- plafond, gains après les matchs, la coupe et les tournois, questions de la
-- presse validées par le serveur, effets doux, anciens profils, interface.
local S = H.boot(MODULES)
local Reputation = mock.run(MODULES.Reputation)
local ReputationService = mock.run(MODULES.ReputationService)
local MatchService, Config, Locale = S.MatchService, S.Config, S.Locale
local realSimulate = MatchService.Simulate

local function forceScore(mine: number?, theirs: number?)
	if mine == nil then
		MatchService.Simulate = realSimulate
		return
	end
	MatchService.Simulate = function(home, away, weather)
		local score = realSimulate(home, away, weather)
		score.homeGoals, score.awayGoals = mine, theirs
		score.events = {}
		return score
	end
end

local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)

local function heal()
	-- Le club reste en D7 (plafond 40) sauf dans le test de la montée.
	data.club.division = "D7"
	data.club.divisionPoints = 0
	for _, footballer in data.squad do
		footballer.injuredUntil = 0
		footballer.suspended = 0
		footballer.energy = 100
	end
end

local function play(mine: number, theirs: number, opponent: string?)
	heal()
	forceScore(mine, theirs)
	H.advance(Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", opponent or "ai", "Balanced")
	forceScore()
	local results = H.received(p, "MatchResult")
	H.ok(#results > before, "match joué")
	return results[#results][1]
end

local function findNamed(root, name: string)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function resetReputation(score: number?)
	data.reputation.score = score or 20
	data.reputation.pending = { id = 0, topic = "", at = 0 }
	data.reputation.buzz = { kind = "", matches = 0 }
	data.reputation.sincePress = Reputation.PRESS_GAP
	data.reputation.streak = 0
	data.reputation.provocative = false
end

H.test("plafond selon la division, plancher selon la division et les tribunes", function()
	H.eq(Reputation.Cap(7), 40, "D7 : au plus 40")
	H.eq(Reputation.Cap(1), 100, "D1 : jusqu'à 100")
	for tier = 1, 7 do
		for stands = 1, 5 do
			local floor, cap = Reputation.Floor(tier, stands), Reputation.Cap(tier)
			H.ok(floor >= 0 and floor < cap, ("plancher sous le plafond D%d tribunes %d"):format(tier, stands))
		end
		H.ok(Reputation.Floor(tier, 5) > Reputation.Floor(tier, 1), "un beau stade protège la réputation")
	end
	H.eq(Reputation.Clamp(500, 7, 1), 40, "valeur trop haute ramenée au plafond")
	H.eq(Reputation.Clamp(-20, 7, 1), Reputation.Floor(7, 1), "valeur trop basse ramenée au plancher")
	H.eq(Reputation.Clamp(0 / 0, 7, 1), Reputation.Floor(7, 1), "NaN ramené au plancher")
	H.eq(Reputation.Level(97), "legend", "palier légende")
	H.eq(Reputation.Level(5), "unknown", "palier inconnu")
	H.eq(Reputation.SponsorMultiplier(100), 1.1, "sponsors +10 % au plus")
	H.eq(Reputation.SponsorMultiplier(0), 1, "aucun malus à 0")
end)

H.test("nouveau club : réputation de départ dans les limites, envoyée au client", function()
	local score = data.reputation.score
	H.eq(score, Reputation.Initial(7, 1), "valeur de départ")
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.eq(snapshot.reputation.score, score, "score dans l'instantané")
	H.eq(snapshot.reputation.cap, 40, "plafond envoyé")
	H.eq(snapshot.reputation.pending, nil, "aucune question au départ")
end)

H.test("victoires, défaites, gros scores : la réputation bouge, sans sortir des limites", function()
	data.tutorial.completed = true
	resetReputation(20)
	local result = play(1, 0)
	H.eq(result.reputation.delta, Reputation.Gains.Win, "victoire")
	H.eq(data.reputation.score, 20 + Reputation.Gains.Win, "score après la victoire")
	result = play(0, 1)
	H.eq(result.reputation.delta, Reputation.Gains.Loss, "défaite : petite baisse")
	result = play(4, 0)
	H.eq(result.reputation.delta, Reputation.Gains.Win + Reputation.Gains.bigWin, "gros score")
	resetReputation(Reputation.Floor(7, data.buildings.Stands))
	result = play(0, 5)
	H.eq(result.reputation.delta, 0, "au plancher : aucune baisse")
	H.eq(data.reputation.score, Reputation.Floor(7, data.buildings.Stands), "jamais sous le plancher")
	resetReputation(40)
	result = play(3, 0)
	H.eq(data.reputation.score, 40, "jamais au-dessus du plafond de la division")
end)

H.test("conférence de presse après un gros score, puis pas avant PRESS_GAP matchs", function()
	resetReputation(20)
	local result = play(4, 0)
	H.ok(result.reputation.press, "la presse arrive")
	local pending = S.PlayerDataService.BuildSnapshot(p).reputation.pending
	H.eq(pending.topic, "bigWin", "sujet : gros score")
	H.ok(pending.expiresIn > 0, "durée de la question")
	-- La question est remplacée seulement après PRESS_GAP matchs.
	H.fire(p, "RequestPressAnswer", "skip")
	H.eq(data.reputation.pending.id, 0, "question passée sans conséquence")
	result = play(5, 0)
	H.ok(not result.reputation.press, "pas de nouvelle conférence tout de suite")
	for _ = 1, Reputation.PRESS_GAP - 2 do
		play(1, 1)
	end
	result = play(4, 1)
	H.ok(result.reputation.press, "nouvelle conférence après quelques matchs")
	H.fire(p, "RequestPressAnswer", "skip")
end)

H.test("réponse humble : énergie rendue aux joueurs, réputation +1", function()
	resetReputation(20)
	play(4, 0)
	for _, footballer in data.squad do
		footballer.energy = 50
	end
	local before = data.reputation.score
	H.fire(p, "RequestPressAnswer", "humble")
	H.eq(data.reputation.score, before + 1, "réputation")
	H.eq(data.squad[1].energy, 50 + Reputation.MORALE_ENERGY, "énergie +10")
	H.eq(data.reputation.buzz.kind, "morale", "vestiaire soudé")
	local message, kind = H.lastNotify(p)
	H.eq(kind, "success", "message de réussite")
	H.ok(message:find("Énergie", 1, true), "message en français")
	-- Une seule réponse par question.
	H.fire(p, "RequestPressAnswer", "ambitious")
	H.eq(data.reputation.buzz.kind, "morale", "deuxième réponse refusée")
	H.eq(select(2, H.lastNotify(p)), "error", "erreur affichée")
end)

H.test("réponse provocante : billetterie +10 % pendant 3 matchs, puis fin du buzz", function()
	resetReputation(20)
	play(4, 0)
	H.fire(p, "RequestPressAnswer", "provocative")
	H.eq(data.reputation.buzz.matches, Reputation.BUZZ_MATCHES, "3 matchs")
	for i = 1, Reputation.BUZZ_MATCHES do
		local result = play(1, 1)
		H.eq(result.rewards.press, math.floor(result.rewards.tickets * Reputation.FANS_BUZZ + 0.5), "bonus billetterie " .. i)
		H.ok(result.rewards.press > 0, "bonus positif")
	end
	local result = play(1, 1)
	H.eq(result.rewards.press, 0, "buzz terminé")
	H.eq(S.PlayerDataService.BuildSnapshot(p).reputation.buzz, nil, "plus de buzz affiché")
end)

H.test("provocant puis défaite : petite baisse de réputation, jamais d'argent perdu", function()
	resetReputation(30)
	play(4, 0)
	H.fire(p, "RequestPressAnswer", "provocative")
	local before = data.reputation.score
	local coins = data.coins
	local result = play(0, 2)
	H.eq(result.reputation.delta, Reputation.Gains.Loss + Reputation.Gains.provocativeLoss, "défaite après provocation")
	H.eq(data.reputation.score, before + Reputation.Gains.Loss + Reputation.Gains.provocativeLoss, "score")
	H.ok(data.coins >= coins, "aucune perte d'argent")
	H.ok(result.rewards.press >= 0, "bonus jamais négatif")
end)

H.test("réponse ambitieuse : primes des sponsors +15 %", function()
	resetReputation(20)
	play(4, 0)
	H.fire(p, "RequestPressAnswer", "ambitious")
	local result = play(1, 1)
	H.eq(
		result.rewards.press,
		math.floor((result.rewards.sponsor + result.rewards.contracts) * Reputation.SPONSOR_BUZZ + 0.5),
		"bonus sponsors"
	)
	resetReputation(20)
end)

H.test("valeurs invalides refusées, question expirée", function()
	resetReputation(20)
	for _, junk in { "nope", 42, nil, {}, "skip" } do
		H.fire(p, "RequestPressAnswer", junk)
		H.eq(data.reputation.buzz.kind, "", "aucun effet sans question : " .. tostring(junk))
	end
	play(4, 0)
	H.ok(data.reputation.pending.id ~= 0, "question posée")
	H.fire(p, "RequestPressAnswer", "Humble")
	H.ok(data.reputation.pending.id ~= 0, "réponse inconnue : la question reste")
	H.advance(Reputation.PRESS_EXPIRES + 1)
	H.eq(S.PlayerDataService.BuildSnapshot(p).reputation.pending, nil, "question expirée")
	H.fire(p, "RequestPressAnswer", "provocative")
	H.eq(data.reputation.buzz.kind, "", "trop tard : aucun effet")
end)

H.test("montée : réputation +5 et conférence même juste après une autre", function()
	resetReputation(30)
	data.reputation.sincePress = 0
	heal()
	data.club.divisionPoints = S.Divisions.Get("D7").pointsToPromote - 1
	forceScore(1, 0)
	H.advance(Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "ai", "Balanced")
	forceScore()
	local results = H.received(p, "MatchResult")
	local result = results[#results][1]
	H.ok(result.promoted, "montée en D6")
	H.eq(result.reputation.delta, Reputation.Gains.Win + Reputation.Gains.promotion, "victoire + montée")
	H.eq(data.reputation.pending.topic, "promotion", "la presse parle de la montée")
	H.eq(S.PlayerDataService.BuildSnapshot(p).reputation.cap, 50, "plafond de la D6")
	H.fire(p, "RequestPressAnswer", "skip")
end)

H.test("série de 5 victoires : la presse s'y intéresse", function()
	resetReputation(30)
	data.reputation.sincePress = 0
	local topic
	for _ = 1, Reputation.STREAK do
		play(1, 0)
		topic = data.reputation.pending.topic
	end
	H.eq(topic, "streak", "série de victoires")
	H.fire(p, "RequestPressAnswer", "skip")
end)

H.test("pas de journalistes pendant le tutoriel", function()
	resetReputation(20)
	data.tutorial.completed = false
	local result = play(5, 0)
	H.ok(not result.reputation.press, "aucune question pendant le tutoriel")
	data.tutorial.completed = true
end)

H.test("coupe et tournoi : réputation en hausse, conférence pour une coupe gagnée", function()
	resetReputation(30)
	local info = ReputationService.OnCupRound(p, data, true, false, false)
	H.eq(info.delta, Reputation.Gains.cupRound, "tour de coupe gagné")
	H.ok(not info.press, "tour normal : pas de presse")
	info = ReputationService.OnCupRound(p, data, false, false, false)
	H.eq(info.delta, 0, "élimination : aucune baisse")
	info = ReputationService.OnCupRound(p, data, true, false, true)
	H.ok(info.press, "coupe gagnée : conférence")
	H.eq(data.reputation.pending.topic, "cupChampion", "sujet coupe")
	H.fire(p, "RequestPressAnswer", "skip")
	resetReputation(30)
	ReputationService.OnTournamentWon(p)
	H.eq(data.reputation.score, 30 + Reputation.Gains.tournament, "tournoi gagné")
	H.eq(data.reputation.pending.topic, "tournament", "conférence du tournoi")
	H.fire(p, "RequestPressAnswer", "skip")
end)

H.test("match de coupe : ligne de réputation dans le résultat", function()
	resetReputation(30)
	local before = data.reputation.score
	H.advance(24 * 3600)
	heal()
	forceScore(3, 0)
	local count = #H.received(p, "MatchResult")
	H.fire(p, "RequestCupMatch", "Balanced")
	forceScore()
	local results = H.received(p, "MatchResult")
	if #results > count then
		local result = results[#results][1]
		H.eq(result.mode, "cup", "résultat de coupe")
		H.ok(type(result.reputation) == "table", "réputation dans le résultat")
		H.ok(data.reputation.score >= before, "réputation en hausse ou stable")
	end
	data.reputation.pending = { id = 0, topic = "", at = 0 }
end)

H.test("contrats de sponsoring : petit bonus selon la réputation", function()
	data.sponsors.contracts = { { id = 999, brand = "Brixo", perMatch = 100, goal = "wins", target = 99, progress = 0, matchesLeft = 99, matches = 99, bonus = 0, completed = false } }
	data.reputation.score = 0
	local low = S.StaffService.ContractIncome(data)
	data.reputation.score = 40
	local high = S.StaffService.ContractIncome(data)
	H.ok(high > low, "meilleure réputation, meilleures primes")
	H.ok(high <= math.ceil(low * 1.04) + 1, "effet modeste (+4 % à 40)")
	data.sponsors.contracts = {}
	resetReputation(20)
end)

H.test("ancien profil sans réputation : calculée selon la division, rien de cassé", function()
	local store = S.PlayerDataService
	local q = H.join(2, "Ancien")
	local old = store.GetData(q)
	old.reputation = nil
	old.club.division = "D3"
	ReputationService.Ensure(old)
	H.eq(old.reputation.score, Reputation.Initial(3, old.buildings.Stands), "valeur de départ D3")
	H.eq(old.reputation.pending.id, 0, "aucune question")
	old.reputation = { score = "abîmé", pending = 5, buzz = "x" }
	ReputationService.Ensure(old)
	H.ok(type(old.reputation.score) == "number", "score réparé")
	H.ok(type(old.reputation.pending) == "table", "question réparée")
	H.eq(old.reputation.sincePress, Reputation.PRESS_GAP, "compteur réparé")
	local snapshot = store.BuildSnapshot(q)
	H.ok(snapshot.reputation.score >= Reputation.Floor(3, 1), "instantané valide")
	H.leave(q)
end)

H.test("textes : toutes les questions et réponses en français et en anglais", function()
	for _, topic in Reputation.Topics do
		for _, lang in { "fr", "en" } do
			H.ok(Locale.T(lang, "press.q." .. topic) ~= "press.q." .. topic, lang .. " question " .. topic)
			for _, answer in Reputation.Answers do
				local key = "press.a." .. topic .. "." .. answer
				H.ok(Locale.T(lang, key) ~= key, lang .. " réponse " .. key)
			end
		end
	end
	for _, level in Reputation.Levels do
		H.ok(Locale.T("en", "reputation.level." .. level.id) ~= "reputation.level." .. level.id, "palier " .. level.id)
	end
end)

H.test("interface : carte Réputation, conférence après le résultat, réponse envoyée", function()
	resetReputation(20)
	data.onboarding.done = true
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	H.clearSent()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	local welcome = findNamed(gui, "Welcome")
	if welcome and welcome.Visible then
		H.click(gui, "Super !") -- résumé « Pendant ton absence… »
	end
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.ok(H.findText(gui, "Réputation du club"), "carte Réputation")
	H.ok(H.findText(gui, "20 / 100 · Club local"), "score et palier")
	play(4, 0)
	H.frames(5)
	local skip = H.findText(gui, "Passer", "TextButton")
	if skip then
		skip.Activated:Fire() -- replay 3D
		H.flush()
	end
	H.ok(H.findText(gui, "Réputation : +3"), "ligne de réputation dans le résultat")
	H.ok(H.findText(gui, "Les journalistes veulent te parler"), "annonce de la presse")
	H.click(gui, "Continuer")
	local popup = findNamed(gui, "PressConference")
	H.ok(popup and popup.Visible, "conférence de presse affichée")
	H.ok(H.findText(gui, "Quelle victoire large"), "question affichée")
	local energyBefore = data.squad[1].energy
	H.click(gui, "« Les joueurs ont tout donné")
	H.eq(data.reputation.buzz.kind, "morale", "réponse humble envoyée au serveur")
	H.ok(data.squad[1].energy >= energyBefore, "énergie rendue")
	H.ok(not popup.Visible, "fenêtre fermée")
	-- Question suivante : bouton « Ne pas répondre ».
	resetReputation(20)
	play(4, 0)
	H.frames(5)
	skip = H.findText(gui, "Passer", "TextButton")
	if skip then
		skip.Activated:Fire()
		H.flush()
	end
	H.click(gui, "Continuer")
	H.ok(popup.Visible, "nouvelle conférence")
	H.click(gui, "Ne pas répondre")
	H.eq(data.reputation.pending.id, 0, "question passée")
	H.eq(data.reputation.buzz.kind, "", "aucun effet")
	-- Carte de l'accueil : bouton pour répondre plus tard.
	play(1, 1)
	data.reputation.pending = { id = 900, topic = "derby", at = os.time() }
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.click(gui, "Les journalistes t'attendent")
	H.ok(H.findText(gui, "Un message pour ce club"), "question du derby")
end)
