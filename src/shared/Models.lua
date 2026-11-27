--[[
	Models — modèles 3D détaillés faits dans Blender (guide : GUIDE_MODELES_3D.md).

	👉 C'EST LE SEUL ENDROIT OÙ COLLER LES NUMÉROS DES MODÈLES.

	Chaque modèle (fichier .fbx de assets/models/) s'importe dans Roblox Studio
	avec l'Importateur 3D, puis se publie sur Roblox pour obtenir son numéro.
	On accepte le numéro seul, « rbxassetid://… » ou le lien du Creator Hub.
	Tant qu'un champ est vide, ou si Roblox ne renvoie pas le modèle, le jeu
	garde la version en blocs (Parts) construite par le code : rien ne casse.
]]

local Models = {}

Models.ASSET_IDS = {
	-- Bus du club (assets/models/bus_du_club.fbx) : dépôt des véhicules du mode Création.
	ClubBus = "",
}

-- Numéro du modèle (nil si vide ou illisible).
function Models.Id(key: string): number?
	local value = Models.ASSET_IDS[key]
	if type(value) == "number" then
		return if value > 0 then math.floor(value) else nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local digits = string.match(value, "(%d%d%d%d%d+)")
	return if digits then tonumber(digits) else nil
end

return Models
