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
    MarkNativeAsOptional("ModelChooser_UnlockModel");
    MarkNativeAsOptional("ModelChooser_LockModel");
    MarkNativeAsOptional("ModelChooser_SelectModel");
    MarkNativeAsOptional("ModelChooser_IsClientChoosing");
}
#endif

forward void ModelChooser_OnModelChanged(int client, const char[] modelName);

native bool ModelChooser_GetCurrentModelName(int client, char[] modelName, int maxLength);

native bool ModelChooser_GetCurrentModelPath(int client, char[] modelPath, int maxLength);

native bool ModelChooser_UnlockModel(int client, char[] modelName, bool select = false);

native bool ModelChooser_LockModel(int client, char[] modelName);

native bool ModelChooser_SelectModel(int client, char[] modelName);

native bool ModelChooser_IsClientChoosing(int client);
