--[[
	Injuries
	Blessures, cartons et suspensions des footballeurs (gestion simple et pas
	frustrante).

	- Blessure : rare après un match (titulaires seulement), plus fréquente
	  quand le joueur était fatigué. Elle dure quelques MINUTES RÉELLES
	  (MIN_MINUTES à MAX_MINUTES), même hors ligne. Le médecin du staff
	  raccourcit la blessure (effet injuryReduction).
	- Cartons : un carton rouge = suspendu pour le prochain match.
	  YELLOWS_FOR_BAN cartons jaunes cumulés = suspendu pour le prochain match
	  (le compteur repart à zéro).
	- Suspension : se purge en jouant un match du championnat (le joueur
	  suspendu ne joue pas ce match).
	- Un joueur blessé ou suspendu ne peut pas être titulaire : la composition
	  le remplace automatiquement par le meilleur remplaçant disponible, et il
	  retrouve sa place dès qu'il est rétabli (s'il n'a pas été changé).
	- S'il manque des titulaires (petit effectif), l'équipe joue à moins avec
	  un petit malus (MISSING_PENALTY par joueur absent).

	Partagé client/serveur : l'interface affiche les mêmes calculs.
	Champs d'un footballeur : injuredUntil (os.time, 0 = en forme),
	suspended (matchs à purger), yellows (cartons jaunes en cours).
	Les anciens profils n'ont pas ces champs : ils valent « en forme ».
]]

local Injuries = {}

Injuries.BASE_CHANCE = 0.012 -- chance de blessure par titulaire et par match
Injuries.TIRED_ENERGY = 50 -- sous ce niveau d'énergie, le risque augmente
Injuries.TIRED_EXTRA_CHANCE = 0.05 -- risque en plus à 0 % d'énergie
Injuries.MIN_MINUTES = 4 -- durée d'une blessure (minutes réelles)
Injuries.MAX_MINUTES = 12
Injuries.YELLOW_CHANCE = 0.05 -- carton jaune par titulaire et par match
Injuries.RED_CHANCE = 0.006 -- carton rouge par titulaire et par match
Injuries.YELLOWS_FOR_BAN = 2
Injuries.BAN_MATCHES = 1
Injuries.MAX_SUSPENSION = 3 -- borne de sécurité (profil abîmé)
Injuries.MISSING_PENALTY = 2 -- points de note en moins par titulaire absent

local function number(value, default)
	value = tonumber(value)
	if value == nil or value ~= value then
		return default
	end
	return value
end

-- Secondes de blessure restantes (0 = en forme).
function Injuries.InjuryLeft(footballer, now: number): number
	return math.max(0, number(footballer.injuredUntil, 0) - now)
end

function Injuries.IsInjured(footballer, now: number): boolean
	return Injuries.InjuryLeft(footballer, now) > 0
end

function Injuries.IsSuspended(footballer): boolean
	return number(footballer.suspended, 0) > 0
end

function Injuries.IsAvailable(footballer, now: number): boolean
	return not Injuries.IsInjured(footballer, now) and not Injuries.IsSuspended(footballer)
end

-- Chance de blessure pour un titulaire selon son énergie AVANT le match.
function Injuries.InjuryChance(energy: number?): number
	energy = math.clamp(number(energy, 100), 0, 100)
	local tired = math.max(0, Injuries.TIRED_ENERGY - energy) / Injuries.TIRED_ENERGY
	return Injuries.BASE_CHANCE + Injuries.TIRED_EXTRA_CHANCE * tired
end

-- Durée d'une blessure en secondes, raccourcie par le médecin (0 à 0,6).
function Injuries.Duration(minutes: number, reduction: number?): number
	local factor = 1 - math.clamp(number(reduction, 0), 0, 0.9)
	return math.max(60, math.floor(minutes * 60 * factor + 0.5))
end

-- Tire les événements d'un titulaire après un match (au plus un par joueur).
-- rng : Random ; energyBefore : énergie avant le match ; reduction : effet du
-- médecin. Modifie le footballeur et renvoie l'événement, ou nil.
-- Événements : { kind = "injury", minutes = n } | { kind = "red" }
-- | { kind = "yellow", banned = bool }.
function Injuries.Roll(rng, footballer, energyBefore: number, reduction: number?, now: number)
	local roll = rng:NextNumber()
	local injuryChance = Injuries.InjuryChance(energyBefore)
	if roll < injuryChance then
		local minutes = rng:NextInteger(Injuries.MIN_MINUTES, Injuries.MAX_MINUTES)
		local seconds = Injuries.Duration(minutes, reduction)
		footballer.injuredUntil = now + seconds
		return { kind = "injury", name = footballer.name, id = footballer.id, minutes = math.ceil(seconds / 60) }
	end
	roll -= injuryChance
	if roll < Injuries.RED_CHANCE then
		footballer.suspended = math.min(Injuries.MAX_SUSPENSION, number(footballer.suspended, 0) + Injuries.BAN_MATCHES)
		return { kind = "red", name = footballer.name, id = footballer.id }
	end
	roll -= Injuries.RED_CHANCE
	if roll < Injuries.YELLOW_CHANCE then
		local yellows = number(footballer.yellows, 0) + 1
		local banned = yellows >= Injuries.YELLOWS_FOR_BAN
		if banned then
			yellows = 0
			footballer.suspended =
				math.min(Injuries.MAX_SUSPENSION, number(footballer.suspended, 0) + Injuries.BAN_MATCHES)
		end
		footballer.yellows = yellows
		return { kind = "yellow", name = footballer.name, id = footballer.id, banned = banned }
	end
	return nil
end

-- Un match du club a été joué sans ce joueur suspendu : un match purgé.
-- Renvoie true si le joueur peut rejouer.
function Injuries.ServeSuspension(footballer): boolean
	local left = number(footballer.suspended, 0)
	if left <= 0 then
		return false
	end
	footballer.suspended = left - 1
	return footballer.suspended <= 0
end

-- Remet des valeurs saines (anciens profils, valeurs abîmées). Une blessure
-- plus longue que le maximum possible (horloge changée) est ramenée au maximum.
function Injuries.Sanitize(footballer, now: number)
	local untilTime = number(footballer.injuredUntil, 0)
	local maxLeft = Injuries.MAX_MINUTES * 60
	if untilTime <= now then
		untilTime = 0
	elseif untilTime - now > maxLeft then
		untilTime = now + maxLeft
	end
	footballer.injuredUntil = untilTime
	footballer.suspended = math.clamp(math.floor(number(footballer.suspended, 0)), 0, Injuries.MAX_SUSPENSION)
	footballer.yellows = math.clamp(math.floor(number(footballer.yellows, 0)), 0, Injuries.YELLOWS_FOR_BAN - 1)
end

return Injuries
