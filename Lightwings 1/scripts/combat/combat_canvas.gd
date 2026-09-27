extends Node2D

const Pool = preload("res://scripts/combat/bullet_pool.gd")
const ProjectileShader = preload("res://scripts/combat/projectile_instances.gdshader")
const TrailShader = preload("res://scripts/combat/projectile_trails.gdshader")
const STRIDE: int = 16 # 2D transform (8), instance color (4), custom data (4).
const INITIAL_CAPACITY: int = 256
const PLAYER_COLOR: Color = Elements.PLAYER_RIM
const COLORS: Array[Color] = Elements.RIM_BY_INDEX

var world: Node2D
var player_mesh: MultiMeshInstance2D
var enemy_mesh: MultiMeshInstance2D
var player_buffer: PackedFloat32Array = PackedFloat32Array()
var enemy_buffer: PackedFloat32Array = PackedFloat32Array()
var player_capacity: int = INITIAL_CAPACITY
var enemy_capacity: int = INITIAL_CAPACITY
var player_count: int = 0
var enemy_count: int = 0
var upload_ms: float = 0.0
var trail_mesh: MultiMeshInstance2D
var trail_buffer: PackedFloat32Array = PackedFloat32Array()
var trail_capacity: int = INITIAL_CAPACITY
var history_texture: ImageTexture

func _ready() -> void:
	_ensure_meshes()

func _ensure_meshes() -> void:
	if is_instance_valid(player_mesh):
		return
	player_mesh = _make_pass("PlayerProjectiles", -2)
	enemy_mesh = _make_pass("EnemyProjectiles", -1)
	player_buffer.resize(player_capacity * STRIDE)
	enemy_buffer.resize(enemy_capacity * STRIDE)
	_make_trails()

