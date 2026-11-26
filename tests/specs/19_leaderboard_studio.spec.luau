-- Classement sans DataStore (Studio sans accès aux API) : clubs de ce serveur
-- seulement, aucune requête, écran qui le dit clairement.
H.datastoreAvailable = false
local S = H.boot(MODULES)
local Leaderboard = mock.run(MODULES.Leaderboard)
local LeaderboardService = mock.run(MODULES.LeaderboardService)

H.test("mode test : classement de ce serveur, sans DataStore ni erreur", function()
	local a = H.join(1, "Alice")
	local b = H.join(2, "Bruno")
	H.flush()
	local da = S.PlayerDataService.GetData(a)
	local db = S.PlayerDataService.GetData(b)
	da.season.points, db.season.points = 5, 12
	H.advance(Leaderboard.FIRST_REFRESH + Leaderboard.WRITE_INTERVAL + 20)
	LeaderboardService.Refresh()
	local list = H.received(a, "LeaderboardUpdated")
	local st = list[#list][1]
	H.eq(st.scope, "server", "ce serveur seulement")
	H.eq(#st.boards.week, 2, "deux clubs")
	H.eq(st.boards.week[1].userId, 2, "Bruno devant")
	H.eq(st.boards.week[1].club, db.club.name, "nom du club")
	H.eq(next(H.orderedStores), nil, "aucun DataStore ordonné utilisé")
	H.eq(S.PlayerDataService.BuildSnapshot(a).leaderboard.ranks.week, 2, "place d'Alice")

	local gui = H.startClient(MODULES, a)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Ranking")
	H.flush()
	H.ok(H.findText(gui, "Mode test : seulement les clubs de ce serveur"), "écran : mode test expliqué")
	local screen = LeaderboardService.GetBoardModel().PrimaryPart.Screen
	LeaderboardService.ShowBoard(1)
	H.ok(screen.Subtitle.Text:find("this server"), "panneau 3D : ce serveur")
	H.ok(screen.Row1.Text:find(db.club.name, 1, true), "panneau 3D : Bruno en tête")
	H.leave(a)
	H.leave(b)
	H.shutdown()
end)
