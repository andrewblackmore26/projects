class_name ShipGrammar
extends RefCounted
## The ship design spec's fixed numbers: the radius ladder (§3), the rails (§4.2), the cluster
## layout (§4.4) and every motion default (§9). A ship file stores only what it overrides; the
## compiler reads the rest from here, so retuning the fleet is an edit to this file.
## (S2 adds the coded validator to this class.)

## §3. No circle on a ship or in a set piece may use any other radius.
const LADDER: Dictionary = {"core_1": 34, "core_2": 22, "core_3": 13, "core_dot": 5, "hub": 15, "pod": 7, "micro": 4}
const CORE_RADII: Array[int] = [34, 22, 13]

## §4.2, inside out. A ship uses the first N.
const RAIL_RADII: Array[int] = [52, 96, 140, 184]
const MIN_ORDER: int = 3
const MAX_ORDER: int = 8
const MAX_RAIL_OFFSET: float = 12.0

## §4.4 / §9.2. Pods sit this far from the hub's centre, fanned this far apart, centred on outward.
const POD_DISTANCE: float = 30.0
const POD_SPACING: float = 0.78
const MAX_PODS: int = 4

## §9. Frequencies are rad/s, as the spec writes them (`sin(t * 1.9 + ...)`), not Hz.
const MOTION: Dictionary = {
	# §9.1: magnitude falls with radius so rim speed stays ~constant; the SIGN alternates by rail
	# index and is not negotiable. A ship may jitter the magnitude by up to `rail_speed_jitter`.
	"rail_speed": [-0.95, 0.42, -0.26, 0.18],
	"rail_speed_jitter": 0.15,
	# §9.2: angle = hub_angle + slot_offset + sin(t * 1.9 + pod_index * 1.0) * 0.14
	"pod_bob_amp": 0.14, "pod_bob_freq": 1.9, "pod_bob_phase_step": 1.0,
	"node_bob_amp": 0.10, "node_bob_freq": 2.3, "node_bob_phase_step": 0.7,
	# §9.3: effective_radius = rail.radius * (1 + sin(t * 1.4 + rail_phase) * 0.03)
	"pump_amp": 0.03, "pump_freq": 1.4, "pump_phase_step": 0.9,
	# §9.4: one bright arc per rim; small circles buzz, big ones turn slowly.
	"shine_fraction": 0.13,
	"shine_period": {34: 2.50, 22: 2.30, 15: 2.00, 13: 1.90, 7: 1.70, 5: 1.50, 4: 1.40},
	"shine_phase_per_part": 0.05, "shine_phase_per_cluster": 0.12,
	# §9.5: radius = 5 * (1 + sin(t * 4.0) * 0.22). Render-only; the core collider never changes.
	"core_pulse_amp": 0.22, "core_pulse_freq": 4.0,
	# §9.6
	"chain_rest_length": 30.0, "chain_wave_freq": 3.2, "chain_phase_step": 0.85,
	"chain_amplitude": {"rigid": 0.0, "sway": 6.0, "whip": 14.0},
	# §9.7
	"aim_slew": 3.0, "aim_return_seconds": 1.0,
	# §9.8, converted from the spec's per-frame units at 60 fps where marked.
	"collapse_seconds": 0.10, "fragments_min": 5, "fragments_max": 7,
	"debris_spread": 84.0,          # 1.4 px/frame
	"debris_outward_accel": 72.0,   # 0.02 px/frame^2
	"debris_spin_min": 0.5, "debris_spin_max": 1.5,
	"debris_fade_seconds": 1.0, "debris_light_drop_seconds": 0.5,
	# §4.2 / §9.9
	"rail_dash_on": 2.0, "rail_dash_off": 5.0, "rail_opacity": 0.28,
}

## Signed default speed of the rail at `index` (0-based). §9.1.
static func rail_speed(index: int) -> float:
	var speeds: Array = MOTION.rail_speed
	return float(speeds[clampi(index, 0, speeds.size() - 1)])

## Shine lap period for a ladder radius. §9.4.
static func shine_period(radius: int) -> float:
	return float((MOTION.shine_period as Dictionary).get(radius, 2.0))

