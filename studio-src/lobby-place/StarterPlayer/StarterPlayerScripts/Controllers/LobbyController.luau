-- The lobby interface (milestone 10, second pass): the dock, the lobby menu (Play, Party, Settings, Help), the queue
-- banner, invitation cards, toasts, and the client's part of the world (texts of signs, zone lights, labels, low
-- detail). It shows what the server sent (LobbyState) and sends the player's intentions back (LobbyAction); it
-- decides nothing itself. Instance names are stable: the Studio test hook (Kit.hook) finds controls by their path
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local PartyCfg = require(Shared.Config.Party)
local LobbyCfg = require(Shared.Config.Lobby)
local Ui = script.Parent.Parent:WaitForChild("Ui")
local Kit = require(Ui:WaitForChild("Kit"))
local Icons = require(Ui:WaitForChild("Icons"))

local Lobby = {Priority = 50}
local player = Players.LocalPlayer
-- the settings (kept for this visit) and the state of the menu
local S = {open = false, tab = "Play", lang = Locale.Default, size = 1, lowDetail = false, labels = true}
local snap = nil     -- the last LobbyState
local canInviteFriends = false
local statics = {}   -- [label or button] = {key, argument}: texts that change only with the language
local dimmed = {}    -- [emitter or light] = true: switched off by "low detail"
local pulsing = {}   -- [zone id] = true while the runes of the zone pulse
local toasts = {}    -- {frame, text}, oldest first

local U, px = UDim2.new, UDim2.fromOffset
local BOLD, BLACK = Enum.Font.GothamBold, Enum.Font.GothamBlack
local CENTER = Enum.TextXAlignment.Center
local TABS = {"Play", "Party", "Settings", "Help"}

-- The four modes in zone order: {id, color, cap}. Colours of the contract, if the config has none
local FALLBACK = {
	{id = "solo", color = Color3.fromRGB(96, 214, 140)}, {id = "duo", color = Color3.fromRGB(92, 170, 255)},
	{id = "trio", color = Color3.fromRGB(255, 168, 72)}, {id = "quartet", color = Color3.fromRGB(214, 112, 232)},
}
local ZONES, ZONE = {}, {}
for i, z in ipairs(LobbyCfg.Zones or FALLBACK) do
	local cap = i
	for _, f in ipairs(PartyCfg.Formats) do
		if f.id == z.id then cap = f.size end
	end
	ZONES[i] = {id = z.id, color = z.color, cap = cap}
	ZONE[z.id] = ZONES[i]
end

local function T(key, ...)
	return Locale.T(S.lang, key, ...)
end

local function act(action, arg)
	Net.Event("LobbyAction"):FireServer(action, arg)
end

local function static(o, key, arg)
	statics[o] = {key, arg}
	return o
end

-- whole seconds until a moment of the server clock
local function left(moment, now)
	return math.max(0, math.ceil((moment or now) - now))
end

local function row(parent, name, order, height)
	local r = Kit.panel(parent, name, px(0, 0), U(1, -8, 0, height), "slot")
	r.LayoutOrder = order
	return r
end

local function title(parent, name, x, y, key)
	return static(Kit.label(parent, name, px(x, y), px(300, 20), 15, {Font = BOLD, TextColor3 = Kit.Amber}), key)
end

-- Accept and Decline of one invitation
local function answers(parent, id, x, y, width)
	Kit.button(parent, "Accept", U(x, 0, 0, y), px(width, 26), function() act("accept", id) end,
		{text = T("invite_accept"), color = Kit.Teal}).AnchorPoint = Vector2.new(x, 0)
	Kit.button(parent, "Decline", U(x, x == 0 and width + 6 or -width - 6, 0, y), px(width, 26),
		function() act("decline", id) end, {text = T("invite_decline")}).AnchorPoint = Vector2.new(x, 0)
end

