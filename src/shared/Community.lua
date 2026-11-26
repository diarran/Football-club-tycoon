--[[
	Community
	Boutons « Soutiens le jeu » de l'accueil : favori, groupe Roblox, J'aime.

	- Favori : fenêtre officielle de Roblox (le jeu doit être publié).
	- Groupe : fenêtre officielle « Rejoindre le groupe ». Bonus unique de
	  GROUP_REWARD FC Coins, vérifié par le serveur (le joueur doit vraiment
	  être membre). Le bouton reste caché tant que GROUP_ID vaut 0.
	- J'aime : Roblox n'offre aucune fenêtre pour ça, on affiche un rappel.
	  Règle Roblox : aucune récompense pour un favori ou un J'aime.

	POUR NJ : après avoir créé ton groupe Roblox, colle son numéro dans
	GROUP_ID (il est dans l'adresse de la page du groupe :
	roblox.com/communities/12345678/... → 12345678).
]]

local Community = {}

Community.GROUP_ID = 0
Community.GROUP_REWARD = 1000

function Community.GroupEnabled(): boolean
	return type(Community.GROUP_ID) == "number" and Community.GROUP_ID > 0
end

return Community
