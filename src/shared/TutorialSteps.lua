--[[
	TutorialSteps
	Étapes du tutoriel guidé (document de conception, section 8).

	Texte affiché : clé « tutorial.<id> » de Locale (Lang/fr.lua, Lang/en.lua).

	completedBy = "client" : étape informative que le client signale
	(menu ouvert, effectif consulté…). Elle ne donne aucune récompense,
	donc le serveur peut l'accepter sans risque si c'est l'étape en cours.
	completedBy = "server" : validée uniquement par une vraie action serveur.
]]

local TutorialSteps = {
	{
		id = "DiscoverPlot",
		completedBy = "client",
	},
	{
		id = "OpenMenu",
		completedBy = "client",
	},
	{
		id = "CheckSquad",
		completedBy = "client",
	},
	{
		id = "FirstUpgrade",
		completedBy = "server",
	},
	{
		id = "FirstMatch",
		completedBy = "server",
	},
	{
		id = "SeeRewards",
		completedBy = "client",
	},
}

return TutorialSteps
