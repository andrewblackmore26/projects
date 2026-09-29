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
## Modernization M13 (h): enemies per node before the ring term, which is ring / ENEMY_RING_DIVISOR.
## An elite lair's figure is its escort; the lair's elite comes on top. A boss's figure is its ADDS,
## split over the BOSS_ADD_WAVE_HP waves (the boss itself is not counted). Was 1/2/4/1/1 + ring/3.
const ARCHETYPE_ENEMY_BASE: Dictionary = {"transit": 3, "skirmish": 5, "dense": 9, "elite_lair": 3, "boss": 2}
const ENEMY_RING_DIVISOR: int = 2
const ARCHETYPE_ELITE_BASE: Dictionary = {"transit": 0.0, "skirmish": 0.06, "dense": 0.16, "elite_lair": 0.65, "boss": 0.0}
## M13 (h): doubled (was 60/120/220/180/400) so the denser waves have light to pay out.
const ARCHETYPE_POOL_BASE: Dictionary = {"transit": 120.0, "skirmish": 240.0, "dense": 440.0, "elite_lair": 360.0, "boss": 800.0}
## --- Waves (modernization M13). All (h) until the play census measures them. ------------------
## A node's enemies arrive in waves split by these fractions (cumulative boundaries, rounded).
const WAVE_SPLIT: Array[float] = [0.4, 0.3, 0.3]
## The next wave is released when at most this fraction of the previous wave is still alive (or
## queued), or WAVE_GAP_SECONDS after the previous release, whichever comes first.
const WAVE_ADVANCE_ALIVE_FRACTION: float = 1.0 / 3.0
const WAVE_GAP_SECONDS: float = 8.0
## Wave 1 lands this long after arrival (the sector swap happens at the warp commit; the wave clock
## is held until the arrival, see CombatWorld._update_waves).
const WAVE_FIRST_SECONDS: float = 0.2
## Every life starts in a fight: the origin's training wave of T1 drones.
const ORIGIN_TRAINING_COUNT: int = 3
const ORIGIN_TRAINING_DELAY_SECONDS: float = 1.0
## A boss node's add waves are released as the boss's core falls to these fractions of its HP.
const BOSS_ADD_WAVE_HP: Array[float] = [0.66, 0.33]
## Alive cap: WAVE_ALIVE_CAP_BASE + tier / 2, at most WAVE_ALIVE_CAP_MAX. Queued spawns count as alive.
const WAVE_ALIVE_CAP_BASE: int = 8
const WAVE_ALIVE_CAP_MAX: int = 12
## Rim spawns: telegraphed this long ahead, this far inside the rim, never within this many degrees
## of the arrival point (wave 1) or the player's bearing (later spawns), and a batch fans out at
## SPAWN_SPACING_DEG with SPAWN_STAGGER_SECONDS between landings.
const SPAWN_TELEGRAPH_SECONDS: float = 0.6
const SPAWN_RIM_INSET: float = 60.0
const SPAWN_CLEAR_DEGREES: float = 60.0
const SPAWN_SPACING_DEG: float = 16.0
const SPAWN_STAGGER_SECONDS: float = 0.08
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
## Kill combo: x1.0 -> x2.5 at 10 consecutive kills. The window resets
## on every kill; once it expires the count drains 1 per 0.25s rather than
## resetting hard (approved preamble). M13: 2.5 -> 3.0 s, and frozen while the
## warp is locked so chaining nodes keeps the combo.
const COMBO_WINDOW_SECONDS: float = 3.0
## M13 (h): light collected on a full bar is banked, up to this fraction of the NEXT tier's
## threshold, and paid into the bar on evolve.
const LIGHT_BANK_FRACTION: float = 0.25
const COMBO_MAX_COUNT: int = 10
const COMBO_MULTIPLIER_MAX: float = 2.5
const COMBO_DRAIN_INTERVAL_SECONDS: float = 0.25
## Pickup sizes (spec §10): three sizes worth 1/5/20. Enemy-dropped light is
## worth 3x a floating pickup of the same SIZE (draw radius must come from
## size, not value, or a 3x drop looks like a bigger pickup than it is).
const PICKUP_SIZES: Array[int] = [1, 5, 20]
const ENEMY_DROP_MULTIPLIER: float = 3.0
## Frictionless death: M12 replaced P7's 1.2 s card (DEATH_CARD_SECONDS, DEATH_INPUT_GUARD_SECONDS)
## with a death beat and a no-press reboot; its timings are RunController.DEATH_*.

