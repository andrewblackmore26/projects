extends SceneTree
## ShipMotion._step_fk, the evaluator for rail-grammar hulls (ship design spec §9). The claims: a
## rail's cluster spins and pumps about the rail's centre; a pod bobs about its hub WHILE the hub
## moves (the thing the v0.3 group evaluator cannot do); a set piece takes the aim it is given and
## otherwise points outward; nothing ever changes a circle's size; the pose is a pure function of
## the tick; and non-solid circles stay out of the list the broadphase walks.
const Harness = preload("res://tests/support/harness.gd")

const RAIL: float = 96.0
const SPIN: float = 0.42
const TICKS_10S: int = 600

func _initialize() -> void: _run.call_deferred()

func _part(id: String, parent: String, at: Vector2, radius: float) -> PartDefinition:
	var part: PartDefinition = PartDefinition.new()
	part.id = id
	part.shape = "circle"
	part.parent_id = parent
	part.position = at
	part.radius = radius
	return part

## core -> rail ring (non-solid) -> hub (spins, pumps) -> pod (bobs), set-piece root (aim) -> tip.
## `pod_parent` and the amplitudes are the knobs the negative controls turn.
func _ship(pod_parent: String = "hub", bob: float = 0.14, pump: float = 0.03, aim: bool = true) -> ShipDefinition:
	var motion: Dictionary = ShipGrammar.MOTION
	var ship: ShipDefinition = ShipDefinition.new()
	ship.id = "fk_fixture"
	ship.schema_version = 4
	ship.parts.append(_part("core", "", Vector2.ZERO, 34))
	var ring: PartDefinition = _part("r2", "core", Vector2.ZERO, RAIL)
	ring.solid = false
	ship.parts.append(ring)
	var hub: PartDefinition = _part("hub", "r2", Vector2(0, -RAIL), 15)
	hub.spin_speed = SPIN
	hub.pump_amp = pump
	hub.pump_freq = float(motion.pump_freq)
	hub.pump_phase = 0.9
	ship.parts.append(hub)
	var pod: PartDefinition = _part("pod", pod_parent, Vector2(0, -RAIL - ShipGrammar.POD_DISTANCE), 7)
	pod.bob_amp = bob
	pod.bob_freq = float(motion.pod_bob_freq)
	pod.bob_phase = 1.0
	ship.parts.append(pod)
	var piece: PartDefinition = _part("w0", "hub", Vector2(0, -RAIL), 4)
	piece.aim_joint = aim
	piece.solid = false
	ship.parts.append(piece)
	var tip: PartDefinition = _part("w1", "w0", Vector2(0, -RAIL - 20), 4)
	tip.solid = false
	ship.parts.append(tip)
	return ship

func _pose_at(ship: ShipDefinition, tick: int, aim: float = NAN) -> ShipMotion.ShipPose:
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	if not is_nan(aim): pose.aim_angle[rig.index_of("w0")] = aim
	ShipMotion.step(rig, pose, tick)
	return pose

## Worst error, over ten seconds, between where the pod is and where §9.2 says it is: 30 px from
## the hub's LIVE centre, at the hub's angle plus the bob.
func _pod_error(ship: ShipDefinition) -> float:
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	var worst: float = 0.0
	for tick: int in range(0, TICKS_10S, 7):
		ShipMotion.step(rig, pose, tick)
		var t: float = float(tick) / 60.0
		var turn: float = SPIN * t + 0.14 * sin(float(ShipGrammar.MOTION.pod_bob_freq) * t + 1.0)
		var expected: Vector2 = pose.local[rig.index_of("hub")] + Vector2(0, -ShipGrammar.POD_DISTANCE).rotated(turn)
		worst = maxf(worst, pose.local[rig.index_of("pod")].distance_to(expected))
	return worst

## Peak-to-peak swing of the pod about its hub's outward direction, and of the hub's distance from
## the rail's centre as a fraction of the rail radius, over ten seconds (acceptance test 4).
func _excursions(ship: ShipDefinition) -> Dictionary:
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	var hub: int = rig.index_of("hub")
	var pod: int = rig.index_of("pod")
	var swing_low: float = INF
	var swing_high: float = -INF
	var reach_low: float = INF
	var reach_high: float = -INF
	for tick: int in range(TICKS_10S):
		ShipMotion.step(rig, pose, tick)
		var outward: float = pose.local[hub].angle()
		var swing: float = wrapf((pose.local[pod] - pose.local[hub]).angle() - outward, -PI, PI)
		swing_low = minf(swing_low, swing)
		swing_high = maxf(swing_high, swing)
		reach_low = minf(reach_low, pose.local[hub].length())
		reach_high = maxf(reach_high, pose.local[hub].length())
	return {"bob": swing_high - swing_low, "pump": (reach_high - reach_low) / RAIL}

## Direction the set piece points (root -> tip), in the hull frame, as an angle from "up".
func _piece_heading(ship: ShipDefinition, tick: int, aim: float) -> float:
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = _pose_at(ship, tick, aim)
	return wrapf((pose.local[rig.index_of("w1")] - pose.local[rig.index_of("w0")]).angle() + PI * 0.5, -PI, PI)

