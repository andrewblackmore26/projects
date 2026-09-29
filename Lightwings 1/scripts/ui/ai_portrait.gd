class_name AIPortrait
extends Control
## The speaker's portrait in the dialogue box. M19 review: a round badge (a disc on a thin ring in
## the speaker's colour), not a square frame, so it reads as a voice, not a window.

var element: String = "companion"

func _draw() -> void:
	var center: Vector2 = size*0.5
	var ink: Color = ShipCatalog.get_color(element) if element != "companion" else Color("9aa3b3")
	var outer: float = minf(size.x,size.y)*0.5
	draw_circle(center,outer,UiTokens.GLASS_RAISED,true,-1.0,true)
	draw_arc(center,outer-0.75,0,TAU,64,Color(ink,0.45),1.5,true)
	var radius: float = outer*0.64
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
