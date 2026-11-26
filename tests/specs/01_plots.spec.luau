-- Terrains : un terrain unique par joueur, 6 clubs maximum, libération au départ.
local S = H.boot(MODULES)
local players = {}

H.test("6 joueurs reçoivent chacun un terrain différent", function()
	local seen = {}
	for i = 1, 6 do
		local p = H.join(1000 + i)
		players[i] = p
		local slot = S.ClubService.GetSlot(p)
		H.ok(slot, "terrain attribué au joueur " .. i)
		H.ok(slot >= 1 and slot <= 6, "numéro de terrain valide")
		H.ok(not seen[slot], "terrain " .. slot .. " attribué deux fois")
		seen[slot] = true
		H.eq(p:GetAttribute("ClubSlot"), slot, "attribut ClubSlot")
	end
end)

H.test("chaque club a un nom et apparaît dans la liste des clubs", function()
	local list = S.ClubService.GetClubList()
	H.eq(#list, 6, "clubs listés")
	for _, club in list do
		H.ok(type(club.clubName) == "string" and #club.clubName > 0, "nom du club")
		H.eq(club.division, "D7", "division de départ")
		H.eq(club.squadSize, 3, "effectif de départ")
	end
end)

H.test("le 7e joueur est refusé proprement (serveur complet)", function()
	local p = H.join(2000)
	H.ok(p.kickMessage and p.kickMessage:find("complet"), "message serveur complet")
	H.eq(S.ClubService.GetSlot(p), nil, "pas de terrain")
	H.eq(#S.ClubService.GetClubList(), 6, "toujours 6 clubs")
end)

H.test("un départ libère le terrain, qui est réattribué au suivant", function()
	local leaving = players[3]
	local freed = S.ClubService.GetSlot(leaving)
	H.leave(leaving)
	H.eq(S.ClubService.GetSlot(leaving), nil, "terrain libéré")
	H.eq(#S.ClubService.GetClubList(), 5, "5 clubs")
	local newcomer = H.join(3000)
	H.eq(S.ClubService.GetSlot(newcomer), freed, "terrain réattribué")
	players[3] = newcomer
end)

H.test("un joueur qui se reconnecte n'obtient jamais deux terrains", function()
	local p = players[1]
	local profile = S.PlayerDataService.Get(p)
	S.ClubService.OnPlayerReady(p, profile) -- second appel (double chargement)
	local count = 0
	for _, club in S.ClubService.GetClubList() do
		if club.id == "player:" .. p.UserId then
			count += 1
		end
	end
	H.eq(count, 1, "occurrences du club")
end)

H.test("la liste des clubs envoyée aux joueurs est transmissible", function()
	H.ok(#H.broadcasts > 0, "liste diffusée")
	-- H.broadcasts vérifie déjà la sérialisation ; on vérifie le dernier contenu.
	local last = H.broadcasts[#H.broadcasts]
	H.eq(last.name, "ClubsUpdated", "dernier envoi")
end)
