-- Parties in the lobby (milestone 9, design doc 2.1): players gather a party of 1, 2, 3 or 4 Guardians here and
-- only then go to the game. Every player always has a party; alone, it is a solo party that the player leads.
-- The leader becomes the host of the team in the game, and the shared progress is the host's team record
-- (decision 5).
-- Milestone 10: the party sets out from the Expedition Circle. The leader chooses a mode (Solo, Duo, Squad); the
-- party is ready when its size fits the mode and every member stands in the circle; then a short countdown runs,
-- which the leader can cancel, and the party is teleported together. The server format is the size of the party
-- when it sets out (design doc 2.2). The client sends intentions only; every rule, including who stands in the
-- circle, is checked here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Matchmaking = require(Shared.Modules.Matchmaking)
local PartyCfg = require(Shared.Config.Party)
local LobbyCfg = require(Shared.Config.Lobby)

local PartyService = {Priority = 80}
PartyService.Clock = os.clock -- tests move time by replacing this
local MatchService
local present = {} -- [player] = true: everyone in the lobby
local partyOf = {} -- [player] = party {leader, mode, members, launching, countdown}
local invites = {} -- [invitee] = {[leader] = expiresAt}
local rejoin = {}  -- [player] = the team session the player can go back to
local circle = {}  -- [player] = true: the player stands in the Expedition Circle
local queued = false

-- Tests use stand-in players (tables); they get no network messages
local function isReal(player)
	return typeof(player) == "Instance"
end

local function tell(player, key, ...)
	if isReal(player) and player.Parent then Net.Fire(player, "Notify", key, ...) end
end

local function refuse(player, reason)
	tell(player, "lobby_err_" .. reason)
	return false, reason
end

local function nameOf(player)
	return player.DisplayName or player.Name
end

local function soloParty(player)
	local party = {leader = player, mode = PartyCfg.Modes[1].id, members = {player}, launching = false, countdown = nil}
	partyOf[player] = party
	return party
end

function PartyService.Mode(id)
	for _, m in ipairs(PartyCfg.Modes) do
		if m.id == id then return m end
	end
	return nil
end

-- The mode a party of this size plays in
function PartyService.ModeOfSize(size)
	for _, m in ipairs(PartyCfg.Modes) do
		if size >= m.min and size <= m.max then return m end
	end
	return nil
end

function PartyService:Init()
	MatchService = Loader.Get("MatchService")
end

function PartyService:Get(player)
	return partyOf[player]
end

-- A player came into the lobby
function PartyService:Enter(player)
	if present[player] then return partyOf[player] end
	present[player] = true
	invites[player] = {}
	soloParty(player)
	self:Changed()
	return partyOf[player]
end

-- A player left the lobby: to the game or out of the experience
function PartyService:Exit(player)
	if not present[player] then return end
	self:Leave(player, true)
	present[player], partyOf[player], invites[player], rejoin[player], circle[player] = nil, nil, nil, nil, nil
	for _, set in pairs(invites) do set[player] = nil end
	self:Changed()
end

-- ===== The Expedition Circle =====

function PartyService:InCircle(player)
	return circle[player] == true
end

-- Tests place their stand-ins; real players are placed by UpdateCircle
function PartyService:SetInCircle(player, inside)
	circle[player] = inside and true or nil
	self:Changed()
end

-- Where the circle is: LobbyBuilder puts ExpeditionCircle.Zone into the lobby. nil when the lobby has none
function PartyService.CircleArea()
	local lobby = workspace:FindFirstChild("Lobby")
	local model = lobby and lobby:FindFirstChild("ExpeditionCircle")
	local zone = model and model:FindFirstChild("Zone")
	if not (zone and zone:IsA("BasePart")) then return nil end
	return zone.Position, (tonumber(model:GetAttribute("Radius")) or 13) + LobbyCfg.CircleMargin
end

function PartyService.IsInside(position, center, radius)
	local d = position - center
	return Vector3.new(d.X, 0, d.Z).Magnitude <= radius and math.abs(d.Y) <= 14
end

