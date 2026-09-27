class_name ShipMotion
extends RefCounted
## The single source of where a circle is. `ShipRig` is the immutable, cached
## shape of a hull's motion (built once per `ShipDefinition`); `ShipPose` is
## the small per-instance state `step()` writes in place from the simulation's
## integer tick. Both the renderer and the simulation (muzzles, gun colliders,
## the bullet-eater mouth) must read the same pose or aiming stops feeling
## honest (spec §18).

const MAX_CACHE_ENTRIES: int = 96
## Hulls at or above this schema are rail-grammar hulls: forward kinematics, no groups.
const FK_SCHEMA: int = 4
static var _cache: Dictionary = {}
static var cache_hits: int = 0
static var cache_misses: int = 0

static func clear_cache() -> void:
	_cache.clear()
	cache_hits = 0
	cache_misses = 0

static func cache_stats() -> Dictionary:
	return {"entries": _cache.size(), "hits": cache_hits, "misses": cache_misses}

class ShipRig extends RefCounted:
	## Circles only, in pre-order depth-first order from the core: every
	## subtree is the contiguous range [i, i + subtree_size[i]).
	var ids: PackedStringArray = PackedStringArray()
	var parent_index: PackedInt32Array = PackedInt32Array()
	var rest: PackedVector2Array = PackedVector2Array()
	var radius: PackedFloat32Array = PackedFloat32Array()
	var subtree_size: PackedInt32Array = PackedInt32Array()
	var group_index: PackedInt32Array = PackedInt32Array()      # -1, else index into `groups`
	var group_root_index: PackedInt32Array = PackedInt32Array() # per group, rig index of its root
	var chain_position: PackedFloat32Array = PackedFloat32Array() # 0 (root) .. 1 (tip) inside a sway/whip chain
	var mirror_index: PackedInt32Array = PackedInt32Array()     # -1, else the rig index of the mirrored circle
	var line_from: PackedInt32Array = PackedInt32Array()
	var line_to: PackedInt32Array = PackedInt32Array()
	var line_ids: PackedStringArray = PackedStringArray() # the line's own PartDefinition.id, aligned with line_from/line_to
	## P4a: per-hull-constant per-circle metadata, cached here (not per actor)
	## because it never changes for a given ShipDefinition. Combat reads these
	## to size an actor's mutable per-circle packed arrays (part_hp etc.).
	var ability_id: PackedStringArray = PackedStringArray()
	var mount_id: PackedStringArray = PackedStringArray()
	var authored_hp: PackedFloat32Array = PackedFloat32Array()
	var groups: Array[GroupDefinition] = []
	var id_index: Dictionary = {}
	## Ship design spec (schema 4). `legacy` hulls use the v0.3 group evaluator and leave the joint
	## arrays empty; rail-grammar hulls use forward kinematics (`_step_fk`) and have no groups.
	var legacy: bool = true
	var spin_speed: PackedFloat32Array = PackedFloat32Array()
	var bob_amp: PackedFloat32Array = PackedFloat32Array()
	var bob_freq: PackedFloat32Array = PackedFloat32Array()
	var bob_phase: PackedFloat32Array = PackedFloat32Array()
	var pump_amp: PackedFloat32Array = PackedFloat32Array()
	var pump_freq: PackedFloat32Array = PackedFloat32Array()
	var pump_phase: PackedFloat32Array = PackedFloat32Array()
	var aim_joint: PackedByteArray = PackedByteArray()
	var rest_heading: PackedFloat32Array = PackedFloat32Array()
	## Rig indices of the aim joints (set-piece roots), so the sim slews only those.
	var aim_indices: PackedInt32Array = PackedInt32Array()
	## 1 = has HP, a collider and a reward share. Every circle of a legacy hull is solid.
	var solid: PackedByteArray = PackedByteArray()
	## Rig indices of the solid circles other than the core, ascending: what the broadphase walks.
	var solid_indices: PackedInt32Array = PackedInt32Array()
	## Main links only, head to tip. Decorations remain ordinary children of their link.
	var follow_indices: PackedInt32Array = PackedInt32Array()
	var follow_slot: PackedInt32Array = PackedInt32Array()
	var follow_head_lobes: PackedInt32Array = PackedInt32Array()

	func has(id: String) -> bool:
		return id_index.has(id)

	func index_of(id: String) -> int:
		return int(id_index.get(id, -1))