## --- Feel: camera and movement (docs/LIGHTSHIP_CAMERA_MOVEMENT_SPEC.md) -------------------------
## Every number that spec gives, in the spec's own terms, in ONE flat table. Everything that moves is
## priced as a ratio of `player_top_speed` (spec §2), so retuning the game's pace is one value.
## Read through `feel(key)`, never the table: the dev console overrides values live (`tune <key> <v>`)
## so the §9 feel pass can be run without a rebuild. Overrides are never saved, and a test that sets
## one calls `reset_feel()` first (tasks/lessons.md: shared mutable state couples scenarios).
##
## A hull's `.tres` `speed` is an AUTHORING unit in which 240 is the base hull: every shipped
## standard hull, the seed included, authors 240 (ship_generator.gd `_base_stats`); Compact authors
## 300 (1.25x, the spec's ratio) and Heavy 200 (0.83x; the spec says 0.85). Runtime top speed is
## `player_top_speed * speed / AUTHORING_BASE_SPEED`, so retuning never needs a rebake.
## M7 measured the P11a value of 220 (ShipDefinition's default, which no shipped hull uses): it ran
## the standard hull at 1.09x, 502 px/s, and the seed crossed the node in 3.24 s against the 3.5 s
## the whole budget is anchored on.
const AUTHORING_BASE_SPEED: float = 240.0
const FEEL_DEFAULTS: Dictionary = {
	# §2. 1600 px node / 3.5 s crossing. The source's 560 assumed 1920x1080; this game is 1280x800.
	"player_top_speed": 460.0,
	# §3. t90 = time from rest to 90 % of top speed. One exponential approach with tau = t90/ln10
	# also gives reversal-to-90 % = ln20*tau: 0.208 s standard (spec 0.22), 0.17 s compact (spec 0.17).
	# Heavy is not in the spec: it mirrors the compact ratio the other way.
	"move.t90.standard": 0.16,
	"move.t90.compact": 0.1307,
	"move.t90.heavy": 0.196,
	"move.coast_stop_s": 0.40,      # input released at top speed -> below coast_stop_frac
	"move.coast_stop_frac": 0.05,
	"move.snap_frac": 0.02,         # coasting below this fraction of top speed snaps to rest
	"move.drift_deg": 18.0,         # velocity lags a 90 degree input step by this much...
	"move.drift_s": 0.15,           # ...this long after the step
	"rim.speed_scale": 0.55,        # once on first contact, then a cap while sliding. Never per tick
	# §4
	"dash.burst_s": 0.18,
	"dash.peak_ratio": 2.5,
	"dash.cooldown_s": 1.1,
	# §5
	"trail.len_top": 180.0,
	"trail.len_dash": 320.0,
	"trail.enemy_scale": 0.3,
	# Pickups fly at max(pull_min, pull_ratio x the player's top speed), so a ship at top speed can
	# never outrun its own light. 330 was the flat pull before M7, when top speed was 220.
	"pickup.pull_min": 330.0,
	"pickup.pull_ratio": 1.3,
	# §7, sim side. Control returns at the START of arrival. M9 turns each into a sim_q deadline
	# (x720, rounded): 144 / 43 / 216 / 144 q, which is 12 / 4 / 18 / 12 ticks at 60 Hz (break is
	# 43 q = 3.6 ticks, so its deadline lands on the 4th). Reduced motion replaces break + warp with
	# one 0.20 s cross-fade (was 0.25 s before M9).
	"warp.push_s": 0.20,
	"warp.break_s": 0.06,
	"warp.warp_s": 0.30,
	"warp.arrival_s": 0.20,
	"warp.reduced_s": 0.20,
	"warp.speed_ratio": 3.0,
	"warp.push_speed_scale": 0.4,
	# §2 and §8: top speed as a ratio of the player's, keyed by CombatAI.archetype_of. Chains and the
	# heavy elite are not in the spec's table: chains take 0.22, the heavy elite the elite row.
	# M8 replaced the hull-authored speed x 0.45 (x 0.85 for a boss): drone 108, elite 90, boss 187 px/s.
	"enemy_ratio.drone": 0.29,
	"enemy_ratio.sentry": 0.0,
	"enemy_ratio.chain": 0.22,
	"enemy_ratio.radial": 0.16,
	"enemy_ratio.irregular": 0.16,
	"enemy_ratio.heavy": 0.16,
	"enemy_ratio.boss": 0.11,
	# §8 "accelerate slowly and turn slowly": seconds to 90 % of their own top speed (one exponential
	# approach), and rad/s of the unicycle heading. Hypotheses the M8 disengage test holds them to.
	"enemy_t90.drone": 0.5,
	"enemy_t90.chain": 0.6,
	"enemy_t90.radial": 0.9,
	"enemy_t90.irregular": 0.9,
	"enemy_t90.heavy": 0.9,
	"enemy_t90.boss": 1.2,
	"enemy_turn.drone": 3.0,
	"enemy_turn.chain": 2.5,
	"enemy_turn.radial": 1.5,
	"enemy_turn.irregular": 1.5,
	"enemy_turn.heavy": 1.5,
	"enemy_turn.boss": 1.0,
	# A seeker's TOTAL angular rate, pursuit and weave together, rad/s at the enemy seeker's speed (a
	# faster seeker turns proportionally faster: one turn radius). M8 derived 3.0 from a sweep of
	# 1.2-6.0 (movement_feel_test `_seeker_hits`): the lowest rate that hits a ship charging it in a
	# straight line from 500 px 18 times in 20; 1.8 hit 14. The weave is a heading offset of
	# amp x sin(freq x t) the seeker steers for, so its amplitude does not depend on the tick rate.
	"seeker.turn_rate": 3.0,
	"seeker.weave_amp": 0.30,       # rad
	"seeker.weave_freq": 4.0,       # rad/s
	# §2 projectiles, keyed by faction then weapon. Player 1.43-1.70, enemy 0.50-0.71, so the
	# slowest player shot is 2.01x the fastest enemy shot (rule b) by construction.
	"shot.player.bolt": 1.70,
	"shot.player.pulse": 1.55,
	"shot.player.ricochet": 1.48,
	"shot.player.flame": 1.43,
	"shot.player.seeker": 1.43,
	"shot.player.rocket": 1.43,
	"shot.player.ring": 1.43,
	"shot.player.orbit": 1.43,
	"shot.player.bay_drone": 0.57,
	"shot.player.spiral": 1.48,
	"shot.enemy.bolt": 0.71,
	"shot.enemy.pulse": 0.60,
	"shot.enemy.ricochet": 0.60,
	"shot.enemy.spiral": 0.52,
	"shot.enemy.ring": 0.60,
	"shot.enemy.orbit": 0.60,
	"shot.enemy.seeker": 0.57,
	"shot.enemy.flame": 0.55,
	"shot.enemy.plasma": 0.52,
	"shot.enemy.void": 0.50,
	"shot.enemy.rocket": 0.50,
	"shot.enemy.bay_drone": 0.29,
	# The void orb's identity is "one slow heavy orb" (piercing): like the black hole it is a drifting
	# hazard, not a shot dodged or landed on reaction, so it sits outside the shot rules on both sides.
	# 0.34 keeps its authored 155 px/s at the base speed.
	"orb.void": 0.34,
	# §6 camera. Fractions are of the viewport half-width (640 px). "Smoothing time" is a time
	# constant; "over X s" and "recentre time" are 95 % settle times, so tau = X/3.
	"cam.lag_tau": 0.22,
	"cam.recentre_s": 0.30,
	"cam.recentre_speed_frac": 0.25, # below this fraction of top speed the lag tau blends to recentre
	"cam.lag_clamp": 0.14,
	"cam.zoom_top": 0.96,
	"cam.zoom_dash": 0.93,
	"cam.zoom_in_s": 0.40,
	"cam.zoom_out_s": 0.25,
	"cam.aim_frac": 0.06,
	"cam.aim_tau": 0.30,
	"cam.total_clamp": 0.18,
	# §7 camera
	"cam.push_lag_tau": 0.45,
	"cam.push_zoom": 1.02,
	"cam.break_zoom": 0.94,
	"cam.warp_lag_tau": 0.10,
	"cam.overshoot": 0.08,
	# §6.5 shake: screen px and seconds
	"shake.dash.px": 2.0, "shake.dash.s": 0.10,
	"shake.hit.px": 4.0, "shake.hit.s": 0.12,
	"shake.regression.px": 7.0, "shake.regression.s": 0.25,
	"shake.limb.px": 3.0, "shake.limb.s": 0.10,
	"shake.boss_death.px": 10.0, "shake.boss_death.s": 0.5,
	"shake.rotation_per_px": 0.001, # radians of roll per px of shake amplitude: 10 px -> 0.57 degrees
	# M10 layer switches (1 on, 0 off) so the §9 order can be tuned one layer at a time: `cam <layer> off`.
	"cam.lag_on": 1.0, "cam.zoom_on": 1.0, "cam.aim_on": 1.0, "shake.on": 1.0,
	# M10 hitstop, in sim ticks, per feel_event kind (h). A kind with no key gets none. The M1 broker
	# caps grants at 8 ticks per rolling 60; the boss kill was 12 and could only ever be granted 8,
	# so review fix 9 states it at the cap.
	"hitstop.player_hit": 4.0,
	"hitstop.elite_limb": 3.0,
	"hitstop.elite_kill": 3.0,
	"hitstop.boss_phase": 6.0,
	"hitstop.boss_kill": 8.0,
	"hitstop.enemy_kill": 0.0,
}
static var _feel_live: Dictionary = {}
## Bumped on every change. Hot loops cache their floats and re-read only when this moves.
static var feel_revision: int = 0

