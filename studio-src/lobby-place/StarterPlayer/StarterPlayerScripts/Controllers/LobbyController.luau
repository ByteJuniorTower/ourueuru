-- The lobby on the client (milestone 9, design doc 2.1; milestone 10: the Expedition Circle).
-- A party line is always on the screen. When the player stands in the Expedition Circle, the expedition panel
-- opens: the mode (Solo, Duo, Squad), the party with its leader, invitations, what is missing and the "Set out"
-- button; then the countdown, which the leader can cancel. It shows what the server sent and sends the player's
-- intentions back; it decides nothing itself. Interface built in code until the Figma layouts exist.
-- The language is English by default and Russian by choice (decision 6); in the lobby the choice lasts for the visit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local PartyCfg = require(Shared.Config.Party)

local Lobby = {Priority = 50}
local player = Players.LocalPlayer
local lang = Locale.Default
local state = nil         -- the last LobbyState from the server
local friends = {}        -- [userId] = true or false, once Roblox has answered
local canInviteFriends = false
local runesLit = nil

local DARK = Color3.fromRGB(24, 30, 27)
local SLOT = Color3.fromRGB(38, 46, 42)
local GREEN = Color3.fromRGB(70, 150, 90)
local GREY = Color3.fromRGB(62, 66, 64)
local RED = Color3.fromRGB(150, 70, 62)
local AMBER = Color3.fromRGB(255, 214, 120)
local CREAM = Color3.fromRGB(255, 244, 214)
local TEAL = Color3.fromRGB(120, 230, 200)
local Y = Enum.AutomaticSize.Y

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function list(parent, padding, horizontal)
	return make("UIListLayout", {Padding = UDim.new(0, padding or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical}, parent)
end

local function corner(parent, radius)
	return make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, parent)
end

local function panel(props, parent)
	local f = make("Frame", props, parent)
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 0.1
	corner(f, 12)
	make("UIStroke", {Color = CREAM, Transparency = 0.82, Thickness = 1}, f)
	make("UIPadding", {PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)}, f)
	list(f, 8)
	return f
end

local function label(text, parent, props)
	local l = make("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y,
		BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = text}, parent)
	if props then for k, v in pairs(props) do l[k] = v end end
	return l
end

local function button(text, parent, props)
	local b = make("TextButton", {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = GREY, AutoButtonColor = true,
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 15, Text = text}, parent)
	if props then for k, v in pairs(props) do b[k] = v end end
	corner(b, 8)
	return b
end

local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

local function T(key, ...)
	return Locale.T(lang, key, ...)
end

local function act(action, a)
	Net.Event("LobbyAction"):FireServer(action, a)
end

-- Roblox is asked once about every Guardian in the lobby; friends are listed first
local function checkFriend(id)
	if friends[id] ~= nil or id <= 0 then return end
	friends[id] = false
	task.spawn(function()
		local ok, res = pcall(function() return player:IsFriendsWith(id) end)
		if ok and res == true then
			friends[id] = true
			Lobby:Render()
		end
	end)
end

