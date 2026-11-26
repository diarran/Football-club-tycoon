-- Classement mondial : scores calculés par le serveur, écritures limitées
-- dans les DataStore ordonnés, lecture du haut des tableaux, budgets
-- respectés, pannes sans casse, semaine remise à zéro, panneau 3D, écran.
local S = H.boot(MODULES)
local Leaderboard = mock.run(MODULES.Leaderboard)
local LeaderboardService = mock.run(MODULES.LeaderboardService)
local Daily = S.Daily

local function storeOf(board)
	return H.getOrderedStore(Leaderboard.StoreName(board, os.time()))
end

local function lastState(p)
	local list = H.received(p, "LeaderboardUpdated")
	return list[#list] and list[#list][1]
end

local function snap(p)
	return S.PlayerDataService.BuildSnapshot(p).leaderboard
end

-- Clubs des autres serveurs, déjà dans les tableaux.
for i = 1, 30 do
	local id = tostring(1000 + i)
	storeOf("week").data[id] = i * 10
	storeOf("club").data[id] = Leaderboard.Score("club", { club = { division = "D6", divisionPoints = i } }, os.time())
	storeOf("trophies").data[id] = i % 7
end

local a = H.join(1, "Alice")
local b = H.join(2, "Bruno")
H.flush()
local da = S.PlayerDataService.GetData(a)
local db = S.PlayerDataService.GetData(b)

H.test("scores : venant des données du serveur, entiers, ordre des divisions", function()
	local now = os.time()
	local d7top = { club = { division = "D7", divisionPoints = 999999999 } }
	local d6low = { club = { division = "D6", divisionPoints = 0 } }
	H.ok(Leaderboard.Score("club", d6low, now) > Leaderboard.Score("club", d7top, now), "D6 devant D7, quels que soient les points")
	local d1 = { club = { division = "D1", divisionPoints = 40 } }
	local division, points = Leaderboard.DecodeClub(Leaderboard.Score("club", d1, now))
	H.eq(division, "D1", "division relue")
	H.eq(points, 40, "points relus")
	local week = { club = { division = "D7" }, season = { id = Daily.SeasonId(now), points = 37.8 } }
	H.eq(Leaderboard.Score("week", week, now), 37, "points de la semaine (entier)")
	week.season.id -= 1
	H.eq(Leaderboard.Score("week", week, now), 0, "saison passée : 0")
	for _, bad in { {}, { club = "x" }, { club = { division = "??", divisionPoints = 0 / 0 } } } do
		for _, board in Leaderboard.BOARDS do
			local score = Leaderboard.Score(board, bad, now)
			H.ok(score >= 0 and score == math.floor(score), "score valide pour un profil abîmé")
		end
	end
	H.eq(snap(a).scores.club, Leaderboard.Score("club", da, now), "score dans l'instantané")
end)

H.test("lecture : haut des tableaux envoyé à tous, noms en une requête", function()
	H.advance(Leaderboard.FIRST_REFRESH + 1)
	local st = lastState(a)
	H.ok(st, "classement reçu")
	H.eq(st.scope, "global", "tous les serveurs")
	H.eq(#st.boards.week, Leaderboard.SHOWN, "lignes affichées limitées")
	H.eq(st.boards.week[1].userId, 1030, "meilleur score en tête")
	H.eq(st.boards.week[1].name, "Pseudo1030", "nom Roblox")
	for i = 2, #st.boards.week do
		H.ok(st.boards.week[i].score <= st.boards.week[i - 1].score, "tri décroissant")
		H.eq(st.boards.week[i].rank, i, "rang")
	end
	H.eq(H.userInfoCalls, 1, "une seule requête de noms")
	H.ok(lastState(b), "Bruno aussi")
	H.eq(storeOf("week").reads, 1, "une lecture par tableau")
end)

H.test("écriture : seulement si le score change, au plus une fois par intervalle", function()
	da.season.points = 500
	da.club.division, da.club.divisionPoints = "D5", 12
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	H.eq(storeOf("week").data["1"], 500, "score de la semaine écrit")
	H.eq(storeOf("club").data["1"], Leaderboard.Score("club", da, os.time()), "niveau du club écrit")
	H.eq(storeOf("week").data["2"], nil, "Bruno (0 point) n'est pas écrit")
	local writes = storeOf("week").writes
	H.advance(Leaderboard.WRITE_INTERVAL * 3)
	H.eq(storeOf("week").writes, writes, "score inchangé : aucune écriture")
	da.season.points = 510
	H.advance(30)
	H.eq(storeOf("week").data["1"], 500, "pas avant l'intervalle")
	H.advance(Leaderboard.WRITE_INTERVAL)
	H.eq(storeOf("week").data["1"], 510, "puis écrit")
end)

H.test("après rafraîchissement : club présent avec son nom, place dans l'instantané", function()
	LeaderboardService.Refresh()
	H.flush()
	local st = lastState(a)
	H.eq(st.boards.week[1].userId, 1, "Alice en tête de la semaine")
	H.eq(st.boards.week[1].club, da.club.name, "nom du club d'Alice")
	H.eq(snap(a).ranks.week, 1, "place d'Alice")
	H.eq(snap(b).ranks.week, nil, "Bruno hors du haut du tableau")
	local calls = H.userInfoCalls
	LeaderboardService.Refresh()
	H.eq(H.userInfoCalls, calls, "noms gardés en cache")
end)

H.test("budget DataStore bas : rien n'est envoyé, l'ancien tableau reste", function()
	H.requestBudget.SetIncrementSortedAsync = Leaderboard.MIN_BUDGET
	H.requestBudget.GetSortedAsync = Leaderboard.MIN_BUDGET
	local writes, reads = storeOf("week").writes, storeOf("week").reads
	da.season.points = 900
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	LeaderboardService.Refresh()
	H.eq(storeOf("week").writes, writes, "aucune écriture")
	H.eq(storeOf("week").reads, reads, "aucune lecture")
	H.eq(lastState(a).boards.week[1].userId, 1, "classement précédent conservé")
	H.requestBudget.SetIncrementSortedAsync = nil
	H.requestBudget.GetSortedAsync = nil
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	H.eq(storeOf("week").data["1"], 900, "écrit dès que le budget revient")
end)

H.test("panne du DataStore : avertissement, pas de casse, réessai plus tard", function()
	local warnings = #H.warnings
	storeOf("week").failNext = 2
	da.season.points = 950
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	LeaderboardService.Refresh()
	H.ok(#H.warnings > warnings, "panne signalée dans la sortie")
	H.eq(lastState(a).boards.week[1].userId, 1, "classement conservé")
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	H.eq(storeOf("week").data["1"], 950, "réessayé au tour suivant")
end)

H.test("départ du joueur : dernier score écrit tout de suite", function()
	db.season.points = 42
	db.trophies.titles = 2
	H.leave(b)
	H.flush()
	H.eq(storeOf("week").data["2"], 42, "semaine de Bruno")
	H.ok((storeOf("trophies").data["2"] or 0) >= 2, "trophées de Bruno")
	b = H.join(2, "Bruno")
	H.flush()
	db = S.PlayerDataService.GetData(b)
	H.ok(lastState(b), "classement envoyé à l'arrivée")
end)

H.test("nouvelle semaine : nouveau tableau, l'ancien n'est pas effacé", function()
	H.advance(Leaderboard.WRITE_INTERVAL + 16) -- écritures en attente faites
	local oldName = Leaderboard.StoreName("week", os.time())
	local oldWrites = H.getOrderedStore(oldName).writes
	H.advance(Daily.SEASON_SECONDS)
	H.ok(Leaderboard.StoreName("week", os.time()) ~= oldName, "nom du tableau changé")
	H.eq(H.getOrderedStore(oldName).data["1"], 950, "ancienne semaine intacte")
	H.eq(H.getOrderedStore(oldName).writes, oldWrites, "aucune écriture dans l'ancienne semaine")
	LeaderboardService.Refresh()
	local st = lastState(a)
	for _, row in st.boards.week do
		H.ok(row.score > 0, "nouvelle semaine : seulement des scores de cette semaine")
	end
	H.ok(#st.boards.club > 0, "tous les temps : toujours là")
end)

H.test("panneau 3D sur la place : titre, top 10, un tableau après l'autre", function()
	local model = LeaderboardService.GetBoardModel()
	H.ok(model and model.Parent, "panneau construit")
	H.eq(model.Parent.Name, "District", "dans le quartier")
	local screen = model.PrimaryPart:FindFirstChild("Screen")
	H.eq(screen.Title.Text, "WORLD RANKINGS", "titre (anglais côté serveur, traduit par chaque client)")
	H.eq(screen.Title:GetAttribute("TextKey"), "leaderboard.boardTitle", "titre traduit par chaque client")
	LeaderboardService.ShowBoard(2) -- tous les temps
	H.ok(screen.Row1.Text:find("^1%. "), "1re ligne : " .. screen.Row1.Text)
	H.ok(screen.Row1.Text:find("D5") or screen.Row1.Text:find("D6"), "division affichée")
	H.ok(screen.Row10.Text ~= "", "10 lignes")
	H.eq(screen.Subtitle.Text, "Top Clubs", "sous-titre")
	H.advance(Leaderboard.ROTATE_SECONDS + 0.1)
	H.eq(screen.Subtitle.Text, "Trophies", "tableau suivant")
end)

H.test("client : onglet Classement, 3 tableaux, place du joueur", function()
	da.season.points = 77
	H.advance(Leaderboard.WRITE_INTERVAL + 16)
	LeaderboardService.Refresh()
	local gui = H.startClient(MODULES, a)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Ranking")
	H.flush()
	H.ok(H.findText(gui, "Classement mondial"), "carte du classement mondial")
	H.ok(H.findText(gui, "Tous les serveurs"), "portée : tous les serveurs")
	H.ok(H.findText(gui, "Remise à zéro dans"), "fin de la semaine")
	H.ok(H.findText(gui, "Ta place : 1"), "place d'Alice")
	H.ok(H.findText(gui, "1. " .. da.club.name), "Alice en tête avec son club")
	H.click(gui, "Meilleurs clubs")
	H.ok(H.findText(gui, "D6 · 30 pts"), "tableau tous les temps")
	H.click(gui, "Trophées")
	H.ok(H.findText(gui, "trophées"), "tableau des trophées")
	UI.SetLanguage("en")
	H.flush()
	H.ok(H.findText(gui, "World Rankings"), "traduit en anglais")
	UI.SetLanguage("fr")
end)
