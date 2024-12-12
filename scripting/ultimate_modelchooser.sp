#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>
#include <dhooks>

#include <smlib>
#include <studio_hdr>
#include <smartdm_redux>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "3.1"

public Plugin myinfo =
{
	name = "Ultimate modelchooser",
	author = "Alienmario",
	description = "The enhanced playermodel system",
	version = PLUGIN_VERSION,
	url = "https://github.com/Alienmario/ModelChooser"
};

#define MAX_MODELNAME 64
#define MAX_SOUNDSNAME 64
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

#include <model_chooser/structs>
#include <model_chooser/utils>
#include <model_chooser/globals>
#include <model_chooser/natives>
#include <model_chooser/commands>
#include <model_chooser/menu>
#include <model_chooser/sounds>
#include <model_chooser/anims>
#include <model_chooser/config>
#include <model_chooser/viewmodels>

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	modelList = new ModelList();
	soundMap = new SoundMap();
	downloads = new SmartDM_FileSet();
	persistentPreferences[TEAM_UNASSIGNED].Init(TEAM_UNASSIGNED);
	
	fwdOnModelChanged = new GlobalForward("ModelChooser_OnModelChanged", ET_Ignore, Param_Cell, Param_String);
	
	RegConsoleCmd("sm_models", Command_Model);
	RegConsoleCmd("sm_model", Command_Model);
	RegConsoleCmd("sm_skins", Command_Model);
	RegConsoleCmd("sm_skin", Command_Model);
	RegAdminCmd("sm_unlockmodel", Command_UnlockModel, ADMFLAG_KICK, "Unlock a locked model by name for a player");
	RegAdminCmd("sm_lockmodel", Command_LockModel, ADMFLAG_KICK, "Lock a previously unlocked model by name for a player");

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
	cvForceFullUpdate = CreateConVar("modelchooser_forcefullupdate", "1", "Fixes weapon prediction glitch caused by going thirdperson, recommended to keep on unless you run into issues");
	mp_forcecamera = FindConVar("mp_forcecamera");

	cvTeamBased.AddChangeHook(Hook_TeamBasedCvarChanged);
	
	UserMsg hudMsgId = GetUserMessageId("HudMsg");
	if (hudMsgId != INVALID_MESSAGE_ID)
	{
		HookUserMessage(hudMsgId, Hook_HudMsg, true);
	}
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	CreateTimer(2.0, Sounds_CheckHealthRaise, _, TIMER_REPEAT);
	
	GameData gamedata = new GameData("modelchooser");
	if (!gamedata)
	{
		SetFailState("Failed to load \"modelchooser\" gamedata");
	}

	LoadDHookVirtual(gamedata, hkSetModel, "CBaseEntity::SetModel_");
	LoadDHookVirtual(gamedata, hkDeathSound, "CBasePlayer::DeathSound");
	LoadDHookVirtual(gamedata, hkSetAnimation, "CBasePlayer::SetAnimation");
	
	if (GetEngineVersion() == Engine_HL2DM)
	{
		char szResetSequence[] = "CBaseAnimating::ResetSequence";
		StartPrepSDKCall(SDKCall_Entity);
		if (PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, szResetSequence))
		{
			PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
			if (!(callResetSequence = EndPrepSDKCall()))
				LogError("Could not prep SDK call %s", szResetSequence);
		}
		else LogError("Could not obtain gamedata signature %s", szResetSequence);
	
		if (!callResetSequence)
			LogError("Custom animations will not work");
	}
	
	char szGetClient[] = "CBaseServer::GetClient";
	StartPrepSDKCall(SDKCall_Server);
	if (PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, szGetClient))
	{
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		if (!(callGetClient = EndPrepSDKCall()))
			LogError("Could not prep SDK call %s", szGetClient);
	}
	else LogError("Could not obtain gamedata offset %s", szGetClient);
	
	char szUpdateAcknowledgedFramecount[] = "CBaseClient::UpdateAcknowledgedFramecount";
	StartPrepSDKCall(SDKCall_Raw);
	if (PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, szUpdateAcknowledgedFramecount))
	{
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		if (!(callUpdateAcknowledgedFramecount = EndPrepSDKCall()))
			LogError("Could not prep SDK call %s", szUpdateAcknowledgedFramecount);
	}
	else LogError("Could not obtain gamedata offset %s", szUpdateAcknowledgedFramecount);
	
	if (!callGetClient || !callUpdateAcknowledgedFramecount)
		LogError("Prediction fix \"modelchooser_forcefullupdate\" will not work");
	
	gamedata.Close();
}

