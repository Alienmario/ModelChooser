#pragma semicolon 1
#pragma newdecls required

bool IsInMenu(int client)
{
	return (menuSelection[client].index != -1);
}

bool PreEnterCheck(int client)
{
	if (!client)
	{
		return false;
	}
	if (selectableModels[client] == null || !selectableModels[client].Length)
	{
		PrintToChat(client, "[ModelChooser] No models are available.");
		return false;
	}
	if (!IsPlayerAlive(client))
	{
		PrintToChat(client, "[ModelChooser] You need to be alive to use models.");
		return false;
	}
	if (IsInMenu(client))
	{
		PrintToChat(client, "[ModelChooser] You are already changing models, dummy :]");
		return false;
	}
	if (GetEntityFlags(client) & FL_ATCONTROLS || Client_IsInThirdPersonMode(client))
	{
		PrintToChat(client, "[ModelChooser] You cannot change models currently.");
		return false;
	}
	return true;
}

void EnterModelChooser(int client)
{
	menuSelection[client] = activeSelection[client];
	
	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (ragdoll != -1)
	{
		RemoveEntity(ragdoll);
	}

	StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
	StopSound(client, SNDCHAN_AUTO, lastPlayedSound[client]);
	
	// center camera pitch
	if (mp_forcecamera)
	{
		mp_forcecamera.ReplicateToClient(client, "0");
	}
	float eyeAngles[3];
	GetClientEyeAngles(client, eyeAngles);
	eyeAngles[0] = 0.0;
	TeleportEntity(client, .angles = eyeAngles);

	Client_SetObserverTarget(client, 0);
	Client_SetObserverMode(client, OBS_MODE_DEATHCAM, false);
	Client_SetDrawViewModel(client, false);
	FixThirdpersonWeapons(client);
	ToggleMenuOverlay(client, true);
	Client_SetHideHud(client, HIDEHUD_HEALTH|HIDEHUD_CROSSHAIR|HIDEHUD_FLASHLIGHT|HIDEHUD_WEAPONSELECTION|HIDEHUD_MISCSTATUS);
	Client_ScreenFade(client, 100, FFADE_PURGE|FFADE_IN, 0);
	SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);
	SetEntPropFloat(client, Prop_Data, "m_flNextAttack", float(cellmax));

	if (cvSelectionImmunity.BoolValue)
	{
		SDKHook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
	}
	
	tMenuInit[client] = CreateTimer(0.1, Timer_MenuInit1, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	OnMenuModelSelection(client, true);
}

void ExitModelChooser(int client, bool silent = false, bool cancel = false)
{
	Client_SetObserverTarget(client, -1);
	Client_SetObserverMode(client, OBS_MODE_NONE, false);
	Client_SetDrawViewModel(client, true);
	if (mp_forcecamera)
	{
		mp_forcecamera.ReplicateToClient(client, mp_forcecamera.BoolValue? "1" : "0");
	}
	ToggleMenuOverlay(client, false);
	Client_SetHideHud(client, 0);
	Client_ScreenFade(client, 200, FFADE_PURGE|FFADE_IN, 0);
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
	ClearMenuHud(client);
	SDKUnhook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
	SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime() + 0.25);
	ToggleMenuLock(client, false);
	delete tMenuInit[client];
	
	PlayerModel model;
	if (!cancel && menuSelection[client].IsValid() && Selection2Model(client, menuSelection[client], model))
	{
		if (!silent)
		{
			SoundPack soundPack;
			GetSoundPack(model, soundPack);
			PlayRandomSound(soundPack.selectSounds, client);
		}
		
		activeSelection[client] = menuSelection[client];
		
		PersistentPreferences prefs; prefs = GetPreferences(client);
		prefs.model.Set(client, model.name);
		prefs.skin.SetInt(client, model.GetSkin(menuSelection[client].skin));
		prefs.body.SetInt(client, model.GetBody(menuSelection[client].body));

		PrintToChat(client, "\x07d9843fModel selected: \x07f5bf42%s", model.name);
		
		CallModelChanged(client, model);
	}

	menuSelection[client].Reset();
	ForceFullUpdate(client);
}

void OnMenuModelSelection(int client, bool initial = false)
{
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);

	PlayerModel model;
	Selection2Model(client, menuSelection[client], model);
	
	menuSelection[client].skinCount = model.skins.Length;
	menuSelection[client].bodyCount = model.bodyGroups.Length;
	menuSelection[client].locked = IsModelLocked(model, client);
	
	if (!initial)
	{
		menuSelection[client].skin = 0;
		menuSelection[client].body = 0;
		PlayMenuClickSound(client);
	}
	
	if (!menuSelection[client].locked)
	{
		SoundPack soundPack;
		GetSoundPack(model, soundPack);
		PlayRandomSound(soundPack.viewSounds, client, _, SNDCHAN_BODY);
	}

	RefreshModel(client);
	UpdateMenuHud(client, model);
	ToggleMenuLock(client, menuSelection[client].locked);
}

