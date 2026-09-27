extends SceneTree
## ShipRecipe (ship design spec §13, acceptance 8's automated half): twenty seeds of every
## archetype, across a spread of colour pairs, must pass the validator AND the style check with no
## edits; the same seed must give the same bytes; different seeds must differ; every player hull
## of every element, tier and family must validate; each style rule has a control that breaks it.
const Harness = preload("res://tests/support/harness.gd")
const SEEDS: int = 20
const PAIRS: Array = [["yellow", "red"], ["red", "green"], ["green", "silver"], ["silver", "violet"], ["violet", "yellow"], ["yellow", "green"], ["red", "silver"], ["green", "violet"], ["silver", "yellow"], ["violet", "red"]]

func _initialize() -> void: _run.call_deferred()

func _params(archetype: String, pair: Array, seed_value: int) -> Dictionary:
	var faction: String = "boss" if archetype == "boss" else "elite" if archetype.ends_with("_elite") else "enemy"
	var mono: bool = faction == "enemy" # regulars are the weak, mono-colour ones (§6.6)
	return {"id": "gen_%s_%d" % [archetype, seed_value], "faction": faction, "archetype": archetype, "tier": 3, "chassis_color": pair[0], "accent_color": "" if mono else pair[1], "seed": seed_value}

func _median(values: Array[int]) -> int:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func _run() -> void:
	var h := Harness.new("SHIP RECIPE")
	for archetype: String in ShipGrammar.ARCHETYPES:
		var failures: PackedStringArray = PackedStringArray()
		var counts: Array[int] = []
		var stub_shares: Array[float] = []
		for seed_value: int in range(1, SEEDS + 1):
			var ship: ShipDefinition = ShipRecipe.generate(_params(archetype, PAIRS[seed_value % PAIRS.size()], seed_value))
			counts.append(int(ShipCompiler.budget(ship).circles))
			for problem: String in ShipRecipe.style_check(ship): failures.append("seed %d: %s" % [seed_value, problem])
			for problem: String in ShipGrammar.warnings(ship): failures.append("seed %d warning: %s" % [seed_value, problem])
			if archetype == "irregular_elite":
				var slots: int = 0
				var stubs: int = 0
				for rail: RailDefinition in ship.rails:
					for slot: SlotDefinition in rail.slots:
						slots += 1
						if slot.type == "stub": stubs += 1
				stub_shares.append(float(stubs) / float(slots))
		print("recipe %-16s circles min %d median %d max %d (limit %d)" % [archetype, counts.min(), _median(counts), counts.max(), int(ShipRecipe.CIRCLE_LIMITS[archetype])])
		h.check(failures.is_empty(), "%d seeds of %s pass validate, style check and warnings unedited (%s)" % [SEEDS, archetype, "; ".join(failures.slice(0, 3))])
		h.check(counts.max() <= int(ShipRecipe.CIRCLE_LIMITS[archetype]), "%s stays below its clutter limit without a minimum fill requirement" % archetype)
		if archetype == "irregular_elite":
			h.check(stub_shares.min() >= 0.10 - 0.0001 and stub_shares.max() <= 0.25 + 0.0001, "Irregular elites turn 10-25 %% of their slots to stubs (%.3f..%.3f)" % [stub_shares.min(), stub_shares.max()])

	# Determinism, and that the seed matters.
	var a: ShipDefinition = ShipRecipe.generate(_params("irregular_elite", PAIRS[0], 7))
	var b: ShipDefinition = ShipRecipe.generate(_params("irregular_elite", PAIRS[0], 7))
	var c: ShipDefinition = ShipRecipe.generate(_params("irregular_elite", PAIRS[0], 8))
	h.check(var_to_bytes(ShipCompiler.grammar_signature(a)) == var_to_bytes(ShipCompiler.grammar_signature(b)), "The same seed gives the same ship, byte for byte")
	h.control("a different seed", var_to_bytes(ShipCompiler.grammar_signature(a)) != var_to_bytes(ShipCompiler.grammar_signature(c)))

	# Every player hull the roster needs: 5 elements x tiers 2-6 x 4 families, and the seed hull.
	var player_failures: PackedStringArray = PackedStringArray()
	var shapes: Dictionary = {}
	var loadouts: Dictionary = {}
	var seed_hull: ShipDefinition = ShipRecipe.generate({"id": "player_seed", "faction": "player", "element": "neutral", "tier": 1, "family": "standard_a", "seed": 1})
	for problem: String in ShipGrammar.validate(seed_hull): player_failures.append("player_seed: " + problem)
	for element: String in Elements.INDEX_ORDER:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			for family: String in ShipCatalog.FAMILIES:
				var id: String = "player_%s_t%d_%s" % [element, tier, family]
				var ship: ShipDefinition = ShipRecipe.generate({"id": id, "faction": "player", "element": element, "tier": tier, "family": family, "role": ShipCatalog.role_for_family(family), "seed": 1})
				for problem: String in ShipGrammar.validate(ship): player_failures.append("%s: %s" % [id, problem])
				var shape: Array = []
				for rail: RailDefinition in ship.rails:
					var row: Array = [rail.order, rail.speed == 0.0]
					for slot: SlotDefinition in rail.slots: row.append("%s%d/%.2f" % [slot.type, slot.pods, slot.pod_spacing])
					shape.append(row)
				var key: String = "%s_t%d" % [element, tier]
				if not shapes.has(key):
					shapes[key] = {}
					loadouts[key] = {}
				shapes[key][str(shape)] = true
				ShipCompiler.compile(ship)
				loadouts[key]["%s|%s" % [ship.primary, str(ship.secondaries)]] = true
				# The accent must be VISIBLE: the player's dot is white, so only a set piece can show it.
				var shows_accent: bool = false
				for piece: String in ShipGrammar.mounted_pieces(ship):
					if (SetPieceCatalog.colours_of(piece) as Array).has(ship.accent_color): shows_accent = true
				if not shows_accent: player_failures.append("%s mounts nothing in its %s accent" % [id, ship.accent_color])
	h.check(player_failures.is_empty(), "All 101 player hulls validate and show their accent (%d problems: %s)" % [player_failures.size(), "; ".join(player_failures.slice(0, 4))])
	var same_shape: PackedStringArray = PackedStringArray()
	var same_loadout: PackedStringArray = PackedStringArray()
	for key: String in shapes:
		if (shapes[key] as Dictionary).size() < 4: same_shape.append("%s has %d shapes" % [key, (shapes[key] as Dictionary).size()])
		if (loadouts[key] as Dictionary).size() < 4: same_loadout.append("%s has %d loadouts" % [key, (loadouts[key] as Dictionary).size()])
	h.check(same_shape.is_empty(), "A tier's four offers are four different SHAPES (%s)" % "; ".join(same_shape.slice(0, 4)))
	h.check(same_loadout.is_empty(), "A tier's four offers are four different LOADOUTS (%s)" % "; ".join(same_loadout.slice(0, 4)))

	# Pins: a pinned structure is used verbatim, whatever the seed says.
	var pinned: Array = [{"radius": 52, "order": 3, "speed": -0.9, "phase": 0.0, "slots": ["node", "node", "node"]}]
	var first: ShipDefinition = ShipRecipe.generate({"id": "pinned", "faction": "enemy", "archetype": "drone", "tier": 1, "chassis_color": "red", "seed": 1, "pins": {"rails": pinned}})
	var second: ShipDefinition = ShipRecipe.generate({"id": "pinned", "faction": "enemy", "archetype": "drone", "tier": 1, "chassis_color": "red", "seed": 99, "pins": {"rails": pinned}})
	h.check(first.rails.size() == 1 and is_equal_approx(first.rails[0].speed, -0.9) and is_equal_approx(second.rails[0].speed, -0.9) and is_equal_approx(second.rails[0].phase, 0.0), "Pinned rails are used verbatim under any seed")

	# One control per style rule: break a generated ship and the check must name that rule.
	var subject: ShipDefinition = ShipRecipe.generate(_params("radial_elite", PAIRS[0], 3))
	h.check(ShipRecipe.style_check(subject).is_empty(), "The control subject passes before it is broken")
	var sparse: ShipDefinition = subject.duplicate(true)
	for slot: SlotDefinition in sparse.rails[1].slots: slot.pods = 1
	h.check(ShipRecipe.style_check(sparse).is_empty(), "A sparse design is accepted without adding circles to meet a target")
	_control(h, subject, "STYLE-COUNT", "eight outer hubs with four pods exceed the radial budget", func(s: ShipDefinition) -> void:
		s.rails[1].order = 8
		while s.rails[1].slots.size() < 8: s.rails[1].slots.append(s.rails[1].slots[0].duplicate())
		for slot: SlotDefinition in s.rails[1].slots:
			slot.pods = 4
			slot.set_piece = "v_rack")
	_control(h, subject, "STYLE-RING", "a rail's reach ring switched off", func(s: ShipDefinition) -> void: s.rails[0].reach_ring = false)
	_control(h, subject, "COLOUR-GATE", "a third colour's piece mounted", func(s: ShipDefinition) -> void: s.rails[1].slots[0].set_piece = "halo_node")
	_control(h, subject, "RAIL-ORDER-ADJ", "two adjacent rails of one order", func(s: ShipDefinition) -> void:
		s.rails[1].order = s.rails[0].order
		while s.rails[1].slots.size() < s.rails[1].order: s.rails[1].slots.append(s.rails[1].slots[0].duplicate()))
	_control(h, subject, "RAIL-SIGN", "two adjacent rails turning the same way", func(s: ShipDefinition) -> void: s.rails[1].speed = -absf(s.rails[1].speed))
	# An off-ladder node is caught on the GRAMMAR (SLOT) before the compiled ladder guard ever runs.
	_control(h, subject, "SLOT", "a node off the ladder", func(s: ShipDefinition) -> void:
		for slot: SlotDefinition in s.rails[0].slots: slot.node_radius = 6)

	# The §13.1 template from free text; unknown words are reported, never silently dropped.
	var parsed: Dictionary = ShipRecipe.from_description("yellow red radial elite t4, artillery platform, heavy rockets, slow", 81734)
	var params: Dictionary = parsed.params
	h.check(str(params.archetype) == "radial_elite" and str(params.chassis_color) == "yellow" and str(params.accent_color) == "red" and int(params.tier) == 4 and int(params.seed) == 81734, "A description resolves to the §13.1 template (%s)" % str(params))
	h.check((parsed.unknown as PackedStringArray).has("platform") and not (parsed.unknown as PackedStringArray).has("rockets"), "Words it cannot use are reported (%s)" % str(parsed.unknown))
	var themed: int = 0
	var plain: int = 0
	for seed_value: int in range(1, 41):
		for piece: String in ShipGrammar.mounted_pieces(ShipRecipe.generate(_params("radial_elite", PAIRS[0], seed_value).merged({"theme": "heavy rockets"}, true))):
			if piece == "v_rack": themed += 1
		for piece: String in ShipGrammar.mounted_pieces(ShipRecipe.generate(_params("radial_elite", PAIRS[0], seed_value))):
			if piece == "v_rack": plain += 1
	h.check(themed > plain, "A 'rockets' theme mounts more v_racks over 40 seeds than no theme (%d vs %d), and changes no structure" % [themed, plain])
	h.finish(self)

func _control(h: Harness, subject: ShipDefinition, code: String, what: String, mutate: Callable) -> void:
	var broken: ShipDefinition = subject.duplicate(true)
	mutate.call(broken)
	var named: bool = false
	for problem: String in ShipRecipe.style_check(broken):
		if problem.begins_with(code): named = true
	h.control("%s -> %s" % [what, code], named)
