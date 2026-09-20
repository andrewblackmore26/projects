extends SceneTree
## P5b: save schema 4. Migrates the genuine v0.2 (schema 3) fixtures written
## by the real build (tests/fixtures/*_v3.json), archives the original bytes
## byte-for-byte, and resets unlocks to Lightning while keeping the old list
## in legacy_history (approved preamble).
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("SAVE MIGRATION")
	SaveService.storage_root = "user://save-migration-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(SaveService.storage_root)

	for slot: String in ["campaign", "demo"]:
		var fixture_path: String = "res://tests/fixtures/%s_v3.json" % slot
		var original: PackedByteArray = FileAccess.get_file_as_bytes(fixture_path)
		h.check(not original.is_empty(), "Fixture %s_v3.json is readable" % slot)
		var target: String = SaveService.snapshot_path(slot)
		var file := FileAccess.open(target, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()

		var decoded_before: Dictionary = SaveService.decode_snapshot(original)
		var old_unlocked: Array = decoded_before.get("profile", {}).get("unlocked", [])
		h.check(int(decoded_before.get("profile", {}).get("schema_version", -1)) == 3, "Fixture %s is genuinely schema 3" % slot)

		var loaded: Dictionary = SaveService.load_snapshot(slot)
		h.check(not loaded.is_empty(), "v3 -> v4 migration loads %s" % slot)
		var profile: Dictionary = loaded.get("profile", {})
		h.check(int(profile.get("schema_version", -1)) == SchemaVersion.CURRENT, "%s profile now carries schema %d" % [slot, SchemaVersion.CURRENT])
		h.check(int(profile.get("deaths", -1)) == 1, "%s deaths carried over" % slot)
		h.check(bool(profile.get("story_flags", {}).get("reboot_1", false)), "%s whitelisted reboot_ story flag carried over" % slot)
		h.check(profile.get("unlocked", []) == ["lightning"], "%s unlocked resets to Lightning only" % slot)
		h.check(profile.get("legacy_history", {}).get("schema_3_unlocked", []) == old_unlocked, "%s old unlocked list survives in legacy_history" % slot)
		h.check(not old_unlocked.is_empty(), "Setup: the fixture's old unlocked list was non-trivial, not a vacuous check")

		var legacy_path: String = target + ".legacy-v3"
		h.check(FileAccess.file_exists(legacy_path), "%s.json.legacy-v3 was written" % slot)
		var archived: PackedByteArray = FileAccess.get_file_as_bytes(legacy_path)
		h.check(archived == original, "%s.json.legacy-v3 holds the original bytes byte-for-byte" % slot)

	# Negative control: a payload claiming an unknown future version must be
	# rejected outright, not half-read.
	var payload: PackedByteArray = "not a real payload".to_utf8_buffer()
	var envelope: Dictionary = {"format": "lightship_snapshot", "version": 99, "encoding": "godot_variant_base64", "sha256": "0", "payload": Marshalls.raw_to_base64(payload)}
	var bogus: PackedByteArray = JSON.stringify(envelope, "\t").to_utf8_buffer()
	var rejected: Dictionary = SaveService.decode_snapshot(bogus)
	h.control("a version-99 payload accepted instead of rejected", rejected.is_empty())

	# Control: a legitimate current-schema save must NOT be treated as legacy
	# (proves the >= SchemaVersion.CURRENT short-circuit still works after
	# the P5b bugfix -- before the fix this compared against a stale literal
	# 3, so it is not enough to prove schema-3 alone migrates correctly).
	var fresh_slot: String = "campaign2"
	var current_profile: Dictionary = {"schema_version": SchemaVersion.CURRENT, "mode": "campaign", "world_seed": 1, "current_sector": "0,0"}
	SaveService.save_snapshot(current_profile, {}, fresh_slot)
	SaveService.load_snapshot(fresh_slot)
	h.control("a current-schema save wrongly archived as legacy",
		not FileAccess.file_exists(SaveService.snapshot_path(fresh_slot) + ".legacy-v%d" % SchemaVersion.CURRENT))

	h.finish(self)
