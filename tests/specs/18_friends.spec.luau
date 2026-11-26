-- Clubs entre amis : amis Roblox repérés par le serveur, matchs amicaux
-- (sans mise, petit bonus limité par jour) et primes d'invitation
-- (parrainage Roblox : une fois par ami, plafonnées, même inviteur absent).
local S = H.boot(MODULES)
local Friends = mock.run(MODULES.Friends)
local FriendService = mock.run(MODULES.FriendService)
local C = S.Config.Challenge

-- Amitiés Roblox simulées : paires d'UserId.
local friendships = { ["1:2"] = true }
FriendService.IsFriendsWith = function(x, y)
	task.wait(0.5) -- la vraie fonction attend la réponse de Roblox
	local i, j = math.min(x.UserId, y.UserId), math.max(x.UserId, y.UserId)
	return friendships[i .. ":" .. j] == true
end
-- Données d'arrivée : ReferredByPlayerId de chaque joueur.
local referrals = {}
FriendService.ReadJoinData = function(p)
	return { ReferredByPlayerId = referrals[p.UserId] or 0 }
end

local a = H.join(1, "Alice")
local b = H.join(2, "Bruno")
local c = H.join(3, "Chloé")
H.advance(2)
local da = S.PlayerDataService.GetData(a)
local db = S.PlayerDataService.GetData(b)
local dc = S.PlayerDataService.GetData(c)

local function ids(p)
	return table.concat(S.PlayerDataService.BuildSnapshot(p).friends.clubIds, ",")
end

local function snap(p)
	return S.PlayerDataService.BuildSnapshot(p).friends
end

