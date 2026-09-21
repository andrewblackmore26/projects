class_name SetPieceCatalog
extends RefCounted
## The weapon set pieces (ship design spec §4.5, §6.3): fixed, named arrangements of ladder circles
## and lines that mount on a hub. Authored once, here, by hand; there is deliberately no per-ship
## override and no .tres directory, because "edited per ship" is what the spec forbids.
##
## Frame: the hub (r 15) is at the origin, -y points OUTWARD along the arm (and along the aim once
## the piece tracks it), +x is to the right. Colours are intrinsic: `colours[k]` names a palette key
## and every circle and line says which one it uses, so a piece looks identical on every ship and
## "a third colour anywhere" is a checkable property of a compiled hull.
##
## circles: [x, y, radius, filled, colour_index]          radius is 7, 5 or 4 (the ladder)
## lines:   [from, to, colour_index]                      -1 = the hub's CENTRE, else a circle index
## A line from the hub starts at its centre and draws over its fill (the reference's V is visible
## inside the hub); a line between two piece circles is clipped at both rims like any other.

const HUB: int = -1

const PIECES: Dictionary = {
	# ---- mono: blue (player only) ----
	"twin_barrel": {"ability": "pulse_cannon", "slot": "primary", "colours": ["blue"], "muzzle": Vector2(0, -24),
		"circles": [[-5, -7, 4, true, 0], [5, -7, 4, true, 0], [-5, -20, 4, false, 0], [5, -20, 4, false, 0]], "lines": [[0, 2, 0], [1, 3, 0]]},
	"lens_stack": {"ability": "beam", "slot": "primary", "colours": ["blue"], "muzzle": Vector2(0, -34),
		"circles": [[0, -9, 7, false, 0], [0, -21, 4, true, 0], [0, -30, 4, false, 0]], "lines": [[0, 1, 0], [1, 2, 0]]},
	"shell_pair": {"ability": "orbital_blockers", "slot": "secondary", "colours": ["blue"], "muzzle": Vector2.ZERO,
		"circles": [[-19, -10, 7, true, 0], [19, -10, 7, true, 0]], "lines": []},
	# ---- mono: red ----
	"vent_fan": {"ability": "flame_cone", "slot": "primary", "colours": ["red"], "muzzle": Vector2(0, -24),
		"circles": [[0, 6, 4, true, 0], [-12, -15, 4, false, 0], [0, -20, 4, false, 0], [12, -15, 4, false, 0]], "lines": [[0, 1, 0], [0, 2, 0], [0, 3, 0]]},
	"drop_cradle": {"ability": "mine_layer", "slot": "secondary", "colours": ["red"], "muzzle": Vector2(0, 22),
		"circles": [[0, 22, 7, true, 0], [-10, 13, 4, false, 0], [10, 13, 4, false, 0]], "lines": [[1, 0, 0], [2, 0, 0]]},
	"burst_ring": {"ability": "explosives", "slot": "secondary", "colours": ["red"], "muzzle": Vector2(0, -15),
		"circles": [[0, 0, 7, false, 0], [-11, -11, 4, true, 0], [11, -11, 4, true, 0], [-11, 11, 4, true, 0], [11, 11, 4, true, 0]], "lines": []},
	# ---- mono: yellow ----
	"coil_pair": {"ability": "bolt", "slot": "primary", "colours": ["yellow"], "muzzle": Vector2(0, -26),
		"circles": [[-7, 0, 7, false, 0], [7, 0, 7, false, 0], [0, -22, 4, true, 0]], "lines": [[0, 2, 0], [1, 2, 0]]},
	"wedge_pair": {"ability": "ricochet", "slot": "primary", "colours": ["yellow"], "muzzle": Vector2(0, -27),
		"circles": [[0, -23, 4, true, 0], [-14, 8, 4, false, 0], [14, 8, 4, false, 0]], "lines": [[0, 1, 0], [0, 2, 0]]},
	"hook_node": {"ability": "arc_tether", "slot": "secondary", "colours": ["yellow"], "muzzle": Vector2(0, -26),
		"circles": [[0, -22, 4, true, 0], [10, -13, 4, false, 0]], "lines": [[HUB, 0, 0], [0, 1, 0]]},
	# ---- mono: green ----
	"sac_cluster": {"ability": "virus", "slot": "secondary", "colours": ["green"], "muzzle": Vector2(0, -20),
		"circles": [[1, -20, 7, true, 0], [14, -13, 7, true, 0], [14, -26, 4, true, 0]], "lines": []},
	"bloom_pod": {"ability": "poison_cloud", "slot": "secondary", "colours": ["green"], "muzzle": Vector2(0, -30),
		"circles": [[0, -21, 7, false, 0], [-8, -28, 4, true, 0], [8, -28, 4, true, 0]], "lines": []},
	"spore_rack": {"ability": "drone_hatch", "slot": "secondary", "colours": ["green"], "muzzle": Vector2(0, 23),
		"circles": [[-10, 16, 4, true, 0], [0, 19, 4, true, 0], [10, 16, 4, true, 0]], "lines": []},
	# ---- mono: violet ----
	"spin_ring": {"ability": "spiral_shot", "slot": "primary", "colours": ["violet"], "muzzle": Vector2(0, -22),
		"circles": [[0, -18, 4, true, 0], [15.6, 9, 4, true, 0], [-15.6, 9, 4, true, 0]], "lines": [[HUB, 0, 0], [HUB, 1, 0], [HUB, 2, 0]]},
	"halo_node": {"ability": "pulse_ring", "slot": "secondary", "colours": ["violet"], "muzzle": Vector2.ZERO,
		"circles": [[0, 0, 7, false, 0], [0, 0, 4, true, 0]], "lines": []},
	"phase_pair": {"ability": "blink_mine", "slot": "secondary", "colours": ["violet"], "muzzle": Vector2(0, -15),
		"circles": [[-15, 13, 7, true, 0], [15, -13, 7, false, 0]], "lines": [[0, 1, 0]]},
	# ---- mono: silver ----
	"well_cup": {"ability": "void_orb", "slot": "primary", "colours": ["silver"], "muzzle": Vector2(0, -21),
		"circles": [[0, 0, 7, true, 0], [-12, -12, 4, false, 0], [0, -17, 4, false, 0], [12, -12, 4, false, 0]], "lines": []},
	"iris_ring": {"ability": "slow_field", "slot": "secondary", "colours": ["silver"], "muzzle": Vector2.ZERO,
		"circles": [[0, 0, 7, false, 0], [-15, 0, 4, false, 0], [15, 0, 4, false, 0]], "lines": [[1, 2, 0]]},
	"pull_cage": {"ability": "black_hole_shot", "slot": "secondary", "colours": ["silver"], "muzzle": Vector2(0, -15),
		"circles": [[-17, -14, 4, true, 0], [-17, 14, 4, true, 0], [17, -14, 4, true, 0], [17, 14, 4, true, 0]], "lines": [[0, 1, 0], [2, 3, 0]]},
	# ---- two-colour. colours[0] is listed first in spec §6.3 ----
	# v_rack is TRACED from docs/ship-design-reference.json, not drafted: a red ring (r 5.2 -> ladder 5)
	# 21.7-22.0 outward on a red pin from the hub's centre, and a yellow V from the centre toward the
	# side pods. The image's V runs on to the pods themselves; pods bob and a piece tracks the aim,
	# so here the V ends on two yellow micro beads on the hub's rim at the pods' +-0.78 rad instead.
	"v_rack": {"ability": "rocket_launcher", "slot": "secondary", "colours": ["yellow", "red"], "muzzle": Vector2(0, -27),
		"circles": [[0, -22, 5, true, 1], [-10.55, -10.66, 4, true, 0], [10.55, -10.66, 4, true, 0]], "lines": [[HUB, 0, 1], [HUB, 1, 0], [HUB, 2, 0]]},
	"fin_trio": {"ability": "seeker_missiles", "slot": "secondary", "colours": ["yellow", "violet"], "muzzle": Vector2(0, -15),
		"circles": [[0, 19, 4, false, 0], [0, 27, 4, false, 0], [0, 35, 4, false, 0]], "lines": [[HUB, 0, 1], [0, 1, 1], [1, 2, 1]]},
	"storm_crown": {"ability": "discharge", "slot": "secondary", "colours": ["yellow", "silver"], "muzzle": Vector2.ZERO,
		"circles": [[-16, -9, 4, true, 0], [-8, -22, 4, true, 0], [0, -13, 4, true, 0], [8, -22, 4, true, 0], [16, -9, 4, true, 0]], "lines": [[0, 1, 1], [1, 2, 1], [2, 3, 1], [3, 4, 1]]},
	"coil_array": {"ability": "chain_infection", "slot": "secondary", "colours": ["yellow", "green"], "muzzle": Vector2(0, -26),
		"circles": [[-9, -3, 7, false, 0], [9, -3, 7, false, 0], [-9, -22, 4, true, 0], [9, -22, 4, true, 0]], "lines": [[0, 2, 1], [1, 3, 1]]},
	"split_lance": {"ability": "ignition_lance", "slot": "primary", "colours": ["blue", "red"], "muzzle": Vector2(0, -35),
		"circles": [[0, -6, 4, true, 0], [-4, -31, 4, false, 0], [4, -31, 4, false, 0]], "lines": [[0, 1, 1], [0, 2, 1]]},
	"shell_ring": {"ability": "shield", "slot": "secondary", "colours": ["blue", "silver"], "muzzle": Vector2.ZERO,
		"circles": [[0, -24, 4, true, 0], [-21, 12, 4, true, 0], [21, 12, 4, true, 0]], "lines": [[0, 1, 1], [1, 2, 1], [2, 0, 1]]},
	"web_node": {"ability": "siphon_tether", "slot": "secondary", "colours": ["blue", "green"], "muzzle": Vector2(0, -24),
		"circles": [[-14, -15, 4, true, 0], [3, -23, 4, true, 0], [18, -9, 4, true, 0]], "lines": [[HUB, 0, 1], [HUB, 1, 1], [HUB, 2, 1], [0, 1, 1], [1, 2, 1]]},
	"node_pair": {"ability": "phase_shot", "slot": "primary", "colours": ["blue", "violet"], "muzzle": Vector2(0, -34),
		"circles": [[0, -6, 4, true, 0], [0, -27, 7, false, 0]], "lines": [[0, 1, 1]]},
	"rift_pair": {"ability": "overcharge", "slot": "primary", "colours": ["blue", "yellow"], "muzzle": Vector2(0, -31),
		"circles": [[-8, -24, 7, false, 0], [8, -24, 7, false, 0]], "lines": [[HUB, 0, 1], [HUB, 1, 1]]},
	"ember_rack": {"ability": "incendiary_spores", "slot": "secondary", "colours": ["red", "green"], "muzzle": Vector2(0, -22),
		"circles": [[-13, -18, 7, true, 0], [13, -18, 7, true, 0]], "lines": [[HUB, 0, 1], [HUB, 1, 1], [0, 1, 1]]},
	"collapse_cage": {"ability": "collapse_charge", "slot": "secondary", "colours": ["red", "silver"], "muzzle": Vector2.ZERO,
		"circles": [[-17, -17, 4, true, 0], [17, -17, 4, true, 0], [17, 17, 4, true, 0], [-17, 17, 4, true, 0]], "lines": [[0, 1, 1], [1, 2, 1], [2, 3, 1], [3, 0, 1]]},
	"flare_ring": {"ability": "nova_pulse", "slot": "secondary", "colours": ["red", "violet"], "muzzle": Vector2.ZERO,
		"circles": [[0, 0, 4, true, 0], [0, -22, 4, true, 0], [0, 22, 4, true, 0], [-22, 0, 4, true, 0], [22, 0, 4, true, 0]], "lines": [[0, 1, 1], [0, 2, 1], [0, 3, 1], [0, 4, 1]]},
	"leech_arm": {"ability": "siphon_leech", "slot": "secondary", "colours": ["green", "silver"], "muzzle": Vector2(6, -30),
		"circles": [[-8, -20, 4, true, 0], [6, -30, 7, true, 0]], "lines": [[HUB, 0, 1], [0, 1, 1]]},
	"mesh_node": {"ability": "drone_swarm", "slot": "secondary", "colours": ["green", "violet"], "muzzle": Vector2(0, -15),
		"circles": [[-7, -7, 4, true, 0], [7, -7, 4, true, 0], [7, 7, 4, true, 0], [-7, 7, 4, true, 0]], "lines": [[0, 1, 1], [1, 2, 1], [2, 3, 1], [3, 0, 1], [0, 2, 1], [1, 3, 1]]},
	"prism_stack": {"ability": "refract_beam", "slot": "primary", "colours": ["violet", "silver"], "muzzle": Vector2(11, -35),
		"circles": [[0, -7, 4, true, 0], [0, -21, 7, false, 0], [11, -31, 4, true, 0]], "lines": [[0, 1, 1], [1, 2, 1]]},
}

