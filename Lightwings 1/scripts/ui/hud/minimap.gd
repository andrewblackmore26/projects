class_name Minimap
extends RefCounted
## The corner minimap (moved from main.gd's `_draw_minimap` in modernization M2): the explored
## neighbourhood of the current node, the level edge and the boss bearing, drawn into a clipped
## Control of the HUD. MinimapModel is the model; MapScreen colours the nodes.
##
## Modernization M14: a circular window on the open lattice. The current node sits at the centre,
## its neighbourhood's nodes and rails around it fade toward the rim, the level edge is a clean
## line, and the boss bearing is a chevron on the rim. Everything is geometry clipped to the circle
## (`primitives`), so the mask is exact without a shader, and the list is rebuilt only when the run
## moves (`_signature`); a frame just replays it plus the current node's pulse.

const BLUE := VisualStyle.BLUE
const MUTED := VisualStyle.MUTED
const GOLD := VisualStyle.ACCENT

var app: Node
var minimap: Control

func _init(owner: Node) -> void:
	app = owner

## The panel, backing and caption included (M6: the backing and the ring caption used to be drawn
## outside a 186 px clip rect, so the caption never showed).
const SIZE: Vector2 = Vector2(196,217)
## The current node's centre in the panel.
const CENTER: Vector2 = Vector2(98,98)
## M14: the circular window. Nothing but the caption is drawn outside this radius of CENTER.
const CLIP_RADIUS: float = 92.0
## Lattice spacing: ring 4 lies 84 px out, so the 9x9 window's nodes that fit the circle show and
## the rails to ring 5 run out under the rim.
const CELL: float = 21.0
const WINDOW: int = 5
const NODE_RADIUS: float = 4.5
const UNEXPLORED_RADIUS: float = 2.6
const RAIL_WIDTH: float = 1.25
const EDGE_WIDTH: float = 1.5
## Rails and the edge fade from full at this fraction of the radius to FADE_FLOOR at the rim.
const FADE_FROM: float = 0.62
const FADE_FLOOR: float = 0.18

## The cached primitives and the run state they were built for.
var _cache: Array = []
var _cache_key: Array = []
var _caption: Dictionary = {}
static var _font: Font

func build(parent: Control) -> void:
	minimap = Control.new()
	minimap.name = "Minimap"
	minimap.position = Vector2(1052,96)
	minimap.size = SIZE
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Review finding 6: the perimeter used to be a circular arc that both had
	# the wrong shape (the level boundary is a square Chebyshev ring, spec
	# §11) and spilled outside this panel across the playfield. Clip so
	# nothing this Control draws can ever leave its own declared rect.
	minimap.clip_contents = true
	parent.add_child(minimap)
	minimap.draw.connect(_draw_minimap)

func redraw() -> void:
	minimap.queue_redraw()

## M6: pins the panel's top-right corner at `top_right` (UI px).
func layout(top_right: Vector2) -> void:
	minimap.size = SIZE
	minimap.position = top_right-Vector2(SIZE.x,0)

## What the cache depends on: a new node, a discovery, a new life or level, a tier.
static func _signature(campaign: CampaignState, tier: int) -> Array:
	return [campaign.current_sector,campaign.discovered.size(),campaign.level,campaign.epoch,campaign.world_seed,campaign.boss_down,tier]

func _draw_minimap() -> void:
	var campaign: CampaignState = app.campaign
	var combat: CombatWorld = app.combat
	if campaign == null or not is_instance_valid(combat): return
	# The primitives (and the model under them) are rebuilt only when the run moves on. Keep
	# `primitives` directly below: tests/hud_model_test.gd's source scan of this function runs to
	# the next non-static func and checks the per-cell perimeter test there.
	var key: Array = _signature(campaign,combat.player_tier)
	if key != _cache_key:
		_cache = batched(primitives(campaign,CLIP_RADIUS))
		_caption = caption_for(campaign,combat.player_tier)
		_cache_key = key
	for primitive: Dictionary in _cache: draw_primitive(minimap,primitive)
	# The current node breathes: one ring, from the UI clock (still in a paused or captured frame).
	var phase: float = fposmod(float(app.get("elapsed_ui"))*0.8,1.0)
	minimap.draw_arc(CENTER,NODE_RADIUS+2.0+7.0*phase,0,TAU,24,Color(BLUE,0.55*(1.0-phase)),1.25,true)
	_draw_caption(_caption)

