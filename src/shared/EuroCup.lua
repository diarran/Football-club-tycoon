--[[
	EuroCup
	Coupe d'Europe des clubs : une compétition par semaine entre les clubs de
	VRAIS joueurs, tous serveurs confondus (règles partagées serveur / client).

	Fonctionnement « asynchrone » :
	- Chaque club de D3, D2 ou D1 publie régulièrement une « photo » de son
	  équipe (titulaires, notes, tactique, bonus) dans un réservoir commun à
	  tous les serveurs (MemoryStore, une liste par semaine).
	- En s'inscrivant, le club reçoit un groupe de 8 clubs : lui et les 7 clubs
	  du réservoir dont la force est la plus proche (clubs du serveur et clubs
	  fictifs en complément si le réservoir est vide ou indisponible).
	- Les adversaires n'ont pas besoin d'être connectés : on joue contre leur
	  photo. Les autres matchs du groupe sont simulés en même temps.
	- Phase de groupe : 7 journées (chaque club rencontre les 7 autres une
	  fois). Les 4 premiers vont en demi-finale (1er contre 4e, 2e contre 3e),
	  puis finale contre le vainqueur de l'autre demi-finale.
	- Un match au plus toutes les MATCH_SECONDS (temps réel), joué quand le
	  joueur le décide. Match neutre : pas d'énergie, pas de points de division.
	  Phase finale : un nul se règle aux tirs au but (50/50 serveur).
	- Une édition par saison (lundi 00:00 UTC, comme Daily.lua) : l'édition
	  repart de zéro le lundi, même si elle n'était pas finie.

	Primes (× multiplicateur de la division du club) : victoire et nul de groupe,
	qualification, demi-finale gagnée, finale gagnée. Maximum de base 3 750
	(D1 : 11 250 FC par semaine), du même ordre que la Coupe nationale (voir
	docs/economy/README.md). Vainqueur : trophée « Coupe d'Europe » (stat
	euroWon) dans la vitrine.

	Textes : clés « euro.* » de Locale.
]]

local Daily = require(script.Parent.Daily)
local Divisions = require(script.Parent.Divisions)
local Tactics = require(script.Parent.Tactics)

local EuroCup = {}

-- Division minimale pour participer (index de Divisions.List : D3 = 5).
EuroCup.UNLOCK_DIVISION = "D3"

EuroCup.GROUP_SIZE = 8
EuroCup.GROUP_ROUNDS = EuroCup.GROUP_SIZE - 1 -- 7 journées
EuroCup.QUALIFIED = 4 -- les 4 premiers vont en demi-finale

-- Temps réel minimum entre deux matchs européens d'un même club.
EuroCup.MATCH_SECONDS = 30 * 60

-- Réservoir commun (MemoryStore) : une liste par édition.
EuroCup.POOL_PREFIX = "EuroPool_v1_"
EuroCup.POOL_READ_COUNT = 200 -- clubs lus au plus pour former un groupe
EuroCup.POOL_CACHE_SECONDS = 60 -- lecture partagée par tous les joueurs du serveur
EuroCup.PUBLISH_SECONDS = 15 * 60 -- photo du club republiée au plus toutes les 15 min
EuroCup.POOL_EXPIRATION_EXTRA = 24 * 3600 -- la liste expire un jour après la fin de l'édition

-- Photo d'un club : bornes de sécurité (données venant d'autres serveurs).
EuroCup.MAX_SNAPSHOT_PLAYERS = 11
EuroCup.MAX_NAME_LENGTH = 40

-- Primes de base (FC Coins, × multiplicateur de division).
EuroCup.REWARDS = {
	groupWin = 150,
	groupDraw = 50,
	qualified = 300,
	semiWin = 800,
	finalWin = 1600,
}

-- Étapes : "group", "semi", "final" (affichage « euro.stage.<id> »).
function EuroCup.Edition(t: number): number
	return Daily.SeasonId(t)
end

function EuroCup.EditionEndsAt(edition: number): number
	return Daily.SeasonEndsAt(edition)
end