-- Who stands in the circle now. The server measures it; the client is not asked. Returns true when it changed.
-- A lobby without a circle does not hold anybody back: everyone counts as standing in it
function PartyService:UpdateCircle()
	local center, radius = PartyService.CircleArea()
	local changed = false
	for player in pairs(present) do
		if isReal(player) then
			local inside = center == nil
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if center and root then inside = PartyService.IsInside(root.Position, center, radius) end
			if (circle[player] == true) ~= inside then
				circle[player] = inside and true or nil
				changed = true
			end
		end
	end
	return changed
end

-- Can this party set out now? true, "ready" — or false, a reason and the numbers or the name its text needs
function PartyService:Readiness(party)
	local mode = PartyService.Mode(party.mode)
	local size = #party.members
	if size < mode.min then return false, "need_more", mode.min, mode.min - size end
	if size > mode.max then return false, "too_many" end
	if LobbyCfg.RequireCircle then
		for _, m in ipairs(party.members) do
			if not self:InCircle(m) then return false, "need_circle", nameOf(m) end
		end
	end
	return true, "ready"
end

-- The countdown of a party ends without a teleport; every member is told why
function PartyService:StopCountdown(party, key, ...)
	if not party.countdown then return false end
	party.countdown = nil
	for _, m in ipairs(party.members) do tell(m, key, ...) end
	self:Changed()
	return true
end

-- ===== The party =====

-- Leave the party. The leader is the host of the team, so a party without its leader is disbanded.
-- gone: the player is leaving the lobby and gets no party of their own
function PartyService:Leave(player, gone)
	local party = partyOf[player]
	if not party then return false, "unknown" end
	if party.launching and not gone then return refuse(player, "launching") end
	if #party.members == 1 then return false, "alone" end
	self:StopCountdown(party, "lobby_countdown_stopped")
	if party.launching then
		-- the party is on its way: its members leave the lobby one after another, nobody is told anything
		table.remove(party.members, table.find(party.members, player))
	elseif party.leader == player then
		for _, m in ipairs(party.members) do
			if m ~= player then
				soloParty(m)
				tell(m, "lobby_disbanded")
			end
		end
	else
		table.remove(party.members, table.find(party.members, player))
		for _, m in ipairs(party.members) do tell(m, "lobby_left", nameOf(player)) end
	end
	if not gone then soloParty(player) end
	self:Changed()
	return true
end

-- The leader chooses the mode: Solo, Duo or Squad
function PartyService:SetMode(player, modeId)
	local party, mode = partyOf[player], PartyService.Mode(modeId)
	if not (party and mode) then return false, "unknown" end
	if party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if party.countdown then return refuse(player, "countdown") end
	if #party.members > mode.max then return refuse(player, "too_many") end
	party.mode = mode.id
	self:Changed()
	return true
end

