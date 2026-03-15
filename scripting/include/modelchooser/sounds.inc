#pragma semicolon 1
#pragma newdecls required

static DynamicHook g_hkDeathSound;

// Used for stopping
char g_szLastPlayedSound[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

methodmap Sounds
{
	public static void Init(GameData gamedata)
	{
		CreateTimer(2.0, Timer_CheckHealthRaise, _, TIMER_REPEAT);
		LoadDHookVirtual(gamedata, g_hkDeathSound, "CBasePlayer::DeathSound");
	}

	public static void PlayerInit(int client)
	{
		DHookEntity(g_hkDeathSound, false, client, _, Hook_DeathSound);
	}

	public static void HandlePlayerHurt(int client, int health)
	{
		if (playedHurtSoundAt[client] != -1 || currentTeam[client] == 1)
			return;

		PlayerModel model;
		if (GetSelectedModelAuto(client, model))
		{
			if (0 < health <= model.hurtSndHP.Rand())
			{
				Sounds.PlayRandom(GetSoundPack(model).GetSoundList("hurt"), client, client, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX);
				playedHurtSoundAt[client] = health;
			}
		}
	}
	
	public static void HandlePlayerSpawn(int client)
	{
		int m_hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (m_hRagdoll != -1)
		{
			Sounds.StopLast(client, SNDCHAN_STATIC, m_hRagdoll);
		}
		Sounds.StopLast(client, SNDCHAN_STATIC);
	}

	public static bool PlayRandom(ArrayList soundList, int client, int entity = SOUND_FROM_PLAYER, int channel = SNDCHAN_AUTO,
									bool toAll = false, int pitchMin = 100, int pitchMax = 100, float volume = SNDVOL_NORMAL)
	{
		if (soundList && soundList.Length)
		{
			int pitch = pitchMin == pitchMax? pitchMax : GetRandomInt(pitchMin, pitchMax);
			soundList.GetString(GetRandomInt(0, soundList.Length - 1), g_szLastPlayedSound[client], sizeof(g_szLastPlayedSound[]));
			
			if (toAll)
			{
				EmitSoundToAll(g_szLastPlayedSound[client], entity, channel, .volume = volume, .pitch = pitch);
			}
			else
			{
				EmitSoundToClient(client, g_szLastPlayedSound[client], entity, channel, .volume = volume, .pitch = pitch);
			}
			return true;
		}
		return false;
	}

	public static void StopLast(int client, int channel, int entity = -1)
	{
		StopSound(entity == -1 ? client : entity, channel, g_szLastPlayedSound[client]);
	}
}

static Action Timer_CheckHealthRaise(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (playedHurtSoundAt[i] != -1 && GetClientHealth(i) > playedHurtSoundAt[i])
			{
				playedHurtSoundAt[i] = -1;
			}
		}
	}
	return Plugin_Continue;
}

static MRESReturn Hook_DeathSound(int client, DHookParam hParams)
{
	if (UI.IsOpen(client) && !IsPlayerAlive(client))
	{
		UI.Exit(client, true);
	}

	PlayerModel model;
	if (GetSelectedModel(client, model))
	{
		Sounds.StopLast(client, SNDCHAN_BODY);
		Sounds.StopLast(client, SNDCHAN_STATIC);

		int target = client;
		int m_hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (m_hRagdoll != -1 && !(GetEntityFlags(m_hRagdoll) & FL_DISSOLVING))
		{
			target = m_hRagdoll;
		}
		
		if (Sounds.PlayRandom(GetSoundPack(model).GetSoundList("death"), client, target, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX))
			return MRES_Supercede;
	}
	return MRES_Ignored;
}

