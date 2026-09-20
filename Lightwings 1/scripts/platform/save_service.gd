class_name SaveService
extends RefCounted

const SCHEMA_VERSION: int = 3
const MAX_SAVE_BYTES: int = 16 * 1024 * 1024
static var storage_root: String = "user://saves"
static var last_load_source: String = ""
static var last_error: String = ""

static func save_snapshot(profile: Dictionary, run: Dictionary, slot: String = "campaign") -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var state: Dictionary = {"profile": profile.duplicate(true), "run": run.duplicate(true)}
	if _read_snapshot(snapshot_path(slot)) == state:
		return OK
	return _atomic_write(snapshot_path(slot), encode_snapshot(state))

static func load_snapshot(slot: String = "campaign") -> Dictionary:
	last_load_source = ""
	last_error = ""
	if not _valid_slot(slot):
		last_error = "Invalid save slot"
		return {}
	var path: String = snapshot_path(slot)
	var found_candidate: bool = false
	for candidate: String in [path, path + ".bak", path + ".tmp"]:
		found_candidate = found_candidate or FileAccess.file_exists(candidate)
		var snapshot: Dictionary = _read_snapshot(candidate)
		if not snapshot.is_empty():
			last_load_source = candidate
			return _migrate_gameplay(snapshot, candidate, slot)
	if found_candidate:
		last_error = "Save files exist but no supported, valid snapshot could be recovered. Original files were retained."
	return {}

static func snapshot_path(slot: String = "campaign") -> String:
	return storage_root.path_join(slot + ".json")

## Install reviewed transport bytes exactly, preserving the former local backup.
## Legacy normalization runs only after the original bytes are safely archived.
static func install_snapshot(bytes: PackedByteArray, slot: String = "campaign") -> Error:
	if not _valid_slot(slot) or decode_snapshot(bytes).is_empty(): return ERR_INVALID_DATA
	var error: Error = _atomic_write(snapshot_path(slot), bytes)
	if error != OK: return error
	return OK if not load_snapshot(slot).is_empty() else ERR_FILE_CORRUPT

static func save_settings(settings: Dictionary) -> Error:
	return save_snapshot({}, settings, "settings")

static func load_settings() -> Dictionary:
	var snapshot: Dictionary = load_snapshot("settings")
	return snapshot.get("run", {})

static func import_demo(destination_slot: String = "campaign") -> Error:
	if destination_slot == "demo" or not _valid_slot(destination_slot):
		return ERR_INVALID_PARAMETER
	# Never overwrite a real campaign through the import action.
	if not load_snapshot(destination_slot).is_empty():
		return ERR_ALREADY_EXISTS
	if not last_error.is_empty(): return ERR_FILE_CORRUPT
	var saved: Dictionary = load_snapshot("demo")
	if saved.is_empty():
		return ERR_FILE_NOT_FOUND if last_error.is_empty() else ERR_FILE_CORRUPT
	var campaign_script: GDScript = preload("res://scripts/world/campaign_state.gd")
	var campaign: RefCounted = campaign_script.new()
	campaign.import_demo(saved["profile"])
	# The full map has five wedges; resume safely at its origin, retaining story.
	var run: Dictionary = {}
	if saved["run"].get("seen_lines") is Dictionary:
		run["seen_lines"] = saved["run"]["seen_lines"].duplicate(true)
	return save_snapshot(campaign.to_dict(), run, destination_slot)

static func _migrate_gameplay(snapshot: Dictionary, source: String, slot: String) -> Dictionary:
	var profile: Dictionary = snapshot["profile"]
	# Settings, Steam ledgers and generic transport fixtures are not campaigns.
	if not (profile.has("world_seed") or profile.has("current_sector") or profile.has("territories")):
		return snapshot
	if int(profile.get("schema_version", 1)) >= 3:
		return snapshot
	var original: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var legacy_path: String = snapshot_path(slot) + ".legacy-v%d" % int(profile.get("schema_version", 1))
	# A later cloud choice can bring a different legacy campaign into this slot.
	# Keep both originals instead of treating the first archive as a replacement.
	if FileAccess.file_exists(legacy_path) and FileAccess.get_file_as_bytes(legacy_path) != original:
		legacy_path += "-" + _digest(original).substr(0, 16)
	if not FileAccess.file_exists(legacy_path):
		var legacy: FileAccess = FileAccess.open(legacy_path, FileAccess.WRITE)
		if legacy == null:
			last_error = "Could not preserve legacy save; migration deferred"
			return {}
		legacy.store_buffer(original)
		legacy.flush()
		var write_error: Error = legacy.get_error()
		legacy.close()
		if write_error != OK or FileAccess.get_file_as_bytes(legacy_path) != original:
			last_error = "Legacy save verification failed; migration deferred"
			return {}
	if _read_snapshot(legacy_path).is_empty():
		last_error = "Existing legacy archive is invalid; migration deferred"
		return {}
	return preview_migration(snapshot)