void OnMenuSkinSelection(int client)
{
	if (menuSelection[client].locked)
		return;
	
	PlayerModel model;
	GetSelectedModel(client, model, true);
	UpdateMenuHud(client, model);
	SetEntitySkin(client, model.GetSkin(menuSelection[client].skin));
	PlayMenuClickSound(client);
}

void OnMenuBodySelection(int client)
{
	if (menuSelection[client].locked)
		return;
	
	PlayerModel model;
	GetSelectedModel(client, model, true);
	UpdateMenuHud(client, model);
	SetEntityBody(client, model.GetBody(menuSelection[client].body));
	PlayMenuClickSound(client);
}

void PlayMenuClickSound(int client)
{
	char path[PLATFORM_MAX_PATH];
	cvMenuSnd.GetString(path, sizeof(path));
	if (path[0] != EOS)
	{
		EmitSoundToClient(client, path, .level = 0);
	}
}

void ToggleMenuOverlay(int client, bool enable)
{
	char path[PLATFORM_MAX_PATH];
	cvOverlay.GetString(path, sizeof(path));

	if (!StrEqual(path, "") && !StrEqual(path, "0"))
	{
		Client_SetScreenOverlay(client, enable ? path : "");
	}
}

void ToggleMenuLock(int client, bool enable)
{
	static int lockRef[MAXPLAYERS + 1] = {-1, ...};

	if (enable)
	{
		char lockModel[PLATFORM_MAX_PATH];
		cvLockModel.GetString(lockModel, sizeof(lockModel));

		SetEntityEffects(client, GetEntityEffects(client) | EF_NODRAW | EF_NOSHADOW);
		int weapon = Client_GetActiveWeapon(client);
		if (weapon != -1)
		{
			SetEntityEffects(weapon, GetEntityEffects(weapon) | EF_NODRAW | EF_NOSHADOW);
		}
		
		if (lockModel[0] == EOS)
			return;
		
		if (IsValidEntity(lockRef[client]))
			return;

		int entity = CreateEntityByName("prop_dynamic_override");
		if (entity != -1)
		{
			DispatchKeyValue(entity, "model", lockModel);
			DispatchKeyValueFloat(entity, "modelscale", cvLockScale.FloatValue);
			DispatchKeyValue(entity, "disableshadows", "1");
			DispatchKeyValue(entity, "solid", "0");
			
			float eyePos[3];
			GetClientEyePosition(client, eyePos);
			DispatchKeyValueVector(entity, "origin", eyePos);

			SetEntityOwner(entity, client);
			SDKHook(entity, SDKHook_SetTransmit, Hook_TransmitToOwnerOnly);

			DispatchSpawn(entity);
			ActivateEntity(entity);
			Entity_SetParent(entity, client);

			lockRef[client] = EntIndexToEntRef(entity);
		}
	}
	else
	{
		SetEntityEffects(client, GetEntityEffects(client) & ~EF_NODRAW & ~EF_NOSHADOW);
		int weapon = Client_GetActiveWeapon(client);
		if (weapon != -1)
		{
			SetEntityEffects(weapon, GetEntityEffects(weapon) & ~EF_NODRAW & ~EF_NOSHADOW);
		}
		
		if (!IsValidEntity(lockRef[client]))
			return;
		
		RemoveEntity(lockRef[client]);
		lockRef[client] = -1;
	}
}

static bool g_bDrawing;

void UpdateMenuHud(int client, PlayerModel model, bool initital = false)
{
	if (tMenuInit[client])
		return;
	
	ClearMenuHud(client, true, true);
	g_bDrawing = true;

	static char text[128];

	bool showBody = menuSelection[client].bodyCount > 1 && !menuSelection[client].locked;
	bool showSkin = menuSelection[client].skinCount > 1 && !menuSelection[client].locked;
	text = (!showBody || !showSkin) ? "\n" : "";

	int color[4];
	if (menuSelection[client].locked)
	{
		StrCat(text, sizeof(text), "?");
		color = DEFAULT_HUD_COLOR;
	}
	else
	{
		StrCat(text, sizeof(text), model.name);
		color = model.hudColor;
	}

	if (showBody)
	{
		Format(text, sizeof(text), "%s\n⎧◦⎫ %3d / %-3d ⎧◦⎫", text, menuSelection[client].body + 1, menuSelection[client].bodyCount);
	}

	if (showSkin)
	{
		Format(text, sizeof(text), "%s\n⇡⇣ %5d / %-5d ⇡⇣", text, menuSelection[client].skin + 1, menuSelection[client].skinCount);
	}
	
	SetHudTextParamsEx(cvHudText1x.FloatValue, cvHudText1y.FloatValue, 60.0, color, {200, 200, 200, 200}, 1, 0.1, initital? 1.2 : 0.0, 0.15);
	ShowHudText(client, topHudChanToggle[client], text);

	// Bottom
	Format(text, sizeof(text), "⮜ %7d / %-7d ⮞", menuSelection[client].index + 1, selectableModels[client].Length);
	SetHudTextParamsEx(cvHudText2x.FloatValue, cvHudText2y.FloatValue, 9999999.0, DEFAULT_HUD_COLOR, _, 1, 0.0, initital? 1.2 : 0.0, 1.0);
	ShowHudText(client, bottomHudChanToggle[client], text);
	
	g_bDrawing = false;
}

