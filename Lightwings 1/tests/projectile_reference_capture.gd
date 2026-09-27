extends SceneTree
## -- --width=1280 --height=800 --fps=10 --seconds=6
const ReferenceRange = preload("res://scripts/combat/projectile_reference_range.gd")
var width: int = 1280
var height: int = 800
var fps: int = 10
var seconds: float = 6.0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="): width = arg.trim_prefix("--width=").to_int()
		elif arg.begins_with("--height="): height = arg.trim_prefix("--height=").to_int()
		elif arg.begins_with("--fps="): fps = arg.trim_prefix("--fps=").to_int()
		elif arg.begins_with("--seconds="): seconds = arg.trim_prefix("--seconds=").to_float()
	if DisplayServer.get_name() == "headless":
		push_error("Projectile reference capture requires the production GPU renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	var view := SubViewport.new()
	view.size = Vector2i(width, height)
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background := ColorRect.new()
	background.color = Color("050507")
	background.size = Vector2(width, height)
	view.add_child(background)
	var fixture := ReferenceRange.new()
	var zoom: float = minf(float(width - 100) / 680.0, float(height - 210) / 316.0)
	fixture.position = (Vector2(width, height) - Vector2(680, 316) * zoom) * 0.5 + Vector2(0, 20)
	fixture.scale = Vector2.ONE * zoom
	view.add_child(fixture)
	fixture.set_physics_process(false)
	var title := Label.new()
	title.text = "LIGHTSHIP / PROJECTILE RANGE"
	title.position = Vector2(42, 30)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("e5e3da"))
	view.add_child(title)
	var caption := Label.new()
	caption.position = Vector2(42, height - 60)
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color("9c9a92"))
	view.add_child(caption)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(1280, 800)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(preview)
	var output: String = "res://artifacts/living-ships/projectiles-%dx%d" % [width, height]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var records: Array = []
	var tick: int = 0
	var frames: int = roundi(seconds * fps) + 1
	var failures: int = 0
	for frame: int in range(frames):
		var at: int = roundi(float(frame) * 60.0 / fps)
		fixture.friendly = float(frame) / fps >= seconds * 0.5
		while tick <= at:
			fixture.advance(1.0 / 60.0)
			tick += 1
		for index: int in fixture.pool.active_indices: fixture.pool.factions[index] = 0 if fixture.friendly else 1
		fixture.canvas.sync_pool(fixture.pool)
		fixture.queue_redraw()
		caption.text = "%05.2f s  ·  %s  ·  actual pooled bodies, ribbons, impacts and beam renderer" % [float(frame) / fps, "friendly centre pip / beam collar" if fixture.friendly else "weapon type colours"]
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var source: Image = view.get_texture().get_image()
		var encoded := Image.create(width, height, false, Image.FORMAT_RGB8)
		for y: int in range(height):
			for x: int in range(width): encoded.set_pixel(x, y, source.get_pixel(x, y).linear_to_srgb())
		var name: String = "frame_%03d.png" % frame
		if encoded.save_png(ProjectSettings.globalize_path(output.path_join(name))) != OK: failures += 1
		records.append({"frame":name, "tick":at, "seconds":float(frame)/fps})
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"width":width, "height":height, "fps":fps, "seconds":seconds, "frames":records, "failures":failures, "source":"Production CombatCanvas, projectile GPU bodies/ribbons, CombatFX and continuous beam path; deterministic isolated HTML reference trajectories."}, "\t"))
	print("PROJECTILE REFERENCE CAPTURE: %d frames, %d failures" % [frames, failures])
	quit(1 if failures else 0)
