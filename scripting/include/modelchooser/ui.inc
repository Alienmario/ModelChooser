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

enum struct ModelOptionsSequenceHelper
{
	bool bSkinSelection;
	int iNumBodyGroups;
	int iTotal;

	void Init(PlayerModel model)
	{
		this.bSkinSelection = model.SkinCount() > 1;
		this.iNumBodyGroups = model.BodyGroupCount();
		this.iTotal = view_as<int>(this.bSkinSelection) + this.iNumBodyGroups;
	}

	int GetTotal()
	{
		return this.iTotal;
	}

	int GetBodyGroupStart()
	{
		return view_as<int>(this.bSkinSelection);
	}
	int GetBodyGroupEnd()
	{
		return this.GetBodyGroupStart() + this.iNumBodyGroups;
	}
	int ToBodyGroupIndex(int idx)
	{
		return idx - this.GetBodyGroupStart();
	}

	bool IsSkin(int idx)
	{
		return this.bSkinSelection && idx == 0;
	}
	bool IsBodyGroup(int idx)
	{
		return this.iNumBodyGroups > 0 && idx >= this.GetBodyGroupStart() && idx <= this.GetBodyGroupEnd();
	}

}

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
		if (!selectableModels[client] || !selectableModels[client].Length)
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
		
		// lock the camera in a downward pitch
		if (mp_forcecamera)
		{
			mp_forcecamera.ReplicateToClient(client, "0");
		}
		float eyeAngles[3];
		GetClientEyeAngles(client, eyeAngles);
		eyeAngles[0] = 25.0;
		TeleportEntity(client, .angles = eyeAngles);

		UI.UpdateOverlay(client, true);
		Client_SetObserverTarget(client, 0);
		Client_SetObserverMode(client, OBS_MODE_DEATHCAM, false);
		Client_SetDrawViewModel(client, false);
		FixThirdpersonWeapons(client);
		Client_SetHideHud(client, HIDEHUD_HEALTH|HIDEHUD_CROSSHAIR|HIDEHUD_FLASHLIGHT|HIDEHUD_WEAPONSELECTION|HIDEHUD_MISCSTATUS);
		Client_ScreenFade(client, 100, FFADE_PURGE|FFADE_IN, 0);
		SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", float(cellmax));

		if (cvSelectionImmunity.BoolValue)
		{
			SDKHook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
		}
		
		g_hMenuInitTimer[client] = CreateTimer(0.1, Timer_MenuInit1, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		UI.HandleModelSelection(client, true);
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
		UI.ClearHud(client);
		UI.UpdateLock(client, false);
		Sounds.StopLast(client, SNDCHAN_BODY);
		Client_SetHideHud(client, 0);
		Client_ScreenFade(client, 200, FFADE_PURGE|FFADE_IN, 0);
		SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
		SDKUnhook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime() + 0.25);
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
			
			PersistentPreferences prefs;
			prefs = GetPreferences(client);
			prefs.model.Set(client, model.name);
			prefs.skin.SetInt(client, model.GetSkin(menuSelection[client].skin));
			
			PlayerModelBodyGroup bodyGroup;
			int body;
			int len = model.BodyGroupCount();
			for (int i = 0; i < len; i++)
			{
				model.GetBodyGroup(i, bodyGroup);
				CalcBodygroup(bodyGroup.base, bodyGroup.numModels, body, menuSelection[client].subModels[i]);
			}
			prefs.body.SetInt(client, body);

			PrintToChat(client, "\x07d9843fModel selected: \x07f5bf42%s", model.name);
			
			CallModelChanged(client, model);
		}

		menuSelection[client].Reset();
	}

	public static void HandleModelSelection(int client, bool initial = false, bool autoScrolling = false)
	{
		Sounds.StopLast(client, SNDCHAN_BODY);

		PlayerModel model;
		GetModelFromSelection(client, menuSelection[client], model);
		menuSelection[client].locked = IsModelLocked(model, client);
		
		if (!initial)
		{
			menuSelection[client].ResetModelOptions();
			UI.PlayClickSound(client);
		}
		
		if (!autoScrolling && !menuSelection[client].locked)
		{
			Sounds.PlayRandom(GetSoundPack(model).GetSoundList("view"), client, _, SNDCHAN_BODY);
		}

		RefreshModel(client);
		UI.UpdateHud(client, model);
		UI.UpdateLock(client, menuSelection[client].locked);
	}

	public static void HandleSkinSelection(int client, const PlayerModel model)
	{
		UI.UpdateHud(client, model);
		UI.PlayClickSound(client);
		SetEntitySkin(client, model.GetSkin(menuSelection[client].skin));
	}

	public static void HandleSubmodelSelection(int client, const PlayerModel model, const PlayerModelBodyGroup bodyGroup, int subModel)
	{
		UI.UpdateHud(client, model);
		UI.PlayClickSound(client);
		int body = GetEntityBody(client);
		CalcBodygroup(bodyGroup.base, bodyGroup.numModels, body, subModel);
		SetEntityBody(client, body);
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
		bool locked = menuSelection[client].locked;

		static ModelOptionsSequenceHelper optionsHelper;
		optionsHelper.Init(model);
		
		// Model select:
		SetHudTextParamsEx(cvHudText2x.FloatValue, cvHudText2y.FloatValue, 9999999.0, DEFAULT_HUD_COLOR, _, 1, 0.0, initital ? 1.2 : 0.0, 1.0);
		ShowHudText(client, g_iSecondaryHudChanToggle[client],  "◀ %12d / %-12d ▶",
			menuSelection[client].index + 1, selectableModels[client].Length);

		// Model name and options select:
		SetHudTextParamsEx(cvHudText1x.FloatValue, cvHudText1y.FloatValue, 60.0,
			locked ? DEFAULT_HUD_COLOR : model.hudColor, {200, 200, 200, 200}, 1, 0.1, initital ? 1.2 : 0.0, 0.15);

		if (locked)
		{
			ShowHudText(client, g_iMainHudChanToggle[client], "\n?");
		}
		else if (!optionsHelper.GetTotal())
		{
			ShowHudText(client, g_iMainHudChanToggle[client], "\n%s", model.name);
		}
		else
		{
			char optionTitle[MODELCHOOSER_MAX_NAME];
			int optionValue, optionCount;
			if (optionsHelper.IsSkin(menuSelection[client].optionIndex))
			{
				optionTitle = "SKIN";
				optionValue = menuSelection[client].skin + 1;
				optionCount = model.SkinCount();
			}
			else if (optionsHelper.IsBodyGroup(menuSelection[client].optionIndex))
			{
				int bodyGroupIndex = optionsHelper.ToBodyGroupIndex(menuSelection[client].optionIndex);
				PlayerModelBodyGroup bodyGroup; model.GetBodyGroup(bodyGroupIndex, bodyGroup);
				optionTitle = bodyGroup.name;
				optionValue = menuSelection[client].subModels[bodyGroupIndex] + 1;
				optionCount = bodyGroup.numModels;
			}
			
			static char optionBar[256];
			if (optionsHelper.GetTotal() > 1)
			{
				// construct a visual guide for option selection
				int totalBytes;
				for (int i = 0; i < optionsHelper.GetTotal(); i++)
				{
					int bytes = strcopy(optionBar[totalBytes], sizeof(optionBar)-totalBytes, (i == menuSelection[client].optionIndex) ? "◼" : "◻");
					if (!bytes) break;
					totalBytes += bytes;
				}
			}
			else
			{
				optionBar = "";
			}

			ShowHudText(client, g_iMainHudChanToggle[client], "%s\n%s\n%s: %3d / %-3d ⇡⇣",
				model.name, optionBar, optionTitle, optionValue, optionCount);
		}
		
		g_bDrawing = false;
	}

	public static void ClearHud(int client, bool main = true, bool secondary = true)
	{
		g_bDrawing = true;
		SetHudTextParams(-1.0, -1.0, 0.0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0);
		if (main)
		{
			ShowHudText(client, g_iMainHudChanToggle[client], " ");
			g_iMainHudChanToggle[client] = !g_iMainHudChanToggle[client];
		}
		if (secondary)
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
	
	public static void SelectionThink(int client, int buttons, int oldButtons, bool autoScrolling)
	{
		if (UI.IsOpening(client) || !selectableModels[client].Length)
		{
			return;
		}

		/* Model selection */
		
		if (buttons & IN_ATTACK && !(oldButtons & IN_ATTACK))
		{
			if (--menuSelection[client].index < 0)
			{
				menuSelection[client].index = selectableModels[client].Length - 1;
			}
			UI.HandleModelSelection(client, false, autoScrolling);
			return;
		}
		if (buttons & IN_ATTACK2 && !(oldButtons & IN_ATTACK2))
		{
			if (++menuSelection[client].index >= selectableModels[client].Length)
			{
				menuSelection[client].index = 0;
			}
			UI.HandleModelSelection(client, false, autoScrolling);
			return;
		}

		/* Model options */

		static PlayerModel model;
 
		if (menuSelection[client].locked || !GetModelFromSelection(client, menuSelection[client], model))
		{
			return;
		}

		static ModelOptionsSequenceHelper optionsHelper;
		optionsHelper.Init(model);

		if (optionsHelper.GetTotal() > 1)
		{
			if (buttons & IN_MOVELEFT && !(oldButtons & IN_MOVELEFT))
			{
				if (--menuSelection[client].optionIndex < 0)
				{
					menuSelection[client].optionIndex = optionsHelper.GetTotal() - 1;
				}
				UI.UpdateHud(client, model);
				UI.PlayClickSound(client);
				return;
			}
			if (buttons & IN_MOVERIGHT && !(oldButtons & IN_MOVERIGHT))
			{
				if (++menuSelection[client].optionIndex >= optionsHelper.GetTotal())
				{
					menuSelection[client].optionIndex = 0;
				}
				UI.UpdateHud(client, model);
				UI.PlayClickSound(client);
				return;
			}
		}
		
		if (optionsHelper.IsSkin(menuSelection[client].optionIndex))
		{
			if (buttons & IN_BACK && !(oldButtons & IN_BACK))
			{
				if (--menuSelection[client].skin < 0)
				{
					menuSelection[client].skin = model.SkinCount() - 1;
				}
				UI.HandleSkinSelection(client, model);
			}
			if (buttons & IN_FORWARD && !(oldButtons & IN_FORWARD))
			{
				if (++menuSelection[client].skin >= model.SkinCount())
				{
					menuSelection[client].skin = 0;
				}
				UI.HandleSkinSelection(client, model);
			}
		}
		else if (optionsHelper.IsBodyGroup(menuSelection[client].optionIndex))
		{
			int bodyGroupIndex = optionsHelper.ToBodyGroupIndex(menuSelection[client].optionIndex);
			PlayerModelBodyGroup bodyGroup; model.GetBodyGroup(bodyGroupIndex, bodyGroup);

			if (buttons & IN_BACK && !(oldButtons & IN_BACK))
			{
				if (--menuSelection[client].subModels[bodyGroupIndex] < 0)
				{
					menuSelection[client].subModels[bodyGroupIndex] = bodyGroup.numModels - 1;
				}
				UI.HandleSubmodelSelection(client, model, bodyGroup, menuSelection[client].subModels[bodyGroupIndex]);
			}
			if (buttons & IN_FORWARD && !(oldButtons & IN_FORWARD))
			{
				if (++menuSelection[client].subModels[bodyGroupIndex] >= bodyGroup.numModels)
				{
					menuSelection[client].subModels[bodyGroupIndex] = 0;
				}
				UI.HandleSubmodelSelection(client, model, bodyGroup, menuSelection[client].subModels[bodyGroupIndex]);
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
