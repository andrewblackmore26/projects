class_name OptionsScreen
extends UiScreen
## Options and controls (moved from main.gd's `_show_options` in M2). Settings live on main.gd
## (`settings`, `apply_settings`, `save_settings`), as does the rebind capture in `_input`, which
## rebuilds this screen once a binding is taken. DONE pops back to the screen below.
##
## M15: every row is operable with a pad. A list or a percentage is an OptionRow spinner (left/right
## step it, focus stays on the row; percentages also carry a slider for the mouse); an on/off is a
## toggle row that confirm flips and left/right set. Tabs: Audio, Display, Gameplay, Controls,
## Accessibility (the tab index is stable for `options_tab` and the captures; Accessibility is new
## and last). LB/RB (Q/E on a keyboard) switch tabs from anywhere on the screen. Controls shows each
## action's keyboard and controller glyph (InputPrompts) and opens a rebinding MODAL - a card that
## waits for the input and cancels on Escape or after REBIND_SECONDS - instead of the old 60 s toast.
##
## M19 review: four tabs. Gameplay's two rows (auto-fire, element labels) joined Accessibility, the
## aids they are, so no tab is a near-empty panel; every tab keeps one panel size (the binding rows
## no longer force Controls wider). Text size is a percentage row with a slider like its neighbours.
## A caption under the panel says, in one line, what the focused row does (DESCRIPTIONS).

const TAB_TITLES: Array[String] = ["Audio", "Display", "Controls", "Accessibility"]
## Row name -> the one-line caption shown while it has focus. Binding rows share BINDING_CAPTION.
const DESCRIPTIONS: Dictionary = {
	"Row_volume": "Overall loudness of everything the game plays.",
	"Row_ambience_volume": "Loudness of the adaptive music.",
	"Row_effects_volume": "Loudness of weapons, hits, pickups and warps.",
	"Row_interface_volume": "Loudness of menu moves, confirms and toasts.",
	"Row_music": "Music follows the fight: calmer when a node is clear, fuller in a boss fight.",
	"Row_pickup_cues": "A soft chime for every light pickup.",
	"Row_window_mode": "Windowed, borderless full screen or exclusive full screen.",
	"Row_resolution": "The window's size while windowed.",
	"Row_vsync": "Syncs frames to the display to stop tearing; off gives the lowest input delay.",
	"Row_fps_cap": "The most frames drawn per second.",
	"Row_ui_scale": "The size of the whole interface, HUD included; the playfield is unchanged.",
	"Row_glow": "The soft bloom around light, bullets and ships.",
	"Row_auto_fire": "The primary weapon fires on its own while there is a target.",
	"Row_show_elements": "Names each element and attack pattern next to its colour.",
	"Row_screen_shake": "How hard hits, dashes and explosions shake the camera.",
	"Row_flash_intensity": "How bright full-screen flashes get (evolutions, bosses, big hits).",
	"Row_reduced_motion": "Menus and the HUD appear without sliding or springing.",
	"Row_colorblind": "Element colours from a palette that stays apart under every colour-vision type.",
	"Row_text_scale": "The size of all text; layouts reflow to fit.",
	"Row_rumble": "How strongly the controller vibrates.",
	"Row_damage_numbers": "Shows the damage of each hit where it lands.",
	"Row_reduced_warp": "A calmer, shorter warp between nodes.",
	"Done": "Saves every change and closes Options.",
	"Tabs": "Switch category. Q / E (LB / RB) switch it from anywhere on the screen.",
}
const BINDING_CAPTION: String = "Select to rebind, then press the new key, button or stick. Esc cancels."
## The design canvas rows: title, tab panel, caption, footer.
const TABS_RECT: Rect2 = Rect2(90, 104, 1100, 580)
const CAPTION_Y: float = 690.0
const FOOTER_Y: float = 716.0
## Every row's height (spinner, toggle): ten Accessibility rows fit TABS_RECT with the page margins.
const ROW_HEIGHT: float = OptionRow.ROW_HEIGHT
const PAGE_MARGIN_Y: int = 10
const ROW_GAP: int = 3
const REBIND_SECONDS: float = 10.0
const RESOLUTIONS: Array[String] = ["1280x720", "1280x800", "1366x768", "1600x900", "1920x1080", "1920x1200", "2560x1080", "2560x1440", "3440x1440", "3840x2160"]
const PERCENT_STEPS: Array = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const VOLUME_STEPS: Array = [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0]

## The action whose row takes focus when the screen is rebuilt after a rebind (or its cancel).
static var return_action: String = ""

