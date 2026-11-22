-- LobbyKit (milestone 10): palette, shapes and small helpers shared by LobbyProps, LobbyStructures and LobbyBuilder.
-- Every shape is anchored. Placement: part / cyl / ball / ring take the CENTRE;
-- box / pillar / dome / arch take the centre of the BASE and rise along +Y of that CFrame.
-- Directions in the lobby: north is -Z; a prop faces -Z of its CFrame (its LookVector).
local K = {}
local Mat = Enum.Material
K.Mat = Mat

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
K.rgb = rgb

K.C = {
	Cream = rgb(244, 240, 228), Stem = rgb(232, 222, 198), StemShade = rgb(206, 192, 166),
	Red = rgb(196, 54, 46), RedDark = rgb(150, 38, 36), Orange = rgb(226, 132, 58), Gold = rgb(226, 170, 70),
	Blue = rgb(104, 150, 214), Violet = rgb(150, 110, 200), Pink = rgb(214, 130, 170),
	Amber = rgb(255, 214, 120), Teal = rgb(120, 230, 200), Ember = rgb(255, 150, 60),
	Wood = rgb(112, 82, 58), DarkWood = rgb(76, 58, 46), Plank = rgb(150, 112, 74), Thatch = rgb(188, 160, 96),
	Stone = rgb(134, 132, 130), StoneLight = rgb(164, 160, 152), StoneDark = rgb(98, 98, 104), Paving = rgb(150, 144, 130),
	Moss = rgb(74, 122, 66), Leaf = rgb(62, 118, 76), LeafDark = rgb(40, 84, 62), Hedge = rgb(46, 96, 66),
	Dirt = rgb(112, 90, 66), Soil = rgb(70, 52, 42), Canvas = rgb(196, 176, 140), Iron = rgb(60, 58, 62), Rope = rgb(170, 140, 96),
	Parchment = rgb(232, 214, 176), Ink = rgb(52, 38, 28), Label = rgb(255, 244, 214),
}

-- Small decoration does not collide and casts no shadow; a ghost is an invisible marker
K.DECO = {CanCollide = false, CastShadow = false, CanTouch = false}
K.GHOST = {CanCollide = false, CastShadow = false, CanTouch = false, CanQuery = false, Transparency = 1}
K.SPARK = "rbxasset://textures/particles/sparkles_main.dds"
K.SMOKE = "rbxasset://textures/particles/smoke_main.dds"

function K.with(base, more)
	local t = table.clone(base)
	for k, v in pairs(more) do t[k] = v end
	return t
end

local function finish(p, parent, name, cf, color, material, extra)
	p.Name = name
	p.Anchored = true
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		if extra.CanCollide ~= nil then p.CanCollide = extra.CanCollide end -- before CanQuery
		for k, v in pairs(extra) do
			if k ~= "CanCollide" then p[k] = v end
		end
	end
	p.Parent = parent
	return p
end

local function new(class, size, shape)
	local p = Instance.new(class)
	if shape then p.Shape = shape end
	p.Size = size
	return p
end

local TURN = CFrame.Angles(0, 0, math.rad(90)) -- the axis of a cylinder is X: this stands it up
local SIDE = CFrame.Angles(0, math.rad(90), 0)

function K.part(parent, name, size, cf, color, material, extra)
	return finish(new("Part", size), parent, name, cf, color, material, extra)
end

function K.box(parent, name, size, baseCf, color, material, extra)
	return K.part(parent, name, size, baseCf * CFrame.new(0, size.Y / 2, 0), color, material, extra)
end

function K.cyl(parent, name, height, diameter, cf, color, material, extra)
	return finish(new("Part", Vector3.new(height, diameter, diameter), Enum.PartType.Cylinder), parent, name, cf * TURN, color, material, extra)
end

function K.pillar(parent, name, height, diameter, baseCf, color, material, extra)
	return K.cyl(parent, name, height, diameter, baseCf * CFrame.new(0, height / 2, 0), color, material, extra)
end

function K.wedge(parent, name, size, cf, color, material, extra)
	return finish(new("WedgePart", size), parent, name, cf, color, material, extra)
end

function K.corner(parent, name, size, cf, color, material, extra)
	return finish(new("CornerWedgePart", size), parent, name, cf, color, material, extra)
