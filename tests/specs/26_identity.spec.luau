-- Identité du club : couleurs, motif du maillot et écusson choisis par le
-- joueur. Validé par le serveur, visible sur le terrain, les 22 joueurs du
-- replay, la liste des clubs et le HUD ; sans effet sportif ; anciens profils intacts.
local S = H.boot(MODULES)
local ClubIdentity = mock.run(MODULES.ClubIdentity)
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local WorldConfig = mock.run(MODULES.WorldConfig)
local Locale = S.Locale
local visitor = H.join(2, "Visiteur")
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)

local function plot()
	return WorldBuilder.getPlot(S.ClubService.GetSlot(p))
end

local function slotColors()
	return WorldConfig.CLUB_COLORS[S.ClubService.GetSlot(p)]
end

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

-- Le serveur limite à 8 demandes par 5 s : on laisse passer le temps.
local realFire = H.fire
local function fire(...)
	H.advance(1)
	realFire(...)
end

local function rgb(color)
	return table.concat(ClubIdentity.ToArray(color), ",")
end

local function sameColor(a, b, label)
	if typeof(a) ~= "Color3" then
		a = ClubIdentity.FromArray(a, Color3.new())
	end
	if typeof(b) ~= "Color3" then
		b = ClubIdentity.FromArray(b, Color3.new())
	end
	H.eq(rgb(a), rgb(b), label)
end

local function snapshot()
	return S.PlayerDataService.BuildSnapshot(p)
end

