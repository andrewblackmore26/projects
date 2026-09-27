class_name ShipGenerator
extends RefCounted
## Owns the 141-hull ROSTER manifest and the five element growth builders
## (spec V3 §8, §9, §14, §17, §21, §22). ShipCatalog keeps loading, caching,
## `recalculate()` and `validate()`; this file is the only place that
## decides what a hull's geometry actually is.
##
## Growth by addition (§17 rule 7): a player hull of tier T is built by
## running `_grow_<element>` once per tier from 2..T, with tier-stamped
## part ids ("t4_pod_1_l"). Each step only ADDS ids (or updates the shared
## "core" id's radius/position in place); no step ever removes or renames
## an id, so tier N-1's set of part ids is always a subset of tier N's -
## which is what lets the renderer's id-matching reshape tween read as
## growth instead of a rebuild.

const Catalog = preload("res://scripts/ships/ship_catalog.gd")

## Tier band [lo, hi] an element's enemy archetypes live in, chosen from the
## campaign level that introduces the element (L1 lightning .. L5 plasma),
## so bands rise across the game.
const ELEMENT_TIER_BAND: Dictionary = {
	"lightning": {"lo": 1, "hi": 2},
	"fire": {"lo": 2, "hi": 3},
	"corruption": {"lo": 3, "hi": 4},
	"void": {"lo": 4, "hi": 5},
	"plasma": {"lo": 5, "hi": 6},
}

## --- The manifest -----------------------------------------------------

static func roster_manifest() -> Array[Dictionary]:
	var manifest: Array[Dictionary] = []
	manifest.append({"faction": "player", "element": "neutral", "tier": 1, "family": "standard_a"})
	for element: String in Catalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			for family: String in Catalog.FAMILIES:
				manifest.append({"faction": "player", "element": element, "tier": tier, "family": family})
	for element: String in Catalog.ELEMENTS:
		var band: Dictionary = ELEMENT_TIER_BAND[element]
		var lo: int = int(band.lo)
		var hi: int = int(band.hi)
		manifest.append({"faction": "enemy", "kind": "drone", "element": element, "tier": lo})
		manifest.append({"faction": "enemy", "kind": "drone", "element": element, "tier": hi})
		manifest.append({"faction": "enemy", "kind": "sentry", "element": element, "tier": lo})
		manifest.append({"faction": "enemy", "kind": "sentry", "element": element, "tier": hi})
		manifest.append({"faction": "enemy", "kind": "chain", "element": element, "tier": hi})
		manifest.append({"faction": "elite", "kind": "radial", "element": element, "tier": hi})
		manifest.append({"faction": "elite", "kind": "irregular", "element": element, "tier": hi})
		manifest.append({"faction": "boss", "element": element, "tier": hi})
	return manifest

## Derived from the manifest so labels can never drift from the roster (the gallery said "81" for a
## while after the roster became 101).
static func player_hull_count() -> int:
	var count: int = 0
	for entry: Dictionary in roster_manifest():
		if str(entry.faction) == "player": count += 1
	return count

static func build_from_entry(entry: Dictionary) -> ShipDefinition:
	match str(entry.get("faction", "")):
		"player": return build_player(str(entry.element), int(entry.tier), str(entry.family))
		"enemy": return build_enemy(str(entry.kind), str(entry.element), int(entry.tier))
		"elite": return build_elite(str(entry.kind), str(entry.element), int(entry.tier))
		"boss": return build_boss(str(entry.element), int(entry.tier))
	return null

## Back-compat single-hull entry point for the editor and description
## compiler, which build one hull outside the manifest for authoring
## experiments; production content always comes from ROSTER.
static func build_ship(element: String, tier: int, is_player: bool = false, family: String = "standard_a", faction: String = "") -> ShipDefinition:
	if is_player: return build_player(element, tier, family)
	if faction == "elite": return build_elite("radial" if tier % 2 == 0 else "irregular", element, tier)
	if faction == "boss": return build_boss(element, tier)
	return build_enemy("drone" if tier % 2 == 0 else "sentry", element, tier)

## P5: deterministic (no search/fallback) resolver from a world descriptor's
## (faction, kind, element, requested difficulty tier) onto the exact,
## always-existing roster id. Each element is only authored across its
## ELEMENT_TIER_BAND, so `tier` is clamped into that band -- a node whose
## Chebyshev difficulty tier sits outside the band gets the nearer authored
## hull and fights at the REQUESTED tier's HP/reward (set by the caller,
## see combat_world.gd `_make_actor`) and slot budget (see
## ShipCatalog.cap_to_tier), not the hull's own authored tier. This replaces
## the old runtime "pick nearest, then trim" shim: the world descriptor now
## names the hull directly, so this function never guesses or falls back --
## an element/kind combination with no roster entry is a hard "" (the
## caller must treat that as a bug, not silently substitute).
static func hull_id(faction: String, kind: String, element: String, tier: int) -> String:
	if not ELEMENT_TIER_BAND.has(element): return ""
	var band: Dictionary = ELEMENT_TIER_BAND[element]
	var lo: int = int(band.lo)
	var hi: int = int(band.hi)
	match faction:
		"boss": return "boss_%s" % element
		"elite":
			if kind not in ["radial", "irregular", "heavy"]: return ""
			return "elite_%s_%s_t%d" % [kind, element, hi]
		"enemy":
			if kind == "chain": return "enemy_chain_%s_t%d" % [element, hi]
			if kind not in ["drone", "sentry"]: return ""
			var midpoint: int = roundi(float(lo + hi) / 2.0)
			var hull_tier: int = hi if tier >= midpoint else lo
			return "enemy_%s_%s_t%d" % [kind, element, hull_tier]
	return ""

