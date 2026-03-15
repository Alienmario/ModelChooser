#pragma semicolon 1
#pragma newdecls required

#define MENU_SCROLL_DELAY_MAX 0.6
#define MENU_SCROLL_DELAY_MIN 0.15

// Indicator for filtering menu hudtexts inside hudmsg hook
static bool g_bDrawing;

// Delayed hud init timer
static Handle g_hMenuInitTimer[MAXPLAYERS + 1];

// Hud channel toggles (bi-channel switching allows displaying proper colors)
static int g_iMainHudChanToggle[MAXPLAYERS + 1];
static int g_iSecondaryHudChanToggle[MAXPLAYERS + 1] = {2, ...};

// Whether control keys hint has been displayed to a player
static bool g_bControlsHintDisplayed[MAXPLAYERS + 1];

methodmap UI
{
	public static void Init()
	{
		UserMsg hudMsgId = GetUserMessageId("HudMsg");
		if (hudMsgId != INVALID_MESSAGE_ID)
		{
			HookUserMessage(hudMsgId, Hook_HudMsg, true);
		}
	}

	public static bool IsOpen(int client)
	{
		return (menuSelection[client].index != -1);
	}

	public static bool IsOpening(int client)
	{
		return g_hMenuInitTimer[client] != null;
	}

	public static bool PreEnterCheck(int client, bool printError = true)
	{
		if (!client)
		{
			return false;
		}
		if (selectableModels[client] == null || !selectableModels[client].Length)
		{
			if (printError) PrintToChat(client, "[ModelChooser] No models are available.");
			return false;
		}
		if (!IsPlayerAlive(client))
		{
			if (printError) PrintToChat(client, "[ModelChooser] You need to be alive to use models.");
			return false;
		}
		if (UI.IsOpen(client))
		{
			if (printError) PrintToChat(client, "[ModelChooser] You are already changing models, dummy :]");
			return false;
		}
		if (GetEntityFlags(client) & FL_ATCONTROLS || Client_IsInThirdPersonMode(client))
		{
			if (printError) PrintToChat(client, "[ModelChooser] You cannot change models currently.");
			return false;
		}
		return true;
	}

	public static void Enter(int client)
	{
		menuSelection[client] = activeSelection[client];
		
		int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (ragdoll != -1)
		{
			RemoveEntity(ragdoll);
		}

		Sounds.StopLast(client, SNDCHAN_STATIC);
		Sounds.StopLast(client, SNDCHAN_BODY);
		Sounds.StopLast(client, SNDCHAN_AUTO);
		
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
		UI.UpdateOverlay(client, true);
		Client_SetHideHud(client, HIDEHUD_HEALTH|HIDEHUD_CROSSHAIR|HIDEHUD_FLASHLIGHT|HIDEHUD_WEAPONSELECTION|HIDEHUD_MISCSTATUS);
		Client_ScreenFade(client, 100, FFADE_PURGE|FFADE_IN, 0);
		SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", float(cellmax));

		if (cvSelectionImmunity.BoolValue)
		{
			SDKHook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
		}
		
		g_hMenuInitTimer[client] = CreateTimer(0.1, Timer_MenuInit1, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		UI.HandleSelection(client, true);
	}

	public static void Exit(int client, bool silent = false, bool cancel = false)
	{
		Client_SetObserverTarget(client, -1);
		Client_SetObserverMode(client, OBS_MODE_NONE, false);
		Client_SetDrawViewModel(client, true);
		if (mp_forcecamera)
		{
			mp_forcecamera.ReplicateToClient(client, mp_forcecamera.BoolValue? "1" : "0");
		}
		UI.UpdateOverlay(client, false);
		Client_SetHideHud(client, 0);
		Client_ScreenFade(client, 200, FFADE_PURGE|FFADE_IN, 0);
		SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
		UI.ClearHud(client);
		SDKUnhook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
		Sounds.StopLast(client, SNDCHAN_BODY);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime() + 0.25);
		UI.UpdateLock(client, false);
		FixFirstpersonWeapons(client);
		delete g_hMenuInitTimer[client];
		
		PlayerModel model;
		if (!cancel && menuSelection[client].IsValid() && GetModelFromSelection(client, menuSelection[client], model))
		{
			if (!silent)
			{
				Sounds.PlayRandom(GetSoundPack(model).GetSoundList("select"), client);
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
	}

	public static void HandleSelection(int client, bool initial = false, bool scrolling = false)
	{
		Sounds.StopLast(client, SNDCHAN_BODY);

		PlayerModel model;
		GetModelFromSelection(client, menuSelection[client], model);
		
		menuSelection[client].skinCount = model.skins.Length;
		menuSelection[client].bodyCount = model.bodyGroups.Length;
		menuSelection[client].locked = IsModelLocked(model, client);
		
		if (!initial)
		{
			menuSelection[client].skin = 0;
			menuSelection[client].body = 0;
			UI.PlayClickSound(client);
		}
		
		if (!scrolling && !menuSelection[client].locked)
		{
			Sounds.PlayRandom(GetSoundPack(model).GetSoundList("view"), client, _, SNDCHAN_BODY);
		}

		RefreshModel(client);
		UI.UpdateHud(client, model);
		UI.UpdateLock(client, menuSelection[client].locked);
	}

	public static void HandleSkinSelection(int client)
	{
		if (menuSelection[client].locked)
			return;
		
		PlayerModel model;
		GetSelectedModel(client, model, true);
		UI.UpdateHud(client, model);
		SetEntitySkin(client, model.GetSkin(menuSelection[client].skin));
		UI.PlayClickSound(client);
	}

	public static void HandleBodySelection(int client)
	{
		if (menuSelection[client].locked)
			return;
		
		PlayerModel model;
		GetSelectedModel(client, model, true);
		UI.UpdateHud(client, model);
		SetEntityBody(client, model.GetBody(menuSelection[client].body));
		UI.PlayClickSound(client);
	}

	public static void PlayClickSound(int client)
	{
		char path[PLATFORM_MAX_PATH];
		cvMenuSnd.GetString(path, sizeof(path));
		if (path[0] != EOS)
		{
			EmitSoundToClient(client, path, .level = 0);
		}
	}

	public static void UpdateOverlay(int client, bool enable)
	{
		char path[PLATFORM_MAX_PATH];
		cvOverlay.GetString(path, sizeof(path));

		if (!StrEqual(path, "") && !StrEqual(path, "0"))
		{
			Client_SetScreenOverlay(client, enable ? path : "");
		}
	}

	public static void UpdateLock(int client, bool enable)
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
	
	public static void UpdateHud(int client, PlayerModel model, bool initital = false)
	{
		if (UI.IsOpening(client))
		{
			return;
		}
		
		UI.ClearHud(client, true, true);
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
			Format(text, sizeof(text), "%s\n↑ %4d / %-4d ↓", text, menuSelection[client].body + 1, menuSelection[client].bodyCount);
		}

		if (showSkin)
		{
			Format(text, sizeof(text), "%s\n← %3d / %-3d →", text, menuSelection[client].skin + 1, menuSelection[client].skinCount);
		}
		
		SetHudTextParamsEx(cvHudText1x.FloatValue, cvHudText1y.FloatValue, 60.0, color, {200, 200, 200, 200}, 1, 0.1, initital? 1.2 : 0.0, 0.15);
		ShowHudText(client, g_iMainHudChanToggle[client], text);

		// Bottom
		Format(text, sizeof(text), "◀ %12d / %-12d ▶", menuSelection[client].index + 1, selectableModels[client].Length);
		SetHudTextParamsEx(cvHudText2x.FloatValue, cvHudText2y.FloatValue, 9999999.0, DEFAULT_HUD_COLOR, _, 1, 0.0, initital? 1.2 : 0.0, 1.0);
		ShowHudText(client, g_iSecondaryHudChanToggle[client], text);
		
		g_bDrawing = false;
	}

	public static void ClearHud(int client, bool top = true, bool bottom = true)
	{
		g_bDrawing = true;
		SetHudTextParams(-1.0, -1.0, 0.0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0);
		if (top)
		{
			ShowHudText(client, g_iMainHudChanToggle[client], " ");
			g_iMainHudChanToggle[client] = !g_iMainHudChanToggle[client];
		}
		if (bottom)
		{
			ShowHudText(client, g_iSecondaryHudChanToggle[client], " ");
			g_iSecondaryHudChanToggle[client] = g_iSecondaryHudChanToggle[client] == 2? 3 : 2;
		}
		g_bDrawing = false;
	}

	public static void ShowControlsHint(int client)
	{
		if (GetEngineVersion() == Engine_BlackMesa)
		{
			Client_PrintKeyHintText(client, "Browse models: %%+attack%% %%+attack2%%Customize model: %%+forward%% %%+moveleft%% %%+back%% %%+moveright%%Exit: %%+jump%% %%+use%%");
		}
		else
		{
			PrintHintText(client, "Browse models: %%+attack%%/%%+attack2%%  Customize model: %%+forward%%/%%+moveleft%%/%%+back%%/%%+moveright%%  Exit: %%+jump%%/%%+use%%");
		}
		g_bControlsHintDisplayed[client] = true;
	}
	
	public static void SelectionThink(int client, int buttons, int oldButtons, bool scrolling)
	{
		if (UI.IsOpening(client))
		{
			return;
		}

		if (selectableModels[client].Length > 1)
		{
			if (buttons & IN_ATTACK && !(oldButtons & IN_ATTACK))
			{
				if (--menuSelection[client].index < 0)
				{
					menuSelection[client].index = selectableModels[client].Length - 1;
				}
				UI.HandleSelection(client, false, scrolling);
			}
			if (buttons & IN_ATTACK2 && !(oldButtons & IN_ATTACK2))
			{
				if (++menuSelection[client].index >= selectableModels[client].Length)
				{
					menuSelection[client].index = 0;
				}
				UI.HandleSelection(client, false, scrolling);
			}
		}

		if (menuSelection[client].skinCount > 1)
		{
			if (buttons & IN_MOVELEFT && !(oldButtons & IN_MOVELEFT))
			{
				if (--menuSelection[client].skin < 0)
				{
					menuSelection[client].skin = menuSelection[client].skinCount - 1;
				}
				UI.HandleSkinSelection(client);
			}
			if (buttons & IN_MOVERIGHT && !(oldButtons & IN_MOVERIGHT))
			{
				if (++menuSelection[client].skin >= menuSelection[client].skinCount)
				{
					menuSelection[client].skin = 0;
				}
				UI.HandleSkinSelection(client);
			}
		}

		if (menuSelection[client].bodyCount > 1)
		{
			if (buttons & IN_BACK && !(oldButtons & IN_BACK))
			{
				if (--menuSelection[client].body < 0)
				{
					menuSelection[client].body = menuSelection[client].bodyCount - 1;
				}
				UI.HandleBodySelection(client);
			}
			if (buttons & IN_FORWARD && !(oldButtons & IN_FORWARD))
			{
				if (++menuSelection[client].body >= menuSelection[client].bodyCount)
				{
					menuSelection[client].body = 0;
				}
				UI.HandleBodySelection(client);
			}
		}
	}

	public static void Reset(int client)
	{
		g_hMenuInitTimer[client] = null;
		g_bControlsHintDisplayed[client] = false;
	}
}

static Action Hook_HudMsg(UserMsg msg_id, BfRead msg, const int[] clients, int numClients, bool reliable, bool init)
{
	// Block other hud messages while inside the menu
	if (numClients == 1 && UI.IsOpen(clients[0]) && !g_bDrawing)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

static void Timer_MenuInit1(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	g_hMenuInitTimer[client] = null;

	if (client)
	{
		// Locking the camera has to be delayed after the view angles have been snapped
		if (mp_forcecamera)
		{
			mp_forcecamera.ReplicateToClient(client, "1");
		}
		g_hMenuInitTimer[client] = CreateTimer(0.4, Timer_MenuInit2, userId, TIMER_FLAG_NO_MAPCHANGE);
	}
}

static void Timer_MenuInit2(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	g_hMenuInitTimer[client] = null;

	if (client)
	{
		// Start drawing the hud
		PlayerModel model;
		if (GetSelectedModel(client, model, true))
		{
			UI.UpdateHud(client, model, true);
		}
		if (!g_bControlsHintDisplayed[client])
		{
			UI.ShowControlsHint(client);
		}
	}
}
