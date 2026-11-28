--[[
	roblox-mock.luau — imitation MINIMALE de l'API Roblox pour exécuter les
	modules src/server/World hors de Roblox Studio (avec le binaire `luau`).

	Ce n'est PAS un émulateur complet : juste ce que les modules du monde utilisent
	(Instance, Vector2/3, CFrame, Color3, Enum, UDim/UDim2, game:GetService, task).
	Utilisé par tools/world-preview.js pour compter les Parts, vérifier les
	chevauchements et dessiner la vue de dessus.
]]

local mock = {}

------------------------------------------------------------------ Vector3
local Vector3 = {}
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return nil
end
function Vector3.new(x: number?, y: number?, z: number?)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __kind = "Vector3" }, V3)
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
V3.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)

------------------------------------------------------------------ Vector2
local Vector2 = {}
local V2 = {}
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return nil
end
function Vector2.new(x: number?, y: number?)
	return setmetatable({ X = x or 0, Y = y or 0, __kind = "Vector2" }, V2)
end
V2.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return Vector2.new(a.X / b, a.Y / b)
end
Vector2.zero = Vector2.new(0, 0)

------------------------------------------------------------------ CFrame
-- R = matrice 3x3 (lignes), p = position.
local CFrame = {}
local CF = {}
local function mkcf(p, R)
	return setmetatable({ p = p, R = R, __kind = "CFrame" }, CF)
end
local function matmul(A, B)
	local C = {}
	for i = 1, 3 do
		C[i] = {}
		for j = 1, 3 do
			C[i][j] = A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j]
		end
	end
	return C
end
local function matvec(A, v)
	return Vector3.new(
		A[1][1] * v.X + A[1][2] * v.Y + A[1][3] * v.Z,
		A[2][1] * v.X + A[2][2] * v.Y + A[2][3] * v.Z,
		A[3][1] * v.X + A[3][2] * v.Y + A[3][3] * v.Z
	)
end
local IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
CF.__index = function(cf, k)
	if k == "Position" then
		return cf.p
	elseif k == "LookVector" then
		return Vector3.new(-cf.R[1][3], -cf.R[2][3], -cf.R[3][3])
	end
	return nil
end
CF.__mul = function(a, b)
	if b.__kind == "CFrame" then
		return mkcf(a.p + matvec(a.R, b.p), matmul(a.R, b.R))
	end
	return a.p + matvec(a.R, b)
end
-- CFrame + Vector3 : même orientation, position décalée (comme dans Roblox).
CF.__add = function(a, b)
	return mkcf(a.p + b, a.R)
end
function CFrame.new(x: any?, y: number?, z: number?)
	if x == nil then
		return mkcf(Vector3.zero, IDENTITY)
	elseif type(x) == "table" then
		return mkcf(x, IDENTITY)
	end
	return mkcf(Vector3.new(x, y, z), IDENTITY)
end
function CFrame.Angles(rx: number, ry: number, rz: number)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local Rx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Ry = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Rz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return mkcf(Vector3.zero, matmul(matmul(Rx, Ry), Rz))
end
local function cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function CFrame.lookAt(pos, target)
	local look = (target - pos).Unit
	local right = cross(look, Vector3.new(0, 1, 0)).Unit
	local up = cross(right, look)
	local back = -look
	return mkcf(pos, {
		{ right.X, up.X, back.X },
		{ right.Y, up.Y, back.Y },
		{ right.Z, up.Z, back.Z },
	})
end

------------------------------------------------------------------ Color3, UDim, Enum
local Color3 = {}
function Color3.new(r: number, g: number, b: number)
	return { R = r, G = g, B = b, __kind = "Color3" }
end
function Color3.fromRGB(r: number, g: number, b: number)
	return Color3.new(r / 255, g / 255, b / 255)
end
local UDim = {
	new = function(s, o)
		return { Scale = s, Offset = o }
	end,
}
local UDim2 = {
	fromScale = function(x, y)
		return { X = x, Y = y }
	end,
	new = function(a, b, c, d)
		return { a, b, c, d }
	end,
}
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumType)
		enumCache[enumType] = enumCache[enumType]
			or setmetatable({}, {
				__index = function(t, name)
					local item = { Name = name, EnumType = enumType }
					rawset(t, name, item)
					return item
				end,
			})
		return enumCache[enumType]
	end,
})

