class_name SectorEdges
extends Node2D
## Exit labels share the world camera and never reveal unexplored neighbours.
## Modernization M3: the whole rim exits, so every arc (3 to 8 of them) gets
## one small label at its centre, set along the rim and never upside down.
var campaign: CampaignState
var world: CombatWorld
const LABEL_SIZE: int = 10
const MUTED: Color = Color("747e8c")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if campaign == null or not is_instance_valid(world) or world.arena.sealed: return
	for arc: Dictionary in world.arena.arcs:
		var direction: Vector2i = arc.dir
		var coord: Vector2i = campaign.current_sector+direction
		var known: bool = CampaignState.coord_key(coord) in campaign.discovered
		var title: String = "UNEXPLORED"
		var ink: Color = MUTED
		if known:
			var sector: Dictionary = campaign.sector_at(coord)
			title = "ORIGIN" if coord == Vector2i.ZERO else str(sector.element).to_upper()
			ink = MUTED if coord == Vector2i.ZERO else ShipCatalog.get_color(str(sector.element))
		var angle: float = float(arc.center)
		var unit: Vector2 = Vector2.from_angle(angle)
		var at: Vector2 = world.arena.center+unit*(world.arena.radius-CircularArena.ANCHOR_INSET)
		draw_arc(at,4,0,TAU,20,ink,1.5,true)
		# Tangent to the rim, flipped on the lower half so it always reads left to right.
		var turn: float = angle+PI*0.5
		if cos(turn) < -0.001: turn += PI
		draw_set_transform(at-unit*18.0,turn)
		var width: float = ThemeDB.fallback_font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_SIZE).x
		draw_string(ThemeDB.fallback_font,Vector2(-width/2,4),title,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_SIZE,ink)
		draw_set_transform(Vector2.ZERO)
