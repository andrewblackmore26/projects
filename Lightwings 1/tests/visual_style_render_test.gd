extends SceneTree
## Real pixels: bright coloured rims, travelling pale arcs, dark fills and dotted guides.
var failures: int = 0
var checks: int = 0
var controls: int = 0
const AT: Vector2 = Vector2(320, 400)

func _initialize() -> void: _run.call_deferred()

func _fixture() -> ShipDefinition:
	var ship := ShipDefinition.new()
	ship.is_player = true
	ship.core_radius = 5.0
	for entry: Array in [["core", Vector2.ZERO, 34.0, true, -1], ["guide", Vector2.ZERO, 52.0, false, 5], ["tip", Vector2(96, 0), 7.0, true, -1]]:
		var part := PartDefinition.new()
		part.id = entry[0]
		part.position = entry[1]
		part.radius = entry[2]
		part.filled = entry[3]
		part.style = entry[4]
		part.parent_id = "" if part.id == "core" else "core"
		ship.parts.append(part)
	var line := PartDefinition.new()
	line.id = "spoke"
	line.shape = "line"
	line.from_id = "core"
	line.to_id = "tip"
	ship.parts.append(line)
	return ship

func _renderer(at: Vector2, scale_factor: float) -> ShipRenderer:
	var renderer := ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = at
	renderer.visual_scale = scale_factor
	renderer.set_ship(_fixture())
	renderer.set_process(false)
	renderer._process(0)
	return renderer

func _frame() -> Image:
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _brightness(pixel: Color) -> float: return pixel.r + pixel.g + pixel.b

func _peak(image: Image, at: Vector2i) -> float:
	var peak: float = 0.0
	for y: int in range(at.y - 1, at.y + 2):
		for x: int in range(at.x - 1, at.x + 2): peak = maxf(peak, _brightness(image.get_pixel(x, y)))
	return peak

func _stroke_width(image: Image, at: Vector2i, vertical: bool) -> int:
	var width: int = 0
	for offset: int in range(-5, 6):
		var point: Vector2i = at + (Vector2i(0, offset) if vertical else Vector2i(offset, 0))
		if _brightness(image.get_pixelv(point)) > 0.20: width += 1
	return width

func _guide_peak(image: Image) -> float:
	var peak: float = 0.0
	# Keep away from the spoke and its circle. The guide must be visible on its own.
	for i: int in range(90, 630):
		var angle: float = TAU * float(i) / 720.0
		peak = maxf(peak, _peak(image, Vector2i(AT + Vector2.from_angle(angle) * 52)))
	return peak

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var backdrop := ColorRect.new()
	backdrop.color = VisualStyle.BG
	backdrop.size = Vector2(1280, 800)
	root.add_child(backdrop)
	var normal := _renderer(AT, 1.0)
	_renderer(Vector2(850, 400), 0.65)
	var before: Image = await _frame()
	var body: float = _peak(before, Vector2i(AT + Vector2(-34, 0)))
	var guide: float = _guide_peak(before)
	var background: float = _brightness(before.get_pixel(50, 50))
	var fill: float = _brightness(before.get_pixelv(Vector2i(AT + Vector2(15, 0))))
	_check(body > 0.9 and body < 3.0, "Body outlines retain saturated reference colour")
	_check(guide > background + 0.03 and guide < body * 0.40, "Reference guides are visible but subordinate to structure")
	_check(fill > background + 0.005 and fill < body * 0.15, "Dark tinted bodies separate from the reference background")
	var rim_width: int = _stroke_width(before, Vector2i(AT + Vector2(-34, 0)), false)
	var line_width: int = _stroke_width(before, Vector2i(AT + Vector2(65, 0)), true)
	var small_width: int = _stroke_width(before, Vector2i(850 - 22, 400), false)
	_check(rim_width >= 1 and rim_width <= 2 and abs(rim_width-line_width) <= 1 and abs(rim_width-small_width) <= 1, "Rims and connectors retain thin screen-space widths at minimum zoom")
	normal.animation_time = 0.73
	normal._process(0)
	var after: Image = await _frame()
	var delta: float = 0.0
	for i: int in range(360):
		var point: Vector2i = Vector2i(AT + Vector2.from_angle(TAU * float(i) / 360.0) * 34)
		delta = maxf(delta, absf(_brightness(after.get_pixelv(point)) - _brightness(before.get_pixelv(point))))
	_check(delta > 0.25, "Pale rounded highlights travel around idle circular rims")
	normal._mesh_material.set_shader_parameter("light_fraction", 0.0)
	var no_light: Image = await _frame()
	var light_control: bool = false
	for i: int in range(360):
		var point: Vector2i = Vector2i(AT + Vector2.from_angle(TAU * float(i) / 360.0) * 34)
		if _brightness(after.get_pixelv(point)) - _brightness(no_light.get_pixelv(point)) > 0.25: light_control = true
	controls += int(light_control)
	_check(light_control, "Negative control detects removed running highlights")
	normal._mesh_material.set_shader_parameter("guide_opacity", 1.0)
	var bad_guide: Image = await _frame()
	var guide_control: bool = _guide_peak(bad_guide) >= body * 0.40
	controls += int(guide_control)
	_check(guide_control, "Negative control catches a guide rendered as bright structure")
	normal._mesh_material.set_shader_parameter("stroke_width", 6.0)
	var fat: Image = await _frame()
	var stroke_control: bool = _stroke_width(fat, Vector2i(AT + Vector2(-34, 0)), false) > 2
	controls += int(stroke_control)
	_check(stroke_control, "Negative control catches thick body outlines")
	print("VISUAL STYLE: %d checks, %d failures, %d controls; body=%.3f guide=%.3f fill=%.3f bg=%.3f widths=%d/%d/%d" % [checks, failures, controls, body, guide, fill, background, rim_width, line_width, small_width])
	quit(1 if failures else 0)
