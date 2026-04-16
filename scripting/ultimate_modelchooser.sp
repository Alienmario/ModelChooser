#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>
#include <dhooks>

#include <smlib>
#include <studio_hdr>
#include <smartdm_redux>
#include <filenetwork>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "4.0"

public Plugin myinfo =
{
	name = "Ultimate modelchooser",
	author = "Alienmario",
	description = "The enhanced playermodel system",
	version = PLUGIN_VERSION,
	url = "https://github.com/Alienmario/ModelChooser"
};

#define MAX_ANIM_NAME 128
#define HURT_SOUND_HP 45.0

#define HURT_PITCH_MIN 95
#define HURT_PITCH_MAX 102
#define JUMP_PITCH_MIN 90
#define JUMP_PITCH_MAX 105
#define JUMP_VOL 0.5

#define EF_NOSHADOW	0x010
#define EF_NODRAW 0x020

#define FALLBACK_MODEL "models/error.mdl"
int DEFAULT_HUD_COLOR[] = {150, 150, 150, 150};

#include <modelchooser/structs>
#include <modelchooser/utils>
#include <modelchooser/globals>
#include <modelchooser/natives>
#include <modelchooser/commands>
#include <modelchooser/ui>
#include <modelchooser/sounds>
#include <modelchooser/anims>
#include <modelchooser/config>
#include <modelchooser/viewmodels>

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	modelList = new PlayerModelList();
	soundMap = new SoundMap();
	downloads = new SmartDM_FileSet();
	coreDownloads = new SmartDM_FileSet();
	persistentPreferences[TEAM_UNASSIGNED].Init(TEAM_UNASSIGNED);
	
	fwdOnConfigLoaded = new GlobalForward("ModelChooser_OnConfigLoaded", ET_Ignore, Param_Cell, Param_String);
	fwdOnModelChanged = new GlobalForward("ModelChooser_OnModelChanged", ET_Ignore, Param_Cell, Param_String);

	cvSelectionImmunity = CreateConVar("modelchooser_immunity", "0", "Whether players are immune to damage when selecting models", _, true, 0.0, true, 1.0);
	cvAutoReload = CreateConVar("modelchooser_autoreload", "0", "Whether to reload the model list on mapchanges", _, true, 0.0, true, 1.0);
	cvTeamBased = CreateConVar("modelchooser_teambased", "2", "Configures model restrictions in teamplay mode\n 0 = Do not enforce any team restrictions\n 1 = Enforce configured team restrictions, allows picking unrestricted models\n 2 = Strictly enforce teams, only allows models with matching teams", _, true, 0.0, true, 2.0);
	cvMenuSnd = CreateConVar("modelchooser_sound", "ui/buttonclickrelease.wav", "Menu click sound (auto downloads supported), empty to disable");
	cvOverlay = CreateConVar("modelchooser_overlay", "modelchooser/background", "Screen overlay material to show when choosing models (auto downloads supported), empty to disable");
	cvLockModel = CreateConVar("modelchooser_lock_model", "models/props_wasteland/prison_padlock001a.mdl", "Model to display for locked playermodels (auto downloads supported)");
	cvLockScale = CreateConVar("modelchooser_lock_scale", "5.0", "Scale of the lock model", _, true, 0.1);
	cvHudText1x = CreateConVar("modelchooser_hudtext_x", "-1", "Hudtext 1 X coordinate, from 0 (left) to 1 (right), -1 is the center");
	cvHudText1y = CreateConVar("modelchooser_hudtext_y", "0.01", "Hudtext 1 Y coordinate, from 0 (top) to 1 (bottom), -1 is the center");
	cvHudText2x = CreateConVar("modelchooser_hudtext2_x", "-1", "Hudtext 2 X coordinate, from 0 (left) to 1 (right), -1 is the center");
	cvHudText2y = CreateConVar("modelchooser_hudtext2_y", "0.95", "Hudtext 2 Y coordinate, from 0 (top) to 1 (bottom), -1 is the center");
	cvLateDownloads = CreateConVar("modelchooser_late_downloads", "0", "Whether to send content downloads (models, sounds) to clients via File-Network instead of the classic download table. Requires the File-Network plugin to be loaded; falls back to standard downloads if it is not available. Core plugin downloads (lock model, overlay, menu sound) are always added to the download table.", _, true, 0.0, true, 1.0);
	mp_forcecamera = FindConVar("mp_forcecamera");

	cvTeamBased.AddChangeHook(Hook_TeamBasedCvarChanged);
	
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	GameData gamedata = new GameData("modelchooser");
	if (!gamedata)
	{
		SetFailState("Failed to load \"modelchooser\" gamedata");
	}

	UI.Init();
	Commands.Init();
	Anims.Init(gamedata);
	Sounds.Init(gamedata);

	LoadDHookVirtual(gamedata, hkSetModel, "CBaseEntity::SetModel_");
	
	gamedata.Close();
}

