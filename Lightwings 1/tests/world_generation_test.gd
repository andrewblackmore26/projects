extends SceneTree
## P5a: the v0.3 world model (spec §7, §8, §11). Four deliberate mutants
## (subclasses of CampaignState, each overriding exactly one hash seam) prove
## every instrument below can actually fail.
##
## Performance note: `exits_of`/`archetype_of`/`element_of` are pure but not
## cheap (several hash() calls each). `_scan_level` below calls each exactly
## ONCE per coordinate and caches the result, then every metric is derived
## from that one cached pass - the first version of this test called
## `exits_of` from five separate places per coordinate and timed out the
## suite's 900s budget on the mutant re-runs; measure the cost of your own
## instrument, not just the thing it measures.
const Harness = preload("res://tests/support/harness.gd")
const Campaign = preload("res://scripts/world/campaign_state.gd")

const FULL_SCAN_SEEDS: int = 40
const CHEAP_SEEDS: int = 200
const MUTANT_SEEDS: int = 20

## A mutant is EXPECTED to fail some of these checks; that must not print an
## engine "ERROR:" line (test.ps1 greps the log and fails the suite on any
## ERROR:, even from a deliberately-sabotaged scratch run - see lessons.md
## "a probe must not see its own subject"). Same `.check`/`.failures`
## surface as Harness, but silent.
class SilentProbe:
	var failures: Array[String] = []
	func check(ok: bool, message: String) -> bool:
		if not ok: failures.append(message)
		return ok

## --- Deliberate mutants (see the P5a task brief) -------------------------

class NoParentMutant extends CampaignState:
	# Removes the structural parent term: every non-origin cell "parents"
	# onto the origin regardless of adjacency, so most cells lose their
	# guaranteed connection. Connectivity should fail.
	func _parent_of(_coord: Vector2i) -> Vector2i:
		return Vector2i.ZERO

class OrderedPairMutant extends CampaignState:
	# Hashes the ORDERED pair instead of a canonical/sorted one, so A->B and
	# B->A can disagree. Exit symmetry should fail.
	func _pair_hash01(a: Vector2i, b: Vector2i) -> float:
		var h: int = absi(hash("%d:%d:%d:%d:%d:edge" % [level_seed(), a.x, a.y, b.x, b.y]))
		return float(h % 100000) / 100000.0

class OffByOneBossMutant extends CampaignState:
	# Boss biased to ring R-1: the perimeter/corner/axis check should fail.
	func boss_coord() -> Vector2i:
		return Vector2i(level_radius() - 1, 0)

class IgnoredSeedMutant extends CampaignState:
	# level_seed ignores epoch and level entirely: dying (or travelling)
	# should still change the layout, but this mutant never does.
	func level_seed() -> int:
		return hash("ignored:%d" % world_seed)

## --- One cached pass per (seed, level) ------------------------------------

static func _all_in_bounds(campaign: CampaignState) -> Array[Vector2i]:
	var r: int = campaign.level_radius()
	var result: Array[Vector2i] = []
	for x: int in range(-r, r + 1):
		for y: int in range(-r, r + 1):
			var coord: Vector2i = Vector2i(x, y)
			if campaign.in_bounds(coord): result.append(coord)
	return result

## Computes exits/archetype/tier/element for every in-bounds coord exactly
## once, plus BFS reachability, all from that single cached exits map.
static func _scan_level(campaign: CampaignState) -> Dictionary:
	var coords: Array[Vector2i] = _all_in_bounds(campaign)
	var exits: Dictionary = {}
	var archetypes: Dictionary = {}
	var elements: Dictionary = {}
	var tiers: Dictionary = {}
	for coord: Vector2i in coords:
		exits[coord] = campaign.exits_of(coord)
		archetypes[coord] = campaign.archetype_of(coord)
		elements[coord] = campaign.element_of(coord)
		tiers[coord] = campaign.tier_of(coord)
	var reached: Dictionary = {Vector2i.ZERO: 0}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for dir: Vector2i in exits.get(current, []):
			var neighbor: Vector2i = current + dir
			if not reached.has(neighbor) and exits.has(neighbor):
				reached[neighbor] = int(reached[current]) + 1
				queue.append(neighbor)
	return {"coords": coords, "exits": exits, "archetypes": archetypes, "elements": elements, "tiers": tiers, "reached": reached, "boss": campaign.boss_coord()}

static func _fingerprint(campaign: CampaignState) -> String:
	var pieces: PackedStringArray = []
	var r: int = campaign.level_radius()
	for coord: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(r, 0), campaign.boss_coord()]:
		if not campaign.in_bounds(coord): continue
		pieces.append("%s:%s:%s:%s" % [Campaign.coord_key(coord), campaign.archetype_of(coord), campaign.element_of(coord), str(campaign.exits_of(coord))])
	return "|".join(pieces)

## --- The full measurement pass -------------------------------------------

