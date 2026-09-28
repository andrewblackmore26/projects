extends SceneTree
## Modernization M14, in a real window: the map lattice and the circular minimap, captured at
## 1920x1080 and 1280x800 (fresh level, mid-exploration, zoomed in, boss revealed; the HUD with its
## minimap) into artifacts/m14/ for review, plus three pixel instruments:
## - FILL: an explored node's centre reads its element colour and an unexplored node's centre stays
##   dark (control: a point between two nodes read as the explored node);
## - CLIP: the minimap panel's pixels outside its circle are identical with the minimap shown and
##   hidden (control: primitives built for twice the clip radius, which reach the corners);
## - SCREEN: every capture is of the screen that was built (the focus-out pause lesson).
const Harness = preload("res://tests/support/harness.gd")
const STEP: float = 1.0 / 60.0
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 800)]

var h := Harness.new("MAP VIEW RENDER")
var out_dir: String = ProjectSettings.globalize_path("res://artifacts/m14")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_move_to_foreground()
	for size: Vector2i in SIZES:
		for scene: String in ["fresh", "mid", "zoom", "boss"]:
			await _map(size, scene)
		await _minimap(size)
	h.finish(self)

func _descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in node.get_children():
		nodes.append(child)
		nodes.append_array(_descendants(child))
	return nodes

func _new_app(size: Vector2i) -> Node:
	root.size = size
	SaveService.storage_root = "user://map-render-%d" % Time.get_ticks_usec()
	seed(1414)
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	return app

## Walks the run through the lattice: `steps` random rail steps (mid) or straight at the boss
## until beside it, then reveals the boss node (boss).
func _explore(app: Node, scene: String) -> void:
	var campaign: CampaignState = app.campaign
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	if scene in ["mid", "zoom"]:
		for i: int in range(34):
			var dirs: Array[Vector2i] = campaign.neighbours_of(campaign.current_sector)
			campaign.on_enter(campaign.current_sector + dirs[rng.randi() % dirs.size()])
	elif scene == "boss":
		var boss: Vector2i = campaign.boss_coord()
		while CampaignState.ring(boss - campaign.current_sector) > 1:
			var delta: Vector2i = boss - campaign.current_sector
			campaign.on_enter(campaign.current_sector + Vector2i(signi(delta.x), signi(delta.y)))
			for dir: Vector2i in campaign.neighbours_of(campaign.current_sector):
				if rng.randf() < 0.3: campaign.discover(campaign.current_sector + dir)
		campaign.discover(boss)

## The window pixel of a point in `control`'s local space.
func _pixel(control: Control, local: Vector2) -> Vector2i:
	var at: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
	return Vector2i(roundi(at.x), roundi(at.y))

func _grab(name: String) -> Image:
	for i: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var raw: Image = root.get_texture().get_image()
	h.check(raw.get_size() == root.size, "%s: the grab is the window's %s (got %s)" % [name, root.size, raw.get_size()])
	var encoded := Image.create(raw.get_width(), raw.get_height(), false, Image.FORMAT_RGB8)
	for y: int in range(raw.get_height()):
		for x: int in range(raw.get_width()):
			encoded.set_pixel(x, y, raw.get_pixel(x, y).linear_to_srgb() if root.use_hdr_2d else raw.get_pixel(x, y))
	encoded.save_png(out_dir.path_join(name + ".png"))
	return encoded

