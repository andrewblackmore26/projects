class_name AIPortrait
extends Control

var element: String = "companion"

func _draw() -> void:
	var center: Vector2 = size*0.5
	var ink: Color = ShipCatalog.get_color(element) if element != "companion" else Color("9aa3b3")
	draw_style_box(frame(ink),Rect2(Vector2.ZERO,size))
	var radius: float = minf(size.x,size.y)*0.32
	draw_circle(center,radius,Color.BLACK if element == "void" else Color(ink.r*0.08,ink.g*0.08,ink.b*0.08))
	draw_arc(center,radius,0,TAU,64,ink,1.5,true)
	var count: int = 5 if element == "corruption" else 4
	for index: int in range(count):
		var angle: float = TAU*index/count-PI/2
		var at: Vector2 = center+Vector2.from_angle(angle)*radius*0.72
		var part_radius: float = radius*(0.20 if element == "lightning" else 0.29)
		draw_line(center,at,Color(ink,0.65),2.0,true)
		draw_circle(at,part_radius,Color.BLACK)
		draw_arc(at,part_radius,0,TAU,32,ink,1.5,true)
	if element in ["plasma","void"]:
		draw_arc(center,radius*0.53,0,TAU,48,ink.lightened(0.3),1.5,true)
		draw_arc(center,radius*1.16,0.2,TAU-0.2,64,Color(ink,0.5),1.0,true)
	draw_circle(center,3.0,Color.WHITE if element == "companion" else ink)

static func frame(ink: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b0e15")
	style.border_color = Color(ink,0.3)
	style.set_border_width_all(1)
	return style