static func feel(key: String) -> float:
	if _feel_live.has(key): return float(_feel_live[key])
	if not FEEL_DEFAULTS.has(key):
		push_error("GameTuning.feel: unknown key '%s'" % key)
		return 0.0
	return float(FEEL_DEFAULTS[key])

## False, and nothing changes, for a key that does not exist or a value that is not a finite number.
static func set_feel(key: String, value: float) -> bool:
	if not FEEL_DEFAULTS.has(key) or is_nan(value) or is_inf(value): return false
	_feel_live[key] = value
	feel_revision += 1
	return true

static func reset_feel() -> void:
	_feel_live.clear()
	feel_revision += 1

static func feel_overrides() -> Dictionary: return _feel_live.duplicate()

## The one table of hitstop lengths (M10): ticks for a feel_event kind, 0 for a kind without one.
static func hitstop_ticks(kind: StringName) -> int:
	var key: String = "hitstop." + String(kind)
	return maxi(0, roundi(feel(key))) if FEEL_DEFAULTS.has(key) else 0

## The three time constants of the movement model for a hull role, derived from the spec's terms.
## `drift` is the decay of the velocity component PERPENDICULAR to the input: it solves "the velocity
## lags a 90 degree input step by drift_deg, drift_s after the step". Equal to `accel` when the
## target cannot be met, which is the plain isotropic model.
static func movement_taus(role: String) -> Dictionary:
	var key: String = "move.t90." + (role if role in ["compact", "heavy"] else "standard")
	var accel: float = maxf(0.001, feel(key) / log(10.0))
	var coast: float = maxf(0.001, feel("move.coast_stop_s") / log(1.0 / clampf(feel("move.coast_stop_frac"), 0.0001, 0.9999)))
	var drift: float = accel
	var seconds: float = feel("move.drift_s")
	var remaining: float = tan(deg_to_rad(feel("move.drift_deg"))) * (1.0 - exp(-seconds / accel))
	if seconds > 0.0 and remaining > 0.0 and remaining < 1.0: drift = maxf(accel, -seconds / log(remaining))
	return {"accel": accel, "coast": coast, "drift": drift}

