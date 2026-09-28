class_name InputPrompts
extends RefCounted
## Device-aware input prompts (modernization M11). Tracks the device the player touched last
## (keyboard/mouse or a pad, and the pad's family) and turns an action's CURRENT InputMap binding
## for that device into a Kenney Input Prompts glyph (CC0, assets/prompts/). A binding with no
## glyph on disk draws as a text chip; an action with no binding for the device is reported
## (`missing`), never drawn blank. Nothing here hardcodes which key an action uses: rebinding
## through InputBindings changes the glyph on the next draw.
##
## One shared instance, fed by main.gd's `_input`. Tests make their own.

signal device_changed(device: String, family: String)

const KEYBOARD_MOUSE: String = "keyboard_mouse"
const PAD: String = "pad"
const FAMILIES: Array[String] = ["xbox", "playstation", "steamdeck", "generic"]
const ROOT: String = "res://assets/prompts"
## The three secondary slots, in slot order (the HUD dock and the build readout index this).
const SLOT_ACTIONS: Array[String] = ["ability_primary", "ability_secondary", "ability_tertiary"]
## Keyboard/mouse aim has no InputMap binding: the ship aims at the pointer (main.gd). Said here,
## once, so the prompt shows the mouse instead of reporting four unbound actions.
const POINTER_ACTIONS: Array[String] = ["aim_up", "aim_down", "aim_left", "aim_right"]
## Below these a pad's drift or a mouse's jitter is not the player picking up that device.
const AXIS_THRESHOLD: float = 0.4
const MOUSE_MOTION_THRESHOLD: float = 3.0

## button_index -> [xbox file, playstation file, steamdeck file, xbox text, playstation text, deck text]
const PAD_BUTTONS: Dictionary = {
	JOY_BUTTON_A: ["xbox_button_a", "playstation_button_cross", "steamdeck_button_a", "A", "CROSS", "A"],
	JOY_BUTTON_B: ["xbox_button_b", "playstation_button_circle", "steamdeck_button_b", "B", "CIRCLE", "B"],
	JOY_BUTTON_X: ["xbox_button_x", "playstation_button_square", "steamdeck_button_x", "X", "SQUARE", "X"],
	JOY_BUTTON_Y: ["xbox_button_y", "playstation_button_triangle", "steamdeck_button_y", "Y", "TRIANGLE", "Y"],
	JOY_BUTTON_BACK: ["xbox_button_view", "playstation5_button_create", "steamdeck_button_view", "VIEW", "CREATE", "VIEW"],
	JOY_BUTTON_START: ["xbox_button_menu", "playstation5_button_options", "steamdeck_button_options", "MENU", "OPTIONS", "MENU"],
	JOY_BUTTON_LEFT_SHOULDER: ["xbox_lb", "playstation_trigger_l1", "steamdeck_button_l1", "LB", "L1", "L1"],
	JOY_BUTTON_RIGHT_SHOULDER: ["xbox_rb", "playstation_trigger_r1", "steamdeck_button_r1", "RB", "R1", "R1"],
	JOY_BUTTON_LEFT_STICK: ["xbox_ls", "playstation_button_l3", "steamdeck_stick_l_press", "LS", "L3", "L3"],
	JOY_BUTTON_RIGHT_STICK: ["xbox_rs", "playstation_button_r3", "steamdeck_stick_r_press", "RS", "R3", "R3"],
	JOY_BUTTON_DPAD_UP: ["xbox_dpad_up", "playstation_dpad_up", "steamdeck_dpad_up", "D-UP", "D-UP", "D-UP"],
	JOY_BUTTON_DPAD_DOWN: ["xbox_dpad_down", "playstation_dpad_down", "steamdeck_dpad_down", "D-DOWN", "D-DOWN", "D-DOWN"],
	JOY_BUTTON_DPAD_LEFT: ["xbox_dpad_left", "playstation_dpad_left", "steamdeck_dpad_left", "D-LEFT", "D-LEFT", "D-LEFT"],
	JOY_BUTTON_DPAD_RIGHT: ["xbox_dpad_right", "playstation_dpad_right", "steamdeck_dpad_right", "D-RIGHT", "D-RIGHT", "D-RIGHT"],
}
## "axis:direction" -> [kenney stem after the family prefix, text]. Sticks share a stem pattern
## across all three families; triggers do not, so they are spelled per family below.
const PAD_AXES: Dictionary = {
	"0:-1": ["stick_l_left", "LS LEFT"], "0:1": ["stick_l_right", "LS RIGHT"],
	"1:-1": ["stick_l_up", "LS UP"], "1:1": ["stick_l_down", "LS DOWN"],
	"2:-1": ["stick_r_left", "RS LEFT"], "2:1": ["stick_r_right", "RS RIGHT"],
	"3:-1": ["stick_r_up", "RS UP"], "3:1": ["stick_r_down", "RS DOWN"],
}
const PAD_TRIGGERS: Dictionary = {
	JOY_AXIS_TRIGGER_LEFT: ["xbox_lt", "playstation_trigger_l2", "steamdeck_button_l2", "LT", "L2", "L2"],
	JOY_AXIS_TRIGGER_RIGHT: ["xbox_rt", "playstation_trigger_r2", "steamdeck_button_r2", "RT", "R2", "R2"],
}
const MOUSE_BUTTONS: Dictionary = {
	MOUSE_BUTTON_LEFT: ["mouse_left", "LMB"], MOUSE_BUTTON_RIGHT: ["mouse_right", "RMB"],
	MOUSE_BUTTON_MIDDLE: ["mouse_scroll", "MMB"], MOUSE_BUTTON_WHEEL_UP: ["mouse_scroll_up", "WHEEL UP"],
	MOUSE_BUTTON_WHEEL_DOWN: ["mouse_scroll_down", "WHEEL DOWN"],
}