func _run() -> void:
	var h := Harness.new("SHIP FK")
	var ship: ShipDefinition = _ship()
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	h.check(not rig.legacy and rig.groups.is_empty(), "A schema-4 hull takes the forward-kinematics path")
	# A schema-3 hull built here: since the cutover no SHIPPED hull is v0.3 any more.
	var old: ShipDefinition = ShipDefinition.new()
	old.id = "legacy_fixture"
	old.parts.append(_part("core", "", Vector2.ZERO, 6))
	old.parts.append(_part("arm", "core", Vector2(20, 0), 5))
	var shipped: ShipMotion.ShipRig = ShipMotion.get_rig(old)
	h.check(old.schema_version == 3 and shipped.legacy and shipped.solid_indices.size() == shipped.rest.size() - 1, "A v0.3 hull stays on the legacy path with every circle but the core solid")

	# --- The rail: spin about the rail's centre, and pump of the RADIUS (§9.1, §9.3) ---
	var hub: int = rig.index_of("hub")
	var worst_angle: float = 0.0
	var worst_reach: float = 0.0
	for tick: int in range(0, TICKS_10S, 11):
		var pose: ShipMotion.ShipPose = _pose_at(ship, tick)
		var t: float = float(tick) / 60.0
		worst_angle = maxf(worst_angle, absf(wrapf(pose.local[hub].angle() + PI * 0.5 - SPIN * t, -PI, PI)))
		worst_reach = maxf(worst_reach, absf(pose.local[hub].length() - RAIL * (1.0 + 0.03 * sin(float(ShipGrammar.MOTION.pump_freq) * t + 0.9))))
	h.check(worst_angle < 0.0001, "The hub's angle about the rail centre is spin * t (worst error %.6f rad)" % worst_angle)
	h.check(worst_reach < 0.001, "The hub's distance from the rail centre is the pumped radius (worst error %.5f px)" % worst_reach)

	# --- The pod: bobs about its hub while the hub moves (§9.2) ---
	var pod_error: float = _pod_error(ship)
	h.check(pod_error < 0.001, "The pod sits 30 px from the hub's LIVE centre at hub angle + bob (worst error %.5f px)" % pod_error)
	var orphan_error: float = _pod_error(_ship("core"))
	h.control("the pod parented to the core, so it inherits nothing from the hub (error %.1f px)" % orphan_error, not (orphan_error < 0.001))

	# --- Acceptance 4: over ten seconds the pod visibly bobs and the arm visibly pumps ---
	var moving: Dictionary = _excursions(ship)
	h.check(float(moving.bob) >= 0.27, "Pod bob is at least 0.27 rad peak to peak over 10 s (measured %.3f; 2 x 0.14 = 0.28)" % float(moving.bob))
	h.check(float(moving.pump) >= 0.058, "Arm pump is at least 5.8%% of the rail radius peak to peak over 10 s (measured %.4f; 2 x 3%% = 6%%)" % float(moving.pump))
	var still: Dictionary = _excursions(_ship("hub", 0.0, 0.0))
	h.control("bob amplitude zeroed (measured %.3f)" % float(still.bob), not (float(still.bob) >= 0.27))
	h.control("pump amplitude zeroed (measured %.4f)" % float(still.pump), not (float(still.pump) >= 0.058))

	# --- Nothing scales (§3, §9.3) ---
	var scaled: bool = false
	for tick: int in range(0, TICKS_10S, 13):
		for value: float in _pose_at(ship, tick).scale:
			if not is_equal_approx(value, 1.0): scaled = true
	h.check(not scaled, "No circle's scale ever leaves 1.0")

	# --- The aim joint (§9.7): given an aim it holds it; given none it points outward ---
	var held: float = 0.0
	var outward: float = 0.0
	for tick: int in [0, 90, 333]:
		held = maxf(held, absf(wrapf(_piece_heading(ship, tick, 1.0) - 1.0, -PI, PI)))
		outward = maxf(outward, absf(wrapf(_piece_heading(ship, tick, NAN) - SPIN * float(tick) / 60.0, -PI, PI)))
	h.check(held < 0.0001, "A set piece given an aim of 1.0 rad points there at every tick while its rail turns (worst %.6f)" % held)
	h.check(outward < 0.0001, "A set piece given no aim points outward along its arm (worst %.6f)" % outward)
	var unjointed: float = absf(wrapf(_piece_heading(_ship("hub", 0.14, 0.03, false), 333, 1.0) - 1.0, -PI, PI))
	h.control("the aim joint removed, so the piece spins with its rail (off by %.2f rad)" % unjointed, not (unjointed < 0.0001))

	# --- Purity: the pose is a function of the tick, not of what was stepped before ---
	var direct: ShipMotion.ShipPose = _pose_at(ship, 250)
	var walked: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	for tick: int in [600, 3, 250]: ShipMotion.step(rig, walked, tick)
	h.check(direct.local == walked.local, "Stepping 600, 3, 250 leaves the same pose as stepping 250 alone")

	# --- Solid: what the broadphase will walk ---
	h.check(Array(rig.solid_indices) == [rig.index_of("hub"), rig.index_of("pod")], "Only the hub and the pod are solid; the rail ring and the set piece are not (%s)" % str(rig.solid_indices))
	var all_solid: ShipDefinition = _ship()
	for part: PartDefinition in all_solid.parts: part.solid = true
	h.control("every part marked solid, the 96 px rail ring included", ShipMotion.get_rig(all_solid).solid_indices.size() != 2)

	# --- The §9.2 pod fan ---
	var fan3: PackedFloat32Array = ShipGrammar.pod_angles(3)
	var fan4: PackedFloat32Array = ShipGrammar.pod_angles(4)
	# Tolerance, not equality: the array is float32 and the constants are float64.
	h.check(fan3.size() == 3 and absf(fan3[0] + 0.78) < 0.0001 and absf(fan3[1]) < 0.0001 and absf(fan3[2] - 0.78) < 0.0001 and fan4.size() == 4 and absf(fan4[0] + 1.17) < 0.0001 and absf(fan4[3] - 1.17) < 0.0001, "Pods fan 0.78 rad apart, centred on outward (%s, %s)" % [str(fan3), str(fan4)])
	h.control("a fan asked for five pods", ShipGrammar.pod_angles(5).size() != 5)
	h.finish(self)
