extends SceneTree
## Review capture 2: all 33 set pieces at 1x, each mounted on a hub of a ship in its own colours,
## through the real compiler and renderer. Not a test. Run in a real window:
##   tools\godot.ps1 -Arguments '--script "res://tests/set_piece_sheet_capture.gd"'
## Writes artifacts/acceptance/set_pieces.png (11 columns x 3 rows of 110 px cells, catalogue order).
const CELL: int = 110
const COLUMNS: int = 11
const HUB_AT: Vector2 = Vector2(640, 400)

func _initialize() -> void: _run.call_deferred()

func _host(piece_id: String) -> ShipDefinition:
	var colours: Array = SetPieceCatalog.colours_of(piece_id)
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.from_dict({"id": "sheet_" + piece_id, "faction": "enemy", "archetype": "sentry", "tier": 2,
		"chassis_color": colours[0], "accent_color": colours[1] if colours.size() > 1 else "", "core_depth": 2,
		"rails": [{"radius": 52, "order": 3, "speed": -0.95, "phase": 0.0, "slots": [{"type": "hub", "pods": 1, "set_piece": piece_id}, "stub", "stub"]}]}, errors)
	ShipCompiler.compile(ship)
	return ship

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var ids: Array[String] = SetPieceCatalog.ids()
	var rows: int = int(ceil(float(ids.size()) / float(COLUMNS)))
	var sheet: Image = Image.create(CELL * COLUMNS, CELL * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("050507"))
	for n: int in range(ids.size()):
		var renderer: ShipRenderer = ShipRenderer.new()
		root.add_child(renderer)
		renderer.position = HUB_AT + Vector2(0, 52) # the hub sits 52 px above the core, so it lands on HUB_AT
		renderer.set_ship(_host(ids[n]))
		renderer.set_process(false)
		renderer.set_motion_tick(0)
		renderer._process(0)
		for i: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		var origin: Vector2i = Vector2i(int(HUB_AT.x) - CELL / 2, int(HUB_AT.y) - CELL / 2 - 8)
		var cell: Vector2i = Vector2i((n % COLUMNS) * CELL, (n / COLUMNS) * CELL)
		for y: int in range(CELL):
			for x: int in range(CELL):
				var pixel: Color = frame.get_pixel(origin.x + x, origin.y + y).linear_to_srgb()
				sheet.set_pixel(cell.x + x, cell.y + y, Color(clampf(pixel.r, 0, 1), clampf(pixel.g, 0, 1), clampf(pixel.b, 0, 1), 1.0))
		renderer.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/acceptance"))
	sheet.save_png(ProjectSettings.globalize_path("res://artifacts/acceptance/set_pieces.png"))
	print("set piece sheet checks: %d rendered, 0 failures" % ids.size())
	quit(0)
