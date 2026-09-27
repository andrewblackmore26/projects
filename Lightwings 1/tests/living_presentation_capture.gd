extends SceneTree
## Production menu/evolution/combat reels, with a fixed simulation clock and isolated saves.
var width: int = 1280
var height: int = 800
var fps: int = 8
var seconds: float = 4.0
var screen: String = "menu"
var app: Node
var failures: int = 0

func _initialize() -> void: _run.call_deferred()

func _descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in node.get_children():
		nodes.append(child)
		nodes.append_array(_descendants(child))
	return nodes

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="): width = arg.trim_prefix("--width=").to_int()
		elif arg.begins_with("--height="): height = arg.trim_prefix("--height=").to_int()
		elif arg.begins_with("--screen="): screen = arg.trim_prefix("--screen=")
		elif arg.begins_with("--seconds="): seconds = arg.trim_prefix("--seconds=").to_float()
	if DisplayServer.get_name() == "headless":
		push_error("Presentation capture requires a GPU")
		quit(1)
		return
	root.size = Vector2i(width,height)
	SaveService.storage_root = "user://living-presentation-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	for i: int in range(3): await process_frame
	if screen in ["evolution","combat"]:
		app._new_game(false)
		app._close_overlay()
		app.combat.set_physics_process(false)
		if screen == "evolution":
			app.combat.setup_player("lightning",3,1000,[],GameTuning.ARENA_CENTER)
			app.combat.absorption = {"lightning":300.0,"fire":100.0,"plasma":80.0}
			app._show_evolution()
		else:
			app.combat.benchmark(400)
			app.combat._fx_rng.seed = 814204
			app.combat.command.fire = true
			for tick: int in range(90): app.combat._physics_process(1.0/60.0)
		app._refresh_hud()
	elif screen == "options":
		app._show_options()
		seconds = 0.125
	for i: int in range(3): await process_frame
	var previews: Array[ShipPreview] = []
	for node: Node in _descendants(app):
		if node is ShipPreview:
			node.set_process(false)
			previews.append(node)
		elif node is ShipRenderer: node.set_process(false)
	var output: String = "res://artifacts/living-ships/%s-%dx%d" % [screen,width,height]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var frames: int = roundi(seconds*fps)+1
	var records: Array = []
	var tick: int = 0
	for frame: int in range(frames):
		var next_tick: int = roundi(float(frame)*60.0/fps)
		while tick < next_tick:
			for preview: ShipPreview in previews: preview._process(1.0/60.0)
			if screen == "combat":
				app.combat.command.aim = Vector2.from_angle(float(tick)/60.0*0.5)
				app.combat._physics_process(1.0/60.0)
			tick += 1
		if screen == "combat":
			app._refresh_hud()
			for actor: Dictionary in app.combat.actors_by_id.values():
				var renderer: ShipRenderer = actor.get("renderer")
				if is_instance_valid(renderer): renderer._process(0)
			app.compositor._process(0)
		for preview: ShipPreview in previews:
			if not preview.is_visible_in_tree(): continue
			if preview.auto_fit and preview.motion_radius*preview.renderer.visual_scale > minf(preview.size.x,preview.size.y)*0.5-preview.fit_margin+0.1:
				failures += 1
				push_error("Clipped %s preview at tick%d" % [screen,tick])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var raw: Image = root.get_texture().get_image()
		var encoded := Image.create(raw.get_width(),raw.get_height(),false,Image.FORMAT_RGB8)
		for y: int in range(raw.get_height()):
			for x: int in range(raw.get_width()):
				encoded.set_pixel(x,y,raw.get_pixel(x,y).linear_to_srgb() if root.use_hdr_2d else raw.get_pixel(x,y))
		var name: String = "frame_%03d.png" % frame
		if encoded.save_png(ProjectSettings.globalize_path(output.path_join(name))) != OK: failures += 1
		records.append({"frame":name,"seconds":float(frame)/fps,"tick":tick})
	var manifest := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"screen":screen,"width":width,"height":height,"fps":fps,"seconds":seconds,"frames":records,"failures":failures},"\t"))
	await app._stop_audio()
	print("LIVING PRESENTATION CAPTURE: %s, %d frames, %d failures" % [screen,frames,failures])
	quit(1 if failures else 0)
