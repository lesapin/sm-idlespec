#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PL_VERSION "1.0.5"

bool preventTeamBroadcast = false;

bool timerStopRepeat = false;
bool timerAlive = true;

int idleTime = 0;
float resetIdleTime = 0.0;

ConVar g_cvEnabled;
ConVar g_cvKickFull;
ConVar g_cvVersion;
ConVar g_cvIdleMaxTime;

bool isEnabled = true;
bool kickIdleOnFull = true;

enum 
{
	TeamNone = 0,
	TeamSpec = 1
};

public Plugin myinfo =
{
	name = "Idle Spectators",
	author = "bzdmn",
	description = "Deal with idle spectators",
	version = PL_VERSION,
	url = "http://mge.me/"
};

/*
 * On-Functions
 */

public void OnPluginStart()
{
	Cvar_Set();

	CreateTimer(resetIdleTime, Timer_ResetIdle, _, TIMER_REPEAT);

	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
}

public void OnClientConnected(int client)
{
	if (isEnabled && kickIdleOnFull)
	{
		if (GetClientCount() == MaxClients)
		{
			timerStopRepeat = true;
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (isEnabled && !timerAlive)
	{
		timerAlive = true;
		timerStopRepeat = false;
		CreateTimer(resetIdleTime, Timer_ResetIdle, _, TIMER_REPEAT);
	}
}

/*
 * ConVars
 */

void Cvar_Set()
{
	g_cvEnabled = CreateConVar("sm_idlespec", "1",
		"Enable handling of idle spectators");

	g_cvKickFull = CreateConVar("sm_idlespec_kick_full", "1", 
		"Auto-kick idle spectators if the server is full");

	g_cvVersion = CreateConVar("sm_idlespec_version", PL_VERSION);

	// L4D: sv_spectatoridletime
	// CSS: sv_timeout
	g_cvIdleMaxTime = FindConVar("mp_idlemaxtime");
	g_cvIdleMaxTime.AddChangeHook(Cvar_IdleMaxTimeChange);

	idleTime = g_cvIdleMaxTime.IntValue;
	resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;
#if defined DEBUG
	PrintToServer("idleTime: %i, resetIdleTime: %f", idleTime, resetIdleTime);
#endif
}

void Cvar_IdleMaxTimeChange(ConVar cvar, char[] oldval, char[] newval)
{
	Timer_ResetIdle(null);

	idleTime = StringToInt(newval);
	resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;

	PrintToServer("[Idle Spectators] resetIdleTime changed to %f seconds", resetIdleTime);
}

/*
 * Events
 */

Action Event_PlayerTeam(Event ev, const char[] name, bool dontBroadcast)
{
	if (preventTeamBroadcast)
	{
		SetEventBroadcast(ev, true);
	}
	else
	{
		SetEventBroadcast(ev, dontBroadcast);
	}

	return Plugin_Continue;
}

void ResetClientIdleTime(int client)
{
	float eyeAngles[3];
	float eyePosition[3];

	// Get all properties of the spectator

	int iObsMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int hObsTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

	GetClientEyeAngles(client, eyeAngles);
	GetClientEyePosition(client, eyePosition);

	ChangeClientTeam(client, TeamNone);
	ChangeClientTeam(client, TeamSpec);

	// Reset the previous spectator state

	TeleportEntity(client, eyePosition, eyeAngles, NULL_VECTOR);

	SetEntProp(client, Prop_Send, "m_iObserverMode", iObsMode);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", hObsTarget);
#if defined DEBUG
	PrintToChat(client, "mode: %i, target: %i", iObsMode, hObsTarget);
	PrintToChat(client, "ang: %f %f %f", eyeAngles[0], eyeAngles[1], eyeAngles[2]);
	PrintToChat(client, "pos: %f %f %f", eyePosition[0], eyePosition[1], eyePosition[2]);
#endif
}

Action Timer_ResetIdle(Handle timer)
{
#if defined DEBUG
	PrintToChatAll("Timer_ResetIdle");
#endif
	preventTeamBroadcast = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsClientObserver(client))
		{
			ResetClientIdleTime(client);
		}
	}

	preventTeamBroadcast = false;

	if (timerStopRepeat)
	{
		timerAlive = false;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}
