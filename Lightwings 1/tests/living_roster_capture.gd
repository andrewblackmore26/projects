extends SceneTree
## Production roster evidence. Requires the exclusive GPU capture lane.
## -- --width=1280 --height=800 --fps=8 --seconds=8
## -- --width=1920 --height=1080 --contact-sheets
## Motion: four full-size pages, exact 60Hz poses and a moving historical-follow head.
## Contact sheets: every one of the 146 manifest IDs, twelve per page, plus coverage metadata.

const OUTPUT: String = "res://artifacts/living-ships"
const PADDING: float = 24.0
const WARMUP: int = 600
var width: int = 1280
var height: int = 800
var fps: int = 8
var seconds: float = 8.0
var contact_sheets: bool = false
var bosses_only: bool = false
var requested_page: String = ""
var view: SubViewport
var page_node: Node2D
var subjects: Array[Dictionary] = []
var clock_label: Label
var failures: int = 0
var output: String
var ui_scale: float = 1.0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="): width = arg.trim_prefix("--width=").to_int()
		elif arg.begins_with("--height="): height = arg.trim_prefix("--height=").to_int()
		elif arg.begins_with("--fps="): fps = arg.trim_prefix("--fps=").to_int()
		elif arg.begins_with("--seconds="): seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--page="): requested_page = arg.trim_prefix("--page=")
		elif arg == "--contact-sheets": contact_sheets = true
		elif arg == "--bosses-only": bosses_only = true
	if DisplayServer.get_name() == "headless" or width < 640 or height < 480 or fps < 1 or fps > 60 or seconds <= 0:
		push_error("Living roster capture requires a GPU, valid dimensions, 1..60fps and a positive duration.")
		quit(1)
		return
	ui_scale = float(height) / 800.0
	output = OUTPUT.path_join(("contact-" if contact_sheets else "bosses-" if bosses_only else "roster-") + "%dx%d" % [width,height])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_build_view()
	var records: Array[Dictionary] = []
	if contact_sheets:
		records = await _capture_contacts()
	else:
		for page: Dictionary in _motion_pages():
			if requested_page != "" and requested_page != str(page.id): continue
			records.append(await _capture_motion_page(page))
		if records.is_empty():
			failures += 1
			push_error("No motion page matched --page=" + requested_page)
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if manifest == null:
		failures += 1
	else:
		manifest.store_string(JSON.stringify({"width":width,"height":height,"fps":fps,"seconds":seconds,"padding_pixels":PADDING,"warmup_ticks":WARMUP,"pages":records,"failures":failures,"mode":"all_manifest_contact_sheets" if contact_sheets else "moving_production_roster","source":"Production ShipCatalog, ShipMotion and ShipRenderer external poses; motion bounds checked at every 60Hz simulation tick, not only exported frames."}, "\t"))
	print("LIVING ROSTER CAPTURE: %d pages, %d failures, %s" % [records.size(),failures,output])
	quit(1 if failures else 0)

func _build_view() -> void:
	root.size = Vector2i(1280,800)
	view = SubViewport.new()
	view.size = Vector2i(width,height)
	view.use_hdr_2d = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	VisualStyle.configure_glow(environment)
	for level: int in range(7): environment.set_glow_level(level,0.8 if level == 0 else 0.0)
	var holder := WorldEnvironment.new()
	holder.environment = environment
	view.add_child(holder)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(1280,800)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(preview)

func _new_page(title: String, subtitle: String) -> void:
	if is_instance_valid(page_node): page_node.free()
	subjects.clear()
	page_node = Node2D.new()
	view.add_child(page_node)
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.size = Vector2(width,height)
	page_node.add_child(background)
	_label(title,Vector2(36,24)*ui_scale,25,VisualStyle.TEXT)
	_label(subtitle,Vector2(36,63)*ui_scale,13,VisualStyle.MUTED)
	clock_label = _label("",Vector2(36*ui_scale,height-34*ui_scale),12,VisualStyle.MUTED)

