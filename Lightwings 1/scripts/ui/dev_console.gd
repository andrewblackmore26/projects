## Dev-mode console (spec §4: "Level select and a tier-set console command...
## stays in the shipped build"). Lives OUTSIDE scripts/editor/, because every
## export preset excludes that folder and a Dev mode that cannot start in a
## shipped build is exactly the silent failure package_validation.gd must
## catch. The parser is a pure static function so it is testable headlessly,
## with no Control/scene-tree instantiation required.
class_name DevConsole
extends Control

const TOGGLE_KEY: Key = KEY_QUOTELEFT
signal command_submitted(result: Dictionary)

var line_edit: LineEdit
var log_label: Label
var open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := Panel.new()
	panel.position = Vector2(200, 300)
	panel.size = Vector2(880, 90)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	log_label = Label.new()
	log_label.position = Vector2(210, 306)
	log_label.size = Vector2(860, 20)
	log_label.add_theme_font_size_override("font_size", 12)
	add_child(log_label)
	line_edit = LineEdit.new()
	line_edit.position = Vector2(210, 330)
	line_edit.size = Vector2(860, 40)
	line_edit.placeholder_text = "tier <1-6> [element] · level <1-5> · light <n> · help"
	add_child(line_edit)
	line_edit.text_submitted.connect(_on_submit)

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
## "light <n>", "help". Anything else -- empty input, unknown command, wrong
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
		_:
			return _fail("unknown command: %s" % command)

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "command": "", "args": {}, "error": message}
