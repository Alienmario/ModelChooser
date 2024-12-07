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

#define PLUGIN_VERSION  "3.0"

public Plugin myinfo =
{
	name = "Playermodel chooser",
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

//------------------------------------------------------
// Data structures
//------------------------------------------------------

enum struct Interval
{
	float min;
	float max;

	float Rand()
	{
		return GetRandomFloat(this.min, this.max);
	}
}

enum struct SoundParams
{
	Interval cooldown;
}

enum struct SoundPack
{
	ArrayList hurtSounds;
	ArrayList deathSounds;
	ArrayList viewSounds;
	ArrayList selectSounds;
	ArrayList jumpSounds;
	
	void Close()
	{
		delete this.hurtSounds;
		delete this.deathSounds;
		delete this.viewSounds;
		delete this.selectSounds;
		delete this.jumpSounds;
	}

	void Precache()
	{
		PrecacheSoundsInList(this.hurtSounds);
		PrecacheSoundsInList(this.deathSounds);
		PrecacheSoundsInList(this.viewSounds);
		PrecacheSoundsInList(this.selectSounds);
		PrecacheSoundsInList(this.jumpSounds);
	}
}

methodmap SoundMap < StringMap
{
	public SoundMap()
	{
		return view_as<SoundMap>(new StringMap());
	}
	
	public void Clear()
	{
		StringMapSnapshot snapshot = this.Snapshot();
		SoundPack soundPack;
		for (int i = 0; i < snapshot.Length; i++)
		{
			int keySize = snapshot.KeyBufferSize(i);
			char[] key = new char[keySize];
			snapshot.GetKey(i, key, keySize);
			this.GetArray(key, soundPack, sizeof(SoundPack));
			soundPack.Close();
		}
		snapshot.Close();
		view_as<StringMap>(this).Clear();
	}

	public void Precache()
	{
		StringMapSnapshot snapshot = this.Snapshot();
		SoundPack soundPack;
		for (int i = 0; i < snapshot.Length; i++)
		{
			int keySize = snapshot.KeyBufferSize(i);
			char[] key = new char[keySize];
			snapshot.GetKey(i, key, keySize);
			this.GetArray(key, soundPack, sizeof(SoundPack));
			soundPack.Precache();
		}
		snapshot.Close();	
	}
}

// Complete sounds map containing entries of SoundPack, indexed by names
SoundMap soundMap;

enum struct WeightedSequence
{
	int weight;
	int sequence;
}

methodmap WeightedSequenceList < ArrayList
{
	public WeightedSequenceList()
	{
		return view_as<WeightedSequenceList>(new ArrayList(sizeof(WeightedSequence)));
	}

	public void Add(int sequence, int weight)
	{
		WeightedSequence ws;
		ws.weight = weight;
		ws.sequence = sequence;
		this.PushArray(ws);
	}

	public int NextSequence()
	{
		int size = this.Length;
		if (size)
		{
			if (size == 1)
				return this.Get(0, WeightedSequence::sequence);

			int weightSum;
			for (int i = 0; i < size; i++)
			{
				weightSum += this.Get(i, WeightedSequence::weight);
			}
			float target = GetURandomFloat() * weightSum;
			for (int i = 0; i < size; i++)
			{
				target -= this.Get(i, WeightedSequence::weight);
				if (target <= 0)
				{
					return this.Get(i, WeightedSequence::sequence);
				}
			}
		}
		return -1;
	}
}

enum struct PlayerAnimation
{
	WeightedSequenceList seqList;
	float rate;

	void Close()
	{
		delete this.seqList;
	}
}

enum struct PlayerModel
{
	bool locked;
	char name[MAX_MODELNAME];
	char path[PLATFORM_MAX_PATH];
	char vmBodyGroups[256];
	int adminBitFlags;
	int defaultPrio;
	char sounds[MAX_SOUNDSNAME];
	SoundParams jumpSndParams;
	Interval hurtSndHP;
	int hudColor[4];

	ArrayList skins;
	ArrayList bodyGroups;

	PlayerAnimation anim_idle;
	PlayerAnimation anim_walk;
	PlayerAnimation anim_run;
	PlayerAnimation anim_jump;
	PlayerAnimation anim_idle_crouch;
	PlayerAnimation anim_walk_crouch;
	PlayerAnimation anim_noclip;
	
	void Close()
	{
		this.skins.Close();
		this.bodyGroups.Close();
		this.anim_idle.Close();
		this.anim_walk.Close();
		this.anim_run.Close();
		this.anim_jump.Close();
		this.anim_idle_crouch.Close();
		this.anim_walk_crouch.Close();
		this.anim_noclip.Close();
	}
	
	void GetSoundPack(SoundPack soundPack)
	{
		soundMap.GetArray(this.sounds, soundPack, sizeof(SoundPack));
	}

	void Precache()
	{
		PrecacheModel(this.path, true);
	}

	int GetSkin(int index)
	{
		return this.skins.Get(index);
	}

	int GetBody(int index)
	{
		return this.bodyGroups.Get(index);
	}

	int IndexOfSkin(int skin, int fallback = 0)
	{
		int i = this.skins.FindValue(skin);
		return i == -1 ? fallback : i;
	}

	int IndexOfBody(int body, int fallback = 0)
	{
		int i = this.bodyGroups.FindValue(body);
		return i == -1 ? fallback : i;
	}
}

methodmap ModelList < ArrayList
{
	public ModelList()
	{
		return view_as<ModelList>(new ArrayList(sizeof(PlayerModel)));
	}
	
	public void Clear()
	{
		PlayerModel model;
		int len = this.Length;
		for (int i = 0; i < len; i++)
		{
			this.GetArray(i, model);
			model.Close();
		}
		view_as<ArrayList>(this).Clear();
	}
	
	public int FindByName(const char[] modelName, PlayerModel model)
	{
		int len = this.Length;
		for (int i = 0; i < len; i++)
		{
			this.GetArray(i, model);
			if (StrEqual(model.name, modelName, false))
				return i;
		}
		return -1;
	}

	public void Precache()
	{
		int len = this.Length;
		PlayerModel model;
		for (int i = 0; i < len; i++)
		{
			this.GetArray(i, model);
			model.Precache();
		}
	}
}

enum struct SelectionData
{
	// Index into selectableModels, -1 = invalid
	int index;

	// Index into PlayerModel.skins
	int skin;

	// Index into PlayerModel.bodyGroups
	int body;

	// Cached by menu
	int skinCount;
	int bodyCount;
	bool locked;

	void Reset()
	{
		this.index = -1;
		this.skin = this.skinCount = this.body = this.bodyCount = 0;
		this.locked = false;
	}
	
	bool IsValid()
	{
		return this.index != -1 && !this.locked;
	}
}

//------------------------------------------------------
// Variables
//------------------------------------------------------

// Complete model list containing entries of PlayerModel
ModelList modelList;

// The filtered list of selectable models. Contains indexes into modelList. Is null until client models are initialized.
ArrayList selectableModels[MAXPLAYERS + 1];

// Active selection data
SelectionData activeSelection[MAXPLAYERS + 1];

// Menu selection data
SelectionData menuSelection[MAXPLAYERS + 1];

// Map containing names of unlocked models
StringMap unlockedModels[MAXPLAYERS + 1];

// Used for stopping
char lastPlayedSound[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

// Flag for playing hurt sound once
int playedHurtSoundAt[MAXPLAYERS + 1] = {-1, ...};

// Time to play next jump sound at
float nextJumpSound[MAXPLAYERS + 1];

// Counter for # of checks to pass until client models can be initialized
int clientInitChecks[MAXPLAYERS + 1];

// Hud channel toggles (bi-channel switching allows displaying proper colors)
int topHudChanToggle[MAXPLAYERS + 1];
int bottomHudChanToggle[MAXPLAYERS + 1] = {2, ...};

// Delayed hud init timer
Handle tMenuInit[MAXPLAYERS + 1];

// Downloads fileset
SmartDM_FileSet downloads;

// Hooks
DynamicHook hkSetModel;
DynamicHook hkDeathSound;
DynamicHook hkSetAnimation;

// Calls
Handle callResetSequence;

// Cookies
Cookie cookieModel;
Cookie cookieSkin;
Cookie cookieBody;

// Forwards
GlobalForward fwdOnModelChanged;

// Cvars
ConVar cvSelectionImmunity;
ConVar cvAutoReload;
ConVar cvOverlay;
ConVar cvLockModel;
ConVar cvLockScale;
ConVar cvMenuSnd;
ConVar mp_forcecamera;

//------------------------------------------------------
// Natives
//------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ModelChooser_GetCurrentModelName", Native_GetCurrentModelName);
	CreateNative("ModelChooser_GetCurrentModelPath", Native_GetCurrentModelPath);
	CreateNative("ModelChooser_UnlockModel", Native_UnlockModel);
	CreateNative("ModelChooser_LockModel", Native_LockModel);
	CreateNative("ModelChooser_SelectModel", Native_SelectModel);
	CreateNative("ModelChooser_IsClientChoosing", Native_IsClientChoosing);
	RegPluginLibrary("ModelChooser");
	return APLRes_Success;
}

public any Native_GetCurrentModelName(Handle plugin, int numParams)
{
	PlayerModel model;

	if (GetSelectedModel(GetNativeCell(1), model))
	{
		SetNativeString(2, model.name, GetNativeCell(3));
		return true;
	}
	return false;
}

public any Native_GetCurrentModelPath(Handle plugin, int numParams)
{
	PlayerModel model;

	if (GetSelectedModel(GetNativeCell(1), model))
	{
		SetNativeString(2, model.path, GetNativeCell(3));
		return true;
	}
	return false;
}

public any Native_UnlockModel(Handle plugin, int numParams)
{
	char modelName[MAX_MODELNAME];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	int client = GetNativeCell(1);
	
	UnlockModel(client, modelName);
	if (GetNativeCell(3))
	{
		return SelectModelByName(client, modelName);
	}
	return true;
}

public any Native_LockModel(Handle plugin, int numParams)
{
	char modelName[MAX_MODELNAME];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	LockModel(GetNativeCell(1), modelName);
	return true;
}

public any Native_SelectModel(Handle plugin, int numParams)
{
	char modelName[MAX_MODELNAME];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	return SelectModelByName(GetNativeCell(1), modelName);
}

public any Native_IsClientChoosing(Handle plugin, int numParams)
{
	return menuSelection[GetNativeCell(1)].index != -1;
}

//------------------------------------------------------
// Plugin entry points, init
//------------------------------------------------------

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	modelList = new ModelList();
	soundMap = new SoundMap();
	downloads = new SmartDM_FileSet();
	cookieModel = new Cookie("playermodel", "Stores player model preference", CookieAccess_Protected);
	cookieSkin = new Cookie("playermodel_skin", "Stores player model skin type preference", CookieAccess_Protected);
	cookieBody = new Cookie("playermodel_body", "Stores player model body type preference", CookieAccess_Protected);
	
	fwdOnModelChanged = new GlobalForward("ModelChooser_OnModelChanged", ET_Ignore, Param_Cell, Param_String);
	
	RegConsoleCmd("sm_models", Command_Model);
	RegConsoleCmd("sm_model", Command_Model);
	RegConsoleCmd("sm_skins", Command_Model);
	RegConsoleCmd("sm_skin", Command_Model);
	RegAdminCmd("sm_unlockmodel", Command_UnlockModel, ADMFLAG_KICK, "Unlock a locked model by name for a player");
	RegAdminCmd("sm_lockmodel", Command_LockModel, ADMFLAG_KICK, "Lock a previously unlocked model by name for a player");

	cvSelectionImmunity = CreateConVar("modelchooser_immunity", "0", "Whether players are immune to damage when selecting models", _, true, 0.0, true, 1.0);
	cvAutoReload = CreateConVar("modelchooser_autoreload", "0", "Whether to reload the model list on mapchanges", _, true, 0.0, true, 1.0);
	cvMenuSnd = CreateConVar("modelchooser_sound", "ui/buttonclickrelease.wav", "Menu click sound (auto downloads supported), empty to disable");
	cvOverlay = CreateConVar("modelchooser_overlay", "modelchooser/background", "Screen overlay material to show when choosing models (auto downloads supported), empty to disable");
	cvLockModel = CreateConVar("modelchooser_lock_model", "models/props_wasteland/prison_padlock001a.mdl", "Model to display for locked playermodels (auto downloads supported)");
	cvLockScale = CreateConVar("modelchooser_lock_scale", "5.0", "Scale of the lock model", _, true, 0.1);
	mp_forcecamera = FindConVar("mp_forcecamera");
	
	UserMsg hudMsgId = GetUserMessageId("HudMsg");
	if (hudMsgId != INVALID_MESSAGE_ID)
	{
		HookUserMessage(hudMsgId, Hook_HudMsg, true);
	}
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	CreateTimer(2.0, CheckHealthRaise, _, TIMER_REPEAT);
	
	GameData gamedata = new GameData("modelchooser");
	if (!gamedata)
	{
		SetFailState("Failed to load \"modelchooser\" gamedata");
	}
	LoadDHookVirtual(gamedata, hkSetModel, "CBaseEntity::SetModel");
	LoadDHookVirtual(gamedata, hkDeathSound, "CBasePlayer::DeathSound");
	LoadDHookVirtual(gamedata, hkSetAnimation, "CBasePlayer::SetAnimation");
	
	char szResetSequence[] = "CBaseAnimating::ResetSequence";
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, szResetSequence))
		SetFailState("Could not obtain gamedata signature %s", szResetSequence);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	if (!(callResetSequence = EndPrepSDKCall()))
		SetFailState("Could not prep SDK call %s", szResetSequence);
	
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
	delete selectableModels[client];
	delete unlockedModels[client];
	delete tMenuInit[client];
	unlockedModels[client] = new StringMap();
	activeSelection[client].Reset();
	menuSelection[client].Reset();
	playedHurtSoundAt[client] = -1;
	clientInitChecks[client] = 3;
	nextJumpSound[client] = 0.0;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
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

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "viewmodel") != -1 && HasEntProp(entity, Prop_Data, "m_hWeapon"))
	{
		DHookEntity(hkSetModel, false, entity, _, Hook_SetViewModelModel);
	}
}

