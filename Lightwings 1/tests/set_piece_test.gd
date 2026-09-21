extends SceneTree
## SetPieceCatalog against ship design spec §6: the catalogue table, the colour gate, the player
## pools of §6.5, the ladder, and that 33 pieces are 33 DIFFERENT shapes. Every expectation is
## written out from the spec here, never derived from the table under test.
const Harness = preload("res://tests/support/harness.gd")

## Spec §6.3, verbatim: piece -> [colours, slot].
const SPEC: Dictionary = {
	"twin_barrel": [["blue"], "primary"], "lens_stack": [["blue"], "primary"], "shell_pair": [["blue"], "secondary"],
	"vent_fan": [["red"], "primary"], "drop_cradle": [["red"], "secondary"], "burst_ring": [["red"], "secondary"],
	"coil_pair": [["yellow"], "primary"], "wedge_pair": [["yellow"], "primary"], "hook_node": [["yellow"], "secondary"],
	"sac_cluster": [["green"], "secondary"], "bloom_pod": [["green"], "secondary"], "spore_rack": [["green"], "secondary"],
	"spin_ring": [["violet"], "primary"], "halo_node": [["violet"], "secondary"], "phase_pair": [["violet"], "secondary"],
	"well_cup": [["silver"], "primary"], "iris_ring": [["silver"], "secondary"], "pull_cage": [["silver"], "secondary"],
	"v_rack": [["yellow", "red"], "secondary"], "fin_trio": [["yellow", "violet"], "secondary"], "storm_crown": [["yellow", "silver"], "secondary"],
	"coil_array": [["yellow", "green"], "secondary"], "split_lance": [["blue", "red"], "primary"], "shell_ring": [["blue", "silver"], "secondary"],
	"web_node": [["blue", "green"], "secondary"], "node_pair": [["blue", "violet"], "primary"], "rift_pair": [["blue", "yellow"], "primary"],
	"ember_rack": [["red", "green"], "secondary"], "collapse_cage": [["red", "silver"], "secondary"], "flare_ring": [["red", "violet"], "secondary"],
	"leech_arm": [["green", "silver"], "secondary"], "mesh_node": [["green", "violet"], "secondary"], "prism_stack": [["violet", "silver"], "primary"],
}
## Spec §6.5, verbatim: the accent's pool is 3 blue + 3 of the accent + one hybrid.
const POOLS: Dictionary = {
	"red": ["twin_barrel", "lens_stack", "shell_pair", "vent_fan", "drop_cradle", "burst_ring", "split_lance"],
	"yellow": ["twin_barrel", "lens_stack", "shell_pair", "coil_pair", "wedge_pair", "hook_node", "rift_pair"],
	"green": ["twin_barrel", "lens_stack", "shell_pair", "sac_cluster", "bloom_pod", "spore_rack", "web_node"],
	"violet": ["twin_barrel", "lens_stack", "shell_pair", "spin_ring", "halo_node", "phase_pair", "node_pair"],
	"silver": ["twin_barrel", "lens_stack", "shell_pair", "well_cup", "iris_ring", "pull_cage", "shell_ring"],
}
const GRID: int = 96

func _initialize() -> void: _run.call_deferred()

func _sorted(values: Array) -> Array:
	var copy: Array = values.duplicate()
	copy.sort()
	return copy

## A piece drawn on a 96 x 96 bit grid at 1 px per unit, hub included: what the eye separates.
func _raster(piece: Dictionary) -> PackedByteArray:
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(GRID * GRID)
	var centre: Vector2 = Vector2(GRID * 0.5, GRID * 0.5)
	_ring(grid, centre, 15.0)
	var at: Array[Vector2] = []
	for circle: Array in piece.circles:
		var position: Vector2 = centre + Vector2(float(circle[0]), float(circle[1]))
		at.append(position)
		_ring(grid, position, float(circle[2]))
	for line: Array in piece.lines:
		var from: Vector2 = centre if int(line[0]) == SetPieceCatalog.HUB else at[int(line[0])]
		var to: Vector2 = at[int(line[1])]
		for step: int in range(65): _plot(grid, from.lerp(to, float(step) / 64.0))
	return grid

func _ring(grid: PackedByteArray, centre: Vector2, radius: float) -> void:
	for step: int in range(360): _plot(grid, centre + Vector2.from_angle(TAU * float(step) / 360.0) * radius)

func _plot(grid: PackedByteArray, at: Vector2) -> void:
	var x: int = int(round(at.x))
	var y: int = int(round(at.y))
	if x >= 0 and y >= 0 and x < GRID and y < GRID: grid[y * GRID + x] = 1

func _distance(a: PackedByteArray, b: PackedByteArray) -> int:
	var differing: int = 0
	for i: int in range(a.size()):
		if a[i] != b[i]: differing += 1
	return differing

