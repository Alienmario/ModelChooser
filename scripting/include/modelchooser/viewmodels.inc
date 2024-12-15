#pragma semicolon 1
#pragma newdecls required

public MRESReturn Hook_SetViewModelModel(int vm, DHookParam hParams)
{
	RequestFrame(UpdateViewModel, EntIndexToEntRef(vm));
	return MRES_Ignored;
}

void UpdateViewModels(int client)
{
	int count = GetEntPropArraySize(client, Prop_Send, "m_hViewModel");
	for (int i = 0; i < count; i++)
	{
		int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel", i);
		if (vm != -1)
		{
			UpdateViewModel(vm);
		}
	}
}

void UpdateViewModel(int vm)
{
	vm = EntRefToEntIndex(vm);
	if (vm != -1)
	{
		int client = GetEntPropEnt(vm, Prop_Data, "m_hOwner");
		if (0 < client <= MaxClients)
		{
			PlayerModel model;
			if (GetSelectedModelAuto(client, model))
			{
				ApplyEntityBodyGroupsFromString(vm, model.vmBodyGroups);
			}
		}
	}
}
