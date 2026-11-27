--[[
	Locale
	Textes du jeu en plusieurs langues : français, anglais, espagnol, portugais (Brésil).

	- Tous les textes visibles sont dans Lang/fr.lua, en.lua, es.lua et pt.lua, une clé par texte.
	- La langue vient de la langue du compte Roblox du joueur (Player.LocaleId) :
	  « fr-… » donne le français, « es-… » l'espagnol, « pt-… » le portugais,
	  toute autre langue donne l'anglais (langue par défaut).
	- Le joueur peut changer de langue dans les Paramètres (attribut « Language »).
	- Locale.T(lang, clé, { nom = valeur }) remplace les {nom} du texte.

	Les noms de clubs, de joueurs et de lieux sont fictifs et ne sont pas traduits.
	Ajouter une langue : créer Lang/xx.lua avec les mêmes clés, l'ajouter à SUPPORTED.
]]

local Lang = script.Parent.Lang

local Locale = {}

Locale.DEFAULT = "en"
Locale.SUPPORTED = { "fr", "en", "es", "pt" }
Locale.Strings = {
	fr = require(Lang.fr),
	en = require(Lang.en),
	es = require(Lang.es),
	pt = require(Lang.pt),
}

-- Clés demandées mais absentes de toutes les langues (doit rester vide).
Locale.Missing = {}

-- Nom de la langue dans sa propre langue (bouton des Paramètres).
Locale.NativeNames = { fr = "Français", en = "English", es = "Español", pt = "Português" }

function Locale.IsSupported(lang: any): boolean
	return type(lang) == "string" and Locale.Strings[lang] ~= nil
end

-- « fr-fr », « fr_CA », « FR » -> "fr" ; « es-mx » -> "es" ; « pt-br », « pt-PT » -> "pt" ;
-- langue non gérée -> "en".
function Locale.FromLocaleId(localeId: any): string
	if type(localeId) ~= "string" then
		return Locale.DEFAULT
	end
	local prefix = string.lower(localeId):match("^(%a+)")
	if prefix and Locale.Strings[prefix] then
		return prefix
	end
	return Locale.DEFAULT
end

-- Langue d'un joueur : choix fait dans les Paramètres, sinon langue du compte Roblox.
function Locale.ForPlayer(player: Player?): string
	if not player then
		return Locale.DEFAULT
	end
	local chosen = player:GetAttribute("Language")
	if Locale.IsSupported(chosen) then
		return chosen
	end
	local ok, localeId = pcall(function()
		return player.LocaleId
	end)
	return Locale.FromLocaleId(ok and localeId or nil)
end

-- Texte traduit. Repli : langue par défaut, puis la clé elle-même (jamais d'erreur).
function Locale.T(lang: string, key: string, params: { [string]: any }?): string
	local strings = Locale.Strings[lang] or Locale.Strings[Locale.DEFAULT]
	local text = strings[key] or Locale.Strings[Locale.DEFAULT][key]
	if not text then
		Locale.Missing[key] = true -- vérifié par le test 09_locale
		text = key
	end
	if params then
		text = text:gsub("{(%w+)}", function(name)
			local value = params[name]
			if value == nil then
				return nil -- laisse « {nom} » tel quel
			end
			return tostring(value)
		end)
	end
	return text
end

-- Raccourci : texte dans la langue d'un joueur.
function Locale.TP(player: Player?, key: string, params: { [string]: any }?): string
	return Locale.T(Locale.ForPlayer(player), key, params)
end

-- Textes du décor (panneaux 3D, invites) -------------------------------------
-- Le serveur construit le décor une seule fois pour tous les joueurs : il écrit
-- le texte dans la langue par défaut et note la clé en attributs. Chaque client
-- réécrit ensuite le texte dans la langue de son joueur (WorldTextController).

local PARAM_PREFIX = "TextParam_"

function Locale.Tag(instance: Instance, key: string, params: { [string]: any }?, property: string?)
	local prop = property or "Text"
	instance:SetAttribute("TextKey", key)
	instance:SetAttribute("TextProperty", prop)
	if params then
		for name, value in params do
			instance:SetAttribute(PARAM_PREFIX .. name, value)
		end
	end
	local target: any = instance
	target[prop] = Locale.T(Locale.DEFAULT, key, params)
end

function Locale.Untag(instance: Instance)
	instance:SetAttribute("TextKey", nil)
end

-- Réécrit un texte marqué par Locale.Tag dans la langue voulue. Renvoie true si fait.
function Locale.ApplyTag(instance: Instance, lang: string): boolean
	local key = instance:GetAttribute("TextKey")
	if type(key) ~= "string" then
		return false
	end
	local params = {}
	for name, value in instance:GetAttributes() do
		if string.sub(name, 1, #PARAM_PREFIX) == PARAM_PREFIX then
			params[string.sub(name, #PARAM_PREFIX + 1)] = value
		end
	end
	local prop = instance:GetAttribute("TextProperty") or "Text"
	local target: any = instance
	target[prop] = Locale.T(lang, key, params)
	return true
end

-- Variables d'un texte (« {points} / {needed} » -> { points = true, needed = true }).
function Locale.Placeholders(text: string): { [string]: boolean }
	local found = {}
	for name in text:gmatch("{(%w+)}") do
		found[name] = true
	end
	return found
end

return Locale
