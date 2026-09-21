class_name ShipRecipe
extends RefCounted
## Ship design spec §13: given a faction, a colour pair, a tier or archetype and a seed, build a
## ship that is on-style without hand-tuning. ONE engine serves both kinds of ship: a roster entry
## is a recipe whose structure is PINNED (`params.pins`, a partial spec-§10 dictionary that is used
## verbatim), a generated ship leaves structure to the seed. So "a designer cannot pick the
## generated ones out of a line-up" (acceptance 8) is a property of the code path, not a hope.
##
## Deterministic: its own RandomNumberGenerator, no clock, no iteration over unordered containers.
## The theme biases set-piece choice and speed jitter only; it never touches a structural rule.

const PASSIVES: Array[String] = ["radar", "magnet", "thrusters", "health_readout", "siphon", "forcefield", "orbital_seekers"]

## §7, per family. standard_a is the spec's own row; the others differ in rail count, order
## sequence and which rail carries the primary, so a tier's four offers read as four shapes.
## Each entry: [orders inside-out, index of the rail that carries the primary].
const PLAYER_RAILS: Dictionary = {
	"standard_a": {1: [[3], 0], 2: [[4], 0], 3: [[4, 3], 1], 4: [[4, 5], 1], 5: [[6, 4, 3], 2], 6: [[6, 5, 4], 2]},
	"standard_b": {1: [[3], 0], 2: [[5], 0], 3: [[3, 4], 0], 4: [[5, 4], 0], 5: [[3, 4, 6], 0], 6: [[4, 5, 6], 0]},
	"compact": {1: [[3], 0], 2: [[3], 0], 3: [[5], 0], 4: [[3, 4], 0], 5: [[4, 5], 1], 6: [[5, 6], 1]},
	"heavy": {1: [[3], 0], 2: [[4], 0], 3: [[4, 3], 1], 4: [[4, 5], 1], 5: [[6, 4, 3], 1], 6: [[6, 5, 4], 1]},
}
## §7's hub counts by tier (armed hubs included); compact carries one fewer, heavy one more.
const PLAYER_HUBS: Array[int] = [1, 2, 3, 4, 6, 8]
const PLAYER_CORE_DEPTH: Array[int] = [2, 2, 3, 3, 4, 4]

## What each element's four families fly: [primary, secondaries in priority order]. A hull takes
## the first `GameTuning.slots().secondary` of them; slots are a cap, so lightning, whose pool has
## two secondaries, flies two. Every id is a weapon; its set piece is looked up.
const PLAYER_LOADOUTS: Dictionary = {
	"neutral": {"standard_a": ["pulse_cannon", []]},
	"fire": {"compact": ["flame_cone", ["mine_layer", "explosives"]], "standard_a": ["ignition_lance", ["explosives", "mine_layer", "orbital_blockers"]], "standard_b": ["pulse_cannon", ["mine_layer", "orbital_blockers", "explosives"]], "heavy": ["beam", ["explosives", "orbital_blockers", "mine_layer"]]},
	"lightning": {"compact": ["ricochet", ["arc_tether", "orbital_blockers"]], "standard_a": ["bolt", ["arc_tether", "orbital_blockers"]], "standard_b": ["overcharge", ["orbital_blockers", "arc_tether"]], "heavy": ["beam", ["arc_tether", "orbital_blockers"]]},
	"corruption": {"compact": ["pulse_cannon", ["virus", "siphon_tether"]], "standard_a": ["pulse_cannon", ["poison_cloud", "virus", "drone_hatch"]], "standard_b": ["beam", ["siphon_tether", "drone_hatch", "orbital_blockers"]], "heavy": ["beam", ["drone_hatch", "poison_cloud", "virus"]]},
	"plasma": {"compact": ["phase_shot", ["blink_mine", "pulse_ring"]], "standard_a": ["spiral_shot", ["pulse_ring", "blink_mine", "orbital_blockers"]], "standard_b": ["pulse_cannon", ["blink_mine", "orbital_blockers", "pulse_ring"]], "heavy": ["beam", ["pulse_ring", "orbital_blockers", "blink_mine"]]},
	"void": {"compact": ["pulse_cannon", ["shield", "slow_field"]], "standard_a": ["void_orb", ["black_hole_shot", "slow_field", "shield"]], "standard_b": ["beam", ["slow_field", "shield", "orbital_blockers"]], "heavy": ["void_orb", ["shield", "black_hole_shot", "orbital_blockers"]]},
}

