class_name MapScreen
extends UiScreen
## The full map screen (spec §11). MinimapModel is the single source of
## truth: the whole level fits on screen at every level radius (R up to 12
## -> a 25x25 grid), so there is no panning, no waypoint picker, no JUMP.
## The node descriptions and colours are static here because the corner minimap
## (scripts/ui/hud/minimap.gd) and main.gd's forwarders use them too.

var map_detail: Label
var map_selected: Vector2i

func build() -> void:
	var campaign: CampaignState = app.campaign
	UiKit.label(host,"THE AI-VERSE",Vector2(85,20),Vector2(620,40),28,WHITE)
	var model: MinimapModel = MinimapModel.build(campaign)
	UiKit.label(host,"Boss bearing: %s · %d nodes" % [model.bearing_direction,model.bearing_distance],Vector2(87,58),Vector2(1000,26),16,GOLD)
	var side: int = model.grid_size()
	var area: float = 600.0
	var cell: float = area/float(side)
	var origin := Vector2(80,92)
	for map_cell: MinimapModel.Cell in model.cells:
		var local: Vector2i = map_cell.coord+Vector2i(model.radius,model.radius)
		var at: Vector2 = origin+Vector2(local)*cell
		var tile: Button = button(host,"",Rect2(at,Vector2(cell-1.5,cell-1.5)),_select_map_sector.bind(map_cell.coord))
		var ink: Color = sector_color(campaign,map_cell.coord,map_cell.explored)
		var fill: Color = Color(ink,0.14) if map_cell.explored else Color("050608")
		var border: Color = Color(ink,0.55) if map_cell.explored else Color("1c2028")
		# A Chebyshev disc IS the square this grid draws, so the sealed
		# perimeter is the OUTERMOST RING, not a set of excluded cells: those
		# nodes' membranes never open outward (spec §11 "sits on the
		# perimeter"). Draw that ring as a solid wall regardless of element.
		var is_perimeter: bool = not map_cell.in_bounds or CampaignState.ring(map_cell.coord) == model.radius
		if is_perimeter:
			fill = Color("0b0d12") if not map_cell.in_bounds else fill
			border = MUTED
		tile.add_theme_stylebox_override("normal",UiKit.box(fill,border,3 if is_perimeter else 1))
		tile.tooltip_text = sector_description(campaign,map_cell.coord)
		if map_cell.is_boss: centered_label(host,"◎",at,Vector2(cell,cell),12,GOLD)
		elif map_cell.current: centered_label(host,"●",at,Vector2(cell,cell),12,WHITE)
	UiKit.panel(host,Rect2(700,92,480,412),VisualStyle.PANEL,Color("34343b"))
	map_detail = UiKit.label(host,"",Vector2(725,112),Vector2(430,201),17,WHITE)
	UiKit.label(host,"● You   ◎ Boss (bearing above, from the first tick)\nDark = unexplored, reveals nothing. Wall border = sealed perimeter.\nLayouts re-roll every life (spec §7).",Vector2(725,330),Vector2(430,140),15,MUTED)
	_focus = button(host,"RETURN TO FLIGHT",Rect2(870,721,320,45),app._close_overlay)
	_select_map_sector(campaign.current_sector)

func _select_map_sector(coord: Vector2i) -> void:
	map_selected = coord
	map_detail.text = sector_description(app.campaign,coord)

static func sector_description(campaign: CampaignState, coord: Vector2i) -> String:
	if not campaign.in_bounds(coord): return "NODE %s\n\nSealed perimeter." % CampaignState.coord_key(coord)
	if not sector_known(campaign,coord): return "NODE %s\n\nUnexplored space." % CampaignState.coord_key(coord)
	var sector: Dictionary = campaign.sector_at(coord)
	var lines := PackedStringArray(["NODE %s · RING %d" % [CampaignState.coord_key(coord),int(sector.get("ring",0))]])
	lines.append("\nSAFE ORIGIN" if coord == Vector2i.ZERO else "\n%s · %s" % [str(sector.get("element","")).to_upper(),str(sector.get("kind","regular")).replace("_"," ").to_upper()])
	if coord != Vector2i.ZERO: lines.append("Threat tier %d" % int(sector.get("tier",1)))
	return "\n".join(lines)

static func sector_known(campaign: CampaignState, coord: Vector2i) -> bool:
	return coord == Vector2i.ZERO or CampaignState.coord_key(coord) in campaign.discovered

static func sector_color(campaign: CampaignState, coord: Vector2i, known: bool) -> Color:
	if coord == campaign.current_sector: return WHITE
	if not known: return Color("242b36")
	if coord == Vector2i.ZERO: return WHITE
	return ShipCatalog.get_color(str(campaign.sector_at(coord).get("element","fire")))
