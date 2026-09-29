extends SceneTree
## The adversarial gameplay review's reproduced bugs, each measured after its fix, each line with a
## negative control that restores the pre-fix behaviour (or the pre-fix path) and must be caught:
##  1. a boss killed during the death beat no longer strands a dead player: the reboot comes, the
##     level-complete card follows it, and the fresh life keeps its own boss_down;
##  2. a death in ARRIVAL leaves no warp state behind: the next life warps at once;
##  3. sim_q is exact under slow motion (the fractional quanta carry) and the warp protects to its
##     sim_q deadline (0 unprotected ARRIVAL ticks at 0.35); a frozen step advances no dash;
##  5. big-kill slow motion and the death beat run on physics steps: the same inputs at different
##     render/physics interleavings give the same sim state;
##  6. an ability pressed during hitstop reaches the first step after it;
##  7. a restore keeps the player's reduced-warp setting and still finishes a saved FADE;
##  8. a node clear saves once, on the next frame;
##  9. the death beat's hitstop adds on top of the killing hit's, and the boss kill's is honoured;
## 10. a cached node swapped in at a warp commit holds its wave clock until the arrival;
## 11. the light bank obeys the lower cap after a regression; the combo and decay state round-trip.

const Harness = preload("res://tests/support/harness.gd")
const DT: float = 1.0 / 60.0

class FakeApp extends Node:
	var settings: Dictionary = {}
	var combat: CombatWorld
	var sound: Object
	var campaign: Object

var t: RefCounted
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("SIM REVIEW FIXES")
	SaveService.storage_root = "user://review-fixes-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	_boss_in_death_beat()
	_death_in_arrival()
	_slow_motion_warp()
	_frozen_dash()
	_death_beat_interleavings()
	_ability_latch()
	_reduced_warp_restore()
	await _sector_clear_save()
	_death_hitstop()
	_cached_arrival_hold()
	_bank_and_pace()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	_slow_mo_interleavings()
	t.finish(self)

## --- helpers ------------------------------------------------------------------------------------

func _frame() -> void:
	app._process(DT)
	app._physics_process(DT)
	if is_instance_valid(app.combat): app.combat._physics_process(DT)

func _fresh() -> CombatWorld:
	app._close_overlay()
	paused = false
	app._new_game(false)
	app.combat.set_physics_process(false)
	app.line_queue.clear()
	return app.combat

func _kill_player(w: CombatWorld) -> void:
	w.player_invulnerable = 0.0
	w.player.invulnerable = 0.0
	w.invulnerable_until_q = 0
	w._damage_actor(w.player, 1000000.0, 1, 1)

func _dead() -> bool:
	return bool(app.combat.player.get("dead", false))

## A standalone world with one open membrane to the right; the swap is confirmed at once.
func _world() -> CombatWorld:
	var w := CombatWorld.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	w.arena.set_exits([Vector2i.RIGHT])
	w.warp_committed.connect(func(_d: Vector2i) -> void: w.confirm_warp_swap())
	return w

func _release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _press(w: CombatWorld, direction: Vector2) -> void:
	var c := ShipCommand.new()
	c.movement = direction
	c.aim = direction
	w.set_command(c)

## --- 1. a boss killed during the death beat ----------------------------------------------------

func _boss_beat(old_path: bool, drop_stash: bool) -> Dictionary:
	var w: CombatWorld = _fresh()
	w.start_sector({"id": "pb", "kind": "boss", "element": "fire", "tier": 1, "resource_budget": 200, "enemy_hulls": [], "boss_hull": "boss_fire"})
	for i: int in range(5): _frame()
	var boss: Dictionary = {}
	for a: Dictionary in w.enemies:
		if bool(a.rival): boss = a
	_kill_player(w)
	_frame()
	if old_path:
		# The pre-fix flow: the level-complete card replaced the banner at once, and step_death read
		# a non-death overlay as "cancelled".
		app.run_controller._complete_boss("fire", true)
		app.run_controller.death_elapsed = -1.0
	elif not boss.is_empty():
		for i: int in boss.get("shield_generator_indices", PackedInt32Array()): boss.part_hp[i] = 0.0
		for i: int in boss.get("sub_core_indices", PackedInt32Array()): boss.part_hp[i] = 0.0
		boss.invulnerable = 0.0
		w._damage_actor(boss, 1e7, 0, 0) # the dead player's shot still in flight
	var overlay_in_beat: String = app.overlay_kind
	if drop_stash: app.run_controller._boss_defeated_in_beat = ""
	for i: int in range(120): _frame()
	return {"boss": not boss.is_empty(), "in_beat": overlay_in_beat, "dead": _dead(), "overlay": app.overlay_kind, "boss_down": app.campaign.boss_down, "completed": app.campaign.is_level_complete(1), "mode": app.mode_config.id}

