extends SceneTree

const Platform = preload("res://scripts/platform/platform_service.gd")
const NativeInput = preload("res://scripts/platform/steam_input_service.gd")
const Saves = preload("res://scripts/platform/save_service.gd")
var checks: int = 0
var failures: Array[String] = []

class MockSteam extends RefCounted:
	signal user_stats_stored(game_id: int, result: int)
	var cloud: Dictionary = {}
	var cloud_enabled: bool = true
	var write_ok: bool = true
	var manifest: String = ""
	var selected_set: int = 1
	var connected: Array = [123]
	var digital: Dictionary = {}
	var analog: Dictionary = {100: Vector2(0.6, 0.8), 101: Vector2(1, 0), 102: Vector2.ZERO}
	var actions_active: bool = true
	var names: Array[String] = ["Fire", "ComponentPrimary", "ComponentSecondary", "ComponentTertiary", "Evolve", "Map", "Pause", "MenuConfirm", "MenuBack", "MenuUp", "MenuDown", "MenuLeft", "MenuRight"]
	func inputInit(_explicit_runframe: bool) -> bool: return true
	func inputShutdown() -> bool: return true
	func runFrame() -> void: pass
	func getConnectedControllers() -> Array: return connected
	func getActionSetHandle(action: String) -> int: return 1 if action == "Gameplay" else 2
	func activateActionSet(_controller: int, action_set: int) -> void: selected_set = action_set
	func getAnalogActionHandle(action: String) -> int: return {"Move": 100, "Aim": 101, "MenuNavigate": 102}.get(action, 0)
	func getDigitalActionHandle(action: String) -> int: return names.find(action) + 1
	func getAnalogActionData(_controller: int, action: int) -> Dictionary:
		var vector: Vector2 = analog.get(action, Vector2.ZERO)
		return {"active": actions_active, "x": vector.x, "y": vector.y}
	func getDigitalActionData(_controller: int, action: int) -> Dictionary:
		return {"active": actions_active, "state": digital.get(names[action - 1], false)}
	func setInputActionManifestFilePath(path: String) -> bool: manifest = path; return true
	func showBindingPanel(_controller: int) -> bool: return true
	func isCloudEnabledForApp() -> bool: return cloud_enabled
	func isCloudEnabledForAccount() -> bool: return cloud_enabled
	func fileWrite(file: String, data: PackedByteArray, size: int = 0) -> bool:
		if not write_ok or size != data.size(): return false
		cloud[file] = data.duplicate()
		return true
	func fileExists(file: String) -> bool: return cloud.has(file)
	func getFileSize(file: String) -> int: return cloud.get(file, PackedByteArray()).size()
	func fileRead(file: String, _size: int) -> Dictionary: return {"ret": cloud.has(file), "buf": cloud.get(file, PackedByteArray())}
	func setAchievement(_id: String) -> bool: return true
	func storeStats() -> bool: return true