function Lobby:Build()
	local gui = make("ScreenGui", {Name = "GS_Lobby", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling},
		player:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Scale = make("UIScale", {}, gui)

	-- the right-hand column: the party line, invitations, the expedition panel
	local column = make("Frame", {Name = "Column", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(400, 0), AutomaticSize = Y, BackgroundTransparency = 1}, gui)
	list(column, 10)

	local hud = panel({Name = "Hud", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, LayoutOrder = 1}, column)
	self.HudTitle = label("", hud, {Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, LayoutOrder = 1})
	self.HudParty = label("", hud, {LayoutOrder = 2})
	self.HudHint = label("", hud, {Name = "Hint", TextColor3 = AMBER, LayoutOrder = 3})
	self.RejoinLabel = label("", hud, {Name = "RejoinText", LayoutOrder = 4})
	self.RejoinButton = button("", hud, {Name = "Rejoin", BackgroundColor3 = GREEN, LayoutOrder = 5})
	self.RejoinButton.Activated:Connect(function() act("rejoin") end)
	local langs = make("Frame", {Name = "Languages", Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 6}, hud)
	list(langs, 6, true)
	self.LangButtons = {}
	for i, code in ipairs(Locale.Languages) do
		local b = button(code == "ru" and "Русский" or "English", langs, {Name = code, Size = UDim2.new(0.5, -3, 1, 0),
			TextSize = 13, Font = Enum.Font.GothamMedium, LayoutOrder = i})
		b.Activated:Connect(function()
			lang = code
			self:Render()
			self:World()
		end)
		self.LangButtons[code] = b
	end

	self.Invites = make("Frame", {Name = "Invites", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y,
		BackgroundTransparency = 1, LayoutOrder = 2}, column)
	list(self.Invites, 8)

	-- the expedition panel: only while the player stands in the Expedition Circle
	local exp = panel({Name = "Expedition", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, LayoutOrder = 3, Visible = false}, column)
	self.Expedition = exp
	self.ExpTitle = label("", exp, {Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = CREAM, LayoutOrder = 1})
	self.ExpLeader = label("", exp, {Name = "Leader", TextColor3 = AMBER, LayoutOrder = 2})
	self.ModeLabel = label("", exp, {Font = Enum.Font.GothamBold, LayoutOrder = 3})
	local modes = make("Frame", {Name = "Modes", Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, LayoutOrder = 4}, exp)
	list(modes, 6, true)
	self.ModeButtons = {}
	for i, mode in ipairs(PartyCfg.Modes) do
		local b = button("", modes, {Name = mode.id, Size = UDim2.new(1 / #PartyCfg.Modes, -4, 1, 0), LayoutOrder = i,
			RichText = true, TextSize = 16})
		make("UIStroke", {Name = "Ring", Color = AMBER, Thickness = 2, Enabled = false,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
		b.Activated:Connect(function()
			local s = state
			if s and s.party.leader == player.UserId then act("mode", mode.id) end
		end)
		self.ModeButtons[mode.id] = b
	end
	self.ModeLocked = label("", exp, {Name = "ModeLocked", TextTransparency = 0.3, TextSize = 13, LayoutOrder = 5})
	self.PartyLabel = label("", exp, {Font = Enum.Font.GothamBold, LayoutOrder = 6})
	self.Members = make("Frame", {Name = "Members", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y,
		BackgroundTransparency = 1, LayoutOrder = 7}, exp)
	list(self.Members, 4)
	self.InviteLabel = label("", exp, {Font = Enum.Font.GothamBold, LayoutOrder = 8})
	self.InviteNote = label("", exp, {Name = "InviteNote", TextTransparency = 0.3, TextSize = 13, LayoutOrder = 9})
	self.PlayerList = make("ScrollingFrame", {Name = "Players", Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Y, LayoutOrder = 10}, exp)
	list(self.PlayerList, 4)
	self.FriendsButton = button("", exp, {Name = "InviteFriends", LayoutOrder = 11})
	self.FriendsButton.Activated:Connect(function()
		pcall(function() SocialService:PromptGameInvite(player) end)
	end)
	self.FriendsNote = label("", exp, {Name = "FriendsNote", TextTransparency = 0.4, TextSize = 12, LayoutOrder = 12})
	self.Status = label("", exp, {Name = "Status", Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 13})
	self.StartButton = button("", exp, {Name = "Start", BackgroundColor3 = GREEN, Size = UDim2.new(1, 0, 0, 46),
		TextSize = 19, LayoutOrder = 14})
	self.StartButton.Activated:Connect(function() act("start") end)
	self.LeaveButton = button("", exp, {Name = "Leave", LayoutOrder = 15, Font = Enum.Font.GothamMedium})
	self.LeaveButton.Activated:Connect(function() act("leave") end)

	-- the countdown, in the middle of the screen
	local count = panel({Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.16, 0),
		Size = UDim2.fromOffset(380, 0), AutomaticSize = Y, Visible = false}, gui)
	self.Countdown = count
	self.CountNumber = label("", count, {Font = Enum.Font.GothamBlack, TextSize = 64, TextColor3 = AMBER,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1})
	self.CountTitle = label("", count, {Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2})
	self.CountSub = label("", count, {TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.2, LayoutOrder = 3})
	self.CancelButton = button("", count, {Name = "Cancel", BackgroundColor3 = RED, Size = UDim2.new(1, 0, 0, 44),
		TextSize = 17, LayoutOrder = 4})
	self.CancelButton.Activated:Connect(function() act("cancel") end)
	self.CancelNote = label("", count, {TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.35, TextSize = 13, LayoutOrder = 5})

	self.Toasts = make("Frame", {Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 0), AutomaticSize = Y, BackgroundTransparency = 1}, gui)
	list(self.Toasts, 6)
end

function Lobby:Toast(text)
	local l = label(text, self.Toasts, {TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.15,
		BackgroundColor3 = DARK, TextSize = 16})
	corner(l, 8)
	make("UIPadding", {PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, l)
	task.delay(5, function() l:Destroy() end)
end

-- One seat of the party: portrait, name, tags, where the Guardian stands, and "Remove" for the leader
function Lobby:MemberRow(order, member, party, leading, free)
	local me = player.UserId
	local f = make("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = SLOT, BackgroundTransparency = member and 0 or 0.5,
		LayoutOrder = order}, self.Members)
	corner(f, 8)
	if not member then
		local optional = order > party.min
		label(T(optional and "slot_optional" or "slot_empty"), f, {Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextTransparency = 0.5})
		return
	end
	if member.id > 0 then
		local face = make("ImageLabel", {Name = "Face", Position = UDim2.new(0, 6, 0.5, -16), Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = DARK, Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", member.id)}, f)
		corner(face, 16)
	end
	local tags = {}
	if member.id == party.leader then table.insert(tags, "★ " .. T("tag_leader")) end
	if member.id == me then table.insert(tags, T("tag_you")) end
	if friends[member.id] then table.insert(tags, T("tag_friend")) end
	label(member.name, f, {Name = "Name", Position = UDim2.new(0, 46, 0, 4), Size = UDim2.new(1, -150, 0, 18),
		AutomaticSize = Enum.AutomaticSize.None, Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false})
	label(table.concat(tags, " · "), f, {Name = "Tags", Position = UDim2.new(0, 46, 0, 23), Size = UDim2.new(1, -150, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextSize = 12, TextColor3 = AMBER, TextWrapped = false})
	if leading and free and member.id ~= me then
		local kick = button(T("lobby_kick"), f, {Name = "Kick", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(88, 30), BackgroundColor3 = RED, TextSize = 13})
		kick.Activated:Connect(function() act("kick", member.id) end)
	else
		label((member.inCircle and "● " or "○ ") .. T(member.inCircle and "circle_in" or "circle_out"), f, {Name = "Circle",
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 120, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = member.inCircle and TEAL or AMBER, TextWrapped = false})
	end
end

function Lobby:Render()
	if not self.Gui then return end
	for code, b in pairs(self.LangButtons) do
		b.BackgroundColor3 = code == lang and GREEN or GREY
	end
	self.HudTitle.Text = T("lobby_title")
	local s = state
	if not s then return end
	local party = s.party
	local me = player.UserId
	local leading = party.leader == me
	local counting = party.countdownEnds ~= nil
	local free = not party.launching and not counting
	local size = #party.members
	local leaderName = "?"
	for _, m in ipairs(party.members) do
		if m.id == party.leader then leaderName = m.name end
		checkFriend(m.id)
	end

	-- the party line
	self.HudParty.Text = T("hud_party", T("mode_" .. party.mode), size, party.max) .. "\n"
		.. (leading and T("hud_lead_you") or T("hud_lead_other", leaderName))
	self.HudHint.Text = party.launching and T("lobby_launching") or T("hud_hint_circle")
	self.HudHint.Visible = party.launching or not s.inCircle
	local back = s.rejoin
	self.RejoinLabel.Visible = back ~= nil and free
	self.RejoinButton.Visible = back ~= nil and free and size == 1
	if back then
		self.RejoinLabel.Text = T("lobby_rejoin", back.hostName, T("format_" .. tostring(back.format)))
		self.RejoinButton.Text = T("lobby_rejoin_button")
	end

	-- invitations can be answered anywhere in the lobby
	clear(self.Invites)
	for i, inv in ipairs(s.invites) do
		local card = panel({Name = "Invite", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, LayoutOrder = i}, self.Invites)
		label(T("invite_card", inv.name, T("mode_" .. tostring(inv.mode))), card, {Font = Enum.Font.GothamBold, LayoutOrder = 1})
		local answers = make("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 2}, card)
		list(answers, 8, true)
		local yes = button(T("lobby_accept"), answers, {Name = "Accept", Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = GREEN, LayoutOrder = 1})
		yes.Activated:Connect(function() act("accept", inv.id) end)
		local no = button(T("lobby_decline"), answers, {Name = "Decline", Size = UDim2.new(0.5, -4, 1, 0), LayoutOrder = 2})
		no.Activated:Connect(function() act("decline", inv.id) end)
	end

	-- the expedition panel
	self.Expedition.Visible = s.inCircle and not party.launching
	self.ExpTitle.Text = T("exp_title")
	self.ExpLeader.Text = leading and ("★ " .. T("exp_leader_you")) or ("★ " .. T("exp_leader_other", leaderName))
	self.ModeLabel.Text = T("exp_mode")
	for id, b in pairs(self.ModeButtons) do
		local chosen = id == party.mode
		b.Text = string.format("<b>%s</b>\n<font size=\"12\">%s</font>", T("mode_" .. id), T("mode_" .. id .. "_sub"))
		b.BackgroundColor3 = chosen and GREEN or GREY
		b.Ring.Enabled = chosen
		b.Active = leading and free
		b.AutoButtonColor = leading and free
		b.TextTransparency = (leading and free or chosen) and 0 or 0.5
	end
	self.ModeLocked.Text = T("mode_locked")
	self.ModeLocked.Visible = not leading
	self.PartyLabel.Text = T("exp_party", size, party.max)
	clear(self.Members)
	for i = 1, party.max do
		self:MemberRow(i, party.members[i], party, leading, free)
	end

	-- inviting: the leader, while there is a seat
	local seats = party.max - size
	local inviting = leading and free
	self.InviteLabel.Visible = inviting
	self.InviteLabel.Text = T("exp_invite_title")
	self.InviteNote.Visible = inviting and seats <= 0
	self.InviteNote.Text = T(party.max == 1 and "exp_invite_solo" or "exp_invite_full")
	self.PlayerList.Visible = inviting and seats > 0
	clear(self.PlayerList)
	if inviting and seats > 0 then
		local others = table.clone(s.players)
		for _, other in ipairs(others) do checkFriend(other.id) end
		table.sort(others, function(a, b)
			local fa, fb = friends[a.id] == true, friends[b.id] == true
			if fa ~= fb then return fa end
			return a.id < b.id
		end)
		if #others == 0 then
			label(T("lobby_nobody"), self.PlayerList, {TextTransparency = 0.5, LayoutOrder = 1})
		end
		for i, other in ipairs(others) do
			local f = make("Frame", {Size = UDim2.new(1, -6, 0, 34), BackgroundTransparency = 1, LayoutOrder = i}, self.PlayerList)
			label(other.name .. (friends[other.id] and ("  ♥ " .. T("tag_friend")) or ""), f, {Size = UDim2.new(1, -116, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false})
			if other.size > 1 or other.invited then
				label(T(other.size > 1 and "lobby_in_party" or "lobby_invite_sent"), f, {AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 110, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.5})
			else
				local b = button(T("lobby_invite"), f, {Name = "Invite", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0, 110, 1, 0), BackgroundColor3 = GREEN})
				b.Activated:Connect(function() act("invite", other.id) end)
			end
		end
	end
	self.FriendsButton.Visible = inviting and seats > 0 and canInviteFriends
	self.FriendsButton.Text = T("exp_invite_friends")
	self.FriendsNote.Visible = inviting and seats > 0 and not canInviteFriends
	self.FriendsNote.Text = T("exp_invite_friends_off")

	-- what is missing, and the way out
	self.Status.Text = T(party.status[1], party.status[2], party.status[3])
	self.Status.TextColor3 = party.ready and TEAL or AMBER
	self.StartButton.Visible = leading and free
	self.StartButton.Text = T("exp_start")
	self.StartButton.BackgroundColor3 = party.ready and GREEN or GREY
	self.StartButton.TextTransparency = party.ready and 0 or 0.4
	self.LeaveButton.Visible = size > 1 and free
	self.LeaveButton.Text = T("lobby_leave")
	if not leading then self.Status.Text = self.Status.Text .. "\n" .. T("exp_start_wait") end

	-- the countdown
	self.Countdown.Visible = counting and not party.launching
	self.CountSub.Text = T("countdown_sub")
	self.CancelButton.Visible = leading
	self.CancelButton.Text = T("countdown_cancel")
	self.CancelNote.Visible = not leading
	self.CancelNote.Text = T("countdown_leader_can")
	self:Tick()
	if runesLit ~= counting then
		runesLit = counting
		self:Runes(counting)
	end
end

-- The number of the countdown, on the clock shared with the server
function Lobby:Tick()
	local ends = state and state.party.countdownEnds
	if not ends then return end
	local left = math.max(0, math.ceil(ends - workspace:GetServerTimeNow()))
	self.CountNumber.Text = tostring(left)
	self.CountTitle.Text = T("countdown_title", left)
end

-- The runes of the Expedition Circle glow amber while this player's party counts down
function Lobby:Runes(counting)
	local lobby = workspace:FindFirstChild("Lobby")
	local circle = lobby and lobby:FindFirstChild("ExpeditionCircle")
	local runes = circle and circle:FindFirstChild("Runes")
	for _, p in ipairs(runes and runes:GetDescendants() or {}) do
		if p:IsA("BasePart") then p.Color = counting and AMBER or TEAL end
	end
end

-- Signs of the lobby speak the player's language: LobbyBuilder marks them with the attribute LocaleKey
function Lobby:World()
	local lobby = workspace:FindFirstChild("Lobby")
	for _, d in ipairs(lobby and lobby:GetDescendants() or {}) do
		local key = d:GetAttribute("LocaleKey")
		if key then
			if d:IsA("TextLabel") then
				d.Text = T(key)
			else
				local text = d:FindFirstChild("Text", true)
				if text and text:IsA("TextLabel") then text.Text = T(key) end
			end
		end
	end
end

function Lobby:Start()
	self:Build()
	-- the lobby lists its Guardians itself
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
	local camera = workspace.CurrentCamera
	local function fit()
		self.Scale.Scale = math.clamp(camera.ViewportSize.Y / 860, 0.5, 1)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
	Net.Event("LobbyState").OnClientEvent:Connect(function(snapshot)
		state = snapshot
		self:Render()
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(key, ...)
		self:Toast(T(key, ...))
	end)
	task.spawn(function()
		local ok, res = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
		canInviteFriends = ok and res == true
		self:Render()
	end)
	self:Render()
	self:World()
	act("refresh")
	local n = 0
	while true do
		task.wait(0.1)
		self:Tick()
		n += 1
		if n % 50 == 0 then self:World() end -- parts of the lobby may arrive later
	end
end

return Lobby
