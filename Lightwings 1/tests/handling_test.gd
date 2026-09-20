extends SceneTree
## Spec v0.3 §13/§26, plan P6 item 1+2: momentum handling and dash.
## Drives `CombatWorld` directly (no main.gd), the same pattern
## `tests/combat_tests.gd` uses.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("HANDLING")
	_terminal_speed()
	_reversal_and_turn_radius()
	_dash_distance()
	_dash_cooldown_gate()
	_dash_not_invulnerable()
	_rim_friction()
	await process_frame
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	# These tests are about the movement/dash PHYSICS, not the warp (that is
	# tests/warp_test.gd) or the rim (its own test below sets a tight arena on
	# purpose) - push the wall far out so a multi-second full-speed run never
	# accidentally engages a membrane or clamps against it mid-measurement.
	w.arena.exits.clear()
	w.arena.radius = 100000.0
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## Sets the player's momentum constants directly (compact/standard/heavy, as
## tuned in ship_generator.gd's `_base_stats`) rather than going through a
## specific hull id - this is a test of the PHYSICS model, not hull picking
## (the roster's own role assignment is covered by ship_roster_test.gd).
func _set_role(w: CombatWorld, speed: float, accel: float, drag: float) -> void:
	w.player.speed = speed
	w.player.accel = accel
	w.player.drag = drag
	w.player.vel = Vector2.ZERO

const ROLES: Dictionary = {"compact": [300.0, 4800.0, 16.0], "standard": [240.0, 1200.0, 5.0], "heavy": [200.0, 700.0, 3.5]}

func _terminal_speed() -> void:
	for role: String in ROLES:
		var w: CombatWorld = make_world()
		var stats: Array = ROLES[role]
		_set_role(w, stats[0], stats[1], stats[2])
		w.command.movement = Vector2.RIGHT
		w.command.aim = Vector2.RIGHT
		for i: int in range(180): w._update_player(STEP) # 3s, well past the ~0.12-0.29s time constant
		var terminal: float = Vector2(w.player.vel).length()
		var error: float = absf(terminal - stats[0]) / stats[0]
		t.check(error <= 0.02, "%s terminal speed %.2f within 2%% of %.1f (error %.3f)" % [role, terminal, stats[0], error])
		release(w)

## 180 deg reversal time (ordered compact < standard < heavy) and a compact
## 90 deg turn radius <=0.5x standard's. Both measured, not hand-derived from
## the accel/drag constants - "measure, don't assert" (tasks/lessons.md).
func _reversal_and_turn_radius() -> void:
	var reversal_ticks: Dictionary = {}
	var turn_radius: Dictionary = {}
	for role: String in ROLES:
		var stats: Array = ROLES[role]
		# Reversal: run to terminal speed moving RIGHT, then command LEFT and
		# count ticks until velocity has actually reversed direction.
		var w: CombatWorld = make_world()
		_set_role(w, stats[0], stats[1], stats[2])
		w.command.movement = Vector2.RIGHT
		for i: int in range(180): w._update_player(STEP)
		w.command.movement = Vector2.LEFT
		var ticks: int = 0
		while Vector2(w.player.vel).x > -stats[0] * 0.5 and ticks < 600:
			w._update_player(STEP)
			ticks += 1
		reversal_ticks[role] = ticks
		release(w)
		# Turn radius proxy: run to terminal speed moving RIGHT, then command
		# UP and measure the lateral (perpendicular-to-original-heading)
		# distance travelled before velocity direction is within 5 degrees of
		# the new target - a tighter hull sweeps that arc over less ground.
		var w2: CombatWorld = make_world()
		_set_role(w2, stats[0], stats[1], stats[2])
		w2.command.movement = Vector2.RIGHT
		for i: int in range(180): w2._update_player(STEP)
		var start: Vector2 = Vector2(w2.player.pos)
		w2.command.movement = Vector2.UP
		var turn_ticks: int = 0
		while Vector2(w2.player.vel).normalized().dot(Vector2.UP) < 0.9962 and turn_ticks < 600: # cos(5deg)
			w2._update_player(STEP)
			turn_ticks += 1
		turn_radius[role] = absf(Vector2(w2.player.pos).y - start.y)
		release(w2)
	t.check(reversal_ticks.compact < reversal_ticks.standard and reversal_ticks.standard < reversal_ticks.heavy,
		"180deg reversal ticks ordered compact(%d) < standard(%d) < heavy(%d)" % [reversal_ticks.compact, reversal_ticks.standard, reversal_ticks.heavy])
	t.check(float(turn_radius.compact) <= float(turn_radius.standard) * 0.5,
		"Compact 90deg turn radius proxy %.1fpx <= 0.5x standard's %.1fpx" % [turn_radius.compact, turn_radius.standard])