public Action Command_Model(int client, int args)
{
	if (PreEnterCheck(client))
	{
		EnterModelChooser(client);
	}
	return Plugin_Handled;
}

public Action Command_UnlockModel(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_unlockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MAX_MODELNAME];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	char targetName[MAX_TARGET_LENGTH];
	int targets[MAXPLAYERS], targetCount;
	bool tnIsMl;
	
	if ((targetCount = ProcessTargetString(
			arg1,
			client,
			targets,
			MAXPLAYERS,
			COMMAND_FILTER_NO_IMMUNITY,
			targetName,
			sizeof(targetName),
			tnIsMl)) <= 0)
	{
		ReplyToTargetError(client, targetCount);
		return Plugin_Handled;
	}
	
	String_ToUpper(arg2, arg2, sizeof(arg2));
	
	PlayerModel model;
	if (modelList.FindByName(arg2, model) == -1)
	{
		ReplyToCommand(client, "Model named %s doesn't exist!", arg2);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < targetCount; i++)
	{
		UnlockModel(targets[i], arg2);
	}
	
	if (targetCount == 1)
	{
		ReplyToCommand(client, "Unlocked model %s for %N.", arg2, targets[0]);
	}
	else
	{
		ReplyToCommand(client, "Unlocked model %s for %d players.", arg2, targetCount);
	}
	
	return Plugin_Handled;
}

