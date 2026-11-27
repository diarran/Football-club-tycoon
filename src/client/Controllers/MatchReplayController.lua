--[[
	MatchReplayController
	Rejoue en 3D, sur le terrain du club hôte, un match déjà calculé par le serveur.

	- Le résultat ne change jamais ici : on met seulement en scène la chronologie
	  reçue (MatchReplay.Build côté serveur, à partir des buts déjà décidés).
	- Léger pour téléphone : un seul jeu de pièces créé une fois puis réutilisé
	  (22 joueurs de 2 pièces, le ballon, le public), aucun Humanoid ni animation :
	  on déplace seulement les pièces, et uniquement pendant le replay.
	- Le joueur hôte a la caméra de match, « Passer » et le mode accéléré ;
	  les visiteurs proches voient le match se jouer et le tableau d'affichage.
	- À chaque but : confettis aux couleurs de l'équipe derrière le but, public
	  debout, bannière qui pulse, légère secousse de la caméra (hôte) et sons
	  (via les rappels OnStart / OnGoal / OnEnd branchés par Main.client.lua).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local MatchReplay = require(Shared:WaitForChild("MatchReplay"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

local player = Players.LocalPlayer

local MatchReplayController = {}

-- Rappels branchés par Main.client.lua (sons de l'ambiance).
MatchReplayController.OnStart = nil -- function(crowdLevel, spectator)
MatchReplayController.OnGoal = nil -- function(side, spectator)
MatchReplayController.OnEnd = nil -- function()

local CONFETTI_HOST = 60 -- particules par but (hôte)
local CONFETTI_SPECTATOR = 30 -- moins pour un match de voisin

local HALF_L = WorldConfig.PITCH_SIZE.X / 2 -- 50 studs
local HALF_W = WorldConfig.PITCH_SIZE.Y / 2 -- 32 studs
local TURF_Y = 0.45 -- dessus de la pelouse
local RUN_SPEED = 14 -- studs par seconde
local SPECTATOR_RANGE = 230 -- distance max pour qu'un visiteur voie le replay
local CROWD_BY_LEVEL = { 40, 70, 100, 130, 160 }
local CROWD_MAX = CROWD_BY_LEVEL[#CROWD_BY_LEVEL]

-- Formation 4-4-2 de l'équipe qui défend à gauche (x négatif), en studs.
local FORMATION = {
	{ -46, 0, "GK" },
	{ -32, -20 }, { -34, -7 }, { -34, 7 }, { -32, 20 },
	{ -16, -20 }, { -18, -7 }, { -18, 7 }, { -16, 20 },
	{ -4, -8 }, { -4, 8 },
}

local function T(key: string, params: { [string]: any }?): string
	return Locale.T(Locale.ForPlayer(player), key, params)
end

local function toColor(array, fallback: Color3): Color3
	if type(array) == "table" and type(array[1]) == "number" and type(array[2]) == "number" and type(array[3]) == "number" then
		return Color3.fromRGB(math.clamp(array[1], 0, 255), math.clamp(array[2], 0, 255), math.clamp(array[3], 0, 255))
	end
	return fallback
end

-- Pièces réutilisées -----------------------------------------------------

local pool = nil -- { folder, players = { {body, head} }, ball, crowd = { Part }, board, boardLabel }

local function newPart(parent: Instance, name: string, size: Vector3, shape): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function getPool()
	if pool then
		return pool
	end
	local folder = Instance.new("Folder")
	folder.Name = "MatchReplay"
	pool = { folder = folder, players = {}, crowd = {} }
	for index = 1, 22 do
		local body = newPart(folder, "ReplayPlayer", Vector3.new(1.4, 2.6, 0.9))
		local head = newPart(folder, "ReplayHead", Vector3.new(1.1, 1.1, 1.1), Enum.PartType.Ball)
		head.Color = Color3.fromRGB(234, 190, 150)
		-- Short et deux bandes de motif (couleur secondaire de la tenue).
		local shorts = newPart(folder, "ReplayShorts", Vector3.new(1.44, 0.9, 0.94))
		local d1 = newPart(folder, "ReplayPattern", Vector3.new(0.3, 1.7, 0.94))
		local d2 = newPart(folder, "ReplayPattern", Vector3.new(0.3, 1.7, 0.94))
		pool.players[index] = { body = body, head = head, shorts = shorts, d1 = d1, d2 = d2 }
	end
	pool.ball = newPart(folder, "ReplayBall", Vector3.new(0.9, 0.9, 0.9), Enum.PartType.Ball)
	pool.ball.Color = Color3.new(1, 1, 1)
	for index = 1, CROWD_MAX do
		pool.crowd[index] = newPart(folder, "ReplayFan", Vector3.new(1, 1.6, 0.8))
	end
	-- Tableau d'affichage 3D, visible par tous (au-dessus de la tribune nord).
	local board = newPart(folder, "ReplayScoreboard", Vector3.new(1, 1, 1))
	board.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Board"
	billboard.Size = UDim2.new(0, 320, 0, 70)
	billboard.MaxDistance = 400
	billboard.LightInfluence = 0
	billboard.Parent = board
	local boardLabel = Instance.new("TextLabel")
	boardLabel.Name = "Score"
	boardLabel.Size = UDim2.fromScale(1, 1)
	boardLabel.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	boardLabel.BackgroundTransparency = 0.15
	boardLabel.TextColor3 = Color3.new(1, 1, 1)
	boardLabel.Font = Enum.Font.GothamBold
	boardLabel.TextScaled = true
	boardLabel.Text = ""
	boardLabel.Parent = billboard
	pool.board, pool.boardLabel = board, boardLabel
	-- Confettis : un canon invisible derrière chaque but, éteint hors des buts.
	pool.confetti = {}
	for _, side in { "home", "away" } do
		local cannon = newPart(folder, "ReplayConfetti", Vector3.new(1, 1, 1))
		cannon.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Confetti"
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Lifetime = NumberRange.new(1.6, 2.6)
		emitter.Speed = NumberRange.new(20, 30)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.Acceleration = Vector3.new(0, -14, 0)
		emitter.Drag = 1.5
		emitter.Size = NumberSequence.new(0.45)
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.LightEmission = 0.2
		emitter.Parent = cannon
		pool.confetti[side] = { part = cannon, emitter = emitter }
	end
	return pool
end

-- Interface de l'hôte ------------------------------------------------------

local hud = nil -- { gui, score, banner, skip, fast }

local function makeButton(parent: Instance, name: string, position: UDim2, onClick)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, 170, 0, 44)
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(20, 28, 40)
	button.BackgroundTransparency = 0.1
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.Parent = parent
	button.Activated:Connect(onClick)
	return button
end

local function getHud()
	if hud and hud.gui.Parent then
		return hud
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchReplayGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = playerGui

	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.Size = UDim2.new(0, 460, 0, 44)
	score.Position = UDim2.new(0.5, 0, 0, 10)
	score.AnchorPoint = Vector2.new(0.5, 0)
	score.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	score.BackgroundTransparency = 0.15
	score.TextColor3 = Color3.new(1, 1, 1)
	score.Font = Enum.Font.GothamBold
	score.TextScaled = true
	score.Text = ""
	score.Parent = gui

	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	banner.Size = UDim2.new(0, 520, 0, 56)
	banner.Position = UDim2.new(0.5, 0, 0.3, 0)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.BackgroundTransparency = 1
	banner.TextColor3 = Color3.fromRGB(255, 215, 90)
	banner.TextStrokeTransparency = 0.3
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.Text = ""
	banner.Visible = false
	banner.Parent = gui

	hud = { gui = gui, score = score, banner = banner }
	hud.skip = makeButton(gui, "Skip", UDim2.new(1, -12, 1, -12), function()
		MatchReplayController.Skip()
	end)
	hud.fast = makeButton(gui, "Fast", UDim2.new(1, -192, 1, -12), function()
		MatchReplayController.SetFast(not MatchReplayController.IsFast())
	end)
	return hud
end

-- Replay -------------------------------------------------------------------

local active = nil -- état du replay en cours
local connection = nil

local function pitchOrigin(slotIndex: number): CFrame
	local layout = WorldConfig.LAYOUT.Pitch
	return WorldConfig.getPlotCFrame(slotIndex) * CFrame.new(layout.x, WorldConfig.PLOT_GROUND_TOP, layout.z)
end

-- Repère d'une tribune, comme Stands.lua : +Z = on monte en s'éloignant du terrain.
local function standFrame(origin: CFrame, side: string): CFrame
	local hx = HALF_L + WorldConfig.PITCH_RUNOFF
	local hz = HALF_W + WorldConfig.PITCH_RUNOFF
	if side == "North" then
		return origin * CFrame.new(0, 0, hz)
	elseif side == "South" then
		return origin * CFrame.new(0, 0, -hz) * CFrame.Angles(0, math.pi, 0)
	elseif side == "East" then
		return origin * CFrame.new(hx, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	end
	return origin * CFrame.new(-hx, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
end

-- Tribunes présentes selon le niveau (mêmes règles que Stands.lua).
local function standsFor(level: number)
	if level <= 1 then
		return { { side = "North", length = 40, rows = 4 } }
	elseif level == 2 then
		return { { side = "North", length = 90, rows = 6 }, { side = "South", length = 90, rows = 6 } }
	end
	local L, W = HALF_L * 2, HALF_W * 2
	return {
		{ side = "North", length = L, rows = 8 },
		{ side = "South", length = L, rows = 8 },
		{ side = "East", length = W, rows = 6 },
		{ side = "West", length = W, rows = 6 },
	}
end

local function placeCrowd(state)
	local p = state.pool
	local level = math.clamp(math.floor(tonumber(state.replay.crowdLevel) or 1), 1, #CROWD_BY_LEVEL)
	local count = CROWD_BY_LEVEL[level]
	local stands = standsFor(level)
	local seats = {}
	local perStand = math.ceil(count / #stands)
	for _, stand in stands do
		local frame = standFrame(state.origin, stand.side)
		local rows = math.min(stand.rows, 5)
		local perRow = math.ceil(perStand / rows)
		for row = 0, rows - 1 do
			for i = 1, perRow do
				local u = (i - 0.5) / perRow - 0.5
				local jitter = ((i * 7 + row * 3) % 5 - 2) * 0.25
				table.insert(
					seats,
					frame * CFrame.new(u * (stand.length - 4) + jitter, (row + 1) * WorldConfig.STAND_ROW_RISE + 0.8, (row + 0.5) * WorldConfig.STAND_ROW_DEPTH)
				)
			end
		end
	end
	local shirts = { state.homeColor, state.homeColor, state.awayColor, Color3.fromRGB(240, 240, 240), Color3.fromRGB(60, 60, 70) }
	state.fans = {}
	for index, fan in p.crowd do
		local seat = seats[index]
		if index <= count and seat then
			fan.Color = shirts[(index * 7) % #shirts + 1]
			fan.Transparency = 0
			fan.CFrame = seat
			table.insert(state.fans, { part = fan, seat = seat, phase = (index % 6) * 0.5 })
		else
			fan.Transparency = 1
			fan.CFrame = state.origin * CFrame.new(0, -50, 0)
		end
	end
end

-- Hauteur du bloc selon la tactique (studs vers le but adverse, gardien exclu).
-- Motifs du maillot dans le replay : pour chaque bande, { taille, x, y, rotation Z }.
-- y = 0.45 : milieu du maillot (le bas du corps est couvert par le short).
local PATTERN_STRIPS = {
	plain = {},
	stripes = { { Vector3.new(0.3, 1.7, 0.94), -0.35, 0.45, 0 }, { Vector3.new(0.3, 1.7, 0.94), 0.35, 0.45, 0 } },
	pinstripes = { { Vector3.new(0.1, 1.7, 0.94), -0.3, 0.45, 0 }, { Vector3.new(0.1, 1.7, 0.94), 0.3, 0.45, 0 } },
	hoops = { { Vector3.new(1.44, 0.3, 0.94), 0, 0.8, 0 }, { Vector3.new(1.44, 0.3, 0.94), 0, 0.1, 0 } },
	band = { { Vector3.new(1.44, 0.5, 0.94), 0, 0.45, 0 } },
	halves = { { Vector3.new(0.72, 1.7, 0.94), 0.35, 0.45, 0 } },
	sash = { { Vector3.new(0.3, 2, 0.94), 0, 0.45, 40 } },
	chevron = { { Vector3.new(0.25, 0.9, 0.94), -0.3, 0.7, 55 }, { Vector3.new(0.25, 0.9, 0.94), 0.3, 0.7, -55 } },
}
local HIDDEN = CFrame.new(0, -60, 0)

-- Tenue reçue du serveur ({ pattern, shirt = {r,g,b}, detail = {r,g,b} }),
-- ou tenue unie à la couleur `fallback` (ancien format de replay).
local function readKit(kit, fallback: Color3)
	if type(kit) ~= "table" then
		return { pattern = "plain", shirt = fallback, detail = Color3.fromRGB(245, 245, 245) }
	end
	return {
		pattern = if type(kit.pattern) == "string" and PATTERN_STRIPS[kit.pattern] then kit.pattern else "plain",
		shirt = toColor(kit.shirt, fallback),
		detail = toColor(kit.detail, Color3.fromRGB(245, 245, 245)),
	}
end

local LINE_SHIFT = { Offensive = 6, Pressing = 9, Defensive = -7, Counter = -4, Balanced = 0 }

local function setupPlayers(state)
	state.squad = {}
	local shifts = {
		home = LINE_SHIFT[state.replay.homeTactic] or 0,
		away = LINE_SHIFT[state.replay.awayTactic] or 0,
	}
	for index, parts in state.pool.players do
		local team = if index <= 11 then "home" else "away"
		local slot = FORMATION[(index - 1) % 11 + 1]
		local dir = if team == "home" then 1 else -1
		local color = if team == "home" then state.homeColor else state.awayColor
		if slot[3] == "GK" then
			color = if team == "home" then Color3.fromRGB(250, 200, 40) else Color3.fromRGB(120, 220, 90)
		end
		parts.body.Color = color
		-- Motif : seulement pour les joueurs de champ (le gardien reste uni).
		local kit = if team == "home" then state.homeKit else state.awayKit
		local strips = if slot[3] == "GK" then {} else PATTERN_STRIPS[kit.pattern] or {}
		parts.shorts.Color = if slot[3] == "GK" then Color3.fromRGB(30, 30, 36) else kit.detail
		local offsets = {}
		for i, part in { parts.d1, parts.d2 } do
			local strip = strips[i]
			if strip then
				part.Size = strip[1]
				part.Color = kit.detail
				part.Transparency = 0
				offsets[i] = CFrame.new(strip[2], strip[3], 0) * CFrame.Angles(0, 0, math.rad(strip[4]))
			else
				part.Transparency = 1
				part.CFrame = state.origin * HIDDEN
			end
		end
		local slotX = slot[1] + (if slot[3] == "GK" then 0 else shifts[team])
		local member = {
			parts = parts,
			team = team,
			keeper = slot[3] == "GK",
			baseX = slotX * dir,
			baseZ = slot[2] * dir,
			x = slotX * dir,
			z = slot[2] * dir,
			facing = CFrame.Angles(0, if team == "home" then -math.pi / 2 else math.pi / 2, 0),
			strips = offsets,
		}
		table.insert(state.squad, member)
	end
end

-- Position du ballon pendant une action : passes (75 % du temps) puis tir.
local function ballOnPath(action, progress: number): (number, number, number)
	local path = action.path
	local passes = #path - 2 -- segments avant le tir
	local function point(i)
		return path[i][1] * HALF_L, path[i][2] * HALF_W
	end
	if progress < 0.75 and passes > 0 then
		local f = progress / 0.75 * passes
		local i = math.min(math.floor(f) + 1, passes)
		local s = f - (i - 1)
		local ax, az = point(i)
		local bx, bz = point(i + 1)
		return ax + (bx - ax) * s, az + (bz - az) * s, 0
	end
	local s = math.clamp((progress - 0.75) / 0.25, 0, 1)
	local ax, az = point(#path - 1)
	local bx, bz = point(#path)
	return ax + (bx - ax) * s, az + (bz - az) * s, math.sin(s * math.pi) * 3 + s * 1.5
end

local function approach(current: number, target: number, maxStep: number): number
	local delta = target - current
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + math.sign(delta) * maxStep
end

local function updateTexts(state)
	local home, away = MatchReplay.ScoreAt(state.timeline, state.t)
	local minute = MatchReplay.MinuteAt(state.timeline, state.t)
	local text = ("%s  %d - %d  %s   %d'"):format(state.replay.homeName or "?", home, away, state.replay.awayName or "?", minute)
	state.pool.boardLabel.Text = text
	if state.hud then
		state.hud.score.Text = text
		state.hud.fast.Text = if state.speed > 1 then T("replay.normal") else T("replay.fast")
		state.hud.skip.Text = T("replay.skip")
	end
	-- But marqué : bannière et public debout.
	if home + away > state.lastGoals then
		state.lastGoals = home + away
		state.cheerUntil = state.t + 2.5
		state.ballResetAt = state.t + 1.5
		local scorer = state.lastAction and state.lastAction.scorer or "?"
		state.bannerText = T("replay.goal", { scorer = scorer, minute = state.lastAction and state.lastAction.minute or minute })
		state.bannerUntil = state.t + 2.5
		state.bannerFrom = nil
		state.goalBannerUntil = state.t + 2.5
		state.shakeUntil = state.t + 0.6
		local side = (state.lastAction and state.lastAction.side) or (if home > (state.lastHome or 0) then "home" else "away")
		state.lastHome = home
		MatchReplayController.GoalEffects(state, side)
	end
	if state.hud then
		local showBanner = state.bannerUntil and state.t < state.bannerUntil and state.t >= (state.bannerFrom or -1)
		state.hud.banner.Visible = showBanner == true
		if showBanner then
			state.hud.banner.Text = state.bannerText
		end
		-- La bannière « BUT ! » pulse pendant la célébration.
		local scale = 1
		if showBanner and state.goalBannerUntil and state.t < state.goalBannerUntil then
			scale = 1 + 0.12 * math.abs(math.sin(state.t * 8))
		end
		state.hud.banner.Size = UDim2.new(0, math.floor(520 * scale), 0, math.floor(56 * scale))
	end
end

local function step(dt: number)
	local state = active
	if not state then
		return
	end
	dt = math.min(dt, 0.1) * state.speed
	state.t += dt
	if state.t >= state.timeline.duration then
		MatchReplayController.Skip()
		return
	end

	-- Ballon
	local action, progress = MatchReplay.ActionAt(state.timeline, state.t)
	local bx, bz, by = state.ballX, state.ballZ, 0
	if action then
		bx, bz, by = ballOnPath(action, progress)
		if action ~= state.lastAction then
			state.lastAction = action
			if action.kind ~= "goal" then
				state.bannerText = T("replay." .. action.kind)
				state.bannerUntil = action.t + MatchReplay.ActionSeconds(state.timeline) + 1.2
				state.bannerFrom = action.t + MatchReplay.ActionSeconds(state.timeline)
			end
		end
	elseif state.ballResetAt and state.t < state.ballResetAt then
		by = 0 -- le ballon reste au fond des filets
	else
		if state.ballResetAt then
			state.ballResetAt = nil
			bx, bz = 0, 0 -- remise en jeu au centre
		end
		local wx = math.sin(state.t * 0.7) * 18
		local wz = math.sin(state.t * 0.45 + 1) * 14
		bx = approach(bx, wx, 10 * dt)
		bz = approach(bz, wz, 10 * dt)
	end
	state.ballX, state.ballZ = bx, bz
	state.pool.ball.CFrame = state.origin * CFrame.new(bx, TURF_Y + 0.45 + by, bz)

	-- Joueurs : chacun garde son poste en suivant le ballon ; le plus proche de
	-- chaque équipe va au ballon ; le gardien reste sur sa ligne.
	local closest = { home = nil, away = nil }
	local best = { home = math.huge, away = math.huge }
	for _, m in state.squad do
		if not m.keeper then
			local d = (m.x - bx) ^ 2 + (m.z - bz) ^ 2
			if d < best[m.team] then
				best[m.team], closest[m.team] = d, m
			end
		end
	end
	local maxStep = RUN_SPEED * dt
	for _, m in state.squad do
		local tx, tz
		if m.keeper then
			tx = m.baseX
			tz = math.clamp(bz * 0.25, -6, 6)
			if math.abs(bx - m.baseX) < 12 then
				tz = math.clamp(bz, -8, 8)
			end
		elseif m == closest[m.team] then
			tx, tz = bx, bz
		else
			tx = math.clamp(m.baseX + bx * 0.35, -44, 44)
			tz = math.clamp(m.baseZ * 0.85 + bz * 0.25, -HALF_W + 2, HALF_W - 2)
		end
		m.x = approach(m.x, tx, maxStep)
		m.z = approach(m.z, tz, maxStep)
		local base = state.origin * CFrame.new(m.x, TURF_Y + 1.3, m.z) * m.facing
		m.parts.body.CFrame = base
		m.parts.head.CFrame = base * CFrame.new(0, 1.85, 0)
		m.parts.shorts.CFrame = base * CFrame.new(0, -0.86, 0)
		if m.strips[1] then
			m.parts.d1.CFrame = base * m.strips[1]
		end
		if m.strips[2] then
			m.parts.d2.CFrame = base * m.strips[2]
		end
	end

	-- Public : debout et qui saute après un but (sinon immobile, aucun calcul).
	if state.cheerUntil and state.t < state.cheerUntil then
		for _, fan in state.fans do
			fan.part.CFrame = fan.seat * CFrame.new(0, math.abs(math.sin(state.t * 9 + fan.phase)) * 0.9, 0)
		end
		state.cheering = true
	elseif state.cheering then
		state.cheering = false
		for _, fan in state.fans do
			fan.part.CFrame = fan.seat
		end
	end

	updateTexts(state)

	-- Caméra de match (hôte) : vue haute depuis le côté entrée, qui suit le ballon.
	if state.camera then
		state.camX = state.camX + (bx * 0.6 - state.camX) * math.min(1, dt * 2)
		local shake = 0
		if state.shakeUntil and state.t < state.shakeUntil then
			shake = math.sin(state.t * 60) * 0.35 * (state.shakeUntil - state.t) / 0.6
		end
		local eye = state.origin * Vector3.new(state.camX + shake, 34 + shake, -HALF_W - 34)
		local focus = state.origin * Vector3.new(state.camX + (bx - state.camX) * 0.5, 0, bz * 0.4)
		state.camera.CFrame = CFrame.lookAt(eye, focus)
	end
end

local function finish(callDone: boolean)
	local state = active
	if not state then
		return
	end
	active = nil
	if connection then
		connection:Disconnect()
		connection = nil
	end
	state.pool.folder.Parent = nil
	if MatchReplayController.OnEnd then
		pcall(MatchReplayController.OnEnd)
	end
	if state.hud then
		state.hud.gui.Enabled = false
	end
	if state.camera then
		state.camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			state.camera.CameraSubject = humanoid
		end
	end
	if callDone and state.onDone then
		task.spawn(state.onDone)
	end
end

local function nearPitch(origin: CFrame): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - origin.Position).Magnitude <= SPECTATOR_RANGE
end

local function validTimeline(timeline): boolean
	if type(timeline) ~= "table" or type(timeline.duration) ~= "number" or type(timeline.actions) ~= "table" then
		return false
	end
	for _, action in timeline.actions do
		if type(action) ~= "table" or type(action.t) ~= "number" or type(action.path) ~= "table" or #action.path < 2 then
			return false
		end
	end
	return true
end

-- Lance un replay. options = { spectator = bool, onDone = function }.
-- Renvoie true si le replay a démarré (sinon l'appelant affiche directement le résultat).
function MatchReplayController.Play(replay, options): boolean
	options = options or {}
	if type(replay) ~= "table" or not validTimeline(replay.timeline) then
		return false
	end
	local slotIndex = tonumber(replay.slotIndex)
	if not slotIndex or not WorldConfig.SLOTS[slotIndex] then
		return false
	end
	if options.spectator and active and not active.spectator then
		return false -- notre propre match passe avant celui d'un voisin
	end
	local origin = pitchOrigin(slotIndex)
	if options.spectator and not nearPitch(origin) then
		return false
	end
	finish(false)

	local ok, err = pcall(function()
		local p = getPool()
		local state = {
			replay = replay,
			timeline = replay.timeline,
			spectator = options.spectator == true,
			onDone = options.onDone,
			origin = origin,
			pool = p,
			t = 0,
			speed = 1,
			lastGoals = 0,
			ballX = 0,
			ballZ = 0,
			camX = 0,
			homeColor = toColor(replay.homeColor, Color3.fromRGB(200, 40, 50)),
			awayColor = toColor(replay.awayColor, Color3.fromRGB(240, 240, 240)),
		}
		state.homeKit = readKit(replay.homeKit, state.homeColor)
		state.awayKit = readKit(replay.awayKit, state.awayColor)
		setupPlayers(state)
		placeCrowd(state)
		p.board.CFrame = origin * CFrame.new(0, 26, HALF_W + 30)
		if not state.spectator then
			state.hud = getHud()
			if state.hud then
				state.hud.gui.Enabled = true
				-- Coup d'envoi : rappel du duel tactique (« Offensive contre Défensive »).
				local kickoff = T("replay.kickoff")
				if type(replay.homeTactic) == "string" and type(replay.awayTactic) == "string" then
					kickoff = T("replay.kickoffTactics", {
						home = T("tactic." .. replay.homeTactic),
						away = T("tactic." .. replay.awayTactic),
					})
				end
				state.hud.banner.Text = kickoff
				state.bannerText = kickoff
				state.bannerUntil = 2.5
			end
			state.camera = workspace.CurrentCamera
			if state.camera then
				state.camera.CameraType = Enum.CameraType.Scriptable
			end
		end
		for side, cannon in p.confetti do
			local x = (HALF_L + 2) * (if side == "home" then 1 else -1)
			cannon.part.CFrame = origin * CFrame.new(x, TURF_Y + 0.5, 0)
			local color = if side == "home" then state.homeColor else state.awayColor
			pcall(function()
				cannon.emitter.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color),
					ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, color),
				})
			end)
		end
		p.folder.Parent = workspace
		active = state
		if MatchReplayController.OnStart then
			pcall(MatchReplayController.OnStart, replay.crowdLevel, state.spectator)
		end
		step(0)
	end)
	if not ok then
		warn("[Replay] impossible de lancer le replay : " .. tostring(err))
		active = nil
		if pool then
			pool.folder.Parent = nil
		end
		return false
	end
	if RunService.Heartbeat then
		connection = RunService.Heartbeat:Connect(function(dt)
			local okStep, stepErr = pcall(step, dt)
			if not okStep then
				warn("[Replay] erreur pendant le replay : " .. tostring(stepErr))
				MatchReplayController.Skip()
			end
		end)
	end
	return true
end

-- Effets d'un but : confettis derrière le but marqué, puis rappel (sons).
-- side = équipe qui marque ("home" tire vers +X, "away" vers -X).
function MatchReplayController.GoalEffects(state, side: string)
	state.goals = (state.goals or 0) + 1
	local cannon = state.pool.confetti and state.pool.confetti[side]
	if cannon then
		pcall(function()
			cannon.emitter:Emit(if state.spectator then CONFETTI_SPECTATOR else CONFETTI_HOST)
		end)
	end
	if MatchReplayController.OnGoal then
		pcall(MatchReplayController.OnGoal, side, state.spectator)
	end
end

-- Termine le replay tout de suite (bouton « Passer », ou fin normale).
function MatchReplayController.Skip()
	finish(true)
end

function MatchReplayController.SetFast(fast: boolean)
	if active then
		active.speed = if fast then MatchReplay.FAST_FACTOR else 1
		updateTexts(active)
	end
end

function MatchReplayController.IsFast(): boolean
	return active ~= nil and active.speed > 1
end

function MatchReplayController.IsPlaying(): boolean
	return active ~= nil
end

function MatchReplayController.IsSpectating(): boolean
	return active ~= nil and active.spectator
end

-- Avance le replay à la main (tests).
function MatchReplayController.Step(dt: number)
	step(dt)
end

-- État lisible par les tests : temps, score affiché, nombre de supporters.
function MatchReplayController.Debug()
	if not active then
		return nil
	end
	local home, away = MatchReplay.ScoreAt(active.timeline, active.t)
	return { t = active.t, home = home, away = away, fans = #active.fans, speed = active.speed, goals = active.goals or 0 }
end

return MatchReplayController
