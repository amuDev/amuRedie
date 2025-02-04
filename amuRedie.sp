#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

bool g_bIsGhost[MAXPLAYERS+1]
	 , g_bNoclipEnabled[MAXPLAYERS+1];

int g_iCollision;

float g_fNewHullValues[] = {
// SEE https://developer.valvesoftware.com/wiki/Player_Entity
	 0.0,   0.0,   64.0,    // Eye position (m_vView)

	 0.0,   0.0,  0.0,      // hull min (m_vHullMin)
	 0.1,   0.1,  0.1,      // hull max (m_vHullMax)

	 0.0,   0.0,   0.0,     // duck hull min (m_vDuckHullMin)
	 0.1,   0.1,   0.1,     // duck hull max (m_vDuckHullMax)
	 0.0,   0.0,   28.0,    // duck eye position (m_vDuckView)

	-10.0, -10.0, -10.0,    // observer hull min (m_vObsHullMin)
	 10.0 , 10.0,  10.0,    // observer hull max (m_vObsHullMax)

	 0.0,   0.0,   14.0     // dead view height (m_vDeadViewHeight)
};
float g_fOldHullValues[sizeof(g_fNewHullValues)];

Address g_CSViewVectors;

public Plugin myinfo = {
	name = "amuRedie",
	author = "hiiamu",
	description = "Better redie plugin with extra features",
	version = "0.1.0",
	url = "/id/hiiamu/"
};

public void OnPluginStart() {
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);

	AddNormalSoundHook(view_as<NormalSHook>(OnSoundPlayed));

	CreateTimer(90.0, Timer_Advert, _, TIMER_REPEAT);

	RegConsoleCmd("sm_redie", Client_Redie, "Respawn when dead");
	RegConsoleCmd("sm_ghost", Client_Redie, "Respawn when dead");
	RegConsoleCmd("sm_unredie", Client_UnRedie, "Return to spec after redie");
	RegConsoleCmd("sm_unghost", Client_UnRedie, "Return to spec after redie");
	RegAdminCmd("sm_listghosts", Admin_ListRedie, ADMFLAG_GENERIC, "Spectate players in redie");
	//RegConsoleCmd("sm_rediemenu", Client_RedieMenu, "Show redie menu");

	g_iCollision = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");

	for(int i = 0; i <= MaxClients; i++) {
		if(IsValidClient(i))
			OnClientPutInServer(i);
	}
}

