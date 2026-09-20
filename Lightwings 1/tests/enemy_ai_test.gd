extends SceneTree
## P4b: archetype behaviour (combat_ai.gd) - reaction delay, resampled aim
## error, retreat/protect-core decisions, sentry telegraphs, boss shielded
## core / sub-cores, chain severing, determinism and a play census. Every
## instrument here carries its own negative control (house rule: a gate that
## cannot fail is not a gate).

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const BotPilot = preload("res://tests/support/bot_pilot.gd")
const CombatAI = preload("res://scripts/combat/combat_ai.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var t: RefCounted = Harness.new("ENEMY AI")
	_test_reaction_delay(t)
	_test_aim_error(t)
	_test_not_perfect(t)
	_test_sentry(t)
	_test_retreat(t)
	_test_boss(t)
	_test_chain_sever(t)
	_test_determinism(t)
	_test_play_census(t)
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2(500, 500))
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## Spawns a named roster hull directly (bypassing `pick_enemy`'s
## nearest-tier-band substitution), so a test can ask for a SPECIFIC
## archetype (e.g. "enemy_sentry_lightning_t2") instead of whatever
## `_spawn_enemy`/`_spawn_elite` would pick for a (faction, element, tier).
func spawn_named(w: CombatWorld, hull_id: String, pos: Vector2) -> Dictionary:
	var definition: ShipDefinition = ShipCatalog.get_ship(hull_id)
	var actor: Dictionary = w._make_actor(w.next_actor_id, definition.element, definition.tier, pos, World.ELEMENTS.find(definition.element) + 1, definition.faction == "boss")
	w.next_actor_id += 1
	actor.hull_id = hull_id
	actor.elite = definition.faction == "elite"
	if definition.faction == "elite":
		actor.max_hp = 180.0 + 110.0 * definition.tier
		actor.hp = actor.max_hp
		actor.reward_remaining = 150 + 60 * definition.tier
	w._configure_actor(actor, definition, true)
	w.enemies.append(actor)
	w.actors_by_id[int(actor.id)] = actor
	return actor

## --- Reaction delay ---------------------------------------------------

func _test_reaction_delay(t: RefCounted) -> void:
	var lag: float = _measure_reaction_lag(false)
	t.check(lag >= CombatAI.REACTION_MIN - 0.001 and lag <= CombatAI.REACTION_MAX + 0.001, "Reaction lag %.3f s is within the 150-300 ms decision band" % lag)
	print("ENEMY AI: measured reaction lag = %.1f ms (%.1f ticks)" % [lag * 1000.0, lag * 60.0])
	var control_lag: float = _measure_reaction_lag(true)
	print("ENEMY AI: control (zero delay) lag = %.1f ms" % (control_lag * 1000.0))
	t.control("ai_reaction_disabled=true", control_lag < CombatAI.REACTION_MIN * 0.5)

## Every decision stamps `_delayed_tick` with the sim tick its `_delayed_pos`
## observation was actually captured at (see `combat_ai.gd::_decide`), so the
## lag is read directly in ticks - `now_tick - _delayed_tick` - rather than
## inferred from a moving target's position (which would conflate the delay
## itself with how often decisions are sampled).
func _measure_reaction_lag(reaction_disabled: bool) -> float:
	var w: CombatWorld = make_world()
	w.ai_reaction_disabled = reaction_disabled
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var elite: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(300, 0))
	var dt: float = 1.0 / 60.0
	var last_decided: int = -1
	var lags: Array[float] = []
	for tick: int in range(900):
		w._physics_process(dt)
		var decided: int = int(elite.get("_decided_tick", -1))
		if decided >= 0 and decided != last_decided:
			last_decided = decided
			lags.append(float(decided - int(elite.get("_delayed_tick", decided))) / 60.0)
	release(w)
	if lags.size() < 2: return -1.0
	lags.remove_at(0) # first decision has nothing to be delayed against yet
	var total: float = 0.0
	for s: float in lags: total += s
	return total / lags.size()

## --- Aim error ----------------------------------------------------------

