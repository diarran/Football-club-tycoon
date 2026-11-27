--[[
	Onboarding
	Les 10 premières minutes : onglets débloqués petit à petit, onglet mis
	en avant, et « objectifs de départ » avec une petite récompense.

	Tout est calculé à partir du profil : aucun nouvel état n'est nécessaire
	pour les onglets (un ancien profil qui a déjà joué voit tout de suite
	tous ses onglets). Les objectifs de départ sont suivis dans
	data.onboarding = { goal = n, done = bool } (OnboardingService).

	Les récompenses sont versées une seule fois par profil et restent
	petites (2 450 FC en tout, environ 6 victoires en D7) : la fin de partie
	n'est pas touchée.

	Texte : clés « onboarding.goal.<id> » et « onboarding.lock.<règle> » de Locale.
]]

local Divisions = require(script.Parent.Divisions)

local Onboarding = {}

-- Onglets à débloquer. Les autres (Accueil, Stade, Effectif, Matchs,
-- Paramètres) sont toujours ouverts : le tutoriel en a besoin.
-- tutorial = débloqué à la fin du tutoriel ; matches = nombre de matchs joués.
Onboarding.TAB_RULES = {
	Management = { tutorial = true },
	Ranking = { matches = 3 },
	Prestige = { matches = 5 },
}

-- Onglet mis en avant pendant chaque étape du tutoriel (TutorialSteps).
Onboarding.TUTORIAL_TABS = {
	CheckSquad = "Squad",
	FirstUpgrade = "Stadium",
	FirstMatch = "Matches",
}

local function upgradesDone(data): number
	local total = 0
	for _, level in data.buildings or {} do
		if type(level) == "number" then
			total += math.max(0, level - 1)
		end
	end
	return total
end

local function trainedPlayers(data): number
	local count = 0
	for _, footballer in data.squad or {} do
		if type(footballer) == "table" and (tonumber(footballer.trainedAt) or 0) > 0 then
			count += 1
		end
	end
	return count
end

local function staffHired(data): number
	local count = 0
	for _, level in data.staff or {} do
		if type(level) == "number" and level > 0 then
			count += 1
		end
	end
	return count
end

local function sponsorsSigned(data): number
	local sponsors = data.sponsors
	return if type(sponsors) == "table" and type(sponsors.contracts) == "table" then #sponsors.contracts else 0
end

local function promoted(data): number
	local club = data.club or {}
	return if club.division and club.division ~= Divisions.STARTING_DIVISION then 1 else 0
end

-- Objectifs de départ, dans l'ordre. progress(data) lit le profil serveur
-- (ou l'instantané client, qui a les mêmes champs).
-- tab : onglet où se fait l'action (mis en avant dans le menu).
Onboarding.GOALS = {
	{ id = "Upgrade", target = 2, reward = 250, tab = "Stadium", progress = upgradesDone },
	{
		id = "Win",
		target = 3,
		reward = 300,
		tab = "Matches",
		progress = function(data)
			return (data.club and data.club.stats and data.club.stats.wins) or 0
		end,
	},
	{ id = "Train", target = 1, reward = 300, tab = "Squad", progress = trainedPlayers },
	{ id = "Staff", target = 1, reward = 400, tab = "Management", progress = staffHired },
	{ id = "Sponsor", target = 1, reward = 400, tab = "Management", progress = sponsorsSigned },
	{ id = "Promote", target = 1, reward = 800, tab = "Matches", progress = promoted },
}

function Onboarding.TotalRewards(): number
	local total = 0
	for _, goal in Onboarding.GOALS do
		total += goal.reward
	end
	return total
end

-- Objectif en cours : { id, index, progress, target, reward, tab, ready } ou nil.
-- Les objectifs ne commencent qu'à la fin du tutoriel (un seul message à la fois).
function Onboarding.CurrentGoal(data)
	local state = data.onboarding
	local tutorial = data.tutorial
	if type(state) ~= "table" or state.done or not (tutorial and tutorial.completed) then
		return nil
	end
	local index = tonumber(state.goal) or 1
	local goal = Onboarding.GOALS[index]
	if not goal then
		return nil
	end
	local progress = math.min(goal.target, goal.progress(data))
	return {
		id = goal.id,
		index = index,
		total = #Onboarding.GOALS,
		progress = progress,
		target = goal.target,
		reward = goal.reward,
		tab = goal.tab,
		ready = progress >= goal.target,
	}
end

-- Onglet ouvert ? Renvoie aussi la règle qui le bloque (pour le message).
-- profile : instantané client (tutorial, club.stats, club.division, onboarding).
function Onboarding.TabUnlocked(tabId: string, profile): (boolean, string?)
	local rule = Onboarding.TAB_RULES[tabId]
	if not rule or type(profile) ~= "table" then
		return true, nil
	end
	local onboarding = profile.onboarding
	if profile.adminUnlimited or (type(onboarding) == "table" and onboarding.done) then
		return true, nil
	end
	local club = profile.club or {}
	if club.division and club.division ~= Divisions.STARTING_DIVISION then
		return true, nil
	end
	local completed = profile.tutorial == nil or profile.tutorial.completed
	if rule.tutorial and not completed then
		return false, "tutorial"
	end
	local played = (club.stats and club.stats.played) or 0
	if rule.matches and played < rule.matches then
		return false, "matches"
	end
	return true, nil
end

-- Onglet à mettre en avant (tutoriel en cours, sinon objectif de départ).
function Onboarding.FocusTab(profile, stepId: string?): string?
	if type(profile) ~= "table" then
		return nil
	end
	local tutorial = profile.tutorial
	if tutorial and not tutorial.completed then
		return if stepId then Onboarding.TUTORIAL_TABS[stepId] else nil
	end
	local goal = profile.onboarding and profile.onboarding.current
	return if type(goal) == "table" and not goal.ready then goal.tab else nil
end

return Onboarding
