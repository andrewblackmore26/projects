class_name ArenaBackdrop
extends Node2D
## Shared world camera: traces drift at 0.15x/0.35x while the rim stays fixed.
## Node geometry per spec v3 §11 and modernization M3: a circular rim that is
## ALL exit (every arc leads to the nearest neighbour), ~80 px of dead space
## beyond it. Calm at rest; while the player presses into it, the predicted
## destination arc brightens around the contact point.
var world: CombatWorld
var flashes: Array[Dictionary] = []
var dead_zone_clip_enabled: bool = true # Test-only knob for the dead-zone negative control.
var canvas_scale_override: float = -1.0 # Test-only knob: forces canvas_scale to a fixed value instead of reading the live transform.
## Test-only knob for the rim-render negative controls: added to the highlight's centre angle
## (PI/2 puts it on the wrong arc); `highlight_enabled = false` removes it.
var highlight_offset: float = 0.0
var highlight_enabled: bool = true
const RIM_COLOR: Color = Color("747e8c")
const HIGHLIGHT_COLOR: Color = Color("dff1ff")
const RIM_SEGMENTS: int = 240
## Half-width (radians) of the press highlight's cosine falloff around the contact angle.
const HIGHLIGHT_HALF_WIDTH: float = 0.55
## The inner of the rim's two thin strokes (lessons: a thick bright ring blooms inward).
const INNER_STROKE_INSET: float = 4.0

func _ready() -> void:
	z_index = -20
	world.boundary_contact.connect(_contact)

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
	draw_rect(Rect2(player-Vector2(800,500),Vector2(1600,1000)),VisualStyle.BG)
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
			var seed_point := Vector2((index*239+layer*411)%1600,(index*173+layer*237)%1000)
			var local: Vector2 = seed_point-player*rate
			local = Vector2(fposmod(local.x,1600),fposmod(local.y,1000))-Vector2(800,500)
			var a: Vector2 = player+local
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
	if world.warp_phase in [CombatWorld.WARP_ZOOM_IN,CombatWorld.WARP_TRAVEL,CombatWorld.WARP_ARRIVAL]: _draw_streaks(player,canvas_scale)

## The rim: one closed polyline per stroke, coloured per vertex. Push (spec
## §12: "the arc brightens as push depth builds"): only the predicted
## destination arc, with a cosine falloff centred on the contact angle and cut
## off at that arc's own bisectors, so the glow says exactly where you will go.
func _draw_rim(center: Vector2, canvas_scale: float) -> void:
	var radius: float = world.arena.radius
	var weight: PackedFloat32Array = rim_highlight_weights()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_ink := PackedColorArray()
	var inner_ink := PackedColorArray()
	for index: int in range(RIM_SEGMENTS+1):
		var unit: Vector2 = Vector2.from_angle(TAU*index/RIM_SEGMENTS)
		var w: float = weight[index % RIM_SEGMENTS]
		outer.append(center+unit*radius)
		inner.append(center+unit*(radius-INNER_STROKE_INSET))
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

## Warp streaks (spec §12: "background traces stretch into radial streaks
## running from a vanishing point in the travel direction... length ramps up,
## holds, then collapses"). No motion blur - hard-edged lines, ramped by the
## SIM's own warp_progress, never a local clock.
func _draw_streaks(player: Vector2, canvas_scale: float) -> void:
	var ramp: float = 1.0
	if world.warp_phase==CombatWorld.WARP_ZOOM_IN: ramp=world.warp_progress
	elif world.warp_phase==CombatWorld.WARP_ARRIVAL: ramp=1.0-world.warp_progress
	var length: float = 260.0*ramp
	if length<=1.0: return
	var vanishing: Vector2 = player+Vector2(world.warp_direction).normalized()*640.0
	var ink: Color = Color(0.82,0.9,1.0,0.4*ramp)
	for index: int in range(28):
		var angle: float = TAU*index/28.0
		var base: Vector2 = player+Vector2.from_angle(angle)*36.0
		var dir: Vector2 = (vanishing-base).normalized() if base.distance_squared_to(vanishing)>1.0 else Vector2(world.warp_direction)
		draw_line(base,base+dir*length,ink,1.5/canvas_scale,true)
