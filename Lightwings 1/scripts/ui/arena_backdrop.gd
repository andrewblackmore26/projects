class_name ArenaBackdrop
extends Node2D
## Shared world camera: traces drift at 0.15x/0.35x while arena edges stay fixed.
var world: CombatWorld
var flashes: Array[Dictionary] = []
var wall_segments: Array[PackedVector2Array] = []

func _ready() -> void:
	z_index = -20
	world.boundary_contact.connect(_contact)
	_build_wall()

func _contact(point: Vector2) -> void:
	if flashes.size() < 12: flashes.append({"point":point,"time":0.22})

func _process(delta: float) -> void:
	for index: int in range(flashes.size()-1,-1,-1):
		flashes[index].time = float(flashes[index].time)-delta
		if float(flashes[index].time)<=0: flashes.remove_at(index)
	queue_redraw()

func _build_wall() -> void:
	wall_segments.clear()
	var outline: PackedVector2Array = world.arena.outline(18)
	var center: Vector2 = world.bounds.get_center()
	var gap: float = world.arena.opening_half_width
	for index: int in range(outline.size()-1):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[index+1]
		if is_equal_approx(a.x,b.x) and minf(a.y,b.y)<center.y-gap and maxf(a.y,b.y)>center.y+gap:
			var low: Vector2 = a if a.y<b.y else b
			var high: Vector2 = b if a.y<b.y else a
			wall_segments.append(PackedVector2Array([low,Vector2(a.x,center.y-gap)]))
			wall_segments.append(PackedVector2Array([Vector2(a.x,center.y+gap),high]))
		elif is_equal_approx(a.y,b.y) and minf(a.x,b.x)<center.x-gap and maxf(a.x,b.x)>center.x+gap:
			var low: Vector2 = a if a.x<b.x else b
			var high: Vector2 = b if a.x<b.x else a
			wall_segments.append(PackedVector2Array([low,Vector2(center.x-gap,a.y)]))
			wall_segments.append(PackedVector2Array([Vector2(center.x+gap,a.y),high]))
		else: wall_segments.append(PackedVector2Array([a,b]))

func _draw() -> void:
	if not is_instance_valid(world): return
	var player: Vector2 = world.player_position
	draw_rect(Rect2(player-Vector2(800,500),Vector2(1600,1000)),Color("050507"))
	var tint: Color = ShipCatalog.get_color(str(world.sector.get("element","fire")))
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
			draw_line(a,b,ink,1.0,true)
			draw_line(b,c,ink,1.0,true)
			draw_circle(a,1.2,ink)
	for segment: PackedVector2Array in wall_segments:
		draw_polyline(segment,Color("747e8c"),1.5,true)
	for flash: Dictionary in flashes:
		var ink: Color = Color.WHITE
		ink.a = float(flash.time)/0.22
		draw_arc(flash.point,9,0,TAU,24,ink,2.6,true)
