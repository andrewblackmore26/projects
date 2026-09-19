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
