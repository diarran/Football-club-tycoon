-- Studio sans accès aux API : le jeu reste jouable avec un profil temporaire.
H.datastoreAvailable = false
local S = H.boot(MODULES)

H.test("profil temporaire, jeu jouable et joueur prévenu", function()
	local p = H.join(1)
	local profile = S.PlayerDataService.Get(p)
	H.ok(profile and profile.temporary, "profil temporaire")
	H.ok(S.ClubService.GetSlot(p), "terrain attribué")
	local msg = H.lastNotify(p)
	H.ok(msg and msg:find("Mode test"), "notification mode test")
	H.fire(p, "RequestUpgrade", "Pitch")
	H.eq(profile.data.buildings.Pitch, 2, "amélioration possible")
	H.leave(p)
	H.shutdown()
end)