------------------------------------------------------------------ Instances
local CLASS_TREE = {
	Part = { "Part", "FormFactorPart", "BasePart", "PVInstance" },
	WedgePart = { "WedgePart", "FormFactorPart", "BasePart", "PVInstance" },
	SpawnLocation = { "SpawnLocation", "Part", "FormFactorPart", "BasePart", "PVInstance" },
	Model = { "Model", "PVInstance" },
	SurfaceGui = { "SurfaceGui", "SurfaceGuiBase", "LayerCollector", "GuiBase" },
	TextLabel = { "TextLabel", "GuiLabel", "GuiObject", "GuiBase2d" },
	SpotLight = { "SpotLight", "Light" },
	PointLight = { "PointLight", "Light" },
}

local Inst = {}
local methods = {}

function methods:IsA(className: string): boolean
	if className == "Instance" or className == self.ClassName then
		return true
	end
	for _, c in CLASS_TREE[self.ClassName] or {} do
		if c == className then
			return true
		end
	end
	return false
end
function methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in rawget(i, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name: string)
	for _, c in rawget(self, "_children") do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods:WaitForChild(name: string)
	local c = self:FindFirstChild(name)
	if not c then
		error("WaitForChild bloquerait indéfiniment : " .. self.Name .. "." .. name)
	end
	return c
end
function methods:FindFirstChildWhichIsA(className: string)
	for _, c in rawget(self, "_children") do
		if c:IsA(className) then
			return c
		end
	end
	return nil
end
function methods:SetAttribute(key: string, value: any)
	rawget(self, "_attributes")[key] = value
end
function methods:GetAttribute(key: string)
	return rawget(self, "_attributes")[key]
end
function methods:GetAttributes()
	return table.clone(rawget(self, "_attributes"))
end
function methods:Destroy()
	self.Parent = nil
	rawset(self, "_destroyed", true)
end
function methods:GetFullName()
	local parts = {}
	local i = self
	while i and i.ClassName ~= "DataModel" do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, ".")
end

Inst.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	local props = rawget(self, "_props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	return self:FindFirstChild(key)
end
Inst.__newindex = function(self, key, value)
	local props = rawget(self, "_props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "_children")
			local idx = table.find(list, self)
			if idx then
				table.remove(list, idx)
			end
		end
		props.Parent = value
		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end
	props[key] = value
end

mock.created = 0
local function newInstance(className: string)
	mock.created += 1
	local props = { ClassName = className, Name = className }
	if CLASS_TREE[className] and table.find(CLASS_TREE[className], "BasePart") then
		props.Anchored = false
		props.CanCollide = true
		props.Transparency = 0
		props.Size = Vector3.new(4, 1, 2)
		props.CFrame = CFrame.new()
		props.Color = Color3.new(0.6, 0.6, 0.6)
		props.Shape = Enum.PartType.Block
	end
	return setmetatable({ _props = props, _children = {}, _attributes = {} }, Inst)
end
local Instance = { new = newInstance }

------------------------------------------------------------------ game, script, require
local game = newInstance("DataModel")
game.Name = "Game"
rawget(game, "_props").GetService = function(self, name)
	local s = self:FindFirstChild(name)
	if not s then
		s = newInstance(name)
		s.Name = name
		s.Parent = self
	end
	return s
end

local moduleSources = {} -- [Instance] = function(script) ... end
local moduleCache = {}
local function mockRequire(moduleScript)
	if moduleCache[moduleScript] == nil then
		local fn = moduleSources[moduleScript]
		assert(fn, "require : module inconnu " .. tostring(moduleScript and moduleScript.Name))
		moduleCache[moduleScript] = fn(moduleScript)
	end
	return moduleCache[moduleScript]
end

-- Crée l'arborescence de dossiers et le (Module)Script correspondant à `path`.
function mock.register(path: { string }, className: string, fn)
	local parent = game:GetService(path[1])
	for i = 2, #path - 1 do
		local child = parent:FindFirstChild(path[i])
		if not child then
			child = newInstance("Folder")
			child.Name = path[i]
			child.Parent = parent
		end
		parent = child
	end
	local s = newInstance(className)
	s.Name = path[#path]
	s.Parent = parent
	moduleSources[s] = fn
	return s
end

function mock.run(scriptInstance)
	return mockRequire(scriptInstance)
end

mock.env = {
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	Enum = Enum,
	Instance = Instance,
	game = game,
	workspace = game:GetService("Workspace"),
	require = mockRequire,
	task = { wait = function() end },
	warn = function(...)
		print("[warn]", ...)
	end,
	typeof = function(v)
		if type(v) == "table" and rawget(v, "__kind") then
			return rawget(v, "__kind")
		elseif type(v) == "table" and getmetatable(v) == Inst then
			return "Instance"
		end
		return typeof(v)
	end,
}
mock.matvec = matvec

return mock
