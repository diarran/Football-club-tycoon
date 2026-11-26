--[[
	world-check.luau — exécuté par tools/world-preview.js APRÈS le mock Roblox et
	les modules du jeu (tout est concaténé dans un seul fichier temporaire).

	1. Lance le vrai script WorldPreview.server.lua (quartier + 6 terrains).
	2. Vérifie : Parts toutes ancrées, chaque Part dans son terrain, installations
	   dans leur empreinte, empreintes sans chevauchement, Spawn présent, API.
	3. Compte les Parts par installation et par niveau.
	4. Affiche un JSON (géométrie vue de dessus) entre deux marqueurs.

	Variables fournies par le fichier assemblé : mock, MODULES (instances).
]]

local WorldConfig = mock.run(MODULES.WorldConfig)
local WorldBuilder = mock.run(MODULES.WorldBuilder)
local Workspace = mock.env.game:GetService("Workspace")

local errors = {}
local function fail(msg: string)
	table.insert(errors, msg)
end

local function isPart(i): boolean
	return i:IsA("BasePart")
end

local function countParts(root): number
	local n = 0
	for _, d in root:GetDescendants() do
		if isPart(d) then
			n += 1
		end
	end
	return n
end

-- Coins (X, Z) de l'empreinte au sol d'une Part + hauteur de son sommet.
local function footprint(part)
	local cf, s = part.CFrame, part.Size
	local R = cf.R
	local axes = {
		{ R[1][1], R[2][1], R[3][1], s.X },
		{ R[1][2], R[2][2], R[3][2], s.Y },
		{ R[1][3], R[2][3], R[3][3], s.Z },
	}
	local vert = 1
	for i = 2, 3 do
		if math.abs(axes[i][2]) > math.abs(axes[vert][2]) then
			vert = i
		end
	end
	local h = {}
	for i = 1, 3 do
		if i ~= vert then
			table.insert(h, axes[i])
		end
	end
	local top = cf.p.Y
	for i = 1, 3 do
		top += math.abs(axes[i][2]) * axes[i][4] / 2
	end
	local pts = {}
	for _, sg in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local x = cf.p.X + sg[1] * h[1][1] * h[1][4] / 2 + sg[2] * h[2][1] * h[2][4] / 2
		local z = cf.p.Z + sg[1] * h[1][3] * h[1][4] / 2 + sg[2] * h[2][3] * h[2][4] / 2
		table.insert(pts, { x, z })
	end
	return pts, top
end

-- Point monde -> repère local du terrain.
local function toLocal(slotIndex: number, x: number, z: number)
	local cf = WorldConfig.getPlotCFrame(slotIndex)
	local dx, dz = x - cf.p.X, z - cf.p.Z
	local R = cf.R
	-- R^T * d (rotation autour de Y uniquement)
	return R[1][1] * dx + R[3][1] * dz, R[1][3] * dx + R[3][3] * dz
end

local function facilityOf(part): string
	local i = part.Parent
	while i and i.Parent do
		local f = i:GetAttribute("Facility")
		if f then
			return f
		end
		i = i.Parent
	end
	return "Plot"
end

------------------------------------------------------------------ 1. aperçu
mock.run(MODULES.WorldPreview)

local district = Workspace:FindFirstChild(WorldConfig.DISTRICT_NAME)
if not district then
	fail("District absent")
end

------------------------------------------------------------------ 2. vérifications
local EPS = 0.6
for slot = 1, WorldConfig.MAX_PLOTS do
	local plot = Workspace:FindFirstChild("Plot" .. slot)
	if not plot then
		fail("Plot" .. slot .. " absent")
		continue
	end
	if not plot.PrimaryPart then
		fail("Plot" .. slot .. " sans PrimaryPart")
	end
	local spawn = plot:FindFirstChild("Spawn")
	if not spawn or spawn.CanCollide ~= false or spawn.Transparency ~= 1 or not spawn.Anchored then
		fail("Plot" .. slot .. " : Spawn absent ou mal configuré")
	end
	local hx, hz = WorldConfig.PLOT_SIZE.X / 2, WorldConfig.PLOT_SIZE.Y / 2
	for _, d in plot:GetDescendants() do
		if isPart(d) then
			if not d.Anchored then
				fail(d:GetFullName() .. " non ancrée")
			end
			local pts = footprint(d)
			local facility = facilityOf(d)
			local layout = WorldConfig.LAYOUT[facility]
			for _, p in pts do
				local lx, lz = toLocal(slot, p[1], p[2])
				if math.abs(lx) > hx + EPS or math.abs(lz) > hz + EPS then
					fail(string.format("%s hors du terrain (%.1f, %.1f)", d:GetFullName(), lx, lz))
					break
				end
				if layout and d.Name ~= "Root" then
					local fx, fz = layout.footprint.X / 2, layout.footprint.Y / 2
					if math.abs(lx - layout.x) > fx + EPS or math.abs(lz - layout.z) > fz + EPS then
						fail(
							string.format(
								"%s dépasse l'empreinte de %s (%.1f, %.1f)",
								d:GetFullName(),
								facility,
								lx - layout.x,
								lz - layout.z
							)
						)
						break
					end
				end
			end
		end
	end
	-- Chaque installation : Model + Attributes + PrimaryPart.
	for _, id in WorldConfig.FACILITY_IDS do
		local f = plot:FindFirstChild(id)
		if not f or not f:IsA("Model") then
			fail("Plot" .. slot .. "." .. id .. " absent")
		elseif f:GetAttribute("Facility") ~= id or type(f:GetAttribute("Level")) ~= "number" or not f.PrimaryPart then
			fail("Plot" .. slot .. "." .. id .. " : attributs ou PrimaryPart manquants")
		end
	end
