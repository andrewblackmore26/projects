class_name ShipRenderer
extends Node2D
## Shared game/editor renderer. One cached mesh draws every fill, perimeter
## running light and core. CPU contours are used only during 0.8-second reshapes.
## Native HDR post-processing supplies bloom; no gameplay logic runs here.

var definition: ShipDefinition
var animation_time: float = 0.0
var reshape_remaining: float = 0.0
var visual_scale: float = 1.0
var draw_hull: bool = true
var hull_only: bool = false
var show_core: bool = true
var evolution_ready: bool = false
var part_position_overrides: Dictionary = {}
var hidden_part_ids: PackedStringArray = []
var rig: ShipMotion.ShipRig
var pose: ShipMotion.ShipPose
## P8 target feedback: the sim's own decaying per-circle flare (index-aligned
## with `rig`), pushed in every tick by `CombatWorld._step_motion` since this
## renderer keeps its OWN `pose` (built fresh in `set_ship`) and
## `ShipMotion.step` always zeroes `pose.flare` (see ship_motion.gd). Empty
## for anything the sim does not drive (editor previews, menus) - `_sync_part_offsets`
## falls back to `pose.flare` (always 0.0) when the size does not match.
var part_flare: PackedFloat32Array = PackedFloat32Array()
## The simulation's own pose for this hull, when there is a simulation (CombatWorld hands it over
## every tick). While it fits the rig the renderer draws from it and does not evaluate motion
## itself, so the pixels ARE the hitboxes and each hull is posed once per tick, not twice. This
## renderer only ever reads it. Null for previews, menus and the editor, which keep `pose`.
var external_pose: ShipMotion.ShipPose
var motion_tick: int = 0
var _tick_driven: bool = false
var _pose_hash: int = -2
var _pose_source: int = -1
var _flare_hash: int = -2
var _source: ShipDefinition
var _contours: Dictionary = {}
var _draw_cache: Dictionary = {}
var _display_parts: Array[PartDefinition] = []
var _phase: float = 0.0
var _old_hull: float = 0.0
var _mesh_instance: MeshInstance2D
var _mesh_material: ShaderMaterial
var _mesh_builder: ShipMesh
var _mesh_offsets: PackedVector4Array = []
var _rig_to_mesh: PackedInt32Array = PackedInt32Array()
var _override_hash: int = -1
var _hidden_hash: int = -1
var _last_factor: float = -1.0
var _last_canvas_scale: float = -1.0
var _last_hull_only: bool = false
var _last_draw_hull: bool = true
var _last_show_core: bool = true
var _last_evolution_ready: bool = false
var last_draw_usec: int = 0
static var frame_draw_usec: int = 0
static var frame_draw_calls: int = 0
static var _measured_frame: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_phase = float(get_instance_id() % 1000) / 170.0

func set_ship(ship: ShipDefinition, animate: bool = false) -> void:
	_source = definition
	_old_hull = definition.hull_radius if definition != null else 0.0
	definition = ship
	reshape_remaining = GameTuning.RESHAPE_SECONDS if animate and _source != null else 0.0
	_contours.clear()
	_draw_cache.clear()
	_display_parts.clear()
	rig = ShipMotion.get_rig(definition) if definition != null else null
	pose = ShipMotion.ShipPose.new(rig) if rig != null else null
	external_pose = null # the old hull's; the simulation hands the new one over on its next tick
	_rig_to_mesh = PackedInt32Array() # rebuilt after the mesh is, on the first sync
	_pose_hash = -2
	_flare_hash = -2
	if definition != null:
		for part: PartDefinition in definition.parts:
			_display_parts.append(part)
	if reshape_remaining > 0:
		for old: PartDefinition in _source.parts:
			if _find(definition, old.id) == null:
				_display_parts.append(old)
	_display_parts.sort_custom(func(a: PartDefinition, b: PartDefinition) -> bool: return a.layer < b.layer)
	_build_mesh()
	queue_redraw()

