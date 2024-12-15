#if defined _model_chooser_included
	#endinput
#endif
#define _model_chooser_included

#define MODELCHOOSER_LIBRARY "ModelChooser"

public SharedPlugin __pl_model_chooser = 
{
    name = MODELCHOOSER_LIBRARY,
    file = "ultimate_modelchooser.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_model_chooser_SetNTVOptional()
{
    MarkNativeAsOptional("ModelChooser_GetCurrentModelName");
    MarkNativeAsOptional("ModelChooser_GetCurrentModelPath");
    MarkNativeAsOptional("ModelChooser_GetCurrentModelProperty");
    MarkNativeAsOptional("ModelChooser_UnlockModel");
    MarkNativeAsOptional("ModelChooser_LockModel");
    MarkNativeAsOptional("ModelChooser_SelectModel");
    MarkNativeAsOptional("ModelChooser_IsClientChoosing");
    MarkNativeAsOptional("ModelChooser_OpenChooser");
    MarkNativeAsOptional("ModelChooser_PlayRandomSound");
    MarkNativeAsOptional("ModelChooser_GetProperty");
    MarkNativeAsOptional("ModelChooser_GetModelList");
    MarkNativeAsOptional("ModelChooser_GetSoundMap");
}
#endif

/* Forwards */

forward void ModelChooser_OnConfigLoaded();

forward void ModelChooser_OnModelChanged(int client, const char[] modelName);

/* Natives */

native bool ModelChooser_GetCurrentModelName(int client, char[] modelName, int maxLength);

native bool ModelChooser_GetCurrentModelPath(int client, char[] modelPath, int maxLength);

native bool ModelChooser_GetCurrentModelProperty(int client, const char[] key, char[] value, int maxLength);

native bool ModelChooser_UnlockModel(int client, const char[] modelName, bool select = false);

native bool ModelChooser_LockModel(int client, const char[] modelName);

native bool ModelChooser_SelectModel(int client, const char[] modelName);

native bool ModelChooser_IsClientChoosing(int client);

native bool ModelChooser_OpenChooser(int client, bool printErrorMsg);

native bool ModelChooser_PlayRandomSound(int client, const char[] soundType, bool toAll = false, bool stopLast = true, int pitch = 100, float volume = 1.0);

native bool ModelChooser_GetProperty(const char[] modelName, const char[] key, char[] value, int maxLength);

#if defined MODELCHOOSER_RAWDOG_API

#include <sdktools>
#include <clientprefs>
#include <modelchooser/structs>

native ModelList ModelChooser_GetModelList();

native SoundMap ModelChooser_GetSoundMap();

#endif
