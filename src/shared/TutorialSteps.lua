--[[
	TutorialSteps
	Étapes du tutoriel guidé (document de conception, section 8).

	completedBy = "client" : étape informative que le client signale
	(menu ouvert, effectif consulté…). Elle ne donne aucune récompense,
	donc le serveur peut l'accepter sans risque si c'est l'étape en cours.
	completedBy = "server" : validée uniquement par une vraie action serveur.
]]

local TutorialSteps = {
	{
		id = "DiscoverPlot",
		text = "Bienvenue ! Voici ton terrain. Fais le tour de ton futur stade.",
		completedBy = "client",
	},
	{
		id = "OpenMenu",
		text = "Ouvre le menu de gestion avec le bouton « Club ».",
		completedBy = "client",
	},
	{
		id = "CheckSquad",
		text = "Consulte ton solde de FC Coins et ton effectif dans l'onglet « Effectif ».",
		completedBy = "client",
	},
	{
		id = "FirstUpgrade",
		text = "Améliore une première installation dans l'onglet « Stade ».",
		completedBy = "server",
	},
	{
		id = "FirstMatch",
		text = "Choisis un adversaire dans l'onglet « Matchs » et lance un match simulé.",
		completedBy = "server",
	},
	{
		id = "SeeRewards",
		text = "Bravo ! Consulte tes récompenses, puis vise la montée en D6.",
		completedBy = "client",
	},
}

return TutorialSteps
