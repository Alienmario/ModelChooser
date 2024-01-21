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

#define PLUGIN_VERSION  "2.0"

public Plugin myinfo =
{
	name = "Playermodel chooser",
	author = "Alienmario",
	description = "The enhanced playermodel system",
	version = PLUGIN_VERSION
};

#define MAX_MODELNAME 128
#define MAX_ANIM_NAME 128
#define HURT_SOUND_HP 45

#define HURT_PITCH_MIN 95
#define HURT_PITCH_MAX 102
#define JUMP_PITCH_MIN 90
#define JUMP_PITCH_MAX 105
#define JUMP_VOL 0.5
#define JUMP_SND_DELAY_MIN 2.0
#define JUMP_SND_DELAY_MAX 2.0

// #define OVERLAY     "folder/example"
// #define OVERLAY_VMT "materials/" ...OVERLAY... ".vmt"
// #define OVERLAY_VTF "materials/" ...OVERLAY... ".vtf"

#define DEFAULT_MODEL "models/error.mdl"
int DEFAULT_HUD_COLOR[] = {150, 150, 150, 150};

//------------------------------------------------------
// Data structures
//------------------------------------------------------

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
		PrecacheSounds(this.hurtSounds);
		PrecacheSounds(this.deathSounds);
		PrecacheSounds(this.viewSounds);
		PrecacheSounds(this.selectSounds);
		PrecacheSounds(this.jumpSounds);
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
		if (size > 0)
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
		if (this.seqList)
		{
			this.seqList.Close();
		}
	}
}

enum struct PlayerModel
{
	bool locked;
	char name[MAX_MODELNAME];
	char path[PLATFORM_MAX_PATH];
	int skinCount;
	int adminBitFlags;
	int defaultPrio;
	char sounds[MAX_MODELNAME];
	int hurtSoundHP;
	int hudColor[4];

	PlayerAnimation anim_idle;
	PlayerAnimation anim_walk;
	PlayerAnimation anim_run;
	PlayerAnimation anim_jump;
	PlayerAnimation anim_idle_crouch;
	PlayerAnimation anim_walk_crouch;
	PlayerAnimation anim_noclip;
	
