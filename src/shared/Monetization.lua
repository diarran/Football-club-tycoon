--[[
	Monetization
	Achats facultatifs en Robux (document de conception, section 9).

	Règle du jeu : le jeu est gratuit. On ne vend QUE de l'apparence
	(objets exclusifs du Prestige), jamais d'avantage sportif : pas de
	joueurs, pas de points de division, pas de victoire achetée.

	IDs : chaque achat est un « produit développeur » créé sur le site Roblox
	(voir GUIDE_PUBLICATION.md, section « Boutique Robux »). Tant qu'un
	productId vaut 0, l'achat est caché dans le jeu et refusé par le serveur.

	Le boost de revenus est « prudence » : il reste coupé (BOOST_ENABLED =
	false) tant qu'on n'a pas décidé de l'ouvrir, même si son ID est rempli.
]]

local Monetization = {}

-- Interrupteur du boost temporaire de revenus des matchs (désactivé par défaut).
Monetization.BOOST_ENABLED = false

-- key : nom interne (ne change jamais : il sert dans les tests et les journaux).
-- productId : ID du produit développeur Roblox (0 = pas encore créé, donc caché).
-- cosmetic : objet exclusif de Cosmetics.EXCLUSIVE accordé une seule fois.
-- boost : { multiplier, minutes } accordé à chaque achat (cumulable en durée).
Monetization.PRODUCTS = {
	{ key = "colors_vip_neon", productId = 0, cosmetic = "colors_vip_neon" },
	{ key = "lighting_vip_ruby", productId = 0, cosmetic = "lighting_vip_ruby" },
	{ key = "statue_vip_crystal", productId = 0, cosmetic = "statue_vip_crystal" },
	{ key = "kit_vip_carbon", productId = 0, cosmetic = "kit_vip_carbon" },
	{ key = "boost_income", productId = 0, boost = { multiplier = 1.5, minutes = 30 } },
}

-- Durée maximale cumulée d'un boost (évite d'empiler des journées entières).
Monetization.BOOST_MAX_MINUTES = 120

-- Nombre de reçus gardés dans le profil pour reconnaître un reçu déjà accordé.
Monetization.RECEIPTS_KEPT = 200

local byKey = {}
for _, product in Monetization.PRODUCTS do
	byKey[product.key] = product
end

local function validId(id): boolean
	return type(id) == "number" and id > 0 and id == math.floor(id)
end

-- Produit utilisable : ID rempli et, pour le boost, interrupteur ouvert.
function Monetization.IsAvailable(product): boolean
	if not product or not validId(product.productId) then
		return false
	end
	if product.boost and not Monetization.BOOST_ENABLED then
		return false
	end
	return true
end

function Monetization.Get(key: any)
	if type(key) ~= "string" then
		return nil
	end
	return byKey[key]
end

-- Produit correspondant à un ID Roblox (seulement s'il est disponible).
function Monetization.ByProductId(productId: any)
	if not validId(productId) then
		return nil
	end
	for _, product in Monetization.PRODUCTS do
		if product.productId == productId and Monetization.IsAvailable(product) then
			return product
		end
	end
	return nil
end

-- Produit qui accorde cet objet exclusif (disponible ou non).
function Monetization.ForCosmetic(cosmeticId: string)
	for _, product in Monetization.PRODUCTS do
		if product.cosmetic == cosmeticId then
			return product
		end
	end
	return nil
end

-- Y a-t-il au moins un achat Robux visible ? Sinon la boutique est cachée.
function Monetization.AnyAvailable(): boolean
	for _, product in Monetization.PRODUCTS do
		if Monetization.IsAvailable(product) then
			return true
		end
	end
	return false
end

-- Multiplicateur appliqué aux revenus d'un match (1 sans boost actif).
function Monetization.BoostMultiplier(data, now: number): number
	if not Monetization.BOOST_ENABLED or type(data) ~= "table" or type(data.boost) ~= "table" then
		return 1
	end
	local boost = data.boost
	if type(boost.expiresAt) == "number" and boost.expiresAt > now and type(boost.multiplier) == "number" then
		return math.clamp(boost.multiplier, 1, 2)
	end
	return 1
end

return Monetization
