extends SceneTree
## Camera and movement spec: the feel of the SHIPPED game, measured against the spec. P11a wrote the
## first numbers down as a baseline (P6 recorded none); M7 turned the player half into gates:
##   handling   t90 / coast / reversal within ONE TICK of the closed-form prediction at 1/30, 1/60,
##              1/120 and 1/144 s, and the same trajectory at every rate (control: an Euler step)
##   drift      18 +- 2 degrees at 0.15 s; no turn ever exceeds 1.02 x top speed
##   crossing   the base hull crosses the 1600 px node in 3.5 +- 0.15 s (control: half speed)
##   dash       2.5 x for 0.18 s, 1.1 s cooldown, each within one tick at every rate
##   rim        x0.55 once on contact, a 0.55 cap while sliding, ONE boundary_contact per episode
##              (controls: scale 1.0; an episode memory wiped every tick)
##   trails     180 px at top speed, 320 px in a dash, nothing at rest, +-10 % (controls per line)
##   pickups    light reaches a player fleeing at top speed (control: the old flat 330 px/s)
## M8 gated the enemy half:
##   enemies    every archetype at two tiers reaches ratio x player_top_speed +- 2 % (control: the
##              pre-M8 absolute speed), never turns its heading faster than its unicycle limit
##              (control: limit 50 rad/s), and never fires faster than the fastest enemy shot ratio
##              (control: every enemy shot at the player's bolt ratio)
##   disengage  every archetype x base, compact, heavy and slowed heavy hull, 20 seeds: holding a
##              direction away gains separation over 2 s, median AND min (control: a drone at 1.3)
##   seeker     the weave's amplitude and the total turn rate at 1/30..1/144 s match a 1/720 s run
##              (control: the pre-M8 per-tick weave); a straight charge from 500 px is hit >= 90 %,
##              and a weave is hit at most 40 % as often as a straight line (controls: turn 0.3, 18)
## M9 gated the warp (the full phase and persistence proofs are warp_test / warp_persistence_test):
##   warp       press 0.20 s to commit, commit -> the ship answers the stick <= 0.6 s, stepped
##              through the real tick (control: the pre-M9 1.02 s locked window)
##
## Every measurement has a cap and reports UNRESOLVED (-1) when it hits it, never a number it did not
## measure (tasks/lessons.md: an instrument that guards on a precondition reports "absent"). The
## control at the end proves that path: a ship that cannot move must come back unresolved.
##
## Results: `baseline:` lines on stdout and `artifacts/movement_feel.json`.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const STEP: float = 1.0 / 60.0
const RATES: Array[int] = [30, 60, 120, 144]
const OUT_PATH: String = "res://artifacts/movement_feel.json"
const UNRESOLVED: float = -1.0

## One hull per role at the first and last evolved tier, plus the seed everyone starts on.
const PLAYER_HULLS: Array[String] = [
	"player_seed",
	"player_lightning_t2_standard_a", "player_lightning_t6_standard_a",
	"player_lightning_t2_compact", "player_lightning_t6_compact",
	"player_lightning_t2_heavy", "player_lightning_t6_heavy",
]
## Measured at all four tick rates.
const RATE_HULLS: Array[String] = ["player_seed", "player_lightning_t2_compact", "player_lightning_t2_heavy"]
## [hull id, rival, elite]: every archetype at its first tier and its last.
const ENEMY_HULLS: Array = [
	["enemy_drone_lightning_t1", false, false], ["enemy_drone_plasma_t6", false, false],
	["enemy_sentry_lightning_t2", false, false], ["enemy_sentry_plasma_t6", false, false],
	["enemy_chain_lightning_t2", false, false], ["enemy_chain_plasma_t6", false, false],
	["elite_radial_lightning_t2", false, true], ["elite_radial_plasma_t6", false, true],
	["elite_irregular_lightning_t2", false, true], ["elite_irregular_plasma_t6", false, true],
	["elite_heavy_lightning_t2", false, true], ["elite_heavy_plasma_t6", false, true],
	["boss_lightning", true, false], ["boss_void", true, false],
]
## The movers, for the disengage test: [hull id, rival, elite].
const DISENGAGE_ENEMIES: Array = [
	["enemy_drone_lightning_t2", false, false], ["enemy_chain_lightning_t2", false, false],
	["elite_radial_lightning_t2", false, true], ["elite_irregular_lightning_t2", false, true],
	["elite_heavy_lightning_t2", false, true], ["boss_lightning", true, false],
]
## [player hull, slowed]: the base hull, the fastest, the slowest, and the slowest in a slow field.
const DISENGAGE_PLAYERS: Array = [
	["player_seed", false], ["player_lightning_t2_compact", false],
	["player_lightning_t2_heavy", false], ["player_lightning_t2_heavy", true],
]
const SEEDS: int = 20

var t: RefCounted
var report: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("MOVEMENT FEEL")
	GameTuning.reset_feel()
	_player_handling()
	_tick_rates()
	_node_crossing()
	_dash()
	_rim()
	_trails()
	_pickups()
	_enemy_speeds()
	_disengage()
	_seeker_weave()
	_seeker_hits()
	_warp_locked()
	_unresolved_control()
	GameTuning.reset_feel()
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
	w.arena.sealed = true # no exit can engage a warp mid-measurement
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
func _seconds_until(w: CombatWorld, done: Callable, cap_ticks: int = 600, step: float = STEP) -> float:
	for tick: int in range(1, cap_ticks + 1):
		w._update_player(step)
		if done.call(): return float(tick) * step
	return UNRESOLVED

func _to_terminal(w: CombatWorld, direction: Vector2, step: float = STEP) -> float:
	w.command.movement = direction
	w.command.aim = direction
	for i: int in range(roundi(3.0 / step)): w._update_player(step) # dozens of time constants for every role
	return Vector2(w.player.vel).length()

func _role(w: CombatWorld) -> String:
	return str(w.player.definition.role) if w.player.get("definition") != null else "standard"

## The spec's three timings as the closed form predicts them for this hull's role.
func _predicted(w: CombatWorld) -> Dictionary:
	var taus: Dictionary = GameTuning.movement_taus(_role(w))
	return {"t90": float(taus.accel) * log(10.0), "coast": float(taus.coast) * log(1.0 / GameTuning.feel("move.coast_stop_frac")), "reversal": float(taus.accel) * log(20.0)}

