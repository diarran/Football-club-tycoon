--[[
	UIController
	HUD et menus de gestion (document de conception, section 8).

	L'interface est créée par code pour rester versionnée dans GitHub.
	Elle ne fait qu'AFFICHER l'état envoyé par le serveur et ENVOYER des
	demandes : aucun prix ni solde n'est calculé ou décidé ici.

	Menus : Accueil, Stade, Effectif, Matchs, Classement, Paramètres.
	Tailles en échelle + UIScale pour rester lisible sur mobile et tablette.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Brand = require(Shared.Brand)
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Divisions = require(Shared.Divisions)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local WorldConfig = require(Shared.WorldConfig)

local player = Players.LocalPlayer

local UIController = {}

-- Rappels branchés par Main.client.lua
UIController.OnMenuOpened = nil -- function()
UIController.OnMenuClosed = nil -- function()
UIController.OnTabOpened = nil -- function(tabId)
UIController.OnMatchResultClosed = nil -- function()
UIController.OnSettingChanged = nil -- function(settingId, value)

local COLORS = {
	background = Color3.fromRGB(18, 24, 38),
	panel = Color3.fromRGB(28, 36, 54),
	card = Color3.fromRGB(40, 50, 72),
	accent = Color3.fromRGB(46, 170, 90),
	accentDark = Color3.fromRGB(30, 120, 64),
	gold = Color3.fromRGB(245, 196, 66),
	text = Color3.fromRGB(240, 244, 250),
	muted = Color3.fromRGB(160, 170, 190),
	error = Color3.fromRGB(220, 80, 80),
	disabled = Color3.fromRGB(80, 86, 100),
}

local TABS = {
	{ id = "Home", label = "Accueil" },
	{ id = "Stadium", label = "Stade" },
	{ id = "Squad", label = "Effectif" },
	{ id = "Matches", label = "Matchs" },
	{ id = "Ranking", label = "Classement" },
	{ id = "Settings", label = "Paramètres" },
}

local state = {
	profile = nil,
	clubs = {},
	cooldownEndsAt = 0,
	selectedTactic = Config.DEFAULT_TACTIC,
	settings = { managementCamera = true, showTutorial = true },
}

local gui, hud, crestBadge, panel, content, tabButtons, toast, resultPopup
local currentTab = "Home"

-- Outils de construction ------------------------------------------------

local function create(className: string, props, children)
	local instance = Instance.new(className)
	for key, value in props or {} do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius: number?)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function padding(px: number)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(text: string, props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props or {} do
		base[key] = value
	end
	return create("TextLabel", base)
end

local function button(text: string, onClick, props)
	local base = {
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.accent,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 18,
		Size = UDim2.new(0, 160, 0, 44), -- 44 px minimum : confortable au doigt
	}
	for key, value in props or {} do
		base[key] = value
	end
	local instance = create("TextButton", base, { corner(8) })
	instance.Activated:Connect(onClick)
	return instance
end

local function card(children, height: number?)
	return create("Frame", {
		BackgroundColor3 = COLORS.card,
		Size = UDim2.new(1, 0, 0, height or 0),
		AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
	}, {
		corner(8),
		padding(10),
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		table.unpack(children),
	})
end

local function formatCoins(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return formatted .. " FC"
end

local function divisionLabel(id: string): string
	local division = Divisions.Get(id)
	return division and division.label or id
end

local function clearContent()
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- Contenu des onglets ---------------------------------------------------

local renderers = {}

function renderers.Home(profile)
	local club = profile.club
	local division = Divisions.Get(club.division)
	local progress = if division and division.pointsToPromote
		then ("%d / %d points pour monter"):format(club.divisionPoints, division.pointsToPromote)
		else "Division la plus haute du MVP atteinte !"
	local stats = club.stats

	-- Logo du jeu en tête de l'accueil (image importée si disponible, sinon titre).
	local logo = Brand.LogoImage()
	if logo then
		create("ImageLabel", {
			Name = "Logo",
			BackgroundTransparency = 1,
			Image = logo,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(1, 0, 0, 72),
			Parent = content,
		})
	else
		label(Brand.GAME_TITLE, {
			Name = "Logo",
			Font = Enum.Font.GothamBlack,
			TextColor3 = COLORS.gold,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
		}).Parent = content
	end

	card({
		label(club.name, { Font = Enum.Font.GothamBold, TextSize = 24 }),
		label(divisionLabel(club.division) .. " · " .. progress, { TextColor3 = COLORS.muted }),
		label(
			"Solde : " .. formatCoins(profile.coins),
			{ TextColor3 = COLORS.gold, Font = Enum.Font.GothamBold }
		),
		label(
			("Bilan : %d matchs · %d V · %d N · %d D · %d buts marqués"):format(
				stats.played,
				stats.wins,
				stats.draws,
				stats.losses,
				stats.goalsFor
			),
			{ TextColor3 = COLORS.muted }
		),
	}).Parent =
		content

	local nameBox = create("TextBox", {
		BackgroundColor3 = COLORS.panel,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = "Nouveau nom du club",
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 18,
		Size = UDim2.new(1, -170, 0, 44),
	}, { corner(8) })
	local renameButton = button("Renommer", function()
		Net.Get("RequestRename"):FireServer(nameBox.Text)
	end, { Position = UDim2.new(1, -160, 0, 0) })

	card({
		label("Nom du club", { Font = Enum.Font.GothamBold }),
		create(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) },
			{ nameBox, renameButton }
		),
	}).Parent =
		content
end

function renderers.Stadium(profile)
	for _, def in Buildings.List() do
		local level = profile.buildings[def.id] or 1
		local maxLevel = Buildings.MaxLevel(def.id)
		local cost = Buildings.GetUpgradeCost(def.id, level)
		local action
		if cost then
			local affordable = profile.coins >= cost
			action = button("Améliorer · " .. formatCoins(cost), function()
				Net.Get("RequestUpgrade"):FireServer(def.id)
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if affordable then COLORS.accent else COLORS.disabled,
			})
		else
			action = label("Niveau maximum", { TextColor3 = COLORS.gold })
		end
		card({
			label(
				("%s · niveau %d / %d"):format(def.label, level, maxLevel),
				{ Font = Enum.Font.GothamBold }
			),
			label(def.description, { TextColor3 = COLORS.muted, TextSize = 16 }),
			action,
		}).Parent =
			content
	end
