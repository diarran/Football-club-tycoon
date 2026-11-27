--[[
	MatchReplay
	Chronologie d'un replay de match en 3D (purement visuelle).

	Le serveur calcule le résultat d'abord (MatchService.Simulate), PUIS construit
	cette chronologie à partir des buts déjà décidés. Elle ne fait que mettre en
	scène le score : elle n'utilise jamais le tirage aléatoire des matchs (son
	propre générateur, initialisé par une graine) et ne modifie pas les événements.
	Le client la rejoue sur le terrain du club hôte (MatchReplayController).

	Coordonnées du terrain normalisées : x de -1 (but de gauche) à +1 (but de
	droite), z de -1 à +1 sur la largeur. L'équipe à domicile attaque vers +x.

	Chronologie renvoyée par Build :
	  {
	    duration = secondes du replay à vitesse normale (entre MIN et MAX),
	    actionSeconds = durée d'une action (ACTION_SECONDS, moins s'il y a beaucoup de buts),
	    actions = { { t, minute, side, kind = "goal" | "save" | "miss", scorer?, path = { {x, z}, ... } }, ... },
	  }
	Chaque action dure actionSeconds ; son dernier point est l'arrivée du ballon
	(dans le but pour "goal").
]]

local MatchReplay = {}

MatchReplay.INTRO_SECONDS = 3 -- coup d'envoi
MatchReplay.PLAY_SECONDS = 36 -- 90 minutes de match ramenées à 36 s
MatchReplay.OUTRO_SECONDS = 3 -- coup de sifflet final
MatchReplay.ACTION_SECONDS = 4 -- durée d'une action (passes puis tir)
MatchReplay.MIN_SECONDS = 30
MatchReplay.MAX_SECONDS = 60
MatchReplay.FAST_FACTOR = 3 -- mode accéléré
MatchReplay.MAX_ACTIONS = 12 -- buts compris (les buts sont toujours gardés)

-- Petit générateur congruentiel : rejouable, indépendant du tirage des matchs.
local function newRng(seed: number)
	local state = math.floor(math.abs(seed or 1)) % 2147483647
	if state == 0 then
		state = 1
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Mise en scène de chaque style (Tactics.lua) : nombre d'occasions, point de
-- départ des actions (x, 0 = milieu ; négatif = dans son camp) et passes.
MatchReplay.STYLES = {
	Balanced = { chances = 1 },
	Offensive = { chances = 1.4 },
	Defensive = { chances = 0.7, startX = -0.2 },
	Counter = { chances = 1, startX = -0.55, passes = 1 }, -- départ de loin, une passe en profondeur
	Pressing = { chances = 1.2, startX = 0.4, passes = 1 }, -- ballon récupéré haut
}

-- Construit le trajet du ballon d'une action : 2 à 3 passes, puis le tir.
-- style (facultatif) : entrée de MatchReplay.STYLES.
local function buildPath(rand, side: string, kind: string, style)
	local dir = if side == "home" then 1 else -1
	local path = {}
	local x = (rand() - 0.5) * 0.4 -- départ vers le milieu de terrain
	local z = (rand() - 0.5) * 1.2
	if style and style.startX then
		x = style.startX + x * 0.5
	end
	table.insert(path, { x * dir, z })
	local passes = 2 + math.floor(rand() * 2)
	if style and style.passes then
		passes = style.passes
	end
	for i = 1, passes do
		x = x + (0.75 - x) * (i / passes) * 0.8 + rand() * 0.1
		z = math.clamp(z + (rand() - 0.5) * 0.9, -0.85, 0.85)
		table.insert(path, { math.clamp(x, -0.9, 0.9) * dir, z })
	end
	-- Tir
	local shotZ
	if kind == "goal" then
		shotZ = (rand() - 0.5) * 0.36 -- dans le cadre (le but fait ±0,25 de large)
		table.insert(path, { 1.03 * dir, shotZ })
	elseif kind == "save" then
		shotZ = (rand() - 0.5) * 0.2
		table.insert(path, { 0.95 * dir, shotZ }) -- arrêté par le gardien
	else
		shotZ = (if rand() < 0.5 then -1 else 1) * (0.32 + rand() * 0.2)
		table.insert(path, { 1.08 * dir, shotZ }) -- à côté
	end
	return path
end

