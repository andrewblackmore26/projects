class_name CombatCompositor
extends Node2D
## Two HDR stages. Gameplay coordinates and all actor references are unchanged.
## Background source occlusion -> background glow -> opaque Void hulls -> threats.

var world: CombatWorld
var background_viewport: SubViewport
var background_image: TextureRect
var background_environment: Environment
var _original_parent: Node
var _original_process_mode: Node.ProcessMode
var _hull_masks: Dictionary = {}
var _detaching: bool = false
var foreground: Node2D
var camera_offset: Vector2 = Vector2.ZERO
var follow_player: bool = true
## Zoom (spec §12/§23): 1.0 in ordinary flight, the warp pushes it to 1.30x
## centred slightly ahead of the ship in the travel direction. Sourced from
## the SIM (`world.warp_phase`/`warp_progress`), never a local clock - two
## time sources is a bug waiting to happen (tasks/lessons.md).
var zoom: float = 1.0
const WARP_ZOOM_PEAK: float = 1.30
const FOCUS_LEAD_PIXELS: float = 90.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100

func attach(combat: CombatWorld) -> void:
	if is_instance_valid(world):
		push_error("CombatCompositor already has a world")
		return
	world = combat
	_original_parent = world.get_parent()
	_original_process_mode = world.process_mode
	background_viewport = SubViewport.new()
	background_viewport.name = "BackgroundHDR"
	background_viewport.size = Vector2i(1280, 800)
	background_viewport.use_hdr_2d = true
	background_viewport.own_world_3d = true
	background_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(background_viewport)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	for child: Node in _original_parent.get_children():
		if child is WorldEnvironment:
			background_environment = child.environment
			break
	if background_environment == null:
		background_environment = Environment.new()
		background_environment.background_mode = Environment.BG_CANVAS
		background_environment.glow_enabled = true
		background_environment.glow_hdr_threshold = 1.0
		background_environment.glow_intensity = 1.5
		background_environment.glow_strength = 0.35
		background_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level: int in range(7): background_environment.set_glow_level(level, 0.6 if level == 0 else 0.0)
	environment_node.environment = background_environment
	background_viewport.add_child(environment_node)
	background_image = TextureRect.new()
	background_image.name = "ProcessedBackground"
	background_image.position = Vector2.ZERO
	background_image.size = Vector2(1280, 800)
	background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_image.texture = background_viewport.get_texture()
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/ship_background.gdshader")
	background_image.material = shader_material
	background_image.z_index = 0
	add_child(background_image)
	foreground = Node2D.new()
	foreground.name = "WorldForeground"
	foreground.z_index = 1
	add_child(foreground)
	world.reparent(background_viewport, false)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_sync_foreground()
	_update_camera()

func _process(_delta: float) -> void:
	if _detaching: return
	if not is_instance_valid(world) or world.is_queued_for_deletion():
		if background_viewport != null: queue_free()
		return
	_sync_foreground()
	_update_camera()

func _update_camera() -> void:
	zoom = _warp_zoom()
	var lead: Vector2 = Vector2.ZERO
	if zoom > 1.001 and world.warp_direction != Vector2i.ZERO:
		lead = Vector2(world.warp_direction).normalized() * FOCUS_LEAD_PIXELS * clampf((zoom - 1.0) / (WARP_ZOOM_PEAK - 1.0), 0.0, 1.0)
	var focus: Vector2 = (world.player_position + lead) if follow_player else Vector2.ZERO
	var screen_center: Vector2 = Vector2(640, 400) if follow_player else Vector2.ZERO
	camera_offset = screen_center - focus * zoom
	var xform := Transform2D(0.0, Vector2.ZERO).scaled(Vector2(zoom, zoom))
	xform.origin = camera_offset
	background_viewport.canvas_transform = xform
	foreground.position = camera_offset
	foreground.scale = Vector2(zoom, zoom)

## Reads the sim's warp phase/progress and turns it into a screen zoom -
## the same shape as the phase table in spec §12 (zoom in 0.12s to 1.30x,
## hold through the travel+arrival, zoom out 0.20s back to 1.00x). The
## reduced-warp accessibility option (WARP_FADE) never zooms at all.
func _warp_zoom() -> float:
	if not is_instance_valid(world): return 1.0
	match world.warp_phase:
		world.WARP_ZOOM_IN: return lerpf(1.0, WARP_ZOOM_PEAK, world.warp_progress)
		world.WARP_TRAVEL, world.WARP_ARRIVAL: return WARP_ZOOM_PEAK
		world.WARP_ZOOM_OUT: return lerpf(WARP_ZOOM_PEAK, 1.0, world.warp_progress)
		_: return 1.0

func screen_to_world(point: Vector2) -> Vector2:
	return (point - camera_offset) / maxf(0.0001, zoom)

func add_world_overlay(node: Node2D) -> void:
	foreground.add_child(node)

func _sync_foreground() -> void:
	var bullets: Node2D = world._bullet_canvas
	if is_instance_valid(bullets) and bullets.get_parent() != foreground:
		bullets.reparent(foreground, false)
		bullets.z_index = 40
	var trails: Node2D = world._trail_canvas
	if is_instance_valid(trails) and trails.get_parent() != foreground:
		trails.reparent(foreground, false)
		trails.z_index = 5
	var live_voids: Dictionary = {}
	for actor: Dictionary in world.actors_by_id.values():
		var source: ShipRenderer = actor.get("renderer") as ShipRenderer
		if not is_instance_valid(source) or source.is_queued_for_deletion(): continue
		var player: bool = int(actor.id) == 0
		var void_hull: bool = source.definition != null and source.definition.hull_radius > 0.0
		if player or void_hull:
			if source.get_parent() != foreground: source.reparent(foreground, false)
			source.z_index = 30 if player else 20
		else:
			if source.get_parent() != world: source.reparent(world, false)
			source.z_index = 10
		if void_hull:
			var id: int = int(actor.id)
			live_voids[id] = true
			var mask: ShipRenderer = _hull_masks.get(id) as ShipRenderer
			if not is_instance_valid(mask):
				mask = ShipRenderer.new()
				mask.name = "SourceHull_" + str(id)
				mask.hull_only = true
				mask.show_core = false
				mask.z_index = 30
				background_viewport.add_child(mask)
				_hull_masks[id] = mask
			if mask.definition != source.definition:
				mask.set_ship(source.definition, source.reshape_remaining > 0)
			mask.position = source.position
			mask.rotation = source.rotation
			mask.visual_scale = source.visual_scale
			mask.reshape_remaining = source.reshape_remaining
			mask.animation_time = source.animation_time
	for id: int in _hull_masks.keys():
		if not live_voids.has(id):
			var mask: ShipRenderer = _hull_masks[id]
			if is_instance_valid(mask): mask.queue_free()
			_hull_masks.erase(id)

func detach() -> void:
	_detaching = true
	if is_instance_valid(world) and is_instance_valid(_original_parent):
		var bullets: Node2D = world._bullet_canvas
		if is_instance_valid(bullets) and bullets.get_parent() == foreground: bullets.reparent(world, false)
		var trails: Node2D = world._trail_canvas
		if is_instance_valid(trails) and trails.get_parent() == foreground: trails.reparent(world, false)
		for actor: Dictionary in world.actors_by_id.values():
			var renderer: ShipRenderer = actor.get("renderer") as ShipRenderer
			if is_instance_valid(renderer):
				if renderer.get_parent() == foreground: renderer.reparent(world, false)
				renderer.z_index = 10
		world.reparent(_original_parent, false)
		world.process_mode = _original_process_mode
	world = null
	queue_free()