## Keywords a theme may carry, and the pieces they favour. Anything else in a theme is ignored.
const THEME_WORDS: Dictionary = {
	"rocket": ["v_rack"], "artillery": ["v_rack", "burst_ring", "collapse_cage"], "mine": ["drop_cradle", "phase_pair"], "swarm": ["spore_rack", "mesh_node"],
	"drone": ["spore_rack", "mesh_node"], "tether": ["hook_node", "leech_arm", "web_node"], "storm": ["storm_crown", "coil_array"], "poison": ["bloom_pod", "sac_cluster", "ember_rack"],
	"gravity": ["pull_cage", "collapse_cage", "iris_ring"], "missile": ["fin_trio", "v_rack"], "pulse": ["halo_node", "flare_ring"],
}

## Circle-count targets for §13.2's "within ±20 % of the archetype's target". MEASURED: the median
## `ShipCompiler.budget().circles` of 20 unpinned seeds per archetype (tests/ship_recipe_test.gd
## prints them); restate these from that printout whenever the fill rules change.
const CIRCLE_TARGET: Dictionary = {"drone": 8, "sentry": 19, "radial_elite": 26, "heavy_elite": 57, "irregular_elite": 68, "chain": 16, "boss": 99}
## Set pieces run from 2 to 5 circles, so a free draw lands outside the ±20 % band fairly often
## (measured on the first run: sentry 17-24 about 19, radial elite 23-32 about 26, irregular elite
## 52-87 about 68). The recipe therefore AIMS: it re-draws, from the same RNG stream so it stays
## deterministic, until the count is in the band or this many draws are spent.
const MAX_DRAWS: int = 24

static func generate(params: Dictionary) -> ShipDefinition:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 1))
	var faction: String = str(params.get("faction", "enemy"))
	var pins: Dictionary = params.get("pins", {})
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = null
	for draw: int in range(MAX_DRAWS):
		var data: Dictionary = _player(params, rng) if faction == "player" else _enemy(params, rng)
		# Pins win, key by key: a pinned `rails` replaces the generated rails outright.
		for key: String in pins: data[key] = pins[key]
		errors = PackedStringArray()
		ship = ShipGrammar.from_dict(data, errors)
		var target: int = int(CIRCLE_TARGET.get(ship.archetype, 0))
		# A player hull, a pinned structure and an archetype with no target are taken as drawn.
		if faction == "player" or pins.has("rails") or target == 0: break
		if absf(float(int(ShipCompiler.budget(ship).circles) - target)) <= float(target) * 0.2: break
	ship.element = str(params.get("element", ship.element))
	ship.role = str(params.get("role", "standard"))
	ship.family = str(params.get("family", "standard_a"))
	ship.motion_signature = "smooth"
	ShipGenerator._base_stats(ship)
	ship.magnet_radius = 100.0
	ship.description = str(params.get("description", "%s, seed %d" % [str(params.get("theme", "")), int(rng.seed)] if str(params.get("theme", "")) != "" else "seed %d" % int(rng.seed)))
	return ship

## §13.2. Validator errors first (they are most of the list), then the four extras it does not own.
static func style_check(ship: ShipDefinition) -> PackedStringArray:
	var problems: PackedStringArray = ShipGrammar.validate(ship)
	var target: int = int(CIRCLE_TARGET.get(ship.archetype, 0))
	var circles: int = int(ShipCompiler.budget(ship).circles)
	if target > 0 and absf(float(circles - target)) > float(target) * 0.2: problems.append("STYLE-COUNT: %d circles, the %s target is %d +/- 20 %%" % [circles, ship.archetype, target])
	for rail: RailDefinition in ship.rails:
		if not rail.reach_ring: problems.append("STYLE-RING: a rail without its reach ring")
	if ship.core_depth < 2: problems.append("STYLE-DOT: no core dot")
	if float(ShipGrammar.MOTION.core_pulse_amp) <= 0.0: problems.append("STYLE-DOT: the core dot does not pulse")
	return problems

