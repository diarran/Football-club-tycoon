-- Ambiance sonore : sons qui se chargent (ou restent muets), public selon la
-- taille du stade, effets de but pendant le replay, clics, réglages du son.
local S = H.boot(MODULES)
local Audio = mock.run(MODULES.Audio)

-- Sons glissés dans Studio (ReplicatedStorage > Sons) pour la musique et le public.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage:FindFirstChild("Sons")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Sons"
	folder.Parent = ReplicatedStorage
end
for key, id in { Musique = "rbxassetid://101", Foule = "rbxassetid://102", Chants = "rbxassetid://103" } do
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = id
	sound.Parent = folder
end
-- Le premier son de clic « ne se charge pas » : le suivant doit prendre le relais.
H.missingSounds["rbxasset://sounds/button.wav"] = true

local p = H.join(1, "Testeur")
local data = S.PlayerDataService.GetData(p)
local gui = H.startClient(MODULES, p)
local UI = mock.run(MODULES.Client_UIController)
local Sound = mock.run(MODULES.Client_SoundController)
local Replay = mock.run(MODULES.Client_MatchReplayController)
H.flush()

local function play()
	H.advance(S.Config.MATCH_COOLDOWN_SECONDS + 1)
	local before = #H.received(p, "MatchResult")
	H.fire(p, "RequestMatch", "ai", "Balanced")
	local results = H.received(p, "MatchResult")
	return if #results > before then results[#results][1] else nil
end

H.test("règles : public plus fort dans un grand stade, chants dès le niveau 3", function()
	for level = 2, 5 do
		H.ok(Audio.CrowdVolume(level) > Audio.CrowdVolume(level - 1), "foule niveau " .. level)
		H.ok(Audio.RoarVolume(level) > Audio.RoarVolume(level - 1), "clameur niveau " .. level)
	end
	H.eq(Audio.ChantVolume(1), 0, "pas de chants au niveau 1")
	H.eq(Audio.ChantVolume(2), 0, "pas de chants au niveau 2")
	H.ok(Audio.ChantVolume(3) > 0 and Audio.ChantVolume(5) > Audio.ChantVolume(3), "chants de plus en plus forts")
	for _, value in { Audio.CrowdVolume(99), Audio.ChantVolume(99), Audio.RoarVolume("x"), Audio.CrowdVolume(nil) } do
		H.ok(value >= 0 and value <= 1, "volume borné : " .. tostring(value))
	end
	H.eq(Audio.ClampVolume(7), 1, "volume plafonné")
	H.eq(Audio.ClampVolume(-1), 0, "volume plancher")
	H.eq(Audio.ClampVolume("abc"), Audio.DEFAULT_VOLUME, "valeur invalide")
end)

H.test("chargement : son de Studio d'abord, adresse suivante si la première échoue, sinon muet", function()
	local d = Sound.Debug()
	H.eq(d.sounds.Musique.id, "rbxassetid://101", "musique glissée dans Studio")
	H.eq(d.sounds.Foule.id, "rbxassetid://102", "foule glissée dans Studio")
	H.eq(d.sounds.Clic.id, "rbxasset://sounds/switch.wav", "clic : 2ᵉ adresse")
	H.eq(d.sounds.But.id, "rbxasset://sounds/victory.wav", "son de but intégré à Roblox")
	H.eq(d.sounds.Sifflet.id, "", "sifflet sans son : reste muet")
	H.ok(d.sounds.Musique.playing, "musique lancée")
	H.eq(Sound.Play("Sifflet"), false, "un son absent ne joue pas, sans erreur")
	for key, def in Audio.SOUNDS do
		for _, id in def.ids do
			H.ok(id:sub(1, 18) == "rbxasset://sounds/", key .. " : seulement des sons livrés avec Roblox")
		end
	end
end)

H.test("clics : chaque bouton du menu fait un son, sans doublon", function()
	local before = Sound.Debug().sounds.Clic.plays
	UI.SetMenuOpen(true)
	H.click(gui, "Paramètres")
	H.ok(Sound.Debug().sounds.Clic.plays == before + 1, "son de clic joué")
	H.click(gui, "Stade")
	H.click(gui, "Paramètres")
	H.eq(Sound.Debug().sounds.Clic.plays, before + 3, "un son par clic, sans doublon")
end)

