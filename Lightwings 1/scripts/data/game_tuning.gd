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
const START_ELEMENTS: Array[String] = ["fire", "corruption", "plasma"]
# NOTE (P2b-1): deliberately NOT reordered even though the campaign now
# introduces elements lightning(L1) -> fire(L2) -> corruption(L3) -> void(L4)
# -> plasma(L5). Reordering this changes the v0.2 wedge world's element
# assignment (campaign_state.gd _initial_element) and the evolution
# tie-break (evolution_rules.gd ROOT_ORDER). Deferred to P5.
const ELEMENTS: Array[String] = ["fire", "corruption", "plasma", "lightning", "void"]
const CORE_DISTANCES: Array[int] = [8, 14, 20, 26, 32]
const WAYPOINT_INTERVAL: int = 6
const TP_BUDGETS: Array[float] = [6.0, 10.0, 15.0, 21.0, 28.0, 36.0]
## Kept equal to the old 1792x1120 rounded-rect arena's centre and area so enemy
## density and the benchmark stay comparable (see docs/LIGHTSHIP_GAME_SPEC_V3.md preamble).
const ARENA_CENTER: Vector2 = Vector2(896, 560)
const ARENA_RADIUS: float = 800.0
const ARENA_MARGIN: float = 80.0 # Dead space beyond the rim; nothing playable exists out there.
const SHIELD_DURATION: float = 2.0
const SHIELD_COOLDOWN: float = 8.0

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
