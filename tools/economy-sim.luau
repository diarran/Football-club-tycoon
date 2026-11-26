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

	Variables fournies par economy-sim.js : SIM_RUNS (parties par profil).
]]

local S = H.boot(MODULES)
local Config, Buildings, Divisions, PlayerConfig = S.Config, S.Buildings, S.Divisions, S.PlayerConfig
local RUNS = SIM_RUNS or 40
local print = H.realPrint -- les print du jeu restent dans le journal du harnais

-- Joueurs types -------------------------------------------------------------
-- sessionMinutes : durée d'une session ; pauseHours : temps hors ligne entre deux.
-- matchEvery : secondes entre deux matchs (le joueur ne joue pas forcément dès
-- la fin du délai : il regarde le résultat, se promène, achète…).
local PROFILS = {
	{ id = "actif", label = "Joueur actif", sessionMinutes = 40, pauseHours = 6, matchEvery = 75, maxSessions = 200 },
	{ id = "occasionnel", label = "Joueur occasionnel", sessionMinutes = 15, pauseHours = 24, matchEvery = 120, maxSessions = 365 },
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
local RECRUITS = Config.MAX_SQUAD_SIZE - Config.STARTING_PLAYERS
for n = 1, RECRUITS do
	table.insert(ITEMS, { key = "Recrue " .. n, recruit = n, cost = PlayerConfig.RECRUIT_COST })
end
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
				if item.recruit then
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

	while run.sessions < profil.maxSessions and not (run.reach[TOP] and run.allBoughtAt) do
		run.sessions += 1
		local player = H.join(userId)
		local data = S.PlayerDataService.GetData(player)
		assert(data, "profil non chargé")
		local sessionEnd = run.playSeconds + profil.sessionMinutes * 60
		-- Le premier match d'une session part dès l'arrivée.
		local wait = 0
		while run.playSeconds + wait <= sessionEnd do
			H.advance(wait)
			run.playSeconds += wait
			shop(player, data)
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
				local income = data.coins - coins - (result.promotionReward or 0)
				table.insert(run.incomes, income)
				-- Contrôle des sources anormales : hors bonus voulu de la division
				-- (prime de match ×1 à ×3), le gain doit rester sous 5 000.
				table.insert(run.baseIncomes, income - (result.rewards.match - Config.Rewards[result.outcome]))
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
	print(("Transferts : médiane %s (dépense %s FC Coins)"):format(fmt(median(transfers)), fmt(median(transferSpent))))

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