public void OnAllPluginsLoaded()
{
	fileNetAvailable = GetFeatureStatus(FeatureType_Native, "FileNet_SendFile") == FeatureStatus_Available;
}

public void OnConfigsExecuted()
{
	static bool init;
	if (!init || cvAutoReload.BoolValue)
	{
		modelList.Clear();
		soundMap.Clear();
		downloads.Clear();
		Config.Load();
		init = true;
	}
	else
	{
		soundMap.Precache();
		modelList.Precache();
	}
	
	coreDownloads.Clear();
	
	char file[PLATFORM_MAX_PATH];
	
	cvLockModel.GetString(file, sizeof(file));
	SmartDM.AddEx(file, coreDownloads);

	cvOverlay.GetString(file, sizeof(file));
	if (!StrEqual(file, "") && !StrEqual(file, "0"))
	{
		Format(file, sizeof(file), "materials/%s.vmt", file);
		SmartDM.AddEx(file, coreDownloads);
	}

	cvMenuSnd.GetString(file, sizeof(file));
	if (!StrEqual(file, ""))
	{
		Format(file, sizeof(file), "sound/%s", file);
		SmartDM.AddEx(file, coreDownloads, true);
	}

	coreDownloads.AddToDownloadsTable();

	if (!cvLateDownloads.BoolValue || !fileNetAvailable)
	{
		downloads.AddToDownloadsTable();
	}

	PrecacheModel(FALLBACK_MODEL, true);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientConnected(i);
			OnClientPutInServer(i);
			if (IsClientAuthorized(i))
				OnClientPostAdminCheck(i);
			if (AreClientCookiesCached(i))
				OnClientCookiesCached(i);
		}
	}
}

public void OnClientConnected(int client)
{
	ResetClientModels(client);
	ResetUnlockedModels(client);
	UI.Reset(client);
	clientInitChecks[client] = 3;
	currentTeam[client] = 0;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		currentTeam[client] = GetClientTeam(client);
		DHookEntity(hkSetModel, false, client, _, Hook_SetModel);
		Anims.PlayerInit(client);
		Sounds.PlayerInit(client);

		if (cvLateDownloads.BoolValue && fileNetAvailable)
		{
			StringMapSnapshot snapshot = downloads.Snapshot();
			int count = snapshot.Length;
			char path[PLATFORM_MAX_PATH];
			for (int i = 0; i < count; i++)
			{
				snapshot.GetKey(i, path, sizeof(path));
				FileNet_SendFile(client, path);
			}
			snapshot.Close();
		}

		if (!--clientInitChecks[client])
			InitClientModels(client);
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!--clientInitChecks[client])
		InitClientModels(client);
}

public void OnClientCookiesCached(int client)
{
	if (!--clientInitChecks[client])
		InitClientModels(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		Sounds.HandlePlayerSpawn(client);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetBool("disconnect"))
		return;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		int oldTeam = event.GetInt("oldteam");
		int team = currentTeam[client] = event.GetInt("team");
		if (team != oldTeam)
		{
			if (UI.IsOpen(client))
			{
				UI.Exit(client, true, true);
			}
			if (team == TEAM_UNASSIGNED || team > TEAM_SPECTATOR)
			{
				ReloadClientModels(client);
			}
		}
	}
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		int health = event.GetInt("health");
		Sounds.HandlePlayerHurt(client, health);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "viewmodel") != -1 && HasEntProp(entity, Prop_Data, "m_hWeapon"))
	{
		DHookEntity(hkSetModel, false, entity, _, Hook_SetViewModelModel);
	}
}

void Hook_TeamBasedCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			ReloadClientModels(i);
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!(0 < client <= MAXPLAYERS))
		return;
	
	if (UI.IsOpen(client))
	{
		static int lastButtons[MAXPLAYERS + 1];
		static int lastButtonsAdjusted[MAXPLAYERS + 1];
		static float lastChange[MAXPLAYERS + 1];
		static float delay[MAXPLAYERS + 1];

		if (!IsPlayerAlive(client))
		{
			UI.Exit(client, true);
		}
		else if ((buttons & IN_USE || buttons & IN_JUMP) && !menuSelection[client].locked)
		{
			UI.Exit(client);
		}
		else
		{
			UI.SelectionThink(client, buttons, lastButtonsAdjusted[client], delay[client] != MENU_SCROLL_DELAY_MAX);
		}
		
		float time = GetGameTime();
		if (lastButtons[client] != buttons)
		{
			lastButtons[client] = lastButtonsAdjusted[client] = buttons;
			lastChange[client] = time;
			delay[client] = MENU_SCROLL_DELAY_MAX;
		}
		else if (buttons && time - lastChange[client] > delay[client])
		{
			lastButtonsAdjusted[client] = 0;
			lastChange[client] = time;
			delay[client] = Math_Clamp(delay[client] * 0.9, MENU_SCROLL_DELAY_MIN, MENU_SCROLL_DELAY_MAX);
		}
		else
		{
			lastButtonsAdjusted[client] = lastButtons[client];
		}
	}
}

