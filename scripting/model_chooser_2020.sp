#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <smlib>
#include <clientprefs>
#include <model_chooser>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "1.0"

public Plugin myinfo =
{
	name = "Playermodel chooser",
	author = "Alienmario",
	description = "The enhanced playermodel system",
	version = PLUGIN_VERSION
};

#define MAX_KEY 128
#define HURT_SOUND_HP 45

//------------------------------------------------------
// Data structures
//------------------------------------------------------

enum struct SoundPack
{
	ArrayList hurtSounds;
	ArrayList viewSounds;
	ArrayList selectSounds;
	
	void Close() {
		delete this.hurtSounds;
		delete this.viewSounds;
		delete this.selectSounds;
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
		for(int i = 0; i < snapshot.Length; i++)
		{
			int keySize = snapshot.KeyBufferSize(i);
			char[] key = new char[keySize];
			snapshot.GetKey(i, key, keySize);
			SoundPack soundPack; this.GetArray(key, soundPack, sizeof(SoundPack)); soundPack.Close();
		}
		delete snapshot;
		view_as<StringMap>(this).Clear();
	}
}

// Complete sounds map containing entries of SoundPack, indexed by names
SoundMap soundMap;

enum struct PlayerModel
{
	bool locked;
	char name[MAX_KEY];
	char path[PLATFORM_MAX_PATH];
	int adminBitFlags;
	int defaultPrio;
	ArrayList downloads;
	char sounds[MAX_KEY];
	
	void Close() {
		delete this.downloads;
	}
	
	void GetSoundPack(SoundPack soundPack) {
		soundMap.GetArray(this.sounds, soundPack, sizeof(SoundPack));
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
		for(int i = 0; i < this.Length; i++)
		{
			PlayerModel model; this.GetArray(i, model); model.Close();
		}
		view_as<ArrayList>(this).Clear();
	}
	
	public int FindByName(const char[] modelName, PlayerModel model) {
		for(int i = 0; i < this.Length; i++) {
			this.GetArray(i, model);
			if(StrEqual(model.name, modelName, false)) {
				return i;
			}
		}
		return -1;
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

// Index into selectableModels for active model in menu, -1 indicates menu closed
int selectedMenuIndex[MAXPLAYERS+1];

// Whether currently selected model in menu is locked
bool selectedMenuIndexLocked[MAXPLAYERS+1];

// Map containing names of unlocked models
StringMap unlockedModels[MAXPLAYERS+1];

// Used for stopping
char lastPlayedSound[MAXPLAYERS+1][PLATFORM_MAX_PATH];

// Flag for playing hurt sound once
bool playedHurtSound[MAXPLAYERS+1];

// Counter for # of checks to pass until client models can be initialized
int clientInitChecks[MAXPLAYERS+1];

Handle hudSynch;
Handle DHook_SetModel;
Cookie modelCookie;
GlobalForward onModelChangedFwd;
ConVar cvSelectionImmunity;

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
	RegPluginLibrary(MODELCHOOSER_LIBRARY);
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
	char modelName[MAX_KEY];
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
	char modelName[MAX_KEY];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	LockModel(GetNativeCell(1), modelName);
	return true;
}

public any Native_SelectModel(Handle plugin, int numParams)
{
	char modelName[MAX_KEY];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	return SelectModelByName(GetNativeCell(1), modelName);
}

//------------------------------------------------------
// Plugin entry points, init
//------------------------------------------------------

public void OnPluginStart()
{
	modelList = new ModelList();
	soundMap = new SoundMap();
	hudSynch = CreateHudSynchronizer();
	modelCookie = new Cookie("playermodel", "Stores player model prefernce", CookieAccess_Protected);
	onModelChangedFwd = new GlobalForward("ModelChooser_OnModelChanged", ET_Ignore, Param_Cell, Param_String);
	
	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_models", Command_Model);
	RegConsoleCmd("sm_model", Command_Model);
	RegAdminCmd("sm_unlockmodel", Command_UnlockModel, ADMFLAG_KICK, "Unlock a locked model by name for a player");
	RegAdminCmd("sm_lockmodel", Command_LockModel, ADMFLAG_KICK, "Re-lock a model by name for a player");
	cvSelectionImmunity = CreateConVar("modelchooser_immunity", "0", "Whether players have damage immunity / are unable to fire when selecting models", _, true, 0.0, true, 1.0);
	
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	CreateTimer(2.0, CheckHealthRaise, _, TIMER_REPEAT);
	
	char gamedataPath[64];
	GetGameFolderName(gamedataPath, sizeof(gamedataPath));
	Format(gamedataPath, sizeof(gamedataPath), "sdktools.games/game.%s", gamedataPath);
	Handle gamedata = LoadGameConfigFile(gamedataPath);

	if (!gamedata)
	{
		SetFailState("Failed to load gamedata '%s'", gamedataPath);
	}

	int offset = GameConfGetOffset(gamedata, "SetEntityModel");
	DHook_SetModel = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Hook_SetModel);
	DHookAddParam(DHook_SetModel, HookParamType_CharPtr);
}