function PartyService:Invite(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if party.countdown then return refuse(player, "countdown") end
	if not target or target == player or not present[target] then return refuse(player, "unknown") end
	local mode = PartyService.Mode(party.mode)
	if mode.max == 1 then return refuse(player, "solo") end
	if #party.members >= mode.max then return refuse(player, "full") end
	if #partyOf[target].members > 1 then return refuse(player, "busy") end
	local now, waiting = PartyService.Clock(), 0
	for _, set in pairs(invites) do
		if set[player] and set[player] > now then waiting += 1 end
	end
	if waiting >= LobbyCfg.InvitesPerParty then return refuse(player, "too_many_invites") end
	invites[target][player] = now + LobbyCfg.InviteSeconds
	tell(target, "lobby_invited", nameOf(player))
	self:Changed()
	return true
end

-- The invited player accepts or declines the invitation of this leader
function PartyService:Answer(player, leader, accept)
	local set = invites[player]
	local expires = set and leader and set[leader]
	if not expires then return refuse(player, "expired") end
	local party = partyOf[leader]
	if not accept then
		set[leader] = nil
		tell(leader, "lobby_declined", nameOf(player))
		self:Changed()
		return true, "declined"
	end
	if expires <= PartyService.Clock() or not party or party.leader ~= leader then
		set[leader] = nil
		self:Changed()
		return refuse(player, "expired")
	end
	if party.launching then return refuse(player, "launching") end
	if #party.members >= PartyService.Mode(party.mode).max then return refuse(player, "full") end
	if #partyOf[player].members > 1 then return refuse(player, "leave_first") end
	invites[player] = {}
	for _, other in pairs(invites) do other[player] = nil end -- what the player sent as the leader of their own party
	self:StopCountdown(party, "lobby_countdown_stopped") -- the party changes: nobody leaves without having seen it
	for _, m in ipairs(party.members) do tell(m, "lobby_joined", nameOf(player)) end
	partyOf[player] = party
	table.insert(party.members, player)
	self:Changed()
	return true, "joined"
end

function PartyService:Kick(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if not target or target == player or partyOf[target] ~= party then return refuse(player, "unknown") end
	self:StopCountdown(party, "lobby_countdown_stopped")
	table.remove(party.members, table.find(party.members, target))
	soloParty(target)
	tell(target, "lobby_kicked")
	self:Changed()
	return true
end

-- The party did not leave after all. If its leader has already gone, the others get parties of their own
function PartyService:Unlock(player, key)
	local party = partyOf[player]
	if not (party and party.launching) then return false end
	party.launching = false
	local keep = present[party.leader] and partyOf[party.leader] == party
	for _, m in ipairs(table.clone(party.members)) do
		if not keep then soloParty(m) end
		tell(m, key)
	end
	self:Changed()
	return true
end

-- ===== Setting out =====

-- The leader asks to set out. A ready party gets its countdown; otherwise the leader is told what is missing
function PartyService:SetOut(player)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if party.countdown then return refuse(player, "countdown") end
	local ok, code, a, b = self:Readiness(party)
	if not ok then
		tell(player, "lobby_status_" .. code, a, b)
		return false, code
	end
	if LobbyCfg.CountdownSeconds <= 0 then return self:Launch(party) end
	party.countdown = PartyService.Clock() + LobbyCfg.CountdownSeconds
	self:Changed()
	return true, "countdown"
end

-- The leader calls the countdown off
function PartyService:CancelCountdown(player)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if not party.countdown then return false, "no_countdown" end
	self:StopCountdown(party, "lobby_countdown_cancelled")
	return true
end

-- The countdown ran out: the party goes to a game server of the format its size has now
function PartyService:Launch(party)
	local leader = party.leader
	local format = Matchmaking.FormatBySize(PartyCfg.Formats, #party.members)
	party.countdown = nil
	if not format then return false, "format" end
	party.launching = true
	self:Changed()
	local ok, reason = MatchService:Launch(table.clone(party.members), leader, format)
	if not ok then
		self:Unlock(leader, "lobby_launch_failed")
		return false, reason
	end
	-- the members leave the lobby one by one; whoever is still here after a while gets the party back
	task.delay(LobbyCfg.LaunchLockSeconds, function()
		for _, m in ipairs(party.members) do
			if present[m] and partyOf[m] == party then
				self:Unlock(m, "lobby_launch_failed")
				break
			end
		end
	end)
	return true, "launched"
end

-- One step of the lobby: old invitations go away, the circle is measured, countdowns stop or run out.
-- now is passed in so that tests can move time themselves; sync makes a launch finish inside the step
function PartyService:Step(now, sync)
	local changed = false
	for invitee, set in pairs(invites) do
		for leader, expires in pairs(set) do
			if expires <= now then
				set[leader] = nil
				changed = true
				tell(leader, "lobby_invite_expired", nameOf(invitee))
			end
		end
	end
	if self:UpdateCircle() then changed = true end
	local seen = {}
	for _, party in pairs(partyOf) do
		if party.countdown and not seen[party] then
			seen[party] = true
			local ok, code, a, b = self:Readiness(party)
			if not ok then
				-- somebody stepped out of the circle: nobody is teleported without the whole party
				party.countdown = nil
				changed = true
				for _, m in ipairs(party.members) do
					tell(m, "lobby_countdown_stopped")
					tell(m, "lobby_status_" .. code, a, b)
				end
			elseif now >= party.countdown then
				if sync then
					self:Launch(party)
				else
					task.spawn(self.Launch, self, party)
				end
			end
		end
	end
	if changed then self:Changed() end
end

-- MatchService found the team this player was playing with: it is still on a game server
function PartyService:OfferRejoin(player, session)
	if not present[player] then return end
	rejoin[player] = session
	self:Changed()
end

function PartyService:Rejoin(player)
	local party = partyOf[player]
	if not (party and rejoin[player]) then return false, "gone" end
	if #party.members > 1 then return refuse(player, "leave_first") end
	if party.launching then return refuse(player, "launching") end
	if party.countdown then return refuse(player, "countdown") end
	party.launching = true
	self:Changed()
	local ok, reason = MatchService:Rejoin(player)
	if not ok then
		party.launching = false
		if reason == "gone" then
			rejoin[player] = nil
			tell(player, "lobby_rejoin_gone")
		else
			tell(player, "lobby_launch_failed")
		end
		self:Changed()
	end
	return ok, reason
end

-- What one player sees: their party and whether it is ready, the invitations they got and the others in the lobby
function PartyService:Snapshot(player)
	local party = partyOf[player]
	if not party then return nil end
	local now = PartyService.Clock()
	local mode = PartyService.Mode(party.mode)
	local members = {}
	for i, m in ipairs(party.members) do
		members[i] = {id = m.UserId, name = nameOf(m), inCircle = self:InCircle(m)}
	end
	local got = {}
	for leader, expires in pairs(invites[player] or {}) do
		if expires > now and partyOf[leader] then
			table.insert(got, {id = leader.UserId, name = nameOf(leader), mode = partyOf[leader].mode})
		end
	end
	table.sort(got, function(a, b) return a.id < b.id end)
	local others = {}
	for other in pairs(present) do
		if other ~= player and partyOf[other] ~= party then
			table.insert(others, {
				id = other.UserId, name = nameOf(other), size = #partyOf[other].members,
				invited = (invites[other][player] or 0) > now,
			})
		end
	end
	table.sort(others, function(a, b) return a.id < b.id end)
	local ready, code, a, b = self:Readiness(party)
	local session = rejoin[player]
	return {
		party = {
			leader = party.leader.UserId, mode = party.mode, min = mode.min, max = mode.max, members = members,
			launching = party.launching, ready = ready, status = {"lobby_status_" .. code, a, b},
			-- on the clock every client shares with the server
			countdownEnds = party.countdown and (workspace:GetServerTimeNow() + (party.countdown - now)) or nil,
		},
		inCircle = self:InCircle(player),
		invites = got,
		players = others,
		rejoin = session and {hostName = tostring(session.hostName or session.host), format = session.format} or nil,
	}
end

-- Send everyone their view of the lobby, at most once a frame
function PartyService:Changed()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		for player in pairs(present) do
			if isReal(player) and player.Parent then Net.Fire(player, "LobbyState", self:Snapshot(player)) end
		end
	end)
end

function PartyService:Start()
	local function entered(player)
		self:Enter(player)
		MatchService:Greet(player)
	end
	Players.PlayerAdded:Connect(entered)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(entered, p) end
	Players.PlayerRemoving:Connect(function(player) self:Exit(player) end)

	local function byId(id)
		return Players:GetPlayerByUserId(tonumber(id) or 0)
	end
	Net.On("LobbyAction", 6, function(player, action, a)
		if not present[player] then return end
		if action == "mode" then
			self:SetMode(player, a)
		elseif action == "invite" then
			self:Invite(player, byId(a))
		elseif action == "accept" or action == "decline" then
			self:Answer(player, byId(a), action == "accept")
		elseif action == "leave" then
			self:Leave(player)
		elseif action == "kick" then
			self:Kick(player, byId(a))
		elseif action == "start" then
			self:SetOut(player)
		elseif action == "cancel" then
			self:CancelCountdown(player)
		elseif action == "rejoin" then
			self:Rejoin(player)
		elseif action == "refresh" then
			Net.Fire(player, "LobbyState", self:Snapshot(player))
		end
	end)

	while true do
		task.wait(LobbyCfg.StepSeconds)
		local ok, err = pcall(self.Step, self, PartyService.Clock())
		if not ok then warn("[Lobby] step: " .. tostring(err)) end
	end
end

return PartyService
