extends SceneTree

func _initialize() -> void:
	print("Steam singleton: ", Engine.has_singleton("Steam"), "; Steam class: ", ClassDB.class_exists("Steam"))
	var wanted: Array[String] = ["steamInitEx", "fileWrite", "fileRead", "inputInit", "inputShutdown", "runFrame", "getConnectedControllers", "getActionSetHandle", "activateActionSet", "getDigitalActionHandle", "getAnalogActionHandle", "getDigitalActionData", "getAnalogActionData", "setInputActionManifestFilePath", "showBindingPanel", "getInputTypeForHandle", "run_callbacks", "getFileTimestamp", "isCloudEnabledForAccount", "isCloudEnabledForApp"]
	if ClassDB.class_exists("Steam"):
		for method: Dictionary in ClassDB.class_get_method_list("Steam", true):
			if str(method["name"]) in wanted:
				print(JSON.stringify(method))
		for steam_signal: Dictionary in ClassDB.class_get_signal_list("Steam", true):
			if "stats" in str(steam_signal["name"]):
				print("SIGNAL ", JSON.stringify(steam_signal))
	quit()
