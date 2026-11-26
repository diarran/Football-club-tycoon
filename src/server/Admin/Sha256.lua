--[[
	Sha256
	Empreinte SHA-256 d'un texte (renvoyée en hexadécimal, 64 caractères).

	Sert au code admin : le dépôt est public, donc on n'y écrit jamais le code
	lui-même, seulement son empreinte. Retrouver le code à partir de
	l'empreinte est impossible en pratique.
]]

local band, bxor, bnot = bit32.band, bit32.bxor, bit32.bnot
local rrotate, rshift = bit32.rrotate, bit32.rshift

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function add(...)
	local sum = 0
	for i = 1, select("#", ...) do
		sum = (sum + select(i, ...)) % 4294967296
	end
	return sum
end

local function sha256(message: string): string
	local length = #message
	-- Complément : 0x80, des zéros, puis la longueur en bits sur 8 octets.
	message ..= "\128" .. string.rep("\0", (55 - length) % 64)
	local bits = length * 8
	local tail = {}
	for i = 8, 1, -1 do
		tail[i] = string.char(bits % 256)
		bits = math.floor(bits / 256)
	end
	message ..= table.concat(tail)

	local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
	local w = {}
	for chunk = 1, #message, 64 do
		for i = 0, 15 do
			local a, b, c, d = string.byte(message, chunk + i * 4, chunk + i * 4 + 3)
			w[i] = ((a * 256 + b) * 256 + c) * 256 + d
		end
		for i = 16, 63 do
			local v15, v2 = w[i - 15], w[i - 2]
			local s0 = bxor(rrotate(v15, 7), rrotate(v15, 18), rshift(v15, 3))
			local s1 = bxor(rrotate(v2, 17), rrotate(v2, 19), rshift(v2, 10))
			w[i] = add(w[i - 16], s0, w[i - 7], s1)
		end
		local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
		for i = 0, 63 do
			local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = add(h, S1, ch, K[i + 1], w[i])
			local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			local t2 = add(S0, maj)
			h, g, f, e, d, c, b, a = g, f, e, add(d, t1), c, b, a, add(t1, t2)
		end
		h0, h1, h2, h3 = add(h0, a), add(h1, b), add(h2, c), add(h3, d)
		h4, h5, h6, h7 = add(h4, e), add(h5, f), add(h6, g), add(h7, h)
	end
	return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4, h5, h6, h7)
end

return sha256
