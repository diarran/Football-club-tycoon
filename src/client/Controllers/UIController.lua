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
local Audio = require(Shared.Audio)
local Brand = require(Shared.Brand)
local Community = require(Shared.Community)
local Buildings = require(Shared.Buildings)
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Trophies = require(Shared.Trophies)
local Divisions = require(Shared.Divisions)
local Daily = require(Shared.Daily)
local Leaderboard = require(Shared.Leaderboard)
local Friends = require(Shared.Friends)
local Locale = require(Shared.Locale)
local Monetization = require(Shared.Monetization)
local Net = require(Shared.Net)
local Onboarding = require(Shared.Onboarding)
local PlayerConfig = require(Shared.PlayerConfig)
local Staff = require(Shared.Staff)
local Tactics = require(Shared.Tactics)
local Training = require(Shared.Training)
local TutorialSteps = require(Shared.TutorialSteps)
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
local TABS = { "Home", "Stadium", "Squad", "Management", "Matches", "Ranking", "Prestige", "Settings" }

local state = {
	profile = nil,
	clubs = {},
	cooldownEndsAt = 0,
	cupReadyAt = 0, -- os.clock() où le prochain tour de Coupe nationale est jouable
	selectedTactic = Config.DEFAULT_TACTIC,
	selectedStake = Config.Challenge.STAKES[2],
	challenges = { incoming = {}, outgoing = nil },
	tournament = nil,
	tournamentEndsAt = 0,
	leaderboard = nil, -- classement mondial (LeaderboardService)
	leaderboardBoard = "week", -- tableau affiché : week, club ou trophies
	settings = { managementCamera = true, showTutorial = true, volume = Audio.DEFAULT_VOLUME, music = true },
}

local gui, hud, crestBadge, panel, content, tabButtons, toast, resultPopup, welcomePopup
local tabBar, tabGrid -- barre d'onglets et sa grille (1 ou 2 rangées selon l'écran)
local TAB_HEIGHT = 44
local TAB_GAP = 4
local shownWelcome = nil -- dernier résumé « Pendant ton absence… » affiché
local shownEventWeek = nil -- dernier événement de la semaine annoncé
local currentTab = "Home"
local unlockedTabs = nil -- onglets ouverts au dernier profil reçu (annonce des déblocages)

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
	-- %.0f : pas d'écriture « 1e+12 » pour les très grands soldes.
	local text = string.format("%.0f", math.floor(amount))
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

-- Durée lisible (« 3 jours 4 heures », « 2 h 15 min », « 12 min »).
local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds or 0))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return T("time.dh", { d = d, h = h })
	elseif h > 0 then
		return T("time.hm", { h = h, m = m })
	end
	return T("time.m", { m = math.max(1, m) })
end

-- Objectifs quotidiens et saison (accueil). daily = instantané de DailyService.
local function dailyCards(daily)
	if type(daily) ~= "table" then
		return
	end
	card({
		label(T("daily.title"), { Font = Enum.Font.GothamBold }),
		label(T("daily.streak", { day = daily.cycleDay }), { TextColor3 = COLORS.gold }),
		label(T("daily.next", { coins = formatCoins(daily.nextReward or 0) }), { TextColor3 = COLORS.muted }),
	}).Parent = content

	local missionLines = {
		label(T("daily.missionsTitle"), { Font = Enum.Font.GothamBold }),
	}
	for _, mission in daily.missions or {} do
		local name = T("mission." .. mission.id, { n = mission.target })
		local line = if mission.done
			then T("mission.lineDone", { mission = name, coins = formatCoins(mission.reward) })
			else T("mission.line", {
				mission = name,
				progress = mission.progress,
				target = mission.target,
				coins = formatCoins(mission.reward),
			})
		table.insert(missionLines, label(line, {
			Name = "Mission_" .. mission.id,
			TextColor3 = if mission.done then COLORS.accent else COLORS.text,
		}))
	end
	table.insert(missionLines, label(T("daily.resetIn", { time = formatDuration(daily.resetIn) }), { TextColor3 = COLORS.muted }))
	local missionsCard = card(missionLines)
	missionsCard.Name = "Missions"
	missionsCard.Parent = content

	local season = daily.season
	if type(season) == "table" then
		local lines = {
			label(T("season.title"), { Font = Enum.Font.GothamBold }),
			label(T("season.status", {
				rank = season.rank,
				total = #(season.rows or {}),
				points = season.points,
				time = formatDuration(season.endsIn),
			}), { TextColor3 = COLORS.gold }),
		}
		for index, row in season.rows or {} do
			table.insert(lines, label(("%d. %s · %d pts"):format(index, row.name, row.points), {
				TextSize = 16,
				Font = if row.me then Enum.Font.GothamBold else Enum.Font.Gotham,
				TextColor3 = if row.me then COLORS.accent else COLORS.muted,
			}))
		end
		table.insert(lines, label(T("season.rewardNow", { coins = formatCoins(season.reward or 0) }), { TextColor3 = COLORS.muted }))
		table.insert(lines, label(T("season.info"), { TextColor3 = COLORS.muted, TextSize = 16 }))
		if type(season.last) == "table" then
			table.insert(lines, label(T("season.last", { rank = season.last.rank, coins = formatCoins(season.last.reward) }), {
				TextColor3 = COLORS.muted,
				TextSize = 16,
			}))
		end
		local seasonCard = card(lines)
		seasonCard.Name = "Season"
		seasonCard.Parent = content
	end
end

-- Événement de la semaine (accueil). event = instantané d'EventService.
local function eventCard(event)
	if type(event) ~= "table" or type(event.theme) ~= "string" then
		return
	end
	local endsIn = math.max(0, (state.eventEndsAt or 0) - os.clock())
	local lines = {
		label(T("event.title", { event = T("event.theme." .. event.theme) }), {
			Font = Enum.Font.GothamBold,
			TextColor3 = COLORS.gold,
		}),
		label(T("event.desc." .. event.theme), { TextSize = 16 }),
		label(T("event.status", { points = event.points or 0, time = formatDuration(endsIn) }), { TextColor3 = COLORS.accent }),
	}
	local claimable = false
	for index, tier in event.tiers or {} do
		local reward = formatCoins(tier.coins)
		if tier.cosmetic then
			reward ..= " + " .. T("cosmetic." .. tier.cosmetic)
		end
		local key = if tier.claimed then "event.tierClaimed" elseif tier.reached then "event.tierReady" else "event.tier"
		claimable = claimable or (tier.reached and not tier.claimed)
		table.insert(lines, label(T(key, { n = index, points = tier.points, reward = reward }), {
			Name = "EventTier_" .. index,
			TextSize = 16,
			TextColor3 = if tier.claimed then COLORS.muted elseif tier.reached then COLORS.gold else COLORS.text,
		}))
	end
	if claimable then
		table.insert(lines, button(T("event.claim"), function()
			Net.Get("RequestEventClaim"):FireServer()
		end, { Name = "EventClaim", Size = UDim2.new(0, 260, 0, 44), BackgroundColor3 = COLORS.gold }))
	end
	table.insert(lines, label(
		if event.weekend
			then T("event.cupNow", { percent = math.floor(((event.cupMultiplier or 1) - 1) * 100 + 0.5) })
			else T("event.cupSoon", { time = formatDuration(math.max(0, (state.eventWeekendAt or 0) - os.clock())) }),
		{ TextColor3 = COLORS.muted, TextSize = 16 }
	))
	local eventFrame = card(lines)
	eventFrame.Name = "WeeklyEvent"
	eventFrame.Parent = content
end

-- Contenu des onglets ---------------------------------------------------

local renderers = {}

