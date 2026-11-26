-- Prestige : personnalisation du club (achetée en FC Coins, sans effet sportif)
-- et salle des trophées (montées, titres de D1, records).
local S = H.boot(MODULES)
local Cosmetics, Trophies = S.Cosmetics, S.Trophies
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local Locale = mock.run(MODULES.Locale)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

local function plot()
	return WorldBuilder.getPlot(S.ClubService.GetSlot(p))
end

local function changed()
	S.PlayerDataService.MarkChanged(p)
	H.flush()
end

H.test("catalogue : 5 catégories, prix serveur, textes FR/EN, conditions valides", function()
	H.eq(#Cosmetics.CATEGORIES, 5, "catégories")
	for _, category in Cosmetics.CATEGORIES do
		H.ok(#Cosmetics.ByCategory(category) >= 5, "au moins 5 objets : " .. category)
		for _, lang in { "fr", "en" } do
			H.ok(Locale.Strings[lang]["cosmeticCategory." .. category], "texte de catégorie " .. lang)
		end
	end
	for _, item in Cosmetics.List do
		H.ok(item.cost > 0 and item.cost == math.floor(item.cost), "prix entier : " .. item.id)
		H.ok(S.Divisions.Get(item.requires.division), "division valide : " .. item.id)
		for _, lang in { "fr", "en" } do
			H.ok(Locale.Strings[lang]["cosmetic." .. item.id], ("nom %s de %s"):format(lang, item.id))
		end
	end
	-- Fin de partie : le catalogue complet vaut des millions (relancer le simulateur si on le change).
	H.ok(Cosmetics.TotalCost() > 10000000, "catalogue complet : " .. Cosmetics.TotalCost())
end)

H.test("achat refusé sans débit : objet inconnu, division trop basse, pas assez d'argent", function()
	data.coins = 10000000
	for _, bad in { "nope", 42, nil, { id = "colors_royal" } } do
		H.eq(S.CosmeticService.TryBuy(p, bad), false, "identifiant invalide refusé")
	end
	H.eq(data.club.division, "D7", "nouveau club en D7")
	local ok, msg = S.CosmeticService.TryBuy(p, "colors_royal")
	H.eq(ok, false, "couleurs réservées à la D5")
	H.ok(msg:find("Division 5", 1, true), "message : " .. msg)
	H.eq(data.coins, 10000000, "aucun débit")
	data.club.division = "D6"
	data.coins = 100
	H.eq(S.CosmeticService.TryBuy(p, "decor_flags"), false, "pas assez d'argent")
	H.eq(data.coins, 100, "aucun débit")
	H.eq(next(data.cosmetics.owned), nil, "rien acheté")
end)

H.test("achat validé par le serveur : prix du catalogue, débit unique, objet porté", function()
	data.club.division = "D5"
	data.coins = 1000000
	-- Le client ne peut envoyer que l'identifiant : un prix ajouté est ignoré.
	H.fire(p, "RequestBuyCosmetic", "colors_royal", 1)
	H.eq(data.coins, 1000000 - Cosmetics.Get("colors_royal").cost, "prix du serveur")
	H.ok(data.cosmetics.owned.colors_royal, "possédé")
	H.eq(data.cosmetics.equipped.colors, "colors_royal", "porté tout de suite")
	local coins = data.coins
	H.advance(1)
	H.fire(p, "RequestBuyCosmetic", "colors_royal")
	H.eq(data.coins, coins, "pas de double achat")
	H.eq(plot():GetAttribute("Colors"), "colors_royal", "terrain reconstruit aux nouvelles couleurs")
end)

H.test("porter, retirer : seulement un objet possédé de la bonne catégorie", function()
	H.eq(S.CosmeticService.TryEquip(p, "colors", "colors_emerald"), false, "non possédé")
	H.eq(S.CosmeticService.TryEquip(p, "lighting", "colors_royal"), false, "mauvaise catégorie")
	H.eq(S.CosmeticService.TryEquip(p, "decor", "default"), false, "les décorations ne se portent pas")
	H.eq(S.CosmeticService.TryEquip(p, "hack", "default"), false, "catégorie inconnue")
	H.eq(S.CosmeticService.TryEquip(p, "colors", "default"), true, "apparence d'origine")
	H.eq(data.cosmetics.equipped.colors, nil, "plus de couleurs portées")
	H.ok(data.cosmetics.owned.colors_royal, "toujours possédé")
	H.fire(p, "RequestEquipCosmetic", "colors", "colors_royal")
	H.eq(data.cosmetics.equipped.colors, "colors_royal", "remis par le client")
end)

H.test("terrain 3D : statue, décorations, éclairage et tenue visibles par tous", function()
	data.club.division = "D1"
	data.trophies.titles = 10
	data.coins = 100000000
	data.buildings.Pitch = 3
	for _, item in Cosmetics.List do
		if not data.cosmetics.owned[item.id] then
			H.advance(1)
			H.fire(p, "RequestBuyCosmetic", item.id)
			H.ok(data.cosmetics.owned[item.id], "acheté : " .. item.id)
		end
	end
	H.fire(p, "RequestEquipCosmetic", "lighting", "lighting_gold")
	H.fire(p, "RequestEquipCosmetic", "statue", "statue_cup")
	H.fire(p, "RequestEquipCosmetic", "kit", "kit_galaxy")
	local model = plot()
	H.eq(model.Statue:GetAttribute("Cosmetic"), "statue_cup", "statue choisie")
	H.ok(model.Decor:FindFirstChild("FountainBasin") and model.Decor:FindFirstChild("Star"), "décorations")
	local gold = Cosmetics.Get("lighting_gold").color
	local spots = 0
	for _, d in model.Pitch:GetDescendants() do
		if d:IsA("SpotLight") then
			spots += 1
			H.eq(d.Color, gold, "projecteur doré")
		end
	end
	H.ok(spots > 0, "projecteurs présents")
	H.eq(model.TrophyRoom.KitMannequin.Shirt.Color, Cosmetics.Get("kit_galaxy").shirt, "tenue sur le mannequin")
	H.ok(WorldBuilder.countParts(model) <= 900, "budget de Parts avec toute la personnalisation")
end)

H.test("aucun avantage sportif : la note de l'équipe ne change pas", function()
	local before = S.ClubService.GetClubList()[1].rating
	data.cosmetics = { owned = {}, equipped = {} }
	H.eq(S.ClubService.GetClubList()[1].rating, before, "même note")
end)

H.test("objets réservés aux champions : refusés tant qu'il manque des titres", function()
	data.trophies.titles = 0
	data.coins = 100000000
	local ok, msg = S.CosmeticService.TryBuy(p, "statue_cup")
	H.eq(ok, false, "10 titres requis")
	H.ok(msg:find("10", 1, true), "message : " .. msg)
	H.eq(data.coins, 100000000, "aucun débit")
end)

H.test("salle des trophées : une montée = un trophée, annoncé et exposé", function()
	data.club.division = "D7"
	data.trophies = { titles = 0, seen = 0 }
	data.club.stats = { played = 0, wins = 0, draws = 0, losses = 0, goalsFor = 0, goalsAgainst = 0 }
	changed()
	S.ClubService.RefreshPlot(p)
	H.eq(#Trophies.Earned("D7", data.club.stats, 0), 0, "D7 : vitrine vide")
	H.eq(plot().TrophyRoom:GetAttribute("Trophies"), 0, "vitrine vide en 3D")
	data.club.division = "D5"
	H.clearSent()
	changed()
	H.eq(data.trophies.seen, 2, "montées en D6 et D5")
	H.ok(H.lastNotify(p):find("2", 1, true), "annonce : " .. H.lastNotify(p))
	H.eq(plot().TrophyRoom:GetAttribute("Trophies"), 2, "deux coupes exposées")
	H.clearSent()
	changed()
	H.eq(H.lastNotify(p), nil, "pas d'annonce en double")
end)

H.test("titres de D1 : chaque saison de 300 points donne un titre, les points repartent", function()
	data.club.division = "D1"
	data.club.divisionPoints = Trophies.TITLE_POINTS * 2 + 50
	changed()
	H.eq(data.trophies.titles, 2, "deux titres")
	H.eq(data.club.divisionPoints, 50, "points restants")
	H.eq(data.trophies.seen, 6 + 2, "6 montées + 2 titres")
	local snapshot = H.invoke(p, "GetSnapshot")
	H.eq(snapshot.titles, 2, "titres envoyés au client")
	H.eq(#snapshot.trophies, 8, "trophées envoyés au client")
	-- Des matchs en D1 font avancer le prochain titre.
	data.club.divisionPoints = Trophies.TITLE_POINTS - 1
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "ai", "Balanced")
	H.advance(1)
	H.ok(data.trophies.titles == 3 or data.club.divisionPoints == Trophies.TITLE_POINTS - 1, "titre après une victoire ou un nul")
end)

H.test("records : 50 victoires, 500 matchs, 1 000 buts", function()
	data.club.stats.wins = 50
	data.club.stats.played = 500
	data.club.stats.goalsFor = 1000
	local list = Trophies.Earned(data.club.division, data.club.stats, data.trophies.titles)
	local ids = {}
	for _, t in list do
		ids[t.id] = true
	end
	H.ok(ids.wins_50 and ids.played_500 and ids.goals_1000, "trois records")
	H.ok(not ids.wins_250, "pas encore 250 victoires")
	-- Défis et tournois entre clubs : compteurs du bilan, lus s'ils existent.
	H.ok(not ids.tournaments_1, "aucun tournoi gagné")
	data.club.stats.tournamentsWon = 1
	local withCup = Trophies.Earned(data.club.division, data.club.stats, data.trophies.titles)
	H.eq(#withCup, #list + 1, "un tournoi gagné = un trophée")
	data.club.stats.tournamentsWon = nil
	for _, m in Trophies.MILESTONES do
		for _, lang in { "fr", "en" } do
			H.ok(Locale.Strings[lang]["trophy." .. m.stat], ("texte %s du record %s"):format(lang, m.id))
		end
	end
end)

H.test("classement : les visiteurs voient le nombre de trophées", function()
	changed()
	local club = S.ClubService.GetClubList()[1]
	H.eq(club.trophies, data.trophies.seen, "trophées dans la liste des clubs")
	H.eq(club.titles, data.trophies.titles, "titres dans la liste des clubs")
end)

H.test("sauvegarde : objets, tenue portée et titres restent après reconnexion", function()
	data.coins = 100000000
	S.CosmeticService.TryBuy(p, "kit_stripes")
	local titles = data.trophies.titles
	H.leave(p)
	p = H.join(1)
	data = S.PlayerDataService.GetData(p)
	H.ok(data.cosmetics.owned.kit_stripes, "objet gardé")
	H.eq(data.cosmetics.equipped.kit, "kit_stripes", "tenue gardée")
	H.eq(data.trophies.titles, titles, "titres gardés")
end)

H.test("ancien profil sans personnalisation : complété au chargement", function()
	local store = H.getStore(S.Config.DATASTORE_NAME)
	local p2 = H.join(2)
	local d2 = S.PlayerDataService.GetData(p2)
	d2.cosmetics, d2.trophies = nil, nil
	d2.club.division = "D4"
	H.leave(p2)
	H.ok(store, "DataStore")
	p2 = H.join(2)
	d2 = S.PlayerDataService.GetData(p2)
	H.ok(d2.cosmetics and d2.cosmetics.owned and d2.trophies, "champs ajoutés")
	H.flush()
	H.eq(d2.trophies.seen, 3, "trophées déjà mérités comptés (D6, D5, D4)")
end)

local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)

H.test("écran Prestige : trophées, objets, achat par bouton", function()
	data.club.division = "D6"
	data.coins = 50000
	data.cosmetics = { owned = {}, equipped = {} }
	changed()
	UI.SetMenuOpen(true)
	UI.OpenTab("Prestige")
	H.flush()
	H.ok(H.findText(gui, "Salle des trophées") or H.findText(gui, "Trophy Room"), "salle des trophées")
	local button = H.findText(gui, "Buy · ", "TextButton") or H.findText(gui, "Acheter · ", "TextButton")
	H.ok(button, "bouton d'achat")
	H.click(gui, button.Text)
	H.flush()
	H.ok(data.cosmetics.owned.decor_flags, "drapeaux achetés depuis l'écran")
end)