## t90, coast to 5 % and reversal to 90 %, measured at one tick size.
func _timings(hull: String, step: float, euler: bool = false) -> Dictionary:
	var w: CombatWorld = make_world()
	var out: Dictionary = {}
	if not w.set_player_hull(hull):
		release(w)
		return out
	w.movement_euler = euler
	var nominal: float = w.player_top_speed()
	var terminal: float = _to_terminal(w, Vector2.RIGHT, step)
	w.player.vel = Vector2.ZERO
	var cap: int = roundi(10.0 / step)
	out.t90 = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() >= terminal * 0.9, cap, step)
	_to_terminal(w, Vector2.RIGHT, step)
	w.command.movement = Vector2.ZERO
	out.coast = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() < terminal * 0.05, cap, step)
	_to_terminal(w, Vector2.RIGHT, step)
	w.command.movement = Vector2.LEFT
	out.reversal = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).x <= -terminal * 0.9, cap, step)
	out.nominal = nominal
	out.terminal = terminal
	out.predicted = _predicted(w)
	release(w)
	return out

## Every timing within one tick of its prediction (a timing sampled at ticks lands on the first tick
## at or after the continuous moment, so the honest band is one step wide).
func _within_a_tick(m: Dictionary, step: float) -> bool:
	if m.is_empty(): return false
	for key: String in ["t90", "coast", "reversal"]:
		if float(m[key]) == UNRESOLVED or absf(float(m[key]) - float(m.predicted[key])) > step + 0.000001: return false
	return true

func _player_handling() -> void:
	for hull: String in PLAYER_HULLS:
		var m: Dictionary = _timings(hull, STEP)
		if not t.check(not m.is_empty(), "roster hull %s loads" % hull): continue
		_note(hull, "nominal_speed", snappedf(float(m.nominal), 0.01))
		_note(hull, "terminal_speed", snappedf(float(m.terminal), 0.01))
		_note(hull, "t90_s", snappedf(float(m.t90), 0.0001))
		_note(hull, "coast_to_5pct_s", snappedf(float(m.coast), 0.0001))
		_note(hull, "reversal_to_90pct_s", snappedf(float(m.reversal), 0.0001))
		t.check(absf(float(m.terminal) - float(m.nominal)) <= float(m.nominal) * 0.005, "%s: terminal %.2f is its top speed %.2f (no clamp, no drag equilibrium)" % [hull, m.terminal, m.nominal])
		t.check(_within_a_tick(m, STEP), "%s at 1/60: t90 %.4f / coast %.4f / reversal %.4f within a tick of %.4f / %.4f / %.4f" % [hull, m.t90, m.coast, m.reversal, m.predicted.t90, m.predicted.coast, m.predicted.reversal])
		# Drift: 90 degree input step at top speed. Angle between velocity and the NEW input at
		# 0.15 s, how far the ship is carried along the OLD heading, and its peak speed in the turn.
		var w: CombatWorld = make_world()
		w.set_player_hull(hull)
		_to_terminal(w, Vector2.RIGHT)
		var start_x: float = Vector2(w.player.pos).x
		w.command.movement = Vector2.UP
		var angle_at_150ms: float = UNRESOLVED
		var peak: float = 0.0
		for tick: int in range(1, 121):
			w._update_player(STEP)
			peak = maxf(peak, Vector2(w.player.vel).length())
			if tick == 9: angle_at_150ms = rad_to_deg(absf(Vector2(w.player.vel).angle_to(Vector2.UP)))
		_to_terminal(w, Vector2.RIGHT)
		w.command.movement = Vector2(-1.0, 1.0).normalized() # a 135 degree step
		for tick: int in range(60):
			w._update_player(STEP)
			peak = maxf(peak, Vector2(w.player.vel).length())
		_note(hull, "drift_angle_deg_at_0.15s", snappedf(angle_at_150ms, 0.01))
		_note(hull, "drift_carry_px", snappedf(Vector2(w.player.pos).x - start_x, 0.01))
		_note(hull, "peak_speed_in_turn_ratio", snappedf(peak / float(m.nominal), 0.0001))
		t.check(peak <= float(m.nominal) * 1.02, "%s: peak speed in a 90 and a 135 degree turn is %.4f x top (<= 1.02)" % [hull, peak / float(m.nominal)])
		if _role(w) == "standard":
			t.check(absf(angle_at_150ms - GameTuning.feel("move.drift_deg")) <= 2.0, "%s: velocity lags a 90 degree step by %.2f degrees at 0.15 s (spec 18 +- 2)" % [hull, angle_at_150ms])
		release(w)

## Position and velocity after 1/3 s RIGHT, 1/3 s UP and 1/3 s released: tick-aligned at every rate.
func _trajectory(hull: String, step: float, euler: bool) -> PackedVector2Array:
	var w: CombatWorld = make_world()
	w.set_player_hull(hull)
	w.movement_euler = euler
	var origin: Vector2 = Vector2(w.player.pos)
	var out: PackedVector2Array = PackedVector2Array()
	for input: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.ZERO]:
		w.command.movement = input
		for i: int in range(roundi(1.0 / 3.0 / step)): w._update_player(step)
		out.append(Vector2(w.player.pos) - origin)
		out.append(Vector2(w.player.vel))
	release(w)
	return out

## The worst disagreement with a 1/720 s closed-form reference: [position px, velocity px/s].
func _disagreement(hull: String, step: float, euler: bool) -> Vector2:
	var reference: PackedVector2Array = _trajectory(hull, 1.0 / 720.0, false)
	var run: PackedVector2Array = _trajectory(hull, step, euler)
	var worst: Vector2 = Vector2.ZERO
	for i: int in range(reference.size()):
		var error: float = reference[i].distance_to(run[i])
		if i % 2 == 0: worst.x = maxf(worst.x, error)
		else: worst.y = maxf(worst.y, error)
	return worst

func _rates_agree(hull: String, step: float, euler: bool) -> bool:
	var worst: Vector2 = _disagreement(hull, step, euler)
	return worst.x <= 0.5 and worst.y <= 2.0 # 0.5 px; 2 px/s is 0.4 % of top speed