local function lastResult(p)
	local list = H.received(p, "MatchResult")
	return list[#list] and list[#list][1]
end

local function incomingId(p)
	local list = H.received(p, "ChallengeUpdated")
	local state = list[#list] and list[#list][1]
	return state and state.incoming[1] and state.incoming[1].id, state and state.incoming[1]
end

local function settle()
	H.advance(math.max(C.SEND_COOLDOWN_SECONDS, C.PAIR_COOLDOWN_SECONDS, C.EXPIRE_SECONDS) + 1)
end

local function playFriendly(from, to, stake)
	H.fire(from, "RequestChallenge", "player:" .. to.UserId, stake or 0)
	local id = incomingId(to)
	H.fire(to, "RequestChallengeResponse", id, true)
	return lastResult(from), lastResult(to)
end

H.test("amis Roblox repérés par le serveur : liste dans l'instantané", function()
	H.ok(FriendService.AreFriends(a, b), "Alice et Bruno sont amis")
	H.ok(not FriendService.AreFriends(a, c), "Alice et Chloé ne le sont pas")
	H.eq(ids(a), "player:2", "Alice voit Bruno comme ami")
	H.eq(ids(b), "player:1", "Bruno voit Alice")
	H.eq(ids(c), "", "Chloé n'a pas d'ami ici")
	H.eq(snap(a).friendlyLeft, Friends.FRIENDLY_BONUS_PER_DAY, "matchs amicaux du jour")
end)

H.test("match amical entre amis : sans mise, petit bonus pour chacun", function()
	da.coins, db.coins = 3000, 3000
	H.fire(a, "RequestChallenge", "player:2", 0)
	local _, entry = incomingId(b)
	H.ok(entry and entry.friendly, "Bruno voit un match amical")
	H.ok(H.lastNotify(b):find("match amical"), "Bruno est prévenu")
	H.fire(b, "RequestChallengeResponse", entry.id, true)
	local ra, rb = lastResult(a), lastResult(b)
	H.eq(ra.friendly, true, "résultat amical (Alice)")
	H.eq(rb.friendly, true, "résultat amical (Bruno)")
	H.eq(ra.friendlyBonus, Friends.FRIENDLY_BONUS, "bonus Alice")
	H.eq(da.coins, 3000 + Friends.FRIENDLY_BONUS, "solde d'Alice")
	H.eq(db.coins, 3000 + Friends.FRIENDLY_BONUS, "solde de Bruno")
	H.eq(snap(a).friendlyLeft, Friends.FRIENDLY_BONUS_PER_DAY - 1, "un bonus utilisé")
end)

H.test("bonus amical limité par jour, puis renouvelé le lendemain", function()
	for _ = 2, Friends.FRIENDLY_BONUS_PER_DAY do
		settle()
		playFriendly(a, b)
	end
	H.eq(snap(a).friendlyLeft, 0, "plus de bonus aujourd'hui")
	settle()
	local before = da.coins + db.coins
	local ra = playFriendly(a, b)
	H.eq(ra.friendly, true, "le match amical reste possible")
	H.eq(ra.friendlyBonus, 0, "mais sans bonus")
	H.eq(da.coins + db.coins, before, "aucune monnaie créée")
	H.advance(S.Daily.DAY_SECONDS)
	H.eq(snap(a).friendlyLeft, Friends.FRIENDLY_BONUS_PER_DAY, "nouveau jour : bonus revenus")
end)

H.test("pas de bonus : défi avec mise entre amis, ou sans mise avec un non-ami", function()
	settle()
	da.coins, db.coins, dc.coins = 3000, 3000, 3000
	local ra = playFriendly(a, b, 100)
	H.ok(not ra.friendly, "défi avec mise = défi normal")
	H.eq(da.coins + db.coins, 6000, "mise seulement échangée")
	settle()
	da.coins, dc.coins = 3000, 3000
	local rc = playFriendly(c, a, 0)
	H.ok(not rc.friendly, "Chloé n'est pas amie d'Alice")
	H.eq(da.coins + dc.coins, 6000, "aucun bonus")
end)

H.test("invitation : bienvenue pour l'ami, prime pour l'inviteur, une seule fois", function()
	H.leave(c)
	local before = da.coins
	referrals[10] = 1
	local p10 = H.join(10, "Invité")
	local d10 = S.PlayerDataService.GetData(p10)
	H.eq(d10.coins, S.Config.STARTING_COINS + Friends.INVITEE_WELCOME, "bonus de bienvenue")
	H.eq(da.coins, before + Friends.INVITER_REWARD, "prime d'Alice")
	H.eq(snap(a).rewardsGiven, 1, "1 ami invité")
	H.ok(H.lastNotify(a):find("invitation"), "Alice est prévenue")
	-- Revient avec le même lien : rien de plus.
	H.leave(p10)
	H.join(10, "Invité")
	d10 = S.PlayerDataService.GetData(H.Players:GetPlayerByUserId(10))
	H.eq(d10.coins, S.Config.STARTING_COINS + Friends.INVITEE_WELCOME, "pas de second bonus")
	H.eq(da.coins, before + Friends.INVITER_REWARD, "pas de seconde prime")
	H.leave(H.Players:GetPlayerByUserId(10))
end)

H.test("invitation : valeurs invalides ou soi-même refusées", function()
	local before = da.coins
	for index, bad in { 0, -5, 0 / 0, math.huge, "1" } do
		local id = 20 + index
		referrals[id] = bad
		local p = H.join(id)
		local d = S.PlayerDataService.GetData(p)
		H.eq(d.friends.welcomeClaimed, false, "aucun bonus pour " .. tostring(bad))
		H.leave(p)
	end
	referrals[11] = 11
	local p11 = H.join(11)
	H.eq(S.PlayerDataService.GetData(p11).friends.welcomeClaimed, false, "pas d'auto-parrainage")
	H.leave(p11)
	H.eq(da.coins, before, "Alice ne reçoit rien")
end)

H.test("prime d'invitation plafonnée", function()
	for i = 1, Friends.MAX_INVITER_REWARDS + 3 do
		local id = 100 + i
		referrals[id] = 2
		local p = H.join(id)
		H.leave(p)
	end
	H.eq(db.friends.rewardsGiven, Friends.MAX_INVITER_REWARDS, "plafond respecté")
end)

H.test("inviteur absent : la prime l'attend jusqu'à sa prochaine connexion", function()
	referrals[50] = 99
	local p50 = H.join(50)
	H.advance(1)
	H.eq(S.PlayerDataService.GetData(p50).friends.welcomeClaimed, true, "l'invité a son bonus")
	H.leave(p50)
	local p99 = H.join(99, "Absent")
	H.advance(1)
	local d99 = S.PlayerDataService.GetData(p99)
	H.eq(d99.friends.rewardsGiven, 1, "prime versée à l'arrivée")
	H.eq(d99.coins, S.Config.STARTING_COINS + Friends.INVITER_REWARD, "solde")
	H.leave(p99)
	local again = H.join(99, "Absent")
	H.advance(1)
	H.eq(S.PlayerDataService.GetData(again).friends.rewardsGiven, 1, "jamais versée deux fois")
	H.leave(again)
end)

H.test("un ami qui part disparaît de la liste", function()
	H.leave(b)
	H.eq(ids(a), "", "Bruno parti")
	b = H.join(2, "Bruno")
	H.advance(1)
	db = S.PlayerDataService.GetData(b)
	H.eq(ids(a), "player:2", "Bruno revenu")
end)

H.test("client : carte Amis, invitation Roblox, étiquette Ami et bouton Match amical", function()
	local invites = {}
	local social = game:GetService("SocialService")
	social.CanSendGameInviteAsync = function(_self, p)
		return p == a
	end
	social.PromptGameInvite = function(_self, p, options)
		table.insert(invites, { player = p, options = options })
	end
	settle()
	local gui = H.startClient(MODULES, a)
	local UI = mock.run(MODULES.Client_UIController)
	UI.SetMenuOpen(true)
	UI.OpenTab("Ranking")
	H.flush()
	H.ok(H.findText(gui, "Amis venus jouer"), "carte Amis")
	H.ok(H.findText(gui, "Inviter des amis"), "bouton Inviter")
	H.click(gui, "Inviter des amis")
	H.flush()
	H.eq(#invites, 1, "fenêtre d'invitation Roblox ouverte")
	H.ok(H.findText(gui, "· Ami"), "club de Bruno marqué Ami")
	H.click(gui, "Match amical")
	H.flush()
	local id, entry = incomingId(b)
	H.ok(id and entry.friendly, "match amical envoyé à Bruno")
	H.fire(b, "RequestChallengeResponse", id, true)
	H.flush()
	H.ok(H.findText(gui, "Match amical terminé") or H.findText(gui, "Tu as gagné"), "résultat affiché")
end)
