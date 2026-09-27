extends SceneTree
## Deterministic production-renderer motion reel; run only when the GPU test lane is free.
## tools/godot.ps1 -Arguments '--script res://tests/redesign_motion_capture.gd -- --width=1280 --height=800'
## Repeat with --width=1920 --height=1080. Outputs native-size PNG frames and a manifest.
## This is presentation evidence, not a replacement for topology/pixel regression tests.

const OUTPUT: String = "res://artifacts/redesign-motion"
const CASES: Array[Dictionary] = [
	{"id":"player_lightning_t3_standard_a","label":"PLAYER / THREE ARMS","detail":"Aiming, pumping and pod motion"},
	{"id":"elite_irregular_lightning_t2","label":"ELITE / OFFSET RAILS","detail":"Independent orbit centres and attached spokes"},
	{"id":"enemy_chain_lightning_t2","label":"CHAIN / FOLLOW THROUGH","detail":"Linked circles and a travelling wave"},
]
var width: int = 1280
var height: int = 800
var fps: int = 8
var duration: float = 8.0
var subjects: Array[Dictionary] = []
var failures: int = 0
var viewport: SubViewport
var timestamp: Label

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--width="): width = argument.trim_prefix("--width=").to_int()
		elif argument.begins_with("--height="): height = argument.trim_prefix("--height=").to_int()
		elif argument.begins_with("--fps="): fps = argument.trim_prefix("--fps=").to_int()
		elif argument.begins_with("--seconds="): duration = argument.trim_prefix("--seconds=").to_float()
	if DisplayServer.get_name() == "headless":
		push_error("Motion capture requires a real renderer; no images were produced.")
		quit(1)
		return
	if width < 640 or height < 480 or fps < 1 or duration <= 0:
		push_error("Invalid capture dimensions or duration.")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	var output: String = OUTPUT + "/%dx%d" % [width,height]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_build_scene()
	var frames: int = roundi(duration * fps) + 1
	var poses: Array[Dictionary] = []
	for frame: int in range(frames):
		var seconds: float = minf(duration, float(frame) / fps)
		var tick: int = roundi(seconds * 60.0)
		for subject: Dictionary in subjects:
			_pose(subject, tick)
			var renderer: ShipRenderer = subject.renderer
			renderer.set_motion_tick(tick)
			renderer.animation_time = seconds
			renderer._process(0.0)
			_check_bounds(subject, tick)
		timestamp.text = "%05.2f s     /     %05.2f s     ·     tick %03d" % [seconds,duration,tick]
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var source: Image = viewport.get_texture().get_image()
		var image: Image = _srgb(source)
		var filename: String = "frame_%03d.png" % frame
		if image.save_png(ProjectSettings.globalize_path(output + "/" + filename)) != OK: failures += 1
		poses.append({"frame":filename,"seconds":seconds,"tick":tick})
	var metadata: Array[Dictionary] = []
	for subject: Dictionary in subjects:
		metadata.append({"id":subject.ship.id,"geometry_revision":subject.ship.geometry_revision,"circle_count":subject.rig.ids.size(),"line_count":subject.rig.line_ids.size(),"scale":subject.renderer.visual_scale,"aim_joints":subject.rig.aim_indices.size()})
	var manifest: FileAccess = FileAccess.open(output + "/manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"width":width,"height":height,"fps":fps,"seconds":duration,"subjects":metadata,"frames":poses,"bounds_failures":failures,"note":"Actual ShipRenderer with deterministic ShipMotion poses, authored motion and continuous aim input. Samples include the exact final pose; playback may omit the final sample to retain the exact duration."}, "\t"))
	else: failures += 1
	print("REDESIGN MOTION CAPTURE: ", frames, " frames at ", width, "x", height, ", ", failures, " failures")
	quit(1 if failures else 0)

func _build_scene() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(width,height)
	viewport.use_hdr_2d = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.size = Vector2(width,height)
	viewport.add_child(background)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	VisualStyle.configure_glow(environment)
	for level: int in range(7): environment.set_glow_level(level,0.8 if level == 0 else 0.0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var scale: float = float(height) / 800.0
	_label("LIGHTSHIP / MOTION STUDY",Vector2(44,34)*scale,27*scale,VisualStyle.TEXT)
	_label("Production ships and connectors, sampled through eight seconds of motion.",Vector2(44,76)*scale,15*scale,VisualStyle.MUTED)
	timestamp = _label("",Vector2(44,float(height)/scale-49)*scale,14*scale,VisualStyle.MUTED)
	var margin: float = 44.0 * scale
	var gap: float = 24.0 * scale
	var column: float = (width - margin * 2.0 - gap * 2.0) / 3.0
	for index: int in range(CASES.size()):
		var entry: Dictionary = CASES[index]
		var panel: Rect2 = Rect2(margin + index*(column+gap),132*scale,column,height-240*scale)
		var backdrop := ColorRect.new()
		backdrop.color = VisualStyle.PANEL
		backdrop.position = panel.position
		backdrop.size = panel.size
		viewport.add_child(backdrop)
		_label(str(entry.label),panel.position+Vector2(18,18)*scale,14*scale,VisualStyle.ACCENT)
		_label(str(entry.detail),panel.position+Vector2(18,panel.size.y/scale-36)*scale,11*scale,VisualStyle.MUTED)
		var ship: ShipDefinition = ShipCatalog.get_ship(str(entry.id))
		var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
		var pose := ShipMotion.ShipPose.new(rig)
		var renderer := ShipRenderer.new()
		viewport.add_child(renderer)
		renderer.set_ship(ship)
		renderer.set_process(false)
		renderer.external_pose = pose
		var area: Rect2 = Rect2(panel.position+Vector2(18,61)*scale,panel.size-Vector2(36,122)*scale)
		var subject: Dictionary = {"ship":ship,"rig":rig,"pose":pose,"renderer":renderer,"area":area}
		var bounds: Rect2 = _motion_bounds(subject)
		renderer.visual_scale = minf(area.size.x/bounds.size.x,area.size.y/bounds.size.y)*0.94
		renderer.position = area.get_center()-bounds.get_center()*renderer.visual_scale
		subjects.append(subject)
	# Show the native capture as a fitted preview without altering saved resolution.
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(1280,800)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(preview)

func _label(text: String, position: Vector2, font_size: float, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size",roundi(font_size))
	label.add_theme_color_override("font_color",colour)
	viewport.add_child(label)
	return label

func _pose(subject: Dictionary, tick: int) -> void:
	var rig: ShipMotion.ShipRig = subject.rig
	var pose: ShipMotion.ShipPose = subject.pose
	var seconds: float = float(tick)/60.0
	for index: int in rig.aim_indices:
		pose.aim_angle[index] = -PI*0.5 + sin(seconds*TAU/5.5)*0.8
	ShipMotion.step(rig,pose,tick)

func _motion_bounds(subject: Dictionary) -> Rect2:
	var bounds: Rect2 = Rect2()
	var first: bool = true
	var rig: ShipMotion.ShipRig = subject.rig
	for tick: int in range(roundi(duration*60.0)+1):
		_pose(subject,tick)
		for index: int in range(rig.ids.size()):
			var extent: Vector2 = Vector2.ONE*(rig.radius[index]+3.0)
			var part: Rect2 = Rect2(subject.pose.local[index]-extent,extent*2.0)
			bounds = part if first else bounds.merge(part)
			first = false
	return bounds

func _check_bounds(subject: Dictionary, tick: int) -> void:
	var rig: ShipMotion.ShipRig = subject.rig
	var renderer: ShipRenderer = subject.renderer
	var area: Rect2 = subject.area
	for index: int in range(rig.ids.size()):
		var centre: Vector2 = renderer.position + subject.pose.local[index]*renderer.visual_scale
		var extent: Vector2 = Vector2.ONE*rig.radius[index]*renderer.visual_scale
		if not area.encloses(Rect2(centre-extent,extent*2.0)):
			failures += 1
			push_error("%s / %s clipped at tick %d" % [subject.ship.id,rig.ids[index],tick])

func _srgb(source: Image) -> Image:
	var output: Image = Image.create(width,height,false,Image.FORMAT_RGBA8)
	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = source.get_pixel(x,y).linear_to_srgb()
			output.set_pixel(x,y,Color(clampf(pixel.r,0,1),clampf(pixel.g,0,1),clampf(pixel.b,0,1),1))
	return output
