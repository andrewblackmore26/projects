extends SceneTree
## The warp state machine, sim-side (camera/movement spec §7, modernization M9):
## PUSH 12 -> BREAK 4 -> TRAVEL 18 -> ARRIVAL 12 ticks at 60 Hz, every phase a sim_q deadline.
## Every world here is stepped through `_physics_process` (the sim_q clock advances there), never
## `_update_player` alone.
##
##   control   commit -> the ship answers a new input in <= 0.6 s, measured by what the ship does
##             (control: the pre-M9 1.02 s locked window, BREAK 0.12 + TRAVEL 0.90)
##   rates     the same seconds within one tick at 30/60/120/144 Hz
##   speed     arrival speed >= 95 % of the approach at slow / cruise / dash, 20 seeds, median and
##             worst (control: the approach captured at commit, after the 40 % press slowdown)
##   arrival   ARRIVAL is playable and takes no damage (control: the grant ending with TRAVEL)
##   reduced   FADE: control back after 12 ticks (control: the pre-M9 0.25 s)
##   trail     the player's ribbon survives the swap and stays continuous across the jump
##             (control: the jump without the trail translation)
##   events    warp_strain x12 rising to 1, then warp_snap, warp_rush, warp_arrive in that order
##   determinism two runs of the whole warp are byte-identical tick by tick

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0
const SEEDS: int = 20

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("WARP")
	GameTuning.reset_feel()
	_release_before_threshold_never_commits()
	_hold_to_threshold_commits()
	_phase_ticks()
	_control_returns()
	_tick_rates()
	_arrival_speed()
	_no_damage_in_arrival()
	_projectiles_discarded_at_commit()
	_reduced_warp_timing()
	_missing_swap_springs_back()
	_trail_continuity()
	_feel_events()
	_determinism()
	_engage_threshold()
	_diagonal_round_trip()
	GameTuning.reset_feel()
	await process_frame
	t.finish(self)

func make_world(visuals: bool = false) -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = visuals
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2.ZERO)
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## The listener's half of the swap, without a real sector change.
func confirming(w: CombatWorld) -> CombatWorld:
	w.warp_committed.connect(func(_direction: Vector2i) -> void: w.confirm_warp_swap())
	return w

func tick(w: CombatWorld, step: float = STEP) -> void:
	w._physics_process(step)

## The player just inside the rim along `outward`, moving out at `speed`, input `scale` outward.
func place(w: CombatWorld, outward: Vector2, inset: float = 4.0, speed: float = 200.0, scale: float = 1.0) -> void:
	w.player_position = w.arena.center + outward * (w.arena.radius - inset)
	w.player.vel = outward * speed
	w.command.movement = outward * scale
	w.command.aim = outward

## Ticks until `done`, or -1 at the cap.
func ticks_until(w: CombatWorld, done: Callable, cap: int = 600, step: float = STEP) -> int:
	for i: int in range(1, cap + 1):
		tick(w, step)
		if done.call(): return i
	return -1

func _release_before_threshold_never_commits() -> void:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.RIGHT)
	for i: int in range(11): tick(w)
	t.check(w.warp_phase == CombatWorld.WARP_PUSH and not w.warp_locked(), "11 ticks of press (0.183 s) have not committed (depth %.3f)" % w.warp_progress)
	w.command.movement = Vector2.ZERO
	var drained: int = ticks_until(w, func() -> bool: return w.warp_phase == CombatWorld.WARP_NONE, 60)
	t.check(drained > 0 and drained <= 7, "Releasing drains the press at twice the fill rate (%d ticks)" % drained)
	t.check(w.warp_release_q > 0 and w.warp_release_depth > 0.9, "The release is stamped for the rim's wobble (depth %.3f)" % w.warp_release_depth)
	release(w)

func _hold_to_threshold_commits() -> void:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.RIGHT)
	var ticks: int = ticks_until(w, func() -> bool: return w.warp_locked(), 60)
	t.check(ticks == 12, "Holding into the rim commits on the 12th tick (%d)" % ticks)
	t.check(w.warp_phase == CombatWorld.WARP_BREAK, "The commit enters BREAK")
	release(w)

