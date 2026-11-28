--[[
	CityService
	Centre-ville : concessionnaire (acheter, choisir, peindre sa voiture),
	voiture à conduire, banque (prêt et placement), hôtel du club (mise au vert),
	déplacement rapide entre la ville et son club.

	Le client envoie seulement : RequestCity(action, ...) avec
	  "buyCar", carId        acheter une voiture (prix et division lus dans City.lua)
	  "selectCar", carId     choisir la voiture à sortir (déjà achetée)
	  "paint", paintId       peinture de la voiture
	  "spawnCar"             sortir sa voiture à côté de soi ("despawnCar" pour la ranger)
	  "loan" / "repay"       emprunter le maximum de sa division / rembourser ce qu'on peut
	  "invest" / "withdraw"  placer un quart du plafond / tout retirer (intérêts après 4 h)
	  "hotel"                mise au vert : toute l'équipe retrouve son énergie
	  "goto", "city"|"club"  aller en ville / revenir à son club
	Le serveur vérifie tout et débite une seule fois.

	Voiture : un Model par joueur dans Workspace.PlayerCars, physique simple et
	robuste (LinearVelocity dans le plan + AlignOrientation). Le conducteur reçoit
	la propriété réseau : c'est son client (CarController) qui pilote, comme
	dans tous les jeux de voiture Roblox. Seul le propriétaire peut conduire.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Campus = require(Shared.Campus)
local CarModels = require(Shared.CarModels)
local City = require(Shared.City)
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local PlayerConfig = require(Shared.PlayerConfig)
local ClubIdentity = require(Shared.ClubIdentity)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ClubService = require(script.Parent.ClubService)

local CityService = {}

local cars = {} -- [Player] = { model, seat, chassis, idleSince }
local lastSpawn = setmetatable({}, { __mode = "k" }) -- [Player] = os.clock()

local function T(player, key, params)
	return Locale.TP(player, key, params)
end

local function cityOf(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, nil
	end
	data.city = City.Sanitize(data.city)
	return data, data.city
end

-- « 12 000 FC » : montants lisibles dans les messages.
local function fc(amount: number): string
	local text = string.format("%.0f", math.floor(amount))
	return (text:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")) .. " FC"
end

local function carLabel(player: Player, id: string): string
	return T(player, "city.car." .. id)
end

local function notEnough(player: Player)
	return false, T(player, "error.notEnoughCoins", { currency = Config.CURRENCY_NAME })
end

-- Couleur principale du club (identité choisie, palette achetée ou couleurs de l'emplacement).
local function clubColor(player: Player, data): Color3
	return ClubIdentity.Resolve(data, ClubService.GetSlot(player) or 1).primary
end

-- Couleur de peinture : « club » = couleur principale du club.
local function paintColor(player: Player, data): Color3
	local paint = City.GetPaint(data.city.paint)
	if paint and paint.color then
		return paint.color
	end
	return clubColor(player, data)
end

--------------------------------------------------------------------------------
-- Voiture à conduire
--------------------------------------------------------------------------------

local function carsFolder(): Instance
	local folder = Workspace:FindFirstChild("PlayerCars")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlayerCars"
		folder.Parent = Workspace
	end
	return folder
end

function CityService.DespawnCar(player: Player)
	local entry = cars[player]
	cars[player] = nil
	if entry and entry.model then
		entry.model:Destroy()
	end
end

function CityService.GetCar(player: Player)
	local entry = cars[player]
	return entry and entry.model or nil
end

local function weld(chassis: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = part
	w.Parent = chassis
end

local function setOwner(part: BasePart, owner: Player?)
	pcall(function()
		part:SetNetworkOwner(owner)
	end)
end

-- Rend le modèle conduisible : roues porteuses invisibles, siège, contraintes.
local function makeDrivable(player: Player, model: Model, def)
	local chassis = model.PrimaryPart :: BasePart
	local dims = CarModels.Dimensions(def.shape)
	local base = chassis.CFrame * CFrame.new(0, -(CarModels.WHEEL / 2 + 0.1 + dims.body / 2), 0)
	local axle = dims.length / 2 - 1.8
	-- Deux essieux ronds et invisibles : ils roulent sur les trottoirs sans accrocher.
	for _, sz in { -1, 1 } do
		local a = Instance.new("Part")
		a.Name = "Axle"
		a.Shape = Enum.PartType.Cylinder
		a.Size = Vector3.new(dims.width - 0.4, CarModels.WHEEL, CarModels.WHEEL)
		a.CFrame = base * CFrame.new(0, CarModels.WHEEL / 2, sz * axle)
		a.Transparency = 1
		a.CanCollide = true
		a.Anchored = true
		if PhysicalProperties then
			a.CustomPhysicalProperties = PhysicalProperties.new(0.8, 0.05, 0, 100, 1)
		end
		a.Parent = model
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.6, 2)
	seat.CFrame = base * CFrame.new(-dims.width / 4, CarModels.WHEEL / 2 + 0.4 + dims.body * 0.6, dims.cabin[3])
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Anchored = true
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	seat.Parent = model

	local attachment = Instance.new("Attachment")
	attachment.Name = "Drive"
	attachment.Parent = chassis
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DriveVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.PlaneVelocity = Vector2.new(0, 0)
	velocity.MaxForce = 80000
	velocity.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name = "DriveAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e7
	align.Responsiveness = 30
	local look = chassis.CFrame.LookVector
	align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z).Unit)
	align.Parent = chassis

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d ~= chassis then
				weld(chassis, d)
				d.Massless = d.Name ~= "Axle"
			end
			d.Anchored = false
		end
	end
	chassis.CanCollide = false

	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CarId", def.id)
	model:SetAttribute("MaxSpeed", def.speed)
	model:SetAttribute("Accel", def.accel)
	model:SetAttribute("Turn", def.turn)
	return seat, chassis, velocity, align
end

local function onOccupantChanged(player: Player, entry)
	local seat, chassis = entry.seat, entry.chassis
	local humanoid = seat.Occupant
	if humanoid then
		local character = humanoid.Parent
		if character ~= player.Character then
			-- Seul le propriétaire conduit sa voiture.
			humanoid.Sit = false
			humanoid.Jump = true
			return
		end
		entry.idleSince = nil
		setOwner(chassis, player)
	else
		entry.idleSince = os.clock()
		setOwner(chassis, nil)
		-- Voiture garée : on la freine et on garde son cap actuel.
		entry.velocity.PlaneVelocity = Vector2.new(0, 0)
		local look = chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			entry.align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		end
	end
end

function CityService.TrySpawnCar(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < City.CAR_SPAWN_COOLDOWN then
		return false, T(player, "city.error.tooFast")
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, T(player, "city.error.noCharacter")
	end
	local def = City.GetCar(city.car) or City.GetCar(City.DEFAULT_CAR)
	lastSpawn[player] = now
	CityService.DespawnCar(player)

	-- À droite du joueur, posée au sol, dans le même sens que lui.
	local rootCF: CFrame = root.CFrame
	local look = rootCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local groundY = math.max(0.2, rootCF.Position.Y - 3)
	local pos = Vector3.new(rootCF.Position.X, groundY + 0.3, rootCF.Position.Z) + right * 9
	local cf = CFrame.lookAt(pos, pos + flat)

	local model = CarModels.Build(def.shape, paintColor(player, data), cf, "Car_" .. player.UserId)
	local seat, chassis, velocity, align = makeDrivable(player, model, def)
	model.Parent = carsFolder()
	setOwner(chassis, nil)
	local entry = { model = model, seat = seat, chassis = chassis, velocity = velocity, align = align, idleSince = os.clock() }
	cars[player] = entry
	local signal = seat:GetPropertyChangedSignal("Occupant")
	if signal then
		signal:Connect(function()
			if cars[player] == entry then
				onOccupantChanged(player, entry)
			end
		end)
	end
	return true, T(player, "city.carSpawned", { car = carLabel(player, def.id) })
end

-- Repeint la voiture déjà sortie (sans la reconstruire).
local function repaint(player: Player, data)
	local model = CityService.GetCar(player)
	if not model then
		return
	end
	local color = paintColor(player, data)
	for _, name in { "Body", "Roof" } do
		local part = model:FindFirstChild(name)
		if part then
			part.Color = color
		end
	end
end

--------------------------------------------------------------------------------
-- Concessionnaire
--------------------------------------------------------------------------------

function CityService.TryBuyCar(player: Player, id): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local def = City.GetCar(id)
	if not def then
		return false, T(player, "city.error.unknownCar")
	end
	if city.cars[def.id] then
		return false, T(player, "city.error.alreadyOwned")
	end
	if not Campus.DivisionAllows(data.club.division, def.division) then
		return false, T(player, "city.error.division", { division = def.division })
	end
	if not EconomyService.TrySpend(player, def.price, "city:car:" .. def.id) then
		return notEnough(player)
	end
	city.cars[def.id] = true
	city.car = def.id
	return true, T(player, "city.carBought", { car = carLabel(player, def.id) })
end

function CityService.TrySelectCar(player: Player, id): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local def = City.GetCar(id)
	if not def or not city.cars[def.id] then
		return false, T(player, "city.error.notOwned")
	end
	city.car = def.id
	return true, T(player, "city.carSelected", { car = carLabel(player, def.id) })
end

function CityService.TryPaint(player: Player, id): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	if not City.GetPaint(id) then
		return false, T(player, "city.error.unknownPaint")
	end
	city.paint = id
	repaint(player, data)
	return true, T(player, "city.painted", { paint = T(player, "city.paint." .. id) })
end

--------------------------------------------------------------------------------
-- Banque
--------------------------------------------------------------------------------

function CityService.TryLoan(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	if city.bank.loan > 0 then
		return false, T(player, "city.error.loanOpen")
	end
	local amount = City.LoanMax(data.club.division)
	local due = City.LoanDue(amount)
	city.bank.loan = due
	EconomyService.Add(player, amount, "city:loan")
	return true, T(player, "city.loanTaken", { amount = fc(amount), due = fc(due) })
end

function CityService.TryRepay(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local loan = city.bank.loan
	if loan <= 0 then
		return false, T(player, "city.error.noLoan")
	end
	local amount = math.min(loan, math.floor(data.coins))
	if amount <= 0 or not EconomyService.TrySpend(player, amount, "city:repay") then
		return notEnough(player)
	end
	city.bank.loan = loan - amount
	if city.bank.loan <= 0 then
		return true, T(player, "city.loanCleared")
	end
	return true, T(player, "city.loanRepaid", { amount = fc(amount), left = fc(city.bank.loan) })
end

-- Après un match : une part du gain rembourse le prêt en cours. Renvoie la somme prélevée.
function CityService.RepayFromMatch(player: Player, data, reward: number): number
	if type(data) ~= "table" then
		return 0
	end
	data.city = City.Sanitize(data.city)
	local loan = data.city.bank.loan
	if loan <= 0 or type(reward) ~= "number" or reward <= 0 then
		return 0
	end
	local cut = math.min(loan, math.floor(reward * City.LOAN_REPAY_SHARE))
	if cut <= 0 or not EconomyService.TrySpend(player, cut, "city:repay:match") then
		return 0
	end
	data.city.bank.loan = loan - cut
	if data.city.bank.loan <= 0 then
		Net.FireClient("Notify", player, T(player, "city.loanCleared"), "success")
	end
	return cut
end

function CityService.TryInvest(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local cap = City.InvestMax(data.club.division)
	local room = cap - city.bank.invest
	if room <= 0 then
		return false, T(player, "city.error.investFull", { max = fc(cap) })
	end
	local amount = math.min(room, math.ceil(cap / City.INVEST_STEPS))
	if not EconomyService.TrySpend(player, amount, "city:invest") then
		return notEnough(player)
	end
	city.bank.invest += amount
	city.bank.investAt = os.time()
	return true, T(player, "city.invested", { amount = fc(amount), total = fc(city.bank.invest) })
end

function CityService.TryWithdraw(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	if city.bank.invest <= 0 then
		return false, T(player, "city.error.noInvest")
	end
	local value = City.InvestValue(city.bank, os.time())
	local interest = value - city.bank.invest
	city.bank.invest = 0
	city.bank.investAt = 0
	EconomyService.Add(player, value, "city:withdraw")
	if interest > 0 then
		return true, T(player, "city.withdrawnInterest", { amount = fc(value), interest = fc(interest) })
	end
	return true, T(player, "city.withdrawn", { amount = fc(value) })
end

--------------------------------------------------------------------------------
-- Hôtel du club
--------------------------------------------------------------------------------

function CityService.TryHotel(player: Player): (boolean, string)
	local data, city = cityOf(player)
	if not data then
		return false, T(player, "error.profileNotLoaded")
	end
	local now = os.time()
	local wait = City.HOTEL_COOLDOWN - (now - city.hotelAt)
	if city.hotelAt > 0 and wait > 0 then
		return false, T(player, "city.error.hotelCooldown", { minutes = math.ceil(wait / 60) })
	end
	local tired = false
	for _, footballer in data.squad or {} do
		if (footballer.energy or 0) < PlayerConfig.MAX_ENERGY then
			tired = true
		end
	end
	if not tired then
		return false, T(player, "city.error.hotelRested")
	end
	local price = City.HotelPrice(data.club.division)
	if not EconomyService.TrySpend(player, price, "city:hotel") then
		return notEnough(player)
	end
	for _, footballer in data.squad do
		footballer.energy = PlayerConfig.MAX_ENERGY
	end
	city.hotelAt = now
	return true, T(player, "city.hotelDone")
end

--------------------------------------------------------------------------------
-- Déplacements rapides
--------------------------------------------------------------------------------

function CityService.TryGoto(player: Player, target): (boolean, string)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, T(player, "city.error.noCharacter")
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid and humanoid.SeatPart then
		return false, T(player, "city.error.driving")
	end
	if target == "city" then
		character:PivotTo(CFrame.new(City.ToWorld(City.ARRIVAL)) * CFrame.Angles(0, math.rad(-90), 0))
		return true, T(player, "city.arrived")
	elseif target == "club" then
		ClubService.TeleportToPlot(player)
		return true, T(player, "city.backHome")
	end
	return false, T(player, "city.error.unknownAction")
end

--------------------------------------------------------------------------------
-- Point d'entrée, instantané, boucle d'entretien
--------------------------------------------------------------------------------

local ACTIONS = {
	buyCar = CityService.TryBuyCar,
	selectCar = CityService.TrySelectCar,
	paint = CityService.TryPaint,
	spawnCar = CityService.TrySpawnCar,
	despawnCar = function(player)
		if not cars[player] then
			return false, T(player, "city.error.noCar")
		end
		CityService.DespawnCar(player)
		return true, T(player, "city.carParked")
	end,
	loan = CityService.TryLoan,
	repay = CityService.TryRepay,
	invest = CityService.TryInvest,
	withdraw = CityService.TryWithdraw,
	hotel = CityService.TryHotel,
	["goto"] = CityService.TryGoto,
}

function CityService.Handle(player: Player, action, ...): (boolean, string)
	local fn = type(action) == "string" and ACTIONS[action]
	if not fn then
		return false, T(player, "city.error.unknownAction")
	end
	return fn(player, ...)
end

function CityService.Snapshot(player: Player, data)
	local city = City.Sanitize(data.city)
	local now = os.time()
	local division = data.club and data.club.division
	local hotelWait = if city.hotelAt > 0 then math.max(0, City.HOTEL_COOLDOWN - (now - city.hotelAt)) else 0
	local investWait = if city.bank.invest > 0 then math.max(0, City.INVEST_SECONDS - (now - city.bank.investAt)) else 0
	local club = clubColor(player, data)
	return {
		clubColor = { club.R, club.G, club.B }, -- pastille « couleur du club » du concessionnaire
		cars = table.clone(city.cars),
		car = city.car,
		paint = city.paint,
		loan = city.bank.loan,
		loanMax = City.LoanMax(division),
		invest = city.bank.invest,
		investValue = City.InvestValue(city.bank, now),
		investMax = City.InvestMax(division),
		investReadyIn = investWait,
		hotelPrice = City.HotelPrice(division),
		hotelReadyIn = hotelWait,
		carOut = cars[player] ~= nil,
	}
end

function CityService.OnPlayerLeaving(player: Player)
	CityService.DespawnCar(player)
	lastSpawn[player] = nil
end

-- Voitures abandonnées (trop longtemps sans conducteur) ou tombées : rangées.
function CityService.Cleanup()
	local now = os.clock()
	for player, entry in cars do
		local model = entry.model
		local fell = entry.chassis and entry.chassis.Parent and entry.chassis.CFrame.Position.Y < -40
		local idle = entry.idleSince and now - entry.idleSince > City.CAR_IDLE_DESPAWN
		if not model.Parent or fell or idle or player.Parent ~= Players then
			CityService.DespawnCar(player)
			if player.Parent == Players then
				PlayerDataService.MarkChanged(player)
			end
		end
	end
end

function CityService.Init()
	PlayerDataService.AddSnapshotField("city", CityService.Snapshot)
	Net.Handle("RequestCity", function(player, action, a)
		local ok, message = CityService.Handle(player, action, a)
		Net.FireClient("Notify", player, message, if ok then "success" else "error")
		if ok then
			-- Même sortir sa voiture change l'instantané (carOut) : on le renvoie.
			PlayerDataService.MarkChanged(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(10)
			local ok, err = pcall(CityService.Cleanup)
			if not ok then
				warn("[City] " .. tostring(err))
			end
		end
	end)
end

return CityService
