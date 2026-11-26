--[[
	AdminConfig (serveur uniquement, jamais envoyé aux joueurs)
	Réglages du code admin « argent illimité ».

	Qui peut utiliser le code ?
	- le propriétaire du jeu sur Roblox (le compte qui l'a publié) ;
	- le propriétaire d'un groupe Roblox, si le jeu est publié dans un groupe ;
	- les comptes listés dans ADMIN_USER_IDS ;
	- tout le monde quand on teste dans Roblox Studio.
	Pour tous les autres joueurs, le champ n'apparaît pas et le code est
	refusé même s'il est juste : un code divulgué ne sert donc à rien.

	Le dépôt est public : on n'écrit JAMAIS le code ici, seulement son
	empreinte (CODE_SHA256). Pour changer de code, demander à Claude d'en
	générer un nouveau : il remplace l'empreinte et donne le code en privé.
]]

local AdminConfig = {}

-- Empreinte SHA-256 de SALT .. code (code en majuscules, sans espaces ni tirets).
AdminConfig.SALT = "fct-admin:79b8dbaec8da16c2:"
AdminConfig.CODE_SHA256 = "9d957972d6706b5233386c53413a8a8ef15558492b2507f6c4f25457200bcb6b"

-- Identifiants Roblox (UserId) d'autres administrateurs, ex. { 123456789 }.
AdminConfig.ADMIN_USER_IDS = {}

-- Protection contre les essais au hasard : après MAX_ATTEMPTS codes faux,
-- le joueur est bloqué LOCK_SECONDS secondes.
AdminConfig.MAX_ATTEMPTS = 5
AdminConfig.LOCK_SECONDS = 600
AdminConfig.MAX_CODE_LENGTH = 40

return AdminConfig
