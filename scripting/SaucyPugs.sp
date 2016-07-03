#include <sourcemod>

enum GameState
{
	GameState_Idle,
	GameState_WaitingForPlayers,
	GameState_CaptainDecision,
	GameState_PickingPlayers,
	GameState_Ready,
	GameState_Playing,
};

enum GameType
{
	GameType_Undecided,
	GameType_Fours,
	GameType_Sixes,
	GameType_HL,
}

enum CaptainDecisionMethod
{
	CaptainMethod_Undecided,
	CaptainMethod_CaptainPick,
	CaptainMethod_SpectateCall,
};

/** Forwards **/
Handle g_hOnReady = INVALID_HANDLE;
Handle g_hOnUnready = INVALID_HANDLE;
Handle g_hOnPugReady = INVALID_HANDLE;
Handle g_hOnPugStart = INVALID_HANDLE;

/** Globals **/
int g_PlayersReady = 0;
int g_CaptainOne = -1;
int g_CaptainTwo = -1;
bool g_PlayerReady[MAXPLAYERS + 1];
GameState g_GameState = GameState_Idle;
GameType g_GameType = GameType_Undecided;
CaptainDecisionMethod g_CaptainMethod = CaptainMethod_Undecided;


public Plugin myinfo = 
{
	name = "Saucy Pugs (fucking kill me)",
	author = "Alex",
	description = "SourceMod plugin for pugs.",
	version = "1.0",
	url = "http://rnndm.xyz/saucy_pugs"
};

/**
 * Called when the plugin starts.
 **/
public void OnPluginStart()
{
	AddCommand("setup", Command_Setup, "Sets up the pug");
	AddCommand("mode", Command_Mode, "Sets the game mode (4v4, 6v6 or 9v9)");
	// AddCommand("medic", Command_MedicMode, "Sets the medic decision mode (captain or spectate call)");
	AddCommand("ready", Command_Ready, "Marks yourself as ready");
	AddCommand("unready", Command_Unready, "Marks yourself as unready");
	// AddCommand("captain", Command_Captain, "Selects yourself as a team captain");

	// Create forwards.
	g_hOnReady = CreateGlobalForward("SaucyPugs_OnReady", ET_Ignore, Param_Cell);
	g_hOnUnready = CreateGlobalForward("SaucyPugs_OnUnready", ET_Ignore, Param_Cell);
	g_hOnPugReady = CreateGlobalForward("SaucyPugs_OnPugReady", ET_Ignore);
	g_hOnPugStart = CreateGlobalForward("SaucyPugs_OnPugStart", ET_Ignore);
}

/**
 * Called when a client connects to the server.
 **/
public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
	g_PlayerReady[client] = false;
	return true;
}

/**
 * Called when a client disconnects from the server.
 **/
public void OnClientDisconnect_Post(int client)
{
	g_PlayerReady[client] = false;
}

Action Command_Setup(int client, int args)
{
	if (args < 0)
	{
		ReplyToCommand(client, "Invalid arguments");

		return Plugin_Handled;
	}

	if (g_GameType != GameType_Undecided && g_CaptainMethod != CaptainMethod_Undecided)
	{
		if (g_GameState == GameState_Idle)
		{
			// Set state amd start the player check timer.
			g_GameState = GameState_WaitingForPlayers;
			CreateTimer(1.0, Timer_CheckPugReady, _, TIMER_REPEAT);

			// Reply with the 'PugSetup' translation,
			// indicating that the pug has successfully been started.
			ReplyToCommand(client, "%T", "PugSetup", client);

			return Plugin_Handled;
		}
		else
		{
			// Reply with the 'PugAlreadyStarted' translation,
			// indicating that the pug has already been started.
			ReplyToCommand(client, "%T", "PugAlreadyStarted", client);

			return Plugin_Handled;
		}
	}
	else
	{
		// Reply with the 'PugSettingsNotSet' translation,
		// indicating that the gametype and medic mode is not set.
		ReplyToCommand(client, "%T", "PugSettingsNotSet", client);

		return Plugin_Handled;
	}
}

