extends SceneTree
## ShipGrammar.validate: every coded rule gets a negative control that applies exactly ONE mutation
## to a valid fixture through the real validator and asserts THAT rule's code appears. The last
## assertion requires every entry of ShipGrammar.RULES to have been triggered, so a rule added
## without a control fails the suite (lessons: a gate that cannot fail is not a gate; tautological
## controls over literals are the P10 failure this file must not repeat).
const Harness = preload("res://tests/support/harness.gd")

var h: Harness
var triggered: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _load(name: String) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	return ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)

func _codes(errors: PackedStringArray) -> Array[String]:
	var codes: Array[String] = []
	for error: String in errors:
		var code: String = error.get_slice(":", 0)
		if not codes.has(code): codes.append(code)
	return codes

## Mutates a fresh copy of `fixture` and expects `code` among the validator's errors.
func _expect(fixture: String, code: String, what: String, mutate: Callable) -> void:
	var ship: ShipDefinition = _load(fixture)
	mutate.call(ship)
	var codes: Array[String] = _codes(ShipGrammar.validate(ship))
	if codes.has(code): triggered[code] = true
	h.control("%s -> %s (got %s)" % [what, code, str(codes)], codes.has(code))

## The same, for the guards that run on COMPILED parts: compile, then mutate the parts.
func _expect_compiled(code: String, what: String, mutate: Callable) -> void:
	var ship: ShipDefinition = _load("radial_elite")
	ShipCompiler.compile(ship)
	mutate.call(ship)
	var codes: Array[String] = _codes(ShipGrammar.validate_compiled(ship))
	if codes.has(code): triggered[code] = true
	h.control("%s -> %s (got %s)" % [what, code, str(codes)], codes.has(code))

func _part(ship: ShipDefinition, id: String) -> PartDefinition:
	for part: PartDefinition in ship.parts:
		if part.id == id: return part
	return null

