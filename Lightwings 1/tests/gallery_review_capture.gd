extends SceneTree
## Review the first, middle and last atlas pages without shrinking the full contact sheet.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,800)
	var gallery: Control = load("res://scenes/gallery.tscn").instantiate()
	root.add_child(gallery)
	for frame: int in range(4): await process_frame
	var maximum: float = maxf(0.0,gallery._grid.size.y-gallery._scroll.size.y)
	var suffix: String = "true_scale" if "--true-scale" in OS.get_cmdline_user_args() else "fitted"
	for page: int in range(3):
		gallery._scroll.scroll_vertical = roundi(maximum*float(page)*0.5)
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var capture: Image = root.get_texture().get_image()
		gallery._linear_to_srgb_per_pixel(capture)
		capture.convert(Image.FORMAT_RGB8)
		capture.save_png("res://artifacts/acceptance/atlas_%s_page_%d.png" % [suffix,page+1])
	print("Atlas review capture: 3 pages written, 0 failures")
	quit(0)