## --- Shared helpers -----------------------------------------------------

static func _role_radius(role: String) -> float:
	return 12.0 if role == "compact" else 18.0 if role == "heavy" else 15.0

## Like ShipCatalog.add_pair, but the two mirrored circles can each name a
## different parent (used by fire's "each row parents to the previous row"
## chain, where the left/right chains never cross).
static func _add_chained_pair(ship: ShipDefinition, id: String, position: Vector2, radius: float, color: String, stat: String, layer: int, parent_l: String, parent_r: String) -> void:
	var left: PartDefinition = Catalog.add_part(ship, id + "_l", "circle", Vector2(-position.x, position.y), radius, color, stat, layer, true, parent_l)
	var right: PartDefinition = Catalog.add_part(ship, id + "_r", "circle", position, radius, color, stat, layer, true, parent_r)
	left.mirror_id = right.id
	right.mirror_id = left.id

## Momentum tuning (spec v0.3 §13, plan P6): "Compact hulls turn far tighter."
## `drag` is authored as `accel/speed` so a sustained full-magnitude input
## approaches exactly `speed`, never overshoots it (see ShipDefinition.accel).
## The plan's own suggested compact numbers (300/2400/8.0) measured a 90deg
## turn-radius proxy only ~0.79x standard's, short of the plan's own ">=2x
## tighter" acceptance line - both hulls share the same v^2/accel turn-radius
## shape, so matching drag/speed ratios (accel/speed, both giving top speed
## 300) is not enough; compact needed a materially higher accel BEYOND that
## ratio. Doubled again from the first attempt (2x drag/accel measured
## ~0.5-0.55x, still a coin flip) to 4x standard's, which measured with
## headroom - see tasks/todo.md P6 review for the actual numbers.
static func _base_stats(ship: ShipDefinition) -> void:
	if ship.role == "compact":
		ship.speed = 300.0
		ship.accel = 4800.0
		ship.drag = 16.0
	elif ship.role == "heavy":
		ship.speed = 200.0
		ship.accel = 700.0
		ship.drag = 3.5
	else:
		ship.speed = 240.0
		ship.accel = 1200.0
		ship.drag = 5.0
	ship.turn_rate = 10.0 * (1.25 if ship.role == "compact" else 0.8 if ship.role == "heavy" else 1.0)
	ship.hp_buffer = 0.8 if ship.role == "compact" else 1.3 if ship.role == "heavy" else 1.0
	ship.damage_multiplier = 1.15 if ship.role == "heavy" else 1.0

## --- Player: shared neutral seed -----------------------------------------

static func build_seed() -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	ship.is_player = true
	ship.faction = "player"
	ship.tier = 1
	ship.element = "neutral"
	ship.family = "standard_a"
	ship.role = "standard"
	ship.id = "player_seed"
	ship.display_name = "Lumen"
	ship.motion_signature = "smooth"
	_base_stats(ship)
	ship.primary = "pulse_cannon"
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, 15.0, "chassis", "speed", 3)
	# Two small symmetric fins - not a component, just enough hull mass that
	# the shared seed is not a trivially empty hull (>=60% of its TP budget).
	Catalog.add_pair(ship, "fin", "circle", Vector2(11.0, 6.0), 14.0, "chassis", "structure", 2, "core")
	Catalog.add_line(ship, "fin_link_l", "core", "fin_l")
	Catalog.add_line(ship, "fin_link_r", "core", "fin_r")
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -10.5), 3.5)
	ship.magnet_radius = 95.0
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

## --- Player: growth by addition ------------------------------------------

