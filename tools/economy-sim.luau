--[[
	economy-sim.luau — simulateur de progression économique (hors Studio).

	Lancé par tools/economy-sim.js, qui l'assemble comme un fichier de test :
	il tourne donc sur le VRAI code du jeu (services serveur, config, matchs,
	sauvegarde) avec une horloge simulée. Rien n'est recopié : si la config
	ou une règle change, le simulateur le voit tout de suite.

	Chaque « joueur type » (PROFILS ci-dessous) enchaîne des sessions :
	- il se connecte (chargement du profil sauvegardé) ;
	- il achète ce qui est abordable, du moins cher au plus cher
	  (améliorations et recrues), puis lance un match dès que le délai le permet ;
	- il se déconnecte (sauvegarde), puis revient après une pause hors ligne.

	Le simulateur ne lit les installations et leurs niveaux que dans
	Buildings.Definitions : ajouter des niveaux ne demande aucun changement ici.

	Fin de partie : une fois en D1 avec tout acheté, le joueur continue et
	achète la personnalisation (Cosmetics.lua, la moins chère d'abord). Le
	rapport dit combien d'heures après la D1 il reste des choses à acheter.

	Variables fournies par economy-sim.js : SIM_RUNS (parties par profil).
]]

local S = H.boot(MODULES)
local Config, Buildings, Divisions, PlayerConfig = S.Config, S.Buildings, S.Divisions, S.PlayerConfig
local Cosmetics = S.Cosmetics
local RUNS = SIM_RUNS or 40
local print = H.realPrint -- les print du jeu restent dans le journal du harnais

-- Joueurs types -------------------------------------------------------------
-- sessionMinutes : durée d'une session ; pauseHours : temps hors ligne entre deux.
-- matchEvery : secondes entre deux matchs (le joueur ne joue pas forcément dès
-- la fin du délai : il regarde le résultat, se promène, achète…).
local PROFILS = {
-- postSessions : sessions jouées au plus après la D1 (phase de fin de partie).
	{ id = "actif", label = "Joueur actif", sessionMinutes = 40, pauseHours = 6, matchEvery = 75, maxSessions = 200, postSessions = 200 },
	{ id = "occasionnel", label = "Joueur occasionnel", sessionMinutes = 15, pauseHours = 24, matchEvery = 120, maxSessions = 365, postSessions = 60 },
}

-- Outils --------------------------------------------------------------------

local function median(list)
	if #list == 0 then
		return nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local mid = (#sorted + 1) / 2
	return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

local function percentile(list, p)
	if #list == 0 then
		return nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.clamp(math.ceil(p * #sorted), 1, #sorted)]
end

local TOP = Divisions.List[#Divisions.List].id

local function fmt(value, suffix)
	if value == nil then
		return "—"
	end
	return ("%g%s"):format(math.floor(value * 10 + 0.5) / 10, suffix or "")
end

-- Liste de tous les achats possibles (installation et niveau), lue dans la config.
local ITEMS = {}
for _, def in Buildings.List() do
	for level = 2, #def.levels do
		table.insert(ITEMS, { key = def.id .. " " .. level, building = def.id, level = level, cost = def.levels[level].cost })
	end
end
-- Staff du club (Staff.lua) : chaque niveau est un achat de plus.
for _, def in S.Staff.List() do
	for level = 1, #def.levels do
		table.insert(ITEMS, { key = "Staff " .. def.id .. " " .. level, staff = def.id, level = level, cost = def.levels[level].cost })
	end
end
local RECRUITS = Config.MAX_SQUAD_SIZE - Config.STARTING_PLAYERS
for n = 1, RECRUITS do
	table.insert(ITEMS, { key = "Recrue " .. n, recruit = n, cost = PlayerConfig.RECRUIT_COST })
end
-- Entraînement : le joueur garde au moins N fois le prix d'une séance.
local TRAIN_RESERVE = 4
-- Fin de partie : seuil d'alerte (heures de jeu après la D1 avant de tout posséder).
local MIN_ENDGAME_HOURS = 15
local CHECK_HOURS = 10 -- « objets achetés N heures après la D1 »
local TOTAL_COST = 0
for _, item in ITEMS do
	TOTAL_COST += item.cost
end

-- Une partie ----------------------------------------------------------------

local nextUserId = 1000

local function playRun(profil)
	nextUserId += 1
	local userId = nextUserId
	local run = {
		playSeconds = 0,
		matches = 0,
		sessions = 0,
		bought = {}, -- [clé] = { minutes, matches, session }
		reach = {}, -- [division] = { minutes, matches, session }
		firstPurchase = nil,
		incomes = {},
		allBoughtAt = nil,
		minEnergy = 100,
		wins = 0,
		transfers = 0,
		transferSpent = 0,
		divisionWins = {}, -- [division] = { wins, matches }
		baseIncomes = {},
		cosmeticMinutes = {}, -- minutes de jeu de chaque achat de personnalisation
		allCosmeticsAt = nil,
		postSessions = 0,
		titlesAtEnd = 0,
		tournamentGains = {}, -- gains versés par le tournoi du serveur
		sponsorPerMatch = {}, -- prime fixe des contrats à chaque match
		sponsorBonuses = 0, -- total des bonus d'objectif
		sponsorSigned = 0,
		loginGains = 0, -- cadeau du jour + revenus hors ligne + fin de saison (à l'arrivée)
		missionGains = 0, -- primes des missions du jour
		matchGains = 0, -- gains des matchs (hors missions et primes de montée)
		eventBonus = 0, -- part des gains de match venant du thème de la semaine
		eventTiers = 0, -- paliers de l'événement de la semaine récupérés (FC Coins)
		eventCosmetics = 0, -- objets d'événement gagnés
		topWeeks = {}, -- semaines où la dernière étape de l'événement est atteinte
		weeks = {}, -- semaines jouées
		trainingSessions = 0, -- séances d'entraînement (Training.lua)
		trainingSpent = 0,
	}
	local function stamp()
		return { minutes = run.playSeconds / 60, matches = run.matches, session = run.sessions }
	end
	local function note(key)
		if not run.bought[key] then
			run.bought[key] = stamp()
			run.firstPurchase = run.firstPurchase or run.bought[key]
		end
	end

	local function shop(player, data)
		while true do
			local best = nil
			for _, item in ITEMS do
				local available
				if item.staff then
					available = (data.staff[item.staff] or 0) == item.level - 1
				elseif item.recruit then
					available = #data.squad < Config.MAX_SQUAD_SIZE
						and not run.bought[item.key]
						and (item.recruit == 1 or run.bought["Recrue " .. (item.recruit - 1)])
				else
					available = (data.buildings[item.building] or 1) == item.level - 1
				end
				if available and item.cost <= data.coins and (not best or item.cost < best.cost) then
					best = item
				end
			end
			-- Transfert : un candidat de plus, au prix du marché de la division.
			local market = Divisions.Get(data.club.division).transfer
			if market and #data.squad >= Config.MAX_SQUAD_SIZE and market.cost <= data.coins then
				local weakest = S.SquadService.GetWeakest(data.squad)
				if weakest.rating < market.ratingMax and (not best or market.cost < best.cost) then
					best = { transfer = true, cost = market.cost }
				end
			end
			if not best then
				-- Fin de partie : tout est acheté et le club est en D1 → personnalisation.
				if run.allBoughtAt and data.club.division == TOP then
					local pick = nil
					for _, item in Cosmetics.List do
						if not data.cosmetics.owned[item.id] and item.cost <= data.coins
							and Cosmetics.IsUnlocked(item, data.club.division, data.trophies.titles)
							and (not pick or item.cost < pick.cost) then
							pick = item
						end
					end
					if pick and S.CosmeticService.TryBuy(player, pick.id) then
						table.insert(run.cosmeticMinutes, run.playSeconds / 60)
						if #run.cosmeticMinutes == #Cosmetics.List then
							run.allCosmeticsAt = stamp()
						end
						continue
					end
				end
				return
			end
			local ok
			if best.transfer then
				ok = S.SquadService.TryTransfer(player)
				if ok then
					run.transfers += 1
					run.transferSpent += best.cost
				end
			elseif best.recruit then
				ok = S.SquadService.TryRecruit(player)
			elseif best.staff then
				ok = S.StaffService.TryHire(player, best.staff)
			else
				ok = S.BuildingService.TryUpgrade(player, best.building)
			end
			if not ok then
				return
			end
			if not best.transfer then
				note(best.key)
			end
		end
	end

	-- Entraînement : le joueur entraîne ses titulaires prêts, s'il garde de
	-- quoi acheter (réserve de TRAIN_RESERVE fois le prix de la séance) et
	-- seulement s'ils sont en forme (une séance fatigue avant le match).
	local function train(player, data)
		local now = os.time()
		for _, footballer in S.SquadService.Starters(data) do
			local cost = S.Training.SessionCost(footballer.rating)
			if footballer.rating < footballer.potential
				and S.Training.CooldownLeft(footballer, now) <= 0
				and footballer.energy >= 90
				and data.coins >= cost * TRAIN_RESERVE
			then
				if S.SquadService.TryTrain(player, footballer.id) then
					run.trainingSessions += 1
					run.trainingSpent += cost
				end
			end
		end
	end

	while run.sessions < profil.maxSessions and not run.allCosmeticsAt and run.postSessions < profil.postSessions do
		run.sessions += 1
		if run.reach[TOP] and run.allBoughtAt then
			run.postSessions += 1
		end
		local player = H.join(userId)
		local data = S.PlayerDataService.GetData(player)
		assert(data, "profil non chargé")
		if run.coinsAtEnd then
			run.loginGains += math.max(0, data.coins - run.coinsAtEnd)
		end
		local sessionEnd = run.playSeconds + profil.sessionMinutes * 60
		-- Le premier match d'une session part dès l'arrivée.
		local wait = 0
		while run.playSeconds + wait <= sessionEnd do
			-- Le joueur s'inscrit à chaque tournoi du serveur ouvert pendant sa session ;
			-- les récompenses tombent pendant l'attente entre deux matchs.
			S.TournamentService.TryJoin(player)
			local beforeWait = data.coins
			local dayBefore, seasonBefore = data.daily.lastClaimDay, data.season.id
			H.advance(wait)
			run.playSeconds += wait
			if data.daily.lastClaimDay ~= dayBefore or data.season.id ~= seasonBefore then
				-- Minuit pendant la session : cadeau du jour ou fin de saison (pas le tournoi).
				run.loginGains += math.max(0, data.coins - beforeWait)
			elseif data.coins > beforeWait then
				table.insert(run.tournamentGains, data.coins - beforeWait)
			end
			shop(player, data)
			train(player, data)
			-- Sponsors : le joueur signe l'offre la plus payante dès qu'il a une place.
			while #data.sponsors.contracts < S.Sponsors.MaxActive(Divisions.Get(data.club.division).tier) do
				S.StaffService.RefreshOffers(data)
				local pick = nil
				for _, offer in data.sponsors.offers do
					local value = offer.perMatch * offer.matches + offer.bonus
					if not pick or value > pick.value then
						pick = { id = offer.id, value = value }
					end
				end
				if not pick or not S.StaffService.TrySignSponsor(player, pick.id) then
					break
				end
				run.sponsorSigned += 1
			end
			local coins = data.coins
			local divisionBefore = data.club.division
			local result, err = S.MatchService.TryStartMatch(player, "ai", "Balanced")
			if result then
				run.matches += 1
				if result.outcome == "Win" then
					run.wins += 1
				end
				local dw = run.divisionWins[divisionBefore] or { wins = 0, matches = 0 }
				dw.matches += 1
				dw.wins += if result.outcome == "Win" then 1 else 0
				run.divisionWins[divisionBefore] = dw
				local bonus = 0
				for _, b in result.sponsorBonuses do
					bonus += b.coins
				end
				run.sponsorBonuses += bonus
				table.insert(run.sponsorPerMatch, result.rewards.contracts)
				-- Bonus d'objectif des sponsors : versement unique, compté à part.
				run.missionGains += result.missionReward or 0
				run.eventBonus += result.rewards.event or 0
				run.weeks[S.Events.Week(os.time())] = true
				local income = data.coins - coins - (result.promotionReward or 0) - bonus - (result.missionReward or 0)
				run.matchGains += income
				table.insert(run.incomes, income)
				-- Contrôle des sources anormales : hors bonus voulu de la division
				-- (prime de match ×1 à ×3), le gain doit rester sous 5 000.
				-- Les contrats de sponsoring sont contrôlés à part (plafond ci-dessous).
				-- Le bonus de l'événement de la semaine est voulu lui aussi (contrôlé à part).
				table.insert(run.baseIncomes, income - (result.rewards.match - Config.Rewards[result.outcome]) - result.rewards.contracts - (result.rewards.event or 0))
				-- Événement de la semaine : le joueur récupère ses paliers dès qu'ils sont atteints.
				local beforeClaim, ownedBefore = data.coins, 0
				for id in data.cosmetics.owned do
					ownedBefore += if S.Cosmetics.Get(id) and S.Cosmetics.Get(id).event then 1 else 0
				end
				if S.EventService.TryClaim(player) then
					run.eventTiers += data.coins - beforeClaim
					local ownedAfter = 0
					for id in data.cosmetics.owned do
						ownedAfter += if S.Cosmetics.Get(id) and S.Cosmetics.Get(id).event then 1 else 0
					end
					run.eventCosmetics += ownedAfter - ownedBefore
					if data.events.claimed >= #S.Events.TIERS then
						run.topWeeks[data.events.week] = true
					end
				end
				if result.promoted then
					run.reach[result.division] = stamp()
				end
				for _, footballer in data.squad do
					run.minEnergy = math.min(run.minEnergy, footballer.energy)
				end
			else
				assert(err and err:find("prochain match"), "match refusé : " .. tostring(err))
			end
			shop(player, data)
			if not run.allBoughtAt then
				local all = true
				for _, item in ITEMS do
					all = all and run.bought[item.key] ~= nil
				end
				if all then
					run.allBoughtAt = stamp()
				end
			end
			wait = math.max(profil.matchEvery, Config.MATCH_COOLDOWN_SECONDS)
		end
		run.coinsAtEnd = data.coins
		run.titlesAtEnd = data.trophies.titles
		H.leave(player)
		H.advance(profil.pauseHours * 3600)
		H.clearSent()
		H.logs = {}
	end
	return run
end

-- Rapport -------------------------------------------------------------------

print(("# Simulation de l'économie (%d parties par profil)"):format(RUNS))
print("")
print(("Départ : %d %s · prime de match V/N/D : %d/%d/%d · recrue : %d · délai entre matchs : %d s"):format(
	Config.STARTING_COINS,
	Config.CURRENCY_NAME,
	Config.Rewards.Win,
	Config.Rewards.Draw,
	Config.Rewards.Loss,
	PlayerConfig.RECRUIT_COST,
	Config.MATCH_COOLDOWN_SECONDS
))
print(("Coût total de tout le contenu (installations + %d recrues) : %d"):format(RECRUITS, TOTAL_COST))

local problems = {}

for _, profil in PROFILS do
	local runs = {}
	for _ = 1, RUNS do
		table.insert(runs, playRun(profil))
	end

	local function column(get)
		local values = {}
		for _, run in runs do
			local v = get(run)
			if v ~= nil then
				table.insert(values, v)
			end
		end
		return values
	end
	local function line(label, get, unit)
		local m = column(function(r)
			local s = get(r)
			return s and s.minutes
		end)
		local n = column(function(r)
			local s = get(r)
			return s and s.matches
		end)
		local se = column(function(r)
			local s = get(r)
			return s and s.session
		end)
		local missing = RUNS - #m
		print(("| %s | %s | %s | %s | %s |%s"):format(
			label,
			fmt(median(m), " min"),
			fmt(percentile(m, 0.9), " min"),
			fmt(median(n)),
			fmt(median(se)),
			if missing > 0 then (" jamais dans %d partie(s)"):format(missing) else ""
		))
		return missing
	end

	print("")
	print(("## %s (sessions de %d min, pause de %d h, un match toutes les %d s)"):format(
		profil.label,
		profil.sessionMinutes,
		profil.pauseHours,
		math.max(profil.matchEvery, Config.MATCH_COOLDOWN_SECONDS)
	))
	print("")
	print("| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |")
	print("| --- | --- | --- | --- | --- |")
	line("Premier achat", function(r)
		return r.firstPurchase
	end)
	local missing = {}
	for index = 2, #Divisions.List do
		local id = Divisions.List[index].id
		missing[id] = line("Montée en " .. id, function(r)
			return r.reach[id]
		end)
	end
	for _, item in ITEMS do
		line(("%s (%d)"):format(item.key, item.cost), function(r)
			return r.bought[item.key]
		end)
	end
	line("Tout acheté", function(r)
		return r.allBoughtAt
	end)

	-- Objectif long terme : D1 en heures de jeu et en jours.
	local topHours, topDays = {}, {}
	for _, run in runs do
		local r = run.reach[TOP]
		if r then
			table.insert(topHours, r.minutes / 60)
			table.insert(topDays, r.session * (profil.sessionMinutes / 60 + profil.pauseHours) / 24)
		end
	end
	print("")
	print(("%s : médiane %s de jeu (90 %% avant %s), soit ~%s jours au rythme du profil"):format(
		TOP,
		fmt(median(topHours), " h"),
		fmt(percentile(topHours, 0.9), " h"),
		fmt(median(topDays))
	))
	local winLine = {}
	for _, division in Divisions.List do
		local w, m = 0, 0
		for _, run in runs do
			local dw = run.divisionWins[division.id]
			if dw then
				w += dw.wins
				m += dw.matches
			end
		end
		if m > 0 then
			table.insert(winLine, ("%s %s %%"):format(division.id, fmt(w / m * 100)))
		end
	end
	print("Victoires par division : " .. table.concat(winLine, " · "))
	local transfers, transferSpent = {}, {}
	for _, run in runs do
		table.insert(transfers, run.transfers)
		table.insert(transferSpent, run.transferSpent)
	end
	local sessions, spent = {}, {}
	for _, run in runs do
		table.insert(sessions, run.trainingSessions)
		table.insert(spent, run.trainingSpent)
	end
	print(("Entraînement : médiane %s séances (dépense %s FC Coins)"):format(fmt(median(sessions)), fmt(median(spent))))
	print(("Transferts : médiane %s (dépense %s FC Coins)"):format(fmt(median(transfers)), fmt(median(transferSpent))))

	-- Fin de partie : personnalisation achetée après la D1.
	local endHours, ownedLater, titlesEnd, unfinished = {}, {}, {}, 0
	for _, run in runs do
		local r = run.reach[TOP]
		if r then
			if run.allCosmeticsAt then
				table.insert(endHours, (run.allCosmeticsAt.minutes - r.minutes) / 60)
			else
				unfinished += 1
			end
			local count = 0
			for _, m in run.cosmeticMinutes do
				if m <= r.minutes + CHECK_HOURS * 60 then
					count += 1
				end
			end
			table.insert(ownedLater, count)
			table.insert(titlesEnd, run.titlesAtEnd)
		end
	end
	print(("Fin de partie : personnalisation complète (%d objets, %s FC Coins) %s h de jeu après la D1 (médiane)%s"):format(
		#Cosmetics.List,
		fmt(Cosmetics.TotalCost()),
		fmt(median(endHours)),
		if unfinished > 0 then (" · pas finie après %d sessions en D1 dans %d partie(s)"):format(profil.postSessions, unfinished) else ""
	))
	print(("Objets possédés %d h après la D1 : médiane %s / %d · titres de champion en fin de simulation : médiane %s"):format(
		CHECK_HOURS,
		fmt(median(ownedLater)),
		#Cosmetics.List,
		fmt(median(titlesEnd))
	))
	local h = median(endHours)
	if h and h < MIN_ENDGAME_HOURS then
		table.insert(problems, ("%s : tout est acheté %s h après la D1 (moins de %d h : plus rien à acheter)"):format(profil.label, fmt(h), MIN_ENDGAME_HOURS))
	end

	local incomes, baseIncomes, winRates, minEnergy, endCoins = {}, {}, {}, {}, {}
	for _, run in runs do
		for _, v in run.incomes do
			table.insert(incomes, v)
		end
		for _, v in run.baseIncomes do
			table.insert(baseIncomes, v)
		end
		table.insert(winRates, run.wins / math.max(1, run.matches))
		table.insert(minEnergy, run.minEnergy)
		table.insert(endCoins, run.coinsAtEnd or 0)
	end
	print("")
	print(("Gain par match : médiane %s, max %s · victoires : %s %% · énergie la plus basse : %s · solde final médian : %s"):format(
		fmt(median(incomes)),
		fmt(percentile(incomes, 1)),
		fmt(median(winRates) * 100),
		fmt(median(minEnergy)),
		fmt(median(endCoins))
	))

	local gains, perHour = {}, {}
	for _, run in runs do
		local total = 0
		for _, v in run.tournamentGains do
			table.insert(gains, v)
			total += v
		end
		table.insert(perHour, total / math.max(1, run.playSeconds / 3600))
	end
	local maxMultiplier = 0
	for _, division in Divisions.List do
		maxMultiplier = math.max(maxMultiplier, division.rewardMultiplier)
	end
	-- Coupe du week-end : récompenses majorées le samedi et le dimanche.
	local tournamentCap = Config.Tournament.Rewards.Winner * maxMultiplier * S.Events.WEEKEND_CUP_MULTIPLIER
	print(("Tournoi du serveur : %d récompenses · médiane %s · max %s (plafond %s) · %s FC Coins par heure de jeu (médiane)"):format(
		#gains,
		fmt(median(gains)),
		fmt(percentile(gains, 1)),
		fmt(tournamentCap),
		fmt(median(perHour))
	))
	if (percentile(gains, 1) or 0) > tournamentCap then
		table.insert(problems, profil.label .. " : une récompense de tournoi dépasse le plafond (source anormale)")
	end

	local perMatchAll, bonusPerHour, signed = {}, {}, {}
	for _, run in runs do
		for _, v in run.sponsorPerMatch do
			table.insert(perMatchAll, v)
		end
		table.insert(bonusPerHour, run.sponsorBonuses / math.max(1, run.playSeconds / 3600))
		table.insert(signed, run.sponsorSigned)
	end
	print(("Sponsors : prime des contrats par match médiane %s, max %s · bonus d'objectif %s FC Coins par heure de jeu (médiane) · %s contrats signés (médiane)"):format(
		fmt(median(perMatchAll)),
		fmt(percentile(perMatchAll, 1)),
		fmt(median(bonusPerHour)),
		fmt(median(signed))
	))

	-- Plafond des contrats : 2 contrats de D1 au maximum (tirage, prestige, directeur commercial).
	local sponsorCap = 2 * S.Sponsors.BASE_PER_MATCH.D1 * 1.2 * (1 + S.Sponsors.PRESTIGE_BONUS_MAX)
		* (1 + S.Staff.Effect({ Commercial = S.Staff.MaxLevel("Commercial") }, "sponsorBonus")) + 10
	if (percentile(perMatchAll, 1) or 0) > sponsorCap then
		table.insert(problems, profil.label .. " : les contrats de sponsoring dépassent leur plafond (source anormale)")
	end

	-- Événements de la semaine (EventService) : bonus du thème et paliers.
	local bonusShare, tierShare, cosmeticsPerWeek = {}, {}, {}
	for _, run in runs do
		local total = math.max(1, run.matchGains + run.loginGains + run.missionGains + run.eventTiers)
		table.insert(bonusShare, run.eventBonus / math.max(1, run.matchGains))
		table.insert(tierShare, run.eventTiers / total)
		local weeks, top = 0, 0
		for _ in run.weeks do
			weeks += 1
		end
		for _ in run.topWeeks do
			top += 1
		end
		table.insert(cosmeticsPerWeek, top / math.max(1, weeks))
	end
	print(("Événements de la semaine : bonus du thème %s %% des gains de match · paliers %s %% des gains · dernière étape atteinte %s semaine(s) jouée(s) sur 10"):format(
		fmt(median(bonusShare) * 100),
		fmt(median(tierShare) * 100),
		fmt(median(cosmeticsPerWeek) * 10)
	))
	if median(bonusShare) > 0.15 or median(tierShare) > 0.15 then
		table.insert(problems, profil.label .. " : l'événement de la semaine pèse plus de 15 % des gains (trop généreux)")
	end

	-- Objectifs quotidiens (DailyService) : part des revenus venant du retour quotidien.
	local loginShare, missionShare, loginPerSession = {}, {}, {}
	for _, run in runs do
		local total = math.max(1, run.matchGains + run.loginGains + run.missionGains + run.eventTiers)
		table.insert(loginShare, run.loginGains / total)
		table.insert(missionShare, run.missionGains / total)
		table.insert(loginPerSession, run.loginGains / math.max(1, run.sessions - 1))
	end
	print(("Retour quotidien : arrivée (cadeau + hors ligne + saison) %s %% des gains, %s par session · missions %s %% des gains"):format(
		fmt(median(loginShare) * 100),
		fmt(median(loginPerSession)),
		fmt(median(missionShare) * 100)
	))
	if median(loginShare) + median(missionShare) > 0.5 then
		table.insert(problems, profil.label .. " : plus de la moitié des gains vient sans jouer (cadeaux, hors ligne, missions)")
	end

	-- Contrôles : sources infinies et blocages
	print(("Gain par match hors bonus de division : max %s (seuil d'alerte 5 000)"):format(fmt(percentile(baseIncomes, 1))))
	if percentile(baseIncomes, 1) > 5000 then
		table.insert(problems, profil.label .. " : un match rapporte plus de 5 000 hors bonus de division (source anormale)")
	end
	for id, miss in missing do
		if miss > 0 then
			table.insert(problems, ("%s : %s non atteinte dans %d partie(s) (blocage sportif)"):format(profil.label, id, miss))
		end
	end
	if percentile(endCoins, 1) >= Config.MAX_COINS then
		table.insert(problems, profil.label .. " : solde au plafond (monnaie infinie)")
	end
end

print("")
if #problems == 0 then
	print("Aucune source de monnaie infinie ni blocage détecté.")
else
	for _, p in problems do
		print("⚠ " .. p)
	end
end
