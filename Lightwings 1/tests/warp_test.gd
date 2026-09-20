extends SceneTree
## Spec v0.3 §12, plan P6 item 5: the warp state machine, sim-side.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("WARP")
	_release_before_threshold_never_commits()
	_hold_to_threshold_commits()
	_projectiles_discarded_at_commit()
	_no_damage_during_lock()
	_entry_speed_and_total_locked_time()
	_reduced_warp_timing()
	_missing_swap_springs_back()
	_determinism()
	await process_frame
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2.ZERO)
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## Places the player pressing straight into the RIGHT membrane, `ticks`
## physics steps in, without ever letting go.
func _push_toward_right(w: CombatWorld, ticks: int) -> void:
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 4.0, 0.0)
	w.player.vel = Vector2(200.0, 0.0)
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	for i: int in range(ticks): w._update_player(STEP)

func _release_before_threshold_never_commits() -> void:
	var w: CombatWorld = make_world()
	var push_ticks: int = floori(0.29 / STEP)
	_push_toward_right(w, push_ticks)
	var reached_locked: bool = w.warp_phase != CombatWorld.WARP_NONE and w.warp_phase != CombatWorld.WARP_PUSH
	t.check(not reached_locked, "A release-bound push at 0.29s has not committed yet")
	w.command.movement = Vector2.ZERO
	for i: int in range(120): w._update_player(STEP) # spring back drains at 2x fill rate - well within 120 ticks
	t.check(w.warp_phase == CombatWorld.WARP_NONE, "Releasing before the threshold springs back to WARP_NONE")
	release(w)

func _hold_to_threshold_commits() -> void:
	var w: CombatWorld = make_world()
	_push_toward_right(w, floori(0.30 / STEP) + 2)
	var locked: bool = w.warp_phase != CombatWorld.WARP_NONE and w.warp_phase != CombatWorld.WARP_PUSH
	t.check(locked, "Holding to 0.30s commits (control locks)")
	release(w)

func _projectiles_discarded_at_commit() -> void:
	var w: CombatWorld = make_world()
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 40.0, 0.0)
	w.bullets.add(Vector2(500, 500), Vector2.ZERO, -1.0, 5.0, 2.0, 5, 1, 0) # enemy
	w.bullets.add(Vector2(510, 500), Vector2.ZERO, -1.0, 5.0, 2.0, 6, 1, 0) # enemy
	w.bullets.add(Vector2(520, 500), Vector2.ZERO, -1.0, 5.0, 2.0, 0, 0, 0) # player's own shot
	w.command.movement = Vector2.RIGHT
	w.command.aim = Vector2.RIGHT
	for i: int in range(floori(0.30 / STEP) + 2): w._update_player(STEP)
	t.check(w.warp_phase != CombatWorld.WARP_NONE and w.warp_phase != CombatWorld.WARP_PUSH, "Commit reached before counting projectiles")
	var enemy_remaining: int = 0
	var player_remaining: int = 0
	for index: int in w.bullets.active_indices:
		if w.bullets.factions[index] == 0: player_remaining += 1
		else: enemy_remaining += 1
	t.check(enemy_remaining == 0, "0 enemy projectiles remain at commit")
	t.check(player_remaining == 1, "The player's own shot is not an 'enemy projectile' and survives commit")
	release(w)

func _no_damage_during_lock() -> void:
	var w: CombatWorld = make_world()
	_push_toward_right(w, floori(0.30 / STEP) + 2)
	t.check(w.warp_phase != CombatWorld.WARP_NONE and w.warp_phase != CombatWorld.WARP_PUSH, "Commit reached before the no-damage window")
	var before: float = w.light_total
	var ticks: int = 0
	while w.warp_locked() and ticks < 200:
		w._damage_actor(w.player, 1000.0, 5, 1)
		w._update_player(STEP)
		ticks += 1
	t.check(w.light_total == before, "No damage is taken for the whole locked window (%d ticks tried)" % ticks)
	release(w)