## Pod angles about the outward direction for a hub carrying `count` pods: spaced POD_SPACING,
## centred. 1 -> [0], 2 -> [-0.39, 0.39], 3 -> [-0.78, 0, 0.78], 4 -> [-1.17, -0.39, 0.39, 1.17].
static func pod_angles(count: int) -> PackedFloat32Array:
	var angles: PackedFloat32Array = PackedFloat32Array()
	var pods: int = clampi(count, 0, MAX_PODS) # clamp first, or an over-count fan would sit off-centre
	for i: int in range(pods):
		angles.append((float(i) - float(pods - 1) * 0.5) * POD_SPACING)
	return angles

const ARCHETYPES: Array[String] = ["drone", "sentry", "radial_elite", "heavy_elite", "irregular_elite", "chain", "boss"]
const FACTIONS: Array[String] = ["player", "enemy", "elite", "boss"]
const MAX_CIRCLES: int = 128 # the outline shader's uniform slots

## Every rule the validator can raise. Each error string starts with its code, so a negative
## control can assert the RIGHT rule fired; `ship_grammar_test` fails if any code here is never
## triggered by some control. Spec §11 lists the save-blockers; the rest guard the compiler.
const RULES: Dictionary = {
	"SCHEMA": "schema 4, a filename-safe id, a known faction and archetype, tier 1..6",
	"COLOUR-SET": "chassis is one of the six colours; accent is another of them or none",
	"COLOUR-BLUE": "a player's chassis is blue; blue never appears on an enemy",
	"CORE": "core depth 2..4; a core weapon is a known set piece on a non-player",
	"RAIL-LADDER": "rails use 52, 96, 140, 184 from the inside out, at most four",
	"RAIL-ORDER": "order 3..8 and exactly that many slots",
	"RAIL-ORDER-ADJ": "adjacent rails differ in order",
	"RAIL-SIGN": "adjacent rails turn opposite ways; only a player's primary rail may stand still",
	"RAIL-OFFSET": "a rail centre is offset only on an irregular elite, by at most 12 px",
	"RAIL-EMPTY": "every rail has an occupied slot and draws its reach ring",
	"SLOT": "hub, node or stub; pods 1..4 on hubs only; a node is r4 or r7; one set piece per hub",
	"SYM-ROT": "a non-irregular enemy rail repeats under some rotation",
	"SYM-MIRROR": "a player rail mirrors about the forward line at rest",
	"PRIMARY-FWD": "a player has exactly one primary and it sits on the forward line",
	"COLOUR-GATE": "every mounted set piece exists and its colours are in the ship's pair",
	"SETPIECE-IMPL": "a mounted set piece's weapon behaviour exists",
	"SLOT-BUDGET": "a player's secondaries and passives fit GameTuning.slots",
	"C-BUDGET": "at most 128 circles and 512 lines",
	"C-LADDER": "every compiled circle is on the ladder, every ring on a rail radius",
	"C-COLOUR": "every compiled part is chassis or accent coloured",
	"C-GRAPH": "one core, every circle reaches it, every line ends on two circles",
	"C-POS": "every cluster root sits on its rail at its slot angle",
}

static func validate(ship: ShipDefinition) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	_validate_header(ship, errors)
	_validate_rails(ship, errors)
	_validate_symmetry(ship, errors)
	for mount: Dictionary in illegal_mounts(ship): errors.append("COLOUR-GATE: %s at %s needs %s" % [mount.piece, mount.where, mount.needs])
	for piece: String in mounted_pieces(ship):
		if SetPieceCatalog.has(piece) and not SetPieceCatalog.is_implemented(piece): errors.append("SETPIECE-IMPL: %s has no weapon behaviour yet" % piece)
	_validate_budget(ship, errors)
	if errors.is_empty():
		# Compiled-output guards run on a private copy: validating must never mutate the subject.
		var copy: ShipDefinition = ship.duplicate(true)
		ShipCompiler.compile(copy)
		errors.append_array(validate_compiled(copy))
	return errors

