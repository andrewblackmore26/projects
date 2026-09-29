class_name PlatformService
extends Node

signal status_changed(message: String)

const CLOUD_FILE: String = "lightship_campaign_v2.json"
const MAX_CLOUD_BYTES: int = 16 * 1024 * 1024
const Saves = preload("res://scripts/platform/save_service.gd")
const NativeInput = preload("res://scripts/platform/steam_input_service.gd")
var online: bool = false
var status: String = "Offline mode"
var steam: Object
var pending_achievements: Array[String] = []
var app_id: int = 0
var _retry_elapsed: float = 0.0
var last_cloud_error: Error = OK
var steam_input: RefCounted
var _submitted_achievements: Array[String] = []

func initialize() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	var ledger: Dictionary = Saves.load_snapshot("steam_state")
	var pending: Variant = ledger.get("run", {}).get("pending", [])
	if pending is Array:
		for id: Variant in pending:
			if id is String and not id.is_empty() and id not in pending_achievements:
				pending_achievements.append(id)
	online = false
	steam = null
	app_id = int(ProjectSettings.get_setting("lightship/steam/app_id", 0))
	if app_id <= 0:
		_set_status("Offline mode — Steam App ID is not configured")
		return
	if not Engine.has_singleton("Steam"):
		_set_status("Offline mode — GodotSteam extension is not installed")
		return
	steam = Engine.get_singleton("Steam")
	if not _has("steamInitEx"):
		_set_status("Offline mode — compatible GodotSteam API unavailable")
		return
	var response: Variant = steam.call("steamInitEx", app_id, false)
	if response is Dictionary:
		online = int(response.get("status", -1)) == 0
	else:
		online = false
	if not online:
		_set_status("Offline mode — Steam initialization unavailable")
		return
	if steam.has_signal("user_stats_stored") and not steam.is_connected("user_stats_stored", _on_stats_stored):
		steam.connect("user_stats_stored", _on_stats_stored)
	if steam.has_signal("user_stats_received") and not steam.is_connected("user_stats_received", _on_stats_received):
		steam.connect("user_stats_received", _on_stats_received)
	if _has("requestCurrentStats"):
		steam.call("requestCurrentStats")
	steam_input = NativeInput.new()
	steam_input.initialize(steam)
	_set_status("Steam connected")
	_flush_achievements()

func _process(delta: float) -> void:
	if online and _has("run_callbacks"):
		steam.call("run_callbacks")
	elif online and _has("runCallbacks"):
		steam.call("runCallbacks")
	if online and steam_input != null:
		steam_input.poll(delta)
	_retry_elapsed += delta
	if _retry_elapsed >= 5.0:
		_retry_elapsed = 0.0
		_flush_achievements()

func unlock_achievement(id: String) -> void:
	if id.is_empty():
		return
	if id not in pending_achievements:
		pending_achievements.append(id)
		_persist_achievements()
	_flush_achievements()

func _flush_achievements() -> void:
	if not online or not _submitted_achievements.is_empty() or not _has("setAchievement") or not _has("storeStats"):
		return
	var accepted: Array[String] = []
	for id: String in pending_achievements:
		if bool(steam.call("setAchievement", id)):
			accepted.append(id)
	if not accepted.is_empty():
		_submitted_achievements = accepted
		if not bool(steam.call("storeStats")):
			_submitted_achievements.clear()

func _on_stats_received(game_id: int, result: int, _user_id: int) -> void:
	if game_id == app_id and result == 1:
		_flush_achievements()

func _on_stats_stored(game_id: int, result: int) -> void:
	if game_id != app_id:
		return
	if result == 1:
		for id: String in _submitted_achievements:
			pending_achievements.erase(id)
		_persist_achievements()
	_submitted_achievements.clear()

func _persist_achievements() -> void:
	Saves.save_snapshot({}, {"pending": pending_achievements.duplicate()}, "steam_state")

func save_cloud(data: PackedByteArray, slot: String = "campaign") -> void:
	last_cloud_error = ERR_UNAVAILABLE
	if not _cloud_available() or data.is_empty() or data.size() > MAX_CLOUD_BYTES or not _has("fileWrite"):
		return
	var filename: String = _cloud_filename(slot)
	if filename.is_empty() or Saves.decode_snapshot(data).is_empty():
		last_cloud_error = ERR_INVALID_DATA
		return
	if not bool(steam.call("fileWrite", filename, data, data.size())):
		last_cloud_error = ERR_CANT_CREATE
		_set_status("Steam connected — cloud write unavailable; local save retained")
	else:
		last_cloud_error = OK

