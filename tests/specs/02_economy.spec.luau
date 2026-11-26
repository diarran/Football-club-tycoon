-- Économie et construction : débit unique, prix serveur, valeurs client refusées.
local S = H.boot(MODULES)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

H.test("un nouveau club démarre avec le solde de départ et tout au niveau 1", function()
	H.eq(data.coins, S.Config.STARTING_COINS, "solde de départ")
	for id in S.Buildings.Definitions do
		H.eq(data.buildings[id], 1, "niveau de " .. id)
	end
end)

H.test("une amélioration débite le prix exact une seule fois", function()
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	H.fire(p, "RequestUpgrade", "Pitch")
	H.eq(data.buildings.Pitch, 2, "niveau du terrain")
	H.eq(data.coins, S.Config.STARTING_COINS - S.Buildings.GetUpgradeCost("Pitch", 1), "solde après achat")
	local msg, kind = H.lastNotify(p)
	H.eq(kind, "success", "notification " .. tostring(msg))
end)

H.test("deux clics rapides ne débitent pas deux fois", function()
	data.coins = 3000
	data.buildings.Stands = 1
	H.fire(p, "RequestUpgrade", "Stands")
	H.fire(p, "RequestUpgrade", "Stands") -- niveau 3 coûte 8 000 : refusé
	H.eq(data.coins, 0, "solde")
	H.eq(data.buildings.Stands, 2, "niveau des tribunes")
	local _, kind = H.lastNotify(p)
	H.eq(kind, "error", "second clic refusé")
end)

H.test("sans assez de FC Coins, rien n'est débité ni construit", function()
	data.coins = 100
	H.fire(p, "RequestUpgrade", "Training")
	H.eq(data.coins, 100, "solde inchangé")
	H.eq(data.buildings.Training, 1, "niveau inchangé")
end)

H.test("niveau maximum : refusé sans débit", function()
	data.coins = 100000
	data.buildings.Offices = S.Buildings.MaxLevel("Offices")
	H.fire(p, "RequestUpgrade", "Offices")
	H.eq(data.coins, 100000, "solde inchangé")
	H.eq(data.buildings.Offices, S.Buildings.MaxLevel("Offices"), "niveau inchangé")
end)

H.test("valeurs client invalides pour une amélioration : toutes refusées", function()
	H.advance(10)
	data.coins = 100000
	local before = table.clone(data.buildings)
	local bad = { nil, 42, true, {}, { "Pitch" }, "pitch", "__index", "Pitch ", string.rep("A", 10000), "Definitions" }
	for i = 1, 10 do
		H.advance(1) -- reste sous la limite de fréquence
		H.fire(p, "RequestUpgrade", bad[i])
	end
	H.eq(data.coins, 100000, "solde inchangé")
	for id, level in before do
		H.eq(data.buildings[id], level, "niveau de " .. id)
	end
end)

H.test("le client ne peut pas imposer un prix ou un montant", function()
	H.advance(10)
	data.coins = 3000
	data.buildings.LockerRoom = 1
	H.fire(p, "RequestUpgrade", "LockerRoom", -1000000, { cost = 0 })
	H.eq(data.coins, 1500, "prix serveur appliqué")
	H.eq(data.buildings.LockerRoom, 2, "niveau")
end)

H.test("EconomyService refuse les montants invalides", function()
	data.coins = 500
	for _, amount in { -10, 0 / 0, math.huge, "100", nil } do
		H.eq(S.EconomyService.TrySpend(p, amount, "test"), false, "débit de " .. tostring(amount))
		H.eq(S.EconomyService.Add(p, amount, "test"), false, "ajout de " .. tostring(amount))
	end
	H.eq(data.coins, 500, "solde inchangé")
	H.eq(S.EconomyService.TrySpend(p, 501, "test"), false, "débit supérieur au solde")
	H.eq(data.coins, 500, "jamais négatif")
end)

H.test("le solde est plafonné (garde-fou)", function()
	data.coins = S.Config.MAX_COINS - 10
	S.EconomyService.Add(p, 1000, "test")
	H.eq(data.coins, S.Config.MAX_COINS, "plafond")
end)

H.test("recrutement : prix débité une fois, joueur ajouté, effectif limité", function()
	H.advance(10)
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	data.coins = 1500
	local size = #data.squad
	H.fire(p, "RequestRecruit")
	H.fire(p, "RequestRecruit") -- plus assez d'argent
	H.eq(data.coins, 0, "solde")
	H.eq(#data.squad, size + 1, "effectif")
	local recruit = data.squad[#data.squad]
	H.ok(recruit.rating >= S.PlayerConfig.RECRUIT_RATING_MIN and recruit.rating <= S.PlayerConfig.RECRUIT_RATING_MAX, "note")
	data.coins = 1000000
	for _ = 1, 10 do
		H.advance(1)
		H.fire(p, "RequestRecruit")
	end
	H.eq(#data.squad, S.Config.MAX_SQUAD_SIZE, "effectif maximum")
	H.eq(data.coins, 1000000 - (S.Config.MAX_SQUAD_SIZE - size - 1) * S.PlayerConfig.RECRUIT_COST, "seuls les vrais recrutements sont payés")
	local ids = {}
	for _, f in data.squad do
		H.ok(not ids[f.id], "identifiant unique de joueur")
		ids[f.id] = true
	end
end)

H.test("limitation de fréquence : les demandes en rafale sont ignorées", function()
	H.advance(10)
	data.coins = 1000000
	for id in data.buildings do
		data.buildings[id] = 1
	end
	-- 20 demandes dans la même seconde : seules les 8 premières passent.
	local order = { "Pitch", "Pitch", "Stands", "Stands", "Training", "Training", "Offices", "LockerRoom" }
	for _ = 1, 20 do
		H.fire(p, "RequestUpgrade", order[1])
		table.insert(order, table.remove(order, 1))
	end
	local upgrades = 0
	for _, level in data.buildings do
		upgrades += level - 1
	end
	H.eq(upgrades, S.Config.RATE_LIMIT_MAX_REQUESTS, "améliorations acceptées")
end)

H.test("un joueur n'agit que sur son propre club", function()
	H.advance(10)
	local other = H.join(2)
	local otherData = S.PlayerDataService.GetData(other)
	local coinsBefore = otherData.coins
	data.coins = 100000
	H.fire(p, "RequestUpgrade", "Training")
	H.eq(otherData.coins, coinsBefore, "solde de l'autre club")
	H.eq(otherData.buildings.Training, 1, "installation de l'autre club")
end)
