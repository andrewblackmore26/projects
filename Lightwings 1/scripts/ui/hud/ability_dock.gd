class_name AbilityDock
extends RefCounted
## The bottom-centre ability dock of the floating HUD (modernization M11b): the dash, the primary,
## up to three secondaries and the passives as SLOT px circles, each with its procedural glyph
## (AbilityGlyphs), a radial cooldown sweep, a ring that pulses once when the slot comes ready,
## and the bound input's glyph for the device in hand under it (InputPrompts). Passives have no
## input: they wear a small PASSIVE mark instead. Read from the sim every frame.

const SLOT: float = 44.0
const PITCH: float = 56.0
## Extra room between the active slots and the passives.
const PASSIVE_GAP: float = 12.0
const PROMPT_HEIGHT: float = 26.0
const PROMPT_GAP: float = 5.0
const PAD: float = 10.0
const READY_PULSE_SECONDS: float = 0.35
## A primary whose cooldown is shorter than this fires continuously: no sweep flicker.
const SWEEP_MIN_COOLDOWN: float = 0.35

var app: Node
var root: Control
## [{id, kind: dash|primary|secondary|passive, action, fill}], rebuilt every frame.
var slots: Array[Dictionary] = []
var _ready_pulse: Dictionary = {}
var _was_ready: Dictionary = {}

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	root = Hud.cluster(parent, "AbilityDock")
	root.draw.connect(draw_slots)

func reset() -> void:
	_ready_pulse.clear()
	_was_ready.clear()

## The dock's size for up to 7 slots; the cluster keeps it whatever the hull mounts.
func layout(size: Vector2, safe: Rect2) -> void:
	var count: int = maxi(1, slots.size())
	var passives: int = 0
	for slot: Dictionary in slots: if str(slot.kind) == "passive": passives += 1
	var width: float = PAD * 2.0 + SLOT + PITCH * float(count - 1) + (PASSIVE_GAP if passives > 0 and passives < count else 0.0)
	root.size = Vector2(width, SLOT + PROMPT_GAP + PROMPT_HEIGHT + 4.0)
	root.position = Vector2(roundf(size.x * 0.5 - width * 0.5), safe.end.y - root.size.y)

## The slots of the hull in hand, with each one's readiness 0..1. Returns whether the slot list
## changed shape (the dock resizes).
func update(dt: float) -> bool:
	var combat: CombatWorld = app.combat
	var ship: ShipDefinition = combat.player.get("definition")
	var before: int = slots.size()
	slots.clear()
	if ship == null: return before != 0
	slots.append({"id": "dash", "kind": "dash", "action": "dash", "fill": combat.dash_ready_fraction(), "sweep": true})
	var primary: AbilityDefinition = AbilityCatalog.get_definition(ship.primary)
	slots.append({"id": ship.primary, "kind": "primary", "action": "fire", "fill": _fill(float(combat.player.get("fire_cd", 0.0)), primary), "sweep": primary != null and primary.cooldown >= SWEEP_MIN_COOLDOWN})
	var cooldowns: Dictionary = combat.player.get("cooldowns", {})
	for index: int in range(mini(ship.secondaries.size(), InputPrompts.SLOT_ACTIONS.size())):
		var definition: AbilityDefinition = AbilityCatalog.get_definition(ship.secondaries[index])
		slots.append({"id": ship.secondaries[index], "kind": "secondary", "action": InputPrompts.SLOT_ACTIONS[index], "fill": _fill(float(cooldowns.get("secondary_%d" % index, 0.0)), definition), "sweep": true})
	for id: String in ship.passives:
		slots.append({"id": id, "kind": "passive", "action": "", "fill": 1.0, "sweep": false})
	for index: int in range(slots.size()):
		var key: String = "%d:%s" % [index, slots[index].id]
		var ready: bool = float(slots[index].fill) >= 1.0
		if ready and _was_ready.has(key) and not bool(_was_ready[key]) and bool(slots[index].sweep): _ready_pulse[key] = 0.0
		_was_ready[key] = ready
	for key: Variant in _ready_pulse.keys():
		_ready_pulse[key] = float(_ready_pulse[key]) + dt
		if float(_ready_pulse[key]) >= READY_PULSE_SECONDS: _ready_pulse.erase(key)
	root.queue_redraw()
	return slots.size() != before

