extends SceneTree
## Modernization M13: waves, rim spawns and the light economy, measured. Every line has a control
## that must fail:
## - the wave plan is a pure function of the seed (control: another seed differs);
## - the plan's shape: 40/30/30, elites last, the origin's training wave, the boss's add waves;
## - the alive cap holds over a 60 s bot-free run on a dense T6 node (control: cap 999);
## - the first enemy lands <= 1.0 s after a real warp's arrival, 20 seeds, median and max
##   (control: a 1.5 s first-wave delay);
## - no wave-1 spawn is within +-60 deg of the arrival point (control: unconstrained fans);
## - later spawns are telegraphed SPAWN_TELEGRAPH_SECONDS ahead (control: the wave-1 lead);
## - `sector_cleared` fires exactly once, after the last wave (control: the old "list empty" rule);
## - save/restore mid-wave restores the queue, the clock and the dead records, and the restored run
##   spawns on the same ticks (control: the wave block dropped from the save);
## - a revisited node keeps its wave state through the encounter cache;
## - banked overflow is capped at 25 % of the next threshold and paid on evolve (control: cap lifted);
## - the combo window is 3.0 s and frozen while the warp is locked (control: an unlocked tick);
## - the origin's training wave lands 1.0 s in.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("WAVES")
	_plan_deterministic()
	_plan_shape()
	_alive_cap()
	_arrival_timing_and_angles()
	_telegraph_lead()
	_cleared_once()
	_save_restore_mid_wave()
	_cache_round_trip()
	_overflow_bank()
	_combo_window_and_freeze()
	_origin_training_wave()
	_music_intensity()
	await process_frame
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 40, [], w.arena.center)
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func campaign_for(seed_value: int, level: int = 1) -> CampaignState:
	var campaign: CampaignState = CampaignState.new()
	campaign.world_seed = seed_value
	campaign.level = level
	return campaign

func step(w: CombatWorld, ticks: int) -> void:
	for i: int in range(ticks): w._physics_process(STEP)

func kill(w: CombatWorld, actor: Dictionary) -> void:
	actor.invulnerable = 0.0
	w._damage_actor(actor, 1000000.0, 0, 0)

## The first node of `archetype` at ring >= `min_ring` in a level-5 campaign, scanning seeds.
func find_node(archetype: String, min_ring: int) -> Dictionary:
	for seed_value: int in range(1, 60):
		var campaign: CampaignState = campaign_for(seed_value, 5)
		var r: int = campaign.level_radius()
		for x: int in range(-r, r + 1):
			for y: int in range(-r, r + 1):
				var coord: Vector2i = Vector2i(x, y)
				if CampaignState.ring(coord) >= min_ring and campaign.archetype_of(coord) == archetype:
					return campaign.sector_at(coord)
	return {}

func _plan_json(campaign: CampaignState) -> String:
	var r: int = campaign.level_radius()
	var parts: PackedStringArray = []
	for x: int in range(-r, r + 1):
		for y: int in range(-r, r + 1):
			var d: Dictionary = campaign.sector_at(Vector2i(x, y))
			parts.append(JSON.stringify([d.enemy_hulls, d.elite_hulls, d.waves, d.wave_boss_hp, d.wave_first_s]))
	return "|".join(parts)

func _plan_deterministic() -> void:
	var a: String = _plan_json(campaign_for(11, 3))
	var b: String = _plan_json(campaign_for(11, 3))
	var other: String = _plan_json(campaign_for(12, 3))
	t.check(a == b and not a.is_empty(), "The wave plan of every node is identical across two campaigns with the same seed")
	t.control("a different world seed", a != other)

