#pragma semicolon 1
#pragma newdecls required

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ModelChooser_GetCurrentModelName", Native_GetCurrentModelName);
	CreateNative("ModelChooser_GetCurrentModelPath", Native_GetCurrentModelPath);
	CreateNative("ModelChooser_GetCurrentModelProperty", Native_GetCurrentModelProperty);
	CreateNative("ModelChooser_UnlockModel", Native_UnlockModel);
	CreateNative("ModelChooser_LockModel", Native_LockModel);
	CreateNative("ModelChooser_SelectModel", Native_SelectModel);
	CreateNative("ModelChooser_IsClientChoosing", Native_IsClientChoosing);
	CreateNative("ModelChooser_OpenChooser", Native_OpenChooser);
	CreateNative("ModelChooser_PlayRandomSound", Native_PlayRandomSound);
	CreateNative("ModelChooser_GetProperty", Native_GetProperty);
	CreateNative("ModelChooser_GetModelList", Native_GetModelList);
	CreateNative("ModelChooser_GetSoundMap", Native_GetSoundMap);
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

public any Native_GetCurrentModelProperty(Handle plugin, int numParams)
{
	PlayerModel model;

	if (GetSelectedModel(GetNativeCell(1), model))
	{
		int keySize; GetNativeStringLength(2, keySize); keySize++;
		int valSize = GetNativeCell(4);
		char[] key = new char[keySize];
		char[] val = new char[valSize];
		GetNativeString(2, key, keySize);
		String_ToUpper(key, key, keySize);
		if (model.customProperties.GetString(key, val, valSize))
		{
			SetNativeString(3, val, valSize);
			return true;
		}
	}
	return false;
}

public any Native_UnlockModel(Handle plugin, int numParams)
{
	char modelName[MODELCHOOSER_MAX_NAME];
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
	char modelName[MODELCHOOSER_MAX_NAME];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	LockModel(GetNativeCell(1), modelName);
	return true;
}

public any Native_SelectModel(Handle plugin, int numParams)
{
	char modelName[MODELCHOOSER_MAX_NAME];
	GetNativeString(2, modelName, sizeof(modelName));
	String_ToUpper(modelName, modelName, sizeof(modelName));
	
	return SelectModelByName(GetNativeCell(1), modelName);
}

public any Native_IsClientChoosing(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return IsInMenu(client);
}

public any Native_OpenChooser(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool printError = GetNativeCell(2);
	if (PreEnterCheck(client, printError))
	{
		EnterModelChooser(client);
		return true;
	}
	return false;
}

public any Native_PlayRandomSound(Handle plugin, int numParams)
{
	PlayerModel model;
	int client = GetNativeCell(1);

	if (GetSelectedModel(client, model))
	{
		char soundType[MODELCHOOSER_MAX_NAME];
		GetNativeString(2, soundType, sizeof(soundType));

		SoundPack soundPack = GetSoundPack(model, false);
		if (!soundPack)
			return false;
		
		bool toAll = GetNativeCell(3);
		bool stopLast = GetNativeCell(4);
		int pitch = GetNativeCell(5);
		float volume = GetNativeCell(6);
		
		if (stopLast)
		{
			StopSound(client, SNDCHAN_BODY, lastPlayedSound[client]);
			StopSound(client, SNDCHAN_STATIC, lastPlayedSound[client]);
		}

		return PlayRandomSound(soundPack.GetSoundList(soundType), client,
			.channel = SNDCHAN_STATIC, .toAll = toAll, .pitchMin = pitch, .pitchMax = pitch, .volume = volume
		);
	}
	return false;
}

public any Native_GetProperty(Handle plugin, int numParams)
{
	char modelName[MODELCHOOSER_MAX_NAME];
	GetNativeString(1, modelName, sizeof(modelName));
	if (modelList)
	{
		int i = modelList.FindByName(modelName);
		if (i != -1)
		{
			StringMap customProperties = modelList.Get(i, PlayerModel::customProperties);

			int keySize; GetNativeStringLength(2, keySize); keySize++;
			int valSize = GetNativeCell(4);
			char[] key = new char[keySize];
			char[] val = new char[valSize];
			GetNativeString(2, key, keySize);
			String_ToUpper(key, key, keySize);
			if (customProperties.GetString(key, val, valSize))
			{
				SetNativeString(3, val, valSize);
				return true;
			}
		}
	}
	return false;
}

public any Native_GetModelList(Handle plugin, int numParams)
{
	return modelList;
}

public any Native_GetSoundMap(Handle plugin, int numParams)
{
	return soundMap;
}
