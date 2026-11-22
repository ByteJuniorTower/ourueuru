-- The lobby (milestone 10): "Guardians' Glade", a twilight glade under the Black Moon where players gather a party.
-- Built from simple shapes in a chunky low-poly look; every prop is its own named Model made by its own function
-- (B.Props), so that imported meshes can replace them later.
-- Rebuild in Studio (edit mode):  require(game.ServerStorage.Modules.LobbyBuilder).Build()
-- The server calls Ensure() on start, which builds the lobby only when it is missing.
-- Contract with other scripts: Lobby.Spawn_1..8, Lobby.ExpeditionCircle (Zone part, Radius attribute, Runes folder),
-- world labels are parts named Label_<key> with attribute LocaleKey (the client localises them).
local B = {}
local Mat = Enum.Material

B.GladeRadius = 96
B.PlazaRadius = 30
B.Spawns = 8
B.Circle = {Center = Vector3.new(0, 0, -52), Radius = 13}
B.Props = {}

local P = B.Props

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local CREAM = rgb(244, 240, 228)
local STEM = rgb(232, 222, 198)
local RED = rgb(190, 52, 44)
local AMBER = rgb(255, 214, 120)
local TEAL = rgb(120, 230, 200)
local WOOD = rgb(96, 72, 52)
local DARKWOOD = rgb(72, 56, 44)
local STONE = rgb(132, 130, 128)
local DARKSTONE = rgb(98, 98, 104)
local MOSS = rgb(74, 122, 66)
local DIRT = rgb(112, 90, 66)
local LABEL = rgb(255, 244, 214)

-- Small decorative parts do not collide and cast no shadow
local DECO = {CanCollide = false, CastShadow = false}
local GHOST = {CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false, Transparency = 1}

local function with(base, more)
	local t = table.clone(base)
	for k, v in pairs(more) do t[k] = v end
	return t
end

local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	-- CanCollide goes first: CanQuery can be switched off only on a part that does not collide
	if extra and extra.CanCollide ~= nil then p.CanCollide = extra.CanCollide end
	for k, v in pairs(extra or {}) do p[k] = v end
	p.Parent = parent
	return p
end

-- An upright cylinder: cf is its middle, the axis is the Y axis of cf
local function cylinder(parent, name, height, diameter, cf, color, material, extra)
	local e = extra and table.clone(extra) or {}
	e.Shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, e)
end

-- A lying cylinder: the axis is the X axis of cf
local function hcyl(parent, name, length, diameter, cf, color, material, extra)
	local e = extra and table.clone(extra) or {}
	e.Shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, e)
end

local function ball(parent, name, size, cf, color, material, extra)
	local p = part(parent, name, size, cf, color, material, extra)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function wedge(parent, name, size, cf, color, material, extra)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	for k, v in pairs(extra or {}) do p[k] = v end
	p.Parent = parent
	return p
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A point on a circle around the middle of the lobby: angle in degrees, radius in studs
local function around(deg, radius, y)
	local a = math.rad(deg)
	return Vector3.new(math.sin(a) * radius, y, -math.cos(a) * radius)
end

-- A CFrame standing on the ground at pos whose front (-Z) looks at target
local function facing(pos, target)
	return CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function fade(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, peak),
		NumberSequenceKeypoint.new(0.8, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- A flat ring of thin blocks lying on the ground around center
local function ring(parent, name, center, radius, count, height, width, color, material, extra)
	local len = 2 * math.pi * radius / count * 1.06
	for i = 1, count do
		part(parent, name, Vector3.new(len, height, width),
			CFrame.new(center) * CFrame.Angles(0, math.rad(i * 360 / count), 0) * CFrame.new(0, 0, -radius), color, material, extra)
	end
end

-- An upright oval ring in the XY plane of cf
local function vring(parent, name, cf, rx, ry, count, thick, color, material, extra)
	local len = 2 * math.pi * math.max(rx, ry) / count * 1.05
	for i = 1, count do
		local a = math.rad(i * 360 / count)
		local tangent = math.atan2(ry * math.cos(a), -rx * math.sin(a))
		part(parent, name, Vector3.new(len, thick, thick),
			cf * CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 0) * CFrame.Angles(0, 0, tangent), color, material, extra)
	end
end

-- A world label: the client replaces the text by the player's language using the LocaleKey attribute
local function label(parent, key, pos, text, opts)
	opts = opts or {}
	local anchor = part(parent, opts.Name or ("Label_" .. key), Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), LABEL, Mat.SmoothPlastic, GHOST)
	anchor:SetAttribute("LocaleKey", key)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = opts.Size or UDim2.fromOffset(260, opts.HintKey and 64 or 44)
	gui.StudsOffset = Vector3.new(0, opts.Offset or 1.5, 0)
	gui.MaxDistance = opts.MaxDistance or 90
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local function line(name, str, y, h)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0, y)
		t.Size = UDim2.fromScale(1, h)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = LABEL
		t.TextStrokeTransparency = 0.35
		t.Text = str
		t.Parent = gui
		return t
	end
	if opts.HintKey then
		line("Text", text, 0, 0.62)
		local hint = line("Hint", opts.Hint, 0.64, 0.36)
		hint:SetAttribute("LocaleKey", opts.HintKey)
	else
		line("Text", text, 0, 1)
	end
	gui.Parent = anchor
	return anchor
end

-- ---------------------------------------------------------------------------------------------------------------
-- Props: each takes the parent and a CFrame standing on the ground, and returns a Model

-- opts: Spots (true or a colour), Glow, Collide, Name, StemColor, Wide (cap width as a share of the height)
function P.Mushroom(parent, cf, height, capColor, opts)
	opts = opts or {}
	local m = model(parent, opts.Name or "Mushroom")
	local e = opts.Collide and {} or DECO
	local w = height * (opts.Wide or 1.2)
	cylinder(m, "Stem", height, height * 0.3, cf * CFrame.new(0, height / 2, 0), opts.StemColor or STEM, Mat.SmoothPlastic, e)
	local cap = ball(m, "Cap", Vector3.new(w, height * 0.5, w), cf * CFrame.new(0, height, 0), capColor,
		opts.Glow and Mat.Neon or Mat.SmoothPlastic, e)
	if opts.Glow then light(cap, capColor, math.clamp(height * 3, 8, 20), 0.8) end
	if opts.Spots then
		local color = typeof(opts.Spots) == "Color3" and opts.Spots or CREAM
		for i = 1, 4 do
			local a = math.rad(i * 90 + 25)
			ball(m, "Spot", Vector3.new(w * 0.2, height * 0.1, w * 0.2),
				cf * CFrame.new(math.sin(a) * w * 0.28, height * 1.2, math.cos(a) * w * 0.28), color, Mat.SmoothPlastic, DECO)
		end
	end
	return m
end

function P.SporeLantern(parent, cf)
	local m = model(parent, "SporeLantern")
	local lean = cf * CFrame.Angles(0, 0, math.rad(4))
	cylinder(m, "Post", 9, 0.8, lean * CFrame.new(0, 4.5, 0), DARKWOOD, Mat.Wood)
	cylinder(m, "Foot", 0.6, 1.5, cf * CFrame.new(0, 0.3, 0), DARKSTONE, Mat.Slate, DECO)
	part(m, "Beam", Vector3.new(0.45, 0.45, 3.4), lean * CFrame.new(0, 8.4, -1.3), DARKWOOD, Mat.Wood, DECO)
	part(m, "Brace", Vector3.new(0.3, 0.3, 2), lean * CFrame.new(0, 7.5, -0.8) * CFrame.Angles(math.rad(45), 0, 0), DARKWOOD, Mat.Wood, DECO)
	local hang = cf * CFrame.new(-0.6, 0, -2.6)
	cylinder(m, "Chain", 1.3, 0.12, hang * CFrame.new(0, 7.6, 0), rgb(50, 46, 44), Mat.Metal, DECO)
	ball(m, "Cap", Vector3.new(3, 1.5, 3), hang * CFrame.new(0, 6.7, 0), RED, Mat.SmoothPlastic, DECO)
	for i = 1, 4 do
		local a = math.rad(i * 90 + 20)
		ball(m, "Spot", Vector3.new(0.6, 0.3, 0.6), hang * CFrame.new(math.sin(a) * 0.85, 7.28, math.cos(a) * 0.85), CREAM, Mat.SmoothPlastic, DECO)
	end
	local bulb = ball(m, "Bulb", Vector3.new(1.6, 1.9, 1.6), hang * CFrame.new(0, 5.9, 0), AMBER, Mat.Neon, DECO)
	light(bulb, AMBER, 26, 1.3)
	cylinder(m, "Tip", 0.3, 0.5, hang * CFrame.new(0, 4.9, 0), DARKWOOD, Mat.Wood, DECO)
	return m
end

-- opts: Dead (leafless), Collide, Seed
function P.Tree(parent, cf, height, opts)
	opts = opts or {}
	local m = model(parent, opts.Dead and "DeadTree" or "Tree")
	local rng = Random.new(opts.Seed or 1)
	local e = opts.Collide and {} or DECO
	local d = math.max(height * 0.09, 1)
	if opts.Dead then
		cylinder(m, "Trunk", height, d, cf * CFrame.new(0, height / 2, 0), rgb(86, 82, 80), Mat.Wood, e)
		for i = 1, 5 do
			local len = height * rng:NextNumber(0.3, 0.5)
			local at = cf * CFrame.new(0, height * rng:NextNumber(0.5, 0.95), 0) * CFrame.Angles(0, math.rad(i * 72 + rng:NextNumber(-20, 20)), 0)
				* CFrame.Angles(0, 0, math.rad(rng:NextNumber(40, 65)))
			cylinder(m, "Branch", len, d * 0.35, at * CFrame.new(0, len / 2, 0), rgb(86, 82, 80), Mat.Wood, DECO)
		end
		return m
	end
	cylinder(m, "Trunk", height * 0.6, d, cf * CFrame.new(0, height * 0.3, 0), rgb(46, 38, 40), Mat.Wood, e)
	local greens = {rgb(28, 70, 72), rgb(34, 84, 80), rgb(24, 58, 66)}
	for i = 1, 3 do
		local w = height * (0.62 - i * 0.11) * rng:NextNumber(0.9, 1.15)
		ball(m, "Canopy", Vector3.new(w, height * 0.3, w),
			cf * CFrame.new(rng:NextNumber(-1, 1), height * (0.42 + i * 0.17), rng:NextNumber(-1, 1)), greens[i], Mat.Grass, DECO)
	end
	return m