## Acceptance 7: the model is the same at every tick rate. The timings hold to a tick at 1/30..1/144 s
## and the trajectory matches a 1/720 s reference to half a pixel.
func _tick_rates() -> void:
	for hull: String in RATE_HULLS:
		for rate: int in RATES:
			var step: float = 1.0 / float(rate)
			var m: Dictionary = _timings(hull, step)
			_note("rates", "%s_%dhz" % [hull, rate], [snappedf(float(m.t90), 0.0001), snappedf(float(m.coast), 0.0001), snappedf(float(m.reversal), 0.0001)])
			t.check(_within_a_tick(m, step), "%s at 1/%d: t90 / coast / reversal within a tick of the prediction" % [hull, rate])
			var worst: Vector2 = _disagreement(hull, step, false)
			_note("rates", "%s_%dhz_disagreement" % [hull, rate], [snappedf(worst.x, 0.0001), snappedf(worst.y, 0.0001)])
			t.check(worst.x <= 0.5 and worst.y <= 2.0, "%s at 1/%d: trajectory within %.4f px / %.4f px/s of the 1/720 s reference" % [hull, rate, worst.x, worst.y])
	var euler: Vector2 = _disagreement("player_seed", 1.0 / 30.0, true)
	_note("rates", "euler_30hz_disagreement", [snappedf(euler.x, 0.01), snappedf(euler.y, 0.01)])
	_note("rates", "euler_30hz_timings_within_a_tick", _within_a_tick(_timings("player_seed", 1.0 / 30.0, true), 1.0 / 30.0))
	t.control("an explicit Euler step at 1/30 s (the trajectory must disagree with the reference)", not _rates_agree("player_seed", 1.0 / 30.0, true))

func _crossing_seconds(hull: String) -> float:
	var w: CombatWorld = make_world()
	w.set_player_hull(hull)
	w.arena.radius = GameTuning.ARENA_RADIUS
	var reach: float = w.arena.radius - 4.0
	w.player.pos = w.arena.center + Vector2(-reach, 0.0)
	w.player.vel = Vector2.ZERO
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	var seconds: float = _seconds_until(w, func() -> bool: return Vector2(w.player.pos).x >= w.arena.center.x + reach - 1.0, 3600)
	release(w)
	return seconds

## Rim to rim along a diameter from rest, in the real 800 px arena (spec §2 / acceptance 5).
func _node_crossing() -> void:
	for hull: String in ["player_seed", "player_lightning_t2_compact", "player_lightning_t2_heavy"]:
		var seconds: float = _crossing_seconds(hull)
		_note("node_crossing", hull + "_s", snappedf(seconds, 0.001))
		t.check(seconds != UNRESOLVED, "%s crosses the node before the 60 s cap" % hull)
	var base: float = float(report.node_crossing.player_seed_s)
	t.check(absf(base - 3.5) <= 0.15, "the base hull (player_seed, authored %d) crosses the node in %.3f s (spec 3.5 +- 0.15)" % [roundi(GameTuning.AUTHORING_BASE_SPEED), base])
	# What P11a's authoring base of 220 would have given the seed (it authors 240).
	GameTuning.set_feel("player_top_speed", GameTuning.FEEL_DEFAULTS.player_top_speed * GameTuning.AUTHORING_BASE_SPEED / 220.0)
	_note("node_crossing", "player_seed_at_base_220_s", snappedf(_crossing_seconds("player_seed"), 0.001))
	GameTuning.set_feel("player_top_speed", GameTuning.FEEL_DEFAULTS.player_top_speed * 0.5)
	var slow: float = _crossing_seconds("player_seed")
	GameTuning.reset_feel()
	t.control("half the top speed (the crossing must leave the 3.5 +- 0.15 s band: %.3f s)" % slow, absf(slow - 3.5) > 0.15)

## One press at cruise: burst length, peak, distance at 1/3 s, and when a second press is accepted.
func _dash_at(step: float) -> Dictionary:
	var w: CombatWorld = make_world()
	var top: float = _to_terminal(w, Vector2.RIGHT, step)
	var start: Vector2 = Vector2(w.player.pos)
	var peak: float = 0.0
	var burst_ticks: int = 0
	var third: int = roundi(1.0 / 3.0 / step)
	var distance: float = 0.0
	w.command.dash = true
	for tick: int in range(1, third + 1):
		w._update_player(step)
		w.command.dash = false # a single press
		peak = maxf(peak, Vector2(w.player.vel).length())
		if burst_ticks == 0 and not w.dashing(): burst_ticks = tick # the tick the burst ran out in
	distance = Vector2(w.player.pos).distance_to(start)
	# Cooldown: first tick a second press is accepted, counted from the first press.
	var ready_tick: int = -1
	for tick: int in range(third + 1, roundi(3.0 / step)):
		w.command.dash = true
		var before: bool = w.dashing()
		w._update_player(step)
		if not before and w.dashing():
			ready_tick = tick
			break
	release(w)
	return {"top": top, "peak_ratio": peak / maxf(1.0, top), "burst_s": float(burst_ticks) * step if burst_ticks > 0 else UNRESOLVED,
		"distance": distance, "cooldown_s": float(ready_tick - 1) * step if ready_tick > 0 else UNRESOLVED}

func _dash() -> void:
	var reference: Dictionary = _dash_at(1.0 / 720.0)
	for rate: int in RATES:
		var step: float = 1.0 / float(rate)
		var d: Dictionary = _dash_at(step)
		var label: String = "%dhz_" % rate
		_note("dash", label + "peak_ratio", snappedf(float(d.peak_ratio), 0.001))
		_note("dash", label + "burst_s", snappedf(float(d.burst_s), 0.0001))
		_note("dash", label + "distance_at_third_s_px", snappedf(float(d.distance), 0.01))
		_note("dash", label + "second_dash_accepted_after_s", snappedf(float(d.cooldown_s), 0.0001))
		t.check(absf(float(d.peak_ratio) - GameTuning.feel("dash.peak_ratio")) <= 0.01, "1/%d: dash peak %.3f x top (spec 2.5)" % [rate, d.peak_ratio])
		t.check(float(d.burst_s) != UNRESOLVED and absf(float(d.burst_s) - GameTuning.feel("dash.burst_s")) <= step + 0.000001, "1/%d: burst %.4f s within a tick of 0.18" % [rate, d.burst_s])
		t.check(float(d.cooldown_s) != UNRESOLVED and absf(float(d.cooldown_s) - GameTuning.feel("dash.cooldown_s")) <= step + 0.000001, "1/%d: second dash accepted %.4f s after the first, within a tick of 1.1" % [rate, d.cooldown_s])
		t.check(absf(float(d.distance) - float(reference.distance)) <= 1.0, "1/%d: %.2f px covered 1/3 s after the press, within 1 px of the 1/720 s run (%.2f)" % [rate, d.distance, reference.distance])

