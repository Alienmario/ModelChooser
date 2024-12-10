#pragma semicolon 1
#pragma newdecls required

// Complete model list containing entries of PlayerModel
ModelList modelList;

// Complete sounds map containing entries of SoundPack, indexed by names
SoundMap soundMap;

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

// Team number cached from changeteam event hook
int currentTeam[MAXPLAYERS + 1];

// Downloads fileset
SmartDM_FileSet downloads;

// Hooks
DynamicHook hkSetModel;
DynamicHook hkDeathSound;
DynamicHook hkSetAnimation;

// Calls
Handle callResetSequence;

// Persistence
PersistentPreferences persistentPreferences[MAX_TEAMS];

// Forwards
GlobalForward fwdOnModelChanged;

// Cvars
ConVar cvSelectionImmunity;
ConVar cvAutoReload;
ConVar cvOverlay;
ConVar cvLockModel;
ConVar cvLockScale;
ConVar cvMenuSnd;
ConVar cvTeamBased;
ConVar mp_forcecamera;
