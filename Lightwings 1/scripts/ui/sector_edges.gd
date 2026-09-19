class_name SectorEdges
extends Node2D
## Exit labels share the world camera and never reveal unexplored neighbours.
var campaign: CampaignState
var world: CombatWorld

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if campaign == null or not is_instance_valid(world): return
	var bounds: Rect2 = world.bounds
	var anchors: Array[Vector2] = [Vector2(bounds.get_center().x,bounds.position.y+26),Vector2(bounds.end.x-26,bounds.get_center().y),Vector2(bounds.get_center().x,bounds.end.y-26),Vector2(bounds.position.x+26,bounds.get_center().y)]
	var directions: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for i: int in range(4):
		var coord: Vector2i = campaign.current_sector+directions[i]
		var known: bool = CampaignState.coord_key(coord) in campaign.discovered
		var title: String = "UNEXPLORED"
		var ink: Color = Color("747e8c")
		if known:
			var sector: Dictionary = campaign.sector_at(coord)
			title = "ORIGIN" if coord == Vector2i.ZERO else str(sector.element).to_upper()
			ink = Color("747e8c") if coord == Vector2i.ZERO else ShipCatalog.get_color(str(sector.element))
		var at: Vector2 = anchors[i]
		draw_arc(at,6,0,TAU,24,ink,1.5,true)
		var label_at: Vector2 = at-Vector2(directions[i])*22.0
		if directions[i].x != 0: draw_set_transform(label_at,PI/2 if directions[i].x>0 else -PI/2)
		else: draw_set_transform(label_at)
		var width: float = ThemeDB.fallback_font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
		draw_string(ThemeDB.fallback_font,Vector2(-width/2,4),title,HORIZONTAL_ALIGNMENT_LEFT,-1,10,ink)
		draw_set_transform(Vector2.ZERO)