func _process(delta: float) -> void:
	animation_time += delta
	var frame: int = Engine.get_frames_drawn()
	if _measured_frame != frame:
		_measured_frame = frame
		frame_draw_usec = 0
		frame_draw_calls = 0
	if reshape_remaining > 0:
		reshape_remaining = maxf(0, reshape_remaining - delta)
		if reshape_remaining == 0 and definition != null:
			_display_parts.assign(definition.parts)
			_display_parts.sort_custom(func(a: PartDefinition, b: PartDefinition) -> bool: return a.layer < b.layer)
			_contours.clear()
			_draw_cache.clear()
		queue_redraw()
	if not is_visible_in_tree() or definition == null: return
	var canvas_scale: float = maxf(0.01, get_global_transform_with_canvas().get_scale().abs().x)
	var factor: float = _body_scale()
	if _last_factor != factor or _last_canvas_scale != canvas_scale or _last_hull_only != hull_only or _last_draw_hull != draw_hull:
		if (definition.hull_radius > 0 and draw_hull) or _last_draw_hull != draw_hull or _last_hull_only != hull_only: queue_redraw()
		if _mesh_material != null:
			_mesh_material.set_shader_parameter("body_scale", factor)
			_mesh_material.set_shader_parameter("canvas_scale", canvas_scale)
		_last_factor = factor
		_last_canvas_scale = canvas_scale
		_last_hull_only = hull_only
		_last_draw_hull = draw_hull
	if _mesh_instance != null:
		_mesh_instance.visible = not hull_only and reshape_remaining <= 0
		if _mesh_instance.visible:
			_mesh_material.set_shader_parameter("visual_time", animation_time)
			if _last_show_core != show_core:
				_mesh_material.set_shader_parameter("show_core", show_core)
				_last_show_core = show_core
			if _last_evolution_ready != evolution_ready:
				_mesh_material.set_shader_parameter("evolution_ready", evolution_ready)
				_last_evolution_ready = evolution_ready
			if pose != null:
				# Geometry motion always comes from an integer tick, never a wall
				# clock. Owners with a real sim (CombatWorld) drive `motion_tick`
				# every physics frame via `set_motion_tick`, so it freezes exactly
				# when the sim pauses; standalone previews (editor, menus) fall
				# back to the renderer's own always-on clock.
				if not _tick_driven: motion_tick = int(animation_time * 60.0)
				if not _uses_external_pose(): ShipMotion.step(rig, pose, motion_tick)
			_sync_part_offsets()

func set_motion_tick(tick: int) -> void:
	motion_tick = tick
	_tick_driven = true

## Rig index -> mesh uniform slot (-1 when the mesh has no such circle), built once per hull. The
## per-frame loop used to look each circle's id string up in a Dictionary instead.
func _map_rig_to_mesh() -> void:
	_rig_to_mesh.resize(rig.ids.size())
	for i: int in range(rig.ids.size()):
		_rig_to_mesh[i] = int(_mesh_builder.part_indices.get(rig.ids[i], -1))

func _uses_external_pose() -> bool:
	return external_pose != null and rig != null and external_pose.local.size() == rig.rest.size()

## The pose to draw from: the simulation's when it gave one that fits this rig, else our own.
func _drawn_pose() -> ShipMotion.ShipPose:
	return external_pose if _uses_external_pose() else pose

func _body_scale() -> float:
	# Whole-hull breathing is gone: a group's breathe_amp scales only its own
	# subtree, through the pose, not the entire ship uniformly (spec §18).
	return visual_scale