func _map(size: Vector2i, scene: String) -> void:
	var app: Node = _new_app(size)
	await process_frame
	app._new_game(false)
	app.line_queue.clear()
	app.combat.set_physics_process(false)
	app.combat._physics_process(STEP)
	_explore(app, scene)
	app._show_map()
	var screen: MapScreen = app.screen_router.stack.back().screen
	var view: MapScreen.MapView = screen.view
	if scene == "zoom": view.zoom_at(1.8, view.to_view(Vector2(view.focus)))
	# Let the entrance and the whole reveal finish. The reveal clock starts at its first tween step,
	# and the first frames of a process can take over a second (pipeline compilation), so wait on
	# the clock itself, then on the entrance.
	var frames: int = 0
	while view.elapsed() < view.reveal_end + MapScreen.MapView.REVEAL_FADE and frames < 600:
		await process_frame
		frames += 1
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.2, true, false, true).timeout
	var name: String = "map_%s_%dx%d" % [scene, size.x, size.y]
	h.check(view.elapsed() >= view.reveal_end + MapScreen.MapView.REVEAL_FADE, "%s: precondition, the reveal has finished (%.3f of %.3f s)" % [name, view.elapsed(), view.reveal_end + MapScreen.MapView.REVEAL_FADE])
	var image: Image = await _grab(name)
	h.check(app.overlay_kind == "map", "%s: the capture is of the map ('%s')" % [name, app.overlay_kind])
	if scene == "mid" or scene == "boss":
		# FILL: an explored node other than the current one, and an unexplored one.
		var explored := Vector2i(1 << 20, 0)
		var dark := Vector2i(1 << 20, 0)
		for cell: MinimapModel.Cell in view.model.cells:
			if cell.current or cell.is_boss: continue
			if cell.explored and explored.x == 1 << 20 and CampaignState.ring(cell.coord - view.model.current_coord) > 1: explored = cell.coord
			if not cell.explored and dark.x == 1 << 20 and CampaignState.ring(cell.coord - view.model.current_coord) > 2: dark = cell.coord
		var ink: Color = MapScreen.sector_color(app.campaign, explored, true)
		var got: Color = image.get_pixelv(_pixel(view, view.to_view(Vector2(explored))))
		# Between nodes and off every rail (the diagonals cross at the cell's middle).
		var off: Color = image.get_pixelv(_pixel(view, view.to_view(Vector2(explored) + Vector2(0.5, 0.2))))
		var unlit: Color = image.get_pixelv(_pixel(view, view.to_view(Vector2(dark))))
		print("measure: %s node %s ink %s reads %s; between nodes %s; unexplored %s reads %s" % [name, explored, ink.to_html(false), got.to_html(false), off.to_html(false), dark, unlit.to_html(false)])
		h.check(_close(got, ink), "%s: explored node %s is filled with its element colour (%s vs %s)" % [name, explored, got.to_html(false), ink.to_html(false)])
		h.check(unlit.get_luminance() < 0.12, "%s: unexplored node %s stays dark (luminance %.3f)" % [name, dark, unlit.get_luminance()])
		h.control("%s: a point between nodes read as the explored node" % name, not _close(off, ink))
	await _free(app)

## Same hue family and at least 60% of the colour's brightness (the fill is 92% over the field).
func _close(got: Color, ink: Color) -> bool:
	return absf(got.r - ink.r) + absf(got.g - ink.g) + absf(got.b - ink.b) < 0.3

func _minimap(size: Vector2i) -> void:
	var app: Node = _new_app(size)
	await process_frame
	app._new_game(false)
	app.line_queue.clear()
	app.combat.set_physics_process(false)
	app.combat._physics_process(STEP)
	_explore(app, "mid")
	app._refresh_hud()
	for node: Node in _descendants(root):
		node.set_process(false)
		node.set_physics_process(false)
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.2, true, false, true).timeout
	var minimap: Minimap = app.hud_view.minimap
	var panel: Control = minimap.minimap
	var name: String = "hud_minimap_%dx%d" % [size.x, size.y]
	var shown: Image = await _grab(name)
	h.check(app.overlay_kind.is_empty() and app.hud.visible, "%s: the capture is of the HUD" % name)
	var top_left: Vector2i = _pixel(panel, Vector2.ZERO)
	var bottom_right: Vector2i = _pixel(panel, Minimap.SIZE)
	var crop: Image = shown.get_region(Rect2i(top_left, bottom_right - top_left))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(out_dir.path_join(name + "_crop.png"))
	panel.visible = false
	var hidden: Image = await _grab(name + "_hidden")
	panel.visible = true
	var outside: int = _corner_diff(shown, hidden, panel)
	h.check(outside == 0, "%s: no pixel of the panel outside the circle changes when the minimap draws (%d changed)" % [name, outside])
	# Control: the cache swapped for primitives built at twice the clip radius (kept until the key
	# changes, which nothing does in a frozen frame).
	minimap._cache = Minimap.primitives(app.campaign, Minimap.CLIP_RADIUS * 2.0)
	panel.queue_redraw()
	var sabotaged: Image = await _grab(name + "_control")
	var leaked: int = _corner_diff(sabotaged, hidden, panel)
	h.control("%s: primitives for twice the clip radius (%d corner pixels changed)" % [name, leaked], leaked > 0)
	await _free(app)

## Pixels of the panel more than 2 px (window px) outside the circle that differ between a and b.
func _corner_diff(a: Image, b: Image, panel: Control) -> int:
	var center: Vector2i = _pixel(panel, Minimap.CENTER)
	var radius: float = float(_pixel(panel, Minimap.CENTER + Vector2(Minimap.CLIP_RADIUS, 0)).x - center.x) + 2.0
	var top_left: Vector2i = _pixel(panel, Vector2.ZERO)
	var bottom_right: Vector2i = _pixel(panel, Vector2(Minimap.SIZE.x, Minimap.CENTER.y + Minimap.CLIP_RADIUS))
	var changed: int = 0
	for y: int in range(top_left.y, bottom_right.y):
		for x: int in range(top_left.x, bottom_right.x):
			if Vector2(x, y).distance_to(Vector2(center)) <= radius: continue
			if a.get_pixel(x, y) != b.get_pixel(x, y): changed += 1
	return changed

func _free(app: Node) -> void:
	await app._stop_audio()
	app.queue_free()
	await process_frame
	await process_frame
