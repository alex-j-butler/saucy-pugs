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
int g_TeamOnePlayers = 0;
int g_TeamTwoPlayers = 0;
bool g_PlayerReady[MAXPLAYERS + 1];
Team g_PlayerTeam[MAXPLAYERS + 1];
GameState g_GameState = GameState_Idle;
GameType g_GameType = GameType_Undecided;
CaptainDecisionMethod g_CaptainMethod = CaptainMethod_Undecided;
Team g_PickingTeam = Team_Undecided;

Handle g_hHudSyncReady;
Handle g_hHudSyncUnready;


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
	LoadTranslations("saucypugs.phrases");

	AddCommand("setup", Command_Setup, "Sets up the pug");
	AddCommand("mode", Command_Mode, "Sets the game mode (4v4, 6v6 or 9v9)");
	AddCommand("medic", Command_MedicMode, "Sets the medic decision mode (captain or spectate call)");
	AddCommand("ready", Command_Ready, "Marks yourself as ready");
	AddCommand("unready", Command_Unready, "Marks yourself as unready");
	AddCommand("captain", Command_Captain, "Selects yourself as a team captain");

	// Create forwards.
	g_hOnReady = CreateGlobalForward("SaucyPugs_OnReady", ET_Ignore, Param_Cell);
	g_hOnUnready = CreateGlobalForward("SaucyPugs_OnUnready", ET_Ignore, Param_Cell);
	g_hOnPugReady = CreateGlobalForward("SaucyPugs_OnPugReady", ET_Ignore);
	g_hOnPugStart = CreateGlobalForward("SaucyPugs_OnPugStart", ET_Ignore);

	g_hHudSyncReady = CreateHudSynchronizer();
	g_hHudSyncUnready = CreateHudSynchronizer();
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

	if (g_GameType != GameType_Undecided && g_CaptainMethod != CaptainMethod_Undecided)
	{
		if (g_GameState == GameState_Idle)
		{
			// Set state and start the player check timer.
			g_GameState = GameState_WaitingForPlayers;
			CreateTimer(1.0, Timer_CheckPugReady, _, TIMER_REPEAT);
			CreateTimer(1.0, Timer_DrawReady, _, TIMER_REPEAT);

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

/**
 * Command to set the game mode.
 */
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
		GameType gameType = GameTypeFromString(type);
		if (gameType != GameType_Undecided)
		{
			g_GameType = gameType;

			// Lowercase the string argument and
			// print it out.
			char lowercase[10];
			ToLowerCase(type, lowercase, sizeof(lowercase));
			ReplyToCommand(client, "%T", "Command_Mode_SetMode", client, lowercase, "mode");
		}
		else
		{
			ReplyToCommand(client, "%T", "Command_Mode_Usage", client);

			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else
	{
		ReplyToCommand(client, "%T", "Command_Mode_AlreadyStarted", client);

		return Plugin_Handled;
	}
}

/**
 * Command to set the medic decision mode.
 */
Action Command_MedicMode(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%T", "Command_MedicMode_Usage", client);

		return Plugin_Handled;
	}

	if (g_GameState == GameState_Idle || g_GameState == GameState_WaitingForPlayers)
	{
		// Get the first argument.
		char type[50];
		GetCmdArg(1, type, sizeof(type));

		// Set the medic mode.
		CaptainDecisionMethod method = CaptainMethodFromString(type);
		if (method != CaptainMethod_Undecided)
		{
			g_CaptainMethod = method;

			// Lowercase the string argument and
			// print it out.
			char lowercase[10];
			ToLowerCase(type, lowercase, sizeof(lowercase));
			ReplyToCommand(client, "%T", "Command_Mode_SetMode", client, lowercase, "medic mode");
		}
		else
		{
			ReplyToCommand(client, "%T", "Command_MedicMode_Usage", client);

			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else
	{
		ReplyToCommand(client, "%T", "Command_Mode_AlreadyStarted", client);

		return Plugin_Handled;
	}
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

Action Command_Captain(int client, int args)
{
	if (g_GameState != GameState_CaptainDecision)
	{
		ReplyToCommand(client, "%T", "Unable to ready", client);

		return Plugin_Handled;
	}

	if (IsValidClient(client) && !IsFakeClient(client))
	{
		if (g_CaptainOne == -1)
		{
			// Set captain one and print message.
			g_CaptainOne = client;

			ReplyToCommand(client, "%T", "Ready status set", client, "captain one");

			return Plugin_Handled;
		}
		else if (g_CaptainTwo == -1)
		{
			// Set captain two and print message.
			g_CaptainTwo = client;

			ReplyToCommand(client, "%T", "Ready status set", client, "captain two");

			return Plugin_Handled;
		}
		else
		{
			// Print already chosen message.
			ReplyToCommand(client, "%T", "Captains already chosen", client);

			return Plugin_Handled;
		}
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

	// Make sure the plugin is setup with a gametype, captain method, and that the game is idle.
	if (g_GameState == GameState_Idle && g_GameType != GameType_Undecided && g_CaptainMethod != CaptainMethod_Undecided)
	{
		if (g_PlayersReady >= GetRequiredPlayers())
		{
			// We can begin the captain selection.
			if (g_CaptainMethod == CaptainMethod_CaptainPick)
			{
				// Start a timer for every 5 second, checking if two people have typed .captain.
				// TODO
				CreateTimer(5.0, Timer_CheckCaptains, _, TIMER_REPEAT);
			}

			// End this timer.
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
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
	if (g_GameState != GameState_CaptainDecision)
	{
		return Plugin_Stop;
	}

	if (IsValidClient(g_CaptainOne) && !IsFakeClient(g_CaptainOne) && IsValidClient(g_CaptainTwo) && !IsFakeClient(g_CaptainTwo))
	{
		// Begin picking.
		g_GameState = GameState_PickingPlayers;

		// Move everyone to spectator.
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				if (i != g_CaptainOne && i != g_CaptainTwo)
				{
					// 1 = Spectator.
					ChangeClientTeam(i, 1);
				}
			}
		}

		// Let captain one pick first.
		g_PickingTeam = Team_One;

		Menu menu = BuildPlayerMenu();
		menu.Display(g_CaptainOne, MENU_TIME_FOREVER);

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

CaptainDecisionMethod CaptainMethodFromString(const char[] str)
{
	char buffer[50];
	ToLowerCase(str, buffer, sizeof(buffer));

	if (strcmp(buffer, "captain") == 0)
	{
		return CaptainMethod_CaptainPick;
	}

	if (strcmp(buffer, "spectate") == 0)
	{
		return CaptainMethod_SpectateCall;
	}

	return CaptainMethod_Undecided;
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

Menu BuildPlayerMenu()
{
	Menu menu = new Menu(Menu_SelectPlayer);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			if (g_PlayerTeam[i] == Team_Undecided)
			{
				char playerName[32];
				GetClientName(i, playerName, sizeof(playerName));

				char clientId[10];
				IntToString(i, clientId, sizeof(clientId));
				menu.AddItem(clientId, playerName);
			}
		}
	}

	menu.SetTitle("Choose a player:");

	return menu;
}

public int Menu_SelectPlayer(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char playerName[32];
		menu.GetItem(param2, playerName, sizeof(playerName));

		// Announce the player chosen, and move the player to the right team.
		if (g_CaptainOne == client)
		{
			// Move the chosen player to team one.
			g_PlayerTeam[param2] = Team_One;
			ChangeClientTeam(param2, 2);

			g_TeamOnePlayers++;
		}
		else if (g_CaptainTwo == client)
		{
			// Move the chosen player to team two.
			g_PlayerTeam[param2] = Team_Two;
			ChangeClientTeam(param2, 3);

			g_TeamTwoPlayers++;
		}
		else
		{
			return 1;
		}

		int requiredPlayers = GetRequiredPlayers();

		if (g_PickingTeam == Team_One)
		{
			if (g_TeamTwoPlayers != requiredPlayers / 2)
			{
				g_PickingTeam = Team_Two;
			}
			else
			{
				g_PickingTeam = Team_One;
			}
		}
		else if (g_PickingTeam == Team_Two)
		{
			if (g_TeamOnePlayers != requiredPlayers / 2)
			{
				g_PickingTeam = Team_One;
			}
			else
			{
				g_PickingTeam = Team_Two;
			}
		}

		
		if (g_TeamTwoPlayers == requiredPlayers / 2 && g_TeamOnePlayers == requiredPlayers / 2)
		{
			// Ready to starrrrrrt!
		}
		else
		{
			Menu newMenu = BuildPlayerMenu();

			// Show the menu for the person to choose next.
			if (g_PickingTeam == Team_One)
			{
				newMenu.Display(g_CaptainOne, MENU_TIME_FOREVER);
			}
			else if (g_PickingTeam == Team_Two)
			{
				newMenu.Display(g_CaptainTwo, MENU_TIME_FOREVER);
			}
		}
	}

	return 1;
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
