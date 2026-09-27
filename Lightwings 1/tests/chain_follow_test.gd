extends SceneTree
## The attached HTML's historical following, exercised through the production rig and world.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _fixture() -> ShipDefinition:
	var ship := ShipDefinition.new()
	ship.id = "chain_follow_reference_test"
	ship.schema_version = 4
	ship.archetype = "chain"
	ship.chain_mode = "follow"
	ship.element = "corruption"
	ship.faction = "enemy"
	ShipCatalog.add_part(ship, "core", "circle", Vector2.ZERO, 3.0, "white")
	var parent: String = "core"
	for i: int in range(9):
		ship.chain_links.append(SlotDefinition.new())
		var id: String = "c%d" % i
		var point := Vector2((i + 1) * 30.0, 0.0)
		var part: PartDefinition = ShipCatalog.add_part(ship, id, "circle", point, 16.0 - i * 1.1, "green", "structure", 3, true, parent)
		if i == 2 or i == 6:
			part.ability_id = "bolt"
			part.mount_id = "gun_%d" % i
		var line := PartDefinition.new()
		line.id = id + "_line"
		line.shape = "line"
		line.from_id = parent
		line.to_id = id
		ship.parts.append(line)
		if i % 3 == 1:
			var mark: PartDefinition = ShipCatalog.add_part(ship, id + "_mark", "circle", point, part.radius * 0.3, "yellow", "", 4, true, id)
			mark.solid = false
			mark.integrated_host = id
		if i == 6:
			var ornament: PartDefinition = ShipCatalog.add_part(ship, id + "_glyph", "circle", point + Vector2(12, -15), 4.0, "yellow", "", 4, true, id)
			ornament.solid = false
			var tether := PartDefinition.new()
			tether.id = id + "_glyph_line"
			tether.shape = "line"
			tether.from_id = id
			tether.to_id = ornament.id
			tether.color_role = "yellow"
			ship.parts.append(tether)
		parent = id
	return ship

func _head(tick: int) -> Vector2:
	var time: float = float(tick) / 60.0
	return Vector2(330.0 + cos(time * 0.5) * 90.0, 150.0 + sin(time * 0.9) * 46.0)

func _run() -> void:
	var h := Harness.new("CHAIN FOLLOW")
	var ship: ShipDefinition = _fixture()
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose := ShipMotion.ShipPose.new(rig)
	var repeat := ShipMotion.ShipPose.new(rig)
	var stretch: float = 0.0
	var difference: float = 0.0
	for tick: int in range(361):
		ShipMotion.step(rig, pose, tick, _head(tick))
		ShipMotion.step(rig, repeat, tick, _head(tick))
		# A second renderer pass at the same tick must not advance the solver.
		ShipMotion.step(rig, repeat, tick, _head(tick))
		var previous: Vector2 = _head(tick)
		for slot: int in range(rig.follow_indices.size()):
			var point: Vector2 = pose.chain_current[slot]
			stretch = maxf(stretch, absf(point.distance_to(previous) - 30.0))
			difference = maxf(difference, point.distance_to(repeat.chain_current[slot]))
			previous = point
	h.check(rig.follow_indices.size() == 9, "Nine tapered main links are identified independently of nested markings")
	h.check(stretch < 0.001, "Moving reference head keeps every tether at30px (worst stretch %.6f)" % stretch)
	h.check(difference < 0.00001, "Extra render samples do not advance historical following")
	var before: Vector2 = pose.chain_current[-1]
	ShipMotion.step(rig, pose, 361, _head(360), PI / 2.0)
	h.check(before.distance_to(pose.chain_current[-1]) < 2.0, "A90degree hull turn bends from history instead of instantly rotating the tail")
	var rigid_tip: Vector2 = _head(360) + rig.rest[rig.follow_indices[-1]].rotated(PI / 2.0)
	h.control("Rigid hull-frame rotation", rigid_tip.distance_to(pose.chain_current[-1]) > 100.0)
	var encoded: Dictionary = CombatPersistence.json_value(ShipMotion.encode_chain_state(rig, pose))
	var restored := ShipMotion.ShipPose.new(rig)
	ShipMotion.restore_chain_state(rig, restored, CombatPersistence.decode_value(encoded))
	for tick: int in range(362, 422):
		ShipMotion.step(rig, pose, tick, _head(tick), PI / 2.0)
		ShipMotion.step(rig, restored, tick, _head(tick), PI / 2.0)
	h.check(pose.chain_current == restored.chain_current and pose.chain_previous == restored.chain_previous, "Mid-turn JSON save restores current and previous positions exactly")
	var missing := ShipMotion.ShipPose.new(rig)
	ShipMotion.restore_chain_state(rig, missing, {})
	ShipMotion.step(rig, missing, 422, _head(422), PI / 2.0)
	h.check(missing.chain_current.size() == 9 and missing.chain_tick == 422, "Older saves initialize a valid chain without requiring history")
	_test_combat(h, ship)
	_test_cached_fixture(h)
	_test_player_restore(h)
	h.finish(self)

