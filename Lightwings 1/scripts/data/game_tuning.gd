class_name GameTuning
extends RefCounted
## All progression/world starting values are owned here for reproducible tuning.
const MAX_TIER: int = 5
const START_LIGHT: float = 40.0
const THRESHOLDS: Array[float] = [100.0, 250.0, 500.0, 900.0]
const TERMINAL_CAPACITY: float = 1500.0
const REGRESSION_RATIO: float = 0.85
const RESHAPE_SECONDS: float = 0.8
const REGRESSION_GRACE: float = 1.0
const START_ELEMENTS: Array[String] = ["fire", "corruption", "plasma"]
const ELEMENTS: Array[String] = ["fire", "corruption", "plasma", "lightning", "void"]
const CORE_DISTANCES: Array[int] = [8, 14, 20, 26, 32]
const WAYPOINT_INTERVAL: int = 6
const TP_BUDGETS: Array[float] = [6.0, 10.0, 15.0, 21.0, 28.0]
const ARENA_SIZE: Vector2 = Vector2(1792, 1120)
const ARENA_MARGIN: float = 80.0
const SHIELD_DURATION: float = 2.0
const SHIELD_COOLDOWN: float = 8.0

static func capacity(tier: int, _max_tier: int = MAX_TIER) -> float:
	# A demo cap prevents further evolution; it does not grant T5 survivability.
	return TERMINAL_CAPACITY if tier >= MAX_TIER else THRESHOLDS[clampi(tier - 1, 0, 3)]

static func regression_floor(tier: int) -> float:
	return 0.0 if tier <= 1 else THRESHOLDS[clampi(tier - 2, 0, 3)] * REGRESSION_RATIO

static func slots(tier: int, role: String) -> Dictionary:
	var secondary: int = 0 if tier == 1 else (1 if tier <= 3 else 2)
	if tier > 1:
		secondary = maxi(1, secondary - 1) if role == "compact" else secondary + (1 if role == "heavy" else 0)
	return {"primary": 1, "secondary": secondary, "passive": 1 if tier >= 4 else 0}