public Action Command_LockModel(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_lockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MAX_MODELNAME];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	char targetName[MAX_TARGET_LENGTH];
	int targets[MAXPLAYERS], targetCount;
	bool tnIsMl;
	
	if ((targetCount = ProcessTargetString(
			arg1,
			client,
			targets,
			MAXPLAYERS,
			COMMAND_FILTER_NO_IMMUNITY,
			targetName,
			sizeof(targetName),
			tnIsMl)) <= 0)
	{
		ReplyToTargetError(client, targetCount);
		return Plugin_Handled;
	}
	
	String_ToUpper(arg2, arg2, sizeof(arg2));
	
	PlayerModel model;
	if (modelList.FindByName(arg2, model) == -1)
	{
		ReplyToCommand(client, "Model named %s doesn't exist!", arg2);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < targetCount; i++)
	{
		LockModel(targets[i], arg2);
	}
	
	if (targetCount == 1)
	{
		ReplyToCommand(client, "Locked model %s for %N.", arg2, targets[0]);
	}
	else
	{
		ReplyToCommand(client, "Locked model %s for %d players.", arg2, targetCount);
	}
	
	return Plugin_Handled;
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
		UpdateViewModels(client);
		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

void RefreshModel(int client)
{
	if (IsClientInGame(client))
	{
		// something went wrong if this sticks
		SetEntityModel(client, FALLBACK_MODEL);
	}
}