## Free text -> the §13.1 template. Unknown words are returned, not silently dropped.
static func from_description(text: String, seed: int = 1) -> Dictionary:
	var words: PackedStringArray = text.to_lower().replace(",", " ").split(" ", false)
	var params: Dictionary = {"faction": "enemy", "archetype": "radial_elite", "tier": 3, "chassis_color": "yellow", "accent_color": "", "theme": text, "seed": seed}
	var colours: Array[String] = []
	var unknown: PackedStringArray = PackedStringArray()
	var named: bool = false
	for word: String in words:
		var archetype: String = word if ShipGrammar.ARCHETYPES.has(word) else word + "_elite" if ShipGrammar.ARCHETYPES.has(word + "_elite") else ""
		# The FIRST archetype named wins: in "radial elite ... heavy rockets", "heavy" is theme, and
		# a theme never overrides structure (§13.1).
		if archetype != "":
			if not named: params.archetype = archetype
			named = true
		elif word == "player": params.faction = "player"
		elif Elements.COLOR_KEYS.has(word): colours.append(word)
		elif Elements.COLOR_KEY.has(word): colours.append(str(Elements.COLOR_KEY[word]))
		elif word.begins_with("t") and word.substr(1).is_valid_int(): params.tier = clampi(int(word.substr(1)), 1, GameTuning.MAX_TIER)
		elif word == "tier" or word == "elite" or word == "enemy" or word.is_valid_int() or THEME_WORDS.has(word.trim_suffix("s")): pass
		else: unknown.append(word)
	if colours.size() > 0: params.chassis_color = colours[0]
	if colours.size() > 1: params.accent_color = colours[1]
	if str(params.faction) == "player":
		params.archetype = ""
		params.accent_color = str(params.chassis_color) if str(params.chassis_color) != "blue" else str(params.accent_color)
		params.chassis_color = "blue"
	if str(params.archetype) == "boss": params.faction = "boss"
	elif str(params.archetype).ends_with("_elite"): params.faction = "elite"
	params.id = "generated_%s_%d" % [str(params.archetype) if str(params.archetype) != "" else "player", seed]
	return {"params": params, "unknown": unknown}

# ---------------------------------------------------------------- enemies

static func _enemy(params: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var archetype: String = str(params.get("archetype", "drone"))
	var table: Dictionary = ShipGrammar.ARCHETYPE_TABLE.get(archetype, ShipGrammar.ARCHETYPE_TABLE.drone)
	var chassis: String = str(params.get("chassis_color", "red"))
	var accent: String = str(params.get("accent_color", ""))
	var tier: int = int(params.get("tier", 1))
	var irregular: bool = archetype == "irregular_elite"
	var pool: Dictionary = _pool(chassis, accent, str(params.get("theme", "")))
	var data: Dictionary = {"schema_version": 4, "id": str(params.get("id", "generated")), "name": str(params.get("name", params.get("id", "generated"))), "faction": str(params.get("faction", "enemy")), "archetype": archetype, "tier": tier,
		"chassis_color": chassis, "accent_color": accent, "core_depth": int(table.core), "core_weapon": _pick(pool.core, rng)}
	if archetype == "chain":
		data.core_weapon = ""
		data.chain_mode = "sway"
		var links: Array = []
		for i: int in range(5): links.append({"type": "hub", "pods": 2, "set_piece": _pick(pool.hub, rng)} if i == 0 or i == 2 else {"type": "node", "radius": 7 if i < 4 else 4})
		data.chain = links
		return data
	var orders: Array = (table.orders as Array).duplicate()
	if irregular:
		orders = []
		for r: int in range(int(table.rails)):
			var order: int = rng.randi_range(4, 7)
			while r > 0 and order == int(orders[r - 1]): order = rng.randi_range(4, 7)
			orders.append(order)
	var jitter: float = float(ShipGrammar.MOTION.rail_speed_jitter)
	var hub_hp: float = 40.0 + 10.0 * float(tier) if str(data.faction) != "enemy" else 0.0
	var rails: Array = []
	for r: int in range(orders.size()):
		var order: int = int(orders[r])
		# §13.7: inner rails carry node clusters, outer rails carry weapons. One-rail hulls arm what
		# their archetype needs on that one rail.
		var armed: bool = r > 0 or (archetype == "sentry" and tier >= 2)
		var piece: String = _pick(pool.hub, rng) if armed else ""
		# Two pods straddle the outward axis, so a forward-pointing piece is not drawn over one (S4).
		var pods: int = 2
		var slots: Array = []
		for j: int in range(order):
			if not armed: slots.append({"type": "node", "radius": 7 if orders.size() > 1 else 4})
			elif archetype == "sentry": slots.append({"type": "hub", "pods": pods, "set_piece": piece} if j % 2 == 0 else {"type": "node", "radius": 4})
			else: slots.append({"type": "hub", "pods": pods, "set_piece": piece, "hp": hub_hp})
		rails.append({"radius": ShipGrammar.RAIL_RADII[r], "order": order, "speed": snappedf(ShipGrammar.rail_speed(r) * (1.0 + rng.randf_range(-jitter, jitter)), 0.0001),
			"phase": snappedf(rng.randf() * TAU / float(order), 0.0001), "pump_phase": snappedf(float(r) * float(ShipGrammar.MOTION.pump_phase_step), 0.0001), "slots": slots})
	if archetype == "boss":
		# The second core stack: the shield generator that must fall before the core can (user decision).
		(rails[1].slots as Array)[0] = {"type": "hub", "pods": 2, "set_piece": str(((rails[1].slots as Array)[0] as Dictionary).set_piece), "hp": hub_hp, "feature": "shield_generator"}
	if irregular: _irregular_pass(rails, pool, rng)
	data.rails = rails
	return data

## §13.10: 10-25 % of slots to stubs, pod counts varied per cluster, one rail's centre moved <= 12 px.
static func _irregular_pass(rails: Array, pool: Dictionary, rng: RandomNumberGenerator) -> void:
	var total: int = 0
	for rail: Dictionary in rails: total += (rail.slots as Array).size()
	var stubs: int = clampi(roundi(float(total) * rng.randf_range(0.12, 0.23)), ceili(float(total) * 0.10), floori(float(total) * 0.25))
	var made: int = 0
	var guard: int = 0
	while made < stubs and guard < 200:
		guard += 1
		var rail: Dictionary = rails[rng.randi_range(0, rails.size() - 1)]
		var slots: Array = rail.slots
		var occupied: int = 0
		for slot: Variant in slots:
			if not (slot is String): occupied += 1
		var j: int = rng.randi_range(0, slots.size() - 1)
		if slots[j] is String or occupied <= 2: continue
		slots[j] = "stub"
		made += 1
	for rail: Dictionary in rails:
		for slot: Variant in rail.slots:
			if slot is Dictionary and str((slot as Dictionary).get("type", "")) == "hub":
				(slot as Dictionary).pods = rng.randi_range(1, 4)
				(slot as Dictionary).set_piece = _pick(pool.hub, rng)
	var moved: Dictionary = rails[rng.randi_range(0, rails.size() - 1)]
	var offset: Vector2 = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, ShipGrammar.MAX_RAIL_OFFSET)
	moved.offset = [snappedf(offset.x, 0.01), snappedf(offset.y, 0.01)]