Action Command_Mode(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%T", "Command_Mode_Usage", client);

		return Plugin_Handled;
	}

	if (g_GameState == GameState_Idle || g_GameState == GameState_WaitingForPlayers)
	{
		// Get the first argument.
		char type[10];
		GetCmdArg(1, type, sizeof(type));

		// Set the game type.
		g_GameType = GameTypeFromString(type);

		// Lowercase the string argument and
		// print it out.
		char lowercase[10];
		ToLowerCase(type, lowercase, sizeof(lowercase));
		ReplyToCommand(client, "%T", "Command_Mode_SetMode", client, lowercase);

		return Plugin_Handled;
	}
	else
	{
		ReplyToCommand(client, "%T", "Command_Mode_AlreadyStarted", client);

		return Plugin_Handled;
	}
}

Action Command_Ready(int client, int args)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		g_PlayerReady[client] = true;

		Call_StartForward(g_hOnReady)
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		// TODO: Handle the player not being valid.
	}

	return Plugin_Handled;
}

Action Command_Unready(int client, int args)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		g_PlayerReady[client] = false;

		Call_StartForward(g_hOnUnready);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		// TODO: Handle the player not being valid.
	}

	return Plugin_Handled;
}

void AddCommand(const char[] command, ConCmd callback, const char[] description)
{
	char smCommandBuffer[64];
	Format(smCommandBuffer, sizeof(smCommandBuffer), "sm_%s", command);
	RegConsoleCmd(smCommandBuffer, callback, description);
}

Action Timer_CheckPugReady(Handle timer)
{
	g_PlayersReady = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i) && g_PlayerReady[i])
		{
			g_PlayersReady++;
		}
	}

	// Make sure the plugin is setup with a gametype, captain method, and that the game is idle.
	if (g_GameState == GameState_Idle && g_GameType != GameType_Undecided && g_CaptainMethod != CaptainMethod_Undecided)
	{
		if (g_PlayersReady >= GetRequiredPlayers())
		{
			// We can begin the captain selection.
			if (g_CaptainMethod == CaptainMethod_CaptainPick)
			{
				// Start a timer for every 1 second, checking if two people have typed .captain.
				// TODO
			}

			// End this timer.
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

/**
 * Gets the amount of required players for the selected gametype.
 * Note: If gametype is 'GameType_Undecided', this function will return 0.
 */
int GetRequiredPlayers()
{
	switch (g_GameType)
	{
		case GameType_Undecided:
		{
			return 0;
		}

		case GameType_Fours:
		{
			// 4 players per team.
			return 8;
		}

		case GameType_Sixes:
		{
			// 6 players per team.
			return 12;
		}

		case GameType_HL:
		{
			// 9 players per team.
			return 18;
		}
	}

	// Default to -1.
	return -1;
}

GameType GameTypeFromString(const char[] str)
{
	if (strcmp(str, "4v4") == 0 || strcmp(str, "4V4") == 0)
	{
		return GameType_Fours;
	}

	if (strcmp(str, "6v6") == 0 || strcmp(str, "6V6") == 0)
	{
		return GameType_Sixes;
	}

	if (strcmp(str, "9v9") == 0 || strcmp(str, "9V9") == 0)
	{
		return GameType_HL;
	}

	return GameType_Undecided;
}

void ToLowerCase(const char[] str, char[] buffer, int bufferSize)
{
	int n = 0;
	while (str[n] != '\0' && n < (bufferSize - 1))
	{
		buffer[n] = CharToUpper(str[n]);

		n++;
	}

	buffer[n] = '\0';
}

/**
 * Send the announcement of the game 
 */
void SendAnnouncement()
{
	// TODO: Announcements.
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}