end

function renderers.Squad(profile)
	local squad = profile.squad
	local full = #squad >= Config.MAX_SQUAD_SIZE
	card({
		label(
			("Effectif : %d / %d joueurs"):format(#squad, Config.MAX_SQUAD_SIZE),
			{ Font = Enum.Font.GothamBold }
		),
		if full
			then label("Effectif complet.", { TextColor3 = COLORS.muted })
			else button("Recruter · " .. formatCoins(PlayerConfig.RECRUIT_COST), function()
				Net.Get("RequestRecruit"):FireServer()
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if profile.coins >= PlayerConfig.RECRUIT_COST
					then COLORS.accent
					else COLORS.disabled,
			}),
	}).Parent =
		content

	for _, footballer in squad do
		local position = PlayerConfig.Positions[footballer.position]
		card({
			label(footballer.name, { Font = Enum.Font.GothamBold }),
			label(
				("%s · %d ans · Note %d · Potentiel %d · Énergie %d%%"):format(
					position and position.label or footballer.position,
					footballer.age,
					footballer.rating,
					footballer.potential,
					math.floor(footballer.energy)
				),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
		}).Parent =
			content
	end
end

function renderers.Matches(profile)
	-- Tactique
	local tacticRow = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, tacticId in { "Defensive", "Balanced", "Offensive" } do
		local tactic = Config.Tactics[tacticId]
		local selected = state.selectedTactic == tacticId
		button(tactic.label, function()
			state.selectedTactic = tacticId
			UIController.Refresh()
		end, {
			LayoutOrder = index,
			Size = UDim2.new(0.32, -6, 0, 44),
			BackgroundColor3 = if selected then COLORS.accent else COLORS.panel,
		}).Parent =
			tacticRow
	end
	card({ label("Tactique", { Font = Enum.Font.GothamBold }), tacticRow }).Parent = content

	local cooldown = math.max(0, math.ceil(state.cooldownEndsAt - os.clock()))
	if cooldown > 0 then
		card({ label(("Prochain match possible dans %d s."):format(cooldown), { TextColor3 = COLORS.gold }) }).Parent =
			content
	end

	local function opponentCard(title: string, subtitle: string, opponentId: string)
		card({
			label(title, { Font = Enum.Font.GothamBold }),
			label(subtitle, { TextColor3 = COLORS.muted, TextSize = 16 }),
			button("Jouer", function()
				Net.Get("RequestMatch"):FireServer(opponentId, state.selectedTactic)
			end, { BackgroundColor3 = if cooldown > 0 then COLORS.disabled else COLORS.accent }),
		}).Parent =
			content
	end

	local division = Divisions.Get(profile.club.division)
	opponentCard(
		"Club amical",
		("Adversaire généré · %s · note ~%d"):format(division.label, division.opponentRating),
		"ai"
	)
	local myId = "player:" .. player.UserId
	for _, club in state.clubs do
		if club.id ~= myId then
			opponentCard(
				club.clubName,
				("%s · %s · note %d · %d joueurs"):format(
					club.ownerName,
					divisionLabel(club.division),
					club.rating,
					club.squadSize
				),
				club.id
			)
		end
	end
end

function renderers.Ranking(_profile)
	if #state.clubs == 0 then
		card({ label("Aucun club sur le serveur.") }).Parent = content
		return
	end
	local myId = "player:" .. player.UserId
	for rank, club in state.clubs do
		card({
			label(("%d. %s"):format(rank, club.clubName), {
				Font = Enum.Font.GothamBold,
				TextColor3 = if club.id == myId then COLORS.gold else COLORS.text,
			}),
			label(
				("%s · %d pts · %d V %d N %d D · dirigé par %s"):format(
					divisionLabel(club.division),
					club.divisionPoints,
					club.stats.wins,
					club.stats.draws,
					club.stats.losses,
					club.ownerName
				),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
		}).Parent =
			content
	end
end

function renderers.Settings(_profile)
	local function toggle(settingId: string, text: string)
		local value = state.settings[settingId]
		card({
			label(text, { Font = Enum.Font.GothamBold }),
			button(if value then "Activé" else "Désactivé", function()
				state.settings[settingId] = not state.settings[settingId]
				if UIController.OnSettingChanged then
					UIController.OnSettingChanged(settingId, state.settings[settingId])
				end
				UIController.Refresh()
			end, { BackgroundColor3 = if value then COLORS.accent else COLORS.disabled }),
		}).Parent =
			content
	end
	toggle("managementCamera", "Vue du club quand le menu est ouvert")
	toggle("showTutorial", "Afficher le tutoriel")
end

-- Construction de l'interface -------------------------------------------

-- Écusson du club à gauche du HUD : image importée si disponible (Brand),
-- sinon un écusson dessiné aux couleurs du terrain avec le sigle du club.
local function buildCrestBadge()
	crestBadge = create("Frame", {
		Name = "Crest",
		BackgroundColor3 = COLORS.card,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(56, 56),
		Parent = gui,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		create("UIStroke", { Name = "Stroke", Thickness = 3, Color = COLORS.gold }),
		label("FC", {
			Name = "Tag",
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
			AutomaticSize = Enum.AutomaticSize.None,
		}),
		create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
		}),
	})