## Ticks spent in each phase at 60 Hz, counted from what the sim reports each tick.
func _phase_ticks() -> void:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.RIGHT)
	var counts: Dictionary = {}
	for i: int in range(120):
		tick(w)
		counts[w.warp_phase] = int(counts.get(w.warp_phase, 0)) + 1
		if w.warp_phase == CombatWorld.WARP_NONE and counts.has(CombatWorld.WARP_ARRIVAL): break
	var got: Array = [int(counts.get(CombatWorld.WARP_PUSH, 0)), int(counts.get(CombatWorld.WARP_BREAK, 0)), int(counts.get(CombatWorld.WARP_TRAVEL, 0)), int(counts.get(CombatWorld.WARP_ARRIVAL, 0))]
	# PUSH is counted on ticks 1-11 (the 12th tick commits and reports BREAK).
	t.check(got == [11, 4, 18, 12], "Phase ticks PUSH/BREAK/TRAVEL/ARRIVAL = %s (expected [11 + commit tick, 4, 18, 12])" % str(got))
	release(w)

## From the commit tick, the input turns to `turn`; returns ticks until the velocity has 40 px/s
## along it - the ship visibly obeying the stick again. -1 if it never does.
func commit_to_control(w: CombatWorld, turn: Vector2, step: float = STEP) -> int:
	place(w, Vector2.RIGHT)
	if ticks_until(w, func() -> bool: return w.warp_locked(), roundi(1.0 / step), step) < 0: return -1
	w.command.movement = turn
	return ticks_until(w, func() -> bool: return Vector2(w.player.vel).dot(turn) > 40.0, roundi(3.0 / step), step)

func _control_returns() -> void:
	var w: CombatWorld = confirming(make_world())
	var ticks: int = commit_to_control(w, Vector2.UP)
	var seconds: float = ticks * STEP
	print("warp: commit -> control %d ticks = %.4f s" % [ticks, seconds])
	t.check(ticks > 0 and seconds <= 0.6, "Control returns %.4f s after commit (<= 0.6 s; spec §10 test 6)" % seconds)
	t.check(not w.warp_locked() and w.warp_phase == CombatWorld.WARP_ARRIVAL, "Control returns during ARRIVAL, which is playable")
	release(w)
	GameTuning.set_feel("warp.break_s", 0.12)
	GameTuning.set_feel("warp.warp_s", 0.90) # the pre-M9 ZOOM_IN 0.12 + TRAVEL 0.55 + ARRIVAL 0.15 + ZOOM_OUT 0.20
	var old: CombatWorld = confirming(make_world())
	var old_ticks: int = commit_to_control(old, Vector2.UP)
	GameTuning.reset_feel()
	print("warp: control (pre-M9 constants) commit -> control %d ticks = %.4f s" % [old_ticks, old_ticks * STEP])
	t.control("the pre-M9 1.02 s locked window (%.4f s)" % (old_ticks * STEP), old_ticks < 0 or old_ticks * STEP > 0.6)
	release(old)

func _tick_rates() -> void:
	var seconds: Array[float] = []
	for rate: int in [30, 60, 120, 144]:
		var w: CombatWorld = confirming(make_world())
		var step: float = 1.0 / rate
		var ticks: int = commit_to_control(w, Vector2.UP, step)
		seconds.append(ticks * step if ticks > 0 else 99.0)
		release(w)
	var spread: float = seconds.max() - seconds.min()
	print("warp: commit -> control at 30/60/120/144 Hz: %s s" % str(seconds))
	t.check(spread <= 1.0 / 30.0 + 0.0001, "Commit -> control is the same within one 30 Hz tick at every rate (spread %.4f s)" % spread)