func _test_combat(h: RefCounted, ship: ShipDefinition) -> void:
	var world := CombatWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	var actor: Dictionary = world._spawn_enemy("corruption", 4, Vector2(900, 500), false)
	actor.erase("_reward_split")
	actor.reward_remaining = 100.0
	world._configure_actor(actor, ship, true)
	actor.aim = Vector2.UP
	for tick: int in range(180):
		world.tick = tick
		actor.pos = _head(tick) + Vector2(500, 400)
		world._step_motion(actor)
	var rig: ShipMotion.ShipRig = actor.rig
	var pose: ShipMotion.ShipPose = actor.pose
	var aligned: bool = true
	for index: int in rig.follow_indices:
		aligned = aligned and world._part_position(actor, index).distance_to(pose.world_current[index]) < 0.001
	h.check(aligned, "Combat colliders and weapon origins consume the solved historical pose")
	h.check(pose.world_velocity[rig.index_of("c6")].length() > 0.1, "Per-circle velocity includes the actual chain motion")
	actor.archetype = "chain"
	actor.decision_cd = 10.0
	actor.desired = Vector2.RIGHT
	actor.desired_aim = Vector2.RIGHT
	actor.part_cd[rig.index_of("c2")] = 0.0
	actor.part_cd[rig.index_of("c6")] = 999.0
	var fired: Array[Vector2] = []
	world.shot_audio_requested.connect(func(at: Vector2, _element: String, ability: String, owner: int) -> void:
		if owner == int(actor.id) and ability == "bolt": fired.append(at))
	world.tick += 1
	world._update_ai(actor, 1.0 / 60.0)
	h.check(pose.chain_head == Vector2(actor.pos), "AI integrates the final head position before the historical chain solve")
	h.check(fired.size() == 1 and fired[0].distance_to(world._part_position(actor, rig.index_of("c2"))) < 0.001, "A moving chain fires from its current authoritative muzzle")
	actor.pos += Vector2(4.0, -2.0)
	world._refresh_follow_pose(actor)
	h.check(pose.chain_current[0].distance_to(actor.pos) > 29.999 and pose.chain_current[0].distance_to(actor.pos) < 30.001, "Late external pull reanchors the head tether without another wave tick")
	var rng_before: int = world._rng.state
	world._destroy_part(actor, rig.index_of("c4"), world.player)
	h.check(world._rng.state == rng_before, "Visual debris scatter does not advance combat RNG")
	var detached: bool = true
	for i: int in range(9):
		detached = detached and (bool(actor.part_attached[rig.index_of("c%d" % i)]) == (i < 4))
	h.check(detached and actor.part_hp[rig.index_of("c6")] == 0.0, "Severed descendants immediately lose attachment and weapon HP")
	var debris: Dictionary = world.debris[-1]
	h.check(debris.pieces.size() == 4, "Four downstream links remain as separate outlined debris bodies; the junction disappears")
	var old_positions: Array = []
	for body: Dictionary in debris.pieces: old_positions.append(body.position)
	var nested: bool = false
	var linked_ornament: bool = false
	for body: Dictionary in debris.pieces:
		if body.circles.size() > 1: nested = body.circles[1].color == VisualStyle.ACCENT and body.circles[1].radius > 0.0
		if not body.lines.is_empty(): linked_ornament = body.lines[0].color == VisualStyle.ACCENT
	h.check(nested, "Detached link keeps its nested gold marking and original radius")
	h.check(linked_ornament, "External weapon ornament retains its own connecting line on the same debris body")
	for i: int in range(20): world._update_debris(1.0 / 60.0)
	var held: bool = true
	for i: int in range(debris.pieces.size()): held = held and debris.pieces[i].position == old_positions[i]
	h.check(held, "Visual-only remains hold during the0.35second release delay")
	for i: int in range(13): world._update_debris(1.0 / 60.0)
	var first_drift: Vector2 = Vector2(debris.pieces[0].position) - Vector2(old_positions[0])
	var second_drift: Vector2 = Vector2(debris.pieces[1].position) - Vector2(old_positions[1])
	h.check(first_drift.length() > 0.1 and first_drift.distance_to(second_drift) > 0.1, "Released links inherit motion and drift independently")
	var pickups: int = world.pickups.size()
	h.check(float(debris.light) == 0.0 and pickups > 0, "Detached reward pays once at0.5seconds while geometry keeps fading")
	for i: int in range(54): world._update_debris(1.0 / 60.0)
	h.check(not world.debris.is_empty(), "The 1.4 second fade starts after the 0.35 second release delay")
	for i: int in range(20): world._update_debris(1.0 / 60.0)
	h.check(world.debris.is_empty() and world.pickups.size() == pickups, "Outlined debris expires after 1.75 seconds without a second reward")
	world._clear_encounter()
	world.free()