## [{piece, where, needs}] for every mounted piece that is unknown or outside the colour pair.
## The editor's Colours tab and the COLOUR-GATE rule are both built from this one function.
static func illegal_mounts(ship: ShipDefinition) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mounts: Array = []
	if ship.core_weapon != "": mounts.append([ship.core_weapon, "the core"])
	for r: int in range(ship.rails.size()):
		for j: int in range(ship.rails[r].slots.size()):
			if ship.rails[r].slots[j].set_piece != "": mounts.append([ship.rails[r].slots[j].set_piece, "rail %d slot %d" % [r + 1, j]])
	for i: int in range(ship.chain_links.size()):
		if ship.chain_links[i].set_piece != "": mounts.append([ship.chain_links[i].set_piece, "chain link %d" % i])
	for mount: Array in mounts:
		var piece: String = str(mount[0])
		if not SetPieceCatalog.has(piece):
			result.append({"piece": piece, "where": mount[1], "needs": "to exist"})
		elif not SetPieceCatalog.is_legal(piece, ship.chassis_color, ship.accent_color):
			var missing: Array[String] = []
			for colour: String in SetPieceCatalog.colours_of(piece):
				if colour != ship.chassis_color and colour != ship.accent_color: missing.append(colour)
			result.append({"piece": piece, "where": mount[1], "needs": " + ".join(missing)})
	return result

static func mounted_pieces(ship: ShipDefinition) -> Array[String]:
	var result: Array[String] = []
	if ship.core_weapon != "": result.append(ship.core_weapon)
	for rail: RailDefinition in ship.rails:
		for slot: SlotDefinition in rail.slots:
			if slot.set_piece != "": result.append(slot.set_piece)
	for link: SlotDefinition in ship.chain_links:
		if link.set_piece != "": result.append(link.set_piece)
	return result

static func is_irregular(ship: ShipDefinition) -> bool:
	return ship.archetype == "irregular_elite"

static func _validate_header(ship: ShipDefinition, errors: PackedStringArray) -> void:
	if ship.schema_version != 4: errors.append("SCHEMA: schema_version is %d, not 4" % ship.schema_version)
	if ship.id.is_empty() or not ship.id.is_valid_filename() or ship.id.contains("."): errors.append("SCHEMA: id '%s' is not filename-safe" % ship.id)
	if not FACTIONS.has(ship.faction): errors.append("SCHEMA: unknown faction '%s'" % ship.faction)
	if ship.tier < 1 or ship.tier > GameTuning.MAX_TIER: errors.append("SCHEMA: tier %d" % ship.tier)
	var player: bool = ship.faction == "player"
	if player != (ship.archetype == ""): errors.append("SCHEMA: a player hull has no archetype and every other hull has one ('%s')" % ship.archetype)
	if not player and not ARCHETYPES.has(ship.archetype): errors.append("SCHEMA: unknown archetype '%s'" % ship.archetype)
	if not Elements.COLOR_KEYS.has(ship.chassis_color): errors.append("COLOUR-SET: chassis '%s'" % ship.chassis_color)
	if ship.accent_color != "" and (not Elements.COLOR_KEYS.has(ship.accent_color) or ship.accent_color == ship.chassis_color): errors.append("COLOUR-SET: accent '%s'" % ship.accent_color)
	if player and ship.chassis_color != Elements.PLAYER_COLOR_KEY: errors.append("COLOUR-BLUE: a player's chassis is blue, not '%s'" % ship.chassis_color)
	if not player and (ship.chassis_color == Elements.PLAYER_COLOR_KEY or ship.accent_color == Elements.PLAYER_COLOR_KEY): errors.append("COLOUR-BLUE: blue on a %s" % ship.faction)
	if ship.core_depth < 2 or ship.core_depth > 4: errors.append("CORE: depth %d" % ship.core_depth)
	if ship.core_weapon != "" and player: errors.append("CORE: a player mounts its primary on a rail, not the core")
	if ship.core_weapon == "" and not player and ship.archetype != "chain" and ship.archetype != "drone": errors.append("CORE: a %s carries its main weapon in the core" % ship.archetype)

