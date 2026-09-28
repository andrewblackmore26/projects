extends SceneTree
## P4b: archetype behaviour (combat_ai.gd) - reaction delay, resampled aim
## error, retreat/protect-core decisions, sentry telegraphs, boss shielded
## core / sub-cores, chain severing, determinism and a play census. Every
## instrument here carries its own negative control (house rule: a gate that
## cannot fail is not a gate).
##
## Migrated 2026-09-21 to the ship design spec's rail roster (every hull in `content/ships/`
## replaced - core stack + dashed rails + hub/pod clusters + set-piece weapons, ShipDefinition
## schema_version 4, `is_rail_hull()`). What changed here and why:
## - Chain link ids are now positional (`c0`..`c4`, ship_compiler.gd); `tail_2` no longer exists.
## - `laser_prong` is retired (no set piece mounts it any more), so a sentry firing a TELEGRAPHED
##   attack is no longer a spec guarantee - a lightning t2 sentry's loadout (coil_pair/wedge_pair
##   primary, hook_node secondary) mounts no telegraphed weapon at all. What survives is "a sentry
##   fires" and "it never moves"; the telegraph-warn-time claim is retired here (still covered on a
##   hull that DOES mount a telegraphed weapon, by the chain-sever fixture's fire+t3 chain, which
##   mounts drop_cradle/burst_ring).
## - The boss's sub-cores are retired by user decision; only the shield generator survives as its
##   "second core stack". `sub_core_indices` is now always empty, so `_boss_can_die` is always
##   true: a boss with its shield down dies the instant its core hp reaches 0, it does not linger
##   with a dead core waiting on a sub-core.
## - Enemy-only components egg, deployment ramp, turret ring and droid bay are retired by user
##   decision; the play census's checks and direct-exercise code for them are removed outright.
## - The strafing hit-rate instrument's absolute band was measured on the v0.3 hulls; the rail
##   fire elite mounts `incendiary_spores` (ember_rack), whose damage-over-time cloud scores many
##   hit-ticks per activation, so the metric's SCALE changed even though the claim ("an elite is
##   not perfect") did not - restated relative to a measured zero-limits control.

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

## The absolute band `0.05 < rate < 0.6` was measured on the v0.3 hulls. On the rail roster a fire
## elite mounts `incendiary_spores` (ember_rack), whose cloud damages every tick it lingers, so one
## shot activation now scores dozens of hit-ticks and the metric's SCALE changed (measured
## 2026-09-21: with human limits = 2.038, with zero reaction delay AND zero aim error = 4.943). The
## claim under test - "an elite is not perfect" - survives; restated RELATIVELY against the same
## fixture's own perfect-aim control instead of a hand-picked absolute constant.
func _test_not_perfect(t: RefCounted) -> void:
	var rate: float = _measure_strafe_hit_rate(false, false)
	print("ENEMY AI: strafing hit rate (with limits) = %.3f" % rate)
	var control_rate: float = _measure_strafe_hit_rate(true, true)
	print("ENEMY AI: strafing hit rate (zero delay/error control) = %.3f" % control_rate)
	t.check(rate > 0.0, "Strafing target's hit rate with human limits is above zero (%.3f)" % rate)
	t.check(rate < control_rate * 0.8, "Human limits keep the hit rate well below the zero-delay/zero-error control (%.3f vs %.3f)" % [rate, control_rate])
	t.control("zero reaction delay AND zero aim error", control_rate > rate)

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