end

-- size is the rough width; opts: Collide, Seed, Color
function P.Rock(parent, cf, size, opts)
	opts = opts or {}
	local m = model(parent, "Rock")
	local rng = Random.new(opts.Seed or 1)
	local e = opts.Collide and {} or DECO
	local color = opts.Color or STONE
	part(m, "Stone", Vector3.new(size, size * 0.7, size * 0.85),
		cf * CFrame.new(0, size * 0.25, 0) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-12, 12))),
		color, Mat.Slate, e)
	part(m, "Stone", Vector3.new(size * 0.6, size * 0.5, size * 0.55),
		cf * CFrame.new(size * 0.45, size * 0.15, size * 0.2) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(0, 90)), 0),
		color:Lerp(Color3.new(0, 0, 0), 0.12), Mat.Slate, e)
	return m
end

-- A log to sit on: it lies along the X axis of cf
function P.LogBench(parent, cf)
	local m = model(parent, "LogBench")
	hcyl(m, "Log", 6, 1.6, cf * CFrame.new(0, 1.1, 0), WOOD, Mat.Wood)
	hcyl(m, "CutEnd", 0.1, 1.3, cf * CFrame.new(3.02, 1.1, 0), rgb(196, 164, 118), Mat.Wood, DECO)
	hcyl(m, "CutEnd", 0.1, 1.3, cf * CFrame.new(-3.02, 1.1, 0), rgb(196, 164, 118), Mat.Wood, DECO)
	for _, x in ipairs({-2, 2}) do
		part(m, "Foot", Vector3.new(0.9, 0.6, 2), cf * CFrame.new(x, 0.3, 0), DARKWOOD, Mat.Wood, DECO)
	end
	return m
end

