#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <smlib>
#include <clientprefs>

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

// Complete model list containing entries of PlayerModel
ArrayList modelList;

// Complete sound map containing entries of SoundPack, indexed by names
StringMap soundMap;

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

enum struct PlayerModel
{
	bool enabled;
	char name[32];
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

Handle hudSynch;
Handle DHook_SetModel;
Cookie modelCookie;

// The filtered list of selectable models. Contains indexes into modelList
ArrayList selectableModels[MAXPLAYERS+1];

// Index into selectableModels for active model
int selectedIndex[MAXPLAYERS+1];

// Selection indicator
bool inModelMenu[MAXPLAYERS+1];

// Used for stopping
char lastPlayedSound[MAXPLAYERS+1][PLATFORM_MAX_PATH];

// Flag for playing hurt sound once
bool playedHurtSound[MAXPLAYERS+1];

public void OnPluginStart()
{
	modelList = new ArrayList(sizeof(PlayerModel));
	soundMap = new StringMap();
	hudSynch = CreateHudSynchronizer();
	modelCookie = new Cookie("playermodel", "Stores player model prefernce", CookieAccess_Protected);
	
	RegConsoleCmd("sm_models", Command_Model);
	RegConsoleCmd("sm_model", Command_Model);
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
	for(int i = 0; i < modelList.Length; i++)
	{
		PlayerModel model; modelList.GetArray(i, model); model.Close();
	}
	modelList.Clear();
	
	StringMapSnapshot snapshot = soundMap.Snapshot();
	for(int i = 0; i < snapshot.Length; i++)
	{
		int keySize = snapshot.KeyBufferSize(i);
		char[] key = new char[keySize];
		snapshot.GetKey(i, key, keySize);
		SoundPack soundPack; soundMap.GetArray(key, soundPack, sizeof(SoundPack)); soundPack.Close();
	}
	delete snapshot;
	soundMap.Clear();
	
	LoadConfig();
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) OnClientPutInServer(i);
	}
}

public void OnClientPutInServer(int client)
{
	delete selectableModels[client];
	selectedIndex[client] = 0;
	inModelMenu[client] = false;
	playedHurtSound[client] = false;
	DHookEntity(DHook_SetModel, false, client);
}

public void OnClientPostAdminCheck(int client)
{
	TryInitClientModels(client);
}

public void OnClientCookiesCached(int client)
{
	TryInitClientModels(client);
}

