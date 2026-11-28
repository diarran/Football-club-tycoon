--[[
	CityController
	Interface du centre-ville côté client :
	  - deux boutons sous « Club » : « Ma voiture » (sortir / ranger sa voiture)
	    et « Ville » / « Mon club » (aller en ville ou revenir au club) ;
	  - les fenêtres du concessionnaire, de la banque et de l'hôtel, ouvertes
	    par les ProximityPrompt des guichets (Part « Counter » du centre-ville).
	Le client n'envoie que des demandes (RequestCity) : prix, soldes et règles
	sont vérifiés par le serveur (CityService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local City = require(Shared.City)
local Divisions = require(Shared.Divisions)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local CityController = {}

local COLORS = {
	panel = Color3.fromRGB(20, 21, 26),
	card = Color3.fromRGB(36, 38, 46),
	gold = Color3.fromRGB(212, 175, 55),
	goldDark = Color3.fromRGB(150, 120, 34),
	text = Color3.fromRGB(240, 244, 250),
	muted = Color3.fromRGB(160, 166, 180),
	disabled = Color3.fromRGB(80, 84, 96),
	accent = Color3.fromRGB(46, 170, 90),
}

local gui, popup, body, title, carButton, cityButton
local current = nil -- "dealer", "bank", "hotel" ou nil
local profile = nil
local inCity = false

local function T(key: string, params: { [string]: any }?): string
	return Locale.T(Locale.ForPlayer(player), key, params)
end

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

local function coins(amount: number): string
	local text = string.format("%.0f", math.floor(amount or 0))
	return text:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "") .. " FC"
end

local function minutes(seconds: number): string
	local m = math.max(1, math.ceil((seconds or 0) / 60))
	if m >= 60 then
		return T("time.hm", { h = m // 60, m = m % 60 })
	end
	return T("time.m", { m = m })
end

local function label(text: string, props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
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
		BackgroundColor3 = COLORS.gold,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = COLORS.panel,
		TextSize = 17,
		Size = UDim2.new(0, 150, 0, 44),
	}
	for key, value in props or {} do
		base[key] = value
	end
	base.TextScaled = true
	local instance = create("TextButton", base, {
		corner(8),
		create("UITextSizeConstraint", { MaxTextSize = base.TextSize, MinTextSize = 10 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	instance.Activated:Connect(onClick)
	return instance
end

local function card(children)
	return create("Frame", {
		BackgroundColor3 = COLORS.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		corner(8),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		table.unpack(children),
	})
end

local function row(children)
	return create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		table.unpack(children),
	})
end

local function request(action: string, arg: any?)
	Net.Get("RequestCity"):FireServer(action, arg)
end

local function division(): string
	return profile and profile.club and profile.club.division or "D7"
end

local function divisionAllows(required: string): boolean
	local mine, need = Divisions.Get(division()), Divisions.Get(required)
	return mine ~= nil and need ~= nil and mine.tier <= need.tier
end

local function divisionLabel(id: string): string
	local d = Divisions.Get(id)
	return if d then T("division.label", { tier = d.tier }) else id
end

--------------------------------------------------------------------------------
-- Contenu des fenêtres
--------------------------------------------------------------------------------

local function add(instance, order: number)
	instance.LayoutOrder = order
	instance.Parent = body
	return instance
end

local function renderDealer(city)
	add(label(T("city.dealer.intro"), { TextColor3 = COLORS.muted, TextSize = 15 }), 1)
	for i, car in City.CARS do
		local owned = city.cars and city.cars[car.id]
		local selected = city.car == car.id
		local details = T("city.carStats", { speed = car.speed, price = coins(car.price) })
		local action
		if selected then
			action = button(T("city.selected"), function() end, { BackgroundColor3 = COLORS.disabled, TextColor3 = COLORS.text, AutoButtonColor = false })
		elseif owned then
			action = button(T("city.select"), function()
				request("selectCar", car.id)
			end)
		elseif divisionAllows(car.division) then
			action = button(T("city.buy"), function()
				request("buyCar", car.id)
			end)
		else
			action = button(divisionLabel(car.division), function() end, { BackgroundColor3 = COLORS.disabled, TextColor3 = COLORS.text, AutoButtonColor = false })
		end
		action.Name = "Car_" .. car.id
		add(card({
			label(T("city.car." .. car.id), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, LayoutOrder = 1 }),
			label(details, { TextColor3 = COLORS.muted, TextSize = 15, LayoutOrder = 2 }),
			row({ action }),
		}), 10 + i)
	end
	-- Peintures : petits boutons de couleur.
	local swatches = {}
	for i, paint in City.PAINTS do
		local club = type(city.clubColor) == "table" and city.clubColor
		local color = paint.color or (if club then Color3.new(club[1] or 0, club[2] or 0, club[3] or 0) else COLORS.gold)
		local chosen = city.paint == paint.id
		local b = button(if chosen then "✓" else "", function()
			request("paint", paint.id)
		end, {
			Name = "Paint_" .. paint.id,
			BackgroundColor3 = color,
			Size = UDim2.new(0, 40, 0, 40),
			TextColor3 = if paint.id == "white" or paint.id == "gold" or paint.id == "silver" then COLORS.panel else COLORS.text,
			LayoutOrder = i,
		})
		table.insert(swatches, b)
	end
	add(card({
		label(T("city.paintTitle"), { Font = Enum.Font.GothamBold, LayoutOrder = 1 }),
		label(T("city.paint." .. (city.paint or "club")), { TextColor3 = COLORS.muted, TextSize = 15, LayoutOrder = 2 }),
		row(swatches),
	}), 30)
end

local function renderBank(city)
	add(label(T("city.bank.intro"), { TextColor3 = COLORS.muted, TextSize = 15 }), 1)
	local loanCard
	if (city.loan or 0) > 0 then
		loanCard = card({
			label(T("city.loanTitle"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, LayoutOrder = 1 }),
			label(T("city.loanOpen", { due = coins(city.loan) }), { LayoutOrder = 2 }),
			label(T("city.loanAuto", { share = math.floor(City.LOAN_REPAY_SHARE * 100) }), { TextColor3 = COLORS.muted, TextSize = 15, LayoutOrder = 3 }),
			row({ button(T("city.repay"), function()
				request("repay")
			end, { Name = "Repay" }) }),
		})
	else
		loanCard = card({
			label(T("city.loanTitle"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, LayoutOrder = 1 }),
			label(T("city.loanOffer", { amount = coins(city.loanMax or 0), due = coins(City.LoanDue(city.loanMax or 0)) }), { LayoutOrder = 2 }),
			label(T("city.loanAuto", { share = math.floor(City.LOAN_REPAY_SHARE * 100) }), { TextColor3 = COLORS.muted, TextSize = 15, LayoutOrder = 3 }),
			row({ button(T("city.borrow"), function()
				request("loan")
			end, { Name = "Borrow" }) }),
		})
	end
	add(loanCard, 10)

	local investLines = {
		label(T("city.investTitle"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, LayoutOrder = 1 }),
		label(T("city.investRule", { rate = math.floor(City.INVEST_RATE * 100), hours = City.INVEST_SECONDS // 3600, max = coins(city.investMax or 0) }), {
			TextColor3 = COLORS.muted,
			TextSize = 15,
			LayoutOrder = 2,
		}),
	}
	if (city.invest or 0) > 0 then
		local status = if (city.investReadyIn or 0) > 0
			then T("city.investWaiting", { amount = coins(city.invest), time = minutes(city.investReadyIn) })
			else T("city.investReady", { amount = coins(city.investValue or city.invest) })
		table.insert(investLines, label(status, { LayoutOrder = 3 }))
	end
	local buttons = {
		button(T("city.invest"), function()
			request("invest")
		end, { Name = "Invest", LayoutOrder = 1 }),
	}
	if (city.invest or 0) > 0 then
		table.insert(buttons, button(T("city.withdraw"), function()
			request("withdraw")
		end, { Name = "Withdraw", LayoutOrder = 2, BackgroundColor3 = COLORS.accent, TextColor3 = COLORS.text }))
	end
	table.insert(investLines, row(buttons))
	add(card(investLines), 20)
end

local function renderHotel(city)
	add(label(T("city.hotel.intro"), { TextColor3 = COLORS.muted, TextSize = 15 }), 1)
	local lines = {
		label(T("city.hotelTitle"), { Font = Enum.Font.GothamBold, TextColor3 = COLORS.gold, LayoutOrder = 1 }),
		label(T("city.hotelRule", { price = coins(city.hotelPrice or 0) }), { LayoutOrder = 2 }),
	}
	if (city.hotelReadyIn or 0) > 0 then
		table.insert(lines, label(T("city.hotelWait", { time = minutes(city.hotelReadyIn) }), { TextColor3 = COLORS.muted, LayoutOrder = 3 }))
	else
		table.insert(lines, row({ button(T("city.book"), function()
			request("hotel")
		end, { Name = "Book" }) }))
	end
	add(card(lines), 10)
end

local RENDERERS = { dealer = renderDealer, bank = renderBank, hotel = renderHotel }

function CityController.Refresh()
	if carButton then
		local out = profile and profile.city and profile.city.carOut
		carButton.Text = if out then T("city.hud.park") else T("city.hud.car")
	end
	if cityButton then
		cityButton.Text = if inCity then T("city.hud.club") else T("city.hud.city")
	end
	if not popup or not popup.Visible or not current then
		return
	end
	title.Text = T("city." .. current .. ".title")
	for _, child in body:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	local city = profile and profile.city
	if type(city) ~= "table" then
		add(label(T("hud.loading")), 1)
		return
	end
	RENDERERS[current](city)
end

function CityController.Open(kind: string)
	if not RENDERERS[kind] or not popup then
		return
	end
	current = kind
	popup.Visible = true
	CityController.Refresh()
end

function CityController.Close()
	current = nil
	if popup then
		popup.Visible = false
	end
end

function CityController.IsOpen(): (boolean, string?)
	return popup ~= nil and popup.Visible, current
end

function CityController.SetProfile(newProfile)
	if type(newProfile) ~= "table" then
		return
	end
	profile = newProfile
	CityController.Refresh()
end

-- Le personnage est-il dans le centre-ville ? (bouton « Ville » / « Mon club »)
function CityController.UpdatePosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local now = root ~= nil and City.IsInside(root.CFrame.Position, 20)
	if now ~= inCity then
		inCity = now
		CityController.Refresh()
	end
end

local function buildHud(parent: Instance)
	carButton = button(T("city.hud.car"), function()
		local out = profile and profile.city and profile.city.carOut
		request(if out then "despawnCar" else "spawnCar")
	end, {
		Name = "CarButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 64),
		Size = UDim2.fromOffset(110, 46),
		BackgroundColor3 = COLORS.panel,
		TextColor3 = COLORS.gold,
		Parent = parent,
	})
	cityButton = button(T("city.hud.city"), function()
		request("goto", if inCity then "club" else "city")
	end, {
		Name = "CityButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 116),
		Size = UDim2.fromOffset(110, 46),
		BackgroundColor3 = COLORS.panel,
		TextColor3 = COLORS.gold,
		Parent = parent,
	})
end

local function buildPopup(parent: Instance)
	popup = create("Frame", {
		Name = "CityPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.8),
		BackgroundColor3 = COLORS.panel,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, {
		corner(14),
		create("UISizeConstraint", { MaxSize = Vector2.new(520, 520) }),
		create("UIStroke", { Color = COLORS.gold, Thickness = 2 }),
	})
	title = label("", {
		Name = "Title",
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.gold,
		TextSize = 22,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -80, 0, 34),
		AutomaticSize = Enum.AutomaticSize.None,
		TextScaled = true,
		Parent = popup,
	})
	button("X", CityController.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = COLORS.card,
		TextColor3 = COLORS.text,
		Parent = popup,
	})
	body = create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 58),
		Size = UDim2.new(1, -20, 1, -68),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = popup,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

-- Guichets du centre-ville : le ProximityPrompt ouvre la bonne fenêtre.
local function hookPrompts()
	local ok, service = pcall(function()
		return game:GetService("ProximityPromptService")
	end)
	if not ok or not service or not service.PromptTriggered then
		return
	end
	service.PromptTriggered:Connect(function(prompt)
		local kind = prompt:GetAttribute("CityCounter")
		if type(kind) == "string" then
			CityController.Open(kind)
		end
	end)
end

function CityController.Init(parent: Instance)
	gui = parent
	buildHud(gui)
	buildPopup(gui)
	hookPrompts()
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(1)
			pcall(CityController.UpdatePosition)
		end
	end)
end

return CityController
