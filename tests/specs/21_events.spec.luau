-- Événements de la semaine : thème qui tourne chaque lundi, bonus de match,
-- points et paliers à récupérer, objet d'événement gagné (jamais vendu),
-- Coupe du week-end, anciens profils, accueil et HUD. Horloge du serveur seulement.
local S = H.boot(MODULES)
local Events, EventService = S.Events, S.EventService
local store = H.getStore(S.Config.DATASTORE_NAME)

local function toNextWeek(extra: number?)
	H.advance(Events.WeekEndsAt(Events.Week(os.time())) - os.time() + (extra or 0))
end

local function playMatch(p)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local result, err = S.MatchService.TryStartMatch(p, "ai", "Balanced")
	assert(result, "match refusé : " .. tostring(err))
	return result
end

H.test("rotation : un thème par semaine, 4 thèmes différents puis retour au premier", function()
	local week = Events.Week(os.time())
	local seen = {}
	for offset = 0, #Events.THEMES - 1 do
		local theme = Events.ThemeForWeek(week + offset)
		H.ok(not seen[theme.id], "thème différent : " .. theme.id)
		seen[theme.id] = true
		H.ok(S.Cosmetics.Get(theme.cosmetic) and S.Cosmetics.Get(theme.cosmetic).event == theme.id, "objet du thème " .. theme.id)
	end
	H.eq(Events.ThemeForWeek(week + #Events.THEMES).id, Events.ThemeForWeek(week).id, "le cycle recommence")
	-- Semaine = saison : du lundi 00:00 UTC au lundi suivant.
	local monday = Events.WeekEndsAt(week)
	H.eq(Events.Weekday(monday), 1, "lundi")
	H.eq(Events.Weekday(monday + 5 * 86400), 6, "samedi")
	H.ok(not Events.IsWeekend(monday + 4 * 86400 + 86399), "vendredi soir : pas encore le week-end")
	H.ok(Events.IsWeekend(monday + 5 * 86400), "samedi 00:00 : week-end")
	H.ok(Events.IsWeekend(monday + 7 * 86400 - 1), "dimanche 23:59 : week-end")
	H.eq(Events.WeekendStartsAt(monday), monday + 5 * 86400, "début du week-end annoncé")
	H.eq(Events.TournamentMultiplier(monday), 1, "pas de bonus en semaine")
	H.eq(Events.TournamentMultiplier(monday + 6 * 86400), Events.WEEKEND_CUP_MULTIPLIER, "bonus le week-end")
end)

H.test("bonus de chaque thème : calculé par le serveur, modéré", function()
	local income = { match = 100, tickets = 1000, sponsor = 200, shop = 300 }
	local tickets, derby, goals, fans = Events.GetTheme("tickets"), Events.GetTheme("derby"), Events.GetTheme("goals"), Events.GetTheme("fans")
	H.eq(Events.MatchBonus(tickets, income, 2, false, "D7"), 500, "billetterie +50 %")
	H.eq(Events.MatchBonus(derby, income, 2, false, "D7"), 50, "derby contre un club fictif +50 %")
	H.eq(Events.MatchBonus(derby, income, 2, true, "D7"), 100, "derby contre un vrai club +100 %")
	H.eq(Events.MatchBonus(goals, income, 3, false, "D7"), 3 * goals.goalCoins, "FC Coins par but")
	H.eq(Events.MatchBonus(goals, income, 3, false, "D1"), math.floor(3 * goals.goalCoins * S.Daily.Scale("D1")), "selon la division")
	H.eq(Events.MatchBonus(goals, income, -5, false, "D7"), 0, "jamais négatif")
	H.eq(Events.MatchBonus(fans, income, 0, false, "D7"), 250, "sponsors et boutique +50 %")
	H.eq(Events.MatchBonus(nil, income, 0, false, "D7"), 0, "sans thème : rien")
	H.eq(Events.MatchPoints(goals, "Win", 2, false), 5, "points : victoire + buts")
	H.eq(Events.MatchPoints(derby, "Loss", 4, true), 2, "points doublés contre un vrai club")
	H.eq(Events.MatchPoints(tickets, "Draw", 1, false), 2, "points : nul")
end)

H.test("match pendant l'événement : bonus compris dans le total, points d'événement", function()
	local p = H.join(2101)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	local theme = Events.Current(os.time())
	local coins = data.coins
	local result = playMatch(p)
	local r = result.rewards
	H.eq(r.event, Events.MatchBonus(theme, r, result.homeGoals, false, data.club.division), "bonus du thème " .. theme.id)
	H.eq(r.total, r.match + r.tickets + r.sponsor + r.shop + r.vip + r.contracts + r.event, "total = somme, bonus compris")
	H.eq(data.coins, coins + r.total + (result.promotionReward or 0), "bonus versé une seule fois, avec le match")
	H.eq(result.eventPoints, Events.MatchPoints(theme, result.outcome, result.homeGoals, false), "points du match")
	H.eq(data.events.points, result.eventPoints, "points enregistrés")
	H.eq(data.events.week, Events.Week(os.time()), "semaine en cours")
	H.leave(p)
end)

H.test("paliers : récupérés une seule fois, objet du thème gagné et porté, jamais vendu", function()
	local p = H.join(2102)
	local data = S.PlayerDataService.GetData(p)
	local theme = Events.Current(os.time())
	local ok = EventService.TryClaim(p)
	H.ok(not ok, "rien à récupérer sans points")
	-- Même en Robux ou en FC Coins, l'objet d'événement ne s'achète pas.
	data.coins = 10_000_000
	local bought = S.CosmeticService.TryBuy(p, theme.cosmetic)
	H.ok(not bought, "objet d'événement refusé à l'achat")
	H.eq(data.coins, 10_000_000, "rien débité")
	data.coins = 1000

	EventService.AddPoints(p, Events.TIERS[1].points)
	H.ok(H.lastNotify(p) and H.lastNotify(p):find("Étape 1"), "annonce du palier atteint")
	local before = data.coins
	H.ok(EventService.TryClaim(p), "palier 1 récupéré")
	H.eq(data.coins, before + Events.TierCoins(1, data.club.division), "prime du palier 1")
	H.ok(not EventService.TryClaim(p), "pas deux fois")
	H.eq(data.coins, before + Events.TierCoins(1, data.club.division), "pas de double versement")

	EventService.AddPoints(p, Events.TIERS[#Events.TIERS].points)
	before = data.coins
	local okAll, message = EventService.TryClaim(p)
	H.ok(okAll, "derniers paliers récupérés")
	local expected = 0
	for index = 2, #Events.TIERS do
		expected += Events.TierCoins(index, data.club.division)
	end
	H.eq(data.coins, before + expected, "primes des paliers 2 et 3")
	H.ok(data.cosmetics.owned[theme.cosmetic], "objet du thème gagné")
	local item = S.Cosmetics.Get(theme.cosmetic)
	H.eq(data.cosmetics.equipped[item.category], theme.cosmetic, "objet porté")
	H.ok(message:find("Prestige"), "message de l'objet")
	H.eq(data.events.claimed, #Events.TIERS, "tous les paliers versés")
	-- Valeurs invalides : rien n'est ajouté.
	local points = data.events.points
	EventService.AddPoints(p, -50)
	EventService.AddPoints(p, 0 / 0)
	EventService.AddPoints(p, "100" :: any)
	H.eq(data.events.points, points, "points invalides refusés")
	-- Demande du client : sans aucune valeur, la réponse vient du serveur.
	H.fire(p, "RequestEventClaim", 999999)
	H.eq(data.coins, before + expected, "requête client : rien de plus")
	H.leave(p)
end)

H.test("nouvelle semaine : paliers oubliés versés, points remis à zéro, nouveau thème", function()
	local p = H.join(2103)
	local data = S.PlayerDataService.GetData(p)
	local oldTheme = Events.Current(os.time())
	EventService.AddPoints(p, Events.TIERS[2].points)
	local coins = data.coins
	local division = data.club.division
	H.leave(p)
	toNextWeek(60)
	local back = H.join(2103)
	H.flush()
	data = S.PlayerDataService.GetData(back)
	local welcome = S.PlayerDataService.Get(back).welcome or {}
	local arrival = (welcome.offline and welcome.offline.coins or 0) + (welcome.daily and welcome.daily.coins or 0)
		+ (welcome.season and welcome.season.reward or 0)
	H.eq(data.coins - arrival, coins + Events.TierCoins(1, division) + Events.TierCoins(2, division), "paliers de la semaine dernière versés")
	H.eq(data.events.points, 0, "points remis à zéro")
	H.eq(data.events.claimed, 0, "nouveaux paliers")
	H.eq(data.events.week, Events.Week(os.time()), "nouvelle semaine")
	H.ok(Events.Current(os.time()).id ~= oldTheme.id, "nouveau thème")
	H.ok(not data.cosmetics.owned[oldTheme.cosmetic], "objet du dernier palier seulement au dernier palier")
	local snap = H.invoke(back, "GetSnapshot")
	H.eq(snap.event.theme, Events.Current(os.time()).id, "thème dans l'instantané")
	H.eq(snap.event.points, 0, "points dans l'instantané")
	H.ok(snap.event.endsIn > 6 * 86400, "compte à rebours de la semaine")
	H.eq(snap.event.weekend, false, "lundi : pas de Coupe du week-end")
	H.ok(snap.event.weekendIn > 4 * 86400, "Coupe du week-end annoncée")
	-- Lundi en pleine partie : la semaine change aussi pour un joueur en ligne.
	EventService.AddPoints(back, 10)
	toNextWeek(5)
	data.missions.list = {}
	playMatch(back)
	H.eq(data.events.week, Events.Week(os.time()), "semaine changée en ligne")
	H.ok(data.events.points <= 15, "points de la nouvelle semaine seulement")
	H.leave(back)
end)

H.test("Coupe du week-end : tournoi majoré et points d'événement seulement le samedi et le dimanche", function()
	local p = H.join(2104)
	local data = S.PlayerDataService.GetData(p)
	-- On se place en semaine.
	while Events.IsWeekend(os.time()) do
		H.advance(3600)
	end
	H.eq(EventService.AddCupPoints(p, "Winner"), 0, "pas de points de coupe en semaine")
	H.eq(S.TournamentService.GetState().weekendCup, false, "tournoi normal en semaine")
	H.advance(Events.WeekendStartsAt(os.time()) - os.time() + 10)
	H.ok(Events.IsWeekend(os.time()), "samedi")
	local points = data.events.points
	H.eq(EventService.AddCupPoints(p, "Winner"), Events.CUP_POINTS.Winner, "points du vainqueur de la coupe")
	H.eq(EventService.AddCupPoints(p, "nimporte"), 0, "tour inconnu : rien")
	H.eq(data.events.points, points + Events.CUP_POINTS.Winner, "points ajoutés")
	local state = S.TournamentService.GetState()
	H.eq(state.weekendCup, true, "Coupe du week-end annoncée")
	H.eq(state.cupMultiplier, Events.WEEKEND_CUP_MULTIPLIER, "récompenses majorées")
	H.ok(S.Config.Tournament.Rewards.Winner * 6.5 * Events.WEEKEND_CUP_MULTIPLIER < 15000, "récompense de coupe bornée")
	H.leave(p)
end)

H.test("ancien profil sans événement : champ ajouté, rien d'inventé", function()
	local p = H.join(2105)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	data.events = nil
	data.coins = 4321
	store.data["player_2105"] = { data = data, lock = nil }
	local back = H.join(2105)
	H.flush()
	local loaded = S.PlayerDataService.GetData(back)
	H.eq(loaded.events.points, 0, "points à zéro")
	H.eq(loaded.events.claimed, 0, "aucun palier")
	H.eq(loaded.events.week, Events.Week(os.time()), "semaine en cours")
	H.ok(loaded.coins >= 4321, "solde gardé")
	H.ok(not EventService.TryClaim(back), "aucune récompense inventée")
	H.leave(back)
end)

H.test("écran : événement dans l'accueil, compte à rebours dans le HUD, bouton Récupérer, objet dans Prestige", function()
	local p = H.join(2106, "Événement")
	local data = S.PlayerDataService.GetData(p)
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	local theme = Events.Current(os.time())
	local found = false
	for _, d in gui:GetDescendants() do
		if d.Name == "Event" and d:IsA("TextLabel") and d.Visible and d.Text:find("fin dans") then
			found = true
		end
	end
	H.ok(found, "ligne d'événement dans le HUD avec compte à rebours")
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, "Événement de la semaine"), "carte de l'événement")
	H.ok(H.findText(gui, "Étape 1 de l'événement"), "paliers affichés")
	H.ok(not H.findText(gui, "Récupérer mes récompenses"), "pas de bouton sans palier atteint")
	EventService.AddPoints(p, Events.TIERS[#Events.TIERS].points)
	H.flush()
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, "Récupérer mes récompenses"), "bouton Récupérer")
	local before = data.coins
	H.advance(1)
	H.click(gui, "Récupérer mes récompenses")
	H.flush()
	H.ok(data.coins > before, "récompenses versées par le bouton")
	H.ok(data.cosmetics.owned[theme.cosmetic], "objet gagné")
	UI.OpenTab("Prestige")
	H.flush()
	H.ok(H.findText(gui, "Objet gagné pendant un événement"), "objet visible dans Prestige")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	H.leave(p)
end)
