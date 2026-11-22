-- Parties and the matchmaking zones of the lobby (milestones 9 and 10, design doc 2.1 and 2.2).
-- Every player always has a party; alone, it is a party of one that the player leads. The leader becomes the
-- host of the team in the game, and the shared progress is the host's team record (decision 5).
-- Milestone 10: nobody chooses a mode, the zone decides. A party is a unit; it is queued when all its members
-- stand in one zone and it is not larger than the capacity of that zone. In each zone the queued units are put
-- together in order of arrival; a group that fills the capacity exactly counts down and is teleported together
-- to a server of the zone's format. The client sends intentions only; every rule is checked here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local PartyCfg = require(Shared.Config.Party)
local LobbyCfg = require(Shared.Config.Lobby)

local PartyService = {Priority = 80}
PartyService.Clock = os.clock -- tests move time by replacing this
local MatchService
local present = {} -- [player] = true: everyone in the lobby
local partyOf = {} -- [player] = party {leader, members, launching, n, zone, queuedAt, order, group, have, cooldown}
local invites = {} -- [invitee] = {[leader] = expiresAt}
local rejoin = {}  -- [player] = the team session the player can go back to
local zoneOf = {}  -- [player] = id of the zone the player stands in
local groups = {}  -- full groups that count down: {zone, units, size, ends}
local serial, order = 0, 0
local zoneFolder, zoneList
local pending = false

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
	serial += 1
	local party = {leader = player, members = {player}, launching = false, n = serial}
	partyOf[player] = party
	return party
end

-- Distance on the ground
local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The root part of a real player's living character, or nil
local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") or nil
end

-- Put the character 3 studs above a point. false when there is no living character or no point
local function place(player, position)
	if not (position and rootOf(player)) then return false end
	player.Character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	return true
end

function PartyService:Init()
	MatchService = Loader.Get("MatchService")
end

function PartyService:Get(player)
	return partyOf[player]
end

-- ===== The zones =====

function PartyService.Format(id)
	for _, f in ipairs(PartyCfg.Formats) do
		if f.id == id then return f end
	end
	return nil
end

-- The zones in their order: {id, capacity, center, radius, exit, spots}. Ids and capacities come from the
-- config; the places are read from workspace.Lobby.Zones (LobbyBuilder) and are nil while the lobby is not built
function PartyService.Zones()
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Zones")
	if zoneList and folder == zoneFolder then return zoneList end
	zoneFolder, zoneList = folder, {}
	for i, cfg in ipairs(LobbyCfg.Zones) do
		local zone = {id = cfg.id, capacity = PartyService.Format(cfg.id).size, spots = {}}
		local model = folder and folder:FindFirstChild("Zone_" .. cfg.id)
		local pad = model and model:FindFirstChild("Zone")
		if pad then
			local exit, spots = model:FindFirstChild("Exit"), model:FindFirstChild("Spots")
			zone.center, zone.radius = pad.Position, tonumber(model:GetAttribute("Radius")) or 0
			zone.exit = exit and exit.Position or zone.center + Vector3.new(0, 0, zone.radius + 6)
			for n = 1, zone.capacity do
				local spot = spots and spots:FindFirstChild("Spot_" .. n)
				if spot then table.insert(zone.spots, spot.Position) end
			end
		end
		zoneList[i] = zone
	end
	return zoneList
end

local function zoneInfo(id)
	for _, zone in ipairs(PartyService.Zones()) do
		if zone.id == id then return zone end
	end
	return nil
end

-- The zone this point is in: on the pad or ZoneMargin around it, and not far above or below its floor
function PartyService.ZoneAt(position)
	for _, zone in ipairs(PartyService.Zones()) do
		if zone.center and flat(position, zone.center) <= zone.radius + LobbyCfg.ZoneMargin
			and math.abs(position.Y - zone.center.Y) <= LobbyCfg.ZoneHeight then
			return zone.id
		end
	end
	return nil
end

function PartyService:ZoneOf(player)
	return zoneOf[player]
end

-- Who stands in which zone now. The server measures it; the client is not asked. Returns true when it changed.
-- A player without a living character is in no zone
function PartyService:UpdateZones()
	local changed = false
	for player in pairs(present) do
		if isReal(player) then
			local root = rootOf(player)
			local id = root and PartyService.ZoneAt(root.Position) or nil
			if zoneOf[player] ~= id then
				zoneOf[player], changed = id, true
			end
		end
	end
	return changed
