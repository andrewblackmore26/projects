extends SceneTree

func _initialize() -> void:
	var root: String = "res://content/ships"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root + "/abilities"))
	var rebuild: bool = "--rebuild" in OS.get_cmdline_user_args()
	var failures: int = 0
	var forms: Array[ShipDefinition] = [ShipCatalog.build_ship("corruption", 1, true)]
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			for family: String in ShipCatalog.FAMILIES: forms.append(ShipCatalog.build_ship(element, tier, true, [], family))
		for tier: int in range(1, GameTuning.MAX_TIER + 1):
			forms.append(ShipCatalog.build_ship(element, tier))
			forms.append(ShipCatalog.build_ship(element, tier, false, [], "heavy", "elite"))
		forms.append(ShipCatalog.build_ship(element, GameTuning.MAX_TIER, false, [], "standard_b", "rival"))
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
	print("Catalog: 136 ship / 26 ability definitions, ", preserved, " existing files preserved, ", failures, " failures.")
	quit(1 if failures else 0)