static func _validate_rails(ship: ShipDefinition, errors: PackedStringArray) -> void:
	var chain: bool = ship.archetype == "chain"
	if ship.rails.size() > RAIL_RADII.size() or (ship.rails.is_empty() != chain): errors.append("RAIL-LADDER: %d rails on a %s" % [ship.rails.size(), ship.archetype if ship.archetype != "" else "player"])
	if chain and ship.chain_links.is_empty(): errors.append("RAIL-EMPTY: a chain with no links")
	var primary_rail: int = -1
	for r: int in range(ship.rails.size()):
		for slot: SlotDefinition in ship.rails[r].slots:
			if slot.mount == "primary": primary_rail = r
	for r: int in range(mini(ship.rails.size(), RAIL_RADII.size())):
		var rail: RailDefinition = ship.rails[r]
		if rail.radius != RAIL_RADII[r]: errors.append("RAIL-LADDER: rail %d is at %d, not %d" % [r + 1, rail.radius, RAIL_RADII[r]])
		if rail.order < MIN_ORDER or rail.order > MAX_ORDER or rail.slots.size() != rail.order: errors.append("RAIL-ORDER: rail %d has order %d and %d slots" % [r + 1, rail.order, rail.slots.size()])
		if r > 0 and rail.order == ship.rails[r - 1].order: errors.append("RAIL-ORDER-ADJ: rails %d and %d are both order %d" % [r, r + 1, rail.order])
		# Only a player's primary rail may stand still (user decision 3); everything else turns, and
		# against its neighbours. A still rail has no direction, so it is skipped when comparing signs.
		var still_allowed: bool = ship.faction == "player" and r == primary_rail
		if rail.speed == 0.0 and not still_allowed: errors.append("RAIL-SIGN: rail %d does not turn" % (r + 1))
		if absf(rail.speed) > 3.0: errors.append("RAIL-SIGN: rail %d turns at %.2f rad/s" % [r + 1, rail.speed])
		if r > 0 and rail.speed * ship.rails[r - 1].speed > 0.0: errors.append("RAIL-SIGN: rails %d and %d turn the same way" % [r, r + 1])
		if rail.offset.length() > MAX_RAIL_OFFSET + 0.001 or (rail.offset != Vector2.ZERO and not is_irregular(ship)): errors.append("RAIL-OFFSET: rail %d is offset %.1f px" % [r + 1, rail.offset.length()])
		var occupied: int = 0
		for j: int in range(rail.slots.size()):
			occupied += 1 if rail.slots[j].is_occupied() else 0
			_validate_slot(rail.slots[j], "rail %d slot %d" % [r + 1, j], errors)
		if occupied == 0 or not rail.reach_ring: errors.append("RAIL-EMPTY: rail %d has %d occupied slots, reach ring %s" % [r + 1, occupied, rail.reach_ring])
	for i: int in range(ship.chain_links.size()): _validate_slot(ship.chain_links[i], "chain link %d" % i, errors)

static func _validate_slot(slot: SlotDefinition, where: String, errors: PackedStringArray) -> void:
	if not ["hub", "node", "stub"].has(slot.type): errors.append("SLOT: %s is a '%s'" % [where, slot.type])
	if slot.type == "hub" and (slot.pods < 1 or slot.pods > MAX_PODS): errors.append("SLOT: %s has %d pods" % [where, slot.pods])
	if slot.type != "hub" and (slot.pods != 0 or slot.set_piece != "" or slot.mount != ""): errors.append("SLOT: %s is a %s carrying pods, a set piece or a mount" % [where, slot.type])
	if slot.type == "node" and slot.node_radius != int(LADDER.micro) and slot.node_radius != int(LADDER.pod): errors.append("SLOT: %s is a node of radius %d" % [where, slot.node_radius])
	if slot.mount != "" and slot.set_piece == "": errors.append("SLOT: %s has a mount and no set piece" % where)

## One slot's identity for symmetry. Set pieces count: "filled identically" (spec §5).
static func _slot_key(slot: SlotDefinition) -> String:
	return "%s/%d/%d/%s" % [slot.type, slot.node_radius if slot.type == "node" else 0, slot.pods, slot.set_piece]

