-- Espagnol et portugais (Brésil) : langue détectée d'après le compte Roblox,
-- sélecteur à 4 langues dans les Paramètres, aucun texte manquant ni resté en
-- français, boutons lisibles sur téléphone malgré des textes plus longs.
local S = H.boot(MODULES)
local Locale = mock.run(MODULES.Locale)
local TABS = { "Home", "Stadium", "Squad", "Management", "Matches", "Ranking", "Prestige", "Settings" }

H.test("4 langues complètes : mêmes clés et mêmes variables partout", function()
	H.eq(#Locale.SUPPORTED, 4, "fr, en, es, pt")
	local counts = {}
	for _, lang in Locale.SUPPORTED do
		local n = 0
		for key, text in Locale.Strings[lang] do
			n += 1
			H.ok(type(text) == "string" and text ~= "", lang .. " : texte vide pour " .. key)
		end
		counts[lang] = n
	end
	H.eq(counts.es, counts.fr, "autant de textes en espagnol qu'en français")
	H.eq(counts.pt, counts.fr, "autant de textes en portugais qu'en français")
	H.eq(Locale.T("es", "result.promoted", { division = "División 6" }), "¡Ascenso! Bienvenido a División 6.", "variables en espagnol")
	H.eq(Locale.T("pt", "squad.count", { count = 3, max = 16 }), "Elenco: 3 / 16 jogadores", "variables en portugais")
end)

H.test("textes vraiment traduits : pas de phrase française restée telle quelle", function()
	local leaks = {}
	for key, text in Locale.Strings.fr do
		-- Les formats sans mots (« {a}. {b} · {c} pts ») peuvent rester identiques.
		local words = text:gsub("{%w+}", ""):gsub("[%p%d%s]", "")
		if #words > 12 then
			for _, lang in { "es", "pt" } do
				if Locale.Strings[lang][key] == text then
					table.insert(leaks, lang .. " " .. key)
				end
			end
		end
	end
	H.eq(#leaks, 0, "non traduits : " .. table.concat(leaks, ", "))
end)

local brazilian = H.join(5, "Jogador", "pt-br")
local spanish = H.join(6, "Jugador", "es-mx")

H.test("messages du serveur dans la langue du compte (pt-br, es-mx)", function()
	H.fire(brazilian, "RequestUpgrade", "Pitch")
	local msg = H.lastNotify(brazilian)
	H.ok(msg and msg:find("Campo principal: nível 2", 1, true), "message en portugais : " .. tostring(msg))
	H.fire(spanish, "RequestUpgrade", "Pitch")
	msg = H.lastNotify(spanish)
	H.ok(msg and msg:find("Campo principal: ¡nivel 2!", 1, true), "message en espagnol : " .. tostring(msg))
end)

local gui = H.startClient(MODULES, spanish)
local UI = mock.run(MODULES.Client_UIController)

local function openAll()
	UI.SetMenuOpen(true)
	for _, tab in TABS do
		UI.OpenTab(tab)
		H.flush()
	end
end

H.test("le client s'affiche en espagnol pour un compte hispanophone", function()
	UI.SetMenuOpen(true)
	UI.OpenTab("Squad")
	H.flush()
	H.ok(H.findText(gui, "Plantilla: 3 / "), "effectif en espagnol")
	UI.OpenTab("Stadium")
	H.flush()
	H.ok(H.findText(gui, "Campo principal · nivel 2"), "stade en espagnol")
	H.ok(H.findText(workspace, "OFICINAS"), "décor 3D en espagnol")
end)

-- Mots qui n'existent qu'en français (les petits mots comme « la » ou « de »
-- existent aussi en espagnol et en portugais).
local FRENCH = { "Améliorer", "Embaucher", "Signer", "Joue ", "Gagne ", "matchs", "Défier", "Saison", "Cadeau", "Effectif", "Récupérer", " avec ", " pour ", "ton club", " tes " }

local function leaksIn(lang)
	UI.SetLanguage(lang)
	H.flush()
	local leaks = {}
	openAll()
	for _, tab in TABS do
		UI.OpenTab(tab)
		H.flush()
		for _, d in gui:GetDescendants() do
			local text = d.Text
			if type(text) == "string" and text ~= "Français" then
				for _, word in FRENCH do
					if string.find(" " .. text .. " ", word, 1, true) then
						table.insert(leaks, tab .. " : " .. text)
						break
					end
				end
			end
		end
	end
	return leaks
end

H.test("espagnol et portugais : aucun texte français dans les 8 onglets", function()
	for _, lang in { "es", "pt" } do
		local leaks = leaksIn(lang)
		H.eq(#leaks, 0, lang .. " : textes en français : " .. table.concat(leaks, " | "))
	end
end)

H.test("textes espagnols et portugais lisibles sur téléphone", function()
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new(667, 375)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	H.flush()
	local scale = gui:FindFirstChildWhichIsA("ScreenGui"):FindFirstChildWhichIsA("UIScale").Scale
	for _, lang in { "es", "pt" } do
		UI.SetLanguage(lang)
		H.flush()
		local checked, narrow = 0, {}
		openAll()
		for _, tab in TABS do
			UI.OpenTab(tab)
			H.flush()
			for _, d in gui:GetDescendants() do
				if d.ClassName == "TextButton" and type(d.Size) == "table" and d.Size[1] == 0 then
					-- Largeur moyenne d'un caractère Gotham ≈ 0,6 × la taille du texte.
					local width = (d.Size[2] - 12) * scale
					local chars = utf8.len(d.Text) or #d.Text
					local fittingSize = width / (math.max(chars, 1) * 0.6)
					H.ok(d.TextScaled, lang .. " : le texte doit pouvoir rétrécir : " .. d.Text)
					if fittingSize < 9 then
						table.insert(narrow, ("« %s » (%.1f px)"):format(d.Text, fittingSize))
					end
					checked += 1
				end
			end
		end
		H.ok(checked > 10, lang .. " : boutons vérifiés : " .. checked)
		H.eq(#narrow, 0, lang .. " : boutons trop étroits : " .. table.concat(narrow, " | "))
	end
end)

H.test("Paramètres : 4 boutons de langue sur une ligne, le choix est appliqué", function()
	UI.SetLanguage("es")
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Settings")
	H.flush()
	for _, name in { "Français", "English", "Español", "Português" } do
		local b = H.findText(gui, name, "TextButton")
		H.ok(b, "bouton " .. name)
		H.eq(b.Size[1], 0.25, "largeur relative (un quart de ligne) : " .. name)
	end
	H.click(gui, "Português")
	H.eq(spanish:GetAttribute("Language"), "pt", "langue enregistrée sur le joueur")
	H.ok(H.findText(gui, "Configurações", "TextButton"), "onglets en portugais")
	H.ok(H.findText(workspace, "ESCRITÓRIOS"), "décor en portugais")
	H.fire(spanish, "RequestUpgrade", "Stands") -- pas assez d'argent : message d'erreur
	local msg = H.lastNotify(spanish)
	H.ok(msg and msg:find("Faltam", 1, true), "serveur en portugais : " .. tostring(msg))
	H.click(gui, "Español")
	H.eq(spanish:GetAttribute("Language"), "es", "retour à l'espagnol")
	H.ok(H.findText(gui, "Ajustes", "TextButton"), "onglets en espagnol")
end)

H.test("aucune clé de texte demandée sans traduction (es, pt)", function()
	for _, lang in { "es", "pt" } do
		UI.SetLanguage(lang)
		openAll()
	end
	local list = {}
	for key in Locale.Missing do
		table.insert(list, key)
	end
	H.eq(#list, 0, "clés introuvables : " .. table.concat(list, ", "))
end)