-- A wicker basket full of small mushrooms; colors is an optional list of cap colours
function P.Basket(parent, cf, colors)
	local m = model(parent, "Basket")
	colors = colors or {RED, rgb(226, 170, 70), rgb(120, 170, 220)}
	cylinder(m, "Wicker", 1.3, 2.2, cf * CFrame.new(0, 0.65, 0), rgb(168, 126, 78), Mat.WoodPlanks, DECO)
	cylinder(m, "Rim", 0.2, 2.5, cf * CFrame.new(0, 1.3, 0), rgb(134, 98, 60), Mat.Wood, DECO)
	for i = 1, 5 do
		local a = math.rad(i * 72)
		local r = i == 5 and 0 or 0.6
		ball(m, "Cap", Vector3.new(0.9, 0.5, 0.9), cf * CFrame.new(math.sin(a) * r, 1.5 + (i % 2) * 0.12, math.cos(a) * r),
			colors[(i - 1) % #colors + 1], Mat.SmoothPlastic, DECO)
	end
	return m
end

function P.Crate(parent, cf, size)
	size = size or 2.4
	local m = model(parent, "Crate")
	part(m, "Box", Vector3.new(size, size, size), cf * CFrame.new(0, size / 2, 0), rgb(150, 112, 72), Mat.WoodPlanks)
	for _, y in ipairs({0.2, 0.8}) do
		part(m, "Slat", Vector3.new(size + 0.15, size * 0.14, size + 0.15), cf * CFrame.new(0, size * y, 0), WOOD, Mat.Wood, DECO)
	end
	return m
end

-- A standing stone with a glyph on its front. opts: Lit, Color (glyph), Height, Width, Tilt (degrees)
function P.RuneStone(parent, cf, opts)
	opts = opts or {}
	local m = model(parent, "RuneStone")
	local h, w = opts.Height or 5, opts.Width or 3
	local at = cf * CFrame.Angles(math.rad(opts.Tilt or 0), 0, math.rad((opts.Tilt or 0) * 0.6))
	part(m, "Slab", Vector3.new(w, h, w * 0.3), at * CFrame.new(0, h / 2, 0), DARKSTONE, Mat.Slate, h < 3 and DECO or nil)
	part(m, "Top", Vector3.new(w * 0.7, h * 0.12, w * 0.3), at * CFrame.new(0, h * 1.05, 0), DARKSTONE, Mat.Slate, DECO)
	local color = opts.Lit and (opts.Color or TEAL) or rgb(52, 52, 60)
	local material = opts.Lit and Mat.Neon or Mat.Slate
	local front = at * CFrame.new(0, h * 0.55, -w * 0.15 - 0.03)
	local g = part(m, "Glyph", Vector3.new(w * 0.1, h * 0.5, 0.08), front, color, material, DECO)
	part(m, "Glyph", Vector3.new(w * 0.5, h * 0.06, 0.08), front * CFrame.new(0, h * 0.12, 0) * CFrame.Angles(0, 0, math.rad(25)), color, material, DECO)
	part(m, "Glyph", Vector3.new(w * 0.4, h * 0.06, 0.08), front * CFrame.new(0, -h * 0.1, 0) * CFrame.Angles(0, 0, math.rad(-25)), color, material, DECO)
	if opts.Lit then light(g, color, 12, 1) end
	m:SetAttribute("Lit", opts.Lit == true)
	return m
end

-- A wooden post with two plain arrow boards: the first points along -Z of cf
function P.Signpost(parent, cf)
	local m = model(parent, "Signpost")
	cylinder(m, "Post", 6.5, 0.6, cf * CFrame.new(0, 3.25, 0), DARKWOOD, Mat.Wood)
	for i, yaw in ipairs({0, 110}) do
		local at = cf * CFrame.new(0, 5.9 - i * 1.1, 0) * CFrame.Angles(0, math.rad(yaw), 0)
		part(m, "Arrow", Vector3.new(0.2, 0.8, 2.6), at * CFrame.new(0, 0, -1), rgb(170, 132, 88), Mat.WoodPlanks, DECO)
		wedge(m, "ArrowTip", Vector3.new(0.2, 0.8, 0.8), at * CFrame.new(0, 0, -2.7) * CFrame.Angles(0, math.rad(180), 0), rgb(170, 132, 88), Mat.WoodPlanks, DECO)
	end
	return m
end

-- A low fence segment along the X axis of cf
function P.Fence(parent, cf, length)
	length = length or 6
	local m = model(parent, "Fence")
	for _, x in ipairs({-length / 2, length / 2}) do
		part(m, "Post", Vector3.new(0.5, 2.6, 0.5), cf * CFrame.new(x, 1.3, 0), DARKWOOD, Mat.Wood)
	end
	for _, y in ipairs({1, 2}) do
		part(m, "Rail", Vector3.new(length, 0.3, 0.25), cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(y == 1 and 1.5 or -1.5)), WOOD, Mat.Wood, DECO)
	end
	return m
end

-- A harvest sickle standing on the end of its handle; the blade curves towards +X of cf
function P.Sickle(parent, cf, scale, handle, color, material)
	local m = model(parent, "Sickle")
	scale = scale or 1
	handle = handle or 2.2 * scale
	cylinder(m, "Handle", handle, 0.22 * scale, cf * CFrame.new(0, handle / 2, 0), color or WOOD, material or Mat.Wood, DECO)
	local r = 1.1 * scale
	for i = 1, 5 do
		local a = math.rad(i * 30 - 15)
		part(m, "Blade", Vector3.new(r * math.rad(30) * 1.15, 0.3 * scale * (1.1 - i * 0.12), 0.06 * scale),
			cf * CFrame.new(r - r * math.cos(a), handle + r * math.sin(a), 0) * CFrame.Angles(0, 0, math.rad(90) - a),
			color or rgb(190, 196, 204), material or Mat.Metal, DECO)
	end
	return m
end

function P.Barrel(parent, cf)
	local m = model(parent, "Barrel")
	cylinder(m, "Staves", 3.2, 2.4, cf * CFrame.new(0, 1.6, 0), rgb(128, 92, 60), Mat.WoodPlanks)
	for _, y in ipairs({0.6, 2.6}) do
		cylinder(m, "Hoop", 0.2, 2.55, cf * CFrame.new(0, y, 0), rgb(60, 58, 60), Mat.Metal, DECO)
	end
	return m
end

-- A line of small flags sagging between two points
local function bunting(parent, from, to, count)
	local m = model(parent, "Bunting")
	local colors = {RED, AMBER, rgb(120, 170, 220), CREAM, rgb(150, 90, 230)}
	local function at(t)
		return from:Lerp(to, t) - Vector3.new(0, 1.4 * 4 * t * (1 - t), 0)
	end
	for i = 1, count do
		local a, b = at((i - 1) / count), at(i / count)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b)
		part(m, "Line", Vector3.new(0.08, 0.08, (b - a).Magnitude), cf, rgb(60, 50, 44), Mat.Fabric, DECO)
		part(m, "Flag", Vector3.new(0.06, 1.1, 0.9), CFrame.new(mid - Vector3.new(0, 0.6, 0)) * (cf - cf.Position), colors[(i - 1) % #colors + 1], Mat.Fabric, DECO)
	end
	return m
end

-- ---------------------------------------------------------------------------------------------------------------
-- Areas

-- Dirt paths; scattered details keep off them
local pathSegments = {}

local function path(parent, from, to, width)
	local a, b = Vector3.new(from.X, 0.06, from.Z), Vector3.new(to.X, 0.06, to.Z)
	part(parent, "Path", Vector3.new(width, 0.12, (b - a).Magnitude + width * 0.5), CFrame.lookAt((a + b) / 2, b), DIRT, Mat.Ground, {CastShadow = false})
	table.insert(pathSegments, {a, b, width})
end

local function ground(lobby)
	local m = model(lobby, "Ground")
	cylinder(m, "Outskirts", 4, 300, CFrame.new(0, -2.3, 0), rgb(40, 62, 56), Mat.Grass, {CastShadow = false})
	cylinder(m, "Glade", 4, B.GladeRadius * 2, CFrame.new(0, -2, 0), rgb(78, 124, 78), Mat.Grass)
	cylinder(m, "Plaza", 0.4, B.PlazaRadius * 2, CFrame.new(0, 0.2, 0), rgb(150, 144, 130), Mat.Cobblestone)
	cylinder(m, "PlazaInlay", 0.06, 22, CFrame.new(0, 0.41, 0), rgb(120, 114, 108), Mat.Slate, DECO)
	ring(m, "Kerb", Vector3.new(0, 0.3, 0), B.PlazaRadius, 36, 0.6, 1.2, rgb(118, 114, 108), Mat.Slate, DECO)

	table.clear(pathSegments)
	path(m, Vector3.new(0, 0, -29), Vector3.new(0, 0, -72), 7)
	path(m, Vector3.new(29, 0, 0), Vector3.new(54, 0, 0), 6)
	path(m, Vector3.new(-29, 0, 0), Vector3.new(-52, 0, 3), 6)
	path(m, Vector3.new(0, 0, 29), Vector3.new(0, 0, 33), 6)
	path(m, Vector3.new(0, 0, 32), Vector3.new(30, 0, 37), 5)
	path(m, Vector3.new(0, 0, 32), Vector3.new(-28, 0, 38), 5)

	-- flat stepping stones off the plaza
	local rng = Random.new(31)
	for i = 1, 10 do
		local pos = around(i * 36 + 18 + rng:NextNumber(-6, 6), B.PlazaRadius + rng:NextNumber(2.5, 6), 0.08)
		cylinder(m, "SteppingStone", 0.16, rng:NextNumber(2, 3.4), CFrame.new(pos), rgb(138, 134, 124), Mat.Slate, {CastShadow = false})
	end
	return m
end

local function border(lobby)
	local m = model(lobby, "Border")
	local rng = Random.new(17)
	-- a dark thicket around the glade, so that nobody walks off it
	local segments = 40
	local width = 2 * math.pi * 92 / segments + 2
	for i = 1, segments do
		local deg = i * 360 / segments
		local h = rng:NextNumber(12.5, 15.5)
		part(m, "Thicket", Vector3.new(width, h, 6), CFrame.lookAt(around(deg, 92, h / 2), Vector3.new(0, h / 2, 0)), rgb(30, 62, 54), Mat.Grass)
		ball(m, "ThicketTop", Vector3.new(width * 1.1, 7, 9), CFrame.lookAt(around(deg, 92, h), Vector3.new(0, h, 0)), rgb(36, 74, 62), Mat.Grass, DECO)
		ball(m, "ThicketBush", Vector3.new(width * 0.7, 6, 6), CFrame.lookAt(around(deg + 4, 88.5, 2), Vector3.new(0, 2, 0)), rgb(42, 84, 64), Mat.Grass, DECO)
	end
	for i = 1, 24 do
		part(m, "Wall", Vector3.new(2 * math.pi * 96 / 24 + 2, 60, 2), CFrame.lookAt(around(i * 15, 96, 30), Vector3.new(0, 30, 0)), STONE, Mat.SmoothPlastic,
			{Transparency = 1, CastShadow = false})
	end
	-- tall trees behind the thicket, for depth
	for i = 1, 36 do
		local pos = around(i * 10 + rng:NextNumber(-3, 3), rng:NextNumber(100, 130), -0.3)
		P.Tree(m, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(38, 62), {Seed = i})
	end
	for i = 1, 6 do
		local pos = around(i * 60 + rng:NextNumber(-15, 15), rng:NextNumber(99, 110), -0.3)
		P.Rock(m, CFrame.new(pos), rng:NextNumber(7, 12), {Seed = 40 + i, Color = rgb(84, 88, 96)})
	end
	return m
end

local function elderCap(lobby)
	local m = model(lobby, "ElderCap")
	cylinder(m, "Stem", 26, 9, CFrame.new(0, 13.4, 0), STEM, Mat.SmoothPlastic)
	cylinder(m, "StemBase", 3, 11.5, CFrame.new(0, 1.9, 0), rgb(222, 210, 184), Mat.SmoothPlastic)
	for i = 1, 6 do
		local pos = around(i * 60 + 10, 5.6, 1.6)
		ball(m, "RootFlare", Vector3.new(5, 5 + (i % 2) * 1.5, 7), CFrame.lookAt(pos, Vector3.new(0, 1.6, 0)), rgb(222, 210, 184), Mat.SmoothPlastic, DECO)
	end
	cylinder(m, "Skirt", 1.2, 12.5, CFrame.new(0, 19.4, 0), CREAM, Mat.SmoothPlastic, DECO)
	ball(m, "Cap", Vector3.new(46, 18, 46), CFrame.new(0, 29, 0), RED, Mat.SmoothPlastic)
	for i = 1, 7 do
		local pos = around(i * 360 / 7 + 12, 13 + (i % 2) * 4, 36.3 - (i % 2) * 1.3)
		ball(m, "Spot", Vector3.new(5, 1.6, 5), CFrame.new(pos), CREAM, Mat.SmoothPlastic, DECO)
	end
	for i = 1, 4 do
		ball(m, "Spot", Vector3.new(3.4, 1.2, 3.4), CFrame.new(around(i * 90 + 40, 5.5, 37.6)), CREAM, Mat.SmoothPlastic, DECO)
	end
	-- glowing gills under the cap
	local glow = with(DECO, {Transparency = 0.15})
	ring(m, "GillRing", Vector3.new(0, 22.2, 0), 16.2, 28, 0.5, 1.4, AMBER, Mat.Neon, glow)
	for i = 1, 16 do
		part(m, "Gill", Vector3.new(0.3, 1.3, 8), CFrame.new(0, 20.7, 0) * CFrame.Angles(0, math.rad(i * 22.5), 0) * CFrame.new(0, 0, -8.6), AMBER, Mat.Neon, glow)
	end
	local heart = part(m, "GillLight", Vector3.new(34, 1, 34), CFrame.new(0, 19.5, 0), AMBER, Mat.SmoothPlastic, GHOST)
	light(heart, AMBER, 46, 1.1)
	emitter(heart, {
		Name = "Spores", Texture = SPARK, Rate = 9, Lifetime = NumberRange.new(9, 13), Speed = NumberRange.new(0.8, 1.6),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(0, -0.05, 0),
		Size = NumberSequence.new(0.35), Transparency = fade(0.25), Color = ColorSequence.new(AMBER), LightEmission = 1,
		RotSpeed = NumberRange.new(-30, 30),
	})
	-- shelf mushrooms up the stem
	local shelves = {{40, 6, 5}, {75, 9, 4}, {150, 12, 5.5}, {200, 7.5, 4.2}, {285, 10.5, 5}, {320, 15, 3.6}}
	for _, s in ipairs(shelves) do
		ball(m, "Shelf", Vector3.new(s[3], 0.9, s[3]), CFrame.new(around(s[1], 4.9, s[2])), rgb(226, 170, 70), Mat.SmoothPlastic, DECO)
	end
	return m
end

local function expeditionCircle(lobby)
	local c = B.Circle.Center
	local m = model(lobby, "ExpeditionCircle")
	m:SetAttribute("Radius", B.Circle.Radius)
	cylinder(m, "Zone", 0.2, B.Circle.Radius * 2, CFrame.new(c), TEAL, Mat.SmoothPlastic, GHOST)
	cylinder(m, "Stone", 0.3, 23, CFrame.new(c + Vector3.new(0, 0.2, 0)), rgb(124, 124, 132), Mat.Slate, {CastShadow = false})
	cylinder(m, "StoneInner", 0.06, 15, CFrame.new(c + Vector3.new(0, 0.36, 0)), rgb(104, 104, 114), Mat.Slate, DECO)

	-- the client recolours the direct children of Runes during the countdown
	local runes = Instance.new("Folder")
	runes.Name = "Runes"
	runes.Parent = m
	ring(runes, "RuneRing", c + Vector3.new(0, 0.39, 0), 9.6, 28, 0.08, 0.4, TEAL, Mat.Neon, DECO)
	ring(runes, "RuneRingInner", c + Vector3.new(0, 0.41, 0), 4.2, 14, 0.08, 0.3, TEAL, Mat.Neon, DECO)
	for i = 1, 6 do
		part(runes, "RuneMark", Vector3.new(0.3, 0.08, 2.4), CFrame.new(c + Vector3.new(0, 0.39, 0)) * CFrame.Angles(0, math.rad(i * 60), 0) * CFrame.new(0, 0, -6.9),
			TEAL, Mat.Neon, DECO)
	end
	local glow = part(m, "RuneLight", Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, 3, 0)), TEAL, Mat.SmoothPlastic, GHOST)
	light(glow, TEAL, 24, 0.7)
	emitter(glow, {
		Name = "Motes", Texture = SPARK, Rate = 4, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(0.6, 1.2),
		SpreadAngle = Vector2.new(60, 60), Size = NumberSequence.new(0.3), Transparency = fade(0.3), Color = ColorSequence.new(TEAL), LightEmission = 1,
	})
	for i = 1, 3 do
		local pos = c + around(i * 120 + 60, 7.6, 0.35)
		local stone = P.RuneStone(m, facing(pos, c + Vector3.new(0, 0.35, 0)), {Lit = true, Color = TEAL, Height = 2.2, Width = 1.5, Tilt = i * 3 - 6})
		for _, child in ipairs(stone:GetChildren()) do
			if child.Name == "Glyph" then child.Parent = runes end
		end
	end

	-- the fairy ring
	local rng = Random.new(5)
	local caps = {RED, rgb(226, 170, 70), rgb(120, 170, 220)}
	for i = 1, 14 do
		local pos = c + around(i * 360 / 14 + rng:NextNumber(-3, 3), B.Circle.Radius + rng:NextNumber(-0.3, 0.6), 0)
		local color = caps[i % 3 + 1]
		P.Mushroom(m, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(2.4, 5.6), color,
			{Spots = i % 3 == 0, Glow = i % 3 == 2 and i % 2 == 0, Name = "RingMushroom"})
	end
	label(m, "label_circle", c + Vector3.new(0, 9, 0), "Expedition Circle", {HintKey = "label_circle_hint", Hint = "Step in to gather your party"})
	return m
