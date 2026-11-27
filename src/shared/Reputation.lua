--[[
	Reputation
	Réputation du club (0 à 100) et conférences de presse (gestion légère).

	Réputation :
	- Elle monte avec les victoires, les gros scores, les montées, les tours de
	  coupe et les tournois ; elle baisse un peu après une défaite.
	- Plafond selon la division (Cap) : un club de D7 ne peut pas être une
	  légende. Plancher selon la division et les tribunes (Floor) : la
	  réputation ne s'effondre jamais, et un beau stade la protège.
	- Effet doux : les primes fixes des contrats de sponsoring augmentent
	  jusqu'à +SPONSOR_MAX (à 100 de réputation).

	Conférences de presse :
	- Après un grand moment (montée, gros score, série de victoires, match
	  contre un autre club du serveur, exploit en coupe…), une question des
	  journalistes arrive. Jamais plus d'une tous les PRESS_GAP matchs, sauf
	  pour une montée ou une coupe gagnée.
	- 3 réponses : humble, ambitieuse, provocante. Toujours facultatif :
	  « Passer » ne coûte rien, et une question non répondue disparaît.
	- Chaque réponse donne un petit effet pour les BUZZ_MATCHES prochains
	  matchs du championnat (jamais de perte d'argent) :
	  humble → moral : énergie des joueurs +MORALE_ENERGY tout de suite ;
	  ambitieuse → sponsors : primes de sponsors +SPONSOR_BUZZ ;
	  provocante → fans : billetterie +FANS_BUZZ, mais la réputation
	  baisse un peu si le match suivant est perdu.

	Partagé client/serveur. Profil : data.reputation (ReputationService).
	Textes : clés « reputation.* » et « press.* » de Locale.
]]

local Reputation = {}

Reputation.MIN = 0
Reputation.MAX = 100

-- Variations de réputation.
Reputation.Gains = {
	Win = 2,
	Draw = 0,
	Loss = -1,
	bigWin = 1, -- en plus, victoire avec 3 buts d'écart ou plus
	vsClub = 1, -- en plus, victoire contre un autre club du serveur
	promotion = 5,
	cupRound = 1, -- tour de Coupe nationale gagné
	cupGiant = 2, -- en plus, exploit contre une division plus haute
	cupChampion = 5,
	tournament = 3, -- tournoi du serveur gagné
	provocativeLoss = -2, -- réponse provocante puis défaite au match suivant
}

Reputation.BIG_MARGIN = 3 -- écart de buts d'un « gros score »
Reputation.STREAK = 5 -- série de victoires qui intéresse la presse
Reputation.PRESS_GAP = 4 -- matchs minimum entre deux conférences
Reputation.PRESS_EXPIRES = 15 * 60 -- une question non répondue disparaît (secondes)

Reputation.BUZZ_MATCHES = 3
Reputation.FANS_BUZZ = 0.10 -- billetterie +10 %
Reputation.SPONSOR_BUZZ = 0.15 -- primes de sponsors (bureaux + contrats) +15 %
Reputation.MORALE_ENERGY = 10 -- énergie rendue aux joueurs
Reputation.SPONSOR_MAX = 0.10 -- contrats : jusqu'à +10 % à 100 de réputation

Reputation.Answers = { "humble", "ambitious", "provocative" }
-- Effet de chaque réponse : réputation tout de suite, buzz pour les matchs suivants.
Reputation.AnswerEffects = {
	humble = { reputation = 1, buzz = "morale" },
	ambitious = { reputation = 2, buzz = "sponsors" },
	provocative = { reputation = 1, buzz = "fans" },
}

-- Sujets de conférence (clé « press.q.<id> » et « press.a.<id>.<réponse> »).
Reputation.Topics = { "promotion", "bigWin", "bigLoss", "streak", "derby", "cupWin", "cupChampion", "tournament" }
-- Sujets qui passent même si une conférence vient d'avoir lieu.
Reputation.PriorityTopics = { promotion = true, cupChampion = true, tournament = true }

-- Paliers affichés (clé « reputation.level.<id> »), du plus haut au plus bas.
Reputation.Levels = {
	{ id = "legend", min = 95 },
	{ id = "famous", min = 80 },
	{ id = "national", min = 60 },
	{ id = "regional", min = 40 },
	{ id = "local", min = 20 },
	{ id = "unknown", min = 0 },
}

local function tierOf(tier: number?): number
	if type(tier) ~= "number" or tier ~= tier then
		return 7
	end
	return math.clamp(math.floor(tier), 1, 7)
end

-- Plafond : D7 40, D6 50… D1 100.
function Reputation.Cap(tier: number?): number
	return math.min(Reputation.MAX, 40 + (7 - tierOf(tier)) * 10)
end

-- Plancher : division et niveau des tribunes (toujours sous le plafond).
function Reputation.Floor(tier: number?, standsLevel: number?): number
	local stands = if type(standsLevel) == "number" and standsLevel == standsLevel then standsLevel else 1
	local floor = 5 + (7 - tierOf(tier)) * 8 + math.clamp(math.floor(stands) - 1, 0, 4) * 2
	return math.min(floor, Reputation.Cap(tier) - 10)
end

function Reputation.Clamp(score: number?, tier: number?, standsLevel: number?): number
	local value = if type(score) == "number" and score == score then score else 0
	return math.clamp(math.floor(value + 0.5), Reputation.Floor(tier, standsLevel), Reputation.Cap(tier))
end

-- Valeur de départ (nouveau club ou ancienne sauvegarde) : un peu au-dessus du plancher.
function Reputation.Initial(tier: number?, standsLevel: number?): number
	return Reputation.Clamp(Reputation.Floor(tier, standsLevel) + 10, tier, standsLevel)
end

function Reputation.Level(score: number): string
	for _, level in Reputation.Levels do
		if score >= level.min then
			return level.id
		end
	end
	return "unknown"
end

-- Multiplicateur des primes fixes des contrats de sponsoring (1 à 1,10).
function Reputation.SponsorMultiplier(score: number?): number
	local value = if type(score) == "number" and score == score then math.clamp(score, 0, 100) else 0
	return 1 + Reputation.SPONSOR_MAX * value / 100
end

function Reputation.IsAnswer(answer): boolean
	return type(answer) == "string" and Reputation.AnswerEffects[answer] ~= nil
end

function Reputation.IsTopic(topic): boolean
	return type(topic) == "string" and table.find(Reputation.Topics, topic) ~= nil
end

--[[
	Sujet de conférence après un match du championnat, ou nil.
	match = { outcome, goalsFor, goalsAgainst, vsClub, promoted, streak }
]]
function Reputation.LeagueTopic(match): string?
	local margin = (match.goalsFor or 0) - (match.goalsAgainst or 0)
	if match.promoted then
		return "promotion"
	elseif match.vsClub and match.outcome == "Win" then
		return "derby"
	elseif margin >= Reputation.BIG_MARGIN then
		return "bigWin"
	elseif (match.streak or 0) > 0 and (match.streak or 0) % Reputation.STREAK == 0 then
		return "streak"
	elseif margin <= -Reputation.BIG_MARGIN then
		return "bigLoss"
	end
	return nil
end

return Reputation
