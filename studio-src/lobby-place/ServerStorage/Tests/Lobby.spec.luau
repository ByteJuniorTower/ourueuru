-- Milestones 9 and 10: parties in the lobby, the four matchmaking zones, the server list by party format and the
-- way to the game (technical plan, milestones 9-10; design doc 2.1, 2.2; decision 2).
-- Runs in a play session (ctx.live). Other players are stand-ins (tables) that the tests put into the zones, the
-- two calls that leave the server are replaced by a recorder and the server list is a table, so nothing is
-- teleported and no store is touched.
return function(it, expect, ctx)
	local PartyCfg = require(ctx.shared.Config.Party)
	local GameCfg = require(ctx.shared.Config.Game)
	local LobbyCfg = require(ctx.shared.Config.Lobby)
	local Strings = require(ctx.shared.Locale.LobbyStrings)
	local Matchmaking = require(ctx.shared.Modules.Matchmaking)
	local ORDER = {"solo", "duo", "trio", "quartet"}

	it("M9 config: the four party formats of the plan and two places", function()
		local want = {{"solo", 1, 20}, {"duo", 2, 10}, {"trio", 3, 6}, {"quartet", 4, 5}}
		expect(#PartyCfg.Formats).toBe(#want)
		for i, w in ipairs(want) do
			local f = PartyCfg.Formats[i]
			expect(f.id).toBe(w[1])
			expect(f.size).toBe(w[2])
			expect(f.houses).toBe(w[3])
			-- one team per house, so a full server never holds more than the server limit (a trio server holds 18)
			expect(f.size * f.houses <= PartyCfg.ServerPlayers).toBeTruthy()
			expect(Matchmaking.FormatBySize(PartyCfg.Formats, w[2]).id).toBe(w[1])
		end
		expect(PartyCfg.MaxSize).toBe(4)
		expect(GameCfg.Places.Lobby > 0 and GameCfg.Places.Game > 0 and GameCfg.Places.Lobby ~= GameCfg.Places.Game).toBeTruthy()
	end)

	it("M10 config: four zones in order, each with a colour and a format; every text in en and ru; a short countdown", function()
		expect(PartyCfg.Modes).toBe(nil) -- nobody chooses a mode any more: the zone decides
		expect(#LobbyCfg.Zones).toBe(#ORDER)
		for i, id in ipairs(ORDER) do
			local zone = LobbyCfg.Zones[i]
			expect(zone.id).toBe(id)
			expect(typeof(zone.color)).toBe("Color3")
			expect(PartyCfg.Formats[i].id).toBe(id) -- the capacity of a zone is the size of its format
			expect(PartyCfg.Formats[i].size).toBe(i)
			expect(type(Strings.en["mode_" .. id])).toBe("string")
			expect(type(Strings.ru["mode_" .. id])).toBe("string")
		end
		expect(type(Strings.en.mode_capacity)).toBe("string")
		expect(type(Strings.ru.mode_capacity)).toBe("string")
		for key in pairs(Strings.en) do expect(type(Strings.ru[key])).toBe("string") end
		for key in pairs(Strings.ru) do expect(type(Strings.en[key])).toBe("string") end
		-- every message the server sends has a text
		local keys = {"invited", "declined", "joined", "left", "kicked", "disbanded", "launch_failed", "rejoin_gone",
			"countdown_stopped", "err_not_leader", "err_launching", "err_full", "err_busy", "err_leave_first",
			"err_too_many_invites", "err_expired", "err_unknown", "err_party_too_big", "err_not_queued", "err_no_zone"}
		for _, key in ipairs(keys) do expect(type(Strings.en["lobby_" .. key])).toBe("string") end
		-- the 3 to 5 seconds a player needs to see the countdown
		expect(LobbyCfg.CountdownSeconds >= 3 and LobbyCfg.CountdownSeconds <= 5).toBeTruthy()
		expect(LobbyCfg.RetryCooldownSeconds > 0 and LobbyCfg.StepSeconds > 0 and LobbyCfg.ZoneMargin >= 0).toBeTruthy()
	end)

	it("M9 server list: houses are held and released, a full server is skipped, entries and tickets expire", function()
		local saved = {Matchmaking.Backend(), Matchmaking.Now}
		local t = 5000
		Matchmaking.Now = function() return t end
		Matchmaking.UseBackend(Matchmaking.LocalBackend())
		local ok, err = pcall(function()
			expect(#Matchmaking.FindOpen("trio")).toBe(0)
			local entry = Matchmaking.Register("trio", "A", "codeA", 6, 1)
			expect(Matchmaking.OpenHouses(entry)).toBe(5)
			for host = 2, 6 do expect(Matchmaking.Claim("trio", "A", host) ~= nil).toBeTruthy() end
			expect(Matchmaking.Claim("trio", "A", 7)).toBe(nil) -- six houses, six parties
			expect(Matchmaking.Claim("trio", "A", 3) ~= nil).toBeTruthy() -- the same party again keeps its house
			expect(#Matchmaking.FindOpen("trio")).toBe(0)
			Matchmaking.Release("trio", "A", 6)
			expect(Matchmaking.FindOpen("trio")[1].open).toBe(1)
			expect(#Matchmaking.FindOpen("duo")).toBe(0) -- another format has its own servers
			-- the game server reports: two parties arrived, their houses are taken and their claims end
			local after = Matchmaking.Heartbeat("trio", "A", "codeA", 6, 4, 6, {1, 2})
			expect(after.free).toBe(4)
			expect(Matchmaking.OpenHouses(after)).toBe(1) -- 4 free, 3 still on their way
			-- fuller servers come first
			Matchmaking.Register("trio", "B", "codeB", 6)
			local open = Matchmaking.FindOpen("trio")
			expect(open[1].id).toBe("A")
			expect(open[2].id).toBe("B")
			-- a claim that nobody used ends by itself
			t += Matchmaking.Ttl.Claim + 1
			expect(#Matchmaking.FindOpen("trio")).toBe(0) -- and so do servers that stopped reporting
			Matchmaking.Heartbeat("trio", "A", "codeA", 6, 4, 6, {})
			expect(Matchmaking.FindOpen("trio")[1].open).toBe(4)
			-- tickets: for one server, used once, gone after their time
			expect(Matchmaking.PutTicket(11, {host = 12, format = "trio", server = "A"})).toBe(true)
			local ticket, why = Matchmaking.TakeTicket(11, "B")
			expect(ticket).toBe(nil)
			expect(why).toBe("other_server")
			expect(Matchmaking.TakeTicket(11, "A").host).toBe(12)
			ticket, why = Matchmaking.TakeTicket(11, "A")
			expect(why).toBe("none")
			Matchmaking.PutTicket(11, {host = 12, format = "trio", server = "A"})
			t += Matchmaking.Ttl.Ticket + 1
			expect((Matchmaking.TakeTicket(11, "A"))).toBe(nil)
			expect(Matchmaking.ReservedId("")).toBe(Matchmaking.StudioServer)
			expect(Matchmaking.ReservedId("abc")).toBe("abc")
		end)
		Matchmaking.UseBackend(saved[1])
		Matchmaking.Now = saved[2]
		if not ok then error(err, 0) end
	end)

	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local PS, MS = Loader.Get("LobbyPartyService"), Loader.Get("MatchService")

	-- stand-in players, a recorder instead of the teleport and a clock the test moves; everything is put back
	local function fixture(fn)
		local saved = {MS.Teleporter, Matchmaking.Backend(), Matchmaking.Now, PS.Clock, Matchmaking.Attempts}
		local savedCfg = {LobbyCfg.TeleportAttempts, LobbyCfg.TeleportRetrySeconds, LobbyCfg.PrivateServerPerParty}
		local f = {bots = {}, reserved = 0, sends = {}, t = 1000}
		-- a stand-in stands where the test puts it: SetZone is what UpdateZones does for a real player
		function f.bot(i, zone)
			local b = {UserId = -9100 - i, Name = "Bot" .. i, DisplayName = "Bot " .. i, Parent = workspace}
			table.insert(f.bots, b)
			PS:Enter(b)
			if zone then expect(PS:SetZone(b, zone)).toBe(true) end
			return b
		end
		-- a party led by the first bot; with a zone, its members step into it one after another
		function f.party(first, size, zone)
			local leader = f.bot(first)
			for i = 1, size - 1 do
				local guest = f.bot(first + i)
				expect(PS:Invite(leader, guest)).toBe(true)
				expect(PS:Answer(guest, leader, true)).toBe(true)
			end
			local party = PS:Get(leader)
			for _, m in ipairs(party.members) do PS:SetZone(m, zone) end
			return leader, party
		end
		MS.Teleporter = {
			Reserve = function(placeId)
				if f.failReserve then error("reserve refused") end
				f.reserved += 1
				f.reservedPlace = placeId
				return "code" .. f.reserved, "server" .. f.reserved
			end,
			Send = function(placeId, players, code, data)
				if f.failSend then error("teleport refused") end
				table.insert(f.sends, {place = placeId, players = table.clone(players), code = code, data = data})
			end,
		}
		Matchmaking.UseBackend(Matchmaking.LocalBackend())
		Matchmaking.Now = function() return f.t end
		Matchmaking.Attempts = 1
		PS.Clock = function() return f.t end
		LobbyCfg.TeleportAttempts, LobbyCfg.TeleportRetrySeconds = 1, 0 -- no waiting inside a test
		-- time passes and the lobby takes its step; a launch finishes inside it
		function f.pass(seconds)
			f.t += seconds
			PS:Step(f.t, true)
		end
		-- the countdown of this player's group runs out: what PartyService:Step does then, without the wait
		function f.launch(player)
			local group = PS:Get(player).group
			expect(group ~= nil).toBeTruthy()
			return PS:Launch(group)
		end
		function f.state(player)
			local queue = PS:Snapshot(player).queue
			return queue and queue.state
		end
		local ok, err = pcall(fn, f)
		for _, b in ipairs(f.bots) do PS:Exit(b) end
		MS.Teleporter = saved[1]
		Matchmaking.UseBackend(saved[2])
		Matchmaking.Now, PS.Clock, Matchmaking.Attempts = saved[3], saved[4], saved[5]
		LobbyCfg.TeleportAttempts, LobbyCfg.TeleportRetrySeconds, LobbyCfg.PrivateServerPerParty = savedCfg[1], savedCfg[2], savedCfg[3]
		if not ok then error(err, 0) end
	end

	-- how `other` looks in the list of lobby players that `player` gets
	local function listed(player, other)
		for _, entry in ipairs(PS:Snapshot(player).players) do
			if entry.id == other.UserId then return entry end
		end
		return nil
	end

	it("M9 store: Studio keeps the server list in memory unless asked otherwise, live servers use MemoryStore", function()
		expect(MS.StoreKind(true, nil)).toBe("local")
		expect(MS.StoreKind(true, "memorystore")).toBe("memorystore")
		expect(MS.StoreKind(false, nil)).toBe("memorystore")
		expect(MS.StoreKind(false, "local")).toBe("memorystore")
	end)

	it("M9 party: everyone starts alone as a leader; invite, accept, decline, expiry, a full party, kick and leave", function() fixture(function(f)
		local a, b, c, d, e = f.bot(1), f.bot(2), f.bot(3), f.bot(4), f.bot(5)
		local party = PS:Get(a)
		expect(party.leader).toBe(a)
		expect(#party.members).toBe(1)
		expect(PS:Invite(a, b)).toBe(true)
		expect(PS:Snapshot(b).invites[1].id).toBe(a.UserId)
		expect(PS:Snapshot(b).invites[1].size).toBe(1)
		expect(listed(a, b).invited).toBe(true)
		expect(listed(a, c).invited).toBe(false)
		local ok, why = PS:Answer(b, a, false)
		expect(why).toBe("declined")
		expect(#PS:Get(a).members).toBe(1)
		-- an invitation nobody answered in time goes away by itself
		expect(PS:Invite(a, b)).toBe(true)
		f.pass(LobbyCfg.InviteSeconds + 1)
		expect(#PS:Snapshot(b).invites).toBe(0)
		ok, why = PS:Answer(b, a, true)
		expect(ok).toBe(false)
		expect(why).toBe("expired")
		-- accept: a party is four Guardians at most, whatever zone it goes to
		for _, guest in ipairs({b, c, d, e}) do expect(PS:Invite(a, guest)).toBe(true) end
		for _, guest in ipairs({b, c, d}) do expect(PS:Answer(guest, a, true)).toBe(true) end
		expect(PS:Get(d)).toBe(PS:Get(a))
		expect(PS:Snapshot(d).party.members[1].id).toBe(a.UserId) -- the leader comes first
		ok, why = PS:Answer(e, a, true)
		expect(why).toBe("full")
		ok, why = PS:Invite(a, e)
		expect(why).toBe("full")
		ok, why = PS:Invite(b, e)
		expect(why).toBe("not_leader")
		ok, why = PS:Invite(e, b)
		expect(why).toBe("busy") -- somebody who is already in a party cannot be invited
		-- kick and leave give the player a party of their own again
		ok, why = PS:Kick(b, a)
		expect(why).toBe("not_leader")
		expect(PS:Kick(a, b)).toBe(true)
		expect(PS:Get(b).leader).toBe(b)
		expect(#PS:Get(a).members).toBe(3)
		expect(PS:Leave(d)).toBe(true)
		expect(PS:Get(d).leader).toBe(d)
		expect(#PS:Get(a).members).toBe(2)
		-- a leader with a party of their own has to leave it before joining another
		expect(PS:Invite(a, b)).toBe(true)
		expect(PS:Invite(b, d)).toBe(true)
		expect(PS:Answer(d, b, true)).toBe(true)
		ok, why = PS:Answer(b, a, true)
		expect(why).toBe("leave_first")
		-- the leader is the host of the team: when the leader leaves, the party is disbanded
		expect(PS:Leave(a)).toBe(true)
		expect(PS:Get(c).leader).toBe(c)
		expect(#PS:Get(c).members).toBe(1)
		expect(PS:Get(a).leader).toBe(a)
	end) end)

	it("M10 solo zone: stepping in starts a countdown at once, stepping out stops it, two players get two launches", function() fixture(function(f)
		local a, b = f.bot(1), f.bot(2)
		expect(PS:Snapshot(a).queue).toBe(nil)
		expect(PS:SetZone(a, "solo")).toBe(true)
		expect(PS:ZoneOf(a)).toBe("solo")
		expect(f.state(a)).toBe("countdown")
		f.pass(LobbyCfg.CountdownSeconds - 1)
		expect(#f.sends).toBe(0) -- still counting
		PS:SetZone(a, nil)
		expect(PS:Snapshot(a).queue).toBe(nil)
		f.pass(10)
		expect(#f.sends).toBe(0) -- stepped out: nobody is teleported
		-- back in: the countdown starts from the beginning; a second player gets a countdown of their own
		PS:SetZone(a, "solo")
		f.pass(2)
		PS:SetZone(b, "solo")
		expect(PS:Get(b).group ~= nil and PS:Get(a).group ~= PS:Get(b).group).toBeTruthy()
		expect(PS:Snapshot(b).zones[1].players).toBe(2)
		f.pass(LobbyCfg.CountdownSeconds - 2)
		expect(#f.sends).toBe(1)
		expect(#f.sends[1].players).toBe(1)
		expect(f.sends[1].players[1]).toBe(a)
		expect(f.state(b)).toBe("countdown")
		f.pass(2)
		expect(#f.sends).toBe(2)
		expect(f.sends[2].players[1]).toBe(b)
		expect(f.reserved).toBe(1) -- two launches; the second takes a house of the same solo server
	end) end)

	it("M10 duo zone: one waits, the second starts the countdown, a third waits for a fourth; a group that loses a member stops", function() fixture(function(f)
		local a, b, c = f.bot(1, "duo"), f.bot(2), f.bot(3)
		local q = PS:Snapshot(a).queue
		expect(q.state).toBe("waiting")
		expect(q.have).toBe(1)
		expect(q.need).toBe(1)
		f.pass(60)
		expect(#f.sends).toBe(0) -- nobody leaves the duo zone alone
		PS:SetZone(b, "duo")
		expect(f.state(a)).toBe("countdown")
		expect(PS:Get(a).group).toBe(PS:Get(b).group)
		PS:SetZone(c, "duo")
		q = PS:Snapshot(c).queue
		expect(q.state).toBe("waiting")
		expect(q.have).toBe(1)
		expect(q.need).toBe(1)
		expect(PS:Get(c).group).toBe(nil)
		-- b steps out during the countdown: the group stops and a goes with c, who is next in line
		f.pass(LobbyCfg.CountdownSeconds - 1)
		PS:SetZone(b, nil)
		expect(PS:Get(a).group ~= nil).toBeTruthy()
		expect(PS:Get(a).group).toBe(PS:Get(c).group)
		expect(PS:Get(a).group.units[1]).toBe(PS:Get(a)) -- a came first
		f.pass(1)
		expect(#f.sends).toBe(0) -- the new group has a countdown of its own
		PS:SetZone(b, "duo")
		expect(f.state(b)).toBe("waiting") -- b is back, behind the others, and waits for a fourth
		f.pass(LobbyCfg.CountdownSeconds - 1)
		expect(#f.sends).toBe(1)
		expect(f.sends[1].players[1]).toBe(a)
		expect(f.sends[1].players[2]).toBe(c)
		local d = f.bot(4, "duo")
		expect(PS:Get(d).group ~= nil).toBeTruthy()
		expect(PS:Get(d).group.units[1]).toBe(PS:Get(b))
	end) end)

	it("M10 parties: a party is one unit; groups fill in order of arrival; a party that is too big or split is not matched", function() fixture(function(f)
		-- quartet: a party of two and two Guardians on their own make one group
		local pair = f.party(1, 2, "quartet")
		local q = PS:Snapshot(pair).queue
		expect(q.state).toBe("waiting")
		expect(q.have).toBe(2)
		expect(q.need).toBe(2)
		local s1 = f.bot(3, "quartet")
		expect(PS:Snapshot(pair).queue.have).toBe(3)
		expect(PS:Snapshot(s1).queue.need).toBe(1)
		local s2 = f.bot(4, "quartet")
		local group = PS:Get(pair).group
		expect(group ~= nil and PS:Get(s1).group == group and PS:Get(s2).group == group).toBeTruthy()
		expect(#group.units).toBe(3)
		expect(group.units[1]).toBe(PS:Get(pair))
		q = PS:Snapshot(s2).queue
		expect(q.state).toBe("countdown")
		expect(q.have).toBe(4)
		expect(q.need).toBe(0)
		-- trio: two pairs do not fit together; a single goes with the pair that came first
		local p1, p2 = f.party(5, 2, "trio"), f.party(7, 2, "trio")
		expect(PS:Get(p1).group).toBe(nil)
		expect(PS:Snapshot(p2).queue.have).toBe(2)
		local s3 = f.bot(9, "trio")
		expect(PS:Get(p1).group ~= nil).toBeTruthy()
		expect(PS:Get(s3).group).toBe(PS:Get(p1).group)
		expect(f.state(p2)).toBe("waiting")
		-- a party of three in the trio zone needs nobody else; in the duo zone it is too big
		local three, threeParty = f.party(10, 3, "trio")
		expect(#PS:Get(three).group.units).toBe(1)
		for _, m in ipairs(threeParty.members) do PS:SetZone(m, "duo") end
		expect(f.state(three)).toBe("too_big")
		expect(PS:Get(three).group).toBe(nil)
		-- split: a party with a member outside the zone holds no place in it
		local lead, party = f.party(13, 2)
		local guest = party.members[2]
		PS:SetZone(lead, "duo")
		q = PS:Snapshot(lead).queue
		expect(q.state).toBe("split")
		expect(#q.missing).toBe(1)
		expect(q.missing[1]).toBe(guest.DisplayName)
		q = PS:Snapshot(guest).queue -- the one who is not there is shown where to go
		expect(q.zone).toBe("duo")
		expect(q.state).toBe("split")
		expect(q.missing[1]).toBe(guest.DisplayName)
		local single = f.bot(15, "duo")
		expect(f.state(single)).toBe("waiting") -- not matched with half a party
		PS:SetZone(guest, "duo")
		expect(f.state(lead)).toBe("countdown") -- complete: the pair is a group by itself
		expect(#PS:Get(lead).group.units).toBe(1)
		expect(f.state(single)).toBe("waiting")
		-- the three full groups set out; nobody else does
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(3)
		expect(#f.sends[1].players + #f.sends[2].players + #f.sends[3].players).toBe(4 + 3 + 2)
	end) end)

	it("M10 launch: when the countdown ends the whole group is teleported together, once, with a ticket for everyone", function() fixture(function(f)
		local single = f.bot(1, "quartet")
		local pair, pairParty = f.party(2, 2, "quartet")
		local mate, last, other = pairParty.members[2], f.bot(4), f.bot(5)
		expect(PS:Invite(other, last)).toBe(true)
		PS:SetZone(last, "quartet")
		local group = PS:Get(single).group
		f.pass(LobbyCfg.CountdownSeconds - 1)
		expect(#f.sends).toBe(0)
		f.pass(1)
		expect(f.reserved).toBe(1)
		expect(f.reservedPlace).toBe(GameCfg.Places.Game)
		expect(#f.sends).toBe(1)
		expect(f.sends[1].place).toBe(GameCfg.Places.Game)
		expect(#f.sends[1].players).toBe(4)
		expect(f.sends[1].code).toBe("code1")
		-- the list has the new quartet server with five houses, one of them held for this team
		local entry = Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "quartet", "server1")
		expect(entry.houses).toBe(5)
		expect(entry.code).toBe("code1")
		expect(Matchmaking.OpenHouses(entry)).toBe(4)
		-- the host is the leader of the unit that came first; the format is the zone
		for _, p in ipairs({single, pair, mate, last}) do
			local ticket = Matchmaking.TakeTicket(p.UserId, "server1")
			expect(ticket.host).toBe(single.UserId)
			expect(ticket.format).toBe("quartet")
			expect(#ticket.members).toBe(4)
			expect(ticket.code).toBe("code1")
			expect(PS:Get(p).launching).toBe(true)
		end
		-- while the units are on their way nothing about them can be changed
		local ok, why = PS:Kick(pair, mate)
		expect(why).toBe("launching")
		ok, why = PS:Leave(mate)
		expect(why).toBe("launching")
		ok, why = PS:Invite(pair, other)
		expect(why).toBe("launching")
		ok, why = PS:Answer(last, other, true)
		expect(why).toBe("launching")
		-- and nobody is launched twice
		ok, why = PS:Launch(group)
		expect(ok).toBe(false)
		f.pass(LobbyCfg.CountdownSeconds + 1)
		expect(#f.sends).toBe(1)
		-- the members leave the lobby one after another; those still here stay in the party
		PS:Exit(pair)
		expect(#PS:Get(mate).members).toBe(1)
		expect(PS:Get(mate).launching).toBe(true)
	end) end)

	it("M9 matching: teams of one format fill a server house by house, other formats and full servers get new ones", function() fixture(function(f)
		local duoA = f.party(1, 2, "duo")
		expect(f.launch(duoA)).toBe(true)
		local duoB = f.party(3, 2, "duo")
		expect(f.launch(duoB)).toBe(true)
		expect(f.reserved).toBe(1) -- the second duo goes to the server of the first
		expect(f.sends[2].code).toBe("code1")
		expect(Matchmaking.TakeTicket(duoB.UserId, "server1").host).toBe(duoB.UserId)
		local solo = f.bot(5, "solo")
		expect(f.launch(solo)).toBe(true)
		expect(f.reserved).toBe(2) -- a solo player needs a solo server
		expect(f.sends[3].code).toBe("code2")
		expect(Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "solo", "server2").houses).toBe(20)
		-- the duo server reports that every house is taken: the next duo opens a new server
		Matchmaking.Heartbeat("duo", "server1", "code1", 10, 0, 20, {duoA.UserId, duoB.UserId})
		local duoC = f.party(6, 2, "duo")
		expect(f.launch(duoC)).toBe(true)
		expect(f.reserved).toBe(3)
		expect(f.sends[4].code).toBe("code3")
		-- six trio teams fit one trio server (18 players), the seventh gets another
		local before = f.reserved
		for i = 1, 7 do
			local trio = f.party(10 + i * 3, 3, "trio")
			expect(f.launch(trio)).toBe(true)
			expect(f.reserved).toBe(before + (i <= 6 and 1 or 2))
		end
	end) end)

	it("M10 failure: a refused teleport or server unlocks the units; after the cooldown they are queued and launched again", function() fixture(function(f)
		local first = f.party(1, 2, "duo")
		expect(f.launch(first)).toBe(true)
		local a, b = f.bot(3, "duo"), f.bot(4, "duo")
		f.failSend = true
		local ok, why = f.launch(a)
		expect(ok).toBe(false)
		expect(why).toBe("teleport")
		for _, p in ipairs({a, b}) do
			expect(PS:Get(p).launching).toBe(false)
			local q = PS:Snapshot(p).queue
			expect(q.state).toBe("cooldown")
			expect(q.retryAt).toNear(workspace:GetServerTimeNow() + LobbyCfg.RetryCooldownSeconds, 1)
		end
		local entry = Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "duo", "server1")
		expect(Matchmaking.OpenHouses(entry)).toBe(9) -- only the first team holds a house
		-- nothing happens during the cooldown; after it the two are queued again without stepping out
		f.failSend = false
		f.pass(LobbyCfg.RetryCooldownSeconds - 1)
		expect(f.state(a)).toBe("cooldown")
		expect(PS:Get(a).group).toBe(nil)
		f.pass(1)
		expect(f.state(a)).toBe("countdown")
		expect(PS:Get(a).group).toBe(PS:Get(b).group)
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(2)
		expect(#f.sends[2].players).toBe(2)
		expect(f.sends[2].code).toBe("code1")
		expect(PS:Get(b).launching).toBe(true)
		-- no server can be reserved: the same, as often as it takes
		f.failReserve = true
		local solo = f.bot(5, "solo")
		ok, why = f.launch(solo)
		expect(ok).toBe(false)
		expect(why).toBe("server")
		expect(PS:Get(solo).launching).toBe(false)
		f.pass(LobbyCfg.RetryCooldownSeconds)
		expect(f.state(solo)).toBe("countdown")
		f.pass(LobbyCfg.CountdownSeconds)
		expect(f.state(solo)).toBe("cooldown")
		f.failReserve = false
		f.pass(LobbyCfg.RetryCooldownSeconds)
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(3)
		expect(f.sends[3].players[1]).toBe(solo)
		-- a unit that stepped out during the cooldown is not queued again
		local gone = f.bot(6, "solo")
		f.failSend = true
		expect(f.launch(gone)).toBe(false)
		PS:SetZone(gone, nil)
		f.failSend = false
		f.pass(LobbyCfg.RetryCooldownSeconds + LobbyCfg.CountdownSeconds)
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(3)
	end) end)

	it("M10 join and leave: Join puts a player into a zone, refuses an unknown zone and a party that is too big; LeaveQueue stops the countdown", function() fixture(function(f)
		local a, b = f.bot(1), f.bot(2)
		local ok, why = PS:Join(a, "septet")
		expect(ok).toBe(false)
		expect(why).toBe("no_zone")
		ok, why = PS:LeaveQueue(a)
		expect(why).toBe("not_queued")
		expect(PS:Join(a, "duo")).toBe(true)
		expect(PS:ZoneOf(a)).toBe("duo")
		expect(f.state(a)).toBe("waiting")
		expect(PS:Join(b, "duo")).toBe(true)
		expect(f.state(b)).toBe("countdown")
		expect(PS:Snapshot(a).zones[2].countdown).toBe(true)
		-- leaving the queue stops the countdown; the other one stays queued
		expect(PS:LeaveQueue(b)).toBe(true)
		expect(PS:ZoneOf(b)).toBe(nil)
		expect(f.state(a)).toBe("waiting")
		expect(PS:Snapshot(a).zones[2].countdown).toBe(false)
		f.pass(LobbyCfg.CountdownSeconds + 1)
		expect(#f.sends).toBe(0)
		-- a party of three does not fit the duo zone, but it fits the trio zone
		local three, party = f.party(3, 3)
		ok, why = PS:Join(three, "duo")
		expect(why).toBe("party_too_big")
		expect(PS:ZoneOf(three)).toBe(nil)
		for _, m in ipairs(party.members) do expect(PS:Join(m, "trio")).toBe(true) end
		expect(f.state(three)).toBe("countdown")
		-- going to another zone takes the player out of the first one
		expect(PS:Join(a, "solo")).toBe(true)
		expect(PS:Get(a).zone).toBe("solo")
		expect(PS:Snapshot(a).zones[2].players).toBe(0)
		-- on the way to the game nobody leaves the queue or changes the zone
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(2)
		ok, why = PS:LeaveQueue(three)
		expect(why).toBe("launching")
		ok, why = PS:Join(party.members[2], "quartet")
		expect(why).toBe("launching")
		expect(PS:ZoneOf(party.members[2])).toBe("trio")
	end) end)

	it("M10 snapshot: the party, the viewer's place in the queue in every state and the four zones", function() fixture(function(f)
		local a = f.bot(1)
		local snap = PS:Snapshot(a)
		expect(snap.me).toBe(a.UserId)
		expect(snap.party.leader).toBe(a.UserId)
		expect(snap.party.launching).toBe(false)
		expect(snap.party.max).toBe(PartyCfg.MaxSize)
		expect(snap.queue).toBe(nil)
		expect(#snap.zones).toBe(#ORDER)
		for i, id in ipairs(ORDER) do
			local z = snap.zones[i]
			expect(z.id).toBe(id)
			expect(z.capacity).toBe(i)
			expect(z.players).toBe(0)
			expect(z.countdown).toBe(false)
			expect(z.ends).toBe(nil)
		end
		-- waiting
		PS:SetZone(a, "trio")
		snap = PS:Snapshot(a)
		expect(snap.party.members[1].zone).toBe("trio")
		local q = snap.queue
		expect(q.zone).toBe("trio")
		expect(q.capacity).toBe(3)
		expect(q.state).toBe("waiting")
		expect(q.have).toBe(1)
		expect(q.need).toBe(2)
		expect(q.ends).toBe(nil)
		expect(snap.zones[3].players).toBe(1)
		-- countdown: times are on the clock the clients share with the server
		local pair, party = f.party(2, 2, "trio")
		local guest = party.members[2]
		snap = PS:Snapshot(guest)
		q = snap.queue
		expect(q.state).toBe("countdown")
		expect(q.have).toBe(3)
		expect(q.need).toBe(0)
		expect(q.ends).toNear(workspace:GetServerTimeNow() + LobbyCfg.CountdownSeconds, 1)
		expect(snap.zones[3].players).toBe(3)
		expect(snap.zones[3].countdown).toBe(true)
		expect(snap.zones[3].ends).toNear(q.ends, 1)
		expect(snap.zones[2].countdown).toBe(false)
		f.t += 2
		expect(PS:Snapshot(a).queue.ends).toNear(workspace:GetServerTimeNow() + LobbyCfg.CountdownSeconds - 2, 1)
		-- too_big for the one who went to a zone that is too small, split for the one who stayed
		PS:SetZone(pair, "solo")
		q = PS:Snapshot(pair).queue
		expect(q.zone).toBe("solo")
		expect(q.capacity).toBe(1)
		expect(q.state).toBe("too_big")
		q = PS:Snapshot(guest).queue
		expect(q.zone).toBe("trio")
		expect(q.state).toBe("split")
		expect(q.missing[1]).toBe(pair.DisplayName)
		snap = PS:Snapshot(a)
		expect(snap.queue.state).toBe("waiting") -- the group stopped
		expect(snap.zones[1].players).toBe(1)
		expect(snap.zones[3].players).toBe(2)
		expect(snap.zones[3].countdown).toBe(false)
		expect(snap.zones[3].ends).toBe(nil)
		-- cooldown after a launch that failed, then launching
		PS:SetZone(pair, "trio")
		f.failSend = true
		f.pass(LobbyCfg.CountdownSeconds)
		q = PS:Snapshot(a).queue
		expect(q.state).toBe("cooldown")
		expect(q.retryAt).toNear(workspace:GetServerTimeNow() + LobbyCfg.RetryCooldownSeconds, 1)
		expect(q.have).toBe(nil)
		f.failSend = false
		f.pass(LobbyCfg.RetryCooldownSeconds)
		f.pass(LobbyCfg.CountdownSeconds)
		snap = PS:Snapshot(a)
		expect(snap.party.launching).toBe(true)
		expect(snap.queue.zone).toBe("trio")
		expect(snap.queue.state).toBe("launching")
		expect(snap.zones[3].players).toBe(3)
		expect(snap.zones[3].countdown).toBe(false)
	end) end)

	it("M10 switch: with PrivateServerPerParty every launch reserves a server of its own", function() fixture(function(f)
		expect(LobbyCfg.PrivateServerPerParty).toBe(false) -- decision 2: teams of one format share a server
		LobbyCfg.PrivateServerPerParty = true
		expect(f.launch(f.party(1, 2, "duo"))).toBe(true)
		expect(f.launch(f.party(3, 2, "duo"))).toBe(true)
		expect(f.reserved).toBe(2)
		expect(f.sends[2].code).toBe("code2")
	end) end)

	it("M9 return: a player whose team is still on a game server is offered the way back and gets a ticket to it", function() fixture(function(f)
		local bot = f.bot(1)
		expect(MS:Greet(bot)).toBe(nil)
		local ok, why = PS:Rejoin(bot)
		expect(ok).toBe(false)
		expect(why).toBe("gone")
		Matchmaking.PutSession(bot.UserId, {host = 777, hostName = "Host", format = "trio", server = "srv", code = "key", members = {777, bot.UserId}})
		expect(MS:Greet(bot).host).toBe(777)
		local offer = PS:Snapshot(bot).rejoin
		expect(offer.hostName).toBe("Host")
		expect(offer.format).toBe("trio")
		-- going back from inside a zone: the countdown there stops and the player returns to the team
		PS:SetZone(bot, "solo")
		expect(f.state(bot)).toBe("countdown")
		expect(PS:Rejoin(bot)).toBe(true)
		expect(f.sends[1].code).toBe("key")
		expect(f.sends[1].players[1]).toBe(bot)
		expect(f.reserved).toBe(0)
		local ticket = Matchmaking.TakeTicket(bot.UserId, "srv")
		expect(ticket.host).toBe(777)
		expect(ticket.rejoin).toBe(true)
		expect(f.state(bot)).toBe("launching")
		f.pass(LobbyCfg.CountdownSeconds)
		expect(#f.sends).toBe(1)
		-- the team has left the game meanwhile: the offer is withdrawn
		local other = f.bot(2)
		Matchmaking.PutSession(other.UserId, {host = 778, hostName = "H", format = "duo", server = "s2", code = "k2", members = {}})
		MS:Greet(other)
		f.t += Matchmaking.Ttl.Session + 1
		ok, why = PS:Rejoin(other)
		expect(why).toBe("gone")
		expect(PS:Snapshot(other).rejoin).toBe(nil)
		expect(PS:Get(other).launching).toBe(false)
	end) end)

	it("M10 world: the built lobby has the four zones with standing places and exits, apart from each other and from the spawns", function()
		local lobby = workspace.Lobby
		local zones = PS.Zones()
		expect(#zones).toBe(#ORDER)
		for i, id in ipairs(ORDER) do
			local model, zone = lobby.Zones["Zone_" .. id], zones[i]
			expect(zone.id).toBe(id)
			expect(zone.capacity).toBe(i)
			expect(model:GetAttribute("Mode")).toBe(id)
			expect(model:GetAttribute("Capacity")).toBe(i)
			expect(model:GetAttribute("Radius") > 0).toBeTruthy()
			expect(zone.radius).toBe(model:GetAttribute("Radius"))
			expect(zone.center).toBe(model.Zone.Position)
			expect(model:FindFirstChild("Runes") ~= nil and model:FindFirstChild("Sign") ~= nil).toBeTruthy()
			-- a standing place for everyone the zone holds; Join puts a character 3 studs above one
			expect(#model.Spots:GetChildren()).toBe(i)
			expect(#zone.spots).toBe(i)
			for _, spot in ipairs(zone.spots) do expect(PS.ZoneAt(spot + Vector3.new(0, 3, 0))).toBe(id) end
			-- the centre and the edge with its margin are in the zone; the exit and the air above are not
			local reach = zone.radius + LobbyCfg.ZoneMargin
			expect(PS.ZoneAt(zone.center)).toBe(id)
			expect(PS.ZoneAt(zone.center + Vector3.new(reach - 0.1, 3, 0))).toBe(id)
			expect(PS.ZoneAt(zone.center + Vector3.new(reach + 0.1, 3, 0))).toBe(nil)
			expect(PS.ZoneAt(zone.center + Vector3.new(0, LobbyCfg.ZoneHeight + 1, 0))).toBe(nil)
			expect(zone.exit).toBe(model.Exit.Position)
			expect(PS.ZoneAt(zone.exit)).toBe(nil)
			expect(PS.ZoneAt(zone.exit + Vector3.new(0, 3, 0))).toBe(nil)
			for j = i + 1, #zones do -- the zones do not overlap
				local d = zone.center - zones[j].center
				expect(Vector3.new(d.X, 0, d.Z).Magnitude > reach + zones[j].radius + LobbyCfg.ZoneMargin).toBeTruthy()
			end
		end
		-- nobody arrives inside a zone
		for n = 1, 8 do expect(PS.ZoneAt(lobby["Spawn_" .. n].Position)).toBe(nil) end
	end)

	it("M9 live: the player in this session has a party of one and sees the others in the lobby", function() fixture(function(f)
		local player = game:GetService("Players"):GetPlayers()[1]
		expect(player ~= nil).toBeTruthy()
		local snap = PS:Snapshot(player)
		expect(snap.me).toBe(player.UserId)
		expect(snap.party.leader).toBe(player.UserId)
		expect(#snap.party.members).toBe(1)
		expect(snap.party.members[1].zone).toBe(PS:ZoneOf(player))
		local bot = f.bot(1)
		expect(listed(player, bot).size).toBe(1)
	end) end)
end