end

local function expeditionGate(lobby)
	local m = model(lobby, "ExpeditionGate")
	local cf = facing(Vector3.new(0, 0, -76), Vector3.new(0, 0, 0))
	local PORTAL = rgb(150, 90, 230)
	for _, x in ipairs({-7, 7}) do
		part(m, "Base", Vector3.new(6.4, 1.2, 7.4), cf * CFrame.new(x, 0.6, 0), DARKSTONE, Mat.Slate)
		part(m, "Base", Vector3.new(5.2, 1.2, 6.2), cf * CFrame.new(x, 1.8, 0), STONE, Mat.Slate)
		for i = 1, 4 do
			part(m, "PillarBlock", Vector3.new(4 + (i % 2) * 0.3, 3.4, 5 - (i % 2) * 0.3), cf * CFrame.new(x, 0.7 + i * 3.4, 0) * CFrame.Angles(0, math.rad((i % 2) * 3 - 1.5), 0),
				i % 2 == 0 and STONE or rgb(122, 120, 122), Mat.Slate)
		end
		for _, y in ipairs({6, 11}) do
			part(m, "RuneBand", Vector3.new(4.5, 0.35, 5.4), cf * CFrame.new(x, y, 0), TEAL, Mat.Neon, DECO)
		end
	end
	part(m, "Lintel", Vector3.new(19, 2.4, 5.4), cf * CFrame.new(0, 17.2, 0), STONE, Mat.Slate)
	part(m, "Keystone", Vector3.new(11, 1.8, 5), cf * CFrame.new(0, 19.1, 0), rgb(122, 120, 122), Mat.Slate)
	part(m, "KeystoneRune", Vector3.new(2, 2, 0.2), cf * CFrame.new(0, 17.4, -2.75) * CFrame.Angles(0, 0, math.rad(45)), TEAL, Mat.Neon, DECO)
	for _, x in ipairs({-7.5, -2, 4.5}) do
		ball(m, "Moss", Vector3.new(5.5, 1.4, 5), cf * CFrame.new(x, x == -2 and 20.1 or 18.5, 0), MOSS, Mat.Grass, DECO)
	end
	for i = 1, 5 do
		ball(m, "Shelf", Vector3.new(2.6 - i * 0.2, 0.6, 2.6 - i * 0.2), cf * CFrame.new(9.3, 2.5 + i * 2.6, -1.5 + (i % 2) * 2), rgb(226, 170, 70), Mat.SmoothPlastic, DECO)
	end
	-- the portal in the opening
	local centre = cf * CFrame.new(0, 8.3, 0)
	local disc = ball(m, "Portal", Vector3.new(10, 15.4, 0.5), centre, PORTAL, Mat.Neon, with(DECO, {Transparency = 0.35}))
	vring(m, "PortalRing", centre * CFrame.new(0, 0, -0.5), 4.6, 7.2, 18, 0.3, rgb(196, 150, 255), Mat.Neon, DECO)
	vring(m, "PortalRing", centre * CFrame.new(0, 0, -0.7), 3, 4.8, 14, 0.2, rgb(230, 200, 255), Mat.Neon, with(DECO, {Transparency = 0.2}))
	vring(m, "PortalRing", centre * CFrame.new(0, 0, -0.9), 1.4, 2.2, 10, 0.14, TEAL, Mat.Neon, with(DECO, {Transparency = 0.3}))
	light(disc, PORTAL, 30, 1.4)
	emitter(disc, {
		Name = "Swirl", Texture = SPARK, Rate = 14, Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(50, 50), Size = NumberSequence.new(0.45),
		Transparency = fade(0.2), Color = ColorSequence.new(rgb(196, 150, 255)), LightEmission = 1, RotSpeed = NumberRange.new(-120, 120),
	})
	part(m, "Blocker", Vector3.new(10, 16, 3), cf * CFrame.new(0, 8, 0), STONE, Mat.SmoothPlastic, {Transparency = 1, CastShadow = false})
	for i = 1, 2 do
		part(m, "Step", Vector3.new(11 + i * 2, 0.4, 2), cf * CFrame.new(0, 0.6 - i * 0.2, -2.6 - i * 1.6), STONE, Mat.Slate, {CastShadow = false})
	end
	label(m, "label_gate", (cf * CFrame.new(0, 21.5, -2)).Position, "Road to Mushroomhaven", {Offset = 2})
	return m
end

-- Spore Lanterns along the road to the gate, with bunting between the posts on both sides
local function gateRoad(lobby)
	local m = model(lobby, "GateRoad")
	for _, x in ipairs({-16.5, 16.5}) do
		local zs = {-33, -52, -71}
		for i, z in ipairs(zs) do
			local pos = Vector3.new(x * (i == 1 and 0.55 or 1), 0, z)
			zs[i] = pos
			P.SporeLantern(m, facing(pos, Vector3.new(0, 0, z)))
		end
		for i = 1, 2 do
			bunting(m, zs[i] + Vector3.new(0, 8, 0), zs[i + 1] + Vector3.new(0, 8, 0), 7)
		end
	end
	return m
end

local function shrine(lobby)
	local m = model(lobby, "Shrine")
	local cf = facing(Vector3.new(64, 0, 0), Vector3.new(0, 0, 0))
	local S, SM = rgb(140, 140, 146), Mat.Slate

	local statue = model(m, "GuardianStatue")
	part(statue, "PlinthStep", Vector3.new(11, 1, 11), cf * CFrame.new(0, 0.5, 0), DARKSTONE, SM)
	part(statue, "Plinth", Vector3.new(8, 2, 8), cf * CFrame.new(0, 2, 0), STONE, SM)
	part(statue, "PlinthBand", Vector3.new(8.4, 0.4, 8.4), cf * CFrame.new(0, 2.6, 0), rgb(190, 52, 44), Mat.Neon, with(DECO, {Transparency = 0.2}))
	cylinder(statue, "Cloak", 6, 5.6, cf * CFrame.new(0, 6, 0), S, SM)
	cylinder(statue, "CloakHem", 1, 6.6, cf * CFrame.new(0, 3.5, 0), S, SM, DECO)
	ball(statue, "Shoulders", Vector3.new(6.6, 4.6, 6), cf * CFrame.new(0, 9.4, 0), S, SM, DECO)
	ball(statue, "Head", Vector3.new(3.6, 3.4, 3.6), cf * CFrame.new(0, 11.9, -0.3), rgb(150, 150, 156), SM, DECO)
	ball(statue, "CapHelmet", Vector3.new(9.4, 4.4, 9.4), cf * CFrame.new(0, 14.2, 0), S, SM, DECO)
	for i = 1, 5 do
		local a = math.rad(i * 72)
		ball(statue, "CapSpot", Vector3.new(1.6, 0.6, 1.6), cf * CFrame.new(math.sin(a) * 2.6, 16.1, math.cos(a) * 2.6), rgb(168, 168, 174), SM, DECO)
	end
	for _, x in ipairs({-0.7, 0.7}) do
		ball(statue, "Eye", Vector3.new(0.5, 0.6, 0.3), cf * CFrame.new(x, 12, -2.05), AMBER, Mat.Neon, DECO)
	end
	for _, x in ipairs({-1, 1}) do
		part(statue, "Arm", Vector3.new(1.2, 1.2, 3.6), cf * CFrame.new(x * 1.9, 8.6, -2.2) * CFrame.Angles(math.rad(-20), math.rad(x * 28), 0), S, SM, DECO)
	end
	ball(statue, "Hands", Vector3.new(2, 1.5, 1.6), cf * CFrame.new(0, 9.2, -3.5), rgb(150, 150, 156), SM, DECO)
	P.Sickle(statue, cf * CFrame.new(0, 3, -3.6), 2.4, 10.5, rgb(120, 120, 128), SM)
	for i, o in ipairs({{-3.4, 3.2, 3}, {3.2, 3.1, -3.3}, {-4.6, 1.1, -4.4}, {2, 3.1, 3.4}}) do
		ball(statue, "Moss", Vector3.new(2.6 + i * 0.3, 0.7, 2.4), cf * CFrame.new(o[1], o[2], o[3]), MOSS, Mat.Grass, DECO)
	end
	for i, o in ipairs({{-3, -3.3, 1.1}, {-2.2, -3.6, 0.7}, {2.6, -3.4, 1.3}, {3.3, -3, 0.8}, {0, -4.8, 0.6}}) do
		local y = o[1] == 0 and 1 or 3
		cylinder(statue, "Candle", o[3], 0.4, cf * CFrame.new(o[1], y + o[3] / 2, o[2]), CREAM, Mat.SmoothPlastic, DECO)
		local flame = ball(statue, "Flame", Vector3.new(0.3, 0.5, 0.3), cf * CFrame.new(o[1], y + o[3] + 0.3, o[2]), rgb(255, 190, 90), Mat.Neon, DECO)
		if i == 1 or i == 3 then light(flame, rgb(255, 190, 90), 14, 0.9) end
	end
	P.Basket(m, cf * CFrame.new(-3.6, 1, -4.4))
	P.Basket(m, cf * CFrame.new(3.8, 0, -6.6) * CFrame.Angles(0, 1, 0), {RED, RED, CREAM})

	-- seven standing stones, one for each land; only Mushroomhaven is known so far
	for i = 1, 7 do
		local a = math.rad(-66 + (i - 1) * 22)
		local at = cf * CFrame.new(math.sin(a) * 15, 0, math.cos(a) * 15)
		local lit = i == 1
		local stone = P.RuneStone(m, facing(at.Position, cf.Position), {Lit = lit, Color = RED, Height = 5, Width = 3, Tilt = ((i * 37) % 9) - 4})
		stone.Name = "RegionStone_" .. i
		stone:SetAttribute("Region", i)
		ball(stone, "Moss", Vector3.new(2.4, 0.6, 1.6), at * CFrame.new(0.3, 0.2, 0), MOSS, Mat.Grass, DECO)
		if lit then
			label(stone, "region_mushroomhaven", at.Position + Vector3.new(0, 6.2, 0), "Mushroomhaven", {MaxDistance = 45, Size = UDim2.fromOffset(180, 30), Offset = 1})
		else
			-- shown from close by only: six identical labels side by side overlap from the plaza
			label(stone, "region_unknown", at.Position + Vector3.new(0, 6.2, 0), "Undiscovered land",
				{Name = "Label_region_unknown_" .. i, MaxDistance = 16, Size = UDim2.fromOffset(180, 30), Offset = 1})
		end
	end
	label(m, "label_shrine", (cf * CFrame.new(0, 18.5, 0)).Position, "Shrine of the Seven Lands")
	P.SporeLantern(m, facing(Vector3.new(47, 0, 7), Vector3.new(47, 0, 0)))
	return m
