extends SceneTree
## Camera/movement spec §3-§4 (M7; first written for v0.3 §13/§26, plan P6 items 1+2): momentum
## handling and dash, on ROSTER hulls. Drives `CombatWorld` directly (no main.gd), the same pattern
## `tests/combat_tests.gd` uses. The timings themselves, at four tick rates, are gated in
## `movement_feel_test.gd`; this file keeps the properties that are not timings.
##
## Retired by M7, with their replacements:
##   the `ROLES` speed/accel/drag literals and `_set_role`   -> roster hulls; movement reads
##       `GameTuning.movement_taus(role)` and `player_top_speed()`, not per-hull accel/drag
##   the Compact turn-radius proxy (<= 0.5x standard)          -> drift at 0.15 s and the peak speed
##       in a turn (movement_feel_test); the radius was a property of the old v^2/accel model
##   "second dash at ~1.19 s refused / ~1.21 s allowed"       -> ticks 65 / 66 of the 1.1 s cooldown

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0
const ROLE_HULLS: Dictionary = {"compact": "player_lightning_t2_compact", "standard": "player_seed", "heavy": "player_lightning_t2_heavy"}

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("HANDLING")
	GameTuning.reset_feel()
	_terminal_speed()
	_reversal_order()
	_dash_distance()
	_dash_cooldown_gate()
	_dash_not_invulnerable()
	_rim_friction()
	await process_frame
	t.finish(self)

func make_world(hull: String = "player_seed") -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	t.check(w.set_player_hull(hull), "roster hull %s loads" % hull)
	# These tests are about the movement/dash PHYSICS, not the warp (that is
	# tests/warp_test.gd) or the rim (its own test below sets a tight arena on
	# purpose) - push the wall far out so a multi-second full-speed run never
	# accidentally engages the rim's exits or clamps against it mid-measurement.
	w.arena.sealed = true
	w.arena.radius = 100000.0
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## Terminal speed IS the spec's top speed for the hull's authored speed: 460 x speed / base.
func _terminal_speed() -> void:
	for role: String in ROLE_HULLS:
		var w: CombatWorld = make_world(ROLE_HULLS[role])
		w.command.movement = Vector2.RIGHT
		w.command.aim = Vector2.RIGHT
		for i: int in range(180): w._update_player(STEP) # 3 s, dozens of time constants
		var terminal: float = Vector2(w.player.vel).length()
		var expected: float = GameTuning.feel("player_top_speed") * float(w.player.speed) / GameTuning.AUTHORING_BASE_SPEED
		var error: float = absf(terminal - expected) / expected
		t.check(error <= 0.005, "%s terminal speed %.2f within 0.5%% of %.2f (error %.4f)" % [role, terminal, expected, error])
		release(w)

## 180 degree reversal to 90 % of top the other way, ordered compact < standard < heavy.
func _reversal_order() -> void:
	var reversal_ticks: Dictionary = {}
	for role: String in ROLE_HULLS:
		var w: CombatWorld = make_world(ROLE_HULLS[role])
		var top: float = w.player_top_speed()
		w.command.movement = Vector2.RIGHT
		for i: int in range(180): w._update_player(STEP)
		w.command.movement = Vector2.LEFT
		var ticks: int = 0
		while Vector2(w.player.vel).x > -top * 0.9 and ticks < 600:
			w._update_player(STEP)
			ticks += 1
		reversal_ticks[role] = ticks
		release(w)
	t.check(reversal_ticks.compact < reversal_ticks.standard and reversal_ticks.standard < reversal_ticks.heavy,
		"180deg reversal ticks ordered compact(%d) < standard(%d) < heavy(%d)" % [reversal_ticks.compact, reversal_ticks.standard, reversal_ticks.heavy])

