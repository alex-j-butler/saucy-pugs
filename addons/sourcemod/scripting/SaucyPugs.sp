#include <sourcemod>

#define RED 0
#define BLU 1
#define TEAM_OFFSET 2

enum GameState
{
	GameState_Idle,
	GameState_WaitingForPlayers,
	GameState_WaitingForTeamReady,
	GameState_Playing,
};

enum GameType
{
	GameType_Undecided,
	GameType_Fours,
	GameType_Sixes,
	GameType_HL,
}

enum Team
{
	Team_Undecided,
	Team_One,
	Team_Two,
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
bool g_TeamReady[2] = { false, false };
GameState g_GameState = GameState_Idle;
GameType g_GameType = GameType_Undecided;

Handle g_hHudSyncReady;
Handle g_hHudSyncUnready;
Handle g_hHudSyncCountdown;

Handle g_hDrawHUDTimer;

ConVar g_cTournament;

public Plugin myinfo = 
{
	name = "Saucy Pugs",
	author = "Alex",
	description = "SourceMod plugin for pugs.",
	version = "1.1",
	url = ""
};

/**
 * Called when the plugin starts.
 **/
public void OnPluginStart()
{
	LoadTranslations("saucypugs.phrases");

	AddCommand("setup", Command_Setup, "Sets up the pug");
	AddCommand("ready", Command_Ready, "Marks yourself as ready");
	AddCommand("unready", Command_Unready, "Marks yourself as unready");

	// Create forwards.
	g_hOnReady = CreateGlobalForward("SaucyPugs_OnReady", ET_Ignore, Param_Cell);
	g_hOnUnready = CreateGlobalForward("SaucyPugs_OnUnready", ET_Ignore, Param_Cell);
	g_hOnPugReady = CreateGlobalForward("SaucyPugs_OnPugReady", ET_Ignore);
	g_hOnPugStart = CreateGlobalForward("SaucyPugs_OnPugStart", ET_Ignore);

	g_hHudSyncReady = CreateHudSynchronizer();
	g_hHudSyncUnready = CreateHudSynchronizer();
	g_hHudSyncCountdown = CreateHudSynchronizer();

	// Hook events.
	HookEvent("tournament_stateupdate", Event_TournamentStateUpdate);
	HookEvent("teamplay_game_over", Event_GameOver);
	HookEvent("tf_game_over", Event_GameOver);

	g_cTournament = FindConVar("mp_tournament");
}

public void Event_TournamentStateUpdate(Event event, const char[] name, bool dontBroadcast)
{
	int team = GetClientTeam(GetEventInt(event, "userid")) - TEAM_OFFSET;
	bool nameChange = GetEventBool(event, "namechange");
	bool readyState = GetEventBool(event, "readystate");

	if (!nameChange && g_GameState == GameState_WaitingForTeamReady)
	{
		g_TeamReady[team] = readyState;

		if (g_TeamReady[RED] && g_TeamReady[BLU])
		{
			g_GameState = GameState_Playing;
		}
		else
		{
			g_GameState = GameState_WaitingForTeamReady;
		}
	}
}

public Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
	g_TeamReady[RED] = false;
	g_TeamReady[BLU] = false;
	g_GameState = GameState_Idle;
}

public void OnMapStart()
{
	g_TeamReady[RED] = false;
	g_TeamReady[BLU] = false;
	g_GameState = GameState_Idle;
}

/**
 * Called when a client connects to the server.
 **/
public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
	g_PlayerReady[client] = false;

	if (g_CaptainOne == client)
	{
		g_CaptainOne = -1;
	}
	if (g_CaptainTwo == client)
	{
		g_CaptainTwo = -1;
	}

	return true;
}

/**
 * Called when a client disconnects from the server.
 **/
public void OnClientDisconnect_Post(int client)
{
	g_PlayerReady[client] = false;

	if (g_CaptainOne == client)
	{
		g_CaptainOne = -1;
	}
	if (g_CaptainTwo == client)
	{
		g_CaptainTwo = -1;
	}
}

/**
 * Command to setup the pug.
 */