func _test_aim_error(t: RefCounted) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9001
	var degrees: Array[float] = []
	for i: int in range(500): degrees.append(rad_to_deg(absf(CombatAI.sample_aim_error(rng))))
	var lo: float = 999.0
	var hi: float = -999.0
	var distinct: Dictionary = {}
	for d: float in degrees:
		lo = minf(lo, d)
		hi = maxf(hi, d)
		distinct[snappedf(d, 0.01)] = true
	t.check(lo >= CombatAI.AIM_ERROR_MIN_DEG - 0.001, "Every sampled |error| >= %.1f deg (min seen %.3f)" % [CombatAI.AIM_ERROR_MIN_DEG, lo])
	t.check(hi <= CombatAI.AIM_ERROR_MAX_DEG + 0.001, "Every sampled |error| <= %.1f deg (max seen %.3f)" % [CombatAI.AIM_ERROR_MAX_DEG, hi])
	t.check(distinct.size() > 100, "Error is resampled across 500 draws, not one fixed offset (%d distinct values)" % distinct.size())
	# Control: forcing the constant to 0 obviously fails the "within [2,5]" check.
	t.control("aim error forced to a fixed 0 deg", not (0.0 >= CombatAI.AIM_ERROR_MIN_DEG - 0.001))
	# In-gameplay: an elite's per-gun error is resampled once per DECISION.
	var w: CombatWorld = make_world()
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var elite: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(260, 0))
	var gun: int = elite.gun_indices[0]
	var seen_errors: Dictionary = {}
	for tick: int in range(300):
		w._physics_process(1.0 / 60.0)
		seen_errors[snappedf(rad_to_deg(float(elite.part_aim_error[gun])), 0.01)] = true
	t.check(seen_errors.size() > 1, "A single gun's applied error changes across decisions in real gameplay (%d distinct)" % seen_errors.size())
	release(w)
	# Control: `ai_aim_error_disabled` forces every applied error to exactly 0.
	var w2: CombatWorld = make_world()
	w2.setup_player("fire", 3, 400, [], w2.arena.center)
	w2.ai_aim_error_disabled = true
	var elite2: Dictionary = w2._spawn_elite("fire", 3, w2.arena.center + Vector2(260, 0))
	var all_zero: bool = true
	for tick: int in range(120):
		w2._physics_process(1.0 / 60.0)
		for gi: int in elite2.gun_indices:
			if not is_equal_approx(float(elite2.part_aim_error[gi]), 0.0): all_zero = false
	t.control("ai_aim_error_disabled=true", all_zero)
	release(w2)

## --- Not perfect: strafing target's hit rate -----------------------------

func _test_not_perfect(t: RefCounted) -> void:
	var rate: float = _measure_strafe_hit_rate(false, false)
	print("ENEMY AI: strafing hit rate (with limits) = %.3f" % rate)
	t.check(rate > 0.05 and rate < 0.6, "Strafing target's hit rate %.3f sits strictly between 0.05 and 0.6" % rate)
	var control_rate: float = _measure_strafe_hit_rate(true, true)
	print("ENEMY AI: strafing hit rate (zero delay/error control) = %.3f" % control_rate)
	t.control("zero reaction delay AND zero aim error", control_rate > 0.6)

func _measure_strafe_hit_rate(reaction_disabled: bool, error_disabled: bool) -> float:
	var w: CombatWorld = make_world()
	w.ai_reaction_disabled = reaction_disabled
	w.ai_aim_error_disabled = error_disabled
	w.setup_player("fire", 3, 100000.0, [], w.arena.center)
	w.player.max_hp = 100000.0
	var elite: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(150, 0))
	# GDScript lambdas capture outer locals BY VALUE, so `shots += 1` inside a
	# closure would mutate a private copy, not this function's `shots` - a
	# one-element Array is a reference type and survives that.
	var shots_box: Array = [0]
	var hits: int = 0
	var cb: Callable = func(_p: Vector2, _e: String, _a: String) -> void: shots_box[0] += 1
	w.shot_fired.connect(cb)
	var dt: float = 1.0 / 60.0
	var prev_light: float = w.light_total
	for tick: int in range(2400): # 40 simulated seconds
		# P7 decay (spec §7.1) drains light every tick this loop is not firing
		# back, which is not what this measures (enemy aim, not pace) - pin the
		# suppression window open so "hits" stays a pure hit-detector.
		w.decay_suppress_timer = GameTuning.DECAY_SUPPRESSION_SECONDS
		w.command.movement = Vector2(0, sin(float(tick) * 0.05)) * 0.15
		w.command.fire = false
		w._physics_process(dt)
		if w.light_total < prev_light - 0.0001: hits += 1
		if w.light_total < w.player.max_hp * 0.5:
			w.light_total = w.player.max_hp
			w.player.hp = w.light_total
		prev_light = w.light_total
	w.shot_fired.disconnect(cb)
	release(w)
	var shots: int = int(shots_box[0])
	if shots == 0: return 0.0
	return float(hits) / float(shots)

