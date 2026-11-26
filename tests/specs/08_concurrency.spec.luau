-- Situations simultanées : arrivées groupées, départs/retours rapides, matchs croisés.
-- Le DataStore répond ici avec un délai, comme en vrai.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
H.datastoreLatency = 0.5

H.test("6 joueurs arrivent presque en même temps : 6 terrains différents", function()
	local players = {}
	for i = 1, 6 do
		players[i] = H.join(100 + i)
		H.advance(0.1)
	end
	H.advance(5)
	local seen = {}
	for i, p in players do
		local slot = S.ClubService.GetSlot(p)
		H.ok(slot, "terrain du joueur " .. i)
		H.ok(not seen[slot], "terrain " .. tostring(slot) .. " en double")
		seen[slot] = true
	end
	for _, p in players do
		H.leave(p)
	end
	H.advance(5)
end)

H.test("un joueur quitte puis revient tout de suite : aucune progression perdue", function()
	local p = H.join(200)
	H.advance(2)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	H.fire(p, "RequestUpgrade", "Pitch")
	H.eq(data.buildings.Pitch, 2, "amélioration faite")
	store.failNext = 1 -- la sauvegarde de départ échoue une fois et réessaie
	H.leave(p)
	H.advance(0.2)
	local back = H.join(200) -- revient pendant que la sauvegarde est en cours
	H.advance(20)
	local again = S.PlayerDataService.GetData(back)
	H.ok(again, "profil rechargé")
	H.eq(again.buildings.Pitch, 2, "amélioration retrouvée")
	H.eq(again.coins, S.Config.STARTING_COINS - S.Buildings.GetUpgradeCost("Pitch", 1), "solde retrouvé")
	H.advance(S.Config.AUTOSAVE_INTERVAL_SECONDS + 5)
	local r = store.data.player_200
	H.eq(r.data.buildings.Pitch, 2, "sauvegarde correcte")
	H.ok(r.lock, "verrou de la nouvelle session conservé")
	H.leave(back)
	H.advance(20)
end)

H.test("départ juste après un achat : l'achat est sauvegardé", function()
	local p = H.join(300)
	H.advance(2)
	H.fire(p, "RequestRecruit")
	H.leave(p)
	H.advance(20)
	local r = store.data.player_300
	H.eq(#r.data.squad, 4, "recrue sauvegardée")
	H.eq(r.data.coins, S.Config.STARTING_COINS - S.PlayerConfig.RECRUIT_COST, "débit sauvegardé")
	H.eq(r.lock, nil, "verrou libéré")
end)

H.test("sauvegarde automatique pendant un départ : le verrou ne reste pas bloqué", function()
	local p = H.join(350)
	H.advance(2)
	H.leave(p) -- la sauvegarde de départ est en cours…
	H.task.spawn(S.PlayerDataService.Save, p, false) -- …et l'autosave tombe au même moment
	H.advance(20)
	H.eq(store.data.player_350.lock, nil, "verrou libéré (le joueur peut rejoindre un autre serveur)")
end)

H.test("une sauvegarde qui échoue temporairement finit par passer", function()
	local p = H.join(400)
	H.advance(2)
	S.PlayerDataService.GetData(p).coins = 31337
	store.failNext = 2
	H.leave(p)
	H.advance(30)
	H.eq(store.data.player_400.data.coins, 31337, "sauvegarde réussie après les échecs")
end)

H.test("deux clubs lancent un match l'un contre l'autre en même temps", function()
	local a, b = H.join(501), H.join(502)
	H.advance(2)
	local da, db = S.PlayerDataService.GetData(a), S.PlayerDataService.GetData(b)
	local coinsA, coinsB = da.coins, db.coins
	H.fire(a, "RequestMatch", "player:502", "Offensive")
	H.fire(b, "RequestMatch", "player:501", "Defensive")
	local ra, rb = H.received(a, "MatchResult"), H.received(b, "MatchResult")
	H.eq(#ra, 1, "résultat pour A")
	H.eq(#rb, 1, "résultat pour B")
	H.eq(da.club.stats.played, 1, "A : un match")
	H.eq(db.club.stats.played, 1, "B : un match")
	H.eq(da.coins, coinsA + ra[1][1].rewards.total, "A : sa récompense seulement")
	H.eq(db.coins, coinsB + rb[1][1].rewards.total, "B : sa récompense seulement")
	H.leave(a)
	H.leave(b)
	H.advance(20)
end)