## Slides along the wall with the input held 45 degrees into it IN THE WALL'S FRAME (so the push
## never turns into a head-on stop), leaves, and comes back: two episodes, two contacts.
func _rim_at(step: float, wipe_episode: bool = false) -> Dictionary:
	var w: CombatWorld = make_world()
	var top: float = _to_terminal(w, Vector2.RIGHT, step)
	w.arena.radius = GameTuning.ARENA_RADIUS
	var start_normal: Vector2 = Vector2.from_angle(0.3)
	w.player.pos = w.arena.center + start_normal * (w.arena.radius - 40.0)
	var into: Callable = func() -> Vector2: return w.arena.normal_at(w.player.pos).rotated(PI / 4.0)
	w.player.vel = into.call() * top
	var contacts: Array = []
	w.boundary_contact.connect(func(_at: Vector2) -> void: contacts.append(1))
	var first_ratio: float = UNRESOLVED
	var speed_before: float = 0.0
	for tick: int in range(roundi(2.0 / step)):
		w.command.movement = into.call()
		if wipe_episode: w.player.rim_contact = false
		var was: int = contacts.size()
		var pre: Vector2 = Vector2(w.player.vel)
		w._update_player(step)
		if was == 0 and contacts.size() > 0:
			var normal: Vector2 = w.arena.normal_at(w.player.pos)
			speed_before = pre.length()
			first_ratio = Vector2(w.player.vel).length() / maxf(1.0, (pre - normal * pre.dot(normal)).length())
	var slide_ratio: float = Vector2(w.player.vel).length() / maxf(1.0, top)
	var first_episode: int = contacts.size()
	for tick: int in range(roundi(0.5 / step)):
		w.command.movement = -w.arena.normal_at(w.player.pos)
		w._update_player(step)
	for tick: int in range(roundi(1.0 / step)):
		w.command.movement = into.call()
		w._update_player(step)
	var total: int = contacts.size()
	release(w)
	return {"top": top, "speed_before": speed_before, "first_ratio": first_ratio, "slide_ratio": slide_ratio, "first_episode": first_episode, "total": total}

func _rim() -> void:
	var scale: float = GameTuning.feel("rim.speed_scale")
	for rate: int in RATES:
		var step: float = 1.0 / float(rate)
		var r: Dictionary = _rim_at(step)
		var label: String = "%dhz_" % rate
		_note("rim", label + "first_contact_tangential_ratio", snappedf(float(r.first_ratio), 0.001))
		_note("rim", label + "sliding_speed_ratio_after_2s", snappedf(float(r.slide_ratio), 0.001))
		_note("rim", label + "contact_signals_in_2s_slide", r.first_episode)
		_note("rim", label + "contact_signals_two_episodes", r.total)
		t.check(float(r.speed_before) >= float(r.top) * 0.95, "1/%d: the ship hit the rim at cruise (%.1f of %.1f)" % [rate, r.speed_before, r.top])
		t.check(absf(float(r.first_ratio) - scale) <= 0.02, "1/%d: first contact keeps %.3f of the tangential speed (spec x%.2f once)" % [rate, r.first_ratio, scale])
		t.check(absf(float(r.slide_ratio) - scale) <= 0.02, "1/%d: sliding speed %.3f of top (capped at %.2f, not ground down per tick)" % [rate, r.slide_ratio, scale])
		t.check(int(r.first_episode) == 1, "1/%d: a 2 s slide fires boundary_contact %d time(s), once per episode" % [rate, r.first_episode])
		t.check(int(r.total) == 2, "1/%d: leaving and coming back is a second episode (%d contacts in all)" % [rate, r.total])
	GameTuning.set_feel("rim.speed_scale", 1.0)
	var unscaled: Dictionary = _rim_at(STEP)
	GameTuning.reset_feel()
	t.control("rim scale 1.0 (the first-contact line must fail: %.3f)" % unscaled.first_ratio, absf(float(unscaled.first_ratio) - scale) > 0.02)
	t.control("rim scale 1.0 (the sliding line must fail: %.3f)" % unscaled.slide_ratio, absf(float(unscaled.slide_ratio) - scale) > 0.02)
	var every_tick: Dictionary = _rim_at(STEP, true)
	t.control("episode memory wiped every tick (the once-per-episode line must fail: %d fires)" % every_tick.first_episode, int(every_tick.first_episode) != 1)

func _arc_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, points.size()): total += points[i - 1].distance_to(points[i])
	return total

func _player_trail_px(w: CombatWorld) -> float:
	var trail: Variant = w.trail_pool.trails.get(0)
	return _arc_length(trail.points) if trail != null else 0.0

## Trail arc length at cruise, at the peak of a dash, and after standing still for 2 s.
func _trail_lengths() -> Dictionary:
	var w: CombatWorld = make_world(true) # `_update_trails` returns early without visuals
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	for i: int in range(300): w._physics_process(STEP)
	var cruise: float = _player_trail_px(w)
	var dash_px: float = 0.0
	w.command.dash = true
	for i: int in range(12): # the 0.18 s burst and the tick it runs out in
		w._physics_process(STEP)
		w.command.dash = false
		dash_px = maxf(dash_px, _player_trail_px(w))
	w.command.movement = Vector2.ZERO
	for i: int in range(120): w._physics_process(STEP)
	var out: Dictionary = {"cruise": cruise, "dash": dash_px, "rest": _player_trail_px(w), "rest_speed": Vector2(w.player.vel).length(), "owned": w.trail_pool.trails.has(0)}
	release(w)
	return out