## RETIRED (2026-09-21): "Sentry fires a telegraphed attack" and "the telegraph warns >= 0.5 s"
## both assumed `laser_prong`, which no set piece mounts any more (spec §6.3). An
## `enemy_sentry_lightning_t2` now mounts coil_pair/wedge_pair (bolt/ricochet, both instant
## bullets, no telegraph) as its core weapon and hook_node (arc_tether, also untelegraphed) on its
## hubs - a lightning sentry's loadout has no telegraphed weapon at all, so the old claim is no
## longer a spec guarantee for every sentry. What survives - "a sentry never moves" and "a sentry
## still fires" - is what the check below asserts; the telegraph-timing claim (still true of any
## weapon that DOES go through `_queue_attack`, spec v0.3 §16's ">= 0.5 s" rule) is exercised by
## `_test_chain_sever`'s fire+t3 chain, which mounts drop_cradle/burst_ring.
func _test_sentry(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("lightning", 2, 400, [], w.arena.center)
	var sentry: Dictionary = spawn_named(w, "enemy_sentry_lightning_t2", w.arena.center + Vector2(220, 0))
	var start_pos: Vector2 = Vector2(sentry.pos)
	var shots_before: int = int(sentry.get("shots_fired", 0))
	for tick: int in range(360):
		w._physics_process(1.0 / 60.0)
	t.check(Vector2(sentry.pos).distance_to(start_pos) < 0.01, "Sentry never moves")
	t.check(int(sentry.get("shots_fired", 0)) > shots_before, "Sentry fires within 6 s (shots_fired %d -> %d)" % [shots_before, int(sentry.get("shots_fired", 0))])
	# Control: a moving regular (drone) DOES move.
	var drone: Dictionary = w._spawn_enemy("lightning", 2, w.arena.center + Vector2(-220, 0), false)
	var drone_start: Vector2 = Vector2(drone.pos)
	for tick: int in range(120): w._physics_process(1.0 / 60.0)
	t.control("comparing against a drone (which does move)", Vector2(drone.pos).distance_to(drone_start) > 1.0)
	# Control for the "sentry fires" line specifically: `ai_firing_disabled` must silence it.
	var w2: CombatWorld = make_world()
	w2.ai_firing_disabled = true
	w2.setup_player("lightning", 2, 400, [], w2.arena.center)
	var sentry2: Dictionary = spawn_named(w2, "enemy_sentry_lightning_t2", w2.arena.center + Vector2(220, 0))
	for tick: int in range(360): w2._physics_process(1.0 / 60.0)
	t.control("ai_firing_disabled=true", int(sentry2.get("shots_fired", 0)) == 0)
	release(w2)
	release(w)
	_test_telegraph_warning(t)

## Spec v0.3 §16: "any attack that cannot be dodged on reaction shows a warning >= 0.5 s before it
## lands". A sentry's own loadout no longer mounts one (see above), so each telegraphed enemy weapon is
## fired from a sentry directly and its warning is MEASURED in ticks from the activation to the tick
## its telegraph goes off - not read from the number it was queued with. M8 re-ran it after enemy
## movement and shot speeds became ratios of the player's.
const TELEGRAPHED: Array[String] = ["explosives", "laser_prong", "mine_layer", "discharge", "collapse_charge", "nova_pulse", "blink_mine", "refract_beam", "incendiary_spores"]

func _warning_seconds(w: CombatWorld, sentry: Dictionary, id: String, forced_warn: float = -1.0) -> float:
	w.telegraphs.clear()
	if forced_warn >= 0.0: w._queue_attack(sentry, "explosive", Vector2(sentry.pos) + Vector2(200, 0), Vector2.ZERO, forced_warn, 1.0, 40.0)
	else: w._activate_component(sentry, id, Vector2(sentry.pos), Vector2.RIGHT)
	if w.telegraphs.is_empty(): return -1.0
	for tick: int in range(1, 241):
		w._update_telegraphs(1.0 / 60.0)
		for attack: Dictionary in w.telegraphs:
			if bool(attack.fired): return float(tick) / 60.0
	return -1.0

func _test_telegraph_warning(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("lightning", 2, 400, [], w.arena.center)
	var sentry: Dictionary = spawn_named(w, "enemy_sentry_lightning_t2", w.arena.center + Vector2(-600, 0))
	var shortest: float = INF
	for id: String in TELEGRAPHED:
		var seconds: float = _warning_seconds(w, sentry, id)
		print("ENEMY AI: telegraph %s warns %.3f s" % [id, seconds])
		t.check(seconds >= 0.5 - 0.0001, "A sentry's %s warns %.3f s before it lands (>= 0.5 s)" % [id, seconds])
		if seconds >= 0.0: shortest = minf(shortest, seconds)
	print("ENEMY AI: shortest telegraph warning = %.3f s" % shortest)
	# Control: the pre-P8 0.35 s warning, through the same instrument.
	var old: float = _warning_seconds(w, sentry, "", 0.35)
	t.control("a telegraph queued with the pre-P8 0.35 s warning (%.3f s)" % old, not (old >= 0.5 - 0.0001))
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

## --- Boss: shielded core, no respawn ----------------------------------------
## RETIRED (2026-09-21, user decision): the boss's sub-cores are retired; only its shield
## generator survives as the "second core stack" (spec §14 note in the scope header). `_boss_can_die`
## (combat_world.gd) reads `sub_core_indices`, which is now always empty for every actor, so it is
## always true - a boss whose shield is down dies THE INSTANT its core reaches 0 hp, it no longer
## lingers "dead core, alive sub-core". Replaced the two sub-core checks with the new true behaviour.

func _test_boss(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.setup_player("fire", 3, 400, [], w.arena.center)
	var boss: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(300, 0), true)
	t.check(not boss.shield_generator_indices.is_empty(), "Fixture precondition: boss authors a shield generator")
	t.check(boss.sub_core_indices.is_empty(), "Fixture precondition: sub-cores are retired (always empty on the rail roster)")
	var hp_before: float = float(boss.hp)
	w._damage_actor(boss, 50.0, 0, 0)
	t.check(is_equal_approx(float(boss.hp), hp_before), "Core takes no damage while a shield generator lives")
	for i: int in boss.shield_generator_indices: w._damage_part(boss, i, 1000000.0, w.player)
	w._damage_actor(boss, 50.0, 0, 0)
	t.check(float(boss.hp) < hp_before, "Core takes damage once every generator is dead")
	w._damage_actor(boss, 1000000.0, 0, 0)
	t.check(float(boss.hp) <= 0.0 and bool(boss.dead), "Boss dies the instant its core reaches 0 hp once the shield is down (no sub-core to linger on)")
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
	# Chain link ids are positional now: c0..c4, each the child of the one before it
	# (ship_compiler.gd `_chain`) - the old id `tail_2` no longer exists. c2 is still a mid-tail
	# link (c0 and c2 are the two links wired as hubs; see `ShipRecipe._enemy`'s chain branch).
	var mid: int = rig.index_of("c2")
	t.check(mid >= 0, "Fixture precondition: enemy_chain authors a c2 mid-tail circle")
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

## --- Play census: every archetype fires -------------------------------------
## RETIRED (2026-09-21, user decision): egg, deployment ramp, turret ring and droid bay are
## retired enemy-only components (spec scope header). Their census keys and the code that directly
## exercised them (`egg_index`/`ramp_index`/`ring_index`, the `droid`/`w.drones` loop) are removed
## outright - there is no replacement, the mechanics no longer exist. What remains - "every
## archetype fires at least once in 60 s" - is still checked for the archetypes the roster still
## has, plus the new `heavy` elite.

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
	var counts: Dictionary = {"drone_shots": 0, "sentry_shots": 0, "chain_shots": 0, "radial_shots": 0, "irregular_shots": 0, "heavy_shots": 0, "boss_shots": 0}
	var w: CombatWorld = make_world()
	w.ai_firing_disabled = firing_disabled
	w.setup_player("fire", 3, 100000.0, [], w.arena.center)
	w.player.max_hp = 100000.0
	var drone: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(120, 0), false)
	var sentry: Dictionary = spawn_named(w, "enemy_sentry_lightning_t2", w.arena.center + Vector2(-160, 60))
	var chain: Dictionary = spawn_named(w, "enemy_chain_fire_t3", w.arena.center + Vector2(160, -60))
	var radial: Dictionary = w._spawn_elite("fire", 4, w.arena.center + Vector2(260, 120))
	var irregular: Dictionary = spawn_named(w, "elite_irregular_fire_t3", w.arena.center + Vector2(-260, 120))
	var heavy: Dictionary = spawn_named(w, "elite_heavy_fire_t3", w.arena.center + Vector2(-260, -120))
	var boss: Dictionary = w._spawn_enemy("fire", 3, w.arena.center + Vector2(0, 240), true)
	var dt: float = 1.0 / 60.0
	for tick: int in range(3600): # 60 simulated seconds
		w.command.movement = Vector2(sin(float(tick) * 0.03), cos(float(tick) * 0.05)) * 0.4
		w.command.fire = false
		w._physics_process(dt)
		if w.light_total < w.player.max_hp * 0.5:
			w.light_total = w.player.max_hp
			w.player.hp = w.light_total
	counts.drone_shots = int(drone.get("shots_fired", 0))
	counts.sentry_shots = int(sentry.get("shots_fired", 0))
	counts.chain_shots = int(chain.get("shots_fired", 0))
	counts.radial_shots = int(radial.get("shots_fired", 0))
	counts.irregular_shots = int(irregular.get("shots_fired", 0))
	counts.heavy_shots = int(heavy.get("shots_fired", 0))
	counts.boss_shots = int(boss.get("shots_fired", 0))
	release(w)
	return counts
