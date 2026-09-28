class_name ArenaBackdrop
extends Node2D
## Shared world camera: traces drift at 0.15x/0.35x while the rim stays fixed.
## Node geometry per spec v3 §11 and modernization M3: a circular rim that is
## ALL exit (every arc leads to the nearest neighbour), ~80 px of dead space
## beyond it. Calm at rest; while the player presses into it, the predicted
## destination arc brightens around the contact point.
##
## Modernization M9, the warp's look (camera/movement spec §7), every frame of it read from the
## sim's clock (`sim_q` and the warp's deadlines), never a local one:
## - PUSH: the rim bulges outward at the contact angle, up to BULGE_PX with the press depth; a
##   press let go springs back with a damped wobble, and the commit recoils the same way, harder;
## - BREAK: the world dims to ~DIM_ALPHA behind the ship (the player, its trail and the streaks
##   stay lit);
## - TRAVEL: streaks radiate from a small ring round the ship in EVERY direction, 0 -> STREAK_PX
##   over STREAK_GROW_S, then hold; each is a stepped taper, thick at the ship;
## - ARRIVAL: the streaks contract, staggered, while the dim lifts;
## - reduced warp: no bulge, no streaks - one cross-fade through the background, with the node
##   swap hidden at its opaque midpoint.
## Streaks and dim live on `warp_layer`, which the game mounts ABOVE the world and below the trails
## (`mount_warp_layer`); left alone it stays a child of this node.
var world: CombatWorld
var flashes: Array[Dictionary] = []
var dead_zone_clip_enabled: bool = true # Test-only knob for the dead-zone negative control.
var canvas_scale_override: float = -1.0 # Test-only knob: forces canvas_scale to a fixed value instead of reading the live transform.
## Test-only knob for the rim-render negative controls: added to the highlight's centre angle
## (PI/2 puts it on the wrong arc); `highlight_enabled = false` removes it.
var highlight_offset: float = 0.0
var highlight_enabled: bool = true
## Test-only knobs for warp_render_test's controls: the pre-M9 streaks (every streak aimed at one
## vanishing point ahead), and no dim.
var streak_vanishing: bool = false
var dim_enabled: bool = true
var warp_layer: WarpLayer
const RIM_COLOR: Color = Color("747e8c")
const HIGHLIGHT_COLOR: Color = Color("dff1ff")
const RIM_SEGMENTS: int = 240
## Half-width (radians) of the press highlight's cosine falloff around the contact angle.
const HIGHLIGHT_HALF_WIDTH: float = 0.55
## The inner of the rim's two thin strokes (lessons: a thick bright ring blooms inward).
const INNER_STROKE_INSET: float = 4.0
## The membrane: peak outward bulge at full press depth, and the half-width of its cos^2 dome.
const BULGE_PX: float = 40.0
const BULGE_HALF_WIDTH: float = 0.17
## Damped spring the bulge rings with after a release ([decay tau s, period s]) and at the commit.
const RELEASE_SPRING: Vector2 = Vector2(0.09, 0.18)
const RECOIL_SPRING: Vector2 = Vector2(0.06, 0.11)
const SPRING_SECONDS: float = 0.6
const STREAK_COUNT: int = 44
const STREAK_PX: float = 400.0
const STREAK_GROW_S: float = 0.12
const STREAK_RING_PX: float = 30.0
## ARRIVAL: each streak starts contracting up to STREAK_STAGGER_S late and takes STREAK_SHRINK_S.
const STREAK_STAGGER_S: float = 0.09
const STREAK_SHRINK_S: float = 0.09
## Width steps of a streak from the ship outward (the trail renderer's stepped taper, shorter).
const STREAK_STEPS: PackedFloat32Array = [1.0, 0.72, 0.5, 0.32, 0.18]
const STREAK_COLOR: Color = Color(0.86, 0.94, 1.0)
const STREAK_RUSH_COLOR: Color = Color(1.6, 1.8, 2.0)
const STREAK_RUSH_HZ: float = 4.0
## BG drawn over the world at this alpha during the warp. HDR 2D blends in linear light, so 0.8
## leaves ~20 % of the world's linear light (see warp_render_test for the measured ratio).
const DIM_ALPHA: float = 0.8