end

local function camp(lobby)
	local m = model(lobby, "Camp")
	local cf = facing(Vector3.new(-62, 0, 4), Vector3.new(0, 0, 4))

	local fire = model(m, "Campfire")
	for i = 1, 9 do
		local a = math.rad(i * 40)
		part(fire, "FireStone", Vector3.new(1.3, 0.8 + (i % 2) * 0.2, 1), cf * CFrame.new(math.sin(a) * 2.3, 0.4, math.cos(a) * 2.3) * CFrame.Angles(0, a, 0), DARKSTONE, Mat.Slate, DECO)
	end
	for i = 1, 3 do
		hcyl(fire, "Log", 3, 0.6, cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(i * 60), math.rad(18)), rgb(60, 44, 36), Mat.Wood, DECO)
	end
	local embers = ball(fire, "Embers", Vector3.new(1.8, 1, 1.8), cf * CFrame.new(0, 0.6, 0), rgb(255, 150, 60), Mat.Neon, DECO)
	light(embers, rgb(255, 170, 90), 26, 1.5)
	emitter(embers, {
		Name = "Sparks", Texture = SPARK, Rate = 10, Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(18, 18), Acceleration = Vector3.new(0, 1, 0), Size = NumberSequence.new(0.25),
		Transparency = fade(0.1), Color = ColorSequence.new(rgb(255, 170, 80)), LightEmission = 1,
	})
	emitter(embers, {
		Name = "Smoke", Texture = SMOKE, Rate = 3, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(1.5, 2.5),
		SpreadAngle = Vector2.new(10, 10), Size = NumberSequence.new(1, 3), Transparency = fade(0.8), Color = ColorSequence.new(rgb(120, 116, 124)),
	})

	for _, deg in ipairs({90, 215, 325}) do
		local a = math.rad(deg)
		local pos = (cf * CFrame.new(math.sin(a) * 7, 0, math.cos(a) * 7)).Position
		P.LogBench(m, facing(pos, cf.Position))
	end

	-- a canvas lean-to behind the fire
	local tent = model(m, "LeanTo")
	local back = cf * CFrame.new(0, 0, 14)
	for _, x in ipairs({-4.5, 4.5}) do
		cylinder(tent, "Pole", 6.2, 0.4, back * CFrame.new(x, 3.1, -3.5), DARKWOOD, Mat.Wood)
	end
	hcyl(tent, "Ridge", 9.6, 0.35, back * CFrame.new(0, 6.1, -3.5), DARKWOOD, Mat.Wood, DECO)
	part(tent, "Canvas", Vector3.new(9.4, 0.2, 9.1), back * CFrame.new(0, 3.2, 0) * CFrame.Angles(math.atan2(5.8, 7), 0, 0), rgb(196, 176, 140), Mat.Fabric)
	part(tent, "CanvasPatch", Vector3.new(2, 0.06, 1.6), back * CFrame.new(1.5, 3.36, 0) * CFrame.Angles(math.atan2(5.8, 7), 0, 0), RED, Mat.Fabric, DECO)
	part(tent, "Bedroll", Vector3.new(2.6, 0.4, 5.4), back * CFrame.new(-1.8, 0.2, -0.6), rgb(96, 120, 150), Mat.Fabric, DECO)
	hcyl(tent, "Pillow", 2.2, 0.9, back * CFrame.new(-1.8, 0.5, 1.6), CREAM, Mat.Fabric, DECO)
	P.Crate(tent, back * CFrame.new(2.4, 0, 0.6) * CFrame.Angles(0, 0.3, 0), 1.8)

	-- a cart with the harvest
	local cart = model(m, "Cart")
	local c = cf * CFrame.new(-14, 0, 5) * CFrame.Angles(0, math.rad(25), 0)
	part(cart, "Bed", Vector3.new(4.4, 0.4, 7.4), c * CFrame.new(0, 2.2, 0), rgb(150, 112, 72), Mat.WoodPlanks)
	for _, x in ipairs({-2.1, 2.1}) do
		part(cart, "Side", Vector3.new(0.3, 1.4, 7.4), c * CFrame.new(x, 3.1, 0), WOOD, Mat.WoodPlanks, DECO)
		hcyl(cart, "Wheel", 0.5, 3.6, c * CFrame.new(x * 1.2, 1.8, 0.6), DARKWOOD, Mat.Wood, DECO)
		hcyl(cart, "Hub", 0.7, 0.8, c * CFrame.new(x * 1.2, 1.8, 0.6), rgb(60, 58, 60), Mat.Metal, DECO)
		part(cart, "Shaft", Vector3.new(0.3, 0.3, 5), c * CFrame.new(x * 0.8, 1.5, -5.6) * CFrame.Angles(math.rad(-16), 0, 0), WOOD, Mat.Wood, DECO)
	end
	part(cart, "Back", Vector3.new(4.4, 1.4, 0.3), c * CFrame.new(0, 3.1, 3.6), WOOD, Mat.WoodPlanks, DECO)
	P.Crate(cart, c * CFrame.new(-0.7, 2.4, 2) * CFrame.Angles(0, 0.2, 0), 2)
	P.Basket(cart, c * CFrame.new(0.8, 2.4, -0.4), {RED, CREAM})
	P.Basket(cart, c * CFrame.new(-0.8, 2.4, -2.4), {rgb(226, 170, 70), rgb(120, 170, 220)})
	P.Crate(m, c * CFrame.new(4.6, 0, 1) * CFrame.Angles(0, 0.5, 0), 2.2)
	P.Basket(m, c * CFrame.new(4.4, 0, -2))

	-- a rack with three sickles
	local rack = model(m, "SickleRack")
	local r = cf * CFrame.new(12, 0, 8) * CFrame.Angles(0, math.rad(-35), 0)
	for _, x in ipairs({-2.6, 2.6}) do
		cylinder(rack, "Post", 4.6, 0.4, r * CFrame.new(x, 2.3, 0), DARKWOOD, Mat.Wood)
	end
	hcyl(rack, "Bar", 5.8, 0.3, r * CFrame.new(0, 4.3, 0), DARKWOOD, Mat.Wood, DECO)
	hcyl(rack, "Bar", 5.8, 0.3, r * CFrame.new(0, 1.4, 0), DARKWOOD, Mat.Wood, DECO)
	for i = -1, 1 do
		P.Sickle(rack, r * CFrame.new(i * 1.7 - 0.4, 1.1, -0.3) * CFrame.Angles(math.rad(-6), 0, 0), 1.2, 2.6)
	end

	P.Barrel(m, cf * CFrame.new(8, 0, 13))

	-- the starter kit on a dusty table: basket, simple sickle, spores, research book
	local t = cf * CFrame.new(-9, 0, -8) * CFrame.Angles(0, math.rad(-30), 0)
	local tbl = model(m, "KitTable")
	part(tbl, "Top", Vector3.new(5.4, 0.3, 3), t * CFrame.new(0, 2.85, 0), rgb(140, 108, 74), Mat.WoodPlanks)
	for _, x in ipairs({-2.3, 2.3}) do
		for _, z in ipairs({-1.1, 1.1}) do
			part(tbl, "Leg", Vector3.new(0.4, 2.7, 0.4), t * CFrame.new(x, 1.35, z), DARKWOOD, Mat.Wood, DECO)
		end
	end
	local book = t * CFrame.new(-1.2, 3, 0.1) * CFrame.Angles(0, math.rad(15), 0)
	part(tbl, "BookCover", Vector3.new(1.7, 0.12, 1.2), book * CFrame.new(0, 0.06, 0), rgb(110, 48, 60), Mat.Fabric, DECO)
	for _, x in ipairs({-0.42, 0.42}) do
		part(tbl, "BookPage", Vector3.new(0.78, 0.1, 1.05), book * CFrame.new(x, 0.17, 0) * CFrame.Angles(0, 0, math.rad(x > 0 and -5 or 5)), rgb(236, 226, 200), Mat.SmoothPlastic, DECO)
	end
	part(tbl, "BookRibbon", Vector3.new(0.1, 0.02, 1.3), book * CFrame.new(0.2, 0.24, 0.1), RED, Mat.Fabric, DECO)
	P.Basket(tbl, t * CFrame.new(1.4, 3, -0.4))
	ball(tbl, "SporePouch", Vector3.new(0.8, 0.7, 0.8), t * CFrame.new(0.3, 3.35, 0.8), rgb(120, 150, 110), Mat.Fabric, DECO)
	ball(tbl, "Spores", Vector3.new(0.3, 0.2, 0.3), t * CFrame.new(0.3, 3.72, 0.8), TEAL, Mat.Neon, DECO)
	P.Sickle(tbl, t * CFrame.new(2.3, 3.08, 1) * CFrame.Angles(math.rad(90), 0, math.rad(60)), 0.8)

	label(m, "label_camp", (cf * CFrame.new(0, 9, 0)).Position, "Guardians' Camp")
	P.SporeLantern(m, facing(Vector3.new(-45, 0, -5), Vector3.new(-45, 0, 0)))
	return m