func _boss_in_death_beat() -> void:
	var fixed: Dictionary = _boss_beat(false, false)
	print("measure: boss killed in the death beat -> %s" % [fixed])
	t.check(fixed.boss and fixed.in_beat == "death", "The boss dies during the beat and the banner stays up (%s)" % fixed.in_beat)
	t.check(not fixed.dead, "2 s after a boss kill in the death beat the player has rebooted")
	var old: Dictionary = _boss_beat(true, false)
	t.control("the pre-fix flow: card at once, beat cancelled (dead=%s)" % old.dead, old.dead)
	# The boss-defeated flow's own card: level complete, or the ending when that finished the mode.
	var cards: Array[String] = ["level_complete", "ending"]
	t.check(fixed.overlay in cards and fixed.completed, "The level counts and its card follows the reboot (%s)" % fixed.overlay)
	var dropped: Dictionary = _boss_beat(false, true)
	t.control("the deferred boss dropped before the reboot (overlay '%s')" % dropped.overlay, dropped.overlay not in cards)
	t.check(not fixed.boss_down, "The fresh life keeps its own boss_down (false)")
	# Control: the same completion credited to the life that is current at the reboot.
	app.run_controller._complete_boss("fire", true)
	t.control("boss_down credited to the fresh life", app.campaign.boss_down)
	app._close_overlay()

## --- 2. a death in ARRIVAL ---------------------------------------------------------------------

## Kills the player mid-ARRIVAL 10 s into a life, reboots, then presses into the rim for 1 s.
## Returns whether the press left ARRIVAL/NONE (i.e. a warp could start) and the state after reboot.
func _arrival_death(restore_stale: bool) -> Dictionary:
	var w: CombatWorld = _fresh()
	for i: int in range(600): _frame()
	w.warp_phase = CombatWorld.WARP_ARRIVAL
	w.warp_phase_start_q = w.sim_q
	w.warp_deadline_q = w.sim_q + 144
	w.warp_end_q = w.warp_deadline_q
	var old_deadline: int = w.warp_deadline_q
	_kill_player(w)
	for i: int in range(60): _frame()
	w = app.combat
	var after: Dictionary = {"phase": w.warp_phase, "deadline": w.warp_deadline_q, "hold": w._wave_arrival_hold}
	if restore_stale: # the pre-fix setup_player: sim_q reset, the warp left as it was
		w.warp_phase = CombatWorld.WARP_ARRIVAL
		w.warp_deadline_q = old_deadline
		w.warp_end_q = old_deadline
	w.player_position = w.arena.center + Vector2.RIGHT * (w.arena.radius - 10.0)
	var started: bool = false
	for i: int in range(60):
		_press(w, Vector2.RIGHT)
		w._physics_process(DT)
		if w.warp_phase != CombatWorld.WARP_ARRIVAL and w.warp_phase != CombatWorld.WARP_NONE: started = true
	after["started"] = started
	return after

func _death_in_arrival() -> void:
	var fixed: Dictionary = _arrival_death(false)
	print("measure: death in ARRIVAL -> after reboot %s" % [fixed])
	t.check(fixed.phase == CombatWorld.WARP_NONE and fixed.deadline == 0, "After a death in ARRIVAL the next life has no warp phase or deadline (%s)" % [fixed])
	t.check(fixed.started, "The next life's first press into the rim starts a warp within 1 s")
	var stale: Dictionary = _arrival_death(true)
	t.control("the old life's ARRIVAL left in place (a warp started: %s)" % stale.started, not stale.started)

## --- 3. sim_q exactness and the warp's sim_q protection under slow motion ----------------------

