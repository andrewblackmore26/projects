class_name GameTuning
extends RefCounted
## All progression/world starting values are owned here for reproducible tuning.
const MAX_TIER: int = 6
const START_LIGHT: float = 40.0
# Index i is the light needed to evolve from tier (i+1) to tier (i+2): T1->T2 .. T5->T6.
const THRESHOLDS: Array[float] = [100.0, 250.0, 500.0, 900.0, 1500.0]
const TERMINAL_CAPACITY: float = 2300.0
const REGRESSION_RATIO: float = 0.85
const RESHAPE_SECONDS: float = 0.8
const REGRESSION_GRACE: float = 1.0
## v0.2's three-element demo start, retained only for legacy-save decoding
## (SaveService's schema-3 migration path). Live campaign progression uses
## GameTuning.ELEMENTS[0] (lightning) as the sole starting element (spec §8).
const START_ELEMENTS: Array[String] = ["fire", "corruption", "plasma"]
## P5: reordered to the campaign reveal order (spec §8 table): lightning(L1)
## -> fire(L2) -> corruption(L3) -> void(L4) -> plasma(L5). This is also the
## evolution tie-break order (evolution_rules.gd ROOT_ORDER, which reads this
## constant directly) and the level-reveal prefix (LEVEL_ELEMENTS below).
const ELEMENTS: Array[String] = ["lightning", "fire", "corruption", "void", "plasma"]
## Campaign reveal: level L's node pool may use ELEMENTS[0..L-1] (spec §8 table).
const LEVEL_ELEMENTS: Array[String] = ELEMENTS
const TP_BUDGETS: Array[float] = [6.0, 10.0, 15.0, 21.0, 28.0, 36.0]

## --- v0.3 world (spec §11) ---------------------------------------------
## Bounded-disc level radii (approved preamble default): L1..L5.
const LEVEL_RADIUS: Array[int] = [6, 8, 9, 11, 12]
## Spec §11: "roughly one enemy tier per 2 rings."
const RING_TIER_DIVISOR: int = 2
## Membrane construction (campaign_state.gd): probability an edge that is
## not a structural parent link still opens. Measured in world_generation_test
## to land the <4-exit share >=25% and the dead-end share inside 3%-25%
## (see tasks/todo.md P5 review for the measured numbers).
const EDGE_OPEN_PROBABILITY: float = 0.30
## Node archetypes rolled by ring band (spec §11: "transit, skirmish, dense,
## elite lair, boss"). One table, ring bands widen with level depth; band
## index = ring / RING_BAND_WIDTH, clamped to the last row. Boss is never
## rolled from this table -- it is a fixed archetype at the level's boss cell.
const RING_BAND_WIDTH: int = 3
const ARCHETYPE_TABLE: Array[Dictionary] = [
	{"transit": 0.55, "skirmish": 0.30, "dense": 0.15, "elite_lair": 0.00},
	{"transit": 0.35, "skirmish": 0.35, "dense": 0.25, "elite_lair": 0.05},
	{"transit": 0.22, "skirmish": 0.30, "dense": 0.33, "elite_lair": 0.15},
	{"transit": 0.12, "skirmish": 0.26, "dense": 0.37, "elite_lair": 0.25},
]
const ARCHETYPE_ENEMY_BASE: Dictionary = {"transit": 1, "skirmish": 2, "dense": 4, "elite_lair": 1, "boss": 1}
const ARCHETYPE_ELITE_BASE: Dictionary = {"transit": 0.0, "skirmish": 0.06, "dense": 0.16, "elite_lair": 0.65, "boss": 0.0}
const ARCHETYPE_POOL_BASE: Dictionary = {"transit": 60.0, "skirmish": 120.0, "dense": 220.0, "elite_lair": 180.0, "boss": 400.0}
## Spec §7: "finite light pool that refills slowly (tune: 20% per minute)."
const NODE_POOL_REFILL_PER_MINUTE: float = 0.20
## Spec §7: "Enemies respawn on a cooldown; the pool does not follow." Tune.
const ENEMY_RESPAWN_COOLDOWN: float = 45.0
## Element is rolled per NxN block of cells so territories read on the
## minimap (spec §8 acceptance, M5).
const ELEMENT_BLOCK_SIZE: int = 2
## Chance a block rolls the level's own newest element instead of an older
## revealed one, so a level "feels like its element" (spec §8).
const NEW_ELEMENT_WEIGHT: float = 0.55
## Kept equal to the old 1792x1120 rounded-rect arena's centre and area so enemy
## density and the benchmark stay comparable (see docs/LIGHTSHIP_GAME_SPEC_V3.md preamble).
const ARENA_CENTER: Vector2 = Vector2(896, 560)
const ARENA_RADIUS: float = 800.0
const ARENA_MARGIN: float = 80.0 # Dead space beyond the rim; nothing playable exists out there.
const SHIELD_DURATION: float = 2.0
const SHIELD_COOLDOWN: float = 8.0

