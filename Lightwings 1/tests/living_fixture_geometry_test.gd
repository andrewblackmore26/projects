extends SceneTree
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void:
	var h := Harness.new("LIVING FIXTURE GEOMETRY")
	for name: String in ["orbiting_elite", "following_chain"]:
		var errors: PackedStringArray = PackedStringArray()
		var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/living_ships/%s.json" % name, errors)
		errors.append_array(ShipGrammar.validate(ship))
		ShipCompiler.compile(ship)
		var body: int = 0
		for part: PartDefinition in ship.parts:
			if part.shape == "circle" and part.style != 5: body += 1
		h.check(errors.is_empty(), "%s grammar compiles with connected non-guide topology: %s" % [name, errors])
		h.check(body == (21 if name == "orbiting_elite" else 16), "%s exact reference anatomy count plus separate eye" % name)
		var by_id: Dictionary = {}
		for part: PartDefinition in ship.parts:
			if part.shape == "circle": by_id[part.id] = part
		if name == "orbiting_elite":
			h.check(by_id.core.radius == 34.0 and by_id.core_2.radius == 17.0 and is_equal_approx(ship.core_radius, 4.4), "Elite34/17rings and4.4eye match reference")
			h.check(_rim(by_id.core, 0.4, 0.0) and _rim(by_id.core_2, 0.7, 0.0), "Elite core rims follow the source .4/.7 laps per second")
			for i: int in range(4):
				h.check(_rim(by_id["r1s%d" % i], 0.55, float(i) * 0.25), "Satellite%d follows .55 laps per second with source phase" % i)
			for i: int in range(3):
				var prefix: String = "r2s%d" % i
				h.check(by_id.has(prefix + "p0") and by_id.has(prefix + "p1") and by_id.has(prefix + "p2") and by_id.has(prefix + "w0") and not by_id.has(prefix + "w1"), "Elite arm%d contains exactly3goldpods and1redbead" % i)
				h.check(_rim(by_id[prefix], 0.42, float(i) * 0.2), "Hub%d follows .42 laps per second with source phase" % i)
				h.check(_rim(by_id[prefix + "w0"], 0.6, float(i) * 0.4), "Bead%d follows .6 laps per second with source phase" % i)
				for p: int in range(3):
					h.check(_rim(by_id[prefix + "p%d" % p], 0.5, float(p) * 0.31), "Hub%d pod%d follows .5 laps per second with source phase" % [i, p])
			var legacy: ShipDefinition = ship.duplicate(true)
			legacy.geometry_revision = 2
			ShipCompiler.compile(legacy)
			for part: PartDefinition in legacy.parts:
				if part.id == "r2s0": h.check(is_equal_approx(part.light_period, 2.0), "Revision2 retains its original radius-based hub period")
			var wrong: PartDefinition = by_id.r2s0.duplicate()
			wrong.light_period = 2.0
			h.control("old radius-based hub period fails the reference cadence", not _rim(wrong, 0.42, 0.0))
		else:
			for part: PartDefinition in by_id.values():
				h.check(is_equal_approx(part.light_period, 2.0), "Chain %s rim completes exactly .5 laps per second" % part.id)
			h.check(ship.chain_links.size() == 9 and ship.chain_mode == "follow", "Chain head has nine independent following tail links")
			h.check(by_id.core.radius == 22.0 and by_id.core_2.radius == 9.0 and ship.core_radius == 3.0 and ship.core_dot_color == "white", "Chain22/9headrings andwhite3eye match reference")
			for i: int in range(9):
				var link: PartDefinition = by_id["c%d" % i]
				var parent: PartDefinition = by_id[link.parent_id]
				h.check(is_equal_approx(link.radius, 16.0 - float(i) * 1.1) and is_equal_approx(link.position.distance_to(parent.position), 30.0), "Tail%d exact taper and30pixel centre spacing" % i)
		var copy: ShipDefinition = ship.duplicate(true)
		copy.core_radii = PackedFloat32Array([17.0, 34.0])
		h.control(name + " reversed core stack", not ShipGrammar.validate(copy).is_empty())
		copy = ship.duplicate(true)
		copy.chain_spacing = 0.0
		h.control(name + " zero chain rest length", not ShipGrammar.validate(copy).is_empty())
		print(name, ": body circles=", body, " + eye; budget=", ShipCompiler.budget(ship))
	h.finish(self)

func _rim(part: PartDefinition, laps_per_second: float, source_phase: float) -> bool:
	# Verify speed and starting phase independently: matching one must not hide a wrong other.
	return is_equal_approx(1.0 / part.light_period, laps_per_second) and is_equal_approx(fposmod(part.light_phase / part.light_period, 1.0), fposmod(source_phase, 1.0))
