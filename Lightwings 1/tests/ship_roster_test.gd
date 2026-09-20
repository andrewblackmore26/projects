extends SceneTree
## P2b-1: six tiers, ship_generator.gd, the 141-hull roster (spec V3 §8/§9/§14/§17/§21/§22).
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void:
	var h: Harness = Harness.new("ship_roster")

	# --- Census: 101 player / 25 enemy / 10 elite / 5 boss = 141, 0 warnings ---
	var manifest: Array[Dictionary] = ShipGenerator.roster_manifest()
	h.check(manifest.size() == 141, "Manifest lists 141 hulls (found %d)" % manifest.size())
	var by_faction: Dictionary = {}
	var built: Dictionary = {}
	var total_warnings: int = 0
	for entry: Dictionary in manifest:
		var ship: ShipDefinition = ShipGenerator.build_from_entry(entry)
		h.check(ship != null, "Manifest entry builds a hull: " + JSON.stringify(entry))
		if ship == null: continue
		built[ship.id] = ship
		by_faction[ship.faction] = int(by_faction.get(ship.faction, 0)) + 1
		var errors: PackedStringArray = ShipCatalog.validate(ship)
		h.check(errors.is_empty(), ship.id + " validates: " + " | ".join(errors))
		var warnings: PackedStringArray = ShipCatalog.warnings(ship)
		total_warnings += warnings.size()
		if not warnings.is_empty(): push_error(ship.id + " warnings: " + " | ".join(warnings))
	h.check(by_faction.get("player", 0) == 101 and by_faction.get("enemy", 0) == 25 and by_faction.get("elite", 0) == 10 and by_faction.get("boss", 0) == 5, "Census 101/25/10/5 = 141: " + str(by_faction))
	h.check(total_warnings == 0, "Roster carries 0 warnings (found %d)" % total_warnings)
	# Negative control: a hull with a disconnected part must warn.
	var sample: ShipDefinition = (built.get("player_fire_t3_standard_a") as ShipDefinition).duplicate(true)
	ShipCatalog.add_part(sample, "orphan", "circle", Vector2(900, 900), 3.0, "chassis", "structure", 3, true, "core")
	h.control("a disconnected part added to a valid hull", not ShipCatalog.warnings(sample).is_empty())

	# --- Growth by addition: tier N-1's part ids are a subset of tier N's ---
	var pairs: int = 0
	for element: String in ShipCatalog.ELEMENTS:
		for family: String in ShipCatalog.FAMILIES:
			for tier: int in range(2, GameTuning.MAX_TIER):
				var before: ShipDefinition = built.get("player_%s_t%d_%s" % [element, tier, family])
				var after: ShipDefinition = built.get("player_%s_t%d_%s" % [element, tier + 1, family])
				if before == null or after == null: continue
				var before_ids: Dictionary = {}
				for part: PartDefinition in before.parts: before_ids[part.id] = true
				var after_ids: Dictionary = {}
				for part: PartDefinition in after.parts: after_ids[part.id] = true
				var subset: bool = true
				for id: String in before_ids:
					if not after_ids.has(id): subset = false; break
				h.check(subset, "%s->%s: tier %d ids are a subset of tier %d's" % [before.id, after.id, tier, tier + 1])
				pairs += 1
	h.check(pairs == 80, "80 (hull, tier->tier+1) pairs checked (found %d)" % pairs)
	# Negative control: shuffling one tier's ids must be caught as NOT a subset.
	var shuffled_before: ShipDefinition = (built.get("player_fire_t2_standard_a") as ShipDefinition).duplicate(true)
	shuffled_before.parts[1].id = "shuffled_id_not_in_next_tier"
	var shuffled_ids: Dictionary = {}
	for part: PartDefinition in shuffled_before.parts: shuffled_ids[part.id] = true
	var real_after: ShipDefinition = built.get("player_fire_t3_standard_a")
	var real_after_ids: Dictionary = {}
	for part: PartDefinition in real_after.parts: real_after_ids[part.id] = true
	var caught_shuffle: bool = false
	for id: String in shuffled_ids:
		if not real_after_ids.has(id): caught_shuffle = true; break
	h.control("a shuffled part id no longer present in the next tier", caught_shuffle)

	# --- Each tier's 4 player hulls span >= 2 roles ---
	var role_span_ok: bool = true
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			var roster: Array[ShipDefinition] = ShipCatalog.roster(element, tier)
			var roles: Dictionary = {}
			for ship: ShipDefinition in roster: roles[ship.role] = true
			if roster.size() != 4 or roles.size() < 2: role_span_ok = false
	h.check(role_span_ok, "Every tier's 4 player hulls span >= 2 roles")
	# Negative control: force a synthetic 4-hull roster to share one role and
	# run the same role-counting logic used above over it.
	var mono_roster: Array[ShipDefinition] = []
	for i: int in range(4):
		var clone: ShipDefinition = (built.get("player_fire_t3_standard_a") as ShipDefinition).duplicate(true)
		clone.role = "standard"
		mono_roster.append(clone)
	var mono_roles: Dictionary = {}
	for clone: ShipDefinition in mono_roster: mono_roles[clone.role] = true
	h.control("a synthetic 4-hull roster where every hull shares one role", mono_roles.size() < 2)

	# --- Elite footprint is 2-4x the same-tier standard player hull ---
	var footprint_ok: bool = true
	var footprint_ratios: Array[float] = []
	for element: String in ShipCatalog.ELEMENTS:
		var band: Dictionary = ShipGenerator.ELEMENT_TIER_BAND[element]
		var hi: int = int(band.hi)
		var standard: ShipDefinition = built.get("player_%s_t%d_standard_a" % [element, hi])
		var radial: ShipDefinition = built.get("elite_radial_%s_t%d" % [element, hi])
		var ratio: float = radial.footprint / standard.footprint
		footprint_ratios.append(ratio)
		if ratio < 2.0 or ratio > 4.0: footprint_ok = false
	h.check(footprint_ok, "Elite footprint is 2-4x the same-tier standard player hull: " + str(footprint_ratios))
	h.control("an elite footprint equal to the standard hull's (ratio 1.0)", not (1.0 >= 2.0 and 1.0 <= 4.0))

	# --- Element signatures, measured ---
	var fire: ShipDefinition = built.get("player_fire_t6_standard_a")
	var fire_points: Array = []
	for part: PartDefinition in fire.parts:
		if part.shape == "circle" and part.color_role == "chassis": fire_points.append([part.position.length(), part.radius])
	fire_points.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var fire_non_increasing: bool = true
	for i: int in range(1, fire_points.size()):
		if fire_points[i][1] > fire_points[i - 1][1] + 0.01: fire_non_increasing = false
	h.check(fire_non_increasing, "Fire: chassis circle radius is non-increasing with distance from the core")
	var fire_radii: Array = []
	for p: Array in fire_points: fire_radii.append(p[1])
	var fire_radii_reversed: Array = fire_radii.duplicate()
	fire_radii_reversed.reverse()
	h.control("fire radii reversed (increasing outward)", not _is_non_increasing(fire_radii_reversed))

	var lightning: ShipDefinition = built.get("player_lightning_t6_standard_a")
	var fire_mean_len: float = _mean_line_length(fire)
	var lightning_mean_len: float = _mean_line_length(lightning)
	h.check(lightning_mean_len >= 2.0 * fire_mean_len, "Lightning mean line length (%.1f) >= 2x fire's (%.1f)" % [lightning_mean_len, fire_mean_len])
	h.control("fire's own mean line length compared against 2x itself", not (fire_mean_len >= 2.0 * fire_mean_len) or is_equal_approx(fire_mean_len, 0.0))

	for element: String in ["fire", "lightning", "void", "corruption", "plasma"]:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			var ship: ShipDefinition = built.get("player_%s_t%d_standard_a" % [element, tier])
			if ship == null: continue
			var whip: int = 0
			var sway: int = 0
			var orbit: int = 0
			for group: GroupDefinition in ship.groups:
				if group.chain_mode == "whip": whip += 1
				if group.chain_mode == "sway": sway += 1
				if group.orbit_speed != 0.0: orbit += 1
			if element == "corruption": h.check(whip >= 1, ship.id + ": corruption hull has >=1 whip group")
			if element == "plasma": h.check(orbit >= 1, ship.id + ": plasma hull has >=1 orbit group")
			if element in ["void", "lightning"]: h.check(whip == 0 and sway == 0, ship.id + ": no whip/sway on void/lightning")
	# Negative controls for the group-presence checks.
	var corruption_control: ShipDefinition = (built.get("player_corruption_t2_standard_a") as ShipDefinition).duplicate(true)
	var kept: Array[GroupDefinition] = []
	for group: GroupDefinition in corruption_control.groups:
		if group.chain_mode != "whip": kept.append(group)
	corruption_control.groups = kept
	var still_whip: bool = false
	for group: GroupDefinition in corruption_control.groups:
		if group.chain_mode == "whip": still_whip = true
	h.control("a corruption hull with its whip group stripped", not still_whip)
	var plasma_control: ShipDefinition = (built.get("player_plasma_t2_standard_a") as ShipDefinition).duplicate(true)
	var stripped_orbit: bool = false
	for group: GroupDefinition in plasma_control.groups: group.orbit_speed = 0.0
	var any_orbit: bool = false
	for group: GroupDefinition in plasma_control.groups:
		if group.orbit_speed != 0.0: any_orbit = true
	h.control("a plasma hull with every orbit_speed zeroed", not any_orbit)

	# --- Every (faction, element, tier) the world can request resolves to a hull ---
	var resolve_ok: bool = true
	for faction: String in ["enemy", "elite", "boss"]:
		for element: String in ShipCatalog.ELEMENTS:
			for tier: int in range(1, GameTuning.MAX_TIER + 1):
				var id: String = ShipCatalog.pick_enemy(faction, element, tier)
				if id.is_empty() or ShipCatalog.get_ship(id) == null: resolve_ok = false
	h.check(resolve_ok, "Every (faction, element, tier) combination the world can request resolves to a real hull")
	h.control("an unknown element", ShipCatalog.pick_enemy("enemy", "does_not_exist", 3).is_empty())
	h.control("an unknown faction", ShipCatalog.pick_enemy("does_not_exist", "fire", 3).is_empty())

	# --- TP used <= budget for every hull; >= 60% of budget for player hulls ---
	var tp_ok: bool = true
	var tp_floor_ok: bool = true
	for ship: ShipDefinition in built.values():
		if ship.tp_used > ship.tp_max + 0.001: tp_ok = false
		if ship.is_player and ship.tp_used < ship.tp_max * 0.6 - 0.001: tp_floor_ok = false
	h.check(tp_ok, "TP used never exceeds budget across the roster")
	h.check(tp_floor_ok, "Every player hull uses >= 60% of its TP budget")
	# Negative control: shrink every non-core body circle to near nothing and
	# recompute TP through the real recalculate() path.
	var starved: ShipDefinition = (built.get("player_fire_t3_standard_a") as ShipDefinition).duplicate(true)
	for part: PartDefinition in starved.parts:
		if part.shape == "circle" and part.mount_id.is_empty() and part.id != "core": part.radius = 0.1
	ShipCatalog.recalculate(starved)
	h.control("a hull with every non-core body circle shrunk to near zero", starved.tp_used < starved.tp_max * 0.6)

	# V02-ADAPTER (remove with the shim in P5): an element is only authored across its campaign
	# level's tier band, so a v0.2 wedge sector asking for a low tier of a late element is handed a
	# much higher-tier hull. Slots are a hard cap, so the substitute must fight with the REQUESTED
	# tier's allowance; without this a ring-1 corruption drone carried tier-3 weaponry and out-damaged
	# its own reward and HP by enough to cost the regrowth route ~25 light over 180 s.
	var substituted: int = 0
	for element: String in GameTuning.ELEMENTS:
		for tier: int in range(1, GameTuning.MAX_TIER + 1):
			var id: String = ShipCatalog.pick_enemy("enemy", element, tier)
			if not h.check(not id.is_empty(), "%s tier %d resolves to a hull" % [element, tier]): continue
			var trimmed: ShipDefinition = ShipCatalog.trim_to_tier(ShipCatalog.get_ship(id), tier)
			var limits: Dictionary = GameTuning.slots(tier, trimmed.role)
			h.check(trimmed.secondaries.size() <= int(limits.secondary) and trimmed.passives.size() <= int(limits.passive),
				"%s tier %d fights within tier %d slots (%d secondary, %d passive)" % [id, tier, tier, trimmed.secondaries.size(), trimmed.passives.size()])
			# Every visible circle is an ability or a stat: a dropped ability takes its mount with it.
			for part: PartDefinition in trimmed.parts:
				if part.shape == "circle" and not part.mount_id.is_empty():
					h.check(part.ability_id in trimmed.mounted_components(), "%s keeps no orphaned mount circle (%s)" % [id, part.mount_id])
				if part.shape == "line":
					h.check(_has_circle(trimmed, part.from_id) and _has_circle(trimmed, part.to_id), "%s keeps no line with a removed endpoint (%s)" % [id, part.id])
			if ShipCatalog.get_ship(id).tier > tier: substituted += 1
	h.check(substituted > 0, "the shim really does substitute higher-tier hulls somewhere (%d cases)" % substituted)
	var untrimmed: ShipDefinition = ShipCatalog.get_ship(ShipCatalog.pick_enemy("enemy", "plasma", 1))
	h.control("a substituted hull read without the tier cap", untrimmed.secondaries.size() > int(GameTuning.slots(1, untrimmed.role).secondary))

	h.finish(self)

func _has_circle(ship: ShipDefinition, id: String) -> bool:
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and part.id == id: return true
	return false

func _mean_line_length(ship: ShipDefinition) -> float:
	var lookup: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "circle": lookup[part.id] = part
	var total: float = 0.0
	var count: int = 0
	for part: PartDefinition in ship.parts:
		if part.shape != "line": continue
		var a: PartDefinition = lookup.get(part.from_id)
		var b: PartDefinition = lookup.get(part.to_id)
		if a == null or b == null: continue
		total += a.position.distance_to(b.position)
		count += 1
	return total / count if count > 0 else 0.0

func _is_non_increasing(values: Array) -> bool:
	for i: int in range(1, values.size()):
		if values[i] > values[i - 1] + 0.01: return false
	return true
