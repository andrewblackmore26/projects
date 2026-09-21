extends SceneTree
## Camera and movement spec, P11a: the feel of the SHIPPED game, measured. P6 recorded no numbers
## for handling, dash, trails or the warp, so this is where they are first written down. It reads
## hulls from the roster, not role literals: `handling_test.gd` sets speed/accel/drag by hand and so
## never noticed that a Heavy T6 cannot reach its own nominal speed.
##
## Every measurement has a cap and reports UNRESOLVED (-1) when it hits it, never a number it did not
## measure (tasks/lessons.md: an instrument that guards on a precondition reports "absent"). The
## control below proves that path: a ship that cannot move must come back unresolved.
##
## Results: `baseline:` lines on stdout and `artifacts/movement_feel.json`.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const STEP: float = 1.0 / 60.0
const OUT_PATH: String = "res://artifacts/movement_feel.json"
const UNRESOLVED: float = -1.0

## One hull per role at the first and last evolved tier, plus the seed everyone starts on.
const PLAYER_HULLS: Array[String] = [
	"player_seed",
	"player_lightning_t2_standard_a", "player_lightning_t6_standard_a",
	"player_lightning_t2_compact", "player_lightning_t6_compact",
	"player_lightning_t2_heavy", "player_lightning_t6_heavy",
]
## [hull id, rival, elite]
const ENEMY_HULLS: Array = [
	["enemy_drone_lightning_t2", false, false],
	["enemy_sentry_lightning_t2", false, false],
	["enemy_chain_lightning_t2", false, false],
	["elite_radial_lightning_t2", false, true],
	["elite_irregular_lightning_t2", false, true],
	["boss_lightning", true, false],
]

var t: RefCounted
var report: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("MOVEMENT FEEL")
	_player_handling()
	_node_crossing()
	_dash()
	_rim()
	_trails()
	_enemy_speeds()
	_seeker_turn_rate()
	_warp_locked()
	_unresolved_control()
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	await process_frame
	t.finish(self)

func make_world(visuals: bool = false) -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = visuals
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	w.arena.exits.clear() # no membrane can engage a warp mid-measurement
	w.arena.radius = 100000.0
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _note(group: String, key: String, value: Variant) -> void:
	if not report.has(group): report[group] = {}
	report[group][key] = value
	print("baseline: %s %s=%s" % [group, key, str(value)])

## Steps `_update_player` until `done` says so. Returns SECONDS, or UNRESOLVED at the cap.
func _seconds_until(w: CombatWorld, done: Callable, cap_ticks: int = 600) -> float:
	for tick: int in range(1, cap_ticks + 1):
		w._update_player(STEP)
		if done.call(): return float(tick) * STEP
	return UNRESOLVED

func _to_terminal(w: CombatWorld, direction: Vector2) -> float:
	w.command.movement = direction
	w.command.aim = direction
	for i: int in range(300): w._update_player(STEP) # 5 s: many time constants for every role
	return Vector2(w.player.vel).length()

