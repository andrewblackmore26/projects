extends SceneTree
## M10: feel events, hitstop and screen shake, measured. Each line has a control that must fail:
## - the sim emits `feel_event` at its sites (player hit, dash, kill + combo step, pickup);
## - a player hit freezes the sim for GameTuning.hitstop_ticks(&"player_hit") ticks;
## - shake follows spec §6.5: full amplitude at once, gone after its duration, the MAX of
##   concurrent events and never the sum, scaled by the setting and zero under reduced motion;
## - shake is deterministic;
## - the compositor applies shake to what is drawn, but `screen_to_world` never sees it.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0
var t: RefCounted
var events: Array[StringName] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("FEEL EVENTS")
	GameTuning.reset_feel()
	_emit_sites()
	_hitstop_from_hit()
	_shake_envelope()
	_shake_settings()
	_shake_determinism()
	await _shake_excluded_from_aim()
	GameTuning.reset_feel()
	await process_frame
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	w.arena.exits.clear()
	w.feel_event.connect(func(kind: StringName, _at: Vector2, _m: float, _id: int) -> void: events.append(kind))
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _emit_sites() -> void:
	var w: CombatWorld = make_world()
	events.clear()
	w._damage_actor(w.player, 5.0, -1, 1)
	t.check(&"player_hit" in events, "A hit on the player emits player_hit (saw %s)" % str(events))
	while w.hitstop_remaining > 0: w._physics_process(STEP)
	events.clear()
	w.command.movement = Vector2.RIGHT
	w.command.dash = true
	w._physics_process(STEP)
	w.command.dash = false
	t.check(&"dash" in events, "Starting a dash emits dash (saw %s)" % str(events))
	events.clear()
	var enemy: Dictionary = w._spawn_enemy("fire", 1, w.arena.center + Vector2(300, 0), false)
	enemy.invulnerable = 0.0
	w._damage_actor(enemy, 1.0e6, 0, 0)
	t.check(&"enemy_kill" in events and &"combo_step" in events, "Killing an enemy emits enemy_kill and combo_step (saw %s)" % str(events))
	t.check(w.hitstop_remaining == 0, "An ordinary kill requests no hitstop (remaining %d)" % w.hitstop_remaining)
	events.clear()
	w.pickups.append({"pos": Vector2(w.player.pos), "vel": Vector2.ZERO, "element": "fire", "value": 5.0, "size": 5, "phase": 0.0})
	w.light_total = 40.0
	w._physics_process(STEP)
	t.check(&"pickup_collect" in events, "Absorbing a pickup emits pickup_collect (saw %s)" % str(events))
	events.clear()
	w.player_invulnerable = 5.0
	w._damage_actor(w.player, 5.0, -1, 1)
	t.control("a hit on an invulnerable player, which is no hit", not (&"player_hit" in events))
	release(w)

## Moves the player, lands a hit (or not), and reports how many steps the sim stood still after it.
func _frozen_after_hit(invulnerable: bool) -> int:
	var w: CombatWorld = make_world()
	w.command.movement = Vector2.RIGHT
	for i: int in range(20): w._physics_process(STEP)
	if invulnerable: w.player_invulnerable = 5.0
	var tick: int = w.tick
	var at: Vector2 = Vector2(w.player.pos)
	w._damage_actor(w.player, 5.0, -1, 1)
	var frozen: int = 0
	for i: int in range(20):
		w._physics_process(STEP)
		if w.tick != tick or Vector2(w.player.pos) != at: break
		frozen += 1
	release(w)
	return frozen

func _hitstop_from_hit() -> void:
	var want: int = GameTuning.hitstop_ticks(&"player_hit")
	var frozen: int = _frozen_after_hit(false)
	print("measure: a player hit froze the sim for %d ticks (hitstop.player_hit = %d)" % [frozen, want])
	t.check(want == 4 and frozen == want, "A player hit freezes the sim for exactly %d ticks (measured %d)" % [want, frozen])
	t.control("no hitstop requested (the hit never lands)", _frozen_after_hit(true) != want)

## Amplitude after each of `steps` steps, from the events given.
func _envelope(kinds: Array[StringName], steps: int) -> Array[float]:
	var shake: ScreenShake = ScreenShake.new()
	for kind: StringName in kinds: shake.add(kind)
	var out: Array[float] = []
	for i: int in range(steps):
		out.append(shake.amplitude())
		shake.step(STEP)
	return out

