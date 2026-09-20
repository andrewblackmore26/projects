extends SceneTree

func _initialize() -> void:
	var root: String = "res://content/ships"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root + "/abilities"))
	var rebuild: bool = "--rebuild" in OS.get_cmdline_user_args()
	var failures: int = 0
	var manifest: Array[Dictionary] = ShipGenerator.roster_manifest()
	var forms: Array[ShipDefinition] = []
	for entry: Dictionary in manifest: forms.append(ShipGenerator.build_from_entry(entry))
	var wanted_ids: Dictionary = {}
	for ship: ShipDefinition in forms: wanted_ids[ship.id] = true
	var removed: int = 0
	if rebuild:
		# Stale hulls from a retired manifest (e.g. v0.2's "enemy_%s_t%d",
		# "rival_%s_t5") are not overwritten by name and would otherwise sit
		# on disk forever, silently inflating ShipCatalog.all_forms().
		for file: String in DirAccess.get_files_at(root):
			if not file.ends_with(".tres"): continue
			var id: String = file.trim_suffix(".tres")
			if not wanted_ids.has(id):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/" + file))
				removed += 1
	var preserved: int = 0
	for ship: ShipDefinition in forms:
		var errors: PackedStringArray = ShipCatalog.validate(ship)
		if not errors.is_empty():
			push_error(ship.id + ": " + "; ".join(errors))
			failures += 1
			continue
		var path: String = root + "/" + ship.id + ".tres"
		if not rebuild and FileAccess.file_exists(path):
			preserved += 1
			continue
		var result: Error = ResourceSaver.save(ship, path)
		if result != OK:
			push_error("Save failed: " + ship.id)
			failures += 1
	for id: String in AbilityCatalog.DEFINITIONS:
		var path: String = root + "/abilities/" + id + ".tres"
		if not rebuild and FileAccess.file_exists(path):
			preserved += 1
			continue
		if ResourceSaver.save(AbilityCatalog.build_definition(id), path) != OK: failures += 1
	print("Catalog: ", forms.size(), " ship / 26 ability definitions, ", preserved, " existing files preserved, ", removed, " stale files removed, ", failures, " failures.")
	quit(1 if failures else 0)
