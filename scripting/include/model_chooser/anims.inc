#pragma semicolon 1
#pragma newdecls required

enum PLAYER_ANIM
{
	PLAYER_IDLE,
	PLAYER_WALK,
	PLAYER_JUMP,
	PLAYER_SUPERJUMP,
	PLAYER_DIE,
	PLAYER_ATTACK1,
	PLAYER_IN_VEHICLE,

	// TF Player animations
	PLAYER_RELOAD,
	PLAYER_START_AIMING,
	PLAYER_LEAVE_AIMING,
};

public MRESReturn Hook_SetAnimation(int client, DHookParam hParams)
{
	PLAYER_ANIM playerAnim = hParams.Get(1);

	float playbackRate = 1.0;
	int sequence = GetCustomSequenceForAnim(client, playerAnim, playbackRate);
	if (sequence > -1 && callResetSequence)
	{
		SetEntPropFloat(client, Prop_Data, "m_flPlaybackRate", playbackRate);
		if (GetEntProp(client, Prop_Send, "m_nSequence") != sequence)
		{
			SDKCall(callResetSequence, client, sequence);
			SetEntPropFloat(client, Prop_Data, "m_flCycle", 0.0);
		}
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

int GetCustomSequenceForAnim(int client, PLAYER_ANIM playerAnim, float &playbackRate)
{
	PlayerModel model;
	if (GetSelectedModelAuto(client, model))
	{
		if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
		{
			if (model.anim_noclip.seqList != null)
			{
				playbackRate = model.anim_noclip.rate;
				return model.anim_noclip.seqList.NextSequence();
			}
		}
		
		PlayerAnimation selectedAnim;
		if (playerAnim == PLAYER_IDLE)
		{
			selectedAnim = model.anim_idle;
		}
		else if (playerAnim == PLAYER_JUMP)
		{
			selectedAnim = model.anim_jump;
			float time = GetGameTime();
			if (time > nextJumpSound[client])
			{
				{
					SoundPack soundPack;
					GetSoundPack(model, soundPack);
					PlayRandomSound(soundPack.jumpSounds, client, client, SNDCHAN_STATIC, true, JUMP_PITCH_MIN, JUMP_PITCH_MAX, JUMP_VOL);
					nextJumpSound[client] = time + model.jumpSndParams.cooldown.Rand();
				}
			}
		}
		else if (playerAnim == PLAYER_WALK)
		{
			if (GetEntityFlags(client) & FL_DUCKING)
			{
				selectedAnim = model.anim_walk_crouch;
			}
			else
			{
				if (model.anim_run.seqList && GetEntProp(client, Prop_Send, "m_fIsSprinting"))
				{
					selectedAnim = model.anim_run;
				}
				else
				{
					selectedAnim = model.anim_walk;
				}
			}
		}
		
		if (selectedAnim.seqList != null)
		{
			playbackRate = selectedAnim.rate;
			return selectedAnim.seqList.NextSequence();
		}
	}
	return -1;
}