## --- Pace (spec §7, approved preamble) -----------------------------------
## Light decay: 0.4% of the CURRENT TIER'S MAXIMUM per second, suppressed for
## 3 s after any kill or absorb. Floors at DECAY_FLOOR (approved preamble:
## "can never kill" -- the floor sits well above the tier-1 death threshold
## of 0) and CAN regress a tier, which is the cost of camping.
const DECAY_RATE_PER_SECOND: float = 0.004
const DECAY_SUPPRESSION_SECONDS: float = 3.0
const DECAY_FLOOR: float = 10.0
## Kill combo: x1.0 -> x2.5 at 10 consecutive kills. The 2.5s window resets
## on every kill; once it expires the count drains 1 per 0.25s rather than
## resetting hard (approved preamble).
const COMBO_WINDOW_SECONDS: float = 2.5
const COMBO_MAX_COUNT: int = 10
const COMBO_MULTIPLIER_MAX: float = 2.5
const COMBO_DRAIN_INTERVAL_SECONDS: float = 0.25
## Pickup sizes (spec §10): three sizes worth 1/5/20. Enemy-dropped light is
## worth 3x a floating pickup of the same SIZE (draw radius must come from
## size, not value, or a 3x drop looks like a bigger pickup than it is).
const PICKUP_SIZES: Array[int] = [1, 5, 20]
const ENEMY_DROP_MULTIPLIER: float = 3.0
## Frictionless death (spec §7.4/§24): 1.2s non-pausing card, dismissed on a
## FRESH press only, after a short guard so a held button cannot skip a card
## the player never saw (M1 acceptance: "death-to-flying-again under 2s").
const DEATH_CARD_SECONDS: float = 1.2
const DEATH_INPUT_GUARD_SECONDS: float = 0.35

static func capacity(tier: int, _max_tier: int = MAX_TIER) -> float:
	# A demo cap prevents further evolution; it does not grant terminal survivability.
	return TERMINAL_CAPACITY if tier >= MAX_TIER else THRESHOLDS[clampi(tier - 1, 0, THRESHOLDS.size() - 1)]

static func regression_floor(tier: int) -> float:
	return 0.0 if tier <= 1 else THRESHOLDS[clampi(tier - 2, 0, THRESHOLDS.size() - 1)] * REGRESSION_RATIO

## Spec §9: T1 1/0/0, T2 1/1/0, T3 1/1/0, T4 1/2/1, T5 1/2/1, T6 1/3/2.
## Compact takes -1 secondary (floor 1, once a secondary exists at all);
## Heavy takes +1 on top of the base count.
static func slots(tier: int, role: String) -> Dictionary:
	var base_secondary: int = [0, 1, 1, 2, 2, 3][clampi(tier - 1, 0, 5)]
	var base_passive: int = [0, 0, 0, 1, 1, 2][clampi(tier - 1, 0, 5)]
	var secondary: int = base_secondary
	if tier > 1:
		secondary = maxi(1, base_secondary - 1) if role == "compact" else base_secondary + (1 if role == "heavy" else 0)
	return {"primary": 1, "secondary": secondary, "passive": base_passive}
