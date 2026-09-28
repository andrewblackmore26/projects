extends SceneTree
## Captures every reachable screen of the real main.gd at 1280x800 with processing frozen, so two
## runs of the same build produce the same pixels (modernization M2's before/after proof). Each
## screen gets a fresh app and an isolated save root; after the screen is built, every node in the
## tree stops processing before the first frame, so no real-time delta (ShipPreview motion, sine
## pulses, the ambient fade, the sim) can reach the capture. Combat is stepped by hand at 1/60 s.
##   tools\godot.ps1 -Arguments '--script "res://tools/capture_screens.gd" -- --out=<abs dir> [--only=<name>]'
## `--shift-label=<screen>` moves the first Label under app.overlay/app.menu/app.hud by +1 px x in
## that screen only: the negative control for tools/diff_captures.py.
## M6: `--size=WxH` captures at another window size (aspect "expand": 1920x1080 is a 1422x800 UI,
## 2560x1080 a 1896x800 one); `--text-scale=` and `--ui-scale=` apply those settings. `--only=` takes
## a comma-separated list.
const STEP: float = 1.0 / 60.0

var out_dir: String = ""
var only: String = ""
var shift_screen: String = ""
var window_size: Vector2i = Vector2i(1280, 800)
var text_scale: float = 1.0
var ui_scale: float = 1.0
var failures: int = 0
var captured: int = 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		elif arg.begins_with("--shift-label="): shift_screen = arg.trim_prefix("--shift-label=")
		elif arg.begins_with("--size="): window_size = Vector2i(int(arg.trim_prefix("--size=").get_slice("x",0)),int(arg.trim_prefix("--size=").get_slice("x",1)))
		elif arg.begins_with("--text-scale="): text_scale = arg.trim_prefix("--text-scale=").to_float()
		elif arg.begins_with("--ui-scale="): ui_scale = arg.trim_prefix("--ui-scale=").to_float()
	if DisplayServer.get_name() == "headless" or out_dir.is_empty():
		push_error("capture_screens needs a GPU window and --out=<dir>")
		quit(1)
		return
	root.size = window_size
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for screen: String in ["menu","menu_saves","level_select_campaign","level_select_dev","options_audio","options_display","options_gameplay","options_controls","options_accessibility","pause","options_over_pause","pause_after_options","evolution","evolution_dev","map","death","level_complete","ending_campaign","ending_demo","cloud","confirm_new","import_confirm","dialogue","hud_origin","hud_combat","hud_evolve_ready","hud_dev","toast"]:
		if not only.is_empty() and not screen in only.split(","): continue
		await _capture(screen)
	print("SCREEN CAPTURE: %d screens, %d failures" % [captured,failures])
	quit(1 if failures else 0)

func _descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in node.get_children():
		nodes.append(child)
		nodes.append_array(_descendants(child))
	return nodes

func _step_combat(app: Node, ticks: int) -> void:
	app.combat.set_physics_process(false)
	for tick: int in range(ticks): app.combat._physics_process(STEP)

## A demo save and a campaign save, each written from a run of its own mode (a save whose mode does
## not match its slot is refused on load).
func _write_saves(app: Node) -> void:
	app._new_game(true)
	SaveService.save_snapshot(app.campaign.to_dict(),{},"demo")
	app._new_game(false)
	SaveService.save_snapshot(app.campaign.to_dict(),{},"campaign")