func _trails() -> void:
	var top: float = GameTuning.feel("trail.len_top")
	var dash: float = GameTuning.feel("trail.len_dash")
	var m: Dictionary = _trail_lengths()
	_note("trail", "cruise_px", snappedf(float(m.cruise), 0.1))
	_note("trail", "dash_peak_px", snappedf(float(m.dash), 0.1))
	_note("trail", "after_2s_at_rest_px", snappedf(float(m.rest), 0.1))
	_note("trail", "speed_at_rest", snappedf(float(m.rest_speed), 0.01))
	t.check(bool(m.owned), "the player owns a trail")
	t.check(absf(float(m.cruise) - top) <= top * 0.1, "trail at top speed %.1f px (spec %d +- 10 %%)" % [m.cruise, roundi(top)])
	t.check(absf(float(m.dash) - dash) <= dash * 0.1, "trail at the dash peak %.1f px (spec %d +- 10 %%)" % [m.dash, roundi(dash)])
	t.check(float(m.rest) <= TrailPool.MIN_SAMPLE_DISTANCE, "trail after 2 s at rest %.1f px (spec 0)" % m.rest)
	GameTuning.set_feel("trail.len_top", 1.0e6)
	var uncapped: Dictionary = _trail_lengths()
	GameTuning.reset_feel()
	t.control("no cap at top speed (the cruise line must fail: %.1f px)" % uncapped.cruise, absf(float(uncapped.cruise) - top) > top * 0.1)
	GameTuning.set_feel("trail.len_dash", 1.0e6)
	var uncapped_dash: Dictionary = _trail_lengths()
	GameTuning.reset_feel()
	t.control("no cap in a dash (the dash line must fail: %.1f px)" % uncapped_dash.dash, absf(float(uncapped_dash.dash) - dash) > dash * 0.1)
	# The rest line's control: the same pool fed without a cap, as before M7, keeps its length.
	var pool: TrailPool = TrailPool.new()
	for i: int in range(30): pool.request(0, Vector2(10.0 * i, 0.0), 1.0, 2.0, Color.WHITE)
	for i: int in range(120): pool.request(0, Vector2(290.0, 0.0), 1.0, 2.0, Color.WHITE)
	var kept: float = _arc_length(pool.trails[0].points)
	t.control("a trail with no arc-length cap at rest (the rest line must fail: %.1f px)" % kept, kept > TrailPool.MIN_SAMPLE_DISTANCE)

## Light dropped 80 px behind a player fleeing at top speed, inside the magnet. Seconds to collect.
func _pickup_chase() -> float:
	var w: CombatWorld = make_world()
	w.light_total = GameTuning.capacity(1) * 0.4 # room to collect
	var top: float = _to_terminal(w, Vector2.RIGHT)
	w.player_position = w.player.pos # `_physics_process` starts each tick from this copy
	var behind: Vector2 = Vector2(w.player.pos) - Vector2(minf(80.0, float(w.player.magnet_radius) * 0.8), 0.0)
	w.pickups.append({"pos": behind, "vel": Vector2.ZERO, "element": "neutral", "value": 1.0, "size": 1, "phase": 0.0})
	var seconds: float = UNRESOLVED
	for tick: int in range(1, 121):
		w._physics_process(STEP)
		if w.pickups.is_empty():
			seconds = float(tick) * STEP
			break
	_note("pickup", "chase_top_speed", snappedf(top, 0.01))
	release(w)
	return seconds

func _pickups() -> void:
	var seconds: float = _pickup_chase()
	_note("pickup", "pull_speed", snappedf(maxf(GameTuning.feel("pickup.pull_min"), GameTuning.feel("pickup.pull_ratio") * GameTuning.hull_top_speed(GameTuning.AUTHORING_BASE_SPEED)), 0.01))
	_note("pickup", "caught_fleeing_player_s", snappedf(seconds, 0.0001))
	t.check(seconds != UNRESOLVED, "light reaches a player fleeing at top speed (%.3f s)" % seconds)
	GameTuning.set_feel("pickup.pull_ratio", 0.0) # the flat 330 px/s from before M7
	var flat: float = _pickup_chase()
	GameTuning.reset_feel()
	t.control("pickups at a flat 330 px/s (the fleeing player must outrun them)", flat == UNRESOLVED)

func _spawn(w: CombatWorld, entry: Array, at: Vector2) -> Dictionary:
	var template: ShipDefinition = ShipCatalog.get_ship(str(entry[0]))
	if template == null: return {}
	return w._spawn_named_enemy(str(entry[0]), template.element, template.tier, at, bool(entry[1]), bool(entry[2]))

## The pre-M8 speed model, for the control: the hull's authored speed x 0.45, x 0.85 for a boss.
func _pre_m8_speed(actor: Dictionary) -> float:
	return float(actor.speed) * (0.85 if bool(actor.get("rival", false)) else 0.45)

## The fastest shot any enemy may fire: the largest enemy shot ratio (seekers included, pursuers not).
func _enemy_shot_limit() -> float:
	var ratio: float = 0.0
	for key: String in GameTuning.FEEL_DEFAULTS:
		if key.begins_with("shot.enemy.") and key != "shot.enemy.bay_drone": ratio = maxf(ratio, float(GameTuning.FEEL_DEFAULTS[key]))
	return float(GameTuning.FEEL_DEFAULTS.player_top_speed) * ratio

