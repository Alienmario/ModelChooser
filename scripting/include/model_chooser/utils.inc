#pragma semicolon 1
#pragma newdecls required

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

Action Hook_BlockDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
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

stock int EntIndexToEntRefEx(int ent)
{
	int index = EntRefToEntIndex(ent);
	return index == -1? -1 : EntIndexToEntRef(index);
}

// Copy pasta of "SetBodygroup" from the SDK
stock void CalcBodygroup(StudioHdr pStudioHdr, int& body, int iGroup, int iValue)
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

stock void ApplyEntityBodyGroupsFromString(int entity, const char[] str)
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
