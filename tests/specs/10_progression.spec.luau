-- Progression longue : 5 niveaux par installation et Boutique du club.
local S = H.boot(MODULES)
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local WorldConfig = mock.run(MODULES.WorldConfig)
local store = H.getStore(S.Config.DATASTORE_NAME)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("chaque installation, Boutique comprise, a 5 niveaux de prix croissants", function()
	H.ok(S.Buildings.Get("Shop"), "la Boutique existe")
	for id, def in S.Buildings.Definitions do
		H.eq(#def.levels, 5, "niveaux de " .. id)
		H.eq(def.levels[1].cost, 0, "niveau 1 gratuit pour " .. id)
		for level = 2, #def.levels do
			H.ok(def.levels[level].cost > def.levels[level - 1].cost, ("prix croissant %s %d"):format(id, level))
		end
		-- Chaque effet chiffré progresse (ou reste égal) d'un niveau à l'autre.
		for level = 2, #def.levels do
			for key, value in def.levels[level].effects do
				local previous = def.levels[level - 1].effects[key]
				H.ok(type(previous) == "number" and value >= previous, ("effet %s.%s niveau %d"):format(id, key, level))
			end
		end
	end
	H.eq(WorldConfig.MAX_LEVEL, 5, "niveaux visuels")
	for id in S.Buildings.Definitions do
		H.ok(table.find(WorldConfig.FACILITY_IDS, id), "modèle 3D prévu pour " .. id)
		H.eq(S.Buildings.MaxLevel(id), WorldConfig.MAX_LEVEL, "niveaux 3D de " .. id)
	end
	for level, def in S.Buildings.Get("Stands").levels do
		H.eq(WorldConfig.STANDS_CAPACITY[level], def.effects.capacity, "capacité affichée niveau " .. level)
	end
end)

H.test("monter une installation jusqu'au niveau 5 coûte la somme exacte des prix", function()
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	data.coins = 1000000
	local total = 0
	for level = 2, 5 do
		total += S.Buildings.GetUpgradeCost("Shop", level - 1)
		H.advance(1)
		H.fire(p, "RequestUpgrade", "Shop")
		H.eq(data.buildings.Shop, level, "niveau de la boutique")
	end
	H.eq(data.coins, 1000000 - total, "solde après 4 améliorations")
	H.advance(1)
	H.fire(p, "RequestUpgrade", "Shop")
	H.eq(data.buildings.Shop, 5, "pas de niveau 6")
	H.eq(data.coins, 1000000 - total, "rien débité au-delà du maximum")
	local _, kind = H.lastNotify(p)
	H.eq(kind, "error", "refus notifié")
end)

H.test("le terrain du club affiche la Boutique au bon niveau", function()
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	H.ok(plot, "terrain du joueur")
	local shop = plot:FindFirstChild("Shop")
	H.ok(shop, "modèle Boutique")
	H.eq(shop:GetAttribute("Level"), 5, "niveau du modèle")
	H.eq(plot:GetAttribute("Level_Shop"), 5, "attribut du terrain")
end)

H.test("chaque installation au niveau 5 a son modèle 3D au niveau 5", function()
	data.coins = 10000000
	for id in S.Buildings.Definitions do
		while data.buildings[id] < 5 do
			H.advance(1)
			H.fire(p, "RequestUpgrade", id)
		end
	end
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	for id in S.Buildings.Definitions do
		local model = plot:FindFirstChild(id)
		H.ok(model, "modèle " .. id)
		H.eq(model:GetAttribute("Level"), 5, "niveau 3D de " .. id)
	end
	H.ok(WorldBuilder.countParts(plot) <= 750, "budget de Parts au niveau maximum (8 installations)")
end)

H.test("la Boutique rapporte à chaque match, montant calculé par le serveur", function()
	data.buildings.Shop = 1
	local result = play()
	H.ok(result, "match joué")
	H.eq(result.rewards.shop, S.Buildings.GetEffects("Shop", 1).shopIncome, "revenu boutique niveau 1")
	data.buildings.Shop = 5
	local coins = data.coins
	result = play()
	H.ok(result, "second match")
	H.eq(result.rewards.shop, S.Buildings.GetEffects("Shop", 5).shopIncome, "revenu boutique niveau 5")
	local r = result.rewards
	H.eq(r.total, r.match + r.tickets + r.sponsor + r.shop + r.vip + r.event, "total = somme des revenus")
	H.eq(data.coins, coins + r.total + (result.missionReward or 0), "solde crédité du total")
	H.ok(r.total < 6500, "gain par match raisonnable même tout au maximum")
end)

H.test("un ancien profil sans Boutique la reçoit au niveau 1", function()
	H.leave(p)
	local saved = store.data["player_1"]
	saved.data.buildings.Shop = nil
	local again = H.join(1)
	local loaded = S.PlayerDataService.GetData(again)
	H.eq(loaded.buildings.Shop, 1, "boutique ajoutée")
	H.eq(loaded.buildings.Pitch, 5, "autres niveaux conservés")
end)