class ShipPose extends RefCounted:
	## Per-instance only; deliberately holds no reference back to an actor or
	## renderer (that would create a reference cycle - see `_break_actor_cycles`).
	var local: PackedVector2Array = PackedVector2Array()
	var scale: PackedFloat32Array = PackedFloat32Array()
	var flare: PackedFloat32Array = PackedFloat32Array() # reserved for P8 rim flare; always 0 today
	## Forward kinematics only. `angle` is each circle's accumulated rotation, scratch for the pass.
	## `aim_angle` is an INPUT: the hull-frame angle an aim joint should take, NAN for "none, point
	## outward". The simulation owns it (S3 slews it toward the gun's aim); step() only reads it.
	var angle: PackedFloat32Array = PackedFloat32Array()
	var aim_angle: PackedFloat32Array = PackedFloat32Array()
	## Historical world positions make a following tail respond to translation and turns.
	var chain_current: PackedVector2Array = PackedVector2Array()
	var chain_previous: PackedVector2Array = PackedVector2Array()
	var chain_tick: int = -1
	var chain_head: Vector2 = Vector2.ZERO
	var chain_basis: float = 0.0
	## Also retain each detailed circle's instantaneous velocity for visual debris.
	var world_current: PackedVector2Array = PackedVector2Array()
	var world_previous: PackedVector2Array = PackedVector2Array()
	var world_velocity: PackedVector2Array = PackedVector2Array()
	var world_tick: int = -1
	var world_dt: float = 1.0 / 60.0

	func _init(rig: ShipRig = null) -> void:
		if rig != null: reset(rig)

	func reset(rig: ShipRig) -> void:
		chain_current = PackedVector2Array()
		chain_previous = PackedVector2Array()
		chain_tick = -1
		world_tick = -1
		world_current.resize(rig.rest.size())
		world_previous.resize(rig.rest.size())
		world_velocity.resize(rig.rest.size())
		world_velocity.fill(Vector2.ZERO)
		angle = PackedFloat32Array()
		aim_angle = PackedFloat32Array()
		if not rig.legacy:
			angle.resize(rig.rest.size())
			angle.fill(0.0)
			aim_angle.resize(rig.rest.size())
			aim_angle.fill(NAN)
		local = rig.rest.duplicate()
		scale = PackedFloat32Array()
		scale.resize(rig.rest.size())
		scale.fill(1.0)
		flare = PackedFloat32Array()
		flare.resize(rig.rest.size())
		flare.fill(0.0)

	func local_of(rig: ShipRig, id: String) -> Vector2:
		var index: int = rig.index_of(id)
		return local[index] if index >= 0 else Vector2.ZERO

static func rig_key(ship: ShipDefinition) -> PackedByteArray:
	var signature: Array = []
	var fk: bool = ship.schema_version >= FK_SCHEMA
	if fk: signature.append(["fk", ship.schema_version, ship.archetype, ship.chain_mode, ship.chain_head_lobes])
	for part: PartDefinition in ship.parts:
		if part.shape == "circle":
			signature.append([part.id, part.position, part.radius, part.filled, part.parent_id])
			# Appended only for rail-grammar hulls, so a legacy hull's key is byte-identical to v0.3's.
			if fk: signature.append([part.spin_speed, part.bob_amp, part.bob_freq, part.bob_phase, part.pump_amp, part.pump_freq, part.pump_phase, part.aim_joint, part.rest_heading, part.solid])
		elif part.shape == "line": signature.append(["line", part.id, part.from_id, part.to_id])
	for group: GroupDefinition in ship.groups:
		signature.append(["group", group.root_id, group.orbit_radius, group.orbit_speed, group.drift_amp, group.drift_freq, group.breathe_amp, group.chain_mode, group.reach_ring])
	return var_to_bytes(signature)