func _test_player_restore(h: RefCounted) -> void:
	var errors := PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/living_ships/following_chain.json", errors)
	ShipCompiler.compile(ship)
	var world := CombatWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	world.hull_id = ship.id
	world.player.hull_id = ship.id
	world._configure_actor(world.player, ship, true)
	world.player.aim = Vector2.UP
	for tick: int in range(137):
		world.tick = tick
		world.player_position = _head(tick) + Vector2(300, 300)
		world._step_motion(world.player)
	var pose: ShipMotion.ShipPose = world.player.pose
	var rig: ShipMotion.ShipRig = world.player.rig
	var expected := ShipMotion.ShipPose.new(rig)
	ShipMotion.restore_chain_state(rig, expected, ShipMotion.encode_chain_state(rig, pose))
	var current: PackedVector2Array = pose.chain_current.duplicate()
	var previous: PackedVector2Array = pose.chain_previous.duplicate()
	var local: PackedVector2Array = pose.local.duplicate()
	var saved: Dictionary = CombatPersistence.snapshot(world)
	world.tick += 5000
	CombatPersistence.restore(world, saved)
	var restored: ShipMotion.ShipPose = world.player.pose
	h.check(world.tick == 136 and restored.chain_tick == 136, "Whole-world restore sets the saved clock after player setup and before chain history")
	h.check(restored.chain_current == current and restored.chain_previous == previous and restored.local == local, "Custom chain player restores the complete mid-turn pose immediately")
	var tip: int = (world.player.rig as ShipMotion.ShipRig).follow_indices[-1]
	h.check(restored.world_velocity[tip].distance_to((current[-1] - previous[-1]) * 60.0) < 0.001, "Immediate post-load debris inherits saved chain velocity")
	world.tick += 1
	world.player_position += Vector2(1.0, -0.5)
	ShipMotion.step(rig, expected, world.tick, world.player_position)
	world._step_motion(world.player)
	h.check(restored.chain_current == expected.chain_current and restored.chain_previous == expected.chain_previous, "The next player tick matches uninterrupted chain history")
	world._clear_encounter()
	world.free()

func _test_cached_fixture(h: RefCounted) -> void:
	var errors := PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/living_ships/following_chain.json", errors)
	h.check(ship != null and errors.is_empty(), "Production authoring loads the exact nine-link reference fixture")
	if ship == null: return
	ShipCompiler.compile(ship)
	var world := CombatWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	var actor: Dictionary = world._spawn_enemy("corruption", 4, Vector2(950, 600), false)
	actor.hull_id = ship.id
	actor.archetype = "chain"
	world._configure_actor(actor, ship, true)
	actor.aim = Vector2.UP
	for tick: int in range(240):
		world.tick = tick
		actor.pos = _head(tick) + Vector2(500, 400)
		world._step_motion(actor)
	var pose: ShipMotion.ShipPose = actor.pose
	var rig: ShipMotion.ShipRig = actor.rig
	var head_turn: float = pose.local[rig.index_of("c0")].angle() - Vector2.DOWN.angle()
	var lobes_follow: bool = true
	for id: String in ["head_lobe0", "head_lobe1"]:
		var index: int = rig.index_of(id)
		lobes_follow = lobes_follow and pose.local[index].distance_to(rig.rest[index].rotated(head_turn)) < 0.001 and rig.solid[index] == 0
	h.check(lobes_follow, "Non-solid reference head lobes follow the solved first-link direction")
	var custom: ShipDefinition = ship.duplicate(true)
	custom.chain_head_lobes = false
	var custom_rig: ShipMotion.ShipRig = ShipMotion.get_rig(custom)
	var custom_pose := ShipMotion.ShipPose.new(custom_rig)
	ShipMotion.restore_chain_state(custom_rig, custom_pose, ShipMotion.encode_chain_state(rig, pose))
	ShipMotion.step(custom_rig, custom_pose, world.tick, actor.pos)
	h.control("Same-named custom circles without the authored head-lobe flag", custom_pose.local[custom_rig.index_of("head_lobe0")] == custom_rig.rest[custom_rig.index_of("head_lobe0")] and absf(head_turn) > 0.01)
	var saved_current: PackedVector2Array = pose.chain_current.duplicate()
	var saved_previous: PackedVector2Array = pose.chain_previous.duplicate()
	var saved_local: PackedVector2Array = pose.local.duplicate()
	var snapshot: Dictionary = CombatPersistence.encounter_snapshot(world)
	world.tick += 12000
	CombatPersistence.restore_encounter(world, snapshot)
	var restored: Dictionary = world.enemies[0]
	var resumed: ShipMotion.ShipPose = restored.pose
	h.check(resumed.chain_current == saved_current and resumed.chain_previous == saved_previous, "Cold cached encounter preserves historical positions while absent")
	h.check(resumed.chain_tick == world.tick, "Cache restore rebases the chain clock without simulating absent time")
	h.check(resumed.local == saved_local, "Restored pose is materialized immediately, before the first rendered frame")
	var hp: PackedFloat32Array = restored.part_hp.duplicate()
	world.tick += 1
	world._step_motion(restored)
	h.check(resumed.chain_current[-1].distance_to(saved_current[-1]) < 2.0 and restored.part_hp == hp, "Cold encounter resumes without a tail jump or health change")
	world._clear_encounter()
	world.free()