func _run() -> void:
	var h := Harness.new("SET PIECES")
	var ids: Array[String] = SetPieceCatalog.ids()
	h.check(ids.size() == 33 and _sorted(ids) == _sorted(SPEC.keys()), "The catalogue holds exactly the spec's 33 pieces (%d)" % ids.size())
	var mono: int = 0
	var abilities: Dictionary = {}
	for id: String in ids:
		var piece: Dictionary = SetPieceCatalog.get_piece(id)
		var expected: Array = SPEC.get(id, [[], ""])
		h.check(_sorted(piece.colours) == _sorted(expected[0]) and str(piece.slot) == str(expected[1]), "%s is %s / %s as §6.3 says (%s / %s)" % [id, str(expected[0]), expected[1], str(piece.colours), piece.slot])
		if (piece.colours as Array).size() == 1: mono += 1
		abilities[str(piece.ability)] = true
		var circles: Array = piece.circles
		var ladder: bool = true
		var used: Dictionary = {}
		for circle: Array in circles:
			if not SetPieceCatalog.PIECE_RADII.has(int(circle[2])): ladder = false
			used[int(circle[4])] = true
		var ends: bool = true
		for line: Array in piece.lines:
			if int(line[0]) < SetPieceCatalog.HUB or int(line[0]) >= circles.size() or int(line[1]) < 0 or int(line[1]) >= circles.size() or int(line[0]) == int(line[1]): ends = false
			used[int(line[2])] = true
		h.check(ladder and circles.size() >= 2 and circles.size() <= SetPieceCatalog.MAX_CIRCLES, "%s: 2-5 circles, every one on the ladder (%d)" % [id, circles.size()])
		h.check(ends, "%s: every line runs between two of its circles, or from the hub" % id)
		h.check(used.size() == (piece.colours as Array).size(), "%s uses every colour it declares and no other (%s)" % [id, str(used.keys())])
	h.check(mono == 18 and ids.size() - mono == 15, "18 mono-colour and 15 two-colour pieces (%d / %d)" % [mono, ids.size() - mono])
	h.check(abilities.size() == 33, "33 pieces are 33 different weapons (%d)" % abilities.size())

	# The gate. Expectations are the spec's own lists, not a second reading of the table.
	for accent: String in POOLS:
		h.check(_sorted(SetPieceCatalog.legal_for("blue", accent)) == _sorted(POOLS[accent]), "A blue + %s player may mount exactly §6.5's seven (%s)" % [accent, str(SetPieceCatalog.legal_for("blue", accent))])
	for colour: String in Elements.COLOR_KEYS:
		h.check(SetPieceCatalog.legal_for(colour, "").size() == 3, "A mono-%s ship has exactly three pieces" % colour)
	h.check(SetPieceCatalog.is_legal("v_rack", "yellow", "red") and SetPieceCatalog.is_legal("v_rack", "red", "yellow"), "v_rack mounts on yellow + red either way round")
	h.control("v_rack on a yellow + green ship", not SetPieceCatalog.is_legal("v_rack", "yellow", "green"))
	h.control("v_rack on a mono-yellow ship", not SetPieceCatalog.is_legal("v_rack", "yellow", ""))
	h.control("a blue piece on an enemy's colours", not SetPieceCatalog.is_legal("twin_barrel", "red", "silver"))
	h.control("a piece that does not exist", not SetPieceCatalog.is_legal("not_a_piece", "blue", "red"))
	var enemy_only: int = 0
	for id: String in ids:
		if not (SetPieceCatalog.colours_of(id) as Array).has("blue") and (SetPieceCatalog.colours_of(id) as Array).size() == 2: enemy_only += 1
	h.check(enemy_only == 10, "Ten hybrids carry no blue and are therefore enemy-only (%d)" % enemy_only)

	# 33 different silhouettes. Distances printed so the threshold is a measurement.
	var rasters: Dictionary = {}
	for id: String in ids: rasters[id] = _raster(SetPieceCatalog.get_piece(id))
	var pairs: Array = []
	for a: int in range(ids.size()):
		for b: int in range(a + 1, ids.size()): pairs.append([_distance(rasters[ids[a]], rasters[ids[b]]), ids[a], ids[b]])
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	for k: int in range(5): print("closest pair %d: %s / %s differ in %d cells" % [k + 1, pairs[k][1], pairs[k][2], pairs[k][0]])
	h.check(int(pairs[0][0]) >= MIN_GLYPH_DISTANCE, "No two pieces draw nearly the same glyph: the closest pair differs in %d cells (%s / %s)" % [pairs[0][0], pairs[0][1], pairs[0][2]])
	h.control("a piece compared with itself", _distance(rasters["v_rack"], _raster(SetPieceCatalog.get_piece("v_rack"))) < MIN_GLYPH_DISTANCE)

	var unbuilt: Array[String] = []
	for id: String in ids:
		if not SetPieceCatalog.is_implemented(id): unbuilt.append(id)
	print("set pieces whose weapon is not built yet (%d): %s" % [unbuilt.size(), ", ".join(unbuilt)])
	h.check(SetPieceCatalog.is_implemented("v_rack") and SetPieceCatalog.is_implemented("twin_barrel"), "Pieces whose weapons exist report as implemented")
	h.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://content/ships/set_pieces")), "There is no per-ship set-piece override directory: pieces are authored once")
	h.finish(self)

## Measured (S4): the five closest pairs differ in 109, 116, 135, 141 and 144 cells (halo_node /
## iris_ring is the closest). A single micro circle is ~25 cells, so 55 means "at least two small
## circles apart" and is half the closest real pair - a new piece drawn almost like an old one fails.
const MIN_GLYPH_DISTANCE: int = 55
