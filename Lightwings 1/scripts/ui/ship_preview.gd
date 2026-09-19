class_name ShipPreview
extends SubViewportContainer
## A real HDR ship view, deliberately independent of paused gameplay.

var renderer: ShipRenderer
var preview_viewport: SubViewport
var environment: Environment
static var glow_enabled: bool = true

func initialize(ship: ShipDefinition, area: Vector2, magnification: float = 1.8) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ship_previews")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = area
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(area)
	preview_viewport.transparent_bg = true
	preview_viewport.own_world_3d = true
	preview_viewport.use_hdr_2d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview_viewport)
	environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = glow_enabled
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 1.5
	environment.glow_strength = 0.35
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for index: int in range(7):
		environment.set_glow_level(index,0.8 if index==0 else 0.0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	preview_viewport.add_child(world_environment)
	renderer = ShipRenderer.new()
	preview_viewport.add_child(renderer)
	renderer.position = area*0.5
	renderer.visual_scale = magnification
	renderer.set_ship(ship)
