-- Party formats (design doc 2.1 and 2.2, decision 2). The same numbers as in Config.Party of the game place:
-- a team of `size` Guardians goes to a server of its format, which has `houses` houses.
-- Milestone 10: every format has a matchmaking zone in the lobby (Config.Lobby.Zones, the same ids)
return {
	MaxSize = 4,
	ServerPlayers = 20,
	Formats = {
		{id = "solo", size = 1, houses = 20},
		{id = "duo", size = 2, houses = 10},
		{id = "trio", size = 3, houses = 6},
		{id = "quartet", size = 4, houses = 5},
	},
}
