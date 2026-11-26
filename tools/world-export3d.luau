--[[
	world-export3d.luau — utilisé par tools/world-3d.js à la place de world-check.luau.
	Lance le vrai WorldPreview.server.lua puis affiche toutes les Parts visibles
	(taille, position, matrice de rotation, couleur, matériau, forme) en JSON,
	pour l'aperçu 3D dans le navigateur.
]]
local Workspace = mock.env.game:GetService("Workspace")
mock.run(MODULES.WorldPreview)

local function r(n: number): string
	return string.format("%.3f", n)
end
local out = {}
for _, d in Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		local cf, s, c = d.CFrame, d.Size, d.Color
		local R = cf.R
		local mat = if d.Material then d.Material.Name else "Plastic"
		local shape = if d:IsA("WedgePart") then "Wedge" elseif d.Shape then d.Shape.Name else "Block"
		table.insert(
			out,
			string.format(
				'{"s":[%s,%s,%s],"p":[%s,%s,%s],"r":[%s,%s,%s,%s,%s,%s,%s,%s,%s],"c":[%s,%s,%s],"t":%s,"m":"%s","h":"%s","n":"%s"}',
				r(s.X), r(s.Y), r(s.Z), r(cf.p.X), r(cf.p.Y), r(cf.p.Z),
				r(R[1][1]), r(R[1][2]), r(R[1][3]), r(R[2][1]), r(R[2][2]), r(R[2][3]), r(R[3][1]), r(R[3][2]), r(R[3][3]),
				r(c.R), r(c.G), r(c.B), r(d.Transparency), mat, shape, (string.gsub(d.Name, '"', ""))
			)
		)
	end
end
print("@@JSON_BEGIN@@")
print("[" .. table.concat(out, ",") .. "]")
print("@@JSON_END@@")