static func build_player(element: String, tier: int, family: String) -> ShipDefinition:
	if tier <= 1: return build_seed()
	var ship: ShipDefinition = ShipDefinition.new()
	ship.is_player = true
	ship.faction = "player"
	ship.tier = clampi(tier, 2, GameTuning.MAX_TIER)
	ship.element = element
	ship.family = family
	ship.role = Catalog.role_for_family(family)
	ship.id = "player_%s_t%d_%s" % [element, ship.tier, family]
	ship.display_name = "%s %s" % [str(Catalog.NAMES[element][ship.tier - 1]), family.replace("_", " ").capitalize()]
	ship.motion_signature = {"fire": "flicker", "lightning": "snap", "plasma": "counter_rotate"}.get(element, "smooth")
	_base_stats(ship)
	ship.primary = "ricochet" if family == "standard_b" else str(Catalog.ABILITIES[element][0])
	var limits: Dictionary = GameTuning.slots(ship.tier, ship.role)
	for index: int in range(int(limits.secondary)): ship.secondaries.append(str(Catalog.ABILITIES[element][1 + index % 3]))
	# Spec §9: T4/T5 grant 1 passive, T6 grants 2. The element's own signature
	# passive (or family's radar/health_readout override) fills the first
	# slot; T6's second slot is filled from a fixed generic pool, skipping
	# whichever entry the first slot already used, so a T6 hull never mounts
	# the same passive id twice (measured bug: every T6 hull minted only 1
	# of the 2 slots §9 grants it -- GameTuning.slots already returned 2,
	# this loop just never read it).
	if ship.tier >= 4:
		var first_passive: String = "radar" if family == "standard_b" else "health_readout" if family == "compact" else str(Catalog.ABILITIES[element][4])
		ship.passives.append(first_passive)
		var passive_pool: Array[String] = ["radar", "health_readout", "magnet", "siphon", "thrusters", "forcefield", "orbital_seekers"]
		var slot: int = 1
		while ship.passives.size() < int(limits.passive) and slot <= passive_pool.size():
			var candidate: String = str(passive_pool[(slot - 1) % passive_pool.size()])
			if not candidate in ship.passives: ship.passives.append(candidate)
			slot += 1
	match element:
		"fire": _grow_fire(ship, ship.tier)
		"lightning": _grow_lightning(ship, ship.tier)
		"void": _grow_void(ship, ship.tier)
		"corruption": _grow_corruption(ship, ship.tier)
		"plasma": _grow_plasma(ship, ship.tier)
	var body_radius: float = _role_radius(ship.role)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -body_radius * 0.7), 3.5)
	for index: int in range(ship.secondaries.size()): Catalog.mount_component(ship, ship.secondaries[index], "secondary_" + str(index), Vector2(0, body_radius + 7 + index * 9))
	for index: int in range(ship.passives.size()): Catalog.mount_component(ship, ship.passives[index], "passive_" + str(index), Vector2(0, -body_radius - 8 - index * 9))
	ship.magnet_radius = 95 + (15 if ship.role == "heavy" else -10 if ship.role == "compact" else 0) + (8 if family == "standard_b" else 0)
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	# Every element/role/tier combination is checked against a "not
	# trivially empty" TP floor (>= 60% of budget); rather than hand-tune
	# five growth functions x three roles x six tiers to hit it exactly,
	# top up with small plates hugging the core (well inside the hull's
	# already-established footprint, so this never touches the role's
	# footprint band) until the floor is met. `min_topups` inherits the
	# PREVIOUS tier's own topup count (recursively) so a tier never needs
	# FEWER topups than the tier below it purely because its own organic
	# growth happened to close more of the gap - which would otherwise
	# remove an id and break the growth-by-addition subset property.
	var min_topups: int = 0
	if ship.tier > 2:
		var previous: ShipDefinition = build_player(element, ship.tier - 1, family)
		for part: PartDefinition in previous.parts:
			if part.id.begins_with("topup_") and part.id.ends_with("_l"):
				min_topups = maxi(min_topups, int(part.id.trim_prefix("topup_").trim_suffix("_l")) + 1)
	var topup_index: int = 0
	while topup_index < min_topups or (ship.tp_used < ship.tp_max * 0.62 and topup_index < 16):
		var angle: float = 0.7 + float(topup_index) * 0.9
		var topup_radius: float = 6.0 + float(topup_index) * 0.5
		Catalog.add_pair(ship, "topup_%d" % topup_index, "circle", Vector2.from_angle(angle) * (body_radius * 0.9), topup_radius, "chassis", "structure", 2, "core")
		Catalog.add_line(ship, "topup_%d_link_l" % topup_index, "core", "topup_%d_l" % topup_index)
		Catalog.add_line(ship, "topup_%d_link_r" % topup_index, "core", "topup_%d_r" % topup_index)
		Catalog.recalculate(ship)
		topup_index += 1
	return ship

## Fire (red): dense clusters of small circles fanning outward, radius
## DECREASING outward, short lines. Each new tier's pod is parented to the
## previous tier's pod (a chain out from the core), so a future detachment
## (P4) can sever the outer tiers without touching the inner ones.
static func _grow_fire(ship: ShipDefinition, tier: int) -> void:
	var base_r: float = _role_radius(ship.role)
	# Per-row outward growth scales with the role's own body radius, so a
	# compact hull's footprint stays inside its (smaller) role band instead
	# of fanning out by the same absolute distance as a heavy hull.
	var scale: float = base_r / 15.0
	var prev_l: String = "core"
	var prev_r: String = "core"
	for t: int in range(2, tier + 1):
		if t == 2: Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
		var row: int = t - 2
		var radius: float = maxf(3.0, base_r * 0.75 - row * 1.7 * scale)
		var distance: float = base_r * 0.85 + row * 11.0 * scale
		var y: float = -base_r * 0.25 - row * 5.0 * scale
		var id: String = "t%d_pod" % t
		_add_chained_pair(ship, id, Vector2(distance, y), radius, "chassis", "speed" if row % 2 == 0 else "magnet_radius", 2, prev_l, prev_r)
		Catalog.add_line(ship, id + "_link_l", prev_l, id + "_l")
		Catalog.add_line(ship, id + "_link_r", prev_r, id + "_r")
		# From the second grown row on, a tighter sub-pod gives the "dense
		# cluster" the spec asks for; the very first row stays a single
		# pair so a T2 hull has room in its TP budget.
		if row > 0:
			var tight_id: String = "t%d_bud" % t
			# Same radius as this row's pod (fire's "unequal sizes" belongs to
			# corruption, not fire): placed further out at an equal radius so
			# the outward radius sequence stays measurably non-increasing.
			var tight_radius: float = radius
			# Offset kept smaller than the gap between rows (11px) so this
			# tier's bud never lands farther from the core than the NEXT
			# tier's (smaller-radius) pod - otherwise sorting by distance
			# would show radius increasing outward at that boundary.
			_add_chained_pair(ship, tight_id, Vector2(distance + radius * 0.5, y - 4.0), tight_radius, "chassis", "structure", 2, id + "_l", id + "_r")
			Catalog.add_line(ship, tight_id + "_link_l", id + "_l", tight_id + "_l")
			Catalog.add_line(ship, tight_id + "_link_r", id + "_r", tight_id + "_r")
		prev_l = id + "_l"
		prev_r = id + "_r"

