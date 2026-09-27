extends SceneTree
## One-time source census. Captures the actual authored roster, including local edits.
func _initialize() -> void:
	var path: String = "res://content/ship_geometry_v1.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--revision=2": path = "res://content/ship_geometry_v2.json"
	if FileAccess.file_exists(path):
		push_error("Geometry baseline already exists; refusing to replace it")
		quit(1)
		return
	var entries: Dictionary = {}
	for entry: Dictionary in RailRoster.manifest():
		var ship: ShipDefinition = ResourceLoader.load("res://content/ships/%s.tres" % entry.id, "", ResourceLoader.CACHE_MODE_IGNORE)
		if ship == null:
			quit(1)
			return
		var stats: Dictionary = {}
		for key: String in ["element", "speed", "turn_rate", "accel", "drag", "hp_buffer", "damage_multiplier", "magnet_radius", "motion_signature"]:
			stats[key] = ship.get(key)
		entries[ship.id] = {"grammar": JSON.parse_string(ShipAuthoring.to_json(ship)), "stats": stats, "counts": ShipCompiler.budget(ship)}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(entries, "\t") + "\n")
	file.close()
	print("Geometry baseline: %d authored hulls captured; failures=0" % entries.size())
	quit(0)
