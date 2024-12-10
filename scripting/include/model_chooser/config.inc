#pragma semicolon 1
#pragma newdecls required

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
				if (model.path[0] == EOS)
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
				model.adminBitFlags = StrEqual(buffer, "-1") ? -1 : ReadFlagString(buffer);

				kv.GetString("team", model.team, sizeof(model.team), "0");

				if (kv.GetDataType("downloads") == KvData_None && kv.JumpToKey("downloads"))
				{
					ParseFileItems(kv, false);
					kv.GoBack();
				}
								
				modelList.PushArray(model);
			}
		}
		while (kv.GotoNextKey());
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
			if (path[0] == EOS)
				continue;
			
			files.PushString(path);
			if (folderType[0] != EOS)
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