## Lightning (yellow): few circles on long straight spokes, tight small
## circles at the ends. Stays `rigid` (no motion group).
static func _grow_lightning(ship: ShipDefinition, tier: int) -> void:
	var base_r: float = _role_radius(ship.role)
	var scale: float = base_r / 15.0
	for t: int in range(2, tier + 1):
		if t == 2: Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
		var row: int = t - 2
		var spoke_length: float = base_r * 2.4 + row * 24.0 * scale
		var y: float = -base_r * 0.2 - row * 7.0 * scale
		var tip_radius: float = 6.5 + row * 0.9
		var id: String = "t%d_spoke" % t
		Catalog.add_pair(ship, id, "circle", Vector2(spoke_length, y), tip_radius, "chassis", "magnet_radius" if row % 2 == 0 else "speed", 2, "core")
		Catalog.add_line(ship, id + "_link_l", "core", id + "_l")
		Catalog.add_line(ship, id + "_link_r", "core", id + "_r")
		# A short forked barb at the tip - "few circles on long straight
		# spokes, tight small circles at the ends" plus enough hull mass
		# that lightning hulls are not trivially empty.
		var barb_id: String = "t%d_barb" % t
		_add_chained_pair(ship, barb_id, Vector2(spoke_length + tip_radius * 1.6, y + 6.0), maxf(2.5, tip_radius * 0.6), "chassis", "structure", 2, id + "_l", id + "_r")
		Catalog.add_line(ship, barb_id + "_link_l", id + "_l", barb_id + "_l")
		Catalog.add_line(ship, barb_id + "_link_r", id + "_r", barb_id + "_r")

## Void (black, silver rim): a black disc that widens each tier, the build
## happening INSIDE it; concentric rings; satellites on dashed reach rings
## (orbit groups with reach_ring=true). Discs stay `rigid`.
static func _grow_void(ship: ShipDefinition, tier: int) -> void:
	var base_r: float = _role_radius(ship.role)
	for t: int in range(2, tier + 1):
		if t == 2: Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
		ship.hull_radius = base_r + 4.0 * t
		for part: PartDefinition in ship.parts:
			if part.id == "core": part.radius = ship.hull_radius
		var row: int = t - 2
		# One concentric ring per tier (5 rings by T6 - still "concentric
		# rings", plural, just not doubled within a tier, which was
		# ballooning the footprint past the role's band), each with its own
		# dashed-reach-ring satellite pair; sign alternates tier to tier.
		var ring_radius: float = ship.hull_radius * (0.32 + 0.11 * row)
		var suffix: String = "t%d_ring" % t
		Catalog.add_part(ship, suffix, "circle", Vector2.ZERO, ring_radius, "chassis", "structure", 2, false, "core")
		Catalog.add_pair(ship, suffix + "_sat", "circle", Vector2(ring_radius, 0), 5.0 + row * 0.5, "chassis", "magnet_radius", 3, "core")
		var speed: float = (0.5 + 0.1 * t) * (1.0 if row % 2 == 0 else -1.0)
		var group_l: GroupDefinition = GroupDefinition.new()
		group_l.root_id = suffix + "_sat_l"
		group_l.orbit_radius = ring_radius
		group_l.orbit_speed = speed
		group_l.reach_ring = true
		ship.groups.append(group_l)
		var group_r: GroupDefinition = GroupDefinition.new()
		group_r.root_id = suffix + "_sat_r"
		group_r.orbit_radius = ring_radius
		group_r.orbit_speed = -speed
		group_r.reach_ring = true
		ship.groups.append(group_r)

## Corruption (green): irregular clusters of unequal circles joined by
## lines, off-axis buds; a whipping tail chain (chain_mode="whip"); a
## breathing core group. Every corruption hull carries >=1 whip group from
## tier 2 up, so the tail is seeded once and only ever extended.
static func _grow_corruption(ship: ShipDefinition, tier: int) -> void:
	var base_r: float = _role_radius(ship.role)
	var scale: float = base_r / 15.0
	for t: int in range(2, tier + 1):
		if t == 2:
			Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
			var breathe: GroupDefinition = GroupDefinition.new()
			breathe.root_id = "core"
			breathe.breathe_amp = 0.05
			ship.groups.append(breathe)
			Catalog.add_part(ship, "tail_0", "circle", Vector2(0, base_r + 9.0), 6.0, "chassis", "structure", 2, true, "core")
			Catalog.add_line(ship, "tail_0_link", "core", "tail_0")
			var whip: GroupDefinition = GroupDefinition.new()
			whip.root_id = "tail_0"
			whip.chain_mode = "whip"
			ship.groups.append(whip)
		var row: int = t - 2
		var lobe_radius: float = maxf(5.0, base_r * 0.62 - row * 0.6)
		var lx: float = base_r * 0.9 + row * 9.0 * scale
		var ly: float = (row - 1.0) * 13.0 * scale
		Catalog.add_pair(ship, "t%d_bud" % t, "circle", Vector2(lx, ly), lobe_radius, "chassis", "speed" if row % 2 == 0 else "magnet_radius", 2, "core")
		Catalog.add_line(ship, "t%d_bud_link_l" % t, "core", "t%d_bud_l" % t)
		Catalog.add_line(ship, "t%d_bud_link_r" % t, "core", "t%d_bud_r" % t)
		# From the second grown row on, a second off-axis unequal-size bud
		# gives the "irregular clusters of unequal circles" the spec asks
		# for (T2 stays simple so its TP budget has room).
		if row > 0:
			var stub_radius: float = maxf(3.0, lobe_radius * 0.6)
			Catalog.add_pair(ship, "t%d_stub" % t, "circle", Vector2(lx * 0.7, ly - 10.0), stub_radius, "chassis", "structure", 2, "core")
			Catalog.add_line(ship, "t%d_stub_link_l" % t, "core", "t%d_stub_l" % t)
			Catalog.add_line(ship, "t%d_stub_link_r" % t, "core", "t%d_stub_r" % t)
		var prev_tail: String = "tail_%d" % row
		var next_tail: String = "tail_%d" % (row + 1)
		Catalog.add_part(ship, next_tail, "circle", Vector2(0, base_r + 9.0 + (row + 1) * 9.0 * scale), maxf(3.5, 7.0 - row), "chassis", "structure", 2, true, prev_tail)
		Catalog.add_line(ship, next_tail + "_link", prev_tail, next_tail)

