-- Boutique Robux : objets exclusifs purement visuels, achats validés par le
-- serveur (ProcessReceipt), un reçu = un seul octroi, boost coupé par défaut.
local S = H.boot(MODULES)
local Monetization = mock.run(MODULES.Monetization)
local Locale = mock.run(MODULES.Locale)
local Cosmetics = S.Cosmetics
local Market = game:GetService("MarketplaceService")
local Decision = Enum.ProductPurchaseDecision
local store = H.getStore("PlayerProfiles_v1")

local prompts = {}
Market.PromptProductPurchase = function(_self, player, productId)
	table.insert(prompts, { player = player, id = productId })
end

-- ProcessReceipt peut attendre (sauvegarde, nouvelles tentatives) : on le lance
-- dans une tâche et on fait avancer l'horloge simulée.
local function receipt(userId: number, productId: number, purchaseId: string)
	local decision = "pas de réponse"
	task.spawn(function()
		decision = Market.ProcessReceipt({ PlayerId = userId, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 50 })
	end)
	H.advance(30)
	return decision
end

local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

H.test("par défaut : IDs vides, boutique cachée, boost coupé, rien n'est accordé", function()
	H.eq(Monetization.BOOST_ENABLED, false, "boost désactivé par défaut")
	for _, product in Monetization.PRODUCTS do
		H.eq(product.productId, 0, "ID vide : " .. product.key)
		H.eq(Monetization.IsAvailable(product), false, "caché : " .. product.key)
	end
	H.eq(Monetization.AnyAvailable(), false, "aucune boutique visible")
	H.fire(p, "RequestBuyExclusive", "colors_vip_neon")
	H.eq(#prompts, 0, "aucune fenêtre d'achat")
	H.ok(H.lastNotify(p):find("disponible", 1, true), "message clair")
	H.eq(receipt(1, 0, "r0"), Decision.NotProcessedYet, "reçu d'un produit non configuré : pas accordé")
	H.eq(next(data.cosmetics.owned), nil, "rien accordé")
end)

H.test("objets exclusifs : purement visuels, textes FR/EN, jamais vendus en FC Coins", function()
	for _, item in Cosmetics.EXCLUSIVE do
		H.ok(item.robux and Cosmetics.IsCategory(item.category), "catégorie : " .. item.id)
		H.eq(Cosmetics.Get(item.id), item, "trouvé par son identifiant")
		H.eq(table.find(Cosmetics.List, item), nil, "hors du catalogue Prestige")
		H.ok(Monetization.ForCosmetic(item.id), "produit Robux : " .. item.id)
		for _, lang in { "fr", "en" } do
			H.ok(Locale.Strings[lang]["cosmetic." .. item.id], "nom " .. lang)
		end
	end
	for _, product in Monetization.PRODUCTS do
		H.ok(product.cosmetic or product.boost, "produit cosmétique ou boost : " .. product.key)
		H.ok(not product.coins and not product.players and not product.points, "aucun avantage sportif")
	end
	data.coins = 10000000
	H.eq(S.CosmeticService.TryBuy(p, "colors_vip_neon"), false, "pas d'achat en FC Coins")
	H.eq(data.coins, 10000000, "aucun débit")
	H.eq(S.CosmeticService.TryEquip(p, "colors", "colors_vip_neon"), false, "pas porté sans achat")
end)

-- IDs collés comme le fera Nj après avoir créé les produits sur Roblox.
Monetization.Get("colors_vip_neon").productId = 1001
Monetization.Get("kit_vip_carbon").productId = 1002
Monetization.Get("boost_income").productId = 1003

H.test("demande d'achat : fenêtre Roblox seulement pour un produit ouvert et pas possédé", function()
	H.ok(Monetization.AnyAvailable(), "boutique visible une fois un ID rempli")
	H.fire(p, "RequestBuyExclusive", "colors_vip_neon")
	H.eq(#prompts, 1, "fenêtre ouverte")
	H.eq(prompts[1].id, 1001, "bon produit")
	H.advance(1)
	for _, bad in { "statue_vip_crystal", "nope", 1001, nil } do
		H.fire(p, "RequestBuyExclusive", bad)
		H.advance(1)
	end
	H.eq(#prompts, 1, "IDs vides ou inconnus refusés")
	H.fire(p, "RequestBuyExclusive", "boost_income")
	H.eq(#prompts, 1, "boost refusé tant que l'interrupteur est coupé")
	H.eq(next(data.cosmetics.owned), nil, "la demande seule n'accorde rien")
end)

H.test("reçu accordé une seule fois, sauvegardé avant de répondre à Roblox", function()
	local coins = data.coins
	H.eq(receipt(1, 1001, "r1"), Decision.PurchaseGranted, "accordé")
	H.ok(data.cosmetics.owned.colors_vip_neon, "objet ajouté")
	H.eq(data.cosmetics.equipped.colors, "colors_vip_neon", "porté tout de suite")
	H.eq(data.coins, coins, "aucun FC Coin donné ni pris")
	H.eq(data.purchases.count, 1, "un octroi")
	local saved = store.data.player_1.data
	H.ok(saved.purchases.receipts.r1 and saved.cosmetics.owned.colors_vip_neon, "reçu et objet écrits dans le DataStore")
	H.eq(receipt(1, 1001, "r1"), Decision.PurchaseGranted, "reçu rejoué : réponse identique")
	H.eq(data.purchases.count, 1, "pas de second octroi")
	H.fire(p, "RequestBuyExclusive", "colors_vip_neon")
	H.eq(#prompts, 1, "déjà possédé : pas de nouvelle fenêtre")
end)

H.test("panne de sauvegarde : « pas encore », puis le même reçu n'est pas redonné", function()
	store.failNext = 100
	H.eq(receipt(1, 1002, "r2"), Decision.NotProcessedYet, "sauvegarde impossible : Roblox réessaiera")
	store.failNext = 0
	H.ok(data.cosmetics.owned.kit_vip_carbon, "le joueur a déjà son objet")
	H.eq(data.purchases.count, 2, "un octroi")
	H.eq(receipt(1, 1002, "r2"), Decision.PurchaseGranted, "nouvel essai de Roblox : accordé")
	H.eq(data.purchases.count, 2, "toujours un seul octroi")
	H.ok(store.data.player_1.data.purchases.receipts.r2, "reçu sauvegardé")
end)

H.test("reconnexion : un reçu déjà accordé n'est jamais rejoué ; joueur absent = pas encore", function()
	H.leave(p)
	H.eq(receipt(1, 1001, "r3"), Decision.NotProcessedYet, "joueur parti : on attend son retour")
	p = H.join(1)
	H.advance(5)
	data = S.PlayerDataService.GetData(p)
	H.ok(data.cosmetics.owned.colors_vip_neon and data.cosmetics.owned.kit_vip_carbon, "objets gardés")
	H.eq(receipt(1, 1001, "r1"), Decision.PurchaseGranted, "ancien reçu reconnu")
	H.eq(receipt(1, 1002, "r2"), Decision.PurchaseGranted, "ancien reçu reconnu")
	H.eq(data.purchases.count, 2, "aucun octroi en double après reconnexion")
	H.eq(receipt(1, 1001, "r3"), Decision.PurchaseGranted, "reçu en attente accordé au retour")
	H.eq(data.purchases.count, 3, "un octroi de plus")
	H.eq(receipt(1, 9999, "r4"), Decision.NotProcessedYet, "produit inconnu : pas accordé")
end)

H.test("panne totale avant la sauvegarde : rien n'est perdu, le reçu est accordé au retour", function()
	Monetization.Get("statue_vip_crystal").productId = 1004
	local q = H.join(2)
	H.advance(5)
	store.failNext = 1000
	H.eq(receipt(2, 1004, "s1"), Decision.NotProcessedYet, "pas encore accordé à Roblox")
	H.leave(q) -- la sauvegarde de départ échoue aussi : l'objet n'est pas écrit
	H.advance(120)
	store.failNext = 0
	q = H.join(2)
	H.advance(5)
	local d = S.PlayerDataService.GetData(q)
	H.eq(d.cosmetics.owned.statue_vip_crystal, nil, "objet jamais sauvegardé")
	H.eq(receipt(2, 1004, "s1"), Decision.PurchaseGranted, "Roblox renvoie le reçu : accordé")
	H.ok(d.cosmetics.owned.statue_vip_crystal, "objet accordé une fois")
	H.eq(d.purchases.count, 1, "un seul octroi")
	H.leave(q)
end)

H.test("objet exclusif : porter, retirer, terrain 3D", function()
	H.eq(S.CosmeticService.TryEquip(p, "colors", "default"), true, "apparence d'origine")
	H.eq(S.CosmeticService.TryEquip(p, "colors", "colors_vip_neon"), true, "remis")
	H.flush()
	local WorldBuilder = mock.run(MODULES.WorldBuilder)
	H.eq(WorldBuilder.getPlot(S.ClubService.GetSlot(p)):GetAttribute("Colors"), "colors_vip_neon", "terrain aux couleurs exclusives")
end)

H.test("reçus gardés en nombre limité", function()
	for i = 1, Monetization.RECEIPTS_KEPT + 20 do
		data.purchases.receipts["old" .. i] = i
	end
	H.eq(receipt(1, 1001, "r5"), Decision.PurchaseGranted, "accordé")
	local n = 0
	for _ in data.purchases.receipts do
		n += 1
	end
	H.eq(n, Monetization.RECEIPTS_KEPT, "liste bornée")
	H.ok(data.purchases.receipts.r5, "le plus récent est gardé")
end)

H.test("boost (prudence) : sans effet tant que l'interrupteur est coupé, borné une fois ouvert", function()
	H.eq(receipt(1, 1003, "b1"), Decision.NotProcessedYet, "boost coupé : pas accordé")
	H.eq(Monetization.BoostMultiplier(data, os.time()), 1, "aucun bonus")
	Monetization.BOOST_ENABLED = true
	H.eq(receipt(1, 1003, "b2"), Decision.PurchaseGranted, "boost accordé")
	H.eq(Monetization.BoostMultiplier(data, os.time()), 1.5, "bonus actif")
	for i = 3, 10 do
		receipt(1, 1003, "b" .. i)
	end
	H.ok(data.boost.expiresAt - os.time() <= Monetization.BOOST_MAX_MINUTES * 60, "durée cumulée plafonnée")
	H.advance(Monetization.BOOST_MAX_MINUTES * 60 + 1)
	H.eq(Monetization.BoostMultiplier(data, os.time()), 1, "boost terminé")
	Monetization.BOOST_ENABLED = false
end)

H.test("écran Prestige : boutique Robux visible avec des IDs, bouton d'achat, cachée sinon", function()
	data.cosmetics.owned.kit_vip_carbon = nil
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Prestige")
	H.flush()
	H.ok(H.findText(gui, "Boutique exclusive") or H.findText(gui, "Exclusive Store"), "boutique visible (IDs remplis)")
	local before = #prompts
	H.click(gui, if H.findText(gui, "Buy with Robux", "TextButton") then "Buy with Robux" else "Acheter avec des Robux")
	H.eq(#prompts, before + 1, "le bouton ouvre la fenêtre Roblox")
	H.eq(prompts[#prompts].id, 1004, "statue de cristal (premier objet pas encore possédé)")
	for _, product in Monetization.PRODUCTS do
		product.productId = 0
	end
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	UI.OpenTab("Prestige")
	H.flush()
	H.eq(H.findText(gui, "Boutique exclusive") or H.findText(gui, "Exclusive Store"), nil, "IDs vides : boutique cachée")
	H.eq(H.findText(gui, "Robux", "TextButton"), nil, "aucun bouton Robux")
	H.ok(H.findText(gui, "Néon rose") or H.findText(gui, "Pink and Turquoise"), "objet déjà acheté toujours affiché")
end)

H.shutdown()