func _build_mesh() -> void:
	if definition == null or hull_only:
		if _mesh_instance != null: _mesh_instance.visible = false
		return
	if _mesh_instance == null:
		_mesh_instance = MeshInstance2D.new()
		_mesh_instance.name = "ShipSurface"
		_mesh_material = ShaderMaterial.new()
		_mesh_material.shader = preload("res://shaders/ship_outline.gdshader")
		_mesh_instance.material = _mesh_material
		add_child(_mesh_instance)
	_mesh_builder = ShipMesh.new()
	_mesh_instance.mesh = _mesh_builder.build(definition)
	_mesh_instance.visible = reshape_remaining <= 0
	_mesh_material.set_shader_parameter("light_parameters", _mesh_builder.parameters)
	_mesh_material.set_shader_parameter("part_centers", _mesh_builder.centers)
	_mesh_material.set_shader_parameter("part_geometry", _mesh_builder.geometries)
	_mesh_material.set_shader_parameter("motion_signature", ["smooth", "flicker", "snap", "counter_rotate"].find(definition.motion_signature))
	var dot: Color = Color.WHITE if definition.is_player else ShipCatalog.get_color(definition.element)
	# Rail hull (spec §4.1): the enemy's dot is its accent, or its chassis when it has none.
	if definition.is_rail_hull() and not definition.is_player:
		dot = ShipCatalog.get_color(definition.accent_color if definition.accent_color != "" else definition.chassis_color)
	_mesh_material.set_shader_parameter("core_color", dot)
	_mesh_material.set_shader_parameter("core_radius", definition.core_radius)
	_mesh_material.set_shader_parameter("show_core", show_core)
	_mesh_material.set_shader_parameter("evolution_ready", evolution_ready)
	_last_factor = _body_scale()
	_last_canvas_scale = maxf(0.01, get_global_transform_with_canvas().get_scale().abs().x) if is_inside_tree() else 1.0
	_mesh_material.set_shader_parameter("body_scale", _last_factor)
	_mesh_material.set_shader_parameter("canvas_scale", _last_canvas_scale)
	_mesh_material.set_shader_parameter("visual_time", animation_time)
	_override_hash = -1
	_hidden_hash = -1
	_pose_hash = -2
	_flare_hash = -2
	_sync_part_offsets()

func _sync_part_offsets() -> void:
	var overrides: int = hash(part_position_overrides)
	var hidden: int = hash(hidden_part_ids)
	var pose_tick: int = motion_tick if pose != null else -1
	# The rim flare has to be part of this check, not just the pose tick. It rides in the SAME
	# uniform (`part_offsets[i].w`) but it is written by combat's own decay, not by ShipMotion, so a
	# frame where the flare changed while `motion_tick` did not would skip the upload entirely and
	# the hit would be invisible. In play the tick always advances, which is why the flare looked
	# fine; a GPU test that set a flare without advancing the tick measured the rim as unchanged,
	# deterministically, and that is the honest reading of this dependency being wrong.
	var flare_signature: int = hash(part_flare)
	# WHICH pose is drawn is a dependency too (S1): `set_ship` uploads once from our own pose, so a
	# pose handed over at the same tick was skipped and the hull drew at rest. The pixel test caught
	# it; in play the tick advances every frame, which is why it would have hidden for one frame only.
	var drawn_source: int = external_pose.get_instance_id() if _uses_external_pose() else 0
	if overrides == _override_hash and hidden == _hidden_hash and pose_tick == _pose_hash and flare_signature == _flare_hash and drawn_source == _pose_source: return
	_pose_source = drawn_source
	_override_hash = overrides
	_hidden_hash = hidden
	_pose_hash = pose_tick
	_flare_hash = flare_signature
	_mesh_offsets.resize(ShipMesh.MAX_PARTS)
	_mesh_offsets.fill(Vector4(0, 0, 1, 0))
	# Groups move a circle's pose away from its authored rest position; that
	# delta (and any breathing radius scale) is the base offset every circle
	# uploads. Manual overrides (editor drag, CPU reshape) win over it below.
	var drawn: ShipMotion.ShipPose = _drawn_pose()
	if drawn != null and rig != null:
		var flare_source: PackedFloat32Array = part_flare if part_flare.size() == rig.ids.size() else drawn.flare
		if _rig_to_mesh.size() != rig.ids.size(): _map_rig_to_mesh()
		for i: int in range(rig.ids.size()):
			var index: int = _rig_to_mesh[i]
			if index < 0: continue
			var offset: Vector2 = drawn.local[i] - rig.rest[i]
			_mesh_offsets[index] = Vector4(offset.x, offset.y, drawn.scale[i], flare_source[i])
	for id: String in part_position_overrides:
		if _mesh_builder.part_indices.has(id):
			var index: int = _mesh_builder.part_indices[id]
			var offset: Vector2 = Vector2(part_position_overrides[id]) - _mesh_builder.centers[index]
			_mesh_offsets[index] = Vector4(offset.x, offset.y, _mesh_offsets[index].z, _mesh_offsets[index].w)
	for id: String in hidden_part_ids:
		if _mesh_builder.part_indices.has(id):
			var index: int = _mesh_builder.part_indices[id]
			_mesh_offsets[index].z = 0
	_mesh_material.set_shader_parameter("part_offsets", _mesh_offsets)