## Chases a stationary player from 1600 px for 6 s; then the player jumps 1500 px behind it and it
## has to turn round. Top speed, peak turn rate of the HEADING (the velocity's direction, while moving)
## and the fastest non-orbiting enemy shot. `sabotage` is the three controls in one run: the pre-M8
## absolute speed through the ratio key, a 50 rad/s turn limit, and every enemy shot at the player's
## bolt ratio.
func _enemy_run(entry: Array, sabotage: bool) -> Dictionary:
	var w: CombatWorld = make_world()
	w.player_invulnerable = 1.0e9
	var actor: Dictionary = _spawn(w, entry, w.arena.center + Vector2(1600.0, 0.0))
	if actor.is_empty():
		release(w)
		return {}
	var archetype: String = CombatAI.archetype_of(actor)
	var thrusters: float = 1.2 if w._has_ability(actor, "thrusters") else 1.0
	var out: Dictionary = {"archetype": archetype, "pre_m8": _pre_m8_speed(actor) if archetype != "sentry" else 0.0,
		"expected": float(GameTuning.FEEL_DEFAULTS.player_top_speed) * float(GameTuning.FEEL_DEFAULTS["enemy_ratio." + archetype]) * thrusters,
		"turn_limit": float(GameTuning.FEEL_DEFAULTS.get("enemy_turn." + archetype, 0.0)) * thrusters}
	if sabotage:
		GameTuning.set_feel("enemy_ratio." + archetype, float(out.pre_m8) / GameTuning.feel("player_top_speed"))
		GameTuning.set_feel("enemy_turn." + archetype, 50.0)
		for key: String in GameTuning.FEEL_DEFAULTS:
			if key.begins_with("shot.enemy."): GameTuning.set_feel(key, GameTuning.feel("shot.player.bolt"))
	var top: float = 0.0
	var turn: float = 0.0
	var shot: float = 0.0
	var last: Vector2 = Vector2(actor.vel)
	for i: int in range(720):
		if i == 360 and Vector2(actor.vel).length() > 1.0:
			w.player.pos = Vector2(actor.pos) - Vector2(actor.vel).normalized() * 1500.0
			w.player_position = w.player.pos
		w.player_invulnerable = 1.0e9
		w._physics_process(STEP)
		var vel: Vector2 = Vector2(actor.vel)
		top = maxf(top, vel.length())
		if last.length() > 5.0 and vel.length() > 5.0: turn = maxf(turn, absf(last.angle_to(vel)) / STEP)
		last = vel
		for index: int in w.bullets.active_indices:
			if w.bullets.factions[index] != 0 and (w.bullets.flags[index] & Pool.ORBIT) == 0: shot = maxf(shot, w.bullets.velocities[index].length())
	GameTuning.reset_feel()
	release(w)
	out.top = top
	out.turn = turn
	out.shot = shot
	return out

func _top_ok(m: Dictionary) -> bool: return absf(float(m.top) - float(m.expected)) <= maxf(0.01, float(m.expected) * 0.02)
func _turn_ok(m: Dictionary) -> bool: return float(m.turn) <= float(m.turn_limit) * 1.01
func _shot_ok(m: Dictionary) -> bool: return float(m.shot) <= _enemy_shot_limit() * 1.005

## Spec §2/§8: every enemy's top speed is ratio x player_top_speed, at every tier; it turns like a
## unicycle; its shots stay at or below the fastest enemy shot ratio (rule (b)'s other half, in play).
func _enemy_speeds() -> void:
	var fired_controls: int = 0
	var shot_controls_failed: int = 0
	for entry: Array in ENEMY_HULLS:
		var id: String = str(entry[0])
		var m: Dictionary = _enemy_run(entry, false)
		if not t.check(not m.is_empty(), "roster hull %s spawns" % id): continue
		_note("enemy", id + "_top_speed", snappedf(float(m.top), 0.01))
		_note("enemy", id + "_expected_speed", snappedf(float(m.expected), 0.01))
		_note("enemy", id + "_pre_m8_speed", snappedf(float(m.pre_m8), 0.01))
		_note("enemy", id + "_peak_heading_turn_rad_s", snappedf(float(m.turn), 0.01))
		_note("enemy", id + "_fastest_shot", snappedf(float(m.shot), 0.01))
		t.check(_top_ok(m), "%s (%s): top speed %.2f px/s is %.2f x %d +- 2 %% (%.2f)" % [id, m.archetype, m.top, float(m.expected) / float(GameTuning.FEEL_DEFAULTS.player_top_speed), roundi(float(GameTuning.FEEL_DEFAULTS.player_top_speed)), m.expected])
		t.check(_shot_ok(m), "%s: fastest shot %.1f px/s <= the fastest enemy shot ratio (%.1f)" % [id, m.shot, _enemy_shot_limit()])
		if m.archetype == "sentry": continue
		t.check(_turn_ok(m), "%s: heading turns at most %.2f rad/s (limit %.2f)" % [id, m.turn, m.turn_limit])
		var s: Dictionary = _enemy_run(entry, true)
		t.control("%s at its pre-M8 absolute speed %.1f px/s (the speed line must fail: %.2f)" % [id, s.pre_m8, s.top], not _top_ok(s))
		t.control("%s with a 50 rad/s turn limit (the turn line must fail: %.2f)" % [id, s.turn], not _turn_ok(s))
		if float(s.shot) > 0.0:
			fired_controls += 1
			if not _shot_ok(s): shot_controls_failed += 1
	# The shot line's control only exists for a hull that fired in its 12 s, and not for one whose only
	# travelling shot is the void orb (outside the shot rules): count both, and demand several.
	_note("enemy", "shot_controls_fired", fired_controls)
	_note("enemy", "shot_controls_failed", shot_controls_failed)
	t.control("every enemy shot at the player's bolt ratio (the shot line must fail: %d of the %d hulls that fired)" % [shot_controls_failed, fired_controls], shot_controls_failed >= 6)

func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	return 0.0 if n == 0 else (sorted[n / 2] if n % 2 == 1 else 0.5 * (sorted[n / 2 - 1] + sorted[n / 2]))

func _min(values: Array[float]) -> float:
	var low: float = INF
	for v: float in values: low = minf(low, v)
	return low