## Plasma (violet): concentric orbital rings (unfilled circles) with
## circles RIDING on them - orbit groups at the ring radius, adjacent rings
## alternating orbit_speed sign so the hull does not read as one wheel.
static func _grow_plasma(ship: ShipDefinition, tier: int) -> void:
	var base_r: float = _role_radius(ship.role)
	var scale: float = base_r / 15.0
	for t: int in range(2, tier + 1):
		if t == 2: Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
		var row: int = t - 2
		# One concentric orbital ring per tier (five by T6); adjacent TIERS
		# alternate orbit_speed sign so the hull never reads as one
		# spinning wheel (spec §18); doubling rings within a tier ballooned
		# the footprint past the role's band without adding much signature.
		var ring_radius: float = base_r + (8.0 + row * 9.0) * scale
		var suffix: String = "t%d_ring" % t
		Catalog.add_part(ship, suffix, "circle", Vector2.ZERO, ring_radius, "chassis", "magnet_radius", 2, false, "core")
		var sign: float = 1.0 if row % 2 == 0 else -1.0
		Catalog.add_pair(ship, suffix + "_rider", "circle", Vector2(ring_radius, 0), 5.0 + row * 0.5, "chassis", "speed", 3, "core")
		var speed: float = sign * (0.5 + 0.1 * t)
		var group_l: GroupDefinition = GroupDefinition.new()
		group_l.root_id = suffix + "_rider_l"
		group_l.orbit_radius = ring_radius
		group_l.orbit_speed = speed
		ship.groups.append(group_l)
		var group_r: GroupDefinition = GroupDefinition.new()
		group_r.root_id = suffix + "_rider_r"
		group_r.orbit_radius = ring_radius
		group_r.orbit_speed = -speed
		ship.groups.append(group_r)

## --- Enemies (spec §14) ---------------------------------------------------

## Void/plasma enemies carry the same body-feature stats the sim reads
## (combat_broadphase.gd body_features: bullet_eater / void_pull /
## projectile_orbit) that the old monolithic build_ship authored on its
## "maw"/"reach"/"orbit_0" ids. Regular enemy archetypes keep those ids so
## the mechanic keeps happening in play, not just in the schema.
static func _add_enemy_body_feature(ship: ShipDefinition, element: String, base_r: float) -> void:
	if element == "void":
		# CombatCompositor treats any hull with hull_radius > 0 as an opaque
		# void disc that masks the processed background (combat_compositor.gd).
		ship.hull_radius = base_r
		var maw: PartDefinition = Catalog.add_part(ship, "maw", "circle", Vector2(0, -base_r * 0.3), base_r * 0.5, "chassis", "structure", 3, true, "core")
		maw.stat_id = "bullet_eater"
		maw.stat_value = 9.0
		Catalog.add_line(ship, "maw_link", "core", "maw")
		var reach: PartDefinition = Catalog.add_part(ship, "reach", "circle", Vector2.ZERO, 1.0, "chassis", "structure", 3, false, "core")
		reach.stat_id = "void_pull"
		reach.stat_value = 180.0
		var reach_group: GroupDefinition = GroupDefinition.new()
		reach_group.root_id = "reach"
		reach_group.orbit_radius = base_r + 9.0
		reach_group.reach_ring = true
		ship.groups.append(reach_group)
	elif element == "plasma":
		var orbit0: PartDefinition = Catalog.add_part(ship, "orbit_0", "circle", Vector2.ZERO, base_r + 8.0, "chassis", "structure", 2, false, "core")
		orbit0.stat_id = "projectile_orbit"
		orbit0.stat_value = 65.0

static func _enemy_base(ship: ShipDefinition, element: String, tier: int) -> void:
	ship.is_player = false
	ship.faction = "enemy"
	ship.symmetry = "bilateral"
	ship.tier = clampi(tier, 1, GameTuning.MAX_TIER)
	ship.element = element
	ship.family = "standard_a"
	ship.role = "standard"
	ship.motion_signature = {"fire": "flicker", "lightning": "snap", "plasma": "counter_rotate"}.get(element, "smooth")
	_base_stats(ship)
	# void/plasma's tier-1 primary (homing_beam/beam) is a continuous player
	# weapon; enemies fire bullet patterns instead (matches v0.2 behaviour).
	ship.primary = "pulse_cannon" if element in ["void", "plasma"] else str(Catalog.ABILITIES[element][0])
	var limits: Dictionary = GameTuning.slots(ship.tier, ship.role)
	for index: int in range(int(limits.secondary)): ship.secondaries.append(str(Catalog.ABILITIES[element][1 + index % 3]))
	if element == "corruption" and not ship.secondaries.is_empty(): ship.secondaries[0] = "droid_bay"
	ship.magnet_radius = 90.0