static func get_rig(ship: ShipDefinition) -> ShipRig:
	var key: PackedByteArray = rig_key(ship)
	if _cache.has(key):
		cache_hits += 1
		return _cache[key]
	cache_misses += 1
	var rig: ShipRig = _build_rig(ship)
	_cache[key] = rig
	if _cache.size() > MAX_CACHE_ENTRIES: _cache.erase(_cache.keys()[0])
	return rig

static func _dfs(id: String, children: Dictionary, order: Array[String]) -> void:
	order.append(id)
	for child: String in children.get(id, []):
		_dfs(child, children, order)

static func _build_rig(ship: ShipDefinition) -> ShipRig:
	var rig: ShipRig = ShipRig.new()
	var by_id: Dictionary = {}
	var authored_order: Dictionary = {}
	var circles: Array[PartDefinition] = []
	for part: PartDefinition in ship.parts:
		if part.shape == "circle":
			by_id[part.id] = part
			authored_order[part.id] = circles.size()
			circles.append(part)
	if not by_id.has("core"): return rig
	var children: Dictionary = {}
	for part: PartDefinition in circles:
		if part.id == "core": continue
		if not children.has(part.parent_id): children[part.parent_id] = []
		children[part.parent_id].append(part.id)
	for key: String in children:
		children[key].sort_custom(func(a: String, b: String) -> bool: return int(authored_order.get(a, 0)) < int(authored_order.get(b, 0)))
	var order: Array[String] = []
	_dfs("core", children, order)
	rig.ids = PackedStringArray(order)
	rig.parent_index.resize(order.size())
	rig.rest.resize(order.size())
	rig.radius.resize(order.size())
	rig.group_index.resize(order.size())
	rig.chain_position.resize(order.size())
	rig.mirror_index.resize(order.size())
	rig.group_index.fill(-1)
	rig.mirror_index.fill(-1)
	rig.ability_id.resize(order.size())
	rig.mount_id.resize(order.size())
	rig.authored_hp.resize(order.size())
	for i: int in range(order.size()): rig.id_index[order[i]] = i
	for i: int in range(order.size()):
		var part: PartDefinition = by_id[order[i]]
		rig.rest[i] = part.position
		rig.radius[i] = part.radius
		rig.parent_index[i] = rig.id_index.get(part.parent_id, -1) if part.id != "core" else -1
		rig.ability_id[i] = part.ability_id
		rig.mount_id[i] = part.mount_id
		rig.authored_hp[i] = part.hp
	rig.legacy = ship.schema_version < FK_SCHEMA
	rig.solid.resize(order.size())
	rig.solid.fill(1)
	if not rig.legacy:
		# Resized one by one: a packed array put in a list is a copy, so a loop would resize nothing.
		rig.spin_speed.resize(order.size())
		rig.bob_amp.resize(order.size())
		rig.bob_freq.resize(order.size())
		rig.bob_phase.resize(order.size())
		rig.pump_amp.resize(order.size())
		rig.pump_freq.resize(order.size())
		rig.pump_phase.resize(order.size())
		rig.aim_joint.resize(order.size())
		rig.rest_heading.resize(order.size())
		for i: int in range(order.size()):
			var joint: PartDefinition = by_id[order[i]]
			rig.rest_heading[i] = joint.rest_heading
			if joint.aim_joint: rig.aim_indices.append(i)
			rig.spin_speed[i] = joint.spin_speed
			rig.bob_amp[i] = joint.bob_amp
			rig.bob_freq[i] = joint.bob_freq
			rig.bob_phase[i] = joint.bob_phase
			rig.pump_amp[i] = joint.pump_amp
			rig.pump_freq[i] = joint.pump_freq
			rig.pump_phase[i] = joint.pump_phase
			rig.aim_joint[i] = 1 if joint.aim_joint else 0
			rig.solid[i] = 1 if joint.solid else 0
	for i: int in range(1, order.size()):
		if rig.solid[i] == 1: rig.solid_indices.append(i)
	rig.follow_slot.resize(order.size())
	rig.follow_slot.fill(-1)
	if not rig.legacy and ship.archetype == "chain" and ship.chain_mode == "follow":
		for link: int in range(ship.chain_links.size()):
			var index: int = rig.index_of("c%d" % link)
			if index < 0: continue
			rig.follow_slot[index] = rig.follow_indices.size()
			rig.follow_indices.append(index)
		if ship.chain_head_lobes:
			for id: String in ["head_lobe0", "head_lobe1"]:
				var index: int = rig.index_of(id)
				if index >= 0 and rig.solid[index] == 0 and rig.parent_index[index] == 0: rig.follow_head_lobes.append(index)
	for i: int in range(order.size()):
		var mirror_id: String = str(by_id[order[i]].mirror_id)
		if rig.id_index.has(mirror_id): rig.mirror_index[i] = int(rig.id_index[mirror_id])
	var child_indices: Array = []
	child_indices.resize(order.size())
	for i: int in range(order.size()): child_indices[i] = []
	for i: int in range(order.size()):
		if rig.parent_index[i] >= 0: (child_indices[rig.parent_index[i]] as Array).append(i)
	rig.subtree_size.resize(order.size())
	for i: int in range(order.size() - 1, -1, -1):
		var size: int = 1
		for c: int in child_indices[i]: size += rig.subtree_size[c]
		rig.subtree_size[i] = size
	# Groups: innermost (smallest subtree) claims its range first, so a nested
	# group root and its subtree are excluded from the enclosing group.
	var group_order: Array[int] = []
	for i: int in range(ship.groups.size()): group_order.append(i)
	group_order.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = rig.index_of(ship.groups[a].root_id)
		var rb: int = rig.index_of(ship.groups[b].root_id)
		var sa: int = rig.subtree_size[ra] if ra >= 0 else 0
		var sb: int = rig.subtree_size[rb] if rb >= 0 else 0
		return sa < sb)
	rig.groups = []
	rig.group_root_index.resize(ship.groups.size())
	var slot_for_source: Dictionary = {}
	for source_index: int in group_order:
		var group: GroupDefinition = ship.groups[source_index]
		var root_index: int = rig.index_of(group.root_id)
		if root_index < 0: continue
		var list_index: int = rig.groups.size()
		rig.groups.append(group)
		rig.group_root_index[list_index] = root_index
		slot_for_source[source_index] = list_index
		var last: int = root_index + rig.subtree_size[root_index]
		for i: int in range(root_index, last):
			if rig.group_index[i] == -1: rig.group_index[i] = list_index
		if group.chain_mode in ["sway", "whip"]:
			var span: int = maxi(1, rig.subtree_size[root_index] - 1)
			for i: int in range(root_index, last):
				if rig.group_index[i] == list_index: rig.chain_position[i] = float(i - root_index) / float(span)
	for part: PartDefinition in ship.parts:
		if part.shape != "line": continue
		if not rig.id_index.has(part.from_id) or not rig.id_index.has(part.to_id): continue
		rig.line_from.append(int(rig.id_index[part.from_id]))
		rig.line_to.append(int(rig.id_index[part.to_id]))
		rig.line_ids.append(part.id)
	return rig

