extends SceneTree
## Rail hulls inside the real CombatWorld (ship design spec §4, §9.7, §9.8): the hub is the mount
## and the muzzle, scenery circles carry no HP or reward, killing a hub takes its whole cluster,
## a rail's ring goes with its last cluster, set pieces SLEW toward the aim, debris inherits the
## rail's velocity and pays its light halfway through its fade, and an elite's core weapon fires.
## The fixtures are saved into a throwaway catalog root, so the shipped roster is untouched.
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")

var root_before: String
var stage: String

func _initialize() -> void: call_deferred("run")

func _stage_fixtures() -> void:
	root_before = ShipCatalog.catalog_root
	stage = "user://rail_combat_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stage))
	for name: String in ["radial_elite", "drone", "boss", "player_t3"]:
		var errors: PackedStringArray = PackedStringArray()
		var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
		ShipCatalog.save_ship(ship, stage.path_join(ship.id + ".tres"))
	ShipCatalog.catalog_root = stage
	ShipCatalog.invalidate()

func _unstage() -> void:
	ShipCatalog.catalog_root = root_before
	ShipCatalog.invalidate()
	var dir: DirAccess = DirAccess.open(stage)
	if dir != null:
		for file: String in dir.get_files(): dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stage))

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	# The player is the shipped seed hull, so it is built from the REAL roster; only then does the
	# catalogue point at the staged fixtures. (The first run redirected first, the seed was not
	# found, and the player came up without `speed` or `magnet_radius`.)
	ShipCatalog.catalog_root = root_before
	ShipCatalog.invalidate()
	w.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	ShipCatalog.catalog_root = stage
	ShipCatalog.invalidate()
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _elite(w: CombatWorld) -> Dictionary:
	return w._spawn_named_enemy("fixture_radial_elite", "lightning", 2, Vector2(1100, 500), false, true)

func run() -> void:
	var t: RefCounted = Harness.new("RAIL COMBAT")
	_stage_fixtures()
	_test_parts(t)
	_test_muzzle_and_detach(t)
	_test_slew(t)
	_test_debris(t)
	_test_core_weapon_fires(t)
	_test_twins(t)
	_unstage()
	t.finish(self)