func _player_handling() -> void:
	for hull: String in PLAYER_HULLS:
		var w: CombatWorld = make_world()
		if not t.check(w.set_player_hull(hull), "roster hull %s loads" % hull):
			release(w)
			continue
		# Nominal includes the Thrusters passive (x1.2), which every T6 hull sampled here carries.
		var nominal: float = float(w.player.speed) * (1.2 if w._has_ability(w.player, "thrusters") else 1.0)
		var terminal: float = _to_terminal(w, Vector2.RIGHT)
		_note(hull, "nominal_speed", snappedf(nominal, 0.01))
		_note(hull, "terminal_speed", snappedf(terminal, 0.01))
		_note(hull, "reaches_nominal", terminal >= nominal * 0.98)
		# Time to 90 % of the speed it actually reaches, from rest.
		w.player.vel = Vector2.ZERO
		var t90: float = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() >= terminal * 0.9)
		_note(hull, "t90_s", snappedf(t90, 0.0001))
		# Coast: input released at terminal speed, until below 5 %.
		_to_terminal(w, Vector2.RIGHT)
		w.command.movement = Vector2.ZERO
		var coast: float = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() < terminal * 0.05)
		_note(hull, "coast_to_5pct_s", snappedf(coast, 0.0001))
		# Reversal: from +terminal, until 90 % of terminal the other way.
		_to_terminal(w, Vector2.RIGHT)
		w.command.movement = Vector2.LEFT
		var reversal: float = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).x <= -terminal * 0.9)
		_note(hull, "reversal_to_90pct_s", snappedf(reversal, 0.0001))
		# Drift: 90 degree input step at terminal speed. Angle between velocity and the NEW input
		# at 0.15 s, and how far the ship is carried along the OLD heading before it settles.
		_to_terminal(w, Vector2.RIGHT)
		var start_x: float = Vector2(w.player.pos).x
		w.command.movement = Vector2.UP
		var angle_at_150ms: float = UNRESOLVED
		for tick: int in range(1, 121):
			w._update_player(STEP)
			if tick == 9: angle_at_150ms = rad_to_deg(absf(Vector2(w.player.vel).angle_to(Vector2.UP)))
		_note(hull, "drift_angle_deg_at_0.15s", snappedf(angle_at_150ms, 0.01))
		_note(hull, "drift_carry_px", snappedf(Vector2(w.player.pos).x - start_x, 0.01))
		t.check(t90 != UNRESOLVED and coast != UNRESOLVED and reversal != UNRESOLVED, "%s: t90, coast and reversal all resolved before their caps" % hull)
		release(w)

## Rim to rim along a diameter from rest, in the real 800 px arena (spec §2 / acceptance 5).
func _node_crossing() -> void:
	for hull: String in ["player_seed", "player_lightning_t2_compact", "player_lightning_t2_heavy"]:
		var w: CombatWorld = make_world()
		w.set_player_hull(hull)
		w.arena.radius = GameTuning.ARENA_RADIUS
		var reach: float = w.arena.radius - 4.0
		w.player.pos = w.arena.center + Vector2(-reach, 0.0)
		w.player.vel = Vector2.ZERO
		w.command.movement = Vector2.RIGHT
		w.command.aim = Vector2.RIGHT
		var seconds: float = _seconds_until(w, func() -> bool: return Vector2(w.player.pos).x >= w.arena.center.x + reach - 1.0, 3600)
		_note("node_crossing", hull + "_s", snappedf(seconds, 0.001))
		t.check(seconds != UNRESOLVED, "%s crosses the node before the 60 s cap" % hull)
		release(w)

func _dash() -> void:
	var w: CombatWorld = make_world()
	var top: float = _to_terminal(w, Vector2.RIGHT)
	var start: Vector2 = Vector2(w.player.pos)
	var peak: float = 0.0
	var burst_ticks: int = 0
	w.command.dash = true
	for tick: int in range(60):
		w._update_player(STEP)
		w.command.dash = false # a single press
		peak = maxf(peak, Vector2(w.player.vel).length())
		if float(w.player.get("dash_timer", 0.0)) > 0.0: burst_ticks = tick + 1
		elif burst_ticks > 0: break
	_note("dash", "cruise_speed", snappedf(top, 0.01))
	_note("dash", "peak_speed", snappedf(peak, 0.01))
	_note("dash", "peak_ratio", snappedf(peak / maxf(1.0, top), 0.001))
	_note("dash", "burst_s", snappedf(float(burst_ticks) * STEP, 0.0001))
	_note("dash", "distance_px", snappedf(Vector2(w.player.pos).distance_to(start), 0.01))
	# Cooldown: first tick a second press is accepted.
	var ready_tick: int = -1
	for tick: int in range(1, 240):
		w.command.dash = true
		var before: float = float(w.player.get("dash_timer", 0.0))
		w._update_player(STEP)
		if before <= 0.0 and float(w.player.get("dash_timer", 0.0)) > 0.0:
			ready_tick = tick
			break
	_note("dash", "second_dash_accepted_after_s", snappedf(float(burst_ticks + ready_tick) * STEP, 0.0001) if ready_tick > 0 else UNRESOLVED)
	t.check(burst_ticks > 0 and ready_tick > 0, "dash fired and its cooldown elapsed inside the measurement window")
	release(w)