func _shake_envelope() -> void:
	var hit: Array[float] = _envelope([&"player_hit"], 10)
	print("measure: hit shake amplitude by tick %s" % str(hit))
	t.check(is_equal_approx(hit[0], 4.0), "A player hit shakes at 4 px at once (measured %.3f)" % hit[0])
	# 0.12 s is 7.2 ticks: tick 7 (0.117 s) still carries a sliver, tick 8 (0.133 s) nothing.
	t.check(hit[8] == 0.0 and hit[7] > 0.0, "and is gone by 0.12 s (tick 8: %.4f, tick 7: %.4f)" % [hit[8], hit[7]])
	var both: float = _envelope([&"player_hit", &"dash"], 1)[0]
	t.check(is_equal_approx(both, 4.0), "A hit during a dash shakes at the max, 4 px, not the sum (measured %.3f)" % both)
	t.control("a regression in place of the hit, 7 px", not is_equal_approx(_envelope([&"regression", &"dash"], 1)[0], 4.0))
	var boss: Array[float] = _envelope([&"boss_kill"], 33)
	t.check(is_equal_approx(boss[0], 10.0) and boss[15] < 3.0 and boss[29] > 0.0 and boss[32] == 0.0, "A boss death shakes 10 px, decaying (%.2f at 0.25 s), over 0.5 s (%.2f, %.4f, %.2f)" % [boss[15], boss[0], boss[29], boss[32]])
	t.control("a player hit in place of the boss death", is_equal_approx(_envelope([&"player_hit"], 1)[0], 10.0) == false)

func _shake_settings() -> void:
	var shake: ScreenShake = ScreenShake.new()
	shake.add(&"regression")
	shake.intensity = 0.5
	var half: float = shake.amplitude()
	shake.reduced_motion = true
	var reduced: float = shake.amplitude()
	shake.step(STEP)
	print("measure: regression shake at screen_shake 0.5 = %.2f px, under reduced motion = %.2f px" % [half, reduced])
	t.check(is_equal_approx(half, 3.5), "screen_shake 0.5 halves the 7 px regression shake (measured %.2f)" % half)
	t.check(reduced == 0.0 and shake.offset == Vector2.ZERO, "Reduced motion zeroes the shake (measured %.2f)" % reduced)
	shake.reduced_motion = false
	t.control("reduced motion off again", shake.amplitude() > 0.0)

func _offsets(extra_first_step: bool) -> Array[Vector2]:
	var shake: ScreenShake = ScreenShake.new()
	if extra_first_step: shake.step(STEP)
	shake.add(&"boss_kill")
	var out: Array[Vector2] = []
	for i: int in range(20):
		shake.step(STEP)
		out.append(shake.offset)
	return out

func _shake_determinism() -> void:
	var first: Array[Vector2] = _offsets(false)
	t.check(first == _offsets(false) and first[0] != Vector2.ZERO, "The same events shake identically twice (first offset %s)" % str(first[0]))
	t.control("the noise one step out of phase", first != _offsets(true))

func _shake_excluded_from_aim() -> void:
	var scene: Node2D = Node2D.new()
	root.add_child(scene)
	var w: CombatWorld = World.new()
	scene.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	w.arena.exits.clear()
	var compositor: CombatCompositor = CombatCompositor.new()
	scene.add_child(compositor)
	compositor.attach(w)
	compositor.set_process(false)
	w.feel_event.emit(&"boss_kill", w.player_position, 1.0, 1)
	w._physics_process(STEP)
	compositor._update_camera()
	var target: Vector2 = w.player_position + Vector2(120, -70)
	var mouse: Vector2 = compositor.world_to_screen(target)
	var aimed: Vector2 = compositor.screen_to_world(mouse)
	var leaked: Vector2 = compositor.background_viewport.canvas_transform.affine_inverse() * mouse
	print("measure: shake offset %s rot %.4f; screen_to_world error %.4f px; through the drawn transform %.2f px" % [str(compositor.view_shake_offset), compositor.view_shake_rotation, aimed.distance_to(target), leaked.distance_to(target)])
	t.check(compositor.view_shake_offset.length() > 1.0, "A boss kill shakes the view (%.2f px)" % compositor.view_shake_offset.length())
	t.check(aimed.distance_to(target) < 0.001, "screen_to_world ignores the shake: the aim point comes back exact (%.4f px)" % aimed.distance_to(target))
	t.check(compositor.foreground.transform.is_equal_approx(compositor.background_viewport.canvas_transform), "Both stages draw with the same shaken transform")
	t.control("shake leaking into aim (the drawn transform inverted)", leaked.distance_to(target) >= 0.5)
	compositor.detach()
	await process_frame
	w.queue_free()
	scene.queue_free()