public void OnConfigsExecuted()
{
	static bool init;
	if (!init || cvAutoReload.BoolValue)
	{
		modelList.Clear();
		soundMap.Clear();
		downloads.Clear();
		LoadConfig();
		init = true;
	}
	else
	{
		soundMap.Precache();
		modelList.Precache();
	}
	
	char file[PLATFORM_MAX_PATH];
	
	cvLockModel.GetString(file, sizeof(file));
	SmartDM.AddEx(file, downloads);

	cvOverlay.GetString(file, sizeof(file));
	if (!StrEqual(file, "") && !StrEqual(file, "0"))
	{
		Format(file, sizeof(file), "materials/%s.vmt", file);
		SmartDM.AddEx(file, downloads);
	}

	cvMenuSnd.GetString(file, sizeof(file));
	if (!StrEqual(file, ""))
	{
		Format(file, sizeof(file), "sound/%s", file);
		SmartDM.AddEx(file, downloads, true);
	}

	downloads.AddToDownloadsTable();

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
	delete tMenuInit[client];
	clientInitChecks[client] = 3;
	currentTeam[client] = 0;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		currentTeam[client] = GetClientTeam(client);
		DHookEntity(hkSetModel, false, client, _, Hook_SetModel);
		DHookEntity(hkDeathSound, false, client, _, Hook_DeathSound);
		DHookEntity(hkSetAnimation, false, client, _, Hook_SetAnimation);

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
		Sounds_EventPlayerSpawn(event, client);
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
		Sounds_EventPlayerHurt(event, client);
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

//------------------------------------------------------
// Core functions
//------------------------------------------------------

bool GetSelectedModelAuto(int client, PlayerModel model)
{
	return GetSelectedModel(client, model, menuSelection[client].IsValid());
}

bool GetSelectedModel(int client, PlayerModel model, bool inMenu = false)
{
	return Selection2Model(client, inMenu? menuSelection[client] : activeSelection[client], model);
}

void GetSelectionDataAuto(int client, SelectionData selectionData)
{
	selectionData = menuSelection[client].IsValid()? menuSelection[client] : activeSelection[client];
}

bool Selection2Model(int client, const SelectionData data, PlayerModel model)
{
	if (data.index != -1 && selectableModels[client] && selectableModels[client].Length)
	{
		modelList.GetArray(selectableModels[client].Get(data.index), model);
		return true;
	}
	return false;
}

public MRESReturn Hook_SetModel(int client, DHookParam hParams)
{
	SelectionData selection;
	PlayerModel model;
	GetSelectionDataAuto(client, selection);
	if (Selection2Model(client, selection, model))
	{
		DHookSetParamString(hParams, 1, model.path);
		SetEntitySkin(client, model.GetSkin(selection.skin));
		SetEntityBody(client, model.GetBody(selection.body));
		// Delay needed for Black Mesa
		CreateTimer(0.1, Timer_UpdateModelAccessories, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

void Timer_UpdateModelAccessories(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client)
	{
		SelectionData selection;
		PlayerModel model;
		GetSelectionDataAuto(client, selection);
		if (Selection2Model(client, selection, model))
		{
			SetEntitySkin(client, model.GetSkin(selection.skin));
			SetEntityBody(client, model.GetBody(selection.body));
			UpdateViewModels(client);
		}
	}
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
	
	if (IsInMenu(client))
	{
		ExitModelChooser(client, true, true);
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

	char modelName[MAX_MODELNAME];
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
	PlayerModel model;
	int index = modelList.FindByName(modelName, model);
	if (index != -1)
	{
		int clIndex = selectableModels[client].FindValue(index);
		if (clIndex != -1 && !IsModelLocked(model, client))
		{
			activeSelection[client].index = clIndex;
			activeSelection[client].skin = model.IndexOfSkin(skin);
			activeSelection[client].body = model.IndexOfBody(body);
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
		activeSelection[client].index = maxPrioList.Get(Math_GetRandomInt(0, maxPrioList.Length - 1));

		PlayerModel model;
		Selection2Model(client, activeSelection[client], model);
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

void UnlockModel(int client, char modelName[MAX_MODELNAME])
{
	unlockedModels[client].SetValue(modelName, true);
}

void LockModel(int client, char modelName[MAX_MODELNAME])
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

void GetSoundPack(const PlayerModel model, SoundPack soundPack)
{
	soundMap.GetArray(model.sounds, soundPack, sizeof(SoundPack));
}

void ForceFullUpdate(int client)
{
	if (cvForceFullUpdate.BoolValue && callGetClient && callUpdateAcknowledgedFramecount)
	{
		int pClient = SDKCall(callGetClient, client - 1) - 4;
		SDKCall(callUpdateAcknowledgedFramecount, pClient, -1);
	}
}