H.test("catalogue : couleurs, motifs, textes FR/EN, aucune couleur exclusive", function()
	H.ok(#ClubIdentity.COLORS >= 12, "au moins 12 couleurs")
	H.ok(#ClubIdentity.PATTERNS >= 6, "au moins 6 motifs")
	for _, lang in { "fr", "en" } do
		for _, entry in ClubIdentity.COLORS do
			H.ok(Locale.Strings[lang]["identity.color." .. entry.id], ("couleur %s : %s"):format(lang, entry.id))
		end
		for _, pattern in ClubIdentity.PATTERNS do
			H.ok(Locale.Strings[lang]["identity.pattern." .. pattern.id], ("motif %s : %s"):format(lang, pattern.id))
			H.ok(ClubIdentity.DRAWN[pattern.id], "motif dessiné : " .. pattern.id)
		end
	end
	-- Les objets Robux restent exclusifs : leurs couleurs ne sont pas dans la palette.
	for _, item in S.Cosmetics.EXCLUSIVE do
		for _, entry in ClubIdentity.COLORS do
			H.ok(entry.color ~= item.primary and entry.color ~= item.secondary and entry.color ~= item.shirt, "couleur exclusive absente : " .. item.id)
		end
	end
	for _, pattern in ClubIdentity.PATTERNS do
		if pattern.kit then
			H.ok(S.Cosmetics.Get(pattern.kit), "tenue Prestige existante : " .. pattern.kit)
		end
	end
end)

H.test("nouveau club : couleurs et écusson de l'emplacement, maillot uni", function()
	H.eq(data.identity.primary, "", "couleur d'origine")
	H.eq(data.identity.pattern, "plain", "maillot uni")
	H.eq(data.identity.crest, 0, "écusson de l'emplacement")
	local snap = snapshot()
	H.eq(snap.identity.crest, S.ClubService.GetSlot(p), "écusson du terrain")
	H.eq(snap.identity.kit.pattern, "plain", "uni")
	H.eq(plot():GetAttribute("ClubPrimary"), slotColors().primary, "terrain aux couleurs de l'emplacement")
end)

H.test("couleurs choisies : validées par le serveur, terrain et tribunes repeints", function()
	data.buildings.Stands = 3 -- tribunes en béton (sièges, drapeaux)
	fire(p, "RequestSetIdentity", "primary", "navy")
	H.eq(data.identity.primary, "navy", "couleur principale enregistrée")
	H.eq(plot():GetAttribute("ClubPrimary"), ClubIdentity.Color("navy"), "terrain repeint")
	fire(p, "RequestSetIdentity", "secondary", "gold")
	H.eq(plot():GetAttribute("ClubSecondary"), ClubIdentity.Color("gold"), "couleur secondaire")
	-- Sièges et drapeaux des tribunes aux nouvelles couleurs.
	local seats, flags = 0, 0
	for _, d in plot():GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ClubFlag" and (rgb(d.Color) == rgb(ClubIdentity.Color("navy")) or rgb(d.Color) == rgb(ClubIdentity.Color("gold"))) then
			flags += 1
		elseif d:IsA("BasePart") and rgb(d.Color) == rgb(ClubIdentity.Color("navy")) then
			seats += 1
		end
	end
	H.ok(flags >= 2, "drapeaux du club : " .. flags)
	H.ok(seats > 10, "pièces à la couleur principale : " .. seats)
	-- Valeurs invalides : rien ne change.
	for _, bad in { "neon", 42, nil, { "red" } } do
		fire(p, "RequestSetIdentity", "primary", bad)
		H.eq(data.identity.primary, "navy", "couleur invalide refusée : " .. tostring(bad))
	end
	fire(p, "RequestSetIdentity", "secondary", "navy")
	H.eq(data.identity.secondary, "gold", "deux couleurs identiques refusées")
	local message, kind = H.lastNotify(p)
	H.eq(kind, "error", "message d'erreur : " .. tostring(message))
	fire(p, "RequestSetIdentity", "nope", "red")
	fire(p, "RequestSetIdentity")
	H.eq(data.identity.primary, "navy", "champ inconnu refusé")
end)

H.test("motifs : gratuits, par division, en FC Coins (débit unique), via Prestige", function()
	fire(p, "RequestSetIdentity", "pattern", "halves")
	H.eq(data.identity.pattern, "halves", "motif gratuit")
	H.eq(plot():GetAttribute("Pattern"), "halves", "terrain : motif mémorisé")

	H.eq(data.club.division, "D7", "club en D7")
	fire(p, "RequestSetIdentity", "pattern", "band")
	H.eq(data.identity.pattern, "halves", "bande réservée à la D5")
	data.club.division = "D5"
	fire(p, "RequestSetIdentity", "pattern", "band")
	H.eq(data.identity.pattern, "band", "débloqué en D5")

	data.coins = 10000
	fire(p, "RequestSetIdentity", "pattern", "pinstripes")
	H.eq(data.identity.pattern, "band", "motif payant non acheté refusé")
	fire(p, "RequestBuyPattern", "pinstripes", 1)
	H.eq(data.coins, 10000, "pas assez d'argent : aucun débit")
	data.coins = 100000
	fire(p, "RequestBuyPattern", "pinstripes", 1)
	H.eq(data.coins, 100000 - 15000, "prix du serveur (le prix envoyé est ignoré)")
	H.ok(data.identity.patterns.pinstripes, "motif acheté")
	H.eq(data.identity.pattern, "pinstripes", "et porté")
	fire(p, "RequestBuyPattern", "pinstripes")
	H.eq(data.coins, 85000, "pas de second débit")
	for _, bad in { "plain", "stripes", "nope", 7 } do
		fire(p, "RequestBuyPattern", bad)
	end
	H.eq(data.coins, 85000, "motifs non vendus : aucun débit")
	fire(p, "RequestBuyPattern", "chevron")
	H.eq(data.coins, 85000, "chevron réservé à la D4")

	fire(p, "RequestSetIdentity", "pattern", "stripes")
	H.eq(data.identity.pattern, "pinstripes", "rayures : tenue Prestige nécessaire")
	data.cosmetics.owned.kit_stripes = true
	fire(p, "RequestSetIdentity", "pattern", "stripes")
	H.eq(data.identity.pattern, "stripes", "rayures débloquées par la tenue Prestige")
end)

H.test("écusson : un des 6, ou celui de l'emplacement", function()
	fire(p, "RequestSetIdentity", "crest", 4)
	H.eq(data.identity.crest, 4, "écusson 4")
	H.eq(plot():GetAttribute("Crest"), 4, "terrain : écusson 4")
	H.eq(snapshot().identity.crest, 4, "HUD : écusson 4")
	for _, bad in { 7, -1, 2.5, "3", {} } do
		fire(p, "RequestSetIdentity", "crest", bad)
		H.eq(data.identity.crest, 4, "écusson invalide refusé : " .. tostring(bad))
	end
	fire(p, "RequestSetIdentity", "crest", 0)
	H.eq(snapshot().identity.crest, S.ClubService.GetSlot(p), "retour à l'écusson du terrain")
	fire(p, "RequestSetIdentity", "crest", 2)
end)

H.test("objet Prestige porté : passe devant ; choisir ici le retire (reste possédé)", function()
	data.cosmetics.owned.colors_royal = true
	data.cosmetics.owned.kit_hoops = true
	fire(p, "RequestEquipCosmetic", "colors", "colors_royal")
	fire(p, "RequestEquipCosmetic", "kit", "kit_hoops")
	local snap = snapshot()
	sameColor(snap.identity.primary, S.Cosmetics.Get("colors_royal").primary, "couleurs Prestige d'abord")
	H.eq(snap.identity.kit.pattern, "hoops", "tenue Prestige d'abord")
	fire(p, "RequestSetIdentity", "primary", "red")
	H.eq(data.cosmetics.equipped.colors, nil, "palette Prestige retirée")
	H.ok(data.cosmetics.owned.colors_royal, "toujours possédée")
	H.eq(plot():GetAttribute("ClubPrimary"), ClubIdentity.Color("red"), "nouvelle couleur visible")
	fire(p, "RequestSetIdentity", "pattern", "stripes")
	H.eq(data.cosmetics.equipped.kit, nil, "tenue Prestige retirée")
	H.eq(snapshot().identity.kit.pattern, "stripes", "motif choisi visible")
end)

H.test("replay : les 22 joueurs portent la tenue du club (motif, short)", function()
	local result = play()
	H.ok(result and result.replay, "replay")
	local kit = result.replay.homeKit
	H.eq(kit.pattern, "stripes", "motif transmis")
	sameColor(kit.shirt, ClubIdentity.Color("red"), "maillot rouge")
	H.ok(type(result.replay.awayKit) == "table" and result.replay.awayKit.shirt, "tenue adverse")
	H.ok(result.replay.awayKit.shirt[1] ~= kit.shirt[1] or result.replay.awayKit.shirt[2] ~= kit.shirt[2] or result.replay.awayKit.shirt[3] ~= kit.shirt[3], "maillots différents")
	H.eq(result.homeGoals + result.awayGoals >= 0, true, "match joué")
end)

H.test("aucun avantage sportif : même note d'équipe quelle que soit l'identité", function()
	local before = S.ClubService.GetClubList()
	local rating
	for _, club in before do
		if club.id == "player:" .. p.UserId then
			rating = club.rating
		end
	end
	fire(p, "RequestSetIdentity", "primary", "black")
	for _, club in S.ClubService.GetClubList() do
		if club.id == "player:" .. p.UserId then
			H.eq(club.rating, rating, "note inchangée")
			-- Visible par les autres joueurs : couleurs et écusson dans la liste des clubs.
			H.eq(club.colors.crest, 2, "écusson visible des autres")
			sameColor(club.colors.primary, ClubIdentity.Color("black"), "couleur visible des autres")
		end
	end
	local broadcasts = H.received(visitor, "ClubsUpdated")
	H.ok(#broadcasts > 0, "les autres joueurs reçoivent la liste mise à jour")
end)

H.test("remise à zéro : tout revient d'origine", function()
	fire(p, "RequestSetIdentity", "reset")
	H.eq(data.identity.primary, "", "couleur d'origine")
	H.eq(data.identity.pattern, "plain", "uni")
	H.eq(data.identity.crest, 0, "écusson d'origine")
	H.ok(data.identity.patterns.pinstripes, "motif acheté gardé")
	H.eq(plot():GetAttribute("ClubPrimary"), slotColors().primary, "terrain d'origine")
end)

H.test("sauvegarde : identité gardée après reconnexion", function()
	data.coins = 100000
	fire(p, "RequestSetIdentity", "primary", "green")
	fire(p, "RequestSetIdentity", "pattern", "pinstripes")
	fire(p, "RequestSetIdentity", "crest", 5)
	H.leave(p)
	p = H.join(1, "Testeur")
	data = S.PlayerDataService.GetData(p)
	H.eq(data.identity.primary, "green", "couleur gardée")
	H.eq(data.identity.pattern, "pinstripes", "motif gardé")
	H.eq(data.identity.crest, 5, "écusson gardé")
	H.eq(plot():GetAttribute("ClubPrimary"), ClubIdentity.Color("green"), "terrain reconstruit aux bonnes couleurs")
end)

H.test("ancien profil sans identité : complété, apparence inchangée", function()
	local p2 = H.join(3, "Ancien")
	local d2 = S.PlayerDataService.GetData(p2)
	d2.identity = nil
	d2.cosmetics.owned.colors_royal = true
	d2.cosmetics.equipped.colors = "colors_royal"
	H.leave(p2)
	p2 = H.join(3, "Ancien")
	d2 = S.PlayerDataService.GetData(p2)
	H.ok(type(d2.identity) == "table" and d2.identity.pattern == "plain" and d2.identity.crest == 0, "identité ajoutée par défaut")
	H.eq(d2.cosmetics.equipped.colors, "colors_royal", "palette Prestige toujours portée")
	local plot2 = WorldBuilder.getPlot(S.ClubService.GetSlot(p2))
	H.eq(plot2:GetAttribute("ClubPrimary"), S.Cosmetics.Get("colors_royal").primary, "même apparence qu'avant")
	-- Identité abîmée : valeurs ignorées sans casser le terrain.
	d2.identity.primary = "???"
	d2.identity.pattern = "laser"
	d2.identity.crest = 99
	d2.cosmetics.equipped.colors = nil
	S.ClubService.RefreshPlot(p2)
	plot2 = WorldBuilder.getPlot(S.ClubService.GetSlot(p2))
	H.eq(plot2:GetAttribute("ClubPrimary"), WorldConfig.CLUB_COLORS[S.ClubService.GetSlot(p2)].primary, "valeurs abîmées : couleurs d'origine")
	H.eq(S.PlayerDataService.BuildSnapshot(p2).identity.kit.pattern, "plain", "motif abîmé : uni")
	H.leave(p2)
end)

H.test("budget de Parts : terrain niveau 5 avec identité", function()
	for _, id in WorldConfig.FACILITY_IDS do
		data.buildings[id] = 5
	end
	S.ClubService.RefreshPlot(p)
	H.ok(WorldBuilder.countParts(plot()) <= 750, "budget mobile : " .. WorldBuilder.countParts(plot()))
end)

local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)
local Replay = mock.run(MODULES.Client_MatchReplayController)

H.test("client : écran Identité dans Prestige, boutons de couleur, motif, écusson", function()
	data.club.stats.played = 10 -- onglet Prestige ouvert
	data.club.division = "D5"
	S.PlayerDataService.MarkChanged(p)
	H.flush()
	UI.SetMenuOpen(true)
	UI.OpenTab("Prestige")
	H.flush()
	H.ok(H.findText(gui, "Identité du club") or H.findText(gui, "Club Identity"), "section Identité")
	local function clickNamed(name)
		for _, d in gui:GetDescendants() do
			if d.Name == name and d.ClassName == "TextButton" then
				d.Activated:Fire()
				H.flush()
				return true
			end
		end
		return false
	end
	H.ok(clickNamed("Swatch_primary_purple"), "pastille violette")
	H.eq(data.identity.primary, "purple", "couleur choisie par bouton")
	H.ok(clickNamed("Pattern_band"), "bouton Bande")
	H.eq(data.identity.pattern, "band", "motif choisi par bouton")
	H.ok(clickNamed("Crest_3"), "écusson 3")
	H.eq(data.identity.crest, 3, "écusson choisi par bouton")
	H.ok(H.findText(gui, "Débloqué en") or H.findText(gui, "Unlocked in"), "motif réservé à une division plus haute")
	local preview
	for _, d in gui:GetDescendants() do
		if d.Name == "KitPreview" then
			preview = d
		end
	end
	H.ok(preview, "aperçu du maillot")
	sameColor(preview.BackgroundColor3, ClubIdentity.Color("purple"), "aperçu du maillot violet")
end)

H.test("client : replay avec motif sur les joueurs de champ, short aux couleurs", function()
	play()
	H.ok(Replay.IsPlaying(), "replay lancé")
	local folder = workspace:FindFirstChild("MatchReplay")
	H.ok(folder, "pièces du replay")
	local shown, shorts = 0, 0
	for _, part in folder:GetChildren() do
		if part.Name == "ReplayPattern" and part.Transparency == 0 then
			shown += 1
		elseif part.Name == "ReplayShorts" then
			shorts += 1
		end
	end
	H.eq(shorts, 22, "22 shorts")
	H.ok(shown >= 10, "bande visible sur les 10 joueurs de champ du club : " .. shown)
	Replay.Skip()
	H.flush()
end)