static func _validate_symmetry(ship: ShipDefinition, errors: PackedStringArray) -> void:
	var player: bool = ship.faction == "player"
	var primaries: int = 0
	for r: int in range(ship.rails.size()):
		var rail: RailDefinition = ship.rails[r]
		var n: int = rail.slots.size()
		if n == 0: continue
		var step: float = TAU / float(n)
		if player:
			# Mirror about forward at rest: the phase puts a slot ON the axis or straddles it, and
			# the fill reads the same from either side.
			var lead: float = fposmod(rail.phase, step)
			var on_axis: bool = lead < 0.0001 or step - lead < 0.0001
			var straddles: bool = absf(lead - step * 0.5) < 0.0001
			if not on_axis and not straddles:
				errors.append("SYM-MIRROR: rail %d's phase %.3f neither puts a slot on the forward line nor straddles it" % [r + 1, rail.phase])
				continue
			var first: int = int(round(-rail.phase / step)) if on_axis else int(round((-rail.phase - step * 0.5) / step))
			# `first` is the slot on the forward line, or the one just left of it when straddling.
			# On the axis, slot first+k mirrors first-k; straddling, first+1+k mirrors first-k.
			for k: int in range(n):
				var right: int = posmod(first + k + (0 if on_axis else 1), n)
				var left: int = posmod(first - k, n)
				if _slot_key(rail.slots[right]) != _slot_key(rail.slots[left]):
					errors.append("SYM-MIRROR: rail %d slots %d and %d differ across the forward line" % [r + 1, right, left])
					break
			for j: int in range(n):
				if rail.slots[j].mount != "primary": continue
				primaries += 1
				var angle: float = fposmod(rail.phase + float(j) * step, TAU)
				if angle > 0.0001 and TAU - angle > 0.0001: errors.append("PRIMARY-FWD: the primary sits %.3f rad off the forward line" % angle)
		elif not is_irregular(ship):
			var repeats: bool = false
			for shift: int in range(1, n):
				var same: bool = true
				for j: int in range(n):
					if _slot_key(rail.slots[j]) != _slot_key(rail.slots[(j + shift) % n]): same = false
				if same: repeats = true
			if not repeats: errors.append("SYM-ROT: rail %d's fill repeats under no rotation" % (r + 1))
	if player and primaries != 1: errors.append("PRIMARY-FWD: a player hull needs exactly one primary mount, found %d" % primaries)

static func _validate_budget(ship: ShipDefinition, errors: PackedStringArray) -> void:
	var budget: Dictionary = ShipCompiler.budget(ship)
	if int(budget.circles) > MAX_CIRCLES or int(budget.lines) > ShipCatalog.MAX_LINES: errors.append("C-BUDGET: %d circles, %d lines" % [budget.circles, budget.lines])
	if ship.faction != "player": return
	var slots: Dictionary = GameTuning.slots(ship.tier, ship.role)
	var secondaries: Dictionary = {}
	for rail: RailDefinition in ship.rails:
		for slot: SlotDefinition in rail.slots:
			if slot.mount.begins_with("secondary_"): secondaries[slot.mount] = true
			elif slot.mount != "" and slot.mount != "primary": errors.append("SLOT-BUDGET: unknown mount '%s'" % slot.mount)
			if slot.mount != "" and SetPieceCatalog.has(slot.set_piece):
				var kind: String = SetPieceCatalog.slot_of(slot.set_piece)
				if (slot.mount == "primary") != (kind == "primary"): errors.append("SLOT-BUDGET: %s is a %s weapon in the %s mount" % [slot.set_piece, kind, slot.mount])
			elif slot.set_piece != "" and slot.mount == "": errors.append("SLOT-BUDGET: a player's %s has no mount" % slot.set_piece)
	if secondaries.size() > int(slots.secondary): errors.append("SLOT-BUDGET: %d secondaries for %d slots" % [secondaries.size(), slots.secondary])
	if ship.passives.size() > int(slots.passive): errors.append("SLOT-BUDGET: %d passives for %d slots" % [ship.passives.size(), slots.passive])

