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
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local WorldConfig = require(Shared.WorldConfig)

local player = Players.LocalPlayer

-- Texte dans la langue du joueur (voir Locale : français ou anglais).
local function T(key: string, params: { [string]: any }?): string
	return Locale.T(Locale.ForPlayer(player), key, params)
end

local UIController = {}

-- Rappels branchés par Main.client.lua
UIController.OnMenuOpened = nil -- function()
UIController.OnMenuClosed = nil -- function()
UIController.OnTabOpened = nil -- function(tabId)
UIController.OnMatchResultClosed = nil -- function()
UIController.OnSettingChanged = nil -- function(settingId, value)
UIController.OnLanguageChanged = nil -- function(lang)

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

-- Nom affiché : clé « tab.<id> » de Locale.
local TABS = { "Home", "Stadium", "Squad", "Matches", "Ranking", "Settings" }

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
	-- Le texte rétrécit s'il est trop long (langues plus longues, petits écrans),
	-- sans dépasser sa taille normale.
	base.TextScaled = true
	local instance = create("TextButton", base, {
		corner(8),
		create("UITextSizeConstraint", { MaxTextSize = base.TextSize, MinTextSize = 10 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
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
	return division and T("division.label", { tier = division.tier }) or id
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
		then T("home.pointsToPromote", { points = club.divisionPoints, needed = division.pointsToPromote })
		else T("home.topDivision")
	local nextDivision = Divisions.GetNext(club.division)
	if nextDivision and (nextDivision.promotionReward or 0) > 0 then
		progress ..= " · " .. T("home.promotionReward", { coins = formatCoins(nextDivision.promotionReward) })
	end
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
			T("home.balance", { coins = formatCoins(profile.coins) }),
			{ TextColor3 = COLORS.gold, Font = Enum.Font.GothamBold }
		),
		label(
			T("home.record", {
				played = stats.played,
				wins = stats.wins,
				draws = stats.draws,
				losses = stats.losses,
				goals = stats.goalsFor,
			}),
			{ TextColor3 = COLORS.muted }
		),
	}).Parent =
		content

	local nameBox = create("TextBox", {
		BackgroundColor3 = COLORS.panel,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = T("home.newNamePlaceholder"),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 18,
		Size = UDim2.new(1, -170, 0, 44),
	}, { corner(8) })
	local renameButton = button(T("home.rename"), function()
		Net.Get("RequestRename"):FireServer(nameBox.Text)
	end, { Position = UDim2.new(1, -160, 0, 0) })

	card({
		label(T("home.clubNameTitle"), { Font = Enum.Font.GothamBold }),
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
			action = button(T("stadium.upgrade", { cost = formatCoins(cost) }), function()
				Net.Get("RequestUpgrade"):FireServer(def.id)
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if affordable then COLORS.accent else COLORS.disabled,
			})
		else
			action = label(T("stadium.maxLevel"), { TextColor3 = COLORS.gold })
		end
		card({
			label(
				T("stadium.levelLine", { name = T("building." .. def.id .. ".label"), level = level, max = maxLevel }),
				{ Font = Enum.Font.GothamBold }
			),
			label(T("building." .. def.id .. ".description"), { TextColor3 = COLORS.muted, TextSize = 16 }),
			action,
		}).Parent =
			content
	end
end

-- Effectif complet : bouton de transfert si la division a un marché.
local function transferControl(profile)
	local division = Divisions.Get(profile.club.division)
	local market = division and division.transfer
	if not market then
		return label(T("squad.fullTransferLater"), { TextColor3 = COLORS.muted })
	end
	local weakest = nil
	for _, footballer in profile.squad do
		if not weakest or footballer.rating < weakest.rating then
			weakest = footballer
		end
	end
	if weakest and weakest.rating >= market.ratingMax then
		return label(T("squad.transferNoBetter"), { TextColor3 = COLORS.muted })
	end
	return button(
		T("squad.transfer", { cost = formatCoins(market.cost), name = weakest and weakest.name or "?" }),
		function()
			Net.Get("RequestTransfer"):FireServer()
		end,
		{
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = if profile.coins >= market.cost then COLORS.accent else COLORS.disabled,
		}
	)
end

function renderers.Squad(profile)
	local squad = profile.squad
	local full = #squad >= Config.MAX_SQUAD_SIZE
	card({
		label(
			T("squad.count", { count = #squad, max = Config.MAX_SQUAD_SIZE }),
			{ Font = Enum.Font.GothamBold }
		),
		if full
			then transferControl(profile)
			else button(T("squad.recruit", { cost = formatCoins(PlayerConfig.RECRUIT_COST) }), function()
				Net.Get("RequestRecruit"):FireServer()
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if profile.coins >= PlayerConfig.RECRUIT_COST
					then COLORS.accent
					else COLORS.disabled,
			}),
	}).Parent =
		content

	-- Centre de formation : jeunes repérés, à signer à bas prix.
	local prospects = profile.prospects or {}
	card({
		label(T("academy.title"), { Font = Enum.Font.GothamBold }),
		label(
			if #prospects == 0 then T("academy.empty") else T("academy.hint"),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
	}).Parent =
		content
	for _, prospect in prospects do
		local position = if PlayerConfig.Positions[prospect.position]
			then T("position." .. prospect.position)
			else prospect.position
		card({
			label("⭐ " .. prospect.name, { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
			label(
				T("academy.prospectLine", {
					position = position,
					age = prospect.age,
					rating = prospect.rating,
					potential = prospect.potential,
				}),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
			button(T("academy.sign", { cost = formatCoins(prospect.cost) }), function()
				Net.Get("RequestSignProspect"):FireServer(prospect.id)
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if not full and profile.coins >= prospect.cost
					then COLORS.accent
					else COLORS.disabled,
			}),
		}).Parent =
			content
	end

	local canRelease = #squad > Config.STARTING_PLAYERS
	for _, footballer in squad do
		local position = if PlayerConfig.Positions[footballer.position]
			then T("position." .. footballer.position)
			else footballer.position
		local children = {
			label((if footballer.youth then "⭐ " else "") .. footballer.name, { Font = Enum.Font.GothamBold }),
			label(
				T("squad.playerLine", {
					position = position,
					age = footballer.age,
					rating = footballer.rating,
					potential = footballer.potential,
					energy = math.floor(footballer.energy),
				}),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
		}
		if canRelease then
			table.insert(
				children,
				button(T("squad.release"), function()
					Net.Get("RequestRelease"):FireServer(footballer.id)
				end, { Size = UDim2.new(0, 160, 0, 44), BackgroundColor3 = COLORS.disabled })
			)
		end
		card(children).Parent = content
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
		local selected = state.selectedTactic == tacticId
		button(T("tactic." .. tacticId), function()
			state.selectedTactic = tacticId
			UIController.Refresh()
		end, {
			LayoutOrder = index,
			Size = UDim2.new(0.32, -6, 0, 44),
			BackgroundColor3 = if selected then COLORS.accent else COLORS.panel,
		}).Parent =
			tacticRow
	end
	card({ label(T("matches.tactic"), { Font = Enum.Font.GothamBold }), tacticRow }).Parent = content

	local cooldown = math.max(0, math.ceil(state.cooldownEndsAt - os.clock()))
	if cooldown > 0 then
		card({ label(T("matches.cooldown", { seconds = cooldown }), { TextColor3 = COLORS.gold }) }).Parent =
			content
	end

	local function opponentCard(title: string, subtitle: string, opponentId: string)
		card({
			label(title, { Font = Enum.Font.GothamBold }),
			label(subtitle, { TextColor3 = COLORS.muted, TextSize = 16 }),
			button(T("matches.play"), function()
				Net.Get("RequestMatch"):FireServer(opponentId, state.selectedTactic)
			end, { BackgroundColor3 = if cooldown > 0 then COLORS.disabled else COLORS.accent }),
		}).Parent =
			content
	end

	local division = Divisions.Get(profile.club.division)
	local myId = "player:" .. player.UserId
	local humans = 0
	for _, club in state.clubs do
		if club.id ~= myId then
			humans += 1
		end
	end
	-- Clubs fictifs de la division quand il n'y a pas assez de clubs humains.
	for _, rival in Divisions.GetSuggestedRivals(division.id, humans) do
		opponentCard(
			rival.name,
			T("matches.aiSubtitle", {
				division = divisionLabel(division.id),
				rating = rival.rating,
				reward = math.floor(rival.rewardFactor * 100 + 0.5),
			}),
			rival.id
		)
	end
	for _, club in state.clubs do
		if club.id ~= myId then
			opponentCard(
				club.clubName,
				T("matches.clubSubtitle", {
					owner = club.ownerName,
					division = divisionLabel(club.division),
					rating = club.rating,
					count = club.squadSize,
				}),
				club.id
			)
		end
	end
end

-- Classement de la division du joueur : clubs fictifs + clubs humains de la
-- même division, triés par points. Ligne de montée sous les clubs qui montent.
local function divisionTable(profile)
	local division = Divisions.Get(profile.club.division)
	local myId = "player:" .. player.UserId
	local rows = {}
	for _, rival in Divisions.GetRivals(division.id) do
		table.insert(rows, { name = rival.name, points = rival.points, fictional = true })
	end
	local mineListed = false
	for _, club in state.clubs do
		if club.division == division.id then
			table.insert(rows, { name = club.clubName, points = club.divisionPoints, mine = club.id == myId })
			mineListed = mineListed or club.id == myId
		end
	end
	if not mineListed then
		table.insert(rows, { name = profile.club.name, points = profile.club.divisionPoints, mine = true })
	end
	table.sort(rows, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return (a.mine and not b.mine) or false
	end)
	local children = {
		label(T("ranking.divisionTitle", { division = divisionLabel(division.id) }), { Font = Enum.Font.GothamBold }),
		label(
			if division.pointsToPromote
				then T("ranking.promotionRule", { points = division.pointsToPromote })
				else T("ranking.topDivisionRule"),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
	}
	for rank, row in rows do
		table.insert(
			children,
			label(
				T(if row.fictional then "ranking.rowFictional" else "ranking.row", {
					rank = rank,
					name = row.name,
					points = row.points,
				}),
				{ TextColor3 = if row.mine then COLORS.gold else COLORS.text, TextSize = 16 }
			)
		)
	end
	card(children).Parent = content
end

function renderers.Ranking(profile)
	divisionTable(profile)
	label(T("ranking.serverTitle"), { Font = Enum.Font.GothamBold }).Parent = content
	if #state.clubs == 0 then
		card({ label(T("ranking.empty")) }).Parent = content
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
				T("ranking.line", {
					division = divisionLabel(club.division),
					points = club.divisionPoints,
					wins = club.stats.wins,
					draws = club.stats.draws,
					losses = club.stats.losses,
					owner = club.ownerName,
				}),
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
			button(if value then T("settings.on") else T("settings.off"), function()
				state.settings[settingId] = not state.settings[settingId]
				if UIController.OnSettingChanged then
					UIController.OnSettingChanged(settingId, state.settings[settingId])
				end
				UIController.Refresh()
			end, { BackgroundColor3 = if value then COLORS.accent else COLORS.disabled }),
		}).Parent =
			content
	end
	toggle("managementCamera", T("settings.managementCamera"))
	toggle("showTutorial", T("settings.showTutorial"))

	-- Langue : un bouton par langue gérée, celle en cours en surbrillance.
	local current = Locale.ForPlayer(player)
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, lang in Locale.SUPPORTED do
		button(Locale.NativeNames[lang], function()
			UIController.SetLanguage(lang)
		end, {
			Name = "Language_" .. lang,
			LayoutOrder = index,
			BackgroundColor3 = if lang == current then COLORS.accent else COLORS.disabled,
			Parent = row,
		})
	end
	card({ label(T("settings.language"), { Font = Enum.Font.GothamBold }), row }).Parent = content
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
		label(T("hud.loadingClub"), { Name = "ClubName", Font = Enum.Font.GothamBold, LayoutOrder = 1 }),
		label("", { Name = "Division", TextColor3 = COLORS.muted, TextSize = 16, LayoutOrder = 2 }),
		label("", {
			Name = "Coins",
			TextColor3 = COLORS.gold,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			LayoutOrder = 3,
		}),
	})

	button(T("hud.menuButton"), function()
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
	for index, tabId in TABS do
		tabButtons[tabId] = button(T("tab." .. tabId), function()
			UIController.OpenTab(tabId)
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

-- Change la langue de l'interface (Paramètres). Le serveur l'enregistre aussi
-- sur le joueur pour que ses messages suivent la même langue.
function UIController.SetLanguage(lang: string)
	if not Locale.IsSupported(lang) then
		return
	end
	player:SetAttribute("Language", lang)
	Net.Get("RequestLanguage"):FireServer(lang)
	UIController.Refresh()
	if UIController.OnLanguageChanged then
		UIController.OnLanguageChanged(lang)
	end
end

function UIController.Refresh()
	local profile = state.profile
	-- Textes fixes (boutons du HUD et onglets), dans la langue en cours.
	gui.MenuButton.Text = T("hud.menuButton")
	for tabId, tabButton in tabButtons do
		tabButton.Text = T("tab." .. tabId)
	end
	if profile then
		hud.ClubName.Text = profile.club.name or T("hud.myClub")
		hud.Division.Text = divisionLabel(profile.club.division)
			.. (if profile.temporary then " · " .. T("hud.testMode") else "")
		hud.Coins.Text = formatCoins(profile.coins)
		refreshCrestBadge(profile)
	end
	if not panel.Visible then
		return
	end
	clearContent()
	if not profile then
		label(T("hud.loading")).Parent = content
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
	local outcomeText = T("result." .. tostring(result.outcome))
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
			T("result.rewards", {
				total = formatCoins(rewards.total),
				match = rewards.match,
				tickets = rewards.tickets,
				sponsor = rewards.sponsor,
				shop = rewards.shop or 0,
				vip = rewards.vip or 0,
			}),
			{ TextColor3 = COLORS.gold, TextXAlignment = Enum.TextXAlignment.Center }
		)
	)
	if result.promoted then
		local promotedText = T("result.promoted", { division = divisionLabel(result.division) })
		if (result.promotionReward or 0) > 0 then
			promotedText ..= " " .. T("result.promotionReward", { coins = formatCoins(result.promotionReward) })
		end
		add(label(promotedText, {
			Font = Enum.Font.GothamBold,
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	else
		add(
			label(T("result.points", { division = divisionLabel(result.division), points = result.divisionPoints }), centered)
		)
	end
	add(button(T("result.continue"), function()
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