func _initialize() -> void:
	var previous_root: String = Saves.storage_root
	Saves.storage_root = "user://world_platform_tests_%d" % Time.get_ticks_usec()
	_test_input()
	_test_cloud()
	_test_legacy_cloud()
	_test_achievements()
	var directory: DirAccess = DirAccess.open(Saves.storage_root)
	if directory != null:
		for filename: String in directory.get_files():
			DirAccess.remove_absolute(Saves.storage_root.path_join(filename))
		DirAccess.remove_absolute(Saves.storage_root)
	Saves.storage_root = previous_root
	if failures.is_empty():
		print("PLATFORM TESTS PASS: %d assertions" % checks)
		quit(0)
	else:
		for failure: String in failures: push_error(failure)
		quit(1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _test_input() -> void:
	var api: MockSteam = MockSteam.new()
	var native: RefCounted = NativeInput.new()
	expect(native.initialize(api), "Steam Input initializes through reflected methods")
	expect(api.manifest.is_absolute_path() and FileAccess.file_exists(api.manifest), "Action manifest supplied as a real disk file")
	native.set_context(false)
	api.digital["Fire"] = true
	api.digital["ComponentPrimary"] = true
	api.digital["ComponentSecondary"] = true
	api.digital["ComponentTertiary"] = true
	native.poll(0.016)
	var command: ShipCommand = native.get_command(Vector2.UP)
	expect(command != null and command.movement.is_equal_approx(Vector2(0.6, -0.8)), "Steam analog coordinates map to Godot movement")
	expect(command.aim == Vector2.RIGHT and command.fire, "Native aim and fire feed ShipCommand")
	expect(command.ability_primary and command.ability_secondary and command.secondary_held, "Component presses and charged hold are distinguishable")
	expect(command.secondaries == [true,true,true], "Three secondary controls reach indexed preset slots")
	command = native.get_command(Vector2.UP)
	expect(not command.ability_primary and not command.ability_secondary and command.secondary_held, "Physics polling consumes each component press once")
	api.actions_active = false
	native.poll(0.016)
	expect(native.get_command() == null, "Unconfigured native actions preserve standard controller fallback")
	api.actions_active = true
	native.set_context(true)
	native.poll(0.016)
	expect(api.selected_set == 2 and native.get_command() == null, "Menus activate their own action set and stop gameplay commands")
	api.connected = []
	native.poll(0.016)
	expect(not native.active and native.controller == 0, "Controller disconnect clears held state")
	native.shutdown()
	expect(not native.ready, "Steam Input shuts down without dangling state")

func _test_cloud() -> void:
	var platform: Node = Platform.new()
	var api: MockSteam = MockSteam.new()
	platform.steam = api
	platform.online = true
	var local: Dictionary = {"profile": {"demo": false, "deaths": 1}, "run": {"energy": 100}}
	var remote: Dictionary = {"profile": {"demo": false, "deaths": 2}, "run": {"energy": 300}}
	expect(Saves.save_snapshot(local["profile"], local["run"]) == OK, "Local cloud-conflict fixture saves")
	platform.save_cloud(Saves.encode_snapshot(remote))
	expect(platform.last_cloud_error == OK, "Steam cloud write uses correct byte count")
	var inspection: Dictionary = platform.inspect_cloud()
	expect(inspection["state"] == "conflict" and Saves.load_snapshot() == local, "Cloud conflict is reviewable without overwriting local state")
	expect(platform.resolve_cloud("use_cloud", "campaign", inspection["remote_bytes"]) == OK, "Explicit remote choice imports the reviewed snapshot")
	expect(Saves.load_snapshot() == remote and platform.inspect_cloud()["state"] == "same", "Remote resolution and subsequent equality check")
	Saves.save_snapshot(local["profile"], local["run"])
	expect(platform.resolve_cloud("keep_local") == OK and platform.inspect_cloud()["state"] == "same", "Explicit local choice updates cloud")
	api.cloud[Platform.CLOUD_FILE] = "corrupt".to_utf8_buffer()
	expect(platform.inspect_cloud()["state"] == "invalid" and Saves.load_snapshot() == local, "Corrupt remote save never replaces local progress")
	api.cloud_enabled = false
	expect(platform.inspect_cloud()["state"] == "offline", "Disabled cloud respects account preference")
	api.cloud_enabled = true
	api.write_ok = false
	platform.save_cloud(Saves.encode_snapshot(remote))
	expect(platform.last_cloud_error != OK and Saves.load_snapshot() == local, "Cloud write failure retains local save")
	platform.free()

func _test_legacy_cloud() -> void:
	var platform: Node = Platform.new()
	var api: MockSteam = MockSteam.new()
	platform.steam = api
	platform.online = true
	var legacy: Dictionary = {"profile":{"schema_version":2,"demo":false,"world_seed":78,"current_sector":"4,0","deaths":7,"unlocked":["void"],"defeated_leaders":["void"]},"run":{"combat":{"version":1,"energy":700},"seen_lines":{"reboot_7":true,"old_gate":true}}}
	var bytes: PackedByteArray = Saves.encode_snapshot(legacy)
	api.cloud[Platform.CLOUD_FILE] = bytes
	var original_local: PackedByteArray = FileAccess.get_file_as_bytes(Saves.snapshot_path())
	var inspection: Dictionary = platform.inspect_cloud()
	expect(inspection.state == "conflict" and inspection.remote.profile.schema_version == 4 and inspection.remote.profile.deaths == 7,"Cloud review compares compatible legacy progress")
	expect(inspection.remote_bytes == bytes and FileAccess.get_file_as_bytes(Saves.snapshot_path()) == original_local,"Cloud preview preserves reviewed original bytes and does not mutate local")
	expect(platform.resolve_cloud("use_cloud","campaign",inspection.remote_bytes) == OK,"Legacy remote choice installs and archives reviewed bytes")
	expect(FileAccess.get_file_as_bytes(Saves.snapshot_path()) == bytes and FileAccess.get_file_as_bytes(Saves.snapshot_path()+".legacy-v2") == bytes,"Legacy remote source and archive retain exact transport envelope")
	var migrated: Dictionary = Saves.load_snapshot()
	expect(migrated.profile.get("levels_completed",[]) == [] and migrated.profile.deaths == 7 and migrated.run.seen_lines == {"reboot_7":true},"Cloud migration retains compatible narrative (deaths, whitelisted flags) but no obsolete v0.2 core-victory progress")
	expect(platform.inspect_cloud().state == "same","Resolved legacy cloud does not reopen the same conflict forever")
	var other: Dictionary = legacy.duplicate(true)
	other.profile.deaths = 8
	var other_bytes: PackedByteArray = Saves.encode_snapshot(other)
	expect(platform.resolve_cloud("use_cloud","campaign",other_bytes) == OK,"Another legacy cloud campaign can be chosen later")
	var second_archive: String = Saves.snapshot_path()+".legacy-v2-"+Saves._digest(other_bytes).substr(0,16)
	expect(FileAccess.get_file_as_bytes(second_archive) == other_bytes and FileAccess.get_file_as_bytes(Saves.snapshot_path()+".legacy-v2") == bytes,"Distinct legacy choices retain both original archives")
	platform.free()

func _test_achievements() -> void:
	var platform: Node = Platform.new()
	var api: MockSteam = MockSteam.new()
	platform.steam = api
	platform.online = true
	platform.app_id = 12345
	platform.unlock_achievement("TEST_MILESTONE")
	expect("TEST_MILESTONE" in platform.pending_achievements, "Achievement waits for asynchronous backend confirmation")
	platform._on_stats_stored(12345, 2)
	expect("TEST_MILESTONE" in platform.pending_achievements, "Failed stats submission remains queued")
	platform._flush_achievements()
	platform._on_stats_stored(12345, 1)
	expect(platform.pending_achievements.is_empty() and Saves.load_snapshot("steam_state")["run"]["pending"].is_empty(), "Successful stats callback clears persistent pending queue")
	platform.free()
