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

static func on_ladder(radius: float) -> bool:
	for value: int in LADDER.values():
		if is_equal_approx(radius, float(value)): return true
	return false