## One seeded approach run from rest, `inset` px inside the rim along a random bearing of the
## east arc. mode: "slow" (input 0.55, just past the 0.5 a press needs to engage), "cruise" (1.0),
## "dash" (1.0 plus a dash on the first
## ticks, placed so the press engages mid-burst). Returns [approach px/s, arrival px/s at the
## arrival instant, arrival px/s over the first ARRIVAL tick]; -1 where the run never got there.
## The approach is measured by behaviour: the ship's displacement over the last tick before the
## press engaged. `at_commit` is the control: it overwrites the saved approach with the velocity
## the ship had going into the commit tick (the 40 %-slowed press speed).
func approach_run(seed: int, mode: String, at_commit: bool = false) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + mode.length()
	var w: CombatWorld = confirming(make_world())
	var outward: Vector2 = Vector2.from_angle(rng.randf_range(-0.3, 0.3))
	var inset: float = rng.randf_range(160.0, 260.0) if mode == "dash" else rng.randf_range(260.0, 420.0)
	place(w, outward, inset, 0.0, 0.55 if mode == "slow" else 1.0)
	var arrival_instant: Array[float] = [-1.0]
	w.warp_arrived.connect(func() -> void: arrival_instant[0] = Vector2(w.player.vel).length())
	var approach: float = -1.0
	var last: Vector2 = w.player_position
	var ticks: int = 0
	while w.warp_phase != CombatWorld.WARP_ARRIVAL and ticks < 300:
		w.command.dash = mode == "dash" and ticks < 2
		var free: bool = w.warp_phase == CombatWorld.WARP_NONE
		var before_commit: Vector2 = Vector2(w.player.vel)
		tick(w)
		ticks += 1
		if free and w.warp_phase == CombatWorld.WARP_NONE: approach = last.distance_to(w.player_position) / STEP
		if at_commit and w.warp_phase == CombatWorld.WARP_BREAK and w.warp_commit_q == w.sim_q: w.warp_approach = before_commit
		last = w.player_position
	var first_tick: float = -1.0
	if w.warp_phase == CombatWorld.WARP_ARRIVAL:
		first_tick = w.arena.entry_point(w.warp_direction, w.warp_exit_point).distance_to(w.player_position) / STEP
	release(w)
	return [approach, arrival_instant[0], first_tick]

func _arrival_speed() -> void:
	for mode: String in ["slow", "cruise", "dash"]:
		var ratios: Array[float] = []
		var first: Array[float] = []
		var failed: int = 0
		var approaches: Array[float] = []
		for seed: int in range(SEEDS):
			var run: Array = approach_run(seed, mode)
			var approach: float = float(run[0])
			approaches.append(approach)
			if approach <= 0.0 or float(run[1]) < 0.0:
				failed += 1
				ratios.append(0.0)
				continue
			ratios.append(float(run[1]) / approach)
			first.append(float(run[2]) / approach)
		ratios.sort()
		first.sort()
		approaches.sort()
		var median: float = ratios[ratios.size() / 2]
		var worst: float = ratios[0]
		print("warp: %s approach %.1f..%.1f px/s; arrival/approach over %d seeds: median %.4f worst %.4f, failed %d (over the first ARRIVAL tick, input held: median %.4f worst %.4f)" % [mode, approaches[0], approaches[-1], SEEDS, median, worst, failed, first[first.size() / 2] if not first.is_empty() else -1.0, first[0] if not first.is_empty() else -1.0])
		t.check(failed == 0 and worst >= 0.95, "%s: arrival speed >= 95%% of approach, median %.3f worst %.3f, %d failed runs" % [mode, median, worst, failed])
	# Control: the approach taken at commit (the slowed press speed) instead of at press start.
	var control_ratios: Array[float] = []
	for seed: int in range(SEEDS):
		var run: Array = approach_run(seed, "cruise", true)
		control_ratios.append(float(run[1]) / float(run[0]) if float(run[0]) > 0.0 else 0.0)
	control_ratios.sort()
	print("warp: control (speed captured at commit) cruise worst %.4f median %.4f" % [control_ratios[0], control_ratios[SEEDS / 2]])
	t.control("approach speed captured at commit (worst %.3f)" % control_ratios[0], control_ratios[0] < 0.95)

## Steps to ARRIVAL and hits the player with 1000 every ARRIVAL tick. Returns [light lost,
## ARRIVAL ticks, every ARRIVAL tick playable].
func arrival_hits(grant_ends_with_travel: bool) -> Array:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.RIGHT)
	ticks_until(w, func() -> bool: return w.warp_phase == CombatWorld.WARP_ARRIVAL, 120)
	var before: float = w.light_total
	var ticks: int = 0
	var playable: bool = true
	if grant_ends_with_travel:
		w.player_invulnerable = 0.0
		w.player.invulnerable = 0.0
		w.invulnerable_until_q = w.sim_q # review fix 3: the grant's sim_q deadline ends here too
	while w.warp_phase == CombatWorld.WARP_ARRIVAL and ticks < 60:
		playable = playable and not w.warp_locked()
		w._damage_actor(w.player, 1000.0, 5, 1)
		tick(w)
		ticks += 1
	var lost: float = before - w.light_total
	release(w)
	return [lost, ticks, playable]

func _no_damage_in_arrival() -> void:
	var hit: Array = arrival_hits(false)
	t.check(int(hit[1]) == 12 and bool(hit[2]), "ARRIVAL lasts 12 ticks and every one is playable (%d)" % int(hit[1]))
	t.check(float(hit[0]) == 0.0, "No damage lands in ARRIVAL (%.1f light lost over %d hits)" % [float(hit[0]), int(hit[1])])
	var control: Array = arrival_hits(true)
	t.control("the invulnerability grant ending with TRAVEL (%.1f light lost)" % float(control[0]), float(control[0]) > 0.0)

