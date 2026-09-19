class_name SteamInputService
extends RefCounted

const MANIFEST: String = "res://content/platform/steam_input_manifest.vdf"
const DIGITAL_ACTIONS: Array[String] = ["Fire", "ComponentPrimary", "ComponentSecondary", "ComponentTertiary", "Evolve", "Map", "Pause", "MenuConfirm", "MenuBack", "MenuUp", "MenuDown", "MenuLeft", "MenuRight"]
const FORWARD_ACTIONS: Dictionary = {"Evolve": "evolve", "Map": "map", "Pause": "pause", "MenuConfirm": "ui_accept", "MenuBack": "ui_cancel", "MenuUp": "ui_up", "MenuDown": "ui_down", "MenuLeft": "ui_left", "MenuRight": "ui_right"}
var steam: Object
var ready: bool = false
var active: bool = false
var controller: int = 0
var is_menu: bool = true
var action_sets: Dictionary = {}
var digital_handles: Dictionary = {}
var analog_handles: Dictionary = {}
var buttons: Dictionary = {}
var movement: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
var _primary_pending: bool = false
var _secondary_pending: bool = false
var _tertiary_pending: bool = false
var _repeat_times: Dictionary = {}

func initialize(api: Object) -> bool:
	steam = api
	for method: String in ["inputInit", "runFrame", "getConnectedControllers", "activateActionSet", "getActionSetHandle", "getAnalogActionHandle", "getDigitalActionHandle", "getAnalogActionData", "getDigitalActionData"]:
		if not steam.has_method(method):
			return false
	if steam.has_method("setInputActionManifestFilePath"):
		var path: String = _manifest_path()
		if not path.is_empty():
			steam.call("setInputActionManifestFilePath", path)
	ready = bool(steam.call("inputInit", true))
	if not ready:
		return false
	for action_set: String in ["Gameplay", "Menu"]:
		action_sets[action_set] = int(steam.call("getActionSetHandle", action_set))
	for action: String in DIGITAL_ACTIONS:
		digital_handles[action] = int(steam.call("getDigitalActionHandle", action))
	for action: String in ["Move", "Aim", "MenuNavigate"]:
		analog_handles[action] = int(steam.call("getAnalogActionHandle", action))
	return ready

func set_context(menu_context: bool) -> void:
	if menu_context == is_menu:
		return
	_release_actions()
	is_menu = menu_context
	if ready and controller != 0:
		steam.call("activateActionSet", controller, int(action_sets.get("Menu" if is_menu else "Gameplay", 0)))

func poll(delta: float) -> void:
	if not ready:
		return
	steam.call("runFrame")
	var controllers: Variant = steam.call("getConnectedControllers")
	if not controllers is Array or controllers.is_empty():
		_release_actions()
		controller = 0
		active = false
		return
	var first: int = int(controllers[0])
	if first != controller:
		_release_actions()
		controller = first
		steam.call("activateActionSet", controller, int(action_sets.get("Menu" if is_menu else "Gameplay", 0)))
	active = false
	movement = _analog("Move") if not is_menu else Vector2.ZERO
	aim = _analog("Aim") if not is_menu else Vector2.ZERO
	var navigation: Vector2 = _analog("MenuNavigate") if is_menu else Vector2.ZERO
	for action: String in DIGITAL_ACTIONS:
		var down: bool = _digital(action)
		if is_menu and action in ["MenuUp", "MenuDown", "MenuLeft", "MenuRight"]:
			down = down or {"MenuUp": navigation.y < -0.5, "MenuDown": navigation.y > 0.5, "MenuLeft": navigation.x < -0.5, "MenuRight": navigation.x > 0.5}[action]
		var previous: bool = bool(buttons.get(action, false))
		if down and not previous:
			if action == "ComponentPrimary": _primary_pending = true
			if action == "ComponentSecondary": _secondary_pending = true
			if action == "ComponentTertiary": _tertiary_pending = true
		if down != previous and FORWARD_ACTIONS.has(action):
			_send_action(str(FORWARD_ACTIONS[action]), down)
		if action in ["MenuUp", "MenuDown", "MenuLeft", "MenuRight"]:
			if down and not previous:
				_repeat_times[action] = 0.35
			elif down:
				_repeat_times[action] = float(_repeat_times.get(action, 0.35)) - delta
				if float(_repeat_times[action]) <= 0.0:
					_send_action(str(FORWARD_ACTIONS[action]), true)
					_repeat_times[action] = 0.1
		buttons[action] = down

func get_command(fallback_aim: Vector2 = Vector2.UP) -> ShipCommand:
	if not ready or not active or controller == 0 or is_menu:
		return null
	var command: ShipCommand = ShipCommand.new()
	command.movement = movement.limit_length(1.0)
	command.aim = aim.normalized() if aim.length() > 0.12 else fallback_aim
	command.fire = bool(buttons.get("Fire", false))
	command.ability_primary = _primary_pending
	command.ability_secondary = _secondary_pending
	command.secondary_held = bool(buttons.get("ComponentSecondary", false))
	command.secondaries = [_primary_pending, _secondary_pending, _tertiary_pending]
	_tertiary_pending = false
	_primary_pending = false
	_secondary_pending = false
	return command

func _analog(action: String) -> Vector2:
	var handle: int = int(analog_handles.get(action, 0))
	if handle == 0:
		return Vector2.ZERO
	var data: Variant = steam.call("getAnalogActionData", controller, handle)
	if not data is Dictionary or not bool(data.get("active", false)):
		return Vector2.ZERO
	active = true
	return Vector2(float(data.get("x", 0.0)), -float(data.get("y", 0.0)))

func _digital(action: String) -> bool:
	var handle: int = int(digital_handles.get(action, 0))
	if handle == 0:
		return false
	var data: Variant = steam.call("getDigitalActionData", controller, handle)
	if not data is Dictionary or not bool(data.get("active", false)):
		return false
	active = true
	return bool(data.get("state", false))

func _release_actions() -> void:
	_tertiary_pending = false
	for action: String in FORWARD_ACTIONS:
		if bool(buttons.get(action, false)):
			_send_action(str(FORWARD_ACTIONS[action]), false)
	buttons.clear()
	_repeat_times.clear()
	movement = Vector2.ZERO
	aim = Vector2.ZERO
	_primary_pending = false
	_secondary_pending = false

func _send_action(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func show_bindings() -> bool:
	return ready and controller != 0 and steam.has_method("showBindingPanel") and bool(steam.call("showBindingPanel", controller))

func shutdown() -> void:
	_release_actions()
	if ready and is_instance_valid(steam) and steam.has_method("inputShutdown"):
		steam.call("inputShutdown")
	ready = false
	active = false

static func _manifest_path() -> String:
	# Steam needs a real disk path, including when the game is packed in a PCK.
	if not FileAccess.file_exists(MANIFEST):
		return ""
	var destination: String = "user://steam_input"
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return ""
	var source: DirAccess = DirAccess.open(MANIFEST.get_base_dir())
	if source == null:
		return ""
	for filename: String in source.get_files():
		if filename.get_extension().to_lower() != "vdf":
			continue
		var output: FileAccess = FileAccess.open(destination.path_join(filename), FileAccess.WRITE)
		if output == null:
			return ""
		output.store_buffer(FileAccess.get_file_as_bytes(MANIFEST.get_base_dir().path_join(filename)))
		output.close()
	return ProjectSettings.globalize_path(destination.path_join(MANIFEST.get_file()))