static func hull_speed_factor(authored_speed: float) -> float:
	return authored_speed / AUTHORING_BASE_SPEED

static func hull_top_speed(authored_speed: float) -> float:
	return feel("player_top_speed") * hull_speed_factor(authored_speed)

static func enemy_top_speed(archetype: String) -> float:
	return feel("player_top_speed") * feel("enemy_ratio." + archetype)

static func projectile_speed(is_player: bool, weapon: String) -> float:
	return feel("player_top_speed") * feel("shot.%s.%s" % ["player" if is_player else "enemy", weapon])

static func capacity(tier: int, _max_tier: int = MAX_TIER) -> float:
	# A demo cap prevents further evolution; it does not grant terminal survivability.
	return TERMINAL_CAPACITY if tier >= MAX_TIER else THRESHOLDS[clampi(tier - 1, 0, THRESHOLDS.size() - 1)]

static func regression_floor(tier: int) -> float:
	return 0.0 if tier <= 1 else THRESHOLDS[clampi(tier - 2, 0, THRESHOLDS.size() - 1)] * REGRESSION_RATIO

## Exactly three secondary bindings exist anywhere in the control scheme
## (spec §26: Space/Shift/Q, LB/RB/X; `ShipCommand.secondaries` is a 3-long
## array and `_update_player` only ever reads index 0..2). A T6 Heavy's
## base 3 + role bonus 1 = 4 is therefore a slot the player can never press
## -- capping it here (the single source of the slot count) is the fix,
## not a defensive clamp at every reader. See tasks/lessons.md and P9
## review notes: adding a 4th binding would touch §26, Steam Input and
## every rebinding surface for a slot four heavy hulls out of 101 would use.
const MAX_SECONDARY_SLOTS: int = 3

## Spec §9: T1 1/0/0, T2 1/1/0, T3 1/1/0, T4 1/2/1, T5 1/2/1, T6 1/3/2.
## Compact takes -1 secondary (floor 1, once a secondary exists at all);
## Heavy takes +1 on top of the base count, capped at MAX_SECONDARY_SLOTS.
static func slots(tier: int, role: String) -> Dictionary:
	var base_secondary: int = [0, 1, 1, 2, 2, 3][clampi(tier - 1, 0, 5)]
	var base_passive: int = [0, 0, 0, 1, 1, 2][clampi(tier - 1, 0, 5)]
	var secondary: int = base_secondary
	if tier > 1:
		secondary = maxi(1, base_secondary - 1) if role == "compact" else base_secondary + (1 if role == "heavy" else 0)
	return {"primary": 1, "secondary": mini(secondary, MAX_SECONDARY_SLOTS), "passive": base_passive}