static func _fill(cooldown: float, definition: AbilityDefinition) -> float:
	if definition == null or cooldown <= 0.0: return 1.0
	return 1.0 - clampf(cooldown / maxf(0.001, definition.cooldown), 0.0, 1.0)

## Where slot `index` sits in the dock.
func slot_center(index: int) -> Vector2:
	var x: float = PAD + SLOT * 0.5 + PITCH * float(index)
	if str(slots[index].kind) == "passive" and index > 0: x += PASSIVE_GAP
	return Vector2(x, SLOT * 0.5 + 2.0)

func draw_slots() -> void:
	var started: int = Time.get_ticks_usec()
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat) or slots.is_empty(): return
	# A faint glass rail behind the circles ties them into one instrument.
	var rail := Rect2(Vector2(PAD * 0.5, SLOT * 0.5 + 2.0 - 5.0), Vector2(root.size.x - PAD, 10.0))
	Hud.draw_pill(root, rail, Color(UiTokens.GLASS, 0.6))
	var font: Font = Hud.font(&"body")
	var radius: float = SLOT * 0.5
	for index: int in range(slots.size()):
		var slot: Dictionary = slots[index]
		var at: Vector2 = slot_center(index)
		var fill: float = float(slot.fill)
		var ready: bool = fill >= 1.0
		var definition: AbilityDefinition = AbilityCatalog.get_definition(str(slot.id))
		var ink: Color = VisualStyle.BLUE if str(slot.kind) == "dash" else (ShipCatalog.get_color(definition.visual_color) if definition != null else VisualStyle.MUTED)
		if str(slot.kind) == "passive": ink = ink.lerp(VisualStyle.MUTED, 0.35)
		root.draw_circle(at, radius, Color(0.03, 0.036, 0.055, 0.94))
		root.draw_circle(at, radius - 1.0, Color(ink.r * 0.12, ink.g * 0.12, ink.b * 0.12, 0.9))
		AbilityGlyphs.draw(root, str(slot.id), at, radius * 0.62, 1.0 if ready else 0.45)
		if not ready and bool(slot.sweep):
			# The sweep: the part still cooling is shaded, and it shrinks clockwise from 12 o'clock.
			var points := PackedVector2Array([at])
			var from: float = -PI * 0.5 + TAU * fill
			for step: int in range(33): points.append(at + Vector2.from_angle(lerpf(from, PI * 1.5, float(step) / 32.0)) * (radius - 1.0))
			root.draw_colored_polygon(points, Color(0.0, 0.0, 0.02, 0.62))
			root.draw_arc(at, radius - 1.0, -PI * 0.5, -PI * 0.5 + TAU * fill, 40, Color(ink, 0.85), 2.0, true)
			root.draw_arc(at, radius - 1.0, 0.0, TAU, 40, Color(ink, 0.18), 1.0, true)
		else:
			root.draw_arc(at, radius - 1.0, 0.0, TAU, 40, Color(ink, 0.9 if str(slot.kind) != "passive" else 0.5), 2.0 if str(slot.kind) != "passive" else 1.0, true)
		var key: String = "%d:%s" % [index, slot.id]
		if _ready_pulse.has(key):
			var t: float = float(_ready_pulse[key]) / READY_PULSE_SECONDS
			root.draw_arc(at, radius + 1.0 + 7.0 * t, 0.0, TAU, 40, Color(ink, 0.9 * (1.0 - t)), 2.5 * (1.0 - t) + 0.5, true)
		var below := Vector2(at.x, SLOT + PROMPT_GAP + PROMPT_HEIGHT * 0.5 + 2.0)
		if str(slot.action).is_empty():
			var size: int = UiLayout.text_px(9)
			root.draw_string(font, Vector2(at.x - PITCH * 0.5, below.y + size * 0.35), "PASSIVE", HORIZONTAL_ALIGNMENT_CENTER, PITCH, size, Color(VisualStyle.MUTED, 0.85))
		else:
			InputPrompts.shared().draw_prompt(root, str(slot.action), below, PROMPT_HEIGHT, Color(1, 1, 1, 0.92 if ready else 0.6))
	Hud.draw_usec += Time.get_ticks_usec() - started
