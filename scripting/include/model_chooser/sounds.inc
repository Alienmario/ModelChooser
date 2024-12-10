#pragma semicolon 1
#pragma newdecls required

public void Sounds_EventPlayerHurt(Event event, int client)
{
	if (playedHurtSoundAt[client] != -1 || currentTeam[client] == 1)
		return;
	
	int health = event.GetInt("health");

	PlayerModel model;
	if (GetSelectedModelAuto(client, model))
	{
		if (0 < health <= model.hurtSndHP.Rand())
		{
			SoundPack soundPack;
			GetSoundPack(model, soundPack);
			PlayRandomSound(soundPack.hurtSounds, client, client, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX);
			playedHurtSoundAt[client] = health;
		}
	}
}

public void Sounds_EventPlayerSpawn(Event event, int client)
{
	int m_hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (m_hRagdoll != -1)
	{
		StopSound(m_hRagdoll, SNDCHAN_STATIC, lastPlayedSound[client]);
	}
	StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
}

public Action Sounds_CheckHealthRaise(Handle timer)
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

public MRESReturn Hook_DeathSound(int client, DHookParam hParams)
{
	if (menuSelection[client].index != -1 && !IsPlayerAlive(client))
	{
		ExitModelChooser(client, true);
	}

	PlayerModel model;
	if (GetSelectedModel(client, model))
	{
		StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
		StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
		SoundPack soundPack;
		GetSoundPack(model, soundPack);

		int target = client;
		int m_hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (m_hRagdoll != -1 && !(GetEntityFlags(m_hRagdoll) & FL_DISSOLVING))
		{
			target = m_hRagdoll;
		}
		
		if (PlayRandomSound(soundPack.deathSounds, client, target, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX))
			return MRES_Supercede;
	}
	return MRES_Ignored;
}

bool PlayRandomSound(ArrayList soundList, int client, int entity = SOUND_FROM_PLAYER, int channel = SNDCHAN_AUTO,
						bool toAll = false, int pitchMin = 100, int pitchMax = 100, float volume = SNDVOL_NORMAL)
{
	if (soundList && soundList.Length)
	{
		int pitch = pitchMin == pitchMax? pitchMax : GetRandomInt(pitchMin, pitchMax);
		soundList.GetString(GetRandomInt(0, soundList.Length - 1), lastPlayedSound[client], sizeof(lastPlayedSound[]));
		
		if (toAll)
		{
			EmitSoundToAll(lastPlayedSound[client], entity, channel, .volume = volume, .pitch = pitch);
		}
		else
		{
			EmitSoundToClient(client, lastPlayedSound[client], entity, channel, .volume = volume, .pitch = pitch);
		}
		return true;
	}
	return false;
}

