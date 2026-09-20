extends SceneTree
## Execute against the actual exported PCK with --script to verify remapped assets.
func _initialize() -> void:
	var failures: int = 0
	ShipCatalog.invalidate()
	var forms: Array[ShipDefinition] = ShipCatalog.all_forms()
	var factions: Dictionary = {}
	if forms.size() != 141:
		failures += 1
		push_error("Exported catalog must enumerate all 141 hulls; found " + str(forms.size()))
	for ship: ShipDefinition in forms:
		factions[ship.faction] = int(factions.get(ship.faction, 0)) + 1
		if not ShipCatalog.validate(ship).is_empty() or ShipCatalog.get_ship(ship.id) == null:
			failures += 1
			push_error("Exported resource failed: " + ship.id)
	if factions.get("player", 0) != 101 or factions.get("enemy", 0) != 50 or factions.get("elite", 0) != 35 or factions.get("boss", 0) != 5:
		failures += 1
		push_error("Exported faction census failed: " + str(factions))
	var seed: ShipDefinition = ShipCatalog.get_ship("player_seed")
	if seed == null or seed.element != "neutral": failures += 1
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			if ShipCatalog.roster(element, tier).size() != 4:
				failures += 1
				push_error("Exported roster gap: %s T%d" % [element, tier])
	for id: String in AbilityCatalog.DEFINITIONS:
		var ability: AbilityDefinition = load("res://content/ships/abilities/" + id + ".tres")
		if ability == null or ability.id != id or ability.description.is_empty():
			failures += 1
			push_error("Exported ability failed: " + id)
	print("Exported catalog: ", forms.size(), " authored ships / 26 abilities, ", failures, " failures")
	quit(1 if failures else 0)