## Pushes into the rim at `scale` until the warp has committed and finished. Returns the ARRIVAL
## ticks that damage could reach and the light a hit on each would have cost.
func _warp_at(scale: float, carry_off: bool, q_off: bool) -> Dictionary:
	var w: CombatWorld = _world()
	w.sim_q_carry_disabled = carry_off
	w.invulnerable_q_disabled = q_off
	w.request_time_scale(&"probe", scale)
	w.player_position = w.arena.center + Vector2.RIGHT * (w.arena.radius - 10.0)
	var committed: bool = false
	var unprotected: int = 0
	var arrival_ticks: int = 0
	for i: int in range(600):
		_press(w, Vector2.RIGHT)
		w._physics_process(DT)
		if w.warp_phase == CombatWorld.WARP_BREAK: committed = true
		if w.warp_phase == CombatWorld.WARP_ARRIVAL:
			arrival_ticks += 1
			if not w.player_protected(): unprotected += 1
		if committed and w.warp_phase == CombatWorld.WARP_NONE: break
	_release(w)
	return {"committed": committed, "unprotected": unprotected, "arrival": arrival_ticks}

func _sim_q_after(scale: float, ticks: int, carry_off: bool) -> int:
	var w: CombatWorld = _world()
	w.sim_q_carry_disabled = carry_off
	w.request_time_scale(&"probe", scale)
	for i: int in range(ticks): w._physics_process(DT)
	var q: int = w.sim_q
	_release(w)
	return q

func _slow_motion_warp() -> void:
	var exact: float = 600.0 * DT * 0.35 * CombatWorld.SIM_Q_PER_SECOND
	var carried: int = _sim_q_after(0.35, 600, false)
	var rounded: int = _sim_q_after(0.35, 600, true)
	print("measure: sim_q after 600 ticks at 0.35 = %d with the carry, %d rounded per tick (exact %.1f)" % [carried, rounded, exact])
	t.check(absf(float(carried) - exact) <= 1.0, "sim_q stays exact over 600 ticks at 0.35 (%d vs %.1f)" % [carried, exact])
	t.control("the per-tick roundi (%d)" % rounded, absf(float(rounded) - exact) > 1.0)
	var fixed: Dictionary = _warp_at(0.35, false, false)
	var old: Dictionary = _warp_at(0.35, true, true)
	print("measure: warp at 0.35: %d of %d ARRIVAL ticks unprotected (pre-fix float-only protection, per-tick roundi: %d of %d)" % [fixed.unprotected, fixed.arrival, old.unprotected, old.arrival])
	t.check(fixed.committed and fixed.arrival > 0 and fixed.unprotected == 0, "Every ARRIVAL tick at 0.35 is protected (%d unprotected)" % fixed.unprotected)
	t.control("float-only protection with per-tick rounding (%d unprotected)" % old.unprotected, old.unprotected > 0)

func _frozen_dash() -> void:
	var results: Array[int] = []
	for scale: float in [0.0, 1.0]:
		var w: CombatWorld = _world()
		w.request_time_scale(&"probe", scale)
		var c := ShipCommand.new()
		c.dash = true
		c.movement = Vector2.UP
		w.set_command(c)
		w.player.dash_dir = Vector2.UP
		w.player.dash_burst_q = 60
		w.player.dash_cooldown_q = 400
		for i: int in range(30): w._physics_process(DT)
		results.append(int(w.player.dash_burst_q) + int(w.player.dash_cooldown_q))
		_release(w)
	print("measure: dash burst + cooldown quanta after 30 ticks: %d at scale 0, %d at scale 1 (from 460)" % [results[0], results[1]])
	t.check(results[0] == 460, "A frozen (scale 0) step advances neither the dash burst nor its cooldown (%d)" % results[0])
	t.control("the same 30 ticks at scale 1 (%d)" % results[1], results[1] != 460)

## --- 5. render/physics interleavings -------------------------------------------------------------

## The pre-fix director: the big-kill scale counted down and eased on the RENDER step.
class RenderEase extends RefCounted:
	var remaining: float = 0.0
	var total: float = 0.0
	var scale: float = 1.0
	func begin(s: float, seconds: float) -> void:
		scale = s
		total = seconds
		remaining = seconds
	func step(world: CombatWorld, dt: float) -> void:
		if remaining <= 0.0: return
		remaining = maxf(0.0, remaining - dt)
		if remaining <= 0.0:
			world.release_time_scale(FeelDirector.SLOW_MO_REASON)
			return
		var back: float = 1.0 - clampf(remaining / total / FeelDirector.SLOW_MO_EASE_FRACTION, 0.0, 1.0)
		world.request_time_scale(FeelDirector.SLOW_MO_REASON, lerpf(scale, 1.0, back * back))

