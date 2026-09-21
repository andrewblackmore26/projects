extends SceneTree
## Ship design spec acceptance 1, the automated half: the rendered radial-elite fixture and the
## reference image must yield the SAME structural signature through the SAME probe - core rim where
## the scale says, a 4-fold inner rail, a 3-fold outer rail, 3 pods on every hub, a red set piece on
## every hub, a red core, two colour families and no third. Whether they LOOK alike is a human's
## call (tests/ship_reference_capture.gd writes the side-by-side); this proves the structure.
## Each signature line has its own sabotaged render that must change exactly that line.
const Probe = preload("res://tests/support/ring_probe.gd")

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var census: Dictionary
var centre: Vector2
var scale: float

func _initialize() -> void: _run.call_deferred()

func _fixture() -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	return ShipGrammar.load_json("res://tests/fixtures/ships_v4/radial_elite.json", errors)

## Renders a compiled ship at the reference's centre and scale, tick 0, and returns sRGB pixels.
func _render(ship: ShipDefinition) -> Image:
	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = centre
	renderer.visual_scale = scale
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	renderer._process(0)
	for i: int in range(3): # the capture can trail the draw by a frame (S0)
		await process_frame
		await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var size: Vector2i = Vector2i(int(census.image_size[0]), int(census.image_size[1]))
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var pixel: Color = frame.get_pixel(x, y).linear_to_srgb()
			image.set_pixel(x, y, Color(clampf(pixel.r, 0, 1), clampf(pixel.g, 0, 1), clampf(pixel.b, 0, 1), 1.0))
	renderer.queue_free()
	await process_frame
	return image

func _compiled(mutate: Callable = Callable()) -> ShipDefinition:
	var ship: ShipDefinition = _fixture()
	if mutate.is_valid(): mutate.call(ship)
	ShipCompiler.compile(ship)
	return ship

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	census = JSON.parse_string(FileAccess.get_file_as_string("res://docs/ship-design-reference.json"))
	centre = Vector2(float(census.center[0]), float(census.center[1]))
	scale = float(census.px_per_unit)
	var reference: Image = Image.load_from_file(ProjectSettings.globalize_path("res://docs/ship-design-reference.png"))
	reference.convert(Image.FORMAT_RGBA8)
	var expected: Dictionary = Probe.signature(reference, centre, scale)
	print("reference signature: ", expected)
	_check(expected == {"core_rim": true, "inner": 4, "outer": 3, "pods": [3, 3, 3], "armed_hubs": 3, "accent_core": true, "third_colour": false, "two_colours": true}, "The probe reads the reference as spec §1 describes it: %s" % str(expected))
	var actual: Dictionary = Probe.signature(await _render(_compiled()), centre, scale)
	print("render signature:    ", actual)
	for key: String in expected:
		_check(actual.get(key) == expected[key], "render.%s == reference.%s (%s vs %s)" % [key, key, str(actual.get(key)), str(expected[key])])

	# One sabotage per signature line; each must move ITS line.
	await _sabotage("outer", "a fourth arm", func(s: ShipDefinition) -> void:
		s.rails[1].order = 4
		s.rails[1].slots.append(s.rails[1].slots[0].duplicate()), expected)
	await _sabotage("inner", "a 3-fold inner rail (the two rails share an order)", func(s: ShipDefinition) -> void:
		s.rails[0].order = 3
		s.rails[0].slots.remove_at(0), expected)
	await _sabotage("pods", "two pods per hub", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[1].slots: slot.pods = 2, expected)
	await _sabotage("armed_hubs", "the set pieces removed", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[1].slots: slot.set_piece = "", expected)
	await _sabotage("accent_core", "no accent colour, so the core turns amber", func(s: ShipDefinition) -> void:
		s.accent_color = ""
		for slot: SlotDefinition in s.rails[1].slots: slot.set_piece = "", expected)
	var green: ShipDefinition = _compiled()
	for part: PartDefinition in green.parts:
		if part.id.begins_with("r2s0p"): part.color_role = "green"
	var green_signature: Dictionary = Probe.signature(await _render(green), centre, scale)
	_control("one hub's pods recoloured green", green_signature.third_colour != expected.third_colour)
	var blank: Image = Image.create(reference.get_width(), reference.get_height(), false, Image.FORMAT_RGBA8)
	_control("a blank image", Probe.signature(blank, centre, scale) != expected)
	_control("the sidecar scale off by 20 %% (core rim line)", Probe.signature(reference, centre, scale * 1.2).core_rim != expected.core_rim)

	print("Ship reference structure: failures=%d, controls %d/%d" % [failures, controls_caught, controls_total])
	quit(1 if failures or controls_caught != controls_total else 0)

func _sabotage(line: String, what: String, mutate: Callable, expected: Dictionary) -> void:
	var signature: Dictionary = Probe.signature(await _render(_compiled(mutate)), centre, scale)
	_control("%s (%s: %s)" % [what, line, str(signature.get(line))], signature.get(line) != expected[line])

func _check(condition: bool, label: String) -> void:
	if condition: print("ok: " + label)
	else:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)