func _label(text: String, at: Vector2, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",roundi(float(size)*ui_scale))
	label.add_theme_color_override("font_color",colour)
	page_node.add_child(label)
	return label

func _motion_pages() -> Array[Dictionary]:
	if bosses_only:
		# The main reel contains the largest boss. Cover each remaining boss too.
		var bosses: Array[String] = []
		var largest: String = _largest("boss")
		for entry: Dictionary in RailRoster.manifest():
			if str(entry.get("archetype","")) == "boss" and str(entry.id) != largest: bosses.append(str(entry.id))
		var pages: Array[Dictionary] = []
		for offset: int in range(0,bosses.size(),2):
			pages.append({"id":"boss-pair-%02d" % (offset/2+1),"title":"BOSS ANATOMY / FULL MOTION","ids":bosses.slice(offset,mini(offset+2,bosses.size()))})
		return pages
	var players: Array[String] = []
	for family: String in ShipCatalog.FAMILIES: players.append("player_lightning_t3_" + family)
	return [
		{"id":"01-player-compact-standard","title":"PLAYER FAMILIES / COMPACT + STANDARD A","ids":players.slice(0,2)},
		{"id":"02-player-standard-heavy","title":"PLAYER FAMILIES / STANDARD B + HEAVY","ids":players.slice(2,4)},
		{"id":"03-irregular-boss","title":"ASYMMETRIC ELITE + LARGEST BOSS","ids":[_largest("irregular_elite"),_largest("boss")]},
		{"id":"04-following-chain","title":"FOLLOWING CHAIN / MOVEMENT RESPONSE","ids":["enemy_chain_corruption_t4"]},
	]

func _largest(archetype: String) -> String:
	var largest: String = ""
	var radius: float = -1.0
	for entry: Dictionary in RailRoster.manifest():
		if str(entry.get("archetype","")) != archetype: continue
		var ship: ShipDefinition = ShipCatalog.get_ship(str(entry.id))
		if ship == null: continue
		var reach: float = ShipPreview.animated_radius(ship)
		if reach > radius:
			radius = reach
			largest = ship.id
	return largest

func _add_subject(id: String, panel: Rect2, contact: bool = false) -> Dictionary:
	var ship: ShipDefinition = ShipCatalog.get_ship(id)
	if ship == null:
		failures += 1
		push_error("Roster capture cannot load " + id)
		return {}
	var backdrop := ColorRect.new()
	backdrop.color = VisualStyle.PANEL
	backdrop.position = panel.position
	backdrop.size = panel.size
	page_node.add_child(backdrop)
	var label_size: int = 10 if contact else 13
	_label(id,panel.position+Vector2(12,12)*ui_scale,label_size,VisualStyle.ACCENT)
	_label("T%d · %s · geometry %d" % [ship.tier,ship.family if ship.is_player else ship.archetype,ship.geometry_revision],panel.position+Vector2(12,panel.size.y/ui_scale-24)*ui_scale,label_size-1,VisualStyle.MUTED)
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose := ShipMotion.ShipPose.new(rig)
	var renderer := ShipRenderer.new()
	page_node.add_child(renderer)
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.external_pose = pose
	var area := Rect2(panel.position+Vector2(PADDING,40*ui_scale),panel.size-Vector2(PADDING*2,76*ui_scale))
	var subject: Dictionary = {"ship":ship,"rig":rig,"pose":pose,"renderer":renderer,"area":area,"head":Vector2.ZERO,"bounds_failures":0}
	var bounds: Rect2
	if contact:
		var radius: float = ShipPreview.animated_radius(ship)
		bounds = Rect2(Vector2.ONE*-radius,Vector2.ONE*radius*2.0)
	else:
		bounds = _measure_motion_bounds(subject)
	var fitting_area: Rect2 = area.grow(-2.0)
	renderer.visual_scale = minf(fitting_area.size.x/maxf(1.0,bounds.size.x),fitting_area.size.y/maxf(1.0,bounds.size.y))
	subject.origin = area.get_center()-bounds.get_center()*renderer.visual_scale
	subject.bounds = bounds
	renderer.position = subject.origin
	subjects.append(subject)
	return subject

func _head_for(rig: ShipMotion.ShipRig, tick: int, moving: bool) -> Vector2:
	if not moving or rig.follow_indices.is_empty(): return Vector2.ZERO
	var time: float = float(tick)/60.0
	return Vector2(cos(time*0.5)*90.0,sin(time*0.9)*46.0)

func _advance(subject: Dictionary, tick: int, moving: bool, check_bounds: bool = false) -> void:
	var rig: ShipMotion.ShipRig = subject.rig
	var pose: ShipMotion.ShipPose = subject.pose
	var time: float = float(tick)/60.0
	for index: int in rig.aim_indices: pose.aim_angle[index] = -PI*0.5 + sin(time*TAU/5.5)*0.8
	var head: Vector2 = _head_for(rig,tick,moving)
	ShipMotion.step(rig,pose,tick,head)
	subject.head = head
	if check_bounds: _check_bounds(subject,tick)

func _measure_motion_bounds(subject: Dictionary) -> Rect2:
	var probe: Dictionary = {"rig":subject.rig,"pose":ShipMotion.ShipPose.new(subject.rig)}
	var bounds := Rect2()
	var first: bool = true
	var rig: ShipMotion.ShipRig = subject.rig
	for tick: int in range(WARMUP+roundi(seconds*60.0)+1):
		_advance(probe,tick,true)
		if tick < WARMUP: continue
		for index: int in range(rig.ids.size()):
			var centre: Vector2 = probe.pose.local[index]+Vector2(probe.head)
			var extent: Vector2 = Vector2.ONE*rig.radius[index]
			var part := Rect2(centre-extent,extent*2.0)
			bounds = part if first else bounds.merge(part)
			first = false
	return bounds

func _check_bounds(subject: Dictionary, tick: int) -> void:
	var rig: ShipMotion.ShipRig = subject.rig
	var scale_factor: float = subject.renderer.visual_scale
	var area: Rect2 = subject.area
	for index: int in range(rig.ids.size()):
		var centre: Vector2 = Vector2(subject.origin)+(subject.pose.local[index]+Vector2(subject.head))*scale_factor
		var extent: Vector2 = Vector2.ONE*(rig.radius[index]*scale_factor+1.5)
		if not area.encloses(Rect2(centre-extent,extent*2.0)):
			failures += 1
			subject.bounds_failures += 1
			if int(subject.bounds_failures) == 1: push_error("%s clips at tick%d (%s)" % [subject.ship.id,tick,rig.ids[index]])

func _present(subject: Dictionary, tick: int) -> void:
	var renderer: ShipRenderer = subject.renderer
	renderer.position = Vector2(subject.origin)+Vector2(subject.head)*renderer.visual_scale
	renderer.set_motion_tick(tick)
	renderer.animation_time = float(tick)/60.0
	renderer._process(0.0)

func _metadata(subject: Dictionary) -> Dictionary:
	var bounds: Rect2 = subject.bounds
	return {"id":subject.ship.id,"geometry_revision":subject.ship.geometry_revision,"circles":subject.rig.ids.size(),"lines":subject.rig.line_ids.size(),"follow_links":subject.rig.follow_indices.size(),"scale":subject.renderer.visual_scale,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"bounds_failures":subject.bounds_failures}

func _capture_motion_page(page: Dictionary) -> Dictionary:
	_new_page("LIGHTSHIP / " + str(page.title),"Production hulls · every simulation tick checked · 24 px fixed side padding")
	var directory: String = output.path_join(str(page.id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var margin: float = 36.0*ui_scale
	var gap: float = 24.0*ui_scale
	var count: int = page.ids.size()
	var panel_width: float = (width-margin*2.0-gap*(count-1))/count
	for index: int in range(count):
		_add_subject(str(page.ids[index]),Rect2(margin+index*(panel_width+gap),112*ui_scale,panel_width,height-174*ui_scale))
	for tick: int in range(WARMUP):
		for subject: Dictionary in subjects: _advance(subject,tick,true)
	var next_tick: int = WARMUP
	var frames: Array[Dictionary] = []
	for frame: int in range(roundi(seconds*fps)+1):
		var tick: int = WARMUP+roundi(float(frame)*60.0/fps)
		while next_tick <= tick:
			for subject: Dictionary in subjects: _advance(subject,next_tick,true,true)
			next_tick += 1
		for subject: Dictionary in subjects: _present(subject,tick)
		clock_label.text = "%05.2f s / %05.2f s · tick%d" % [float(frame)/fps,seconds,tick]
		var filename: String = "frame_%03d.png" % frame
		await _save_frame(directory.path_join(filename))
		frames.append({"frame":str(page.id)+"/"+filename,"tick":tick,"seconds":float(frame)/fps})
	var metadata: Array[Dictionary] = []
	for subject: Dictionary in subjects: metadata.append(_metadata(subject))
	return {"id":page.id,"subjects":metadata,"frames":frames}

func _capture_contacts() -> Array[Dictionary]:
	var entries: Array[Dictionary] = RailRoster.manifest()
	var unique: Dictionary = {}
	for entry: Dictionary in entries: unique[str(entry.id)] = true
	if entries.size() != 146 or unique.size() != 146:
		failures += 1
		push_error("Expected exactly 146 distinct roster manifest IDs")
	var pages: Array[Dictionary] = []
	for offset: int in range(0,entries.size(),12):
		var page_index: int = offset/12
		_new_page("LIGHTSHIP / COMPLETE ROSTER","Manifest hulls %d–%d of %d · production geometry and materials" % [offset+1,mini(offset+12,entries.size()),entries.size()])
		var margin: float = 36.0*ui_scale
		var gap: float = 12.0*ui_scale
		var cell := Vector2((width-margin*2-gap*3)/4.0,(height-168*ui_scale-gap*2)/3.0)
		for local_index: int in range(mini(12,entries.size()-offset)):
			var at := Vector2(margin+(local_index%4)*(cell.x+gap),106*ui_scale+(local_index/4)*(cell.y+gap))
			var subject: Dictionary = _add_subject(str(entries[offset+local_index].id),Rect2(at,cell),true)
			if subject.is_empty(): continue
			for tick: int in range(WARMUP+1): _advance(subject,tick,false)
			_check_bounds(subject,WARMUP)
			_present(subject,WARMUP)
		clock_label.text = "Page %d / %d · all 146 manifest IDs recorded in manifest.json" % [page_index+1,ceili(float(entries.size())/12.0)]
		var filename: String = "page_%02d.png" % (page_index+1)
		await _save_frame(output.path_join(filename))
		var metadata: Array[Dictionary] = []
		for subject: Dictionary in subjects: metadata.append(_metadata(subject))
		pages.append({"page":page_index+1,"image":filename,"subjects":metadata})
	return pages

func _save_frame(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var source: Image = view.get_texture().get_image()
	var encoded := Image.create(width,height,false,Image.FORMAT_RGB8)
	for y: int in range(height):
		for x: int in range(width): encoded.set_pixel(x,y,source.get_pixel(x,y).linear_to_srgb())
	if encoded.save_png(ProjectSettings.globalize_path(path)) != OK: failures += 1