	void Close()
	{
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

//------------------------------------------------------
// Variables
//------------------------------------------------------

// Complete model list containing entries of PlayerModel
ModelList modelList;

// The filtered list of selectable models. Contains indexes into modelList
ArrayList selectableModels[MAXPLAYERS+1];

// Index into selectableModels for active model
int selectedIndex[MAXPLAYERS+1];

// Active model skin
int selectedSkin[MAXPLAYERS+1];

// Index into selectableModels for active model in menu, -1 indicates menu closed
int selectedMenuIndex[MAXPLAYERS+1];

// Active menu model skin
int selectedMenuSkin[MAXPLAYERS+1];

// Whether currently selected model in menu is locked
bool selectedMenuIndexLocked[MAXPLAYERS+1];

// Skin count of currently selected model in menu
int selectedMenuSkinCount[MAXPLAYERS+1];

// Map containing names of unlocked models
StringMap unlockedModels[MAXPLAYERS+1];

// Used for stopping
char lastPlayedSound[MAXPLAYERS+1][PLATFORM_MAX_PATH];

// Flag for playing hurt sound once
int playedHurtSoundAt[MAXPLAYERS+1] = {-1, ...};

float nextJumpSound[MAXPLAYERS + 1];

// Counter for # of checks to pass until client models can be initialized
int clientInitChecks[MAXPLAYERS+1];

int topHudChanToggle[MAXPLAYERS + 1];
int bottomHudChanToggle[MAXPLAYERS + 1] = {2, ...};
Handle hudInitTimer[MAXPLAYERS + 1];
DynamicHook DHook_SetModel;
DynamicHook DHook_DeathSound;
DynamicHook DHook_SetAnimation;
Handle Func_ResetSequence;
Cookie modelCookie;
Cookie skinCookie;
GlobalForward onModelChangedFwd;
ConVar cvSelectionImmunity;
ConVar cvAutoReload;
SmartDM_FileSet downloads;

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

	if (GetSelectedModel(GetNativeCell(1), model)) {
		SetNativeString(2, model.name, GetNativeCell(3));
		return true;
	}
	return false;
}

public any Native_GetCurrentModelPath(Handle plugin, int numParams)
{
	PlayerModel model;

	if (GetSelectedModel(GetNativeCell(1), model)) {
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
	if (GetNativeCell(3)) {
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
	return selectedMenuIndex[GetNativeCell(1)] != -1;
}

//------------------------------------------------------
// Plugin entry points, init
//------------------------------------------------------

public void OnPluginStart()
{
	modelList = new ModelList();
	soundMap = new SoundMap();
	downloads = new SmartDM_FileSet();
	modelCookie = new Cookie("playermodel", "Stores player model prefernce", CookieAccess_Protected);
	skinCookie = new Cookie("playermodel_skin", "Stores player model skin prefernce", CookieAccess_Protected);
	onModelChangedFwd = new GlobalForward("ModelChooser_OnModelChanged", ET_Ignore, Param_Cell, Param_String);
	
	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_models", Command_Model);
	RegConsoleCmd("sm_model", Command_Model);
	RegAdminCmd("sm_unlockmodel", Command_UnlockModel, ADMFLAG_KICK, "Unlock a locked model by name for a player");
	RegAdminCmd("sm_lockmodel", Command_LockModel, ADMFLAG_KICK, "Re-lock a model by name for a player");
	cvSelectionImmunity = CreateConVar("modelchooser_immunity", "0", "Whether players have damage immunity / are unable to fire when selecting models", _, true, 0.0, true, 1.0);
	cvAutoReload = CreateConVar("modelchooser_autoreload", "0", "Whether to reload model list on mapchanges", _, true, 0.0, true, 1.0);
	
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	CreateTimer(2.0, CheckHealthRaise, _, TIMER_REPEAT);
	
	GameData gamedata = new GameData("modelchooser");
	if (!gamedata)
	{
		SetFailState("Failed to load \"modelchooser\" gamedata");
	}
	LoadDHookVirtual(gamedata, DHook_SetModel, "CBaseEntity::SetModel_");
	LoadDHookVirtual(gamedata, DHook_DeathSound, "CBasePlayer::DeathSound");
	LoadDHookVirtual(gamedata, DHook_SetAnimation, "CBasePlayer::SetAnimation");
	
	char szResetSequence[] = "CBaseAnimating::ResetSequence";
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, szResetSequence))
		SetFailState("Could not obtain gamedata signature %s", szResetSequence);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	if (!(Func_ResetSequence = EndPrepSDKCall()))
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
		downloads.AddToDownloadsTable();
		soundMap.Precache();
		modelList.Precache();
	}
	
	PrecacheModel(DEFAULT_MODEL, true);
	#if defined OVERLAY_VMT
	AddFileToDownloadsTable(OVERLAY_VMT);
	#endif
	#if defined OVERLAY_VTF
	AddFileToDownloadsTable(OVERLAY_VTF);
	#endif
	
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
	delete hudInitTimer[client];
	unlockedModels[client] = new StringMap();
	selectedIndex[client] = 0;
	selectedMenuIndex[client] = -1;
	selectedSkin[client] = 0;
	selectedMenuSkin[client] = 0;
	playedHurtSoundAt[client] = -1;
	clientInitChecks[client] = 3;
	nextJumpSound[client] = 0.0;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		DHookEntity(DHook_SetModel, false, client, _, Hook_SetModel);
		DHookEntity(DHook_DeathSound, false, client, _, Hook_DeathSound);
		DHookEntity(DHook_SetAnimation, false, client, _, Hook_SetAnimation);
		clientInitChecks[client]--;
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!--clientInitChecks[client]) {
		InitClientModels(client);
	}
}