var _tabs: TabContainer
var _done: Button
var _pages: Dictionary = {}
var _modal: Array[Control] = []
var _caption: Label

## The title, the tab strip, then the open page's rows one by one, then DONE.
func motion_items() -> Array:
	var items: Array = super()
	var page: Control = _tabs.get_current_tab_control()
	if page == null or page.get_child_count() == 0: return items
	var at: int = items.find(_tabs) + 1
	var result: Array = items.slice(0, at)
	result.append_array(page.get_child(0).get_children())
	result.append_array(items.slice(at))
	return result

func build() -> void:
	var kicker: Label = UiKit.label(host, "SETTINGS", Vector2(90, 28), Vector2(400, 18), UiTokens.TEXT_XS, UiTokens.KICKER)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	UiKit.label(host, "OPTIONS", Vector2(90, 48), Vector2(600, 52), UiTokens.TEXT_2XL, WHITE).autowrap_mode = TextServer.AUTOWRAP_OFF
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.name = "OptionsTabs"
	tabs.position = TABS_RECT.position
	tabs.size = TABS_RECT.size
	# M19 review: the tab strip sits on solid glass (the panel's own fill, opaque), so nothing behind
	# the screen - the title's wordmark, a bright hull - reads through the category names.
	var strip: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.GLASS, 1.0), UiTokens.STROKE, 1, UiTokens.RADIUS_PANEL)
	strip.corner_radius_bottom_left = 0
	strip.corner_radius_bottom_right = 0
	strip.set_content_margin_all(0)
	tabs.add_theme_stylebox_override("tabbar_background", strip)
	host.add_child(tabs)
	for title: String in TAB_TITLES:
		var page := MarginContainer.new()
		page.name = title
		for side: String in ["left", "right"]: page.add_theme_constant_override("margin_" + side, 24)
		for side: String in ["top", "bottom"]: page.add_theme_constant_override("margin_" + side, PAGE_MARGIN_Y)
		tabs.add_child(page)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", ROW_GAP)
		page.add_child(content)
		_pages[title] = content
	var audio: Node = _pages.Audio
	_percent(audio, "Master volume", "volume", VOLUME_STEPS)
	_percent(audio, "Music", "ambience_volume", VOLUME_STEPS)
	_percent(audio, "Effects", "effects_volume", VOLUME_STEPS)
	_percent(audio, "Interface", "interface_volume", VOLUME_STEPS)
	_toggle(audio, "Adaptive music", "music")
	_toggle(audio, "Pickup cues", "pickup_cues")
	var display: Node = _pages.Display
	_choice(display, "Window mode", "window_mode", ["windowed", "borderless", "exclusive"], ["Windowed", "Borderless", "Exclusive"])
	var sizes: Array = resolutions()
	_choice(display, "Resolution (windowed)", "resolution", sizes, PackedStringArray(sizes.map(func(value: String) -> String: return "Current window" if value == "auto" else value.replace("x", " × "))))
	_choice(display, "V-Sync", "vsync", ["on", "adaptive", "off"], ["On", "Adaptive", "Off"])
	_choice(display, "Frame-rate cap", "fps_cap", [30, 60, 120, 144, 0], ["30", "60", "120", "144", "Unlimited"])
	_choice(display, "UI scale", "ui_scale", [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4], ["80%", "90%", "100%", "110%", "120%", "130%", "140%"])
	_toggle(display, "Soft glow", "glow")
	var access: Node = _pages.Accessibility
	_toggle(access, "Auto-fire", "auto_fire")
	_toggle(access, "Element names and pattern labels", "show_elements")
	_percent(access, "Screen shake", "screen_shake", PERCENT_STEPS)
	_percent(access, "Flash intensity", "flash_intensity", PERCENT_STEPS)
	_toggle(access, "Reduced motion", "reduced_motion")
	_toggle(access, "Colourblind-safe element colours", "colorblind")
	_choice(access, "Text size", "text_scale", [0.9, 1.0, 1.1, 1.2, 1.3], ["90%", "100%", "110%", "120%", "130%"], true)
	_percent(access, "Controller rumble", "rumble", PERCENT_STEPS)
	_toggle(access, "Damage numbers", "damage_numbers")
	_toggle(access, "Reduced warp effect", "reduced_warp")
	_build_controls(_pages.Controls)
	tabs.current_tab = clampi(app.options_tab, 0, TAB_TITLES.size() - 1)
	tabs.tab_changed.connect(_on_tab_changed)
	var keys := MenuDraw.new()
	keys.name = "TabKeys"
	keys.input_handler = _tab_keys
	# A listener, not content: full-bleed so the canvas fit does not count its empty rect at (0, 0).
	UiLayout.mark_bleed(keys)
	host.add_child(keys)
	_caption = UiKit.label(host, "", Vector2(TABS_RECT.position.x + 24, CAPTION_Y), Vector2(TABS_RECT.size.x - 48, 20), UiTokens.TEXT_S, MUTED)
	_caption.name = "Caption"
	_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var hints := PromptHints.new([["navigate", "MOVE"], ["change", "ADJUST"], ["tabs", "TAB"], ["ui_cancel", "BACK"]])
	hints.name = "Hints"
	hints.position = Vector2(90, FOOTER_Y + 10)
	host.add_child(hints)
	var done: Button = button(host, "DONE", Rect2(870, FOOTER_Y, 320, 48), request_pop.emit)
	done.name = "Done"
	_done = done
	_describe_on_focus()
	_link.call_deferred()
	_focus = _first_row(tabs.current_tab)
	if not return_action.is_empty():
		var row: Control = _pages.Controls.find_child("Bind_" + return_action, true, false)
		if row != null and tabs.current_tab == TAB_TITLES.find("Controls"): _focus = row
		return_action = ""
	if _focus == null: _focus = done

