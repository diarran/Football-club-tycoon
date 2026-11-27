-- Centre-ville : décor 3D (boulevards, feux, rond-point, bâtiments), voitures
-- achetées et conduites, banque (prêt, placement), hôtel (mise au vert),
-- déplacements rapides, circulation des PNJ et fenêtres côté client.
local S = H.boot(MODULES)
local City = mock.run(MODULES.City)
local CityService = mock.run(MODULES.CityService)
local PlayerConfig = mock.run(MODULES.PlayerConfig)

local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)

local function request(player, ...)
	H.advance(City.CAR_SPAWN_COOLDOWN + 1)
	H.fire(player, "RequestCity", ...)
	local message, kind = H.lastNotify(player)
	return kind == "success", message
end

local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function count(root, predicate): number
	local n = 0
	for _, d in root:GetDescendants() do
		if predicate(d) then
			n += 1
		end
	end
	return n
end

-- Personnage minimal (HumanoidRootPart + Humanoid) posé à `pos`.
local function giveCharacter(player, pos)
	local character = Instance.new("Model")
	character.Name = player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(pos)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Parent = character
	character.PivotTo = function(self, cf)
		self._pivot = cf
		root.CFrame = cf
	end
	character.Parent = workspace
	player.Character = character
	return character, root, humanoid
end

local city = workspace:FindFirstChild("City")

H.test("le centre-ville est construit à l'est du quartier, dans le budget du téléphone", function()
	H.ok(city, "Model City dans le Workspace")
	H.ok(City.ORIGIN.X - City.SIZE.X / 2 >= 449, "il commence au bord est du quartier")
	local parts = count(city, function(d)
		return d:IsA("BasePart")
	end)
	local details = count(city, function(d)
		return d:IsA("BasePart") and d:GetAttribute("Detail") == true
	end)
	H.ok(parts > 600 and parts < 1600, "Parts du centre-ville : " .. parts)
	H.ok(details > parts * 0.3, "beaucoup de petites pièces masquables sur téléphone : " .. details)
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			H.ok(d.Anchored, "Part ancrée : " .. d.Name)
		end
	end
end)

H.test("boulevards, rond-point au ballon géant, feux tricolores et passages piétons", function()
	H.ok(find(city, "GiantBall"), "ballon géant du rond-point")
	H.ok(find(city, "Roundabout"), "anneau du rond-point")
	local lights = count(city, function(d)
		return d.Name == "TrafficLight"
	end)
	H.eq(lights, 8, "4 feux à chacun des 2 carrefours")
	local signals = count(city, function(d)
		return d:IsA("BasePart") and d:GetAttribute("SignalColor") ~= nil
	end)
	H.eq(signals, 24, "3 lampes par feu")
	local crosswalks = count(city, function(d)
		return d.Name == "Crosswalk"
	end)
	H.ok(crosswalks >= 12, "passages piétons : " .. crosswalks)
	H.ok(count(city, function(d)
		return d.Name == "Road"
	end) >= 8, "chaussées")
end)

