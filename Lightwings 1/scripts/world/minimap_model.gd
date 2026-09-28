class_name MinimapModel
extends RefCounted
## Pure, headlessly-testable model shared by BOTH the corner minimap and the
## full map screen (spec §11, M3 acceptance test: "a tester always knows
## which way the boss is"). This class never draws; it only reads
## CampaignState's own pure geometry and reports what a renderer should show,
## so what the player sees can never disagree with the simulation (lessons.md
## "a state the map shows must change what the simulation does").
##
## The whole level is one lattice at every level radius (R up to 12 -> 25x25
## nodes, spec §11). Modernization M14: the map screen can pan and zoom it,
## but its default view still fits the whole level; the rails, the reveal
## order and focus steps below are the view-model both renderers draw from.

const DIRECTIONS: Array[String] = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
## M14: the map reveals node by node outward from the player, this many seconds per ring of
## Chebyshev distance (the plan's "20 ms per ring").
const REVEAL_PER_RING: float = 0.020

class Cell:
	var coord: Vector2i
	var in_bounds: bool = false
	## "Unexplored nodes reveal nothing about their contents" (spec §11): a
	## renderer must draw an unexplored-but-in-bounds cell dark, never omit
	## it (v0.2's map omitted unknown cells outright).
	var explored: bool = false
	var current: bool = false
	var is_boss: bool = false
	## M14: the directions this node has a rail along (CampaignState.neighbours_of: the open
	## lattice's 8 inside, 5 on an edge, 3 at a corner). Travel and focus both follow these.
	var rails: Array[Vector2i] = []

var radius: int = 0
var boss_coord: Vector2i = Vector2i.ZERO
var current_coord: Vector2i = Vector2i.ZERO
var cells: Array[Cell] = []
## Present and correct from the first tick of every node -- the boss is
## marked on the minimap "from the start" (spec §11), never only once found.
var bearing_direction: String = "NONE"
var bearing_distance: int = -1
## coord -> Cell, for cell_at.
var _index: Dictionary = {}

## `debug_hide_boss` is a negative-control seam ONLY (tests/hud_model_test.gd):
## forcing it true blanks the bearing so the boss-bearing check that reads it
## is provably able to fail, per lessons.md "every instrument gets a negative
## control".
## M14: `window` >= 0 keeps only the cells within that many Chebyshev steps of the current node
## (the corner minimap's local window); -1 is the whole level. The bearing is the same either way.
static func build(campaign: CampaignState, debug_hide_boss: bool = false, window: int = -1) -> MinimapModel:
	var model := MinimapModel.new()
	model.radius = campaign.level_radius()
	model.boss_coord = campaign.boss_coord()
	model.current_coord = campaign.current_sector
	var discovered: Dictionary = {}
	for key: Variant in campaign.discovered: discovered[str(key)] = true
	var low := Vector2i(-model.radius, -model.radius)
	var high := Vector2i(model.radius, model.radius)
	if window >= 0:
		low = Vector2i(maxi(low.x, model.current_coord.x - window), maxi(low.y, model.current_coord.y - window))
		high = Vector2i(mini(high.x, model.current_coord.x + window), mini(high.y, model.current_coord.y + window))
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var coord := Vector2i(x, y)
			var cell := Cell.new()
			cell.coord = coord
			cell.in_bounds = campaign.in_bounds(coord)
			cell.explored = discovered.has(CampaignState.coord_key(coord))
			cell.current = coord == model.current_coord
			cell.is_boss = cell.in_bounds and coord == model.boss_coord
			cell.rails = campaign.neighbours_of(coord)
			model.cells.append(cell)
			model._index[coord] = cell
	if debug_hide_boss:
		model.bearing_direction = "NONE"
		model.bearing_distance = -1
	else:
		var delta: Vector2i = model.boss_coord - model.current_coord
		# Travel is eight-connected (modernization M3's open lattice), so the
		# node count is Chebyshev steps; the arrow itself is quantized to
		# eight directions for readability.
		model.bearing_distance = CampaignState.ring(delta)
		model.bearing_direction = direction_of(delta)
	return model

## Screen convention: north is -y (matches Vector2i.UP used throughout
## CampaignState.NEIGHBOURS/neighbours_of).
static func direction_of(delta: Vector2i) -> String:
	if delta == Vector2i.ZERO: return "HERE"
	var angle: float = atan2(float(-delta.y), float(delta.x))
	var index: int = int(roundf(angle / (PI / 4.0))) % DIRECTIONS.size()
	if index < 0: index += DIRECTIONS.size()
	return DIRECTIONS[index]

func cell_at(coord: Vector2i) -> Cell:
	return _index.get(coord)

## Grid side length a renderer needs to lay out (spec: "the whole level must
## fit on screen at every level radius").
func grid_size() -> int:
	return radius * 2 + 1

## --- M14 view-model helpers ---------------------------------------------

## Every rail once, as [a, b] with a before b in `cells` order: one segment per pair of
## neighbouring in-bounds nodes the model holds (both ends inside the window, when windowed).
func rail_segments() -> Array:
	var result: Array = []
	for cell: Cell in cells:
		for dir: Vector2i in cell.rails:
			# Each undirected rail is emitted from its "lower" end only.
			if dir.y < 0 or (dir.y == 0 and dir.x < 0): continue
			if _index.has(cell.coord + dir): result.append([cell.coord, cell.coord + dir])
	return result

## Seconds after the map opens at which `coord` appears: REVEAL_PER_RING per ring of distance
## from the current node.
func reveal_delay(coord: Vector2i) -> float:
	return REVEAL_PER_RING * float(CampaignState.ring(coord - current_coord))

## In-bounds nodes in the order they appear (nearest ring first; within a ring, row order).
func reveal_order() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Cell in cells:
		if cell.in_bounds: result.append(cell.coord)
	var here: Vector2i = current_coord
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return CampaignState.ring(a - here) < CampaignState.ring(b - here))
	return result

## Where map focus lands from `coord` pressing `dir` (one of the 8 bearings): along a rail when
## there is one, otherwise it stays put (the level edge).
func focus_step(coord: Vector2i, dir: Vector2i) -> Vector2i:
	var cell: Cell = cell_at(coord)
	if cell == null or dir not in cell.rails: return coord
	return coord + dir

## Quantizes a stick or key vector (y down) to one of the 8 bearings; ZERO below `deadzone`.
static func bearing_of(vector: Vector2, deadzone: float = 0.3) -> Vector2i:
	if vector.length() < deadzone: return Vector2i.ZERO
	return CampaignState.nearest_bearing(CampaignState.NEIGHBOURS, atan2(vector.y, vector.x))
