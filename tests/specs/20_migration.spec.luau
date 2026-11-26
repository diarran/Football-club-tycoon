-- Profils enregistrés avant les nouveautés de la PR #15 à #22 (version testée
-- dans Studio) : ils se chargent sans erreur, gardent leur progression et
-- reçoivent les nouveaux champs avec des valeurs sûres.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)

-- Champs ajoutés après la version testée dans Studio (PR #14).
local NEW_FIELDS = {
	"purchases", "boost", "admin", "community", "friends", "staff", "sponsors",
	"daily", "missions", "season", "lastSeenAt",
}

-- Fabrique un profil « ancien » : un vrai profil dont on retire les nouveautés.
local function oldProfile(userId: number)
	local p = H.join(userId)
	local data = H.deepCopy(S.PlayerDataService.GetData(p))
	H.leave(p)
	H.advance(5)
	for _, key in NEW_FIELDS do
		data[key] = nil
	end
	data.club.stats.seasonsWon = nil
	data.coins = 12345
	data.club.division = "D4"
	data.club.divisionPoints = 7
	data.buildings.Stands = 3
	store.data["player_" .. userId] = { data = data, lock = nil }
	return data
end

H.test("ancien profil : progression gardée, nouveaux champs ajoutés, aucune erreur", function()
	oldProfile(901)
	H.warnings = {}
	H.advance(2 * 24 * 3600) -- le joueur revient deux jours plus tard
	local p = H.join(901)
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	H.eq(data.club.division, "D4", "division gardée")
	H.eq(data.buildings.Stands, 3, "tribunes gardées")
	H.eq(data.coins, 12345, "solde gardé")
	for id in S.Staff.Definitions do
		H.eq(data.staff[id], 0, "poste vacant : " .. id)
	end
	H.eq(type(data.sponsors.contracts), "table", "contrats")
	H.eq(data.friends.rewardsGiven, 0, "primes d'invitation")
	H.eq(data.admin.unlimited, false, "pas d'argent illimité")
	H.eq(data.boost.multiplier, 1, "pas de boost")
	H.eq(data.club.stats.seasonsWon, 0, "saisons gagnées")
	H.ok(p:GetAttribute("ClubSlot"), "terrain attribué")
	H.ok(H.received(p, "ProfileUpdated"), "instantané envoyé")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	H.leave(p)
end)

H.test("ancien profil : pas de revenus hors ligne inventés", function()
	oldProfile(903)
	H.advance(30 * 24 * 3600)
	local p = H.join(903)
	H.flush()
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.coins, 12345, "solde inchangé")
	H.leave(p)
end)

H.test("ancien profil : le client affiche tous les onglets sans erreur", function()
	oldProfile(904)
	local p = H.join(904)
	H.flush()
	local gui = H.startClient(MODULES, p)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	for _, tab in { "Home", "Stadium", "Squad", "Management", "Matches", "Ranking", "Prestige", "Settings" } do
		UI.OpenTab(tab)
		H.flush()
	end
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, "Cadeau du jour"), "carte du cadeau")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)