static var _shared: InputPrompts
static var _textures: Dictionary = {}

var device: String = KEYBOARD_MOUSE
var family: String = "xbox"

static func shared() -> InputPrompts:
	if _shared == null: _shared = InputPrompts.new()
	return _shared

## Pad family from the SDL name Godot reports. Anything unrecognised is "generic" and wears the
## Xbox set, which is the layout SDL maps every pad onto.
static func family_for_name(joy_name: String) -> String:
	var name: String = joy_name.to_lower()
	if name.contains("steam deck") or name.contains("steamdeck"): return "steamdeck"
	for token: String in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony"]:
		if name.contains(token): return "playstation"
	for token: String in ["xbox", "xinput", "x-box", "microsoft"]:
		if name.contains(token): return "xbox"
	return "generic"

static func folder_for(pad_family: String) -> String:
	return pad_family if pad_family in ["playstation", "steamdeck"] else "xbox"

## Feed every InputEvent here. Returns true when the active device (or pad family) changed.
func observe(event: InputEvent) -> bool:
	var next_device: String = ""
	var next_family: String = family
	if event is InputEventKey and event.pressed: next_device = KEYBOARD_MOUSE
	elif event is InputEventMouseButton and event.pressed: next_device = KEYBOARD_MOUSE
	elif event is InputEventMouseMotion and event.relative.length() >= MOUSE_MOTION_THRESHOLD: next_device = KEYBOARD_MOUSE
	elif event is InputEventJoypadButton and event.pressed: next_device = PAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_THRESHOLD: next_device = PAD
	if next_device.is_empty(): return false
	if next_device == PAD: next_family = _family_of(event.device)
	return select(next_device, next_family)

## Makes `next_device` (with `next_family` for a pad) the active one. Returns true on a change. For
## input that never reaches `observe` as a device event: Steam Input forwards InputEventActions
## (SteamInputService.poll calls this when the player touches a Steam controller).
func select(next_device: String, next_family: String = "") -> bool:
	if next_family.is_empty(): next_family = family
	if next_device == device and next_family == family: return false
	device = next_device
	family = next_family
	device_changed.emit(device, family)
	return true

func _family_of(joy_device: int) -> String:
	if OS.get_environment("SteamDeck") == "1": return "steamdeck"
	return family_for_name(Input.get_joy_name(joy_device))

## The prompt for `action` on the active device (or the one given). Keys:
##   texture  Texture2D or null (null: draw `text` as a chip)
##   text     short label for text surfaces and the chip ("SPACE", "LB", "?" when missing)
##   missing  the action has NO binding for that device: a reportable content bug, drawn as "?"
##   implicit the prompt comes from a rule, not a binding (keyboard/mouse aim follows the pointer)
##   path     the glyph file tried, "" when none applies
func prompt_for(action: String, for_device: String = "", for_family: String = "") -> Dictionary:
	var use_device: String = for_device if not for_device.is_empty() else device
	var use_family: String = for_family if not for_family.is_empty() else family
	var result: Dictionary = {"action": action, "device": use_device, "family": use_family, "texture": null, "text": "?", "missing": true, "implicit": false, "path": ""}
	var event: InputEvent = binding_for(action, use_device)
	if event == null:
		if use_device == KEYBOARD_MOUSE and action in POINTER_ACTIONS:
			result.merge({"path": "%s/%s/mouse_move.png" % [ROOT, KEYBOARD_MOUSE], "text": "MOUSE", "missing": false, "implicit": true}, true)
			result.texture = _texture(result.path)
		return result
	result.missing = false
	var stem_text: Array = _describe(event, use_family)
	result.text = str(stem_text[1])
	if not str(stem_text[0]).is_empty():
		result.path = "%s/%s/%s.png" % [ROOT, KEYBOARD_MOUSE if use_device == KEYBOARD_MOUSE else folder_for(use_family), stem_text[0]]
		result.texture = _texture(result.path)
	return result