## Hits the wall at 45 degrees at cruise speed, then keeps pushing diagonally into it.
func _rim() -> void:
	var w: CombatWorld = make_world()
	# Top speed FIRST, in the open: measured after the arena shrinks, the 5 s run ends grinding
	# head-on into the wall and "top speed" comes back as ~5 px/s (this probe's first run did
	# exactly that and reported a sliding ratio of 47).
	var top: float = _to_terminal(w, Vector2.RIGHT)
	w.arena.radius = GameTuning.ARENA_RADIUS
	var heading: Vector2 = Vector2(1.0, 1.0).normalized()
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 40.0, 120.0) # off-axis, clear of any opening
	w.player.vel = heading * top
	w.command.movement = heading
	var contacts: Array = []
	w.boundary_contact.connect(func(_at: Vector2) -> void: contacts.append(1))
	var speed_before: float = top
	var first_contact_ratio: float = UNRESOLVED
	for tick: int in range(120):
		var was: int = contacts.size()
		var pre: float = Vector2(w.player.vel).length()
		w._update_player(STEP)
		if was == 0 and contacts.size() > 0:
			speed_before = pre
			first_contact_ratio = Vector2(w.player.vel).length() / maxf(1.0, pre)
	_note("rim", "speed_before_contact", snappedf(speed_before, 0.01))
	_note("rim", "first_contact_speed_ratio", snappedf(first_contact_ratio, 0.001))
	_note("rim", "sliding_speed_ratio_after_2s", snappedf(Vector2(w.player.vel).length() / maxf(1.0, top), 0.001))
	_note("rim", "contact_signals_in_2s", contacts.size())
	t.check(first_contact_ratio != UNRESOLVED, "the ship reached the rim inside the measurement window")
	t.check(speed_before >= top * 0.95, "the ship hit the rim at cruise speed (%.1f of %.1f), so the contact ratio is a ratio of cruise" % [speed_before, top])
	release(w)

func _arc_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, points.size()): total += points[i - 1].distance_to(points[i])
	return total

func _player_trail_px(w: CombatWorld) -> float:
	var trail: Variant = w.trail_pool.trails.get(0)
	return _arc_length(trail.points) if trail != null else 0.0

## Trail arc length at cruise, at the end of a dash, and after standing still for 2 s.
func _trails() -> void:
	var w: CombatWorld = make_world(true) # `_update_trails` returns early without visuals
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	for i: int in range(300): w._physics_process(STEP)
	_note("trail", "cruise_px", snappedf(_player_trail_px(w), 0.1))
	var dash_px: float = 0.0
	w.command.dash = true
	for i: int in range(11): # the 0.18 s burst
		w._physics_process(STEP)
		w.command.dash = false
		dash_px = maxf(dash_px, _player_trail_px(w))
	_note("trail", "dash_peak_px", snappedf(dash_px, 0.1))
	w.command.movement = Vector2.ZERO
	for i: int in range(120): w._physics_process(STEP)
	_note("trail", "after_2s_at_rest_px", snappedf(_player_trail_px(w), 0.1))
	_note("trail", "speed_at_rest", snappedf(Vector2(w.player.vel).length(), 0.01))
	t.check(w.trail_pool.trails.has(0), "the player owns a trail")
	release(w)