## Writes `pose` in place. Allocates nothing (Vector2/float are value types).
## `tick` is the simulation's integer tick (never a wall clock) so replays and
## the paused-vs-running renderer cannot disagree with the sim.
static func step(rig: ShipRig, pose: ShipPose, tick: int, head: Vector2 = Vector2.ZERO, basis: float = 0.0, attached: PackedByteArray = PackedByteArray()) -> void:
	if pose.local.size() != rig.rest.size(): pose.reset(rig)
	if rig.legacy: _step_legacy(rig, pose, tick)
	else:
		if not rig.follow_indices.is_empty(): _follow_chain(rig, pose, tick, head, basis, attached)
		_step_fk(rig, pose, tick, head, basis, attached)
	_capture_world(rig, pose, tick, head, basis)

## The HTML reference projects each historical link onto a 30px tether, then adds a tiny
## perpendicular travelling-wave impulse. Reprojecting after the impulse keeps real collider
## spacing exact. Run at simulation ticks, never render delta; repeated draws do not advance it.
static func _follow_chain(rig: ShipRig, pose: ShipPose, tick: int, head: Vector2, basis: float, attached: PackedByteArray) -> void:
	var count: int = rig.follow_indices.size()
	if pose.chain_current.size() != count or tick < pose.chain_tick:
		pose.chain_current.resize(count)
		pose.chain_previous.resize(count)
		for slot: int in range(count):
			var point: Vector2 = head + rig.rest[rig.follow_indices[slot]].rotated(basis)
			pose.chain_current[slot] = point
			pose.chain_previous[slot] = point
		pose.chain_head = head
		pose.chain_basis = basis
		pose.chain_tick = tick - 1
	var elapsed_ticks: int = tick - pose.chain_tick
	if elapsed_ticks <= 0:
		# A late impulse (for example a black-hole pull) can move the head again in this tick.
		# Re-anchor the existing history without advancing the wave or consuming a second tick.
		if head != pose.chain_head:
			var anchor: Vector2 = head
			for slot: int in range(count):
				var index: int = rig.follow_indices[slot]
				if not attached.is_empty() and attached[index] == 0: break
				var rest: Vector2 = rig.rest[index] - rig.rest[rig.parent_index[index]]
				var direction: Vector2 = pose.chain_current[slot] - anchor
				if direction.length_squared() < 0.000001: direction = rest.rotated(basis)
				pose.chain_current[slot] = anchor + direction.normalized() * rest.length()
				anchor = pose.chain_current[slot]
		pose.chain_head = head
		pose.chain_basis = basis
		return
	var old_head: Vector2 = pose.chain_head
	var old_basis: float = pose.chain_basis
	for substep: int in range(1, elapsed_ticks + 1):
		var fraction: float = float(substep) / float(elapsed_ticks)
		var anchor: Vector2 = old_head.lerp(head, fraction)
		var heading: float = lerp_angle(old_basis, basis, fraction)
		var time: float = float(pose.chain_tick + substep) / 60.0
		for slot: int in range(count):
			var index: int = rig.follow_indices[slot]
			pose.chain_previous[slot] = pose.chain_current[slot]
			if not attached.is_empty() and attached[index] == 0: break
			var rest: Vector2 = rig.rest[index] - rig.rest[rig.parent_index[index]]
			var direction: Vector2 = pose.chain_current[slot] - anchor
			if direction.length_squared() < 0.000001: direction = rest.rotated(heading)
			direction = direction.normalized()
			var wave: float = sin(time * 3.2 - float(slot) * 0.85) * 11.0 * float(slot) / float(count)
			var offset: Vector2 = direction * rest.length() + direction.orthogonal() * wave * 0.06
			pose.chain_current[slot] = anchor + offset.normalized() * rest.length()
			anchor = pose.chain_current[slot]
	pose.chain_head = head
	pose.chain_basis = basis
	pose.chain_tick = tick

