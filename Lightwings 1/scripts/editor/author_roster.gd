extends SceneTree
func _initialize() -> void:
	var manifest: Array[Dictionary] = ShipGenerator.roster_manifest()
	var ships: Array[ShipDefinition] = []
	for entry: Dictionary in manifest: ships.append(ShipGenerator.build_from_entry(entry))
	var failed: bool = false
	for ship: ShipDefinition in ships:
		var errors: PackedStringArray = ShipCatalog.validate(ship)
		if not errors.is_empty(): push_error(ship.id + ": " + " | ".join(errors)); failed = true
	if failed: quit(1); return
	for ship: ShipDefinition in ships: ResourceSaver.save(ship, "res://content/ships/" + ship.id + ".tres")
	print("Authored ", ships.size(), " canonical hulls")
	quit()
