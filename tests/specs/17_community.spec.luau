-- Accueil « Soutiens le jeu » : favori, groupe Roblox (bonus unique vérifié
-- par le serveur), rappel J'aime. Rien n'apparaît tant que ce n'est pas configuré.
local S = H.boot(MODULES)
local Community = mock.run(MODULES.Community)
local CommunityService = mock.run(MODULES.CommunityService)

local members = {} -- [UserId] = true : membres du groupe pour Roblox
local favorites, groupPrompts = {}, {}
local promptAnswer = Enum.GroupMembershipStatus.Joined

local function join(userId: number)
	local p = H.join(userId)
	p.IsInGroupAsync = function(self, groupId)
		task.wait(1) -- la vraie fonction attend la réponse de Roblox
		return groupId == Community.GROUP_ID and members[self.UserId] == true
	end
	return p
end

game:GetService("AvatarEditorService").PromptSetFavorite = function(_self, id, itemType, value)
	table.insert(favorites, { id = id, itemType = itemType, value = value })
end
game:GetService("GroupService").PromptJoinAsync = function(_self, groupId)
	table.insert(groupPrompts, groupId)
	members[H.localPlayer.UserId] = promptAnswer == Enum.GroupMembershipStatus.Joined or nil
	return promptAnswer
end

local p = join(1)
local data = S.PlayerDataService.GetData(p)

H.test("par défaut : groupe non configuré, aucun bonus possible", function()
	H.eq(Community.GROUP_ID, 0, "pas de groupe")
	H.eq(CommunityService.ClaimGroupReward(p), "disabled", "refusé")
	H.eq(data.community.groupRewardClaimed, false, "rien reçu")
end)

local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)

H.test("client : rappel J'aime, pas de boutons si le jeu n'est pas publié", function()
	UI.SetMenuOpen(true)
	UI.OpenTab("Home")
	H.flush()
	H.ok(H.findText(gui, "Soutiens le jeu"), "carte affichée")
	H.ok(H.findText(gui, "J'aime"), "rappel J'aime")
	H.eq(H.findText(gui, "Ajouter aux favoris"), nil, "pas de favori sans PlaceId")
	H.eq(H.findText(gui, "Rejoindre le groupe"), nil, "pas de groupe sans GROUP_ID")
end)

Community.GROUP_ID = 4242
H.game.PlaceId = 777

H.test("bonus de groupe : seulement pour un vrai membre, une seule fois", function()
	local p3 = join(3)
	local data3 = S.PlayerDataService.GetData(p3)
	local before = data3.coins
	local result
	task.spawn(function()
		result = CommunityService.ClaimGroupReward(p3)
	end)
	H.advance(2)
	H.eq(result, "notMember", "pas encore membre")
	H.eq(data3.coins, before, "rien reçu")

	members[3] = true
	local results = {}
	for _ = 1, 3 do -- demandes rapides en même temps
		task.spawn(function()
			table.insert(results, CommunityService.ClaimGroupReward(p3))
		end)
	end
	H.advance(2)
	H.eq(table.find(results, "granted") ~= nil, true, "accordé")
	local granted = 0
	for _, r in results do
		granted += if r == "granted" then 1 else 0
	end
	H.eq(granted, 1, "une seule fois malgré les demandes simultanées")
	H.eq(data3.coins, before + Community.GROUP_REWARD, "bonus versé")
	H.eq(data3.community.groupRewardClaimed, true, "noté dans le profil")
end)

H.test("client : favori et groupe ouvrent les fenêtres de Roblox, bonus versé", function()
	local p2, data2 = p, data
	UI.OpenTab("Home")
	H.flush()
	H.click(gui, "Ajouter aux favoris")
	H.eq(#favorites, 1, "fenêtre favori")
	H.eq(favorites[1].id, 777, "le jeu (PlaceId)")
	H.eq(favorites[1].value, true, "ajout aux favoris")

	local before = data2.coins
	H.click(gui, "Rejoindre le groupe")
	H.advance(3)
	H.eq(groupPrompts[#groupPrompts], 4242, "fenêtre du bon groupe")
	H.eq(data2.coins, before + Community.GROUP_REWARD, "bonus versé")
	H.ok(H.lastNotify(p2):find("Merci", 1, true), "remerciement")
	H.eq(#H.errors, 0, "aucune erreur")
end)

H.test("règle Roblox : aucune récompense pour un favori ou un J'aime", function()
	H.eq(Community.FAVORITE_REWARD, nil, "pas de bonus favori")
	H.eq(Community.LIKE_REWARD, nil, "pas de bonus J'aime")
end)
