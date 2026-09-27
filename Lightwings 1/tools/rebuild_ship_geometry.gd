extends SceneTree
## Stage all reviewed manifest entries. -- --apply copies only those files; custom hulls survive.
func _initialize() -> void:
	var stage: String = "res://artifacts/ships_geometry_v3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stage))
	var failures: PackedStringArray = PackedStringArray()
	for entry: Dictionary in RailRoster.manifest():
		var ship: ShipDefinition = RailRoster.build(entry)
		for error: String in ShipCatalog.validate(ship): failures.append("%s: %s" % [ship.id, error])
		if not failures.is_empty(): continue
		if ShipCatalog.save_ship(ship, stage.path_join(ship.id + ".tres")) != OK: failures.append("save " + ship.id)
	if failures.is_empty() and OS.get_cmdline_user_args().has("--apply"):
		for entry: Dictionary in RailRoster.manifest():
			var name: String = str(entry.id) + ".tres"
			var result: Error = DirAccess.copy_absolute(stage.path_join(name), "res://content/ships/" + name)
			if result != OK: failures.append("copy " + name)
	for error: String in failures: push_error(error)
	print("Ship geometry rebuild: %d hulls, %d failures, applied=%s" % [RailRoster.manifest().size(), failures.size(), OS.get_cmdline_user_args().has("--apply")])
	quit(0 if failures.is_empty() else 1)
