-- Look and widgets of the lobby interface: theme, panels, labels, buttons, tooltips, and the test hook of Studio.
-- Every button is made by Kit.button: its handler is kept in a registry, and a press, a hover and the test
-- hook all go through the same functions, so what the hook does is what a player's press does
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Icons = require(script.Parent.Icons)

local Kit = {}
Kit.Panel = Color3.fromRGB(24, 28, 44)
Kit.Slot = Color3.fromRGB(44, 50, 74)
Kit.Grey = Color3.fromRGB(74, 82, 112)
Kit.Cream = Color3.fromRGB(255, 244, 214)
Kit.Amber = Color3.fromRGB(255, 214, 120)
Kit.Red = Color3.fromRGB(200, 60, 50)
Kit.Teal = Color3.fromRGB(120, 230, 200)
Kit.Scale = 1
Kit.T = function(key) return key end -- the controller puts its translate function here (tooltips)

local registry = {} -- [button] = {fn = handler, tip = locale key, side = tooltip to the right, on = enabled, why = reason}
local scales = {}
local gui, tip, tipLabel, tipFor = nil, nil, nil, nil
local tipTurn = 0

function Kit.make(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

function Kit.round(o, radius)
	Kit.make("UICorner", {CornerRadius = UDim.new(0, radius)}, o)
	return o
end

-- An invisible container
function Kit.frame(parent, name, position, size)
	return Kit.make("Frame", {Name = name, Position = position, Size = size, BackgroundTransparency = 1}, parent)
end

-- A glass panel with a thin outline. kind "slot": a lighter box inside a panel; kind "head": a title bar
function Kit.panel(parent, name, position, size, kind)
	local f = Kit.make("Frame", {Name = name, Position = position, Size = size, BackgroundColor3 = Kit.Panel,
		BackgroundTransparency = 0.08}, parent)
	Kit.round(f, kind and 10 or 14)
	Kit.make("UIStroke", {Color = Kit.Cream, Transparency = 0.8, Thickness = 1}, f)
	if kind == "slot" then
		f.BackgroundColor3 = Kit.Slot
		f.BackgroundTransparency = 0.3
	elseif kind == "head" then
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		Kit.make("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(86, 62, 104), Kit.Slot)}, f)
	end
	return f
end

-- Text that always fits its box: it wraps, and shrinks from `textSize` when it has to
function Kit.label(parent, name, position, size, textSize, props)
	local l = Kit.make("TextLabel", {Name = name, Position = position, Size = size, BackgroundTransparency = 1, Text = "",
		Font = Enum.Font.GothamMedium, TextColor3 = Kit.Cream, TextSize = textSize, TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left}, parent)
	for k, v in pairs(props or {}) do l[k] = v end
	Kit.make("UITextSizeConstraint", {MaxTextSize = textSize, MinTextSize = 8}, l)
	return l
end

local function hover(b, entering)
	local r = registry[b]
	local text = nil
	if entering and r then
		if r.on then text = r.tip and Kit.T(r.tip) else text = r.why end
	end
	if not text then
		if tipFor == b then
			tipFor = nil
			tip.Visible = false
		end
		return
	end
	local textSize = math.floor(13 * Kit.Scale + 0.5)
	local bounds = TextService:GetTextSize(text, textSize, Enum.Font.GothamMedium, Vector2.new(260 * Kit.Scale, 400))
	local w, h = bounds.X + 20, bounds.Y + 12
	local view, at, box = gui.AbsoluteSize, b.AbsolutePosition - gui.AbsolutePosition, b.AbsoluteSize
	local x, y = at.X + (box.X - w) / 2, at.Y + box.Y + 6
	if r.side then
		x, y = at.X + box.X + 6, at.Y + (box.Y - h) / 2
	elseif y + h > view.Y then
		y = at.Y - h - 6
	end
	tip.Position = UDim2.fromOffset(math.clamp(x, 4, math.max(4, view.X - w - 4)), math.clamp(y, 4, math.max(4, view.Y - h - 4)))
	tip.Size = UDim2.fromOffset(w, h)
	tipLabel.TextSize = textSize
	tipLabel.Text = text
	tip.Visible = true
	tipFor = b
	-- a touch has no "leave": the tooltip goes away by itself
	tipTurn += 1
	local turn = tipTurn
	task.delay(4, function()
		if tipTurn == turn and tipFor == b then hover(b, false) end
	end)
end

local function press(b)
	local r = registry[b]
	if not (r and r.on) then return end
	hover(b, false)
	local ok, err = pcall(r.fn)
	if not ok then warn("[Lobby UI] " .. b.Name .. ": " .. tostring(err)) end
end

-- opts: text, tip (locale key), side (tooltip to the right of the button), color, icon (name in Icons, left of the
-- text), bare (no background: the caller draws the button's face inside it)
function Kit.button(parent, name, position, size, fn, opts)
	opts = opts or {}
	local color = opts.color or Kit.Grey
	local light = color.R * 0.3 + color.G * 0.6 + color.B * 0.1 > 0.6
	local b = Kit.make("TextButton", {Name = name, Position = position, Size = size, Text = opts.text or "",
		BackgroundColor3 = color, BackgroundTransparency = opts.bare and 1 or 0, AutoButtonColor = not opts.bare,
		Font = Enum.Font.GothamBold, TextColor3 = light and Kit.Panel or Kit.Cream, TextSize = 14, TextScaled = true}, parent)
	Kit.round(b, 8)
	Kit.make("UITextSizeConstraint", {MaxTextSize = 14, MinTextSize = 8}, b)
	if opts.icon then
		Icons.draw(opts.icon, b, Kit.Cream, 16).Position = UDim2.new(0, -16, 0.5, 0) -- left of the padded text
	end
	if not opts.bare then
		Kit.make("UIPadding", {PaddingLeft = UDim.new(0, opts.icon and 30 or 6), PaddingRight = UDim.new(0, 6)}, b)
	end
	registry[b] = {fn = fn, tip = opts.tip, side = opts.side, on = true}
	b.Activated:Connect(function() press(b) end)
	b.MouseEnter:Connect(function() hover(b, true) end)
	b.MouseLeave:Connect(function() hover(b, false) end)
	b.Destroying:Connect(function()
		registry[b] = nil
		hover(b, false)
	end)
	return b
end

-- A button that cannot be used now stays visible, dimmed; `why` is its tooltip
function Kit.enable(b, on, why)
	local r = registry[b]
	r.on, r.why = on, why
	b.AutoButtonColor = on
	b.BackgroundTransparency = on and 0 or 0.65
	b.TextTransparency = on and 0 or 0.5
end

-- A scrolling column of rows; the caller sets CanvasSize after filling it
function Kit.scroll(parent, name, position, size)
	local s = Kit.make("ScrollingFrame", {Name = name, Position = position, Size = size, BackgroundTransparency = 1,
		ScrollBarThickness = 4, ScrollBarImageColor3 = Kit.Cream, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y}, parent)
	Kit.make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, s)
	return s
end

function Kit.clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

-- Top-level pieces are scaled one by one, around their anchor points, so their distance to the screen edge
-- and to the Roblox top bar stays the same in pixels
function Kit.scaled(frame)
	table.insert(scales, Kit.make("UIScale", {Scale = Kit.Scale}, frame))
	return frame
end

function Kit.setScale(scale)
	Kit.Scale = scale
	for _, s in ipairs(scales) do s.Scale = scale end
end

function Kit.init(screenGui)
	gui = screenGui
	tip = Kit.make("Frame", {Name = "Tip", Visible = false, ZIndex = 20, BackgroundColor3 = Color3.fromRGB(12, 14, 24),
		BackgroundTransparency = 0.04}, gui)
	Kit.round(tip, 8)
	Kit.make("UIStroke", {Color = Kit.Amber, Transparency = 0.4, Thickness = 1}, tip)
	tipLabel = Kit.make("TextLabel", {Name = "Text", Position = UDim2.fromOffset(9, 6), Size = UDim2.new(1, -18, 1, -12),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = Kit.Cream, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left}, tip)
end

local function shown(o)
	while o and o ~= gui do
		if o:IsA("GuiObject") and not o.Visible then return false end
		o = o.Parent
	end
	return o == gui
end

local function dump()
	local out, origin = {}, gui.AbsolutePosition
	for _, o in ipairs(gui:GetDescendants()) do
		if (o:IsA("TextLabel") or o:IsA("TextButton")) and shown(o) then
			local names, p = {}, o
			while p ~= gui do
				table.insert(names, 1, p.Name)
				p = p.Parent
			end
			local r, at, size = registry[o], o.AbsolutePosition - origin, o.AbsoluteSize
			table.insert(out, {path = table.concat(names, "/"), class = o.ClassName, text = o.Text, enabled = r and r.on,
				x = math.floor(at.X), y = math.floor(at.Y), w = math.floor(size.X), h = math.floor(size.Y)})
		end
	end
	return out
end

-- Studio only: BindableFunction GS_UiHook in the ScreenGui. Invoke("click" | "hover" | "unhover", path),
-- Invoke("dump"), Invoke("state"). `state` returns the controller's part of the answer
function Kit.hook(state)
	if not RunService:IsStudio() then return end
	local f = Kit.make("BindableFunction", {Name = "GS_UiHook"}, gui)
	f.OnInvoke = function(command, path)
		if command == "dump" then return dump() end
		if command == "state" then
			local s = state()
			s.tooltip = tipFor and tipLabel.Text or nil
			return s
		end
		local b = gui
		for _, name in ipairs(string.split(tostring(path), "/")) do
			b = b and b:FindFirstChild(name)
		end
		local r = b and registry[b]
		if not r then return false, "unknown" end
		if not shown(b) then return false, "hidden" end
		if command == "hover" or command == "unhover" then
			hover(b, command == "hover")
			return true
		end
		if command ~= "click" then return false, "unknown" end
		if not r.on then return false, "disabled" end
		press(b)
		return true
	end
end

return Kit
