-- Party formats (design doc 2.1 and 2.2, decision 2). The same numbers as in Config.Party of the game place:
-- a party of `size` Guardians goes to a server of its format, which has `houses` houses
return {
	MaxSize = 4,
	ServerPlayers = 20,
	Formats = {
		{id = "solo", size = 1, houses = 20},
		{id = "duo", size = 2, houses = 10},
		{id = "trio", size = 3, houses = 6},
		{id = "quartet", size = 4, houses = 5},
	},
	-- Milestone 10: what a player chooses in the Expedition Circle. A mode is a range of party sizes. The format of
	-- the server is still the size of the party when it sets out (design doc 2.2), so a Squad of three goes to a
	-- trio server and a Squad of four to a quartet server
	Modes = {
		{id = "solo", min = 1, max = 1},
		{id = "duo", min = 2, max = 2},
		{id = "squad", min = 3, max = 4},
	},
}
