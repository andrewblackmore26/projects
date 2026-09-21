extends Node2D

const Pool = preload("res://scripts/combat/bullet_pool.gd")
const ProjectileShader = preload("res://scripts/combat/projectile_instances.gdshader")
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

func _ready() -> void:
	_ensure_meshes()

func _ensure_meshes() -> void:
	if is_instance_valid(player_mesh):
		return
	player_mesh = _make_pass("PlayerProjectiles", -2)
	enemy_mesh = _make_pass("EnemyProjectiles", -1)
	player_buffer.resize(player_capacity * STRIDE)
	enemy_buffer.resize(enemy_capacity * STRIDE)

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
		var color: Color = PLAYER_COLOR if friendly else COLORS[clampi(shot_elements[index], 0, 4)]
		var velocity: Vector2 = shot_velocities[index]
		var direction: Vector2 = velocity.normalized() if velocity.length_squared() > 0.001 else Vector2.RIGHT
		var straight: float = 2.0 if (flags & Pool.PIERCING) != 0 else 0.65
		var kind: float = 0.0
		var extent_x: float = radius * (1.0 + straight)
		var extent_y: float = radius
		var special_radius: float = 0.0
		var reach: float = 0.0
		# Finding 1 (tasks/todo.md P8): every projectile used to draw at a flat
		# 1.8x emission regardless of element, so plasma violet (base blue
		# channel already at 1.0) clipped/bloomed toward pale blue-white,
		# visually colliding with pillar 5's "light blue is the player, no
		# other ship/pickup/projectile uses it". 1.4 still clears the HDR glow
		# threshold (1.0, spec §23) without pushing every channel into clip.
		var brightness: float = 1.4
		if (flags & Pool.BLACK_HOLE) != 0:
			kind = 1.0
			special_radius = 13.0
			reach = 171.0
			extent_x = reach
			extent_y = reach
			direction = Vector2.RIGHT
			color = PLAYER_COLOR if friendly else Color("ff5436")
		elif (flags & Pool.MINE) != 0:
			straight = 0.0
			extent_x = shot_radii[index]
			extent_y = shot_radii[index]
			brightness = 1.5
		elif (flags & Pool.ROCKET) != 0 and radius > 6.5:
			# Interior (spec §19 table): "rotating inner ring and spoke", driven
			# by the bullet's own AGE (never a wall clock) so it is identical
			# across simulation and render, and freezes exactly when the sim does.
			kind = 2.0
			special_radius = radius
			reach = shot_ages[index]
		elif (flags & Pool.HOMING) != 0 and radius > 6.5:
			# Interior: "pulsing halo ring" (seeker).
			kind = 3.0
			special_radius = radius
			reach = shot_ages[index]
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

func _draw() -> void:
	if is_instance_valid(world):
		world.draw_projectiles(self)

