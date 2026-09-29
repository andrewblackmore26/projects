extends SceneTree
## Layout and animated-preview regression coverage; every actual catalogue hull is sampled.
##
## Restated in modernization M15 (Options became pad-operable spinner rows in five tabs):
## - retired "Options has four clear categories" (tab count 4, Audio/Display/Gameplay/Controls)
##   -> five, the same four in the same places plus Accessibility last (options_tab indices and the
##   captures keep their meaning);
## - retired "Master, effects, interface and ambience can each be adjusted" (exactly 4 HSliders in
##   Options: Accessibility's shake, flash and rumble rows now carry sliders too) -> the Audio tab
##   has the four bus rows (Master/Music/Effects/Interface = volume/ambience/effects/interface
##   settings), each an OptionRow that left/right step with focus kept on the row, each still
##   carrying a mouse slider;
## - retired "Every input action remains available for rebinding" (any non-toggle Button counted,
##   which the spinner rows now satisfy on their own) -> one Bind_<action> row per InputBindings
##   action;
## - "Primary menu action starts focused" still reads "BEGIN" on a fresh profile: the capsule's text
##   is now just BEGIN/CONTINUE (was "BEGIN CAMPAIGN").
## Restated in the M19 UX review (Gameplay's two rows joined Accessibility):
## - retired "Options has five clear categories" (Audio/Display/Gameplay/Controls/Accessibility)
##   -> four (Audio/Display/Controls/Accessibility), plus a new check that Auto-fire and the element
##   labels are rows of Accessibility.
var failures: int = 0
var checks: int = 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in node.get_children():
		nodes.append(child)
		nodes.append_array(_descendants(child))
	return nodes

func _run() -> void:
	root.size = Vector2i(1280,800)
	SaveService.storage_root = "user://ui-presentation-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	app.settings_path = SaveService.storage_root + ".cfg" # M15: the steps below write settings
	root.add_child(app)
	for i: int in range(4): await process_frame
	var previews: Array[ShipPreview] = []
	for node: Node in _descendants(app.menu):
		if node is ShipPreview: previews.append(node)
		if node is Button:
			_check(Rect2(0,0,1280,800).encloses(node.get_global_rect()),"Menu action fits viewport: " + node.text)
	_check(previews.size() == 1,"Menu has one hero ship")
	if previews.size() == 1:
		var hero: ShipPreview = previews[0]
		_check(hero.renderer.definition.id == "player_lightning_t3_standard_a","Menu hero is the connected player design")
		_check(is_equal_approx(hero.preview_time_scale,1.0),"Menu ship uses the reference motion speed")
		_check(hero.motion_radius * hero.renderer.visual_scale <= minf(hero.size.x,hero.size.y)*0.5 - hero.fit_margin + 0.01,"Entire animated menu ship fits its margins")
	var focus: Control = root.gui_get_focus_owner()
	_check(focus is Button and focus.text.begins_with("BEGIN"),"Primary menu action starts focused")
	app._show_options()
	for i: int in range(3): await process_frame
	var tabs: TabContainer = app.overlay.get_node("OptionsTabs")
	_check(tabs.get_tab_count() == 4,"Options has four clear categories")
	var tab_titles: PackedStringArray = []
	for i: int in range(tabs.get_tab_count()): tab_titles.append(tabs.get_tab_title(i))
	_check(tab_titles == PackedStringArray(["Audio","Display","Controls","Accessibility"]),"Options categories remain in their intended order")
	var access: Node = tabs.get_node("Accessibility")
	_check(access.find_child("Row_auto_fire",true,false) != null and access.find_child("Row_show_elements",true,false) != null,"Auto-fire and the element labels live on Accessibility")
	tabs.current_tab = 0
	for i: int in range(2): await process_frame
	var buses: int = 0
	for key: String in ["volume","ambience_volume","effects_volume","interface_volume"]:
		var row: Node = tabs.get_node("Audio").find_child("Row_"+key,true,false)
		if row is OptionRow and row.slider != null:
			buses += 1
			var before: Variant = app.settings[key]
			row.grab_focus()
			var step := InputEventAction.new()
			step.action = "ui_left" if float(before) > 0.0 else "ui_right"
			step.pressed = true
			root.push_input(step)
			_check(root.gui_get_focus_owner() == row and app.settings[key] != before,"The %s row steps on left/right and keeps focus" % key)
			row.step(1 if step.action == "ui_left" else -1)
	_check(buses == 4,"Master, music, effects and interface each have a pad row with a mouse slider")
	var bindings: int = 0
	for node: Node in _descendants(tabs):
		if node is Button and str(node.name).begins_with("Bind_"): bindings += 1
	_check(bindings == InputBindings.ACTIONS.size(),"Every input action remains available for rebinding")
	tabs.current_tab = 3
	for i: int in range(3): await process_frame
	for node: Node in _descendants(tabs):
		if node is Control and node.is_visible_in_tree() and (node is Button or node is HSlider):
			_check(tabs.get_global_rect().encloses(node.get_global_rect()),"Visible option fits its tab: " + node.name)
	app._close_options()
	_check(root.gui_get_focus_owner() == focus,"Closing menu Options restores the previous menu focus")
	app._new_game(false)
	app._close_overlay()
	app._show_pause()
	app._show_options()
	app._close_options()
	_check(paused and app.overlay_kind == "pause","Closing in-game Options returns to Pause without resuming combat")
	_check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner().text == "RESUME","Returned Pause has a focused Resume action")
	app._close_overlay()
	var tile := GalleryTile.new()
	root.add_child(tile)
	for id: String in ["player_seed","player_lightning_t6_heavy","boss_lightning"]:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		var entry: Dictionary = {"id":id,"ship":ship,"name":id}
		for true_scale: bool in [false,true]:
			tile.set_entry(entry,true_scale)
			await process_frame
			var radius: float = ShipPreview.animated_radius(ship)*tile._renderer.visual_scale
			_check(radius <= minf(tile._stage.size.x,tile._stage.size.y)*0.5-2.0,"Atlas holds every animated limb: %s, true scale %s" % [id,true_scale])
			_check(tile._renderer.position.is_equal_approx(tile._stage.size*0.5),"Atlas centres the preview in the complete tile: " + id)
			if true_scale: _check(is_equal_approx(tile._renderer.visual_scale,0.9),"Atlas true scale remains 0.9 for " + id)
	tile.queue_free()
	# The bound uses full link lengths, not a single still pose. Sample each hull's real evaluator.
	for ship: ShipDefinition in ShipCatalog.all_forms():
		var bound: float = ShipPreview.animated_radius(ship)
		var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
		var pose := ShipMotion.ShipPose.new(rig)
		var inside: bool = true
		for tick: int in range(0,1801,120):
			ShipMotion.step(rig,pose,tick)
			for i: int in range(rig.ids.size()):
				if pose.local[i].length() + rig.radius[i]*pose.scale[i] > bound + 0.01: inside = false
		_check(inside,"Animated preview bound contains " + ship.id)
	await app._stop_audio()
	app.queue_free()
	await process_frame
	print("UI presentation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
