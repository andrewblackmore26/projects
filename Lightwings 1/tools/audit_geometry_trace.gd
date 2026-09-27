extends "res://tests/golden_trace_test.gd"
## Diagnostic only: compares archived revision2 with current geometry using the unchanged route.
## Writes reviewable artifacts; never replaces the golden fixture.
var captured: Array = []
const BulletPool = preload("res://scripts/combat/bullet_pool.gd")

func _record(steps: Array, name: String) -> void:
	super._record(steps, name)
	var state: Dictionary = app.combat.snapshot()
	captured.append({"step": name, "snapshot": state.duplicate(true), "digest_matches": _digest(state) == steps[-1].snapshot})

func _run() -> void:
	SaveService.storage_root = "user://geometry-trace-audit-%d" % Time.get_ticks_usec()
	var original: String = ShipCatalog.catalog_root
	var scratch: String = "user://geometry-trace-v2-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
	for entry: Dictionary in RailRoster.manifest():
		ShipCatalog.save_ship(ShipCatalog.get_ship_revision(str(entry.id), 2), scratch.path_join(str(entry.id) + ".tres"))
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	var report: Dictionary = {"expected": golden.steps}
	for revision: int in [2, 3]:
		ShipCatalog.catalog_root = scratch if revision == 2 else original
		ShipCatalog.invalidate()
		captured.clear()
		var steps: Array = _route(false)
		var normalized: Array = steps.duplicate(true)
		for i: int in range(steps.size()): normalized[i].snapshot = _digest(_without_new_metadata(captured[i].snapshot))
		report["revision%d" % revision] = {"steps": steps, "snapshots": captured.duplicate(true), "without_new_save_metadata": normalized}
		print("revision%d public differences: %s" % [revision, _differences(golden.steps, steps, ["snapshot"])])
		print("revision%d normalized differences: %s" % [revision, _differences(golden.steps, normalized, [])])
		await process_frame
	ShipCatalog.catalog_root = original
	ShipCatalog.invalidate()
	captured.clear()
	var repeated: Array = _route(false)
	var sabotaged: Array = _route(true)
	report.repeat_deterministic = _first_difference(report.revision3.steps, repeated) == ""
	report.command_negative_control = _first_difference(repeated, sabotaged) != ""
	var file: FileAccess = FileAccess.open("res://artifacts/geometry_trace_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	for entry: Dictionary in RailRoster.manifest(): DirAccess.remove_absolute(scratch.path_join(str(entry.id) + ".tres"))
	DirAccess.remove_absolute(scratch)
	await app._stop_audio()
	app.queue_free()
	await process_frame
	print("GEOMETRY TRACE AUDIT: repeat=%s, command control=%s" % [report.repeat_deterministic, report.command_negative_control])
	quit(0 if report.repeat_deterministic and report.command_negative_control else 1)

func _without_new_metadata(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var actors: Array = result.get("enemies", [])
	if result.has("player"): actors = actors.duplicate() + [result.player]
	for actor: Dictionary in actors:
		actor.erase("hull_definition")
		actor.erase("chain_motion")
	# Approved projectile art changes also persist drawn radius (vr), not collider radius.
	for bullet: Dictionary in result.get("bullets", []):
		var flags: int = int(bullet.flags)
		bullet.vr = 9.0 if flags & BulletPool.ROCKET else 7.5 if flags & BulletPool.HOMING else 4.0 if flags & BulletPool.RICOCHET else 3.5 if flags & BulletPool.CHAIN else 3.0
	for key: String in result.get("encounter_records", {}):
		var compressed: PackedByteArray = Marshalls.base64_to_raw(str(result.encounter_records[key]))
		var raw: PackedByteArray = compressed.decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
		var old: Dictionary = _without_new_metadata(bytes_to_var(raw))
		result.encounter_records[key] = Marshalls.raw_to_base64(var_to_bytes(old).compress(FileAccess.COMPRESSION_DEFLATE))
	return result

func _differences(expected: Array, actual: Array, skip: Array) -> Array:
	actual = JSON.parse_string(JSON.stringify(actual))
	var changes: Array = []
	for i: int in range(mini(expected.size(), actual.size())):
		for key: String in expected[i]:
			if key in skip: continue
			if str(expected[i][key]) != str(actual[i].get(key)):
				changes.append({"step": expected[i].step, "field": key, "before": expected[i][key], "after": actual[i].get(key)})
	return changes
