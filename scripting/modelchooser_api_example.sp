#include <sourcemod>

#define MODELCHOOSER_RAWDOG_API 	/* Enable deep access? */
#undef REQUIRE_PLUGIN 				/* Is ModelChooser plugin dependency required or optional? */
#include <modelchooser>

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, MODELCHOOSER_LIBRARY))
	{
		PrintToServer("ModelChooser plugin is running");
		// useModelChooser = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, MODELCHOOSER_LIBRARY))
	{
		PrintToServer("ModelChooser plugin has unloaded");
		// useModelChooser = false;
	}
}

public void ModelChooser_OnModelChanged(int client, const char[] modelName)
{
	PrintToServer("%N changed model to %s", client, modelName);

	char value[512];
	if (ModelChooser_GetCurrentModelProperty(client, "test", value, sizeof(value)))
	{
		PrintToServer("Value of test property: %s", value);
	}
	else
	{
		PrintToServer("There is no custom 'test' property on this model");
	}
}

public void ModelChooser_OnConfigLoaded()
{
	PrintToServer("Model config loaded");

	ModelList modelList = ModelChooser_GetModelList();
	PlayerModel model;

	int size = modelList.Length;
	for (int i = 0; i < size; i++)
	{
		modelList.GetArray(i, model);
		PrintToServer("Model at index %d is named %s", i, model.name);
	}
}