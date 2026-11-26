-- Replay 3D des matchs : chronologie cohérente avec le score, aucun effet sur
-- le résultat, visiteurs prévenus, et le vrai client qui le rejoue.
local S = H.boot(MODULES)
local R = mock.run(MODULES.MatchReplay)
local visitor = H.join(2, "Visiteur")
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local Replay = mock.run(MODULES.Client_MatchReplayController)

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

local function checkTimeline(timeline, events, homeGoals, awayGoals, label)
	H.ok(timeline.duration >= R.MIN_SECONDS and timeline.duration <= R.MAX_SECONDS, label .. " : durée " .. timeline.duration)
	local goals = { home = 0, away = 0 }
	local goalActions = {}
	local previousEnd = -1
	for _, action in timeline.actions do
		H.ok(action.t >= previousEnd - 1e-6, label .. " : actions sans chevauchement")
		previousEnd = action.t + R.ActionSeconds(timeline)
		H.ok(previousEnd <= timeline.duration, label .. " : action avant le coup de sifflet final")
		H.ok(#action.path >= 2, label .. " : trajet du ballon")
		if action.kind == "goal" then
			goals[action.side] += 1
			table.insert(goalActions, action)
			local last = action.path[#action.path]
			local dir = if action.side == "home" then 1 else -1
			H.ok(last[1] * dir > 1 and math.abs(last[2]) < 0.25, label .. " : le ballon finit dans le bon but")
		else
			H.ok(action.kind == "save" or action.kind == "miss", label .. " : type d'action")
		end
	end
	H.eq(goals.home, homeGoals, label .. " : buts à domicile")
	H.eq(goals.away, awayGoals, label .. " : buts à l'extérieur")
	H.eq(#goalActions, #events, label .. " : un but rejoué par but marqué")
	for i, event in events do
		H.eq(goalActions[i].minute, event.minute, label .. " : minute du but")
		H.eq(goalActions[i].scorer, event.scorer, label .. " : buteur")
		H.eq(goalActions[i].side, event.side, label .. " : équipe du buteur")
	end
	local h0, a0 = R.ScoreAt(timeline, 0)
	H.ok(h0 == 0 and a0 == 0, label .. " : 0-0 au coup d'envoi")
	local h, a = R.ScoreAt(timeline, timeline.duration)
	H.ok(h == homeGoals and a == awayGoals, label .. " : score final du replay = score du serveur")
end

H.test("match : le replay suit exactement le score calculé par le serveur", function()
	for round = 1, 6 do
		local result = play()
		H.ok(result and result.replay, "replay joint au résultat")
		local replay = result.replay
		H.eq(replay.homeGoals, result.homeGoals, "score domicile")
		H.eq(replay.awayGoals, result.awayGoals, "score extérieur")
		H.eq(replay.slotIndex, S.ClubService.GetSlot(p), "terrain du club hôte")
		H.eq(replay.crowdLevel, data.buildings.Stands, "public selon le niveau des tribunes")
		H.ok(type(replay.homeColor[1]) == "number" and type(replay.awayColor[3]) == "number", "couleurs transmissibles")
		checkTimeline(replay.timeline, result.events, result.homeGoals, result.awayGoals, "match " .. round)
		Replay.Skip()
	end
end)

H.test("chronologie : de 0 à 14 buts, toujours entre 30 et 60 secondes", function()
	for goals = 0, 14 do
		local events = {}
		for i = 1, goals do
			table.insert(events, { minute = (i * 37) % 90 + 1, side = if i % 3 == 0 then "away" else "home", scorer = "J" .. i })
		end
		table.sort(events, function(a, b)
			return a.minute < b.minute
		end)
		local home, away = 0, 0
		for _, e in events do
			if e.side == "home" then
				home += 1
			else
				away += 1
			end
		end
		for seed = 1, 5 do
			checkTimeline(R.Build(events, seed * 1000 + goals), events, home, away, goals .. " buts")
		end
	end
end)

H.test("le replay n'a aucun effet sur le résultat", function()
	-- 1) Il ne touche ni aux événements ni au tirage aléatoire des matchs.
	local events = { { minute = 12, side = "home", scorer = "A" }, { minute = 70, side = "away", scorer = "B" } }
	math.randomseed(42)
	local expected = math.random()
	math.randomseed(42)
	R.Build(events, 99)
	H.eq(math.random(), expected, "tirage des matchs inchangé")
	H.eq(#events, 2, "événements intacts")
	H.eq(events[1].minute, 12, "minute intacte")
	-- 2) Même graine = même replay (rejouable à l'identique chez chaque visiteur).
	local a, b = R.Build(events, 7), R.Build(events, 7)
	H.eq(#a.actions, #b.actions, "même chronologie")
	H.eq(a.actions[1].t, b.actions[1].t, "mêmes horaires")
	-- 3) Si le replay échoue, le match est quand même joué et payé normalement.
	local original = S.MatchService.BuildReplay
	S.MatchService.BuildReplay = function()
		error("panne simulée")
	end
	local coins = data.coins
	local result = play()
	S.MatchService.BuildReplay = original
	H.ok(result, "résultat envoyé")
	H.eq(result.replay, nil, "pas de replay")
	H.eq(data.coins, coins + result.rewards.total + (result.promotionReward or 0) + (result.missionReward or 0), "récompense versée")
	H.ok(H.findText(gui, "Continuer"), "fenêtre de résultat directe sans replay")
	H.click(gui, "Continuer")
end)

H.test("visiteurs : les autres joueurs reçoivent le replay, pas le club hôte", function()
	local before = #H.received(visitor, "MatchReplay")
	local result = play()
	local got = H.received(visitor, "MatchReplay")
	H.eq(#got, before + 1, "replay envoyé au visiteur")
	H.eq(got[#got][1].slotIndex, result.replay.slotIndex, "même terrain")
	H.eq(#H.received(p, "MatchReplay"), 0, "l'hôte ne le reçoit qu'avec son résultat")
	Replay.Skip()
	H.click(gui, "Continuer")
	-- Un visiteur loin du terrain (ou sans personnage) ne voit rien.
	H.eq(Replay.Play(got[#got][1], { spectator = true }), false, "visiteur loin : pas de replay")
end)

H.test("client : le replay se joue jusqu'au bout puis affiche le résultat", function()
	local result = play()
	H.ok(Replay.IsPlaying(), "replay lancé")
	H.ok(workspace:FindFirstChild("MatchReplay"), "joueurs et ballon sur le terrain")
	H.eq(Replay.Debug().fans, 40, "public du niveau 1 des tribunes")
	local function resultVisible()
		local b = H.findText(gui, "Continuer", "TextButton")
		return b ~= nil and b.Parent.Visible == true
	end
	H.ok(not resultVisible(), "résultat caché pendant le replay")
	H.ok(H.findText(gui, "Passer", "TextButton"), "bouton Passer")
	local duration = result.replay.timeline.duration
	H.frames(math.ceil(duration * 30) + 30)
	H.ok(not Replay.IsPlaying(), "replay terminé")
	H.ok(not workspace:FindFirstChild("MatchReplay"), "pièces rangées")
	H.ok(resultVisible(), "fenêtre de résultat à la fin")
	H.click(gui, "Continuer")
end)

H.test("client : le mode accéléré divise la durée par 3, le score suit", function()
	data.buildings.Stands = 5
	local result = play()
	H.eq(Replay.Debug().fans, 160, "grand stade : plus de public")
	H.click(gui, "Avance rapide")
	H.eq(Replay.Debug().speed, 3, "accéléré")
	local duration = result.replay.timeline.duration
	H.frames(math.floor(duration * 30 / 3) - 15)
	local state = Replay.Debug()
	H.ok(state, "toujours en cours juste avant la fin")
	H.ok(state.home <= result.homeGoals and state.away <= result.awayGoals, "score affiché jamais au-dessus du vrai")
	H.frames(60)
	H.ok(not Replay.IsPlaying(), "terminé en un tiers du temps")
	H.ok(H.findText(gui, "Continuer"), "résultat affiché")
	H.click(gui, "Continuer")
end)