## The resolutions the screen can show, "auto" (leave the window as it is) first.
static func resolutions() -> Array:
	var result: Array = ["auto"]
	var screen: Vector2i = DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	for size: String in RESOLUTIONS:
		var wide: int = int(size.get_slice("x", 0))
		var tall: int = int(size.get_slice("x", 1))
		if screen == Vector2i.ZERO or (wide <= screen.x and tall <= screen.y): result.append(size)
	return result

## Writes one setting and applies and saves it (the one path every row takes).
func _write(value: Variant, key: String) -> void:
	app.settings[key] = value
	if key == "window_mode": app.settings.fullscreen = str(value) != "windowed"
	app.apply_settings()
	app.save_settings()

func _choice(parent: Node, caption: String, key: String, values: Array, names: PackedStringArray, with_slider: bool = false) -> OptionRow:
	var row := OptionRow.new()
	row.name = "Row_" + key
	parent.add_child(row)
	row.sound_owner = app
	row.setup(caption, values, names, app.settings.get(key, values[0]), _write.bind(key), with_slider)
	_row_hover(row)
	return row

## Hover equals focus on a row too, but a full-width row does not grow on focus (UiMotion.hover's
## lift is 2.5 %, 26 px on a 1050 px row); the raised gold row style carries the focus instead.
static func _row_hover(row: Control) -> void:
	row.mouse_entered.connect(func() -> void:
		if row.focus_mode != Control.FOCUS_NONE: row.grab_focus())

## Every focusable row, the tab strip and DONE set the caption to their line when focused.
func _describe_on_focus() -> void:
	var targets: Array[Control] = [_tabs.get_tab_bar(), _done]
	for page: Control in _pages.values():
		for node: Node in page.find_children("*", "BaseButton", true, false): targets.append(node)
	for target: Control in targets:
		if target.focus_mode == Control.FOCUS_NONE: continue
		target.focus_entered.connect(_describe.bind(target))
	_describe(null)

## The caption for `control` (null: the open tab's first row, what the screen opens on).
func _describe(control: Control) -> void:
	if not is_instance_valid(_caption): return
	var key: String = "Tabs" if control == _tabs.get_tab_bar() else str(control.name) if control != null else ""
	if control == null:
		var first: Control = _first_row(_tabs.current_tab)
		key = str(first.name) if first != null else ""
	_caption.text = BINDING_CAPTION if key.begins_with("Bind_") else str(DESCRIPTIONS.get(key, ""))

func _percent(parent: Node, caption: String, key: String, steps: Array) -> OptionRow:
	var names := PackedStringArray()
	for step: float in steps: names.append("%d%%" % roundi(step * 100.0))
	return _choice(parent, caption, key, steps, names, true)

## An on/off row: confirm flips it, left sets off, right sets on.
func _toggle(parent: Node, caption: String, key: String) -> CheckButton:
	var check := CheckButton.new()
	check.name = "Row_" + key
	check.text = caption
	check.custom_minimum_size.y = ROW_HEIGHT
	check.button_pressed = bool(app.settings.get(key, false))
	parent.add_child(check)
	_row_hover(check)
	check.toggled.connect(func(value: bool) -> void: _write(value, key))
	check.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
			var on: bool = event.is_action_pressed("ui_right", true)
			if check.button_pressed != on:
				check.button_pressed = on
				UiScreen.ui_cue(app, "ui_slider_tick")
			check.accept_event())
	return check