func _projectiles_discarded_at_commit() -> void:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.RIGHT, 40.0)
	w.bullets.add(w.arena.center + Vector2(-300, 0), Vector2.ZERO, -1.0, 5.0, 2.0, 5, 1, 0) # enemy
	w.bullets.add(w.arena.center + Vector2(-300, 40), Vector2.ZERO, -1.0, 5.0, 2.0, 6, 1, 0) # enemy
	w.bullets.add(w.arena.center + Vector2(-300, 80), Vector2.ZERO, -1.0, 5.0, 2.0, 0, 0, 0) # the player's own
	var counts: Array[int] = [-1, -1]
	w.warp_committed.connect(func(_direction: Vector2i) -> void:
		counts[0] = 0
		counts[1] = 0
		for index: int in w.bullets.active_indices:
			if w.bullets.factions[index] == 0: counts[1] += 1
			else: counts[0] += 1)
	ticks_until(w, func() -> bool: return w.warp_locked(), 60)
	t.check(counts[0] == 0, "0 enemy projectiles remain at commit (%d)" % counts[0])
	t.check(counts[1] == 1, "The player's own shot is not an enemy projectile and survives commit (%d)" % counts[1])
	release(w)

## Reduced warp: FADE replaces BREAK + TRAVEL; control is back after it (12 ticks).
func reduced_control_ticks() -> int:
	var w: CombatWorld = confirming(make_world())
	w.warp_reduced = true
	var ticks: int = commit_to_control(w, Vector2.UP)
	var saw_fade: bool = w.warp_phase == CombatWorld.WARP_ARRIVAL
	release(w)
	return ticks if saw_fade else -1

func _reduced_warp_timing() -> void:
	var w: CombatWorld = confirming(make_world())
	w.warp_reduced = true
	place(w, Vector2.RIGHT)
	ticks_until(w, func() -> bool: return w.warp_locked(), 60)
	t.check(w.warp_phase == CombatWorld.WARP_FADE, "Reduced warp commits into FADE")
	# The commit tick already reports FADE, so ARRIVAL begins on the 12th tick after it.
	var fade: int = ticks_until(w, func() -> bool: return w.warp_phase != CombatWorld.WARP_FADE, 60)
	t.check(fade == 12 and w.warp_phase == CombatWorld.WARP_ARRIVAL, "FADE lasts 12 ticks (%d) and hands over to ARRIVAL" % fade)
	release(w)
	var ticks: int = reduced_control_ticks()
	print("warp: reduced commit -> control %d ticks = %.4f s" % [ticks, ticks * STEP])
	t.check(ticks > 0 and ticks <= 13, "Reduced warp: control back %.4f s after commit (12 ticks + the answering tick)" % (ticks * STEP))
	GameTuning.set_feel("warp.reduced_s", 0.25)
	var old: int = reduced_control_ticks()
	GameTuning.reset_feel()
	t.control("the pre-M9 0.25 s fade (%d ticks)" % old, old < 0 or old > 13)

## No listener confirms the swap: the ship springs back at the end of BREAK instead of leaving.
func _missing_swap_springs_back() -> void:
	var w: CombatWorld = make_world()
	place(w, Vector2.RIGHT)
	ticks_until(w, func() -> bool: return w.warp_locked(), 60)
	var ticks: int = ticks_until(w, func() -> bool: return w.warp_phase == CombatWorld.WARP_NONE, 120)
	t.check(ticks == 4, "A missing node swap springs back at the end of BREAK (%d ticks after commit)" % ticks)
	t.check(w.player_invulnerable == 0.0, "Spring-back also releases the invulnerability grant")
	t.check(w.player_position.distance_to(w.arena.center) <= w.arena.radius - 2.9, "Spring-back puts the ship back inside the rim (%.1f px from centre)" % w.player_position.distance_to(w.arena.center))
	release(w)
	var w2: CombatWorld = confirming(make_world())
	place(w2, Vector2.RIGHT)
	var arrived: int = ticks_until(w2, func() -> bool: return w2.warp_phase == CombatWorld.WARP_ARRIVAL, 120)
	t.control("missing-swap spring-back (with the swap confirmed, the warp must arrive instead)", arrived > 0)
	release(w2)