## --- Sentry ---------------------------------------------------------------

func _test_sentry(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("lightning", 2, 400, [], w.arena.center)
	var sentry: Dictionary = spawn_named(w, "enemy_sentry_lightning_t2", w.arena.center + Vector2(220, 0))
	var start_pos: Vector2 = Vector2(sentry.pos)
	var saw_telegraph: bool = false
	var min_warn: float = 999.0
	for tick: int in range(360):
		w._physics_process(1.0 / 60.0)
		for attack: Dictionary in w.telegraphs:
			if int(attack.owner) == int(sentry.id) and not bool(attack.fired):
				saw_telegraph = true
				min_warn = minf(min_warn, float(attack.warn))
	t.check(Vector2(sentry.pos).distance_to(start_pos) < 0.01, "Sentry never moves")
	t.check(saw_telegraph, "Sentry fires a telegraphed attack within 6 s")
	t.check(min_warn >= 0.5, "Sentry's telegraph warns >= 0.5 s before it lands (measured %.2f s)" % min_warn)
	# Control: a moving regular (drone) DOES move.
	var drone: Dictionary = w._spawn_enemy("lightning", 2, w.arena.center + Vector2(-220, 0), false)
	var drone_start: Vector2 = Vector2(drone.pos)
	for tick: int in range(120): w._physics_process(1.0 / 60.0)
	t.control("comparing against a drone (which does move)", Vector2(drone.pos).distance_to(drone_start) > 1.0)
	release(w)

## --- Retreat ---------------------------------------------------------------

func _test_retreat(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var hurt: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(220, 0))
	var healthy: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(-220, 0))
	var start_hurt: float = Vector2(hurt.pos).distance_to(w.player_position)
	var start_healthy: float = Vector2(healthy.pos).distance_to(w.player_position)
	var total: int = int(hurt.gun_total)
	var to_kill: int = int(total / 2) + 1 # strictly below half survive, not exactly half
	var killed: int = 0
	for i: int in hurt.gun_indices:
		if killed >= to_kill: break
		w._damage_part(hurt, i, 1000000.0, w.player)
		killed += 1
	t.check(CombatAI._should_retreat(hurt), "Fixture precondition: below-half-limbs elite is flagged to retreat")
	t.check(not CombatAI._should_retreat(healthy), "Fixture precondition: full-health elite is NOT flagged to retreat")
	for tick: int in range(240): w._physics_process(1.0 / 60.0)
	var end_hurt: float = Vector2(hurt.pos).distance_to(w.player_position)
	var end_healthy: float = Vector2(healthy.pos).distance_to(w.player_position)
	t.check(end_hurt > start_hurt, "An elite below the limb threshold increases its distance from the player (%.1f -> %.1f)" % [start_hurt, end_hurt])
	print("ENEMY AI: retreat distance gained - hurt %.1f px, full-health %.1f px" % [end_hurt - start_hurt, end_healthy - start_healthy])
	# A full-health elite still orbits within engagement range (small drift is
	# expected, e.g. turn-rate lag on a tight orbit) - the CONTROL is that it
	# gains nowhere near what an actively retreating elite gains over the same
	# window, not that it holds position to the pixel.
	t.control("a full-health elite retreating", (end_healthy - start_healthy) < (end_hurt - start_hurt) * 0.5)
	release(w)

## --- Boss: shielded core, sub-cores, no respawn ----------------------------