## The first focusable row of tab `index`.
func _first_row(index: int) -> Control:
	var page: Control = _pages.get(TAB_TITLES[index])
	if page == null: return null
	for node: Node in page.find_children("*", "BaseButton", true, false):
		if (node as Control).focus_mode != Control.FOCUS_NONE: return node
	return null

## The open page's focus rows: the tab strip, each row (Controls: each pair of binding rows), DONE.
func _link() -> void:
	if not is_instance_valid(_tabs) or not _tabs.is_inside_tree(): return
	var lines: Array = [[_tabs.get_tab_bar()]]
	var page: Control = _pages[TAB_TITLES[_tabs.current_tab]]
	for node: Node in page.find_children("*", "BaseButton", true, false):
		var control: Control = node
		if control.focus_mode == Control.FOCUS_NONE: continue
		# Binding rows sit two to a grid row: one focus row per grid row.
		var grid: GridContainer = control.get_parent() as GridContainer
		var previous: Control = lines.back()[0]
		if grid != null and previous.get_parent() == grid and previous.get_index() / grid.columns == control.get_index() / grid.columns:
			lines.back().append(control)
		else:
			lines.append([control])
	lines.append([_done])
	FocusChain.rows(lines)

func _on_tab_changed(index: int) -> void:
	app.options_tab = index
	_link.call_deferred()
	# Focus follows the tab only when it was on a row of the page that just closed; a player moving
	# along the tab strip itself stays on the strip.
	var focused: Control = host.get_viewport().gui_get_focus_owner() if host.is_inside_tree() else null
	if focused == null or not focused.is_visible_in_tree():
		var first: Control = _first_row(index)
		if first != null: first.grab_focus.call_deferred()
	UiMotion.stagger(_pages[TAB_TITLES[index]].get_children())

## LB/RB (Q/E) switch tabs from anywhere; not while a rebind is waiting.
func _tab_keys(event: InputEvent) -> void:
	if not _modal.is_empty() or not is_instance_valid(_tabs) or not _tabs.is_visible_in_tree(): return
	var step: int = 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER: step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER: step = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q: step = -1
		elif event.physical_keycode == KEY_E: step = 1
	if step == 0: return
	var next: int = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
	var first: Control = _first_row(next)
	_tabs.current_tab = next
	if first != null: first.grab_focus()
	UiScreen.ui_cue(app, "ui_move")
	host.get_viewport().set_input_as_handled()

## Controls: two columns of binding rows, each the action's name and its keyboard and controller
## glyphs; a press opens the rebinding modal. The left column is flight (move, aim), the right
## everything else (weapons, abilities, menus, dialogue skip). The caption under the panel explains
## the rebind (BINDING_CAPTION), so the page carries no header note.
func _build_controls(parent: Node) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var left: Array = []
	var right: Array = []
	for action: String in InputBindings.ACTIONS:
		if action.begins_with("move_") or action.begins_with("aim_"): left.append(action)
		else: right.append(action)
	for row_index: int in range(maxi(left.size(), right.size())):
		for column: Array in [left, right]:
			if row_index < column.size():
				_binding_row(grid, str(column[row_index]))
			else:
				# A grid fills row by row: an empty cell keeps the shorter column's rows in place.
				var gap := Control.new()
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(gap)
	if app.platform.online: menu_action(parent, "STEAM CONTROLLER LAYOUT", func() -> void: app.platform.show_input_bindings())

func _binding_row(parent: Node, action: String) -> Button:
	var row: Button = app.button(parent, str(InputBindings.ACTIONS[action]), Rect2(0, 0, 0, 44), _capture_binding.bind(action))
	_row_hover(row)
	row.name = "Bind_" + action
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# No minimum width: the two columns share the page's width, so Controls keeps every tab's size.
	row.custom_minimum_size = Vector2(0, 44)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		row.add_theme_stylebox_override(state, row.get_theme_stylebox(state, &"CheckButton"))
	row.add_theme_font_override("font", row.get_theme_font("font", &"CheckButton"))
	row.add_theme_font_size_override("font_size", UiTokens.TEXT_M)
	for ink: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		row.add_theme_color_override(ink, row.get_theme_color(ink, &"CheckButton"))
	var chips := HBoxContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("separation", 10)
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	chips.offset_left = -170
	chips.offset_right = -12
	row.add_child(chips)
	for device: String in [InputPrompts.KEYBOARD_MOUSE, InputPrompts.PAD]:
		_chip(chips, InputPrompts.shared().prompt_for(action, device, InputPrompts.shared().family))
	return row

