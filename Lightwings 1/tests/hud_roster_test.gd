extends SceneTree
## Review finding 1 (spec §9/§24/§26): GameTuning.slots(6,"heavy") used to grant
## a 4th secondary slot ("+1 on top of the base count") that main.gd's literal
## 3-entry keybind arrays (["SPACE","SHIFT","Q"] etc, mirroring the 3 real
## bindings in §26's control table) cannot index. Every T6 heavy player hull
## (5 of 101) threw a SCRIPT ERROR out of _draw_slot_icons/_component_controls
## every frame, which aborted the function before it reached the minimap
## redraw call, freezing the corner minimap for the whole run.
## Separately, T6 grants 2 passive slots (spec §9) but ship_generator only
## ever appended 1, so all 20 T6 hulls (4 families x 5 elements) shipped
## short a slot GameTuning itself already accounted for.
## This builds the HUD once for EVERY hull in the roster (101 player hulls)
## and drives the real draw path, not just the data.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("HUD ROSTER")
	SaveService.storage_root = "user://hud-roster-test-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	app._new_game(false)
	await process_frame
	app.benchmark_mode = true

	var player_hulls: int = 0
	for entry: Dictionary in ShipGenerator.roster_manifest():
		if str(entry.faction) != "player": continue
		player_hulls += 1
		var ship: ShipDefinition = ShipGenerator.build_from_entry(entry)
		var limits: Dictionary = GameTuning.slots(ship.tier, ship.role)
		# The literal keybind arrays in main.gd (["SPACE","SHIFT","Q"] /
		# ["Space/LB","Shift/RB","Q/X"]) are exactly 3 long -- the real
		# number of secondary bindings anywhere in the control scheme (§26).
		h.check(ship.secondaries.size() <= 3, "%s: secondaries fit the 3 real keybind slots (found %d)" % [ship.id, ship.secondaries.size()])
		h.check(ship.passives.size() == int(limits.passive), "%s: T%d/%s mounts its full %d passive slot(s) (found %d)" % [ship.id, ship.tier, ship.role, int(limits.passive), ship.passives.size()])

		# Drive the real draw path for this hull, exactly as the HUD does in
		# play, so an engine SCRIPT ERROR (which tools/test.ps1's harness
		# treats as a failing run -- see tools/lib.ps1 ErrorPattern) would be
		# caught here instead of silently every frame in a real session.
		app.combat.player["definition"] = ship
		app.slot_overlay.queue_redraw()
		await process_frame
		var controls: String = app._component_controls()
		h.check(controls is String, "%s: _component_controls returns a string" % ship.id)
		if ship.secondaries.is_empty():
			h.check(controls == "Secondary: None", "%s: no secondaries reads as 'Secondary: None'" % ship.id)
		else:
			h.check(controls.split(" | ").size() == ship.secondaries.size(), "%s: _component_controls emits one label per secondary (found %d for %d secondaries)" % [ship.id, controls.split(" | ").size(), ship.secondaries.size()])

	h.check(player_hulls == 101, "Roster has 101 player hulls (found %d)" % player_hulls)

	# Negative controls: sabotage the exact invariant each check reads, on a
	# real built hull, so the control fails for the reason the check exists.
	# A hull that really flies THREE secondaries: lightning's pool has only two (slots are a cap),
	# so its T6 heavy carries two and appending one would not overflow anything.
	var oversized: ShipDefinition = ShipCatalog.get_ship("player_fire_t6_heavy")
	oversized.secondaries.append("bolt")
	h.control("a T6 heavy hull with a 4th secondary appended", oversized.secondaries.size() > 3)

	var starved: ShipDefinition = ShipCatalog.get_ship("player_fire_t6_standard_a")
	starved.passives.resize(1)
	var starved_limits: Dictionary = GameTuning.slots(starved.tier, starved.role)
	h.control("a T6 hull with its 2nd passive slot emptied", starved.passives.size() != int(starved_limits.passive))

	h.finish(self)