func _make_trails() -> void:
	trail_mesh = _make_pass("ProjectileRibbons", -3)
	var vertices: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(Pool.HISTORY_POINTS):
		vertices.append(Vector3(float(i), -1, 0))
		vertices.append(Vector3(float(i), 1, 0))
		uv.append(Vector2(float(i), -1))
		uv.append(Vector2(float(i), 1))
		if i < Pool.HISTORY_POINTS - 1:
			var n: int = i * 2
			indices.append_array(PackedInt32Array([n, n + 1, n + 2, n + 1, n + 3, n + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var strip: ArrayMesh = ArrayMesh.new()
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	trail_mesh.multimesh.mesh = strip
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TrailShader
	trail_mesh.material = material
	_prepare_trail_instances()

func _prepare_trail_instances() -> void:
	trail_buffer.resize(trail_capacity * STRIDE)
	for index: int in range(trail_capacity):
		_write_instance(trail_buffer, index * STRIDE, Vector2.ZERO, Vector2.RIGHT, 1, 1, Color.WHITE, 1, float(index), 0, 0, 0)
	trail_mesh.multimesh.instance_count = trail_capacity
	trail_mesh.multimesh.buffer = trail_buffer

func _sync_trails(pool: LightBulletPool) -> void:
	if pool.count() == 0:
		trail_mesh.multimesh.visible_instance_count = 0
		return
	var needed: int = pool.next_unused
	if needed > trail_capacity:
		while needed > trail_capacity: trail_capacity *= 2
		_prepare_trail_instances()
	var image: Image = Image.create_from_data(Pool.HISTORY_STRIDE, Pool.CAPACITY, false, Image.FORMAT_RGF, pool.history.to_byte_array())
	if history_texture == null:
		history_texture = ImageTexture.create_from_image(image)
		(trail_mesh.material as ShaderMaterial).set_shader_parameter("history_texture", history_texture)
	else: history_texture.update(image)
	# Holes in the pool have a zero sample count; the shader collapses them.
	# Slot identities and transforms remain fixed, including after reuse.
	trail_mesh.multimesh.visible_instance_count = needed

func _make_pass(label: String, order: int) -> MultiMeshInstance2D:
	var instance: MultiMeshInstance2D = MultiMeshInstance2D.new()
	instance.name = label
	instance.z_index = order
	var geometry: QuadMesh = QuadMesh.new()
	geometry.size = Vector2(2, 2)
	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = geometry
	batch.instance_count = INITIAL_CAPACITY
	batch.visible_instance_count = 0
	# Fixed, generous AABB: a MultiMeshInstance2D caches its culling rect from the
	# instances present at its first draw, and in live play that first frame is empty.
	# Circular arena centre (896,560) radius 800, plus the black-hole special_radius
	# reach of 171 and slack on every side, sits well inside this box.
	batch.custom_aabb = AABB(Vector3(-400, -800, -1), Vector3(2600, 2800, 2))
	instance.multimesh = batch
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ProjectileShader
	instance.material = material
	add_child(instance)
	return instance

func sync_pool(pool: LightBulletPool) -> void:
	var began: int = Time.get_ticks_usec()
	_ensure_meshes()
	_sync_trails(pool)
	var shot_positions: PackedVector2Array = pool.positions
	var shot_velocities: PackedVector2Array = pool.velocities
	var shot_radii: PackedFloat32Array = pool.radii
	var shot_visual_radii: PackedFloat32Array = pool.visual_radii
	var shot_ages: PackedFloat32Array = pool.ages
	var shot_factions: PackedInt32Array = pool.factions
	var shot_elements: PackedInt32Array = pool.elements
	var shot_flags: PackedInt32Array = pool.flags
	var shot_active_indices: Array[int] = pool.active_indices
	player_count = 0
	enemy_count = 0
	for index: int in shot_active_indices:
		if shot_factions[index] == 0:
			player_count += 1
		else:
			enemy_count += 1
	if player_count > player_capacity:
		while player_count > player_capacity:
			player_capacity *= 2
		player_buffer.resize(player_capacity * STRIDE)
		player_mesh.multimesh.instance_count = player_capacity
	if enemy_count > enemy_capacity:
		while enemy_count > enemy_capacity:
			enemy_capacity *= 2
		enemy_buffer.resize(enemy_capacity * STRIDE)
		enemy_mesh.multimesh.instance_count = enemy_capacity
	var player_cursor: int = 0
	var enemy_cursor: int = 0
	for index: int in shot_active_indices:
		var friendly: bool = shot_factions[index] == 0
		var pos: Vector2 = shot_positions[index]
		# Visual radius only (spec §19 per-weapon size); the COLLISION radius
		# (`shot_radii`, used below for the mine's blast extent) is untouched.
		var radius: float = shot_visual_radii[index]
		var flags: int = shot_flags[index]
		var color: Color = Pool.projectile_color(flags)
		var velocity: Vector2 = shot_velocities[index]
		var direction: Vector2 = velocity.normalized() if velocity.length_squared() > 0.001 else Vector2.RIGHT
		var straight: float = radius
		var kind: float = 0.0
		var extent_x: float = radius + 2.0
		var extent_y: float = extent_x
		var special_radius: float = 0.0
		var reach: float = shot_ages[index]
		# Type hue is identical across factions. The shader adds a small blue
		# centre pip for friendly shots; saturation is never used as a bloom multiplier.
		var brightness: float = 1.0
		if (flags & Pool.BLACK_HOLE) != 0:
			kind = 1.0
			special_radius = 13.0
			straight = 13.0
			extent_x = 171.0
			extent_y = 171.0
			direction = Vector2.RIGHT
			color = Color("ff5436")
		elif (flags & Pool.MINE) != 0:
			straight = shot_radii[index]
			extent_x = shot_radii[index] + 2.0
			extent_y = extent_x
			color = COLORS[clampi(shot_elements[index], 0, 4)]
		elif (flags & Pool.ROCKET) != 0:
			# Inner ring and rotating diameter use the bullet's simulation age.
			kind = 2.0
			special_radius = radius
			reach = shot_ages[index]
		elif (flags & Pool.HOMING) != 0:
			# The halo is OUTSIDE the reference's small radius-4.5 seeker body.
			kind = 3.0
			special_radius = radius
			reach = shot_ages[index]
			extent_x = radius + 5.2
			extent_y = extent_x
		elif (flags & Pool.RICOCHET) != 0: kind = 4.0
		special_radius = extent_x
		if friendly: kind += 8.0
		var offset: int = (player_cursor if friendly else enemy_cursor) * STRIDE
		# MultiMesh buffer rows: [xx,yx,0,ox] and [xy,yy,0,oy].
		if friendly:
			_write_instance(player_buffer, offset, pos, direction, extent_x, extent_y, color, brightness, straight, kind, special_radius, reach)
			player_cursor += 1
		else:
			_write_instance(enemy_buffer, offset, pos, direction, extent_x, extent_y, color, brightness, straight, kind, special_radius, reach)
			enemy_cursor += 1
	if player_count > 0:
		player_mesh.multimesh.buffer = player_buffer
	if enemy_count > 0:
		enemy_mesh.multimesh.buffer = enemy_buffer
	player_mesh.multimesh.visible_instance_count = player_count
	enemy_mesh.multimesh.visible_instance_count = enemy_count
	upload_ms = float(Time.get_ticks_usec() - began) / 1000.0

func _write_instance(buffer: PackedFloat32Array, offset: int, pos: Vector2, direction: Vector2, width: float, height: float, color: Color, brightness: float, straight: float, kind: float, special_radius: float, reach: float) -> void:
	buffer[offset] = direction.x * width
	buffer[offset + 1] = -direction.y * height
	buffer[offset + 2] = 0.0
	buffer[offset + 3] = pos.x
	buffer[offset + 4] = direction.y * width
	buffer[offset + 5] = direction.x * height
	buffer[offset + 6] = 0.0
	buffer[offset + 7] = pos.y
	buffer[offset + 8] = color.r * brightness
	buffer[offset + 9] = color.g * brightness
	buffer[offset + 10] = color.b * brightness
	buffer[offset + 11] = 1.0
	buffer[offset + 12] = straight
	buffer[offset + 13] = kind
	buffer[offset + 14] = special_radius
	buffer[offset + 15] = reach

func clear_instances() -> void:
	player_count = 0
	enemy_count = 0
	if is_instance_valid(player_mesh):
		player_mesh.multimesh.visible_instance_count = 0
		enemy_mesh.multimesh.visible_instance_count = 0
		trail_mesh.multimesh.visible_instance_count = 0

func _draw() -> void:
	if is_instance_valid(world):
		world.draw_projectiles(self)

static func point_along(points: PackedVector2Array, fraction: float) -> Vector2:
	if points.is_empty(): return Vector2.ZERO
	var total: float = 0.0
	for i: int in range(1, points.size()): total += points[i - 1].distance_to(points[i])
	var distance: float = clampf(fraction, 0.0, 1.0) * total
	for i: int in range(1, points.size()):
		var length: float = points[i - 1].distance_to(points[i])
		if distance <= length and length > 0.0001: return points[i - 1].lerp(points[i], distance / length)
		distance -= length
	return points[-1]

static func draw_beam(canvas: CanvasItem, points: PackedVector2Array, age: float, friendly: bool) -> void:
	if points.size() < 2: return
	var intensity: float = 0.55 + absf(sin(age * 9.0)) * 0.45
	canvas.draw_polyline(points, Color(Pool.BEAM_COLOR, intensity * 0.3), 6.0 + sin(age * 11.0) * 2.5, true)
	canvas.draw_polyline(points, Color(Pool.BEAM_LIGHT, intensity), 2.4, true)
	for i: int in range(4):
		canvas.draw_circle(point_along(points, fposmod(age * 0.85 + float(i) * 0.25, 1.0)), 3.2, Color(Pool.BEAM_LIGHT, 0.95), true, -1, true)
	if friendly: canvas.draw_arc(points[0], 5.0, 0, TAU, 20, Pool.PULSE_COLOR, 1.5, true)

