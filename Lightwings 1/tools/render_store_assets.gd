extends SceneTree
## Local review artwork only. Run with a real rendering device, after GPU QA
## coordination. No network calls or store publication occurs in this script.

const Catalog = preload("res://scripts/ships/ship_catalog.gd")
const Renderer = preload("res://scripts/ships/ship_renderer.gd")
const OUTPUT_DIRECTORY: String = "res://artifacts/store"
const OUTPUTS: Array[Dictionary] = [
	{"name": "header_920x430", "size": Vector2i(920, 430), "title_size": 86},
	{"name": "small_462x174", "size": Vector2i(462, 174), "title_size": 43},
	{"name": "main_1232x706", "size": Vector2i(1232, 706), "title_size": 122},
]

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Store capsules require a real render device; do not use --headless.")
		quit(2)
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	if directory_error != OK:
		push_error("Cannot create store draft directory: " + error_string(directory_error))
		quit(1)
		return
	var generated: Array[Dictionary] = []
	for output: Dictionary in OUTPUTS:
		var result: Dictionary = await _render_capsule(output)
		if not result.is_empty():
			generated.append(result)
	var manifest: Dictionary = {"version": "0.2.0", "status": "unpublished review drafts", "engine": Engine.get_version_info()["string"], "created_utc": Time.get_datetime_string_from_system(true), "source": "Original ShipCatalog definitions rendered by native ShipRenderer", "external_images": false, "dimensions_source": "https://partner.steamgames.com/doc/store/assets?l=english", "capture_conversion": "floating-point pixels -> Color.linear_to_srgb -> RGBA8 -> PNG", "files": generated, "failures": failures}
	var file: FileAccess = FileAccess.open(OUTPUT_DIRECTORY.path_join("manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
	else:
		failures.append("Could not save provenance manifest")
	print("STORE DRAFTS: %d / %d generated" % [generated.size(), OUTPUTS.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _render_capsule(output: Dictionary) -> Dictionary:
	var dimensions: Vector2i = output["size"]
	var area: Vector2 = Vector2(dimensions)
	var viewport: SubViewport = SubViewport.new()
	viewport.name = str(output["name"])
	viewport.size = dimensions
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.color = Color("050507")
	background.size = area
	viewport.add_child(background)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 1.7
	environment.glow_strength = 0.35
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for index: int in range(7):
		environment.set_glow_level(index, 0.8 if index == 0 else 0.0)
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var ships: Array[ShipRenderer] = []
	var compact: bool = dimensions.y < 200
	var art_height: float = area.y * (0.63 if compact else 0.69)
	var rival_tier: int = 3 if compact else 5
	var rival_height: float = art_height * (0.55 if compact else 0.47)
	var player_height: float = art_height * 0.85
	var arrangements: Array[Dictionary]
	if compact:
		arrangements = [
			{"element": "fire", "point": Vector2(0.12, 0.48), "angle": 0.17},
			{"element": "lightning", "point": Vector2(0.32, 0.42), "angle": -0.10},
			{"element": "void", "point": Vector2(0.70, 0.48), "angle": 0.0},
			{"element": "corruption", "point": Vector2(0.88, 0.49), "angle": -0.18},
		]
	else:
		arrangements = [
			{"element": "fire", "point": Vector2(0.16, 0.30), "angle": 0.18},
			{"element": "lightning", "point": Vector2(0.83, 0.31), "angle": -0.18},
			{"element": "void", "point": Vector2(0.23, 0.78), "angle": 0.0},
			{"element": "corruption", "point": Vector2(0.77, 0.78), "angle": -0.10},
		]
	for arrangement: Dictionary in arrangements:
		var renderer: ShipRenderer = _add_ship(viewport, str(arrangement["element"]), rival_tier, false, Vector2(arrangement["point"].x * area.x, arrangement["point"].y * art_height), rival_height, float(arrangement["angle"]))
		ships.append(renderer)
	ships.append(_add_ship(viewport, "plasma", 5, true, Vector2(area.x * 0.50, art_height * 0.50), player_height, 0.0))
	var player_form_id: String = ships[ships.size() - 1].definition.id
	var title: Label = Label.new()
	title.text = "LIGHTSHIP"
	title.position = Vector2(area.x * 0.06, art_height + area.y * 0.015)
	title.size = Vector2(area.x * 0.88, area.y - title.position.y)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("edf6fc"))
	title.add_theme_constant_override("outline_size", 0)
	var font: FontVariation = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 1.1
	font.spacing_glyph = 2 if compact else 4
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", int(output["title_size"]))
	viewport.add_child(title)
	# Freeze all running-light phases so a repeated invocation is reviewable.
	for renderer: ShipRenderer in ships:
		renderer.animation_time = 0.65
		renderer._process(0.0)
		renderer.set_process(false)
		renderer.queue_redraw()
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = viewport.get_texture().get_image()
	if capture == null or capture.is_empty():
		failures.append("Empty viewport image: " + str(output["name"]))
		viewport.queue_free()
		await process_frame
		return {}
	# HDR viewport values must remain floating point during gamma conversion.
	if capture.get_format() != Image.FORMAT_RGBAF:
		capture.convert(Image.FORMAT_RGBAF)
	# Image.linear_to_srgb() only accepts RGB8/RGBA8 in this engine. Apply
	# Color.linear_to_srgb() per pixel while the image still holds HDR floats.
	for y: int in range(capture.get_height()):
		for x: int in range(capture.get_width()):
			capture.set_pixel(x, y, capture.get_pixel(x, y).linear_to_srgb())
	capture.convert(Image.FORMAT_RGBA8)
	var path: String = OUTPUT_DIRECTORY.path_join(str(output["name"]) + ".png")
	var error: Error = capture.save_png(path)
	viewport.queue_free()
	await process_frame
	if error != OK:
		failures.append("PNG export failed: " + path + " (" + error_string(error) + ")")
		return {}
	print("Saved ", path, " ", dimensions)
	return {"file": path.trim_prefix("res://"), "width": dimensions.x, "height": dimensions.y, "player_form": player_form_id, "rival_tier": rival_tier, "title": "LIGHTSHIP"}

func _add_ship(parent: SubViewport, element: String, tier: int, is_player: bool, point: Vector2, target_height: float, angle: float) -> ShipRenderer:
	var ship: ShipDefinition = Catalog.make_ship(element, tier, is_player)
	var renderer: ShipRenderer = Renderer.new()
	parent.add_child(renderer)
	renderer.position = point
	renderer.rotation = angle
	# Fit the authored geometry; do not redesign or stretch any ship part.
	var radius: float = maxf(ship.hull_radius, 12.0)
	for part: PartDefinition in ship.parts:
		if part.shape == "tether":
			continue
		radius = maxf(radius, part.position.length() + part.size.length() * 0.5)
	renderer.visual_scale = target_height / (radius * 2.0)
	renderer.set_ship(ship)
	return renderer