-- The world speaks the player's language and follows the settings; also called for parts that arrive later
local function world(d)
	if d:IsA("TextLabel") then
		local key = d:GetAttribute("LocaleKey")
		if key then
			local text = T(key, d:GetAttribute("LocaleArg"))
			if text ~= key then d.Text = text end
		end
	elseif d:IsA("BillboardGui") then
		if d.Name == "Tag" and not d:FindFirstAncestor("Zones") then d.Enabled = S.labels end
	elseif d:IsA("ParticleEmitter") or (d:IsA("Light") and d:GetAttribute("Detail") == true) then
		if S.lowDetail and d.Enabled then
			dimmed[d] = true
			d.Enabled = false
		elseif not S.lowDetail and dimmed[d] then
			dimmed[d] = nil
			d.Enabled = true
		end
	end
end

-- What the snapshot says about this player; safe before the first snapshot
function Lobby:My()
	local party = snap and snap.party or {}
	local id = player.UserId
	local my = {id = id, members = party.members or {{id = id, name = player.Name}}, leader = party.leader or id,
		launching = party.launching == true, max = party.max or PartyCfg.MaxSize}
	my.size = #my.members
	my.leading = my.leader == id
	for _, m in ipairs(my.members) do
		if m.id == id then my.zone = m.zone end
	end
	return my
end

function Lobby:Open(open, tab)
	S.open = open
	S.tab = tab or S.tab
	self:Render()
end

function Lobby:BuildDock()
	local dock = Kit.scaled(Kit.frame(self.Gui, "Dock", U(0, 8, 0.5, 29), px(64, 334)))
	dock.AnchorPoint = Vector2.new(0, 0.5)
	self.Dock = {}
	for i, name in ipairs({"Menu", "Play", "Party", "Settings", "Help"}) do
		local low = string.lower(name)
		local b = Kit.button(dock, name, px(0, (i - 1) * 68), px(64, 62), function()
			if name == "Menu" then
				self:Open(not S.open)
			else
				self:Open(not (S.open and S.tab == name), name)
			end
		end, {tip = "tip_" .. low, side = true, bare = true})
		local tile = Kit.panel(b, "Tile", px(9, 0), px(46, 46))
		Icons.draw(low, tile, Kit.Cream, 26)
		static(Kit.label(b, "Caption", px(0, 47), U(1, 0, 0, 15), 11, {TextXAlignment = CENTER}), "tab_" .. low)
		self.Dock[name] = tile
	end
	self.Badge = Kit.round(Kit.label(self.Dock.Party, "Badge", U(1, -13, 0, -6), px(19, 19), 12, {Font = BOLD,
		BackgroundColor3 = Kit.Red, BackgroundTransparency = 0, TextXAlignment = CENTER}), 10)
end