func _find(ship: ShipDefinition, id: String) -> PartDefinition:
	if ship != null:
		for part: PartDefinition in ship.parts:
			if part.id == id:
				return part
	return null

func _morph(part: PartDefinition) -> Dictionary:
	var pos: Vector2 = part.position
	if part_position_overrides.has(part.id): pos = part_position_overrides[part.id]
	var radius: float = part.radius
	if reshape_remaining > 0:
		var amount: float = smoothstep(0.0, 1.0, 1.0 - reshape_remaining / GameTuning.RESHAPE_SECONDS)
		var before: PartDefinition = _find(_source, part.id)
		var after: PartDefinition = _find(definition, part.id)
		if before != null and after != null:
			pos = ShipMotion.reshape_local(before.position, after.position, amount)
			radius = ShipMotion.reshape_radius(before.radius, after.radius, amount)
		elif after != null:
			pos = ShipMotion.reshape_local(Vector2.ZERO, pos, amount)
			radius = ShipMotion.reshape_radius(0.0, radius, amount)
		else:
			pos = ShipMotion.reshape_local(pos, Vector2.ZERO, amount)
			radius = ShipMotion.reshape_radius(radius, 0.0, amount)
	return {"position": pos, "radius": radius}

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	if definition == null:
		return
	var canvas_scale: float = maxf(0.01, get_global_transform_with_canvas().get_scale().abs().x)
	var factor: float = _body_scale()
	var hull: float = definition.hull_radius
	if reshape_remaining > 0:
		hull = lerpf(_old_hull, hull, smoothstep(0, 1, 1.0 - reshape_remaining / GameTuning.RESHAPE_SECONDS))
	if draw_hull and hull > 0:
		draw_circle(Vector2.ZERO, hull * factor, Color.BLACK, true, -1, true)
	if hull_only:
		_record_draw(started)
		return
	if reshape_remaining <= 0:
		_record_draw(started)
		return
	for part: PartDefinition in _display_parts:
		if part.id in hidden_part_ids: continue
		_draw_part(part, factor, canvas_scale)
	if show_core:
		var core: Color = Color.WHITE if definition.is_player else ShipCatalog.get_color(definition.element)
		var boost: float = 1.8 * (1.0 + 0.1 * (0.5 - 0.5 * cos(animation_time * PI)) if evolution_ready else 1.0)
		core = _emission(core, boost)
		draw_circle(Vector2.ZERO, definition.core_radius / canvas_scale, core, true, -1, true)
	_record_draw(started)

func _record_draw(started: int) -> void:
	last_draw_usec = Time.get_ticks_usec() - started
	var frame: int = Engine.get_frames_drawn()
	if _measured_frame != frame:
		_measured_frame = frame
		frame_draw_usec = 0
		frame_draw_calls = 0
	frame_draw_usec += last_draw_usec
	frame_draw_calls += 1

