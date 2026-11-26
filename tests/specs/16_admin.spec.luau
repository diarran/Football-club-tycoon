-- Code admin « argent illimité » : réservé au propriétaire du jeu, vérifié
-- par le serveur, jamais écrit en clair dans le dépôt, protégé contre les essais.
local S = H.boot(MODULES)
local AdminAccess = mock.run(MODULES.AdminAccess)
local AdminConfig = mock.run(MODULES.AdminConfig)
local AdminService = mock.run(MODULES.AdminService)
local sha256 = mock.run(MODULES.Sha256)

-- Le vrai code n'est pas dans le dépôt : les tests utilisent un code à eux.
local TEST_CODE = "TEST-CODE-42"
AdminConfig.CODE_SHA256 = sha256(AdminConfig.SALT .. AdminAccess.Normalize(TEST_CODE))

-- Jeu publié par le compte 100 (le propriétaire).
H.game.CreatorType = Enum.CreatorType.User
H.game.CreatorId = 100
local owner = H.join(100, "Proprio")
local other = H.join(2, "Curieux")
local ownerData = S.PlayerDataService.GetData(owner)
local otherData = S.PlayerDataService.GetData(other)
local back -- le propriétaire revenu (test de sauvegarde)

H.test("SHA-256 : résultats officiels", function()
	H.eq(sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "texte vide")
	H.eq(sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc")
	H.eq(
		sha256(string.rep("a", 1000)),
		"41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
		"plusieurs blocs"
	)
end)

H.test("qui est admin : propriétaire, liste, Studio ; pas les autres", function()
	H.ok(AdminAccess.IsAdmin(owner), "propriétaire du jeu")
	H.eq(AdminAccess.IsAdmin(other), false, "autre joueur")
	table.insert(AdminConfig.ADMIN_USER_IDS, 2)
	H.ok(AdminAccess.IsAdmin(other), "compte ajouté à la liste")
	table.remove(AdminConfig.ADMIN_USER_IDS)
	H.studio = true
	H.ok(AdminAccess.IsAdmin(other), "tout le monde dans Studio")
	H.studio = false
	H.game.CreatorId = 0
	H.eq(AdminAccess.IsAdmin(owner), false, "jeu non publié hors Studio : personne")
	H.game.CreatorId = 100
end)

H.test("le champ n'est envoyé qu'à l'admin", function()
	H.eq(S.PlayerDataService.BuildSnapshot(owner).isAdmin, true, "admin")
	H.eq(S.PlayerDataService.BuildSnapshot(other).isAdmin, false, "pas admin")
end)

H.test("code juste mais joueur non admin : refusé, même message qu'un code faux", function()
	local before = otherData.coins
	H.fire(other, "RequestAdminCode", TEST_CODE)
	H.flush()
	H.eq(otherData.admin.unlimited, false, "pas activé")
	H.eq(otherData.coins, before, "solde intact")
	H.eq(H.lastNotify(other), "Code invalide.", "message neutre")
end)

H.test("admin : le code active l'argent illimité, les achats ne coûtent rien", function()
	ownerData.coins = 1234
	H.fire(owner, "RequestAdminCode", " test code 42 ") -- minuscules/espaces acceptés
	H.flush()
	H.eq(ownerData.admin.unlimited, true, "activé")
	H.eq(ownerData.coins, S.Config.MAX_COINS, "solde au maximum")
	H.ok(H.lastNotify(owner):find("activé", 1, true), "message de confirmation")
	H.eq(S.PlayerDataService.BuildSnapshot(owner).adminUnlimited, true, "le client le sait")
	H.ok(S.EconomyService.CanAfford(owner, 1e11), "tout est abordable")
	H.ok(S.EconomyService.TrySpend(owner, 5000, "test"), "achat accepté")
	H.eq(ownerData.coins, S.Config.MAX_COINS, "rien n'est débité")
	H.eq(S.EconomyService.TrySpend(owner, -5, "test"), false, "montant invalide toujours refusé")
end)

H.test("admin : le même code désactive et rend le solde d'avant", function()
	H.advance(10)
	H.fire(owner, "RequestAdminCode", TEST_CODE)
	H.flush()
	H.eq(ownerData.admin.unlimited, false, "désactivé")
	H.eq(ownerData.coins, 1234, "solde d'avant rendu")
	H.ok(S.EconomyService.TrySpend(owner, 234, "test"), "achat normal")
	H.eq(ownerData.coins, 1000, "débit normal")
end)

H.test("essais au hasard : blocage après trop de codes faux", function()
	H.advance(10)
	for i = 1, AdminConfig.MAX_ATTEMPTS do
		H.eq(AdminService.SubmitCode(owner, "FAUX" .. i), "invalid", "code faux " .. i)
	end
	H.eq(AdminService.SubmitCode(owner, TEST_CODE), "locked", "bloqué, même avec le bon code")
	H.advance(AdminConfig.LOCK_SECONDS + 1)
	H.eq(AdminService.SubmitCode(owner, TEST_CODE), "on", "débloqué après l'attente")
	H.eq(AdminService.SubmitCode(owner, TEST_CODE), "off", "et désactivable")
end)

H.test("entrées bizarres du client : refusées sans erreur", function()
	H.advance(AdminConfig.LOCK_SECONDS + 1)
	for _, bad in { 42, {}, true, string.rep("A", 500) } do
		H.eq(AdminService.SubmitCode(owner, bad), "invalid", "refusé : " .. typeof(bad))
	end
	H.eq(#H.errors, 0, "aucune erreur")
end)

H.test("le mode illimité est sauvegardé avec le profil", function()
	H.advance(AdminConfig.LOCK_SECONDS + 1)
	H.eq(AdminService.SubmitCode(owner, TEST_CODE), "on", "activé")
	H.leave(owner)
	H.flush()
	H.advance(10)
	back = H.join(100, "Proprio")
	local data = S.PlayerDataService.GetData(back)
	H.eq(data.admin.unlimited, true, "toujours actif au retour")
	H.ok(S.EconomyService.TrySpend(back, 999, "test"), "achats gratuits")
	H.eq(data.coins, S.Config.MAX_COINS, "solde au maximum")
end)

H.test("client : champ visible pour l'admin, le HUD affiche ∞", function()
	local gui = H.startClient(MODULES, back)
	local UI = mock.run(MODULES.Client_UIController)
	H.flush()
	H.ok(H.findText(gui, "∞ FC"), "solde infini dans le HUD")
	UI.SetMenuOpen(true)
	UI.OpenTab("Settings")
	H.flush()
	H.ok(H.findText(gui, "Code admin"), "carte du code admin")
	H.advance(10)
	local box
	for _, d in gui:GetDescendants() do
		if d.Name == "AdminCodeBox" then
			box = d
		end
	end
	H.ok(box, "champ de saisie")
	box.Text = TEST_CODE
	local validate
	for _, d in gui:GetDescendants() do
		if d.Name == "AdminCodeButton" then
			validate = d
		end
	end
	validate.Activated:Fire()
	H.flush()
	H.eq(S.PlayerDataService.GetData(back).admin.unlimited, false, "désactivé depuis l'interface")
	H.eq(box.Text, "", "le code est effacé du champ")
end)