## Returns [trail points kept across the swap, largest gap between consecutive points on the tick
## the ship jumps nodes].
func trail_across_jump(translate: bool) -> Array:
	var w: CombatWorld = make_world(true)
	# A real encounter swap: `start_sector` clears the trail pool, the commit carries the ribbon over.
	var campaign := CampaignState.new()
	w.start_sector(campaign.sector_at(Vector2i.ZERO))
	w.warp_committed.connect(func(direction: Vector2i) -> void:
		var destination: Vector2i = campaign.current_sector + direction
		campaign.on_enter(destination)
		w.start_sector(campaign.sector_at(destination))
		w.confirm_warp_swap())
	place(w, Vector2.RIGHT, 300.0, 460.0)
	ticks_until(w, func() -> bool: return w.warp_locked(), 120)
	var kept: int = w.trail_pool.trails[0].points.size() if w.trail_pool.trails.has(0) else 0
	var before: Vector2 = w.player_position
	var guard: int = 0
	while w.warp_phase != CombatWorld.WARP_TRAVEL and guard < 20:
		before = w.player_position
		tick(w)
		guard += 1
	if not translate:
		# The control: undo the translation `_warp_teleport` applied on this tick (the jump's delta
		# is exactly the ship's displacement over it: TRAVEL's first tick only jumps).
		var points: PackedVector2Array = w.trail_pool.trails[0].points
		var jump: Vector2 = w.player_position - before
		for index: int in range(points.size()): points[index] -= jump
		w.trail_pool.trails[0].points = points
	tick(w) # one TRAVEL tick of flight appends past the jump
	var gap: float = 0.0
	var trail_points: PackedVector2Array = w.trail_pool.trails[0].points
	for index: int in range(1, trail_points.size()): gap = maxf(gap, trail_points[index - 1].distance_to(trail_points[index]))
	release(w)
	return [kept, gap]

func _trail_continuity() -> void:
	var kept: Array = trail_across_jump(true)
	var fling: float = GameTuning.feel("warp.speed_ratio") * GameTuning.feel("player_top_speed") * STEP
	t.check(int(kept[0]) >= 10, "The player's trail survives the synchronous sector swap (%d points)" % int(kept[0]))
	t.check(float(kept[1]) <= fling * 1.5, "Across the node jump the trail is one continuous ribbon (largest gap %.1f px, one tick of the fling %.1f px)" % [float(kept[1]), fling])
	var broken: Array = trail_across_jump(false)
	t.control("the jump without the trail translation (largest gap %.1f px)" % float(broken[1]), float(broken[1]) > fling * 1.5)

## Runs a press into the east rim for 80 ticks. Returns [warp_strain magnitudes, the other warp_*
## kinds in order with repeats collapsed].
func warp_events(engage_dot: float, hold_ticks: int = 80) -> Array:
	var w: CombatWorld = confirming(make_world())
	w.warp_engage_dot = engage_dot
	var strains: Array[float] = []
	var order: Array[StringName] = []
	w.feel_event.connect(func(kind: StringName, _at: Vector2, magnitude: float, _actor: int) -> void:
		if kind == &"warp_strain": strains.append(magnitude)
		elif str(kind).begins_with("warp_") and (order.is_empty() or order[-1] != kind): order.append(kind))
	place(w, Vector2.RIGHT)
	for i: int in range(80):
		if i == hold_ticks: w.command.movement = Vector2.ZERO
		tick(w)
	release(w)
	return [strains, order]

func _strains_rise(strains: Array) -> bool:
	var rising: bool = strains.size() == 12 and is_equal_approx(float(strains[-1]), 1.0)
	for index: int in range(1, strains.size()): rising = rising and float(strains[index]) > float(strains[index - 1])
	return rising

func _feel_events() -> void:
	var full: Array = warp_events(0.5)
	t.check(_strains_rise(full[0]), "warp_strain fires on each of the 12 press ticks with the depth rising to 1 (%s)" % str(full[0]))
	t.check(full[1] == [&"warp_snap", &"warp_rush", &"warp_arrive"], "Then warp_snap, warp_rush, warp_arrive once each, in order (%s)" % str(full[1]))
	var let_go: Array = warp_events(0.5, 6)
	t.check(let_go[1] == [&"warp_release"], "A press let go after 6 ticks emits warp_release once and never snaps (%s)" % str(let_go[1]))
	# Control: a press that can never engage emits nothing, and both lines above must say so.
	var never: Array = warp_events(2.0)
	t.control("a press that never engages (strain line)", not _strains_rise(never[0]))
	t.control("a press that never engages (order line)", never[1] != [&"warp_snap", &"warp_rush", &"warp_arrive"])