## An elite kill's slow motion, then 60 physics steps with `renders` render frames of `render_dt`
## between each. Returns the sim state the steps produced.
func _slow_mo_run(renders: float, render_dt: float, render_driven: bool) -> String:
	var fake := FakeApp.new()
	var w: CombatWorld = _world()
	w.arena.set_exits([])
	fake.combat = w
	var director := FeelDirector.new(fake, func(_a: float, _b: float, _c: float) -> void: pass)
	director.bind(w)
	var ease := RenderEase.new()
	if render_driven:
		director.slow_mo_release_enabled = false # the director asks open-ended; the test eases it
		ease.begin(0.35, 0.35)
	w.feel_event.emit(&"elite_kill", Vector2.ZERO, 1.0, 5)
	var owed: float = 0.0
	for i: int in range(60):
		owed += renders
		while owed >= 1.0:
			owed -= 1.0
			director.step(render_dt)
			if render_driven: ease.step(w, render_dt)
		_press(w, Vector2.UP)
		w._physics_process(DT)
	var state: String = "%d %.5f %.3f,%.3f" % [w.sim_q, w.elapsed, Vector2(w.player.pos).x, Vector2(w.player.pos).y]
	director.bind(null)
	director.free()
	fake.free()
	_release(w)
	return state

func _slow_mo_interleavings() -> void:
	var patterns: Array = [[0.0, DT], [1.0, DT], [2.4, 1.0 / 144.0], [0.5, 1.0 / 30.0]]
	var fixed: Array[String] = []
	var render: Array[String] = []
	for p: Array in patterns:
		fixed.append(_slow_mo_run(float(p[0]), float(p[1]), false))
		render.append(_slow_mo_run(float(p[0]), float(p[1]), true))
	var fixed_same: bool = fixed.count(fixed[0]) == fixed.size()
	var render_same: bool = render.count(render[1]) == render.size()
	print("measure: big-kill slow motion, sim state over 4 render interleavings: physics-driven %s; render-driven %s" % [fixed, render])
	t.check(fixed_same, "Big-kill slow motion gives one sim state at every render/physics interleaving")
	t.control("the render-driven ease (%d distinct states)" % _distinct(render), not render_same)

func _distinct(values: Array[String]) -> int:
	var seen: Dictionary = {}
	for v: String in values: seen[v] = true
	return seen.size()

## A death, then frames with `renders` render steps of `render_dt` per physics step. Returns the
## dead life's sim_q at its last step and the physics steps to the reboot.
func _death_run(renders: float, render_dt: float, render_driven: bool) -> String:
	var w: CombatWorld = _fresh()
	for i: int in range(30): _frame()
	_kill_player(w)
	var owed: float = 0.0
	var steps: int = 0
	var last_q: int = -1
	while steps < 180 and _dead():
		owed += renders
		while owed >= 1.0:
			owed -= 1.0
			app._process(render_dt)
			if render_driven: app.run_controller.step_death(render_dt) # the pre-fix placement
		last_q = w.sim_q
		app._physics_process(DT)
		if is_instance_valid(app.combat): app.combat._physics_process(DT)
		steps += 1
	return "%d@%d" % [last_q, steps]

func _death_beat_interleavings() -> void:
	var patterns: Array = [[0.0, DT], [1.0, DT], [2.4, 1.0 / 144.0], [0.5, 1.0 / 30.0]]
	var fixed: Array[String] = []
	var render: Array[String] = []
	for p: Array in patterns:
		fixed.append(_death_run(float(p[0]), float(p[1]), false))
		render.append(_death_run(float(p[0]), float(p[1]), true))
	print("measure: death beat, last sim_q @ physics steps to the reboot over 4 interleavings: physics-driven %s; render-driven %s" % [fixed, render])
	t.check(fixed.count(fixed[0]) == fixed.size(), "The death beat reboots on the same sim_q and step at every interleaving")
	t.control("the reboot wait on the render step (%d distinct)" % _distinct(render), _distinct(render) > 1)