func _run_full_scan(make_campaign: Callable, h: Variant, label: String, seed_count: int, purity_sample: int) -> void:
	var exit_counts: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	var dead_ends: int = 0
	var total_nodes: int = 0
	var symmetry_breaks: int = 0
	var symmetry_checked: int = 0
	var connectivity_failures: int = 0
	var boss_ring_failures: int = 0
	var boss_positions: Dictionary = {}
	var boss_distances: Array[int] = []
	var archetype_totals_by_band: Dictionary = {}
	var tier_ok: bool = true
	var enemy_count_rising_ok: bool = true
	var element_pool_ok: bool = true
	var pure_ok: bool = true

	for seed_index: int in range(seed_count):
		for level: int in range(1, 6):
			var campaign: CampaignState = make_campaign.call()
			campaign.world_seed = seed_index * 104729 + 17
			campaign.level = level
			var scan: Dictionary = _scan_level(campaign)
			var coords: Array[Vector2i] = scan.coords
			var exits: Dictionary = scan.exits
			var reached: Dictionary = scan.reached
			var boss: Vector2i = scan.boss
			total_nodes += coords.size()

			# Determinism + purity, on a small sample (this is where the cost was).
			var twin: CampaignState = make_campaign.call()
			twin.world_seed = campaign.world_seed
			twin.level = level
			var before: Dictionary = campaign.to_dict()
			for sample_index: int in range(mini(purity_sample, coords.size())):
				var coord: Vector2i = coords[(sample_index * 37) % coords.size()]
				if campaign.sector_at(coord) != twin.sector_at(coord): pure_ok = false
				if campaign.sector_at(coord) != campaign.sector_at(coord): pure_ok = false
			if campaign.to_dict() != before: pure_ok = false

			# Exits + symmetry + dead ends, from the cached map.
			for coord: Vector2i in coords:
				var here: Array = exits[coord]
				exit_counts[here.size()] = int(exit_counts[here.size()]) + 1
				if here.size() <= 1: dead_ends += 1
				for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var neighbor: Vector2i = coord + dir
					if not exits.has(neighbor): continue
					symmetry_checked += 1
					var forward_open: bool = dir in here
					var backward_open: bool = (-dir) in (exits[neighbor] as Array)
					if forward_open != backward_open: symmetry_breaks += 1

			for coord: Vector2i in coords:
				if not reached.has(coord): connectivity_failures += 1
			if reached.has(boss): boss_distances.append(int(reached[boss]))
			else: connectivity_failures += 1

			var r: int = campaign.level_radius()
			var ax: int = absi(boss.x)
			var ay: int = absi(boss.y)
			var on_ring: bool = maxi(ax, ay) == r
			var is_corner: bool = ax == r and ay == r
			var free: int = ay if ax == r else ax
			if not on_ring or is_corner or free <= 1: boss_ring_failures += 1
			boss_positions[Campaign.coord_key(boss)] = true

			var pool: Array = Array(GameTuning.ELEMENTS).slice(0, level)
			var previous_count: int = -1
			var previous_ring: int = -1
			for coord: Vector2i in coords:
				var band: int = clampi(Campaign.ring(coord) / GameTuning.RING_BAND_WIDTH, 0, GameTuning.ARCHETYPE_TABLE.size() - 1)
				var key: String = "%d:%d" % [level, band]
				var archetype: String = scan.archetypes[coord]
				if archetype != "boss":
					var bucket: Dictionary = archetype_totals_by_band.get(key, {"transit": 0, "skirmish": 0, "dense": 0, "elite_lair": 0, "total": 0})
					bucket[archetype] = int(bucket[archetype]) + 1
					bucket.total = int(bucket.total) + 1
					archetype_totals_by_band[key] = bucket
				var expected_tier: int = clampi(1 + Campaign.ring(coord) / GameTuning.RING_TIER_DIVISOR, 1, GameTuning.MAX_TIER)
				if int(scan.tiers[coord]) != expected_tier: tier_ok = false
				var ring_now: int = Campaign.ring(coord)
				if ring_now != previous_ring:
					if previous_ring >= 0 and ring_now > previous_ring and campaign.enemy_count_for(coord) < previous_count - 4: enemy_count_rising_ok = false
					previous_count = campaign.enemy_count_for(coord)
					previous_ring = ring_now
				if str(scan.elements[coord]) not in pool: element_pool_ok = false

	h.check(pure_ok, "%s: descriptors are deterministic, reading never mutates, and repeated reads agree" % label)
	h.check(symmetry_checked > 0 and symmetry_breaks == 0, "%s: every exit is reciprocal (%d/%d mismatches)" % [label, symmetry_breaks, symmetry_checked])
	h.check(connectivity_failures == 0, "%s: BFS from the origin reaches every in-bounds node and the boss (%d unreachable)" % [label, connectivity_failures])
	h.check(boss_ring_failures == 0, "%s: the boss is always on the perimeter ring, never a corner or axis-adjacent (%d failures)" % [label, boss_ring_failures])
	h.check(boss_positions.size() >= mini(12, seed_count), "%s: boss position varies across seeds (%d distinct positions)" % [label, boss_positions.size()])
	var below_four: int = int(exit_counts[0]) + int(exit_counts[1]) + int(exit_counts[2]) + int(exit_counts[3])
	var below_four_share: float = float(below_four) / float(maxi(1, total_nodes))
	var dead_end_share: float = float(dead_ends) / float(maxi(1, total_nodes))
	h.check(below_four_share >= 0.25, "%s: >=25%% of nodes have fewer than 4 exits (measured %.3f)" % [label, below_four_share])
	h.check(dead_end_share >= 0.03 and dead_end_share <= 0.25, "%s: dead-end share is between 3%% and 25%% (measured %.3f)" % [label, dead_end_share])
	h.check(tier_ok, "%s: tier == 1 + ring/2, clamped to MAX_TIER, on every sampled node" % label)
	h.check(enemy_count_rising_ok, "%s: enemy count does not fall sharply as ring rises" % label)
	h.check(element_pool_ok, "%s: every rolled element stays inside the level's revealed prefix" % label)
	boss_distances.sort()
	if not boss_distances.is_empty():
		var median: int = boss_distances[boss_distances.size() / 2]
		var maximum: int = boss_distances[boss_distances.size() - 1]
		print("%s: BFS distance to boss median=%d max=%d (n=%d)" % [label, median, maximum, boss_distances.size()])
	print("%s: exit-count histogram %s, dead-end share %.3f, <4-exit share %.3f, total nodes %d" % [label, str(exit_counts), dead_end_share, below_four_share, total_nodes])
	var archetype_ok: bool = true
	var elite_lair_monotonic: bool = true
	for level: int in range(1, 6):
		var previous_share: float = -1.0
		for band: int in range(GameTuning.ARCHETYPE_TABLE.size()):
			var key: String = "%d:%d" % [level, band]
			if not archetype_totals_by_band.has(key): continue
			var bucket: Dictionary = archetype_totals_by_band[key]
			var total: int = int(bucket.total)
			if total == 0: continue
			var table: Dictionary = GameTuning.ARCHETYPE_TABLE[band]
			for kind: String in ["transit", "skirmish", "dense", "elite_lair"]:
				var measured: float = float(bucket[kind]) / float(total)
				if absf(measured - float(table[kind])) > 0.05: archetype_ok = false
			var elite_share: float = float(bucket.elite_lair) / float(total)
			if previous_share >= 0.0 and elite_share < previous_share - 0.001: elite_lair_monotonic = false
			previous_share = elite_share
	h.check(archetype_ok, "%s: archetype shares per ring band are within +/-0.05 of the table" % label)
	h.check(elite_lair_monotonic, "%s: elite-lair share is non-decreasing with ring" % label)

