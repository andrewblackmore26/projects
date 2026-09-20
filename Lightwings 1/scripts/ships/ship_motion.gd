class_name ShipMotion
extends RefCounted
## The single source of where a circle is. `ShipRig` is the immutable, cached
## shape of a hull's motion (built once per `ShipDefinition`); `ShipPose` is
## the small per-instance state `step()` writes in place from the simulation's
## integer tick. Both the renderer and the simulation (muzzles, gun colliders,
## the bullet-eater mouth) must read the same pose or aiming stops feeling
## honest (spec §18).

const MAX_CACHE_ENTRIES: int = 96
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
	var groups: Array[GroupDefinition] = []
	var id_index: Dictionary = {}

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

	func _init(rig: ShipRig = null) -> void:
		if rig != null: reset(rig)

	func reset(rig: ShipRig) -> void:
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
	for part: PartDefinition in ship.parts:
		if part.shape == "circle": signature.append([part.id, part.position, part.radius, part.filled, part.parent_id])
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
	for i: int in range(order.size()): rig.id_index[order[i]] = i
	for i: int in range(order.size()):
		var part: PartDefinition = by_id[order[i]]
		rig.rest[i] = part.position
		rig.radius[i] = part.radius
		rig.parent_index[i] = rig.id_index.get(part.parent_id, -1) if part.id != "core" else -1
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
	return rig

## Writes `pose` in place. Allocates nothing (Vector2/float are value types).
## `tick` is the simulation's integer tick (never a wall clock) so replays and
## the paused-vs-running renderer cannot disagree with the sim.
static func step(rig: ShipRig, pose: ShipPose, tick: int) -> void:
	if pose.local.size() != rig.rest.size(): pose.reset(rig)
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
