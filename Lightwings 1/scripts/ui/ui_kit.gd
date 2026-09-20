## Generic immediate-mode UI builders shared by main.gd and any screen code.
## Pure static builders: no game state, no signals beyond the optional click callback.
class_name UiKit
extends RefCounted

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
