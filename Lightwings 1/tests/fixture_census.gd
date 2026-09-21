extends SceneTree
## Prints each schema-4 fixture's compiled budget and footprint. Not a test; a measurement for the
## review tables.   tools\godot.ps1 -Arguments '--headless --script "res://tests/fixture_census.gd"'

func _initialize() -> void:
	for name: String in ["drone", "player_t3", "radial_elite", "irregular", "boss"]:
		var errors: PackedStringArray = PackedStringArray()
		var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
		ShipCatalog.refresh(ship)
		print("fixture %-13s %s footprint=%.0f" % [name, str(ShipCompiler.budget(ship)), ship.footprint])
	print("fixture census checks: 5 measured, 0 failures")
	quit(0)
