-- PNJ : supporters qui rapportent des FC Coins (décidé par le serveur), trajets
-- vers la Boutique, le Musée et les tribunes, joueurs à l'entraînement, gardiens,
-- joueurs e-sport, passants, et budget anti-lag côté client.
local S = H.boot(MODULES)
local Npc = mock.run(MODULES.Npc)
local Campus = mock.run(MODULES.Campus)
local WorldConfig = mock.run(MODULES.WorldConfig)
local SupporterService = mock.run(MODULES.SupporterService)

local function campusRequest(p, ...)
	H.advance(Campus.MOVE_COOLDOWN + 1)
	H.fire(p, "RequestCampus", ...)
	local _, kind = H.lastNotify(p)
	return kind == "success"
end

local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
data.missions.list = {}
local slot = S.ClubService.GetSlot(p)

H.test("réglages : budget plus bas sur téléphone et sans détails, gains croissants", function()
	H.eq(Npc.Budget(false, true), Npc.BUDGET_DESKTOP, "ordinateur")
	H.eq(Npc.Budget(true, true), Npc.BUDGET_MOBILE, "téléphone")
	H.ok(Npc.Budget(false, false) < Npc.BUDGET_DESKTOP, "détails coupés : moins de PNJ")
	H.ok(Npc.Budget(true, false) >= 4, "toujours quelques PNJ")
	for level = 2, 5 do
		H.ok(Npc.ShopSpend(level) > Npc.ShopSpend(level - 1), "boutique niveau " .. level)
	end
	H.eq(Npc.MuseumSpend(0), 0, "pas de musée, pas d'argent")
	H.ok(Npc.MuseumSpend(3) > Npc.MuseumSpend(1), "musée amélioré")
	H.eq(Npc.ShopSpend("abc"), Npc.ShopSpend(1), "valeur abîmée ramenée au niveau 1")
	-- Gain par heure modeste (au plus la moitié d'un match bien rémunéré au niveau max).
	local perHour = 3600 / Npc.VISIT_INTERVAL * (Npc.ShopSpend(5) + Npc.MuseumSpend(3))
	H.ok(perHour <= 3000, "au plus 3 000 FC Coins par heure (" .. perHour .. ")")
end)

H.test("trajets : chaque parcelle et chaque orientation mènent à la porte, sans sortir du terrain", function()
	local maxZ = WorldConfig.PLOT_SIZE.Y / 2 + WorldConfig.CAMPUS_DEPTH
	local function inside(route, label)
		for _, point in route do
			H.ok(math.abs(point.X) <= WorldConfig.PLOT_SIZE.X / 2, label .. " : x dans le terrain")
			H.ok(point.Z >= -WorldConfig.PLOT_SIZE.Y / 2 - 4 and point.Z <= maxZ, label .. " : z dans le terrain")
		end
	end
	for index in WorldConfig.PARCELS do
		for _, rot in Campus.ROTATIONS do
			local route = Npc.CampusRoute(index, rot)
			H.ok(route and #route >= 5, "trajet parcelle " .. index .. " / " .. rot)
			local door = Npc.CampusDoor(index, rot)
			H.ok((route[#route] - door).Magnitude < 0.01, "finit devant la porte")
			inside(route, "parcelle " .. index)
			-- Jamais de traversée en diagonale à travers une parcelle : segments droits.
			for i = 2, #route do
				local a, b = route[i - 1], route[i]
				if i > 2 then
					H.ok(math.abs(a.X - b.X) < 0.01 or math.abs(a.Z - b.Z) < 0.01, "segment droit " .. index .. "/" .. rot .. "/" .. i)
				end
			end
		end
	end
	H.eq(Npc.CampusRoute(99, 0), nil, "parcelle inconnue")
	inside(Npc.ShopRoute(3), "boutique")
	inside(Npc.StadiumRoute(-3), "tribunes")
	for i = 1, #Npc.STROLL_TARGETS do
		inside(Npc.StrollRoute(i), "balade " .. i)
	end
end)

H.test("serveur : chaque achat de supporter rapporte des FC Coins et est annoncé à tous", function()
	local before = data.coins
	H.clearSent()
	local earned = SupporterService.Tick(p)
	H.eq(earned, Npc.ShopSpend(data.buildings.Shop), "achat à la boutique")
	H.eq(data.coins, before + earned, "versé au club")
	local visits = H.received(p, "SupporterVisit")
	H.eq(#visits, 1, "visite annoncée")
	H.eq(visits[1][1], slot, "sur le bon terrain")
	H.eq(visits[1][2], "shop", "à la boutique")
	H.eq(visits[1][3], earned, "montant affiché")
	-- La boucle du serveur tourne toute seule.
	H.clearSent()
	H.advance(Npc.VISIT_INTERVAL * 3 + 1)
	H.ok(#H.received(p, "SupporterVisit") >= 3, "une visite toutes les " .. Npc.VISIT_INTERVAL .. " s")
end)

H.test("musée construit : visites en plus, résumé de temps en temps", function()
	data.club.division = "D2"
	data.coins = 10000000
	campusRequest(p, "unlock", 1)
	campusRequest(p, "unlock", 2)
	campusRequest(p, "unlock", 3)
	H.ok(campusRequest(p, "build", "Museum", 1, 90), "musée construit")
	local visits = SupporterService.VisitsFor(data)
	H.eq(#visits, 2, "boutique + musée")
	H.eq(visits[2].kind, "museum", "musée")
	H.eq(visits[2].coins, Npc.MuseumSpend(1), "prix du musée")
	H.clearSent()
	for _ = 1, Npc.SUMMARY_EVERY do
		SupporterService.Tick(p)
	end
	local found = false
	for _, msg in H.received(p, "Notify") do
		if string.find(msg[1], "supporters", 1, true) then
			found = true
		end
	end
	H.ok(found, "résumé « Tes supporters ont dépensé… »")
	H.eq(SupporterService.Tick(H.join(99)), 0, "joueur sans club : rien")
	H.eq(#SupporterService.VisitsFor(nil), 0, "profil abîmé : rien")
end)

-- Client -------------------------------------------------------------------

H.ok(campusRequest(p, "build", "Esport", 2, 0), "centre e-sport")
H.ok(campusRequest(p, "build", "Security", 3, 0), "centre de sécurité")
local gui = H.startClient(MODULES, p)
local NpcC = mock.run(MODULES.Client_NpcController)
local camera = workspace.CurrentCamera
local center = WorldConfig.getPlotCFrame(slot).Position

local function lookAtClub()
	camera.CFrame = CFrame.new(center + Vector3.new(0, 70, 0))
	NpcC.Rescan()
end

local function run(seconds: number)
	for _ = 1, math.floor(seconds * 30) do
		NpcC.Step(1 / 30)
	end
end

H.test("client : le club proche s'anime (gardiens, entraînement, e-sport, supporters)", function()
	H.ok(gui, "client démarré")
	lookAtClub()
	local stats = NpcC.Stats()
	H.eq(stats.zones, 1, "un terrain animé")
	H.eq(stats.byRole.guard, 4, "2 gardiens au portique + 2 en ronde (centre de sécurité)")
	H.eq(stats.byRole.trainer, Npc.TrainingCount(data.buildings.Training), "joueurs à l'entraînement")
	H.ok((stats.byRole.gamer or 0) >= 2, "joueurs e-sport assis")
	H.ok((stats.byRole.stroller or 0) >= 1, "supporters qui se promènent")
	H.ok(stats.total <= stats.budget, "budget respecté")
	local folder = workspace:FindFirstChild("Npcs")
	H.ok(folder, "dossier des PNJ (côté client)")
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			H.ok(d.Anchored and not d.CanCollide and not d.CastShadow and not d.CanQuery, "pièce légère : " .. d.Name)
		end
	end
	-- Ils bougent.
	local stroller
	for _, agent in NpcC.Agents() do
		if agent.role == "stroller" or (agent.role == "trainer" and agent.trainer == "run") then
			stroller = agent
			break
		end
	end
	local start = stroller.pos
	run(10)
	H.ok((stroller.pos - start).Magnitude > 5, "un PNJ s'est déplacé")
	H.ok(stroller.fig.torso.CFrame.Position.Y > 0, "dessiné au-dessus du sol")
end)

H.test("client : un achat annoncé envoie un supporter à la boutique, « +N » puis il repart", function()
	lookAtClub()
	NpcC.OnVisit(slot, "shop", 9)
	NpcC.OnVisit(slot, "museum", 10)
	local maxPopups, sawVisitor = 0, false
	for _ = 1, 120 do
		run(0.5)
		local stats = NpcC.Stats()
		maxPopups = math.max(maxPopups, stats.popups)
		sawVisitor = sawVisitor or (stats.byRole.visitor or 0) > 0
	end
	H.ok(sawVisitor, "supporter en route")
	H.ok(maxPopups >= 1, "« +N » affiché à l'arrivée")
	H.eq(NpcC.Stats().byRole.visitor, nil, "reparti ensuite (personnage rendu à la réserve)")
	H.ok(NpcC.Stats().pooled >= 1, "réserve réutilisée")
	-- Annonce pour un terrain loin de la caméra, ou abîmée : ignorée.
	NpcC.OnVisit(6, "shop", 9)
	NpcC.OnVisit("x", nil, nil)
	run(2)
	H.eq(NpcC.Stats().byRole.visitor, nil, "rien pour un terrain lointain")
end)

H.test("client : jour de match, les supporters en maillot rejoignent les tribunes", function()
	lookAtClub()
	NpcC.MatchDay(slot)
	local seen = 0
	for _ = 1, 60 do
		run(0.5)
		seen = math.max(seen, NpcC.Stats().byRole.matchday or 0)
	end
	H.ok(seen >= 3, "vague de supporters (" .. seen .. ")")
	run(30)
	H.eq(NpcC.Stats().byRole.matchday, nil, "entrés dans le stade")
	NpcC.MatchDay(nil)
end)

H.test("anti-lag : détails coupés, téléphone, caméra loin", function()
	lookAtClub()
	NpcC.SetDetailsEnabled(false)
	H.ok(NpcC.Stats().total <= Npc.Budget(false, false), "moins de PNJ sans détails (" .. NpcC.Stats().total .. ")")
	NpcC.SetDetailsEnabled(true)
	local uis = game:GetService("UserInputService")
	uis.TouchEnabled = true
	uis.KeyboardEnabled = false
	NpcC.Rescan()
	H.ok(NpcC.Stats().total <= Npc.BUDGET_MOBILE, "téléphone : au plus " .. Npc.BUDGET_MOBILE)
	uis.TouchEnabled = false
	uis.KeyboardEnabled = true
	camera.CFrame = CFrame.new(5000, 80, 5000)
	NpcC.Rescan()
	H.eq(NpcC.Stats().total, 0, "personne à animer loin de tout")
	H.eq(NpcC.Stats().zones, 0, "aucun terrain animé")
	-- Retour : les personnages de la réserve sont réutilisés.
	local created = mock.created
	lookAtClub()
	H.ok(NpcC.Stats().total > 0, "de nouveau animés")
	H.ok(mock.created - created < 20, "réserve réutilisée (" .. (mock.created - created) .. " objets créés)")
end)

H.test("passants sur les trottoirs du quartier", function()
	camera.CFrame = CFrame.new(0, 40, 0)
	NpcC.Rescan()
	local count = NpcC.Stats().byRole.pedestrian or 0
	H.ok(count >= 1 and count <= Npc.PEDESTRIANS_DESKTOP, "passants (" .. count .. ")")
	local lanes = Npc.SidewalkLanes()
	for _, agent in NpcC.Agents() do
		if agent.role == "pedestrian" then
			H.ok(table.find(lanes, agent.pos.Z) ~= nil, "sur un trottoir")
		end
	end
	run(5)
	H.ok(NpcC.Stats().total <= NpcC.Stats().budget, "budget respecté")
end)

H.finish()
