-- Stabilité avant le premier test dans Studio : profils abîmés, service qui
-- plante à l'arrivée d'un joueur, demandes absurdes ou en rafale, onglets du
-- menu sur petit écran.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)

local function hasWarning(fragment: string): boolean
	for _, w in H.warnings do
		if string.find(w, fragment, 1, true) then
			return true
		end
	end
	return false
end

H.test("profil abîmé : chaque champ invalide reprend sa valeur par défaut", function()
	store.data["player_41"] = {
		data = {
			schemaVersion = 1,
			coins = "beaucoup",
			club = { name = "FC Test", division = "D7", divisionPoints = "dix", stats = 5 },
			buildings = { Stands = "x", Pitch = -3 },
			squad = "aucun",
			academy = 12,
			cosmetics = { owned = "rien", equipped = {} },
			trophies = { titles = "beaucoup", seen = 0 },
			tutorial = { step = 1, completed = false },
		},
	}
	local p = H.join(41)
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	H.eq(data.coins, S.Config.STARTING_COINS, "pièces")
	H.eq(data.club.name, "FC Test", "nom gardé")
	H.eq(data.club.divisionPoints, 0, "points")
	H.eq(type(data.club.stats), "table", "statistiques")
	H.eq(data.buildings.Stands, 1, "tribunes")
	H.eq(data.buildings.Pitch, 1, "pelouse")
	H.eq(type(data.cosmetics.owned), "table", "objets")
	H.eq(data.trophies.titles, 0, "titres")
	H.ok(#data.squad > 0, "effectif recréé")
	H.ok(p:GetAttribute("ClubSlot"), "terrain attribué")
	H.ok(H.received(p, "ProfileUpdated"), "instantané envoyé")
	H.leave(p)
end)

H.test("profil enregistré qui n'est pas une table : nouveau profil", function()
	store.data["player_42"] = { data = "cassé" }
	local p = H.join(42)
	local data = S.PlayerDataService.GetData(p)
	H.ok(data and data.coins == S.Config.STARTING_COINS, "profil neuf")
	H.ok(p:GetAttribute("ClubSlot"), "terrain attribué")
	H.leave(p)
end)

H.test("un service qui plante à l'arrivée ne bloque pas le joueur", function()
	local original = S.ChallengeService.OnPlayerReady
	S.ChallengeService.OnPlayerReady = function()
		error("panne simulée")
	end
	local p = H.join(43)
	S.ChallengeService.OnPlayerReady = original
	H.ok(p:GetAttribute("ClubSlot"), "terrain attribué malgré la panne")
	H.ok(H.received(p, "ProfileUpdated"), "menu alimenté")
	H.ok(H.received(p, "TournamentUpdated"), "services suivants lancés")
	H.ok(hasWarning("ChallengeService.OnPlayerReady"), "panne signalée dans la sortie")
	H.leave(p)
	H.ok(store.data["player_43"].lock == nil, "profil libéré au départ")
end)

H.test("panne à l'attribution du terrain : message clair, emplacement et profil libérés", function()
	local original = S.ClubService.OnPlayerReady
	S.ClubService.OnPlayerReady = function()
		error("panne simulée")
	end
	local p = H.join(44)
	S.ClubService.OnPlayerReady = original
	H.flush()
	H.ok(p.kickMessage and #p.kickMessage > 0, "joueur prévenu")
	H.ok(S.PlayerDataService.GetData(p) == nil, "profil libéré")
	H.ok(store.data["player_44"].lock == nil, "verrou levé")
	-- Les 6 emplacements restent disponibles.
	local players = {}
	for i = 1, S.Config.MAX_CLUBS_PER_SERVER do
		players[i] = H.join(500 + i)
		H.ok(players[i]:GetAttribute("ClubSlot"), "emplacement " .. i)
	end
	for _, other in players do
		H.leave(other)
	end
end)

H.test("demandes absurdes sur chaque RemoteEvent : aucune erreur, rien de gratuit", function()
	local Net = mock.run(MODULES.Net)
	local p = H.join(45)
	local data = S.PlayerDataService.GetData(p)
	local coins = data.coins
	local nan = 0 / 0
	local junk = {
		{},
		{ nil, nil },
		{ 0 / 0, math.huge },
		{ -1e9, -1e9 },
		{ { a = 1 }, { 1, 2 } },
		{ string.rep("é", 5000), true },
		{ "Stands", nan },
		{ "default", "default" },
	}
	H.warnings = {}
	for _, name in Net.Requests do
		for _, args in junk do
			H.advance(1) -- reste sous la limite de fréquence
			H.fire(p, name, args[1], args[2])
		end
	end
	H.ok(not hasWarning("[Net] Erreur"), "aucune erreur de gestionnaire : " .. table.concat(H.warnings, " / "))
	H.eq(#H.errors, 0, "erreurs")
	H.ok(data.coins <= coins, "aucune pièce gagnée")
	H.ok(data.coins == data.coins, "pièces toujours valides")
	H.leave(p)
end)

H.test("rafale de demandes : limitée par joueur", function()
	local p = H.join(46)
	local data = S.PlayerDataService.GetData(p)
	data.coins = 10 ^ 9
	H.clearSent()
	for _ = 1, 30 do
		H.fire(p, "RequestUpgrade", "Shop")
	end
	local notifies = 0
	for _, msg in H.sent[p] or {} do
		if msg.name == "Notify" then
			notifies += 1
		end
	end
	H.ok(notifies <= S.Config.RATE_LIMIT_MAX_REQUESTS, "au plus " .. S.Config.RATE_LIMIT_MAX_REQUESTS .. " traitées, vu " .. notifies)
	H.leave(p)
end)

H.test("menu : les 8 onglets toujours visibles (1 rangée sur PC, 2 sur téléphone)", function()
	local p = H.join(47)
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	H.flush()
	local bar
	for _, d in gui:GetDescendants() do
		if d.Name == "Tabs" then
			bar = d
		end
	end
	H.ok(bar, "barre d'onglets")
	local totalScale, count = 0, 0
	for _, child in bar:GetChildren() do
		if child.ClassName == "TextButton" then
			count += 1
			-- UDim2.new(xScale, xOffset, yScale, yOffset) dans l'imitation Roblox.
			totalScale += child.Size[1]
			H.ok(child.Size[2] <= 0, "largeur relative pour " .. child.Text)
			H.ok(child.TextScaled, "texte qui rétrécit pour " .. child.Text)
		end
	end
	H.eq(count, 8, "onglets")
	H.ok(totalScale <= 1.0001, "les onglets ne dépassent pas la barre")
	H.ok(H.findText(gui, "Prestige", "TextButton"), "onglet Prestige visible")
	H.ok(H.findText(gui, "Paramètres", "TextButton"), "onglet Paramètres visible")

	-- Téléphone : 2 rangées de 4, textes lisibles, contenu sous la barre.
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new(667, 375)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	local scale = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChildWhichIsA("UIScale").Scale
	H.eq(UI.TabRows(scale), 2, "deux rangées sur téléphone")
	H.eq(bar.Size[4], 2 * 44 + 4, "hauteur de la barre")
	local content = bar.Parent:FindFirstChild("Content")
	H.ok(content.Position.Y.Offset >= bar.Position.Y.Offset + bar.Size[4], "contenu sous les onglets")
	-- Panneau de 760 px (avant mise à l'échelle) : largeur réelle d'un onglet.
	local tabWidth = ((760 - 74) / 4 - 4 - 12) * scale
	local longest = 0
	for _, child in bar:GetChildren() do
		if child.ClassName == "TextButton" then
			longest = math.max(longest, utf8.len(child.Text) or #child.Text)
			H.eq(child.Size[1], 0.25, "4 onglets par rangée : " .. child.Text)
		end
	end
	H.ok(tabWidth / (longest * 0.6) >= 10, ("texte des onglets lisible : %.1f px"):format(tabWidth / (longest * 0.6)))

	-- Retour sur grand écran : une seule rangée.
	camera.ViewportSize = Vector2.new(1920, 1080)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	H.eq(bar.Size[4], 44, "une rangée sur PC")
end)

H.test("instantané du profil : transmissible par le réseau Roblox", function()
	local p = H.join(48)
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.checkSerializable(snapshot, "GetSnapshot", false)
	H.ok(snapshot.coins, "pièces présentes")
	H.leave(p)
end)