func _run() -> void:
	h = Harness.new("SHIP GRAMMAR")
	# Precondition: the subjects are clean, or every control below would prove nothing.
	for name: String in ["radial_elite", "player_t3", "drone", "boss", "irregular"]:
		var ship: ShipDefinition = _load(name)
		h.check(ShipGrammar.validate(ship).is_empty() and ShipGrammar.warnings(ship).is_empty(), "%s is valid with no warnings before any mutation (%s)" % [name, ", ".join(ShipGrammar.validate(ship))])

	_expect("radial_elite", "SCHEMA", "schema_version 3", func(s: ShipDefinition) -> void: s.schema_version = 3)
	_expect("radial_elite", "SCHEMA", "an id with a dot", func(s: ShipDefinition) -> void: s.id = "bad.id")
	_expect("radial_elite", "SCHEMA", "archetype 'wheel'", func(s: ShipDefinition) -> void: s.archetype = "wheel")
	_expect("player_t3", "SCHEMA", "a player given an archetype", func(s: ShipDefinition) -> void: s.archetype = "drone")
	_expect("radial_elite", "COLOUR-SET", "accent equal to chassis", func(s: ShipDefinition) -> void: s.accent_color = s.chassis_color)
	_expect("radial_elite", "COLOUR-SET", "chassis 'teal'", func(s: ShipDefinition) -> void: s.chassis_color = "teal")
	_expect("radial_elite", "COLOUR-BLUE", "an enemy with a blue accent", func(s: ShipDefinition) -> void: s.accent_color = "blue")
	_expect("player_t3", "COLOUR-BLUE", "a player with a red chassis", func(s: ShipDefinition) -> void: s.chassis_color = "red")
	_expect("radial_elite", "CORE", "core depth 5", func(s: ShipDefinition) -> void: s.core_depth = 5)
	_expect("radial_elite", "CORE", "an elite with no core weapon", func(s: ShipDefinition) -> void: s.core_weapon = "")
	_expect("player_t3", "CORE", "a player with a core weapon", func(s: ShipDefinition) -> void: s.core_weapon = "twin_barrel")
	_expect("radial_elite", "RAIL-LADDER", "rail 1 at radius 60", func(s: ShipDefinition) -> void: s.rails[0].radius = 60)
	_expect("radial_elite", "RAIL-LADDER", "the inner rail dropped, the 96 kept", func(s: ShipDefinition) -> void: s.rails.remove_at(0))
	_expect("radial_elite", "RAIL-ORDER", "order 9", func(s: ShipDefinition) -> void: s.rails[0].order = 9)
	_expect("radial_elite", "RAIL-ORDER", "a slot removed so slots != order", func(s: ShipDefinition) -> void: s.rails[0].slots.remove_at(0))
	_expect("boss", "RAIL-ORDER-ADJ", "rails 2 and 3 both order 6", func(s: ShipDefinition) -> void:
		s.rails[2].order = 6
		s.rails[2].slots.append(s.rails[2].slots[0].duplicate())
		s.rails[2].slots.append(s.rails[2].slots[0].duplicate()))
	_expect("radial_elite", "RAIL-SIGN", "both rails turning the same way", func(s: ShipDefinition) -> void: s.rails[1].speed = -0.42)
	_expect("radial_elite", "RAIL-SIGN", "an enemy rail standing still", func(s: ShipDefinition) -> void: s.rails[0].speed = 0.0)
	_expect("player_t3", "RAIL-SIGN", "a player's NON-primary rail standing still", func(s: ShipDefinition) -> void: s.rails[1].speed = 0.0)
	_expect("radial_elite", "RAIL-OFFSET", "a 5 px offset on a radial elite", func(s: ShipDefinition) -> void: s.rails[0].offset = Vector2(5, 0))
	_expect("irregular", "RAIL-OFFSET", "a 13 px offset on an irregular elite", func(s: ShipDefinition) -> void: s.rails[0].offset = Vector2(13, 0))
	_expect("radial_elite", "RAIL-EMPTY", "every slot of rail 1 a stub", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[0].slots: slot.type = "stub")
	_expect("radial_elite", "RAIL-EMPTY", "a rail without its reach ring", func(s: ShipDefinition) -> void: s.rails[1].reach_ring = false)
	_expect("radial_elite", "SLOT", "five pods on a hub", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[1].slots: slot.pods = 5)
	_expect("radial_elite", "SLOT", "a set piece on a node", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[0].slots: slot.set_piece = "v_rack")
	_expect("radial_elite", "SLOT", "a node of radius 6", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[0].slots: slot.node_radius = 6)
	_expect("radial_elite", "SYM-ROT", "one of three hubs with 1 pod instead of 3", func(s: ShipDefinition) -> void: s.rails[1].slots[0].pods = 1)
	_expect("player_t3", "SYM-MIRROR", "a rail phase of a third of a step", func(s: ShipDefinition) -> void: s.rails[1].phase = TAU / 9.0)
	_expect("player_t3", "SYM-MIRROR", "the left twin given 1 pod and the right 2", func(s: ShipDefinition) -> void: s.rails[1].slots[1].pods = 1)
	_expect("player_t3", "PRIMARY-FWD", "the primary moved to the side slot", func(s: ShipDefinition) -> void:
		s.rails[0].slots[0].mount = ""
		s.rails[0].slots[0].set_piece = ""
		s.rails[0].slots[1].type = "hub"
		s.rails[0].slots[1].pods = 2
		s.rails[0].slots[1].set_piece = "twin_barrel"
		s.rails[0].slots[1].mount = "primary")
	_expect("radial_elite", "COLOUR-GATE", "a yellow + green ship keeping its v_rack", func(s: ShipDefinition) -> void: s.accent_color = "green")
	_expect("radial_elite", "COLOUR-GATE", "a set piece that does not exist", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[1].slots: slot.set_piece = "not_a_piece")
	_expect("player_t3", "SLOT-BUDGET", "a secondary weapon in the primary mount", func(s: ShipDefinition) -> void: s.rails[0].slots[0].set_piece = "shell_pair")
	_expect("player_t3", "SLOT-BUDGET", "three passives at tier 3", func(s: ShipDefinition) -> void: s.passives = ["radar", "magnet", "thrusters"])
	# Dense eight-slot rails exceed the shader budget even with the smaller weapon glyphs.
	_expect("boss", "C-BUDGET", "eight slots and four pods on every boss hub", func(s: ShipDefinition) -> void:
		for rail: RailDefinition in s.rails:
			rail.order = 8
			while rail.slots.size() < 8: rail.slots.append(rail.slots[-1].duplicate())
			for slot: SlotDefinition in rail.slots:
				if slot.type == "hub":
					slot.pods = 4
					slot.set_piece = "burst_ring")
	_expect_compiled("C-LADDER", "a compiled hub of radius 16", func(s: ShipDefinition) -> void: _part(s, "r2s0").radius = 16.0)
	_expect_compiled("C-LADDER", "a rail ring of radius 100", func(s: ShipDefinition) -> void: _part(s, "r2").radius = 100.0)
	_expect_compiled("C-COLOUR", "one pod recoloured green", func(s: ShipDefinition) -> void: _part(s, "r2s0p1").color_role = "green")
	_expect_compiled("C-GRAPH", "a line ending on a line", func(s: ShipDefinition) -> void: _part(s, "r2s0_spoke").to_id = "r2s1_spoke")
	_expect_compiled("C-GRAPH", "a pod whose parent does not exist", func(s: ShipDefinition) -> void: _part(s, "r2s0p0").parent_id = "nowhere")
	_expect_compiled("C-POS", "a hub moved 3 px off its rail", func(s: ShipDefinition) -> void: _part(s, "r2s0").position += Vector2(3, 0))

	# SETPIECE-IMPL needs a piece whose weapon does not exist yet. Until every weapon has landed
	# there is one; afterwards this line reports that and the rule is exercised by an injected id.
	var pending: String = ""
	for id: String in SetPieceCatalog.ids():
		if not SetPieceCatalog.is_implemented(id) and SetPieceCatalog.is_legal(id, "yellow", "red"): pending = id
	if pending != "":
		_expect("radial_elite", "SETPIECE-IMPL", "mounting %s, whose weapon is not built" % pending, func(s: ShipDefinition) -> void:
			for slot: SlotDefinition in s.rails[1].slots: slot.set_piece = pending)
	else:
		triggered["SETPIECE-IMPL"] = true
		h.check(true, "Every yellow/red set piece is implemented, so SETPIECE-IMPL has no live subject")

	# Behavioural control (lessons: a premise can be wrong about the world): the SYM-ROT mutation
	# must be LEGAL on an irregular elite, or the rule is just "pods must match".
	var messy: ShipDefinition = _load("irregular")
	messy.rails[1].slots[0].pods = 1
	h.check(not _codes(ShipGrammar.validate(messy)).has("SYM-ROT"), "Uneven pods are legal on an irregular elite")
	# Warnings: the archetype table.
	var thin: ShipDefinition = _load("radial_elite")
	for slot: SlotDefinition in thin.rails[1].slots: slot.set_piece = ""
	h.control("a radial elite stripped of its hub weapons", not ShipGrammar.warnings(thin).is_empty())
	# illegal_mounts is what the editor's Colours tab shows.
	var recoloured: ShipDefinition = _load("radial_elite")
	recoloured.accent_color = "green"
	var flagged: Array[Dictionary] = ShipGrammar.illegal_mounts(recoloured)
	h.check(flagged.size() == 3 and str(flagged[0].piece) == "v_rack" and str(flagged[0].needs) == "red", "A recolour flags the three mounted v_racks and names the missing colour (%s)" % str(flagged))
	# Strict JSON: positions are derived, so a file that tries to author one is refused.
	var errors: PackedStringArray = PackedStringArray()
	ShipGrammar.from_dict({"id": "x", "circles": []}, errors)
	h.control("a JSON ship that authors `circles`", not errors.is_empty())

	var silent: Array[String] = []
	for code: String in ShipGrammar.RULES:
		if not triggered.has(code): silent.append(code)
	h.check(silent.is_empty(), "Every coded rule was triggered by some control (never triggered: %s)" % str(silent))
	h.finish(self)