H.test("concessionnaire, hôtel, banque, cafés et tours de pub, avec leurs guichets traduits", function()
	for _, name in { "Dealer", "Hotel", "Bank" } do
		H.ok(find(city, name), name)
	end
	H.ok(count(city, function(d)
		return d.Name == "Shop"
	end) >= 6, "cafés et restaurants")
	H.ok(count(city, function(d)
		return d.Name == "AdBoard"
	end) >= 12, "panneaux publicitaires des tours")
	H.eq(count(city, function(d)
		return d.Name == "DisplayCar"
	end), #City.CARS + 1, "toutes les voitures en vitrine + celle du voiturier de l'hôtel")
	local kinds = {}
	for _, d in city:GetDescendants() do
		if d.Name == "CityPrompt" then
			kinds[d:GetAttribute("CityCounter")] = true
			H.ok(type(d:GetAttribute("TextKey")) == "string", "texte du guichet traduit")
			H.eq(d.HoldDuration, 0, "un simple appui suffit")
		end
	end
	H.ok(kinds.dealer and kinds.bank and kinds.hotel, "3 guichets utiles")
	local signs = {}
	for _, d in city:GetDescendants() do
		local key = d:GetAttribute("TextKey")
		if key then
			signs[key] = true
		end
	end
	for _, key in { "city.dealer.sign", "city.hotel.sign", "city.bank.sign", "city.shop.cafe", "city.ad.derby" } do
		H.ok(signs[key], "enseigne traduite : " .. key)
	end
end)

H.test("nouveau profil : la citadine est offerte, rien d'autre", function()
	local snap = H.invoke(p, "GetSnapshot")
	H.ok(snap.city, "instantané city")
	H.eq(snap.city.car, "Citadine", "voiture choisie")
	H.ok(snap.city.cars.Citadine, "citadine possédée")
	H.ok(not snap.city.cars.Berline, "berline pas encore achetée")
	H.eq(snap.city.loan, 0, "pas de prêt")
	H.eq(type(snap.city.clubColor), "table", "couleur du club pour la pastille de peinture")
end)

H.test("acheter une voiture : division et argent vérifiés par le serveur, une seule fois", function()
	data.coins = 100000
	local ok, msg = request(p, "buyCar", "Berline")
	H.ok(not ok and msg:find("D6", 1, true), "berline réservée à la D6 : " .. tostring(msg))
	data.club.division = "D6"
	data.coins = 5000
	ok = request(p, "buyCar", "Berline")
	H.ok(not ok, "pas assez d'argent")
	data.coins = 20000
	ok, msg = request(p, "buyCar", "Berline")
	H.ok(ok, "achat : " .. tostring(msg))
	H.eq(data.coins, 20000 - City.GetCar("Berline").price, "prix débité une fois")
	H.ok(data.city.cars.Berline and data.city.car == "Berline", "possédée et choisie")
	ok = request(p, "buyCar", "Berline")
	H.ok(not ok, "pas deux fois")
	H.eq(data.coins, 20000 - City.GetCar("Berline").price, "rien de plus débité")
	ok = request(p, "buyCar", "Inconnue")
	H.ok(not ok, "voiture inconnue refusée")
	ok = request(p, "selectCar", "Super")
	H.ok(not ok, "on ne choisit pas une voiture non achetée")
	ok = request(p, "selectCar", "Citadine")
	H.ok(ok and data.city.car == "Citadine", "retour à la citadine")
	ok = request(p, "paint", "gold")
	H.ok(ok and data.city.paint == "gold", "peinture or")
	ok = request(p, "paint", "rainbow")
	H.ok(not ok and data.city.paint == "gold", "peinture inconnue refusée")
end)

H.test("sortir sa voiture : modèle conduisible à côté du joueur, rangé au départ", function()
	local ok = request(p, "spawnCar")
	H.ok(not ok, "sans personnage : refusé")
	local _, root = giveCharacter(p, Vector3.new(0, 3, 0))
	ok = request(p, "spawnCar")
	H.ok(ok, "voiture sortie")
	local car = workspace.PlayerCars:FindFirstChild("Car_" .. p.UserId)
	H.ok(car, "Model de la voiture")
	H.eq(car:GetAttribute("OwnerId"), p.UserId, "propriétaire")
	H.eq(car:GetAttribute("MaxSpeed"), City.GetCar("Citadine").speed, "vitesse de la citadine")
	local seat = car:FindFirstChild("DriverSeat")
	H.ok(seat and seat.ClassName == "VehicleSeat", "siège conducteur")
	local chassis = car.PrimaryPart
	H.ok(chassis:FindFirstChild("DriveVelocity") and chassis:FindFirstChild("DriveAlign"), "contraintes de conduite")
	H.eq(car:FindFirstChild("Body").Color, City.GetPaint("gold").color, "peinture appliquée")
	H.ok(not chassis.Anchored, "la voiture n'est pas ancrée")
	H.ok((chassis.CFrame.Position - root.CFrame.Position).Magnitude < 15, "à côté du joueur")
	local axles = 0
	for _, d in car:GetChildren() do
		if d.Name == "Axle" then
			axles += 1
			H.ok(d.CanCollide, "essieu porteur")
		end
	end
	H.eq(axles, 2, "deux essieux ronds")
	-- Repeindre la voiture sortie.
	request(p, "paint", "blue")
	H.eq(car:FindFirstChild("Body").Color, City.GetPaint("blue").color, "repeinte sans la ressortir")
	H.ok(H.invoke(p, "GetSnapshot").city.carOut, "instantané : voiture sortie")
	-- Un autre joueur ne peut pas la conduire.
	local other = H.join(2, "Autre")
	local _, _, otherHumanoid = giveCharacter(other, Vector3.new(5, 3, 0))
	seat.Occupant = otherHumanoid
	seat:GetPropertyChangedSignal("Occupant"):Fire()
	H.flush()
	H.ok(otherHumanoid.Jump == true, "l'intrus est éjecté")
	-- Ranger, puis départ du joueur : plus de voiture.
	ok = request(p, "despawnCar")
	H.ok(ok and not workspace.PlayerCars:FindFirstChild("Car_" .. p.UserId), "voiture rangée")
	ok = request(p, "despawnCar")
	H.ok(not ok, "déjà rangée")
	request(other, "spawnCar")
	H.ok(workspace.PlayerCars:FindFirstChild("Car_2"), "voiture de l'autre joueur")
	H.leave(other)
	H.ok(not workspace.PlayerCars:FindFirstChild("Car_2"), "rangée quand il quitte le jeu")
end)

H.test("voiture abandonnée : rangée automatiquement après 5 minutes", function()
	request(p, "spawnCar")
	H.ok(workspace.PlayerCars:FindFirstChild("Car_" .. p.UserId), "sortie")
	H.advance(City.CAR_IDLE_DESPAWN + 20)
	H.ok(not workspace.PlayerCars:FindFirstChild("Car_" .. p.UserId), "rangée")
end)

H.test("banque : prêt du montant de la division, remboursé par les matchs", function()
	data.club.division = "D5"
	data.coins = 0
	local ok, msg = request(p, "loan")
	local max = City.LoanMax("D5")
	H.ok(ok, "prêt : " .. tostring(msg))
	H.eq(data.coins, max, "argent versé")
	H.eq(data.city.bank.loan, City.LoanDue(max), "à rendre avec 10 % de frais")
	ok = request(p, "loan")
	H.ok(not ok and data.coins == max, "un seul prêt à la fois")
	-- Un gain de match en rembourse une part.
	local before = data.city.bank.loan
	local cut = CityService.RepayFromMatch(p, data, 4000)
	H.eq(cut, math.floor(4000 * City.LOAN_REPAY_SHARE), "25 % du gain")
	H.eq(data.city.bank.loan, before - cut, "dette diminuée")
	H.eq(data.coins, max - cut, "prélevé sur le solde")
	-- Remboursement manuel avec ce qu'on a.
	data.coins = 1000
	ok = request(p, "repay")
	H.ok(ok and data.coins == 0, "on rend tout ce qu'on a")
	data.coins = data.city.bank.loan + 500
	ok, msg = request(p, "repay")
	H.ok(ok and data.city.bank.loan == 0 and data.coins == 500, "prêt soldé : " .. tostring(msg))
	ok = request(p, "repay")
	H.ok(not ok, "rien à rembourser")
	H.eq(CityService.RepayFromMatch(p, data, 4000), 0, "plus rien prélevé")
end)

H.test("match joué avec un prêt : le résultat affiche la part prélevée", function()
	data.coins = 0
	request(p, "loan")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	for _, f in data.squad do
		f.energy = PlayerConfig.MAX_ENERGY
	end
	local before = data.city.bank.loan
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	local result = results[#results][1]
	H.ok(result.rewards.loanRepaid > 0, "part prélevée : " .. tostring(result.rewards.loanRepaid))
	H.eq(data.city.bank.loan, before - result.rewards.loanRepaid, "dette diminuée d'autant")
	data.coins = 10000000
	request(p, "repay")
end)

H.test("banque : placement d'un quart du plafond, intérêts seulement après 4 heures", function()
	data.club.division = "D5"
	local cap = City.InvestMax("D5")
	data.coins = cap * 2
	local ok = request(p, "invest")
	H.ok(ok, "dépôt")
	H.eq(data.city.bank.invest, math.ceil(cap / City.INVEST_STEPS), "un quart du plafond")
	for _ = 1, 5 do
		request(p, "invest")
	end
	H.eq(data.city.bank.invest, cap, "jamais plus que le plafond")
	ok = request(p, "invest")
	H.ok(not ok, "plafond atteint")
	local coins = data.coins
	ok = request(p, "withdraw")
	H.ok(ok and data.coins == coins + cap, "retrait anticipé : sans intérêts")
	request(p, "invest")
	local placed = data.city.bank.invest
	H.advance(City.INVEST_SECONDS + 5)
	local snap = H.invoke(p, "GetSnapshot")
	H.eq(snap.city.investReadyIn, 0, "délai écoulé")
	coins = data.coins
	ok = request(p, "withdraw")
	H.ok(ok, "retrait")
	H.eq(data.coins, coins + math.floor(placed * (1 + City.INVEST_RATE) + 0.5), "+5 %")
	ok = request(p, "withdraw")
	H.ok(not ok, "plus rien de placé")
end)

H.test("hôtel : toute l'équipe retrouve son énergie, une fois toutes les 45 minutes", function()
	data.club.division = "D5"
	for _, f in data.squad do
		f.energy = PlayerConfig.MAX_ENERGY
	end
	local ok = request(p, "hotel")
	H.ok(not ok, "équipe déjà reposée : rien à payer")
	for _, f in data.squad do
		f.energy = 20
	end
	data.coins = 0
	ok = request(p, "hotel")
	H.ok(not ok and data.squad[1].energy == 20, "pas assez d'argent")
	data.coins = 10000
	ok = request(p, "hotel")
	H.ok(ok, "mise au vert")
	H.eq(data.coins, 10000 - City.HotelPrice("D5"), "prix de la D5")
	for _, f in data.squad do
		H.eq(f.energy, PlayerConfig.MAX_ENERGY, "énergie pleine : " .. f.name)
	end
	data.squad[1].energy = 10
	ok = request(p, "hotel")
	H.ok(not ok, "hôtel complet pendant 45 minutes")
	H.advance(City.HOTEL_COOLDOWN)
	ok = request(p, "hotel")
	H.ok(ok, "de nouveau possible")
end)

H.test("aller en ville et revenir au club", function()
	local character, root = giveCharacter(p, Vector3.new(0, 3, 0))
	local ok = request(p, "goto", "city")
	H.ok(ok, "en ville")
	H.ok(City.IsInside(root.CFrame.Position), "personnage dans le centre-ville")
	ok = request(p, "goto", "club")
	H.ok(ok, "retour")
	H.ok(not City.IsInside(root.CFrame.Position), "personnage revenu au club")
	ok = request(p, "goto", "lune")
	H.ok(not ok, "destination inconnue")
	character:FindFirstChild("Humanoid").SeatPart = Instance.new("VehicleSeat")
	ok = request(p, "goto", "city")
	H.ok(not ok, "pas de téléportation en conduisant")
	character:FindFirstChild("Humanoid").SeatPart = nil
end)

H.test("profil ancien ou abîmé : data.city réparé sans erreur", function()
	local clean = City.Sanitize({ cars = { Super = true, Fake = true, Berline = "oui" }, car = "Fake", paint = 3, bank = { loan = -5, invest = 0 / 0 }, hotelAt = "x" })
	H.ok(clean.cars.Super and clean.cars.Citadine, "voitures valides gardées, citadine toujours offerte")
	H.ok(not clean.cars.Fake and not clean.cars.Berline, "valeurs abîmées retirées")
	H.eq(clean.car, "Citadine", "voiture choisie réparée")
	H.eq(clean.paint, "club", "peinture réparée")
	H.eq(clean.bank.loan, 0, "prêt négatif remis à 0")
	H.eq(clean.bank.invest, 0, "placement NaN remis à 0")
	H.eq(clean.hotelAt, 0, "date d'hôtel réparée")
	H.eq(City.Sanitize(nil).car, "Citadine", "profil d'avant la ville")
	data.city = "abîmé"
	local ok = request(p, "selectCar", "Citadine")
	H.ok(ok, "le service répare avant d'agir")
end)

H.test("feux : même cycle pour tout le monde, jamais vert dans les deux sens", function()
	for t = 0, City.LIGHT_CYCLE * 2, 0.5 do
		local main, cross = City.LightState("main", t), City.LightState("cross", t)
		H.ok(not (main == "green" and cross == "green"), "jamais deux verts à t = " .. t)
		H.ok(main == "red" or cross == "red", "au moins un rouge à t = " .. t)
	end
	H.eq(City.LightState("main", 1), "green", "boulevard vert au début du cycle")
	H.eq(City.LightState("cross", 20), "green", "rue verte ensuite")
end)

H.test("circulation : budget ordinateur / téléphone / détails, feux allumés, arrêt au rouge", function()
	H.eq(City.TrafficBudget(false, true), City.TRAFFIC_DESKTOP, "ordinateur")
	H.eq(City.TrafficBudget(true, true), City.TRAFFIC_MOBILE, "téléphone")
	H.ok(City.TrafficBudget(true, false) < City.TRAFFIC_MOBILE, "moins sans les détails")
	H.startClient(MODULES, p)
	local Traffic = mock.run(MODULES.Client_TrafficController)
	local length, stops = Traffic.Prepare()
	H.ok(length > 1000, "boucle des boulevards : " .. length)
	H.eq(stops, #City.STOP_LINES, "une ligne d'arrêt par feu du boulevard")
	Traffic.Attach(city)
	H.eq(Traffic.Count(), City.TRAFFIC_DESKTOP, "voitures sur ordinateur")
	Traffic.SetDetails(false)
	H.eq(Traffic.Count(), City.TrafficBudget(false, false), "moins de voitures sans les détails")
	Traffic.SetDetails(true)
	-- t = 1 : boulevard vert. Les feux du boulevard sont verts et allumés.
	Traffic.UpdateLights(1)
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SignalColor") then
			local axis, color = d:GetAttribute("SignalAxis"), d:GetAttribute("SignalColor")
			local lit = (axis == "main" and color == "green") or (axis == "cross" and color == "red")
			H.eq(d.Material == Enum.Material.Neon, lit, ("feu %s %s"):format(axis, color))
		end
	end
	-- Feu rouge pour le boulevard : aucune voiture ne franchit une ligne d'arrêt.
	local red = City.LIGHT_MAIN_GREEN + City.LIGHT_YELLOW + 1
	local Workspace = workspace
	local carsFolder = Workspace:FindFirstChild("Traffic")
	H.ok(carsFolder and #carsFolder:GetChildren() == City.TRAFFIC_DESKTOP, "voitures dans le Workspace")
	for _ = 1, 30 * 20 do
		Traffic.Step(1 / 30, red)
	end
	local stopped = 0
	for _, car in carsFolder:GetChildren() do
		local pivot = car._pivot
		H.ok(pivot, "voiture placée")
		local x = pivot.Position.X - City.ORIGIN.X
		for _, line in City.STOP_LINES do
			if math.abs(x - line.x) < 4 then
				stopped += 1
			end
		end
	end
	H.ok(stopped >= 1, "des voitures attendent aux feux : " .. stopped)
end)

H.test("client : boutons « Ma voiture » et « Ville », fenêtres du concessionnaire et de la banque", function()
	local gui = p.PlayerGui
	local CityUI = mock.run(MODULES.Client_CityController)
	H.ok(H.findText(gui, "Ma voiture", "TextButton"), "bouton Ma voiture")
	H.ok(H.findText(gui, "Ville", "TextButton"), "bouton Ville")
	data.club.division = "D6"
	data.coins = 50000
	data.city = City.Default()
	S.PlayerDataService.MarkChanged(p)
	H.advance(1)
	CityUI.Open("dealer")
	H.flush()
	local open, kind = CityUI.IsOpen()
	H.ok(open and kind == "dealer", "fenêtre du concessionnaire")
	H.ok(H.findText(gui, "Concessionnaire auto"), "titre")
	H.ok(H.findText(gui, "Berline"), "berline dans la liste")
	H.ok(H.findText(gui, "Division 1", "TextButton"), "supercar verrouillée (D1)")
	H.advance(City.CAR_SPAWN_COOLDOWN + 1)
	H.click(gui, "Acheter")
	H.flush()
	H.ok(data.city.cars.Berline, "achat depuis la fenêtre")
	H.advance(1)
	H.ok(H.findText(gui, "Choisie", "TextButton"), "la berline est choisie")
	CityUI.Open("bank")
	H.flush()
	H.ok(H.findText(gui, "Banque du football"), "fenêtre de la banque")
	H.click(gui, "Emprunter")
	H.flush()
	H.ok(data.city.bank.loan > 0, "prêt depuis la fenêtre")
	H.advance(1)
	H.ok(H.findText(gui, "Prêt en cours"), "prêt affiché")
	CityUI.Open("hotel")
	H.flush()
	H.ok(H.findText(gui, "Mise au vert"), "fenêtre de l'hôtel")
	CityUI.Close()
	H.ok(not CityUI.IsOpen(), "fermée")
	data.coins = 10000000
	request(p, "repay")
end)

H.test("conduite : la voiture accélère, plafonne, tourne seulement en roulant", function()
	local Car = mock.run(MODULES.Client_CarController)
	giveCharacter(p, Vector3.new(0, 3, 0))
	request(p, "spawnCar")
	local car = workspace.PlayerCars:FindFirstChild("Car_" .. p.UserId)
	local seat = car:FindFirstChild("DriverSeat")
	local align = car.PrimaryPart:FindFirstChild("DriveAlign")
	local velocity = car.PrimaryPart:FindFirstChild("DriveVelocity")
	seat.ThrottleFloat = 0
	seat.SteerFloat = 1
	Car.Step(seat, 0.5)
	local still = align.CFrame
	Car.Step(seat, 0.5)
	H.eq(Car.GetSpeed(), 0, "à l'arrêt")
	H.ok(math.abs(align.CFrame.LookVector.X - still.LookVector.X) < 1e-6, "ne tourne pas sur place")
	seat.SteerFloat = 0
	seat.ThrottleFloat = 1
	for _ = 1, 300 do
		Car.Step(seat, 1 / 30)
	end
	local max = car:GetAttribute("MaxSpeed")
	H.ok(math.abs(Car.GetSpeed() - max) < 0.01, "vitesse maximale : " .. Car.GetSpeed())
	H.ok(math.abs(velocity.PlaneVelocity.Magnitude - max) < 0.01, "LinearVelocity suit la vitesse")
	seat.SteerFloat = 1
	local before = align.CFrame.LookVector
	Car.Step(seat, 0.2)
	H.ok((align.CFrame.LookVector - before).Magnitude > 0.05, "tourne en roulant")
	seat.SteerFloat = 0
	seat.ThrottleFloat = -1
	for _ = 1, 600 do
		Car.Step(seat, 1 / 30)
	end
	H.ok(Car.GetSpeed() < 0 and Car.GetSpeed() >= -max * 0.35 - 0.01, "marche arrière limitée : " .. Car.GetSpeed())
	request(p, "despawnCar")
end)

H.test("aucune erreur dans les tâches", function()
	H.eq(#H.errors, 0, table.concat(H.errors, " | "))
end)