func _draw_part(part: PartDefinition, factor: float, canvas_scale: float) -> void:
	var points: PackedVector2Array
	var distances: PackedFloat32Array
	var stable: bool = reshape_remaining <= 0 and part.shape != "line" and not part_position_overrides.has(part.id)
	var cached: Dictionary = _draw_cache.get(part.id, {}) if stable else {}
	if not cached.is_empty() and is_equal_approx(float(cached.factor), factor):
		points = cached.points
		distances = cached.distances
	elif part.shape == "line":
		var from: PartDefinition = _find(definition, part.from_id)
		var to: PartDefinition = _find(definition, part.to_id)
		if from == null: from = _find(_source, part.from_id)
		if to == null: to = _find(_source, part.to_id)
		if from == null or to == null: return
		var from_data: Dictionary = _morph(from)
		var to_data: Dictionary = _morph(to)
		points = ShipGeometry.clipped_line(from_data, to_data)
		for index: int in range(points.size()): points[index] *= factor
	else:
		var radius: float = part.radius
		var pos: Vector2 = part_position_overrides.get(part.id, part.position)
		if reshape_remaining > 0:
			var data: Dictionary = _morph(part)
			radius = data["radius"]
			pos = data["position"]
		var key: String = part.id
		if reshape_remaining <= 0 and _contours.has(key):
			points = _contours[key]
		else:
			points = ShipGeometry.outline(part.shape, radius)
			if reshape_remaining <= 0: _contours[key] = points
		var transformed: PackedVector2Array = []
		for point: Vector2 in points:
			transformed.append((point + pos) * factor)
		points = transformed
	if points.size() < 2:
		return
	if distances.is_empty():
		distances = ShipGeometry.lengths(points)
		if stable: _draw_cache[part.id] = {"factor": factor, "points": points, "distances": distances}
	var role: String = part.color_role
	if role == "chassis": role = "player" if definition.is_player else definition.element
	var stroke: Color = ShipCatalog.get_color(role)
	var fill: Color = ShipCatalog.FILLS.get(role, Color("062a12"))
	if definition.element == "void": fill = Color.BLACK
	if part.layer != 0 and part.shape == "circle" and part.filled:
		var polygon: PackedVector2Array = points.duplicate()
		if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[-1]): polygon.remove_at(polygon.size() - 1)
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, fill)
	var width: float = (2.0 if part.shape == "line" else 1.5) / canvas_scale
	if part.dashed or part.layer == 0:
		var total: float = distances[-1]
		var cursor: float = 0.0
		while cursor < total:
			var dash: PackedVector2Array = ShipGeometry.section(points, distances, cursor, minf(total, cursor + 2.0 / canvas_scale))
			if dash.size() >= 2: draw_polyline(dash, Color(stroke, 0.5), 1.0 / canvas_scale, true)
			cursor += 6.0 / canvas_scale
	else:
		draw_polyline(points, stroke * 0.96, width, true)
	var light: Color = ShipCatalog.LIGHTS.get(role, Color.WHITE)
	light = _emission(light, 1.8)
	var perimeter: float = distances[-1]
	if perimeter < 0.001:
		return
	var start: float = running_phase(part) * perimeter
	var finish: float = start + perimeter * 0.13
	_draw_segment(points, distances, start, minf(finish, perimeter), light, 2.6 / canvas_scale)
	if finish > perimeter:
		_draw_segment(points, distances, 0.0, finish - perimeter, light, 2.6 / canvas_scale)

func _emission(tint: Color, boost: float) -> Color:
	# Immediate canvas colors are sRGB; the mesh shader emits linear HDR values.
	# Match the two paths so changing to/from reshape cannot flash brighter.
	var emitted: Color = (tint.srgb_to_linear() * boost).linear_to_srgb()
	emitted.a = 1.0
	return emitted

func _draw_segment(points: PackedVector2Array, distances: PackedFloat32Array, start: float, finish: float, color: Color, width: float) -> void:
	var segment: PackedVector2Array = ShipGeometry.section(points, distances, start, finish)
	if segment.size() < 2: return
	draw_polyline(segment, color, width, true)
	draw_circle(segment[0], width * 0.5, color, true, -1, true)
	draw_circle(segment[-1], width * 0.5, color, true, -1, true)

func running_phase(part: PartDefinition) -> float:
	var cycles: float = (animation_time + part.light_phase) / maxf(0.05, part.light_period)
	match definition.motion_signature:
		"flicker": cycles += 0.025 * sin(cycles * TAU * 5.0)
		"snap": cycles = floorf(cycles * 12.0) / 12.0
		"counter_rotate":
			if not part.filled and int(part.light_phase * 10) % 2 != 0: cycles *= -1
	return fposmod(cycles, 1.0)

