-- Mode Création : parcelles à débloquer, bâtiments placés, tournés, déplacés et
-- améliorés (validés par le serveur), bonus des bâtiments, décor 3D de la zone,
-- anciens profils et onglet Création.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local Campus = mock.run(MODULES.Campus)
local WorldBuilder = mock.run(MODULES.WorldBuilder)

local function play(p)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

local function campusRequest(p, ...)
	H.advance(Campus.MOVE_COOLDOWN + 1)
	H.fire(p, "RequestCampus", ...)
	local message, kind = H.lastNotify(p)
	return kind == "success", message
end

local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

H.test("catalogue : 12 parcelles et bâtiments à 3 niveaux de prix croissants, tenant dans leur carré", function()
	H.eq(#Campus.Parcels, 12, "parcelles")
	local WorldConfig = mock.run(MODULES.WorldConfig)
	H.eq(#WorldConfig.PARCELS, #Campus.Parcels, "une position 3D par parcelle")
	for index = 2, #Campus.Parcels do
		H.ok(Campus.Parcels[index].cost >= Campus.Parcels[index - 1].cost, "prix croissant parcelle " .. index)
	end
	for id, def in Campus.Definitions do
		H.eq(#def.levels, Campus.MAX_LEVEL, "niveaux de " .. id)
		for level = 2, #def.levels do
			H.ok(def.levels[level].cost > def.levels[level - 1].cost, "prix croissant " .. id)
		end
		H.ok(S.Divisions.Get(def.division), "division valide pour " .. id)
	end
	H.ok(WorldConfig.CAMPUS_FOOTPRINT.X <= math.min(WorldConfig.PARCEL_SIZE.X, WorldConfig.PARCEL_SIZE.Y), "un bâtiment tourne dans sa parcelle")
end)

H.test("nouveau club : aucune parcelle, terrain avec 12 parcelles à vendre", function()
	local p = H.join(1)
	local data = S.PlayerDataService.GetData(p)
	H.eq(Campus.ParcelCount(data.campus), 0, "aucune parcelle")
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.checkSerializable(snapshot, "GetSnapshot", false)
	H.ok(snapshot.campus and snapshot.campus.parcels, "campus dans l'instantané")
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	local zone = plot:FindFirstChild("Campus")
	H.ok(zone, "zone de création derrière le terrain")
	local forSale = 0
	for _, child in zone:GetChildren() do
		if child:GetAttribute("State") == "locked" then
			forSale += 1
		end
	end
	H.eq(forSale, 12, "12 parcelles à vendre")
	H.ok(find(zone, "ForSale"), "panneau À VENDRE")
	H.leave(p)
end)

H.test("débloquer : division, prix serveur, débit unique, valeurs invalides refusées", function()
	local p = H.join(2)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.coins = 100000
	local ok = campusRequest(p, "unlock", 1)
	H.eq(ok, false, "parcelle 1 refusée en D7")
	H.eq(data.coins, 100000, "rien débité")
	data.club.division = "D6"
	for _, bad in { 0, 13, "x", 1.5, -1, nil, math.huge } do
		H.eq(campusRequest(p, "unlock", bad), false, "valeur refusée " .. tostring(bad))
	end
	H.eq(campusRequest(p, "unlock", 3), false, "parcelle 3 réservée à la D5")
	H.eq(data.coins, 100000, "toujours rien débité")
	H.eq(campusRequest(p, "unlock", 1), true, "parcelle 1 débloquée")
	H.eq(data.coins, 100000 - Campus.Parcels[1].cost, "prix lu dans Campus.lua")
	H.eq(campusRequest(p, "unlock", 1), false, "déjà débloquée")
	H.eq(data.coins, 100000 - Campus.Parcels[1].cost, "pas de double débit")
	data.coins = 10
	H.eq(campusRequest(p, "unlock", 2), false, "pas assez de FC Coins")
	H.eq(Campus.HasParcel(data.campus, 2), false, "parcelle 2 toujours à vendre")
	H.eq(campusRequest(p, "hack", 1), false, "action inconnue refusée")
	H.leave(p)
end)

H.test("construire, améliorer, tourner, déplacer (échange) : tout vérifié par le serveur", function()
	local p = H.join(3)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.club.division = "D6"
	data.coins = 1000000
	H.eq(campusRequest(p, "build", "Esport", 1, 0), false, "parcelle non débloquée")
	campusRequest(p, "unlock", 1)
	campusRequest(p, "unlock", 2)
	H.eq(campusRequest(p, "build", "Champions", 1, 0), false, "place des champions réservée à la D4")
	H.eq(campusRequest(p, "build", "Nope", 1, 0), false, "bâtiment inconnu")
	local before = data.coins
	H.eq(campusRequest(p, "build", "Esport", 1, 45), true, "centre e-sport construit")
	H.eq(data.coins, before - Campus.Get("Esport").levels[1].cost, "prix de construction")
	H.eq(data.campus.placed.Esport.rot, 0, "orientation invalide ramenée à 0")
	H.eq(campusRequest(p, "build", "Esport", 2, 0), false, "un seul centre e-sport")
	H.eq(campusRequest(p, "build", "Museum", 1, 90), false, "parcelle occupée")
	H.eq(campusRequest(p, "build", "Museum", 2, 90), true, "musée sur la parcelle 2")
	H.eq(data.campus.placed.Museum.rot, 90, "orientation choisie")
	-- Améliorations jusqu'au niveau 3 au prix exact.
	before = data.coins
	H.eq(campusRequest(p, "upgrade", "Esport"), true, "niveau 2")
	H.eq(campusRequest(p, "upgrade", "Esport"), true, "niveau 3")
	local levels = Campus.Get("Esport").levels
	H.eq(data.coins, before - levels[2].cost - levels[3].cost, "prix des niveaux 2 et 3")
	H.eq(campusRequest(p, "upgrade", "Esport"), false, "pas de niveau 4")
	H.eq(campusRequest(p, "upgrade", "Recovery"), false, "bâtiment non construit")
	-- Tourner : un quart de tour, sans spam.
	H.eq(campusRequest(p, "rotate", "Esport"), true, "tourné")
	H.eq(data.campus.placed.Esport.rot, 90, "90°")
	H.fire(p, "RequestCampus", "rotate", "Esport")
	H.eq(data.campus.placed.Esport.rot, 90, "trop rapide : refusé")
	-- Déplacer : échange avec le musée, refus vers une parcelle verrouillée.
	before = data.coins
	H.eq(campusRequest(p, "move", "Esport", 2), true, "déplacé")
	H.eq(data.campus.placed.Esport.parcel, 2, "e-sport sur la parcelle 2")
	H.eq(data.campus.placed.Museum.parcel, 1, "musée échangé sur la parcelle 1")
	H.eq(campusRequest(p, "move", "Esport", 5), false, "parcelle verrouillée")
	H.eq(campusRequest(p, "move", "Esport", 2), false, "même parcelle")
	H.eq(data.coins, before, "déplacer et tourner sont gratuits")
	-- Décor 3D : bâtiments à leur place, au bon niveau et dans le bon sens.
	local plot = WorldBuilder.getPlot(S.ClubService.GetSlot(p))
	local parcel2 = plot.Campus:FindFirstChild("Parcel2")
	H.eq(parcel2:GetAttribute("State"), "built", "parcelle 2 construite")
	local esport = parcel2:FindFirstChild("Esport")
	H.ok(esport, "modèle du centre e-sport")
	H.eq(esport:GetAttribute("Level"), 3, "niveau 3D")
	H.eq(esport:GetAttribute("Rotation"), 90, "orientation 3D")
	H.ok(plot.Campus.Parcel1:FindFirstChild("Museum"), "musée sur la parcelle 1")
	H.ok(WorldBuilder.countParts(esport) <= 160, "budget du centre e-sport niveau 3")
	H.leave(p)
end)

H.test("bonus : revenus des matchs, sponsors, récupération et blessures", function()
	local p = H.join(4)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.club.division = "D4"
	data.coins = 10000000
	for parcel = 1, 5 do
		campusRequest(p, "unlock", parcel)
	end
	local first = play(p)
	H.eq(first.rewards.campus, 0, "aucun bonus sans bâtiment")
	for parcel, id in { "Esport", "Museum", "President", "Recovery", "Champions" } do
		H.eq(campusRequest(p, "build", id, parcel, 0), true, "construit : " .. id)
	end
	H.eq(Campus.Effect(data.campus, "matchIncome"), 140, "e-sport + place des champions (niveau 1)")
	H.eq(Campus.Effect(data.campus, "sponsorBonus"), 0.1, "bureau présidentiel")
	H.eq(Campus.Effect(data.campus, "energyRecovery"), 0.15, "centre de récupération")
	H.eq(Campus.Effect(data.campus, "injuryReduction"), 0.1, "blessures plus courtes")
	H.eq(S.StaffService.SponsorMultiplier(data), 1.1, "sponsors des bureaux +10 %")
	local result = play(p)
	local expected = math.floor(result.rewards.tickets * Campus.Effect(data.campus, "ticketBonus") + 140)
	H.eq(result.rewards.campus, expected, "revenu calculé par le serveur")
	local sum = result.rewards.match + result.rewards.tickets + result.rewards.sponsor + result.rewards.shop
		+ result.rewards.vip + result.rewards.contracts + result.rewards.event + result.rewards.campus + (result.rewards.press or 0)
	H.eq(result.rewards.total, sum, "compris dans le total")
	H.ok(result.rewards.total < 5000, "gain par match raisonnable")
	H.leave(p)
end)

H.test("bonus du 2e lot : XP d'entraînement, force en match, billets, remise sur le stade, fatigue", function()
	local p = H.join(7)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.club.division = "D2"
	data.coins = 10000000
	for parcel = 1, 5 do
		campusRequest(p, "unlock", parcel)
	end
	for parcel, id in { "SportsComplex", "IndoorPitch", "Security", "Workshop", "Depot" } do
		H.eq(campusRequest(p, "build", id, parcel, 0), true, "construit : " .. id)
	end
	H.eq(Campus.Effect(data.campus, "growthBonus"), 0.02, "complexe sportif")
	H.eq(Campus.Effect(data.campus, "teamBonus"), 0.25, "terrain couvert")
	H.eq(Campus.Effect(data.campus, "ticketBonus"), 0.04, "centre de sécurité")
	H.eq(Campus.Effect(data.campus, "upgradeDiscount"), 0.05, "atelier technique")
	H.eq(Campus.Effect(data.campus, "matchEnergy"), 0.15, "dépôt des véhicules")
	-- Remise de l'atelier : le serveur débite le prix réduit.
	local level = data.buildings.Shop or 1
	local base = S.Buildings.GetUpgradeCost("Shop", level)
	local before = data.coins
	H.fire(p, "RequestUpgrade", "Shop")
	H.eq(data.buildings.Shop, level + 1, "amélioration faite")
	H.eq(before - data.coins, Campus.DiscountedCost(data.campus, base), "prix réduit de 5 %")
	H.ok(before - data.coins < base, "moins cher qu'avant")
	-- Dépôt : chaque titulaire perd moins d'énergie par match.
	for _, f in data.squad do
		f.energy = 100
	end
	H.ok(play(p), "match joué")
	local spent = 0
	for _, f in S.SquadService.Starters(data) do
		spent = math.max(spent, 100 - f.energy)
	end
	H.ok(spent <= S.Config.ENERGY_COST_PER_MATCH * 0.85 + 0.001, ("énergie dépensée réduite : %.2f"):format(spent))
	H.leave(p)
end)

H.test("ancien profil sans campus ou campus abîmé : réparé sans erreur", function()
	local p = H.join(5)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	data.campus = nil
	store.data["player_5"] = { data = data, lock = nil }
	p = H.join(5)
	local loaded = S.PlayerDataService.GetData(p)
	H.ok(type(loaded.campus) == "table" and type(loaded.campus.parcels) == "table", "campus ajouté")
	H.leave(p)
	H.advance(5)
	data.campus = { parcels = { ["1"] = true, ["99"] = true, x = true }, placed = { Esport = { parcel = 1, level = 9, rot = 33 }, Fake = { parcel = 1 }, Museum = { parcel = 4 } } }
	store.data["player_5"] = { data = data, lock = nil }
	p = H.join(5)
	loaded = S.PlayerDataService.GetData(p)
	H.eq(loaded.campus.parcels["99"], nil, "parcelle inexistante retirée")
	H.eq(loaded.campus.parcels.x, nil, "clé invalide retirée")
	H.eq(loaded.campus.placed.Esport.level, 3, "niveau borné")
	H.eq(loaded.campus.placed.Esport.rot, 0, "orientation réparée")
	H.eq(loaded.campus.placed.Fake, nil, "bâtiment inconnu retiré")
	H.eq(loaded.campus.placed.Museum, nil, "bâtiment sur une parcelle non débloquée retiré")
	H.leave(p)
end)

H.test("onglet Création : grille des parcelles, débloquer et construire depuis le menu", function()
	local p = H.join(6, "Bâtisseur")
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {}
	data.onboarding.done = true
	data.club.division = "D6"
	data.coins = 50000
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Creation")
	H.ok(H.findText(gui, "Mode Création"), "titre de l'onglet")
	H.ok(H.findText(gui, "Parcelles débloquées : 0 / 12"), "compteur")
	H.click(gui, "1 🔒")
	H.flush()
	H.ok(H.findText(gui, "Parcelle 1 à vendre"), "fiche de la parcelle")
	H.advance(Campus.MOVE_COOLDOWN + 1)
	H.click(gui, "Débloquer")
	H.flush()
	H.eq(Campus.HasParcel(data.campus, 1), true, "parcelle débloquée par le serveur")
	H.ok(H.findText(gui, "Parcelle 1 libre"), "parcelle libre affichée")
	H.advance(Campus.MOVE_COOLDOWN + 1)
	H.click(gui, "Construire sur la parcelle 1")
	H.flush()
	H.ok(data.campus.placed.Esport, "premier bâtiment du catalogue construit")
	H.ok(H.findText(gui, "Centre e-sport · niveau 1 / 3"), "fiche du bâtiment")
	H.ok(H.findText(gui, "Tourner"), "bouton tourner")
	H.ok(H.findText(gui, "Déplacer"), "bouton déplacer")
end)
