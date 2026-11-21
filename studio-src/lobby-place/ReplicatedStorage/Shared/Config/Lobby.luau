-- Numbers of the lobby (milestones 9 and 10). They are technical, not balance
return {
	InviteSeconds = 30,       -- an invitation waits this long for an answer
	InvitesPerParty = 6,      -- unanswered invitations one leader may have at a time
	TeleportAttempts = 3,     -- tries of one teleport before the party is told that it failed
	TeleportRetrySeconds = 2,
	LaunchLockSeconds = 45,   -- a party that has set out cannot be changed for this long; then it is unlocked again
	-- Milestone 10: the Expedition Circle
	CountdownSeconds = 5,     -- the visible countdown before the party is teleported; the leader can cancel it
	RequireCircle = true,     -- every member has to stand in the Expedition Circle for the party to set out
	CircleMargin = 1.5,       -- studs around the circle that still count as standing in it
	StepSeconds = 0.25,       -- how often the server looks at the circle, the countdowns and the invitations
	-- false: decision 2, variant A — parties of one format share a reserved game server, house by house.
	-- true: every party gets a reserved game server of its own (the other houses of that server stay empty)
	PrivateServerPerParty = false,
}
