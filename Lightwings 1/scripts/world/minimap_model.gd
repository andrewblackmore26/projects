class_name MinimapModel
extends RefCounted
## Pure, headlessly-testable model shared by BOTH the corner minimap and the
## full map screen (spec §11, M3 acceptance test: "a tester always knows
## which way the boss is"). This class never draws; it only reads
## CampaignState's own pure geometry and reports what a renderer should show,
## so what the player sees can never disagree with the simulation (lessons.md
## "a state the map shows must change what the simulation does").
##
## The whole level fits in one grid at every level radius (R up to 12 -> a
## 25x25 grid, spec §11 "the whole level must fit on screen"): no panning,
## no waypoints, no JUMP.

const DIRECTIONS: Array[String] = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]

class Cell:
	var coord: Vector2i
	var in_bounds: bool = false
	## "Unexplored nodes reveal nothing about their contents" (spec §11): a
	## renderer must draw an unexplored-but-in-bounds cell dark, never omit
	## it (v0.2's map omitted unknown cells outright).
	var explored: bool = false
	var current: bool = false
	var is_boss: bool = false

var radius: int = 0
var boss_coord: Vector2i = Vector2i.ZERO
var current_coord: Vector2i = Vector2i.ZERO
var cells: Array[Cell] = []
## Present and correct from the first tick of every node -- the boss is
## marked on the minimap "from the start" (spec §11), never only once found.
var bearing_direction: String = "NONE"
var bearing_distance: int = -1

## `debug_hide_boss` is a negative-control seam ONLY (tests/hud_model_test.gd):
## forcing it true blanks the bearing so the boss-bearing check that reads it
## is provably able to fail, per lessons.md "every instrument gets a negative
## control".
static func build(campaign: CampaignState, debug_hide_boss: bool = false) -> MinimapModel:
	var model := MinimapModel.new()
	model.radius = campaign.level_radius()
	model.boss_coord = campaign.boss_coord()
	model.current_coord = campaign.current_sector
	for y: int in range(-model.radius, model.radius + 1):
		for x: int in range(-model.radius, model.radius + 1):
			var coord := Vector2i(x, y)
			var cell := Cell.new()
			cell.coord = coord
			cell.in_bounds = campaign.in_bounds(coord)
			cell.explored = CampaignState.coord_key(coord) in campaign.discovered
			cell.current = coord == model.current_coord
			cell.is_boss = cell.in_bounds and coord == model.boss_coord
			model.cells.append(cell)
	if debug_hide_boss:
		model.bearing_direction = "NONE"
		model.bearing_distance = -1
	else:
		var delta: Vector2i = model.boss_coord - model.current_coord
		# Travel is four-connected, so distance is reported in Manhattan
		# steps (spec §11: "a node count in Manhattan steps"); the arrow
		# itself is quantized to eight directions for readability.
		model.bearing_distance = absi(delta.x) + absi(delta.y)
		model.bearing_direction = direction_of(delta)
	return model

## Screen convention: north is -y (matches Vector2i.UP used throughout
## CampaignState.DIRECTIONS/exits_of).
static func direction_of(delta: Vector2i) -> String:
	if delta == Vector2i.ZERO: return "HERE"
	var angle: float = atan2(float(-delta.y), float(delta.x))
	var index: int = int(roundf(angle / (PI / 4.0))) % DIRECTIONS.size()
	if index < 0: index += DIRECTIONS.size()
	return DIRECTIONS[index]

func cell_at(coord: Vector2i) -> Cell:
	for cell: Cell in cells:
		if cell.coord == coord: return cell
	return null

## Grid side length a renderer needs to lay out (spec: "the whole level must
## fit on screen at every level radius").
func grid_size() -> int:
	return radius * 2 + 1