end

local function refreshCrestBadge(profile)
	local slot = player:GetAttribute("ClubSlot")
	local colors = WorldConfig.CLUB_COLORS[slot]
	if colors then
		crestBadge.BackgroundColor3 = colors.primary
		crestBadge.Stroke.Color = colors.secondary
		crestBadge.Tag.TextColor3 = colors.secondary
	end
	crestBadge.Tag.Text = Brand.Tag(profile.club.name)
	local image = Brand.CrestImage(slot)
	crestBadge.Image.Image = image or ""
	crestBadge.Image.Visible = image ~= nil
	crestBadge.Tag.Visible = image == nil
	crestBadge.BackgroundTransparency = if image then 1 else 0
end

local function buildHud()
	buildCrestBadge()
	hud = create("Frame", {
		Name = "HUD",
		BackgroundColor3 = COLORS.background,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(76, 12),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	}, {
		corner(10),
		padding(10),
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		label("Chargement du club…", { Name = "ClubName", Font = Enum.Font.GothamBold, LayoutOrder = 1 }),
		label("", { Name = "Division", TextColor3 = COLORS.muted, TextSize = 16, LayoutOrder = 2 }),
		label("", {
			Name = "Coins",
			TextColor3 = COLORS.gold,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			LayoutOrder = 3,
		}),
	})

	button("Club", function()
		UIController.SetMenuOpen(not panel.Visible)
	end, {
		Name = "MenuButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(110, 56),
		TextSize = 22,
		Parent = gui,
	})