func _test_parts(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = _elite(w)
	var rig: ShipMotion.ShipRig = elite.rig
	t.check(not rig.legacy and str(elite.archetype) == "radial_elite" and CombatAI.archetype_of(elite) == "radial", "A rail hull spawns on the FK path and the AI reads its declared archetype")
	t.check(Array(elite.gun_indices) == [rig.index_of("r2s0"), rig.index_of("r2s1"), rig.index_of("r2s2")], "Its guns are its three armed hubs (%s)" % str(elite.gun_indices))
	var scenery_hp: float = 0.0
	var scenery_share: float = 0.0
	var solid_share: float = 0.0
	for i: int in range(1, rig.ids.size()):
		if rig.solid[i] == 0:
			scenery_hp += float(elite.part_max_hp[i])
			scenery_share += float(elite.part_reward_share[i])
		else: solid_share += float(elite.part_reward_share[i])
	t.check(scenery_hp == 0.0 and scenery_share == 0.0 and solid_share > 0.0, "Rings, the inner core ring and set-piece circles carry no HP and no reward; the limb reward (%.1f) sits on solid circles" % solid_share)
	t.check(is_equal_approx(float(elite.part_max_hp[rig.index_of("r2s0")]), 60.0), "A hub's authored hp (60) is its HP")
	release(w)
	# Control: the same hull with its 96 px ring marked solid would give that ring HP.
	var ship: ShipDefinition = ShipCatalog.get_ship("fixture_radial_elite")
	for part: PartDefinition in ship.parts:
		if part.id == "r2": part.solid = true
	t.control("the 96 px rail ring marked solid", ShipMotion.get_rig(ship).solid_indices.has(ShipMotion.get_rig(ship).index_of("r2")))

func _test_muzzle_and_detach(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = _elite(w)
	var rig: ShipMotion.ShipRig = elite.rig
	var hub: int = rig.index_of("r2s0")
	w.tick = 0
	w._step_motion(elite)
	var at_zero: Vector2 = w._muzzle(elite, "r2s0")
	w.tick = 120
	w._step_motion(elite)
	var later: Vector2 = w._muzzle(elite, "r2s0")
	t.check(at_zero.distance_to(w._part_position(elite, hub)) > 1.0 and later.distance_to(w._part_position(elite, hub)) < 0.001, "The muzzle IS the hub's live position, and it moves as the rail turns (%.1f px in 2 s)" % at_zero.distance_to(later))
	# Kill one hub: its whole cluster goes, its spoke goes, the ring stays for the other two.
	var size: int = rig.subtree_size[hub]
	w._damage_part(elite, hub, 1000000.0, w.player)
	var gone: int = 0
	for i: int in range(hub, hub + size):
		if not bool(elite.part_attached[i]): gone += 1
	t.check(gone == size and size == 1 + 3 + 3, "Killing a hub detaches its whole cluster: hub + 3 pods + 3 set-piece circles (%d of %d)" % [gone, size])
	t.check(elite.hidden_ids.has("r2s0_spoke") and not elite.hidden_ids.has("r2") and not w._mount_alive(elite, "r2s0"), "Its spoke is hidden, its weapon is dead, and rail 2's ring stays while two hubs live")
	w._damage_part(elite, rig.index_of("r2s1"), 1000000.0, w.player)
	t.control("the ring asked about one hub too early", not elite.hidden_ids.has("r2"))
	w._damage_part(elite, rig.index_of("r2s2"), 1000000.0, w.player)
	t.check(elite.hidden_ids.has("r2") and not elite.hidden_ids.has("r1"), "The ring goes with its LAST cluster, and rail 1's ring is untouched")
	release(w)

func _test_slew(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = _elite(w)
	var rig: ShipMotion.ShipRig = elite.rig
	var pose: ShipMotion.ShipPose = elite.pose
	var hub: int = rig.index_of("r2s0")
	var joint: int = rig.index_of("r2s0w0")
	elite.aim = Vector2.RIGHT
	elite.part_aim[hub] = Vector2.LEFT # the hull faces right; this gun is told to aim dead behind it
	w._last_dt = 1.0 / 60.0
	var worst_step: float = 0.0
	var previous: float = NAN
	var ticks_to_arrive: int = -1
	for tick: int in range(180):
		w.tick = tick
		w._step_motion(elite)
		var heading: float = pose.aim_angle[joint]
		if not is_nan(previous): worst_step = maxf(worst_step, absf(wrapf(heading - previous, -PI, PI)))
		previous = heading
		if ticks_to_arrive < 0 and absf(wrapf(heading - PI, -PI, PI)) < 0.001: ticks_to_arrive = tick
	var limit: float = float(ShipGrammar.MOTION.aim_slew) / 60.0
	t.check(worst_step <= limit + 0.00001 and worst_step > limit * 0.9, "A set piece swings at the slew limit, never faster (worst step %.5f rad, limit %.5f)" % [worst_step, limit])
	t.check(ticks_to_arrive > 20, "It takes time to come round to an aim behind it (%d ticks), it does not snap" % ticks_to_arrive)
	var drawn: Vector2 = (pose.local[rig.index_of("r2s0w1")] - pose.local[joint])
	t.check(ticks_to_arrive >= 0, "It does arrive on the gun's aim")
	# Control: with the limit lifted the same piece snaps in one tick.
	var fast: Dictionary = _elite(w)
	fast.aim = Vector2.RIGHT
	fast.part_aim[hub] = Vector2.LEFT
	w._last_dt = 10.0
	w.tick = 0
	w._step_motion(fast)
	w._step_motion(fast)
	t.control("a 10 s tick, so 30 rad of slew is allowed", absf(wrapf((fast.pose as ShipMotion.ShipPose).aim_angle[joint] - PI, -PI, PI)) < 0.001)
	if drawn == Vector2.ZERO: pass
	release(w)

func _test_debris(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = _elite(w)
	var rig: ShipMotion.ShipRig = elite.rig
	elite.vel = Vector2.ZERO
	w._last_dt = 1.0 / 60.0
	w.tick = 30
	w._step_motion(elite)
	w._damage_part(elite, rig.index_of("r2s0"), 1000000.0, w.player)
	var d: Dictionary = w.debris[-1]
	var spin: float = absf(float(d.spin))
	t.check(spin >= 0.5 and spin <= 1.5, "Debris spins at 0.5-1.5 rad/s (%.2f)" % spin)
	t.check(Vector2(d.velocity).length() > 1.0, "A cluster torn off a turning rail leaves with velocity though the hull stood still (%.1f px/s)" % Vector2(d.velocity).length())
	var light: float = float(d.light)
	var pickups_before: int = w.pickups.size()
	for i: int in range(29): w._update_debris(1.0 / 60.0) # 0.483 s
	t.control("the light asked for before 0.5 s", w.pickups.size() == pickups_before and float(w.debris[-1].light) == light)
	for i: int in range(3): w._update_debris(1.0 / 60.0) # 0.533 s
	t.check(w.pickups.size() > pickups_before and not w.debris.is_empty() and float(w.debris[-1].light) == 0.0, "It drops its light at 0.5 s and goes on fading")
	var dropped: int = w.pickups.size()
	for i: int in range(40): w._update_debris(1.0 / 60.0)
	t.check(w.debris.is_empty() and w.pickups.size() == dropped, "It is gone at 1.0 s and never pays twice")
	release(w)

func _test_core_weapon_fires(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	var elite: Dictionary = _elite(w)
	for i: int in elite.gun_indices: elite.part_cd[i] = 9999.0 # silence the hubs: only the core may speak
	var from_core: int = 0
	for tick: int in range(600):
		w.set_command(ShipCommand.new())
		w._physics_process(1.0 / 60.0)
		if elite.is_empty() or bool(elite.get("dead", false)): break
	for index: int in w.bullets.active_indices:
		if int(w.bullets.owners[index]) == int(elite.id): from_core += 1
	t.check(str((elite.definition as ShipDefinition).primary) == "bolt" and from_core > 0, "With its hubs silenced, an elite still fires its core weapon (%d bolts live after 10 s)" % from_core)
	release(w)
	var quiet: CombatWorld = make_world()
	var mute: Dictionary = _elite(quiet)
	mute.archetype = "" # what a v0.3 hull declares: the core-weapon call is skipped
	for i: int in mute.gun_indices: mute.part_cd[i] = 9999.0
	for tick: int in range(600):
		quiet.set_command(ShipCommand.new())
		quiet._physics_process(1.0 / 60.0)
	var silent: int = 0
	for index: int in quiet.bullets.active_indices:
		if int(quiet.bullets.owners[index]) == int(mute.id): silent += 1
	t.control("the elite's declared archetype blanked, as on a v0.3 hull (%d bolts)" % silent, silent == 0)
	release(quiet)

func _test_twins(t: RefCounted) -> void:
	var w: CombatWorld = make_world()
	w.set_player_hull("fixture_player_t3", false)
	var player: Dictionary = w.player
	var rig: ShipMotion.ShipRig = player.rig
	w.tick = 0
	w._step_motion(player)
	var first: Vector2 = w._muzzle(player, "secondary_0")
	var second: Vector2 = w._muzzle(player, "secondary_0")
	var third: Vector2 = w._muzzle(player, "secondary_0")
	t.check(first.distance_to(second) > 10.0 and first.distance_to(third) < 0.001, "Mirror twins share one mount and take turns as the muzzle")
	t.check(w._muzzle(player, "primary").distance_to(w._part_position(player, rig.index_of("r1s0"))) < 0.001, "The primary fires from its forward hub")
	t.control("a mount the hull does not have falls back to the hull's centre", w._muzzle(player, "secondary_2").distance_to(Vector2(player.pos)) < 0.001)
	release(w)