public MRESReturn Hook_SetViewModelModel(int vm, DHookParam hParams)
{
	RequestFrame(UpdateViewModel, EntIndexToEntRef(vm));
	return MRES_Ignored;
}

void UpdateViewModels(int client)
{
	int count = GetEntPropArraySize(client, Prop_Send, "m_hViewModel");
	for (int i = 0; i < count; i++)
	{
		int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel", i);
		if (vm != -1)
		{
			UpdateViewModel(vm);
		}
	}
}

void UpdateViewModel(int vm)
{
	vm = EntRefToEntIndex(vm);
	if (vm != -1)
	{
		int client = GetEntPropEnt(vm, Prop_Data, "m_hOwner");
		if (0 < client <= MaxClients)
		{
			PlayerModel model;
			if (GetSelectedModelAuto(client, model))
			{
				ApplyEntityBodyGroupsFromString(vm, model.vmBodyGroups);
			}
		}
	}
}

void InitClientModels(int client)
{
	if (selectableModels[client])
		return;

	selectableModels[client] = BuildSelectableModels(client);
	if (!selectableModels[client].Length)
		return;
	
	char modelName[MAX_MODELNAME];
	cookieModel.Get(client, modelName, sizeof(modelName));
	if (!SelectModelByName(client, modelName, cookieSkin.GetInt(client), cookieBody.GetInt(client)))
	{
		if (!SelectDefaultModel(client, modelName))
		{
			return;
		}
	}

	Call_StartForward(fwdOnModelChanged);
	Call_PushCell(client);
	Call_PushString(modelName);
	Call_Finish();
}

ArrayList BuildSelectableModels(int client)
{
	ArrayList list = new ArrayList();
	for (int i = 0; i < modelList.Length; i++)
	{
		PlayerModel model; modelList.GetArray(i, model);
		if (model.adminBitFlags != -1)
		{
			int clientFlags = GetUserFlagBits(client);
			if (!(clientFlags & ADMFLAG_ROOT || clientFlags & model.adminBitFlags))
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
			return true;
		}
	}
	return false;
}

bool SelectDefaultModel(int client, char selectedName[MAX_MODELNAME] = "")
{
	if (!selectableModels[client].Length)
		return false;
	
	// find models with the highest prio
	// select random if there are multiple
	int maxPrio = cellmin;
	ArrayList maxPrioList = new ArrayList();
	
	for (int i = 0; i < selectableModels[client].Length; i++)
	{
		PlayerModel model; modelList.GetArray(selectableModels[client].Get(i), model);
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
		selectedName = model.name;
		delete maxPrioList;
		return true;
	}

	delete maxPrioList;
	return false;
}

