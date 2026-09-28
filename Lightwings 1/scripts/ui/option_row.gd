class_name OptionRow
extends Button
## One Options row as a pad-friendly spinner (modernization M15): the caption on the left, the value
## on the right between two chevrons. Left/right (ui_left/ui_right: arrows, d-pad, stick) step the
## value and keep focus on the row; confirm steps it forward and wraps. A mouse clicks the chevron
## halves or rolls the wheel. A percentage row also carries an HSlider for the mouse; the slider takes
## no focus, so the pad only ever lands on the row.
##
## `choices` are the stored values, `labels` what the row prints for each; `on_change(value)` is
## called with the new stored value (the screen writes the setting, applies and saves it).

const VALUE_WIDTH: float = 190.0
const SLIDER_WIDTH: float = 250.0
const CHEVRON: float = 5.0

var choices: Array = []
var labels: PackedStringArray = []
var index: int = 0
var on_change: Callable
## The app whose soundscape ticks on a change (UiScreen.ui_cue); null is silent.
var sound_owner: Node
var value_label: Label
var slider: HSlider

## Builds the row for `current` (the nearest choice is selected when it is not one of them).
func setup(caption: String, values: Array, names: PackedStringArray, current: Variant, changed: Callable, with_slider: bool = false) -> OptionRow:
	text = caption
	choices = values
	labels = names
	on_change = changed
	index = _nearest(current)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = 46
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The rows dress like the theme's toggle rows (CheckButton): flat until hovered, raised glass
	# with the gold border when focused. Same font, same ink.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, get_theme_stylebox(state, &"CheckButton"))
	add_theme_font_override("font", get_theme_font("font", &"CheckButton"))
	add_theme_font_size_override("font_size", get_theme_font_size("font_size", &"CheckButton"))
	for ink: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(ink, get_theme_color(ink, &"CheckButton"))
	value_label = Label.new()
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_font_size_override("font_size", UiTokens.TEXT_M)
	value_label.add_theme_color_override("font_color", UiTokens.INK)
	add_child(value_label)
	if with_slider:
		slider = HSlider.new()
		slider.name = "Slider"
		slider.focus_mode = Control.FOCUS_NONE
		slider.min_value = 0
		slider.max_value = choices.size() - 1
		slider.step = 1
		slider.value = index
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_child(slider)
		slider.value_changed.connect(func(value: float) -> void: _select(roundi(value)))
	resized.connect(_place)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_refresh()
	return self

func value() -> Variant:
	return choices[index]

## Steps by `delta` choices; `wrap` for confirm (cycles), clamped for left/right.
func step(delta: int, wrap: bool = false) -> void:
	var next: int = (index + delta + choices.size()) % choices.size() if wrap else clampi(index + delta, 0, choices.size() - 1)
	_select(next)

func _select(next: int) -> void:
	if next == index or next < 0 or next >= choices.size(): return
	index = next
	_refresh()
	if sound_owner != null: UiScreen.ui_cue(sound_owner, "ui_slider_tick")
	if on_change.is_valid(): on_change.call(choices[index])

func _refresh() -> void:
	if value_label != null: value_label.text = labels[index] if index < labels.size() else str(choices[index])
	if slider != null and roundi(slider.value) != index: slider.set_value_no_signal(index)
	queue_redraw()

func _nearest(current: Variant) -> int:
	var best: int = 0
	var gap: float = INF
	for i: int in range(choices.size()):
		if typeof(choices[i]) == typeof(current) and choices[i] == current: return i
		if (typeof(choices[i]) in [TYPE_INT, TYPE_FLOAT]) and (typeof(current) in [TYPE_INT, TYPE_FLOAT]):
			var d: float = absf(float(choices[i]) - float(current))
			if d < gap:
				gap = d
				best = i
	return best

## The value box at the right edge; the slider (when there is one) just left of it.
func _value_rect() -> Rect2:
	return Rect2(size.x - VALUE_WIDTH - UiTokens.SPACE_3, 0, VALUE_WIDTH, size.y)

func _place() -> void:
	var box: Rect2 = _value_rect()
	value_label.position = box.position + Vector2(CHEVRON * 4.0, 0)
	value_label.size = Vector2(box.size.x - CHEVRON * 8.0, box.size.y)
	if slider != null:
		slider.position = Vector2(box.position.x - SLIDER_WIDTH - UiTokens.SPACE_4, (size.y - 20.0) * 0.5)
		slider.size = Vector2(SLIDER_WIDTH, 20.0)

func _draw() -> void:
	var box: Rect2 = _value_rect()
	var lit: bool = has_focus()
	var y: float = box.get_center().y
	var left_ink: Color = UiTokens.FOCUS if lit and index > 0 else Color(UiTokens.INK_MUTED, 0.35 if index == 0 else 0.8)
	var right_ink: Color = UiTokens.FOCUS if lit and index < choices.size() - 1 else Color(UiTokens.INK_MUTED, 0.35 if index == choices.size() - 1 else 0.8)
	var lx: float = box.position.x + CHEVRON * 2.0
	var rx: float = box.end.x - CHEVRON * 2.0
	draw_polyline(PackedVector2Array([Vector2(lx + CHEVRON, y - CHEVRON * 1.4), Vector2(lx, y), Vector2(lx + CHEVRON, y + CHEVRON * 1.4)]), left_ink, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(rx - CHEVRON, y - CHEVRON * 1.4), Vector2(rx, y), Vector2(rx - CHEVRON, y + CHEVRON * 1.4)]), right_ink, 2.0, true)
	# Position pips under the value for short lists (a spinner shows where it is in its range).
	if slider == null and choices.size() <= 8:
		var pitch: float = 10.0
		var start: float = box.get_center().x - pitch * (choices.size() - 1) * 0.5
		for i: int in range(choices.size()):
			var at := Vector2(start + pitch * i, size.y - 7.0)
			draw_circle(at, 2.0 if i == index else 1.5, UiTokens.FOCUS if i == index else Color(UiTokens.INK_MUTED, 0.45))

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				step(1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				step(-1)
				accept_event()
			MOUSE_BUTTON_LEFT:
				var box: Rect2 = _value_rect()
				if box.has_point(event.position):
					step(-1 if event.position.x < box.get_center().x else 1)
					accept_event()

## Confirm (Enter / A / a click on the caption) steps a list forward and wraps. A percentage row
## ignores it: wrapping a volume from 100 % to 0 % on one press is a trap.
func _pressed() -> void:
	if slider == null: step(1, true)