## The warp's overlay canvas item. Draws through the backdrop so all warp drawing lives here.
class WarpLayer extends Node2D:
	var backdrop: ArenaBackdrop
	func _process(_delta: float) -> void: queue_redraw()
	func _draw() -> void:
		if is_instance_valid(backdrop): backdrop._draw_warp(self)

func _init() -> void:
	warp_layer = WarpLayer.new()
	warp_layer.name = "WarpLayer"
	warp_layer.backdrop = self
	warp_layer.z_index = 25

func _ready() -> void:
	z_index = -20
	world.boundary_contact.connect(_contact)
	if warp_layer.get_parent() == null: add_child(warp_layer)

## Moves the warp overlay into `parent` (the compositor's foreground): above the background stage
## (world, rim, ordinary hulls: z 0) and below the trails (5), void hulls (20) and the player (30).
func mount_warp_layer(parent: Node2D) -> void:
	warp_layer.reparent(parent, false)
	warp_layer.z_index = 3

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(warp_layer) and warp_layer.get_parent() != self:
		warp_layer.queue_free()

## The parallax traces repeat on this world-px tile around the player (M6: repeated as often as the
## visible rect needs, `trace_repeats`).
const TRACE_TILE: Vector2i = Vector2i(1600,1000)

## M6: the world rect this node's viewport shows (its canvas transform inverted over the visible rect).
func visible_world_rect() -> Rect2:
	var inverse: Transform2D = get_canvas_transform().affine_inverse()
	var screen: Rect2 = get_viewport_rect()
	var result := Rect2(inverse*screen.position,Vector2.ZERO)
	for corner: Vector2 in [Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
		result = result.expand(inverse*corner)
	return result

## Tile offsets whose copy of the trace tile (centred on `player`) meets `view`; ZERO first.
static func trace_repeats(player: Vector2, view: Rect2) -> Array[Vector2]:
	var tile := Vector2(TRACE_TILE)
	var result: Array[Vector2] = [Vector2.ZERO]
	for kx: int in range(-2,3):
		for ky: int in range(-2,3):
			if kx == 0 and ky == 0: continue
			var shift := Vector2(kx*tile.x,ky*tile.y)
			if Rect2(player-tile*0.5+shift,tile).intersects(view.grow(64.0)): result.append(shift)
	return result

func _contact(point: Vector2) -> void:
	if flashes.size() < 12: flashes.append({"point":point,"time":0.22})

func _process(delta: float) -> void:
	for index: int in range(flashes.size()-1,-1,-1):
		flashes[index].time = float(flashes[index].time)-delta
		if float(flashes[index].time)<=0: flashes.remove_at(index)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(world): return
	# Constant in screen space at any zoom (spec §17/§23), including during
	# the warp's 1.30x push - the same technique `ship_renderer.gd` uses.
	var canvas_scale: float = canvas_scale_override if canvas_scale_override>0.0 else maxf(0.01,get_global_transform_with_canvas().get_scale().abs().x)
	var player: Vector2 = world.player_position
	# M6: the backing and the trace tiling cover the VISIBLE world rect, whatever the window's
	# aspect (a 21:9 view at the 0.93 zoom-out is ~2040 world px wide, past the 1600 px tile).
	var view: Rect2 = visible_world_rect()
	var tile := Vector2(TRACE_TILE)
	draw_rect(Rect2(player-tile*0.5,tile).merge(view.grow(maxf(view.size.x,view.size.y)*0.1)),VisualStyle.BG)
	var repeats: Array[Vector2] = trace_repeats(player,view)
	var tint: Color = ShipCatalog.get_color(str(world.sector.get("element","fire")))
	var center: Vector2 = world.arena.center
	var dead_limit: float = world.arena.radius+GameTuning.ARENA_MARGIN
	for layer: int in range(2):
		var rate: float = 0.15 if layer==0 else 0.35
		# Spec §20: "trace density and hue intensity rise with ring index, so
		# the background tells you how deep you are." Both stay clamped below
		# the spec's own 10-15% ceiling ("always below the bloom threshold") -
		# only the ring's CONTRIBUTION within that band grows, never past it.
		var ring: int = int(world.sector.get("ring",0))
		var intensity: float = clampf((0.035 if layer==0 else 0.05)+float(ring)*0.001,0.035,0.065)
		var ink: Color = VisualStyle.BG.lerp(tint, intensity)
		var count: int = clampi(14+ring*2,14,38)
		for index: int in range(count):
			var seed_point := Vector2((index*239+layer*411)%TRACE_TILE.x,(index*173+layer*237)%TRACE_TILE.y)
			var local: Vector2 = seed_point-player*rate
			local = Vector2(fposmod(local.x,tile.x),fposmod(local.y,tile.y))-tile*0.5
			for repeat: Vector2 in repeats:
				var a: Vector2 = player+local+repeat
				if repeat != Vector2.ZERO and not view.grow(64.0).has_point(a): continue
				var b: Vector2 = a+Vector2(18+(index%4)*11,0)
				var c: Vector2 = b+Vector2(13,13 if index%2==0 else -13)
				# Dead space beyond the rim shows no trace pixels: skip any segment that leaves it.
				if dead_zone_clip_enabled and (a.distance_to(center)>dead_limit or b.distance_to(center)>dead_limit or c.distance_to(center)>dead_limit): continue
				draw_line(a,b,ink,1.0/canvas_scale,true)
				draw_line(b,c,ink,1.0/canvas_scale,true)
				draw_circle(a,1.2/canvas_scale,ink)
	_draw_rim(center,canvas_scale)
	for flash: Dictionary in flashes:
		var ink: Color = Color.WHITE
		ink.a = float(flash.time)/0.22
		draw_arc(flash.point,9,0,TAU,24,ink,2.6/canvas_scale,true)

## The rim: one closed polyline per stroke, coloured per vertex. Push (spec
## §12: "the arc brightens as push depth builds"): only the predicted
## destination arc, with a cosine falloff centred on the contact angle and cut
## off at that arc's own bisectors, so the glow says exactly where you will go.
## M9: every vertex is pushed out by the membrane's bulge (`rim_offsets`).
func _draw_rim(center: Vector2, canvas_scale: float) -> void:
	var radius: float = world.arena.radius
	var weight: PackedFloat32Array = rim_highlight_weights()
	var bulge: PackedFloat32Array = rim_offsets()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_ink := PackedColorArray()
	var inner_ink := PackedColorArray()
	for index: int in range(RIM_SEGMENTS+1):
		var unit: Vector2 = Vector2.from_angle(TAU*index/RIM_SEGMENTS)
		var w: float = weight[index % RIM_SEGMENTS]
		var r: float = radius+bulge[index % RIM_SEGMENTS]
		outer.append(center+unit*r)
		inner.append(center+unit*(r-INNER_STROKE_INSET))
		outer_ink.append(RIM_COLOR.lerp(HIGHLIGHT_COLOR,w))
		var faint: Color = RIM_COLOR.lerp(HIGHLIGHT_COLOR,w*0.8)
		faint.a = 0.35+0.55*w
		inner_ink.append(faint)
	draw_polyline_colors(outer,outer_ink,1.5/canvas_scale,true)
	draw_polyline_colors(inner,inner_ink,1.0/canvas_scale,true)
	# The lit stretch alone gets a slightly heavier (still thin) outer stroke on top, fading
	# with the weight, so a press reads at a glance without the whole ring thickening.
	var lit := PackedVector2Array()
	var lit_ink := PackedColorArray()
	for index: int in range(RIM_SEGMENTS+1):
		var w: float = weight[index % RIM_SEGMENTS]
		if w <= 0.0:
			if lit.size() >= 2: draw_polyline_colors(lit,lit_ink,2.4/canvas_scale,true)
			lit.clear()
			lit_ink.clear()
			continue
		lit.append(outer[index])
		var ink: Color = HIGHLIGHT_COLOR
		ink.a = w
		lit_ink.append(ink)
	if lit.size() >= 2: draw_polyline_colors(lit,lit_ink,2.4/canvas_scale,true)

## Per-vertex highlight weight in [0, 1] for the rim's RIM_SEGMENTS vertices (vertex i at angle
## TAU*i/RIM_SEGMENTS). Pure given the world, so a test can read it without pixels.
func rim_highlight_weights() -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(RIM_SEGMENTS)
	if not highlight_enabled or world.warp_phase!=CombatWorld.WARP_PUSH or world.warp_progress<=0.0: return weights
	var arc: Dictionary = world.arena.arc_for(world.warp_direction)
	if arc.is_empty(): return weights
	var contact: float = (Vector2(world.player.pos)-world.arena.center).angle()+highlight_offset
	var strength: float = 0.35+0.65*world.warp_progress
	for index: int in range(RIM_SEGMENTS):
		var angle: float = TAU*index/RIM_SEGMENTS
		# Bring the vertex into the arc's own [from, from + TAU) window before the bounds test.
		var inside: float = float(arc.from)+fposmod(angle-float(arc.from),TAU)
		if inside>float(arc.to): continue
		var off: float = absf(angle_difference(contact,angle))
		if off>=HIGHLIGHT_HALF_WIDTH: continue
		weights[index] = strength*cos(off/HIGHLIGHT_HALF_WIDTH*PI*0.5)
	return weights

## The membrane's outward displacement (px, negative = inward) at the contact angle right now.
## Pressing: BULGE_PX x depth. Released before commit: that depth ringing out on RELEASE_SPRING.
## Committed: a full-depth recoil on the stiffer RECOIL_SPRING (it snaps back past rest as the ship
## breaks through). Reduced warp: always 0.
func bulge_px() -> float:
	if world.warp_reduced: return 0.0
	var phase: int = world.warp_phase
	if phase==CombatWorld.WARP_PUSH and world.warp_filling: return BULGE_PX*world.warp_progress
	if phase==CombatWorld.WARP_NONE or phase==CombatWorld.WARP_PUSH:
		# The ship is still at the rim after a release, so the inward swing is kept shallow (it
		# would otherwise cut through the hull); after a commit the ship has gone and it may not.
		var ring: float = _spring(float(world.sim_q-world.warp_release_q)/CombatWorld.SIM_Q_PER_SECOND,RELEASE_SPRING)
		return BULGE_PX*world.warp_release_depth*(ring if ring>=0.0 else ring*0.35)
	return BULGE_PX*_spring(float(world.sim_q-world.warp_commit_q)/CombatWorld.SIM_Q_PER_SECOND,RECOIL_SPRING)

static func _spring(t: float, spring: Vector2) -> float:
	if t<0.0 or t>=SPRING_SECONDS: return 0.0
	return exp(-t/spring.x)*cos(TAU*t/spring.y)

## Per-vertex outward offset of the rim (a cos^2 dome of `bulge_px()` centred on the contact angle).
## Pure given the world, like `rim_highlight_weights`.
func rim_offsets() -> PackedFloat32Array:
	var offsets := PackedFloat32Array()
	offsets.resize(RIM_SEGMENTS)
	var amount: float = bulge_px()
	if absf(amount)<0.01: return offsets
	for index: int in range(RIM_SEGMENTS):
		offsets[index] = amount*_dome(absf(angle_difference(world.warp_contact_angle,TAU*index/RIM_SEGMENTS)))
	return offsets

## The rim's radius offset at an arbitrary angle (tests sample the bulged rim with it).
func rim_offset_at(angle: float) -> float:
	return bulge_px()*_dome(absf(angle_difference(world.warp_contact_angle,angle)))

static func _dome(off: float) -> float:
	if off>=BULGE_HALF_WIDTH: return 0.0
	var c: float = cos(off/BULGE_HALF_WIDTH*PI*0.5)
	return c*c

## 0..1: how far the world is dimmed behind the ship. Full warp: ramps in over BREAK, holds through
## TRAVEL, lifts over ARRIVAL. Reduced warp: a cross-fade that is opaque at the FADE's midpoint
## (where the ship jumps nodes) and clear again when it ends.
func dim_amount() -> float:
	if not dim_enabled: return 0.0
	var p: float = world.warp_progress
	match world.warp_phase:
		CombatWorld.WARP_BREAK: return p
		CombatWorld.WARP_TRAVEL: return 1.0
		CombatWorld.WARP_ARRIVAL: return 0.0 if world.warp_reduced else 1.0-p*p*(3.0-2.0*p)
		CombatWorld.WARP_FADE: return 1.0-absf(2.0*p-1.0)
	return 0.0

## Seconds since the streaks began (TRAVEL's start), or -1 when there are none.
func _streak_clock() -> float:
	if world.warp_reduced: return -1.0
	if world.warp_phase==CombatWorld.WARP_TRAVEL: return float(world.sim_q-world.warp_phase_start_q)/CombatWorld.SIM_Q_PER_SECOND
	if world.warp_phase==CombatWorld.WARP_ARRIVAL: return GameTuning.feel("warp.warp_s")+float(world.sim_q-world.warp_phase_start_q)/CombatWorld.SIM_Q_PER_SECOND
	return -1.0

## Streaks as [inner, outer] world-point pairs (empty when there are none). The ring of origins
## and the per-streak variety come from a fixed hash of the index, not an RNG.
func streak_segments() -> PackedVector2Array:
	var result := PackedVector2Array()
	var t: float = _streak_clock()
	if t<0.0: return result
	var ship: Vector2 = world.player_position
	var grow: float = clampf(t/STREAK_GROW_S,0.0,1.0)
	grow = 1.0-(1.0-grow)*(1.0-grow) # ease out: the burst is fastest at the start
	var arrived: float = t-GameTuning.feel("warp.warp_s") # >= 0 once ARRIVAL has begun
	var heading: Vector2 = world.warp_heading if world.warp_heading.length_squared()>0.5 else Vector2.RIGHT
	for index: int in range(STREAK_COUNT):
		var h1: float = _hash(index,1)
		var h2: float = _hash(index,2)
		var angle: float = TAU*(float(index)+h1-0.5)/STREAK_COUNT
		var direction: Vector2 = Vector2.from_angle(angle)
		var origin: Vector2 = ship+direction*STREAK_RING_PX*(0.85+0.3*h2)
		if streak_vanishing: direction = (ship+heading*640.0-origin).normalized()
		var length: float = STREAK_PX*(0.62+0.38*_hash(index,3))*grow
		if world.warp_phase==CombatWorld.WARP_ARRIVAL:
			var shrink: float = clampf((arrived-STREAK_STAGGER_S*_hash(index,4))/STREAK_SHRINK_S,0.0,1.0)
			length *= 1.0-shrink*shrink*(3.0-2.0*shrink)
		if length<=1.0: continue
		result.append(origin)
		result.append(origin+direction*length)
	return result

static func _hash(index: int, salt: int) -> float:
	return fposmod(sin(float(index)*12.9898+float(salt)*78.233)*43758.5453,1.0)

## The warp layer's picture: the dim first, then the streaks over it.
func _draw_warp(layer: Node2D) -> void:
	if not is_instance_valid(world): return
	var canvas_scale: float = canvas_scale_override if canvas_scale_override>0.0 else maxf(0.01,layer.get_global_transform_with_canvas().get_scale().abs().x)
	var ship: Vector2 = world.player_position
	var dim: float = dim_amount()
	if dim>0.001:
		var shade: Color = VisualStyle.BG
		shade.a = dim*(1.0 if world.warp_reduced else DIM_ALPHA)
		layer.draw_rect(Rect2(ship-Vector2(2400,1600),Vector2(4800,3200)),shade)
	var segments: PackedVector2Array = streak_segments()
	var steps: int = STREAK_STEPS.size()
	var clock: float = _streak_clock()
	for pair: int in range(0,segments.size(),2):
		var from: Vector2 = segments[pair]
		var span: Vector2 = segments[pair+1]-from
		var base: float = 1.0+1.2*_hash(pair,5)
		for step: int in range(steps):
			var ink: Color = STREAK_COLOR
			ink.a = 0.75*(1.0-float(step)/steps)
			layer.draw_line(from+span*float(step)/steps,from+span*float(step+1)/steps,ink,base*STREAK_STEPS[step]/canvas_scale,true)
		# The rush: a short over-bright head runs out along every streak, staggered, so the burst
		# flows outward instead of standing still (HDR: it reaches the glow).
		var head: float = fposmod(clock*STREAK_RUSH_HZ+_hash(pair,6),1.0)
		var rush: Color = STREAK_RUSH_COLOR
		rush.a = 0.9*(1.0-head)
		layer.draw_line(from+span*head,from+span*minf(1.0,head+0.14),rush,base*1.4/canvas_scale,true)