const MAX_CIRCLES: int = 5
const PIECE_RADII: Array[int] = [7, 5, 4]

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in PIECES: result.append(id)
	return result

static func has(id: String) -> bool:
	return PIECES.has(id)

static func get_piece(id: String) -> Dictionary:
	return PIECES.get(id, {})

static func colours_of(id: String) -> Array:
	return get_piece(id).get("colours", [])

static func ability_of(id: String) -> String:
	return str(get_piece(id).get("ability", ""))

static func slot_of(id: String) -> String:
	return str(get_piece(id).get("slot", ""))

## The weapon's behaviour exists. A ship may only mount implemented pieces (user decision 1), so a
## hull cannot advertise a weapon the game cannot fire while the behaviours are still landing.
static func is_implemented(id: String) -> bool:
	return has(id) and AbilityCatalog.DEFINITIONS.has(ability_of(id))

## THE colour gate (spec §6.2): every colour in the piece is in the ship's pair.
static func is_legal(id: String, chassis: String, accent: String) -> bool:
	if not has(id): return false
	for colour: String in colours_of(id):
		if colour != chassis and (accent == "" or colour != accent): return false
	return true

static func legal_for(chassis: String, accent: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in PIECES:
		if is_legal(id, chassis, accent): result.append(id)
	return result

static func for_ability(ability: String) -> String:
	for id: String in PIECES:
		if ability_of(id) == ability: return id
	return ""