## Guards on the COMPILED hull: they catch a compiler or catalogue bug the grammar cannot express
## ("a third colour anywhere" can only be seen here).
static func validate_compiled(ship: ShipDefinition) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var allowed: Array[String] = [ship.chassis_color]
	if ship.accent_color != "": allowed.append(ship.accent_color)
	var by_id: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "circle": by_id[part.id] = part
	if not by_id.has("core"): errors.append("C-GRAPH: no core")
	for part: PartDefinition in ship.parts:
		if not allowed.has(part.color_role): errors.append("C-COLOUR: %s is %s" % [part.id, part.color_role])
		if part.shape == "line":
			if not by_id.has(part.from_id) or not by_id.has(part.to_id) or part.from_id == part.to_id: errors.append("C-GRAPH: line %s runs %s -> %s" % [part.id, part.from_id, part.to_id])
			continue
		var ring: bool = part.style == 5
		if ring and not RAIL_RADII.has(int(round(part.radius))): errors.append("C-LADDER: rail ring %s has radius %.1f" % [part.id, part.radius])
		if not ring and not on_ladder(part.radius): errors.append("C-LADDER: %s has radius %.1f" % [part.id, part.radius])
		if part.id != "core":
			var hops: int = 0
			var at: String = part.parent_id
			while at != "core" and by_id.has(at) and hops < 64:
				at = (by_id[at] as PartDefinition).parent_id
				hops += 1
			if at != "core": errors.append("C-GRAPH: %s does not reach the core" % part.id)
	for r: int in range(ship.rails.size()):
		var rail: RailDefinition = ship.rails[r]
		for j: int in range(rail.slots.size()):
			if not rail.slots[j].is_occupied(): continue
			var root: PartDefinition = by_id.get("r%ds%d" % [r + 1, j])
			var expected: Vector2 = rail.offset + Vector2(sin(rail.phase + float(j) * TAU / float(rail.order)), -cos(rail.phase + float(j) * TAU / float(rail.order))) * float(rail.radius)
			if root == null or root.position.distance_to(expected) > 0.01: errors.append("C-POS: rail %d slot %d is off its rail" % [r + 1, j])
	return errors

## Conformance to the spec's §7 and §8 tables. Warnings, not errors: the spec marks them "all tune".
static func warnings(ship: ShipDefinition) -> PackedStringArray:
	var notes: PackedStringArray = PackedStringArray()
	var target: Dictionary = ARCHETYPE_TABLE.get(ship.archetype, {}) if ship.faction != "player" else {}
	if target.is_empty(): return notes
	if ship.rails.size() != int(target.rails): notes.append("%s has %d rails; the archetype table says %d" % [ship.id, ship.rails.size(), target.rails])
	if ship.core_depth != int(target.core) and not (ship.archetype == "irregular_elite" and ship.core_depth == 4): notes.append("%s has core depth %d; the archetype table says %d" % [ship.id, ship.core_depth, target.core])
	var pieces: int = mounted_pieces(ship).size()
	if pieces < int(target.pieces_min) or pieces > int(target.pieces_max): notes.append("%s mounts %d set pieces; the archetype table says %d..%d" % [ship.id, pieces, target.pieces_min, target.pieces_max])
	return notes

## Spec §8, with the two approved restatements: a heavy elite is 7 hub pieces + the core weapon,
## a boss 13 + the core weapon, because of the 128-circle cap.
const ARCHETYPE_TABLE: Dictionary = {
	"drone": {"core": 2, "rails": 1, "orders": [3], "pieces_min": 0, "pieces_max": 1},
	"sentry": {"core": 2, "rails": 1, "orders": [4], "pieces_min": 1, "pieces_max": 3},
	"radial_elite": {"core": 3, "rails": 2, "orders": [4, 3], "pieces_min": 3, "pieces_max": 4},
	"heavy_elite": {"core": 4, "rails": 3, "orders": [6, 4, 3], "pieces_min": 8, "pieces_max": 8},
	"irregular_elite": {"core": 3, "rails": 3, "orders": [], "pieces_min": 6, "pieces_max": 12},
	"chain": {"core": 2, "rails": 0, "orders": [], "pieces_min": 2, "pieces_max": 4},
	"boss": {"core": 4, "rails": 4, "orders": [8, 6, 4, 3], "pieces_min": 14, "pieces_max": 20},
}

# ---------------------------------------------------------------- JSON (spec §10)

## Reads the spec's §10 shape. Strict about what it does not know: an unknown key is an error,
## because positions are derived and a file that tries to author one must not be read as if it had.
const SHIP_KEYS: Array[String] = ["schema_version", "id", "name", "faction", "archetype", "tier", "role", "family", "element", "chassis_color", "accent_color", "core_depth", "core_stack", "core_dot", "core_weapon", "passives", "rails", "chain", "chain_mode", "description"]
const RAIL_KEYS: Array[String] = ["radius", "order", "speed", "phase", "pump_phase", "pump_amp", "reach_ring", "offset", "slots"]
const SLOT_KEYS: Array[String] = ["type", "radius", "pods", "set_piece", "mount", "hp", "feature", "bob_amp"]

