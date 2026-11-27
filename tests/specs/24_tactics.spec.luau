-- Tactiques : 5 styles en pierre-feuille-ciseaux, style des clubs fictifs,
-- effet sur la simulation et sur le replay 3D, affichage dans l'onglet Matchs.
local S = H.boot(MODULES)
local Tactics, Config, Divisions, MatchReplay = S.Tactics, S.Config, S.Divisions, S.MatchReplay
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)
local q -- club humain adverse (test « adversaire humain »)

local function play(opponent, tactic)
	H.advance(Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", opponent or "ai", tactic)
	local results = H.received(p, "MatchResult")
	if #results > before then
		return results[#results][1]
	end
	return nil
end

H.test("5 styles, chacun avec son nom en français et en anglais", function()
	H.eq(#Tactics.ORDER, 5, "5 styles affichés")
	for _, id in Tactics.ORDER do
		H.ok(Config.Tactics[id], "effet défini : " .. id)
	end
	local count = 0
	for _ in Config.Tactics do
		count += 1
	end
	H.eq(count, 5, "aucun style caché")
end)

H.test("cycle : chaque style bat un style et perd contre un autre, Équilibré est neutre", function()
	for _, mine in Tactics.ORDER do
		local wins, losses = 0, 0
		for _, theirs in Tactics.ORDER do
			local m = Tactics.Matchup(mine, theirs)
			H.eq(m, -Tactics.Matchup(theirs, mine), "duel symétrique " .. mine .. "/" .. theirs)
			if m > 0 then
				wins += 1
			elseif m < 0 then
				losses += 1
			end
		end
		local expected = if mine == "Balanced" then 0 else 1
		H.eq(wins, expected, mine .. " : victoires tactiques")
		H.eq(losses, expected, mine .. " : défaites tactiques")
	end
	H.eq(Tactics.Matchup("Counter", "Offensive"), 1, "contre-attaque bat offensif")
	H.eq(Tactics.Matchup("Offensive", "Defensive"), 1, "offensif bat défensif")
	H.eq(Tactics.Matchup("Defensive", "Pressing"), 1, "défensif bat pressing")
	H.eq(Tactics.Matchup("Pressing", "Counter"), 1, "pressing bat contre-attaque")
	H.eq(Tactics.CounterOf("Balanced"), nil, "rien ne bat Équilibré")
	H.eq(Tactics.CounterOf("Offensive"), "Counter", "conseil contre Offensif")
end)

H.test("bonus : seul le gagnant du duel tactique est renforcé ; effets fixes modestes", function()
	local a, d = Tactics.Modifiers("Counter", "Offensive")
	H.eq(a, Config.Tactics.Counter.attack + Tactics.EDGE, "attaque du gagnant")
	H.eq(d, Config.Tactics.Counter.defense + Tactics.EDGE, "défense du gagnant")
	a, d = Tactics.Modifiers("Offensive", "Counter")
	H.eq(a, Config.Tactics.Offensive.attack, "perdant : pas de malus en plus")
	H.eq(d, Config.Tactics.Offensive.defense, "perdant : défense inchangée")
	for id, effect in Config.Tactics do
		H.ok(effect.attack + effect.defense <= 1, "aucun style meilleur partout : " .. id)
	end
	a, d = Tactics.Modifiers("Inconnue", nil)
	H.eq(a, 0, "style inconnu -> Équilibré")
	H.eq(d, 0, "style inconnu -> Équilibré")
end)

H.test("clubs fictifs : un style fixe et différent pour chacun des 5 clubs d'une division", function()
	for _, division in Divisions.List do
		local seen = {}
		for _, rival in Divisions.GetRivals(division.id) do
			H.ok(Tactics.IsValid(rival.tactic), "style valide")
			H.ok(not seen[rival.tactic], division.id .. " : styles tous différents")
			seen[rival.tactic] = true
			H.eq(Divisions.GetRival(division.id, rival.index).tactic, rival.tactic, "même style à chaque fois")
		end
	end
	local d7 = Divisions.GetRival("D7", Divisions.DEFAULT_RIVAL).tactic
	local d6 = Divisions.GetRival("D6", Divisions.DEFAULT_RIVAL).tactic
	H.ok(d7 ~= d6, "le club « ai » change de style en montant")
	H.eq(S.MatchService.RivalTeam("D3", 2).tactic, Divisions.GetRival("D3", 2).tactic, "tournoi : même style")
end)

H.test("simulation : avoir l'avantage tactique fait gagner plus souvent", function()
	local function team(tactic)
		local squad = {}
		for i, position in { "GK", "DEF", "DEF", "MID", "ATT" } do
			squad[i] = { name = "J" .. i, position = position, rating = 60, energy = 80 }
		end
		return { id = "t", name = "T", squad = squad, tactic = tactic, bonus = 0 }
	end
	local function goalDiff(homeTactic, awayTactic)
		local total = 0
		for _ = 1, 600 do
			local score = S.MatchService.Simulate(team(homeTactic), team(awayTactic))
			total += score.homeGoals - score.awayGoals
		end
		return total / 600
	end
	local edge = goalDiff("Counter", "Offensive")
	local against = goalDiff("Offensive", "Counter")
	H.ok(edge > against + 0.3, ("écart net : %.2f contre %.2f"):format(edge, against))
	local score = S.MatchService.Simulate(team("Pressing"), team("Counter"))
	H.eq(score.tactics.edge, 1, "duel indiqué dans le résultat")
	H.eq(score.tactics.home, "Pressing", "style de l'hôte")
end)

H.test("match contre un club fictif : son style compte, le conseil donne l'avantage", function()
	local rival = Divisions.GetRival(data.club.division, Divisions.DEFAULT_RIVAL)
	local counter = Tactics.CounterOf(rival.tactic)
	local result = play("ai", counter or "Balanced")
	H.ok(result, "match joué")
	H.eq(result.tactics.away, rival.tactic, "style du club fictif")
	H.eq(result.tactics.edge, if counter then 1 else 0, "avantage tactique")
	H.eq(result.replay.homeTactic, counter or "Balanced", "replay : style de l'hôte")
	H.eq(result.replay.awayTactic, rival.tactic, "replay : style adverse")
	H.eq(data.tactic, counter or "Balanced", "style retenu")
end)

H.test("ancienne sauvegarde : style absent ou inconnu -> Équilibré, le match se joue", function()
	data.tactic = nil
	local result = play("ai", nil)
	H.ok(result, "match joué sans style enregistré")
	H.eq(data.tactic, "Balanced", "style par défaut")
	data.tactic = "Catenaccio2019"
	result = play("ai", "Triche")
	H.ok(result, "match joué avec un ancien style inconnu")
	H.eq(data.tactic, "Balanced", "style réparé")
	H.eq(result.tactics.home, "Balanced", "simulé en Équilibré")
end)

H.test("adversaire humain : son style est visible et compte dans la simulation", function()
	q = H.join(2, "Rival")
	local other = S.PlayerDataService.GetData(q)
	other.tactic = "Offensive"
	local listed
	for _, club in S.ClubService.GetClubList() do
		if club.id == "player:2" then
			listed = club
		end
	end
	H.eq(listed and listed.tactic, "Offensive", "style dans la liste des clubs")
	local result = play("player:2", "Counter")
	H.ok(result, "match joué")
	H.eq(result.tactics.edge, 1, "contre-attaque bat offensif")
	H.eq(other.tactic, "Offensive", "style adverse jamais modifié")
end)

H.test("replay 3D : même score, chances et départs selon les styles", function()
	local events = { { minute = 10, side = "home", scorer = "A" }, { minute = 70, side = "away", scorer = "B" } }
	local plain = MatchReplay.Build(events, 42)
	local again = MatchReplay.Build(events, 42, nil)
	H.eq(#plain.actions, #again.actions, "sans tactique : comme avant")
	local homeChances, awayChances = 0, 0
	for seed = 1, 200 do
		local timeline = MatchReplay.Build(events, seed, { home = "Offensive", away = "Defensive" })
		local goals = 0
		for _, action in timeline.actions do
			if action.kind == "goal" then
				goals += 1
			elseif action.side == "home" then
				homeChances += 1
			else
				awayChances += 1
			end
		end
		H.eq(goals, 2, "les buts du serveur sont tous là")
		H.ok(timeline.duration <= MatchReplay.MAX_SECONDS, "durée maximale")
	end
	H.ok(homeChances > awayChances * 1.4, ("offensif : plus d'occasions (%d contre %d)"):format(homeChances, awayChances))
	local counter = MatchReplay.Build({ { minute = 30, side = "home", scorer = "C" } }, 7, { home = "Counter", away = "Offensive" })
	for _, action in counter.actions do
		if action.side == "home" then
			H.ok(action.path[1][1] < -0.2, "contre-attaque : départ dans son camp")
			H.eq(#action.path, 3, "contre-attaque : une passe puis le tir")
		end
	end
end)

H.test("onglet Matchs : 5 boutons, style adverse, conseil, puis ligne dans le résultat", function()
	-- Adversaire seul : le rival humain part, il ne reste que les clubs fictifs.
	H.leave(q)
	data.missions.list = {}
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	for _, id in Tactics.ORDER do
		H.ok(H.findText(gui, S.Locale.T("fr", "tactic." .. id), "TextButton"), "bouton " .. id)
	end
	local rival = Divisions.GetRival(data.club.division, Divisions.DEFAULT_RIVAL)
	local styleName = S.Locale.T("fr", "tactic." .. rival.tactic)
	H.ok(H.findText(gui, "Style de jeu : " .. styleName), "style du club fictif affiché")
	local counter = Tactics.CounterOf(rival.tactic)
	if counter then
		H.click(gui, S.Locale.T("fr", "tactic." .. counter))
		H.ok(H.findText(gui, "✓ Avantage tactique"), "avantage annoncé")
		local loser = Tactics.BEATS[rival.tactic]
		H.click(gui, S.Locale.T("fr", "tactic." .. loser))
		H.ok(H.findText(gui, "✗ Attention"), "désavantage annoncé")
		H.click(gui, S.Locale.T("fr", "tactic." .. counter))
	end
	H.advance(Config.MATCH_COOLDOWN_SECONDS + 1)
	UI.Refresh()
	H.click(gui, "Jouer")
	H.frames(5)
	H.click(gui, "Passer")
	if counter then
		H.ok(H.findText(gui, "Avantage tactique : "), "ligne tactique dans le résultat")
	end
	H.click(gui, "Continuer")
end)