void ClearMenuHud(int client, bool top = true, bool bottom = true)
{
	g_bDrawing = true;
	SetHudTextParams(-1.0, -1.0, 0.0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0);
	if (top)
	{
		ShowHudText(client, topHudChanToggle[client], " ");
		topHudChanToggle[client] = !topHudChanToggle[client];
	}
	if (bottom)
	{
		ShowHudText(client, bottomHudChanToggle[client], " ");
		bottomHudChanToggle[client] = bottomHudChanToggle[client] == 2? 3 : 2;
	}
	g_bDrawing = false;
}

public Action Hook_HudMsg(UserMsg msg_id, BfRead msg, const int[] clients, int numClients, bool reliable, bool init)
{
	// Block other hud messages while inside the menu
	if (numClients == 1 && menuSelection[clients[0]].index != -1 && !g_bDrawing)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void Timer_MenuInit1(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	tMenuInit[client] = null;

	if (client)
	{
		// Locking the camera has to be delayed after the view angles have been snapped
		if (mp_forcecamera)
		{
			mp_forcecamera.ReplicateToClient(client, "1");
		}
		tMenuInit[client] = CreateTimer(0.4, Timer_MenuInit2, userId, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void Timer_MenuInit2(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	tMenuInit[client] = null;

	if (client)
	{
		// Start drawing the hud
		PlayerModel model;
		if (GetSelectedModel(client, model, true))
		{
			UpdateMenuHud(client, model, true);
		}
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!(0 < client <= MAXPLAYERS))
		return;
	
	static int lastButtons[MAXPLAYERS + 1];
	
	if (IsInMenu(client))
	{
		if (!IsPlayerAlive(client))
		{
			ExitModelChooser(client, true);
		}
		else if ((buttons & IN_USE || buttons & IN_JUMP) && !menuSelection[client].locked)
		{
			ExitModelChooser(client);
		}
		else
		{
			if (selectableModels[client].Length > 1)
			{
				if (buttons & IN_MOVELEFT && !(lastButtons[client] & IN_MOVELEFT))
				{
					if (--menuSelection[client].index < 0)
					{
						menuSelection[client].index = selectableModels[client].Length - 1;
					}
					OnMenuModelSelection(client);
				}
				if (buttons & IN_MOVERIGHT && !(lastButtons[client] & IN_MOVERIGHT))
				{
					if (++menuSelection[client].index >= selectableModels[client].Length)
					{
						menuSelection[client].index = 0;
					}
					OnMenuModelSelection(client);
				}
			}

			if (menuSelection[client].skinCount > 1)
			{
				if (buttons & IN_FORWARD && !(lastButtons[client] & IN_FORWARD))
				{
					if (++menuSelection[client].skin >= menuSelection[client].skinCount)
					{
						menuSelection[client].skin = 0;
					}
					OnMenuSkinSelection(client);
				}
				if (menuSelection[client].skinCount && buttons & IN_BACK && !(lastButtons[client] & IN_BACK))
				{
					if (--menuSelection[client].skin < 0)
					{
						menuSelection[client].skin = menuSelection[client].skinCount - 1;
					}
					OnMenuSkinSelection(client);
				}
			}

			if (menuSelection[client].bodyCount > 1)
			{
				if (buttons & IN_ATTACK && !(lastButtons[client] & IN_ATTACK))
				{
					if (--menuSelection[client].body < 0)
					{
						menuSelection[client].body = menuSelection[client].bodyCount - 1;
					}
					OnMenuBodySelection(client);
				}
				if (buttons & IN_ATTACK2 && !(lastButtons[client] & IN_ATTACK2))
				{
					if (++menuSelection[client].body >= menuSelection[client].bodyCount)
					{
						menuSelection[client].body = 0;
					}
					OnMenuBodySelection(client);
				}
			}
		}
	}

	lastButtons[client] = buttons;
}
