--[[
	Weather
	Météo et cycle jour/nuit du quartier, calculés à partir de l'heure seule.

	Pas de tirage ni de message réseau : le serveur (matchs) et chaque client
	(ciel, pluie, projecteurs) appellent les mêmes fonctions avec la même heure,
	donc tout le monde voit la même météo que celle qui compte dans le match.

	- Jour/nuit : une journée de jeu dure DAY_SECONDS (20 min). La nuit va de
	  NIGHT_START à NIGHT_END (heure du jeu) : les projecteurs s'allument.
	- Météo : change toutes les SLOT_SECONDS (10 min). La neige n'existe qu'en
	  hiver (décembre, janvier, février, heure UTC).
	- Effet sur les matchs : léger. Chaque météo (sauf le beau temps) donne +1
	  en attaque et en défense au style qu'elle avantage, pour les DEUX équipes
	  (le club fictif aussi s'il joue ce style). C'est la moitié d'un avantage
	  tactique (Tactics.EDGE = 2).

	Lu par le serveur (MatchService) et par le client (WeatherController, onglet Matchs).
]]

local Weather = {}

Weather.DAY_SECONDS = 20 * 60
Weather.SLOT_SECONDS = 10 * 60
Weather.NIGHT_START = 19.5 -- heure du jeu (0-24)
Weather.NIGHT_END = 5.5
Weather.BONUS = 1 -- points d'attaque et de défense du style avantagé
Weather.WINTER_MONTHS = { [12] = true, [1] = true, [2] = true }

Weather.KINDS = { "Clear", "Cloudy", "Rain", "Wind", "Snow" }

-- Style de jeu avantagé par chaque météo (nil = aucun effet).
Weather.FAVORS = {
	Clear = nil,
	Cloudy = nil,
	Rain = "Defensive", -- terrain lourd : le bloc bas tient mieux
	Wind = "Counter", -- longs ballons portés par le vent
	Snow = "Pressing", -- ballon qui ralentit : on le récupère plus vite
}

-- Chances (sur 100) de chaque météo, hors hiver et en hiver.
Weather.CHANCES = {
	normal = { Clear = 50, Cloudy = 20, Rain = 20, Wind = 10, Snow = 0 },
	winter = { Clear = 35, Cloudy = 20, Rain = 10, Wind = 10, Snow = 25 },
}

Weather.EMOJI = { Clear = "☀️", Cloudy = "☁️", Rain = "🌧️", Wind = "💨", Snow = "❄️" }

-- Petit générateur à partir d'un entier (calcul exact en nombres flottants).
local function hash(n: number): number
	local h = (math.floor(n) % 2147483646) + 1
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end

function Weather.IsValid(kind: any): boolean
	return type(kind) == "string" and Weather.CHANCES.normal[kind] ~= nil
end

function Weather.IsWinter(t: number): boolean
	local date = os.date("!*t", math.floor(t))
	return Weather.WINTER_MONTHS[date.month] == true
end

function Weather.Slot(t: number): number
	return math.floor(t / Weather.SLOT_SECONDS)
end

-- Météo à l'instant t (secondes depuis 1970, heure du serveur).
function Weather.At(t: number): string
	local slot = Weather.Slot(t)
	local chances = if Weather.IsWinter(slot * Weather.SLOT_SECONDS) then Weather.CHANCES.winter else Weather.CHANCES.normal
	local roll = hash(slot) % 100
	for _, kind in Weather.KINDS do
		roll -= chances[kind]
		if roll < 0 then
			return kind
		end
	end
	return "Clear"
end

-- Prochain changement de météo : (instant, météo suivante).
function Weather.Next(t: number): (number, string)
	local at = (Weather.Slot(t) + 1) * Weather.SLOT_SECONDS
	return at, Weather.At(at)
end

-- Heure du jeu (0 à 24) à l'instant t. Le jeu démarre le matin (8 h) au début de chaque journée.
function Weather.ClockTime(t: number): number
	local progress = (t % Weather.DAY_SECONDS) / Weather.DAY_SECONDS
	return (8 + progress * 24) % 24
end

function Weather.IsNight(t: number): boolean
	local clock = Weather.ClockTime(t)
	return clock >= Weather.NIGHT_START or clock < Weather.NIGHT_END
end

-- Style avantagé par une météo (nil si aucun).
function Weather.Favors(kind: any): string?
	if not Weather.IsValid(kind) then
		return nil
	end
	return Weather.FAVORS[kind]
end

-- Bonus (attaque, défense) d'une équipe qui joue `tactic` par cette météo.
function Weather.Modifiers(kind: any, tactic: any): (number, number)
	local favored = Weather.Favors(kind)
	if favored and favored == tactic then
		return Weather.BONUS, Weather.BONUS
	end
	return 0, 0
end

-- Résumé envoyé avec le résultat d'un match (affichage seulement).
function Weather.Describe(t: number)
	local kind = Weather.At(t)
	return {
		kind = kind,
		night = Weather.IsNight(t),
		favors = Weather.Favors(kind),
	}
end

-- Pluie ou neige : nombre de particules par seconde (0 = rien), réduit sur téléphone.
function Weather.ParticleRate(kind: any, mobile: boolean?): number
	local rate = if kind == "Rain" then 60 elseif kind == "Snow" then 25 elseif kind == "Wind" then 8 else 0
	if mobile then
		rate = math.floor(rate / 2)
	end
	return rate
end

return Weather