static func _capture_world(rig: ShipRig, pose: ShipPose, tick: int, head: Vector2, basis: float) -> void:
	var first: bool = pose.world_tick < 0 or tick < pose.world_tick
	if tick != pose.world_tick:
		pose.world_dt = 1.0 / 60.0 if first else float(maxi(1, tick - pose.world_tick)) / 60.0
		for index: int in range(rig.ids.size()): pose.world_previous[index] = pose.world_current[index]
	for index: int in range(rig.ids.size()):
		pose.world_current[index] = head + pose.local[index].rotated(basis)
		if first:
			pose.world_previous[index] = pose.world_current[index]
			# A freshly restored chain already has one tick of world history. Preserve that
			# velocity, including for its nested markings, if it breaks before another tick.
			var host: int = index
			while host > 0 and rig.follow_slot[host] < 0: host = rig.parent_index[host]
			var slot: int = rig.follow_slot[host] if host >= 0 else -1
			if slot >= 0 and slot < pose.chain_previous.size():
				pose.world_previous[index] -= pose.chain_current[slot] - pose.chain_previous[slot]
		pose.world_velocity[index] = (pose.world_current[index] - pose.world_previous[index]) / pose.world_dt
	pose.world_tick = tick

## Stable IDs keep history independent of rig ordering. Persistence's existing vector codec
## handles the vectors; restore also accepts JSON arrays for direct fixture/tool round trips.
static func encode_chain_state(rig: ShipRig, pose: ShipPose) -> Dictionary:
	if pose == null or pose.chain_current.size() != rig.follow_indices.size() or rig.follow_indices.is_empty(): return {}
	var links: Dictionary = {}
	for slot: int in range(rig.follow_indices.size()):
		links[rig.ids[rig.follow_indices[slot]]] = {"current": pose.chain_current[slot], "previous": pose.chain_previous[slot]}
	return {"version": 1, "tick": pose.chain_tick, "head": pose.chain_head, "basis": pose.chain_basis, "links": links}

