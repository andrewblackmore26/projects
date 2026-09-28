## Dev-mode console (spec §4: "Level select and a tier-set console command...
## stays in the shipped build"). Lives OUTSIDE scripts/editor/, because every
## export preset excludes that folder and a Dev mode that cannot start in a
## shipped build is exactly the silent failure package_validation.gd must
## catch. The parser is a pure static function so it is testable headlessly,
## with no Control/scene-tree instantiation required.
class_name DevConsole
extends Control

const TOGGLE_KEY: Key = KEY_QUOTELEFT
## `cam <layer> on|off` -> the GameTuning switch it flips.
const CAM_LAYERS: Dictionary = {"lag": "cam.lag_on", "zoom": "cam.zoom_on", "aim": "cam.aim_on", "shake": "shake.on"}
signal command_submitted(result: Dictionary)

var line_edit: LineEdit
var log_label: Label
var open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiLayout.mark_bleed(self) # a full-screen holder; the panel inside is what is laid out
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	log_label = Label.new()
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(log_label)
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "tier <1-6> [element] · level <1-5> · light <n> · tune <key> [v] · cam <layer> on|off · help"
	add_child(line_edit)
	line_edit.text_submitted.connect(_on_submit)
	_layout()

var _panel: Panel

## M6: the 880 px panel centred on the screen (it was pinned at (200, 300) of a 1280x800 frame),
## narrowed to the safe rect on a small UI.
func _layout() -> void:
	if _panel == null: return
	var width: float = minf(880.0, size.x - UiLayout.SAFE_MARGIN * 2.0)
	var origin := Vector2(size.x * 0.5 - width * 0.5, size.y * 0.5 - 100.0)
	_panel.position = origin
	_panel.size = Vector2(width, 90)
	log_label.position = origin + Vector2(10, 6)
	log_label.size = Vector2(width - 20, 20)
	line_edit.position = origin + Vector2(10, 30)
	line_edit.size = Vector2(width - 20, 40)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()

## Pauses the scene tree while open, so WASD does not fly the ship (spec
## P5b explicit requirement). process_mode ALWAYS keeps this node itself
## responsive under that pause.
func toggle() -> void:
	open = not open
	visible = open
	get_tree().paused = open
	if open:
		line_edit.grab_focus()
	else:
		line_edit.release_focus()

func _on_submit(text: String) -> void:
	var result: Dictionary = parse(text)
	log_label.text = ("OK: " + text) if bool(result.ok) else ("ERROR: " + str(result.error))
	command_submitted.emit(result)
	line_edit.text = ""

## Pure parser. Accepts exactly: "tier <1-6> [element]", "level <1-5>",
## "light <n>", "tune <key> [value]", "tune reset", "tune dump", "cam <layer> on|off",
## "cam <name> [value]", "help". Anything else -- empty input, unknown command, wrong
## argument count, out-of-range numbers, an unknown element -- is rejected
## with ok=false and a reason, never a partial/best-effort application.
static func parse(text: String) -> Dictionary:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return _fail("Empty command")
	var parts: PackedStringArray = trimmed.split(" ", false)
	if parts.is_empty():
		return _fail("Empty command")
	var command: String = parts[0].to_lower()
	match command:
		"help":
			if parts.size() != 1:
				return _fail("help takes no arguments")
			return {"ok": true, "command": "help", "args": {}, "error": ""}
		"tier":
			if parts.size() < 2 or parts.size() > 3:
				return _fail("usage: tier <1-6> [element]")
			if not parts[1].is_valid_int():
				return _fail("tier must be an integer")
			var tier: int = int(parts[1])
			if tier < 1 or tier > GameTuning.MAX_TIER:
				return _fail("tier must be between 1 and %d" % GameTuning.MAX_TIER)
			var element: String = ""
			if parts.size() == 3:
				element = parts[2].to_lower()
				if element not in GameTuning.ELEMENTS:
					return _fail("unknown element: %s" % element)
			return {"ok": true, "command": "tier", "args": {"tier": tier, "element": element}, "error": ""}
		"level":
			if parts.size() != 2:
				return _fail("usage: level <1-5>")
			if not parts[1].is_valid_int():
				return _fail("level must be an integer")
			var level: int = int(parts[1])
			if level < 1 or level > GameTuning.LEVEL_RADIUS.size():
				return _fail("level must be between 1 and %d" % GameTuning.LEVEL_RADIUS.size())
			return {"ok": true, "command": "level", "args": {"level": level}, "error": ""}
		"light":
			if parts.size() != 2:
				return _fail("usage: light <n>")
			if not (parts[1].is_valid_float() or parts[1].is_valid_int()):
				return _fail("light must be a number")
			var amount: float = float(parts[1])
			if amount < 0.0:
				return _fail("light must be >= 0")
			return {"ok": true, "command": "light", "args": {"amount": amount}, "error": ""}
		# Camera and movement spec: every number in GameTuning.FEEL_DEFAULTS, live. The parser
		# validates the key here so a typo is an error in the console, not a silent no-op.
		"tune":
			if parts.size() == 2 and parts[1].to_lower() in ["reset", "dump"]:
				return {"ok": true, "command": "tune", "args": {"action": parts[1].to_lower()}, "error": ""}
			if parts.size() == 2:
				if not GameTuning.FEEL_DEFAULTS.has(parts[1]):
					return _fail("unknown tuning key: %s" % parts[1])
				return {"ok": true, "command": "tune", "args": {"action": "get", "key": parts[1]}, "error": ""}
			if parts.size() != 3:
				return _fail("usage: tune <key> [value] · tune reset · tune dump")
			if not GameTuning.FEEL_DEFAULTS.has(parts[1]):
				return _fail("unknown tuning key: %s" % parts[1])
			if not (parts[2].is_valid_float() or parts[2].is_valid_int()):
				return _fail("tune value must be a number")
			return {"ok": true, "command": "tune", "args": {"action": "set", "key": parts[1], "value": float(parts[2])}, "error": ""}
		# M10: the camera's shorthand for `tune`, so it needs no handler of its own. `cam lag off`
		# switches a layer (lag, zoom, aim, shake); `cam <name> [value]` reads or sets `cam.<name>`,
		# or a full `shake.*` / `hitstop.*` key.
		"cam":
			if parts.size() == 3 and CAM_LAYERS.has(parts[1].to_lower()) and parts[2].to_lower() in ["on", "off"]:
				return {"ok": true, "command": "tune", "args": {"action": "set", "key": CAM_LAYERS[parts[1].to_lower()], "value": 1.0 if parts[2].to_lower() == "on" else 0.0}, "error": ""}
			if parts.size() < 2 or parts.size() > 3:
				return _fail("usage: cam <lag|zoom|aim|shake> on|off · cam <name> [value]")
			var key: String = parts[1] if parts[1].begins_with("shake.") or parts[1].begins_with("hitstop.") else "cam." + parts[1]
			if not GameTuning.FEEL_DEFAULTS.has(key):
				return _fail("unknown camera key: %s" % parts[1])
			if parts.size() == 2:
				return {"ok": true, "command": "tune", "args": {"action": "get", "key": key}, "error": ""}
			if not (parts[2].is_valid_float() or parts[2].is_valid_int()):
				return _fail("cam value must be a number")
			return {"ok": true, "command": "tune", "args": {"action": "set", "key": key, "value": float(parts[2])}, "error": ""}
		_:
			return _fail("unknown command: %s" % command)

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "command": "", "args": {}, "error": message}
