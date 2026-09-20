class_name ShipMesh
extends RefCounted
## One painter-ordered surface: dark fills, constant-width outline ribbons, core.
## CUSTOM0 holds the ribbon normal, stable part index and primitive kind.
## CUSTOM1 holds the running-light color and optional tether endpoint indices.

const MAX_PARTS: int = ShipCatalog.MAX_PARTS
var vertices: PackedVector2Array = []
var colors: PackedColorArray = []
var uvs: PackedVector2Array = []
var custom0: PackedFloat32Array = []
var custom1: PackedFloat32Array = []
var indices: PackedInt32Array = []
var centers: PackedVector2Array = []
var parameters: PackedVector4Array = []
var geometries: PackedVector4Array = []
var part_indices: Dictionary = {}

const MAX_CACHE_ENTRIES: int = 96
const MAX_CACHE_BYTES: int = 32 * 1024 * 1024
static var _cache: Dictionary = {}
static var _cache_bytes: int = 0
static var _cache_clock: int = 0
static var cache_hits: int = 0
static var cache_misses: int = 0

static func clear_cache() -> void:
	# Live renderers retain their own reference to any evicted immutable mesh.
	_cache.clear()
	_cache_bytes = 0
	_cache_clock = 0
	cache_hits = 0
	cache_misses = 0

static func cache_stats() -> Dictionary:
	return {"entries": _cache.size(), "estimated_bytes": _cache_bytes, "hits": cache_hits, "misses": cache_misses}

static func geometry_key(ship: ShipDefinition) -> PackedByteArray:
	# Exact serialized values avoid hash-collision reuse and stale edited drafts.
	# Gameplay-only stats and hull occlusion radius are not baked into this mesh.
	var signature: Array = [ship.is_player, ship.element, ship.core_radius]
	for part: PartDefinition in ship.parts:
		# parent_id affects only the authoring graph, never geometry; excluded deliberately.
		signature.append([part.id, part.shape, part.position, part.radius, part.filled, part.color_role, part.layer, part.light_period, part.light_phase, part.from_id, part.to_id, part.dashed])
	return var_to_bytes(signature)

func build(ship: ShipDefinition) -> ArrayMesh:
	var key: PackedByteArray = geometry_key(ship)
	_cache_clock += 1
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		entry.used = _cache_clock
		cache_hits += 1
		centers = entry.centers.duplicate()
		parameters = entry.parameters.duplicate()
		geometries = entry.geometries.duplicate()
		part_indices = entry.part_indices.duplicate()
		_clear_geometry_buffers()
		return entry.mesh
	cache_misses += 1
	var mesh: ArrayMesh = _build_geometry(ship)
	# Account for both CPU mesh arrays and their approximate GPU copies, plus
	# the cache key and the small per-part metadata. The entry cap is separate.
	var estimated: int = vertices.size() * 128 + indices.size() * 8 + MAX_PARTS * 48 + key.size()
	if estimated <= MAX_CACHE_BYTES:
		while not _cache.is_empty() and (_cache.size() >= MAX_CACHE_ENTRIES or _cache_bytes + estimated > MAX_CACHE_BYTES):
			var oldest_key: PackedByteArray = _cache.keys()[0]
			for candidate: PackedByteArray in _cache:
				if int(_cache[candidate].used) < int(_cache[oldest_key].used): oldest_key = candidate
			_cache_bytes -= int(_cache[oldest_key].bytes)
			_cache.erase(oldest_key)
		_cache[key] = {"mesh": mesh, "centers": centers.duplicate(), "parameters": parameters.duplicate(), "geometries": geometries.duplicate(), "part_indices": part_indices.duplicate(), "used": _cache_clock, "bytes": estimated}
		_cache_bytes += estimated
	_clear_geometry_buffers()
	return mesh

func _clear_geometry_buffers() -> void:
	vertices = PackedVector2Array()
	colors = PackedColorArray()
	uvs = PackedVector2Array()
	custom0 = PackedFloat32Array()
	custom1 = PackedFloat32Array()
	indices = PackedInt32Array()