function EuroCup.IsEligible(divisionId: string?): boolean
	local division = Divisions.Get(divisionId or "")
	local unlock = Divisions.Get(EuroCup.UNLOCK_DIVISION)
	return division ~= nil and unlock ~= nil and division.index >= unlock.index
end

function EuroCup.Reward(kind: string, divisionId: string): number
	local base = EuroCup.REWARDS[kind]
	if not base then
		return 0
	end
	local division = Divisions.Get(divisionId)
	return math.floor(base * (division and division.rewardMultiplier or 1) + 0.5)
end

-- Total maximum d'une édition (toutes les journées gagnées puis le titre).
function EuroCup.MaxReward(divisionId: string): number
	return EuroCup.Reward("groupWin", divisionId) * EuroCup.GROUP_ROUNDS
		+ EuroCup.Reward("qualified", divisionId)
		+ EuroCup.Reward("semiWin", divisionId)
		+ EuroCup.Reward("finalWin", divisionId)
end

-- Calendrier « en cercle » : 7 journées, chaque club joue une fois par journée
-- et rencontre les 7 autres exactement une fois. Renvoie 4 paires { a, b }
-- (index dans le groupe). Le club 1 (le joueur) est toujours dans la 1re paire.
function EuroCup.Fixtures(round: number)
	local n = EuroCup.GROUP_SIZE
	local others = {}
	for i = 2, n do
		table.insert(others, i)
	end
	-- Rotation des clubs 2..8 de (round - 1) crans.
	local rotated = {}
	for i = 1, n - 1 do
		rotated[i] = others[((i - 1 + round - 1) % (n - 1)) + 1]
	end
	local circle = { 1 }
	for _, index in rotated do
		table.insert(circle, index)
	end
	local matches = {}
	for i = 1, n / 2 do
		table.insert(matches, { circle[i], circle[n + 1 - i] })
	end
	return matches
end

-- Force affichée d'une photo de club (moyenne des notes + bonus).
function EuroCup.Strength(snapshot): number
	local squad = snapshot and snapshot.s
	if type(squad) ~= "table" or #squad == 0 then
		return 0
	end
	local total = 0
	for _, footballer in squad do
		total += footballer.r or 0
	end
	return math.floor(total / #squad + (snapshot.b or 0) + 0.5)
end

local POSITIONS = { GK = true, DEF = true, MID = true, ATT = true }

-- Vérifie et nettoie une photo venue d'un autre serveur. Renvoie nil si elle
-- est inutilisable (jamais d'erreur).
function EuroCup.SanitizeSnapshot(value)
	if type(value) ~= "table" then
		return nil
	end
	local userId = tonumber(value.u)
	if not userId or userId ~= userId or userId <= 0 or userId ~= math.floor(userId) then
		return nil
	end
	if type(value.n) ~= "string" or #value.n == 0 then
		return nil
	end
	if not Divisions.Get(value.d) or not EuroCup.IsEligible(value.d) then
		return nil
	end
	if type(value.s) ~= "table" then
		return nil
	end
	local squad = {}
	for _, footballer in value.s do
		if #squad >= EuroCup.MAX_SNAPSHOT_PLAYERS then
			break
		end
		if type(footballer) == "table" and type(footballer.n) == "string" and POSITIONS[footballer.p] then
			local rating = tonumber(footballer.r)
			if rating and rating == rating then
				table.insert(squad, {
					n = string.sub(footballer.n, 1, EuroCup.MAX_NAME_LENGTH),
					p = footballer.p,
					r = math.clamp(math.floor(rating), 1, 99),
				})
			end
		end
	end
	if #squad == 0 then
		return nil
	end
	local bonus = tonumber(value.b) or 0
	if bonus ~= bonus then
		bonus = 0
	end
	return {
		u = userId,
		n = string.sub(value.n, 1, EuroCup.MAX_NAME_LENGTH),
		d = value.d,
		s = squad,
		t = Tactics.Sanitize(value.t),
		b = math.clamp(math.floor(bonus), -10, 15),
	}
end

return EuroCup
