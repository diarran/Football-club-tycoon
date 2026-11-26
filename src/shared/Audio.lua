--[[
	Audio
	Réglages de l'ambiance sonore : quels sons, à quel volume, et la règle
	« plus le stade est grand, plus le public est fort ».

	Deux sources de sons, essayées dans cet ordre :
	1. Les sons glissés dans Studio dans ReplicatedStorage > Sons, avec le nom de
	   la clé (« Musique », « Foule », « Chants », « Clameur », « Sifflet »,
	   « But », « Clic », « Piece »). Voir GUIDE_PUBLICATION.md, partie Sons.
	2. Les sons listés ci-dessous. Les adresses « rbxasset://sounds/… » sont
	   livrées avec Roblox sur tous les appareils (aucun droit, aucun ID privé).
	   On essaie chaque adresse jusqu'à en trouver une qui se charge.

	Un son introuvable est simplement muet : il ne bloque jamais le jeu.
]]

local Audio = {}

-- Nom du dossier de ReplicatedStorage où l'on peut glisser ses propres sons.
Audio.OVERRIDE_FOLDER = "Sons"

-- Groupes : chacun a son volume, multiplié par le volume général des Paramètres.
Audio.GROUPS = {
	Music = 0.5,
	Ambience = 0.8,
	Effects = 1,
}

-- group : groupe de volume ; looped : en boucle ; ids : adresses à essayer.
Audio.SOUNDS = {
	Musique = { group = "Music", volume = 0.35, looped = true, ids = {} },
	Foule = { group = "Ambience", volume = 0.5, looped = true, ids = {} },
	Chants = { group = "Ambience", volume = 0.45, looped = true, ids = {} },
	Clameur = { group = "Ambience", volume = 0.8, ids = {} },
	Sifflet = { group = "Effects", volume = 0.5, ids = {} },
	But = {
		group = "Effects",
		volume = 0.6,
		ids = { "rbxasset://sounds/victory.wav", "rbxasset://sounds/victory.mp3" },
	},
	Clic = {
		group = "Effects",
		volume = 0.35,
		ids = { "rbxasset://sounds/button.wav", "rbxasset://sounds/switch.wav", "rbxasset://sounds/button.mp3" },
	},
	Piece = {
		group = "Effects",
		volume = 0.3,
		ids = { "rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/electronicpingshort.mp3" },
	},
}

-- Paliers proposés dans les Paramètres (0 = muet).
Audio.VOLUME_STEPS = { 0, 0.25, 0.5, 0.75, 1 }
Audio.DEFAULT_VOLUME = 0.75

-- Pendant un match, la musique baisse pour laisser place au public.
Audio.MUSIC_DUCK = 0.25

-- Les chants du public commencent avec les tribunes de niveau 3.
Audio.CHANTS_FROM_LEVEL = 3

local function level(stadiumLevel: any): number
	return math.clamp(math.floor(tonumber(stadiumLevel) or 1), 1, 5)
end

-- Volume du brouhaha de la foule (0..1) selon le niveau des tribunes (1 à 5).
function Audio.CrowdVolume(stadiumLevel: any): number
	return 0.25 + 0.15 * (level(stadiumLevel) - 1)
end

-- Volume des chants (0 en dessous du niveau 3, puis de plus en plus fort).
function Audio.ChantVolume(stadiumLevel: any): number
	local l = level(stadiumLevel)
	if l < Audio.CHANTS_FROM_LEVEL then
		return 0
	end
	return 0.4 + 0.2 * (l - Audio.CHANTS_FROM_LEVEL)
end

-- Clameur après un but : plus forte dans un grand stade.
function Audio.RoarVolume(stadiumLevel: any): number
	return 0.5 + 0.125 * (level(stadiumLevel) - 1)
end

-- Ramène une valeur reçue au palier de volume le plus proche.
function Audio.ClampVolume(value: any): number
	local v = tonumber(value)
	if not v or v ~= v then
		return Audio.DEFAULT_VOLUME
	end
	return math.clamp(v, 0, 1)
end

return Audio
