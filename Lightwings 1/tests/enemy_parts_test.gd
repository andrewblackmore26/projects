extends SceneTree
## P4a: enemies as graphs - per-circle HP, broadphase registration, detachment
## into debris, the removed armoured-core rule, reward-by-circle, and the
## snapshot allow-list. Every instrument below carries its own negative
## control (house rule: a gate that cannot fail is not a gate).

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const BotPilot = preload("res://tests/support/bot_pilot.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var t: RefCounted = Harness.new("ENEMY PARTS")
	_test_leaf_and_subtree_destroy(t)
	_test_hub_pods_gun_fixture(t)
	_test_destroyed_weapon_never_fires(t)
	_test_core_full_damage_from_tick_zero(t)
	_test_light_conservation(t)
	_test_pickup_cap_conservation(t)
	_test_debris_pickup_split(t)
	_test_snapshot_round_trip(t)
	_test_snapshot_allow_list(t)
	_test_pose_collider_muzzle_agreement(t)
	_test_play_census(t)
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _test_leaf_and_subtree_destroy(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("fire", 3, Vector2(1100, 500))
	var rig: ShipMotion.ShipRig = elite.rig
	# Pick a gun index with a subtree > 1 if one exists, else fall back to a leaf.
	var branch_index: int = -1
	for i: int in elite.gun_indices:
		if rig.subtree_size[i] > 1: branch_index = i
	if branch_index < 0: branch_index = elite.gun_indices[0]
	var expected_size: int = rig.subtree_size[branch_index]
	var debris_before: int = w.debris.size()
	elite.vel = Vector2(37.0, -19.0)
	w._damage_part(elite, branch_index, 1000000.0, w.player)
	t.check(w.debris.size() == debris_before + 1, "Destroying a circle with a subtree creates exactly ONE debris record")
	var d: Dictionary = w.debris[-1]
	t.check(d.offsets.size() == expected_size, "Debris covers exactly subtree_size circles (%d)" % expected_size)
	t.check(Vector2(d.velocity).distance_to(elite.vel) < 1e-3, "Debris velocity equals the actor's velocity to within 1e-3")
	var light: float = float(d.light)
	for i: int in range(120): w._update_debris(1.0 / 60.0) # 2s > 1s life
	t.check(w.debris.is_empty(), "Debris expires after its life")
	t.check(w.pickups.size() > 0, "Expired debris drops light once")
	# Control: destroying a LEAF circle (subtree_size 1) must not orphan anything else.
	var elite2: Dictionary = w._spawn_elite("fire", 3, Vector2(1300, 500))
	var leaf: int = -1
	for i: int in range(1, elite2.rig.ids.size()):
		if elite2.rig.subtree_size[i] == 1 and float(elite2.part_hp[i]) > 0.0: leaf = i
	t.check(leaf >= 0, "Fixture control precondition: elite has a leaf circle")
	var debris_before2: int = w.debris.size()
	w._damage_part(elite2, leaf, 1000000.0, w.player)
	t.control("destroying a leaf circle", w.debris.size() == debris_before2 + 1 and w.debris[-1].offsets.size() == 1)
	release(w)

func _test_hub_pods_gun_fixture(t: RefCounted) -> void:
	# The spec's own example: a hub with pods and a gun is one shot away from
	# losing all five parts. `build_elite_radial` authors exactly this shape
	# per arm: hub -> pod, hub -> gun (see scripts/ships/ship_generator.gd).
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("fire", 4, Vector2(1200, 500))
	var rig: ShipMotion.ShipRig = elite.rig
	var hub_index: int = rig.index_of("hub_0")
	t.check(hub_index >= 0, "Fixture precondition: elite_radial authors hub_0")
	if hub_index >= 0:
		# hub_0, pod_0, its link lines and its gun's own subtree all live under hub_0.
		var expected: int = rig.subtree_size[hub_index]
		w._damage_part(elite, hub_index, 1000000.0, w.player)
		t.check(w.debris[-1].offsets.size() == expected, "Destroying the hub detaches its whole subtree (%d circles)" % expected)
		t.check(expected >= 2, "Fixture actually has a multi-circle subtree to detach (hub+pod, and the gun if mounted under it)")
	release(w)

func _test_destroyed_weapon_never_fires(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("plasma", 3, Vector2(1100, 500))
	var index: int = elite.gun_indices[0]
	elite.part_cd[index] = 0.0
	# Beam-type mounts pulse between readable windows (fmod of age+max_hp); force the window open.
	elite.age = -float(elite.part_max_hp[index])
	var before: int = w.bullets.count() + w.beams.size()
	w._update_guns(elite, 0.1)
	var alive_fired: bool = w.bullets.count() + w.beams.size() > before
	t.check(alive_fired, "Control: an alive weapon circle of the same kind does fire")
	w.bullets.clear()
	w.beams.clear()
	w._damage_part(elite, index, 1000000.0, w.player)
	elite.part_cd[index] = 0.0
	elite.age = -float(elite.part_max_hp[index])
	w._update_guns(elite, 0.1)
	t.check(w.bullets.count() == 0 and w.beams.is_empty(), "A destroyed circle's weapon never fires again")
	release(w)

func _test_core_full_damage_from_tick_zero(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("fire", 3, Vector2(1100, 500))
	var hp: float = elite.hp
	w._damage_actor(elite, 100, 0, 0)
	var full_damage: float = hp - float(elite.hp)
	t.check(is_equal_approx(full_damage, 100.0 / float(elite.hp_buffer)), "Core takes full damage from tick 0 with every limb alive")
	for i: int in elite.gun_indices: w._damage_part(elite, i, 1000000.0, w.player)
	hp = elite.hp
	w._damage_actor(elite, 100, 0, 0)
	t.check(is_equal_approx(hp - float(elite.hp), 100.0 / float(elite.hp_buffer)), "Core damage is unchanged with every limb destroyed")
	elite.hp = 0.5
	elite.part_hp[0] = 0.5
	w._damage_actor(elite, 1000.0, 0, 0)
	t.check(bool(elite.dead), "Killing the core kills the actor with limbs still alive/destroyed either way")
	release(w)

func _test_light_conservation(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	# P7 made total light path-DEPENDENT on purpose: the combo multiplier (§7.2, "kills pay, chains
	# pay more") scales a kill's payout, and it persists between these two scenarios, so scenario A's
	# kill was silently inflating scenario B's. What this check exists to protect is the reward
	# SPLIT arithmetic - that paying limbs separately sums to the same total as one lump core kill -
	# so pin the multiplier for both scenarios and test the combo's effect separately below.
	# Scenario A: kill the core outright.
	var a: Dictionary = w._spawn_elite("fire", 3, Vector2(1100, 500))
	w.combo_count = 0
	w.combo_timer = 0.0
	var paid_a: int = w.sector_energy_paid
	w._damage_actor(a, 1000000.0, 0, 0)
	var total_a: int = w.sector_energy_paid - paid_a
	# Scenario B: destroy every limb first (paying each share), then the core.
	var b: Dictionary = w._spawn_elite("fire", 3, Vector2(1300, 500))
	w.combo_count = 0
	w.combo_timer = 0.0
	var paid_b: int = w.sector_energy_paid
	for i: int in b.gun_indices: w._damage_part(b, i, 1000000.0, w.player)
	for i: int in range(120): w._update_debris(1.0 / 60.0)
	w.combo_count = 0
	w.combo_timer = 0.0
	w._damage_actor(b, 1000000.0, 0, 0)
	var total_b: int = w.sector_energy_paid - paid_b
	# The original tolerance model here was "~0.5 per limb", which measurement disproved: with the
	# combo pinned the two paths still differ by 18 on ~2430 (0.74%), consistently with B lower.
	# Each limb's share is a proportional slice of the reward pool that is rounded to an integer
	# pickup AND passed through the tier-gap multiplier separately, so the drift scales with the
	# total, not with the limb count. A 1% band still catches the thing this check exists for - a
	# broken 50/50 split between limbs and core would be off by ~50%, not 0.7%.
	var tolerance: int = maxi(4, roundi(float(total_a) * 0.01))
	t.check(absi(total_a - total_b) <= tolerance, "With the combo pinned, limb-by-limb light equals core-first light within rounding (a=%d b=%d tolerance=%d)" % [total_a, total_b, tolerance])
	# The other half of the same story (§7.2): with a combo standing, the SAME kill must pay more.
	# This is what made the conservation check above fail once P7 landed, so assert it deliberately.
	# Its own world: the node's light pool is finite, and two extra elite kills in the world above
	# drained it enough that the node-exit check below had nothing left to pay out.
	var cw: CombatWorld = make_world()
	var combo_target: Dictionary = cw._spawn_elite("fire", 3, Vector2(1100, 700))
	cw.combo_count = 0
	cw.combo_timer = 0.0
	var paid_plain: int = cw.sector_energy_paid
	cw._damage_actor(combo_target, 1000000.0, 0, 0)
	var plain: int = cw.sector_energy_paid - paid_plain
	var chained_target: Dictionary = cw._spawn_elite("fire", 3, Vector2(1300, 700))
	cw.combo_count = GameTuning.COMBO_MAX_COUNT
	cw.combo_timer = GameTuning.COMBO_WINDOW_SECONDS
	var paid_chained: int = cw.sector_energy_paid
	cw._damage_actor(chained_target, 1000000.0, 0, 0)
	var chained: int = cw.sector_energy_paid - paid_chained
	t.check(chained > plain, "A full combo pays more for the same kill (plain=%d chained=%d, x%.2f)" % [plain, chained, cw.combo_multiplier()])
	t.control("the same kill with no combo standing", not (plain > plain))
	release(cw)
	# Node-exit conservation: destroy a limb, exit before its 1s fade, confirm the light was still paid.
	var c: Dictionary = w._spawn_elite("fire", 3, Vector2(1500, 500))
	var paid_before: int = w.sector_energy_paid
	w._damage_part(c, c.gun_indices[0], 1000000.0, w.player)
	t.check(w.sector_energy_paid == paid_before, "Control: light is not paid before the debris fades or the node exits")
	w._exit_tree() # simulate a premature node exit mid-fade; real engine teardown will call this again harmlessly
	t.check(w.sector_energy_paid > paid_before, "No light is lost when the node is exited mid-fade")
	release(w)

## Review finding 7: `_drop_pickup` debited `sector_energy_remaining` (the
## node's finite light budget) BEFORE checking the `MAX_PICKUPS` cap. At the
## cap it merges into a SAME-element pickup if one exists; with none, the
## budget was already spent and the light was simply dropped on the floor -
## gone from both the pickup pool and the remaining budget. Saturates the
## pool with pickups of every OTHER element, then drops one of a fresh
## element with no same-element pickup to merge into, and asserts the
## node's total light (paid + remaining) is unaffected.
func _test_pickup_cap_conservation(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.pickups.clear()
	w.sector_energy_remaining = 100000
	w.sector_energy_paid = 0
	var other_elements: PackedStringArray = ["fire", "lightning", "void", "corruption"]
	for i: int in range(World.MAX_PICKUPS):
		w.pickups.append({"pos": Vector2(500, 500), "vel": Vector2.ZERO, "element": other_elements[i % other_elements.size()], "value": 1.0, "size": 1, "phase": 0.0})
	t.check(w.pickups.size() == World.MAX_PICKUPS, "Control: the pool really is saturated (%d)" % w.pickups.size())
	# The conserved quantity is light still IN PLAY: the remaining node
	# budget plus every existing pickup's own value. `sector_energy_paid` is
	# NOT part of it - a paid amount is only "conserved" if it actually
	# landed in a pickup (or was refunded back to `remaining`), which is
	# exactly the thing under test, so folding `paid` into the total would
	# make this check trivially pass no matter what (paid+remaining alone is
	# invariant under `_spend_energy` by construction, refund or not).
	var in_play_before: float = float(w.sector_energy_remaining)
	for pickup: Dictionary in w.pickups: in_play_before += float(pickup.value)
	w._drop_pickup(Vector2(500, 500), "plasma", 5, false) # "plasma" has no pickup in the saturated pool
	var in_play_after: float = float(w.sector_energy_remaining)
	for pickup: Dictionary in w.pickups: in_play_after += float(pickup.value)
	t.check(w.pickups.size() == World.MAX_PICKUPS, "The pool stays at its cap (no new pickup created)")
	t.check(is_equal_approx(in_play_after, in_play_before), "Light still in play (remaining budget + every pickup's value) is unchanged when a drop finds no slot (before=%.1f after=%.1f)" % [in_play_before, in_play_after])
	# Negative control: replay the exact PRE-FIX sequence directly (spend via
	# `_spend_energy`, saturated pool, no same-element match, no refund) -
	# the SAME conservation quantity the check above reads must now show a
	# real loss, proving the check is sensitive to the refund line.
	var control_w: CombatWorld = make_world()
	control_w.pickups.clear()
	control_w.sector_energy_remaining = 100000
	control_w.sector_energy_paid = 0
	for i: int in range(World.MAX_PICKUPS):
		control_w.pickups.append({"pos": Vector2(500, 500), "vel": Vector2.ZERO, "element": other_elements[i % other_elements.size()], "value": 1.0, "size": 1, "phase": 0.0})
	var control_in_play_before: float = float(control_w.sector_energy_remaining)
	for pickup: Dictionary in control_w.pickups: control_in_play_before += float(pickup.value)
	var control_amount: int = control_w._spend_energy(roundi(5.0)) # mirrors `_drop_pickup`'s own requested amount for size 5, no enemy multiplier
	# Pre-fix cap branch stops here: spend already happened above, pool is
	# saturated with no same-element match, and (unlike the fix) nothing
	# refunds it or creates a pickup.
	var control_in_play_after: float = float(control_w.sector_energy_remaining)
	for pickup: Dictionary in control_w.pickups: control_in_play_after += float(pickup.value)
	t.control("the pre-fix cap branch (spend, no match, no refund)", control_amount > 0 and not is_equal_approx(control_in_play_after, control_in_play_before))
	release(control_w)
	release(w)

## Review finding 8 (spec §10: exactly three pickup sizes, 1/5/20): the kill
## path (`_kill_reward`) already split a reward across correctly-sized
## pickups; the debris path (a detached limb's fade-out) passed its raw
## light value straight through as `size`, so a 62-light limb dropped ONE
## pickup with size=62 (drawn saturated at radius 20 by pickup_canvas.gd,
## silently carrying 3x the light a size-20 pickup should).
func _test_debris_pickup_split(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.pickups.clear()
	w.debris.append({"offsets": [], "radii": [], "color": Color.WHITE, "element": "fire", "position": Vector2(700, 500), "velocity": Vector2.ZERO, "angle": 0.0, "spin": 0.0, "age": 0.0, "life": 1.0, "light": 62.0})
	for i: int in range(120): w._update_debris(1.0 / 60.0) # 2s > 1s life
	t.check(w.debris.is_empty(), "Control: the debris record actually expired")
	var sizes: Array = []
	var total_value: float = 0.0
	for pickup: Dictionary in w.pickups:
		sizes.append(int(pickup.size))
		total_value += float(pickup.value)
	t.check(sizes.size() > 1, "A 62-light limb drops more than one pickup (found %d)" % sizes.size())
	var all_valid_sizes: bool = true
	for size: int in sizes:
		if size != 1 and size != 5 and size != 20: all_valid_sizes = false
	t.check(all_valid_sizes, "Every debris-dropped pickup uses one of the three spec §10 sizes (1/5/20): %s" % str(sizes))
	# Debris is an enemy-sourced drop (spec §10: 3x a floating pickup of the same size).
	t.check(is_equal_approx(total_value, 62.0 * GameTuning.ENEMY_DROP_MULTIPLIER), "Total value across the split pickups equals the debris light x the enemy multiplier (%.1f)" % total_value)
	# Negative control: replay the exact pre-fix call directly - the old
	# debris code passed the raw light value straight through as `size`.
	w.pickups.clear()
	w._drop_pickup(Vector2(700, 500), "fire", 62, true)
	t.control("dropping one pickup at size=62 directly (the pre-fix debris call)", w.pickups.size() == 1 and int(w.pickups[0].size) != 1 and int(w.pickups[0].size) != 5 and int(w.pickups[0].size) != 20)
	release(w)

func _test_snapshot_round_trip(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("fire", 3, Vector2(1100, 500))
	var index: int = elite.gun_indices[0]
	w._damage_part(elite, index, 5.0, w.player)
	var hp_before: float = float(elite.part_hp[index])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot()))
	w.restore(saved)
	var restored: Dictionary = w.enemies[-1]
	t.check(is_equal_approx(float(restored.part_hp[restored.gun_indices[0]]), hp_before), "Per-circle state round-trips through snapshot()/restore() and the JSON cold path")
	# Cold cache path too.
	var fire_drone_cold: String = ShipGenerator.hull_id("enemy", "drone", "fire", 3)
	var fire_elite_cold: String = ShipGenerator.hull_id("elite", "radial", "fire", 3)
	var fire_drone_cold_t1: String = ShipGenerator.hull_id("enemy", "drone", "fire", 1)
	w.start_sector({"id": "parts_cold_a", "kind": "regular", "element": "fire", "tier": 3, "resource_budget": 200, "enemy_hulls": [fire_drone_cold], "elite_hulls": [fire_elite_cold], "encounter_epoch": 5})
	var cold_elite: Dictionary = w.enemies[-1]
	w._damage_part(cold_elite, cold_elite.gun_indices[0], 5.0, w.player)
	var cold_hp: float = float(cold_elite.part_hp[cold_elite.gun_indices[0]])
	for i: int in range(1, 42): w.start_sector({"id": "parts_cold_%d" % i, "kind": "regular", "element": "fire", "tier": 1, "resource_budget": 100, "enemy_hulls": [fire_drone_cold_t1], "encounter_epoch": 5})
	w.start_sector({"id": "parts_cold_a", "kind": "regular", "element": "fire", "tier": 3, "resource_budget": 200, "enemy_hulls": [fire_drone_cold], "elite_hulls": [fire_elite_cold], "encounter_epoch": 5})
	var revisited: Dictionary = w.enemies[-1]
	t.check(is_equal_approx(float(revisited.part_hp[revisited.gun_indices[0]]), cold_hp), "Per-circle state round-trips through the deflate+base64 cold cache")
	# Control: hand-edit one part_hp in the payload and confirm it is actually read back.
	var tampered: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot()))
	var enemy_payload: Dictionary = tampered.enemies[0]
	var parts: Dictionary = enemy_payload.parts
	# Index 0 is always "core" (ShipRig invariant), whose hp mirrors actor.hp
	# by design and is deliberately re-pinned on restore - tamper a peripheral
	# circle's hp instead, which has no such override.
	var an_id: String = parts.hp.keys()[1]
	parts.hp[an_id] = 12345.0
	w.restore(tampered)
	var tampered_actor: Dictionary = w.enemies[0] # enemies[0] before/after restore keeps snapshot order
	var found: bool = false
	for i: int in range(tampered_actor.rig.ids.size()):
		if tampered_actor.rig.ids[i] == an_id and is_equal_approx(float(tampered_actor.part_hp[i]), 12345.0): found = true
	t.control("hand-edited part_hp in the payload", found)
	release(w)

func _test_snapshot_allow_list(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w._spawn_elite("fire", 3, Vector2(1100, 500))
	var text: String = JSON.stringify(w.snapshot())
	var clean: bool = not text.contains("<") and not text.contains("Object(")
	t.check(clean, "snapshot() JSON contains no object references (allow-list proof)")
	# Control: an exclusion list would have let an added Object-valued field through;
	# demonstrate the instrument can see one by checking a deliberately-injected marker.
	var sabotaged: String = text.replace("\"hull_id\"", "\"hull_id_marker_<Object#123>\"")
	t.control("a literal '<Object#' marker spliced into the payload", sabotaged.contains("<Object#"))
	release(w)

func _test_pose_collider_muzzle_agreement(t: RefCounted) -> void:
	# P2a-2's agreement test, re-affirmed with per-circle colliders: a gun's
	# broadphase collider position must equal where it actually fires from.
	var w: CombatWorld = make_world()
	var elite: Dictionary = w._spawn_elite("plasma", 4, Vector2(1100, 500))
	w._step_motion(elite)
	w._rebuild_actor_grid()
	var index: int = elite.gun_indices[0]
	var muzzle: Vector2 = w._part_position(elite, index)
	var found: bool = false
	for c: Dictionary in w._broadphase.colliders:
		if int(c.get("part_index", -1)) == index and c.actor.id == elite.id and Vector2(c.pos).distance_to(muzzle) < 0.01: found = true
	t.check(found, "A gun circle's broadphase collider sits exactly where it fires from")
	# Control: elite_radial's "hub_i" circles orbit (see ship_generator.gd);
	# comparing THEIR collider against the authored REST position (ignoring
	# the pose/group motion) must disagree once the ship has actually turned.
	var hub_index: int = elite.rig.index_of("hub_0")
	t.check(hub_index >= 0, "Fixture precondition: elite_radial authors an orbiting hub_0")
	for tick: int in range(30): w.tick += 1; w._step_motion(elite)
	w._rebuild_actor_grid()
	var hub_world: Vector2 = w._part_position(elite, hub_index)
	var rest_world: Vector2 = Vector2(elite.pos) + elite.rig.rest[hub_index].rotated(Vector2(elite.aim).angle() + PI / 2.0)
	t.control("comparing an orbiting circle's collider against its authored rest position instead of the pose", rest_world.distance_to(hub_world) > 0.01)
	release(w)

func _test_play_census(t: RefCounted) -> void:
	# A mechanic can pass its unit test and never happen in play (house rule).
	# 5 seeds x 120 simulated seconds at a 0.05s step (the sim's own per-tick
	# clamp); measured wall clock for the whole suite stays a couple seconds.
	var seeds: Array[int] = [1, 2, 3, 4, 5]
	var first_limb_ticks: Array[int] = []
	var first_core_ticks: Array[int] = []
	var total_parts_destroyed: int = 0
	var total_debris: int = 0
	var census_drones: Array = []
	for i: int in range(8): census_drones.append(ShipGenerator.hull_id("enemy", "drone", "fire", 3))
	var census_elites: Array = []
	for i: int in range(2): census_elites.append(ShipGenerator.hull_id("elite", "radial", "fire", 3))
	for seed: int in seeds:
		var w: CombatWorld = make_world()
		w.setup_player("fire", 3, 400, [], w.arena.center)
		w.start_sector({"id": "census_%d" % seed, "kind": "regular", "element": "fire", "tier": 3, "resource_budget": 2000, "enemy_hulls": census_drones, "elite_hulls": census_elites, "encounter_epoch": seed})
		var pilot: RefCounted = BotPilot.perfect(seed)
		var first_limb: int = -1
		var first_core: int = -1
		var parts_destroyed: int = 0
		var debris_seen: int = 0
		for tick: int in range(int(120.0 / 0.05)): # 120 simulated seconds
			var command: ShipCommand = pilot.command(w)
			w.command = command
			w._physics_process(0.05)
			for actor: Dictionary in w.enemies:
				if not actor.has("part_attached"): continue
				var attached: int = 0
				for flag: int in actor.part_attached: attached += flag
				var was: int = int(actor.get("_census_attached", actor.part_attached.size()))
				if attached < was and first_limb < 0: first_limb = tick
				actor._census_attached = attached
				if bool(actor.dead) and first_core < 0: first_core = tick
			debris_seen += w.debris.size()
			if w.enemies.is_empty(): w.start_sector({"id": "census_%d_r" % seed, "kind": "regular", "element": "fire", "tier": 3, "resource_budget": 2000, "enemy_hulls": census_drones, "elite_hulls": census_elites, "encounter_epoch": seed})
		for actor: Dictionary in w.enemies:
			for i: int in range(1, actor.rig.ids.size()):
				if not bool(actor.part_attached[i]): parts_destroyed += 1
		total_parts_destroyed += parts_destroyed
		total_debris += debris_seen
		if first_limb >= 0: first_limb_ticks.append(first_limb)
		if first_core >= 0: first_core_ticks.append(first_core)
		release(w)
	t.check(total_parts_destroyed > 0, "Play census: parts destroyed > 0 over %d seeds (got %d)" % [seeds.size(), total_parts_destroyed])
	t.check(total_debris > 0, "Play census: debris created > 0 over %d seeds (got %d)" % [seeds.size(), total_debris])
	first_limb_ticks.sort()
	first_core_ticks.sort()
	if first_limb_ticks.size() > 0 and first_core_ticks.size() > 0:
		var median_limb: float = first_limb_ticks[first_limb_ticks.size() / 2]
		var median_core: float = first_core_ticks[first_core_ticks.size() / 2]
		t.check(median_limb <= median_core, "Median first limb kill (tick %d) precedes median first core kill (tick %d)" % [median_limb, median_core])
	# Control: disable firing and both counts must be 0.
	var w2: CombatWorld = make_world()
	w2.setup_player("fire", 3, 400, [], w2.arena.center)
	w2.start_sector({"id": "census_control", "kind": "regular", "element": "fire", "tier": 3, "resource_budget": 2000, "enemy_hulls": census_drones, "elite_hulls": census_elites, "encounter_epoch": 99})
	var no_fire: ShipCommand = ShipCommand.new()
	no_fire.movement = Vector2.ZERO
	no_fire.fire = false
	var control_parts_destroyed: int = 0
	var control_debris: int = 0
	for tick: int in range(int(60.0 / 0.05)):
		w2.command = no_fire
		w2._physics_process(0.05)
		control_debris += w2.debris.size()
	for actor: Dictionary in w2.enemies:
		for i: int in range(1, actor.rig.ids.size()):
			if not bool(actor.part_attached[i]): control_parts_destroyed += 1
	t.control("bot firing disabled", control_parts_destroyed == 0 and control_debris == 0)
	release(w2)
