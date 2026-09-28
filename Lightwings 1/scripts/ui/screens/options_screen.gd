class_name OptionsScreen
extends UiScreen
## Options and controls (moved from main.gd's `_show_options` in M2). Settings live on main.gd
## (`settings`, `apply_settings`, `save_settings`), as does the rebind capture in `_input`, which
## rebuilds this screen once a binding is taken. DONE pops back to the screen below.

func build() -> void:
	UiKit.label(host,"OPTIONS",Vector2(90,55),Vector2(1100,52),34,WHITE)
	var tabs := TabContainer.new()
	tabs.name = "OptionsTabs"
	tabs.position = Vector2(90,135)
	tabs.size = Vector2(1100,530)
	host.add_child(tabs)
	var pages: Dictionary = {}
	for title: String in ["Audio","Display","Gameplay","Controls"]:
		var page := MarginContainer.new()
		page.name = title
		for side: String in ["left","right","top","bottom"]: page.add_theme_constant_override("margin_"+side,28)
		tabs.add_child(page)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation",15)
		page.add_child(content)
		pages[title] = content
	_option_slider(pages.Audio,"Master volume","volume")
	_option_slider(pages.Audio,"Effects","effects_volume")
	_option_slider(pages.Audio,"Interface","interface_volume")
	_option_slider(pages.Audio,"Ambience","ambience_volume")
	_option_toggle(pages.Audio,"Ambient music","music")
	_option_toggle(pages.Audio,"Pickup cues","pickup_cues")
	_option_toggle(pages.Display,"Fullscreen","fullscreen")
	_option_toggle(pages.Display,"Soft glow","glow")
	_option_toggle(pages.Display,"Reduced warp effect","reduced_warp")
	_option_toggle(pages.Display,"Damage numbers","damage_numbers")
	_option_toggle(pages.Gameplay,"Auto-fire","auto_fire")
	_option_toggle(pages.Gameplay,"Element names and pattern labels","show_elements")
	menu_label(pages.Controls,"Choose a binding, then press a key, mouse button or controller input.",14,MUTED)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",10)
	pages.Controls.add_child(grid)
	for action: String in InputBindings.ACTIONS:
		var action_label: Label = menu_label(grid,str(InputBindings.ACTIONS[action]),14,WHITE)
		action_label.custom_minimum_size.x = 125
		var bind_button: Button = button(grid,binding_label(action),Rect2(0,0,0,34),_capture_binding.bind(action))
		bind_button.tooltip_text = InputBindings.describe(action)
		bind_button.custom_minimum_size = Vector2(300,34)
		bind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind_button.add_theme_font_size_override("font_size",12)
	if app.platform.online: menu_action(pages.Controls,"STEAM CONTROLLER LAYOUT",func() -> void: app.platform.show_input_bindings())
	tabs.current_tab = app.options_tab
	tabs.tab_changed.connect(func(index: int) -> void: app.options_tab = index)
	_focus = button(host,"DONE",Rect2(870,711,320,48),request_pop.emit)

static func binding_label(action: String) -> String:
	var labels := PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			labels.append(OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode))
		elif event is InputEventMouseButton:
			labels.append({MOUSE_BUTTON_LEFT:"Left click",MOUSE_BUTTON_RIGHT:"Right click",MOUSE_BUTTON_MIDDLE:"Middle click",MOUSE_BUTTON_WHEEL_UP:"Wheel up",MOUSE_BUTTON_WHEEL_DOWN:"Wheel down"}.get(event.button_index,"Mouse %d" % event.button_index))
		elif event is InputEventJoypadMotion:
			var direction: String = "−" if event.axis_value < 0 else "+"
			labels.append({JOY_AXIS_LEFT_X:"Left stick X"+direction,JOY_AXIS_LEFT_Y:"Left stick Y"+direction,JOY_AXIS_RIGHT_X:"Right stick X"+direction,JOY_AXIS_RIGHT_Y:"Right stick Y"+direction,JOY_AXIS_TRIGGER_LEFT:"LT",JOY_AXIS_TRIGGER_RIGHT:"RT"}.get(event.axis,"Pad axis %d%s" % [event.axis,direction]))
		elif event is InputEventJoypadButton:
			labels.append({JOY_BUTTON_A:"South / A",JOY_BUTTON_B:"East / B",JOY_BUTTON_X:"West / X",JOY_BUTTON_Y:"North / Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_BACK:"Back",JOY_BUTTON_START:"Start",JOY_BUTTON_LEFT_STICK:"Left stick press",JOY_BUTTON_RIGHT_STICK:"Right stick press",JOY_BUTTON_DPAD_UP:"D-pad up",JOY_BUTTON_DPAD_DOWN:"D-pad down",JOY_BUTTON_DPAD_LEFT:"D-pad left",JOY_BUTTON_DPAD_RIGHT:"D-pad right"}.get(event.button_index,"Pad button %d" % event.button_index))
		else: labels.append(event.as_text())
	return "  ·  ".join(labels) if not labels.is_empty() else "Unbound"

func _option_toggle(parent: Node, title: String, property: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.custom_minimum_size.y = 40
	check.button_pressed = bool(app.settings[property])
	parent.add_child(check)
	var owner: Node = app
	check.toggled.connect(func(value: bool) -> void: owner.settings[property]=value; owner.apply_settings(); owner.save_settings())
	return check

func _option_slider(parent: Node, title: String, property: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	row.custom_minimum_size.y = 42
	parent.add_child(row)
	var caption: Label = menu_label(row,title,16,WHITE)
	caption.custom_minimum_size.x = 230
	var slider := HSlider.new()
	slider.name = property
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(app.settings[property])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label: Label = menu_label(row,"%d%%" % roundi(slider.value*100),14,MUTED)
	value_label.custom_minimum_size.x = 65
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var owner: Node = app
	slider.value_changed.connect(func(value: float) -> void:
		owner.settings[property]=value
		value_label.text="%d%%" % roundi(value*100)
		owner.apply_settings()
		owner.save_settings())

func _capture_binding(action: String) -> void:
	app.rebind_action = action
	app.toast_stack.show("BIND " + str(InputBindings.ACTIONS[action]).to_upper() + " · Press a key or controller input. ESC cancels.",60.0)
	var focused: Control = app.get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