## Acceptance 4: "The player can disengage from any enemy except a seeker by holding a direction."
## The enemy is already chasing at its own top speed from 320-480 px on a random bearing; the player
## starts at rest and holds one direction up to 60 degrees either side of straight away from it (a
## player running for an exit, not only directly away). Separation gained over 2 s, per seed.
func _disengage_gains(enemy: Array, player: Array) -> Array[float]:
	var gains: Array[float] = []
	for seed: int in range(SEEDS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7000 + seed
		var w: CombatWorld = make_world()
		w._rng.seed = seed
		w.set_player_hull(str(player[0]))
		w.player_invulnerable = 1.0e9
		var bearing: Vector2 = Vector2.from_angle(rng.randf() * TAU)
		var actor: Dictionary = _spawn(w, enemy, w.arena.center + bearing * rng.randf_range(320.0, 480.0))
		if actor.is_empty():
			release(w)
			continue
		actor.aim = -bearing
		actor.vel = -bearing * CombatAI.top_speed(w, actor)
		var flee: Vector2 = (-bearing).rotated(deg_to_rad(rng.randf_range(-60.0, 60.0)))
		var start: float = Vector2(actor.pos).distance_to(w.player.pos)
		for tick: int in range(120):
			w.player_invulnerable = 1.0e9
			if bool(player[1]): w.player.slow = 1.0
			w.command.movement = flee
			w.command.aim = flee
			w._physics_process(STEP)
		gains.append(Vector2(actor.pos).distance_to(w.player.pos) - start)
		release(w)
	return gains

func _disengage() -> void:
	for enemy: Array in DISENGAGE_ENEMIES:
		for player: Array in DISENGAGE_PLAYERS:
			var gains: Array[float] = _disengage_gains(enemy, player)
			var label: String = "%s_vs_%s%s" % [enemy[0], player[0], "_slowed" if bool(player[1]) else ""]
			_note("disengage", label + "_median_px", snappedf(_median(gains), 0.1))
			_note("disengage", label + "_min_px", snappedf(_min(gains), 0.1))
			t.check(gains.size() == SEEDS and _median(gains) > 0.0 and _min(gains) > 0.0, "%s: holding a direction away gains %.1f px median, %.1f px min over 2 s (%d seeds)" % [label, _median(gains), _min(gains), gains.size()])
	GameTuning.set_feel("enemy_ratio.drone", 1.3)
	var caught: Array[float] = _disengage_gains(DISENGAGE_ENEMIES[0], DISENGAGE_PLAYERS[0])
	GameTuning.reset_feel()
	_note("disengage", "control_drone_1.3_median_px", snappedf(_median(caught), 0.1))
	t.control("a drone at 1.3 x the player's speed (the disengage line must fail: median %.1f, min %.1f)" % [_median(caught), _min(caught)], not (_median(caught) > 0.0 and _min(caught) > 0.0))

## A seeker flying at a stationary target 4000 px dead ahead, so all its turning is the weave. After
## 0.5 s to settle: the peak heading offset from the bearing (the weave's amplitude) and the peak
## heading rate, over 3 s. P11a measured the pre-M8 weave at 23.8 rad/s peak at 1/60 and 44.8 at 1/120.
func _weave_at(step: float, per_tick: bool) -> Vector2:
	var w: CombatWorld = make_world()
	w.player_invulnerable = 1.0e9
	w.seeker_weave_per_tick = per_tick
	w.player.pos = w.arena.center + Vector2(4000.0, 0.0)
	w.player_position = w.player.pos
	var index: int = w.bullets.add(w.arena.center, Vector2.RIGHT * GameTuning.projectile_speed(false, "seeker"), 8.0, 0.0, 3.0, 999, 1, 0, Pool.HOMING)
	var amplitude: float = 0.0
	var peak: float = 0.0
	var last: float = w.bullets.velocities[index].angle()
	for i: int in range(roundi(3.5 / step)):
		w.elapsed += step
		w._update_bullets(step)
		var now: float = w.bullets.velocities[index].angle()
		if float(i + 1) * step >= 0.5:
			amplitude = maxf(amplitude, absf(angle_difference((Vector2(w.player.pos) - w.bullets.positions[index]).angle(), now)))
			peak = maxf(peak, absf(angle_difference(last, now)) / step)
		last = now
	release(w)
	return Vector2(amplitude, peak)

func _weave_ok(m: Vector2, reference: Vector2) -> bool: return absf(m.x - reference.x) <= reference.x * 0.02
func _rate_ok(m: Vector2) -> bool: return m.y <= GameTuning.feel("seeker.turn_rate") * 1.01

## Spec §8 and acceptance 7: the seeker weaves by the same amount at every tick rate and never turns
## faster than its limit. The per-tick control is the pre-M8 code path.
func _seeker_weave() -> void:
	var reference: Vector2 = _weave_at(1.0 / 720.0, false)
	_note("seeker", "weave_amplitude_rad_720hz", snappedf(reference.x, 0.0001))
	t.check(absf(reference.x - GameTuning.feel("seeker.weave_amp")) <= GameTuning.feel("seeker.weave_amp") * 0.05, "the 1/720 s weave amplitude %.4f rad is the tuned %.2f +- 5 %%" % [reference.x, GameTuning.feel("seeker.weave_amp")])
	for rate: int in RATES:
		var m: Vector2 = _weave_at(1.0 / float(rate), false)
		_note("seeker", "weave_amplitude_rad_%dhz" % rate, snappedf(m.x, 0.0001))
		_note("seeker", "peak_turn_rad_s_%dhz" % rate, snappedf(m.y, 0.0001))
		t.check(_weave_ok(m, reference), "1/%d: weave amplitude %.4f rad within 2 %% of the 1/720 s run (%.4f)" % [rate, m.x, reference.x])
		t.check(_rate_ok(m), "1/%d: peak turn %.3f rad/s <= seeker.turn_rate %.2f" % [rate, m.y, GameTuning.feel("seeker.turn_rate")])
	var per_tick: Vector2 = _weave_at(1.0 / 144.0, true)
	_note("seeker", "control_per_tick_144hz", [snappedf(per_tick.x, 0.0001), snappedf(per_tick.y, 0.01)])
	t.control("the pre-M8 per-tick weave at 1/144 (the amplitude line must fail: %.4f rad)" % per_tick.x, not _weave_ok(per_tick, reference))
	t.control("the pre-M8 per-tick weave at 1/144 (the turn-rate line must fail: %.2f rad/s)" % per_tick.y, not _rate_ok(per_tick))

## One enemy seeker launched at the player's CURRENT position (a regular's full-information aim) while
## the player charges the launcher at top speed, `geometry` of 20 headings within 30 degrees of
## head-on. Straight holds the line; weave adds a 0.5 s sine of lateral input at 1.2 x the forward.
## A hit is the seeker coming within 16 px (core plus shot radius) or being consumed before its life.
func _seeker_hit(launch_range: float, geometry: int, weave: bool) -> bool:
	var w: CombatWorld = make_world()
	w.player_invulnerable = 1.0e9
	var heading: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(-30.0 + 60.0 * float(geometry) / float(SEEDS - 1)))
	w.player.vel = heading * w.player_top_speed()
	w.player_position = w.player.pos
	var launcher: Vector2 = w.arena.center + Vector2(launch_range, 0.0)
	var index: int = w.bullets.add(launcher, (Vector2(w.player.pos) - launcher).normalized() * GameTuning.projectile_speed(false, "seeker"), 4.0, 1.0, 3.0, 999, 1, 0, Pool.HOMING)
	var hit: bool = false
	for tick: int in range(180):
		var lateral: float = sin(float(tick) * STEP * TAU / 0.5) if weave else 0.0
		w.command.movement = (heading + heading.orthogonal() * lateral * 1.2).normalized()
		w.command.aim = heading
		w.player_invulnerable = 1.0e9
		w._physics_process(STEP)
		if not w.bullets.active_indices.has(index) or Vector2(w.bullets.positions[index]).distance_to(w.player.pos) < 16.0:
			hit = true
			break
	release(w)
	return hit