end

local function along(a, b)
	local d = b - a
	if math.abs(d.Unit.Y) > 0.999 then return CFrame.new((a + b) / 2) * CFrame.Angles(math.rad(d.Y > 0 and 90 or -90), 0, 0) end
	return CFrame.lookAt((a + b) / 2, b)
end

-- A round bar from point a to point b
function K.rod(parent, name, a, b, diameter, color, material, extra)
	return finish(new("Part", Vector3.new((b - a).Magnitude, diameter, diameter), Enum.PartType.Cylinder), parent, name, along(a, b) * SIDE, color, material, extra)
end

-- A square bar from point a to point b (width across, height up)
function K.beam(parent, name, a, b, width, height, color, material, extra)
	return finish(new("Part", Vector3.new(width, height, (b - a).Magnitude)), parent, name, along(a, b), color, material, extra)
end

-- CSG shapes are made once, then cloned and resized. false when the engine refuses: a plain shape is used instead
local templates = {}
local HIGH = CFrame.new(0, 900, 0)

local function raw(tmp, shape, size, cf)
	local p = new("Part", size, shape)
	p.Anchored = true
	p.CFrame = cf or HIGH
	p.Parent = tmp
	return p
end

local function template(key, smoothing, make)
	if templates[key] == nil then
		local tmp = Instance.new("Folder")
		tmp.Name = "LobbyKitTmp"
		tmp.Parent = workspace
		local ok, res = pcall(make, tmp)
		if ok and res then
			res.UsePartColor = true
			res.SmoothingAngle = smoothing
			res.Anchored = true
		else
			warn("[LobbyKit] shape " .. key .. ": " .. tostring(res))
			res = false
		end
		templates[key] = res
		tmp:Destroy()
	end
	return templates[key]
end

local function shaped(t, size)
	local p = t:Clone()
	p.Size = size
	return p
end

-- An ellipsoid of any proportions
function K.ball(parent, name, size, cf, color, material, extra)
	local t = template("sphere", 40, function(tmp)
		return raw(tmp, Enum.PartType.Ball, Vector3.new(8, 8, 8)):UnionAsync({raw(tmp, Enum.PartType.Block, Vector3.new(1, 1, 1))}, Enum.CollisionFidelity.Hull)
	end)
	if t then return finish(shaped(t, size), parent, name, cf, color, material, extra) end
	local p = new("Part", size)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return finish(p, parent, name, cf, color, material, extra)
end

-- Half an ellipsoid with a flat bottom on baseCf: mushroom caps, mounds, helmets
function K.dome(parent, name, diameter, height, baseCf, color, material, extra)
	local t = template("dome", 40, function(tmp)
		local cut = raw(tmp, Enum.PartType.Block, Vector3.new(10, 5, 10), HIGH * CFrame.new(0, -2.5, 0))
		return raw(tmp, Enum.PartType.Ball, Vector3.new(8, 8, 8)):SubtractAsync({cut}, Enum.CollisionFidelity.Hull)
	end)
	local size, cf = Vector3.new(diameter, height, diameter), baseCf * CFrame.new(0, height / 2, 0)
	if t then return finish(shaped(t, size), parent, name, cf, color, material, extra) end
	return K.ball(parent, name, size, cf, color, material, extra)
end

-- A point on such a dome: azimuth in degrees (0 = -Z, 90 = +X), rise 0 (rim) .. 1 (top). +Y of the result is the surface normal
function K.onDome(baseCf, diameter, height, azimuth, rise)
	local a, f, r = math.rad(azimuth), rise * math.pi / 2, diameter / 2
	local p = Vector3.new(r * math.cos(f) * math.sin(a), height * math.sin(f), -r * math.cos(f) * math.cos(a))
	local n = Vector3.new(p.X / (r * r), p.Y / (height * height), p.Z / (r * r)).Unit
	local side = n:Cross(Vector3.yAxis)
	if side.Magnitude < 1e-3 then side = Vector3.xAxis end
	return baseCf * CFrame.fromMatrix(p, side.Unit, n)
end

