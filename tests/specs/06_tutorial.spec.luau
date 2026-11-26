-- Tutoriel et renommage : étapes validées par le serveur, nom filtré.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local p = H.join(1)
local data = S.PlayerDataService.GetData(p)
local Steps = mock.run(MODULES.TutorialSteps)

H.test("le client ne peut pas valider une étape serveur ni sauter d'étape", function()
	H.fire(p, "RequestTutorialStep", "FirstUpgrade")
	H.fire(p, "RequestTutorialStep", "SeeRewards")
	H.fire(p, "RequestTutorialStep", 12)
	H.eq(data.tutorial.step, 1, "étape inchangée")
end)

H.test("parcours complet du tutoriel", function()
	H.fire(p, "RequestTutorialStep", "DiscoverPlot")
	H.fire(p, "RequestTutorialStep", "OpenMenu")
	H.fire(p, "RequestTutorialStep", "CheckSquad")
	H.eq(Steps[data.tutorial.step].id, "FirstUpgrade", "étape amélioration")
	H.fire(p, "RequestTutorialStep", "FirstUpgrade")
	H.eq(Steps[data.tutorial.step].id, "FirstUpgrade", "le client ne valide pas l'amélioration")
	H.fire(p, "RequestUpgrade", "Training")
	H.eq(Steps[data.tutorial.step].id, "FirstMatch", "amélioration validée par le serveur")
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	H.fire(p, "RequestMatch", "ai", "Balanced")
	H.eq(Steps[data.tutorial.step].id, "SeeRewards", "match validé par le serveur")
end)

H.test("après une déconnexion, le tutoriel reprend au bon endroit", function()
	H.leave(p)
	p = H.join(1)
	data = S.PlayerDataService.GetData(p)
	H.eq(Steps[data.tutorial.step].id, "SeeRewards", "étape conservée")
	H.fire(p, "RequestTutorialStep", "SeeRewards")
	H.eq(data.tutorial.completed, true, "tutoriel terminé")
end)

H.test("une vraie action faite en avance fait avancer le tutoriel", function()
	local q = H.join(50)
	local d = S.PlayerDataService.GetData(q)
	H.fire(q, "RequestUpgrade", "Pitch") -- encore à l'étape 1
	H.eq(Steps[d.tutorial.step].id, "FirstMatch", "étapes précédentes considérées comme faites")
	H.fire(q, "RequestTutorialStep", "DiscoverPlot")
	H.eq(Steps[d.tutorial.step].id, "FirstMatch", "pas de retour en arrière")
	H.leave(q)
end)

H.test("renommage du club : nom valide accepté et sauvegardé", function()
	H.fire(p, "RequestRename", "  FC   Les Lions  ")
	H.eq(data.club.name, "FC Les Lions", "nom nettoyé")
	H.eq(p:GetAttribute("ClubName"), "FC Les Lions", "attribut")
	S.PlayerDataService.Save(p)
	H.eq(store.data.player_1.data.club.name, "FC Les Lions", "nom sauvegardé")
end)

H.test("renommage : noms invalides ou filtrés refusés", function()
	for _, bad in { "AB", string.rep("x", 25), 42, {}, nil, "   ", "Club interdit" } do
		H.advance(1)
		H.fire(p, "RequestRename", bad)
	end
	H.eq(data.club.name, "FC Les Lions", "nom inchangé")
	H.filterFails = true
	H.advance(1)
	H.fire(p, "RequestRename", "Nouveau Nom")
	H.filterFails = false
	H.eq(data.club.name, "FC Les Lions", "filtrage indisponible : refusé")
end)

H.test("instantané envoyé au client (GetSnapshot) complet et transmissible", function()
	local snap = H.invoke(p, "GetSnapshot")
	H.ok(snap, "instantané")
	H.checkSerializable(snap, "snapshot", false)
	H.eq(snap.coins, data.coins, "solde")
	H.eq(snap.club.name, data.club.name, "nom")
	H.ok(snap.matchCooldown >= 0, "délai de match")
	-- Modifier la copie du client ne touche pas le serveur.
	snap.coins = 1e9
	H.ok(data.coins ~= 1e9, "données serveur protégées")
end)
