--[[
	world-export3d.luau — utilisé par tools/world-3d.js à la place de world-check.luau.
	Lance le vrai WorldPreview.server.lua puis affiche toutes les Parts visibles
	(taille, position, matrice de rotation, couleur, matériau, forme) et les textes
	des panneaux (SurfaceGui) en JSON, pour l'aperçu 3D dans le navigateur.
]]
local Workspace = mock.env.game:GetService("Workspace")
mock.run(MODULES.WorldPreview)

local function r(n: number): string
	return string.format("%.3f", n)
end
local function q(s: string): string
	return (string.gsub(string.gsub(s, "\\", ""), '"', ""))
end
local function rgb(c): string
	return string.format("[%s,%s,%s]", r(c.R), r(c.G), r(c.B))
end
local out = {}
for _, d in Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		local cf, s, c = d.CFrame, d.Size, d.Color
		local R = cf.R
		local mat = if d.Material then d.Material.Name else "Plastic"
		local shape = if d:IsA("WedgePart") then "Wedge" elseif d.Shape then d.Shape.Name else "Block"
		local labels = {}
		for _, gui in d:GetChildren() do
			if gui:IsA("SurfaceGui") then
				for _, l in gui:GetDescendants() do
					if l:IsA("TextLabel") and l.Text and l.Text ~= "" then
						table.insert(
							labels,
							string.format(
								'{"f":"%s","x":"%s","tc":%s,"bg":%s}',
								gui.Face and gui.Face.Name or "Front",
								q(l.Text),
								rgb(l.TextColor3 or Color3.new(1, 1, 1)),
								if (l.BackgroundTransparency or 1) < 1 then rgb(l.BackgroundColor3) else "null"
							)
						)
						break
					end
				end
			end
		end
		table.insert(
			out,
			string.format(
				'{"s":[%s,%s,%s],"p":[%s,%s,%s],"r":[%s,%s,%s,%s,%s,%s,%s,%s,%s],"c":[%s,%s,%s],"t":%s,"m":"%s","h":"%s","n":"%s","l":[%s]}',
				r(s.X), r(s.Y), r(s.Z), r(cf.p.X), r(cf.p.Y), r(cf.p.Z),
				r(R[1][1]), r(R[1][2]), r(R[1][3]), r(R[2][1]), r(R[2][2]), r(R[2][3]), r(R[3][1]), r(R[3][2]), r(R[3][3]),
				r(c.R), r(c.G), r(c.B), r(d.Transparency), mat, shape, q(d.Name), table.concat(labels, ",")
			)
		)
	end
end
print("@@JSON_BEGIN@@")
print("[" .. table.concat(out, ",") .. "]")
print("@@JSON_END@@")