func _build_geometry(ship: ShipDefinition) -> ArrayMesh:
	_clear_geometry_buffers()
	part_indices = {}
	var parts: Array[PartDefinition] = ship.parts.duplicate()
	parts.sort_custom(func(a: PartDefinition, b: PartDefinition) -> bool: return a.layer < b.layer)
	centers.resize(MAX_PARTS)
	parameters.resize(MAX_PARTS)
	geometries.resize(MAX_PARTS)
	assert(parts.size() <= MAX_PARTS, "Ship exceeds the supported 128 authored parts")
	for i: int in range(parts.size()):
		part_indices[parts[i].id] = i
		centers[i] = parts[i].position
		geometries[i] = Vector4(parts[i].radius, parts[i].radius, 0, 0)
	for i: int in range(parts.size()):
		var part: PartDefinition = parts[i]
		var points: PackedVector2Array = []
		var endpoints: float = -1.0
		if part.shape == "line":
			if not part_indices.has(part.from_id) or not part_indices.has(part.to_id): continue
			var from_index: int = part_indices[part.from_id]
			var to_index: int = part_indices[part.to_id]
			points = PackedVector2Array([centers[from_index], centers[to_index]])
			endpoints = float(from_index + to_index * MAX_PARTS)
		else:
			for point: Vector2 in ShipGeometry.outline(part.shape, part.radius):
				points.append(point + part.position)
		if points.size() < 2: continue
		var distances: PackedFloat32Array = ShipGeometry.lengths(points)
		var role: String = part.color_role
		if role == "chassis": role = "player" if ship.is_player else ship.element
		var stroke: Color = ShipCatalog.get_color(role)
		var fill: Color = ShipCatalog.FILLS.get(role, Color("062a12"))
		if ship.element == "void": fill = Color.BLACK
		var light: Color = ShipCatalog.LIGHTS.get(role, Color.WHITE)
		# Custom attributes do not receive Godot's automatic sRGB conversion.
		light = light.srgb_to_linear() * 1.8
		var style: float = 2.0 if part.shape == "line" else (1.0 if part.dashed or part.layer == 0 else 3.0 if not part.filled else 0.0)
		parameters[i] = Vector4(maxf(0.05, part.light_period), part.light_phase, distances[-1], style)
		if part.layer != 0 and part.shape == "circle" and part.filled:
			_append_fill(points, fill, i)
		_append_outline(points, distances, stroke, light, i, endpoints)
	_append_core(ship.core_radius)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags: int = Mesh.ARRAY_FLAG_USE_2D_VERTICES | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	# Breathing, editor zoom and orbit offsets happen on the GPU. Do not cull the
	# original authored AABB when a satellite or selection preview moves outside it.
	mesh.custom_aabb = AABB(Vector3(-2048, -2048, -1), Vector3(4096, 4096, 2))
	return mesh

func _vertex(point: Vector2, color: Color, uv: Vector2, normal: Vector2, part: int, kind: float, light: Color = Color.WHITE, endpoints: float = -1.0) -> void:
	vertices.append(point)
	colors.append(color)
	uvs.append(uv)
	custom0.append_array(PackedFloat32Array([normal.x, normal.y, float(part), kind]))
	custom1.append_array(PackedFloat32Array([light.r, light.g, light.b, endpoints]))

func _append_fill(points: PackedVector2Array, color: Color, part: int) -> void:
	var polygon: PackedVector2Array = points.duplicate()
	if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[-1]): polygon.remove_at(polygon.size() - 1)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var base: int = vertices.size()
	for point: Vector2 in polygon: _vertex(point, color, Vector2.ZERO, Vector2.ZERO, part, -1.0)
	for index: int in triangles: indices.append(base + index)

func _append_outline(points: PackedVector2Array, distances: PackedFloat32Array, color: Color, light: Color, part: int, endpoints: float) -> void:
	var base: int = vertices.size()
	var closed: bool = points[0].is_equal_approx(points[-1])
	var last: int = points.size() - 1
	for i: int in range(points.size()):
		var before: Vector2 = points[maxi(0, i - 1)]
		var after: Vector2 = points[mini(last, i + 1)]
		if closed and (i == 0 or i == last):
			before = points[last - 1]
			after = points[1]
		var incoming: Vector2 = (points[i] - before).normalized()
		var outgoing: Vector2 = (after - points[i]).normalized()
		if incoming.is_zero_approx(): incoming = outgoing
		if outgoing.is_zero_approx(): outgoing = incoming
		var normal_in: Vector2 = Vector2(-incoming.y, incoming.x)
		var normal_out: Vector2 = Vector2(-outgoing.y, outgoing.x)
		var bisector: Vector2 = (normal_in + normal_out).normalized()
		if bisector.is_zero_approx(): bisector = normal_out
		var miter: Vector2 = bisector / maxf(0.25, absf(bisector.dot(normal_out)))
		for side: float in [-1.0, 1.0]:
			_vertex(points[i], color, Vector2(distances[i], side), miter * side, part, 1.0 if endpoints >= 0 else 0.0, light, endpoints)
	for i: int in range(last):
		var start: int = base + i * 2
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2]))

func _append_core(radius: float) -> void:
	var base: int = vertices.size()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_vertex(corner * (radius + 0.75), Color.WHITE, corner, Vector2.ZERO, 0, -2.0)
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))



