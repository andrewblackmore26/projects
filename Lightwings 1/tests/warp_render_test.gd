extends SceneTree
## Real Vulkan pixels: the rim stroke width stays constant in screen space
## at the warp's 1.30x zoom (spec §12/§23), and warp streaks are present
## during a warp phase and absent before one. Headless has no renderer and a
## failed shader renders black (lessons.md), so this needs a real window.

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	await _zoom_case()
	await _streak_case()
	print("Warp pixels: failures=", failures, " controls_caught=", controls_caught, "/", controls_total)
	scene.queue_free()
	await process_frame
	quit(1 if failures or controls_caught != controls_total else 0)

func _make_world(center: Vector2, radius: float) -> CombatWorld:
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.visuals_enabled = false
	world.setup_player("neutral", 1, 40, [], center)
	world.arena.center = center
	world.arena.radius = radius
	world.arena.exits.assign([Vector2i.RIGHT])
	world.player_position = center
	return world

## `zoom_holder.scale` stands in for what `combat_compositor.gd::_update_camera`
## does to `foreground`/`background_viewport.canvas_transform` at the warp's
## 1.30x - ArenaBackdrop reads the live canvas transform scale the same way
## `ship_renderer.gd` does, so wrapping it in a scaled parent is equivalent to
## driving it through the real compositor, without needing a SubViewport here.
func _zoom_case() -> void:
	var center: Vector2 = Vector2(640, 400)
	var radius: float = 300.0
	var world_1x: CombatWorld = _make_world(center, radius)
	var backdrop_1x: ArenaBackdrop = ArenaBackdrop.new()
	backdrop_1x.world = world_1x
	scene.add_child(backdrop_1x)
	await _frame()
	var width_1x: float = _measure_rim_width(root.get_texture().get_image(), center, radius)
	backdrop_1x.queue_free()
	world_1x.queue_free()
	await process_frame

	var holder: Node2D = Node2D.new()
	holder.scale = Vector2(1.30, 1.30)
	scene.add_child(holder)
	var world_zoom: CombatWorld = CombatWorld.new()
	holder.add_child(world_zoom)
	world_zoom.visuals_enabled = false
	world_zoom.setup_player("neutral", 1, 40, [], center)
	world_zoom.arena.center = center
	world_zoom.arena.radius = radius
	world_zoom.arena.exits.assign([Vector2i.RIGHT])
	world_zoom.player_position = center
	var backdrop_zoom: ArenaBackdrop = ArenaBackdrop.new()
	backdrop_zoom.world = world_zoom
	holder.add_child(backdrop_zoom)
	await _frame()
	# Sample near the zoomed centre (screen-space centre moves with the
	# parent's scale around its origin) - measure at the actual on-screen rim.
	var width_zoom: float = _measure_rim_width(root.get_texture().get_image(), center * 1.30, radius * 1.30)
	_check(absf(width_zoom - width_1x) <= WIDTH_TOLERANCE * width_1x, "Rim stroke weight at 1.30x zoom (%.3f) equals the weight at 1.00x (%.3f)" % [width_zoom, width_1x])

	# Negative control: force canvas_scale to 1 while still actually rendered
	# at 1.30x - the compensation is defeated, so the widths must now differ.
	backdrop_zoom.canvas_scale_override = 1.0
	await _frame()
	var width_broken: float = _measure_rim_width(root.get_texture().get_image(), center * 1.30, radius * 1.30)
	print("Rim stroke weight: 1.00x %.3f, 1.30x %.3f, 1.30x uncompensated %.3f" % [width_1x, width_zoom, width_broken])
	_control("canvas_scale forced to 1 at real 1.30x zoom", absf(width_broken - width_1x) > WIDTH_TOLERANCE * width_1x)
	holder.queue_free()
	await process_frame

## Scans radially through the rim near angle 0 and integrates brightness
## along the scan line (modernization M3: the rim is two thin 1.5/1.0 px
## strokes, too thin for a bright-pixel count to resolve a 1.30x change; the
## integral scales with stroke width, antialiasing included).
const WIDTH_TOLERANCE: float = 0.15
func _measure_rim_width(image: Image, center: Vector2, radius: float) -> float:
	var total: float = 0.0
	for r: int in range(-12, 13):
		var p: Vector2i = Vector2i(center + Vector2(radius + r, 0.0))
		if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height(): continue
		var pixel: Color = image.get_pixel(p.x, p.y)
		total += pixel.r + pixel.g + pixel.b
	return total

func _streak_case() -> void:
	var center: Vector2 = Vector2(640, 400)
	var radius: float = 300.0
	var world: CombatWorld = _make_world(center, radius)
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	scene.add_child(backdrop)
	await _frame()
	var before_image: Image = root.get_texture().get_image()
	var before_streak: float = _ring_max(before_image, center, radius * 0.4, radius * 0.85)
	world.warp_phase = CombatWorld.WARP_TRAVEL
	world.warp_direction = Vector2i.RIGHT
	world.warp_progress = 0.5
	await _frame()
	var during_image: Image = root.get_texture().get_image()
	var during_streak: float = _ring_max(during_image, center, radius * 0.4, radius * 0.85)
	_check(during_streak > before_streak * 1.3, "Streaks are present during the warp phase (%.4f) and measurably brighter than before it (%.4f)" % [during_streak, before_streak])
	# Negative control: warp_phase reset to WARP_NONE - streaks must vanish again.
	world.warp_phase = CombatWorld.WARP_NONE
	await _frame()
	var after_image: Image = root.get_texture().get_image()
	var after_streak: float = _ring_max(after_image, center, radius * 0.4, radius * 0.85)
	_control("warp_phase reset to WARP_NONE", after_streak <= before_streak * 1.3)
	backdrop.queue_free()
	world.queue_free()
	await process_frame

func _ring_max(image: Image, center: Vector2, min_radius: float, max_radius: float) -> float:
	var worst: float = 0.0
	var min_sq: float = min_radius * min_radius
	var max_sq: float = max_radius * max_radius
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var d: float = Vector2(x, y).distance_squared_to(center)
			if d < min_sq or d > max_sq: continue
			var pixel: Color = image.get_pixel(x, y)
			worst = maxf(worst, pixel.r + pixel.g + pixel.b)
	return worst

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)
