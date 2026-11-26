--[[
	SoundController
	Ambiance sonore côté client : musique de fond, public du stade pendant les
	matchs (plus fort si les tribunes sont grandes), clameur et son de but,
	clics des boutons. Volume général et musique réglables dans les Paramètres.

	- Tout est local au joueur : aucun son ne passe par le serveur.
	- Chaque son essaie ses adresses (Audio.SOUNDS) et garde la première qui se
	  charge ; un son introuvable reste muet sans rien casser.
	- Léger pour téléphone : un seul objet Sound par clé, créé une fois.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

local SoundController = {}

local groups = {} -- [nom] = SoundGroup
local sounds = {} -- [clé] = Sound (SoundId vide tant que rien n'a chargé)
local master = Audio.DEFAULT_VOLUME
local musicEnabled = true
local inMatch = false
local matchLevel = 1
local hooked = setmetatable({}, { __mode = "k" }) -- boutons déjà branchés
local initialized = false
local plays = {} -- [clé] = nombre de lectures (tests)

-- Adresses à essayer pour une clé : d'abord le son glissé dans Studio
-- (ReplicatedStorage > Sons > <clé>), puis la liste d'Audio.SOUNDS.
function SoundController.Candidates(key: string): { string }
	local list = {}
	local folder = ReplicatedStorage:FindFirstChild(Audio.OVERRIDE_FOLDER)
	local custom = folder and folder:FindFirstChild(key)
	if custom and custom:IsA("Sound") and type(custom.SoundId) == "string" and custom.SoundId ~= "" then
		table.insert(list, custom.SoundId)
	end
	for _, id in (Audio.SOUNDS[key] and Audio.SOUNDS[key].ids) or {} do
		table.insert(list, id)
	end
	return list
end

-- Garde la première adresse qui se charge vraiment.
local function resolve(key: string, sound: Sound)
	for _, id in SoundController.Candidates(key) do
		sound.SoundId = id
		local loaded = false
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_contentId, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		if ok and loaded then
			return true
		end
	end
	sound.SoundId = ""
	return false
end

local function applyVolumes()
	for name, group in groups do
		local volume = master * (Audio.GROUPS[name] or 1)
		if name == "Music" then
			volume *= if musicEnabled then (if inMatch then Audio.MUSIC_DUCK else 1) else 0
		end
		group.Volume = volume
	end
end

local function refreshMusic()
	local music = sounds.Musique
	if not music or music.SoundId == "" then
		return
	end
	if musicEnabled and master > 0 then
		if not music.IsPlaying then
			music:Play()
		end
	elseif music.IsPlaying then
		music:Pause()
	end
end

function SoundController.Init()
	if initialized then
		return
	end
	initialized = true
	for name in Audio.GROUPS do
		local group = Instance.new("SoundGroup")
		group.Name = "FCT_" .. name
		group.Parent = SoundService
		groups[name] = group
	end
	for key, def in Audio.SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = "FCT_" .. key
		sound.Volume = def.volume or 0.5
		sound.Looped = def.looped == true
		sound.SoundGroup = groups[def.group]
		sound.Parent = SoundService
		sounds[key] = sound
	end
	applyVolumes()
	-- Chargement en arrière-plan : le jeu démarre sans attendre les sons.
	task.spawn(function()
		for key, sound in sounds do
			pcall(resolve, key, sound)
		end
		refreshMusic()
	end)
end

-- Joue un son court (clic, but, sifflet…). Sans effet s'il n'a pas chargé.
function SoundController.Play(key: string, volume: number?)
	local sound = sounds[key]
	if not sound or sound.SoundId == "" or master <= 0 then
		return false
	end
	if volume then
		sound.Volume = volume
	end
	sound:Play()
	plays[key] = (plays[key] or 0) + 1
	return true
end

-- Branche le son de clic sur tous les boutons d'une interface, y compris ceux
-- créés plus tard (les menus se reconstruisent à chaque rafraîchissement).
function SoundController.HookButtons(root: Instance)
	local function hook(instance)
		if hooked[instance] or not (instance:IsA("TextButton") or instance:IsA("ImageButton")) then
			return
		end
		hooked[instance] = true
		local signal = instance.Activated
		if signal then
			signal:Connect(function()
				SoundController.Play("Clic")
			end)
		end
	end
	for _, d in root:GetDescendants() do
		hook(d)
	end
	local added = root.DescendantAdded
	if added then
		added:Connect(hook)
	end
end

-- Match en 3D : brouhaha de la foule (et chants dans un grand stade).
-- spectator = match d'un voisin : même ambiance, plus discrète.
function SoundController.StartMatch(stadiumLevel: number?, spectator: boolean?)
	inMatch = true
	matchLevel = stadiumLevel or 1
	local factor = if spectator then 0.5 else 1
	local crowd, chants = sounds.Foule, sounds.Chants
	if crowd and crowd.SoundId ~= "" then
		crowd.Volume = Audio.CrowdVolume(matchLevel) * factor
		crowd:Play()
	end
	local chantVolume = Audio.ChantVolume(matchLevel) * factor
	if chants and chants.SoundId ~= "" and chantVolume > 0 then
		chants.Volume = chantVolume
		chants:Play()
	end
	applyVolumes()
	if not spectator then
		SoundController.Play("Sifflet")
	end
end

function SoundController.Goal()
	SoundController.Play("Clameur", Audio.RoarVolume(matchLevel))
	SoundController.Play("But")
end

function SoundController.EndMatch()
	if not inMatch then
		return
	end
	inMatch = false
	for _, key in { "Foule", "Chants" } do
		local sound = sounds[key]
		if sound and sound.IsPlaying then
			sound:Stop()
		end
	end
	SoundController.Play("Sifflet")
	applyVolumes()
end

-- Paramètres -----------------------------------------------------------------

function SoundController.SetVolume(value: number)
	master = Audio.ClampVolume(value)
	applyVolumes()
	refreshMusic()
end

function SoundController.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled == true
	applyVolumes()
	refreshMusic()
end

-- État lisible par les tests.
function SoundController.Debug()
	local out = { master = master, music = musicEnabled, inMatch = inMatch, groups = {}, sounds = {} }
	for name, group in groups do
		out.groups[name] = group.Volume
	end
	for key, sound in sounds do
		out.sounds[key] = { id = sound.SoundId, playing = sound.IsPlaying == true, volume = sound.Volume, plays = plays[key] or 0 }
	end
	return out
end

return SoundController
