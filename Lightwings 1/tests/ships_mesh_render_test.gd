extends SceneTree
## Real Vulkan pixels verify time animation, orbit offsets, constant screen-space
## widths and core radius. Run without --headless, with no other GPU benchmark.

var failures: int = 0
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	scene = Node2D.new()
	root.add_child(scene)
	var definition: ShipDefinition = ShipDefinition.new()
	definition.is_player = true
	var part: PartDefinition = PartDefinition.new()
	part.id = "test_body"
	part.shape = "circle"
	part.radius = 40
	definition.parts.append(part)
	var normal: ShipRenderer = _ship(definition, Vector2(120, 120), 1.0)
	var minimum: ShipRenderer = _ship(definition, Vector2(340, 120), 0.65)
	await _frame()
	var first: Image = root.get_texture().get_image()
	var angle: float = -PI / 2 + TAU * 0.065
	var first_light: Vector2i = Vector2i(normal.position + Vector2.from_angle(angle) * 40)
	var opposite: Vector2i = Vector2i(normal.position - Vector2.from_angle(angle) * 40)
	_check(_peak(first, first_light).r > _peak(first, opposite).r + 0.2, "The rounded pale highlight stands out from its saturated rim")
	_check(_peak(first, opposite).r < 0.3, "The opposite rim retains its saturated blue colour")
	var normal_core: int = _horizontal_width(first, Vector2i(120, 120), 8, 1.1)
	var minimum_core: int = _horizontal_width(first, Vector2i(340, 120), 8, 1.1)
	_check(normal_core >= 5 and normal_core <= 7 and normal_core == minimum_core, "Three-pixel core radius survives minimum zoom")
	var normal_stroke: int = _horizontal_width(first, Vector2i(80, 120), 5, 0.2)
	var minimum_stroke: int = _horizontal_width(first, Vector2i(314, 120), 5, 0.2)
	_check(normal_stroke >= 1 and normal_stroke <= 3 and normal_stroke == minimum_stroke, "Outline width stays constant when body shrinks")
	normal.animation_time = 1.0
	normal._process(0)
	await _frame()
	var second: Image = root.get_texture().get_image()
	_check(_peak(second, first_light).r < _peak(first, first_light).r - 0.2 and _peak(second, opposite).r > _peak(first, opposite).r + 0.2, "A half-period moves the pale arc to the opposite side")
	normal.part_position_overrides["test_body"] = Vector2(70, 0)
	normal._process(0)
	await _frame()
	var moved: Image = root.get_texture().get_image()
	_check(_peak(moved, Vector2i(80, 120)).b < 0.05, "Orbit override clears old outline position")
	_check(_peak(moved, Vector2i(150, 120)).b > 0.3, "Orbit override moves the existing mesh")
	_check(moved.get_pixel(120, 120).b > 1.0, "Orbiting components do not move the core")
	normal.part_position_overrides.clear()
	normal.set_process(true)
	paused = true
	var before: float = normal.animation_time
	for i: int in range(5): await process_frame
	_check(normal.animation_time > before, "Shader time advances while gameplay is paused")
	paused = false
	print("Ship mesh pixels: core widths=", normal_core, "/", minimum_core, " outline widths=", normal_stroke, "/", minimum_stroke, " failures=", failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _ship(definition: ShipDefinition, at: Vector2, magnification: float) -> ShipRenderer:
	var renderer: ShipRenderer = ShipRenderer.new()
	scene.add_child(renderer)
	renderer.position = at
	renderer.visual_scale = magnification
	renderer.set_ship(definition)
	renderer.set_process(false)
	renderer._process(0)
	return renderer

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _peak(image: Image, at: Vector2i) -> Color:
	var result: Color = Color.BLACK
	for y: int in range(at.y - 1, at.y + 2):
		for x: int in range(at.x - 1, at.x + 2):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r + pixel.b > result.r + result.b: result = pixel
	return result

func _horizontal_width(image: Image, center: Vector2i, range_pixels: int, threshold: float) -> int:
	var count: int = 0
	for x: int in range(center.x - range_pixels, center.x + range_pixels + 1):
		if image.get_pixel(x, center.y).b > threshold: count += 1
	return count

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
