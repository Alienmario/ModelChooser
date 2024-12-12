#pragma semicolon 1
#pragma newdecls required

enum struct Interval
{
	float min;
	float max;

	float Rand()
	{
		return GetRandomFloat(this.min, this.max);
	}
}

enum struct SoundParams
{
	Interval cooldown;
}

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
		PrecacheSoundsInList(this.hurtSounds);
		PrecacheSoundsInList(this.deathSounds);
		PrecacheSoundsInList(this.viewSounds);
		PrecacheSoundsInList(this.selectSounds);
		PrecacheSoundsInList(this.jumpSounds);
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
		if (size)
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
		delete this.seqList;
	}
}

enum struct PlayerModel
{
	char name[MAX_MODELNAME];
	char path[PLATFORM_MAX_PATH];
	char team[MAX_TEAM_NAME_LENGTH];
	char sounds[MAX_SOUNDSNAME];
	char vmBodyGroups[256];
	SoundParams jumpSndParams;
	Interval hurtSndHP;
	int adminBitFlags;
	int defaultPrio;
	int hudColor[4];
	bool locked;

	ArrayList skins;
	ArrayList bodyGroups;

	PlayerAnimation anim_idle;
	PlayerAnimation anim_walk;
	PlayerAnimation anim_run;
	PlayerAnimation anim_jump;
	PlayerAnimation anim_idle_crouch;
	PlayerAnimation anim_walk_crouch;
	PlayerAnimation anim_noclip;
	
	void Close()
	{
		this.skins.Close();
		this.bodyGroups.Close();
		this.anim_idle.Close();
		this.anim_walk.Close();
		this.anim_run.Close();
		this.anim_jump.Close();
		this.anim_idle_crouch.Close();
		this.anim_walk_crouch.Close();
		this.anim_noclip.Close();
	}

	void Precache()
	{
		PrecacheModel(this.path, true);
	}

	int GetTeamNum()
	{
		int team = String_IsNumeric(this.team) ? StringToInt(this.team) : FindTeamByName(this.team);
		if (team < 0 || team >= MAX_TEAMS)
		{
			if (GetTeamCount() > 2)
			{
				LogError("Invalid team \"%s\" specified for model \"%s\"", this.team, this.name);
			}
			team = 0;
		}
		return team;
	}

	int GetSkin(int index)
	{
		return this.skins.Get(index);
	}

	int GetBody(int index)
	{
		return this.bodyGroups.Get(index);
	}

	int IndexOfSkin(int skin, int fallback = 0)
	{
		int i = this.skins.FindValue(skin);
		return i == -1 ? fallback : i;
	}

	int IndexOfBody(int body, int fallback = 0)
	{
		int i = this.bodyGroups.FindValue(body);
		return i == -1 ? fallback : i;
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

enum struct SelectionData
{
	// Index into selectableModels, -1 = invalid
	int index;

	// Index into PlayerModel.skins
	int skin;

	// Index into PlayerModel.bodyGroups
	int body;

	// Cached by menu
	int skinCount;
	int bodyCount;
	bool locked;

	void Reset()
	{
		this.index = -1;
		this.skin = this.skinCount = this.body = this.bodyCount = 0;
		this.locked = false;
	}
	
	bool IsValid()
	{
		return this.index != -1 && !this.locked;
	}
}

enum struct PersistentPreferences
{
	int team;
	Cookie model;
	Cookie skin;
	Cookie body;

	void Init(int team)
	{
		if (this.model)
			return;

		this.team = team;
		
		char name[32];
		char suffix[4];
		if (team > TEAM_SPECTATOR)
		{
			FormatEx(suffix, sizeof(suffix), "#%d", team);
		}

		FormatEx(name, sizeof(name), "playermodel%s", suffix);
		this.model = new Cookie(name, "Stores player model preference", CookieAccess_Protected);

		FormatEx(name, sizeof(name), "playermodel_skin%s", suffix);
		this.skin = new Cookie(name, "Stores player model skin type preference", CookieAccess_Protected);

		FormatEx(name, sizeof(name), "playermodel_body%s", suffix);
		this.body = new Cookie(name, "Stores player model body type preference", CookieAccess_Protected);
	}
}