end

local function pond(lobby)
	local m = model(lobby, "Pond")
	local c = around(135, 60, 0)
	local discs = {{Vector3.new(0, 0, 0), 11.5}, {Vector3.new(9, 0, 4), 7}, {Vector3.new(-6.5, 0, 7.5), 5.6}}
	local water = with(DECO, {Transparency = 0.25, Reflectance = 0.15})
	for i, d in ipairs(discs) do
		cylinder(m, "Water", 0.3, d[2] * 2, CFrame.new(c + d[1] + Vector3.new(0, 0.2 + i * 0.004, 0)), rgb(30, 86, 96), Mat.Glass, water)
		cylinder(m, "PondBed", 0.05, d[2] * 2, CFrame.new(c + d[1] + Vector3.new(0, 0.03, 0)), rgb(34, 52, 58), Mat.Slate, DECO)
	end
	local function inside(p)
		for _, d in ipairs(discs) do
			if (p - d[1]).Magnitude < d[2] then return true end
		end
		return false
	end
	local function edge(deg)
		local dir = around(deg, 1, 0)
		local last = 0
		for r = 0, 20, 0.5 do
			if inside(dir * r) then last = r end
		end
		return dir * last, dir
	end
	local rng = Random.new(23)
	local toCentre = (Vector3.new(0, 0, 0) - c).Unit
	-- a raised bank of stones round the water
	for i = 1, 44 do
		local deg = i * 360 / 44
		local e, dir = edge(deg)
		local jetty = dir:Dot(toCentre) > 0.97
		if not jetty then
			part(m, "Bank", Vector3.new(rng:NextNumber(2.2, 3), rng:NextNumber(0.7, 1), rng:NextNumber(1.6, 2.2)),
				CFrame.lookAt(c + e + dir * 0.6 + Vector3.new(0, 0.35, 0), c + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0),
				i % 3 == 0 and MOSS or rgb(112, 114, 112), i % 3 == 0 and Mat.Grass or Mat.Slate, {CastShadow = false})
		end
		if i % 3 == 1 and not jetty then
			local base = c + e + dir * rng:NextNumber(-1.2, -0.3)
			for k = 1, 2 do
				local h = rng:NextNumber(2.4, 4.2)
				local at = CFrame.new(base + Vector3.new(k * 0.4 - 0.6, 0, k * 0.3)) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6)))
				cylinder(m, "Reed", h, 0.14, at * CFrame.new(0, h / 2, 0), rgb(92, 132, 78), Mat.Grass, DECO)
				cylinder(m, "ReedHead", 0.7, 0.3, at * CFrame.new(0, h, 0), rgb(84, 60, 44), Mat.Fabric, DECO)
			end
		end
	end
	-- a short jetty from the side of the plaza
	local j = facing(c + toCentre * 14, c)
	for i = 0, 6 do
		part(m, "JettyPlank", Vector3.new(4, 0.25, 1.4), j * CFrame.new(0, 0.95, -i * 1.5) * CFrame.Angles(0, math.rad((i % 2) * 3 - 1.5), 0), rgb(140, 108, 74), Mat.WoodPlanks)
	end
	part(m, "JettyRamp", Vector3.new(4, 0.25, 3), j * CFrame.new(0, 0.48, 1.9) * CFrame.Angles(math.rad(-19), 0, 0), rgb(140, 108, 74), Mat.WoodPlanks)
	for _, x in ipairs({-2, 2}) do
		for _, z in ipairs({-0.5, -8.6}) do
			cylinder(m, "JettyPost", 2.4, 0.45, j * CFrame.new(x, 1, z), DARKWOOD, Mat.Wood, DECO)
		end
	end
	local jl = ball(m, "JettyLamp", Vector3.new(0.7, 0.8, 0.7), j * CFrame.new(2, 2.5, -8.6), AMBER, Mat.Neon, DECO)
	light(jl, AMBER, 14, 0.9)
	for i, o in ipairs({{-4, -3}, {-1, -6.5}, {3.5, -5}, {7, -1}, {10.5, 2.5}}) do
		cylinder(m, "PondStone", 0.5, 2 + (i % 2) * 0.5, CFrame.new(c + Vector3.new(o[1], 0.3, o[2])), rgb(126, 128, 124), Mat.Slate, {CastShadow = false})
	end
	-- glowing lily caps
	for i, o in ipairs({{3, 3, 1.8}, {-3.5, 4, 1.4}, {6, 6.5, 1.2}, {-7, 8.5, 1.6}, {1, -4, 1.3}, {11, 5, 1.5}, {-6, -2.5, 1.1}}) do
		local lily = ball(m, "LilyCap", Vector3.new(o[3], 0.35, o[3]), CFrame.new(c + Vector3.new(o[1], 0.42, o[2])), i % 2 == 0 and TEAL or rgb(170, 220, 255), Mat.Neon, DECO)
		if i <= 2 then light(lily, TEAL, 16, 0.8) end
	end
	for i = 1, 2 do
		local box = part(m, "Fireflies", Vector3.new(18, 4, 16), CFrame.new(c + Vector3.new(i * 8 - 12, 3.5, i * 4 - 4)), AMBER, Mat.SmoothPlastic, GHOST)
		emitter(box, {
			Name = "Fireflies", Texture = SPARK, Rate = 5, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.22), Transparency = fade(0),
			Color = ColorSequence.new(rgb(214, 255, 130)), LightEmission = 1, Drag = 0.5, Acceleration = Vector3.new(0, 0.05, 0),
		})
	end
	label(m, "label_pond", c + Vector3.new(0, 7, 0), "Firefly Pond")
	P.SporeLantern(m, facing(c + toCentre * 15 + Vector3.new(5, 0, -3), c))
	return m
end

-- The eight species of the game, grown as small clusters in the beds
local SPECIES = {
	{"fly_agaric", "Red Fly Agaric", RED},
	{"thunder_hedgehog", "Thunder Hedgehog", rgb(240, 206, 70)},
	{"moon_milkcap", "Moon Milkcap", rgb(176, 214, 255)},
	{"sun_honey", "Sun Honey Fungus", rgb(236, 176, 60)},
	{"ice_crystalcap", "Ice Crystalcap", rgb(160, 220, 245)},
	{"void_galactic", "Void Galactic", rgb(62, 36, 96)},
	{"blood_mooncap", "Blood Mooncap", rgb(140, 20, 36)},
	{"toxic_toadstool", "Toxic Toadstool", rgb(132, 190, 62)},
}

local function speciesCluster(parent, cf, id, color)
	local spots = {{-1.1, 0.2, 1.7}, {0.3, -0.3, 2.3}, {1.3, 0.4, 1.4}}
	for i, s in ipairs(spots) do
		local h = s[3]
		local at = cf * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, i * 1.3, 0)
		local opts = {Name = "Mushroom_" .. id}
		if id == "fly_agaric" then
			opts.Spots = true
		elseif id == "moon_milkcap" then
			opts.Glow = i == 2
			opts.Wide = 1
		elseif id == "sun_honey" then
			opts.Wide = 0.8
		elseif id == "toxic_toadstool" then
			opts.Spots = rgb(210, 240, 130)
			opts.StemColor = rgb(200, 214, 170)
		elseif id == "blood_mooncap" then
			opts.Wide = 1.4
			opts.StemColor = rgb(214, 190, 186)
		elseif id == "void_galactic" then
			opts.StemColor = rgb(120, 104, 150)
		end
		local m = P.Mushroom(parent, at, h, color, opts)
		if id == "moon_milkcap" then
			m.Cap.Material = Mat.Neon
		elseif id == "thunder_hedgehog" then
			for k = 1, 6 do
				local spike = at * CFrame.new(0, h, 0) * CFrame.Angles(0, math.rad(k * 60), 0) * CFrame.Angles(math.rad(k % 2 == 0 and 35 or 60), 0, 0)
				part(m, "Spike", Vector3.new(0.12, h * 0.45, 0.12), spike * CFrame.new(0, h * 0.35, 0), color, Mat.SmoothPlastic, DECO)
				part(m, "SpikeTip", Vector3.new(0.14, 0.14, 0.14), spike * CFrame.new(0, h * 0.6, 0), rgb(255, 250, 170), Mat.Neon, with(DECO, {Transparency = 0.2}))
			end
		elseif id == "ice_crystalcap" then
			for k = 1, 3 do
				part(m, "Crystal", Vector3.new(0.3, h * 0.6, 0.3), at * CFrame.new(0, h * 1.15, 0) * CFrame.Angles(0, math.rad(k * 120), math.rad(28)) * CFrame.new(0, h * 0.2, 0),
					rgb(200, 240, 255), Mat.Glass, with(DECO, {Transparency = 0.3}))
			end
		elseif id == "void_galactic" then
			for k = 1, 4 do
				local a = math.rad(k * 90 + i * 30)
				ball(m, "Speck", Vector3.new(0.16, 0.16, 0.16), at * CFrame.new(math.sin(a) * h * 0.35, h * 1.2, math.cos(a) * h * 0.35),
					k % 2 == 0 and rgb(200, 160, 255) or rgb(140, 220, 255), Mat.Neon, DECO)
			end
		elseif id == "sun_honey" then
			P.Mushroom(m, at * CFrame.new(0.5, 0, 0.5), h * 0.6, color, {Wide = 0.8, Name = "Mushroom_" .. id})
		end
	end