func _dash_distance() -> void:
	var w: CombatWorld = make_world()
	w.player.pos = Vector2(1000, 500)
	w.player.vel = Vector2.ZERO
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	w.command.dash = true
	var start: Vector2 = Vector2(w.player.pos)
	var ticks: int = ceili(CombatWorld.DASH_BURST_SECONDS / STEP) + 1
	for i: int in range(ticks):
		w.command.dash = i == 0 # single press, like a real button edge
		w._update_player(STEP)
	var distance: float = Vector2(w.player.pos).distance_to(start)
	var expected: float = w.player.speed * CombatWorld.DASH_SPEED_MULT * CombatWorld.DASH_BURST_SECONDS
	var error: float = absf(distance - expected) / expected
	t.check(error <= 0.15, "Dash distance %.1fpx within 15%% of %.1fpx (error %.3f)" % [distance, expected, error])

func _dash_cooldown_gate() -> void:
	var w: CombatWorld = make_world()
	w.player.pos = Vector2(1000, 500)
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	w.command.dash = true
	w._update_player(STEP) # trigger tick (tick 1 since trigger): dash_cooldown becomes exactly 1.2s here
	w.command.dash = false
	# 1.2s of cooldown is EXACTLY 72 ticks at 1/60s - test one tick either side
	# of that exact boundary (~1.183s and ~1.217s, close to the spec's own
	# 1.19s/1.21s examples) rather than landing exactly on it, where a floating
	# point tie could go either way.
	for i: int in range(69): w._update_player(STEP) # now at tick 70 since trigger (~1.167s)
	w.command.dash = true
	w._update_player(STEP) # attempt at tick 71 (~1.183s)
	t.check(float(w.player.dash_timer) <= 0.0, "A second dash at ~1.19s is refused (still on cooldown, remaining %.4fs)" % float(w.player.dash_cooldown))
	w.command.dash = false
	for i: int in range(1): w._update_player(STEP) # tick 72 (exactly 1.2s - cooldown reaches 0 here)
	w.command.dash = true
	w._update_player(STEP) # attempt at tick 73 (~1.217s)
	t.check(float(w.player.dash_timer) > 0.0, "A second dash at ~1.21s is allowed (cooldown elapsed)")
	release(w)

## "Not invulnerable" (spec §13): a bullet on the core mid-dash still damages.
## Negative control: force `player_invulnerable` on and the SAME check must
## now fail - proving the instrument can actually tell the difference,
## instead of dash accidentally already being a no-op on damage for some
## other reason.
func _dash_not_invulnerable() -> void:
	var w: CombatWorld = make_world()
	w.player.dash_timer = 0.1 # mid-burst
	w.player_invulnerable = 0.0
	w._rebuild_actor_grid()
	var before: float = w.light_total
	w.bullets.add(w.player.pos, Vector2.ZERO, -1.0, 10.0, 3.0, 999, 1, 0)
	w._update_bullets(STEP)
	var hit: bool = w.light_total < before
	t.check(hit, "A bullet on the core mid-dash still deals damage")
	w.player.dash_timer = 0.1
	w.player_invulnerable = 5.0
	w._rebuild_actor_grid()
	var before2: float = w.light_total
	w.bullets.add(w.player.pos, Vector2.ZERO, -1.0, 10.0, 3.0, 999, 1, 0)
	w._update_bullets(STEP)
	var blocked: bool = w.light_total == before2
	t.control("mid-dash damage check with invulnerability forced on", blocked)
	release(w)

## Rim contact (spec §13/plan item 1): the velocity component INTO the wall
## is removed and the tangential component scaled, not just the position
## clamped.
func _rim_friction() -> void:
	var w: CombatWorld = make_world()
	w.arena.radius = GameTuning.ARENA_RADIUS # this test IS about the rim; make_world widened it for the others
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 2.0, 40.0) # off-axis: away from any membrane opening
	w.player.vel = Vector2(400.0, 150.0) # a genuine mix of radial (into the wall) and tangential
	w.command.movement = Vector2.ZERO
	w._update_player(STEP)
	var normal: Vector2 = w.arena.normal_at(w.player.pos)
	var into_wall: float = Vector2(w.player.vel).dot(normal)
	t.check(into_wall <= 0.5, "Rim contact removes the velocity component into the wall (residual %.2f)" % into_wall)
	var tangential: float = (Vector2(w.player.vel) - normal * into_wall).length()
	t.check(tangential > 1.0, "Rim contact keeps most of the tangential component instead of zeroing all velocity")
	release(w)
