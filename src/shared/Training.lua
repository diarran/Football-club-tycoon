--[[
	Training
	Entraînement et progression des footballeurs (document de conception,
	sections 2 et 5 : « recruter, composer un effectif réduit, entraîner »).

	- Expérience (XP) : chaque joueur gagne de l'XP en match (titulaires
	  seulement) et en séance d'entraînement. Tous les XP_PER_POINT points,
	  sa note monte de 1, sans jamais dépasser son potentiel.
	- Séance d'entraînement : payée en FC Coins (prix selon la note), coûte de
	  l'énergie, puis le joueur doit souffler (délai). L'XP dépend de la zone
	  d'entraînement (teamBonus), de l'entraîneur du staff (growthBonus) et de l'âge.
	- Âge : +1 an à chaque nouvelle saison (7 jours, Daily.SeasonId). Les jeunes
	  progressent plus vite, les plus âgés moins vite (aucune baisse de note).
	- Composition : STARTERS titulaires jouent les matchs (force, buts, fatigue,
	  XP). Les remplaçants se reposent. La composition est complétée
	  automatiquement par les meilleurs joueurs, avec un gardien si possible.

	Partagé client/serveur : l'interface affiche les mêmes calculs que le serveur.
	Les valeurs sont équilibrées avec tools/economy-sim.js.
]]

local Training = {}

Training.STARTERS = 5 -- joueurs sur le terrain (comme les clubs fictifs)
Training.XP_PER_POINT = 100 -- XP pour gagner 1 point de note
Training.SESSION_XP = 40 -- XP d'une séance, avant les bonus
Training.SESSION_ENERGY = 30 -- énergie dépensée par une séance
Training.MIN_ENERGY = 30 -- énergie minimale pour s'entraîner
Training.SESSION_COOLDOWN = 300 -- secondes entre deux séances d'un même joueur
Training.MAX_AGE_STEPS = 2 -- années ajoutées au plus d'un coup (long retour)

-- Âge -> multiplicateur d'XP (séances et matchs).
Training.AgeBands = {
	{ maxAge = 21, factor = 1.5 }, -- jeune talent
	{ maxAge = 29, factor = 1.0 },
	{ maxAge = 33, factor = 0.6 },
	{ maxAge = math.huge, factor = 0.3 }, -- vétéran
}

function Training.AgeFactor(age: number?): number
	age = tonumber(age) or 25
	for _, band in Training.AgeBands do
		if age <= band.maxAge then
			return band.factor
		end
	end
	return 1
end

-- Prix d'une séance : plus le joueur est bon, plus elle coûte.
function Training.SessionCost(rating: number): number
	rating = math.max(0, tonumber(rating) or 0)
	return 40 + math.floor(rating * rating / 10)
end

-- XP d'une séance. teamBonus = effet de la zone d'entraînement (0 à 4),
-- growthBonus = effet de l'entraîneur du staff (0 à 0,08).
function Training.SessionXp(footballer, teamBonus: number?, growthBonus: number?): number
	local facility = 1 + 0.25 * (teamBonus or 0)
	local coach = 1 + 5 * (growthBonus or 0)
	return math.floor(Training.SESSION_XP * facility * coach * Training.AgeFactor(footballer.age) + 0.5)
end

-- XP d'un match pour un titulaire : même moyenne que l'ancienne « chance de
-- progresser » (chance × XP_PER_POINT), modulée par l'âge.
function Training.MatchXp(footballer, chance: number): number
	return math.floor(chance * Training.XP_PER_POINT * Training.AgeFactor(footballer.age) + 0.5)
end

-- Ajoute de l'XP ; renvoie le nombre de points de note gagnés. Au potentiel,
-- l'XP n'est plus gardée (barre pleine).
function Training.AddXp(footballer, xp: number): number
	local gained = 0
	footballer.xp = (tonumber(footballer.xp) or 0) + math.max(0, xp)
	while footballer.xp >= Training.XP_PER_POINT and footballer.rating < footballer.potential do
		footballer.xp -= Training.XP_PER_POINT
		footballer.rating += 1
		gained += 1
	end
	if footballer.rating >= footballer.potential then
		footballer.xp = 0
	end
	footballer.value = footballer.rating * 30
	return gained
end

-- Secondes avant la prochaine séance possible (0 = prêt).
function Training.CooldownLeft(footballer, now: number): number
	return math.max(0, (tonumber(footballer.trainedAt) or 0) + Training.SESSION_COOLDOWN - now)
end

-- Composition -------------------------------------------------------------

local function better(a, b)
	if a.rating ~= b.rating then
		return a.rating > b.rating
	end
	return (a.id or 0) < (b.id or 0)
end

-- Renvoie la liste d'identifiants des titulaires : ceux choisis (encore dans
-- l'effectif, sans doublon), complétés par les meilleurs, gardien d'abord si
-- aucun n'est choisi. Fonction pure : ne modifie ni squad ni lineup.
function Training.Normalize(squad, lineup)
	local byId = {}
	for _, footballer in squad do
		byId[footballer.id] = footballer
	end
	local size = math.min(Training.STARTERS, #squad)
	local ids, taken, hasGK = {}, {}, false
	if type(lineup) == "table" then
		for _, id in lineup do
			if #ids >= size then
				break
			end
			local footballer = byId[id]
			if footballer and not taken[id] then
				table.insert(ids, id)
				taken[id] = true
				hasGK = hasGK or footballer.position == "GK"
			end
		end
	end
	local bench = {}
	for _, footballer in squad do
		if not taken[footballer.id] then
			table.insert(bench, footballer)
		end
	end
	table.sort(bench, better)
	if not hasGK and #ids < size then
		for index, footballer in bench do
			if footballer.position == "GK" then
				table.insert(ids, footballer.id)
				table.remove(bench, index)
				break
			end
		end
	end
	for _, footballer in bench do
		if #ids >= size then
			break
		end
		table.insert(ids, footballer.id)
	end
	return ids
end

-- Titulaires (les tables des joueurs de squad, dans l'ordre de la composition).
function Training.Starters(squad, lineup)
	local byId = {}
	for _, footballer in squad do
		byId[footballer.id] = footballer
	end
	local starters = {}
	for _, id in Training.Normalize(squad, lineup) do
		table.insert(starters, byId[id])
	end
	return starters
end

-- Ensemble { [id] = true } des titulaires.
function Training.StarterSet(squad, lineup)
	local set = {}
	for _, id in Training.Normalize(squad, lineup) do
		set[id] = true
	end
	return set
end

return Training
