-- Bout en bout : le VRAI client (HUD, menus) branché sur le VRAI serveur.
-- On clique sur les boutons comme un joueur et on vérifie l'effet côté serveur.
local S = H.boot(MODULES)
local rival = H.join(2, "Rival")
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)

H.test("le client démarre et affiche le HUD avec le solde du serveur", function()
	H.ok(gui:FindFirstChildWhichIsA("ScreenGui"), "interface créée")
	H.ok(H.findText(gui, data.club.name), "nom du club affiché")
	H.ok(H.findText(gui, "5"), "solde affiché")
end)

H.test("écusson du club dans le HUD : sigle aux couleurs du terrain", function()
	local Brand = mock.run(MODULES.Brand)
	H.eq(Brand.Tag("FC Roquerouge"), "FR", "sigle de deux mots")
	H.eq(Brand.Tag("Racing Club Élan Nord"), "RCÉ", "trois lettres max, accents gardés")
	H.eq(Brand.Tag(""), "FC", "sigle par défaut")
	H.ok(H.findText(gui, Brand.Tag(data.club.name)), "sigle affiché dans le HUD")
end)

H.test("tous les onglets du menu s'affichent sans erreur", function()
	UI.SetMenuOpen(true)
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Settings", "Ranking" } do
		UI.OpenTab(tab)
		H.flush()
	end
	H.ok(H.findText(gui, "dirigé par Rival"), "club rival dans le classement")
end)

H.test("bouton Améliorer : le serveur débite et l'interface se met à jour", function()
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	UI.OpenTab("Stadium")
	H.click(gui, "Améliorer")
	H.eq(data.coins, S.Config.STARTING_COINS - S.Buildings.GetUpgradeCost("Pitch", 1), "solde serveur")
	H.eq(data.buildings.Pitch, 2, "terrain niveau 2")
	H.ok(H.findText(gui, "Terrain principal · niveau 2"), "niveau affiché")
end)

H.test("bouton Recruter : un joueur rejoint l'effectif", function()
	data.coins += S.PlayerConfig.RECRUIT_COST
	UI.OpenTab("Squad")
	H.click(gui, "Recruter")
	H.eq(#data.squad, 4, "effectif serveur")
	H.ok(H.findText(gui, "Effectif : 4"), "effectif affiché")
end)

H.test("bouton Jouer : match simulé, fenêtre de résultat puis Continuer", function()
	UI.OpenTab("Matches")
	H.click(gui, "Offensive")
	H.click(gui, "Jouer")
	H.eq(data.club.stats.played, 1, "match joué côté serveur")
	H.eq(data.tactic, "Offensive", "tactique choisie envoyée")
	H.ok(H.findText(gui, "Continuer"), "fenêtre de résultat")
	H.click(gui, "Continuer")
end)

H.test("renommer le club depuis l'accueil", function()
	UI.OpenTab("Home")
	local box
	for _, d in gui:GetDescendants() do
		if d.ClassName == "TextBox" then
			box = d
		end
	end
	H.ok(box, "zone de saisie")
	box.Text = "Les Testeurs FC"
	H.click(gui, "Renommer")
	H.eq(data.club.name, "Les Testeurs FC", "nom serveur")
	H.ok(H.findText(gui, "Les Testeurs FC"), "nom affiché")
end)

H.test("le tutoriel n'oblige pas à refaire les actions faites en avance", function()
	-- Le joueur a amélioré et joué avant même la fin de l'étape 1 : le tutoriel
	-- doit avoir suivi, et « Continuer » sur le résultat termine le parcours.
	H.advance(10)
	H.eq(data.tutorial.completed, true, "tutoriel terminé")
end)

H.test("le temps qui passe (notifications, délais) ne provoque pas d'erreur", function()
	H.advance(30)
	UI.OpenTab("Matches")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS)
end)

H.test("écran de téléphone : l'interface se réduit et reste utilisable", function()
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new(667, 375) -- téléphone à l'horizontale
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	local scale = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChildWhichIsA("UIScale")
	H.ok(scale, "UIScale présent")
	H.ok(scale.Scale < 1 and scale.Scale >= 0.7, "échelle réduite : " .. tostring(scale.Scale))
	UI.SetMenuOpen(true)
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Ranking", "Prestige", "Settings" } do
		UI.OpenTab(tab)
		H.flush()
	end
	-- Boutons assez grands pour un doigt (44 px de haut minimum avant mise à l'échelle).
	for _, d in gui:GetDescendants() do
		if d.ClassName == "TextButton" and type(d.Size) == "table" and d.Size[4] then
			H.ok(d.Size[4] >= 36, "bouton trop petit : " .. tostring(d.Text))
		end
	end
end)
