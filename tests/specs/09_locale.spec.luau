-- Langues : français et anglais complets, langue choisie d'après le compte Roblox,
-- textes anglais qui tiennent sur un écran de téléphone.
local S = H.boot(MODULES)
local Locale = mock.run(MODULES.Locale)
local fr, en = Locale.Strings.fr, Locale.Strings.en

H.test("chaque clé existe dans toutes les langues, avec les mêmes variables", function()
	local missing = {}
	for lang, strings in Locale.Strings do
		for otherLang, other in Locale.Strings do
			for key, text in other do
				local mine = strings[key]
				if type(mine) ~= "string" or mine == "" then
					table.insert(missing, ("%s manque en %s (présente en %s)"):format(key, lang, otherLang))
				else
					for name in Locale.Placeholders(text) do
						if not Locale.Placeholders(mine)[name] then
							table.insert(missing, ("%s : {%s} manque en %s"):format(key, name, lang))
						end
					end
				end
			end
		end
	end
	H.eq(#missing, 0, "clés manquantes : " .. table.concat(missing, " / "))
end)

H.test("les données du jeu ont toutes leurs textes", function()
	local keys = { "division.label", "hud.menuButton", "tutorial.progress" }
	for id in S.Buildings.Definitions do
		table.insert(keys, "building." .. id .. ".label")
		table.insert(keys, "building." .. id .. ".description")
	end
	for id in S.Config.Tactics do
		table.insert(keys, "tactic." .. id)
	end
	for id in S.PlayerConfig.Positions do
		table.insert(keys, "position." .. id)
	end
	for _, step in mock.run(MODULES.TutorialSteps) do
		table.insert(keys, "tutorial." .. step.id)
	end
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Ranking", "Settings" } do
		table.insert(keys, "tab." .. tab)
	end
	for _, outcome in { "Win", "Draw", "Loss" } do
		table.insert(keys, "result." .. outcome)
	end
	for _, key in keys do
		H.ok(fr[key] and en[key], "clé absente : " .. key)
	end
end)

H.test("langue d'après le compte Roblox, anglais par défaut", function()
	H.eq(Locale.FromLocaleId("fr-fr"), "fr", "fr-fr")
	H.eq(Locale.FromLocaleId("fr-CA"), "fr", "fr-CA")
	H.eq(Locale.FromLocaleId("en-us"), "en", "en-us")
	H.eq(Locale.FromLocaleId("de-de"), "en", "langue non gérée")
	H.eq(Locale.FromLocaleId("pt-br"), "en", "langue non gérée")
	H.eq(Locale.FromLocaleId(nil), "en", "langue inconnue")
	H.eq(Locale.T("en", "result.promoted", { division = "Division 6" }), "Promoted! Welcome to Division 6.", "variables")
end)

local german = H.join(3, "Spieler", "de-de")
local p = H.join(1, "Player", "en-us")

H.test("un joueur allemand reçoit les messages du serveur en anglais", function()
	H.fire(german, "RequestUpgrade", "Pitch")
	local msg = H.lastNotify(german)
	H.ok(msg and msg:find("Main field: Level 2", 1, true), "message anglais : " .. tostring(msg))
end)

local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)

local function openAll()
	UI.SetMenuOpen(true)
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Ranking", "Settings" } do
		UI.OpenTab(tab)
		H.flush()
	end
end

H.test("le client s'affiche en anglais pour un compte anglophone", function()
	H.ok(H.findText(gui, "Club", "TextButton"), "bouton du menu")
	UI.SetMenuOpen(true)
	UI.OpenTab("Squad")
	H.flush()
	H.ok(H.findText(gui, "Roster: 3 / "), "effectif en anglais")
	UI.OpenTab("Stadium")
	H.flush()
	H.ok(H.findText(gui, "Main field · level 1"), "stade en anglais")
	H.ok(not H.findText(gui, "Effectif"), "aucun texte français")
end)

H.test("le décor 3D est traduit pour le joueur", function()
	local offices = H.findText(workspace, "OFFICES")
	H.ok(offices, "panneau des Bureaux en anglais")
	H.eq(offices:GetAttribute("TextKey"), "world.offices", "clé notée par le serveur")
end)

H.test("textes anglais lisibles sur téléphone : aucun bouton trop étroit", function()
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new(667, 375)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	local scale = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChildWhichIsA("UIScale").Scale
	local checked = 0
	local function checkButtons()
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextButton" and type(d.Size) == "table" and d.Size[1] == 0 then
				-- Largeur moyenne d'un caractère Gotham ≈ 0,6 × la taille du texte.
				local width = (d.Size[2] - 12) * scale
				local chars = utf8.len(d.Text) or #d.Text
				local fittingSize = width / (math.max(chars, 1) * 0.6)
				H.ok(d.TextScaled, "le texte doit pouvoir rétrécir : " .. d.Text)
				H.ok(fittingSize >= 9, ("bouton trop étroit pour « %s » (%.1f px)"):format(d.Text, fittingSize))
				checked += 1
			end
		end
	end
	openAll()
	for _, tab in { "Home", "Stadium", "Squad", "Matches", "Ranking", "Settings" } do
		UI.OpenTab(tab)
		H.flush()
		checkButtons()
	end
	H.ok(checked > 10, "boutons vérifiés : " .. checked)
end)

H.test("changer de langue dans les Paramètres : interface, décor et serveur suivent", function()
	UI.OpenTab("Settings")
	H.flush()
	H.click(gui, "Français")
	H.eq(p:GetAttribute("Language"), "fr", "langue enregistrée sur le joueur")
	H.ok(H.findText(gui, "Paramètres", "TextButton"), "onglets en français")
	H.ok(H.findText(workspace, "BUREAUX"), "décor en français")
	H.fire(p, "RequestUpgrade", "Pitch")
	local msg = H.lastNotify(p)
	H.ok(msg and msg:find("Terrain principal : niveau 2", 1, true), "message serveur en français : " .. tostring(msg))
	H.fire(p, "RequestLanguage", "xx")
	H.eq(p:GetAttribute("Language"), "fr", "langue inconnue refusée")
end)

H.test("aucune clé de texte demandée sans traduction", function()
	openAll()
	UI.SetLanguage("en")
	openAll()
	local list = {}
	for key in Locale.Missing do
		table.insert(list, key)
	end
	H.eq(#list, 0, "clés introuvables : " .. table.concat(list, ", "))
end)