public void OnClientCookiesCached(int client)
{
	if (!--clientInitChecks[client]) {
		InitClientModels(client);
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
	if (modelList.FindByName(arg2, model) == -1) {
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

public MRESReturn Hook_SetModel(int client, Handle hParams) {
	PlayerModel model;
	if (GetSelectedModelAuto(client, model)) {
		DHookSetParamString(hParams, 1, model.path);
		SetEntProp(client, Prop_Data, "m_nSkin", GetSelectedSkinAuto(client));
		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

void RefreshModel(int client) {
	if (IsClientInGame(client)) {
		SetEntityModel(client, DEFAULT_MODEL);
	}
}

void InitClientModels(int client) {
	if (selectableModels[client] == null)
	{
		selectableModels[client] = BuildSelectableModels(client);
		
		char modelName[MAX_MODELNAME], modelSkin[4];
		modelCookie.Get(client, modelName, sizeof(modelName));
		skinCookie.Get(client, modelSkin, sizeof(modelSkin));
		if (!SelectModelByName(client, modelName, StringToInt(modelSkin)))
		{
			if (!SelectModelByDefaultPrio(client, modelName))
			{
				return;
			}
		}
		Call_StartForward(onModelChangedFwd);
		Call_PushCell(client);
		Call_PushString(modelName);
		Call_Finish();
	}
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

bool GetSelectedModelAuto(int client, PlayerModel selectedModel) {
	bool inMenu = (!selectedMenuIndexLocked[client] && selectedMenuIndex[client] != -1);
	return GetSelectedModel(client, selectedModel, inMenu);
}

int GetSelectedSkinAuto(int client) {
	bool inMenu = (!selectedMenuIndexLocked[client] && selectedMenuIndex[client] != -1);
	return (inMenu? selectedMenuSkin[client] : selectedSkin[client]);
}

bool GetSelectedModel(int client, PlayerModel selectedModel, bool inMenu = false) {
	if(selectableModels[client] != null && selectableModels[client].Length) {
		int index = selectableModels[client].Get(inMenu? selectedMenuIndex[client] : selectedIndex[client]);
		modelList.GetArray(index, selectedModel);
		return true;
	}
	return false;
}

bool SelectModelByName(int client, const char[] modelName, int skin = 0)
{
	PlayerModel model;
	int index = modelList.FindByName(modelName, model);
	if (index != -1) {
		int clIndex = selectableModels[client].FindValue(index);
		if (clIndex != -1 && !IsModelLocked(model, client)) {
			selectedIndex[client] = clIndex;
			selectedSkin[client] = skin;
			RefreshModel(client);
			return true;
		}
	}
	return false;
}

bool SelectModelByDefaultPrio(int client, char selectedName[MAX_MODELNAME] = "")
{
	if (!selectableModels[client].Length) {
		return false;
	}
	
	// find models with the highest prio
	// select random if there are multiple
	int maxPrio = -1;
	ArrayList maxPrioList = new ArrayList();
	
	for (int i = 0; i < selectableModels[client].Length; i++) {
		PlayerModel model; modelList.GetArray(selectableModels[client].Get(i), model);
		if (IsModelLocked(model, client)) {
			continue;
		}
		if (model.defaultPrio > maxPrio) {
			maxPrio = model.defaultPrio;
			maxPrioList.Clear();
			maxPrioList.Push(i);
		} else if (model.defaultPrio == maxPrio) {
			maxPrioList.Push(i);
		}
	}
	
	if (maxPrioList.Length) {
		selectedIndex[client] = maxPrioList.Get(Math_GetRandomInt(0, maxPrioList.Length - 1));
		PlayerModel model;
		modelList.GetArray(selectableModels[client].Get(selectedIndex[client]), model);
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

void UnlockModel(int client, char modelName[MAX_MODELNAME]) {
	unlockedModels[client].SetValue(modelName, true);
}

void LockModel(int client, char modelName[MAX_MODELNAME]) {
	unlockedModels[client].Remove(modelName);
}

//------------------------------------------------------
// Third-Person Model chooser menu
//------------------------------------------------------

bool PreEnterCheck(int client)
{
	if (!client) {
		return false;
	}
	if (selectableModels[client] == null || !selectableModels[client].Length) {
		PrintToChat(client, "[ModelChooser] No models are available.");
		return false;
	}
	if (!IsPlayerAlive(client)) {
		PrintToChat(client, "[ModelChooser] You need to be alive to use models.");
		return false;
	}
	if (selectedMenuIndex[client] != -1) {
		PrintToChat(client, "[ModelChooser] You are already changing models, dummy :]");
		return false;
	}
	if (GetEntityFlags(client) & FL_ATCONTROLS || Client_IsInThirdPersonMode(client)) {
		PrintToChat(client, "[ModelChooser] You cannot change models currently.");
		return false;
	}
	return true;
}

void EnterModelChooser(int client)
{
	selectedMenuIndex[client] = selectedIndex[client];
	selectedMenuSkin[client] = selectedSkin[client];
	
	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (ragdoll != -1)
	{
		AcceptEntityInput(ragdoll, "Kill");
	}
	StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
	StopSound(client, SNDCHAN_AUTO, lastPlayedSound[client]);
	
	Client_SetObserverTarget(client, 0);
	Client_SetObserverMode(client, OBS_MODE_DEATHCAM, false);
	Client_SetDrawViewModel(client, false);
	#if defined OVERLAY
	Client_SetScreenOverlay(client, OVERLAY);
	#endif
	Client_SetHideHud(client, HIDEHUD_HEALTH|HIDEHUD_CROSSHAIR|HIDEHUD_FLASHLIGHT|HIDEHUD_WEAPONSELECTION|HIDEHUD_MISCSTATUS);
	Client_ScreenFade(client, 100, FFADE_PURGE|FFADE_IN, 0);
	SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);

	if (cvSelectionImmunity.BoolValue)
	{
		SDKHook(client, SDKHook_OnTakeDamage, BlockDamage);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", float(SIZE_OF_INT));
	}
	
	hudInitTimer[client] = CreateTimer(0.8, Timer_UpdateMenuHud, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	OnMenuModelSelected(client);
}

void ExitModelChooser(int client, bool silent = false)
{
	Client_SetObserverTarget(client, -1);
	Client_SetObserverMode(client, OBS_MODE_NONE, false);
	Client_SetDrawViewModel(client, true);
	#if defined OVERLAY
	Client_SetScreenOverlay(client, "");
	#endif
	Client_SetHideHud(client, 0);
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
	ClearHud(client);
	SDKUnhook(client, SDKHook_OnTakeDamage, BlockDamage);
	SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime());
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
	
	PlayerModel model;
	GetSelectedModel(client, model, true);
	
	if (!selectedMenuIndexLocked[client])
	{
		if (!silent)
		{
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			PlayRandomSound(soundPack.selectSounds, client);
		}
		selectedIndex[client] = selectedMenuIndex[client];
		selectedSkin[client] = selectedMenuSkin[client];
		
		modelCookie.Set(client, model.name);
		char buf[4]; IntToString(selectedSkin[client], buf, sizeof(buf));
		skinCookie.Set(client, buf);

		PrintToChat(client, "\x07d9843fModel selected: \x07f5bf42%s", model.name);
		
		Call_StartForward(onModelChangedFwd);
		Call_PushCell(client);
		Call_PushString(model.name);
		Call_Finish();
	}
	selectedMenuIndex[client] = -1;
	delete hudInitTimer[client];
}

void OnMenuModelSelected(int client) {
	StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);

	PlayerModel model;
	GetSelectedModel(client, model, true);
	selectedMenuSkinCount[client] = model.skinCount;
	
	if (IsModelLocked(model, client))
	{
		selectedMenuIndexLocked[client] = true;
	}
	else
	{
		selectedMenuIndexLocked[client] = false;
		SoundPack soundPack;
		model.GetSoundPack(soundPack);
		RefreshModel(client);
		PlayRandomSound(soundPack.viewSounds, client, _, SNDCHAN_BODY);
	}
	UpdateMenuHud(client, model);
}

void OnMenuSkinSelected(int client) {
	if (!selectedMenuIndexLocked[client])
	{
		PlayerModel model;
		GetSelectedModel(client, model, true);
		UpdateMenuHud(client, model, false);
		RefreshModel(client);
	}
}

void UpdateMenuHud(int client, PlayerModel model, bool top = true, bool initital = false) {
	if (hudInitTimer[client])
		return;
	
	static char text[128];

	ClearHud(client, top, true);
	if (top)
	{
		FormatEx(text, sizeof(text), selectedMenuIndexLocked[client]? "|LOCKED|" : model.name);
		SetHudTextParamsEx(-1.0, 0.035, 60.0,  model.hudColor, {200, 200, 200, 200}, 1, 0.1, initital? 0.5 : 0.15, 0.15);
		ShowHudText(client, topHudChanToggle[client], text);
	}
	
	// BOTTOM
	if (selectedMenuSkinCount[client] > 1 && !selectedMenuIndexLocked[client])
	{
		FormatEx(text, sizeof(text), "⇣ %d / %d ⇡\n", selectedMenuSkin[client] + 1, selectedMenuSkinCount[client]);
	}
	else
	{
		text = "";
	}
	Format(text, sizeof(text), "%s⮜ %d of %d ⮞", text, selectedMenuIndex[client] + 1, selectableModels[client].Length);
	SetHudTextParamsEx(-1.0, 0.9, 9999999.0, DEFAULT_HUD_COLOR, _, 1, 0.0, initital? 0.5 : 0.0, 1.0);
	ShowHudText(client, bottomHudChanToggle[client], text);
}

void ClearHud(int client, bool top = true, bool bottom = true)
{
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
}

public void Timer_UpdateMenuHud(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client)
	{
		hudInitTimer[client] = null;
		PlayerModel model;
		if (GetSelectedModel(client, model, true))
		{
			UpdateMenuHud(client, model, true, true);
		}
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (0 < client <= MAXPLAYERS) {
		static int lastButtons[MAXPLAYERS+1];
		if (selectedMenuIndex[client] != -1) {
			if (!IsPlayerAlive(client))
			{
				ExitModelChooser(client, true);
			}
			else if ((buttons & IN_USE || buttons & IN_JUMP) && !selectedMenuIndexLocked[client])
			{
				ExitModelChooser(client);
			}
			else
			{
				if (buttons & IN_MOVELEFT && !(lastButtons[client] & IN_MOVELEFT)) {
					if (--selectedMenuIndex[client] < 0) {
						selectedMenuIndex[client] = selectableModels[client].Length - 1;
					}
					selectedMenuSkin[client] = 0;
					OnMenuModelSelected(client);
				}
				if (buttons & IN_MOVERIGHT && !(lastButtons[client] & IN_MOVERIGHT)) {
					if (++selectedMenuIndex[client] >= selectableModels[client].Length) {
						selectedMenuIndex[client] = 0;
					}
					selectedMenuSkin[client] = 0;
					OnMenuModelSelected(client);
				}
				if (buttons & IN_FORWARD && !(lastButtons[client] & IN_FORWARD)) {
					if (--selectedMenuSkin[client] < 0) {
						selectedMenuSkin[client] = selectedMenuSkinCount[client] - 1;
					}
					OnMenuSkinSelected(client);
				}
				if (buttons & IN_BACK && !(lastButtons[client] & IN_BACK)) {
					if (++selectedMenuSkin[client] >= selectedMenuSkinCount[client]) {
						selectedMenuSkin[client] = 0;
					}
					OnMenuSkinSelected(client);
				}
			}
		}
		lastButtons[client] = buttons;
	}
}

//------------------------------------------------------
// Hurt sounds
//------------------------------------------------------

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (playedHurtSoundAt[client] != -1)
		return;
	if (GetClientTeam(client) == 1)
		return;
	
	int health = GetEventInt(event, "health");
	PlayerModel model;

	if (GetSelectedModelAuto(client, model)) {
		if (0 < health <= model.hurtSoundHP) {
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			PlayRandomSound(soundPack.hurtSounds, client, client, SNDCHAN_STATIC, true, HURT_PITCH_MIN, HURT_PITCH_MAX);
			playedHurtSoundAt[client] = health;
		}
	}
}

public Action CheckHealthRaise(Handle timer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			if (playedHurtSoundAt[i] != -1 && GetClientHealth(i) > playedHurtSoundAt[i]) {
				playedHurtSoundAt[i] = -1;
			}
		}
	}
	return Plugin_Continue;
}

public MRESReturn Hook_DeathSound(int client, DHookParam hParams)
{
	if (selectedMenuIndex[client] != -1 && !IsPlayerAlive(client))
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
			SDKCall(Func_ResetSequence, client, sequence);
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
				// if (GetRandomFloat(0.0, 1.0) <= JUMP_SND_CHANCE)
				{
					SoundPack soundPack;
					model.GetSoundPack(soundPack);
					PlayRandomSound(soundPack.jumpSounds, client, client, SNDCHAN_STATIC, true, JUMP_PITCH_MIN, JUMP_PITCH_MAX, JUMP_VOL);
					nextJumpSound[client] = time + GetRandomFloat(JUMP_SND_DELAY_MIN, JUMP_SND_DELAY_MAX);
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
		} while (kv.GotoNextKey());
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

				StudioHdr studiohdr = StudioHdr(model.path);
				model.skinCount = studiohdr.numskinfamilies;
				
				if (kv.GetDataType("anims") == KvData_None && kv.JumpToKey("anims"))
				{
					ParseAnims(kv, studiohdr, model);
					kv.GoBack();
				}
				
				kv.GetString("sounds", model.sounds, sizeof(model.sounds));
				String_ToUpper(model.sounds, model.sounds, sizeof(model.sounds));
				
				model.locked = !!kv.GetNum("locked", 0);
				model.defaultPrio = kv.GetNum("defaultprio");
				model.hurtSoundHP = kv.GetNum("hurtsoundHP", HURT_SOUND_HP);
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
	for(int i = 0; i < snapshot.Length; i++)
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
			char name[MAX_MODELNAME];
			if (kv.GetSectionName(name, sizeof(name)))
			{
				if (kv.JumpToKey("Hurt"))
				{
					soundPack.hurtSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				}
				else
				{
					soundPack.hurtSounds = CreateArray();
				}
				
				if (kv.JumpToKey("Death"))
				{
					soundPack.deathSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				} else {
					soundPack.deathSounds = CreateArray();
				}
				
				if (kv.JumpToKey("View"))
				{
					soundPack.viewSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				} else {
					soundPack.viewSounds = CreateArray();
				}
				
				if (kv.JumpToKey("Select"))
				{
					soundPack.selectSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				} else {
					soundPack.selectSounds = CreateArray();
				}

				if (kv.JumpToKey("Jump"))
				{
					soundPack.jumpSounds = ParseFileItems(kv, true, "sound");
					kv.GoBack();
				} else {
					soundPack.jumpSounds = CreateArray();
				}

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
		} while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	return files;
}

//------------------------------------------------------
// Utils
//------------------------------------------------------

bool PlayRandomSound(ArrayList soundList, int client, int entity = SOUND_FROM_PLAYER, int channel = SNDCHAN_AUTO, bool toAll = false, int pitchMin = 100, int pitchMax = 100, float volume = SNDVOL_NORMAL)
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

void PrecacheSounds(ArrayList soundList)
{
	int len = soundList.Length;
	char path[PLATFORM_MAX_PATH];
	for (int i = 0; i < len; i++)
	{
		soundList.GetString(i, path, sizeof(path));
		PrecacheSound(path, true);
	}	
}

public Action BlockDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	return Plugin_Handled;
}

stock void LoadDHookDetour(const Handle pGameConfig, DynamicDetour& pHandle, const char[] szFuncName, DHookCallback pCallbackPre = INVALID_FUNCTION, DHookCallback pCallbackPost = INVALID_FUNCTION)
{
	pHandle = DynamicDetour.FromConf(pGameConfig, szFuncName);
	if (pHandle == null)
		SetFailState("Couldn't create hook %s", szFuncName);
	if (pCallbackPre != INVALID_FUNCTION && !pHandle.Enable(Hook_Pre, pCallbackPre))
		SetFailState("Couldn't enable pre detour hook %s", szFuncName);
	if (pCallbackPost != INVALID_FUNCTION && !pHandle.Enable(Hook_Post, pCallbackPost))
		SetFailState("Couldn't enable post detour hook %s", szFuncName);
}

stock void LoadDHookVirtual(const Handle pGameConfig, DynamicHook& pHandle, const char[] szFuncName)
{
	pHandle = DynamicHook.FromConf(pGameConfig, szFuncName);
	if (pHandle == null)
		SetFailState("Couldn't create hook %s", szFuncName);
}