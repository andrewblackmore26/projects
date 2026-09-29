class_name PromptHints
extends HBoxContainer
## A row of input hints for a menu footer (modernization M15): "[glyph] Select  [glyph] Back".
## Glyphs follow the device in hand (InputPrompts), and redraw when it changes. A hint's source is
## an InputMap action ("ui_accept", "ui_cancel", "dialogue_skip", any game action), several of
## them joined by "|" ("ui_cancel|map": one caption, both glyphs), or one of the menu gestures below
## that no single action names: "change" (left/right), "navigate" (up/down), "tabs" (the two
## tab-switch keys, shown as a pair) and the map's "map_move", "map_pan" and "map_zoom".
## M19 review: MOVE and ADJUST read apart on a keyboard (up+down against left+right keys; the old
## arrow-cluster glyphs differed by one highlighted key at 26 px).

const HEIGHT: float = 26.0
## gesture -> [keyboard stems, pad stems (family prefix added)]
const GESTURES: Dictionary = {
	"change": [["keyboard_arrow_left", "keyboard_arrow_right"], ["dpad_horizontal"]],
	"navigate": [["keyboard_arrow_up", "keyboard_arrow_down"], ["dpad_vertical"]],
	"tabs": [["keyboard_q", "keyboard_e"], ["lb", "rb"]],
	"map_move": [["keyboard_arrows_all"], ["dpad"]],
	"map_pan": [["mouse_left", "mouse_move"], ["stick_r"]],
	"map_zoom": [["mouse_scroll_vertical"], ["lt", "rt"]],
}
## The shoulder and trigger glyph stems per family ("lb" -> xbox_lb, playstation_trigger_l1,
## steamdeck_button_l1).
const SHOULDERS: Dictionary = {
	"xbox": {"lb": "xbox_lb", "rb": "xbox_rb", "lt": "xbox_lt", "rt": "xbox_rt"},
	"playstation": {"lb": "playstation_trigger_l1", "rb": "playstation_trigger_r1", "lt": "playstation_trigger_l2", "rt": "playstation_trigger_r2"},
	"steamdeck": {"lb": "steamdeck_button_l1", "rb": "steamdeck_button_r1", "lt": "steamdeck_button_l2", "rt": "steamdeck_button_r2"},
}

## [[source, caption], ...]
var hints: Array = []
var ink: Color = UiTokens.INK_MUTED

func _init(items: Array = []) -> void:
	hints = items
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	rebuild()
	InputPrompts.shared().device_changed.connect(_on_device_changed)

func _on_device_changed(_device: String, _family: String) -> void:
	rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for index: int in range(hints.size()):
		var hint: Array = hints[index]
		if index > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = UiTokens.SPACE_4
			add_child(gap)
		for texture: Texture2D in textures_for(str(hint[0])):
			var glyph := TextureRect.new()
			glyph.texture = texture
			glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# As wide as the glyph's own aspect needs (a cropped SPACE keycap is wider than tall).
			glyph.custom_minimum_size = Vector2(HEIGHT * maxf(1.0, float(texture.get_width()) / maxf(1.0, float(texture.get_height()))), HEIGHT)
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			glyph.modulate = Color(1, 1, 1, 0.9)
			add_child(glyph)
		var caption := Label.new()
		caption.text = str(hint[1])
		caption.theme_type_variation = UiTokens.KICKER_LABEL
		caption.add_theme_color_override("font_color", ink)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(caption)
	UiLayout.scale_text(self)
	# Take the row's size now, not at the container's next sort: a canvas screen measures its
	# content (UiLayout.fit_canvas) in the same frame it is built.
	size = get_combined_minimum_size()

## The glyph textures for one hint source on the active device; a text chip's texture is never
## invented: an action with no glyph on disk shows its caption alone.
static func textures_for(source: String) -> Array[Texture2D]:
	var prompts: InputPrompts = InputPrompts.shared()
	var result: Array[Texture2D] = []
	if source.contains("|"):
		for part: String in source.split("|", false): result.append_array(textures_for(part))
		return result
	if GESTURES.has(source):
		var pad: bool = prompts.device == InputPrompts.PAD
		var folder: String = InputPrompts.folder_for(prompts.family) if pad else InputPrompts.KEYBOARD_MOUSE
		for stem: String in GESTURES[source][1 if pad else 0]:
			var file: String = stem
			if pad: file = str(SHOULDERS[folder].get(stem, "")) if SHOULDERS[folder].has(stem) else "%s_%s" % [folder, stem]
			var texture: Texture2D = InputPrompts._texture("%s/%s/%s.png" % [InputPrompts.ROOT, folder, file])
			if texture != null: result.append(texture)
		return result
	var texture: Texture2D = prompts.prompt_for(source).texture
	if texture != null: result.append(texture)
	return result