func _fresh_seed_identical_count(make_campaign: Callable, seed_count: int) -> int:
	var identical: int = 0
	for seed_index: int in range(seed_count):
		var campaign: CampaignState = make_campaign.call()
		campaign.world_seed = seed_index * 104729 + 17
		var before: String = _fingerprint(campaign)
		campaign.on_death()
		var after: String = _fingerprint(campaign)
		if before == after: identical += 1
	return identical

func _initialize() -> void:
	var h: Harness = Harness.new("world_generation")
	_run_full_scan(func() -> CampaignState: return Campaign.new(), h, "real world", FULL_SCAN_SEEDS, 6)
	var real_identical: int = _fresh_seed_identical_count(func() -> CampaignState: return Campaign.new(), CHEAP_SEEDS)
	h.check(real_identical == 0, "Every seed's layout fingerprint differs after death (100%% of %d seeds; %d unchanged)" % [CHEAP_SEEDS, real_identical])

	# --- Deliberate mutants: each must be caught by exactly the check it breaks ---
	var no_parent_h: SilentProbe = SilentProbe.new()
	_run_full_scan(func() -> CampaignState: return NoParentMutant.new(), no_parent_h, "no-parent mutant", MUTANT_SEEDS, 0)
	h.control("no parent term (connectivity)", not no_parent_h.failures.filter(func(m: String) -> bool: return m.contains("BFS from the origin reaches")).is_empty())

	var ordered_pair_h: SilentProbe = SilentProbe.new()
	_run_full_scan(func() -> CampaignState: return OrderedPairMutant.new(), ordered_pair_h, "ordered-pair mutant", MUTANT_SEEDS, 0)
	h.control("ordered-pair edge hash (symmetry)", not ordered_pair_h.failures.filter(func(m: String) -> bool: return m.contains("every exit is reciprocal")).is_empty())

	var off_by_one_h: SilentProbe = SilentProbe.new()
	_run_full_scan(func() -> CampaignState: return OffByOneBossMutant.new(), off_by_one_h, "off-by-one boss mutant", MUTANT_SEEDS, 0)
	h.control("boss on ring R-1 (perimeter)", not off_by_one_h.failures.filter(func(m: String) -> bool: return m.contains("boss is always on the perimeter")).is_empty())

	var identical: int = _fresh_seed_identical_count(func() -> CampaignState: return IgnoredSeedMutant.new(), MUTANT_SEEDS)
	h.control("level_seed ignoring epoch/level (fresh-seed-per-life)", identical > 0)

	h.finish(self)