func _capture(screen: String) -> void:
	SaveService.storage_root = "user://screen-capture-%s-%d" % [screen,Time.get_ticks_usec()]
	seed(424242)
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	match screen:
		"menu": pass
		"menu_saves":
			_write_saves(app)
			app._show_menu()
		"level_select_campaign": app._show_level_select("campaign")
		"level_select_dev": app._show_level_select("dev")
		"options_audio","options_display","options_gameplay","options_controls","options_accessibility":
			app.options_tab = ["options_audio","options_display","options_gameplay","options_controls","options_accessibility"].find(screen)
			app._show_options()
		"pause","options_over_pause","pause_after_options":
			app._new_game(false)
			_step_combat(app,1)
			app._close_overlay()
			app._show_pause()
			if screen != "pause": app._show_options()
			if screen == "pause_after_options": app._close_options()
		"evolution":
			app._new_game(false)
			_step_combat(app,1)
			app.combat.setup_player("lightning",3,1000,[],GameTuning.ARENA_CENTER)
			app.combat.absorption = {"lightning":300.0,"fire":100.0,"plasma":80.0}
			app._show_evolution()
		"evolution_dev":
			app._new_game_as("dev")
			_step_combat(app,1)
			app.combat.collect_light(120.0,"lightning")
			app._show_evolution()
		"map":
			app._new_game(false)
			_step_combat(app,1)
			app._show_map()
		"death":
			app._new_game(false)
			_step_combat(app,1)
			app._on_death()
		"level_complete":
			app._new_game(false)
			_step_combat(app,1)
			app._show_level_complete({"next_level":2,"revealed_element":"fire"})
		"ending_campaign","ending_demo":
			app._new_game(screen == "ending_demo")
			_step_combat(app,1)
			app._show_ending(screen == "ending_demo")
		"cloud":
			app.cloud_review = {"state":"conflict","local_summary":"Level 2 · T3 · 14 nodes","remote_summary":"Level 1 · T2 · 6 nodes"}
			app._show_cloud_review()
		"confirm_new": app._confirm_new(false)
		"import_confirm":
			_write_saves(app)
			app._show_menu()
			app._import_demo()
		"dialogue":
			app._new_game(false)
			_step_combat(app,1)
			# M6: the origin may now hold enemies, which holds back an ordinary line; show the
			# welcome through the immediate lane so the box is always in the capture.
			if app.line_queue.is_empty() or not app.dialogue_director.can_show_next(false):
				var front: Dictionary = app.line_queue[0] if not app.line_queue.is_empty() else {"element":"fire","title":"ECHO","text":"Signal found."}
				app.line_queue.clear()
				app.dialogue_director.queue_immediate(str(front.element),str(front.title),str(front.text),"capture_dialogue")
			app._update_dialogue(0.0)
		"hud_origin":
			app._new_game(false)
			app.line_queue.clear()
			_step_combat(app,30)
		"hud_combat","hud_evolve_ready":
			app._new_game(false)
			app.line_queue.clear()
			app.combat.set_physics_process(false)
			app.combat.setup_player("plasma",4,750,[],Vector2(896,560))
			app.campaign.current_sector = Vector2i(-3,2)
			var showcase: Dictionary = app.campaign.sector_at(app.campaign.current_sector)
			showcase.kind = "regular"
			app.combat.start_sector(showcase)
			if screen == "hud_evolve_ready":
				app.combat.setup_player("fire",2,0,[],Vector2(896,560))
				app.combat.collect_light(float(EvolutionRules.threshold(2))+5.0,"fire")
			_step_combat(app,45)
		"hud_dev":
			app._new_game_as("dev")
			app.line_queue.clear()
			_step_combat(app,10)
			if is_instance_valid(app.dev_console): app.dev_console.toggle()
		"toast":
			app._new_game(false)
			app.line_queue.clear()
			_step_combat(app,5)
			app._toast("NODE CLEAR · 0,0")
	# main.gd pauses a run when the window loses focus (NOTIFICATION_APPLICATION_FOCUS_OUT), which a
	# capture cannot rule out: the screen must still be the one that was built when it is grabbed.
	var built_kind: String = app.overlay_kind
	if text_scale != 1.0 or ui_scale != 1.0:
		app.settings.text_scale = text_scale
		app.settings.ui_scale = ui_scale
		app.apply_settings()
		# A preview refitted by the new layout draws its new scale on its next _process, which the
		# freeze below would otherwise never let run.
		for preview: Node in get_nodes_in_group("ship_previews"):
			if is_instance_valid(preview.renderer): preview.renderer._process(0)
	if app.mode == "play" and is_instance_valid(app.combat):
		app._refresh_hud()
		for actor: Dictionary in app.combat.actors_by_id.values():
			var renderer: ShipRenderer = actor.get("renderer")
			if is_instance_valid(renderer): renderer._process(0)
		app.compositor._process(0)
	# Frozen: nothing advances on a real frame delta from here on.
	for node: Node in _descendants(root):
		node.set_process(false)
		node.set_physics_process(false)
	# M5: UI tweens are not node processing; let every entrance finish so the capture is the settled
	# screen (the longest is a STAGGER_MAX delay plus a SLOW rise).
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.2, true, false, true).timeout
	if screen == shift_screen:
		for group_node: Control in [app.overlay,app.menu,app.hud]:
			if not group_node.visible: continue
			var shifted: bool = false
			for node: Node in _descendants(group_node):
				if node is Label and node.is_visible_in_tree() and not node.text.is_empty():
					# A container re-lays its children out every sort, so a label inside one is
					# moved by moving the outermost container that holds it.
					var moved: Control = node
					while moved.get_parent() is Container: moved = moved.get_parent()
					moved.position.x += 1.0
					print("negative control: shifted label '%s' by +1 px (moved %s)" % [node.text.left(30),moved.name])
					shifted = true
					break
			if shifted: break
	for i: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var raw: Image = root.get_texture().get_image()
	if app.overlay_kind != built_kind:
		push_error("capture %s: overlay changed from '%s' to '%s' before the grab (window focus lost?)" % [screen,built_kind,app.overlay_kind])
		failures += 1
	if raw.get_size() != root.size:
		push_error("capture %s is %dx%d, expected root.size %s" % [screen,raw.get_width(),raw.get_height(),root.size])
		failures += 1
	var encoded := Image.create(raw.get_width(),raw.get_height(),false,Image.FORMAT_RGB8)
	for y: int in range(raw.get_height()):
		for x: int in range(raw.get_width()):
			encoded.set_pixel(x,y,raw.get_pixel(x,y).linear_to_srgb() if root.use_hdr_2d else raw.get_pixel(x,y))
	var path: String = out_dir.path_join(screen+".png")
	if encoded.save_png(path) != OK:
		failures += 1
		push_error("could not write "+path)
	else:
		captured += 1
		print("captured %s (overlay_kind='%s', mode=%s)" % [screen,app.overlay_kind,app.mode])
	await app._stop_audio()
	app.queue_free()
	await process_frame
	await process_frame
