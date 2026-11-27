-- Vraie identité visuelle : numéros d'images collés dans shared/Brand.lua (logo,
-- écussons), version dessinée tant qu'une image manque ou n'est pas chargée,
-- lien du jeu publié affiché pour être partagé.
local S = H.boot(MODULES)
local Brand = mock.run(MODULES.Brand)
local WorldBuilder = mock.run(MODULES.WorldBuilder)

local function find(root, name: string)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

H.test("numéros d'images : tous les formats collés sont acceptés", function()
	H.eq(Brand.AssetUri(""), nil, "vide")
	H.eq(Brand.AssetUri(nil), nil, "absent")
	H.eq(Brand.AssetUri("abc"), nil, "illisible")
	H.eq(Brand.AssetUri(0), nil, "zéro")
	H.eq(Brand.AssetUri(123456789), "rbxassetid://123456789", "nombre")
	H.eq(Brand.AssetUri("123456789"), "rbxassetid://123456789", "texte")
	H.eq(Brand.AssetUri(" 123456789 \n"), "rbxassetid://123456789", "espaces autour")
	H.eq(Brand.AssetUri("rbxassetid://987"), "rbxassetid://987", "déjà au bon format")
	H.eq(
		Brand.AssetUri("https://create.roblox.com/store/asset/555/logo"),
		"rbxassetid://555",
		"lien du Creator Hub"
	)
	H.eq(Brand.AssetUri("https://www.roblox.com/library/444/Club-1"), "rbxassetid://444", "ancien lien")
	H.eq(Brand.AssetUri("http://www.roblox.com/asset/?id=333"), "rbxassetid://333", "lien ?id=")
	H.eq(Brand.AssetUri(75942746782438), "rbxassetid://75942746782438", "grand nombre sans virgule")
end)

H.test("par défaut : aucune image, jeu publié connu", function()
	H.eq(Brand.LogoImage(), nil, "pas de logo importé")
	for slot = 1, 6 do
		H.eq(Brand.CrestImage(slot), nil, "pas d'écusson importé " .. slot)
	end
	H.eq(#Brand.CREST_ASSET_IDS, 6, "un écusson par terrain")
	H.eq(Brand.PLACE_ID, 75942746782438, "numéro du jeu publié")
	H.eq(Brand.GAME_URL, "https://www.roblox.com/games/75942746782438", "lien du jeu")
end)

local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)
local slot = S.ClubService.GetSlot(p)

H.test("sans image : titre écrit et écusson dessiné", function()
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, Brand.GAME_TITLE), "titre écrit")
	local hudCrest = find(gui, "Crest")
	H.ok(hudCrest, "écusson du HUD")
	H.eq(hudCrest.Tag.Visible, true, "sigle dessiné")
	H.eq(hudCrest.Image.Visible, false, "pas d'image")
end)

H.test("lien du jeu affiché dans la carte Amis, copiable", function()
	UI.OpenTab("Ranking")
	H.flush()
	local box = find(gui, "GameLink")
	H.ok(box, "case du lien")
	H.eq(box.ClassName, "TextBox", "sélectionnable")
	H.eq(box.Text, Brand.GAME_URL, "bon lien")
	H.eq(box.TextEditable, false, "non modifiable")
end)

-- Images collées, mais Roblox ne les a pas encore chargées (vérification).
Brand.LOGO_ASSET_ID = "111"
Brand.CREST_ASSET_IDS[slot] = 222
local realShow = Brand.ShowWhenLoaded
local loadedNow = false
local pending = {}
Brand.ShowWhenLoaded = function(image, onLoaded)
	table.insert(pending, onLoaded)
	onLoaded(loadedNow)
end

H.test("image pas encore chargée : la version dessinée reste affichée", function()
	UI.OpenTab("Home")
	UI.Refresh()
	H.flush()
	local logo = find(gui, "LogoImage")
	H.ok(logo, "image du logo créée")
	H.eq(logo.Image, "rbxassetid://111", "bon numéro")
	H.eq(logo.Visible, false, "cachée tant que non chargée")
	H.ok(H.findText(gui, Brand.GAME_TITLE).Visible, "titre écrit toujours visible")
	local hudCrest = find(gui, "Crest")
	H.eq(hudCrest.Image.Image, "rbxassetid://222", "écusson du terrain")
	H.eq(hudCrest.Tag.Visible, true, "sigle dessiné en attendant")
end)

H.test("image chargée : le vrai logo et le vrai écusson remplacent le dessin", function()
	loadedNow = true
	for _, onLoaded in pending do
		onLoaded(true)
	end
	UI.OpenTab("Home")
	UI.Refresh()
	H.flush()
	local logo = find(gui, "LogoImage")
	H.eq(logo.Visible, true, "logo affiché")
	local hudCrest = find(gui, "Crest")
	H.eq(hudCrest.Image.Visible, true, "écusson image")
	H.eq(hudCrest.Tag.Visible, false, "sigle caché")
	H.eq(hudCrest.BackgroundTransparency, 1, "fond dessiné retiré")
end)
Brand.ShowWhenLoaded = realShow

H.test("terrain 3D : écusson au portique et sur le toit des bureaux niveau 5", function()
	local levels = {}
	for id in S.Buildings.Definitions do
		levels[id] = 5
	end
	local plot = WorldBuilder.buildPlot(slot, levels, data.club.name)
	local images = {}
	for _, d in plot:GetDescendants() do
		if d.ClassName == "ImageLabel" and d.Image == "rbxassetid://222" then
			table.insert(images, d)
		end
	end
	H.ok(#images >= 3, "portique + 2 faces du toit (" .. #images .. ")")
	H.ok(find(plot, "CrestImageLeft"), "face gauche du toit")
	H.ok(find(plot, "CrestImageRight"), "face droite du toit")
	H.ok(WorldBuilder.countParts(plot) <= 750, "budget de Parts inchangé")
end)

H.test("ShowWhenLoaded sans IsLoaded (imitation) : reste sur le dessin, sans erreur", function()
	local seen
	Brand.ShowWhenLoaded(Instance.new("ImageLabel"), function(loaded)
		seen = loaded
	end)
	H.eq(seen, false, "non chargé")
end)

H.finish()