## Pure normalization for cloud comparisons. The original reviewed bytes must
## still be installed and archived by load_snapshot after the user's choice.
static func preview_migration(snapshot: Dictionary) -> Dictionary:
	var profile: Dictionary = snapshot.get("profile", {})
	if not (profile.has("world_seed") or profile.has("current_sector") or profile.has("territories")) or int(profile.get("schema_version", 1)) >= 3:
		return snapshot.duplicate(true)
	var campaign_script: GDScript = preload("res://scripts/world/campaign_state.gd")
	var campaign: RefCounted = campaign_script.new()
	campaign.from_dict(profile)
	# A new light bar and hull roster cannot safely resume old combat entities.
	var run: Dictionary = {}
	var old_seen: Variant = snapshot["run"].get("seen_lines", {})
	if old_seen is Dictionary:
		var retained: Dictionary = {}
		for id: String in old_seen:
			if id.begins_with("reboot_") or id in ["first_evolution", "first_regression", "first_elite"]:
				retained[id] = bool(old_seen[id])
		if not retained.is_empty(): run["seen_lines"] = retained
	return {"profile": campaign.to_dict(), "run": run}

static func encode_snapshot(snapshot: Dictionary) -> PackedByteArray:
	var payload: PackedByteArray = var_to_bytes(snapshot)
	var envelope: Dictionary = {"format": "lightship_snapshot", "version": SCHEMA_VERSION, "saved_at": int(Time.get_unix_time_from_system()), "encoding": "godot_variant_base64", "sha256": _digest(payload), "payload": Marshalls.raw_to_base64(payload)}
	return JSON.stringify(envelope, "\t").to_utf8_buffer()

static func decode_snapshot(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_SAVE_BYTES:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {}
	var envelope: Dictionary = parsed
	var version: int = int(envelope.get("version", envelope.get("schema_version", 1)))
	if version > SCHEMA_VERSION or version < 1:
		return {}
	# v1 development saves used plain JSON profile/run dictionaries.
	if version == 1 and envelope.has("profile") and envelope.has("run"):
		return _validate_snapshot(envelope)
	if envelope.get("format", "") != "lightship_snapshot" or envelope.get("encoding", "") != "godot_variant_base64":
		return {}
	var payload: PackedByteArray = Marshalls.base64_to_raw(str(envelope.get("payload", "")))
	if payload.is_empty() or _digest(payload) != str(envelope.get("sha256", "")):
		return {}
	var snapshot: Variant = bytes_to_var(payload)
	if not snapshot is Dictionary:
		return {}
	return _validate_snapshot(snapshot)

## Highest CampaignState gameplay schema this build understands (P5: v0.3
## world model bumped CampaignState.GAMEPLAY_VERSION 3 -> 4). Kept as a
## literal, not a preload of campaign_state.gd, to avoid a load-order cycle;
## bump this whenever GAMEPLAY_VERSION moves.
const MAX_KNOWN_GAMEPLAY_SCHEMA: int = 4

static func _validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.get("profile") is Dictionary or not snapshot.get("run") is Dictionary:
		return {}
	if int(snapshot["profile"].get("schema_version", 1)) > MAX_KNOWN_GAMEPLAY_SCHEMA:
		return {}
	return {"profile": snapshot["profile"].duplicate(true), "run": snapshot["run"].duplicate(true)}

static func _valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64:
		return false
	for character: String in slot:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func _digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return decode_snapshot(bytes)

static func _atomic_write(path: String, bytes: PackedByteArray) -> Error:
	last_error = ""
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temporary: String = path + ".tmp"
	var backup: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK or _read_snapshot(temporary).is_empty():
		last_error = "Save verification failed"
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if not _read_snapshot(path).is_empty():
			if FileAccess.file_exists(backup):
				error = DirAccess.remove_absolute(backup)
				if error != OK:
					return error
			error = DirAccess.rename_absolute(path, backup)
		else:
			# Retain the known-good backup when replacing a corrupt primary.
			error = DirAccess.remove_absolute(path)
		if error != OK:
			return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		last_error = "Save rename failed; backup remains available"
	return error
