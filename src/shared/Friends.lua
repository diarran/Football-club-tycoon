--[[
	Friends
	Clubs entre amis : invitations Roblox, indicateur « Ami », matchs amicaux.

	- Inviter : fenêtre officielle de Roblox (SocialService). Quand un ami
	  rejoint le jeu grâce à une invitation ou un lien de parrainage Roblox,
	  le serveur le voit (GetJoinData().ReferredByPlayerId) :
	    • l'ami reçoit INVITEE_WELCOME une seule fois par compte ;
	    • celui qui a invité reçoit INVITER_REWARD une fois par ami,
	      MAX_INVITER_REWARDS fois au maximum (même s'il n'est pas sur le
	      même serveur : la prime l'attend jusqu'à sa prochaine connexion).
	  C'est le « système de parrainage » prévu par Roblox : la prime n'est
	  versée que si l'ami vient vraiment jouer, jamais pour un simple envoi.
	- Match amical : défi sans mise entre deux amis Roblox. Petit bonus
	  FRIENDLY_BONUS pour chacun, FRIENDLY_BONUS_PER_DAY fois par jour.
]]

local Friends = {}

Friends.INVITEE_WELCOME = 500
Friends.INVITER_REWARD = 500
Friends.MAX_INVITER_REWARDS = 10
Friends.FRIENDLY_BONUS = 50
Friends.FRIENDLY_BONUS_PER_DAY = 3
Friends.PENDING_STORE = "Referrals_v1" -- primes de parrainage en attente (inviteur absent)
Friends.MAX_PENDING = 20

return Friends