## --- 6. presses during hitstop ------------------------------------------------------------------

func _latched(disabled: bool) -> bool:
	var w: CombatWorld = _world()
	w.command_latch_disabled = disabled
	w.hitstop_remaining = 3
	var read: bool = false
	for i: int in range(4):
		var c := ShipCommand.new()
		c.ability_primary = i == 1 # pressed on a hitstop frame only
		c.secondaries = [i == 1, false, false]
		w.set_command(c)
		var frozen: bool = w.hitstop_remaining > 0
		w._physics_process(DT)
		if not frozen: read = w.command.ability_primary and w.command.secondaries[0]
	_release(w)
	return read

func _ability_latch() -> void:
	var fixed: bool = _latched(false)
	var old: bool = _latched(true)
	t.check(fixed, "An ability pressed during hitstop reaches the first step after it")
	t.control("the latch off: the press is overwritten (reached: %s)" % old, not old)

## --- 7. reduced warp across a restore -----------------------------------------------------------

func _reduced_warp_restore() -> void:
	var source: CombatWorld = _world()
	source.warp_reduced = true
	source.player_position = source.arena.center + Vector2.RIGHT * (source.arena.radius - 10.0)
	for i: int in range(60):
		_press(source, Vector2.RIGHT)
		source._physics_process(DT)
		if source.warp_phase == CombatWorld.WARP_FADE: break
	var snap: Dictionary = source.snapshot().duplicate(true)
	_release(source)
	var target: CombatWorld = _world()
	target.warp_reduced = false # the player's setting now
	target.restore(snap)
	var kept: bool = target.warp_reduced == false
	var phases: Array[int] = [target.warp_phase]
	for i: int in range(120):
		target._physics_process(DT)
		if phases[-1] != target.warp_phase: phases.append(target.warp_phase)
	print("measure: a FADE saved with reduced warp on, restored with it off: setting kept=%s, phases %s" % [kept, phases])
	t.check(kept, "A restore keeps the player's reduced-warp setting over the saved one")
	t.check(phases[0] == CombatWorld.WARP_FADE and phases[-1] == CombatWorld.WARP_NONE and CombatWorld.WARP_ARRIVAL in phases, "The saved FADE still finishes through ARRIVAL (%s)" % [phases])
	# Control: the pre-fix restore line.
	target.warp_reduced = bool(snap.get("warp_reduced", false))
	t.control("the saved flag assigned on restore (reduced=%s)" % target.warp_reduced, target.warp_reduced != false)
	_release(target)

## --- 8. the node-clear save ---------------------------------------------------------------------

func _sector_clear_save() -> void:
	_fresh()
	app.testing = false
	var before: int = app.run_controller.save_timings_ms.size()
	app._on_sector_clear()
	var synchronous: int = app.run_controller.save_timings_ms.size() - before
	await process_frame
	var next_frame: int = app.run_controller.save_timings_ms.size() - before - synchronous
	var old_before: int = app.run_controller.save_timings_ms.size()
	app._save_game() # the pre-fix handler: two synchronous saves
	app._save_game()
	var old: int = app.run_controller.save_timings_ms.size() - old_before
	app.testing = true
	print("measure: node clear saves %d synchronously and %d on the next frame (pre-fix handler: %d synchronously)" % [synchronous, next_frame, old])
	t.check(synchronous == 0 and next_frame == 1, "A node clear saves once, on the next frame (%d now, %d next)" % [synchronous, next_frame])
	t.control("the pre-fix handler (%d synchronous saves)" % old, old != 0)

## --- 9. hitstop ----------------------------------------------------------------------------------

