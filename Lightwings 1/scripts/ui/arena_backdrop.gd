class_name ArenaBackdrop
extends Node2D
## Shared world camera: traces drift at 0.15x/0.35x while the rim stays fixed.
## Node geometry per spec v3 §11: a circular rim, up to four brighter membrane
## arcs where the sector has an exit, ~80 px of dead space beyond the rim.
var world: CombatWorld
var flashes: Array[Dictionary] = []
var dead_zone_clip_enabled: bool = true # Test-only knob for the dead-zone negative control.
var canvas_scale_override: float = -1.0 # Test-only knob: forces canvas_scale to a fixed value instead of reading the live transform.
const WALL_COLOR: Color = Color("747e8c")
const MEMBRANE_COLOR: Color = Color("bfe3ff")

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
	draw_rect(Rect2(player-Vector2(800,500),Vector2(1600,1000)),Color("050507"))
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
		var intensity: float = clampf((0.10 if layer==0 else 0.13)+float(ring)*0.0025,0.10,0.15)
		var ink: Color = tint*intensity
		ink.a = 1.0
		var count: int = clampi(64+ring*6,64,160)
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
	draw_arc(center,world.arena.radius,0,TAU,64,WALL_COLOR,1.5/canvas_scale,true)
	for direction: Vector2i in world.arena.exits:
		var mid: float = world.arena.direction_angle(direction)
		var half: float = world.arena.membrane_half_angle
		# Push (spec §12): "the arc brightens as push depth builds" - only the
		# arc the player is actually pressing into.
		var brighten: float = world.warp_progress if world.warp_phase==CombatWorld.WARP_PUSH and direction==world.warp_direction else 0.0
		draw_arc(center,world.arena.radius,mid-half,mid+half,16,MEMBRANE_COLOR.lerp(Color.WHITE,brighten*0.6),(3.5+brighten*3.5)/canvas_scale,true)
	for flash: Dictionary in flashes:
		var ink: Color = Color.WHITE
		ink.a = float(flash.time)/0.22
		draw_arc(flash.point,9,0,TAU,24,ink,2.6/canvas_scale,true)
	if world.warp_phase in [CombatWorld.WARP_ZOOM_IN,CombatWorld.WARP_TRAVEL,CombatWorld.WARP_ARRIVAL]: _draw_streaks(player,canvas_scale)

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
