--[[
	Brand
	Identité visuelle utilisée dans le jeu (voir assets/brand/README.md).

	👉 C'EST LE SEUL ENDROIT OÙ COLLER LES NUMÉROS DES IMAGES (guide : GUIDE_IMAGES.md).

	Les images (logo, écussons) doivent d'abord être importées sur Roblox
	(Studio > Gestionnaire de ressources > Importer) pour obtenir leur numéro.
	On accepte le numéro seul (123456789), « rbxassetid://123456789 » ou le lien
	copié depuis le Creator Hub. Tant qu'un champ est vide, ou tant que Roblox n'a
	pas encore validé l'image, le jeu affiche la version dessinée (écusson aux
	couleurs du club + sigle), qui ne demande aucun import.
]]

local Brand = {}

-- Logo horizontal (assets/brand/logo.png) : en haut de l'écran d'accueil.
Brand.LOGO_ASSET_ID = ""
-- Écussons des 6 clubs (assets/brand/crests/club-1..6.png), par numéro de terrain :
-- HUD, portique d'entrée et toit des bureaux niveau 5.
Brand.CREST_ASSET_IDS = {
	"", -- club-1.png
	"", -- club-2.png
	"", -- club-3.png
	"", -- club-4.png
	"", -- club-5.png
	"", -- club-6.png
}

-- Jeu publié sur Roblox (lien envoyé par Nj le 27/11/2026).
Brand.PLACE_ID = 75942746782438
Brand.GAME_URL = "https://www.roblox.com/games/" .. tostring(Brand.PLACE_ID)

Brand.GAME_TITLE = "FOOTBALL CLUB TYCOON"

-- Transforme ce qui a été collé en « rbxassetid://… » (nil si vide ou illisible).
-- Accepte : 123456789, "123456789", "rbxassetid://123456789",
-- "https://create.roblox.com/store/asset/123456789/logo", "…?id=123456789".
function Brand.AssetUri(value: any): string?
	if type(value) == "number" then
		if value > 0 and value == math.floor(value) then
			return "rbxassetid://" .. string.format("%d", value)
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(value, "%s", "")
	local id = string.match(text, "^(%d+)$")
		or string.match(text, "^rbxassetid://(%d+)$")
		or string.match(text, "[?&]id=(%d+)")
		or string.match(text, "/asset/(%d+)")
		or string.match(text, "/library/(%d+)")
		or string.match(text, "/catalog/(%d+)")
	if id and #id >= 1 and tonumber(id) and tonumber(id) > 0 then
		return "rbxassetid://" .. id
	end
	return nil
end

function Brand.LogoImage(): string?
	return Brand.AssetUri(Brand.LOGO_ASSET_ID)
end

function Brand.CrestImage(slotIndex: number?): string?
	return Brand.AssetUri(slotIndex and Brand.CREST_ASSET_IDS[slotIndex])
end

-- Affiche `fallback` (version dessinée) tant que `image` n'est pas chargée :
-- une image encore en vérification chez Roblox ne laisse jamais un trou.
function Brand.ShowWhenLoaded(image: Instance, onLoaded: (boolean) -> ())
	local function update()
		local ok, loaded = pcall(function()
			return (image :: any).IsLoaded
		end)
		onLoaded(ok and loaded == true)
	end
	update()
	pcall(function()
		(image :: any):GetPropertyChangedSignal("IsLoaded"):Connect(update)
	end)
end

-- Sigle du club (3 lettres max) : « FC Roquerouge » -> « FCR ».
function Brand.Tag(clubName: string?): string
	local letters = {}
	for word in string.gmatch(clubName or "", "[%w\128-\255]+") do
		-- Premier caractère UTF-8 complet (accents compris).
		table.insert(letters, string.match(word, "^[%z\1-\127\194-\244][\128-\191]*"))
		if #letters == 3 then
			break
		end
	end
	if #letters == 0 then
		return "FC"
	end
	return string.upper(table.concat(letters))
end

return Brand