## Core + 2-4 pods, radially arranged.
static func build_enemy_drone(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	_enemy_base(ship, element, tier)
	ship.id = "enemy_drone_%s_t%d" % [element, ship.tier]
	ship.display_name = "%s Drone T%d" % [element.capitalize(), ship.tier]
	var base_r: float = 10.0 + ship.tier * 1.5
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	_add_enemy_body_feature(ship, element, base_r)
	var pod_count: int = clampi(2 + ship.tier / 2, 2, 4)
	for i: int in range(pod_count):
		var angle: float = TAU * float(i) / float(pod_count)
		var pos: Vector2 = Vector2.from_angle(angle) * (base_r + 8.0)
		Catalog.add_part(ship, "pod_%d" % i, "circle", pos, 5.0, "chassis", "structure", 2, true, "core")
		Catalog.add_line(ship, "pod_%d_link" % i, "core", "pod_%d" % i)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -base_r * 0.7))
	for index: int in range(ship.secondaries.size()): Catalog.mount_component(ship, ship.secondaries[index], "secondary_" + str(index), Vector2(0, base_r + 7 + index * 9))
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

## Core + a weapon prong cluster; mounts the existing laser_prong ability
## (telegraphed long-range shot). Standing still is AI/combat behaviour
## (P4); this step only authors the geometry.
static func build_enemy_sentry(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	_enemy_base(ship, element, tier)
	ship.id = "enemy_sentry_%s_t%d" % [element, ship.tier]
	ship.display_name = "%s Sentry T%d" % [element.capitalize(), ship.tier]
	# Enemies share the tier/role slot table (spec §9); a T1 sentry has no
	# secondary slot at all, so laser_prong only mounts from T2 up.
	var limits: Dictionary = GameTuning.slots(ship.tier, ship.role)
	var has_secondary: bool = int(limits.secondary) >= 1
	if has_secondary: ship.secondaries = ["laser_prong"]
	var base_r: float = 9.0 + ship.tier * 1.5
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	_add_enemy_body_feature(ship, element, base_r)
	for i: int in range(3):
		var angle: float = -PI / 2.0 + float(i - 1) * 0.5
		var pos: Vector2 = Vector2.from_angle(angle) * (base_r + 10.0)
		Catalog.add_part(ship, "prong_%d" % i, "circle", pos, 3.5, "chassis", "structure", 2, true, "core")
		Catalog.add_line(ship, "prong_%d_link" % i, "core", "prong_%d" % i)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -base_r * 0.7))
	if has_secondary: Catalog.mount_component(ship, "laser_prong", "secondary_0", Vector2(0, base_r + 9))
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

## Head cluster + a tail of shrinking circles, chain_mode="whip" (severable
## in P4 - detachment is out of scope here).
static func build_enemy_chain(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	_enemy_base(ship, element, tier)
	ship.id = "enemy_chain_%s_t%d" % [element, ship.tier]
	ship.display_name = "%s Chain T%d" % [element.capitalize(), ship.tier]
	var base_r: float = 10.0 + ship.tier * 1.5
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	_add_enemy_body_feature(ship, element, base_r)
	var prev: String = "core"
	for i: int in range(5):
		var r: float = maxf(3.0, base_r * 0.55 - i * 1.4)
		var id: String = "tail_%d" % i
		Catalog.add_part(ship, id, "circle", Vector2(0, base_r + 10.0 + i * 9.0), r, "chassis", "structure", 2, true, prev)
		Catalog.add_line(ship, id + "_link", prev, id)
		prev = id
	var whip: GroupDefinition = GroupDefinition.new()
	whip.root_id = "tail_0"
	whip.chain_mode = "whip"
	ship.groups.append(whip)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -base_r * 0.7))
	for index: int in range(ship.secondaries.size()): Catalog.mount_component(ship, ship.secondaries[index], "secondary_" + str(index), Vector2(0, base_r + 7 + index * 9))
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

static func build_enemy(kind: String, element: String, tier: int) -> ShipDefinition:
	match kind:
		"sentry": return build_enemy_sentry(element, tier)
		"chain": return build_enemy_chain(element, tier)
	return build_enemy_drone(element, tier)

## --- Elites (spec §14) -----------------------------------------------------

static func _elite_base(ship: ShipDefinition, element: String, tier: int) -> void:
	ship.is_player = false
	ship.faction = "elite"
	ship.symmetry = "radial"
	ship.tier = clampi(tier, 1, GameTuning.MAX_TIER)
	ship.element = element
	ship.family = "heavy"
	ship.role = "heavy"
	ship.motion_signature = {"fire": "flicker", "lightning": "snap", "plasma": "counter_rotate"}.get(element, "smooth")
	_base_stats(ship)
	ship.primary = str(Catalog.ABILITIES[element][0])
	ship.magnet_radius = 105.0

## Elites are authored 2-4x the same-tier standard player hull's footprint
## (measured, not asserted - see tests/ship_roster_test.gd); this reads the
## in-memory player build directly rather than the on-disk cache, which is
## not yet populated during a fresh export_catalog run.
static func _elite_reference_footprint(element: String, tier: int) -> float:
	var reference: ShipDefinition = build_player(element, clampi(tier, 2, GameTuning.MAX_TIER), "standard_a")
	return reference.footprint if reference != null else 90.0