public void OnConfigsExecuted()
{
	modelList.Clear();
	soundMap.Clear();
	
	LoadConfig();
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) OnClientPutInServer(i);
	}
}

public void OnClientConnected(int client)
{
	delete selectableModels[client];
	delete unlockedModels[client];
	unlockedModels[client] = new StringMap();
	selectedIndex[client] = 0;
	selectedMenuIndex[client] = -1;
	playedHurtSound[client] = false;
	clientInitChecks[client] = 2;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client)) {
		DHookEntity(DHook_SetModel, false, client);
	}
}

public void OnClientPostAdminCheck(int client)
{
	if(!--clientInitChecks[client]) {
		InitClientModels(client);
	}
}

public void OnClientCookiesCached(int client)
{
	if(!--clientInitChecks[client]) {
		InitClientModels(client);
	}
}

public Action Command_Model(int client, int args)
{
	if(!client) {
		return Plugin_Handled;
	}
	if(selectableModels[client] == null || !selectableModels[client].Length) {
		PrintToChat(client, "Sorry! No models are available.");
		return Plugin_Handled;
	}
	if(Client_IsInThirdPersonMode(client)) {
		PrintToChat(client, "Sorry! You need to be in first person to use models.");
		return Plugin_Handled;
	}
	EnterModelChooser(client);
	return Plugin_Handled;
}

public Action Command_UnlockModel(int client, int args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "Usage: sm_unlockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MAX_KEY];
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
	if(modelList.FindByName(arg2, model) == -1) {
		ReplyToCommand(client, "Model named %s doesn't exist!", arg2);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < targetCount; i++)
	{
		UnlockModel(targets[i], arg2);
	}
	
	if(targetCount == 1) {
		ReplyToCommand(client, "Unlocked model %s for %N.", arg2, targets[0]);
	} else {
		ReplyToCommand(client, "Unlocked model %s for %d players.", arg2, targetCount);
	}
	
	return Plugin_Handled;
}

public Action Command_LockModel(int client, int args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "Usage: sm_lockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MAX_KEY];
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
	if(modelList.FindByName(arg2, model) == -1) {
		ReplyToCommand(client, "Model named %s doesn't exist!", arg2);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < targetCount; i++)
	{
		LockModel(targets[i], arg2);
	}
	
	if(targetCount == 1) {
		ReplyToCommand(client, "Locked model %s for %N.", arg2, targets[0]);
	} else {
		ReplyToCommand(client, "Locked model %s for %d players.", arg2, targetCount);
	}
	
	return Plugin_Handled;
}

//------------------------------------------------------
// Core functions
//------------------------------------------------------