void TryInitClientModels(int client) {
	if(selectableModels[client] == null && IsClientAuthorized(client) && AreClientCookiesCached(client))
	{
		selectableModels[client] = BuildSelectableModels(client);
		
		char modelName[MAX_KEY];
		modelCookie.Get(client, modelName, sizeof(modelName));
		if(!SetModelByName(client, modelName)) {
			SetModelByDefaultPrio(client);
		}
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

public MRESReturn Hook_SetModel(int client, Handle hParams) {
	PlayerModel model;
	if(GetSelectedModel(client, model)) {
		DHookSetParamString(hParams, 1, model.path);
		return MRES_ChangedHandled;
	}
	return MRES_Ignored;
}

ArrayList BuildSelectableModels(int client)
{
	ArrayList list = new ArrayList();
	for(int i = 0; i < modelList.Length; i++) {
		PlayerModel model; modelList.GetArray(i, model);
		if(!model.enabled) {
			continue;
		}
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

bool GetSelectedModel(int client, PlayerModel selectedModel) {
	if(selectableModels[client] != null && selectableModels[client].Length) {
		int index = selectableModels[client].Get(selectedIndex[client]);
		modelList.GetArray(index, selectedModel);
		return true;
	}
	return false;
}

bool SetModelByName(int client, const char[] modelName)
{
	for(int i = 0; i < selectableModels[client].Length; i++) {
		PlayerModel model;
		modelList.GetArray(selectableModels[client].Get(i), model);
		if(StrEqual(model.name, modelName, false)) {
			if(IsClientInGame(client)) {
				SetEntityModel(client, model.path);
			}
			selectedIndex[client] = i;
			return true;
		}
	}
	return false;
}

void SetModelByDefaultPrio(int client)
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
		if(model.defaultPrio > maxPrio) {
			maxPrio = model.defaultPrio;
			maxPrioList.Clear();
			maxPrioList.Push(i);
		} else if (model.defaultPrio == maxPrio) {
			maxPrioList.Push(i);
		}
	}
	
	selectedIndex[client] = maxPrioList.Get(GetRandomInt(0, maxPrioList.Length - 1));
	PlayerModel model; modelList.GetArray(selectableModels[client].Get(selectedIndex[client]), model);
	if(IsClientInGame(client)) {
		SetEntityModel(client, model.path);
	}
	delete maxPrioList;
}

void EnterModelChooser(int client)
{
	inModelMenu[client] = true;
	
	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if(ragdoll != -1)
	{
		AcceptEntityInput(ragdoll, "Kill");
	}
	Client_SetObserverTarget(client, 0);
	Client_SetObserverMode(client, OBS_MODE_DEATHCAM, false);
	Client_SetDrawViewModel(client, false);
	SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);
	
	OnModelSelected(client);
}

void ExitModelChooser(int client, bool silent = false)
{
	Client_SetObserverTarget(client, -1);
	Client_SetObserverMode(client, OBS_MODE_NONE, false);
	Client_SetDrawViewModel(client, true);
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ATCONTROLS);
	ClearSyncHud(client, hudSynch);
	
	PlayerModel model;
	GetSelectedModel(client, model);
		
	if(!silent) {
		SoundPack soundPack;
		model.GetSoundPack(soundPack);
		StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
		PlayRandomSound(client, soundPack.selectSounds);
	}
	
	modelCookie.Set(client, model.name);
	
	inModelMenu[client] = false;
}

void OnModelSelected(int client) {
	PlayerModel model; SoundPack soundPack;
	GetSelectedModel(client, model);
	model.GetSoundPack(soundPack);
	
	SetHudTextParams(-1.0, 0.8, 60.0, 255, 255, 255, 255, 0, 0.0, 0.1, 1.0);
	ShowSyncHudText(client, hudSynch, "<< %s >>\n%d of %d", model.name, selectedIndex[client]+1, selectableModels[client].Length);
	
	SetEntityModel(client, model.path);
	PlayRandomSound(client, soundPack.viewSounds, SNDCHAN_BODY);
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if(0 < client <= MAXPLAYERS) {
		static int lastButtons[MAXPLAYERS+1];
		if(inModelMenu[client]) {
			if(!IsPlayerAlive(client)) {
				ExitModelChooser(client, true);
			}
			if(buttons & IN_USE || buttons & IN_JUMP) {
				ExitModelChooser(client);
			}
			if(buttons & IN_MOVELEFT && !(lastButtons[client] & IN_MOVELEFT)) {
				if(--selectedIndex[client] < 0) {
					selectedIndex[client] = selectableModels[client].Length - 1;
				}
				OnModelSelected(client);
			}
			if(buttons & IN_MOVERIGHT && !(lastButtons[client] & IN_MOVERIGHT)) {
				if(++selectedIndex[client] >= selectableModels[client].Length) {
					selectedIndex[client] = 0;
				}
				OnModelSelected(client);
			}
		}
		lastButtons[client] = buttons;
	}
}

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
				String_ToUpper(model.name, model.name, sizeof(model.name));
				
				kv.GetString("path", model.path, sizeof(model.path));
				if(model.path[0] == '\0') {
					continue;
				}
				
				kv.GetString("sounds", model.sounds, sizeof(model.sounds));
				String_ToUpper(model.sounds, model.sounds, sizeof(model.sounds));
				
				model.enabled = !!kv.GetNum("enabled", 1);
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
					if(model.enabled) {
						PrecacheModel(model.path);
					}
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
				PrecacheSound(path);
			}
			if(download) {
				AddFileToDownloadsTable(path);
			}
		} while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	return files;
}