## Canonical reference model (spec): core + 3-6 arms, each a hub with a
## pod and a gun; arms orbit, inner satellites counter-rotate, dashed
## reach rings.
static func build_elite_radial(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	_elite_base(ship, element, tier)
	ship.id = "elite_radial_%s_t%d" % [element, ship.tier]
	ship.display_name = "%s Radial Elite T%d" % [element.capitalize(), ship.tier]
	# Farthest authored point from the core is roughly base_r + 30 (arm hub
	# + pod + radius); pick base_r so the footprint (2x that) lands at 3x
	# the same-tier standard player hull, mid-band of the 2-4x target.
	var target_diameter: float = _elite_reference_footprint(element, ship.tier) * 3.0
	var base_r: float = maxf(20.0, target_diameter / 2.0 - 30.0)
	if element == "void": ship.hull_radius = base_r
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	var arm_count: int = clampi(3 + ship.tier / 2, 3, 6)
	for i: int in range(arm_count):
		var angle: float = TAU * float(i) / float(arm_count)
		var hub_id: String = "hub_%d" % i
		var hub_pos: Vector2 = Vector2.from_angle(angle) * (base_r + 16.0)
		Catalog.add_part(ship, hub_id, "circle", hub_pos, 8.0, "chassis", "structure", 2, true, "core")
		Catalog.add_line(ship, hub_id + "_link", "core", hub_id)
		var pod_id: String = "pod_%d" % i
		var pod_pos: Vector2 = hub_pos + Vector2.from_angle(angle) * 10.0
		Catalog.add_part(ship, pod_id, "circle", pod_pos, 4.0, "chassis", "structure", 2, true, hub_id)
		Catalog.add_line(ship, pod_id + "_link", hub_id, pod_id)
		var gun_ability: String = str(Catalog.ABILITIES[element][1 + i % 3])
		var gun_pos: Vector2 = hub_pos + Vector2.from_angle(angle + PI / 2.0) * 8.0
		Catalog.mount_component(ship, gun_ability, "elite_weapon_%d" % i, gun_pos, 6.0)
		ship.parts[-2].hp = 24 + ship.tier * 15
		var orbit: GroupDefinition = GroupDefinition.new()
		orbit.root_id = hub_id
		orbit.orbit_radius = base_r + 16.0
		orbit.orbit_speed = 0.4 * (1.0 if i % 2 == 0 else -1.0)
		orbit.reach_ring = (i == 0)
		ship.groups.append(orbit)
	Catalog.add_part(ship, "sat_l", "circle", Vector2(-base_r * 0.4, 0), 4.0, "chassis", "structure", 2, true, "core")
	Catalog.add_part(ship, "sat_r", "circle", Vector2(base_r * 0.4, 0), 4.0, "chassis", "structure", 2, true, "core")
	var group_l: GroupDefinition = GroupDefinition.new()
	group_l.root_id = "sat_l"
	group_l.orbit_radius = base_r * 0.4
	group_l.orbit_speed = -0.8
	var group_r: GroupDefinition = GroupDefinition.new()
	group_r.root_id = "sat_r"
	group_r.orbit_radius = base_r * 0.4
	group_r.orbit_speed = 0.8
	ship.groups.append(group_l)
	ship.groups.append(group_r)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -base_r * 0.7), 8.0)
	ship.parts[-2].hp = 24 + ship.tier * 15
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

## 15-40 circles of mixed size, asymmetric, independent drift per cluster.
static func build_elite_irregular(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	_elite_base(ship, element, tier)
	# Spec §14: the irregular elite is deliberately asymmetric, "no repeating pattern".
	ship.symmetry = "none"
	ship.id = "elite_irregular_%s_t%d" % [element, ship.tier]
	ship.display_name = "%s Irregular Elite T%d" % [element.capitalize(), ship.tier]
	# Farthest authored point is roughly base_r + 51 (cluster center spread
	# + bit offset + bit radius); same 3x mid-band target as the radial.
	var target_diameter: float = _elite_reference_footprint(element, ship.tier) * 3.0
	var base_r: float = maxf(18.0, target_diameter / 2.0 - 51.0)
	if element == "void": ship.hull_radius = base_r
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(ship.id)
	var cluster_count: int = 4
	var total_circles: int = clampi(15 + ship.tier * 3, 15, 40)
	var per_cluster: int = maxi(2, total_circles / cluster_count)
	for c: int in range(cluster_count):
		var cluster_angle: float = TAU * float(c) / float(cluster_count) + rng.randf_range(-0.3, 0.3)
		var cluster_center: Vector2 = Vector2.from_angle(cluster_angle) * (base_r + 14.0 + rng.randf_range(-6.0, 10.0))
		var hub_id: String = "cluster_%d_hub" % c
		Catalog.add_part(ship, hub_id, "circle", cluster_center, 7.0 + rng.randf_range(0.0, 3.0), "chassis", "structure", 2, true, "core")
		Catalog.add_line(ship, hub_id + "_link", "core", hub_id)
		var drift: GroupDefinition = GroupDefinition.new()
		drift.root_id = hub_id
		drift.drift_amp = 2.0
		drift.drift_freq = 0.15 + rng.randf_range(0.0, 0.1)
		ship.groups.append(drift)
		for k: int in range(per_cluster - 1):
			var pos: Vector2 = cluster_center + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
			var r: float = rng.randf_range(2.5, 7.0)
			var id: String = "cluster_%d_bit_%d" % [c, k]
			Catalog.add_part(ship, id, "circle", pos, r, "chassis", "structure", 2, true, hub_id)
			Catalog.add_line(ship, id + "_link", hub_id, id)
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, -base_r * 0.6), 8.0)
	ship.parts[-2].hp = 24 + ship.tier * 15
	# A minimum of 3 active/destructible weapon circles is a whole-roster
	# invariant (ships_validation.gd, combat_tests.gd), not just the
	# radial's per-arm guns; the irregular archetype gets extra guns
	# scattered across two of its clusters.
	var weapon_count: int = clampi(2 + ship.tier / 2, 2, 4)
	for w: int in range(weapon_count):
		var cluster: int = w % cluster_count
		var angle: float = TAU * float(cluster) / float(cluster_count)
		var pos: Vector2 = Vector2.from_angle(angle) * (base_r + 24.0 + w * 6.0)
		Catalog.mount_component(ship, str(Catalog.ABILITIES[element][1 + w % 3]), "elite_weapon_%d" % w, pos, 6.0)
		ship.parts[-2].hp = 24 + ship.tier * 15
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship

