-- Jeu publié (hors Studio) : la progression est toujours sauvegardée, même si
-- le DataStore a un raté au démarrage du serveur. Pas de « mode test ».
H.studio = false
local store = H.getStore("PlayerProfiles_v1")
store.failNext = 1 -- la vérification de démarrage échoue une fois
local S = H.boot(MODULES)

H.test("jeu publié : panne au démarrage, profil réel et sauvegardé", function()
	local p = H.join(30)
	local profile = S.PlayerDataService.Get(p)
	H.ok(profile and not profile.temporary, "profil réel (pas de mode test)")
	local msg = H.lastNotify(p)
	H.ok(not (msg and msg:find("Mode test")), "pas de message « mode test »")
	H.fire(p, "RequestUpgrade", "Pitch")
	H.leave(p)
	local saved = store.data["player_30"]
	H.ok(saved and saved.data, "profil écrit dans le DataStore")
	H.eq(saved.data.buildings.Pitch, 2, "amélioration sauvegardée")
	H.shutdown()
end)