func _plan_shape() -> void:
	var counts: Dictionary = {}
	var shape_failures: int = 0
	var elite_last_failures: int = 0
	var boss_ok: bool = true
	var boss_seen: int = 0
	for seed_value: int in range(1, 21):
		var campaign: CampaignState = campaign_for(seed_value, 3)
		var r: int = campaign.level_radius()
		for x: int in range(-r, r + 1):
			for y: int in range(-r, r + 1):
				var coord: Vector2i = Vector2i(x, y)
				if coord == Vector2i.ZERO: continue
				var d: Dictionary = campaign.sector_at(coord)
				var total: int = d.enemy_hulls.size() + d.elite_hulls.size()
				var seen: Array = []
				for wave: Array in d.waves: seen.append_array(wave)
				seen.sort()
				var expected: Array = range(total)
				if seen != expected: shape_failures += 1
				if d.kind == "boss":
					boss_seen += 1
					if d.waves.size() != GameTuning.BOSS_ADD_WAVE_HP.size() or d.wave_boss_hp != Array(GameTuning.BOSS_ADD_WAVE_HP) or d.boss_hull == "": boss_ok = false
					continue
				if d.waves.size() > GameTuning.WAVE_SPLIT.size(): shape_failures += 1
				for i: int in range(d.elite_hulls.size()):
					if not (d.waves[-1] as Array).has(d.enemy_hulls.size() + i): elite_last_failures += 1
				var bucket: Array = counts.get(d.archetype, [])
				bucket.append(total)
				counts[d.archetype] = bucket
	t.check(shape_failures == 0, "Every node's waves hold each of its hulls exactly once, in at most 3 waves (%d failures)" % shape_failures)
	t.check(elite_last_failures == 0, "Every elite arrives in its node's last wave (%d failures)" % elite_last_failures)
	t.check(boss_seen == 20 and boss_ok, "Each boss node has 2 add waves released at 66%% / 33%% boss HP (%d boss nodes)" % boss_seen)
	for archetype: String in ["transit", "skirmish", "dense", "elite_lair"]:
		var bucket: Array = counts.get(archetype, [])
		bucket.sort()
		if bucket.is_empty(): continue
		print("measure: plan archetype=%s nodes=%d enemies min=%d median=%d max=%d" % [archetype, bucket.size(), bucket[0], bucket[bucket.size() / 2], bucket[-1]])
	t.check(CampaignState.split_waves(9, [0.4, 0.3, 0.3]) == [[0, 1, 2, 3], [4, 5], [6, 7, 8]], "9 enemies split 4/2/3 at 40/30/30 (rounded cumulative boundaries)")
	t.control("a 50/50 split read as the 40/30/30 one", CampaignState.split_waves(9, [0.5, 0.5]) != [[0, 1, 2, 3], [4, 5], [6, 7, 8]])
	var origin: Dictionary = campaign_for(3).sector_at(Vector2i.ZERO)
	var training_ok: bool = origin.waves == [[0, 1, 2]] and is_equal_approx(float(origin.wave_first_s), 1.0)
	for hull: Variant in origin.enemy_hulls: training_ok = training_ok and str(hull).begins_with("enemy_drone_") and str(hull).ends_with("_t1")
	t.check(training_ok, "The origin carries one T1 training wave of 3 drones, 1.0 s in (%s)" % str(origin.enemy_hulls))

## A dense node at ring >= 10 (tier 6, cap 11), nothing fighting back, 60 s.
func _alive_run(cap_override: int) -> Dictionary:
	var node: Dictionary = find_node("dense", 10)
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	w.alive_cap_override = cap_override
	w.start_sector(node)
	var peak: int = 0
	for i: int in range(3600):
		w._physics_process(STEP)
		peak = maxi(peak, w._alive_total())
	var result: Dictionary = {"peak": peak, "cap": w.wave_alive_cap(), "planned": node.enemy_hulls.size() + node.elite_hulls.size(), "tier": int(node.tier), "waves": w.wave_index}
	release(w)
	return result

func _alive_cap() -> void:
	var run: Dictionary = _alive_run(0)
	print("measure: dense node tier=%d planned=%d cap=%d peak_alive=%d waves_released=%d" % [run.tier, run.planned, run.cap, run.peak, run.waves])
	t.check(run.planned > run.cap, "The dense node plans more enemies than its cap, so the cap is exercised (%d > %d)" % [run.planned, run.cap])
	t.check(run.cap == mini(GameTuning.WAVE_ALIVE_CAP_MAX, GameTuning.WAVE_ALIVE_CAP_BASE + int(run.tier) / 2), "The cap is 8 + tier/2, at most 12 (%d at tier %d)" % [run.cap, run.tier])
	t.check(run.peak <= run.cap, "Alive + queued never exceeds the cap over 60 s (peak %d, cap %d)" % [run.peak, run.cap])
	var uncapped: Dictionary = _alive_run(999)
	t.control("alive cap 999 (peak %d)" % uncapped.peak, uncapped.peak > run.cap)

