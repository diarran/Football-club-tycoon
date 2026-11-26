-- Divisions D4 à D1 : clubs fictifs, primes croissantes, transferts, classement.
local S = H.boot(MODULES)
local D = S.Divisions
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)

local function play(opponent)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", opponent, "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("7 divisions de D7 à D1 : adversaires, primes et marché de plus en plus forts", function()
	H.eq(#D.List, 7, "nombre de divisions")
	H.eq(D.List[#D.List].id, "D1", "D1 en haut")
	H.eq(D.List[#D.List].pointsToPromote, nil, "pas de montée depuis D1")
	for i = 2, #D.List do
		local a, b = D.List[i - 1], D.List[i]
		H.ok(b.opponentRating > a.opponentRating, "adversaires plus forts en " .. b.id)
		H.ok(b.rewardMultiplier >= a.rewardMultiplier, "prime de match croissante en " .. b.id)
		H.ok(b.promotionReward >= a.promotionReward, "prime de montée croissante en " .. b.id)
		if a.pointsToPromote and b.pointsToPromote then
			H.ok(b.pointsToPromote > a.pointsToPromote, "seuil croissant en " .. b.id)
		end
		if a.transfer and b.transfer then
			H.ok(b.transfer.cost > a.transfer.cost and b.transfer.ratingMax > a.transfer.ratingMax, "marché " .. b.id)
		end
	end
	H.eq(D.Get("D7").transfer, nil, "pas de transfert en D7")
	H.eq(D.Get("D6").transfer, nil, "pas de transfert en D6")
end)

H.test("clubs fictifs : noms fixes et distincts, notes autour de la division", function()
	for _, division in D.List do
		local names = {}
		for i, rival in D.GetRivals(division.id) do
			H.eq(D.GetRival(division.id, i).name, rival.name, "nom stable")
			H.ok(not names[rival.name], "nom unique dans " .. division.id)
			names[rival.name] = true
			H.ok(math.abs(rival.rating - division.opponentRating) <= 4, "note proche de la division")
		end
	end
	H.eq(#D.GetSuggestedRivals("D4", 0), 3, "3 clubs fictifs sans clubs humains")
	H.eq(#D.GetSuggestedRivals("D4", 1), 2, "un club humain remplace un club fictif")
	H.eq(#D.GetSuggestedRivals("D4", 5), 1, "toujours au moins un club fictif")
	H.eq(D.ParseRivalId("ai"), D.DEFAULT_RIVAL, "ancien identifiant")
	H.eq(D.ParseRivalId("ai:1"), 1, "club fictif 1")
	for _, bad in { "ai:0", "ai:9", "ai:12", "ai:-1", "AI:1", 3 } do
		H.eq(D.ParseRivalId(bad), nil, "refusé : " .. tostring(bad))
	end
end)

H.test("match contre un club fictif : prime selon la division et la force de l'adversaire", function()
	data.club.division = "D3"
	local division = D.Get("D3")
	for _, index in { 1, 5 } do
		local rival = D.GetRival("D3", index)
		local result = play(rival.id)
		H.ok(result, "match joué contre " .. rival.id)
		H.eq(result.awayName, rival.name, "nom du club fictif")
		local expected = math.floor(S.Config.Rewards[result.outcome] * division.rewardMultiplier * rival.rewardFactor + 0.5)
		H.eq(result.rewards.match, expected, "prime de match calculée par le serveur")
	end
	H.ok(D.GetRival("D3", 1).rewardFactor > D.GetRival("D3", 5).rewardFactor, "le plus fort rapporte plus")
	local played = data.club.stats.played
	H.ok(not play("ai:9"), "club fictif inconnu refusé")
	H.eq(data.club.stats.played, played, "aucun match compté")
	data.club.division = "D7"
end)

H.test("transfert : fermé avant la D5 et tant que l'effectif n'est pas complet", function()
	data.coins = 1000000
	H.fire(p, "RequestTransfer")
	H.eq(data.coins, 1000000, "rien débité en D7")
	H.eq(select(2, H.lastNotify(p)), "error", "refus en D7")
	data.club.division = "D5"
	H.advance(1)
	H.fire(p, "RequestTransfer")
	H.eq(data.coins, 1000000, "rien débité, effectif incomplet")
end)

H.test("transfert : remplace le moins bien noté, au même poste, par un meilleur joueur", function()
	while #data.squad < S.Config.MAX_SQUAD_SIZE do
		H.advance(1)
		H.fire(p, "RequestRecruit")
	end
	local market = D.Get("D5").transfer
	for _, f in data.squad do
		f.rating = 40
	end
	data.squad[2].rating = 30
	local weakest = data.squad[2]
	local coins = data.coins
	H.advance(1)
	H.fire(p, "RequestTransfer")
	H.eq(data.coins, coins - market.cost, "prix du marché débité une fois")
	H.eq(#data.squad, S.Config.MAX_SQUAD_SIZE, "effectif toujours complet")
	local newcomer = data.squad[2]
	H.ok(newcomer ~= weakest, "joueur remplacé")
	H.eq(newcomer.position, weakest.position, "même poste")
	H.ok(newcomer.rating >= market.ratingMin and newcomer.rating <= market.ratingMax, "note du marché")
	H.ok(newcomer.potential <= newcomer.rating + market.potentialBonusMax, "potentiel limité")
	local ids = {}
	for _, f in data.squad do
		H.ok(not ids[f.id], "identifiant unique")
		ids[f.id] = true
	end
end)

H.test("transfert : refusé sans débit si la division n'a pas mieux, ou sans assez d'argent", function()
	for _, f in data.squad do
		f.rating = 90
	end
	local coins = data.coins
	H.advance(1)
	H.fire(p, "RequestTransfer")
	H.eq(data.coins, coins, "rien débité : effectif déjà meilleur")
	for _, f in data.squad do
		f.rating = 40
	end
	data.coins = 10
	H.advance(1)
	H.fire(p, "RequestTransfer")
	H.eq(data.coins, 10, "rien débité : pas assez d'argent")
	H.eq(select(2, H.lastNotify(p)), "error", "refus notifié")
end)

H.test("écrans : classement de division avec clubs fictifs, adversaires et bouton de transfert", function()
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Ranking")
	H.flush()
	H.ok(H.findText(gui, "Classement de la Division 5"), "titre du classement de division")
	H.ok(H.findText(gui, "Montée dès " .. D.Get("D5").pointsToPromote), "règle de montée")
	local top = D.GetRival("D5", 1)
	H.ok(H.findText(gui, "1. " .. top.name), "club fictif en tête")
	UI.OpenTab("Matches")
	H.flush()
	H.ok(H.findText(gui, D.GetRival("D5", D.DEFAULT_RIVAL).name), "club fictif proposé en match")
	UI.OpenTab("Squad")
	H.flush()
	for _, f in data.squad do
		f.rating = 40
	end
	data.coins = 1000000
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	UI.OpenTab("Squad")
	H.flush()
	local coins = data.coins
	H.click(gui, "Transfert")
	H.eq(data.coins, coins - D.Get("D5").transfer.cost, "transfert payé depuis le bouton")
end)

H.test("transferts sauvegardés : le nouveau joueur reste après reconnexion", function()
	data.coins = 1000000
	H.advance(1)
	H.fire(p, "RequestTransfer")
	local ids = {}
	for _, f in data.squad do
		table.insert(ids, f.id)
	end
	H.leave(p)
	p = H.join(1, "Testeur")
	data = S.PlayerDataService.GetData(p)
	for i, f in data.squad do
		H.eq(f.id, ids[i], "joueur " .. i .. " sauvegardé")
	end
	H.eq(data.club.division, "D5", "division sauvegardée")
end)