static func build_elite(kind: String, element: String, tier: int) -> ShipDefinition:
	if kind == "irregular": return build_elite_irregular(element, tier)
	return build_elite_radial(element, tier)

## --- Bosses (spec §14, one per campaign level/element) ---------------------

## 3-4x player scale, multiple cores / a shielded core. Sub-cores carry
## stat_id "sub_core" and the shield generator carries "shield_generator";
## P4 implements their behaviour, here they are just authored circles with
## hp. faction "boss" replaces the v0.2 "rival" faction.
static func build_boss(element: String, tier: int) -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	ship.is_player = false
	ship.faction = "boss"
	ship.symmetry = "radial"
	ship.tier = clampi(tier, 1, GameTuning.MAX_TIER)
	ship.element = element
	ship.family = "heavy"
	ship.role = "heavy"
	ship.id = "boss_%s" % element
	ship.display_name = "%s Boss" % element.capitalize()
	ship.motion_signature = {"fire": "flicker", "lightning": "snap", "plasma": "counter_rotate"}.get(element, "smooth")
	_base_stats(ship)
	ship.primary = str(Catalog.ABILITIES[element][0])
	ship.magnet_radius = 130.0
	var base_r: float = _role_radius("heavy") * 3.5 + ship.tier * 4.0
	if element == "void": ship.hull_radius = base_r
	Catalog.add_part(ship, "core", "circle", Vector2.ZERO, base_r, "chassis", "speed", 3)
	for i: int in range(2):
		var angle: float = PI / 2.0 + i * PI
		var pos: Vector2 = Vector2.from_angle(angle) * (base_r * 0.55)
		var id: String = "sub_core_%d" % i
		var part: PartDefinition = Catalog.add_part(ship, id, "circle", pos, base_r * 0.35, "chassis", "structure", 3, true, "core")
		part.stat_id = "sub_core"
		part.hp = 200.0 + ship.tier * 40.0
		Catalog.add_line(ship, id + "_link", "core", id)
	var shield_pos: Vector2 = Vector2(0, -base_r * 0.95)
	var shield_part: PartDefinition = Catalog.add_part(ship, "shield_generator", "circle", shield_pos, base_r * 0.22, "yellow", "structure", 3, true, "core")
	shield_part.stat_id = "shield_generator"
	shield_part.hp = 150.0 + ship.tier * 30.0
	Catalog.add_line(ship, "shield_generator_link", "core", "shield_generator")
	Catalog.mount_component(ship, ship.primary, "primary", Vector2(0, base_r * 0.95), 12.0)
	ship.parts[-2].hp = 260.0 + ship.tier * 60.0
	# Turret ring (spec §14 enemy-only component): a REAL ring of independently
	# orbiting weapon circles, each with its own HP and its own orbit group -
	# not a faked spread of instantaneous directions (see combat_ai.gd /
	# combat_world.gd `_update_guns`, which fires every gun circle from where
	# it actually is). Bonus mounts (not listed in `secondaries`), so they do
	# not disturb the loadout-slot invariants `ship_roster_test.gd` checks.
	var ring_ability: String = str(Catalog.ABILITIES[element][1])
	var ring_count: int = 6
	var ring_radius: float = base_r + 22.0
	for i: int in range(ring_count):
		var angle: float = TAU * float(i) / float(ring_count)
		var pos: Vector2 = Vector2.from_angle(angle) * ring_radius
		var mount_id: String = "turret_ring_%d" % i
		Catalog.mount_component(ship, ring_ability, mount_id, pos, 5.0)
		ship.parts[-2].hp = 30.0 + ship.tier * 10.0
		var orbit: GroupDefinition = GroupDefinition.new()
		orbit.root_id = mount_id
		orbit.orbit_radius = ring_radius
		orbit.orbit_speed = 0.35
		ship.groups.append(orbit)
	# Deployment ramp: periodically releases small regular units.
	Catalog.mount_component(ship, "deployment_ramp", "deployment_ramp", Vector2(-base_r * 0.7, base_r * 0.7), 6.0)
	ship.parts[-2].hp = 60.0 + ship.tier * 15.0
	# Egg: bursts into a spread of seeker missiles when damaged (reactive,
	# see `_damage_part`'s `rig.ability_id[index]=="egg"` branch).
	Catalog.mount_component(ship, "egg", "egg", Vector2(base_r * 0.7, base_r * 0.7), 7.0)
	ship.parts[-2].hp = 50.0 + ship.tier * 12.0
	ship.abilities = ship.mounted_components()
	Catalog.recalculate(ship)
	return ship