## Drives a real warp out of the origin toward `direction` with a synchronous swap listener, as
## RunController does, and returns the arrival and the first spawn in sim_q plus the wave-1 bearings.
func _warp_into(seed_value: int, direction: Vector2i, first_s: float = -1.0) -> Dictionary:
	var campaign: CampaignState = campaign_for(seed_value)
	var w: CombatWorld = make_world()
	w.start_sector(campaign.sector_at(Vector2i.ZERO))
	var state: Dictionary = {"arrived_q": -1, "arrival": Vector2.ZERO, "wave1": []}
	w.warp_committed.connect(func(dir: Vector2i) -> void:
		campaign.on_enter(campaign.current_sector + dir)
		var sector: Dictionary = campaign.sector_at(campaign.current_sector, w.elapsed)
		if first_s >= 0.0: sector.wave_first_s = first_s
		w.start_sector(sector)
		w.confirm_warp_swap()
		for entry: Dictionary in w.spawn_queue: state.wave1.append(Vector2(entry.pos)))
	w.warp_arrived.connect(func() -> void:
		state.arrived_q = w.sim_q
		state.arrival = Vector2(w.player.pos))
	var bearing: Vector2 = Vector2(direction).normalized()
	w.player.pos = w.arena.center + bearing * (w.arena.radius - 4.0)
	w.player_position = w.player.pos
	w.player.vel = bearing * 200.0
	w.command.movement = bearing
	var first_q: int = -1
	for i: int in range(600):
		if w.warp_locked(): w.command.movement = Vector2.ZERO
		w._physics_process(STEP)
		if state.arrived_q >= 0 and first_q < 0 and not w.enemies.is_empty(): first_q = w.sim_q
		if first_q >= 0: break
	state.first_q = first_q
	state.arrival_angle = (Vector2(state.arrival) - w.arena.center).angle()
	state.enemies_before_arrival = state.arrived_q < 0 and not w.enemies.is_empty()
	release(w)
	return state

func _arrival_timing_and_angles() -> void:
	var delays: Array[float] = []
	var failed: int = 0
	var min_angle: float = 360.0
	for seed_value: int in range(1, 21):
		var run: Dictionary = _warp_into(seed_value, CampaignState.NEIGHBOURS[seed_value % 8])
		if int(run.arrived_q) < 0 or int(run.first_q) < 0:
			failed += 1
			continue
		delays.append(float(int(run.first_q) - int(run.arrived_q)) / CombatWorld.SIM_Q_PER_SECOND)
		for at: Vector2 in run.wave1:
			min_angle = minf(min_angle, rad_to_deg(absf(angle_difference(float(run.arrival_angle), (at - Vector2(GameTuning.ARENA_CENTER)).angle()))))
	delays.sort()
	var median: float = delays[delays.size() / 2] if not delays.is_empty() else INF
	var worst: float = delays[-1] if not delays.is_empty() else INF
	print("measure: first enemy after arrival seeds=20 failed=%d median_s=%.3f max_s=%.3f min_s=%.3f" % [failed, median, worst, delays[0] if not delays.is_empty() else INF])
	t.check(failed == 0 and worst <= 1.0 and delays[0] >= 0.0, "The first enemy lands <= 1.0 s after arrival on all 20 seeds (median %.3f, max %.3f, %d failed runs)" % [median, worst, failed])
	var late: Dictionary = _warp_into(1, Vector2i.RIGHT, 1.5)
	var late_delay: float = float(int(late.first_q) - int(late.arrived_q)) / CombatWorld.SIM_Q_PER_SECOND
	t.control("a 1.5 s first-wave delay (%.3f s)" % late_delay, late_delay > 1.0)
	print("measure: wave-1 spawn bearing vs arrival min_deg=%.2f" % min_angle)
	t.check(min_angle >= GameTuning.SPAWN_CLEAR_DEGREES - 0.01, "No wave-1 spawn in 20 warps is within +-60 deg of the arrival point (closest %.2f deg)" % min_angle)
	# Control: the same fan with no clear bearing (clear_from at the centre) lands inside the cone.
	var w: CombatWorld = make_world()
	var inside: int = 0
	for i: int in range(200):
		for angle: float in w.spawn_angles(5, w.arena.center):
			if rad_to_deg(absf(angle_difference(0.0, angle))) < GameTuning.SPAWN_CLEAR_DEGREES: inside += 1
	var constrained_inside: int = 0
	for i: int in range(200):
		for angle: float in w.spawn_angles(12, w.arena.center + Vector2(700, 0)):
			if rad_to_deg(absf(angle_difference(0.0, angle))) < GameTuning.SPAWN_CLEAR_DEGREES - 0.01: constrained_inside += 1
	release(w)
	t.check(constrained_inside == 0, "200 fans of 12 kept clear of a rim point: 0 bearings inside its +-60 deg cone")
	t.control("unconstrained fans (%d of 1000 bearings inside the cone)" % inside, inside > 0)

