-- Numbers of the lobby (milestones 9 and 10). They are technical, not balance
return {
	InviteSeconds = 30,       -- an invitation waits this long for an answer
	InvitesPerParty = 6,      -- unanswered invitations one leader may have at a time
	TeleportAttempts = 3,     -- tries of one teleport before the party is told that it failed
	TeleportRetrySeconds = 2,
	LaunchLockSeconds = 45,   -- a party that has set out cannot be changed for this long; then it is unlocked again
	-- Milestone 10: the four matchmaking zones. A zone is the server format with the same id in Config.Party
	-- (its capacity is the size of that format); this list is the single source of their order and colours
	Zones = {
		{id = "solo", color = Color3.fromRGB(96, 214, 140)},
		{id = "duo", color = Color3.fromRGB(92, 170, 255)},
		{id = "trio", color = Color3.fromRGB(255, 168, 72)},
		{id = "quartet", color = Color3.fromRGB(214, 112, 232)},
	},
	CountdownSeconds = 5,     -- the visible countdown of a full group before it is teleported
	ZoneMargin = 1,           -- studs outside the radius of a zone that still count as standing in it
	ZoneHeight = 10,          -- studs above or below the floor of a zone that still count
	StepSeconds = 0.25,       -- how often the server looks at the zones, the countdowns and the invitations
	RetryCooldownSeconds = 10, -- after a launch that failed the party waits this long and is queued again
	-- false: decision 2, variant A: parties of one format share a reserved game server, house by house.
	-- true: every launch gets a reserved game server of its own (the other houses of that server stay empty)
	PrivateServerPerParty = false,
}