## The whole warp, press to NONE, as bytes: position, velocity, phase and sim_q every tick.
func warp_trace() -> PackedByteArray:
	var w: CombatWorld = confirming(make_world())
	place(w, Vector2.from_angle(0.2), 120.0, 300.0)
	var trace: Array = []
	for i: int in range(90):
		tick(w)
		trace.append([w.player_position, w.player.vel, w.warp_phase, w.sim_q, w.player_invulnerable])
	release(w)
	return var_to_bytes(trace)

func _determinism() -> void:
	var a: PackedByteArray = warp_trace()
	var b: PackedByteArray = warp_trace()
	t.check(a == b and a.size() > 1000, "Two identical warp runs are byte-identical tick by tick (%d bytes)" % a.size())

## Modernization M3: a rim press engages at input.outward >= 0.5 (raised from 0.2 against
## accidental exits). One tick from rest just inside the east rim, input at a set outward dot.
func _engages_at(dot: float, threshold: float) -> bool:
	var w: CombatWorld = make_world()
	w.warp_engage_dot = threshold
	place(w, Vector2.RIGHT, 4.0, 0.0)
	w.command.movement = Vector2.from_angle(acos(dot))
	tick(w)
	var engaged: bool = w.warp_phase == CombatWorld.WARP_PUSH
	release(w)
	return engaged

func _engage_threshold() -> void:
	t.check(not _engages_at(0.45, 0.5), "A rim press at 0.45 outward does not engage")
	t.check(_engages_at(0.55, 0.5), "A rim press at 0.55 outward engages")
	t.control("engage threshold back at 0.2 (0.45 outward engages)", _engages_at(0.45, 0.2))

## Presses into the rim at `angle` until the warp commits, then lets go and runs it out.
## Returns the direction the warp committed toward (ZERO if it never did).
func _warp_through(w: CombatWorld, angle: float) -> Vector2i:
	place(w, Vector2.from_angle(angle))
	var ticks: int = ticks_until(w, func() -> bool: return w.warp_locked(), 60)
	var committed: Vector2i = w.warp_direction if ticks > 0 else Vector2i.ZERO
	w.command.movement = Vector2.ZERO
	ticks_until(w, func() -> bool: return w.warp_phase == CombatWorld.WARP_NONE, 200)
	return committed

## Live two-warp diagonal round trip: NE out of the origin, SW back. The swap handler mirrors
## RunController.on_warp_committed, so a diagonal Vector2i has to survive the signal.
func _diagonal_round_trip() -> void:
	var w: CombatWorld = make_world()
	var campaign := CampaignState.new()
	w.start_sector(campaign.sector_at(Vector2i.ZERO))
	w.warp_committed.connect(func(direction: Vector2i) -> void:
		var destination: Vector2i = campaign.current_sector + direction
		campaign.on_enter(destination)
		w.start_sector(campaign.sector_at(destination))
		w.confirm_warp_swap())
	var out_dir: Vector2i = _warp_through(w, -PI * 0.25 + 0.1)
	var after_out: Vector2i = campaign.current_sector
	var out_pos: Vector2 = w.player_position
	t.check(out_dir == Vector2i(1, -1) and after_out == Vector2i(1, -1), "Pressing into the NE arc warps to the NE neighbour (committed %s, now at %s)" % [out_dir, after_out])
	t.check(w.arena.contains(out_pos), "The NE arrival lands inside the arena (%.1f px from centre, radius %.0f)" % [out_pos.distance_to(w.arena.center), w.arena.radius])
	var back_dir: Vector2i = _warp_through(w, PI * 0.75 - 0.1)
	t.check(back_dir == Vector2i(-1, 1) and campaign.current_sector == Vector2i.ZERO, "Pressing into the SW arc returns to the origin (committed %s, now at %s)" % [back_dir, campaign.current_sector])
	t.check(w.arena.contains(w.player_position), "The return arrival lands inside the arena")
	release(w)
	# Negative control: the same NE press on a rim with only the four cardinal exits (the old maze's
	# best case) cannot reach the diagonal neighbour.
	var c: CombatWorld = confirming(make_world())
	c.arena.set_exits([Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	t.control("cardinal-only exits (the NE press goes E instead)", _warp_through(c, -PI * 0.25 + 0.1) != Vector2i(1, -1))
	release(c)