func glyph_for(action: String) -> Texture2D:
	return prompt_for(action).texture

func text_for(action: String) -> String:
	return str(prompt_for(action).text)

## Every action in InputBindings.ACTIONS with no binding for that device. Empty is the healthy answer.
func unbound_actions(for_device: String, for_family: String = "xbox") -> Array[String]:
	var result: Array[String] = []
	for action: String in InputBindings.ACTIONS:
		if bool(prompt_for(action, for_device, for_family).missing): result.append(action)
	return result

## The first binding of `action` that belongs to `for_device`, straight from the InputMap.
static func binding_for(action: String, for_device: String) -> InputEvent:
	if not InputMap.has_action(action): return null
	for event: InputEvent in InputMap.action_get_events(action):
		var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		var keyboard_mouse: bool = event is InputEventKey or event is InputEventMouseButton
		if (for_device == PAD and pad) or (for_device == KEYBOARD_MOUSE and keyboard_mouse): return event
	return null

## [kenney file stem or "", display text] for one bound event.
func _describe(event: InputEvent, pad_family: String) -> Array:
	var column: int = maxi(0, ["xbox", "playstation", "steamdeck"].find(folder_for(pad_family)))
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# The glyph shows the key the player's layout prints there (W on QWERTY is Z on AZERTY).
		# The headless display server has no layout and errors on the call.
		if event.physical_keycode != 0 and DisplayServer.get_name() != "headless":
			var local: int = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
			if local != 0: code = local
		var name: String = OS.get_keycode_string(code)
		var stem: String = "keyboard_" + name.to_lower().replace(" ", "_")
		# Word keys use Kenney's icon variant: "SPACE" printed on a key is unreadable at HUD size.
		if stem in ["keyboard_space", "keyboard_shift", "keyboard_tab"]: stem += "_icon"
		return [stem, name.to_upper()]
	if event is InputEventMouseButton:
		var mouse: Array = MOUSE_BUTTONS.get(event.button_index, ["", "MOUSE %d" % event.button_index])
		return [mouse[0], mouse[1]]
	if event is InputEventJoypadButton:
		if not PAD_BUTTONS.has(event.button_index): return ["", "BUTTON %d" % event.button_index]
		var row: Array = PAD_BUTTONS[event.button_index]
		return [row[column], row[column + 3]]
	if event is InputEventJoypadMotion:
		if PAD_TRIGGERS.has(event.axis):
			var trigger: Array = PAD_TRIGGERS[event.axis]
			return [trigger[column], trigger[column + 3]]
		var key: String = "%d:%d" % [event.axis, 1 if event.axis_value > 0.0 else -1]
		if not PAD_AXES.has(key): return ["", "AXIS %d" % event.axis]
		var prefix: String = ["xbox", "playstation", "steamdeck"][column]
		return ["%s_%s" % [prefix, PAD_AXES[key][0]], PAD_AXES[key][1]]
	return ["", event.as_text().to_upper()]

static func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

## Draw the prompt centred on `center`, `height` px tall. A glyph when there is one; otherwise a
## chip with the text (coral "?" when the action is unbound for this device).
func draw_prompt(canvas: CanvasItem, action: String, center: Vector2, height: float, tint: Color = Color.WHITE) -> void:
	var prompt: Dictionary = prompt_for(action)
	var texture: Texture2D = prompt.texture
	if texture != null:
		var size: Vector2 = Vector2(height * float(texture.get_width()) / maxf(1.0, float(texture.get_height())), height)
		canvas.draw_texture_rect(texture, Rect2(center - size * 0.5, size), false, tint)
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(8, int(height * 0.5))
	var text: String = str(prompt.text)
	var ink: Color = VisualStyle.CORAL if bool(prompt.missing) else tint
	var width: float = maxf(height, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + height * 0.5)
	var chip: Rect2 = Rect2(center - Vector2(width, height * 0.8) * 0.5, Vector2(width, height * 0.8))
	canvas.draw_rect(chip, Color(ink, 0.9), false, 1.0)
	canvas.draw_string(font, Vector2(chip.position.x, center.y + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, ink)
