extends SceneTree
## S6 GPU pixels: (a) an animating tile's pixels change between ticks while a frozen tile's do not;
## (b) detach preview on the radial-elite fixture's hub r2s0 highlights that hub's own subtree and
## not r2s1's cluster (acceptance 7); (c) every ship in a staged root draws something on its tile.

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
const AT: Vector2 = Vector2(640, 400)

func _initialize() -> void: _run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition: print("ok: " + label)
	else:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)

func _load(name: String) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
	ShipCompiler.compile(ship)
	return ship

func _image_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var total: float = 0.0
	var step: int = 4
	var samples: int = 0
	for y: int in range(rect.position.y, rect.position.y + rect.size.y, step):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x, step):
			var pa: Color = a.get_pixel(x, y)
			var pb: Color = b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			samples += 1
	return total / maxf(1.0, float(samples))

func _capture() -> Image:
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var blank: Image = await _capture() # the real background colour, not a synthetic all-zero image

	# --- (a) animating vs frozen ------------------------------------------------------------
	var moving_tile: GalleryTile = GalleryTile.new()
	root.add_child(moving_tile)
	moving_tile.position = Vector2(100, 100)
	moving_tile.size = Vector2(GalleryTile.STAGE_SIZE.x, 250)
	var moving_entry: Dictionary = {"id": "moving", "name": "Moving", "ship": _load("radial_elite"), "footprint": 240.0}
	moving_tile.set_entry(moving_entry, false)
	moving_tile.set_animating(true)

	var frozen_tile: GalleryTile = GalleryTile.new()
	root.add_child(frozen_tile)
	frozen_tile.position = Vector2(500, 100)
	frozen_tile.size = Vector2(GalleryTile.STAGE_SIZE.x, 250)
	var frozen_entry: Dictionary = {"id": "frozen", "name": "Frozen", "ship": _load("radial_elite"), "footprint": 240.0}
	frozen_tile.set_entry(frozen_entry, false)
	frozen_tile.set_animating(false)

	var moving_stage: Rect2i = Rect2i(Vector2i(moving_tile.position + Vector2(10, 10)), Vector2i(GalleryTile.STAGE_SIZE) - Vector2i(20, 20))
	var frozen_stage: Rect2i = Rect2i(Vector2i(frozen_tile.position + Vector2(10, 10)), Vector2i(GalleryTile.STAGE_SIZE) - Vector2i(20, 20))

	var before: Image = await _capture()
	# Advance real frames so the moving tile's own _process ticks its animation clock forward.
	for i: int in range(90): await process_frame
	var after: Image = await _capture()

	var moving_diff: float = _image_diff(before, after, moving_stage)
	var frozen_diff: float = _image_diff(before, after, frozen_stage)
	print("tile diffs: moving=%.5f frozen=%.5f" % [moving_diff, frozen_diff])
	_check(moving_diff > 0.001, "An animating tile's pixels differ between two ticks (%.5f)" % moving_diff)
	_check(frozen_diff < 0.0005, "A frozen tile's pixels do not change (%.5f)" % frozen_diff)
	_control("freezing the 'animating' tile too makes it fail this same check", not (frozen_diff > 0.001))
	moving_tile.queue_free()
	frozen_tile.queue_free()
	await process_frame

	# --- (b) detach preview: r2s0's subtree highlights, r2s1's does not (acceptance 7) -------
	var ship: ShipDefinition = _load("radial_elite")
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var index0: int = rig.index_of("r2s0")
	var index1: int = rig.index_of("r2s1")
	_check(index0 >= 0 and index1 >= 0, "The fixture compiles r2s0 and r2s1 hub circles")

	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = AT
	renderer.visual_scale = 3.0
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	renderer._process(0)
	var overlay: GalleryDetachOverlay = GalleryDetachOverlay.new()
	overlay.target = renderer
	renderer.add_child(overlay)

	var at0: Vector2 = AT + rig.rest[index0] * renderer.visual_scale
	var at1: Vector2 = AT + rig.rest[index1] * renderer.visual_scale

	overlay.clear()
	var none_image: Image = await _capture()
	var none0: Color = none_image.get_pixel(int(at0.x), int(at0.y))
	var none1: Color = none_image.get_pixel(int(at1.x), int(at1.y))

	overlay.highlight(index0)
	var highlighted_image: Image = await _capture()
	var hi0: Color = highlighted_image.get_pixel(int(at0.x), int(at0.y))
	var hi1: Color = highlighted_image.get_pixel(int(at1.x), int(at1.y))

	var redness0: float = (hi0.r - none0.r) - maxf(hi0.g - none0.g, hi0.b - none0.b)
	var redness1: float = (hi1.r - none1.r) - maxf(hi1.g - none1.g, hi1.b - none1.b)
	print("detach redness: r2s0=%.4f r2s1=%.4f" % [redness0, redness1])
	_check(redness0 > 0.05, "Selecting r2s0 reddens its own hub (%.4f)" % redness0)
	_check(absf(redness1) < 0.05, "Selecting r2s0 does not redden r2s1's cluster (%.4f)" % redness1)
	_control("selecting nothing leaves no red highlight there", not (absf((none0.r - none0.r)) > 0.05))
	renderer.queue_free()
	await process_frame

	# --- (c) every ship in a staged root draws something ---------------------------------------
	# Compared against a same-PanelContainer tile with NO ship (its renderer already hidden by
	# `set_entry`'s own null-ship path), so a themed panel background common to every tile cannot
	# read as "drew something" on its own.
	var staged: Array[String] = ["boss", "drone", "irregular", "player_t3", "radial_elite"]
	var tile_position: Vector2 = Vector2(50, 50)
	var stage_rect: Rect2i = Rect2i(Vector2i(tile_position + Vector2(10, 10)), Vector2i(GalleryTile.STAGE_SIZE) - Vector2i(20, 20))

	var blank_tile: GalleryTile = GalleryTile.new()
	root.add_child(blank_tile)
	blank_tile.position = tile_position
	blank_tile.size = Vector2(GalleryTile.STAGE_SIZE.x, 250)
	blank_tile.set_entry({"id": "empty", "name": "Empty", "ship": null, "footprint": 150.0}, false)
	var blank_tile_image: Image = await _capture()

	var drew_something: bool = true
	for name: String in staged:
		var tile: GalleryTile = GalleryTile.new()
		root.add_child(tile)
		tile.position = tile_position
		tile.size = Vector2(GalleryTile.STAGE_SIZE.x, 250)
		var entry: Dictionary = {"id": name, "name": name, "ship": _load(name), "footprint": 150.0}
		tile.set_entry(entry, false)
		tile.set_animating(true)
		var lit_image: Image = await _capture()
		var lit: float = _image_diff(lit_image, blank_tile_image, stage_rect)
		print("lit(%s)=%.5f" % [name, lit])
		if lit < 0.02: drew_something = false
		tile.queue_free()
		await process_frame

	# Negative control: the same non-empty ship, but with its renderer node explicitly hidden,
	# reads no differently from the genuinely empty tile above.
	var hidden_tile: GalleryTile = GalleryTile.new()
	root.add_child(hidden_tile)
	hidden_tile.position = tile_position
	hidden_tile.size = Vector2(GalleryTile.STAGE_SIZE.x, 250)
	hidden_tile.set_entry({"id": "boss", "name": "boss", "ship": _load("boss"), "footprint": 150.0}, false)
	hidden_tile._renderer.visible = false
	var hidden_image: Image = await _capture()
	var hidden_lit: float = _image_diff(hidden_image, blank_tile_image, stage_rect)
	print("lit(hidden)=%.5f" % hidden_lit)
	hidden_tile.queue_free()

	_check(drew_something, "Every staged ship's tile draws something (over the empty-tile baseline)")
	_control("a tile with its renderer hidden reads as background", hidden_lit < 0.02)

	print("Gallery rendering: failures=%d, controls %d/%d" % [failures, controls_caught, controls_total])
	quit(1 if failures or controls_caught != controls_total else 0)
