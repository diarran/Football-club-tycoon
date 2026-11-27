-- Staff du club (embauche validée par le serveur, effets modérés) et contrats
-- de sponsoring (offres, signature, prime par match, objectif, fin de contrat).
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local Staff, Sponsors = S.Staff, S.Sponsors

local function play(p)
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("nouveau club : postes vacants, 3 offres de sponsor, aucun contrat", function()
	local p = H.join(1)
	local data = S.PlayerDataService.GetData(p)
	for _, def in Staff.List() do
		H.eq(data.staff[def.id], 0, "poste vacant " .. def.id)
		H.ok(#def.levels >= 3 and #def.levels <= 5, "3 à 5 niveaux pour " .. def.id)
	end
	H.eq(#data.sponsors.offers, Sponsors.OFFER_COUNT, "offres")
	H.eq(#data.sponsors.contracts, 0, "contrats")
	local snapshot = S.PlayerDataService.BuildSnapshot(p)
	H.checkSerializable(snapshot, "GetSnapshot", false)
	H.eq(snapshot.sponsors.maxActive, 1, "1 contrat en D7")
	H.leave(p)
end)

H.test("embauche : prix serveur, débit unique, niveau max, poste inconnu refusé", function()
	local p = H.join(2)
	local data = S.PlayerDataService.GetData(p)
	data.missions.list = {} -- sans missions du jour (testées dans 16_daily)
	data.coins = 4000
	H.fire(p, "RequestHireStaff", "Coach")
	H.eq(data.staff.Coach, 1, "entraîneur embauché")
	H.eq(data.coins, 0, "prix lu dans Staff.lua")
	H.fire(p, "RequestHireStaff", "Coach")
	H.eq(data.staff.Coach, 1, "pas assez d'argent : rien ne change")
	H.eq(data.coins, 0, "rien débité")
	for _, bad in { "Boss", 12, nil, { "Coach" } } do
		H.fire(p, "RequestHireStaff", bad)
	end
	H.eq(data.coins, 0, "valeurs invalides ignorées")
	data.coins = 1e9
	for _ = 1, 10 do
		H.advance(1)
		H.fire(p, "RequestHireStaff", "Doctor")
	end
	H.eq(data.staff.Doctor, Staff.MaxLevel("Doctor"), "médecin au maximum")
	local spent = 0
	for level = 1, Staff.MaxLevel("Doctor") do
		spent += Staff.Get("Doctor").levels[level].cost
	end
	H.eq(data.coins, 1e9 - spent, "chaque niveau payé une seule fois")
	H.leave(p)
end)

H.test("effets : entraîneur en match, médecin sur l'énergie, recruteur au centre", function()
	local p = H.join(3)
	local data = S.PlayerDataService.GetData(p)
	local base = S.MatchService.ClubTeam(p).bonus
	data.staff.Coach = Staff.MaxLevel("Coach")
	H.eq(S.MatchService.ClubTeam(p).bonus, base + Staff.Effect(data.staff, "teamBonus"), "bonus d'équipe")
	H.ok(Staff.Effect(data.staff, "teamBonus") <= 2, "effet modéré")

	-- Médecin : récupération plus rapide.
	for _, f in data.squad do
		f.energy = 0
	end
	S.SquadService.RefreshEnergy(data)
	H.advance(60)
	S.SquadService.RefreshEnergy(data)
	local normal = data.squad[1].energy
	data.staff.Doctor = Staff.MaxLevel("Doctor")
	for _, f in data.squad do
		f.energy = 0
	end
	H.advance(60)
	S.SquadService.RefreshEnergy(data)
	H.ok(math.abs(data.squad[1].energy - normal * 1.5) < 0.01, "récupération ×1,5 au niveau max")

	-- Recruteur : repérage plus rapide.
	data.staff.Scout = Staff.MaxLevel("Scout")
	data.academy.prospects = {}
	data.academy.lastScoutAt = os.time()
	local interval = 3600 / S.Buildings.GetEffects("Academy", 1).scoutsPerHour
	H.advance(interval / 1.6 + 5)
	S.SquadService.RefreshProspects(data)
	H.eq(#data.academy.prospects, 1, "jeune repéré plus tôt")
	local fx = S.Buildings.GetEffects("Academy", 1)
	H.ok(data.academy.prospects[1].rating >= fx.ratingMin + 4, "note améliorée")
	H.leave(p)
end)

H.test("sponsor : signature, prime à chaque match, place limitée, arrêt", function()
	local p = H.join(4)
	local data = S.PlayerDataService.GetData(p)
	local offer = data.sponsors.offers[1]
	H.fire(p, "RequestSignSponsor", offer.id)
	H.eq(#data.sponsors.contracts, 1, "contrat signé")
	H.eq(#data.sponsors.offers, Sponsors.OFFER_COUNT - 1, "offre retirée")
	H.fire(p, "RequestSignSponsor", data.sponsors.offers[1].id)
	H.eq(#data.sponsors.contracts, 1, "un seul contrat en D7")
	H.fire(p, "RequestSignSponsor", 99999)
	H.fire(p, "RequestSignSponsor", "1")
	H.eq(#data.sponsors.contracts, 1, "offre inconnue refusée")

	-- La réputation du club ajoute un petit bonus aux contrats (Reputation.lua).
	local reputationBonus = S.Reputation.SponsorMultiplier(data.reputation.score)
	local result = play(p)
	H.ok(result, "match joué")
	H.eq(result.rewards.contracts, math.floor(offer.perMatch * reputationBonus + 0.5), "prime fixe du contrat")
	H.eq(data.sponsors.contracts[1].matchesLeft, offer.matches - 1, "un match de moins")

	-- Directeur commercial : +20 % au niveau max, sur les bureaux et les contrats.
	data.staff.Commercial = Staff.MaxLevel("Commercial")
	reputationBonus = S.Reputation.SponsorMultiplier(data.reputation.score)
	result = play(p)
	H.eq(result.rewards.contracts, math.floor(offer.perMatch * 1.2 * reputationBonus + 0.5), "contrat +20 %")

	H.fire(p, "RequestCancelSponsor", offer.id)
	H.eq(#data.sponsors.contracts, 0, "contrat arrêté")
	result = play(p)
	H.eq(result.rewards.contracts, 0, "plus de prime")
	H.leave(p)
end)

H.test("objectif atteint : bonus versé une fois ; contrat fini après sa durée", function()
	local p = H.join(5)
	local data = S.PlayerDataService.GetData(p)
	data.sponsors.offers[1] = {
		id = 500, brand = "Brixo", perMatch = 40, goal = "goals", target = 1, bonus = 300, matches = 3,
	}
	H.fire(p, "RequestSignSponsor", 500)
	local bonusPaid, ended = 0, false
	for _ = 1, 30 do
		local result = play(p)
		for _, b in result.sponsorBonuses do
			bonusPaid += b.coins
		end
		if #result.sponsorsEnded > 0 then
			ended = true
			break
		end
	end
	H.ok(ended, "contrat terminé")
	H.eq(#data.sponsors.contracts, 0, "plus de contrat")
	H.ok(bonusPaid == 0 or bonusPaid == 300, "bonus versé au plus une fois")
	H.leave(p)
end)

H.test("2ᵉ contrat à partir de la D4 ; montants selon la division et le prestige", function()
	H.eq(Sponsors.MaxActive(7), 1, "D7")
	H.eq(Sponsors.MaxActive(5), 1, "D5")
	H.eq(Sponsors.MaxActive(4), 2, "D4")
	H.eq(Sponsors.MaxActive(1), 2, "D1")
	local rng = Random.new(1)
	local low, high, prestige = 0, 0, 0
	for i = 1, 200 do
		low += Sponsors.GenerateOffer(rng, i, "D7", 0).perMatch
		high += Sponsors.GenerateOffer(rng, i, "D1", 0).perMatch
		prestige += Sponsors.GenerateOffer(rng, i, "D1", 10).perMatch
	end
	H.ok(high > low * 5, "plus en D1 qu'en D7")
	H.ok(prestige > high * 1.15 and prestige < high * 1.35, "prestige : au plus +25 %")
	for i = 1, 200 do
		local offer = Sponsors.GenerateOffer(rng, i, "D1", 99)
		H.ok(offer.perMatch <= S.Sponsors.BASE_PER_MATCH.D1 * 1.2 * 1.25 + 5, "prime par match plafonnée")
		H.ok(offer.matches >= offer.target, "objectif possible dans la durée")
	end
end)

H.test("offres renouvelées toutes les 4 h, même hors ligne", function()
	local p = H.join(6)
	local data = S.PlayerDataService.GetData(p)
	local firstId = data.sponsors.offers[1].id
	H.advance(Sponsors.REFRESH_SECONDS - 120)
	H.eq(data.sponsors.offers[1].id, firstId, "pas encore")
	H.clearSent()
	H.advance(180)
	H.ok(data.sponsors.offers[1].id ~= firstId, "nouvelles offres")
	H.ok(H.lastNotify(p), "le joueur est prévenu")
	H.leave(p)
	H.advance(Sponsors.REFRESH_SECONDS + 10)
	local p2 = H.join(6)
	local data2 = S.PlayerDataService.GetData(p2)
	H.ok(data2.sponsors.offers[1].id > firstId + Sponsors.OFFER_COUNT, "renouvelées au retour")
	H.leave(p2)
end)

H.test("ancien profil : staff et sponsors ajoutés, valeurs abîmées corrigées, sauvegarde", function()
	store.data["player_7"] = {
		data = {
			schemaVersion = 1,
			coins = 5000,
			club = { name = "FC Ancien", division = "D5", divisionPoints = 0 },
			buildings = {},
			squad = {},
			staff = { Coach = 99, Doctor = "x", Scout = -1 },
		},
	}
	local p = H.join(7)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.coins, 5000, "solde gardé")
	H.eq(data.staff.Coach, Staff.MaxLevel("Coach"), "niveau ramené au maximum")
	H.eq(data.staff.Doctor, 0, "valeur invalide")
	H.eq(data.staff.Scout, 0, "négatif")
	H.eq(data.staff.Commercial, 0, "poste ajouté")
	H.eq(#data.sponsors.offers, Sponsors.OFFER_COUNT, "offres créées")
	data.staff.Doctor = 2
	H.fire(p, "RequestSignSponsor", data.sponsors.offers[1].id)
	H.leave(p)
	local saved = store.data["player_7"].data
	H.eq(saved.staff.Doctor, 2, "staff sauvegardé")
	H.eq(#saved.sponsors.contracts, 1, "contrat sauvegardé")
end)

H.test("client : onglet Gestion, embauche et signature par les boutons", function()
	local p = H.join(8)
	local data = S.PlayerDataService.GetData(p)
	data.coins = 100000
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Management")
	H.flush()
	H.ok(H.findText(gui, "Le staff du club"), "titre du staff")
	H.ok(H.findText(gui, "Entraîneur · poste vacant"), "poste vacant")
	local hire = H.findText(gui, "Embaucher", "TextButton")
	H.ok(hire, "bouton embaucher")
	hire.Activated:Fire()
	H.flush()
	H.eq(data.staff.Coach, 1, "embauché par le bouton")
	UI.OpenTab("Management")
	H.flush()
	local sign = H.findText(gui, "Signer le contrat", "TextButton")
	H.ok(sign, "bouton signer")
	sign.Activated:Fire()
	H.flush()
	H.eq(#data.sponsors.contracts, 1, "contrat signé par le bouton")
	UI.OpenTab("Management")
	H.flush()
	H.ok(H.findText(gui, "Arrêter le contrat", "TextButton"), "contrat affiché")
	H.leave(p)
end)