bool IsModelLocked(PlayerModel model, int client)
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

//------------------------------------------------------
// Third-Person Model chooser menu
//------------------------------------------------------

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
	if (menuSelection[client].index != -1)
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

void ExitModelChooser(int client, bool silent = false)
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
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
	ClearMenuHud(client);
	SDKUnhook(client, SDKHook_OnTakeDamage, Hook_BlockDamage);
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
	SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime() + 0.25);
	ToggleMenuLock(client, false);
	delete tMenuInit[client];
	
	PlayerModel model;
	if (menuSelection[client].IsValid() && Selection2Model(client, menuSelection[client], model))
	{
		if (!silent)
		{
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			PlayRandomSound(soundPack.selectSounds, client);
		}
		
		activeSelection[client] = menuSelection[client];
		
		cookieModel.Set(client, model.name);
		cookieSkin.SetInt(client, model.GetSkin(menuSelection[client].skin));
		cookieBody.SetInt(client, model.GetBody(menuSelection[client].body));

		PrintToChat(client, "\x07d9843fModel selected: \x07f5bf42%s", model.name);
		
		Call_StartForward(fwdOnModelChanged);
		Call_PushCell(client);
		Call_PushString(model.name);
		Call_Finish();
	}

	menuSelection[client].Reset();
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
		model.GetSoundPack(soundPack);
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

bool g_bDrawing;

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
	
	SetHudTextParamsEx(-1.0, 0.01, 60.0, color, {200, 200, 200, 200}, 1, 0.1, initital? 1.2 : 0.0, 0.15);
	ShowHudText(client, topHudChanToggle[client], text);

	// Bottom
	Format(text, sizeof(text), "⮜ %7d / %-7d ⮞", menuSelection[client].index + 1, selectableModels[client].Length);
	SetHudTextParamsEx(-1.0, 0.95, 9999999.0, DEFAULT_HUD_COLOR, _, 1, 0.0, initital? 1.2 : 0.0, 1.0);
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
	
	if (menuSelection[client].index != -1)
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

//------------------------------------------------------
// Hurt/Death sounds
//------------------------------------------------------

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (playedHurtSoundAt[client] != -1 || GetClientTeam(client) == 1)
		return;
	
	int health = GetEventInt(event, "health");

	PlayerModel model;
	if (GetSelectedModelAuto(client, model))
	{
		if (0 < health <= model.hurtSndHP.Rand())
		{
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			PlayRandomSound(soundPack.hurtSounds, client, client, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX);
			playedHurtSoundAt[client] = health;
		}
	}
}

public Action CheckHealthRaise(Handle timer)
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
		SoundPack soundPack; model.GetSoundPack(soundPack);

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

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client)
	{
		int m_hRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (m_hRagdoll != -1)
		{
			StopSound(m_hRagdoll, SNDCHAN_STATIC, lastPlayedSound[client]);
		}
		StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
	}
}

//------------------------------------------------------
// Animation handling
//------------------------------------------------------

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
	if (sequence > -1)
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
					model.GetSoundPack(soundPack);
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

//------------------------------------------------------
// Bodygroup handling
//------------------------------------------------------

// Copy pasta of "SetBodygroup" from the SDK
void CalcBodygroup(StudioHdr pStudioHdr, int& body, int iGroup, int iValue)
{
	if (!pStudioHdr)
		return;

	BodyPart pBodyPart = pStudioHdr.GetBodyPart(iGroup);
	if (!pBodyPart.valid)
		return;

	int numModels = pBodyPart.nummodels;
	if (iValue >= numModels)
		return;

	int base = pBodyPart.base;
	int iCurrent = (body / base) % numModels;

	body = (body - (iCurrent * base) + (iValue * base));
}

void ApplyEntityBodyGroupsFromString(int entity, const char[] str)
{
	if (str[0] == EOS)
		return;
	
	StudioHdr pStudio = StudioHdr.FromEntity(entity);
	if (!pStudio.valid)
		return;

	int numBodyParts = pStudio.numbodyparts;
	int body = GetEntityBody(entity);

	char buffer1[128], buffer2[128];
	for (int count, strIndex, n;; count++)
	{
		n = SplitString(str[strIndex], ";", buffer1, sizeof(buffer1));
		TrimString(buffer1);
		if (n == -1)
		{
			if (count)
			{
				LogError("Invalid bodygroup string: \"%s\"", str);
				return;
			}
			else
			{
				// no separator found - assume raw body index specified
				body = StringToInt(buffer1);
				break;
			}
		}
		strIndex += n;

		n = SplitString(str[strIndex], ";", buffer2, sizeof(buffer2));
		if (n == -1)
		{
			// copy remainder
			strcopy(buffer2, sizeof(buffer2), str[strIndex]);
		}
		TrimString(buffer2);

		// Convert buffers to actual indexes on the model

		int bodyPartIndex = -1;
		int subModelIndex = StringToInt(buffer2);
		
		for (int i = 0; i < numBodyParts; i++)
		{
			BodyPart pBodyPart = pStudio.GetBodyPart(i);
			pBodyPart.GetName(buffer2, sizeof(buffer2));
			if (StrEqual(buffer1, buffer2, false))
			{
				bodyPartIndex = i;
				break;
			}
		}

		if (bodyPartIndex != -1)
			CalcBodygroup(pStudio, body, bodyPartIndex, subModelIndex);
		
		if (n == -1)
		{
			// end of list
			break;
		}
		strIndex += n;
	}
	SetEntityBody(entity, body);
}