## Every spawn after wave 1 shows its first telegraph pulse SPAWN_TELEGRAPH_SECONDS before landing.
func _telegraph_lead() -> void:
	var node: Dictionary = find_node("skirmish", 4)
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	w.start_sector(node)
	var first_tele: Dictionary = {}
	var leads: Array[float] = []
	var wave1_leads: Array[float] = []
	var wave1_keys: Dictionary = {}
	for entry: Dictionary in w.spawn_queue: wave1_keys["%s@%s" % [entry.hull, entry.pos]] = true
	for i: int in range(1800):
		var before: Dictionary = {}
		for entry: Dictionary in w.spawn_queue:
			var key: String = "%s@%s" % [entry.hull, entry.pos]
			before[key] = true
			if int(entry.tele) >= 1 and not first_tele.has(key): first_tele[key] = w.encounter_q
		w._physics_process(STEP)
		var after: Dictionary = {}
		for entry: Dictionary in w.spawn_queue: after["%s@%s" % [entry.hull, entry.pos]] = true
		for key: String in before:
			if after.has(key) or not first_tele.has(key): continue
			var lead: float = float(w.encounter_q - int(first_tele[key])) / CombatWorld.SIM_Q_PER_SECOND
			if wave1_keys.has(key): wave1_leads.append(lead)
			else: leads.append(lead)
		for actor: Dictionary in w.enemies:
			if not bool(actor.dead) and w.encounter_q % 240 == 0: kill(w, actor)
	release(w)
	leads.sort()
	var lo: float = leads[0] if not leads.is_empty() else -1.0
	var hi: float = leads[-1] if not leads.is_empty() else -1.0
	print("measure: telegraph lead later_spawns=%d min_s=%.3f max_s=%.3f wave1_spawns=%d wave1_max_s=%.3f" % [leads.size(), lo, hi, wave1_leads.size(), wave1_leads.max() if not wave1_leads.is_empty() else -1.0])
	t.check(leads.size() >= 2 and lo >= GameTuning.SPAWN_TELEGRAPH_SECONDS - STEP and hi <= GameTuning.SPAWN_TELEGRAPH_SECONDS + STEP, "Every later spawn is telegraphed %.1f s +-1 tick before it lands (%d spawns, %.3f..%.3f s)" % [GameTuning.SPAWN_TELEGRAPH_SECONDS, leads.size(), lo, hi])
	t.control("wave 1's short lead read by the same instrument", not wave1_leads.is_empty() and float(wave1_leads.max()) < GameTuning.SPAWN_TELEGRAPH_SECONDS - STEP)

## Kills everything the moment it lands; counts `sector_cleared` and the times the list emptied.
func _cleared_once() -> void:
	var node: Dictionary = find_node("dense", 3)
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	var fired: Array[int] = []
	var complete_when_fired: Array[bool] = []
	w.sector_cleared.connect(func() -> void:
		fired.append(w.wave_index)
		complete_when_fired.append(w.waves_complete()))
	w.start_sector(node)
	var emptied: int = 0
	var was_empty: bool = true
	for i: int in range(2400):
		for actor: Dictionary in w.enemies:
			if not bool(actor.dead): kill(w, actor)
		w._physics_process(STEP)
		var empty: bool = w.enemies.is_empty()
		if empty and not was_empty: emptied += 1
		was_empty = empty
	var waves: int = node.waves.size()
	release(w)
	print("measure: cleared waves=%d cleared_emits=%d list_emptied=%d" % [waves, fired.size(), emptied])
	t.check(fired.size() == 1 and complete_when_fired[0] and int(fired[0]) == waves, "sector_cleared fires exactly once, after the last of %d waves (%d emits)" % [waves, fired.size()])
	t.control("the old 'enemy list empty' rule (%d empties)" % emptied, emptied > 1)