## Top speed and peak turn rate of each archetype chasing a stationary player from 650 px.
func _enemy_speeds() -> void:
	for entry: Array in ENEMY_HULLS:
		var w: CombatWorld = make_world()
		w.player_invulnerable = 1.0e9
		var actor: Dictionary = w._spawn_named_enemy(str(entry[0]), "lightning", 2, w.arena.center + Vector2(650.0, 0.0), bool(entry[1]), bool(entry[2]))
		if not t.check(not actor.is_empty(), "roster hull %s spawns" % entry[0]):
			release(w)
			continue
		var top: float = 0.0
		var turn: float = 0.0
		var last_heading: float = Vector2(actor.aim).angle()
		var bullet_speed: float = 0.0
		for i: int in range(600):
			w.player_invulnerable = 1.0e9
			w._physics_process(STEP)
			top = maxf(top, Vector2(actor.vel).length())
			var heading: float = Vector2(actor.aim).angle()
			turn = maxf(turn, absf(angle_difference(last_heading, heading)) / STEP)
			last_heading = heading
			for index: int in w.bullets.active_indices:
				if w.bullets.factions[index] != 0: bullet_speed = maxf(bullet_speed, w.bullets.velocities[index].length())
		_note("enemy", str(entry[0]) + "_top_speed", snappedf(top, 0.01))
		_note("enemy", str(entry[0]) + "_peak_turn_rad_s", snappedf(turn, 0.01))
		_note("enemy", str(entry[0]) + "_fastest_shot", snappedf(bullet_speed, 0.01))
		release(w)

## A homing shot with its target at right angles. The turn limit in the code reads 2.8 rad/s; the
## weave term added after it is not scaled by dt, so the real rate is measured at two step sizes.
## A rate that changes with the step is frame-rate dependent.
func _seeker_turn_rate() -> void:
	for step: float in [1.0 / 60.0, 1.0 / 120.0]:
		var w: CombatWorld = make_world()
		w.player_invulnerable = 1.0e9
		w.player.pos = w.arena.center + Vector2(0.0, -900.0)
		var index: int = w.bullets.add(w.arena.center, Vector2.RIGHT * 310.0, 8.0, 0.0, 3.0, 999, 1, 0, Pool.HOMING)
		var peak: float = 0.0
		var total: float = 0.0
		var last: float = w.bullets.velocities[index].angle()
		var steps: int = roundi(1.0 / step)
		for i: int in range(steps):
			w.elapsed += step
			w._update_bullets(step)
			var now: float = w.bullets.velocities[index].angle()
			var rate: float = absf(angle_difference(last, now)) / step
			peak = maxf(peak, rate)
			total += rate
			last = now
		var label: String = "step_1_%d" % roundi(1.0 / step)
		_note("seeker", label + "_peak_rad_s", snappedf(peak, 0.01))
		_note("seeker", label + "_mean_rad_s", snappedf(total / float(steps), 0.01))
		release(w)

func _warp_locked() -> void:
	var w: CombatWorld = make_world()
	w.arena.radius = GameTuning.ARENA_RADIUS
	w.arena.exits.append(Vector2i.RIGHT) # typed Array[Vector2i]: an untyped literal cannot be assigned
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 4.0, 0.0)
	w.player.vel = Vector2(200.0, 0.0)
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	w.warp_committed.connect(func(_dir: Vector2i) -> void: w.confirm_warp_swap())
	var push_s: float = _seconds_until(w, func() -> bool: return w.warp_locked(), 240)
	var locked_s: float = _seconds_until(w, func() -> bool: return not w.warp_locked(), 600)
	_note("warp", "push_to_commit_s", snappedf(push_s, 0.0001))
	_note("warp", "commit_to_control_s", snappedf(locked_s, 0.0001))
	_note("warp", "warp_locked_measured_s", snappedf(w.warp_locked_measured, 0.0001))
	t.check(push_s != UNRESOLVED and locked_s != UNRESOLVED, "a push into an open membrane commits and the warp returns control")
	release(w)

## A ship with no speed can never reach 90 % of a positive target. If this came back as a number,
## every timing above could be a cap dressed up as a measurement.
func _unresolved_control() -> void:
	var w: CombatWorld = make_world()
	w.player.speed = 0.0
	w.command.movement = Vector2.RIGHT
	var seconds: float = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() >= 100.0, 120)
	t.control("a ship that cannot move (the timing must come back UNRESOLVED, not as a number)", seconds == UNRESOLVED)
	release(w)
