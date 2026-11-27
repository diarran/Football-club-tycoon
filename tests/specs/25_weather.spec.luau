-- Météo et jour/nuit : règles partagées (même météo serveur et client), effet
-- léger sur les matchs, projecteurs la nuit, pluie/neige, option des Paramètres,
-- affichage dans l'onglet Matchs, le résultat et le replay.
local S = H.boot(MODULES)
local Weather = mock.run(MODULES.Weather)
local Config = S.Config
local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)
local WeatherCtl = mock.run(MODULES.Client_WeatherController)
local Replay = mock.run(MODULES.Client_MatchReplayController)
local Lighting = game:GetService("Lighting")

local JAN = 1_767_225_600 -- 1er janvier 2026, 00:00 UTC (hiver)
local JULY = 1_782_864_000 -- 1er juillet 2026, 00:00 UTC (été)

-- Premier instant (par pas d'un créneau) où la météo vaut `kind`.
local function findSlot(kind: string, from: number, night: boolean?): number?
	for i = 0, 5000 do
		local t = from + i * Weather.SLOT_SECONDS + 30
		if Weather.At(t) == kind and (night == nil or Weather.IsNight(t) == night) then
			return t
		end
	end
	return nil
end

local function play(tactic)
	H.advance(Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", tactic or "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("règles : météo fixe par créneau, toutes les météos possibles, neige seulement en hiver", function()
	local t = JULY + 123
	H.eq(Weather.At(t), Weather.At(t + 60), "même créneau : même météo")
	local seen = { normal = {}, winter = {} }
	for i = 0, 2000 do
		seen.normal[Weather.At(JULY + i * Weather.SLOT_SECONDS)] = true
		seen.winter[Weather.At(JAN + i * Weather.SLOT_SECONDS)] = true
	end
	for _, kind in { "Clear", "Cloudy", "Rain", "Wind" } do
		H.ok(seen.normal[kind], "été : " .. kind)
		H.ok(seen.winter[kind], "hiver : " .. kind)
	end
	H.ok(seen.normal.Snow == nil, "pas de neige en été")
	H.ok(seen.winter.Snow, "neige en hiver")
	H.ok(Weather.IsWinter(JAN) and not Weather.IsWinter(JULY), "saison")
	local nextAt, nextKind = Weather.Next(t)
	H.ok(nextAt > t and nextAt - t <= Weather.SLOT_SECONDS, "prochain changement dans le créneau")
	H.eq(nextKind, Weather.At(nextAt), "météo suivante")
end)

H.test("règles : beau temps la moitié du temps environ, météo répartie", function()
	local counts = {}
	local total = 3000
	for i = 0, total - 1 do
		local kind = Weather.At(JULY + i * Weather.SLOT_SECONDS)
		counts[kind] = (counts[kind] or 0) + 1
	end
	local clear = counts.Clear / total
	H.ok(clear > 0.42 and clear < 0.58, ("beau temps ~50 %% (%.2f)"):format(clear))
	local rain = (counts.Rain or 0) / total
	H.ok(rain > 0.14 and rain < 0.26, ("pluie ~20 %% (%.2f)"):format(rain))
end)

H.test("jour/nuit : journée de 20 min, nuit de 19 h 30 à 5 h 30", function()
	local night, total = 0, 1200
	for s = 0, total - 1 do
		local clock = Weather.ClockTime(JULY + s)
		H.ok(clock >= 0 and clock < 24, "heure valide")
		if Weather.IsNight(JULY + s) then
			night += 1
		end
	end
	H.ok(night / total > 0.35 and night / total < 0.45, "un peu plus d'un tiers de nuit")
	H.eq(Weather.ClockTime(JULY), 8, "début de journée : 8 h")
	H.ok(not Weather.IsNight(JULY), "8 h : jour")
	H.ok(Weather.IsNight(JULY + Weather.DAY_SECONDS * 0.6), "22 h 24 : nuit")
end)

H.test("effet léger : +1 au style avantagé, rien par beau temps ou valeur invalide", function()
	H.eq(Weather.Favors("Rain"), "Defensive", "pluie : Défensive")
	H.eq(Weather.Favors("Wind"), "Counter", "vent : Contre-attaque")
	H.eq(Weather.Favors("Snow"), "Pressing", "neige : Pressing")
	H.eq(Weather.Favors("Clear"), nil, "beau temps : rien")
	H.eq(Weather.Favors("Tempête"), nil, "valeur inconnue")
	local a, d = Weather.Modifiers("Rain", "Defensive")
	H.eq(a, 1, "attaque +1")
	H.eq(d, 1, "défense +1")
	a, d = Weather.Modifiers("Rain", "Offensive")
	H.eq(a + d, 0, "autre style : rien")
	a, d = Weather.Modifiers(nil, "Defensive")
	H.eq(a + d, 0, "sans météo : rien")
	H.ok(Weather.BONUS < S.Tactics.EDGE, "moins fort qu'un avantage tactique")
end)

H.test("simulation : la météo compte pour les deux équipes, et seulement si elle est donnée", function()
	local function team(tactic)
		local squad = {}
		for i, pos in { "GK", "DEF", "MID", "ATT", "ATT" } do
			squad[i] = { name = "J" .. i, position = pos, rating = 60, energy = 80 }
		end
		return { id = "x", name = "X", squad = squad, tactic = tactic, bonus = 0 }
	end
	-- Même nombre de buts en moyenne sans météo et par beau temps.
	local function avgGoals(home, away, weather, runs)
		local h, a = 0, 0
		for _ = 1, runs do
			local r = S.MatchService.Simulate(home, away, weather)
			h += r.homeGoals
			a += r.awayGoals
		end
		return h / runs, a / runs
	end
	local runs = 3000
	local hRain, aRain = avgGoals(team("Defensive"), team("Balanced"), "Rain", runs)
	local hNone, aNone = avgGoals(team("Defensive"), team("Balanced"), nil, runs)
	H.ok(hRain - aRain > hNone - aNone, "pluie : la Défensive s'en sort mieux")
	local hAway, aAway = avgGoals(team("Balanced"), team("Defensive"), "Rain", runs)
	H.ok(aAway - hAway > 0, "l'adversaire profite aussi de la pluie")
end)

H.test("match : météo du coup d'envoi dans le résultat et le replay, même règle que le client", function()
	local result = play("Balanced")
	H.ok(result, "match joué")
	local t = os.time()
	H.ok(type(result.weather) == "table", "météo jointe au résultat")
	H.eq(result.weather.kind, Weather.At(t), "même météo que Weather.At")
	H.eq(result.weather.night, Weather.IsNight(t), "jour/nuit")
	H.eq(result.weather.favors, Weather.Favors(result.weather.kind), "style avantagé")
	H.eq(result.replay.weather, result.weather.kind, "replay : météo")
	H.eq(result.replay.night, result.weather.night, "replay : nuit")
	H.ok(Replay.IsPlaying(), "replay lancé")
	H.eq(WeatherCtl.Debug().matchMode, true, "projecteurs du match pendant le replay")
	Replay.Skip()
	H.frames(5)
	H.eq(WeatherCtl.Debug().matchMode, false, "fin du replay : mode normal")
	-- Le résultat reste complet (récompenses, points) comme avant.
	H.ok(result.rewards.total > 0, "récompenses inchangées")
	H.eq(#H.errors, 0, "aucune erreur")
end)

H.test("client : jour/nuit appliqué au ciel, projecteurs allumés seulement la nuit", function()
	-- Un projecteur ajouté après le démarrage (stade amélioré) est suivi aussi.
	local lamp = Instance.new("Part")
	lamp.Name = "Lamps"
	local spot = Instance.new("SpotLight")
	spot.Brightness = 4
	spot.Enabled = true
	spot.Parent = lamp
	lamp.Parent = workspace
	workspace.DescendantAdded:Fire(lamp)
	workspace.DescendantAdded:Fire(spot)
	local other = Instance.new("PointLight") -- lumière décorative : pas touchée
	other.Enabled = true
	other.Parent = workspace

	local day = findSlot("Clear", JULY, false)
	WeatherCtl.SetTimeOverride(day)
	H.ok(math.abs(Lighting.ClockTime - Weather.ClockTime(day)) < 1e-6, "heure du ciel")
	H.eq(WeatherCtl.Debug().night, false, "jour")
	H.eq(spot.Enabled, false, "projecteur éteint le jour")
	H.eq(other.Enabled, true, "lumière décorative intacte")
	H.ok(WeatherCtl.Debug().lightCount >= 1, "projecteurs repérés")

	local night = findSlot("Clear", JULY, true)
	WeatherCtl.SetTimeOverride(night)
	H.eq(WeatherCtl.Debug().night, true, "nuit")
	H.eq(spot.Enabled, true, "projecteur allumé la nuit")
	H.eq(spot.Brightness, 4, "luminosité normale hors match")
	WeatherCtl.SetMatchMode(true)
	H.ok(spot.Brightness > 4, "match de nuit : projecteurs plus forts")
	WeatherCtl.SetMatchMode(false)
	H.eq(spot.Brightness, 4, "fin du match : luminosité normale")
end)

H.test("client : pluie et neige en particules légères, coupées par l'option des Paramètres", function()
	local rain = findSlot("Rain", JULY)
	WeatherCtl.SetTimeOverride(rain)
	local d = WeatherCtl.Debug()
	H.eq(d.kind, "Rain", "pluie")
	H.eq(d.rate, Weather.ParticleRate("Rain"), "particules de pluie")
	H.ok(d.emitter and d.emitter.Enabled, "émetteur actif")
	H.ok(Lighting.FogEnd and Lighting.FogEnd < 1000, "brouillard léger sous la pluie")
	H.ok(Weather.ParticleRate("Rain", true) < Weather.ParticleRate("Rain"), "moins de particules sur téléphone")
	H.ok(Weather.ParticleRate("Rain") <= 60, "pluie légère (≤ 60 particules/s)")

	local snow = findSlot("Snow", JAN)
	WeatherCtl.SetTimeOverride(snow)
	H.eq(WeatherCtl.Debug().kind, "Snow", "neige en hiver")
	H.eq(WeatherCtl.Debug().rate, Weather.ParticleRate("Snow"), "flocons")

	-- Paramètres : bouton « Effets météo » → plus de particules ni de brouillard.
	UI.SetMenuOpen(true)
	UI.OpenTab("Settings")
	H.ok(H.findText(gui, "Effets météo"), "option dans les Paramètres")
	local before = UI.GetSettings().weatherEffects
	H.eq(before, true, "activé par défaut")
	local card = H.findText(gui, "Effets météo").Parent
	local toggle = card:FindFirstChildWhichIsA("TextButton")
	toggle.Activated:Fire()
	H.flush()
	H.eq(UI.GetSettings().weatherEffects, false, "désactivé")
	d = WeatherCtl.Debug()
	H.eq(d.effectsEnabled, false, "contrôleur prévenu")
	H.eq(d.rate, 0, "plus de particules")
	H.eq(d.emitter.Enabled, false, "émetteur coupé")
	H.ok(Lighting.FogEnd > 1000, "plus de brouillard")
	H.ok(Lighting.ClockTime ~= nil, "le jour/nuit reste")
	-- Réactivation.
	card = H.findText(gui, "Effets météo").Parent
	card:FindFirstChildWhichIsA("TextButton").Activated:Fire()
	H.flush()
	H.eq(WeatherCtl.Debug().rate, Weather.ParticleRate("Snow"), "effets revenus")
	WeatherCtl.SetTimeOverride(nil)
end)

H.test("onglet Matchs : météo du moment, son effet et la suivante (FR et EN)", function()
	local rain = findSlot("Rain", JULY)
	UI.weatherTime = rain
	UI.SetMenuOpen(true)
	UI.OpenTab("Matches")
	H.ok(H.findText(gui, "Météo au stade : 🌧️ Pluie"), "titre")
	H.ok(H.findText(gui, "toute équipe qui joue Défensive gagne +1"), "effet expliqué")
	H.ok(H.findText(gui, "Ensuite (dans"), "météo suivante")
	local clear = findSlot("Clear", JULY, false)
	UI.weatherTime = clear
	UI.Refresh()
	H.ok(H.findText(gui, "Aucun effet sur le match"), "beau temps : aucun effet")
	UI.SetLanguage("en")
	H.ok(H.findText(gui, "Stadium weather: ☀️ Clear"), "anglais")
	UI.SetLanguage("fr")
	UI.weatherTime = nil
end)

H.test("résultat et replay : ligne météo, match de nuit, anciens résultats sans météo", function()
	UI.ShowMatchResult({
		homeName = "A", awayName = "B", homeGoals = 1, awayGoals = 0, events = {}, outcome = "Win",
		weather = { kind = "Rain", night = true, favors = "Defensive" },
		rewards = { match = 1, tickets = 0, sponsor = 0, shop = 0, vip = 0, contracts = 0, event = 0, total = 1 },
		division = data.club.division, divisionPoints = 0,
	})
	local line = H.findText(gui, "🌧️ Pluie · 🌙 Match de nuit")
	H.ok(line, "ligne météo du résultat")
	H.ok(line and line.Text:find("avantage Défensive +1", 1, true), "style avantagé")
	H.eq(Replay.WeatherText({ weather = "Snow", night = false }), "❄️ Neige", "replay : neige")
	H.eq(Replay.WeatherText({ weather = "Clear", night = true }), "🌙 Nuit", "replay : nuit")
	H.eq(Replay.WeatherText({ weather = "Clear", night = false }), nil, "beau temps de jour : rien")
	H.eq(Replay.WeatherText({}), nil, "ancien replay : rien")
	H.eq(#H.errors, 0, "aucune erreur")
end)

H.test("ancienne sauvegarde : rien de nouveau à enregistrer", function()
	-- La météo vient de l'heure : la sauvegarde n'a aucun champ nouveau.
	for key in data do
		H.ok(not tostring(key):lower():find("weather"), "pas de champ météo : " .. tostring(key))
	end
end)