end

for _, d in (district and district:GetDescendants() or {}) do
	if isPart(d) and not d.Anchored then
		fail(d:GetFullName() .. " non ancrée")
	end
end

-- Empreintes des installations (hors couple Pitch/Stands, concentriques par conception).
local keys = { "Stands", "LockerRoom", "Training", "Offices", "Entrance" }
for i = 1, #keys do
	for j = i + 1, #keys do
		local a, b = WorldConfig.LAYOUT[keys[i]], WorldConfig.LAYOUT[keys[j]]
		local ox = math.abs(a.x - b.x) < (a.footprint.X + b.footprint.X) / 2
		local oz = math.abs(a.z - b.z) < (a.footprint.Y + b.footprint.Y) / 2
		if ox and oz then
			fail("Chevauchement d'empreintes : " .. keys[i] .. " / " .. keys[j])
		end
	end
end
-- Les terrains ne se chevauchent pas entre eux.
for i = 1, WorldConfig.MAX_PLOTS do
	for j = i + 1, WorldConfig.MAX_PLOTS do
		local a, b = WorldConfig.SLOTS[i], WorldConfig.SLOTS[j]
		if math.abs(a.x - b.x) < WorldConfig.PLOT_SIZE.X and math.abs(a.z - b.z) < WorldConfig.PLOT_SIZE.Y then
			fail("Emplacements " .. i .. " et " .. j .. " se chevauchent")
		end
	end
end

------------------------------------------------------------------ 3. comptage par niveau
local counts = {}
for level = 1, WorldConfig.MAX_LEVEL do
	local levels = {}
	for _, id in WorldConfig.FACILITY_IDS do
		levels[id] = level
	end
	-- On reconstruit temporairement sur l'emplacement 6, puis on remet sa version d'origine.
	local plot = WorldBuilder.buildPlot(6, levels, "Test")
	local row = { level = level, total = countParts(plot), facilities = {} }
	for _, child in plot:GetChildren() do
		if child:IsA("Model") or isPart(child) then
			local n = if isPart(child) then 1 else countParts(child)
			local key = child:GetAttribute("Facility") or "Sol/allées/spawn"
			row.facilities[key] = (row.facilities[key] or 0) + n
		end
	end
	table.insert(counts, row)
end
local districtCount = if district then countParts(district) else 0

-- API : remplacement, idempotence, setFacilityLevel, clés absentes, forme « options ».
local before = #Workspace:GetChildren()
WorldBuilder.buildPlot(6, { Pitch = 2 })
WorldBuilder.buildDistrict()
if #Workspace:GetChildren() ~= before then
	fail("buildPlot/buildDistrict ont dupliqué des modèles")
end
local p6 = Workspace:FindFirstChild("Plot6")
if p6:GetAttribute("Level_Stands") ~= 1 or p6:GetAttribute("Level_Pitch") ~= 2 then
	fail("Niveaux par défaut incorrects")
end
local standsBefore = p6:FindFirstChild("Stands")
local pitchBefore = p6:FindFirstChild("Pitch")
WorldBuilder.setFacilityLevel(p6, "Stands", 3)
if p6:FindFirstChild("Stands") == standsBefore or p6:FindFirstChild("Stands"):GetAttribute("Level") ~= 3 then
	fail("setFacilityLevel n'a pas reconstruit les tribunes")