Action Command_Setup(int client, int args)
{
	if (args < 0)
	{
		ReplyToCommand(client, "Invalid arguments");

		return Plugin_Handled;
	}

	// Display the mode selection dialog to the client.
	Menu menu = BuildModeMenu();
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

/**
 * Command for a player to ready themselves.
 */
Action Command_Ready(int client, int args)
{
	if (g_GameState != GameState_WaitingForPlayers)
	{
		ReplyToCommand(client, "%T", "Command_Ready_Unable", client);

		return Plugin_Handled;
	}

	if (IsValidClient(client) && !IsFakeClient(client))
	{
		g_PlayerReady[client] = true;

		Call_StartForward(g_hOnReady)
		Call_PushCell(client);
		Call_Finish();

		ReplyToCommand(client, "%T", "Command_Ready_Set", client, "ready");

		return Plugin_Handled;
	}
	else
	{
		// TODO: Handle the player not being valid.
	}

	return Plugin_Handled;
}

/**
 * Command for a player to unready themselves.
 */
Action Command_Unready(int client, int args)
{
	if (g_GameState != GameState_WaitingForPlayers)
	{
		ReplyToCommand(client, "%T", "Command_Ready_Unable", client);

		return Plugin_Handled;
	}

	if (IsValidClient(client) && !IsFakeClient(client))
	{
		g_PlayerReady[client] = false;

		Call_StartForward(g_hOnUnready);
		Call_PushCell(client);
		Call_Finish();

		ReplyToCommand(client, "%T", "Command_Ready_Set", client, "unready");

		return Plugin_Handled;
	}
	else
	{
		// TODO: Handle the player not being valid.
	}

	return Plugin_Handled;
}

/**
 * Add a client command.
 */
void AddCommand(const char[] command, ConCmd callback, const char[] description)
{
	char smCommandBuffer[64];
	Format(smCommandBuffer, sizeof(smCommandBuffer), "sm_%s", command);
	RegConsoleCmd(smCommandBuffer, callback, description);
}

/**
 * Repeated timer to check if the pug is ready to be started.
 */
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

	// Make sure the plugin is setup with a gametype and that the game is idle.
	if (g_GameState == GameState_Idle && g_GameType != GameType_Undecided)
	{
		if (g_PlayersReady >= GetRequiredPlayers())
		{
			CreateTimer(2.0, Timer_SpecWarn);

			// End this timer.
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

// Run the spectator warning.
Action Timer_SpecWarn(Handle timer)
{
	// Draw warning.
	PrintCenterTextAll("WARN");

	// Start the spec call timer with a random time
	float time = GetRandomFloat(4.0, 9.0);
	CreateTimer(time, Timer_SpecCall);
}

// Run the spectator call.
// and set tournament mode on
// and stop the ready hud.
Action Timer_SpecCall(Handle timer)
{
	// Draw spec call.
	PrintCenterTextAll("SPEC");

	// Set tournament mode on.
	g_cTournament.SetBool(1);

	// Stop the draw timer.
	KillTimer(g_hDrawHUDTimer);
}

/**
 * Repeated timer to draw the player list on everybody's screen
 * to show the ready status of players.
 */
Action Timer_DrawReady(Handle timer)
{
	if (g_GameState != GameState_WaitingForPlayers)
	{
		return Plugin_Stop;
	}

	char ready[512];
	char unready[512];

	Format(ready, sizeof(ready), "Ready\n=====");
	Format(unready, sizeof(unready), "Unready\n=======");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			char clientName[64];
			GetClientName(i, clientName, sizeof(clientName));

			if (g_PlayerReady[i] == true)
			{
				Format(ready, sizeof(ready), "%s\n%s", ready, clientName);
			}
			else
			{
				Format(unready, sizeof(unready), "%s\n%s", unready, clientName);
			}
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			SetHudTextParams(0.15, 0.1, 1.0, 0, 255, 0, 255);
			ShowSyncHudText(i, g_hHudSyncReady, ready);

			SetHudTextParams(0.35, 0.1, 1.0, 0, 255, 0, 255);
			ShowSyncHudText(i, g_hHudSyncUnready, unready);
		}
	}

	return Plugin_Continue;
}

/**
 * Repeated timer to check if two captains have been chosen
 * and if so, begin the picking routine.
 */
Action Timer_CheckCaptains(Handle timer)
{
	if (IsValidClient(g_CaptainOne) && !IsFakeClient(g_CaptainOne) && IsValidClient(g_CaptainTwo) && !IsFakeClient(g_CaptainTwo))
	{
		// Begin picking.
		g_GameState = GameState_PickingPlayers;

		return Plugin_Stop;
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
		buffer[n] = CharToLower(str[n]);

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

Menu BuildModeMenu()
{
	Menu menu = new Menu(Menu_SelectMode);

	menu.AddItem("4v4", "4v4");
	menu.AddItem("6v6", "6v6");
	menu.AddItem("9v9", "Highlander");

	menu.SetTitle("Choose a game type:");

	return menu;
}

public int Menu_SelectMode(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char type[10];
		bool found = menu.GetItem(param2, type, sizeof(type));

		g_GameType = GameTypeFromString(type);

		if (g_GameType != GameType_Undecided)
		{
			if (g_GameState == GameState_Idle)
			{
				// Set state and start the player check timer.
				g_GameState = GameState_WaitingForPlayers;
				CreateTimer(1.0, Timer_CheckPugReady, _, TIMER_REPEAT);
				g_hDrawHUDTimer = CreateTimer(1.0, Timer_DrawReady, _, TIMER_REPEAT);

				// Reply with the 'PugSetup' translation,
				// indicating that the pug has successfully been started.
				ReplyToCommand(client, "%T", "PugSetup", client);

				// Set tournament mode.
				g_cTournament.SetBool(0);

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
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return Plugin_Handled;
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
