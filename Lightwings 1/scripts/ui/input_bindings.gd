class_name InputBindings
extends RefCounted

## M19 review: `dialogue_skip` (DialogueBox.SKIP_ACTION) joined the table, so the Controls tab shows
## and rebinds it like every other input.
const ACTIONS: Dictionary = {"move_up":"Move up", "move_down":"Move down", "move_left":"Move left", "move_right":"Move right", "aim_up":"Aim up", "aim_down":"Aim down", "aim_left":"Aim left", "aim_right":"Aim right", "fire":"Fire primary", "dash":"Dash", "ability_primary":"Secondary 1", "ability_secondary":"Secondary 2", "ability_tertiary":"Secondary 3", "evolve":"Evolve", "map":"Node map", "pause":"Pause", "dialogue_skip":"Skip dialogue"}
const PATH: String = "user://controls.cfg"

static func setup() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		InputMap.action_erase_events(action)
	key("move_up", KEY_W)
	key("move_down", KEY_S)
	key("move_left", KEY_A)
	key("move_right", KEY_D)
	key("ability_primary", KEY_SPACE)
	key("ability_secondary", KEY_SHIFT)
	key("ability_tertiary", KEY_Q)
	key("evolve", KEY_E)
	key("map", KEY_TAB)
	key("pause", KEY_ESCAPE)
	key("dialogue_skip", KEY_ENTER)
	key("dialogue_skip", KEY_KP_ENTER)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mouse)
	var dash_mouse := InputEventMouseButton.new()
	dash_mouse.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("dash", dash_mouse)
	axis("dash", JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	button("ability_primary", JOY_BUTTON_LEFT_SHOULDER)
	button("ability_secondary", JOY_BUTTON_RIGHT_SHOULDER)
	button("ability_tertiary", JOY_BUTTON_X)
	button("evolve", JOY_BUTTON_A)
	button("map", JOY_BUTTON_BACK)
	button("pause", JOY_BUTTON_START)
	button("dialogue_skip", JOY_BUTTON_Y)
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for action: String in ACTIONS:
			if config.has_section_key("bindings", action):
				var saved: Array = config.get_value("bindings", action)
				InputMap.action_erase_events(action)
				for encoded: Dictionary in saved:
					var event: InputEvent = decode(encoded)
					if event != null:
						InputMap.action_add_event(action, event)

static func key(action: String, code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	InputMap.action_add_event(action, event)

static func button(action: String, code: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	InputMap.action_add_event(action, event)

static func axis(action: String, code: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = code
	event.axis_value = value
	InputMap.action_add_event(action, event)

static func rebind(action: String, event: InputEvent) -> void:
	var controller: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	for old: InputEvent in InputMap.action_get_events(action):
		var was_controller: bool = old is InputEventJoypadButton or old is InputEventJoypadMotion
		if controller == was_controller:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)
	var config := ConfigFile.new()
	for name: String in ACTIONS:
		var events: Array = []
		for current: InputEvent in InputMap.action_get_events(name):
			events.append(encode(current))
		config.set_value("bindings", name, events)
	config.save(PATH)

static func describe(action: String) -> String:
	var descriptions := PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		descriptions.append(event.as_text().replace(" (Physical)", "").replace("Joypad ", ""))
	return " / ".join(descriptions)

static func encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"kind":"key", "code":event.physical_keycode if event.physical_keycode else event.keycode}
	if event is InputEventMouseButton:
		return {"kind":"mouse", "code":event.button_index}
	if event is InputEventJoypadButton:
		return {"kind":"button", "code":event.button_index}
	if event is InputEventJoypadMotion:
		return {"kind":"axis", "code":event.axis, "value":event.axis_value}
	return {}

static func decode(encoded: Dictionary) -> InputEvent:
	match str(encoded.get("kind", "")):
		"key":
			var event := InputEventKey.new()
			event.physical_keycode = int(encoded.code)
			return event
		"mouse":
			var event := InputEventMouseButton.new()
			event.button_index = int(encoded.code)
			return event
		"button":
			var event := InputEventJoypadButton.new()
			event.button_index = int(encoded.code)
			return event
		"axis":
			var event := InputEventJoypadMotion.new()
			event.axis = int(encoded.code)
			event.axis_value = float(encoded.value)
			return event
	return null