## From rest, one press: the burst covers peak x top x burst (quantised to 1/720 s), plus the
## sliver of its last tick that the approach model integrates.
func _dash_distance() -> void:
	var w: CombatWorld = make_world()
	w.player.pos = Vector2(1000, 500)
	w.player.vel = Vector2.ZERO
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	var start: Vector2 = Vector2(w.player.pos)
	var ticks: int = 0
	w.command.dash = true
	while ticks < 60:
		w._update_player(STEP)
		w.command.dash = false # single press, like a real button edge
		ticks += 1
		if not w.dashing(): break
	var distance: float = Vector2(w.player.pos).distance_to(start)
	var burst_q: int = roundi(GameTuning.feel("dash.burst_s") * CombatWorld.SIM_Q_PER_SECOND)
	var expected: float = w.player_top_speed() * GameTuning.feel("dash.peak_ratio") * float(burst_q) / CombatWorld.SIM_Q_PER_SECOND
	var error: float = absf(distance - expected) / expected
	t.check(error <= 0.03, "Dash distance %.1fpx within 3%% of %.1fpx over %d ticks (error %.4f)" % [distance, expected, ticks, error])
	release(w)

## 1.1 s of cooldown is 66 ticks at 1/60 s: a press on tick 65 after the first is refused, one on
## tick 66 accepted.
func _dash_cooldown_gate() -> void:
	var w: CombatWorld = make_world()
	w.player.pos = Vector2(1000, 500)
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	w.command.dash = true
	w._update_player(STEP) # the press
	w.command.dash = false
	for i: int in range(64): w._update_player(STEP) # ticks 1..64 after the press
	w.command.dash = true
	w._update_player(STEP) # tick 65 (~1.083 s)
	t.check(not w.dashing(), "A second dash on tick 65 (~1.083 s) is refused (%.3f of the cooldown elapsed)" % w.dash_ready_fraction())
	w._update_player(STEP) # tick 66 (1.1 s)
	t.check(w.dashing(), "A second dash on tick 66 (1.1 s) is allowed (cooldown elapsed)")
	release(w)

## "Not invulnerable" (spec §4): a bullet on the core mid-dash still damages.
## Negative control: force `player_invulnerable` on and the SAME check must
## now fail - proving the instrument can actually tell the difference,
## instead of dash accidentally already being a no-op on damage for some
## other reason.
func _dash_not_invulnerable() -> void:
	var w: CombatWorld = make_world()
	w.player.dash_burst_q = 60 # mid-burst
	w.player_invulnerable = 0.0
	w._rebuild_actor_grid()
	var before: float = w.light_total
	w.bullets.add(w.player.pos, Vector2.ZERO, -1.0, 10.0, 3.0, 999, 1, 0)
	w._update_bullets(STEP)
	var hit: bool = w.light_total < before
	t.check(w.dashing() and hit, "A bullet on the core mid-dash still deals damage")
	w.player.dash_burst_q = 60
	w.player_invulnerable = 5.0
	w._rebuild_actor_grid()
	var before2: float = w.light_total
	w.bullets.add(w.player.pos, Vector2.ZERO, -1.0, 10.0, 3.0, 999, 1, 0)
	w._update_bullets(STEP)
	var blocked: bool = w.light_total == before2
	t.control("mid-dash damage check with invulnerability forced on", blocked)
	release(w)

## Rim contact: the velocity component INTO the wall is removed and the tangential component kept
## (scaled; the scale itself is gated in movement_feel_test), not just the position clamped.
func _rim_friction() -> void:
	var w: CombatWorld = make_world()
	w.arena.radius = GameTuning.ARENA_RADIUS # this test IS about the rim; make_world widened it for the others
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 2.0, 40.0) # make_world sealed the rim, so no exit can engage
	w.player.vel = Vector2(400.0, 150.0) # a genuine mix of radial (into the wall) and tangential
	w.command.movement = Vector2.ZERO
	w._update_player(STEP)
	var normal: Vector2 = w.arena.normal_at(w.player.pos)
	var into_wall: float = Vector2(w.player.vel).dot(normal)
	t.check(into_wall <= 0.5, "Rim contact removes the velocity component into the wall (residual %.2f)" % into_wall)
	var tangential: float = (Vector2(w.player.vel) - normal * into_wall).length()
	t.check(tangential > 1.0, "Rim contact keeps most of the tangential component instead of zeroing all velocity")
	release(w)