//------------------------------------------------------
// Config parsing
//------------------------------------------------------

void LoadConfig()
{
	char szConfigPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, szConfigPath, sizeof(szConfigPath), "configs/player_models.cfg");
	if (!FileExists(szConfigPath))
		SetFailState("File %s doesn't exist", szConfigPath);
	
	KeyValues kv = new KeyValues("");
	char section[32];
	if (!(kv.ImportFromFile(szConfigPath) && kv.GetSectionName(section, sizeof(section)) && strcmp(section, "ModelSystem", false) == 0))
		SetFailState("Couldn't import %s into KeyValues", szConfigPath);
		
	if (kv.GotoFirstSubKey())
	{
		do
		{
			if (kv.GetSectionName(section, sizeof(section)))
			{
				if (StrEqual(section, "Models", false))
				{
					ParseModels(kv);
				}
				else if (StrEqual(section, "Sounds", false))
				{
					ParseSounds(kv);
				}
			}
		}
		while (kv.GotoNextKey());
	}
	delete kv;
}

void ParseModels(KeyValues kv)
{
	StringMap duplicityChecker = new StringMap();
	char buffer[128];
	
	if (kv.GotoFirstSubKey())
	{
		do
		{
			PlayerModel model;
			if (kv.GetSectionName(model.name, sizeof(model.name)))
			{
				if (!kv.GetNum("enabled", 1))
					continue;

				String_ToUpper(model.name, model.name, sizeof(model.name));
				if (!duplicityChecker.SetString(model.name, "", false))
					SetFailState("Duplicate model name: %s", model.name);

				kv.GetString("path", model.path, sizeof(model.path));
				if (model.path[0] == '\0')
					continue;

				SmartDM.AddEx(model.path, downloads, true, true);

				StudioHdr studio = StudioHdr(model.path);
				model.skins = ProcessSkins(studio, ParseDelimitedIntList(kv, "skins"));
				model.bodyGroups = ProcessBodyGroups(studio, ParseDelimitedIntList(kv, "bodygroups"));

				kv.GetString("vmbody", model.vmBodyGroups, sizeof(model.vmBodyGroups));
				TrimString(model.vmBodyGroups);

				if (kv.GetDataType("anims") == KvData_None && kv.JumpToKey("anims"))
				{
					ParseAnims(kv, studio, model);
					kv.GoBack();
				}
				
				kv.GetString("sounds", model.sounds, sizeof(model.sounds));
				String_ToUpper(model.sounds, model.sounds, sizeof(model.sounds));
				
				ParseInterval(kv, model.jumpSndParams.cooldown, "jumpSoundTime");
				ParseInterval(kv, model.hurtSndHP, "hurtSoundHP", HURT_SOUND_HP, HURT_SOUND_HP);
				
				model.locked = !!kv.GetNum("locked", 0);
				model.defaultPrio = kv.GetNum("defaultprio");
				if (kv.GetDataType("hudcolor") != KvData_None)
				{
					kv.GetColor4("hudcolor", model.hudColor);
				}
				else
				{
					model.hudColor = DEFAULT_HUD_COLOR;
				}

				kv.GetString("adminflags", buffer, sizeof(buffer), "-1");
				model.adminBitFlags = StrEqual(buffer, "-1")? -1 : ReadFlagString(buffer);

				if (kv.GetDataType("downloads") == KvData_None && kv.JumpToKey("downloads"))
				{
					ParseFileItems(kv, false);
					kv.GoBack();
				}
								
				modelList.PushArray(model);
			}
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
	delete duplicityChecker;
}

void ParseAnims(KeyValues kv, StudioHdr studiohdr, PlayerModel model)
{
	StringMap act2seq = new StringMap();
	StringMap seqNums = new StringMap();
	char seqName[MAX_ANIM_NAME], actName[MAX_ANIM_NAME];
	int seqCount = studiohdr.numlocalseq;
	for (int i = 0; i < seqCount; i++)
	{
		Sequence seq = studiohdr.GetSequence(i);
		seq.GetLabelName(seqName, sizeof(seqName));
		seq.GetActivityName(actName, sizeof(actName));
		seqNums.SetValue(seqName, i);

		WeightedSequenceList seqList;
		if (!act2seq.GetValue(actName, seqList))
		{
			seqList = new WeightedSequenceList();
			act2seq.SetValue(actName, seqList);
		}
		seqList.Add(i, seq.actweight);
	}
	
	ParseAnim(kv, model, model.anim_idle, "idle", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_idle_crouch, "idle_crouch", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_walk, "walk", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_walk_crouch, "walk_crouch", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_run, "run", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_jump, "jump", act2seq, seqNums);
	ParseAnim(kv, model, model.anim_noclip, "noclip", act2seq, seqNums);

	StringMapSnapshot snapshot = act2seq.Snapshot();
	for (int i = 0; i < snapshot.Length; i++)
	{
		WeightedSequenceList wsl;
		snapshot.GetKey(i, actName, sizeof(actName));
		act2seq.GetValue(actName, wsl);
		wsl.Close();
	}
	snapshot.Close();
	act2seq.Close();
	seqNums.Close();
}

void ParseAnim(KeyValues kv, PlayerModel model, PlayerAnimation anim, const char[] key, StringMap act2seq, StringMap seqNums)
{
	char szSearchName[MAX_ANIM_NAME];

	if (kv.GetDataType(key) == KvData_None && kv.JumpToKey(key))
	{
		kv.GetString("anim", szSearchName, sizeof(szSearchName));
		anim.rate = kv.GetFloat("rate", 1.0);
		kv.GoBack();
	}
	else
	{
		kv.GetString(key, szSearchName, sizeof(szSearchName));
		anim.rate = 1.0;
	}

	TrimString(szSearchName);
	if (szSearchName[0] == '\0')
		return;

	int seq;
	if (seqNums.GetValue(szSearchName, seq))
	{
		anim.seqList = new WeightedSequenceList();
		anim.seqList.Add(seq, 0);
		return;
	}
	if (act2seq.GetValue(szSearchName, anim.seqList))
	{
		anim.seqList = view_as<WeightedSequenceList>(CloneHandle(anim.seqList));
	}
	else
	{
		LogMessage("Animation activity/sequence \"%s\" not found in model \"%s\"!", szSearchName, model.path);
	}
}

void ParseSounds(KeyValues kv)
{
	if (kv.GotoFirstSubKey())
	{
		do
		{
			SoundPack soundPack;
			char name[MAX_SOUNDSNAME];
			if (kv.GetSectionName(name, sizeof(name)))
			{
				if (kv.JumpToKey("Hurt"))
				{
					soundPack.hurtSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else soundPack.hurtSounds = CreateArray();
				
				if (kv.JumpToKey("Death"))
				{
					soundPack.deathSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else soundPack.deathSounds = CreateArray();
				
				if (kv.JumpToKey("View"))
				{
					soundPack.viewSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else soundPack.viewSounds = CreateArray();
				
				if (kv.JumpToKey("Select"))
				{
					soundPack.selectSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else soundPack.selectSounds = CreateArray();

				if (kv.JumpToKey("Jump"))
				{
					soundPack.jumpSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else soundPack.jumpSounds = CreateArray();

				String_ToUpper(name, name, sizeof(name));
				soundMap.SetArray(name, soundPack, sizeof(SoundPack));
			}
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
}

ArrayList ParseFileItems(KeyValues kv, bool precache, const char[] folderType = "")
{
	ArrayList files = new ArrayList(PLATFORM_MAX_PATH);
	char path[PLATFORM_MAX_PATH];
	
	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			kv.GetString(NULL_STRING, path, sizeof(path));
			if (path[0] == '\0')
				continue;
			
			files.PushString(path);
			if (folderType[0] != '\0')
			{
				Format(path, sizeof(path), "%s/%s", folderType, path);
			}
			SmartDM.AddEx(path, downloads, precache, true);
		}
		while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	return files;
}

ArrayList ParseDelimitedIntList(KeyValues kv, const char[] key)
{
	if (!kv.JumpToKey(key))
		return null;
	
	char value[2048], buffer[32];
	kv.GetString(NULL_STRING, value, sizeof(value));
	
	ArrayList list = new ArrayList();
	
	for (int i, n;;)
	{
		n = SplitString(value[i], ";", buffer, sizeof(buffer));
		if (n == -1)
		{
			// remainder
			strcopy(buffer, sizeof(buffer), value[i]);
			TrimString(buffer);
			if (buffer[0] != EOS)
			{
				list.Push(StringToInt(buffer));
			}
			break;
		}
		i += n;
		TrimString(buffer);
		if (buffer[0] != EOS)
		{
			list.Push(StringToInt(buffer));
		}
	}

	kv.GoBack();
	return list;
}

void ParseInterval(KeyValues kv, Interval interval, const char[] key, float defualtMin = 0.0, float defaultMax = 0.0)
{
	char val[32];
	kv.GetString(key, val, sizeof(val), "");

	if (val[0] == EOS)
	{
		interval.min = defualtMin;
		interval.max = defaultMax;
		return;
	}

	int delim = StrContains(val, ";");
	if (delim != -1 && delim != sizeof(val) - 1)
	{
		interval.max = StringToFloat(val[delim + 1]);
		val[delim] = '\0';
		interval.min = StringToFloat(val);
		return;
	}

	interval.min = interval.max = StringToFloat(val);
}

ArrayList ProcessSkins(StudioHdr studio, ArrayList list)
{
	int numSkins = studio.numskinfamilies;

	if (list)
	{
		for (int i = list.Length - 1; i >= 0; i--)
		{
			int skin = list.Get(i);
			if (skin < 0 || skin >= numSkins)
			{
				list.Erase(i);
			}
		}
	}
	else
	{
		list = new ArrayList();
		for (int i = 0; i < numSkins; i++)
		{
			list.Push(i);
		}
	}

	if (!list.Length)
	{
		list.Push(0);
	}
	
	return list;
}

ArrayList ProcessBodyGroups(StudioHdr studio, ArrayList list)
{
	int numBodyGroups;
	for (int i = studio.numbodyparts - 1; i >= 0; i--)
	{
		BodyPart pBodyPart = studio.GetBodyPart(i);
		numBodyGroups += pBodyPart.nummodels;
	}

	if (list)
	{
		for (int i = list.Length - 1; i >= 0; i--)
		{
			int bodyGroup = list.Get(i);
			if (bodyGroup < 0 || bodyGroup >= numBodyGroups)
			{
				list.Erase(i);
			}
		}
	}
	else
	{
		list = new ArrayList();
		for (int i = 0; i < numBodyGroups; i++)
		{
			list.Push(i);
		}
	}

	if (!list.Length)
	{
		list.Push(0);
	}

	return list;
}

//------------------------------------------------------
// Utils
//------------------------------------------------------

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

stock void PrecacheSoundsInList(ArrayList soundList)
{
	int len = soundList.Length;
	char path[PLATFORM_MAX_PATH];
	
	for (int i = 0; i < len; i++)
	{
		soundList.GetString(i, path, sizeof(path));
		PrecacheSound(path, true);
	}	
}

public Action Hook_BlockDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	return Plugin_Handled;
}

Action Hook_TransmitToOwnerOnly(int entity, int client)
{
	return (Entity_GetOwner(entity) == client) ? Plugin_Continue : Plugin_Stop;
}

stock void LoadDHookDetour(GameData pGameConfig, DynamicDetour& pHandle, const char[] szFuncName, DHookCallback pCallbackPre = null, DHookCallback pCallbackPost = null)
{
	pHandle = DynamicDetour.FromConf(pGameConfig, szFuncName);
	if (!pHandle)
		SetFailState("Couldn't create hook %s", szFuncName);
	if (pCallbackPre && !pHandle.Enable(Hook_Pre, pCallbackPre))
		SetFailState("Couldn't enable pre detour hook %s", szFuncName);
	if (pCallbackPost && !pHandle.Enable(Hook_Post, pCallbackPost))
		SetFailState("Couldn't enable post detour hook %s", szFuncName);
}

stock void LoadDHookVirtual(GameData pGameConfig, DynamicHook& pHandle, const char[] szFuncName)
{
	pHandle = DynamicHook.FromConf(pGameConfig, szFuncName);
	if (pHandle == null)
		SetFailState("Couldn't create hook %s", szFuncName);
}

stock int GetEntityBody(int entity)
{
	return GetEntProp(entity, Prop_Send, "m_nBody");
}

stock void SetEntityBody(int entity, int body)
{
	SetEntProp(entity, Prop_Send, "m_nBody", body);
}

stock int GetEntitySkin(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_nSkin");
}

stock void SetEntitySkin(int entity, int body)
{
	SetEntProp(entity, Prop_Data, "m_nSkin", body);
}

stock int GetEntityEffects(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_fEffects");
}

stock void SetEntityEffects(int entity, int effects)
{
	SetEntProp(entity, Prop_Data, "m_fEffects", effects);
	ChangeEdictState(entity, FindDataMapInfo(entity, "m_fEffects"));
}

/**
 * HL2DM displays all carried weapons' shadows in thirdperson.
 * We fix this to only show active weapon.
 */
stock void FixThirdpersonWeapons(int client)
{
	int activeWeapon = Client_GetActiveWeapon(client);
	LOOP_CLIENTWEAPONS(client, weapon, index)
	{
		if (activeWeapon != weapon)
		{
			SetEntityEffects(weapon, GetEntityEffects(weapon) | EF_NODRAW | EF_NOSHADOW);
		}
		else
		{
			SetEntityEffects(weapon, GetEntityEffects(weapon) & ~EF_NODRAW & ~EF_NOSHADOW);
		}
	}
}