public MRESReturn Hook_SetModel(int client, Handle hParams) {
	PlayerModel model;
	if(GetSelectedModel(client, model, (!selectedMenuIndexLocked[client] && selectedMenuIndex[client] != -1))) {
		DHookSetParamString(hParams, 1, model.path);
		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

void RefreshModel(int client) {
	if(IsClientInGame(client)) {
		SetEntityModel(client, "");
	}
}

void InitClientModels(int client) {
	if(selectableModels[client] == null)
	{
		selectableModels[client] = BuildSelectableModels(client);
		
		char modelName[MAX_KEY];
		modelCookie.Get(client, modelName, sizeof(modelName));
		if(!SelectModelByName(client, modelName)) {
			SelectModelByDefaultPrio(client);
		}
	}
}

ArrayList BuildSelectableModels(int client)
{
	ArrayList list = new ArrayList();
	for(int i = 0; i < modelList.Length; i++) {
		PlayerModel model; modelList.GetArray(i, model);
		if(model.adminBitFlags != -1) {
			int clientFlags = GetUserFlagBits(client);
			if(!(clientFlags & ADMFLAG_ROOT || clientFlags & model.adminBitFlags)) {
				continue;
			}
		}
		list.Push(i);
	}
	return list;
}

bool GetSelectedModel(int client, PlayerModel selectedModel, bool inMenu = false) {
	if(selectableModels[client] != null && selectableModels[client].Length) {
		int index = selectableModels[client].Get(inMenu? selectedMenuIndex[client] : selectedIndex[client]);
		modelList.GetArray(index, selectedModel);
		return true;
	}
	return false;
}

bool SelectModelByName(int client, const char[] modelName)
{
	PlayerModel model;
	int index = modelList.FindByName(modelName, model);
	if(index != -1) {
		int clIndex = selectableModels[client].FindValue(index);
		if(clIndex != -1 && !IsModelLocked(model, client)) {
			selectedIndex[client] = clIndex;
			RefreshModel(client);
			return true;
		}
	}
	return false;
}

void SelectModelByDefaultPrio(int client)
{
	if(!selectableModels[client].Length) {
		return;
	}
	
	// find models with the highest prio
	// select random if there are multiple
	int maxPrio = -1;
	ArrayList maxPrioList = new ArrayList();
	
	for(int i = 0; i < selectableModels[client].Length; i++) {
		PlayerModel model; modelList.GetArray(selectableModels[client].Get(i), model);
		if(IsModelLocked(model, client)) {
			continue;
		}
		if(model.defaultPrio > maxPrio) {
			maxPrio = model.defaultPrio;
			maxPrioList.Clear();
			maxPrioList.Push(i);
		} else if (model.defaultPrio == maxPrio) {
			maxPrioList.Push(i);
		}
	}
	
	if(maxPrioList.Length) {
		selectedIndex[client] = maxPrioList.Get(GetRandomInt(0, maxPrioList.Length - 1));
		PlayerModel model; modelList.GetArray(selectableModels[client].Get(selectedIndex[client]), model);
		RefreshModel(client);
	}
	delete maxPrioList;
}

bool IsModelLocked(PlayerModel model, int client)
{
	return (model.locked && !unlockedModels[client].GetValue(model.name, client));
}

void UnlockModel(int client, char modelName[MAX_KEY]) {
	unlockedModels[client].SetValue(modelName, true);
}

void LockModel(int client, char modelName[MAX_KEY]) {
	unlockedModels[client].Remove(modelName);
}

//------------------------------------------------------
// Third-Person Model chooser menu
//------------------------------------------------------

void EnterModelChooser(int client)
{
	selectedMenuIndex[client] = selectedIndex[client];
	
	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if(ragdoll != -1)
	{
		AcceptEntityInput(ragdoll, "Kill");
	}
	Client_SetObserverTarget(client, 0);
	Client_SetObserverMode(client, OBS_MODE_DEATHCAM, false);
	Client_SetDrawViewModel(client, false);
	SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);

	if(cvSelectionImmunity.BoolValue) {
		SDKHook(client, SDKHook_OnTakeDamage, BlockDamage);
		SetEntPropFloat(client, Prop_Data, "m_flNextAttack", float(SIZE_OF_INT));
	}
	
	OnMenuModelSelected(client);
}

void ExitModelChooser(int client, bool silent = false)
{
	Client_SetObserverTarget(client, -1);
	Client_SetObserverMode(client, OBS_MODE_NONE, false);
	Client_SetDrawViewModel(client, true);
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
	ClearSyncHud(client, hudSynch);
	SDKUnhook(client, SDKHook_OnTakeDamage, BlockDamage);
	SetEntPropFloat(client, Prop_Data, "m_flNextAttack", GetGameTime());
	
	PlayerModel model;
	GetSelectedModel(client, model, true);
	
	if(!selectedMenuIndexLocked[client]) {
		if(!silent) {
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
			PlayRandomSound(client, soundPack.selectSounds);
		}
		selectedIndex[client] = selectedMenuIndex[client];
		modelCookie.Set(client, model.name);
		PrintToChat(client, "\x07d9843fSelected model: \x07f5bf42%s", model.name);
		
		Call_StartForward(onModelChangedFwd);
		Call_PushCell(client);
		Call_PushString(model.name);
		Call_Finish();
	}
	selectedMenuIndex[client] = -1;
}

void OnMenuModelSelected(int client) {
	PlayerModel model; SoundPack soundPack;
	GetSelectedModel(client, model, true);
	model.GetSoundPack(soundPack);
	
	
	if(IsModelLocked(model, client)) {
		SetHudTextParams(-1.0, 0.8, 60.0, 255, 255, 255, 255, 0, 0.1, 0.1, 1.0);
		ShowSyncHudText(client, hudSynch, "<< |LOCKED| >>\n%d of %d", selectedMenuIndex[client]+1, selectableModels[client].Length);
		selectedMenuIndexLocked[client] = true;
	} else {
		SetHudTextParams(-1.0, 0.8, 60.0, 255, 255, -255, 255, 0, 0.0, 0.1, 1.0);
		ShowSyncHudText(client, hudSynch, "<< %s >>\n%d of %d", model.name, selectedMenuIndex[client]+1, selectableModels[client].Length);
		selectedMenuIndexLocked[client] = false;
		RefreshModel(client);
		PlayRandomSound(client, soundPack.viewSounds, SNDCHAN_BODY);
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
					OnMenuModelSelected(client);
				}
				if (buttons & IN_MOVERIGHT && !(lastButtons[client] & IN_MOVERIGHT)) {
					if (++selectedMenuIndex[client] >= selectableModels[client].Length) {
						selectedMenuIndex[client] = 0;
					}
					OnMenuModelSelected(client);
				}
			}
		}
		lastButtons[client] = buttons;
	}
}