end
if p6:FindFirstChild("Pitch") ~= pitchBefore then
	fail("setFacilityLevel a touché une autre installation")
end
WorldBuilder.setClubName(p6, "Nouveau Nom")
WorldBuilder.buildPlot(6, { clubName = "Union Ferlac", levels = { Pitch = 1 } })
if Workspace:FindFirstChild("Plot6"):GetAttribute("ClubName") ~= "Union Ferlac" then
	fail("Forme options de buildPlot non prise en charge")
end
-- Combinaison extrême : terrain 3 + tribunes 3 + reste 1 (vérifie la cohabitation).
WorldBuilder.buildPlot(6, { Pitch = 3, Stands = 3 }, "Union Ferlac")
WorldBuilder.buildPlot(6, nil, "Union Ferlac")

------------------------------------------------------------------ 4. export JSON
local function hex(c): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function round(n: number): string
	return string.format("%.2f", n)
end
local out = {}
local function emit(root, group: string)
	for _, d in root:GetDescendants() do
		if isPart(d) and d.Transparency < 1 then
			local pts, top = footprint(d)
			local coords = {}
			for _, p in pts do
				table.insert(coords, "[" .. round(p[1]) .. "," .. round(p[2]) .. "]")
			end
			local shape = if d.Shape and d.Shape.Name ~= "Block" then d.Shape.Name else "Block"
			table.insert(
				out,
				string.format(
					'{"g":"%s","n":"%s","f":"%s","c":"%s","t":%s,"top":%s,"shape":"%s","pts":[%s]}',
					group,
					d.Name,
					facilityOf(d),
					hex(d.Color),
					round(d.Transparency),
					round(top),
					shape,
					table.concat(coords, ",")
				)
			)
		end
	end
end
if district then
	emit(district, "District")
end
for slot = 1, WorldConfig.MAX_PLOTS do
	local plot = Workspace:FindFirstChild("Plot" .. slot)
	if plot then
		emit(plot, "Plot" .. slot)
	end
end

local countJson = {}
for _, row in counts do
	local fac = {}
	for k, v in row.facilities do
		table.insert(fac, string.format('"%s":%d', k, v))
	end
	table.sort(fac)
	table.insert(countJson, string.format('{"level":%d,"total":%d,"facilities":{%s}}', row.level, row.total, table.concat(fac, ",")))
end
-- Empreintes déclarées dans WorldConfig.LAYOUT, en coordonnées monde (pour le dessin).
local fp = {}
for slot = 1, WorldConfig.MAX_PLOTS do
	local cf = WorldConfig.getPlotCFrame(slot)
	for key, layout in WorldConfig.LAYOUT do
		local coords = {}
		local fx, fz = layout.footprint.X / 2, layout.footprint.Y / 2
		for _, sg in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local w = cf * mock.env.Vector3.new(layout.x + sg[1] * fx, 0, layout.z + sg[2] * fz)
			table.insert(coords, "[" .. round(w.X) .. "," .. round(w.Z) .. "]")
		end
		table.insert(fp, string.format('{"slot":%d,"key":"%s","pts":[%s]}', slot, key, table.concat(coords, ",")))
	end
end
local slotJson = {}
for slot, s in WorldConfig.SLOTS do
	local plot = Workspace:FindFirstChild("Plot" .. slot)
	table.insert(
		slotJson,
		string.format(
			'{"slot":%d,"x":%s,"z":%s,"yaw":%s,"club":"%s","level":%d}',
			slot,
			round(s.x),
			round(s.z),
			round(s.yaw),
			plot and plot:GetAttribute("ClubName") or "",
			plot and plot:GetAttribute("Level_Pitch") or 0
		)
	)
end
local errJson = {}
for _, e in errors do
	table.insert(errJson, '"' .. string.gsub(e, '"', "'") .. '"')
end

print("@@JSON_BEGIN@@")
print(
	string.format(
		'{"errors":[%s],"districtParts":%d,"plotSize":[%s,%s],"districtSize":[%s,%s],"slots":[%s],"footprints":[%s],"counts":[%s],"parts":[%s]}',
		table.concat(errJson, ","),
		districtCount,
		round(WorldConfig.PLOT_SIZE.X),
		round(WorldConfig.PLOT_SIZE.Y),
		round(WorldConfig.DISTRICT_SIZE.X),
		round(WorldConfig.DISTRICT_SIZE.Y),
		table.concat(slotJson, ","),
		table.concat(fp, ","),
		table.concat(countJson, ","),
		table.concat(out, ",")
	)
)
print("@@JSON_END@@")