function Lobby:BuildWindow()
	local w = Kit.scaled(Kit.panel(self.Gui, "Window", U(0.5, 0, 0, 62), px(640, 404)))
	w.AnchorPoint = Vector2.new(0.5, 0)
	w.ZIndex = 4
	w.Active = true -- a press on the menu is not a press on the world behind it
	self.Window = w
	local bar = Kit.panel(w, "Bar", px(4, 4), U(1, -8, 0, 40), "head")
	Icons.draw("mushroom", bar, nil, 28).Position = U(0, 26, 0.5, 0)
	static(Kit.label(bar, "Title", px(48, 0), U(1, -100, 1, 0), 18, {Font = BLACK}), "menu_title")
	Icons.draw("close", Kit.button(w, "Close", U(1, -40, 0, 9), px(30, 30), function() self:Open(false) end,
		{tip = "tip_close", color = Kit.Red}), Kit.Cream, 14)
	local tabs = Kit.frame(w, "Tabs", px(12, 52), U(1, -24, 0, 32))
	self.Tabs, self.Pages = {}, {}
	for i, name in ipairs(TABS) do
		local b = Kit.button(tabs, name, U((i - 1) / 4, 2, 0, 0), U(0.25, -4, 1, 0), function() self:Open(true, name) end,
			{icon = string.lower(name)})
		Kit.make("UIStroke", {Name = "Mark", Color = Kit.Amber, Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
		self.Tabs[name] = static(b, "tab_" .. string.lower(name))
		self.Pages[name] = Kit.frame(w, name, px(12, 92), U(1, -24, 1, -102)) -- 616 x 302
	end
	self:BuildPlay(self.Pages.Play)
	self:BuildParty(self.Pages.Party)
	self:BuildSettings(self.Pages.Settings)
	self:BuildHelp(self.Pages.Help)
end

function Lobby:BuildPlay(page)
	self.Cards = {}
	for i, z in ipairs(ZONES) do
		local card = Kit.panel(page, "Card_" .. z.id, U((i - 1) / 4, 3, 0, 0), U(0.25, -6, 1, -28), "slot")
		Kit.round(Kit.make("Frame", {Name = "Band", Position = px(8, 8), Size = U(1, -16, 0, 5), BackgroundColor3 = z.color}, card), 3)
		Icons.pawns(card, z.cap, z.cap, z.color, 24).Position = U(0.5, 0, 0, 36)
		static(Kit.label(card, "Mode", px(6, 54), U(1, -12, 0, 26), 21, {Font = BLACK, TextColor3 = z.color,
			TextXAlignment = CENTER}), "mode_" .. z.id)
		static(Kit.label(card, "Capacity", px(6, 82), U(1, -12, 0, 18), 13, {TextXAlignment = CENTER}), "mode_capacity", z.cap)
		local c = {zone = z, panel = card}
		c.live = Kit.label(card, "Live", px(6, 108), U(1, -12, 0, 34), 13, {TextColor3 = Kit.Amber, TextXAlignment = CENTER})
		c.why = Kit.label(card, "Why", px(6, 150), U(1, -12, 0, 64), 12, {TextTransparency = 0.25, TextXAlignment = CENTER})
		c.action = Kit.button(card, "Action", U(0, 8, 1, -46), U(1, -16, 0, 38), function()
			if self:My().zone == z.id then act("leave_queue") else act("join", z.id) end
		end, {tip = "tip_action"})
		self.Cards[i] = c
	end
	static(Kit.label(page, "Footer", U(0, 0, 1, -22), U(1, 0, 0, 20), 13, {TextTransparency = 0.3,
		TextXAlignment = CENTER}), "play_footer")
end

function Lobby:BuildParty(page)
	self.PartyTitle = Kit.label(page, "PartyTitle", px(0, 0), px(300, 20), 15, {Font = BOLD, TextColor3 = Kit.Amber})
	self.Members = Kit.scroll(page, "Members", px(0, 24), px(324, 156))
	self.LeaveParty = static(Kit.button(page, "LeaveParty", px(0, 186), px(160, 28), function() act("leave") end,
		{tip = "tip_leave_party"}), "party_leave")
	title(page, "InvitesTitle", 0, 222, "party_invites")
	self.InviteList = Kit.scroll(page, "Invites", px(0, 244), px(324, 58))
	title(page, "PlayersTitle", 332, 0, "party_players")
	self.Players = Kit.scroll(page, "Players", px(332, 24), px(284, 240))
	self.Friends = static(Kit.button(page, "Friends", px(332, 272), px(276, 30), function()
		pcall(function() SocialService:PromptGameInvite(player) end)
	end, {tip = "tip_friends"}), "party_friends")
end

function Lobby:BuildSettings(page)
	self.Segments = {}
	-- one setting: a title, one line about it, and a segmented control of {name, value, key} options
	local function setting(i, name, key, field, options)
		local r = Kit.panel(page, name, px(0, (i - 1) * 76), U(1, 0, 0, 68), "slot")
		static(Kit.label(r, "Title", px(14, 9), px(270, 22), 16, {Font = BOLD}), key)
		static(Kit.label(r, "Text", px(14, 31), px(270, 30), 12, {TextTransparency = 0.3}), key .. "_text")
		for n, o in ipairs(options) do
			local b = Kit.button(r, o[1], U(1, -8 - (#options - n + 1) * 104, 0.5, -17), px(98, 34), function()
				S[field] = o[2]
				self:World()
				self:Render()
			end)
			table.insert(self.Segments, {button = static(b, o[3]), field = field, value = o[2]})
		end
	end
	local switch = {{"Off", false, "toggle_off"}, {"On", true, "toggle_on"}}
	setting(1, "Language", "set_language", "lang", {{"en", "en", "lang_en"}, {"ru", "ru", "lang_ru"}})
	setting(2, "Size", "set_size", "size", {{"small", 0.85, "size_small"}, {"normal", 1, "size_normal"}, {"large", 1.15, "size_large"}})
	setting(3, "LowDetail", "set_detail", "lowDetail", switch)
	setting(4, "Labels", "set_labels", "labels", switch)
end

function Lobby:BuildHelp(page)
	title(page, "StepsTitle", 0, 0, "board_title")
	for i = 1, 4 do
		static(Kit.label(page, "Step_" .. i, px(0, 24 + (i - 1) * 34), px(300, 30), 13), "board_step_" .. i)
	end
	title(page, "ModesTitle", 316, 0, "help_modes")
	for i, z in ipairs(ZONES) do
		local r = Kit.panel(page, "Mode_" .. z.id, px(316, 24 + (i - 1) * 34), px(300, 30), "slot")
		Kit.round(Kit.make("Frame", {Name = "Dot", Position = px(10, 8), Size = px(14, 14), BackgroundColor3 = z.color}, r), 7)
		static(Kit.label(r, "Name", px(32, 0), px(100, 30), 14, {Font = BOLD, TextColor3 = z.color}), "mode_" .. z.id)
		static(Kit.label(r, "Capacity", px(136, 0), px(154, 30), 13, {TextXAlignment = Enum.TextXAlignment.Right}),
			"mode_capacity", z.cap)
	end
	for i, key in ipairs({"help_leave", "help_party"}) do
		local x = (i - 1) * 316
		title(page, key, x, 168, key)
		static(Kit.label(page, key .. "_text", px(x, 190), px(300, 110), 13, {TextYAlignment = Enum.TextYAlignment.Top}),
			key .. "_text")
	end
end

-- Top centre, under the Roblox top bar: the queue banner (or a hint), and the offer to return to the team
function Lobby:BuildTop()
	local top = Kit.scaled(Kit.frame(self.Gui, "Top", U(0.5, 0, 0, 62), px(440, 114)))
	top.AnchorPoint = Vector2.new(0.5, 0)
	self.Hint = Kit.panel(top, "Hint", px(40, 0), px(360, 30))
	self.HintText = Kit.label(self.Hint, "Text", px(10, 0), U(1, -20, 1, 0), 13, {TextColor3 = Kit.Amber, TextXAlignment = CENTER})
	local b = Kit.panel(top, "Banner", px(0, 0), px(440, 64))
	self.Banner = b
	self.Stripe = Kit.round(Kit.make("Frame", {Name = "Stripe", Position = px(7, 8), Size = px(5, 48)}, b), 3)
	self.QTitle = Kit.label(b, "Title", px(98, 7), px(232, 20), 16, {Font = BOLD})
	self.QStatus = Kit.label(b, "Status", px(98, 28), px(190, 30), 12)
	self.QCount = Kit.label(b, "Count", px(290, 22), px(40, 38), 34, {Font = BLACK, TextColor3 = Kit.Amber, TextXAlignment = CENTER})
	self.QLeave = static(Kit.button(b, "Leave", px(336, 15), px(96, 34), function() act("leave_queue") end,
		{tip = "tip_leave_queue", color = Kit.Red}), "queue_leave")
	self.QJoin = static(Kit.button(b, "Join", px(336, 15), px(96, 34), function()
		if snap and snap.queue then act("join", snap.queue.zone) end
	end, {tip = "tip_join_party", color = Kit.Teal}), "play_go")
	local r = Kit.panel(top, "Rejoin", px(0, 70), px(440, 44))
	self.Rejoin = r
	self.RejoinText = Kit.label(r, "Text", px(12, 4), px(280, 36), 13)
	self.Return = static(Kit.button(r, "Return", px(300, 7), px(132, 30), function() act("rejoin") end,
		{tip = "tip_rejoin", color = Kit.Teal}), "rejoin_button")
end

function Lobby:Build()
	self.Gui = Kit.make("ScreenGui", {Name = "GS_Lobby", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, player:WaitForChild("PlayerGui"))
	Kit.init(self.Gui)
	self:BuildDock()
	self:BuildTop()
	self:BuildWindow()
	-- invitation cards at the right edge, toasts at the bottom
	self.InviteCards = Kit.scaled(Kit.frame(self.Gui, "Invites", U(1, -10, 0, 62), px(250, 228)))
	self.InviteCards.AnchorPoint = Vector2.new(1, 0)
	self.Toasts = Kit.scaled(Kit.frame(self.Gui, "Toasts", U(0.5, 0, 1, -14), px(460, 132)))
	self.Toasts.AnchorPoint = Vector2.new(0.5, 1)
	self.Toasts.ZIndex = 6
	Kit.make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom}, self.Toasts)
end

function Lobby:Toast(text)
	if #toasts >= 3 then table.remove(toasts, 1).frame:Destroy() end
	self.ToastCount = (self.ToastCount or 0) + 1
	local t = {frame = Kit.panel(self.Toasts, "Toast", px(0, 0), U(1, 0, 0, 40)), text = text}
	t.frame.LayoutOrder = self.ToastCount
	Kit.label(t.frame, "Text", px(12, 3), U(1, -24, 1, -6), 14, {Text = text, TextXAlignment = CENTER})
	table.insert(toasts, t)
	task.delay(4, function()
		local i = table.find(toasts, t)
		if i then table.remove(toasts, i).frame:Destroy() end
	end)
end

-- The scale of the interface, and the place of the menu: centred under the top bar, below the banner when both fit
function Lobby:Fit()
	local view = self.Gui.AbsoluteSize
	local scale = math.clamp(math.min(view.X / 1280, view.Y / 720), 0.55, 1.3) * S.size
	Kit.setScale(scale)
	local height = 404 * scale
	local top = 62 + (self.TopHeight > 0 and self.TopHeight * scale + 6 or 0)
	local y = math.min(math.max((view.Y + 58 - height) / 2, top), view.Y - height - 6)
	self.Window.Position = U(0.5, 0, 0, math.max(62, y))
end

-- The lists of the Party tab and the invitation cards: rebuilt only when what they show has changed,
-- so a snapshot that arrives during a press does not take the button away
function Lobby:Party(my, invites)
	local others = snap and snap.players or {}
	self.PartyTitle.Text = T("party_title", my.size, my.max)
	self.LeaveParty.Visible = my.size > 1
	Kit.enable(self.LeaveParty, not my.launching, T("why_launching"))
	self.Friends.Visible = canInviteFriends
	local sig = {S.lang, my.leader, tostring(my.launching)}
	for _, m in ipairs(my.members) do table.insert(sig, m.id .. tostring(m.zone)) end
	for _, v in ipairs(invites) do table.insert(sig, "i" .. v.id .. tostring(v.size)) end
	for _, p in ipairs(others) do table.insert(sig, "p" .. p.id .. tostring(p.size) .. tostring(p.invited)) end
	sig = table.concat(sig, " ")
	if sig == self.PartySig then return end
	self.PartySig = sig

	Kit.clear(self.Members)
	for i, m in ipairs(my.members) do
		local r = row(self.Members, "M_" .. m.id, i, 36)
		local zone = ZONE[m.zone]
		local tags = {zone and T("tag_zone", T("mode_" .. zone.id)) or T("tag_no_zone")}
		if m.id == my.id then table.insert(tags, 1, T("tag_you")) end
		if m.id == my.leader then table.insert(tags, 1, T("tag_leader")) end
		Kit.label(r, "Name", px(10, 2), U(1, -92, 0, 18), 14, {Font = BOLD, Text = tostring(m.name)})
		Kit.label(r, "Tags", px(10, 19), U(1, -92, 0, 14), 11, {Text = table.concat(tags, ", "),
			TextColor3 = zone and zone.color or Kit.Amber})
		if my.leading and m.id ~= my.id then
			Kit.enable(Kit.button(r, "Kick", U(1, -74, 0.5, -13), px(66, 26), function() act("kick", m.id) end,
				{text = T("party_kick"), tip = "tip_kick", color = Kit.Red}), not my.launching, T("why_launching"))
		end
	end

	Kit.clear(self.InviteList)
	Kit.clear(self.InviteCards)
	for i, v in ipairs(invites) do
		local text = T("invite_text", tostring(v.name), v.size or 1)
		local r = row(self.InviteList, "I_" .. v.id, i, 30)
		Kit.label(r, "Text", px(10, 0), U(1, -146, 1, 0), 12, {Text = text})
		answers(r, v.id, 1, 2, 62).Parent.Decline.Position = U(1, -4, 0, 2)
		if i <= 3 then
			local card = Kit.panel(self.InviteCards, "I_" .. v.id, px(0, (i - 1) * 76), px(250, 70))
			Kit.label(card, "Text", px(10, 5), px(230, 30), 13, {Text = text})
			answers(card, v.id, 0, 38, 112)
		end
	end
	if #invites == 0 then
		Kit.label(self.InviteList, "Empty", px(0, 0), U(1, -8, 0, 24), 12, {Text = T("party_no_invites"), TextTransparency = 0.4})
	end
	self.InviteList.CanvasSize = px(0, #invites * 34)

	Kit.clear(self.Players)
	for i, p in ipairs(others) do
		local r = row(self.Players, "P_" .. p.id, i, 30)
		local size = p.size or 1
		local why = (size > 1 and T("why_in_party", size)) or (p.invited and T("why_invited"))
			or (not my.leading and T("why_not_leader")) or (my.size >= my.max and T("why_full"))
			or (my.launching and T("why_launching"))
		Kit.label(r, "Name", px(10, 0), U(1, -136, 1, 0), 13, {Text = tostring(p.name)})
		if why then
			Kit.label(r, "Why", U(1, -124, 0, 0), px(118, 30), 11, {Text = why, TextTransparency = 0.35,
				TextXAlignment = Enum.TextXAlignment.Right})
		else
			Kit.button(r, "Invite", U(1, -92, 0.5, -12), px(86, 24), function() act("invite", p.id) end,
				{text = T("party_invite"), color = Kit.Teal})
		end
	end
	if #others == 0 then
		Kit.label(self.Players, "Empty", px(0, 0), U(1, -8, 0, 24), 12, {Text = T("party_nobody"), TextTransparency = 0.4})
	end
	self.Players.CanvasSize = px(0, #others * 34)
end

function Lobby:Render()
	if not self.Window then return end
	for o, s in pairs(statics) do o.Text = T(s[1], s[2]) end
	local my = self:My()
	local invites = snap and snap.invites or {}
	local q = snap and snap.queue
	local zone = q and ZONE[q.zone]

	-- the menu, its tabs, the dock, the settings
	self.Window.Visible = S.open
	for _, name in ipairs(TABS) do
		local on = S.tab == name
		self.Pages[name].Visible = on
		self.Tabs[name].BackgroundColor3 = on and Kit.Grey or Kit.Slot
		self.Tabs[name].Mark.Enabled = on
	end
	for name, tile in pairs(self.Dock) do
		local on = S.open and (name == "Menu" or name == S.tab)
		tile.UIStroke.Color = on and Kit.Amber or Kit.Cream
		tile.UIStroke.Transparency = on and 0 or 0.8
	end
	self.Badge.Visible = #invites > 0
	self.Badge.Text = tostring(#invites)
	for _, seg in ipairs(self.Segments) do
		local on = S[seg.field] == seg.value
		seg.button.BackgroundColor3 = on and Kit.Amber or Kit.Grey
		seg.button.TextColor3 = on and Kit.Panel or Kit.Cream
	end

	-- the mode cards: go to the zone, or leave it; a party that does not fit is told why
	local byId = {}
	for _, z in ipairs(snap and snap.zones or {}) do byId[z.id] = z end
	for _, c in ipairs(self.Cards) do
		local z = c.zone
		local here = my.zone == z.id
		local why = (my.launching and T("why_launching")) or (not here and my.size > z.cap and T("why_too_big", my.size, z.cap))
		c.info = byId[z.id]
		c.action.Text = T(here and "queue_leave" or "play_go")
		c.action.BackgroundColor3 = here and Kit.Red or z.color
		c.action.TextColor3 = here and Kit.Cream or Kit.Panel
		Kit.enable(c.action, not why, why)
		c.why.Text = why or (here and T("play_here")) or ""
		c.panel.UIStroke.Color = here and z.color or Kit.Cream
		c.panel.UIStroke.Transparency = here and 0 or 0.8
	end

	-- top centre: the banner of my queue or a hint, and the way back to a team that still plays
	local back = snap and snap.rejoin
	self.Banner.Visible = zone ~= nil
	self.Hint.Visible = not zone and not S.open
	self.HintText.Text = T(my.launching and "queue_launching" or "hint_walk")
	self.Rejoin.Visible = back ~= nil
	local height = zone and 64 or (self.Hint.Visible and 30 or 0)
	self.Rejoin.Position = px(0, height > 0 and height + 6 or 0)
	self.TopHeight = back and self.Rejoin.Position.Y.Offset + 44 or height
	if back then
		self.RejoinText.Text = T("rejoin_text", tostring(back.hostName), T("mode_" .. tostring(back.format)))
		Kit.enable(self.Return, my.size == 1 and not my.launching, T(my.launching and "why_launching" or "lobby_err_leave_first"))
	end
	if zone then
		local have = q.have or 0
		self.Stripe.BackgroundColor3 = zone.color
		self.QTitle.TextColor3 = zone.color
		self.QTitle.Text = q.have and T("queue_title", T("mode_" .. zone.id), have, q.capacity or zone.cap) or T("mode_" .. zone.id)
		if self.PawnSig ~= zone.id .. have then
			self.PawnSig = zone.id .. have
			if self.QPawns then self.QPawns:Destroy() end
			self.QPawns = Icons.pawns(self.Banner, zone.cap, have, zone.color, 18)
			self.QPawns.Position = px(54, 32)
		end
		self.QLeave.Visible = my.zone ~= nil and q.state ~= "launching"
		self.QJoin.Visible = my.zone == nil and not my.launching
	end

	self:Party(my, invites)
	self:Fit()
	self:Tick(true)
end

-- One zone: the live line of its card and, in the world, the status of its sign, its standing places and its runes
function Lobby:Zone(c, now)
	local z, info = c.zone, c.info or {}
	local players = info.players or 0
	local seconds = info.countdown and left(info.ends, now)
	c.live.Text = (seconds and T("zone_countdown", seconds)) or (players > 0 and T("zone_waiting", players)) or T("zone_empty")
	local lobby = workspace:FindFirstChild("Lobby")
	local model = lobby and lobby:FindFirstChild("Zone_" .. z.id, true)
	if not model then return end
	local status = model:FindFirstChild("Status", true)
	if status and status:IsA("TextLabel") then
		status.Text = (seconds and T("zone_countdown", seconds)) or (players > 0 and T("zone_count", players, info.capacity or z.cap))
			or T("sign_empty")
	end
	local spots, runes = model:FindFirstChild("Spots"), model:FindFirstChild("Runes")
	for _, p in ipairs(spots and spots:GetChildren() or {}) do
		if p:IsA("BasePart") then
			local lit = (tonumber(string.match(p.Name, "%d+")) or 0) <= players
			p.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
			p.Color = lit and z.color or z.color:Lerp(Color3.new(0, 0, 0), 0.65)
		end
	end
	if seconds or pulsing[z.id] then
		pulsing[z.id] = seconds ~= nil or nil
		local color = seconds and z.color:Lerp(Kit.Amber, 0.5 + 0.5 * math.sin(now * 8)) or z.color
		for _, p in ipairs(runes and runes:GetChildren() or {}) do
			if p:IsA("BasePart") then p.Color = color end
		end
	end
end

-- Everything that depends on the clock, ten times a second: countdown numbers and the pulse of the runes.
-- `all`: also the zones that are not counting down (after a snapshot, and now and then for parts that arrive late)
function Lobby:Tick(all)
	local now = workspace:GetServerTimeNow()
	local q = snap and snap.queue
	if q and self.Banner.Visible then
		local state, text, count = q.state, "", nil
		if state == "countdown" then
			text, count = T("queue_countdown"), left(q.ends, now)
		elseif state == "waiting" then
			text = q.need == 1 and T("queue_waiting_one") or T("queue_waiting", q.need or 0)
		elseif state == "launching" then
			text = T("queue_launching")
		elseif state == "too_big" then
			text = T("why_too_big", self:My().size, q.capacity or 0)
		elseif state == "split" then
			text = T("queue_split", table.concat(q.missing or {}, ", "))
		elseif state == "cooldown" then
			text = T("queue_cooldown", left(q.retryAt, now))
		end
		self.QStatus.Text = text
		self.QStatus.Size = px(count and 190 or 232, 30)
		self.QCount.Visible = count ~= nil
		self.QCount.Text = tostring(count or "")
	end
	for _, c in ipairs(self.Cards) do
		if all or (c.info and c.info.countdown) or pulsing[c.zone.id] then self:Zone(c, now) end
	end
end

function Lobby:World()
	local lobby = workspace:FindFirstChild("Lobby")
	for _, d in ipairs(lobby and lobby:GetDescendants() or {}) do world(d) end
end

function Lobby:Start()
	if string.sub(player.LocaleId, 1, 2) == "ru" then S.lang = "ru" end
	self.TopHeight = 0
	Kit.T = T
	self:Build()
	Kit.hook(function()
		local texts = {}
		for i, t in ipairs(toasts) do texts[i] = t.text end
		return {open = S.open, tab = S.tab, lang = S.lang, size = S.size, lowDetail = S.lowDetail, labels = S.labels,
			queue = snap and snap.queue, toasts = texts}
	end)
	self:Render()
	self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:Fit() end)
	UserInputService.InputBegan:Connect(function(input, busy)
		if not busy and input.KeyCode == Enum.KeyCode.M then self:Open(not S.open) end
	end)
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby")
		lobby.DescendantAdded:Connect(world)
		self:World()
		self:Tick(true)
	end)
	task.spawn(function()
		local ok, can = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
		canInviteFriends = ok and can == true
		self:Render()
	end)
	Net.Event("LobbyState").OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" then
			snap = snapshot
			self:Render()
		end
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(key, ...)
		self:Toast(T(tostring(key), ...))
	end)
	act("refresh")
	local n, last = 0, nil
	while true do
		task.wait(0.1)
		n += 1
		local ok, err = pcall(self.Tick, self, n % 20 == 0)
		if not ok and err ~= last then
			last = err
			warn("[Lobby UI] " .. tostring(err))
		end
	end
end

return Lobby
