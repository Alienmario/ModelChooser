#pragma semicolon 1
#pragma newdecls required

methodmap Commands
{
	public static void Init()
	{
		RegConsoleCmd("sm_models", Command_Model);
		RegConsoleCmd("sm_model", Command_Model);
		RegConsoleCmd("sm_skins", Command_Model);
		RegConsoleCmd("sm_skin", Command_Model);
		RegAdminCmd("sm_unlockmodel", Command_UnlockModel, ADMFLAG_KICK, "Unlock a locked model by name for a player");
		RegAdminCmd("sm_lockmodel", Command_LockModel, ADMFLAG_KICK, "Lock a previously unlocked model by name for a player");
	}
}

static Action Command_Model(int client, int args)
{
	if (UI.PreEnterCheck(client))
	{
		UI.Enter(client);
	}
	return Plugin_Handled;
}

static Action Command_UnlockModel(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_unlockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MODELCHOOSER_MAX_NAME];
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
	
	if (modelList.FindByName(arg2) == -1)
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

static Action Command_LockModel(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_lockmodel <target> <model name>");
		return Plugin_Handled;
	}
	
	char arg1[65], arg2[MODELCHOOSER_MAX_NAME];
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
	
	if (modelList.FindByName(arg2) == -1)
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
