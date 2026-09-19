extends SceneTree
func _initialize() -> void:
	var ships: Array[ShipDefinition] = [ShipCatalog.build_ship("corruption", 1, true)]
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			for family: String in ShipCatalog.FAMILIES: ships.append(ShipCatalog.build_ship(element, tier, true, [], family))
		for tier: int in range(1, GameTuning.MAX_TIER + 1):
			ships.append(ShipCatalog.build_ship(element, tier))
			ships.append(ShipCatalog.build_ship(element, tier, false, [], "heavy", "elite"))
		ships.append(ShipCatalog.build_ship(element, GameTuning.MAX_TIER, false, [], "standard_b", "rival"))
	var failed: bool = false
	for ship: ShipDefinition in ships:
		var errors: PackedStringArray = ShipCatalog.validate(ship)
		if not errors.is_empty(): push_error(ship.id + ": " + " | ".join(errors)); failed = true
	if failed: quit(1); return
	for ship: ShipDefinition in ships: ResourceSaver.save(ship, "res://content/ships/" + ship.id + ".tres")
	print("Authored ", ships.size(), " canonical hulls")
	quit()