//------------------------------------------------------
// Core functions
//------------------------------------------------------

bool GetSelectedModelAuto(int client, PlayerModel model)
{
	return GetSelectedModel(client, model, menuSelection[client].IsValid());
}

bool GetSelectedModel(int client, PlayerModel model, bool inMenu = false)
{
	return GetModelFromSelection(client, inMenu? menuSelection[client] : activeSelection[client], model);
}

void GetSelectionDataAuto(int client, SelectionData selectionData)
{
	selectionData = menuSelection[client].IsValid()? menuSelection[client] : activeSelection[client];
}

bool GetModelFromSelection(int client, const SelectionData selectionData, PlayerModel model)
{
	if (selectionData.index != -1 && selectableModels[client] && selectableModels[client].Length)
	{
		modelList.GetArray(selectableModels[client].Get(selectionData.index), model);
		return true;
	}
	return false;
}

public MRESReturn Hook_SetModel(int client, DHookParam hParams)
{
	SelectionData selection;
	PlayerModel model;
	GetSelectionDataAuto(client, selection);
	if (GetModelFromSelection(client, selection, model))
	{
		DHookSetParamString(hParams, 1, model.path);
		SetEntitySkin(client, model.GetSkin(selection.skin));
		UpdateSubModels(client, model, selection);

		// Delay needed for Black Mesa
		CreateTimer(0.1, Timer_SetModelPost, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

void Timer_SetModelPost(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client)
	{
		SelectionData selection;
		PlayerModel model;
		GetSelectionDataAuto(client, selection);
		if (GetModelFromSelection(client, selection, model))
		{
			SetEntitySkin(client, model.GetSkin(selection.skin));
			UpdateSubModels(client, model, selection);
			UpdateViewModels(client);
		}
	}
}
 
void UpdateSubModels(int client, const PlayerModel model, const SelectionData selection)
{
	int body;

	// transpose gameplay driven bodygroups (e.g. longjump) to new model
	StringMap submodelsMap = GetEntityBodygroupsMap(client);
	ApplyStudioBodyGroupsFromMap(StudioHdr(model.path), submodelsMap, body);
	delete submodelsMap;

	// apply selected submodels
	int len = model.BodyGroupCount();
	PlayerModelBodyGroup bodyGroup;
	for (int i = 0; i < len; i++)
	{
		model.GetBodyGroup(i, bodyGroup);
		CalcBodygroup(bodyGroup.base, bodyGroup.numModels, body, selection.subModels[i]);
	}

	// set the new body value
	SetEntityBody(client, body);
}

void RefreshModel(int client)
{
	if (IsClientInGame(client))
	{
		// something went wrong if this sticks
		SetEntityModel(client, FALLBACK_MODEL);
	}
}

void ResetClientModels(int client)
{
	delete selectableModels[client];
	activeSelection[client].Reset();
	menuSelection[client].Reset();
	playedHurtSoundAt[client] = -1;
	nextJumpSound[client] = 0.0;
}

void ReloadClientModels(int client)
{
	if (!selectableModels[client])
		return;
	
	if (UI.IsOpen(client))
	{
		UI.Exit(client, true, true);
	}
	ResetClientModels(client);
	InitClientModels(client);
}

void InitClientModels(int client)
{
	if (selectableModels[client])
		return;

	selectableModels[client] = BuildSelectableModels(client);
	if (!selectableModels[client].Length)
		return;
	
	PersistentPreferences prefs;
	prefs = GetPreferences(client);

	char modelName[MODELCHOOSER_MAX_NAME];
	prefs.model.Get(client, modelName, sizeof(modelName));

	// first select by team based preferences
	if (SelectModelByName(client, modelName, prefs.skin.GetInt(client), prefs.body.GetInt(client)))
		return;

	// if we failed picking by team, try the no-team preferences
	if (prefs.team != 0)
	{
		prefs = GetPreferencesByTeam(0);
		prefs.model.Get(client, modelName, sizeof(modelName));
		if (SelectModelByName(client, modelName, prefs.skin.GetInt(client), prefs.body.GetInt(client)))
			return;
	}

	// no selectable preferences, pick a default
	SelectDefaultModel(client);
}

ArrayList BuildSelectableModels(int client)
{
	ArrayList list = new ArrayList();
	for (int i = 0; i < modelList.Length; i++)
	{
		PlayerModel model;
		modelList.GetArray(i, model);

		if (model.adminBitFlags != -1)
		{
			int clientFlags = GetUserFlagBits(client);
			if (!(clientFlags & ADMFLAG_ROOT || clientFlags & model.adminBitFlags))
				continue;
		}

		int modelTeam = model.GetTeamNum();
		if (currentTeam[client] > TEAM_SPECTATOR && currentTeam[client] != modelTeam)
		{
			if (cvTeamBased.IntValue == 2)
				continue;
			if (cvTeamBased.IntValue == 1 && modelTeam > TEAM_SPECTATOR)
				continue;
		}

		list.Push(i);
	}
	return list;
}

bool SelectModelByName(int client, const char[] modelName, int skin = 0, int body = 0)
{
	int index = modelList.FindByName(modelName);
	if (index != -1)
	{
		PlayerModel model;
		modelList.GetArray(index, model);
		int clIndex = selectableModels[client].FindValue(index);
		if (clIndex != -1 && !IsModelLocked(model, client))
		{
			activeSelection[client].Reset();
			activeSelection[client].index = clIndex;
			activeSelection[client].skin = model.FindSkin(skin);

			PlayerModelBodyGroup bodyGroup;
			int len = model.BodyGroupCount();
			for (int i = 0; i < len; i++)
			{
				model.GetBodyGroup(i, bodyGroup);
				int subModelIndex = CalcBodygroupSubmodel(bodyGroup.base, bodyGroup.numModels, body);
				if (subModelIndex < 0 || subModelIndex >= bodyGroup.numModels)
				{
					subModelIndex = 0;
				}
				activeSelection[client].subModels[i] = subModelIndex;
			}

			RefreshModel(client);
			CallModelChanged(client, model);
			return true;
		}
	}
	return false;
}

bool SelectDefaultModel(int client)
{
	if (!selectableModels[client].Length)
		return false;
	
	// find models with the highest prio
	// select random if there are multiple
	int maxPrio = cellmin;
	ArrayList maxPrioList = new ArrayList();
	
	for (int i = 0; i < selectableModels[client].Length; i++)
	{
		PlayerModel model;
		modelList.GetArray(selectableModels[client].Get(i), model);
		
		if (IsModelLocked(model, client))
			continue;
		
		if (model.defaultPrio > maxPrio)
		{
			maxPrio = model.defaultPrio;
			maxPrioList.Clear();
			maxPrioList.Push(i);
		}
		else if (model.defaultPrio == maxPrio)
		{
			maxPrioList.Push(i);
		}
	}
	
	if (maxPrioList.Length)
	{
		activeSelection[client].Reset();
		activeSelection[client].index = maxPrioList.Get(Math_GetRandomInt(0, maxPrioList.Length - 1));

		PlayerModel model;
		GetModelFromSelection(client, activeSelection[client], model);
		RefreshModel(client);
		CallModelChanged(client, model);
		delete maxPrioList;
		return true;
	}

	delete maxPrioList;
	return false;
}

void CallModelChanged(int client, const PlayerModel model)
{
	Call_StartForward(fwdOnModelChanged);
	Call_PushCell(client);
	Call_PushString(model.name);
	Call_Finish();
}

bool IsModelLocked(const PlayerModel model, int client)
{
	return (model.locked && !unlockedModels[client].GetValue(model.name, client));
}

void UnlockModel(int client, char modelName[MODELCHOOSER_MAX_NAME])
{
	unlockedModels[client].SetValue(modelName, true);
}

void LockModel(int client, char modelName[MODELCHOOSER_MAX_NAME])
{
	unlockedModels[client].Remove(modelName);
}

void ResetUnlockedModels(int client)
{
	delete unlockedModels[client];
	unlockedModels[client] = new StringMap();
}

PersistentPreferences GetPreferences(int client)
{
	int team = currentTeam[client];
	if (team <= TEAM_SPECTATOR || !cvTeamBased.BoolValue)
	{
		team = 0;
	}
	return GetPreferencesByTeam(team);
}

PersistentPreferences GetPreferencesByTeam(int team)
{
	PersistentPreferences prefs;
	prefs = persistentPreferences[team];
	prefs.Init(team);
	return prefs;
}

SoundPack GetSoundPack(const PlayerModel model, bool emptyDefault = true)
{
	SoundPack soundPack = soundMap.GetSoundPack(model.sounds);
	if (soundPack || !emptyDefault)
	{
		return soundPack;
	}
	static SoundPack emptySoundPack;
	if (!emptySoundPack)
	{
		emptySoundPack = new SoundPack();
	}
	return emptySoundPack;
}