end

local function garden(lobby)
	local m = model(lobby, "Garden")
	local cf = facing(around(222, 58, 0), Vector3.new(0, 0, 0))
	for i, s in ipairs(SPECIES) do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local at = cf * CFrame.new((col - 1.5) * 7.4, 0, row * 8 - 4)
		local bed = model(m, "Bed_" .. s[1])
		bed:SetAttribute("Species", s[1])
		part(bed, "Soil", Vector3.new(5.4, 0.7, 3.6), at * CFrame.new(0, 0.35, 0), rgb(70, 52, 42), Mat.Ground, {CastShadow = false})
		for _, z in ipairs({-1.95, 1.95}) do
			part(bed, "Frame", Vector3.new(6, 0.9, 0.3), at * CFrame.new(0, 0.45, z), WOOD, Mat.WoodPlanks, DECO)
		end
		for _, x in ipairs({-2.85, 2.85}) do
			part(bed, "Frame", Vector3.new(0.3, 0.9, 3.6), at * CFrame.new(x, 0.45, 0), WOOD, Mat.WoodPlanks, DECO)
		end
		speciesCluster(bed, at * CFrame.new(0, 0.7, 0), s[1], s[3])
		part(bed, "Stake", Vector3.new(0.15, 1.6, 0.15), at * CFrame.new(-2.4, 1.3, -1.4), DARKWOOD, Mat.Wood, DECO)
		part(bed, "Plaque", Vector3.new(1.1, 0.6, 0.1), at * CFrame.new(-2.4, 2, -1.48), rgb(196, 164, 118), Mat.WoodPlanks, DECO)
		label(bed, "species_" .. s[1], (at * CFrame.new(0, 3.6, 0)).Position, s[2], {MaxDistance = 28, Size = UDim2.fromOffset(170, 26), Offset = 0.6})
	end
	-- a low fence behind and beside the beds, open towards the plaza
	for i = -2, 2 do
		P.Fence(m, cf * CFrame.new(i * 6.6, 0, 9.5), 6.6)
	end
	for _, x in ipairs({-16.5, 16.5}) do
		for k = 0, 1 do
			P.Fence(m, cf * CFrame.new(x, 0, 6.2 - k * 6.6) * CFrame.Angles(0, math.rad(90), 0), 6.6)
		end
	end

	local sc = model(m, "Scarecrow")
	local s = cf * CFrame.new(11.5, 0, 0.2)
	cylinder(sc, "Pole", 6.4, 0.35, s * CFrame.new(0, 3.2, 0), DARKWOOD, Mat.Wood)
	hcyl(sc, "Arms", 5.2, 0.3, s * CFrame.new(0, 4.6, 0), DARKWOOD, Mat.Wood, DECO)
	part(sc, "Coat", Vector3.new(2.2, 2.6, 1), s * CFrame.new(0, 3.9, 0), rgb(120, 96, 140), Mat.Fabric, DECO)
	for _, x in ipairs({-1.8, 1.8}) do
		part(sc, "Sleeve", Vector3.new(1.6, 0.8, 0.8), s * CFrame.new(x, 4.55, 0), rgb(120, 96, 140), Mat.Fabric, DECO)
	end
	ball(sc, "Head", Vector3.new(1.7, 1.7, 1.7), s * CFrame.new(0, 6.1, 0), rgb(214, 190, 140), Mat.Fabric, DECO)
	for _, x in ipairs({-0.35, 0.35}) do
		ball(sc, "Eye", Vector3.new(0.25, 0.25, 0.15), s * CFrame.new(x, 6.2, -0.82), rgb(40, 34, 30), Mat.SmoothPlastic, DECO)
	end
	ball(sc, "CapHat", Vector3.new(3.6, 1.6, 3.6), s * CFrame.new(0, 7.2, 0), RED, Mat.SmoothPlastic, DECO)
	for i = 1, 4 do
		local a = math.rad(i * 90 + 30)
		ball(sc, "HatSpot", Vector3.new(0.7, 0.3, 0.7), s * CFrame.new(math.sin(a) * 1, 7.85, math.cos(a) * 1), CREAM, Mat.SmoothPlastic, DECO)
	end

	local can = model(m, "WateringCan")
	local w = cf * CFrame.new(-10.6, 0, 0.4) * CFrame.Angles(0, 0.6, 0)
	cylinder(can, "Body", 1.4, 1.3, w * CFrame.new(0, 0.7, 0), rgb(110, 140, 150), Mat.Metal, DECO)
	cylinder(can, "Spout", 1.6, 0.25, w * CFrame.new(0.9, 1, 0) * CFrame.Angles(0, 0, math.rad(-50)), rgb(110, 140, 150), Mat.Metal, DECO)
	cylinder(can, "Rose", 0.2, 0.55, w * CFrame.new(1.55, 1.52, 0) * CFrame.Angles(0, 0, math.rad(-50)), rgb(90, 116, 126), Mat.Metal, DECO)
	part(can, "Handle", Vector3.new(0.15, 1.1, 0.15), w * CFrame.new(-0.85, 0.9, 0), rgb(90, 116, 126), Mat.Metal, DECO)
	part(can, "Handle", Vector3.new(0.9, 0.15, 0.15), w * CFrame.new(-0.45, 1.45, 0), rgb(90, 116, 126), Mat.Metal, DECO)

	P.Crate(m, cf * CFrame.new(14, 0, 7) * CFrame.Angles(0, 0.4, 0), 1.8)
	P.Basket(m, cf * CFrame.new(-13.6, 0, 6.6))
	label(m, "label_garden", (cf * CFrame.new(0, 8.5, 2)).Position, "Guardian's Beds")
	P.SporeLantern(m, cf * CFrame.new(-17.5, 0, -6.5) * CFrame.Angles(0, math.rad(-90), 0))
	return m
end

local function noticeBoard(lobby)
	local m = model(lobby, "NoticeBoard")
	local cf = facing(around(180, 37, 0), Vector3.new(0, 0, 0))
	for _, x in ipairs({-4, 4}) do
		cylinder(m, "Post", 8, 0.6, cf * CFrame.new(x, 4, 0), DARKWOOD, Mat.Wood)
	end
	for i = 0, 3 do
		part(m, "Plank", Vector3.new(7.6, 1.2, 0.3), cf * CFrame.new(0, 2.7 + i * 1.22, 0.1) * CFrame.Angles(0, 0, math.rad((i % 2) * 1.6 - 0.8)), rgb(134, 100, 68), Mat.WoodPlanks, DECO)
	end
	local board = part(m, "Board", Vector3.new(7, 4.6, 0.2), cf * CFrame.new(0, 4.55, -0.16), rgb(226, 208, 170), Mat.SmoothPlastic, {CastShadow = false})
	for _, x in ipairs({-1, 1}) do
		local slope = cf * CFrame.new(0, 8.6, 0) * CFrame.Angles(0, 0, math.rad(x * -24)) * CFrame.new(x * 2.55, 0, 0)
		part(m, "Roof", Vector3.new(5.4, 0.3, 2.8), slope, rgb(96, 60, 52), Mat.WoodPlanks, DECO)
		for k = 0, 2 do
			part(m, "Shingle", Vector3.new(1.7, 0.16, 3), slope * CFrame.new(-x * (k * 1.7 - 1.7), 0.2, 0) * CFrame.Angles(0, 0, math.rad(x * 5)), k % 2 == 0 and rgb(120, 72, 60) or rgb(104, 64, 56), Mat.WoodPlanks, DECO)
		end
	end
	hcyl(m, "Ridge", 0.3, 0.3, cf * CFrame.new(0, 9.75, 0), DARKWOOD, Mat.Wood, DECO)
	part(m, "RidgeBeam", Vector3.new(0.35, 0.35, 3.1), cf * CFrame.new(0, 9.7, 0), DARKWOOD, Mat.Wood, DECO)
	cylinder(m, "LanternChain", 0.8, 0.1, cf * CFrame.new(4.9, 7.5, -0.6), rgb(50, 46, 44), Mat.Metal, DECO)
	part(m, "LanternArm", Vector3.new(1.4, 0.2, 0.2), cf * CFrame.new(4.6, 7.9, -0.6), DARKWOOD, Mat.Wood, DECO)
	ball(m, "LanternCap", Vector3.new(1.5, 0.8, 1.5), cf * CFrame.new(4.9, 7, -0.6), RED, Mat.SmoothPlastic, DECO)
	local bulb = ball(m, "LanternBulb", Vector3.new(0.9, 1, 0.9), cf * CFrame.new(4.9, 6.5, -0.6), AMBER, Mat.Neon, DECO)
	light(bulb, AMBER, 18, 1.1)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Notice"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.4
	local frame = Instance.new("Frame")
	frame.Name = "Parchment"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(232, 214, 176)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local lines = {
		{"board_title", "How to set out"},
		{"board_step_1", "1. Step into the Expedition Circle"},
		{"board_step_2", "2. Choose Solo, Duo or Squad"},
		{"board_step_3", "3. Invite Guardians and gather in the circle"},
		{"board_step_4", "4. The leader sets out — the party travels together"},
	}
	for i, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.Name = i == 1 and "Title" or ("Step" .. (i - 1))
		t.BackgroundTransparency = 1
		t.Font = i == 1 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = i == 1 and rgb(120, 36, 30) or rgb(52, 38, 28)
		t.TextXAlignment = i == 1 and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		t.Position = i == 1 and UDim2.fromScale(0.05, 0.04) or UDim2.fromScale(0.06, 0.28 + (i - 2) * 0.17)
		t.Size = i == 1 and UDim2.fromScale(0.9, 0.2) or UDim2.fromScale(0.88, 0.13)
		t.Text = l[2]
		t:SetAttribute("LocaleKey", l[1])
		t.Parent = frame
	end
	gui.Parent = board
	return m