## Everything the minimap draws around `campaign.current_sector` except the caption and the
## pulse, clipped to `clip_radius` of CENTER (tests/map_view_test.gd samples every entry). Each
## entry is {kind: "disc"|"ring"|"line"|"poly", ...}: disc {at, r, color}; ring {at, r, width,
## color}; line {a, b, width, color}; poly {points, color}.
static func primitives(campaign: CampaignState, clip_radius: float) -> Array:
	var result: Array = []
	result.append({"kind": "disc", "at": CENTER, "r": clip_radius, "color": Color(0.02,0.025,0.035,0.9)})
	var model: MinimapModel = MinimapModel.build(campaign,false,WINDOW)
	var here: Vector2i = campaign.current_sector
	var inks: Dictionary = {}
	for map_cell: MinimapModel.Cell in model.cells:
		if map_cell.explored: inks[map_cell.coord] = MapScreen.sector_color(campaign,map_cell.coord,true)
	# Rails first, under the nodes: the blend of both ends' colours where both are explored, a
	# faint neutral otherwise. The HUD blends in linear light (HDR 2D), where a low alpha reads far
	# stronger than it says, so the neutrals are very low.
	for pair: Array in model.rail_segments():
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var ink: Color = Color(0.58,0.66,0.8,0.016)
		if inks.has(a) and inks.has(b): ink = Color((inks[a] as Color).lerp(inks[b],0.5),0.4)
		elif inks.has(a) or inks.has(b): ink = Color(0.62,0.7,0.86,0.06)
		_clipped_line(result,_at(a,here),_at(b,here),RAIL_WIDTH,ink,clip_radius)
	# The level edge: each outermost node contributes the stretch of boundary on its outward
	# side(s), half a cell out, so the edge is one clean line wherever it crosses the window.
	var half: float = 0.5
	for map_cell: MinimapModel.Cell in model.cells:
		var is_perimeter: bool = map_cell.in_bounds and CampaignState.ring(map_cell.coord) == model.radius
		if not is_perimeter: continue
		var c: Vector2 = Vector2(map_cell.coord)
		var edge_ink := Color(MUTED,0.5)
		if absi(map_cell.coord.x) == model.radius:
			var side: float = signf(c.x)*half
			_clipped_line(result,_at_f(c+Vector2(side,-half),here),_at_f(c+Vector2(side,half),here),EDGE_WIDTH,edge_ink,clip_radius)
		if absi(map_cell.coord.y) == model.radius:
			var side: float = signf(c.y)*half
			_clipped_line(result,_at_f(c+Vector2(-half,side),here),_at_f(c+Vector2(half,side),here),EDGE_WIDTH,edge_ink,clip_radius)
	# Nodes whose whole disc fits inside the circle.
	for map_cell: MinimapModel.Cell in model.cells:
		if not map_cell.in_bounds: continue
		var at: Vector2 = _at(map_cell.coord,here)
		var reach: float = at.distance_to(CENTER)
		if map_cell.current: continue # drawn last, on top
		if map_cell.explored:
			if reach+NODE_RADIUS+0.5 > clip_radius: continue
			result.append({"kind": "disc", "at": at, "r": NODE_RADIUS, "color": Color(inks[map_cell.coord],0.9*_fade(reach,clip_radius))})
		else:
			if reach+UNEXPLORED_RADIUS+0.5 > clip_radius: continue
			result.append({"kind": "ring", "at": at, "r": UNEXPLORED_RADIUS, "width": 1.0, "color": Color(0.55,0.62,0.74,0.2*_fade(reach,clip_radius))})
		if map_cell.is_boss and reach+NODE_RADIUS+4.5 <= clip_radius:
			result.append({"kind": "ring", "at": at, "r": NODE_RADIUS+3.5, "width": 1.25, "color": GOLD})
	result.append({"kind": "disc", "at": CENTER, "r": NODE_RADIUS+1.5, "color": BLUE})
	result.append({"kind": "disc", "at": CENTER, "r": 2.4, "color": Color(1,1,1,0.95)})
	# The boss bearing: a triangle on the rim, from the first tick, whatever the window shows.
	var delta: Vector2 = Vector2(model.boss_coord-here)
	if not delta.is_zero_approx():
		var dir: Vector2 = delta.normalized()
		var side := Vector2(-dir.y,dir.x)
		var tip: Vector2 = CENTER+dir*(clip_radius-2.5)
		var base: Vector2 = CENTER+dir*(clip_radius-11.0)
		result.append({"kind": "poly", "points": PackedVector2Array([tip,base+side*5.5,base-side*5.5]), "color": GOLD})
	# North: a small tick at the top of the rim (the map is always north-up).
	result.append({"kind": "line", "a": CENTER+Vector2(0,-clip_radius+2.0), "b": CENTER+Vector2(0,-clip_radius+7.0), "width": 1.5, "color": Color(MUTED,0.7)})
	result.append({"kind": "ring", "at": CENTER, "r": clip_radius-0.75, "width": 1.5, "color": Color(UiTokens.STROKE,1.0)})
	return result

## Replays one entry of `primitives` into `canvas`.
static func draw_primitive(canvas: CanvasItem, primitive: Dictionary) -> void:
	match str(primitive.kind):
		"disc": canvas.draw_circle(primitive.at,primitive.r,primitive.color,true,-1.0,true)
		"ring": canvas.draw_arc(primitive.at,primitive.r,0,TAU,maxi(12,int(primitive.r*1.5)),primitive.color,primitive.width,true)
		"line": canvas.draw_line(primitive.a,primitive.b,primitive.color,primitive.width,true)
		"lines": canvas.draw_multiline_colors(primitive.points,primitive.colors,primitive.width,true)
		"poly": canvas.draw_colored_polygon(primitive.points,primitive.color)

