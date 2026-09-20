class_name EvolutionRules
extends RefCounted

const Tuning = preload("res://scripts/data/game_tuning.gd")
const ROOT_ORDER: Array[String] = Tuning.ELEMENTS
const THRESHOLDS: Array[float] = Tuning.THRESHOLDS

static func threshold(tier: int) -> int:
	return -1 if tier < 1 or tier >= Tuning.MAX_TIER else int(THRESHOLDS[tier - 1])

## previous accepts old string argument during migration, but only hull-ID arrays
## participate in repeat avoidance. Seeded selection never touches global RNG.
static func offers(current: String, tier: int, absorbed: Dictionary, unlocked: Array, previous: Variant = [], seed_value: int = 0) -> Array[String]:
	var result: Array[String] = []
	if tier < 1 or tier >= Tuning.MAX_TIER: return result
	var candidates: Array[String] = []
	for element: String in ROOT_ORDER:
		if element in unlocked: candidates.append(element)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var first: float = maxf(0.0, float(absorbed.get(a, 0)))
		var second: float = maxf(0.0, float(absorbed.get(b, 0)))
		return first > second if first != second else ROOT_ORDER.find(a) < ROOT_ORDER.find(b)
	)
	if candidates.is_empty(): return result
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	if tier == 1:
		for element: String in candidates.slice(0, 3):
			var choices: Array[String] = _roster_ids(element, tier + 1)
			if not choices.is_empty(): result.append(choices[rng.randi_range(0, choices.size() - 1)])
		# Fill rule (spec §8): "With fewer than three unlocked, fill from the
		# current element's roster." A roster carries 4 hulls per element per
		# tier, so it can always supply the gap without repeating an id
		# already offered. If the current element has no roster at this tier
		# (the neutral T1 seed has none), fall back to the highest-ranked
		# unlocked element, then cycle through the remaining ranks so three
		# DISTINCT hulls are always produced whenever any roster can supply
		# them - which, with a real element unlocked, is always.
		if result.size() < 3:
			var fill_order: Array[String] = []
			if not _roster_ids(current, tier + 1).is_empty(): fill_order.append(current)
			for element: String in candidates:
				if element not in fill_order: fill_order.append(element)
			var fill_cursor: int = 0
			var guard: int = 0
			while result.size() < 3 and not fill_order.is_empty() and guard < 64:
				guard += 1
				var element: String = fill_order[fill_cursor % fill_order.size()]
				fill_cursor += 1
				var unused: Array[String] = []
				for id: String in _roster_ids(element, tier + 1):
					if id not in result: unused.append(id)
				if not unused.is_empty(): result.append(unused[rng.randi_range(0, unused.size() - 1)])
	else:
		var element: String = current if current in candidates else candidates[0]
		var choices: Array[String] = _roster_ids(element, tier + 1)
		_shuffle(choices, rng)
		for id: String in choices.slice(0, 3): result.append(id)
		var total: float = 0.0
		for amount: Variant in absorbed.values(): total += maxf(0.0, float(amount))
		for candidate: String in candidates:
			if candidate != element and total > 0.0 and float(absorbed.get(candidate, 0)) / total > 0.4:
				var alternative: Array[String] = _roster_ids(candidate, tier + 1)
				if not alternative.is_empty() and not result.is_empty(): result[result.size() - 1] = alternative[rng.randi_range(0, alternative.size() - 1)]
				break
	if previous is Array and _same_set(result, previous):
		# Change one offer within its element so diet semantics stay unchanged.
		for index: int in range(result.size()):
			var ship: ShipDefinition = ShipCatalog.get_ship(result[index])
			if ship == null: continue
			for alternative: String in _roster_ids(ship.element, tier + 1):
				if alternative not in result:
					result[index] = alternative
					return result
	return result

static func _roster_ids(element: String, tier: int) -> Array[String]:
	var result: Array[String] = []
	for ship: Variant in ShipCatalog.roster(element, tier):
		var id: String = ship.id if ship is ShipDefinition else str(ship)
		if not id.is_empty() and id not in result: result.append(id)
	return result

## Spec §4, Dev mode: "all hulls available at every evolution". Every next-tier hull of every
## element, in a stable order (element order, then the roster's own order) so the tab strip and its
## tests see the same list every time. Campaign and demo never call this - they use `offers` above,
## which is the real three-card rule.
static func all_offers(tier: int) -> Array[String]:
	var result: Array[String] = []
	if tier < 1 or tier >= Tuning.MAX_TIER: return result
	for element: String in ROOT_ORDER:
		for id: String in _roster_ids(element, tier + 1):
			if id not in result: result.append(id)
	return result

static func _shuffle(values: Array[String], rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var original: String = values[index]
		values[index] = values[other]
		values[other] = original

static func _same_set(first: Array[String], second: Array) -> bool:
	if first.size() != second.size(): return false
	for id: String in first:
		if id not in second: return false
	return true

## Legacy helper retained for decoding old fixtures only; combat no longer steals.
static func add_stolen(stolen: Array, _component: String) -> Array:
	return stolen.duplicate(true)
