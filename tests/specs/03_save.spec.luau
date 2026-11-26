-- Sauvegarde : profil persistant, reconnexion, verrou de session, pannes du DataStore.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)
local function record(userId)
	return store.data["player_" .. userId]
end

H.test("un profil est créé, sauvegardé au départ et le verrou est libéré", function()
	local p = H.join(10)
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	H.ok(not S.PlayerDataService.Get(p).temporary, "profil réel (pas temporaire)")
	H.ok(record(10) and record(10).lock, "verrou posé au chargement")
	H.fire(p, "RequestUpgrade", "Pitch")
	H.leave(p)
	local saved = record(10)
	H.eq(saved.lock, nil, "verrou libéré")
	H.eq(saved.data.coins, 2500, "solde sauvegardé")
	H.eq(saved.data.buildings.Pitch, 2, "niveau sauvegardé")
	H.eq(saved.data.schemaVersion, S.Config.DATA_SCHEMA_VERSION, "version du schéma")
	H.eq(S.PlayerDataService.Get(p), nil, "profil déchargé")
end)

H.test("à la reconnexion, toute la progression est retrouvée", function()
	local before = H.deepCopy(record(10).data)
	local p = H.join(10)
	local data = S.PlayerDataService.GetData(p)
	H.eq(data.coins, before.coins, "solde")
	H.eq(data.club.name, before.club.name, "nom du club")
	H.eq(data.buildings.Pitch, 2, "installation")
	H.eq(#data.squad, #before.squad, "effectif")
	for i, f in before.squad do
		H.eq(data.squad[i].name, f.name, "joueur " .. i)
		H.eq(data.squad[i].rating, f.rating, "note du joueur " .. i)
	end
	H.eq(data.nextPlayerId, before.nextPlayerId, "compteur d'identifiants")
	H.leave(p)
end)

H.test("sauvegarde automatique toutes les 120 secondes", function()
	local p = H.join(11)
	local data = S.PlayerDataService.GetData(p)
	data.coins = 4242
	H.advance(S.Config.AUTOSAVE_INTERVAL_SECONDS + 1)
	H.eq(record(11).data.coins, 4242, "solde sauvegardé automatiquement")
	H.ok(record(11).lock, "verrou conservé pendant la partie")
	H.leave(p)
end)

H.test("le profil sauvegardé respecte les règles du DataStore Roblox", function()
	local p = H.join(12)
	H.fire(p, "RequestRecruit")
	S.PlayerDataService.Save(p)
	H.checkSerializable(record(12), "profil", true) -- lève une erreur sinon
	H.leave(p)
end)

H.test("pannes passagères du DataStore au chargement : nouvelles tentatives", function()
	store.failNext = 2
	local p = H.join(13)
	H.advance(30)
	H.ok(S.PlayerDataService.GetData(p), "profil chargé après les pannes")
	H.eq(p.kickMessage, nil, "pas expulsé")
	H.leave(p)
end)

H.test("panne durable du DataStore : le joueur est prévenu, rien n'est écrasé", function()
	store.data.player_14 = { data = { schemaVersion = 1, coins = 777 } }
	store.failNext = 100
	local p = H.join(14)
	H.advance(60)
	store.failNext = 0
	H.ok(p.kickMessage and p.kickMessage:find("charger"), "message d'erreur de chargement")
	H.eq(record(14).data.coins, 777, "ancienne progression intacte")
end)

H.test("profil ouvert sur un autre serveur : pas de double session", function()
	store.data.player_15 = {
		data = { schemaVersion = 1, coins = 9999 },
		lock = { jobId = "autre-serveur", time = os.time() },
	}
	local p = H.join(15)
	H.advance(60)
	H.ok(p.kickMessage and p.kickMessage:find("autre serveur"), "message de session ouverte ailleurs")
	H.eq(record(15).lock.jobId, "autre-serveur", "verrou de l'autre serveur respecté")
	H.eq(record(15).data.coins, 9999, "données intactes")
end)

H.test("verrou abandonné (serveur planté) : le profil est récupéré", function()
	store.data.player_16 = {
		data = { schemaVersion = 1, coins = 1234 },
		lock = { jobId = "serveur-plante", time = os.time() - 3600 },
	}
	local p = H.join(16)
	H.advance(1)
	local data = S.PlayerDataService.GetData(p)
	H.ok(data, "profil chargé")
	H.eq(data.coins, 1234, "progression retrouvée")
	H.ok(data.club.name, "champs manquants complétés (nom du club)")
	H.eq(data.buildings.Stands, 1, "champs manquants complétés (installations)")
	H.eq(#data.squad, 3, "effectif de départ créé")
	H.leave(p)
end)

H.test("une sauvegarde n'écrase pas un profil repris par un autre serveur", function()
	local p = H.join(17)
	local data = S.PlayerDataService.GetData(p)
	data.coins = 1
	store.data.player_17.lock = { jobId = "autre-serveur", time = os.time() }
	store.data.player_17.data = { schemaVersion = 1, coins = 5555 }
	S.PlayerDataService.Save(p)
	H.eq(record(17).data.coins, 5555, "données de l'autre serveur conservées")
	store.data.player_17.lock = nil
	H.leave(p)
end)

H.test("départ pendant le chargement : rien ne reste bloqué", function()
	store.failNext = 1
	local p = H.join(18) -- le chargement attend (nouvelle tentative)
	H.leave(p)
	H.advance(30)
	H.eq(S.PlayerDataService.Get(p), nil, "aucun profil fantôme")
	H.eq(S.ClubService.GetSlot(p), nil, "aucun terrain fantôme")
	local r = record(18)
	H.ok(r == nil or r.lock == nil, "verrou libéré")
end)

H.test("fermeture du serveur : tous les profils sont sauvegardés et libérés", function()
	local a, b = H.join(20), H.join(21)
	S.PlayerDataService.GetData(a).coins = 111
	S.PlayerDataService.GetData(b).coins = 222
	H.shutdown()
	H.eq(record(20).data.coins, 111, "joueur A sauvegardé")
	H.eq(record(21).data.coins, 222, "joueur B sauvegardé")
	H.eq(record(20).lock, nil, "verrou A libéré")
	H.eq(record(21).lock, nil, "verrou B libéré")
end)