## The same list with every run of consecutive lines of one width merged into one "lines" entry
## {points, colors, width}: the ~200 rails of a window become one draw call per frame.
static func batched(source: Array) -> Array:
	var result: Array = []
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var width: float = -1.0
	for primitive: Dictionary in source + [{"kind": "end"}]:
		var joins: bool = primitive.kind == "line" and is_equal_approx(float(primitive.width),width)
		if not joins and not points.is_empty():
			# Packed arrays are values: the run is stored once it is complete.
			result.append({"kind": "lines", "points": points, "colors": colors, "width": width})
			points = PackedVector2Array()
			colors = PackedColorArray()
		if primitive.kind == "end": break
		if primitive.kind != "line":
			result.append(primitive)
			continue
		width = float(primitive.width)
		points.append(primitive.a)
		points.append(primitive.b)
		colors.append(primitive.color)
	return result

## How far out an entry reaches from CENTER (its own half width included).
static func reach_of(primitive: Dictionary) -> float:
	match str(primitive.kind):
		"disc": return (primitive.at as Vector2).distance_to(CENTER)+float(primitive.r)
		"ring": return (primitive.at as Vector2).distance_to(CENTER)+float(primitive.r)+float(primitive.width)*0.5
		"line": return maxf((primitive.a as Vector2).distance_to(CENTER),(primitive.b as Vector2).distance_to(CENTER))+float(primitive.width)*0.5
		"poly":
			var far: float = 0.0
			for point: Vector2 in primitive.points: far = maxf(far,point.distance_to(CENTER))
			return far
	return INF

static func _at(coord: Vector2i, here: Vector2i) -> Vector2:
	return CENTER+Vector2(coord-here)*CELL

static func _at_f(coord: Vector2, here: Vector2i) -> Vector2:
	return CENTER+(coord-Vector2(here))*CELL

## 1 inside FADE_FROM of the radius, easing to FADE_FLOOR at the rim.
static func _fade(reach: float, clip_radius: float) -> float:
	var t: float = clampf((reach-clip_radius*FADE_FROM)/(clip_radius*(1.0-FADE_FROM)),0.0,1.0)
	return lerpf(1.0,FADE_FLOOR,t*t)

## Appends the part of segment a-b inside the circle (radius less the half width), faded by how
## far out its middle lies; nothing when it misses the circle.
static func _clipped_line(into: Array, a: Vector2, b: Vector2, width: float, ink: Color, clip_radius: float) -> void:
	var limit: float = clip_radius-width*0.5-0.5
	var d: Vector2 = b-a
	var f: Vector2 = a-CENTER
	var qa: float = d.dot(d)
	if qa <= 0.0: return
	var qb: float = 2.0*f.dot(d)
	var qc: float = f.dot(f)-limit*limit
	var disc: float = qb*qb-4.0*qa*qc
	if disc <= 0.0: return
	var root: float = sqrt(disc)
	var t0: float = maxf(0.0,(-qb-root)/(2.0*qa))
	var t1: float = minf(1.0,(-qb+root)/(2.0*qa))
	if t1 <= t0: return
	var p0: Vector2 = a+d*t0
	var p1: Vector2 = a+d*t1
	var ink_faded := Color(ink,ink.a*_fade(((p0+p1)*0.5).distance_to(CENTER),clip_radius))
	into.append({"kind": "line", "a": p0, "b": p1, "width": width, "color": ink_faded})

## The caption's two parts: "RING r · Tt · " and "BOSS dir n" (the bearing MinimapModel reports).
static func caption_for(campaign: CampaignState, tier: int) -> Dictionary:
	var delta: Vector2i = campaign.boss_coord()-campaign.current_sector
	return {"lead": "RING %d · T%d · " % [CampaignState.ring(campaign.current_sector),tier], "boss": "BOSS %s %d" % [MinimapModel.direction_of(delta),CampaignState.ring(delta)]}

## "RING · T · BOSS" under the circle, centred, the boss part in gold; a long caption at a large
## text scale steps its size down until it fits the panel.
func _draw_caption(caption: Dictionary) -> void:
	if _font == null: _font = UiKit.font(UiTokens.FONT_MONO,UiTokens.WEIGHT_MONO,true)
	var lead: String = str(caption.get("lead",""))
	var boss: String = str(caption.get("boss",""))
	var px: int = UiLayout.text_px(12)
	var lead_w: float = _font.get_string_size(lead,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var boss_w: float = _font.get_string_size(boss,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	while px > 9 and lead_w+boss_w > SIZE.x-8.0:
		px -= 1
		lead_w = _font.get_string_size(lead,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
		boss_w = _font.get_string_size(boss,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var x: float = maxf(4.0,(SIZE.x-lead_w-boss_w)*0.5)
	var y: float = CENTER.y+CLIP_RADIUS+8.0+_font.get_ascent(px)
	minimap.draw_string(_font,Vector2(x,y),lead,HORIZONTAL_ALIGNMENT_LEFT,-1,px,Color(VisualStyle.TEXT,0.78))
	minimap.draw_string(_font,Vector2(x+lead_w,y),boss,HORIZONTAL_ALIGNMENT_LEFT,-1,px,GOLD)
