extends SceneTree
## Layout and animated-preview regression coverage; every actual catalogue hull is sampled.
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
	_check(tab_titles == PackedStringArray(["Audio","Display","Gameplay","Controls"]),"Options categories remain in their intended order")
	var sliders: int = 0
	var controls: int = 0
	for node: Node in _descendants(tabs):
		if node is HSlider: sliders += 1
		if node is Button and not node is CheckButton: controls += 1
	_check(sliders == 4,"Master, effects, interface and ambience can each be adjusted")
	_check(controls >= InputBindings.ACTIONS.size(),"Every input action remains available for rebinding")
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