func _entry_speed_and_total_locked_time() -> void:
	var w: CombatWorld = make_world()
	_push_toward_right(w, floori(0.30 / STEP) + 2)
	var commit_speed: float = w.warp_commit_speed
	# Caught a real bug during P6: the ordinary rim clamp/friction was still
	# fighting the push's own 40% speed scale every tick, so commit_speed
	# measured exactly 0.0 and the entry-speed check below passed trivially
	# (0 ~= 0). A bare positivity check is the cheap guard against that
	# specific silent failure mode.
	t.check(commit_speed > 20.0, "Commit speed is a real, non-degenerate value (%.1f), not silently zeroed by rim friction fighting the push" % commit_speed)
	w.confirm_warp_swap() # simulate the listener swapping the sector synchronously
	var ticks: int = 0
	while w.warp_locked() and ticks < 300:
		w._update_player(STEP)
		ticks += 1
	t.check(not w.warp_locked(), "Warp finished within a generous tick budget (%d ticks)" % ticks)
	var entry_error: float = absf(w.warp_entry_speed - commit_speed) / maxf(1.0, commit_speed)
	t.check(entry_error <= 0.05, "Entry speed %.1f within 5%% of commit speed %.1f (error %.3f)" % [w.warp_entry_speed, commit_speed, entry_error])
	var expected_locked: float = CombatWorld.WARP_ZOOM_IN_SECONDS + CombatWorld.WARP_TRAVEL_SECONDS + CombatWorld.WARP_ARRIVAL_SECONDS + CombatWorld.WARP_ZOOM_OUT_SECONDS
	# Each of the 4 phase transitions checks `elapsed>=duration` once per tick,
	# so each can overshoot by up to one tick before advancing - up to ~4
	# ticks (0.067s) of slack across the whole locked window is expected, not
	# a bug. Measured 1.05s against the phase table's 1.02s sum (spec: ~1.0s).
	t.check(absf(w.warp_locked_measured - expected_locked) <= STEP * 5.0, "Total locked time measured %.4fs, ~= %.4fs (spec: ~1.0s)" % [w.warp_locked_measured, expected_locked])
	release(w)

func _reduced_warp_timing() -> void:
	var w: CombatWorld = make_world()
	w.warp_reduced = true
	_push_toward_right(w, floori(0.30 / STEP) + 2)
	w.confirm_warp_swap()
	var ticks: int = 0
	while w.warp_locked() and ticks < 120:
		w._update_player(STEP)
		ticks += 1
	t.check(absf(w.warp_locked_measured - CombatWorld.WARP_REDUCED_SECONDS) <= STEP * 1.5, "Reduced-warp setting locks for 0.25s +/- 1 tick (measured %.4fs)" % w.warp_locked_measured)
	release(w)

## "If no node swap arrives... spring back rather than deadlock" - no
## listener is connected on this raw CombatWorld, so `confirm_warp_swap` is
## never called; the travel phase must give up and return control instead of
## sitting locked forever.
func _missing_swap_springs_back() -> void:
	var w: CombatWorld = make_world()
	_push_toward_right(w, floori(0.30 / STEP) + 2)
	t.check(w.warp_phase != CombatWorld.WARP_NONE, "Commit reached before the missing-swap window")
	var ticks: int = 0
	while w.warp_phase != CombatWorld.WARP_NONE and ticks < 300:
		w._update_player(STEP)
		ticks += 1
	t.check(w.warp_phase == CombatWorld.WARP_NONE, "A missing node swap springs back to WARP_NONE instead of deadlocking (%d ticks)" % ticks)
	t.check(w.player_invulnerable == 0.0, "Spring-back also releases the invulnerability grant")
	# Contrast: the SAME setup, but the swap DOES arrive, must NOT spring back.
	var w2: CombatWorld = make_world()
	_push_toward_right(w2, floori(0.30 / STEP) + 2)
	w2.confirm_warp_swap()
	var ticks2: int = 0
	while w2.warp_phase != CombatWorld.WARP_NONE and ticks2 < 300:
		w2._update_player(STEP)
		ticks2 += 1
	var completed_normally: bool = w2.warp_locked_measured > 0.9
	t.control("missing-swap spring-back control (with the swap confirmed, the warp must complete normally instead)", completed_normally)
	release(w)
	release(w2)

## Determinism (spec plan: "same seed, byte-identical outcomes... including a
## warp"): two freshly-built worlds driven through the identical commit and
## an identical simulated swap end up with byte-identical position/velocity.
func _determinism() -> void:
	var a: CombatWorld = make_world()
	var b: CombatWorld = make_world()
	for w: CombatWorld in [a, b]:
		_push_toward_right(w, floori(0.30 / STEP) + 2)
		w.confirm_warp_swap()
		var ticks: int = 0
		while w.warp_locked() and ticks < 300:
			w._update_player(STEP)
			ticks += 1
	t.check(a.player.pos == b.player.pos and a.player.vel == b.player.vel, "Two identical warp runs land at byte-identical position/velocity")
	t.check(a.warp_locked_measured == b.warp_locked_measured, "Two identical warp runs measure byte-identical locked time")
	release(a)
	release(b)
