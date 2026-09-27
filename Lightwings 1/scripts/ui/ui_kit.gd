## Generic immediate-mode UI builders shared by main.gd and any screen code.
## Pure static builders: no game state, no signals beyond the optional click callback.
class_name UiKit
extends RefCounted

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	for kind: String in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "LineEdit", "TabBar", "SpinBox"]:
		result.set_color("font_color", kind, VisualStyle.TEXT)
		result.set_color("font_hover_color", kind, VisualStyle.TEXT)
		result.set_color("font_focus_color", kind, VisualStyle.TEXT)
		result.set_color("font_pressed_color", kind, VisualStyle.ACCENT)
		result.set_color("font_disabled_color", kind, Color("62626d"))
	for kind: String in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("normal", kind, box(VisualStyle.PANEL, Color("39393f")))
		result.set_stylebox("hover", kind, box(Color("25252b"), VisualStyle.MUTED))
		result.set_stylebox("pressed", kind, box(Color("302e24"), VisualStyle.ACCENT))
		result.set_stylebox("focus", kind, box(Color.TRANSPARENT, VisualStyle.ACCENT, 2))
		result.set_stylebox("disabled", kind, box(VisualStyle.BG, Color("303036")))
	result.set_stylebox("panel", "PanelContainer", box(VisualStyle.PANEL, Color("34343b")))
	result.set_stylebox("panel", "TabContainer", box(VisualStyle.PANEL, Color("34343b")))
	result.set_stylebox("tab_selected", "TabContainer", box(VisualStyle.PANEL, VisualStyle.ACCENT))
	result.set_stylebox("tab_unselected", "TabContainer", box(VisualStyle.BG, Color("34343b")))
	result.set_color("font_selected_color", "TabContainer", VisualStyle.TEXT)
	result.set_color("font_unselected_color", "TabContainer", VisualStyle.MUTED)
	var slider_track := box(Color("3b3b43"), Color.TRANSPARENT, 0)
	slider_track.content_margin_top = 2
	slider_track.content_margin_bottom = 2
	var slider_fill := box(VisualStyle.ACCENT, Color.TRANSPARENT, 0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	result.set_stylebox("slider", "HSlider", slider_track)
	result.set_stylebox("grabber_area", "HSlider", slider_fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	result.set_color("font_placeholder_color", "LineEdit", VisualStyle.MUTED)
	return result

static func group(parent: Node) -> Control:
	var result := Control.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	if parent == null: return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	var result := Panel.new()
	result.position = rect.position
	result.size = rect.size
	result.add_theme_stylebox_override("panel",box(fill,border))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text = text
	result.position = position
	result.size = size
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, rect: Rect2, action: Callable, on_click: Callable = Callable()) -> Button:
	var result := Button.new()
	result.clip_text = true
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(result)
	result.pressed.connect(func() -> void:
		if on_click.is_valid(): on_click.call()
		action.call())
	return result

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var result := ProgressBar.new()
	result.position = rect.position
	result.size = rect.size
	result.show_percentage = false
	result.add_theme_font_size_override("font_size",1)
	result.add_theme_stylebox_override("background",box(Color("1a202a"),Color(0,0,0,0),0))
	result.add_theme_stylebox_override("fill",box(color,Color(0,0,0,0),0))
	parent.add_child(result)
	result.size = rect.size
	return result