func load_cloud(slot: String = "campaign") -> PackedByteArray:
	if not _cloud_available() or not _has("fileExists") or not _has("getFileSize") or not _has("fileRead"):
		return PackedByteArray()
	var filename: String = _cloud_filename(slot)
	if filename.is_empty() or not bool(steam.call("fileExists", filename)):
		return PackedByteArray()
	var size: int = int(steam.call("getFileSize", filename))
	if size <= 0 or size > MAX_CLOUD_BYTES:
		return PackedByteArray()
	var response: Variant = steam.call("fileRead", filename, size)
	if response is PackedByteArray:
		return response
	if response is Dictionary:
		if not bool(response.get("ret", true)):
			return PackedByteArray()
		var bytes: Variant = response.get("buf", response.get("data", PackedByteArray()))
		if bytes is PackedByteArray:
			return bytes
	return PackedByteArray()

func inspect_cloud(slot: String = "campaign") -> Dictionary:
	var local: Dictionary = Saves.load_snapshot(slot)
	if not _cloud_available():
		return {"state": "offline", "local": local}
	var bytes: PackedByteArray = load_cloud(slot)
	if bytes.is_empty():
		return {"state": "missing", "local": local}
	var remote: Dictionary = Saves.decode_snapshot(bytes)
	if remote.is_empty() or bool(remote.get("profile", {}).get("demo", false)) != (slot == "demo"):
		return {"state": "invalid", "local": local}
	var compatible_remote: Dictionary = Saves.preview_migration(remote)
	var state: String = "remote_only" if local.is_empty() else "same" if local == compatible_remote else "conflict"
	# M19: each side's envelope metadata (last saved, play time) for the conflict cards.
	return {"state": state, "local": local, "remote": compatible_remote, "remote_bytes": bytes, "local_summary": snapshot_summary(local), "remote_summary": snapshot_summary(compatible_remote), "local_meta": Saves.load_meta(slot), "remote_meta": Saves.read_meta(bytes)}

func resolve_cloud(choice: String, slot: String = "campaign", remote_bytes: PackedByteArray = PackedByteArray()) -> Error:
	if slot not in ["campaign", "demo"]:
		return ERR_INVALID_PARAMETER
	if choice == "use_cloud":
		var bytes: PackedByteArray = remote_bytes if not remote_bytes.is_empty() else load_cloud(slot)
		var snapshot: Dictionary = Saves.decode_snapshot(bytes)
		if snapshot.is_empty() or bool(snapshot["profile"].get("demo", false)) != (slot == "demo"):
			return ERR_INVALID_DATA
		return Saves.install_snapshot(bytes, slot)
	if choice == "keep_local":
		var snapshot: Dictionary = Saves.load_snapshot(slot)
		if snapshot.is_empty():
			return ERR_FILE_NOT_FOUND
		save_cloud(Saves.encode_snapshot(snapshot), slot)
		return last_cloud_error
	return ERR_INVALID_PARAMETER

static func snapshot_summary(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "No saved instance"
	var profile: Dictionary = snapshot.get("profile", {})
	var run: Dictionary = snapshot.get("run", {})
	var combat: Dictionary = run.get("combat", {})
	return "Reboots %d / Waypoints %d / Cores %d / Light %.1f" % [int(profile.get("deaths",0)),profile.get("checkpoints",{}).size(),profile.get("defeated_leaders",[]).size(),float(combat.get("light_total",combat.get("player_energy",40.0)))]

func _cloud_available() -> bool:
	if not online:
		return false
	for method: String in ["isCloudEnabledForApp", "isCloudEnabledForAccount"]:
		if _has(method) and not bool(steam.call(method)):
			return false
	return true

static func _cloud_filename(slot: String) -> String:
	if slot == "campaign":
		return CLOUD_FILE
	if slot == "demo":
		return "lightship_demo_v2.json"
	return ""

func set_input_context(is_menu: bool) -> void:
	if steam_input != null:
		steam_input.set_context(is_menu)

func get_command(fallback_aim: Vector2 = Vector2.UP) -> ShipCommand:
	return steam_input.get_command(fallback_aim) if steam_input != null else null

func show_input_bindings() -> bool:
	return steam_input.show_bindings() if steam_input != null else false

func _exit_tree() -> void:
	if steam_input != null:
		steam_input.shutdown()

func _has(method: String) -> bool:
	return is_instance_valid(steam) and steam.has_method(method)

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)
