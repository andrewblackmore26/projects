extends SceneTree
## Ship design spec §9 as laws over every fixture, headless.
##  Acceptance 3 ("pause any ship at a random frame: no two circles have their shine in the same
##  place, and no two rails are at the same angle"), tested STRUCTURALLY: counter-rotating rails
##  must cross for an instant and two shines of different period must momentarily coincide, so the
##  honest, deterministic form is that nothing is ever LOCKED in sync - no two shining circles share
##  a (period, phase), no two rails share an angular velocity, and neighbours turn opposite ways.
##  §9.4's lap periods by radius, §9.6's chain wave, and §9.5's pulse being render-only.
const Harness = preload("res://tests/support/harness.gd")
const FIXTURES: Array[String] = ["radial_elite", "player_t3", "drone", "boss", "irregular"]

func _initialize() -> void: _run.call_deferred()

func _load(name: String) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
	ShipCompiler.compile(ship)
	return ship

## Pairs of shining circles whose shine is locked together: same period, same phase (mod a lap).
func _locked_shines(ship: ShipDefinition) -> int:
	var seen: Dictionary = {}
	var locked: int = 0
	for part: PartDefinition in ship.parts:
		if part.shape != "circle" or part.style >= 4: continue
		var laps: float = fposmod(-part.light_phase / part.light_period, 1.0)
		var key: String = "%.3f|%.4f" % [part.light_period, laps]
		if seen.has(key): locked += 1
		seen[key] = true
	return locked

func _rail_problems(ship: ShipDefinition) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for a: int in range(ship.rails.size()):
		for b: int in range(a + 1, ship.rails.size()):
			if is_equal_approx(ship.rails[a].speed, ship.rails[b].speed): problems.append("rails %d and %d share %.2f rad/s" % [a + 1, b + 1, ship.rails[a].speed])
		if a > 0 and ship.rails[a].speed * ship.rails[a - 1].speed > 0.0: problems.append("rails %d and %d turn the same way" % [a, a + 1])
	return problems

func _chain(mode: String) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.from_dict({"id": "fixture_chain", "faction": "enemy", "archetype": "chain", "tier": 2, "chassis_color": "yellow", "core_depth": 2, "chain_mode": mode,
		"chain": [{"type": "hub", "pods": 1, "set_piece": "wedge_pair"}, {"type": "node", "radius": 7}, {"type": "hub", "pods": 1, "set_piece": "wedge_pair"}, {"type": "node", "radius": 7}, {"type": "node", "radius": 4}]}, errors)
	return ship

## Peak sideways excursion of the chain's tip and of its first link over ten seconds, in px.
func _chain_sway(ship: ShipDefinition) -> Dictionary:
	ShipCompiler.compile(ship)
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	var tip: float = 0.0
	var head: float = 0.0
	var stretch: float = 0.0
	for tick: int in range(600):
		ShipMotion.step(rig, pose, tick)
		tip = maxf(tip, absf(pose.local[rig.index_of("c4")].x))
		head = maxf(head, absf(pose.local[rig.index_of("c0")].x))
		stretch = maxf(stretch, absf(pose.local[rig.index_of("c4")].distance_to(pose.local[rig.index_of("c3")]) - float(ShipGrammar.MOTION.chain_rest_length)))
	return {"tip": tip, "head": head, "stretch": stretch}

func _run() -> void:
	var h := Harness.new("SHIP MOTION LAW")
	for name: String in FIXTURES:
		var ship: ShipDefinition = _load(name)
		h.check(_locked_shines(ship) == 0, "%s: no two circles' shines are locked together (%d locked pairs)" % [name, _locked_shines(ship)])
		h.check(_rail_problems(ship).is_empty(), "%s: no two rails share a speed and neighbours counter-rotate (%s)" % [name, ", ".join(_rail_problems(ship))])
		var off_table: int = 0
		for part: PartDefinition in ship.parts:
			if part.shape == "circle" and part.style < 4 and not is_equal_approx(part.light_period, ShipGrammar.shine_period(int(round(part.radius)))): off_table += 1
		h.check(off_table == 0, "%s: every shine laps at its radius's period from §9.4 (%d off the table)" % [name, off_table])
	var boss: ShipDefinition = _load("boss")
	for part: PartDefinition in boss.parts:
		if part.id == "r2s1" or part.id == "r2s4":
			part.light_phase = -0.5
	h.control("two boss hubs given the same shine phase", _locked_shines(boss) > 0)
	var wheel: ShipDefinition = _load("boss")
	wheel.rails[2].speed = wheel.rails[0].speed
	h.control("the boss's third rail given the first rail's speed", not _rail_problems(wheel).is_empty())
	h.check(is_equal_approx(ShipGrammar.shine_period(4), 1.40) and is_equal_approx(ShipGrammar.shine_period(34), 2.50) and ShipGrammar.shine_period(4) < ShipGrammar.shine_period(15), "Small circles buzz and big ones turn slowly (micro 1.40 s, hub 2.00 s, core 2.50 s)")

	# §9.6: the wave grows from the head to the tip, links keep their rest length, modes differ.
	var sway: Dictionary = _chain_sway(_chain("sway"))
	var whip: Dictionary = _chain_sway(_chain("whip"))
	var rigid: Dictionary = _chain_sway(_chain("rigid"))
	print("chain tip/head excursion px: rigid %.2f/%.2f sway %.2f/%.2f whip %.2f/%.2f, worst link stretch %.4f" % [rigid.tip, rigid.head, sway.tip, sway.head, whip.tip, whip.head, maxf(float(sway.stretch), float(whip.stretch))])
	# Measured 6.50 and 15.13 (the first link sits 64 px from the core, not 30, which adds a little).
	# The bands would fail the first version's 10.7 and 24.9.
	h.check(float(sway.tip) > float(sway.head) * 2.0 and float(sway.tip) > 5.0 and float(sway.tip) < 7.5, "A sway chain's tip swings §9.6's 6 px and its head far less (tip %.2f, head %.2f)" % [sway.tip, sway.head])
	h.check(float(whip.tip) > 12.5 and float(whip.tip) < 16.5, "A whip chain's tip swings §9.6's 14 px (%.2f)" % float(whip.tip))
	h.check(float(sway.stretch) < 0.001 and float(whip.stretch) < 0.001, "Links keep their 30 px rest length: lines stay straight between neighbours")
	h.control("a rigid chain (tip %.3f)" % float(rigid.tip), not (float(rigid.tip) > 3.0))
	h.check(ShipGrammar.validate(_chain("sway")).is_empty(), "The chain fixture validates (%s)" % ", ".join(ShipGrammar.validate(_chain("sway"))))

	# §9.5 is render-only: the pulse must not reach the pose, so colliders never breathe.
	var elite: ShipDefinition = _load("radial_elite")
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(elite)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	var scaled: bool = false
	for tick: int in [0, 23, 47, 118]:
		ShipMotion.step(rig, pose, tick)
		if not is_equal_approx(pose.scale[0], 1.0): scaled = true
	h.check(not scaled and is_equal_approx(elite.core_radius, 5.0), "The core dot's pulse never reaches the pose: the core's scale stays 1.0 and its radius 5")
	h.finish(self)
