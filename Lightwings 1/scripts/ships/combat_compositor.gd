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
## The shake-free camera: screen = world * zoom + camera_offset. `screen_to_world` inverts exactly
## this, so aim never sees the shake.
var camera_offset: Vector2 = Vector2.ZERO
var follow_player: bool = true
## M10: the trailing camera (scripts/ships/camera_rig.gd) owns focus and zoom. It is stepped only
## when `world.tick` changes, with the sim's dt - two time sources is a bug waiting to happen
## (tasks/lessons.md) - so a hitstop or a pause freezes it with the world.
var zoom: float = 1.0
var rig: CameraRig = CameraRig.new()
var _rig_tick: int = -1
## M10 shake (scripts/fx/screen_shake.gd), fed by `world.feel_event`. Applied to the RENDERED
## transform after the rig's clamp, about the screen centre, and excluded from `camera_offset`.
var shake: ScreenShake = ScreenShake.new()
var view_shake_offset: Vector2 = Vector2.ZERO
var view_shake_rotation: float = 0.0
var _shake_tick: int = -1
var _shake_hitstop: int = 0
const SCREEN_CENTER: Vector2 = Vector2(640, 400)

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
		VisualStyle.configure_glow(background_environment)
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
	world.feel_event.connect(_on_feel_event)
	rig.reset(world.player_position)
	_rig_tick = world.tick
	_shake_tick = world.tick
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
	_step_rig()
	_step_shake()
	zoom = rig.zoom if follow_player else 1.0
	var focus: Vector2 = rig.focus if follow_player else Vector2.ZERO
	var screen_center: Vector2 = SCREEN_CENTER if follow_player else Vector2.ZERO
	camera_offset = screen_center - focus * zoom
	var xform := Transform2D(0.0, Vector2.ZERO).scaled(Vector2(zoom, zoom))
	xform.origin = camera_offset
	if follow_player and (view_shake_offset != Vector2.ZERO or view_shake_rotation != 0.0):
		xform = Transform2D(view_shake_rotation, SCREEN_CENTER + view_shake_offset) * Transform2D(0.0, -SCREEN_CENTER) * xform
	background_viewport.canvas_transform = xform
	foreground.transform = xform

## Steps the rig once per sim tick that has passed since the last frame, with the sim's dt. A tick
## that went BACKWARDS is a new life (setup_player resets it), so the camera snaps to the ship.
func _step_rig() -> void:
	if world.tick < _rig_tick: rig.reset(world.player_position)
	elif world.tick > _rig_tick:
		var player: Dictionary = world.player
		var velocity: Vector2 = Vector2(player.get("vel", Vector2.ZERO))
		var aim: Vector2 = Vector2(player.get("aim", Vector2.ZERO))
		var top_speed: float = float(world.call("player_top_speed")) if world.has_method("player_top_speed") else float(player.get("speed", GameTuning.feel("player_top_speed")))
		rig.step(world._last_dt * float(world.tick - _rig_tick), world.player_position, velocity, aim, top_speed, _warp_mode())
	_rig_tick = world.tick

## The world's warp phase, as the camera override it implies (spec §7). The reduced-motion FADE
## keeps the ordinary camera: no zoom, no whip, no overshoot.
func _warp_mode() -> StringName:
	match world.warp_phase:
		world.WARP_PUSH: return &"push"
		world.WARP_ZOOM_IN: return &"break"
		world.WARP_TRAVEL: return &"warp"
		world.WARP_ARRIVAL, world.WARP_ZOOM_OUT: return &"arrival"
		_: return &""

## One shake step per sim step, and a hitstop step counts: the freeze is exactly when a hit's shake
## should play, so the shake keeps decaying while `world.tick` stands still.
func _step_shake() -> void:
	var settings: Variant = _original_parent.get("settings") if is_instance_valid(_original_parent) else null
	if settings is Dictionary:
		shake.intensity = clampf(float(settings.get("screen_shake", 1.0)), 0.0, 1.0)
		shake.reduced_motion = bool(settings.get("reduced_motion", settings.get("reduced_warp", false)))
	var steps: int = maxi(0, world.tick - _shake_tick) + maxi(0, _shake_hitstop - world.hitstop_remaining)
	if world.tick < _shake_tick: shake.clear()
	_shake_tick = world.tick
	_shake_hitstop = world.hitstop_remaining
	for i: int in range(mini(steps, 8)): shake.step(world._last_dt)
	view_shake_offset = shake.offset
	view_shake_rotation = shake.rotation

func _on_feel_event(kind: StringName, _at: Vector2, _magnitude: float, _actor_id: int) -> void:
	shake.add(kind)

## Shake-free, the exact inverse of `world_to_screen`: mouse aim never jitters with the shake.
func screen_to_world(point: Vector2) -> Vector2:
	return (point - camera_offset) / maxf(0.0001, zoom)

func world_to_screen(point: Vector2) -> Vector2:
	return point * zoom + camera_offset

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
	# Review finding 5: `_fx_canvas` and `_pickup_canvas` used to stay parented
	# under `world`, which lives inside `background_viewport` - a SEPARATE
	# render target composited as one flat texture at the background stage's
	# z_index 0, entirely outside `foreground`'s own z-ordering. Their
	# internal MultiMeshInstance2D passes (fx_canvas.gd's `below_mesh`=1 /
	# `above_mesh`=41, "above the bullet canvas at 40") were correct relative
	# to EACH OTHER but never actually compared against the bullet canvas,
	# trails or the player hull at all - so `above_mesh` composited under
	# all three regardless of its own z_index. Reparenting into `foreground`
	# (z_index 0 on the container, so its children's z_as_relative absolute
	# z_index of 1/41 mean what fx_canvas.gd's own comment says they mean)
	# puts them in the same ordering space as bullets/trails/hulls.
	var fx: Node2D = world._fx_canvas
	if is_instance_valid(fx) and fx.get_parent() != foreground:
		fx.reparent(foreground, false)
		fx.z_index = 0
	var pickups: Node2D = world._pickup_canvas
	if is_instance_valid(pickups) and pickups.get_parent() != foreground:
		pickups.reparent(foreground, false)
		pickups.z_index = 0
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
	if is_instance_valid(world) and world.feel_event.is_connected(_on_feel_event): world.feel_event.disconnect(_on_feel_event)
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