func _wave_state(w: CombatWorld) -> String:
	var queue: Array = []
	for entry: Dictionary in w.spawn_queue: queue.append([entry.hull, int(entry.due_q), snappedf(Vector2(entry.pos).x, 0.01), snappedf(Vector2(entry.pos).y, 0.01)])
	return JSON.stringify([w.encounter_q, w.wave_index, w._wave_due_q, w._wave_pending.size(), queue, w._dead_enemy_records.size(), w._respawn_due_q])

## Spawn timeline: [encounter_q, hull] for every enemy that appears in the next `ticks`.
func _spawn_timeline(w: CombatWorld, ticks: int) -> Array:
	var timeline: Array = []
	var known: Dictionary = {}
	for actor: Dictionary in w.enemies: known[int(actor.id)] = true
	for i: int in range(ticks):
		w._physics_process(STEP)
		for actor: Dictionary in w.enemies:
			if known.has(int(actor.id)): continue
			known[int(actor.id)] = true
			timeline.append([w.encounter_q, str(actor.hull_id)])
	return timeline

func _save_restore_mid_wave() -> void:
	var node: Dictionary = find_node("dense", 3)
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	w.start_sector(node)
	# Kill until wave 2 is released and a spawn is queued, so the save lands mid-wave.
	var guard: int = 0
	while guard < 1200 and not (w.wave_index >= 2 and not w.spawn_queue.is_empty() and not w._dead_enemy_records.is_empty()):
		for actor: Dictionary in w.enemies:
			if not bool(actor.dead) and w.enemies.size() > 1: kill(w, actor)
		w._physics_process(STEP)
		guard += 1
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot()))
	var original_state: String = _wave_state(w)
	var restored: CombatWorld = make_world()
	restored.restore(saved)
	var restored_state: String = _wave_state(restored)
	t.check(guard < 1200 and not w.spawn_queue.is_empty(), "The save lands mid-wave: wave %d released, %d queued, %d dead records" % [w.wave_index, w.spawn_queue.size(), w._dead_enemy_records.size()])
	t.check(original_state == restored_state, "Restore brings back the wave clock, the queue (hull, deadline, position), the gap deadline and the dead records")
	var ahead: Array = _spawn_timeline(w, 900)
	var replay: Array = _spawn_timeline(restored, 900)
	print("measure: save/restore spawns_after=%d restored_spawns_after=%d" % [ahead.size(), replay.size()])
	t.check(not ahead.is_empty() and JSON.stringify(ahead) == JSON.stringify(replay), "The restored run spawns the same hulls on the same encounter ticks for 15 s (%d spawns)" % ahead.size())
	var stripped: Dictionary = saved.duplicate(true)
	stripped.erase("wave_state")
	var lossy: CombatWorld = make_world()
	lossy.restore(stripped)
	t.control("the wave block dropped from the save", _wave_state(lossy) != original_state)
	release(w)
	release(restored)
	release(lossy)

## Leaving a node mid-wave and coming back resumes its queue and dead records from the cache.
func _cache_round_trip() -> void:
	var node: Dictionary = find_node("dense", 3)
	var other: Dictionary = find_node("transit", 2)
	other.encounter_epoch = node.encounter_epoch
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	w.start_sector(node)
	step(w, 20)
	for actor: Dictionary in w.enemies:
		kill(w, actor)
		break
	step(w, 5)
	var before: String = _wave_state(w)
	w.start_sector(other)
	step(w, 30)
	w.start_sector(node)
	var after: String = _wave_state(w)
	t.check(before == after and not w._dead_enemy_records.is_empty(), "A revisited node resumes its wave clock, queue and dead records from the encounter cache")
	release(w)