-- Carte « Soutiens le jeu » : favori, groupe Roblox (bonus unique), J'aime.
-- Les fenêtres de Roblox attendent la réponse du joueur : lancées à part.
local function communityCard(profile)
	local children = {
		label(T("community.title"), { Font = Enum.Font.GothamBold }),
		label(T("community.likeReminder"), { TextColor3 = COLORS.muted }),
	}
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local placeId = game.PlaceId
	if type(placeId) == "number" and placeId > 0 then
		button(T("community.favorite"), function()
			task.spawn(pcall, function()
				game:GetService("AvatarEditorService"):PromptSetFavorite(placeId, Enum.AvatarItemType.Asset, true)
			end)
		end, { Name = "FavoriteButton", LayoutOrder = 1, Parent = row })
	end
	if Community.GroupEnabled() then
		local claimed = profile.community and profile.community.groupRewardClaimed
		button(
			if claimed then T("community.group") else T("community.groupReward", { coins = formatCoins(Community.GROUP_REWARD) }),
			function()
				task.spawn(function()
					local ok, status = pcall(function()
						return game:GetService("GroupService"):PromptJoinAsync(Community.GROUP_ID)
					end)
					local joined = ok
						and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember)
					if joined and not claimed then
						Net.Get("RequestGroupReward"):FireServer()
					end
				end)
			end,
			{ Name = "GroupButton", LayoutOrder = 2, Size = UDim2.new(0, 220, 0, 44), Parent = row }
		)
	end
	if #row:GetChildren() > 1 then
		table.insert(children, row)
	end
	card(children).Parent = content
end

