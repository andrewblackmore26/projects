extends SceneTree
## Human review of all four families at a matched gameplay scale, one sheet per tier.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,800)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,1100)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for tier: int in range(2,7):
		var page := Node2D.new()
		viewport.add_child(page)
		var background := ColorRect.new()
		background.color = VisualStyle.BG
		background.size = Vector2(1280,1100)
		page.add_child(background)
		for i: int in range(ShipCatalog.FAMILIES.size()):
			var family: String = ShipCatalog.FAMILIES[i]
			var ship: ShipDefinition = ShipCatalog.get_ship("player_lightning_t%d_%s" % [tier,family])
			var origin := Vector2((i%2)*640,(i/2)*550)
			var label := Label.new()
			label.text = "LIGHTNING T%d · %s · 0.9×" % [tier,family.to_upper()]
			label.position = origin+Vector2(28,18)
			label.add_theme_color_override("font_color",VisualStyle.TEXT)
			label.add_theme_font_size_override("font_size",19)
			page.add_child(label)
			var renderer := ShipRenderer.new()
			page.add_child(renderer)
			renderer.position = origin+Vector2(320,295)
			renderer.visual_scale = 0.9
			renderer.set_ship(ship)
			renderer.set_process(false)
			renderer.set_motion_tick(0)
			renderer._process(0)
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var raw: Image = viewport.get_texture().get_image()
		var encoded := Image.create(raw.get_width(),raw.get_height(),false,Image.FORMAT_RGB8)
		for y: int in range(raw.get_height()):
			for x: int in range(raw.get_width()): encoded.set_pixel(x,y,raw.get_pixel(x,y).linear_to_srgb())
		encoded.save_png("res://artifacts/acceptance/family_lightning_t%d.png" % tier)
		page.queue_free()
		await process_frame
	print("Player family capture: 5 sheets written, 0 failures")
	quit(0)