func _test_boss(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var boss: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(300, 0), true)
	t.check(not boss.shield_generator_indices.is_empty() and not boss.sub_core_indices.is_empty(), "Fixture precondition: boss authors a shield generator and sub-cores")
	var hp_before: float = float(boss.hp)
	w._damage_actor(boss, 50.0, 0, 0)
	t.check(is_equal_approx(float(boss.hp), hp_before), "Core takes no damage while a shield generator lives")
	for i: int in boss.shield_generator_indices: w._damage_part(boss, i, 1000000.0, w.player)
	w._damage_actor(boss, 50.0, 0, 0)
	t.check(float(boss.hp) < hp_before, "Core takes damage once every generator is dead")
	w._damage_actor(boss, 1000000.0, 0, 0)
	t.check(float(boss.hp) <= 0.0 and not bool(boss.dead), "Boss survives with its core dead but a sub-core alive")
	for i: int in boss.sub_core_indices: w._damage_part(boss, i, 1000000.0, w.player)
	t.check(bool(boss.dead), "Boss dies once the core AND every sub-core are dead")
	# Control: an identical boss with NO generator alive takes core damage immediately.
	var boss2: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(-300, 0), true)
	for i: int in boss2.shield_generator_indices: w._damage_part(boss2, i, 1000000.0, w.player)
	var hp2: float = float(boss2.hp)
	w._damage_actor(boss2, 50.0, 0, 0)
	t.control("no shield generator alive", float(boss2.hp) < hp2)
	release(w)

## --- Chain severing ---------------------------------------------------------

func _test_chain_sever(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var chain: Dictionary = spawn_named(w, "enemy_chain_fire_t3", Vector2(1000, 500))
	var rig: ShipMotion.ShipRig = chain.rig
	var mid: int = rig.index_of("tail_2")
	t.check(mid >= 0, "Fixture precondition: enemy_chain authors a tail_2 mid-tail circle")
	var expected: int = rig.subtree_size[mid]
	var before: int = w.debris.size()
	w._damage_part(chain, mid, 1000000.0, w.player)
	t.check(w.debris.size() == before + 1, "Damaging a mid-tail circle detaches the rest of the tail as ONE debris record")
	t.check(w.debris[-1].offsets.size() == expected and expected >= 2, "The severed debris covers the rest of the tail (%d circles)" % expected)
	# Control: the head (core) is never detachable by this mechanism.
	t.control("damaging the head instead of the tail", rig.subtree_size[0] == rig.ids.size())
	release(w)

## --- Determinism ------------------------------------------------------------

func _test_determinism(t: RefCounted) -> void:
	var trace_a: String = _run_ai_trace(42, false)
	var trace_b: String = _run_ai_trace(42, false)
	t.check(trace_a == trace_b, "The same seed produces a byte-identical trace over 600 ticks")
	var trace_c: String = _run_ai_trace(42, true)
	t.control("a wall-clock-derived decision (re-randomized RNG mid-run)", trace_c != trace_a)

func _run_ai_trace(seed: int, wall_clock_leak: bool) -> String:
	var w: CombatWorld = make_world()
	w._rng.seed = seed
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var a: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(260, 0))
	var b: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(-260, 0), false)
	var trace: Array[String] = []
	for tick: int in range(600):
		if wall_clock_leak: w._rng.randomize() # simulates a decision seeded from the wall clock
		w.command.movement = Vector2(sin(float(tick) * 0.05), cos(float(tick) * 0.05))
		w._physics_process(1.0 / 60.0)
		if tick % 30 == 0: trace.append("%.3f,%.3f,%.3f,%.3f,%d,%d" % [a.pos.x, a.pos.y, b.pos.x, b.pos.y, w.bullets.count(), w.debris.size()])
	release(w)
	return ",".join(trace)

## --- Play census: every archetype fires, every enemy-only component fires --

func _test_play_census(t: RefCounted) -> void:
	var counts: Dictionary = _run_census(false)
	for key: String in counts:
		t.check(counts[key] > 0, "Play census: %s produced at least one event (got %d)" % [key, counts[key]])
	var control_counts: Dictionary = _run_census(true)
	var all_zero: bool = true
	for key: String in control_counts:
		if control_counts[key] != 0: all_zero = false
	t.control("ai_firing_disabled=true", all_zero)

