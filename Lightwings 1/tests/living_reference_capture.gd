extends SceneTree
## Deterministic reference reel using the production world, pose, renderer and detachment.
## -- --width=1280 --height=800 --fps=8 --seconds=16
var width: int = 1280
var height: int = 800
var fps: int = 8
var seconds: float = 16.0
var view: SubViewport
var world: CombatWorld
var elite: Dictionary
var chain: Dictionary
var clock_label: Label
var failures: int = 0
var output: String

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="): width = arg.trim_prefix("--width=").to_int()
		elif arg.begins_with("--height="): height = arg.trim_prefix("--height=").to_int()
		elif arg.begins_with("--fps="): fps = arg.trim_prefix("--fps=").to_int()
		elif arg.begins_with("--seconds="): seconds = arg.trim_prefix("--seconds=").to_float()
	if DisplayServer.get_name() == "headless":
		push_error("Reference capture needs a GPU renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	output = "res://artifacts/living-ships/reference-%dx%d" % [width,height]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_build()
	if elite.is_empty() or chain.is_empty():
		quit(1)
		return
	# Let the historical tail settle on the head's path before the first reviewed frame.
	for tick: int in range(600): _step(tick, false)
	var frame_count: int = roundi(seconds * fps) + 1
	var tick: int = 600
	var records: Array = []
	for frame: int in range(frame_count):
		var at: int = 600 + roundi(float(frame) * 60.0 / fps)
		while tick <= at:
			_step(tick, tick == 600 + roundi(seconds * 0.7 * 60.0))
			tick += 1
		clock_label.text = "%05.2f s  /  %05.2f s" % [float(frame)/fps,seconds]
		for actor: Dictionary in [elite,chain]:
			var renderer: ShipRenderer = actor.renderer
			renderer.position = actor.pos
			renderer.rotation = Vector2(actor.aim).angle()+PI/2.0
			renderer.hidden_part_ids = actor.hidden_ids
			renderer.set_motion_tick(at)
			renderer._process(0)
			for index: int in range(actor.rig.ids.size()):
				if not bool(actor.part_attached[index]): continue
				var centre: Vector2 = world._part_position(actor,index)*world.scale
				var extent: Vector2 = Vector2.ONE*(actor.rig.radius[index]*world.scale.x+2.0)
				if not Rect2(0,0,width,height).encloses(Rect2(centre-extent,extent*2.0)):
					failures += 1
					push_error("Reference clipped at tick%d: %s" % [at,actor.rig.ids[index]])
		world.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var name: String = "frame_%03d.png" % frame
		var source: Image = view.get_texture().get_image()
		var encoded := Image.create(width,height,false,Image.FORMAT_RGB8)
		for y: int in range(height):
			for x: int in range(width): encoded.set_pixel(x,y,source.get_pixel(x,y).linear_to_srgb())
		if encoded.save_png(ProjectSettings.globalize_path(output.path_join(name))) != OK: failures += 1
		records.append({"frame":name,"tick":at,"seconds":float(frame)/fps})
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"width":width,"height":height,"fps":fps,"seconds":seconds,"frames":records,"failures":failures,"source":"Production ShipRenderer, ShipMotion and CombatWorld detachment; HTML numerical reference profiles."},"\t"))
	world._clear_encounter()
	print("LIVING REFERENCE CAPTURE: %d frames, %d failures" % [frame_count,failures])
	quit(1 if failures else 0)

func _label(text: String, at: Vector2, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",colour)
	view.add_child(label)
	return label

func _build() -> void:
	view = SubViewport.new()
	view.size = Vector2i(width,height)
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.size = Vector2(width,height)
	view.add_child(background)
	var scale_factor: float = float(height)/800.0
	_label("LIGHTSHIP / LIVING MACHINES",Vector2(36,24)*scale_factor,roundi(25*scale_factor),VisualStyle.TEXT)
	_label("Orbiting fans · independent rim lights · historical following · individual breakup",Vector2(36,62)*scale_factor,roundi(14*scale_factor),VisualStyle.MUTED)
	_label("ORBITING ELITE",Vector2(36,121)*scale_factor,roundi(13*scale_factor),VisualStyle.ACCENT)
	_label("FOLLOWING CHAIN",Vector2(36,473)*scale_factor,roundi(13*scale_factor),VisualStyle.GREEN)
	clock_label = _label("",Vector2(36,758)*scale_factor,roundi(14*scale_factor),VisualStyle.MUTED)
	world = CombatWorld.new()
	world.visuals_enabled = false
	view.add_child(world)
	world.set_physics_process(false)
	world.scale = Vector2.ONE*scale_factor
	world.actors_by_id.clear()
	world._fx_rng.seed = 814204
	world.visuals_enabled = true
	var centre: float = float(width)/scale_factor*0.5
	elite = _actor("orbiting_elite",1,Vector2(centre,280))
	chain = _actor("following_chain",2,Vector2(centre,555))
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(1280,800)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(preview)

func _actor(fixture: String, id: int, at: Vector2) -> Dictionary:
	var errors := PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/living_ships/%s.json" % fixture,errors)
	if ship == null or not errors.is_empty():
		push_error("Invalid reference fixture: " + str(errors))
		return {}
	ShipCatalog.refresh(ship)
	var actor: Dictionary = world._make_actor(id,ship.element,3,at,1,false)
	actor.aim = Vector2.UP
	world._configure_actor(actor,ship,true)
	world.actors_by_id[id] = actor
	world.enemies.append(actor)
	world._update_visual(actor)
	actor.renderer.set_process(false)
	return actor

func _step(tick: int, sever: bool) -> void:
	world.tick = tick
	world.elapsed = float(tick)/60.0
	var t: float = world.elapsed
	var centre: float = float(width)/world.scale.x*0.5
	chain.pos = Vector2(centre+cos(t*0.5)*90.0,555+sin(t*0.9)*46.0)
	# The reference has no aiming target: show the authored outward-facing weapon fans.
	ShipMotion.step(elite.rig,elite.pose,tick,elite.pos,0.0,elite.part_attached)
	elite.renderer.external_pose = elite.pose
	world._step_motion(chain)
	if tick % 96 == 0: world._emit_shot(elite,"rocket_launcher",elite.pos)
	world._update_effects(1.0/60.0)
	if sever: world._destroy_part(chain,chain.rig.index_of("c4"),world.player)
	world._update_debris(1.0/60.0)