end

-- ===== The queue =====

-- How a party stands to the queue: the zone it is at (the viewer's own first), the state the client shows and
-- the names of the members who are not in that zone. nil when nobody of the party stands in a zone
local function status(party, viewer)
	local id, missing = viewer and zoneOf[viewer], {}
	for _, m in ipairs(party.members) do id = id or zoneOf[m] end
	if not id then return nil end
	for _, m in ipairs(party.members) do
		if zoneOf[m] ~= id then table.insert(missing, nameOf(m)) end
	end
	local state = party.launching and "launching"
		or #party.members > zoneInfo(id).capacity and "too_big"
		or #missing > 0 and "split"
		or party.cooldown and "cooldown"
		or party.group and "countdown" or "waiting"
	return id, state, missing
end

-- A group is no more: its countdown stops. Its units stay queued; whoever still stands in the zone is told
local function dissolve(group)
	local i = group and table.find(groups, group)
	if not i then return end
	table.remove(groups, i)
	for _, unit in ipairs(group.units) do
		unit.group = nil
		for _, m in ipairs(unit.members) do
			if zoneOf[m] == group.zone then tell(m, "lobby_countdown_stopped") end
		end
	end
end

-- Look at every party again: which are queued and where, which groups are full. Returns true when it changed
local function requeue(now)
	now = now or PartyService.Clock()
	local changed, list = false, {}
	for player in pairs(present) do
		if partyOf[player].leader == player then table.insert(list, partyOf[player]) end
	end
	table.sort(list, function(a, b) return a.n < b.n end)
	for _, party in ipairs(list) do
		if party.cooldown and party.cooldown <= now then
			party.cooldown, changed = nil, true
		end
		local id, state = status(party)
		if state ~= "waiting" and state ~= "countdown" then id = nil end
		if party.zone ~= id then
			dissolve(party.group)
			order += 1
			party.zone, party.queuedAt, party.order, party.have, changed = id, now, order, nil, true
		end
	end
	table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
	for _, zone in ipairs(PartyService.Zones()) do
		-- first fit, in order of arrival: a unit goes to the first bucket that has room for all of it
		local buckets = {}
		for _, unit in ipairs(list) do
			if unit.zone == zone.id and not unit.group then
				local bucket
				for _, b in ipairs(buckets) do
					if b.size + #unit.members <= zone.capacity then
						bucket = b
						break
					end
				end
				if not bucket then
					bucket = {zone = zone.id, units = {}, size = 0}
					table.insert(buckets, bucket)
				end
				table.insert(bucket.units, unit)
				bucket.size += #unit.members
				if bucket.size == zone.capacity then
					-- exactly full: this is a group and its countdown starts
					table.remove(buckets, table.find(buckets, bucket))
					bucket.ends = now + LobbyCfg.CountdownSeconds
					table.insert(groups, bucket)
					for _, u in ipairs(bucket.units) do u.group = bucket end
					changed = true
				end
			end
		end
		for _, b in ipairs(buckets) do
			for _, u in ipairs(b.units) do
				if u.have ~= b.size then
					u.have, changed = b.size, true
				end
			end
		end
	end
	return changed
end

-- Tests place their stand-ins; real players are measured by UpdateZones
function PartyService:SetZone(player, id)
	if not present[player] or (id ~= nil and not zoneInfo(id)) then return false end
	zoneOf[player] = id
	requeue()
	self:Changed()
	return true
end

-- The player asks to be put into a zone: onto the first standing place nobody else is on
function PartyService:Join(player, zoneId)
	local party, zone = partyOf[player], zoneInfo(zoneId)
	if not party then return false, "unknown" end
	if not zone then return refuse(player, "no_zone") end
	if party.launching then return refuse(player, "launching") end
	if #party.members > zone.capacity then return refuse(player, "party_too_big") end
	if isReal(player) then
		local spot = zone.spots[1] or zone.center
		for _, s in ipairs(zone.spots) do
			local free = true
			for other in pairs(present) do
				local root = other ~= player and isReal(other) and rootOf(other)
				if root and flat(root.Position, s) < 2.5 then
					free = false
					break
				end
			end
			if free then
				spot = s
				break
			end
		end
		if not place(player, spot) then return refuse(player, "no_zone") end
	end
	zoneOf[player] = zone.id
	requeue()
	self:Changed()
	return true
end

-- The player asks to leave the queue: out of the zone, to its exit
function PartyService:LeaveQueue(player)
	local party, zone = partyOf[player], zoneInfo(zoneOf[player])
	if not (party and zone) then return refuse(player, "not_queued") end
	if party.launching then return refuse(player, "launching") end
	if isReal(player) then place(player, zone.exit) end
	zoneOf[player] = nil
	requeue()
	self:Changed()
	return true
end

-- ===== The party =====

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
	dissolve(partyOf[player].group)
	self:Leave(player, true)
	present[player], partyOf[player], invites[player], rejoin[player], zoneOf[player] = nil, nil, nil, nil, nil
	for _, set in pairs(invites) do set[player] = nil end
	requeue()
	self:Changed()
end

-- Leave the party. The leader is the host of the team, so a party without its leader is disbanded.
-- gone: the player is leaving the lobby and gets no party of their own
function PartyService:Leave(player, gone)
	local party = partyOf[player]
	if not party then return false, "unknown" end
	if party.launching and not gone then return refuse(player, "launching") end
	if #party.members == 1 then return false, "alone" end
	dissolve(party.group)
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
	if gone then return true end -- Exit finishes the rest
	soloParty(player)
	requeue()
	self:Changed()
	return true
end

function PartyService:Invite(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if not target or target == player or not present[target] then return refuse(player, "unknown") end
	if #party.members >= PartyCfg.MaxSize then return refuse(player, "full") end
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
	if party.launching or partyOf[player].launching then return refuse(player, "launching") end
	if #party.members >= PartyCfg.MaxSize then return refuse(player, "full") end
	if #partyOf[player].members > 1 then return refuse(player, "leave_first") end
	invites[player] = {}
	for _, other in pairs(invites) do other[player] = nil end -- what the player sent as the leader of their own party
	-- both parties change: nobody leaves without having seen it
	dissolve(party.group)
	dissolve(partyOf[player].group)
	for _, m in ipairs(party.members) do tell(m, "lobby_joined", nameOf(player)) end
	partyOf[player] = party
	table.insert(party.members, player)
	requeue()
	self:Changed()
	return true, "joined"
end

function PartyService:Kick(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if not target or target == player or partyOf[target] ~= party then return refuse(player, "unknown") end
	dissolve(party.group)
	table.remove(party.members, table.find(party.members, target))
	soloParty(target)
	tell(target, "lobby_kicked")
	requeue()
	self:Changed()
	return true
end

-- ===== The way to the game =====

local function lock(party)
	party.launching, party.zone, party.group = true, nil, nil
	party.try = (party.try or 0) + 1
	return party.try
end

-- Unlock a party through a member who is still here
local function release(self, party, try)
	if party.try ~= try then return end -- it has been unlocked and has set out again since
	for _, m in ipairs(party.members) do
		if present[m] and partyOf[m] == party then return self:Unlock(m, "lobby_launch_failed") end
	end
end

-- The members leave the lobby one by one; whoever is still here after a while gets the party back
local function unlockLater(self, party, try)
	task.delay(LobbyCfg.LaunchLockSeconds, release, self, party, try)
end

-- The party did not leave after all: it waits RetryCooldownSeconds and is queued again where it stands.
-- If its leader has already gone, the others get parties of their own
function PartyService:Unlock(player, key)
	local party = partyOf[player]
	if not (party and party.launching) then return false end
	party.launching = false
	party.cooldown = PartyService.Clock() + LobbyCfg.RetryCooldownSeconds
	local keep = present[party.leader] and partyOf[party.leader] == party
	for _, m in ipairs(table.clone(party.members)) do
		if not keep then soloParty(m) end
		tell(m, key)
	end
	requeue()
	self:Changed()
	return true
end

-- The countdown of a group ran out: all its units go together to one game server of the zone's format.
-- The host of the team is the leader of the unit that came first
function PartyService:Launch(group)
	local i = group and table.find(groups, group)
	if not i then return false, "no_group" end
	table.remove(groups, i)
	local members, tries = {}, {}
	for n, unit in ipairs(group.units) do
		tries[n] = lock(unit)
		for _, m in ipairs(unit.members) do table.insert(members, m) end
	end
	self:Changed()
	local ok, reason = MatchService:Launch(members, group.units[1].leader, PartyService.Format(group.zone))
	for n, unit in ipairs(group.units) do
		if ok then
			unlockLater(self, unit, tries[n])
		else
			release(self, unit, tries[n])
		end
	end
	if not ok then return false, reason end
	return true, "launched"
end

-- One step of the lobby: old invitations go away, the zones are measured, the queue is put in order and the
-- groups whose countdown ran out set out. now is passed in so that tests can move time themselves; sync makes
-- a launch finish inside the step
function PartyService:Step(now, sync)
	local changed = false
	for _, set in pairs(invites) do
		for leader, expires in pairs(set) do
			if expires <= now then
				set[leader], changed = nil, true
			end
		end
	end
	if self:UpdateZones() then changed = true end
	if requeue(now) then changed = true end
	local due = {}
	for _, group in ipairs(groups) do
		if now >= group.ends then table.insert(due, group) end
	end
	for _, group in ipairs(due) do
		if sync then
			self:Launch(group)
		else
			task.spawn(self.Launch, self, group)
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
	dissolve(party.group)
	local try = lock(party)
	requeue()
	self:Changed()
	local ok, reason = MatchService:Rejoin(player)
	if ok then
		unlockLater(self, party, try)
	elseif party.try == try then
		party.launching = false
		if reason == "gone" then
			rejoin[player] = nil
			tell(player, "lobby_rejoin_gone")
		else
			tell(player, "lobby_launch_failed")
		end
		requeue()
		self:Changed()
	end
	return ok, reason
end

-- ===== What the clients see =====

-- What one player sees: the party, its place in the queue, the four zones, the invitations and the others in
-- the lobby. Times are on the clock every client shares with the server
function PartyService:Snapshot(player)
	local party = partyOf[player]
	if not party then return nil end
	local now = PartyService.Clock()
	local function shared(t)
		return workspace:GetServerTimeNow() + (t - now)
	end
	local members = {}
	for i, m in ipairs(party.members) do
		members[i] = {id = m.UserId, name = nameOf(m), zone = zoneOf[m]}
	end
	local queue
	local id, state, missing = status(party, player)
	if id then
		local capacity = zoneInfo(id).capacity
		queue = {zone = id, capacity = capacity, state = state}
		if state == "waiting" or state == "countdown" then
			queue.have = party.group and capacity or party.have or #party.members
			queue.need = capacity - queue.have
			queue.ends = party.group and shared(party.group.ends) or nil
		elseif state == "split" then
			queue.missing = missing
		elseif state == "cooldown" then
			queue.retryAt = shared(party.cooldown)
		end
	end
	local zones = {}
	for i, zone in ipairs(PartyService.Zones()) do
		local z = {id = zone.id, capacity = zone.capacity, players = 0, countdown = false}
		for p in pairs(present) do
			if zoneOf[p] == zone.id then z.players += 1 end
		end
		for _, group in ipairs(groups) do
			if group.zone == zone.id then
				z.countdown = true
				z.ends = math.min(z.ends or math.huge, shared(group.ends))
			end
		end
		zones[i] = z
	end
	local got = {}
	for leader, expires in pairs(invites[player] or {}) do
		if expires > now and partyOf[leader] then
			table.insert(got, {id = leader.UserId, name = nameOf(leader), size = #partyOf[leader].members})
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
	local session = rejoin[player]
	return {
		me = player.UserId,
		party = {leader = party.leader.UserId, members = members, launching = party.launching, max = PartyCfg.MaxSize},
		queue = queue,
		zones = zones,
		invites = got,
		players = others,
		rejoin = session and {hostName = tostring(session.hostName or session.host), format = session.format} or nil,
	}
end

-- Send everyone their view of the lobby, at most once a frame
function PartyService:Changed()
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
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
		if action == "join" then
			self:Join(player, a)
		elseif action == "leave_queue" then
			self:LeaveQueue(player)
		elseif action == "invite" then
			self:Invite(player, byId(a))
		elseif action == "accept" or action == "decline" then
			self:Answer(player, byId(a), action == "accept")
		elseif action == "leave" then
			self:Leave(player)
		elseif action == "kick" then
			self:Kick(player, byId(a))
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
