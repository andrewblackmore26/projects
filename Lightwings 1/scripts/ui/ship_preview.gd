class_name ShipPreview
extends SubViewportContainer
## A real HDR ship view, deliberately independent of paused gameplay.

var renderer: ShipRenderer
var preview_viewport: SubViewport
var environment: Environment
static var glow_enabled: bool = true
var preview_time_scale: float = 1.0
var auto_fit: bool = true
var fit_margin: float = 28.0
var requested_magnification: float = 1.8
var motion_radius: float = 0.0

func initialize(ship: ShipDefinition, area: Vector2, magnification: float = 1.8) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ship_previews")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = area
	requested_magnification = magnification
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
	VisualStyle.configure_glow(environment)
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
	renderer.set_process(false)
	motion_radius = animated_radius(ship)
	fit_to_area(area)
	resized.connect(func() -> void: fit_to_area(size))

func _process(delta: float) -> void:
	if renderer != null: renderer._process(delta * preview_time_scale)

func fit_to_area(area: Vector2) -> void:
	if renderer == null or preview_viewport == null: return
	if not stretch: preview_viewport.size = Vector2i(maxf(1, area.x), maxf(1, area.y))
	renderer.position = area * 0.5
	if auto_fit:
		var available: float = maxf(1.0, minf(area.x, area.y) * 0.5 - fit_margin)
		renderer.visual_scale = minf(requested_magnification, available / maxf(1.0, motion_radius))

## Triangle-inequality bound across the motion hierarchy: any rotation stays inside it.
## Pumping extends each link; chain sway/whip is a root-local translation.
static func animated_radius(ship: ShipDefinition) -> float:
	if ship == null: return 1.0
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var reach: PackedFloat32Array = PackedFloat32Array()
	reach.resize(rig.rest.size())
	var radius: float = maxf(ship.core_radius, ship.hull_radius)
	for i: int in range(rig.rest.size()):
		var parent: int = rig.parent_index[i]
		var offset: float = (rig.rest[i] - rig.rest[parent]).length() if parent >= 0 else rig.rest[i].length()
		var pump: float = absf(rig.pump_amp[i]) if not rig.legacy else 0.0
		reach[i] = (reach[parent] if parent >= 0 else 0.0) + offset * (1.0 + pump)
		radius = maxf(radius, reach[i] + rig.radius[i])
	if ship.chain_mode in ["sway", "whip"]:
		radius += float(ShipGrammar.MOTION.chain_amplitude.get(ship.chain_mode, 0.0))
	return radius + 4.0