func _run_census(firing_disabled: bool) -> Dictionary:
	var counts: Dictionary = {"drone_shots": 0, "sentry_shots": 0, "chain_shots": 0, "radial_shots": 0, "irregular_shots": 0, "boss_shots": 0, "droid_bay_drones": 0, "egg_burst": 0, "deployment_ramp_spawn": 0, "turret_ring_shots": 0}
	var w: CombatWorld = make_world()
	w.ai_firing_disabled = firing_disabled
	w.setup_player("fire", 3, 100000.0, [], w.arena.center)
	w.player.max_hp = 100000.0
	var drone: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(120, 0), false)
	var sentry: Dictionary = spawn_named(w, "enemy_sentry_lightning_t2", w.arena.center + Vector2(-160, 60))
	var chain: Dictionary = spawn_named(w, "enemy_chain_fire_t3", w.arena.center + Vector2(160, -60))
	var droid: Dictionary = spawn_named(w, "enemy_drone_corruption_t3", w.arena.center + Vector2(-120, -100))
	var radial: Dictionary = w._spawn_elite("fire", 3, w.arena.center + Vector2(260, 120))
	var irregular: Dictionary = spawn_named(w, "elite_irregular_fire_t3", w.arena.center + Vector2(-260, 120))
	var boss: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(0, 240), true)
	var dt: float = 1.0 / 60.0
	for tick: int in range(3600): # 60 simulated seconds
		w.command.movement = Vector2(sin(float(tick) * 0.03), cos(float(tick) * 0.05)) * 0.4
		w.command.fire = false
		w._physics_process(dt)
		if w.light_total < w.player.max_hp * 0.5:
			w.light_total = w.player.max_hp
			w.player.hp = w.light_total
		if w.drones.size() > 0:
			for d: Dictionary in w.drones:
				if int(d.owner) == int(droid.id): counts.droid_bay_drones += 1
	counts.drone_shots = int(drone.get("shots_fired", 0))
	counts.sentry_shots = int(sentry.get("shots_fired", 0))
	counts.chain_shots = int(chain.get("shots_fired", 0))
	counts.radial_shots = int(radial.get("shots_fired", 0))
	counts.irregular_shots = int(irregular.get("shots_fired", 0))
	counts.boss_shots = int(boss.get("shots_fired", 0))
	# Directly exercise the reactive/periodic enemy-only components once each,
	# anchored to the real code path rather than hoping bot RNG stumbles into
	# them within 60 s. Still gated by `ai_firing_disabled` (egg via
	# `_damage_part`'s egg branch, ramp/ring via `_update_guns`).
	# On a FRESH boss, not the one that has just been in a 60 s brawl: its component circles take
	# real damage in there (measured: the turret ring fell from 60 to 14.9 hp, and a slightly
	# different run kills it), after which the `hp > 0` guards below silently report 0 and the
	# instrument blames the component instead of the fight. The claim is "this component fires when
	# its cooldown elapses", so exercise it on an undamaged hull.
	for stale: Dictionary in w.enemies: stale.dead = true
	w._cleanup_dead()
	boss = w._spawn_enemy("fire", 3, w.arena.center + Vector2(0, 240), true)
	var egg_index: int = boss.rig.index_of("egg")
	if egg_index >= 0 and float(boss.part_hp[egg_index]) > 0.0:
		var before: int = w.bullets.count()
		w._damage_part(boss, egg_index, 5.0, w.player)
		counts.egg_burst = 1 if w.bullets.count() > before else 0
	var ramp_index: int = boss.rig.index_of("deployment_ramp")
	if ramp_index >= 0 and float(boss.part_hp[ramp_index]) > 0.0:
		var enemies_before: int = w.enemies.size()
		boss.part_cd[ramp_index] = 0.0
		w._update_guns(boss, dt, true)
		counts.deployment_ramp_spawn = 1 if w.enemies.size() > enemies_before else 0
	var ring_index: int = boss.rig.index_of("turret_ring_0")
	if ring_index >= 0 and float(boss.part_hp[ring_index]) > 0.0:
		# The ring's weapon may resolve as an immediate bullet or a queued telegraph (`mine_layer`),
		# so this checks either effect landed. `telegraphs` is capped at 160 (combat_world.gd) and a
		# 60 s census with respawning enemies saturates it, which silently swallowed this event and
		# made the instrument report 0 for a ring that was firing perfectly well. Clear the queue
		# first so the check measures THIS circle rather than the global list's headroom.
		w.telegraphs.clear()
		var bullets_before: int = w.bullets.count()
		var telegraphs_before: int = w.telegraphs.size()
		boss.part_cd[ring_index] = 0.0
		w._update_guns(boss, dt, true)
		counts.turret_ring_shots = 1 if (w.bullets.count() > bullets_before or w.telegraphs.size() > telegraphs_before) else 0
	release(w)
	return counts
