#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PL_VERSION "1.1.2"

bool preventTeamBroadcast = false;

bool timerStopRepeat = false;
bool timerAlive = true;
bool timerRestart = false;

bool isEnabled = true;
bool kickIdleOnFull = true;

int idleTime = 0;
int tempIdleTime = 0;

float resetIdleTime = 0.0;

ConVar g_cvEnabled;
ConVar g_cvKickFull;
ConVar g_cvIdleMaxTime;

Timer tempTimer = INVALID_HANDLE;

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
	url = "https://mge.me/"
};

/**********************/
//	ON-Functions
/**********************/

public void OnPluginStart()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
}

public void OnConfigsExecuted()
{
	Cvar_Set();
	Timer_Start();
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
		timerStopRepeat = false;
		Timer_Start();
	}
}

public void OnMapEnd()
{
	if (tempTimer != INVALID_HANDLE)
	{
		CloseHandle(tempTimer);
		tempTimer = INVALID_HANDLE;
	}
}

/******************/
//	ConVars
/******************/

void Cvar_Set()
{
	g_cvEnabled = CreateConVar("sm_idlespec_autokick", "0",
		"Enable auto-kick for spectators if they are idle");

	g_cvKickFull = CreateConVar("sm_idlespec_kick_full", "1", 
		"Auto-kick idle spectators once the server is full");

	CreateConVar
	(
		"sm_idlespec_version", 
		PL_VERSION,
		"sm_idlespec version",
        	FCVAR_SPONLY | FCVAR_CHEAT
	);

	// L4D: sv_spectatoridletime
	// CSS: sv_timeout
	g_cvIdleMaxTime = FindConVar("mp_idlemaxtime");

	g_cvEnabled.AddChangeHook(Cvar_EnabledChange);
	g_cvKickFull.AddChangeHook(Cvar_KickFullChange);
	g_cvIdleMaxTime.AddChangeHook(Cvar_IdleMaxTimeChange);

	idleTime = g_cvIdleMaxTime.IntValue;
	resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;
#if defined DEBUG
	PrintToServer("idleTime: %i, resetIdleTime: %f", idleTime, resetIdleTime);
#endif
}

void Cvar_IdleMaxTimeChange(ConVar cvar, char[] oldval, char[] newval)
{
	tempIdleTime = StringToInt(newval);

	// Let the old timer run its course and restart it as a longer timer.
	if (tempIdleTime >= idleTime)
	{
		timerRestart = true;
	}
	// Create a temporary timer to fill-in the gap before our original timer can restart.
	else
	{	
		timerRestart = true;

		// Prevent currently idling spectators from getting insta-kicked.
		ResetIdleTimeAll();

		if (tempTimer != INVALID_HANDLE)
		{
			CloseHandle(tempTimer);
		}

		// Temporary timer that expires after at most N steps.
		int N = RoundToFloor(float(idleTime)/float(tempIdleTime));
		if (N <= 0) N = 1;

		tempTimer = CreateTimer
		(
			(tempIdleTime <= 1 ? 1.0 : float(tempIdleTime) - 1.0) * 60.0,
			Timer_RepeatNTimes, 
			N
		);
	}
}

void Cvar_EnabledChange(ConVar cvar, char[] oldval, char[] newval)
{
	if (StringToInt(newval) == 1)
	{
		timerStopRepeat = true;
		isEnabled = false;
	}
	else
	{
		if (!timerAlive && !timerRestart)
		{
			Timer_Start();
		}

		timerStopRepeat = false;
		isEnabled = true;		
	}
}

void Cvar_KickFullChange(ConVar cvar, char[] oldval, char[] newval)
{
	kickIdleOnFull = StringToInt(newval) == 1 ? true : false;
}

/******************/
//	Events
/******************/

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

/******************/
//	Misc
/******************/

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

void ResetIdleTimeAll()
{
	preventTeamBroadcast = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == TeamSpec)
		{
			ResetClientIdleTime(client);
		}
	}

	preventTeamBroadcast = false;
}

/******************/
//	Timers
/******************/

void Timer_Start()
{
	timerAlive = true;
	CreateTimer(resetIdleTime, Timer_ResetIdle,  _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_RepeatNTimes(Handle timer, int N)
{
	ResetIdleTimeAll();
	
	CloseHandle(tempTimer);
	
	if (N >= 1)
	{
		tempTimer = CreateTimer
		(
			(tempIdleTime <= 1 ? 1.0 : float(tempIdleTime) - 1.0) * 60.0,
			Timer_RepeatNTimes, 
			N - 1
		);
	}
	else
	{
		tempTimer = INVALID_HANDLE;
	}

	return Plugin_Stop;
}

Action Timer_ResetIdle(Handle timer)
{
#if defined DEBUG
	PrintToChatAll("Timer_ResetIdle");
#endif
	ResetIdleTimeAll();

	if (timerStopRepeat)
	{
		timerAlive = false;
		return Plugin_Stop;
	}
	else if (timerRestart)
	{
		timerRestart = false;

		idleTime = tempIdleTime;
		resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;

		LogMessage("resetIdleTime changed to %f seconds", resetIdleTime);

		if (tempTimer != INVALID_HANDLE)
		{
			CloseHandle(tempTimer);
			tempTimer = INVALID_HANDLE;
		}

		Timer_Start();

		return Plugin_Stop;
	} 

	return Plugin_Continue;
}
