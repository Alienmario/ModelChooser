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

static DynamicHook g_hkSetAnimation;
static Handle g_hResetSequence;

methodmap Anims
{
	public static void Init(GameData gamedata)
	{
		LoadDHookVirtual(gamedata, g_hkSetAnimation, "CBasePlayer::SetAnimation");

		if (GetEngineVersion() == Engine_HL2DM)
		{
			char szResetSequence[] = "CBaseAnimating::ResetSequence";
			StartPrepSDKCall(SDKCall_Entity);
			if (PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, szResetSequence))
			{
				PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
				if (!(g_hResetSequence = EndPrepSDKCall()))
					LogError("Could not prep SDK call %s", szResetSequence);
			}
			else LogError("Could not obtain gamedata signature %s", szResetSequence);
		
			if (!g_hResetSequence) LogError("Custom animations will not work");
		}
	}

	public static void PlayerInit(int client)
	{
		DHookEntity(g_hkSetAnimation, false, client, _, Hook_SetAnimation);
	}
}

static MRESReturn Hook_SetAnimation(int client, DHookParam hParams)
{
	PLAYER_ANIM playerAnim = hParams.Get(1);

	float playbackRate = 1.0;
	int sequence = GetCustomSequenceForAnim(client, playerAnim, playbackRate);
	if (sequence > -1 && g_hResetSequence)
	{
		SetEntPropFloat(client, Prop_Data, "m_flPlaybackRate", playbackRate);
		if (GetEntProp(client, Prop_Send, "m_nSequence") != sequence)
		{
			SDKCall(g_hResetSequence, client, sequence);
			SetEntPropFloat(client, Prop_Data, "m_flCycle", 0.0);
		}
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

static int GetCustomSequenceForAnim(int client, PLAYER_ANIM playerAnim, float &playbackRate)
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
		
		PlayerModelAnimation selectedAnim;
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
				Sounds.PlayRandom(GetSoundPack(model).GetSoundList("jump"), client, client, SNDCHAN_STATIC, true, JUMP_PITCH_MIN, JUMP_PITCH_MAX, JUMP_VOL);
				nextJumpSound[client] = time + model.jumpSndParams.cooldown.Rand();
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