func _death_hitstop() -> void:
	var w: CombatWorld = _fresh()
	for i: int in range(100): _frame()
	_kill_player(w)
	var want: int = GameTuning.hitstop_ticks(&"player_hit") + RunController.DEATH_HITSTOP_TICKS
	print("measure: hitstop after the killing hit and the death beat = %d (player_hit %d + death %d)" % [w.hitstop_remaining, GameTuning.hitstop_ticks(&"player_hit"), RunController.DEATH_HITSTOP_TICKS])
	t.check(w.hitstop_remaining == want, "The death beat's hitstop adds on top of the killing hit's (%d, want %d)" % [w.hitstop_remaining, want])
	app._reboot()
	var extend: CombatWorld = _world()
	extend.request_hitstop(GameTuning.hitstop_ticks(&"player_hit"), &"player_hit")
	extend.request_hitstop(RunController.DEATH_HITSTOP_TICKS, &"death")
	t.control("the death request as an extend (%d)" % extend.hitstop_remaining, extend.hitstop_remaining != want)
	_release(extend)
	var boss: CombatWorld = _world()
	var granted: int = boss.request_hitstop(GameTuning.hitstop_ticks(&"boss_kill"), &"boss_kill")
	_release(boss)
	t.check(granted == GameTuning.hitstop_ticks(&"boss_kill"), "The boss kill's hitstop is granted in full (%d of %d)" % [granted, GameTuning.hitstop_ticks(&"boss_kill")])
	var old: CombatWorld = _world()
	var old_granted: int = old.request_hitstop(12, &"boss_kill")
	_release(old)
	t.control("the pre-fix 12-tick boss kill (%d granted)" % old_granted, old_granted != 12)

## --- 10. a cached node at a warp commit ----------------------------------------------------------

func _cached_hold(locked: bool) -> bool:
	var w: CombatWorld = _fresh()
	var target: Vector2i = app.campaign.neighbours_of(Vector2i.ZERO)[0]
	app._enter_sector(target, w.arena.entry_position(target), false)
	app._enter_sector(Vector2i.ZERO, w.arena.center, false) # leaves `target` in the cache
	w.warp_phase = CombatWorld.WARP_BREAK if locked else CombatWorld.WARP_NONE
	var cached: bool = w.encounter_records.has(w._sector_key(app.campaign.sector_at(target, w.elapsed)))
	w.start_sector(app.campaign.sector_at(target, w.elapsed))
	var hold: bool = w._wave_arrival_hold
	w._warp_finish()
	return cached and hold

func _cached_arrival_hold() -> void:
	var fixed: bool = _cached_hold(true)
	t.check(fixed, "A cached node swapped in at a warp commit holds its wave clock until the arrival")
	t.control("the same cached swap outside a warp (hold %s)" % _cached_hold(false), not _cached_hold(false))

## --- 11. the light bank after a regression, and the pace state across a save --------------------

func _bank_and_pace() -> void:
	var w: CombatWorld = _world()
	w.collect_light(80.0, "fire")
	w.evolve_hull("player_fire_t2_standard_a")
	w.light_bank = 1000.0
	var tier2_cap: float = w.light_bank_cap()
	w.light_bank = tier2_cap
	w.player_invulnerable = 0.0
	w.player.invulnerable = 0.0
	w.light_total = GameTuning.regression_floor(2) + 0.5
	w._damage_actor(w.player, 20.0, 1)
	var cap: float = w.light_bank_cap()
	print("measure: regression T2 -> T%d: bank %.1f (cap %.1f; T2 cap was %.1f)" % [w.player_tier, w.light_bank, cap, tier2_cap])
	t.check(w.player_tier == 1 and w.light_bank <= cap + 0.0001, "After a regression the bank is within the lower tier's cap (%.1f <= %.1f)" % [w.light_bank, cap])
	t.control("the bank the regression would have kept unclamped (%.1f > %.1f)" % [tier2_cap, cap], tier2_cap > cap + 0.0001)
	w.combo_count = 5
	w.combo_timer = 1.25
	w._combo_drain_accum = 0.5
	w.decay_suppress_timer = 0.75
	var snap: Dictionary = w.snapshot().duplicate(true)
	var pace: Array = [w.combo_count, w.combo_timer, w._combo_drain_accum, w.decay_suppress_timer]
	var restored: CombatWorld = _world()
	restored.restore(snap)
	var got: Array = [restored.combo_count, restored.combo_timer, restored._combo_drain_accum, restored.decay_suppress_timer]
	snap.erase("pace")
	restored.restore(snap)
	var without: Array = [restored.combo_count, restored.combo_timer, restored._combo_drain_accum, restored.decay_suppress_timer]
	print("measure: pace %s -> restored %s (without the saved block %s)" % [pace, got, without])
	t.check(str(got) == str(pace), "The combo and decay suppression survive a save/restore (%s)" % [got])
	t.control("the snapshot without its pace block (%s)" % [without], str(without) != str(pace))
	_release(restored)
	_release(w)
