class_name ArenaBackdrop
extends Node2D
## Shared world camera: traces drift at 0.15x/0.35x while the rim stays fixed.
## Node geometry per spec v3 §11: a circular rim, up to four brighter membrane
## arcs where the sector has an exit, ~80 px of dead space beyond the rim.
var world: CombatWorld
var flashes: Array[Dictionary] = []
var dead_zone_clip_enabled: bool = true # Test-only knob for the dead-zone negative control.
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
	var player: Vector2 = world.player_position
	draw_rect(Rect2(player-Vector2(800,500),Vector2(1600,1000)),Color("050507"))
	var tint: Color = ShipCatalog.get_color(str(world.sector.get("element","fire")))
	var center: Vector2 = world.arena.center
	var dead_limit: float = world.arena.radius+GameTuning.ARENA_MARGIN
	for layer: int in range(2):
		var rate: float = 0.15 if layer==0 else 0.35
		var ink: Color = tint*0.10 if layer==0 else tint*0.13
		ink.a = 1.0
		for index: int in range(64):
			var seed_point := Vector2((index*239+layer*411)%1600,(index*173+layer*237)%1000)
			var local: Vector2 = seed_point-player*rate
			local = Vector2(fposmod(local.x,1600),fposmod(local.y,1000))-Vector2(800,500)
			var a: Vector2 = player+local
			var b: Vector2 = a+Vector2(18+(index%4)*11,0)
			var c: Vector2 = b+Vector2(13,13 if index%2==0 else -13)
			# Dead space beyond the rim shows no trace pixels: skip any segment that leaves it.
			if dead_zone_clip_enabled and (a.distance_to(center)>dead_limit or b.distance_to(center)>dead_limit or c.distance_to(center)>dead_limit): continue
			draw_line(a,b,ink,1.0,true)
			draw_line(b,c,ink,1.0,true)
			draw_circle(a,1.2,ink)
	draw_arc(center,world.arena.radius,0,TAU,64,WALL_COLOR,1.5,true)
	for direction: Vector2i in world.arena.exits:
		var mid: float = world.arena.direction_angle(direction)
		var half: float = world.arena.membrane_half_angle
		draw_arc(center,world.arena.radius,mid-half,mid+half,16,MEMBRANE_COLOR,3.5,true)
	for flash: Dictionary in flashes:
		var ink: Color = Color.WHITE
		ink.a = float(flash.time)/0.22
		draw_arc(flash.point,9,0,TAU,24,ink,2.6,true)