function renderers.Home(profile)
	local club = profile.club
	local division = Divisions.Get(club.division)
	local progress = if division and division.pointsToPromote
		then T("home.pointsToPromote", { points = club.divisionPoints, needed = division.pointsToPromote })
		else T("prestige.titleProgress", { points = club.divisionPoints, needed = Trophies.TITLE_POINTS })
	local nextDivision = Divisions.GetNext(club.division)
	if nextDivision and (nextDivision.promotionReward or 0) > 0 then
		progress ..= " · " .. T("home.promotionReward", { coins = formatCoins(nextDivision.promotionReward) })
	end
	local stats = club.stats

	-- Logo du jeu en tête de l'accueil : titre écrit, remplacé par l'image importée
	-- (Brand) dès qu'elle est chargée.
	local title = label(Brand.GAME_TITLE, {
		Name = "Logo",
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.gold,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	title.Parent = content
	local logo = Brand.LogoImage()
	if logo then
		local logoImage = create("ImageLabel", {
			Name = "LogoImage",
			BackgroundTransparency = 1,
			Image = logo,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(1, 0, 0, 72),
			Visible = false,
			Parent = content,
		})
		Brand.ShowWhenLoaded(logoImage, function(loaded)
			logoImage.Visible = loaded
			title.Visible = not loaded
		end)
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

	eventCard(profile.event)
	dailyCards(profile.daily)

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

	communityCard(profile)
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

-- Ligne de boutons côte à côte (largeur relative : lisible sur téléphone).
local function buttonRow(entries)
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local width = 1 / #entries
	for index, entry in entries do
		button(entry.text, entry.onClick, {
			LayoutOrder = index,
			Size = UDim2.new(width, -6, 0, 44),
			BackgroundColor3 = entry.color or COLORS.accent,
		}).Parent =
			row
	end
	return row
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

	-- Composition et entraînement (shared/Training.lua).
	local starterSet = {}
	for _, id in profile.lineup or Training.Normalize(squad, nil) do
		starterSet[id] = true
	end
	local canSwap = #squad > Training.STARTERS
	local trainingLevel = profile.buildings.Training or 1
	local teamBonus = Buildings.GetEffects("Training", trainingLevel).teamBonus or 0
	local growthBonus = Staff.Effect(profile.staff or {}, "growthBonus")
	local lineupChildren = {
		label(T("lineup.title", { count = math.min(Training.STARTERS, #squad) }), { Font = Enum.Font.GothamBold }),
		label(T("lineup.hint"), { TextColor3 = COLORS.muted, TextSize = 16 }),
		label(T("training.hint", { xp = Training.XP_PER_POINT }), { TextColor3 = COLORS.muted, TextSize = 16 }),
	}
	if canSwap then
		table.insert(
			lineupChildren,
			button(T("lineup.autoButton"), function()
				Net.Get("RequestLineup"):FireServer("auto")
			end, { Size = UDim2.new(0, 240, 0, 44) })
		)
	end
	card(lineupChildren).Parent = content

	local canRelease = #squad > Config.STARTING_PLAYERS
	local now = os.time()
	for _, footballer in squad do
		local position = if PlayerConfig.Positions[footballer.position]
			then T("position." .. footballer.position)
			else footballer.position
		local isStarter = starterSet[footballer.id] == true
		local roleText = if isStarter then T("lineup.starter") else T("lineup.bench")
		local atPotential = footballer.rating >= footballer.potential
		local children = {
			label(
				(if footballer.youth then "⭐ " else "") .. footballer.name .. " · " .. roleText,
				{ Font = Enum.Font.GothamBold, TextColor3 = if isStarter then COLORS.text else COLORS.muted }
			),
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
			label(
				if atPotential
					then T("training.atPotentialShort")
					else T("training.xpLine", {
						xp = math.floor(footballer.xp or 0),
						max = Training.XP_PER_POINT,
						gain = Training.SessionXp(footballer, teamBonus, growthBonus),
					}),
				{ TextColor3 = if atPotential then COLORS.gold else COLORS.muted, TextSize = 16 }
			),
		}
		local entries = {}
		if not atPotential then
			local cost = Training.SessionCost(footballer.rating)
			local wait = Training.CooldownLeft(footballer, now)
			local ready = wait <= 0 and footballer.energy >= Training.MIN_ENERGY and profile.coins >= cost
			table.insert(entries, {
				text = if wait > 0
					then T("training.wait", { seconds = math.ceil(wait) })
					else T("training.button", { cost = formatCoins(cost) }),
				onClick = function()
					Net.Get("RequestTrain"):FireServer(footballer.id)
				end,
				color = if ready then COLORS.accent else COLORS.disabled,
			})
		end
		if canSwap then
			table.insert(entries, {
				text = if isStarter then T("lineup.toBench") else T("lineup.toPitch"),
				onClick = function()
					Net.Get("RequestLineup"):FireServer(footballer.id, not isStarter)
				end,
				color = if isStarter then COLORS.disabled else COLORS.accent,
			})
		end
		if canRelease then
			table.insert(entries, {
				text = T("squad.release"),
				onClick = function()
					Net.Get("RequestRelease"):FireServer(footballer.id)
				end,
				color = COLORS.disabled,
			})
		end
		if #entries > 0 then
			table.insert(children, buttonRow(entries))
		end
		card(children).Parent = content
	end
end

-- Gestion : staff du club et contrats de sponsoring.
local function durationText(seconds: number): string
	local minutes = math.max(0, math.ceil(seconds / 60))
	return T("management.time", { hours = math.floor(minutes / 60), minutes = minutes % 60 })
end

local function staffEffectText(staffId: string, level: number): string
	local def = Staff.Get(staffId)
	local effects = def and def.levels[level] and def.levels[level].effects or {}
	local function pct(value)
		return math.floor((value or 0) * 100 + 0.5)
	end
	return T("staff." .. staffId .. ".effect", {
		teamBonus = effects.teamBonus or 0,
		growth = pct(effects.growthBonus),
		speed = pct((effects.scoutSpeed or 1) - 1),
		bonus = if staffId == "Commercial" then pct(effects.sponsorBonus) else (effects.prospectBonus or 0),
		recovery = pct((effects.energyRecovery or 1) - 1),
	})
end

local function sponsorGoalText(entry): string
	return T("sponsor.goal." .. tostring(entry.goal), { target = entry.target })
end

function renderers.Management(profile)
	local staffLevels = profile.staff or {}
	card({
		label(T("management.staffTitle"), { Font = Enum.Font.GothamBold }),
		label(T("management.staffHint"), { TextColor3 = COLORS.muted, TextSize = 16 }),
	}).Parent =
		content
	for _, def in Staff.List() do
		local level = staffLevels[def.id] or 0
		local maxLevel = Staff.MaxLevel(def.id)
		local name = T("staff." .. def.id .. ".label")
		local children = {
			label(
				if level > 0
					then T("staff.levelLine", { name = name, level = level, max = maxLevel })
					else T("staff.vacant", { name = name }),
				{ Font = Enum.Font.GothamBold }
			),
		}
		if level > 0 then
			table.insert(children, label(T("staff.current", { effect = staffEffectText(def.id, level) }), {
				TextColor3 = COLORS.muted,
				TextSize = 16,
			}))
		end
		local cost = Staff.GetHireCost(def.id, level)
		if cost then
			table.insert(children, label(T("staff.next", { effect = staffEffectText(def.id, level + 1) }), {
				TextColor3 = COLORS.muted,
				TextSize = 16,
			}))
			table.insert(
				children,
				button(T(if level == 0 then "staff.hire" else "staff.upgrade", { cost = formatCoins(cost) }), function()
					Net.Get("RequestHireStaff"):FireServer(def.id)
				end, {
					Size = UDim2.new(0, 240, 0, 44),
					BackgroundColor3 = if profile.coins >= cost then COLORS.accent else COLORS.disabled,
				})
			)
		else
			table.insert(children, label(T("staff.maxLevel"), { TextColor3 = COLORS.gold }))
		end
		card(children).Parent = content
	end

	local sponsors = profile.sponsors or { offers = {}, contracts = {}, refreshIn = 0, maxActive = 1 }
	local contracts = sponsors.contracts or {}
	card({
		label(T("management.sponsorTitle"), { Font = Enum.Font.GothamBold }),
		label(
			T("management.sponsorHint", { count = #contracts, max = sponsors.maxActive or 1 }),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
		if #contracts == 0
			then label(T("management.noContracts"), { TextColor3 = COLORS.muted, TextSize = 16 })
			else nil,
	}).Parent =
		content
	for _, contract in contracts do
		card({
			label("🤝 " .. contract.brand, { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
			label(
				T("sponsor.contractLine", { perMatch = contract.perMatch, matches = contract.matchesLeft }),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
			label(
				if contract.completed
					then T("sponsor.completed")
					else T("sponsor.progress", {
						goal = sponsorGoalText(contract),
						progress = contract.progress,
						target = contract.target,
					}),
				{ TextColor3 = if contract.completed then COLORS.accent else COLORS.muted, TextSize = 16 }
			),
			button(T("sponsor.cancel"), function()
				Net.Get("RequestCancelSponsor"):FireServer(contract.id)
			end, { Size = UDim2.new(0, 240, 0, 44), BackgroundColor3 = COLORS.disabled }),
		}).Parent =
			content
	end

	local offers = sponsors.offers or {}
	local slotsFull = #contracts >= (sponsors.maxActive or 1)
	card({
		label(
			if #offers > 0
				then T("management.offersTitle", { time = durationText(sponsors.refreshIn or 0) })
				else T("management.noOffers", { time = durationText(sponsors.refreshIn or 0) }),
			{ Font = Enum.Font.GothamBold }
		),
	}).Parent =
		content
	for _, offer in offers do
		card({
			label(offer.brand, { Font = Enum.Font.GothamBold }),
			label(
				T("sponsor.offerLine", { perMatch = offer.perMatch, matches = offer.matches }),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
			label(
				T("sponsor.goalLine", { goal = sponsorGoalText(offer), bonus = offer.bonus }),
				{ TextColor3 = COLORS.muted, TextSize = 16 }
			),
			button(T("sponsor.sign"), function()
				Net.Get("RequestSignSponsor"):FireServer(offer.id)
			end, {
				Size = UDim2.new(0, 240, 0, 44),
				BackgroundColor3 = if slotsFull then COLORS.disabled else COLORS.accent,
			}),
		}).Parent =
			content
	end
end

-- Tournoi du serveur : état, inscription, tableau des matchs joués.
local function tournamentCard()
	local tournament = state.tournament
	if not tournament then
		return
	end
	local myId = "player:" .. player.UserId
	local secondsLeft = math.max(0, math.ceil(state.tournamentEndsAt - os.clock()))
	local cup = tournament.weekendCup == true
	local children = { label(T(if cup then "event.cupTitle" else "tournament.title"), {
		Font = Enum.Font.GothamBold,
		TextColor3 = if cup then COLORS.gold else COLORS.text,
	}) }
	if cup then
		table.insert(children, label(T("event.cupInfo", {
			percent = math.floor(((tournament.cupMultiplier or 1) - 1) * 100 + 0.5),
		}), { TextColor3 = COLORS.accent, TextSize = 16 }))
	end
	local registered = false
	for _, entrant in tournament.entrants do
		registered = registered or entrant.id == myId
	end
	if tournament.phase == "registration" then
		table.insert(children, label(T("tournament.registration", {
			seconds = secondsLeft,
			count = #tournament.entrants,
			size = tournament.size,
		}), { TextColor3 = COLORS.gold, TextSize = 16 }))
		if registered then
			table.insert(children, label(T("tournament.registered"), { TextColor3 = COLORS.accent, TextSize = 16 }))
		else
			table.insert(children, button(T("tournament.join"), function()
				Net.Get("RequestTournamentJoin"):FireServer()
			end))
		end
	elseif tournament.phase == "running" then
		table.insert(children, label(T("tournament.running", { seconds = secondsLeft }), { TextColor3 = COLORS.gold, TextSize = 16 }))
	else
		table.insert(children, label(T("tournament.next", { minutes = math.max(1, math.ceil(secondsLeft / 60)) }), {
			TextColor3 = COLORS.muted,
			TextSize = 16,
		}))
	end
	local rewards = Config.Tournament.Rewards
	table.insert(children, label(T("tournament.rewards", {
		winner = rewards.Winner,
		final = rewards.Final,
		semi = rewards.Semi,
		quarter = rewards.Quarter,
	}), { TextColor3 = COLORS.muted, TextSize = 14 }))
	if tournament.phase ~= "registration" then
		for _, round in tournament.rounds or {} do
			table.insert(children, label(T("tournament.stage." .. round.stage), { Font = Enum.Font.GothamBold, TextSize = 16 }))
			for _, match in round.matches do
				local key = if match.forfeit
					then "tournament.matchForfeit"
					elseif match.penalties then "tournament.matchPenalties"
					else "tournament.match"
				table.insert(children, label(T(key, {
					home = match.homeName,
					away = match.awayName,
					homeGoals = match.homeGoals,
					awayGoals = match.awayGoals,
					winner = match.winnerName,
				}), { TextSize = 14, TextColor3 = COLORS.muted }))
			end
		end
	end
	if tournament.lastWinner and tournament.phase ~= "running" then
		table.insert(children, label(T("tournament.lastWinner", { club = tournament.lastWinner.clubName }), {
			TextColor3 = COLORS.gold,
			TextSize = 16,
		}))
	end
	if state.profile and (state.profile.club.stats.tournamentsWon or 0) > 0 then
		table.insert(children, label(T("tournament.myTrophies", { count = state.profile.club.stats.tournamentsWon }), {
			TextColor3 = COLORS.gold,
			TextSize = 16,
		}))
	end
	card(children).Parent = content
end

-- Club dirigé par un ami Roblox du joueur (liste calculée par le serveur).
local function isFriendClub(profile, clubId: string): boolean
	return profile.friends ~= nil and table.find(profile.friends.clubIds or {}, clubId) ~= nil
end

-- Défis reçus (accepter / refuser) et défi envoyé en attente.
local function challengeCards()
	for _, challenge in state.challenges.incoming do
		card({
			label(
				T(
					if challenge.friendly then "friends.friendlyIncomingTitle" else "challenge.incomingTitle",
					{ club = challenge.clubName, owner = challenge.ownerName }
				),
				{
					Font = Enum.Font.GothamBold,
					TextColor3 = COLORS.gold,
				}
			),
			label(
				if challenge.friendly
					then T("friends.friendlyIncomingLine", { coins = Friends.FRIENDLY_BONUS })
					else T("challenge.incomingLine", { stake = challenge.stake }),
				{ TextSize = 16 }
			),
			buttonRow({
				{
					text = T("challenge.accept"),
					onClick = function()
						Net.Get("RequestChallengeResponse"):FireServer(challenge.id, true)
					end,
				},
				{
					text = T("challenge.refuse"),
					color = COLORS.disabled,
					onClick = function()
						Net.Get("RequestChallengeResponse"):FireServer(challenge.id, false)
					end,
				},
			}),
		}).Parent =
			content
	end
	local outgoing = state.challenges.outgoing
	if outgoing then
		card({
			label(T("challenge.waiting", { club = outgoing.clubName, stake = outgoing.stake }), {
				TextColor3 = COLORS.muted,
				TextSize = 16,
			}),
		}).Parent =
			content
	end
end

function renderers.Matches(profile)
	tournamentCard()
	challengeCards()
	-- Tactique : 5 styles sur 2 rangées (lisible au téléphone), puis ce que
	-- bat le style choisi. Le premier affichage reprend le dernier style joué.
	if not state.tacticLoaded then
		state.tacticLoaded = true
		state.selectedTactic = Tactics.Sanitize(profile.tactic)
	end
	local mine = Tactics.Sanitize(state.selectedTactic)
	local function tacticEntries(ids)
		local entries = {}
		for _, tacticId in ids do
			table.insert(entries, {
				text = T("tactic." .. tacticId),
				color = if mine == tacticId then COLORS.accent else COLORS.panel,
				onClick = function()
					state.selectedTactic = tacticId
					UIController.Refresh()
				end,
			})
		end
		return entries
	end
	local beaten, beatenBy = Tactics.BEATS[mine], Tactics.BeatenBy(mine)
	card({
		label(T("matches.tactic"), { Font = Enum.Font.GothamBold }),
		buttonRow(tacticEntries({ "Balanced", "Offensive", "Defensive" })),
		buttonRow(tacticEntries({ "Counter", "Pressing" })),
		label(
			if beaten and beatenBy
				then T("matches.tacticBeats", {
					tactic = T("tactic." .. mine),
					beaten = T("tactic." .. beaten),
					beatenBy = T("tactic." .. beatenBy),
				})
				else T("matches.tacticSafe", { tactic = T("tactic." .. mine) }),
			{ TextSize = 16 }
		),
		label(T("matches.tacticCycle"), { TextColor3 = COLORS.muted, TextSize = 14 }),
	}).Parent =
		content

	local cooldown = math.max(0, math.ceil(state.cooldownEndsAt - os.clock()))
	if cooldown > 0 then
		card({ label(T("matches.cooldown", { seconds = cooldown }), { TextColor3 = COLORS.gold }) }).Parent =
			content
	end

	-- Style de l'adversaire et conseil tactique (même calcul que le serveur).
	local function tacticLines(theirs)
		theirs = Tactics.Sanitize(theirs)
		local edge = Tactics.Matchup(mine, theirs)
		local counter = Tactics.CounterOf(theirs)
		local params = {
			mine = T("tactic." .. mine),
			theirs = T("tactic." .. theirs),
			counter = if counter then T("tactic." .. counter) else "",
		}
		local hint, color
		if edge > 0 then
			hint, color = T("matches.edgeWin", params), COLORS.accent
		elseif edge < 0 then
			hint, color = T("matches.edgeLose", params), COLORS.error
		elseif not counter then
			hint, color = T("matches.edgeNone", params), COLORS.muted
		else
			hint, color = T("matches.edgeNeutral", params), COLORS.gold
		end
		return label(T("matches.rivalStyle", { tactic = params.theirs }), { TextSize = 16 }),
			label(hint, { TextColor3 = color, TextSize = 16, Name = "TacticHint" })
	end

	-- Coupe nationale : tour en cours, adversaire et son style, puis les tours joués.
	local cup = type(profile.cup) == "table" and profile.cup or nil
	if cup then
		local children = {
			label(T("cup.title"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
			label(T("cup.info"), { TextColor3 = COLORS.muted, TextSize = 14 }),
		}
		local endsIn = math.max(0, cup.endsIn or 0)
		table.insert(children, label(T("cup.endsIn", {
			days = math.floor(endsIn / 86400),
			hours = math.floor((endsIn % 86400) / 3600),
		}), { TextColor3 = COLORS.muted, TextSize = 14 }))
		for _, entry in cup.history or {} do
			local params = {
				stage = T("cup.stage." .. tostring(entry.stage)),
				mine = profile.club.name,
				club = entry.name,
				myGoals = entry.myGoals,
				theirGoals = entry.theirGoals,
				coins = formatCoins(entry.coins or 0),
			}
			local text = T(if entry.won then "cup.historyWin" else "cup.historyLoss", params)
			if entry.penalties then
				text ..= T("cup.historyPenalties")
			end
			if entry.giantKill then
				text ..= T("cup.historyGiant")
			end
			table.insert(children, label(text, {
				TextSize = 14,
				TextColor3 = if entry.won then COLORS.accent else COLORS.error,
			}))
		end
		local nextIn = math.max(0, math.ceil(state.cupReadyAt - os.clock()))
		if cup.status == "playing" and type(cup.opponent) == "table" then
			local rival = cup.opponent
			table.insert(children, label(T("cup.next", {
				stage = T("cup.stage." .. tostring(cup.stage)),
				club = rival.name,
				division = divisionLabel(rival.division),
				rating = rival.rating,
			}), { Font = Enum.Font.GothamBold, TextSize = 16 }))
			if rival.giantKill then
				table.insert(children, label(T("cup.giantWarning"), { TextColor3 = COLORS.gold, TextSize = 14 }))
			end
			local styleLine, hintLine = tacticLines(rival.tactic)
			table.insert(children, styleLine)
			table.insert(children, hintLine)
			table.insert(children, label(T("cup.nextReward", { coins = formatCoins(cup.nextReward or 0) }), {
				TextColor3 = COLORS.gold,
				TextSize = 14,
			}))
			if nextIn > 0 then
				table.insert(children, label(T("cup.wait", { minutes = math.max(1, math.ceil(nextIn / 60)) }), {
					Name = "CupWait",
					TextColor3 = COLORS.muted,
					TextSize = 16,
				}))
			else
				table.insert(children, button(T("cup.play"), function()
					Net.Get("RequestCupMatch"):FireServer(state.selectedTactic)
				end, { BackgroundColor3 = COLORS.accent }))
			end
		elseif cup.status == "champion" then
			table.insert(children, label(T("cup.champion"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, TextSize = 16 }))
		else
			table.insert(children, label(T("cup.out"), { TextColor3 = COLORS.muted, TextSize = 16 }))
		end
		table.insert(children, label(T("cup.maxReward", { coins = formatCoins(cup.maxReward or 0) }), {
			TextColor3 = COLORS.muted,
			TextSize = 14,
		}))
		if (cup.cupsWon or 0) > 0 then
			table.insert(children, label(T("cup.myCups", { count = cup.cupsWon }), { TextColor3 = COLORS.gold, TextSize = 14 }))
		end
		card(children).Parent = content
	end

	local function opponentCard(title: string, subtitle: string, opponentId: string, theirs)
		local styleLine, hintLine = tacticLines(theirs)
		card({
			label(title, { Font = Enum.Font.GothamBold }),
			label(subtitle, { TextColor3 = COLORS.muted, TextSize = 16 }),
			styleLine,
			hintLine,
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
			rival.id,
			rival.tactic
		)
	end
	if humans > 0 then
		-- Mise des défis : une valeur parmi celles acceptées par le serveur.
		local entries = {}
		for _, stake in Config.Challenge.STAKES do
			table.insert(entries, {
				text = tostring(stake),
				color = if state.selectedStake == stake then COLORS.accent else COLORS.panel,
				onClick = function()
					state.selectedStake = stake
					UIController.Refresh()
				end,
			})
		end
		card({
			label(T("challenge.stakeTitle"), { Font = Enum.Font.GothamBold }),
			label(T("challenge.stakeHelp"), { TextColor3 = COLORS.muted, TextSize = 14 }),
			buttonRow(entries),
		}).Parent =
			content
	end
	for _, club in state.clubs do
		if club.id ~= myId then
			local styleLine, hintLine = tacticLines(club.tactic)
			card({
				label(club.clubName .. (if isFriendClub(profile, club.id) then "  · " .. T("friends.tag") else ""), {
					Font = Enum.Font.GothamBold,
				}),
				label(T("matches.clubSubtitle", {
					owner = club.ownerName,
					division = divisionLabel(club.division),
					rating = club.rating,
					count = club.squadSize,
				}), { TextColor3 = COLORS.muted, TextSize = 16 }),
				styleLine,
				hintLine,
				buttonRow({
					{
						text = T("matches.play"),
						color = if cooldown > 0 then COLORS.disabled else COLORS.accent,
						onClick = function()
							Net.Get("RequestMatch"):FireServer(club.id, state.selectedTactic)
						end,
					},
					{
						text = T("challenge.send", { stake = state.selectedStake }),
						color = COLORS.accentDark,
						onClick = function()
							Net.Get("RequestChallenge"):FireServer(club.id, state.selectedStake)
						end,
					},
				}),
			}).Parent =
				content
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

-- Fenêtre officielle de Roblox pour inviter des amis (elle attend le joueur).
local function promptInvite()
	task.spawn(function()
		local SocialService = game:GetService("SocialService")
		local ok, canSend = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not ok or canSend ~= true then
			UIController.Notify(T("friends.cannotInvite"), "error")
			return
		end
		local options = nil
		pcall(function()
			options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = T("friends.invitePrompt")
		end)
		pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
	end)
end

-- Carte « Amis » : invitation, primes de parrainage, matchs amicaux du jour.
local function friendsCard(profile)
	local friends = profile.friends or { clubIds = {}, friendlyLeft = Friends.FRIENDLY_BONUS_PER_DAY, rewardsGiven = 0 }
	card({
		label(T("friends.title"), { Font = Enum.Font.GothamBold }),
		label(
			T("friends.inviteHelp", { coins = formatCoins(Friends.INVITER_REWARD), welcome = formatCoins(Friends.INVITEE_WELCOME) }),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
		label(T("friends.invitedCount", { count = friends.rewardsGiven, max = Friends.MAX_INVITER_REWARDS }), {
			TextSize = 16,
		}),
		label(T("friends.friendlyLeft", {
			count = friends.friendlyLeft,
			max = Friends.FRIENDLY_BONUS_PER_DAY,
			coins = Friends.FRIENDLY_BONUS,
		}), { TextSize = 16 }),
		button(T("friends.invite"), promptInvite, { Name = "InviteButton", Size = UDim2.new(1, 0, 0, 44) }),
		-- Lien du jeu publié, sélectionnable pour le copier (message, réseaux…).
		label(T("friends.gameLink"), { TextColor3 = COLORS.muted, TextSize = 16 }),
		create("TextBox", {
			Name = "GameLink",
			BackgroundColor3 = COLORS.background,
			ClearTextOnFocus = false,
			TextEditable = false,
			Font = Enum.Font.GothamBold,
			Text = Brand.GAME_URL,
			TextColor3 = COLORS.gold,
			TextSize = 15,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 36),
		}, { corner(8) }),
	}).Parent =
		content
end

-- Classement mondial : tous les serveurs (ou ce serveur seulement en mode test).
local function globalLeaderboardCard(profile)
	local lb = state.leaderboard
	local board = state.leaderboardBoard
	local entries = {}
	for _, id in Leaderboard.BOARDS do
		table.insert(entries, {
			text = T("leaderboard.tab." .. id),
			color = if id == board then COLORS.accent else COLORS.disabled,
			onClick = function()
				state.leaderboardBoard = id
				UIController.Refresh()
			end,
		})
	end
	local children = {
		label(T("leaderboard.title"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
		label(
			T(if lb and lb.scope == "server" then "leaderboard.serverHelp" else "leaderboard.globalHelp"),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
		buttonRow(entries),
	}
	if board == "week" then
		local now = os.time()
		table.insert(
			children,
			label(T("leaderboard.weekHelp", { time = formatDuration(Daily.SeasonEndsAt(Daily.SeasonId(now)) - now) }), {
				TextColor3 = COLORS.muted,
				TextSize = 16,
			})
		)
	end
	local rows = lb and lb.boards and lb.boards[board] or {}
	if #rows == 0 then
		table.insert(children, label(T(if lb then "leaderboard.empty" else "leaderboard.loading"), { TextSize = 16 }))
	end
	for _, row in rows do
		local key, params = Leaderboard.ValueText(board, row.score)
		local name = if row.club
			then T("leaderboard.rowClub", { rank = row.rank, club = row.club, name = row.name })
			else T("leaderboard.row", { rank = row.rank, name = row.name })
		table.insert(
			children,
			label(name .. "  ·  " .. T(key, params), {
				TextColor3 = if row.userId == player.UserId then COLORS.gold else COLORS.text,
				TextSize = 16,
			})
		)
	end
	local mine = profile.leaderboard
	if mine and mine.scores then
		local key, params = Leaderboard.ValueText(board, mine.scores[board] or 0)
		local rank = mine.ranks and mine.ranks[board]
		table.insert(
			children,
			label(
				if rank
					then T("leaderboard.myRank", { rank = rank, value = T(key, params) })
					else T("leaderboard.outOfTop", { top = Leaderboard.TOP, value = T(key, params) }),
				{ Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, TextSize = 16 }
			)
		)
	end
	card(children).Parent = content
end

function renderers.Ranking(profile)
	globalLeaderboardCard(profile)
	friendsCard(profile)
	divisionTable(profile)
	label(T("ranking.serverTitle"), { Font = Enum.Font.GothamBold }).Parent = content
	if #state.clubs == 0 then
		card({ label(T("ranking.empty")) }).Parent = content
		return
	end
	local myId = "player:" .. player.UserId
	for rank, club in state.clubs do
		local friend = isFriendClub(profile, club.id)
		local friendRow = nil
		if friend then
			friendRow = buttonRow({
				{
					text = T("friends.friendlyButton"),
					onClick = function()
						Net.Get("RequestChallenge"):FireServer(club.id, 0)
					end,
				},
			})
		end
		card({
			label(("%d. %s"):format(rank, club.clubName) .. (if friend then "  · " .. T("friends.tag") else ""), {
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
			label(T("ranking.trophies", { count = club.trophies or 0 }), { TextColor3 = COLORS.gold, TextSize = 16 }),
			friendRow,
		}).Parent =
			content
	end
end

-- Prestige : salle des trophées et personnalisation (purement visuelle).
function renderers.Prestige(profile)
	local trophies = profile.trophies or {}
	local cosmetics = profile.cosmetics or { owned = {}, equipped = {} }
	local titles = profile.titles or 0
	local top = Divisions.List[#Divisions.List].id

	local trophyLines = {
		label(T("prestige.trophiesTitle", { count = #trophies }), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
		label(
			if profile.club.division == top
				then T("prestige.titleProgress", { points = profile.club.divisionPoints, needed = Trophies.TITLE_POINTS })
				else T("prestige.titleLocked"),
			{ TextColor3 = COLORS.muted, TextSize = 16 }
		),
		label(T("prestige.titlesCount", { titles = titles }), { TextColor3 = COLORS.muted, TextSize = 16 }),
	}
	if #trophies == 0 then
		table.insert(trophyLines, label(T("prestige.noTrophy"), { TextSize = 16 }))
	else
		local names = {}
		for _, trophy in trophies do
			-- Les titres sont résumés par le compteur ci-dessus.
			if trophy.kind ~= "title" then
				table.insert(names, T(trophy.key, trophy.params))
			end
		end
		if #names > 0 then
			table.insert(trophyLines, label(table.concat(names, " · "), { TextSize = 16 }))
		end
	end
	card(trophyLines).Parent = content

	local ownedCount = 0
	for id in cosmetics.owned do
		local item = Cosmetics.Get(id)
		if item and not item.robux and not item.event then
			ownedCount += 1
		end
	end
	card({
		label(T("prestige.intro"), { TextSize = 16 }),
		label(T("prestige.progress", { owned = ownedCount, total = #Cosmetics.List }), { TextColor3 = COLORS.muted, TextSize = 16 }),
	}).Parent =
		content

	-- Boutique Robux : cachée tant qu'aucun ID de produit n'est rempli (Monetization.lua).
	if Monetization.AnyAvailable() then
		local shopLines = {
			label(T("shop.title"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold }),
			label(T("shop.intro"), { TextSize = 16 }),
		}
		local boost = Monetization.Get("boost_income")
		if Monetization.IsAvailable(boost) then
			local seconds = profile.boostSeconds or 0
			table.insert(
				shopLines,
				if seconds > 0
					then label(T("shop.boostActive", { minutes = math.ceil(seconds / 60) }), { TextColor3 = COLORS.gold, TextSize = 16 })
					else label(T("shop.boostInfo", { percent = math.floor((boost.boost.multiplier - 1) * 100 + 0.5), minutes = boost.boost.minutes }), { TextSize = 16 })
			)
			table.insert(shopLines, button(T("shop.buyBoost"), function()
				Net.Get("RequestBuyExclusive"):FireServer(boost.key)
			end, { Size = UDim2.new(0, 260, 0, 44) }))
		end
		card(shopLines).Parent = content
	end

	for _, category in Cosmetics.CATEGORIES do
		label(T("cosmeticCategory." .. category), { Font = Enum.Font.GothamBold }).Parent = content
		local single = Cosmetics.SINGLE[category]
		if single then
			local isDefault = cosmetics.equipped[category] == nil
			card({
				label(T("prestige.default"), { Font = Enum.Font.GothamBold }),
				if isDefault
					then label(T("prestige.equipped"), { TextColor3 = COLORS.gold })
					else button(T("prestige.equip"), function()
						Net.Get("RequestEquipCosmetic"):FireServer(category, "default")
					end),
			}).Parent =
				content
		end
		local items = Cosmetics.ByCategory(category)
		-- Objets exclusifs : visibles une fois possédés, ou si leur achat Robux est ouvert.
		for _, item in Cosmetics.EXCLUSIVE do
			if item.category == category and (cosmetics.owned[item.id] or Monetization.IsAvailable(Monetization.ForCosmetic(item.id))) then
				table.insert(items, item)
			end
		end
		-- Objets des événements : visibles une fois gagnés, ou pendant leur semaine.
		local currentEvent = type(profile.event) == "table" and profile.event.theme or nil
		for _, item in Cosmetics.EVENT do
			if item.category == category and (cosmetics.owned[item.id] or item.event == currentEvent) then
				table.insert(items, item)
			end
		end
		for _, item in items do
			local action
			if cosmetics.owned[item.id] then
				if not single then
					action = label(T("prestige.shown"), { TextColor3 = COLORS.gold })
				elseif cosmetics.equipped[category] == item.id then
					action = label(T("prestige.equipped"), { TextColor3 = COLORS.gold })
				else
					action = button(T("prestige.equip"), function()
						Net.Get("RequestEquipCosmetic"):FireServer(category, item.id)
					end)
				end
			elseif item.event then
				action = label(T("event.locked", { event = T("event.theme." .. item.event) }), { TextColor3 = COLORS.accent, TextSize = 16 })
			elseif item.robux then
				local product = Monetization.ForCosmetic(item.id)
				action = button(T("shop.buyRobux"), function()
					Net.Get("RequestBuyExclusive"):FireServer(product.key)
				end, { Size = UDim2.new(0, 240, 0, 44), BackgroundColor3 = COLORS.gold })
			else
				local unlocked, reason = Cosmetics.IsUnlocked(item, profile.club.division, titles)
				if unlocked then
					local affordable = profile.coins >= item.cost
					action = button(T("prestige.buy", { cost = formatCoins(item.cost) }), function()
						Net.Get("RequestBuyCosmetic"):FireServer(item.id)
					end, {
						Size = UDim2.new(0, 240, 0, 44),
						BackgroundColor3 = if affordable then COLORS.accent else COLORS.disabled,
					})
				elseif reason == "titles" then
					action = label(T("prestige.lockedTitles", { titles = item.requires.titles }), { TextColor3 = COLORS.muted, TextSize = 16 })
				else
					action = label(
						T("prestige.lockedDivision", { division = divisionLabel(item.requires.division) }) .. " · " .. formatCoins(item.cost),
						{ TextColor3 = COLORS.muted, TextSize = 16 }
					)
				end
			end
			local name = T("cosmetic." .. item.id)
			if item.robux then
				name = T("shop.exclusiveTag", { name = name })
			elseif item.event then
				name = T("event.itemTag", { name = name })
			end
			card({ label(name, { Font = Enum.Font.GothamBold }), action }).Parent = content
		end
	end
end

-- Son : volume général par paliers (0 = muet) et musique de fond.
local function renderSoundSettings(toggle)
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local steps = #Audio.VOLUME_STEPS
	for index, value in Audio.VOLUME_STEPS do
		local selected = math.abs((state.settings.volume or 0) - value) < 0.01
		button(if value == 0 then T("settings.mute") else ("%d%%"):format(math.floor(value * 100 + 0.5)), function()
			state.settings.volume = value
			if UIController.OnSettingChanged then
				UIController.OnSettingChanged("volume", value)
			end
			UIController.Refresh()
		end, {
			Name = "Volume_" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1 / steps, -6, 0, 44),
			BackgroundColor3 = if selected then COLORS.accent else COLORS.disabled,
			Parent = row,
		})
	end
	card({ label(T("settings.volume"), { Font = Enum.Font.GothamBold }), row }).Parent = content
	toggle("music", T("settings.music"))
end

function renderers.Settings(profile)
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
	renderSoundSettings(toggle)

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

	-- Code admin : montré seulement à l'administrateur (le serveur revérifie tout).
	if profile and profile.isAdmin then
		local codeBox = create("TextBox", {
			Name = "AdminCodeBox",
			BackgroundColor3 = COLORS.panel,
			ClearTextOnFocus = true,
			Font = Enum.Font.Gotham,
			PlaceholderText = T("admin.placeholder"),
			Text = "",
			TextColor3 = COLORS.text,
			TextSize = 18,
			Size = UDim2.new(1, -170, 0, 44),
		}, { corner(8) })
		local validate = button(T("admin.validate"), function()
			Net.Get("RequestAdminCode"):FireServer(codeBox.Text)
			codeBox.Text = ""
		end, { Name = "AdminCodeButton", Position = UDim2.new(1, -160, 0, 0) })
		card({
			label(T("admin.title"), { Font = Enum.Font.GothamBold }),
			label(
				if profile.adminUnlimited then T("admin.statusOn") else T("admin.statusOff"),
				{ TextColor3 = COLORS.muted }
			),
			create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, { codeBox, validate }),
		}).Parent =
			content
	end
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
	-- Écusson dessiné tant que l'image n'est pas chargée (ou pas encore validée).
	local loaded = image ~= nil and crestBadge:GetAttribute("CrestLoaded") == image
	crestBadge.Image.Visible = loaded
	crestBadge.Tag.Visible = not loaded
	crestBadge.BackgroundTransparency = if loaded then 1 else 0
	if image and not loaded and crestBadge:GetAttribute("CrestWatching") ~= image then
		crestBadge:SetAttribute("CrestWatching", image)
		Brand.ShowWhenLoaded(crestBadge.Image, function(isLoaded)
			if isLoaded and crestBadge.Image.Image == image then
				crestBadge:SetAttribute("CrestLoaded", image)
				crestBadge.Image.Visible = true
				crestBadge.Tag.Visible = false
				crestBadge.BackgroundTransparency = 1
			end
		end)
	end
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
		-- Événement de la semaine et compte à rebours (mis à jour chaque seconde).
		label("", {
			Name = "Event",
			TextColor3 = COLORS.accent,
			TextSize = 14,
			LayoutOrder = 4,
			Visible = false,
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

	-- Tous les onglets restent visibles, sans barre qui défile : chaque bouton
	-- prend une part égale de la largeur. Sur PC, une seule rangée ; sur
	-- téléphone, deux rangées de 4 pour que le texte reste lisible
	-- (voir layoutTabs, appelée quand la taille de l'écran change).
	tabGrid = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(TAB_GAP, TAB_GAP),
		CellSize = UDim2.new(1 / #TABS, -TAB_GAP, 0, TAB_HEIGHT),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	tabBar = create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -74, 0, TAB_HEIGHT),
		Parent = panel,
	}, { tabGrid })
	tabButtons = {}
	for index, tabId in TABS do
		tabButtons[tabId] = button(T("tab." .. tabId), function()
			-- Onglet pas encore débloqué (débutant) : on explique quand il s'ouvre.
			local unlocked, rule = Onboarding.TabUnlocked(tabId, state.profile)
			if not unlocked then
				local needed = Onboarding.TAB_RULES[tabId]
				UIController.Notify(T("onboarding.lock." .. rule, {
					tab = T("tab." .. tabId),
					n = needed and needed.matches or 0,
				}), "info")
				return
			end
			UIController.OpenTab(tabId)
		end, {
			LayoutOrder = index,
			Size = UDim2.new(1 / #TABS, -TAB_GAP, 0, TAB_HEIGHT),
			TextSize = 16,
			Parent = tabBar,
		})
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

-- Fenêtre « Pendant ton absence… » (revenus hors ligne, cadeau, saison).
local function buildWelcomePopup()
	welcomePopup = create("Frame", {
		Name = "Welcome",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.85, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.background,
		Visible = false,
		ZIndex = 12,
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

function UIController.ShowWelcome(welcome)
	if not welcomePopup or type(welcome) ~= "table" then
		return
	end
	for _, child in welcomePopup:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function add(instance)
		order += 1
		instance.LayoutOrder = order
		instance.ZIndex = 13
		instance.Parent = welcomePopup
		return instance
	end
	local centered = { TextXAlignment = Enum.TextXAlignment.Center }
	add(label(T("welcome.title"), {
		Font = Enum.Font.GothamBold,
		TextSize = 26,
		TextColor3 = COLORS.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
	}))
	if welcome.offline then
		add(label(T("welcome.offline", {
			coins = formatCoins(welcome.offline.coins),
			time = formatDuration(welcome.offline.away or welcome.offline.seconds),
		}), centered))
		if (welcome.offline.away or 0) > (welcome.offline.seconds or 0) then
			add(label(T("welcome.offlineCap"), { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = COLORS.muted, TextSize = 16 }))
		end
	end
	if welcome.daily then
		add(label(T("welcome.daily", { day = welcome.daily.day, coins = welcome.daily.coins }), centered))
	end
	if welcome.season then
		add(label(T("welcome.season", { rank = welcome.season.rank, coins = formatCoins(welcome.season.reward) }), centered))
	end
	add(button(T("welcome.continue"), function()
		welcomePopup.Visible = false
	end, { Name = "WelcomeContinue" }))
	welcomePopup.Visible = true
end

-- Rangées d'onglets : avec l'interface réduite (téléphone), une seule rangée
-- de 8 donnerait des textes d'environ 8 px ; on passe alors à 2 rangées de 4.
function UIController.TabRows(scale: number): number
	return if scale < 0.95 then 2 else 1
end

local function layoutTabs(scale: number)
	if not tabBar then
		return
	end
	local rows = UIController.TabRows(scale)
	local perRow = math.ceil(#TABS / rows)
	local barHeight = rows * TAB_HEIGHT + (rows - 1) * TAB_GAP
	local cell = UDim2.new(1 / perRow, -TAB_GAP, 0, TAB_HEIGHT)
	tabGrid.CellSize = cell
	tabBar.Size = UDim2.new(1, -74, 0, barHeight)
	for _, tabButton in tabButtons do
		tabButton.Size = cell
	end
	content.Position = UDim2.fromOffset(10, 22 + barHeight)
	content.Size = UDim2.new(1, -20, 1, -(32 + barHeight))
end

-- Échelle de l'interface selon la taille de l'écran (mobile, tablette, PC).
local function setupScaling()
	local uiScale = create("UIScale", { Parent = gui })
	local camera = workspace.CurrentCamera
	local function update()
		local viewport = camera.ViewportSize
		local shortest = math.min(viewport.X, viewport.Y)
		uiScale.Scale = math.clamp(shortest / 720, 0.7, 1.2)
		layoutTabs(uiScale.Scale)
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
	buildWelcomePopup()
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

-- Étape du tutoriel en cours (id), ou nil.
local function tutorialStepId(profile): string?
	local tutorial = profile and profile.tutorial
	if not tutorial or tutorial.completed then
		return nil
	end
	local step = TutorialSteps[tutorial.step]
	return step and step.id
end

-- Onglets : texte, cadenas (pas encore débloqué) et onglet mis en avant
-- (doré) pour guider le débutant vers la prochaine action.
local function refreshTabs()
	local profile = state.profile
	local stepId = tutorialStepId(profile)
	local focus = Onboarding.FocusTab(profile, stepId)
	for tabId, tabButton in tabButtons do
		local unlocked = Onboarding.TabUnlocked(tabId, profile)
		tabButton.Text = (if unlocked then "" else "🔒 ") .. T("tab." .. tabId)
		tabButton.TextColor3 = if unlocked then COLORS.text else COLORS.muted
		tabButton.BackgroundColor3 = if tabId == currentTab
			then COLORS.accent
			elseif not unlocked then COLORS.disabled
			elseif tabId == focus then COLORS.gold
			else COLORS.card
		tabButton:SetAttribute("Locked", not unlocked)
		tabButton:SetAttribute("Focus", tabId == focus)
	end
	local menuButton = gui:FindFirstChild("MenuButton")
	if menuButton then
		local glow = stepId == "OpenMenu" and not panel.Visible
		menuButton.BackgroundColor3 = if glow then COLORS.gold else COLORS.accent
		menuButton:SetAttribute("Focus", glow)
	end
end

-- Annonce les onglets qui viennent de se débloquer (pas au premier profil).
local function announceUnlocks(profile)
	local now = {}
	for _, tabId in TABS do
		now[tabId] = Onboarding.TabUnlocked(tabId, profile)
	end
	if unlockedTabs then
		for _, tabId in TABS do
			if now[tabId] and not unlockedTabs[tabId] then
				UIController.Notify(T("onboarding.unlocked", { tab = T("tab." .. tabId) }), "success")
			end
		end
	end
	unlockedTabs = now
end

function UIController.OpenTab(tabId: string)
	currentTab = tabId
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
	refreshTabs()
	if profile then
		hud.ClubName.Text = profile.club.name or T("hud.myClub")
		hud.Division.Text = divisionLabel(profile.club.division)
			.. (if profile.temporary then " · " .. T("hud.testMode") else "")
		hud.Coins.Text = if profile.adminUnlimited then T("admin.infiniteCoins") else formatCoins(profile.coins)
		refreshCrestBadge(profile)
		UIController.RefreshEventHud()
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

-- Ligne du HUD : thème de la semaine, ou Coupe du week-end, avec compte à rebours.
function UIController.RefreshEventHud()
	local event = state.profile and state.profile.event
	local line = hud and hud:FindFirstChild("Event")
	if not line then
		return
	end
	if type(event) ~= "table" or type(event.theme) ~= "string" then
		line.Visible = false
		return
	end
	local endsIn = math.max(0, (state.eventEndsAt or 0) - os.clock())
	line.Visible = true
	line.Text = if event.weekend
		then T("event.hudCup", { event = T("event.theme." .. event.theme), time = formatDuration(endsIn) })
		else T("event.hud", { event = T("event.theme." .. event.theme), time = formatDuration(endsIn) })
end

function UIController.SetProfile(profile)
	if not profile then
		return
	end
	local event = type(profile.event) == "table" and profile.event or nil
	if event then
		state.eventEndsAt = os.clock() + (event.endsIn or 0)
		state.eventWeekendAt = os.clock() + (event.weekendIn or 0)
		-- Annonce d'un nouvel événement (arrivée ou lundi en pleine partie).
		if event.week ~= shownEventWeek then
			shownEventWeek = event.week
			UIController.Notify(T("event.announce", { event = T("event.theme." .. tostring(event.theme)) }), "info")
		end
	end
	state.profile = profile
	state.cooldownEndsAt = os.clock() + (profile.matchCooldown or 0)
	state.cupReadyAt = os.clock() + (if type(profile.cup) == "table" then profile.cup.nextIn or 0 else 0)
	announceUnlocks(profile)
	UIController.Refresh()
	local welcome = type(profile.daily) == "table" and profile.daily.welcome
	if type(welcome) == "table" and welcome.id ~= shownWelcome then
		shownWelcome = welcome.id
		UIController.ShowWelcome(welcome)
	end
end

function UIController.SetChallenges(challenges)
	state.challenges = challenges or { incoming = {}, outgoing = nil }
	if currentTab == "Matches" then
		UIController.Refresh()
	end
end

function UIController.SetTournament(tournament)
	if not tournament then
		return
	end
	local previous = state.tournament
	state.tournament = tournament
	state.tournamentEndsAt = os.clock() + (tournament.secondsLeft or 0)
	-- Annonce à l'ouverture des inscriptions (le serveur n'envoie pas de message).
	if tournament.phase == "registration" and (not previous or previous.id ~= tournament.id or previous.phase ~= "registration") then
		UIController.Notify(T("tournament.registrationOpen"), "info")
	end
	if currentTab == "Matches" then
		UIController.Refresh()
	end
end

function UIController.SetLeaderboard(leaderboard)
	if type(leaderboard) ~= "table" then
		return
	end
	state.leaderboard = leaderboard
	if currentTab == "Ranking" then
		UIController.Refresh()
	end
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
	-- Duel tactique (le joueur est toujours l'équipe à domicile d'un match normal).
	local duel = result.tactics
	if type(duel) == "table" and Tactics.IsValid(duel.home) and Tactics.IsValid(duel.away) and duel.edge ~= 0 then
		local params = { mine = T("tactic." .. duel.home), theirs = T("tactic." .. duel.away) }
		add(label(T(if duel.edge > 0 then "result.tacticWin" else "result.tacticLose", params), {
			Name = "TacticResult",
			TextSize = 16,
			TextColor3 = if duel.edge > 0 then COLORS.accent else COLORS.error,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	for _, event in result.events do
		local team = if event.side == "home" then result.homeName else result.awayName
		add(label(("%d' ⚽ %s (%s)"):format(event.minute, event.scorer, team), {
			TextSize = 16,
			TextColor3 = COLORS.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	if result.mode == "cup" then
		if result.penalties then
			add(label(T("cup.result.penalties"), { TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Center }))
		end
		if result.giantKill then
			add(label(T("cup.result.giantKill"), {
				Font = Enum.Font.GothamBold,
				TextColor3 = COLORS.gold,
				TextXAlignment = Enum.TextXAlignment.Center,
			}))
		end
		local key = if result.champion
			then "cup.result.champion"
			elseif result.outcome == "Win" then "cup.result.qualified"
			else "cup.result.eliminated"
		add(label(T(key, { coins = formatCoins(result.coins or 0) }), {
			Name = "CupResult",
			Font = Enum.Font.GothamBold,
			TextColor3 = if result.outcome == "Win" then COLORS.gold else COLORS.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
		add(button(T("result.continue"), function()
			resultPopup.Visible = false
		end))
		resultPopup.Visible = true
		return
	end
	if result.mode == "challenge" then
		local change = result.coinsChange or 0
		add(label(
			if change > 0
				then T("challenge.resultWon", { coins = formatCoins(change) })
				elseif change < 0 then T("challenge.resultLost", { coins = formatCoins(-change) })
				elseif result.friendly then T("friends.friendlyResult")
				else T("challenge.resultDraw"),
			{ TextColor3 = COLORS.gold, TextXAlignment = Enum.TextXAlignment.Center }
		))
		if (result.friendlyBonus or 0) > 0 then
			add(label(T("friends.friendlyBonus", { coins = formatCoins(result.friendlyBonus) }), {
				TextColor3 = COLORS.accent,
				TextXAlignment = Enum.TextXAlignment.Center,
			}))
		end
		add(button(T("result.continue"), function()
			resultPopup.Visible = false
		end))
		resultPopup.Visible = true
		return
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
	if (rewards.event or 0) > 0 or (result.eventPoints or 0) > 0 then
		local theme = state.profile and type(state.profile.event) == "table" and state.profile.event.theme
		add(label(T("result.event", {
			event = T("event.theme." .. (theme or "tickets")),
			coins = formatCoins(rewards.event or 0),
			points = result.eventPoints or 0,
		}), {
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	if (rewards.contracts or 0) > 0 then
		add(label(T("result.sponsorContracts", { coins = formatCoins(rewards.contracts) }), {
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	for _, bonus in result.sponsorBonuses or {} do
		add(label(T("result.sponsorBonus", { brand = bonus.brand, coins = formatCoins(bonus.coins) }), {
			Font = Enum.Font.GothamBold,
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
	for _, brand in result.sponsorsEnded or {} do
		add(label(T("result.sponsorEnded", { brand = brand }), centered))
	end
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
		local ticking = state.cooldownEndsAt > os.clock() - 1
			or state.tournamentEndsAt > os.clock() - 1
			or state.cupReadyAt > os.clock() - 1
		if panel and panel.Visible and currentTab == "Matches" and ticking then
			UIController.Refresh()
		end
		-- Compte à rebours de l'événement de la semaine dans le HUD.
		if hud then
			UIController.RefreshEventHud()
		end
	end
end)

return UIController