H.test("replay : public selon les tribunes, effets et sons à chaque but", function()
	UI.SetMenuOpen(false)
	local goalsPlayed = 0
	local result
	for _ = 1, 15 do
		data.buildings.Stands = 4
		result = play()
		if result and result.homeGoals + result.awayGoals > 0 then
			break
		end
		Replay.Skip()
		H.click(gui, "Continuer")
	end
	H.ok(result and result.homeGoals + result.awayGoals > 0, "un match avec au moins un but")
	H.ok(Replay.IsPlaying(), "replay lancé")
	local d = Sound.Debug()
	H.ok(d.inMatch, "ambiance de match")
	H.ok(d.sounds.Foule.playing, "brouhaha de la foule")
	H.ok(math.abs(d.sounds.Foule.volume - Audio.CrowdVolume(4)) < 1e-6, "volume de foule du niveau 4")
	H.ok(d.sounds.Chants.playing, "chants du public (niveau 4)")
	H.ok(d.groups.Music < Audio.GROUPS.Music * Audio.DEFAULT_VOLUME, "musique baissée pendant le match")
	local butBefore = d.sounds.But.plays
	H.frames(math.ceil(result.replay.timeline.duration * 30) + 30)
	H.ok(not Replay.IsPlaying(), "replay terminé")
	local total = result.homeGoals + result.awayGoals
	local after = Sound.Debug()
	H.ok(after.sounds.But.plays - butBefore >= 1, "son de but joué")
	local emitted = 0
	for _, count in H.emitted do
		emitted += count
	end
	H.ok(emitted >= 60, "confettis lancés : " .. emitted .. " pour " .. total .. " but(s)")
	H.ok(not after.inMatch and not after.sounds.Foule.playing and not after.sounds.Chants.playing, "public coupé à la fin")
	H.ok(math.abs(after.groups.Music - Audio.GROUPS.Music * Audio.DEFAULT_VOLUME) < 1e-6, "musique revenue")
	H.click(gui, "Continuer")
end)

H.test("petit stade : foule discrète et pas de chants", function()
	data.buildings.Stands = 1
	play()
	local d = Sound.Debug()
	H.ok(math.abs(d.sounds.Foule.volume - Audio.CrowdVolume(1)) < 1e-6, "volume de foule du niveau 1")
	H.ok(not d.sounds.Chants.playing, "pas de chants")
	Replay.Skip()
	H.click(gui, "Continuer")
end)

H.test("Paramètres : volume par paliers, muet, musique on/off", function()
	UI.SetMenuOpen(true)
	UI.OpenTab("Settings")
	H.flush()
	H.ok(H.findText(gui, "Volume du son"), "réglage du volume affiché")
	H.click(gui, "Muet")
	local d = Sound.Debug()
	H.eq(d.master, 0, "muet")
	for name, volume in d.groups do
		H.eq(volume, 0, "groupe " .. name .. " muet")
	end
	H.ok(not d.sounds.Musique.playing, "musique en pause")
	H.eq(Sound.Play("But"), false, "aucun effet quand c'est muet")
	H.click(gui, "50%")
	d = Sound.Debug()
	H.eq(d.master, 0.5, "volume 50 %")
	H.ok(math.abs(d.groups.Effects - 0.5 * Audio.GROUPS.Effects) < 1e-6, "effets à 50 %")
	H.ok(d.sounds.Musique.playing, "musique relancée")
	-- Musique : le bouton de la carte « Musique de fond ».
	local musicLabel = H.findText(gui, "Musique de fond", "TextLabel")
	H.ok(musicLabel, "réglage de la musique")
	local toggle = musicLabel and musicLabel.Parent:FindFirstChildWhichIsA("TextButton")
	toggle.Activated:Fire()
	H.flush()
	d = Sound.Debug()
	H.eq(d.music, false, "musique coupée")
	H.eq(d.groups.Music, 0, "groupe musique muet")
	H.ok(not d.sounds.Musique.playing, "musique en pause")
	H.ok(d.groups.Effects > 0, "les effets restent audibles")
	UI.SetLanguage("en")
	H.flush()
	H.ok(H.findText(gui, "Sound volume"), "réglage traduit en anglais")
	H.ok(H.findText(gui, "Mute", "TextButton"), "bouton Mute")
	UI.SetLanguage("fr")
end)
