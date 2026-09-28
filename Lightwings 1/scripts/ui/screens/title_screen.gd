class_name TitleScreen
extends UiScreen
## The main menu (moved from main.gd's `_show_menu` in M2). It is built into main.gd's `menu`
## group, not the overlay host: overlays (level select, options, confirm, cloud review) open on
## top of it. main.gd's `_show_menu` still tears the run down and calls this.

func build() -> void:
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(background)
	var margin := MarginContainer.new()
	margin.name = "MenuLayout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 80)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 56)
	host.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 64)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 430
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	menu_label(left, "AN INSTANCE AWAKENS", 12, GOLD)
	menu_label(left, "LIGHTSHIP", 62, WHITE)
	menu_label(left, "Absorb light. Become something new.", 20, MUTED)
	var gap := Control.new()
	gap.custom_minimum_size.y = 20
	left.add_child(gap)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left.add_child(actions)
	## Available modes for THIS build flavour (spec §4: a demo build offers
	## demo only -- Dev must never be reachable there). The old "PLAY THE
	## DEMO" full-build entry is gone: the demo is its own build flavour now
	## (approved preamble), not a menu option inside the full campaign.
	var available_modes: Array[String] = ModeConfig.available_modes(OS.has_feature("demo"))
	var menu_slot: String = ModeConfig.from_id(available_modes[0]).save_slot()
	var exists: bool = not SaveService.load_snapshot(menu_slot).is_empty() or FileAccess.file_exists(SaveService.snapshot_path(menu_slot))
	var primary: Button = menu_action(actions,("CONTINUE " if exists else "BEGIN ")+menu_slot.to_upper(),func() -> void: app._continue_game(menu_slot) if exists else app._show_level_select(available_modes[0]))
	primary.custom_minimum_size.y = 52
	primary.add_theme_stylebox_override("normal",UiKit.box(Color("292820"),GOLD))
	if "dev" in available_modes:
		menu_action(actions,"DEV MODE",app._show_level_select.bind("dev"))
	if exists and OS.has_feature("demo"):
		menu_action(actions,"NEW DEMO",app._confirm_new.bind(true))
	if OS.has_feature("editor"):
		var tools_row := HBoxContainer.new()
		tools_row.add_theme_constant_override("separation", 10)
		actions.add_child(tools_row)
		menu_action(tools_row,"SHIP WORKSHOP",app._open_editor)
		menu_action(tools_row,"SHIP ATLAS",app._open_gallery)
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation", 10)
	actions.add_child(utilities)
	menu_action(utilities,"OPTIONS",app._show_options)
	menu_action(utilities,"QUIT",app._quit)
	if exists and not OS.has_feature("demo"):
		menu_action(actions,"NEW CAMPAIGN",app._confirm_new)
	if not OS.has_feature("demo") and not SaveService.load_snapshot("demo").is_empty():
		menu_action(actions,"IMPORT DEMO",app._import_demo)
	if app.platform.online and not OS.has_feature("demo"):
		app.cloud_review = app.platform.inspect_cloud(menu_slot)
		app.cloud_sync_ready = str(app.cloud_review.get("state","")) in ["same","missing"]
		if str(app.cloud_review.get("state","")) in ["conflict","remote_only"]:
			menu_action(actions,"REVIEW CLOUD SAVE",app._show_cloud_review)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	menu_label(left,"WASD + MOUSE  /  CONTROLLER",11,MUTED)
	menu_label(left,"DEMO · LIGHTNING / FIRE · LEVELS 1–2" if OS.has_feature("demo") else "FIVE ELEMENTS · ONE LIVING MACHINE",11,MUTED)
	var hero := ShipPreview.new()
	hero.name = "MenuHero"
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(360, 360)
	hero.preview_time_scale = 1.0
	hero.fit_margin = 48.0
	columns.add_child(hero)
	hero.initialize(ShipCatalog.get_ship("player_lightning_t3_standard_a"),Vector2(560,640),1.8)
	_focus = primary