// was gonna do OnPluginStart, but not sure if GameRules has been initialized then
public void OnMapStart() {
	Handle hGameConf = LoadGameConfigFile("changehull.games");
	if(hGameConf == INVALID_HANDLE)
		SetFailState("Can't find changehull.games.txt gamedata.");

	g_CSViewVectors = GameConfGetAddress(hGameConf, "g_CSViewVectors");
	if(g_CSViewVectors == Address_Null)
		SetFailState("Couldn't get address of g_CSViewVectors");

/*
	for( int i = 0; i < sizeof( g_fNewHullValues ); i++ ) {
		g_fOldHullValues[i] = view_as<float>( LoadFromAddress( g_CSViewVectors + view_as<Address>( i*4 ), NumberType_Int32 ) );
		StoreToAddress( g_CSViewVectors + view_as<Address>( i*4 ), view_as<int>( g_fNewHullValues[i] ), NumberType_Int32 );
	}
*/
	delete hGameConf;

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnClientPutInServer(int client) {
	if(IsValidClient(client)) {
		g_bIsGhost[client] = false;
		g_bNoclipEnabled[client] = false;
	}
}

public void OnPluginEnd() {
	// restore the original hull values, if we patched them.
	RepatchGame();
}

public Action Client_Redie(int client, int args) {
	if(IsValidClient(client))
		Redie(client);
}

public Action Client_UnRedie(int client, int args) {
	if(IsValidClient(client))
		UnRedie(client);
}

public Action Admin_ListRedie(int client, int args) {
	if(IsValidClient(client)) {
		char szRedieUser[64];
		Menu menu = new Menu(RedieListHandler);
		menu.SetTitle("Players currently in redie");
		for(int i = 0; i <= MaxClients; i++) {
			if(IsValidClient(i)) {
				if(g_bIsGhost[i]) {
					Format(szRedieUser, 64, "%N", i);
					char szUserIndex[32];
					Format(szUserIndex, 32, "%i", GetClientSerial(i));
					menu.AddItem(szUserIndex, szRedieUser);
				}
			}
		}
		PrintToChat(client, "\x01[\x03Redie\x01] \x04Select user to spectate");
		// open menu and show list
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

public int RedieListHandler(Menu menu, MenuAction action, int client, int select) {
	if(action == MenuAction_Select) {
		if(IsPlayerAlive(client)) {
			PrintToChat(client, "\x01[\x03Redie\x01] \x04To spectate a player in redie, you must first be dead.");
		}
		else {
			char szInfo[32];
			int iSerial;
			int iID;

			menu.GetItem(select, szInfo, sizeof(szInfo));

			iSerial = StringToInt(szInfo);
			iID = GetClientFromSerial(iSerial);

			FakeClientCommand(client, "spec_player \"%N\"", iID);
		}
	}
	if(action == MenuAction_End)
		delete menu;
}

void Redie(int client) {
	if(!IsValidClient(client)) {
		return;
	}
	else if(IsPlayerAlive(client)) {
		PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be dead to use redie.");
		return;
	}
	else if(GetClientTeam(client) <= 1) {
		PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be on a team.");
		return;
	}

	g_bIsGhost[client] = true;
	UnpatchGame();
	CS_RespawnPlayer(client);
	return;
}

void UnRedie(int client) {
	if(g_bIsGhost[client]) {
		g_bIsGhost[client] = false;
		RepatchGame();
		//SetEntProp(client, Prop_Send, "m_lifeState", 0);
		ForcePlayerSuicide(client);

		ReplyToCommand(client, "\x01[\x03Redie\x01] \x04You have been removed from redie.");
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(g_bIsGhost[client]) {
		g_bNoclipEnabled[client] = false;

		return Plugin_Handled;
	} else
		PrintToChat(client, "\x01[\x03Redie\x01] \x04Type '!redie' to become a ghost!");

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsValidClient(client)) {
		if(g_bIsGhost[client]) {
			//SetEntProp(client, Prop_Send, "m_lifeState", 1);
			SetEntData(client, g_iCollision, 2, 4, true);
			SetEntProp(client, Prop_Send, "m_nHitboxSet", 2);
			SetEntityRenderMode(client, RENDER_TRANSCOLOR);
			SetEntityRenderColor(client, 111, 1, 104, 255);
		}
		else {
			SetEntProp(client, Prop_Send, "m_nHitboxSet", 0);
			g_bIsGhost[client] = false;
			SetEntityRenderMode(client, RENDER_NORMAL);
			SetEntityRenderColor(client, -1, -1, -1, 255);
			g_bNoclipEnabled[client] = false;
		}

		SDKHook(client, SDKHook_SetTransmit, Hook_HideGhosts);
	}
}

public Action OnSoundPlayed(int[] clients, int &numClients, char[] sample, int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char[] soundEntry, int &seed) {
	if(IsValidClient(entity) && g_bIsGhost[entity])
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsValidClient(i) && g_bIsGhost[i]) {
			UnRedie(i);
			RepatchGame();
		}
	}
}

public Action Timer_Advert(Handle timer) {
	PrintToChatAll("\x01[\x03Redie\x01] \x04This server is running \x06Redie\x04, try /redie when you die!");

	return Plugin_Continue;
}

public Action Hook_HideGhosts(int entity, int client) {
	if(g_bIsGhost[entity]) {
		if(g_bIsGhost[client] || !IsPlayerAlive(client))
			return Plugin_Continue;

		return Plugin_Handled;
	}

	return Plugin_Continue;
/*
	if(!g_bIsGhost[client] && g_bIsGhost[entity])
		return Plugin_Handled;

	else if(g_bIsGhost[client] && g_bIsGhost[entity])
		return Plugin_Continue;

	return Plugin_Continue;
*/
}

// extensive valid check
stock bool IsValidClient(int client) {
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	if (IsFakeClient(client)) return false;
	if (IsClientSourceTV(client))return false;
	return IsClientInGame(client);
}

void UnpatchGame() {
	if(g_CSViewVectors != Address_Null) {
		for(int i = 0; i < sizeof(g_fNewHullValues); i++) {
			g_fOldHullValues[i] = view_as<float>(LoadFromAddress(g_CSViewVectors + view_as<Address>(i*4), NumberType_Int32));
			StoreToAddress(g_CSViewVectors + view_as<Address>(i*4), view_as<int>(g_fNewHullValues[i]), NumberType_Int32);
		}
	}
}

void RepatchGame() {
	if(g_CSViewVectors != Address_Null) {
		for(int i = 0; i < sizeof(g_fOldHullValues); i++)
			StoreToAddress(g_CSViewVectors + view_as<Address>( i*4 ), view_as<int>( g_fOldHullValues[i] ), NumberType_Int32 );
	}
}
