-- Centre de formation (jeunes repérés, signature, libération) et espace VIP.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)

local function academy(level: number)
	return S.Buildings.GetEffects("Academy", level)
end

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("les deux installations existent, au niveau 1 pour un nouveau club", function()
	H.ok(S.Buildings.Get("Academy"), "centre de formation")
	H.ok(S.Buildings.Get("VIP"), "espace VIP")
	H.eq(data.buildings.Academy, 1, "centre de formation niveau 1")
	H.eq(data.buildings.VIP, 1, "espace VIP niveau 1")
	H.eq(#data.academy.prospects, 0, "aucun jeune au départ")
end)

H.test("un jeune est repéré après l'intervalle, même sans action du joueur", function()
	local interval = 3600 / academy(1).scoutsPerHour
	H.advance(interval - 60)
	H.eq(#data.academy.prospects, 0, "pas encore")
	H.clearSent()
	H.advance(120)
	H.eq(#data.academy.prospects, 1, "un jeune repéré")
	local notify = H.lastNotify(p)
	H.ok(notify, "le joueur est prévenu")
	local prospect = data.academy.prospects[1]
	local fx = academy(1)
	H.ok(prospect.rating >= fx.ratingMin and prospect.rating <= fx.ratingMax, "note dans la fourchette")
	H.ok(prospect.potential >= prospect.rating + 10, "fort potentiel")
	H.ok(prospect.age >= 16 and prospect.age <= 18, "jeune")
	H.eq(prospect.cost, fx.signCost, "prix fixé par le serveur")
	H.ok(prospect.cost < S.PlayerConfig.RECRUIT_COST, "moins cher qu'un recrutement classique")
end)

H.test("la liste d'attente est limitée et ne cumule pas d'avance", function()
	H.advance(24 * 3600) -- une journée hors ligne
	H.eq(#data.academy.prospects, academy(1).prospectSlots, "limite de places")
	data.buildings.Academy = 5
	S.SquadService.RefreshProspects(data)
	H.eq(#data.academy.prospects, academy(1).prospectSlots, "pas de rattrapage instantané")
	H.advance(3600 / academy(5).scoutsPerHour + 1)
	S.SquadService.RefreshProspects(data)
	H.eq(#data.academy.prospects, math.min(academy(5).prospectSlots, academy(1).prospectSlots + 1), "plus de places et plus souvent au niveau 5")
	data.buildings.Academy = 1
end)

H.test("signer un jeune : débit unique, ajout à l'effectif, valeurs du client ignorées", function()
	data.coins = 10000
	local prospect = data.academy.prospects[1]
	local squadBefore = #data.squad
	H.fire(p, "RequestSignProspect", "1; drop") -- type invalide
	H.fire(p, "RequestSignProspect", 999999) -- inexistant
	H.eq(data.coins, 10000, "rien débité pour une demande invalide")
	H.fire(p, "RequestSignProspect", prospect.id)
	H.eq(data.coins, 10000 - prospect.cost, "prix débité une fois")
	H.eq(#data.squad, squadBefore + 1, "jeune dans l'effectif")
	local signed = data.squad[#data.squad]
	H.eq(signed.id, prospect.id, "même joueur")
	H.ok(signed.youth, "marqué formé au club")
	H.eq(signed.energy, S.PlayerConfig.MAX_ENERGY, "en forme")
	H.fire(p, "RequestSignProspect", prospect.id)
	H.eq(data.coins, 10000 - prospect.cost, "pas de double signature")
end)

H.test("signature refusée si l'effectif est complet ou si l'argent manque", function()
	table.insert(data.academy.prospects, { id = 5000, name = "Test Jeune", age = 17, position = "MID", rating = 40, potential = 80, cost = 400 })
	while #data.squad < S.Config.MAX_SQUAD_SIZE do
		table.insert(data.squad, { id = 6000 + #data.squad, name = "Rempl", age = 25, position = "DEF", rating = 45, potential = 50, energy = 100, value = 0, salary = 0 })
	end
	data.coins = 10000
	H.fire(p, "RequestSignProspect", 5000)
	H.eq(data.coins, 10000, "effectif complet : rien débité")
	H.eq(#data.squad, S.Config.MAX_SQUAD_SIZE, "effectif inchangé")
	-- Libérer un joueur fait de la place.
	H.fire(p, "RequestRelease", data.squad[#data.squad].id)
	H.eq(#data.squad, S.Config.MAX_SQUAD_SIZE - 1, "joueur libéré")
	data.coins = 100
	H.fire(p, "RequestSignProspect", 5000)
	H.eq(#data.squad, S.Config.MAX_SQUAD_SIZE - 1, "pas assez de FC Coins")
	H.eq(data.coins, 100, "solde intact")
end)

H.test("libérer un joueur : jamais sous le minimum, identifiant vérifié", function()
	H.fire(p, "RequestRelease", "abc")
	H.fire(p, "RequestRelease", 424242)
	while #data.squad > S.Config.STARTING_PLAYERS do
		H.fire(p, "RequestRelease", data.squad[1].id)
	end
	H.fire(p, "RequestRelease", data.squad[1].id)
	H.eq(#data.squad, S.Config.STARTING_PLAYERS, "minimum conservé")
end)

H.test("les jeunes formés au club progressent plus vite", function()
	data.buildings.Academy = 5
	data.squad = {
		{ id = 1, name = "A", age = 17, position = "MID", rating = 40, potential = 99, energy = 100, value = 0, salary = 0, youth = true },
		{ id = 2, name = "B", age = 25, position = "MID", rating = 40, potential = 99, energy = 100, value = 0, salary = 0 },
	}
	data.buildings.Training = 1
	for _ = 1, 100 do
		data.squad[1].energy, data.squad[2].energy = 100, 100
		S.SquadService.ApplyMatchEffects(data)
	end
	H.ok(data.squad[1].rating > data.squad[2].rating + 20, ("jeune %d contre %d"):format(data.squad[1].rating, data.squad[2].rating))
end)

H.test("l'espace VIP ajoute un bonus de billetterie et un revenu fixe", function()
	data.squad = {}
	S.SquadService.OnPlayerReady(p, S.PlayerDataService.Get(p))
	for level = 1, 5 do
		data.buildings.VIP = level
		local result = play()
		H.ok(result, "match joué niveau " .. level)
		local fx = S.Buildings.GetEffects("VIP", level)
		local r = result.rewards
		H.eq(r.vip, math.floor(r.tickets * fx.ticketBonus) + fx.vipIncome, "revenu VIP niveau " .. level)
		H.eq(r.total, r.match + r.tickets + r.sponsor + r.shop + r.vip, "total")
	end
end)

H.test("un ancien profil reçoit les nouvelles installations et le centre de formation", function()
	H.leave(p)
	local saved = store.data["player_1"]
	saved.data.buildings.Academy = nil
	saved.data.buildings.VIP = nil
	saved.data.academy = nil
	local again = H.join(1)
	local loaded = S.PlayerDataService.GetData(again)
	H.eq(loaded.buildings.Academy, 1, "centre de formation ajouté")
	H.eq(loaded.buildings.VIP, 1, "espace VIP ajouté")
	H.ok(type(loaded.academy.prospects) == "table", "liste de jeunes créée")
	local snapshot = S.PlayerDataService.BuildSnapshot(again)
	H.ok(snapshot.prospects, "jeunes envoyés au client")
end)

H.finish()
