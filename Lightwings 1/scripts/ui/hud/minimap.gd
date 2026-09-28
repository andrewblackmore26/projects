class_name Minimap
extends RefCounted
## The corner minimap (moved from main.gd's `_draw_minimap` in modernization M2): the explored
## neighbourhood of the current node, the sealed perimeter and the boss bearing, drawn into a
## clipped 186 px Control of the HUD. MinimapModel is the model; MapScreen colours the nodes.

const BLUE := VisualStyle.BLUE
const MUTED := VisualStyle.MUTED

var app: Node
var minimap: Control

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	minimap = Control.new()
	minimap.position = Vector2(1057,101)
	minimap.size = Vector2(186,186)
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

func _draw_minimap() -> void:
	var campaign: CampaignState = app.campaign
	var combat: CombatWorld = app.combat
	if campaign == null or not is_instance_valid(combat): return
	const CELL: float = 18.0
	var center := Vector2(93,93)
	var model: MinimapModel = MinimapModel.build(campaign)
	minimap.draw_rect(Rect2(Vector2(-5,-5),Vector2(196,217)),Color(0.02,0.025,0.035,0.94))
	# Review finding 6: the level boundary is a square Chebyshev ring around
	# the origin (§11's own "bounded disc" is `in_bounds`, a Chebyshev test -
	# see minimap_model.gd), not a Euclidean circle, and it does not move
	# with the player. The full map screen already draws this correctly as a
	# border on `ring == radius` (scripts/ui/screens/map_screen.gd); this matches
	# that model instead of an independent (and wrong) circle.
	for map_cell: MinimapModel.Cell in model.cells:
		var offset: Vector2i = map_cell.coord-campaign.current_sector
		if maxi(absi(offset.x),absi(offset.y)) > 4: continue # local window only; boss marker (below) is unwindowed
		if not map_cell.in_bounds: continue
		var at: Vector2 = center+Vector2(offset)*CELL
		var is_perimeter: bool = CampaignState.ring(map_cell.coord) == model.radius
		if not map_cell.explored:
			minimap.draw_circle(at,4.0,Color("13161d")) # unexplored: dark, discloses nothing
			if is_perimeter: minimap.draw_rect(Rect2(at-Vector2(CELL,CELL)*0.5,Vector2(CELL,CELL)),Color(MUTED,0.5),false,2.0)
			continue
		var ink: Color = MapScreen.sector_color(campaign,map_cell.coord,true)
		minimap.draw_circle(at,5.0,Color(ink,0.16))
		minimap.draw_arc(at,5.0,0,TAU,16,Color(ink,0.7),1.0,true)
		if is_perimeter: minimap.draw_rect(Rect2(at-Vector2(CELL,CELL)*0.5,Vector2(CELL,CELL)),Color(MUTED,0.5),false,2.0) # perimeter as a solid wall (spec §11), square not circular
	minimap.draw_circle(center,3,BLUE)
	# Boss marker + bearing, present from the first tick regardless of the
	# local window above (spec §11 M3: "always knows which way the boss is").
	var direction: Vector2 = Vector2(model.boss_coord-campaign.current_sector)
	if not direction.is_zero_approx():
		minimap.draw_circle(center+direction.normalized()*87,3,ShipCatalog.get_color(str(campaign.sector_at(model.boss_coord).get("element",""))))
	minimap.draw_string(ThemeDB.fallback_font,Vector2(3,203),"RING %d · T%d · BOSS %s %d" % [CampaignState.ring(campaign.current_sector),combat.player_tier,model.bearing_direction,model.bearing_distance],HORIZONTAL_ALIGNMENT_LEFT,180,12,MUTED)
