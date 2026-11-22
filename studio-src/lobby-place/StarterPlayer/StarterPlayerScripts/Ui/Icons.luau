-- Icons of the lobby interface, drawn from Frames (no image assets): rounded boxes, outlines and rotated bars.
-- Every shape is placed by its centre, in fractions of the icon, so an icon can have any size
local Icons = {}

local CREAM = Color3.fromRGB(255, 244, 214)
local RED = Color3.fromRGB(200, 60, 50)
local DARK = Color3.fromRGB(24, 28, 44)
local fade = 0 -- transparency of the shapes of the icon that is being drawn

-- round: corner radius as a fraction of the shorter side (0.5 = fully round); line: outline of this thickness, no fill
local function shape(parent, x, y, w, h, color, round, rotation, line)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = line and 1 or fade
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	if line then
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = line
		s.Transparency = fade
		s.Parent = f
	end
	f.Parent = parent
	return f
end

local function pawn(i, c, x, y, k)
	shape(i, x, y - 0.26 * k, 0.36 * k, 0.36 * k, c, 0.5)
	shape(i, x, y + 0.2 * k, 0.62 * k, 0.5 * k, c, 0.45)
end

local draw = {}

function draw.menu(i, c)
	for row = 1, 3 do
		shape(i, 0.5, row * 0.25, 0.78, 0.13, c, 0.5)
	end
end

function draw.close(i, c)
	shape(i, 0.5, 0.5, 0.95, 0.15, c, 0.5, 45)
	shape(i, 0.5, 0.5, 0.95, 0.15, c, 0.5, -45)
end

-- a Guardian standing on a zone pad
function draw.play(i, c)
	shape(i, 0.5, 0.8, 0.9, 0.3, c, 0.5, 0, 2)
	pawn(i, c, 0.5, 0.42, 0.72)
end

function draw.party(i, c)
	pawn(i, c, 0.28, 0.52, 0.72)
	pawn(i, c, 0.72, 0.52, 0.72)
end

-- a gear: four bars make eight teeth
function draw.settings(i, c)
	for turn = 0, 3 do
		shape(i, 0.5, 0.5, 0.96, 0.2, c, 0.2, turn * 45)
	end
	shape(i, 0.5, 0.5, 0.66, 0.66, c, 0.5)
	shape(i, 0.5, 0.5, 0.28, 0.28, DARK, 0.5)
end

-- the letter i in a ring
function draw.help(i, c)
	shape(i, 0.5, 0.5, 0.86, 0.86, c, 0.5, 0, 2)
	shape(i, 0.5, 0.28, 0.15, 0.15, c, 0.5)
	shape(i, 0.5, 0.6, 0.15, 0.36, c, 0.5)
end

function draw.pawn(i, c)
	pawn(i, c, 0.5, 0.52, 1)
end

-- the emblem: a fly agaric. The cap is the upper half of a disc, cut by a clipping frame
function draw.mushroom(i)
	shape(i, 0.5, 0.72, 0.3, 0.5, CREAM, 0.3)
	local cap = shape(i, 0.5, 0.3, 0.96, 0.5, CREAM)
	cap.BackgroundTransparency = 1
	cap.ClipsDescendants = true
	shape(cap, 0.5, 1, 1, 2, RED, 0.5)
	shape(cap, 0.27, 0.62, 0.17, 0.34, CREAM, 0.5)
	shape(cap, 0.56, 0.36, 0.2, 0.4, CREAM, 0.5)
	shape(cap, 0.8, 0.72, 0.13, 0.26, CREAM, 0.5)
end

-- An icon of `size` pixels, centred in its parent. `transparency` makes a dim copy
function Icons.draw(name, parent, color, size, transparency)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	fade = transparency or 0
	draw[name](icon, color or CREAM)
	fade = 0
	icon.Parent = parent
	return icon
end

-- A row of `count` pawns, the first `lit` of them bright: the places of a mode and how many are taken.
-- The row is anchored by its centre
function Icons.pawns(parent, count, lit, color, size)
	local row = Instance.new("Frame")
	row.Name = "Pawns"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Size = UDim2.fromOffset(count * size, size)
	for n = 1, count do
		local icon = Icons.draw("pawn", row, color, size, n > lit and 0.75 or 0)
		icon.Position = UDim2.new(0, (n - 0.5) * size, 0.5, 0)
	end
	row.Parent = parent
	return row
end

return Icons