## One binding glyph: the Kenney texture, or its text in a mono chip when there is none (coral "?"
## when the action has no binding on that device).
static func _chip(parent: Node, prompt: Dictionary) -> void:
	if prompt.texture != null:
		var glyph := TextureRect.new()
		glyph.texture = prompt.texture
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# A wide keycap (SPACE, SHIFT) keeps a letter key's height and takes the width it needs.
		glyph.custom_minimum_size = Vector2(32.0 * maxf(1.0, float(prompt.texture.get_width()) / maxf(1.0, float(prompt.texture.get_height()))), 32)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(glyph)
		return
	var text := Label.new()
	text.text = str(prompt.text)
	text.theme_type_variation = UiTokens.MONO_LABEL
	text.add_theme_font_size_override("font_size", UiTokens.TEXT_XS)
	text.add_theme_color_override("font_color", VisualStyle.CORAL if bool(prompt.missing) else UiTokens.INK)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)

## The rebinding modal: dims the screen, shows the action and its current glyphs, and waits. main.gd's
## `_input` takes the next key/button/stick (or Escape) and rebuilds this screen, which closes it; a
## ring runs down REBIND_SECONDS and cancels it if nothing comes.
func _capture_binding(action: String) -> void:
	app.rebind_action = action
	return_action = action
	var focused: Control = app.get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	var shade := ColorRect.new()
	shade.name = "RebindShade"
	shade.color = Color(UiTokens.SCRIM, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UiLayout.mark_bleed(shade)
	host.add_child(shade)
	UiLayout.cover(shade, host, (host.get_parent() as Control).size if host.get_parent() is Control else UiLayout.BASE_SIZE)
	var rect := Rect2(390, 250, 500, 300)
	var card: Panel = UiKit.glass(host, rect)
	card.name = "RebindCard"
	# Opaque: the rows behind must not read through the card that is asking for input.
	var face: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.GLASS_RAISED, 1.0), Color(UiTokens.FOCUS, 0.7), 1, UiTokens.RADIUS_PANEL, true)
	face.shadow_size = UiTokens.FOCUS_GLOW_SIZE
	card.add_theme_stylebox_override("panel", face)
	var kicker: Label = centered_label(host, "REBIND", rect.position + Vector2(30, 30), Vector2(rect.size.x - 60, 18), UiTokens.TEXT_XS, UiTokens.KICKER)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	var title: Label = centered_label(host, str(InputBindings.ACTIONS[action]).to_upper(), rect.position + Vector2(30, 52), Vector2(rect.size.x - 60, 44), UiTokens.TEXT_XL, WHITE)
	var body: Label = centered_label(host, "Press a key, mouse button or controller input.", rect.position + Vector2(30, 104), Vector2(rect.size.x - 60, 24), UiTokens.TEXT_M, MUTED)
	var current := HBoxContainer.new()
	current.alignment = BoxContainer.ALIGNMENT_CENTER
	current.add_theme_constant_override("separation", 16)
	current.position = rect.position + Vector2(30, 142)
	current.size = Vector2(rect.size.x - 60, 40)
	host.add_child(current)
	for device: String in [InputPrompts.KEYBOARD_MOUSE, InputPrompts.PAD]:
		_chip(current, InputPrompts.shared().prompt_for(action, device, InputPrompts.shared().family))
	var timer := MenuDraw.new(func(canvas: MenuDraw) -> void:
		var centre: Vector2 = canvas.size * 0.5
		canvas.draw_arc(centre, 14.0, 0.0, TAU, 40, UiTokens.TRACK, 3.0, true)
		canvas.draw_arc(centre, 14.0, -PI * 0.5, -PI * 0.5 + TAU * canvas.progress, 40, UiTokens.FOCUS, 3.0, true))
	timer.position = rect.position + Vector2(rect.size.x * 0.5 - 16, 200)
	timer.size = Vector2(32, 32)
	host.add_child(timer)
	var cancel := PromptHints.new([["ui_cancel", "CANCEL"]])
	cancel.position = rect.position + Vector2(rect.size.x * 0.5 - 60, 246)
	host.add_child(cancel)
	_modal.assign([shade, card, kicker, title, body, current, timer, cancel])
	for node: Control in _modal: UiMotion.enter(node)
	var countdown: Tween = UiMotion.tween(timer)
	countdown.tween_property(timer, "progress", 0.0, REBIND_SECONDS).from(1.0)
	countdown.tween_callback(func() -> void:
		if app.rebind_action == action:
			app.rebind_action = ""
			app._show_options())

func rebind_open() -> bool:
	return not _modal.is_empty()