func _seeker_hit_counts() -> Dictionary:
	var out: Dictionary = {}
	for launch_range: int in [250, 350, 500]:
		var straight: int = 0
		var weaving: int = 0
		for g: int in range(SEEDS):
			if _seeker_hit(float(launch_range), g, false): straight += 1
			if _seeker_hit(float(launch_range), g, true): weaving += 1
		out[launch_range] = Vector2i(straight, weaving)
	return out

func _straight_ok(c: Dictionary) -> bool: return c[500].x >= roundi(SEEDS * 0.9)
func _weave_beats_ok(c: Dictionary) -> bool: return float(c[350].y + c[500].y) <= 0.4 * float(c[350].x + c[500].x)

## Spec §8: seekers are "the one thing you can't simply outrun ... keep their turn rate limited so
## weaving beats them". Flying straight into one from 500 px gets you hit >= 90 % of the time; from
## 350 and 500 px a weave is hit at most 40 % as often as a straight line. At 250 px nothing can dodge
## in time, so that range is reported only. Controls: a 0.3 rad/s seeker cannot hit a straight line;
## an 18 rad/s one follows the weave.
func _seeker_hits() -> void:
	var c: Dictionary = _seeker_hit_counts()
	for launch_range: int in c: _note("seeker", "hits_of_%d_at_%dpx_straight_weave" % [SEEDS, launch_range], [c[launch_range].x, c[launch_range].y])
	t.check(_straight_ok(c), "a straight charge from 500 px is hit %d / %d times (>= 90 %%)" % [c[500].x, SEEDS])
	t.check(_weave_beats_ok(c), "from 350 and 500 px a weave is hit %d times against %d for a straight line (<= 40 %%)" % [c[350].y + c[500].y, c[350].x + c[500].x])
	GameTuning.set_feel("seeker.turn_rate", 0.3)
	var sluggish: Dictionary = _seeker_hit_counts()
	GameTuning.set_feel("seeker.turn_rate", 18.0)
	var agile: Dictionary = _seeker_hit_counts()
	GameTuning.reset_feel()
	t.control("a 0.3 rad/s seeker (the straight line must fail: %d / %d)" % [sluggish[500].x, SEEDS], not _straight_ok(sluggish))
	t.control("an 18 rad/s seeker (the weave line must fail: %d vs %d)" % [agile[350].y + agile[500].y, agile[350].x + agile[500].x], not _weave_beats_ok(agile))

## Seconds [press -> commit, commit -> the velocity has 40 px/s along a new perpendicular input],
## stepped through `_physics_process` (the warp's deadlines run on the sim_q clock it advances).
func _warp_timing() -> Array[float]:
	var w: CombatWorld = make_world()
	w.arena.radius = GameTuning.ARENA_RADIUS
	w.arena.sealed = false # make_world sealed it
	w.arena.exits.clear()
	w.arena.exits.append(Vector2i.RIGHT) # typed Array[Vector2i]: an untyped literal cannot be assigned
	w.player_position = w.arena.center + Vector2(w.arena.radius - 4.0, 0.0)
	w.player.vel = Vector2(200.0, 0.0)
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	w.warp_committed.connect(func(_dir: Vector2i) -> void: w.confirm_warp_swap())
	var result: Array[float] = [UNRESOLVED, UNRESOLVED]
	for tick: int in range(1, 241):
		w._physics_process(STEP)
		if w.warp_locked():
			result[0] = tick * STEP
			break
	if result[0] != UNRESOLVED:
		w.command.movement = Vector2.UP
		for tick: int in range(1, 601):
			w._physics_process(STEP)
			if Vector2(w.player.vel).dot(Vector2.UP) > 40.0:
				result[1] = tick * STEP
				break
	release(w)
	return result

func _warp_locked() -> void:
	var timing: Array[float] = _warp_timing()
	_note("warp", "push_to_commit_s", snappedf(timing[0], 0.0001))
	_note("warp", "commit_to_control_s", snappedf(timing[1], 0.0001))
	t.check(absf(timing[0] - 0.20) <= STEP * 0.5, "a press into an open membrane commits after 0.20 s (%.4f)" % timing[0])
	t.check(timing[1] != UNRESOLVED and timing[1] <= 0.6, "the ship answers the stick %.4f s after the commit (<= 0.6 s)" % timing[1])
	GameTuning.set_feel("warp.break_s", 0.12)
	GameTuning.set_feel("warp.warp_s", 0.90) # the pre-M9 ZOOM_IN + TRAVEL + ARRIVAL + ZOOM_OUT
	GameTuning.set_feel("warp.push_s", 0.30) # the pre-M9 push
	var old: Array[float] = _warp_timing()
	GameTuning.reset_feel()
	_note("warp", "control_pre_m9_commit_to_control_s", snappedf(old[1], 0.0001))
	t.control("the pre-M9 0.30 s push (%.4f s)" % old[0], absf(old[0] - 0.20) > STEP * 0.5)
	t.control("the pre-M9 1.02 s locked window (%.4f s)" % old[1], old[1] == UNRESOLVED or old[1] > 0.6)

## A ship with no speed can never reach 90 % of a positive target. If this came back as a number,
## every timing above could be a cap dressed up as a measurement.
func _unresolved_control() -> void:
	var w: CombatWorld = make_world()
	w.player.speed = 0.0
	w.command.movement = Vector2.RIGHT
	var seconds: float = _seconds_until(w, func() -> bool: return Vector2(w.player.vel).length() >= 100.0, 120)
	t.control("a ship that cannot move (the timing must come back UNRESOLVED, not as a number)", seconds == UNRESOLVED)
	release(w)