## The colour-legal, implemented pieces, split by where they may go. A core weapon is a primary
## when the colours have one (green has none, so its core takes a secondary).
static func _pool(chassis: String, accent: String, theme: String) -> Dictionary:
	var core: Array[String] = []
	var hub: Array[String] = []
	var favoured: Array[String] = []
	for word: String in theme.to_lower().replace(",", " ").split(" ", false):
		for id: String in THEME_WORDS.get(word.trim_suffix("s"), []): favoured.append(id)
	for id: String in SetPieceCatalog.legal_for(chassis, accent):
		if not SetPieceCatalog.is_implemented(id): continue
		if SetPieceCatalog.slot_of(id) == "primary": core.append(id)
		else:
			hub.append(id)
			# A two-colour piece is what makes the pair readable, and a themed piece is what was asked for.
			if (SetPieceCatalog.colours_of(id) as Array).size() == 2: hub.append(id)
			if favoured.has(id):
				hub.append(id)
				hub.append(id)
	if core.is_empty(): core = hub.duplicate()
	if hub.is_empty(): hub = core.duplicate()
	return {"core": core, "hub": hub}

static func _pick(from: Array, rng: RandomNumberGenerator) -> String:
	return str(from[rng.randi_range(0, from.size() - 1)]) if not from.is_empty() else ""

# ---------------------------------------------------------------- the player