static func _state_vector(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]), float(value[1]))
	return fallback

static func restore_chain_state(rig: ShipRig, pose: ShipPose, encoded: Dictionary) -> void:
	if encoded.is_empty() or int(encoded.get("version", 0)) != 1 or rig.follow_indices.is_empty(): return
	var links: Dictionary = encoded.get("links", {})
	for index: int in rig.follow_indices:
		if not links.has(rig.ids[index]): return # old/changed topology starts cleanly
	pose.chain_current.resize(rig.follow_indices.size())
	pose.chain_previous.resize(rig.follow_indices.size())
	for slot: int in range(rig.follow_indices.size()):
		var state: Dictionary = links[rig.ids[rig.follow_indices[slot]]]
		pose.chain_current[slot] = _state_vector(state.get("current"))
		pose.chain_previous[slot] = _state_vector(state.get("previous"), pose.chain_current[slot])
	pose.chain_tick = int(encoded.get("tick", -1))
	pose.chain_head = _state_vector(encoded.get("head"))
	pose.chain_basis = float(encoded.get("basis", 0.0))

## Rail-grammar hulls (ship design spec §9). One pass down the DFS order, so a parent is always
## posed before its children: a circle's angle is its parent's plus its own spin and bob, and it sits
## at its parent's live position plus its rest offset, pumped and rotated by that angle. So a pod
## bobs about its hub WHILE the hub rides its rail - which the v0.3 evaluator below cannot do,
## because there a circle belongs to one group and is posed from rest positions.
## Pure in (tick, pose.aim_angle), allocation-free, and it never touches `scale`: nothing in the
## new grammar changes a circle's size.
static func _step_fk(rig: ShipRig, pose: ShipPose, tick: int, head: Vector2 = Vector2.ZERO, basis: float = 0.0, attached: PackedByteArray = PackedByteArray()) -> void:
	var t: float = float(tick) / 60.0
	pose.local[0] = rig.rest[0]
	pose.angle[0] = 0.0
	pose.scale[0] = 1.0
	pose.flare[0] = 0.0
	for i: int in range(1, rig.rest.size()):
		var parent: int = rig.parent_index[i]
		var follow: int = rig.follow_slot[i]
		if follow >= 0 and follow < pose.chain_current.size():
			pose.local[i] = (pose.chain_current[follow] - head).rotated(-basis)
			var rest_offset: Vector2 = rig.rest[i] - rig.rest[parent]
			pose.angle[i] = (pose.local[i] - pose.local[parent]).angle() - rest_offset.angle()
			pose.scale[i] = 1.0
			pose.flare[i] = 0.0
			continue
		var turn: float = pose.angle[parent] + rig.spin_speed[i] * t
		if rig.bob_amp[i] != 0.0: turn += rig.bob_amp[i] * sin(rig.bob_freq[i] * t + rig.bob_phase[i])
		if rig.aim_joint[i] == 1:
			# Outward is the parent's own angle: the rest offset already points outward.
			# An aim is a HEADING (clockwise from the hull's forward). The piece's rest offsets already
			# point along its slot's outward heading, so it turns by the difference.
			var aim: float = pose.aim_angle[i]
			turn = pose.angle[parent] if is_nan(aim) else aim - rig.rest_heading[i]
		var offset: Vector2 = rig.rest[i] - rig.rest[parent]
		if rig.pump_amp[i] != 0.0: offset *= 1.0 + rig.pump_amp[i] * sin(rig.pump_freq[i] * t + rig.pump_phase[i])
		pose.local[i] = pose.local[parent] + (offset.rotated(turn) if turn != 0.0 else offset)
		pose.angle[i] = turn
		pose.scale[i] = 1.0
		pose.flare[i] = 0.0
	# Only the two explicitly authored, non-solid reference lobes turn with the tail's
	# shoulder. Custom circles and the actor's aiming direction are untouched.
	if not rig.follow_head_lobes.is_empty() and not pose.chain_current.is_empty():
		var first: int = rig.follow_indices[0]
		if attached.is_empty() or attached[first] != 0:
			var authored: Vector2 = rig.rest[first] - rig.rest[rig.parent_index[first]]
			var turn: float = (pose.chain_current[0] - head).angle() - basis - authored.angle()
			for index: int in rig.follow_head_lobes:
				pose.local[index] = pose.local[0] + (rig.rest[index] - rig.rest[0]).rotated(turn)
				pose.angle[index] = turn

