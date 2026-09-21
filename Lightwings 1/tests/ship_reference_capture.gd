extends SceneTree
## Review capture 1 (ship design spec acceptance 1, the human half): the reference image, the
## rendered radial-elite fixture at the same scale and centre, and a 50 % onion skin of the two.
## Not a test. Run in a real window:
##   tools\godot.ps1 -Arguments '--script "res://tests/ship_reference_capture.gd"'
## Writes artifacts/acceptance/reference_vs_render.png.

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var census: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/ship-design-reference.json"))
	var scale: float = float(census.px_per_unit)
	var centre: Vector2 = Vector2(float(census.center[0]), float(census.center[1]))
	var size: Vector2i = Vector2i(int(census.image_size[0]), int(census.image_size[1]))
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/radial_elite.json", errors)
	ShipCatalog.refresh(ship)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color8(int(census.background_rgb[0]), int(census.background_rgb[1]), int(census.background_rgb[2]))
	backdrop.size = Vector2(1280, 800)
	root.add_child(backdrop)
	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = centre # so the render's pixels line up with the reference's
	renderer.visual_scale = scale
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	renderer._process(0)
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	# The HDR viewport hands back LINEAR values; without this the dark fills and the backdrop crush
	# to black in an 8-bit PNG (the first capture looked unfilled for exactly that reason).
	# Per pixel from the float image: Image.linear_to_srgb() only takes 8-bit data, by which point
	# the darks are already gone.
	var render: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var pixel: Color = frame.get_pixel(x, y).linear_to_srgb()
			render.set_pixel(x, y, Color(clampf(pixel.r, 0, 1), clampf(pixel.g, 0, 1), clampf(pixel.b, 0, 1), 1.0))
	var reference: Image = Image.load_from_file(ProjectSettings.globalize_path("res://docs/ship-design-reference.png"))
	reference.convert(Image.FORMAT_RGBA8)
	var sheet: Image = Image.create(size.x * 3, size.y, false, Image.FORMAT_RGBA8)
	sheet.blit_rect(reference, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	sheet.blit_rect(render, Rect2i(Vector2i.ZERO, size), Vector2i(size.x, 0))
	for y: int in range(size.y):
		for x: int in range(size.x):
			sheet.set_pixel(size.x * 2 + x, y, reference.get_pixel(x, y).lerp(render.get_pixel(x, y), 0.5))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/acceptance"))
	sheet.save_png(ProjectSettings.globalize_path("res://artifacts/acceptance/reference_vs_render.png"))
	print("reference capture checks: 1 written, 0 failures")
	quit(0)