-- events : buts déjà décidés par le serveur ({ minute, side, scorer }).
-- seed : graine du replay (n'importe quel nombre). Ne modifie pas `events`.
-- tactics (facultatif) : { home = style, away = style } pour la mise en scène :
-- un club offensif se crée plus d'occasions, une contre-attaque part de loin…
function MatchReplay.Build(events, seed: number?, tactics)
	local rand = newRng(seed or 1)
	local styles = {
		home = tactics and MatchReplay.STYLES[tactics.home],
		away = tactics and MatchReplay.STYLES[tactics.away],
	}
	local actions = {}
	for _, event in events or {} do
		table.insert(actions, {
			minute = math.clamp(math.floor(tonumber(event.minute) or 1), 1, 90),
			side = if event.side == "away" then "away" else "home",
			kind = "goal",
			scorer = event.scorer,
			order = #actions + 1,
		})
	end
	-- Occasions manquées pour rythmer le replay (sans effet sur le score).
	-- Avec des tactiques : plus d'occasions pour les styles qui attaquent.
	local homeWeight = if styles.home then styles.home.chances else 1
	local awayWeight = if styles.away then styles.away.chances else 1
	local baseChances = 2 + math.floor(rand() * 3)
	if tactics then
		baseChances = math.floor(baseChances * (homeWeight + awayWeight) / 2 + 0.5)
	end
	local chances = math.min(baseChances, math.max(0, MatchReplay.MAX_ACTIONS - #actions))
	local homeShare = homeWeight / (homeWeight + awayWeight)
	for _ = 1, chances do
		table.insert(actions, {
			minute = 1 + math.floor(rand() * 90),
			side = if rand() < homeShare then "home" else "away",
			kind = if rand() < 0.5 then "save" else "miss",
			order = #actions + 1,
		})
	end
	table.sort(actions, function(a, b)
		if a.minute ~= b.minute then
			return a.minute < b.minute
		end
		return a.order < b.order -- même minute : buts dans l'ordre du serveur, puis occasions
	end)
	for _, action in actions do
		action.order = nil
	end

	-- Durée d'une action : raccourcie s'il y a beaucoup de buts, pour rester
	-- sous la durée maximale sans que deux actions se chevauchent.
	local gap = 0.5
	local available = MatchReplay.MAX_SECONDS - MatchReplay.INTRO_SECONDS - MatchReplay.OUTRO_SECONDS
	local actionSeconds = MatchReplay.ACTION_SECONDS
	if #actions > 0 then
		actionSeconds = math.min(actionSeconds, available / #actions - gap)
	end

	-- Horaires : proportionnels à la minute, sans chevauchement.
	local nextFree = MatchReplay.INTRO_SECONDS
	for _, action in actions do
		local wanted = MatchReplay.INTRO_SECONDS + (action.minute / 90) * MatchReplay.PLAY_SECONDS - actionSeconds
		action.t = math.max(wanted, nextFree)
		nextFree = action.t + actionSeconds + gap
		action.path = buildPath(rand, action.side, action.kind, styles[action.side])
	end
	-- Beaucoup d'actions en fin de match : on les avance (dans l'ordre, sans
	-- chevauchement) pour qu'elles finissent toutes avant le coup de sifflet.
	-- Toutes les actions tiennent dans `available`, donc la 1re reste après
	-- le coup d'envoi.
	local limit = MatchReplay.MAX_SECONDS - MatchReplay.OUTRO_SECONDS
	for index = #actions, 1, -1 do
		local action = actions[index]
		action.t = math.min(action.t, limit - actionSeconds)
		limit = action.t - gap
	end
	if #actions > 0 then
		nextFree = actions[#actions].t + actionSeconds + gap
	end
	local duration = math.max(MatchReplay.INTRO_SECONDS + MatchReplay.PLAY_SECONDS, nextFree - gap)
		+ MatchReplay.OUTRO_SECONDS
	return {
		duration = math.clamp(duration, MatchReplay.MIN_SECONDS, MatchReplay.MAX_SECONDS),
		actionSeconds = actionSeconds,
		actions = actions,
	}
end
-- Durée d'une action de cette chronologie.
function MatchReplay.ActionSeconds(timeline): number
	return tonumber(timeline.actionSeconds) or MatchReplay.ACTION_SECONDS
end

-- Score affiché à l'instant `t` du replay.
function MatchReplay.ScoreAt(timeline, t: number): (number, number)
	local home, away = 0, 0
	for _, action in timeline.actions do
		if action.kind == "goal" and t >= action.t + MatchReplay.ActionSeconds(timeline) then
			if action.side == "home" then
				home += 1
			else
				away += 1
			end
		end
	end
	return home, away
end

-- Minute de jeu affichée à l'instant `t`.
function MatchReplay.MinuteAt(timeline, t: number): number
	local playEnd = timeline.duration - MatchReplay.OUTRO_SECONDS
	local span = playEnd - MatchReplay.INTRO_SECONDS
	if span <= 0 then
		return 90
	end
	return math.clamp(math.floor((t - MatchReplay.INTRO_SECONDS) / span * 90), 0, 90)
end

-- Action en cours à l'instant `t` (ou nil) et sa progression de 0 à 1.
function MatchReplay.ActionAt(timeline, t: number)
	local length = MatchReplay.ActionSeconds(timeline)
	for _, action in timeline.actions do
		if t >= action.t and t < action.t + length then
			return action, (t - action.t) / length
		end
	end
	return nil, 0
end

return MatchReplay