end

local function buildPanel()
	panel = create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.82),
		BackgroundColor3 = COLORS.panel,
		Visible = false,
		Parent = gui,
	}, {
		corner(14),
		create("UISizeConstraint", { MaxSize = Vector2.new(760, 560) }),
	})

	local tabBar = create("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -74, 0, 48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = panel,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	tabButtons = {}
	for index, tab in TABS do
		tabButtons[tab.id] = button(tab.label, function()
			UIController.OpenTab(tab.id)
		end, { LayoutOrder = index, Size = UDim2.fromOffset(120, 44), TextSize = 16, Parent = tabBar })
	end

	button("X", function()
		UIController.SetMenuOpen(false)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(48, 44),
		BackgroundColor3 = COLORS.error,
		Parent = panel,
	})

	content = create("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 66),
		Size = UDim2.new(1, -20, 1, -76),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})
end

local function buildToast()
	toast = label("", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 0),
		BackgroundColor3 = COLORS.background,
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	corner(10).Parent = toast
	padding(10).Parent = toast
	create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }).Parent = toast
end

local function buildResultPopup()
	resultPopup = create("Frame", {
		Name = "MatchResult",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.85, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.background,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, {
		corner(14),
		padding(16),
		create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
end

-- Échelle de l'interface selon la taille de l'écran (mobile, tablette, PC).
local function setupScaling()
	local uiScale = create("UIScale", { Parent = gui })
	local camera = workspace.CurrentCamera
	local function update()
		local viewport = camera.ViewportSize
		local shortest = math.min(viewport.X, viewport.Y)
		uiScale.Scale = math.clamp(shortest / 720, 0.7, 1.2)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

-- API publique ----------------------------------------------------------

function UIController.Init()
	gui = create("ScreenGui", {
		Name = "FCTycoonUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildHud()
	buildPanel()
	buildToast()
	buildResultPopup()
	setupScaling()
end

function UIController.GetScreenGui()
	return gui
end

function UIController.GetSettings()
	return state.settings
end

function UIController.SetMenuOpen(open: boolean)
	panel.Visible = open
	if open then
		UIController.OpenTab(currentTab)
		if UIController.OnMenuOpened then
			UIController.OnMenuOpened()
		end
	elseif UIController.OnMenuClosed then
		UIController.OnMenuClosed()
	end
end

function UIController.OpenTab(tabId: string)
	currentTab = tabId
	for id, tabButton in tabButtons do
		tabButton.BackgroundColor3 = if id == tabId then COLORS.accent else COLORS.card
	end
	UIController.Refresh()
	if UIController.OnTabOpened then
		UIController.OnTabOpened(tabId)
	end
end

function UIController.Refresh()
	local profile = state.profile
	if profile then
		hud.ClubName.Text = profile.club.name or "Mon club"
		hud.Division.Text = divisionLabel(profile.club.division)
			.. (if profile.temporary then " · mode test" else "")
		hud.Coins.Text = formatCoins(profile.coins)
		refreshCrestBadge(profile)
	end
	if not panel.Visible then
		return
	end
	clearContent()
	if not profile then
		label("Chargement…").Parent = content
		return
	end
	local renderer = renderers[currentTab]
	if renderer then
		renderer(profile)
	end
end

function UIController.SetProfile(profile)
	if not profile then
		return
	end
	state.profile = profile
	state.cooldownEndsAt = os.clock() + (profile.matchCooldown or 0)
	UIController.Refresh()
end

function UIController.SetClubs(clubs)
	state.clubs = clubs or {}
	if currentTab == "Matches" or currentTab == "Ranking" then
		UIController.Refresh()
	end
end

local toastToken = 0
function UIController.Notify(message: string, kind: string?)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.TextColor3 = if kind == "error"
		then COLORS.error
		elseif kind == "success" then COLORS.accent
		else COLORS.text
	toast.Visible = true
	task.delay(3.5, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

function UIController.ShowMatchResult(result)
	for _, child in resultPopup:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local outcomeText = ({ Win = "Victoire !", Draw = "Match nul", Loss = "Défaite" })[result.outcome]
	local order = 0
	local function add(instance)
		order += 1
		instance.LayoutOrder = order
		instance.ZIndex = 11
		instance.Parent = resultPopup
		return instance
	end
	local centered = { TextXAlignment = Enum.TextXAlignment.Center }

	add(label(outcomeText, {
		Font = Enum.Font.GothamBold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if result.outcome == "Win"
			then COLORS.accent
			elseif result.outcome == "Loss" then COLORS.error
			else COLORS.text,
	}))
	add(
		label(
			("%s  %d - %d  %s"):format(result.homeName, result.homeGoals, result.awayGoals, result.awayName),
			{ Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center }
		)
	)
	for _, event in result.events do
		local team = if event.side == "home" then result.homeName else result.awayName
		add(label(("%d' ⚽ %s (%s)"):format(event.minute, event.scorer, team), {
			TextSize = 16,
			TextColor3 = COLORS.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	local rewards = result.rewards
	add(
		label(
			("Récompenses : %s (match %d + billetterie %d + sponsors %d)"):format(
				formatCoins(rewards.total),
				rewards.match,
				rewards.tickets,
				rewards.sponsor
			),
			{ TextColor3 = COLORS.gold, TextXAlignment = Enum.TextXAlignment.Center }
		)
	)
	if result.promoted then
		add(label(("Montée ! Bienvenue en %s."):format(divisionLabel(result.division)), {
			Font = Enum.Font.GothamBold,
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	else
		add(
			label(("%s · %d points"):format(divisionLabel(result.division), result.divisionPoints), centered)
		)
	end
	add(button("Continuer", function()
		resultPopup.Visible = false
		if UIController.OnMatchResultClosed then
			UIController.OnMatchResultClosed()
		end
	end))

	resultPopup.Visible = true
	resultPopup.Size = UDim2.fromScale(0.75, 0)
	TweenService
		:Create(resultPopup, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.85, 0) })
		:Play()
end

-- Met à jour le compte à rebours de l'onglet Matchs.
task.spawn(function()
	while true do
		task.wait(1)
		if panel and panel.Visible and currentTab == "Matches" and state.cooldownEndsAt > os.clock() - 1 then
			UIController.Refresh()
		end
	end
end)

return UIController