func _overflow_bank() -> void:
	var w: CombatWorld = make_world()
	w.setup_player("lightning", 1, GameTuning.capacity(1), [], w.arena.center)
	var cap: float = w.light_bank_cap()
	w.collect_light(1000.0, "lightning")
	var bar_full: bool = is_equal_approx(w.light_total, GameTuning.capacity(1))
	print("measure: bank cap=%.2f banked=%.2f next_threshold=%.1f" % [cap, w.light_bank, GameTuning.capacity(2)])
	t.check(bar_full and is_equal_approx(w.light_bank, 0.25 * GameTuning.capacity(2)), "1000 light on a full T1 bar banks exactly 25%% of the next threshold (%.2f)" % w.light_bank)
	# A pickup next to the ship is still collected on a full bar while the bank has room.
	w.light_bank = 0.0
	w.pickups.append({"pos": w.player.pos + Vector2(4, 0), "vel": Vector2.ZERO, "element": "lightning", "value": 5.0, "size": 5, "phase": 0.0})
	step(w, 3)
	t.check(w.pickups.is_empty() and is_equal_approx(w.light_bank, 5.0), "A pickup on a full bar flows into the bank (bank %.2f)" % w.light_bank)
	w.light_bank = cap
	var t2: String = "player_lightning_t2_standard_a"
	var evolved: bool = ShipCatalog.get_ship(t2) != null and w.evolve_hull(t2)
	t.check(evolved and is_equal_approx(w.light_total, GameTuning.capacity(1) + cap) and w.light_bank == 0.0, "Evolving pays the bank into the bar (%.2f light, bank %.2f)" % [w.light_total, w.light_bank])
	w.setup_player("lightning", 1, GameTuning.capacity(1), [], w.arena.center)
	w.light_bank_fraction = 10.0
	w.collect_light(1000.0, "lightning")
	t.control("the bank cap lifted (%.2f banked)" % w.light_bank, w.light_bank > 0.25 * GameTuning.capacity(2) + 0.01)
	release(w)

func _combo_window_and_freeze() -> void:
	t.check(is_equal_approx(GameTuning.COMBO_WINDOW_SECONDS, 3.0), "The combo window is 3.0 s")
	var w: CombatWorld = make_world()
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 4.0, 0.0)
	w.player_position = w.player.pos
	w.player.vel = Vector2(200.0, 0.0)
	w.command.movement = Vector2.RIGHT
	w.warp_committed.connect(func(_dir: Vector2i) -> void: w.confirm_warp_swap())
	var guard: int = 0
	while not w.warp_locked() and guard < 60:
		w._physics_process(STEP)
		guard += 1
	w.command.movement = Vector2.ZERO
	w.combo_count = 5
	w.combo_timer = 1.0
	# Only ticks that are still locked when they end count: the tick the warp finishes in unlocks
	# before the pace step runs, so that one tick legitimately counts down.
	var locked_ticks: int = 0
	var frozen: bool = true
	while locked_ticks < 300:
		w._physics_process(STEP)
		if not w.warp_locked(): break
		locked_ticks += 1
		frozen = frozen and w.combo_count == 5 and is_equal_approx(w.combo_timer, 1.0)
	t.check(locked_ticks > 5 and frozen, "The combo neither ticks nor drains through %d locked warp ticks (timer %.3f, count %d)" % [locked_ticks, w.combo_timer, w.combo_count])
	step(w, 6)
	t.control("unlocked ticks after the warp (timer %.3f)" % w.combo_timer, w.combo_timer < 1.0 - STEP)
	release(w)

func _origin_training_wave() -> void:
	var w: CombatWorld = make_world()
	w._grant_invulnerability(1000000.0, &"test")
	w.start_sector(campaign_for(5).sector_at(Vector2i.ZERO))
	var first_s: float = -1.0
	for i: int in range(120):
		w._physics_process(STEP)
		if first_s < 0.0 and not w.enemies.is_empty(): first_s = float(w.encounter_q) / CombatWorld.SIM_Q_PER_SECOND
	var drones: int = 0
	for actor: Dictionary in w.enemies:
		if str(actor.hull_id).begins_with("enemy_drone_") and int(actor.tier) == 1: drones += 1
	print("measure: origin training first_s=%.3f drones=%d" % [first_s, drones])
	t.check(absf(first_s - GameTuning.ORIGIN_TRAINING_DELAY_SECONDS) <= STEP * 1.5 and drones == GameTuning.ORIGIN_TRAINING_COUNT and not w.cleared_emitted, "A reboot lands in a fight: 3 T1 drones 1.0 s in (first at %.3f s, %d drones)" % [first_s, drones])
	release(w)

func _music_intensity() -> void:
	var w: CombatWorld = make_world()
	var calm: int = w.music_intensity()
	var boss: Dictionary = find_node("boss", 0)
	w._grant_invulnerability(1000000.0, &"test")
	w.start_sector(boss)
	step(w, 30)
	var fight: int = w.music_intensity()
	t.check(calm == 0 and fight == 3, "Music intensity reads 0 in an empty node and 3 with a live boss (%d, %d)" % [calm, fight])
	release(w)