## v0.3 hulls, unchanged. Deleted with the legacy roster (S12).
static func _step_legacy(rig: ShipRig, pose: ShipPose, tick: int) -> void:
	var t: float = float(tick) / 60.0
	for i: int in range(rig.rest.size()):
		var group_slot: int = rig.group_index[i]
		if group_slot < 0:
			pose.local[i] = rig.rest[i]
			pose.scale[i] = 1.0
			pose.flare[i] = 0.0
			continue
		var group: GroupDefinition = rig.groups[group_slot]
		var root_index: int = rig.group_root_index[group_slot]
		# The whole subtree (including its own root) swings around the point
		# where the root attaches to its parent, like an arm around a
		# shoulder - not around the root's own rest position, which would
		# leave a root with no children motionless.
		var pivot_index: int = rig.parent_index[root_index]
		var center: Vector2 = rig.rest[pivot_index] if pivot_index >= 0 else rig.rest[root_index]
		var rel: Vector2 = rig.rest[i] - center
		var breathe_scale: float = 1.0
		if group.breathe_amp > 0.0: breathe_scale = 1.0 + group.breathe_amp * 0.5 * (1.0 - cos(t * PI))
		var angle: float = group.orbit_speed * t
		var rotated: Vector2 = rel.rotated(angle) if not rel.is_zero_approx() else rel
		var radial: float = 1.0
		if group.drift_amp > 0.0 and group.drift_freq > 0.0 and rel.length() > 0.001:
			radial += group.drift_amp * sin(t * group.drift_freq * TAU) / rel.length()
		var offset: Vector2 = rotated * radial * breathe_scale
		if group.chain_mode in ["sway", "whip"] and rel.length() > 0.001:
			var fraction: float = rig.chain_position[i]
			var amplitude: float = maxf(group.orbit_radius, rig.radius[i] * 4.0) * 0.15 * fraction * (2.0 if group.chain_mode == "whip" else 1.0)
			var sway: float = amplitude * sin(t * TAU * 0.75 - fraction * 2.4)
			var tangent: Vector2 = rel.orthogonal().normalized()
			offset += tangent * sway
		pose.local[i] = center + offset
		pose.scale[i] = breathe_scale
		pose.flare[i] = 0.0

## Same lerp the sim and the CPU reshape tween must agree on.
static func reshape_local(before: Vector2, after: Vector2, amount: float) -> Vector2:
	return before.lerp(after, amount)

static func reshape_radius(before: float, after: float, amount: float) -> float:
	return lerpf(before, after, amount)