//------------------------------------------------------
// Utils
//------------------------------------------------------

void PlayRandomSound(int client, ArrayList soundList, int channel = SNDCHAN_AUTO, bool toAll = false) {
	if(soundList && soundList.Length) {
		soundList.GetString(GetRandomInt(0, soundList.Length - 1), lastPlayedSound[client], sizeof(lastPlayedSound[]));
		if(toAll) {
			EmitSoundToAll(lastPlayedSound[client], client, channel);
		} else {
			EmitSoundToClient(client, lastPlayedSound[client], _, channel);
		}
	}
}

public Action BlockDamage (int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	return Plugin_Handled;
}

//------------------------------------------------------
// Hurt sounds
//------------------------------------------------------

public void Event_PlayerHurt(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(playedHurtSound[client])
		return;
	if(GetClientTeam(client) == 1)
		return;
	
	int health = GetEventInt(event, "health");
	if(0 < health < HURT_SOUND_HP) {
		PlayerModel model;
		if(GetSelectedModel(client, model)) {
			SoundPack soundPack;
			model.GetSoundPack(soundPack);
			PlayRandomSound(client, soundPack.hurtSounds, _, true);
		}
		
		playedHurtSound[client] = true;
	}
}

public Action CheckHealthRaise(Handle timer) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			if(playedHurtSound[i] && GetClientHealth(i) >= HURT_SOUND_HP) {
				playedHurtSound[i] = false;
			}
		}
	}
	return Plugin_Continue;
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
	char section[MAX_KEY];
	if (!(kv.ImportFromFile(szConfigPath) && kv.GetSectionName(section, sizeof(section)) && strcmp(section, "ModelSystem", false) == 0))
		SetFailState("Couldn't import %s into KeyValues", szConfigPath);
		
	if(kv.GotoFirstSubKey()) {
		do {
			if(kv.GetSectionName(section, sizeof(section)))
			{
				if(StrEqual(section, "Models", false))
				{
					ParseModels(kv);
				}
				else if(StrEqual(section, "Sounds", false))
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
	
	if(kv.GotoFirstSubKey()) {
		do {
			PlayerModel model;
			if(kv.GetSectionName(model.name, sizeof(model.name)))
			{
				if(!kv.GetNum("enabled", 1)) {
					continue;
				}
				kv.GetString("path", model.path, sizeof(model.path));
				if(model.path[0] == '\0') {
					continue;
				}
				
				kv.GetString("sounds", model.sounds, sizeof(model.sounds));
				String_ToUpper(model.name, model.name, sizeof(model.name));
				String_ToUpper(model.sounds, model.sounds, sizeof(model.sounds));
				
				model.locked = !!kv.GetNum("locked", 0);
				model.defaultPrio = kv.GetNum("defaultprio");
				
				char adminFlags[32];
				kv.GetString("adminflags", adminFlags, sizeof(adminFlags), "-1");
				model.adminBitFlags = StrEqual(adminFlags, "-1")? -1 : ReadFlagString(adminFlags);
				
				if(kv.JumpToKey("downloads"))
				{
					model.downloads = ParseFileItems(kv, true);
					kv.GoBack();
				}
				
				if(duplicityChecker.SetString(model.name, "", false))
				{
					modelList.PushArray(model);
					PrecacheModel(model.path, true);
				} else {
					SetFailState("Duplicate model name: %s", model.name);
				}
			}
		} while (kv.GotoNextKey());
		kv.GoBack();
		
		delete duplicityChecker;
	}
}

void ParseSounds(KeyValues kv)
{
	if(kv.GotoFirstSubKey()) {
		do {
			SoundPack soundPack;
			char name[MAX_KEY];
			if(kv.GetSectionName(name, sizeof(name)))
			{
				if(kv.JumpToKey("Hurt")) {
					soundPack.hurtSounds = ParseFileItems(kv, false, true);
					kv.GoBack();
				} else {
					soundPack.hurtSounds = CreateArray();
				}
				
				if(kv.JumpToKey("View")) {
					soundPack.viewSounds = ParseFileItems(kv, false, true);
					kv.GoBack();
				} else {
					soundPack.viewSounds = CreateArray();
				}
				
				if(kv.JumpToKey("Select")) {
					soundPack.selectSounds = ParseFileItems(kv, false, true);
					kv.GoBack();
				} else {
					soundPack.selectSounds = CreateArray();
				}
				String_ToUpper(name, name, sizeof(name));
				soundMap.SetArray(name, soundPack, sizeof(SoundPack));
			}
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
}

ArrayList ParseFileItems(KeyValues kv, bool download = false, bool precacheSounds = false)
{
	ArrayList files = new ArrayList(PLATFORM_MAX_PATH);
	char path[PLATFORM_MAX_PATH];
	
	if(kv.GotoFirstSubKey(false)) {
		do {
			kv.GetString(NULL_STRING, path, sizeof(path));
			if(path[0] == '\0') {
				continue;
			}
			files.PushString(path);
			if(precacheSounds) {
				PrecacheSound(path, true);
			}
			if(download) {
				AddFileToDownloadsTable(path);
			}
		} while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	return files;
}