static func from_dict(data: Dictionary, errors: PackedStringArray) -> ShipDefinition:
	for key: String in data:
		if not SHIP_KEYS.has(key): errors.append("JSON: unknown ship key '%s'" % key)
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 4
	ship.id = str(data.get("id", ""))
	ship.display_name = str(data.get("name", ship.id))
	ship.description = str(data.get("description", ""))
	ship.faction = str(data.get("faction", "enemy"))
	ship.archetype = str(data.get("archetype", ""))
	ship.tier = int(data.get("tier", 1))
	ship.role = str(data.get("role", "standard"))
	ship.family = str(data.get("family", "standard_a"))
	ship.chassis_color = str(data.get("chassis_color", ""))
	ship.accent_color = str(data.get("accent_color", ""))
	ship.element = str(data.get("element", Elements.ELEMENT_OF_COLOR.get(ship.accent_color if ship.faction == "player" else ship.chassis_color, "neutral")))
	# `core_stack` is the spec's list of ring radii; depth counts the dot as well.
	ship.core_depth = int(data.get("core_depth", (data.get("core_stack", [34]) as Array).size() + 1))
	ship.core_weapon = str(data.get("core_weapon", ""))
	ship.chain_mode = str(data.get("chain_mode", "sway"))
	var passives: Array[String] = []
	for passive: Variant in data.get("passives", []): passives.append(str(passive))
	ship.passives = passives
	var rails: Array[RailDefinition] = []
	for entry: Variant in data.get("rails", []):
		var source: Dictionary = entry
		for key: String in source:
			if not RAIL_KEYS.has(key): errors.append("JSON: unknown rail key '%s'" % key)
		var rail: RailDefinition = RailDefinition.new()
		rail.radius = int(source.get("radius", 52))
		rail.order = int(source.get("order", 3))
		rail.speed = float(source.get("speed", rail_speed(rails.size())))
		rail.phase = float(source.get("phase", 0.0))
		rail.pump_phase = float(source.get("pump_phase", float(rails.size()) * float(MOTION.pump_phase_step)))
		rail.pump_amp = float(source.get("pump_amp", -1.0))
		rail.reach_ring = bool(source.get("reach_ring", true))
		var offset: Array = source.get("offset", [0, 0])
		rail.offset = Vector2(float(offset[0]), float(offset[1]))
		var slots: Array[SlotDefinition] = []
		for slot: Variant in source.get("slots", []): slots.append(_slot_from(slot, errors))
		rail.slots = slots
		rails.append(rail)
	ship.rails = rails
	var links: Array[SlotDefinition] = []
	for link: Variant in data.get("chain", []): links.append(_slot_from(link, errors))
	ship.chain_links = links
	return ship

## "node" and "stub" are the spec's string shorthand; a dictionary is the full form.
static func _slot_from(value: Variant, errors: PackedStringArray) -> SlotDefinition:
	var slot: SlotDefinition = SlotDefinition.new()
	if value is String:
		slot.type = str(value)
		return slot
	var source: Dictionary = value
	for key: String in source:
		if not SLOT_KEYS.has(key): errors.append("JSON: unknown slot key '%s'" % key)
	slot.type = str(source.get("type", "stub"))
	slot.node_radius = int(source.get("radius", 4))
	slot.pods = int(source.get("pods", 0))
	slot.set_piece = str(source.get("set_piece", ""))
	slot.mount = str(source.get("mount", ""))
	slot.hp = float(source.get("hp", 0.0))
	slot.feature = str(source.get("feature", ""))
	slot.bob_amp = float(source.get("bob_amp", -1.0))
	return slot

static func load_json(path: String, errors: PackedStringArray) -> ShipDefinition:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		errors.append("JSON: %s is not a ship" % path)
		return null
	return from_dict(parsed, errors)

static func on_ladder(radius: float) -> bool:
	for value: int in LADDER.values():
		if is_equal_approx(radius, float(value)): return true
	return false