local function holed(key, ratio, halved)
	local step = math.clamp(math.floor(ratio * 20 + 0.5), 4, 19)
	return template(key .. step, 30, function(tmp)
		local cuts = {raw(tmp, Enum.PartType.Cylinder, Vector3.new(3, step / 2, step / 2))}
		if halved then table.insert(cuts, raw(tmp, Enum.PartType.Block, Vector3.new(3, 6, 12), HIGH * CFrame.new(0, -3, 0))) end
		return raw(tmp, Enum.PartType.Cylinder, Vector3.new(2, 10, 10)):SubtractAsync(cuts, Enum.CollisionFidelity.PreciseConvexDecomposition)
	end)
end

-- A flat ring (a tube): outer diameter, ratio = inner / outer diameter (0.2 .. 0.95), axis along +Y of cf
function K.ring(parent, name, outer, ratio, height, cf, color, material, extra)
	local t = holed("ring", ratio, false)
	if t then return finish(shaped(t, Vector3.new(height, outer, outer)), parent, name, cf * TURN, color, material, extra) end
	return K.cyl(parent, name, height, outer, cf, color, material, extra)
end

-- Half a ring standing on baseCf: it spans X, rises along Y, and one walks through it along Z. ratio = inner / outer
function K.arch(parent, name, span, rise, depth, ratio, baseCf, color, material, extra)
	local t = holed("arch", ratio, true)
	if t then return finish(shaped(t, Vector3.new(depth, rise, span)), parent, name, baseCf * CFrame.new(0, rise / 2, 0) * SIDE, color, material, extra) end
	local band = rise * (1 - ratio)
	return K.part(parent, name, Vector3.new(span, band, depth), baseCf * CFrame.new(0, rise - band / 2, 0), color, material, extra)
end

function K.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function K.folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A light. detail = true marks a small light that the client setting "low detail" switches off
function K.light(parent, color, range, brightness, detail)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	if detail then l:SetAttribute("Detail", true) end
	l.Parent = parent
	return l
end

function K.emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

function K.fade(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, peak),
		NumberSequenceKeypoint.new(0.8, peak), NumberSequenceKeypoint.new(1, 1),
	})
end

-- Compass: 0 degrees is north (-Z), 90 is east (+X)
function K.around(deg, radius, y)
	local a = math.rad(deg)
	return Vector3.new(math.sin(a) * radius, y or 0, -math.cos(a) * radius)
end

-- A CFrame at pos that looks level at target
function K.facing(pos, target)
	return CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
end

-- The same colour, a little lighter or darker: neighbours never look flat
function K.tint(color, rng, amount)
	local h, s, v = color:ToHSV()
	amount = amount or 0.06
	return Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-amount, amount), 0, 1), math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

-- A text. key = LocaleKey: the client replaces the English text by the player's language. props may hold LocaleArg
function K.text(parent, name, text, key, props)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = K.C.Label
	t.TextStrokeTransparency = 0.4
	t.Text = text
	if key then t:SetAttribute("LocaleKey", key) end
	for k, v in pairs(props or {}) do
		if k == "LocaleArg" then t:SetAttribute(k, v) else t[k] = v end
	end
	t.Parent = parent
	return t
end

-- A floating name over a place: part Label_<key> with BillboardGui "Tag". opts: Name, Size, Offset, MaxDistance, Hint, HintKey
function K.label(parent, key, pos, text, opts)
	opts = opts or {}
	local anchor = K.part(parent, opts.Name or ("Label_" .. key), Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), K.C.Label, Mat.SmoothPlastic, K.GHOST)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = opts.Size or UDim2.fromOffset(240, opts.Hint and 60 or 40)
	gui.StudsOffset = Vector3.new(0, opts.Offset or 1.5, 0)
	gui.MaxDistance = opts.MaxDistance or 80
	gui.LightInfluence = 0
	K.text(gui, "Text", text, key, {Size = UDim2.fromScale(1, opts.Hint and 0.6 or 1)})
	if opts.Hint then
		K.text(gui, "Hint", opts.Hint, opts.HintKey, {Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), Font = Enum.Font.GothamMedium, TextTransparency = 0.15})
	end
	gui.Parent = anchor
	return anchor
end

-- A SurfaceGui on a face of a part, for boards and banners
function K.surface(part, face, pixelsPerStud)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0.3
	gui.Parent = part
	return gui
end

return K