end

local function mouldEdge(lobby)
	local m = model(lobby, "GreyMould")
	local c = around(48, 84, 0)
	local GREY = rgb(128, 132, 128)
	local rng = Random.new(77)
	for i, o in ipairs({{0, 0, 11}, {-6, 3, 7}, {4, -6, 8}, {-3, -8, 6}, {7, 4, 6.5}}) do
		local at = c + Vector3.new(o[1], 0.1 + i * 0.01, o[2])
		cylinder(m, "MouldPatch", 0.25, o[3], CFrame.new(at), GREY, Mat.Slate, DECO)
		for k = 1, 4 do
			local s = rng:NextNumber(0.8, 2)
			ball(m, "MouldLump", Vector3.new(s, s * 0.6, s),
				CFrame.new(at + Vector3.new(rng:NextNumber(-0.4, 0.4) * o[3], 0.2, rng:NextNumber(-0.4, 0.4) * o[3])), rgb(186, 190, 184), Mat.Slate, DECO)
		end
	end
	P.Tree(m, CFrame.new(c + Vector3.new(2, 0, 2)) * CFrame.Angles(0, 0.7, math.rad(5)), 15, {Dead = true, Collide = true, Seed = 3})
	P.Tree(m, CFrame.new(c + Vector3.new(-7, 0, -3)) * CFrame.Angles(0, 2.1, math.rad(-7)), 11, {Dead = true, Collide = true, Seed = 8})
	P.Mushroom(m, CFrame.new(c + Vector3.new(-4, 0, 5)) * CFrame.Angles(0, 0, math.rad(24)), 2.6, rgb(150, 150, 146), {StemColor = rgb(170, 170, 164)})
	local haze = part(m, "MouldHaze", Vector3.new(16, 1, 16), CFrame.new(c + Vector3.new(0, 0.8, 0)), GREY, Mat.SmoothPlastic, GHOST)
	emitter(haze, {
		Name = "Dust", Texture = SMOKE, Rate = 3, Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(30, 30), Size = NumberSequence.new(2, 4), Transparency = fade(0.85), Color = ColorSequence.new(rgb(170, 174, 170)),
		RotSpeed = NumberRange.new(-15, 15),
	})
	return m
end

-- The Black Moon over the Sun: the corona of the Great Eclipse seen from the glade
local function sky(lobby)
	local m = model(lobby, "Sky")
	local pos = Vector3.new(-140, 330, -640)
	local toOrigin = (Vector3.new(0, 0, 0) - pos).Unit
	local extra = {Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false}
	local function disc(name, at, diameter, color, material)
		-- the X axis (the axis of the cylinder) points at the origin
		return part(m, name, Vector3.new(1, diameter, diameter), CFrame.lookAt(at, Vector3.new(0, 0, 0)) * CFrame.Angles(0, math.rad(90), 0), color, material, extra)
	end
	disc("Corona", pos, 150, rgb(255, 222, 170), Mat.Neon)
	disc("BlackMoon", pos + toOrigin * 6, 136, Color3.new(0, 0, 0), Mat.SmoothPlastic)
	return m
end

-- Lanterns, signposts, drifting spores and small growth all over the glade
local function ambience(lobby)
	local m = model(lobby, "Ambience")
	local motes = part(m, "SporeMotes", Vector3.new(170, 1, 170), CFrame.new(0, 26, 0), AMBER, Mat.SmoothPlastic, GHOST)
	emitter(motes, {
		Name = "Motes", Texture = SPARK, Rate = 14, Lifetime = NumberRange.new(16, 24), Speed = NumberRange.new(0.5, 1.2),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(25, 25), Size = NumberSequence.new(0.3),
		Transparency = fade(0.35), Color = ColorSequence.new(rgb(200, 255, 220), AMBER), LightEmission = 1, Drag = 0.1,
		RotSpeed = NumberRange.new(-20, 20),
	})
	P.SporeLantern(m, facing(around(160, 34, 0), Vector3.new(0, 0, 0)))
	for _, deg in ipairs({14, 104, 256}) do
		local pos = around(deg, B.PlazaRadius + 2.5, 0)
		P.Signpost(m, CFrame.lookAt(pos, pos * 2))
	end

	local zones = {
		{Vector3.new(0, 0, 0), B.PlazaRadius + 3}, {B.Circle.Center, B.Circle.Radius + 5}, {Vector3.new(0, 0, -76), 13},
		{Vector3.new(67, 0, 0), 21}, {Vector3.new(-62, 0, 4), 21}, {around(135, 60, 0), 19}, {around(222, 58, 0), 21},
		{around(180, 37, 0), 7}, {around(48, 84, 0), 11},
	}
	local function free(p)
		for _, z in ipairs(zones) do
			if (p - z[1]).Magnitude < z[2] then return false end
		end
		for _, s in ipairs(pathSegments) do
			local ab = s[2] - s[1]
			local t = math.clamp((p - s[1]):Dot(ab) / ab:Dot(ab), 0, 1)
			if (p - (s[1] + ab * t)).Magnitude < s[3] / 2 + 2 then return false end
		end
		return true
	end
	local rng = Random.new(9)
	local function spot()
		for _ = 1, 30 do
			local p = around(rng:NextNumber(0, 360), math.sqrt(rng:NextNumber(31 * 31, 87 * 87)), 0)
			if free(p) then return CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) end
		end
		return nil
	end
	local scatter = model(m, "Scatter")
	local caps = {RED, rgb(226, 170, 70), rgb(120, 170, 220), rgb(170, 130, 220), TEAL}
	for i = 1, 70 do
		local cf = spot()
		if cf then
			local color = caps[i % #caps + 1]
			P.Mushroom(scatter, cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), rng:NextNumber(0.8, 4.2), color,
				{Spots = color == RED and i % 2 == 0, Glow = color == TEAL and i % 10 == 4})
		end
	end
	for i = 1, 34 do
		local cf = spot()
		if cf then
			local big = i % 6 == 0
			P.Rock(scatter, cf, big and rng:NextNumber(4, 6.5) or rng:NextNumber(1, 2.6), {Seed = 100 + i, Collide = big})
		end
	end
	for _ = 1, 90 do
		local cf = spot()
		if cf then
			for k = 1, 2 do
				local h = rng:NextNumber(0.8, 1.7)
				wedge(scatter, "GrassTuft", Vector3.new(0.12, h, 0.7), cf * CFrame.Angles(0, k * 1.9, 0) * CFrame.new(0, h / 2, 0.2), rgb(96, 150, 84), Mat.Grass, DECO)
			end
		end
	end
	for _ = 1, 28 do
		local cf = spot()
		if cf then
			local fern = model(scatter, "Fern")
			for k = 1, 4 do
				part(fern, "Frond", Vector3.new(0.5, 0.08, 2.2), cf * CFrame.Angles(0, math.rad(k * 90 + 20), 0) * CFrame.Angles(math.rad(28), 0, 0) * CFrame.new(0, 0, -1.1),
					rgb(60, 124, 84), Mat.Grass, DECO)
			end
		end
	end
	return m
end

-- ---------------------------------------------------------------------------------------------------------------

-- The mood of the glade: dusk under the eclipse. Existing effects are reused by class.
function B.Lighting()
	local Lighting = game:GetService("Lighting")
	local function effect(class)
		local e = Lighting:FindFirstChildOfClass(class)
		if not e then
			e = Instance.new(class)
			e.Parent = Lighting
		end
		return e
	end
	Lighting.ClockTime = 19.4
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 1.6
	Lighting.Ambient = rgb(64, 62, 92)
	Lighting.OutdoorAmbient = rgb(58, 66, 98)
	Lighting.ColorShift_Top = rgb(150, 120, 200)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.15
	Lighting.GlobalShadows = true

	local atmosphere = effect("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = rgb(150, 140, 190)
	atmosphere.Decay = rgb(62, 52, 96)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6

	local bloom = effect("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 30
	bloom.Threshold = 1.1

	effect("SunRaysEffect").Intensity = 0.02

	local correction = effect("ColorCorrectionEffect")
	correction.TintColor = rgb(232, 236, 255)
	correction.Contrast = 0.08
	correction.Saturation = 0.06

	effect("DepthOfFieldEffect").Enabled = false

	-- no Sun and no Moon of the engine: the only body in the sky is the Black Moon
	local skybox = effect("Sky")
	skybox.SunTextureId = ""
	skybox.MoonTextureId = ""
	skybox.StarCount = 3000
end

function B.Build()
	for _, name in ipairs({"Lobby", "Baseplate", "SpawnLocation"}) do
		local old = workspace:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	lobby:SetAttribute("Build", "M10")

	ground(lobby)
	border(lobby)
	elderCap(lobby)
	expeditionCircle(lobby)
	expeditionGate(lobby)
	gateRoad(lobby)
	shrine(lobby)
	camp(lobby)
	pond(lobby)
	garden(lobby)
	noticeBoard(lobby)
	mouldEdge(lobby)
	sky(lobby)
	ambience(lobby)

	-- players appear on the plaza around the Elder Cap, looking at it
	for i = 1, B.Spawns do
		local pos = around(i * 360 / B.Spawns, 18, 0.9)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn_" .. i
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(5, 1, 5)
		spawn.CFrame = CFrame.lookAt(pos, Vector3.new(0, 0.9, 0))
		spawn.Parent = lobby
	end

	lobby.Parent = workspace
	B.Lighting()
	return lobby
end

function B.Ensure()
	return workspace:FindFirstChild("Lobby") or B.Build()
end

return B
