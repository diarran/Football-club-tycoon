-- Endurance avant le test dans Studio : 6 joueurs jouent pendant une longue
-- session avec toutes les nouveautés (staff, sponsors, défis, matchs amicaux,
-- missions, saisons, classement mondial), passent minuit et lundi, partent et
-- reviennent. Aucune erreur, et les DataStore restent sous les limites Roblox.
local S = H.boot(MODULES)
local store = H.getStore(S.Config.DATASTORE_NAME)

local function hasWarning(fragment: string): string?
	for _, w in H.warnings do
		if string.find(w, fragment, 1, true) then
			return w
		end
	end
	return nil
end

-- Écritures DataStore (profils, parrainages, classements) faites jusqu'ici.
local function totalWrites(): number
	local total = 0
	for _, s in H.stores do
		total += s.writes
	end
	for _, s in H.orderedStores do
		total += s.writes
	end
	return total
end

local function totalSortedReads(): number
	local total = 0
	for _, s in H.orderedStores do
		total += s.reads
	end
	return total
end

local players = {}
for i = 1, 6 do
	players[i] = H.join(700 + i, "Club" .. i)
end
H.flush()

-- Une « minute » de jeu : chaque club fait quelque chose.
local function playMinute(minute: number)
	for i, p in players do
		if p.Parent then
			local data = S.PlayerDataService.GetData(p)
			if data and minute % 2 == i % 2 then
				H.fire(p, "RequestMatch", "ai", "Balanced")
			elseif data then
				local actions = {
					function()
						H.fire(p, "RequestUpgrade", "Shop")
					end,
					function()
						H.fire(p, "RequestHireStaff", "Doctor")
					end,
					function()
						local offer = data.sponsors.offers[1]
						if offer then
							H.fire(p, "RequestSignSponsor", offer.id)
						end
					end,
					function()
						local target = players[(i % 6) + 1]
						H.fire(p, "RequestChallenge", "player:" .. target.UserId, 0)
					end,
					function()
						H.fire(p, "RequestRecruit")
					end,
				}
				actions[(minute + i) % #actions + 1]()
			end
		end
	end
	-- Les défis reçus sont acceptés.
	for _, p in players do
		local list = H.received(p, "ChallengeUpdated")
		local last = list[#list] and list[#list][1]
		for _, challenge in (last and last.incoming) or {} do
			H.fire(p, "RequestChallengeResponse", challenge.id, true)
		end
	end
	H.advance(60)
end

H.test("longue session à 6 : aucune erreur, DataStore sous les limites Roblox", function()
	H.warnings = {}
	for _, p in players do
		S.PlayerDataService.GetData(p).coins = 200000
	end
	local writesBefore = totalWrites()
	local readsBefore = totalSortedReads()
	local minutes = 30
	for minute = 1, minutes do
		playMinute(minute)
	end
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
	local bad = hasWarning("[Net] Erreur") or hasWarning("[Main]")
	H.ok(not bad, "avertissement : " .. tostring(bad))
	-- Roblox : écritures = 60 + 10 × joueurs par minute ; GetSortedAsync = 5 + 2 × joueurs.
	local perMinute = (totalWrites() - writesBefore) / minutes
	H.ok(perMinute <= (60 + 10 * 6) / 4, ("écritures par minute : %.1f (limite 120)"):format(perMinute))
	local readsPerMinute = (totalSortedReads() - readsBefore) / minutes
	H.ok(readsPerMinute <= (5 + 2 * 6) / 4, ("lectures de classement par minute : %.1f (limite 17)"):format(readsPerMinute))
	for _, p in players do
		local data = S.PlayerDataService.GetData(p)
		H.ok(data.coins == data.coins and data.coins >= 0, "solde valide")
		H.ok(data.club.stats.played > 0, "matchs joués")
	end
end)

H.test("minuit et lundi passés en pleine partie : missions, cadeau et saison renouvelés", function()
	H.warnings = {}
	local p = players[1]
	local data = S.PlayerDataService.GetData(p)
	local season = data.season.id
	local day = S.Daily.Day(os.time())
	H.advance(8 * 24 * 3600) -- une semaine et un jour : nouvelle saison, nouveau jour
	playMinute(1)
	H.ok(S.Daily.Day(os.time()) > day, "nouveau jour")
	H.ok(data.missions.day == S.Daily.Day(os.time()), "missions du jour renouvelées")
	H.ok(data.season.id ~= season, "nouvelle saison")
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)

H.test("départ et retour sur le même serveur : profil, staff et contrats intacts", function()
	local p = players[2]
	local data = S.PlayerDataService.GetData(p)
	local doctor = data.staff.Doctor
	local contracts = #data.sponsors.contracts
	local played = data.club.stats.played
	H.leave(p)
	H.advance(10)
	local back = H.join(p.UserId, p.Name)
	H.flush()
	players[2] = back
	local again = S.PlayerDataService.GetData(back)
	H.ok(again, "profil rechargé")
	H.eq(again.staff.Doctor, doctor, "médecin")
	H.eq(#again.sponsors.contracts, contracts, "contrats")
	H.eq(again.club.stats.played, played, "matchs")
	H.ok(back:GetAttribute("ClubSlot"), "terrain attribué")
	H.eq(#H.errors, 0, "erreurs")
end)

H.test("fermeture du serveur : tous les profils enregistrés, sans erreur", function()
	H.warnings = {}
	H.shutdown()
	for _, p in players do
		local record = store.data["player_" .. p.UserId]
		H.ok(record and record.data and record.data.club.stats.played > 0, "profil enregistré " .. p.UserId)
	end
	H.eq(#H.errors, 0, "erreurs : " .. tostring(H.errors[1]))
end)