static func _player(params: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tier: int = clampi(int(params.get("tier", 1)), 1, GameTuning.MAX_TIER)
	var family: String = str(params.get("family", "standard_a"))
	var role: String = str(params.get("role", ShipCatalog.role_for_family(family)))
	var element: String = str(params.get("element", "neutral"))
	var accent: String = str(params.get("accent_color", Elements.COLOR_KEY.get(element, "")))
	var layout: Array = (PLAYER_RAILS.get(family, PLAYER_RAILS.standard_a) as Dictionary)[tier]
	var orders: Array = layout[0]
	var primary_rail: int = int(layout[1])
	var loadout: Array = (PLAYER_LOADOUTS.get(element, PLAYER_LOADOUTS.neutral) as Dictionary).get(family, (PLAYER_LOADOUTS.neutral as Dictionary).standard_a)
	var slots: Dictionary = GameTuning.slots(tier, role)
	var secondaries: Array[String] = []
	for ability: Variant in loadout[1]:
		if secondaries.size() < int(slots.secondary): secondaries.append(SetPieceCatalog.for_ability(str(ability)))
	var hubs_wanted: int = maxi(1 + secondaries.size(), PLAYER_HUBS[tier - 1] + (-1 if family == "compact" else 1 if family == "heavy" else 0))
	# Heavy hulls carry four pods a hub at EVERY tier: below tier 5 that is the only thing that
	# separates a heavy from a standard_a (same orders, same primary rail), and the first run of
	# the distinct-shapes check found three shapes, not four, at tiers 2-4.
	var pods: int = 4 if family == "heavy" else 2
	var jitter: float = float(ShipGrammar.MOTION.rail_speed_jitter)
	var rails: Array = []
	var pending: Array[String] = secondaries.duplicate()
	var hubs: int = 0
	# Outer rails first: weapons go outward (§13.7), and the primary's own rail is filled last.
	var fill_order: Array[int] = []
	for r: int in range(orders.size() - 1, -1, -1):
		if r != primary_rail: fill_order.append(r)
	fill_order.append(primary_rail)
	var filled: Dictionary = {}
	for r: int in fill_order:
		var order: int = int(orders[r])
		# The primary's rail puts a slot ON the forward line and stands still (user decision 3).
		# Every other rail straddles the line when its order is even, so the two differ in look.
		var on_axis: bool = r == primary_rail or order % 2 == 1
		var slot_list: Array = []
		for j: int in range(order): slot_list.append("stub")
		if r == primary_rail:
			slot_list[0] = {"type": "hub", "pods": pods, "set_piece": SetPieceCatalog.for_ability(str(loadout[0])), "mount": "primary"}
			hubs += 1
		# Mirror orbits, nearest the forward line first. With a slot ON the line, slot j mirrors
		# order - j (so 0, and order/2 when even, are their own mirrors); straddling it, slot j
		# mirrors order - 1 - j and every orbit is a pair.
		for j: int in range(order / 2 + 1):
			var a: int = j
			var b: int = posmod(order - j, order) if on_axis else order - 1 - j
			if a > b: continue
			if not (slot_list[a] is String) or not (slot_list[b] is String): continue
			var entry: Variant = {"type": "node", "radius": 7 if r == 0 and family != "compact" else 4}
			if not pending.is_empty() and r != 0 or (not pending.is_empty() and orders.size() == 1):
				var index: int = secondaries.find(pending[0])
				entry = {"type": "hub", "pods": pods, "set_piece": pending.pop_front(), "mount": "secondary_%d" % index}
				hubs += 1 if a == b else 2
			elif hubs < hubs_wanted and r != 0:
				entry = {"type": "hub", "pods": pods}
				hubs += 1 if a == b else 2
			slot_list[a] = entry
			slot_list[b] = (entry as Dictionary).duplicate() if entry is Dictionary else entry
		var speed: float = 0.0 if r == primary_rail else snappedf(ShipGrammar.rail_speed(r) * (1.0 + rng.randf_range(-jitter, jitter)), 0.0001)
		filled[r] = {"radius": ShipGrammar.RAIL_RADII[r], "order": order, "speed": speed, "phase": 0.0 if on_axis else snappedf(PI / float(order), 0.0001),
			"pump_phase": snappedf(float(r) * float(ShipGrammar.MOTION.pump_phase_step), 0.0001), "slots": slot_list}
	for r: int in range(orders.size()): rails.append(filled[r])
	var passives: Array = []
	var start: int = Elements.INDEX_ORDER.find(element) + ShipCatalog.FAMILIES.find(family)
	for k: int in range(int(slots.passive)): passives.append(PASSIVES[posmod(start + k * 3, PASSIVES.size())])
	return {"schema_version": 4, "id": str(params.get("id", "generated_player")), "name": str(params.get("name", params.get("id", "generated_player"))), "faction": "player", "tier": tier,
		"role": role, "family": family, "element": element, "chassis_color": "blue", "accent_color": accent, "core_depth": PLAYER_CORE_DEPTH[tier - 1], "passives": passives, "rails": rails}
