extends SceneTree
## ShipRig/ShipPose/ShipMotion.step: the sim's idea of a mount and the
## renderer's idea of the same circle must never disagree, motion must be a
## pure function of (rig, tick), and nothing may allocate per step.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void:
	var h: Harness = Harness.new("ship_motion")

	# --- Find (or fail loudly on) a hull that actually carries a group ---
	var grouped: ShipDefinition = null
	for id: String in ["enemy_corruption_t2", "enemy_corruption_t3", "player_corruption_t2_standard_a"]:
		var candidate: ShipDefinition = ShipCatalog.get_ship(id)
		if candidate != null and not candidate.groups.is_empty(): grouped = candidate; break
	h.check(grouped != null, "At least one shipped hull carries a group")

	# --- Agreement: sim mount position == renderer pose upload, every tick ---
	if grouped != null:
		var rig: ShipMotion.ShipRig = ShipMotion.get_rig(grouped)
		var sim_pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
		var render_pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
		var moved_index: int = -1
		for i: int in range(rig.group_index.size()):
			var slot: int = rig.group_index[i]
			if slot < 0: continue
			# A group's own root can sit exactly on its rotation pivot (e.g. a
			# whole-hull breathing group rooted at the core, which has no
			# parent to pivot around) and never translate; pick a member that
			# is actually offset from the pivot so "moves" is a real claim.
			if rig.rest[i].distance_to(rig.rest[rig.group_root_index[slot]]) > 0.01: moved_index = i; break
		if moved_index < 0:
			for i: int in range(rig.group_index.size()):
				if rig.group_index[i] >= 0: moved_index = i; break
		h.check(moved_index >= 0, grouped.id + " rig actually assigns a circle to a group")
		var disagreements: int = 0
		var ever_moved: bool = false
		for tick: int in range(600):
			ShipMotion.step(rig, sim_pose, tick)
			ShipMotion.step(rig, render_pose, tick)
			if moved_index >= 0:
				if not sim_pose.local[moved_index].is_equal_approx(rig.rest[moved_index]): ever_moved = true
				if not sim_pose.local[moved_index].is_equal_approx(render_pose.local[moved_index]): disagreements += 1
		h.check(ever_moved, grouped.id + "'s grouped circle actually moves over 600 ticks")
		h.check(disagreements == 0, "Sim pose and render pose agree on every tick (0 differences found)")
		# Negative control: compare against a pose stepped one tick behind.
		var lagging_pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
		var lag_disagreements: int = 0
		for tick: int in range(600):
			ShipMotion.step(rig, sim_pose, tick)
			ShipMotion.step(rig, lagging_pose, maxi(0, tick - 1))
			if moved_index >= 0 and not sim_pose.local[moved_index].is_equal_approx(lagging_pose.local[moved_index]): lag_disagreements += 1
		h.control("comparison pose stepped to tick-1", lag_disagreements > 0)

	# --- Determinism: same ticks -> byte-identical local arrays ---
	if grouped != null:
		var rig_a: ShipMotion.ShipRig = ShipMotion.get_rig(grouped)
		var rig_b: ShipMotion.ShipRig = ShipMotion.get_rig(grouped)
		var pose_a: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig_a)
		var pose_b: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig_b)
		var mismatch: bool = false
		for tick: int in [0, 1, 37, 599, 6000]:
			ShipMotion.step(rig_a, pose_a, tick)
			ShipMotion.step(rig_b, pose_b, tick)
			if pose_a.local.to_byte_array() != pose_b.local.to_byte_array(): mismatch = true
		h.check(not mismatch, "Two independently built rigs/poses stepped with the same ticks are byte-identical")
		# Negative control: a wall-clock-derived "tick" must produce a different result.
		var pose_wall: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig_a)
		var wall_tick: int = int(Time.get_ticks_msec() / 1000.0 * 60.0) + 1000003 # never equals a fixed sim tick
		ShipMotion.step(rig_a, pose_a, 37)
		ShipMotion.step(rig_a, pose_wall, wall_tick)
		h.control("stepped with a wall-clock-derived tick instead of the sim tick", pose_a.local.to_byte_array() != pose_wall.local.to_byte_array())

	# --- No allocation across 600 steps ---
	if grouped != null:
		var rig_alloc: ShipMotion.ShipRig = ShipMotion.get_rig(grouped)
		var pose_alloc: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig_alloc)
		ShipMotion.step(rig_alloc, pose_alloc, 0) # warm up
		var before: int = Performance.get_monitor(Performance.OBJECT_COUNT)
		for tick: int in range(600): ShipMotion.step(rig_alloc, pose_alloc, tick)
		var after: int = Performance.get_monitor(Performance.OBJECT_COUNT)
		h.check(after == before, "step() allocates no new Objects across 600 calls (before=%d after=%d)" % [before, after])
		# Negative control: something that DOES allocate must move the counter.
		var before_control: int = Performance.get_monitor(Performance.OBJECT_COUNT)
		var sink: Array[RefCounted] = []
		for i: int in range(50): sink.append(RefCounted.new())
		var after_control: int = Performance.get_monitor(Performance.OBJECT_COUNT)
		h.control("50 RefCounted.new() calls", after_control != before_control)

	# --- Symmetry: a mirrored pair stays a mirror image at every tick ---
	var mirror_ship: ShipDefinition = null
	for id: String in ["player_plasma_t2_standard_a", "player_plasma_t3_standard_a", "player_plasma_t4_standard_a", "player_void_t4_standard_a"]:
		var candidate: ShipDefinition = ShipCatalog.get_ship(id)
		if candidate != null:
			for group: GroupDefinition in candidate.groups:
				if group.root_id.ends_with("_l"): mirror_ship = candidate; break
		if mirror_ship != null: break
	h.check(mirror_ship != null, "At least one player hull carries a mirrored pair of groups")
	if mirror_ship != null:
		var rig: ShipMotion.ShipRig = ShipMotion.get_rig(mirror_ship)
		var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
		var left_id: String = ""
		for group: GroupDefinition in mirror_ship.groups:
			if group.root_id.ends_with("_l"): left_id = group.root_id; break
		var right_id: String = left_id.substr(0, left_id.length() - 2) + "_r"
		var left_index: int = rig.index_of(left_id)
		var right_index: int = rig.index_of(right_id)
		h.check(left_index >= 0 and right_index >= 0, "Both halves of the mirrored pair resolve to rig indices")
		var broke_symmetry: bool = false
		for tick: int in range(0, 600, 7):
			ShipMotion.step(rig, pose, tick)
			var left: Vector2 = pose.local[left_index]
			var right: Vector2 = pose.local[right_index]
			if not is_equal_approx(left.x, -right.x) or not is_equal_approx(left.y, right.y): broke_symmetry = true
		h.check(not broke_symmetry, mirror_ship.id + ": mirrored pair stays a mirror image at every sampled tick")
		# Negative control: force one side's orbit_speed to match (not oppose) the other's.
		var sabotaged: ShipDefinition = mirror_ship.duplicate(true)
		for group: GroupDefinition in sabotaged.groups:
			if group.root_id == left_id: group.orbit_speed = absf(group.orbit_speed)
			if group.root_id == right_id: group.orbit_speed = absf(group.orbit_speed)
		var broken_rig: ShipMotion.ShipRig = ShipMotion.get_rig(sabotaged)
		var broken_pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(broken_rig)
		var caught: bool = false
		for tick: int in range(1, 600, 7):
			ShipMotion.step(broken_rig, broken_pose, tick)
			var left: Vector2 = broken_pose.local[broken_rig.index_of(left_id)]
			var right: Vector2 = broken_pose.local[broken_rig.index_of(right_id)]
			if not is_equal_approx(left.x, -right.x) or not is_equal_approx(left.y, right.y): caught = true
		h.control("both mirrored roots given the same (not opposite) orbit_speed sign", caught)

	# --- Reach ring: exactly one dashed, unfilled synthesized circle at orbit_radius ---
	var void_ship: ShipDefinition = ShipCatalog.get_ship("enemy_drone_void_t4")
	h.check(void_ship != null, "enemy_drone_void_t4 exists")
	if void_ship != null:
		var ring_groups: Array[GroupDefinition] = []
		for group: GroupDefinition in void_ship.groups:
			if group.reach_ring: ring_groups.append(group)
		h.check(ring_groups.size() == 1, "Exactly one reach-ring group is declared")
		if ring_groups.size() == 1:
			var mesh: ShipMesh = ShipMesh.new()
			mesh.build(void_ship)
			var ring_id: String = "__reach__" + ring_groups[0].root_id
			h.check(mesh.part_indices.has(ring_id), "The synthesized ring occupies a real circle slot")
			var ring_index: int = mesh.part_indices.get(ring_id, -1)
			if ring_index >= 0:
				h.check(is_equal_approx(mesh.geometries[ring_index].x, ring_groups[0].orbit_radius), "Synthesized ring radius equals the group's orbit_radius")
				h.check(is_equal_approx(mesh.parameters[ring_index].w, 1.0), "Synthesized ring is styled dashed (style 1.0)")
		# Negative control: a group claiming reach_ring with a bad root_id must not synthesize a ring.
		var bad_ship: ShipDefinition = void_ship.duplicate(true)
		var bad_group: GroupDefinition = GroupDefinition.new()
		bad_group.root_id = "does_not_exist"
		bad_group.reach_ring = true
		bad_group.orbit_radius = 999.0
		bad_ship.groups = [bad_group]
		var bad_mesh: ShipMesh = ShipMesh.new()
		bad_mesh.build(bad_ship)
		h.control("reach-ring group with a nonexistent root_id", not bad_mesh.part_indices.has("__reach__does_not_exist"))

	h.finish(self)
