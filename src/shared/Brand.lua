--[[
	Brand
	Identité visuelle utilisée dans le jeu (voir assets/brand/README.md).

	Les images (logo, écussons) doivent d'abord être importées sur Roblox
	(Asset Manager > Import) pour obtenir un identifiant « rbxassetid://… ».
	Tant que ces champs sont vides, le jeu affiche une version dessinée
	(écusson aux couleurs du club + sigle), qui ne demande aucun import.
]]

local Brand = {}

-- À remplir après import : "rbxassetid://123456789"
Brand.LOGO_ASSET_ID = "" -- assets/brand/logo.png
Brand.CREST_ASSET_IDS = { -- assets/brand/crests/club-1..6.png, par numéro de terrain
	"",
	"",
	"",
	"",
	"",
	"",
}

Brand.GAME_TITLE = "FOOTBALL CLUB TYCOON"

local function nonEmpty(value: string?): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function Brand.LogoImage(): string?
	return nonEmpty(Brand.LOGO_ASSET_ID)
end

function Brand.CrestImage(slotIndex: number?): string?
	return nonEmpty(slotIndex and Brand.CREST_ASSET_IDS[slotIndex])
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
