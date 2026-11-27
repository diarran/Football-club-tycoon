-- Rendu semi-réaliste : finitions des bâtiments, aménagement paysager, budget
-- de Parts et option « Détails du décor » côté client.
local S = H.boot(MODULES)
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local WorldConfig = mock.run(MODULES.WorldConfig)
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)

local function details(root): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Detail") == true then
			n += 1
			H.eq(d.CastShadow, false, "un détail ne projette pas d'ombre : " .. d.Name)
		end
	end
	return n
end

local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

H.test("chaque terrain a son aménagement : haies, arbres, lampadaires, drapeaux, parking", function()
	for slot = 1, WorldConfig.MAX_PLOTS do
		local plot = WorldBuilder.getPlot(slot)
		H.ok(plot, "terrain " .. slot)
		local landscape = plot:FindFirstChild("Landscape")
		H.ok(landscape, "aménagement du terrain " .. slot)
		local counts = {}
		for _, child in landscape:GetChildren() do
			counts[child.Name] = (counts[child.Name] or 0) + 1
		end
		H.eq(counts.Hedge, #WorldConfig.LANDSCAPE.hedges, "haies")
		H.eq(counts.Tree, #WorldConfig.LANDSCAPE.trees, "arbres")
		H.eq(counts.StreetLamp, #WorldConfig.LANDSCAPE.lamps, "lampadaires")
		H.eq(counts.Flag, #WorldConfig.LANDSCAPE.flags, "drapeaux")
		H.eq(counts.Parking, 1, "parking")
		H.ok(#find(landscape, "Parking"):GetChildren() > 4, "voitures et places marquées")
	end
end)

H.test("les bâtiments ont cadres de fenêtres, angles, acrotère et le stade est habillé", function()
	data.coins = 10000000
	for id in S.Buildings.Definitions do
		while data.buildings[id] < 5 do
			H.advance(1)
			H.fire(p, "RequestUpgrade", id)
		end
	end
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	for _, id in { "Offices", "Shop", "Academy", "VIP", "LockerRoom" } do
		local model = plot:FindFirstChild(id)
		H.ok(find(model, "WindowFrame"), "cadres de fenêtres : " .. id)
		H.ok(find(model, "Corner"), "angles : " .. id)
		H.ok(find(model, "Parapet"), "acrotère : " .. id)
	end
	H.ok(find(plot.Offices, "Canopy"), "marquise du siège")
	H.ok(find(plot.Stands, "Cladding"), "façade du stade habillée")
	H.ok(find(plot.TrophyRoom, "Corner"), "salle des trophées finie")
	-- Aucun plastique lisse « jouet » sur les murs.
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "WallSide" or d.Name == "WallBack") then
			H.ok(d.Material ~= Enum.Material.SmoothPlastic, "mur en vrai matériau : " .. d:GetFullName())
		end
	end
end)

H.test("budget mobile : Parts au niveau max et part des détails masquables", function()
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	local total = WorldBuilder.countParts(plot)
	local detail = details(plot)
	H.ok(total <= 1400, "au plus 1 400 Parts au niveau max (" .. total .. ")")
	H.ok(detail >= total * 0.2, "au moins 20 % de détails masquables (" .. detail .. "/" .. total .. ")")
	local district = workspace:FindFirstChild(WorldConfig.DISTRICT_NAME)
	H.ok(district, "quartier")
end)

H.test("client : option Détails du décor (masque et réaffiche les petits détails)", function()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	local Detail = mock.run(MODULES.Client_DetailController)
	Detail.Init()
	Detail.Update()
	H.ok(Detail.IsEnabled(), "activé par défaut")
	UI.SetMenuOpen(true)
	UI.OpenTab("Settings")
	local text = H.findText(gui, "Détails du décor")
	H.ok(text, "option dans les Paramètres")
	text.Parent:FindFirstChildWhichIsA("TextButton").Activated:Fire()
	H.flush()
	H.eq(UI.GetSettings().details, false, "désactivé")
	H.eq(Detail.IsEnabled(), false, "contrôleur prévenu")
	H.ok(Detail.HiddenCount() > 100, "détails masqués (" .. Detail.HiddenCount() .. ")")
	local sample
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Detail") == true then
			sample = d
			break
		end
	end
	H.eq(sample.LocalTransparencyModifier, 1, "pièce masquée pour ce joueur seulement")
	H.eq(sample.Transparency, 0, "rien ne change côté serveur")
	H.findText(gui, "Détails du décor").Parent:FindFirstChildWhichIsA("TextButton").Activated:Fire()
	H.flush()
	H.eq(Detail.HiddenCount(), 0, "tout réapparaît")
	H.eq(sample.LocalTransparencyModifier, 0, "pièce réaffichée")
end)
