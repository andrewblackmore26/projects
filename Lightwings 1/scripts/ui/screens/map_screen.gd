class_name MapScreen
extends UiScreen
## The full map screen (spec §11). MinimapModel is the single source of truth.
##
## Modernization M14: the level is drawn as what it is since M3, an open lattice. Node circles sit
## on thin rails to all 8 neighbours; explored nodes are filled with their element colour,
## unexplored ones stay dim and disclose nothing, the current node pulses, and the boss is a ring
## with a bearing arrow from the first tick. The lattice reveals outward from the player
## (MinimapModel.REVEAL_PER_RING per ring), pans (mouse drag, right stick) and zooms (wheel,
## triggers, 0.75-2x of the fit), and d-pad/keyboard focus steps node to node along the rails
## while the detail panel follows. The default view fits the whole level. The router lays this
## screen out as "fill": the lattice takes whatever width the window has.
##
## The node descriptions and colours are static here because the corner minimap
## (scripts/ui/hud/minimap.gd) and main.gd's forwarders use them too.

var map_detail: Label
var map_selected: Vector2i
var view: MapView

var _title: Label
var _bearing: Label
var _panel: Panel
var _column: VBoxContainer
var _kicker: Label
var _route: Label
var _hint: Label
var _model: MinimapModel
var _optional: Array[Control] = []

## The lattice reveals itself; everything else enters with the router's stagger.
func motion_items() -> Array:
	return super().filter(func(node: Node) -> bool: return node != view)

func build() -> void:
	var campaign: CampaignState = app.campaign
	_model = MinimapModel.build(campaign)
	_title = UiKit.label(host,"THE AI-VERSE",Vector2(24,24),Vector2(620,40),UiTokens.TEXT_XL,WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bearing = UiKit.label(host,"BOSS BEARING  %s · %d %s" % [_model.bearing_direction,_model.bearing_distance,"NODE" if _model.bearing_distance == 1 else "NODES"],Vector2(26,66),Vector2(620,24),UiTokens.TEXT_M,GOLD)
	_bearing.autowrap_mode = TextServer.AUTOWRAP_OFF
	view = MapView.new()
	view.name = "MapView"
	host.add_child(view)
	view.setup(_model,campaign)
	view.focus_moved.connect(_on_view_focus)
	view.close_requested.connect(func() -> void: app._close_overlay())
	_panel = UiKit.glass(host,Rect2(900,24,356,752))
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation",UiTokens.SPACE_3)
	_panel.add_child(_column)
	_kicker = UiKit.label(_column,"",Vector2.ZERO,Vector2(300,18),UiTokens.TEXT_XS,GOLD)
	_kicker.theme_type_variation = UiTokens.KICKER_LABEL
	map_detail = UiKit.label(_column,"",Vector2.ZERO,Vector2(300,96),UiTokens.TEXT_M,WHITE)
	_route = UiKit.label(_column,"",Vector2.ZERO,Vector2(300,40),UiTokens.TEXT_S,MUTED)
	var legend: VBoxContainer = _section()
	for entry: Array in [["current","You"],["explored","Explored, in its element's colour"],["unexplored","Unexplored: reveals nothing"],["boss","Boss, with its bearing from the first tick"]]:
		_legend_row(legend,str(entry[0]),str(entry[1]))
	var explored: int = 0
	for cell: MinimapModel.Cell in _model.cells:
		if cell.in_bounds and (cell.explored or cell.current): explored += 1
	var level: VBoxContainer = _section()
	var level_kicker: Label = UiKit.label(level,"LEVEL %d" % campaign.level,Vector2.ZERO,Vector2(300,18),UiTokens.TEXT_XS,GOLD)
	level_kicker.theme_type_variation = UiTokens.KICKER_LABEL
	UiKit.label(level,"%d of %d nodes explored.\nThe layout re-rolls every life." % [explored,_model.grid_size()*_model.grid_size()],Vector2.ZERO,Vector2(300,40),UiTokens.TEXT_S,MUTED)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(spacer)
	_hint = UiKit.label(_column,"",Vector2.ZERO,Vector2(300,40),UiTokens.TEXT_XS,MUTED)
	# What a short panel (UI scale 140%, a 16:9 window) drops first: the level note, the legend,
	# then the control hint. The node detail and RETURN always stay.
	_optional = [level,legend,_hint]
	var back: Button = button(_column,"RETURN TO FLIGHT",Rect2(0,0,0,44),app._close_overlay)
	back.custom_minimum_size.y = 44
	_focus = view
	InputPrompts.shared().device_changed.connect(_on_device_changed)
	_update_hint()
	_select_map_sector(campaign.current_sector)

func exit() -> void:
	if InputPrompts.shared().device_changed.is_connected(_on_device_changed): InputPrompts.shared().device_changed.disconnect(_on_device_changed)

## A block of the detail column, set a step apart from what is above it.
func _section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation",UiTokens.SPACE_3)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiTokens.SPACE_2
	section.add_child(gap)
	_column.add_child(section)
	return section

## One legend line: the glyph the lattice draws for `kind`, then its caption.
func _legend_row(parent: Control, kind: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",UiTokens.SPACE_3)
	parent.add_child(row)
	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(22,22)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.draw.connect(func() -> void: MapView.draw_legend_glyph(glyph,kind,Vector2(11,11)))
	row.add_child(glyph)
	var caption: Label = UiKit.label(row,text,Vector2.ZERO,Vector2(260,20),UiTokens.TEXT_S,MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## M6/M14: header top left, the detail column down the right, the lattice in the rest; read from
## the UI rect this "fill" screen is given (the router sizes the host after this runs).
func relayout() -> void:
	var parent: Control = host.get_parent() as Control
	var area: Vector2 = parent.size if parent != null and parent.size.x > 0.0 else UiLayout.BASE_SIZE
	var safe: Rect2 = UiLayout.safe_rect(area)
	var panel_w: float = clampf(area.x*0.27,300.0,400.0)
	_panel.position = Vector2(safe.end.x-panel_w,safe.position.y)
	_panel.size = Vector2(panel_w,safe.size.y)
	_column.position = Vector2(UiTokens.SPACE_5,UiTokens.SPACE_5)
	# The room, not _column.size: a Control is never sized below its minimum.
	var room: Vector2 = _panel.size-Vector2(UiTokens.SPACE_5,UiTokens.SPACE_5)*2.0
	for part: Control in _optional: part.visible = true
	for part: Control in _optional:
		if _column_height() <= room.y: break
		part.visible = false
	_column.size = room
	var left: float = safe.position.x
	var width: float = _panel.position.x-UiTokens.SPACE_5-left
	_title.position = Vector2(left,safe.position.y)
	_title.size = Vector2(width,_title.get_minimum_size().y)
	_bearing.position = Vector2(left+2.0,_title.position.y+_title.size.y)
	_bearing.size = Vector2(width-2.0,_bearing.get_minimum_size().y)
	var top: float = _bearing.position.y+_bearing.size.y+UiTokens.SPACE_3
	view.position = Vector2(left,top)
	view.size = Vector2(width,safe.end.y-top)
	view.refit()

## The height the detail column's visible parts need (the spacer's share excluded).
func _column_height() -> float:
	var total: float = 0.0
	var count: int = 0
	for child: Node in _column.get_children():
		if not (child as Control).visible: continue
		total += (child as Control).get_combined_minimum_size().y
		count += 1
	return total+float(maxi(0,count-1)*_column.get_theme_constant("separation"))

func _on_view_focus(coord: Vector2i, audible: bool) -> void:
	_select_map_sector(coord)
	if audible: UiScreen.ui_cue(app,"ui_move")

func _on_device_changed(_device: String, _family: String) -> void:
	_update_hint()

func _update_hint() -> void:
	if InputPrompts.shared().device == InputPrompts.PAD:
		_hint.text = "D-PAD  move between nodes\nR-STICK  pan · LT / RT  zoom"
	else:
		_hint.text = "ARROWS  move between nodes · CLICK  select\nDRAG  pan · WHEEL  zoom"

func _select_map_sector(coord: Vector2i) -> void:
	map_selected = coord
	map_detail.text = sector_description(app.campaign,coord)
	var campaign: CampaignState = app.campaign
	var steps: int = CampaignState.ring(coord-campaign.current_sector)
	if coord == campaign.current_sector: _kicker.text = "YOU ARE HERE"
	elif coord == _model.boss_coord: _kicker.text = "BOSS NODE"
	else: _kicker.text = "NODE"
	var to_boss: Vector2i = _model.boss_coord-coord
	var lines := PackedStringArray()
	if steps > 0: lines.append("%d %s from you" % [steps,"jump" if steps == 1 else "jumps"])
	if to_boss != Vector2i.ZERO: lines.append("Boss %s · %d from here" % [MinimapModel.direction_of(to_boss),CampaignState.ring(to_boss)])
	_route.text = "\n".join(lines)

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

## The lattice itself: a clipped Control that draws the level in view space (strokes stay one
## pixel weight at every zoom). The static layer (field, rails, nodes) redraws only while the
## reveal runs or the view moves; a child overlay redraws every frame for what animates (the
## current node's pulse, the focus reticle, the boss ring and the bearing).
class MapView extends Control:
	signal focus_moved(coord: Vector2i, audible: bool)
	signal close_requested

	const ZOOM_MIN: float = 0.75
	const ZOOM_MAX: float = 2.0
	const WHEEL_STEP: float = 1.12
	## A node fades and pops in over this long once its ring's delay has passed.
	const REVEAL_FADE: float = 0.16
	## Keyboard/d-pad: a press waits CHORD_S for a second key (two arrows make a diagonal), then
	## steps; holding repeats after FIRST_REPEAT_S, then every REPEAT_S.
	const CHORD_S: float = 0.05
	const FIRST_REPEAT_S: float = 0.3
	const REPEAT_S: float = 0.11
	## Right stick pan at full deflection (view px/s) and trigger zoom (e-folds/s).
	const PAN_SPEED: float = 900.0
	const ZOOM_RATE: float = 1.6
	const DRAG_SLOP: float = 5.0
	const RAIL_WIDTH: float = 1.25
	const NONE := Vector2i(1 << 20,1 << 20)
	const BLUE := VisualStyle.BLUE
	const GOLD := VisualStyle.ACCENT
	const CORE := Color(0.03,0.035,0.052)

	var model: MinimapModel
	var focus: Vector2i
	var zoom: float = 1.0
	## The level centre's offset from the view centre (view px); `pan_target` is where it eases to.
	var pan: Vector2 = Vector2.ZERO
	var pan_target: Vector2 = Vector2.ZERO
	## What the static layer strokes: every rail once ([a, b]), with its colour.
	var rails: Array = []
	var rail_inks: PackedColorArray = PackedColorArray()
	## coord -> seconds after opening at which the node appears.
	var reveal_at: Dictionary = {}
	var reveal_end: float = 0.0
	## The reveal's clock (seconds), tweened from 0 to reveal_end + REVEAL_FADE as the map opens.
	var reveal_time: float = 0.0:
		set(value):
			reveal_time = value
			queue_redraw()
			if _overlay != null: _overlay.queue_redraw()
	var _reveal_us: int = 0
	var _reveal_tween: Tween
	var _inks: Dictionary = {}
	var _fit: float = 24.0
	var _last_us: int = 0
	var _overlay: Control
	var _field := StyleBoxFlat.new()
	var _nav_dir: Vector2i = Vector2i.ZERO
	var _nav_wait: float = 0.0
	var _nav_chording: bool = false
	var _nav_active: bool = false
	var _drag_button: int = -1
	var _drag_from: Vector2
	var _drag_pan: Vector2
	var _dragging: bool = false
	var _hover_travel: float = 0.0
	static var _font: Font

	func setup(source: MinimapModel, campaign: CampaignState) -> void:
		model = source
		focus = model.current_coord
		clip_contents = true
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_ALWAYS
		# No focus ring stylebox: the reticle on the focused node is the focus indicator.
		add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		for cell: MinimapModel.Cell in model.cells:
			if not cell.in_bounds: continue
			reveal_at[cell.coord] = model.reveal_delay(cell.coord)
			reveal_end = maxf(reveal_end,reveal_at[cell.coord])
			if cell.explored or cell.current: _inks[cell.coord] = MapScreen.sector_color(campaign,cell.coord,true)
		rails = model.rail_segments()
		for pair: Array in rails: rail_inks.append(_rail_ink(pair[0],pair[1]))
		_field.bg_color = Color(0.045,0.055,0.085,0.62)
		_field.border_color = Color(0.5,0.56,0.68,0.42)
		_field.set_border_width_all(1)
		_field.shadow_color = Color(BLUE,0.03)
		_field.shadow_size = 16
		_field.anti_aliasing = true
		_overlay = Control.new()
		_overlay.name = "Overlay"
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overlay)
		_overlay.draw.connect(_draw_overlay)
		_last_us = Time.get_ticks_usec()
		if _font == null: _font = UiKit.font(UiTokens.FONT_MONO,UiTokens.WEIGHT_MONO,true)
		# The reveal is driven by a tween, not _process: a tween runs while paused and while node
		# processing is frozen (tools/capture_screens.gd freezes every node before its grab). Its
		# clock starts at its first step, so the long frame that built the screen cannot swallow
		# the reveal (measured: a plain tween had jumped 75% of the way by its first step).
		# Reduced motion: no reveal.
		_reveal_us = 0
		if is_inside_tree() and not UiMotion.reduced:
			_reveal_tween = UiMotion.tween(self)
			_reveal_tween.tween_method(_advance_reveal,0.0,1.0,10.0)
		else: reveal_time = reveal_end+REVEAL_FADE

	func _advance_reveal(_progress: float) -> void:
		var now: int = Time.get_ticks_usec()
		var step: float = 0.0 if _reveal_us == 0 else float(now-_reveal_us)/1000000.0
		# A view whose processing was switched off is a frozen capture (tools/capture_screens.gd,
		# which can hit a fresh process's second-long first frame): it shows the settled map.
		if not is_processing(): step = INF
		reveal_time = minf(reveal_time+step,reveal_end+REVEAL_FADE)
		_reveal_us = now
		if reveal_time >= reveal_end+REVEAL_FADE and _reveal_tween != null:
			_reveal_tween.kill()
			_reveal_tween = null

	## Both ends explored: the blend of their colours; one: a lit neutral; none: a faint neutral.
	func _rail_ink(a: Vector2i, b: Vector2i) -> Color:
		var lit_a: bool = _inks.has(a)
		var lit_b: bool = _inks.has(b)
		if lit_a and lit_b: return Color((_inks[a] as Color).lerp(_inks[b],0.5),0.5)
		# The UI blends in linear light (HDR 2D): these low alphas read several times stronger.
		if lit_a or lit_b: return Color(0.62,0.7,0.86,0.1)
		return Color(0.55,0.62,0.76,0.04)

	## Re-fits after a resize: zoom 1 shows the whole level with room for the boss ring.
	func refit() -> void:
		_fit = maxf(4.0,minf(size.x,size.y)/(2.0*model.radius+2.6))
		_overlay.position = Vector2.ZERO
		_overlay.size = size
		pan = clamp_pan(pan)
		pan_target = clamp_pan(pan_target)
		queue_redraw()

	func spacing() -> float:
		return _fit*zoom

	func node_radius() -> float:
		return clampf(spacing()*0.2,3.0,11.0)

	func to_view(coord: Vector2) -> Vector2:
		return size*0.5+pan+coord*spacing()

	## Pan limits: at the fit the level barely moves; zoomed in, its edge can reach the view's.
	func clamp_pan(value: Vector2) -> Vector2:
		var extent: float = (float(model.radius)+0.5)*spacing()
		var limit := Vector2(maxf(0.0,extent-size.x*0.45),maxf(0.0,extent-size.y*0.45))
		return value.clamp(-limit,limit)

	## Seconds into the reveal.
	func elapsed() -> float:
		return reveal_time

	func revealed(coord: Vector2i, t: float) -> float:
		return clampf((t-float(reveal_at.get(coord,0.0)))/REVEAL_FADE,0.0,1.0)

	## The in-bounds node under a view position (within ~half a spacing), or NONE.
	func node_at(point: Vector2) -> Vector2i:
		var local: Vector2 = (point-size*0.5-pan)/spacing()
		var coord := Vector2i(roundi(local.x),roundi(local.y))
		if not reveal_at.has(coord) or local.distance_to(Vector2(coord)) > 0.55: return NONE
		return coord

	func zoom_at(factor: float, anchor: Vector2) -> void:
		var next: float = clampf(zoom*factor,ZOOM_MIN,ZOOM_MAX)
		if is_equal_approx(next,zoom): return
		var rel: Vector2 = anchor-size*0.5
		pan = rel-(rel-pan)*(next/zoom)
		zoom = next
		pan = clamp_pan(pan)
		pan_target = pan
		queue_redraw()

	func set_focus(coord: Vector2i, follow: bool, audible: bool) -> void:
		if coord == focus or not reveal_at.has(coord): return
		focus = coord
		if follow: _follow_focus()
		focus_moved.emit(coord,audible)

	## Eases the view so the focused node stays a spacing and a half inside its edges.
	func _follow_focus() -> void:
		var at: Vector2 = size*0.5+pan_target+Vector2(focus)*spacing()
		var margin: float = minf(spacing()*1.5,minf(size.x,size.y)*0.3)
		var inner := Rect2(Vector2(margin,margin),size-Vector2(margin,margin)*2.0)
		var shift := Vector2.ZERO
		for axis: int in [0,1]:
			if at[axis] < inner.position[axis]: shift[axis] = inner.position[axis]-at[axis]
			elif at[axis] > inner.end[axis]: shift[axis] = inner.end[axis]-at[axis]
		pan_target = clamp_pan(pan_target+shift)

	## One step of keyboard/d-pad navigation toward `dir` (ZERO: released), `dt` seconds after the
	## last. A tap shorter than the chord window still steps, on release.
	func navigate(dir: Vector2i, dt: float) -> void:
		if dir == Vector2i.ZERO:
			if _nav_active and _nav_chording and _nav_dir != Vector2i.ZERO: _step(_nav_dir)
			_nav_active = false
			_nav_dir = Vector2i.ZERO
			return
		_nav_dir = dir
		if not _nav_active:
			_nav_active = true
			_nav_chording = true
			_nav_wait = CHORD_S
		_nav_wait -= dt
		if _nav_wait <= 0.0:
			_step(dir)
			_nav_wait = FIRST_REPEAT_S if _nav_chording else REPEAT_S
			_nav_chording = false

	func _step(dir: Vector2i) -> void:
		set_focus(model.focus_step(focus,dir),true,true)

	func _process(_delta: float) -> void:
		var now: int = Time.get_ticks_usec()
		var dt: float = minf(float(now-_last_us)/1000000.0,0.1)
		_last_us = now
		if not is_visible_in_tree(): return
		if has_focus(): navigate(MinimapModel.bearing_of(Input.get_vector("ui_left","ui_right","ui_up","ui_down",0.3),0.5),dt)
		var stick := Vector2.ZERO
		var trigger: float = 0.0
		for device: int in Input.get_connected_joypads():
			var axis := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
			if axis.length() > stick.length(): stick = axis
			trigger += Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT)-Input.get_joy_axis(device,JOY_AXIS_TRIGGER_LEFT)
		if stick.length() > 0.2:
			pan = clamp_pan(pan-stick*PAN_SPEED*dt)
			pan_target = pan
			queue_redraw()
		if absf(trigger) > 0.1: zoom_at(exp(trigger*ZOOM_RATE*dt),to_view(Vector2(focus)))
		if not pan.is_equal_approx(pan_target):
			pan = pan.lerp(pan_target,1.0-exp(-14.0*dt))
			if pan.distance_to(pan_target) < 0.25: pan = pan_target
			queue_redraw()
		_overlay.queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event
			if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				zoom_at(WHEEL_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/WHEEL_STEP,button.position)
			elif button.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
				if button.pressed:
					_drag_button = button.button_index
					_drag_from = button.position
					_drag_pan = pan
					_dragging = false
					grab_focus()
				elif button.button_index == _drag_button:
					if not _dragging and button.button_index == MOUSE_BUTTON_LEFT:
						var picked: Vector2i = node_at(button.position)
						if picked != NONE: set_focus(picked,false,true)
					_drag_button = -1
			accept_event()
		elif event is InputEventMouseMotion:
			var motion: InputEventMouseMotion = event
			if _drag_button >= 0:
				if not _dragging and motion.position.distance_to(_drag_from) > DRAG_SLOP: _dragging = true
				if _dragging:
					pan = clamp_pan(_drag_pan+motion.position-_drag_from)
					pan_target = pan
					queue_redraw()
			else:
				# Hover follows only a mouse that has really moved since the map opened: a pointer
				# resting where the map appears must not steal focus from "you are here".
				_hover_travel += motion.relative.length()
				var hovered: Vector2i = node_at(motion.position)
				if hovered != NONE and _hover_travel > DRAG_SLOP: set_focus(hovered,false,false)
			accept_event()
		elif event is InputEventMagnifyGesture:
			zoom_at((event as InputEventMagnifyGesture).factor,(event as InputEventMagnifyGesture).position)
			accept_event()
		elif event is InputEventPanGesture:
			pan = clamp_pan(pan-(event as InputEventPanGesture).delta*spacing()*0.5)
			pan_target = pan
			queue_redraw()
			accept_event()
		elif event.is_action_pressed("map") and not event.is_echo():
			close_requested.emit()
			accept_event()
		elif event.is_action_pressed("ui_accept"):
			# Centre the view on the focused node.
			pan_target = clamp_pan(-Vector2(focus)*spacing())
			accept_event()
		elif event.is_action("ui_left") or event.is_action("ui_right") or event.is_action("ui_up") or event.is_action("ui_down"):
			# Polled in _process (two arrows make a diagonal); kept from the GUI's focus walk.
			accept_event()

	func _draw() -> void:
		var t: float = elapsed()
		var sp: float = spacing()
		var r: float = node_radius()
		var extent: float = (float(model.radius)+0.5)*sp
		var shown: float = clampf(t/REVEAL_FADE,0.0,1.0)
		# The level: one rounded field whose border is the level edge.
		_field.set_corner_radius_all(int(sp*0.5))
		_field.bg_color.a = 0.62*shown
		_field.border_color.a = 0.42*shown
		_field.shadow_color.a = 0.03*shown
		draw_style_box(_field,Rect2(to_view(Vector2.ZERO)-Vector2(extent,extent),Vector2(extent,extent)*2.0))
		var bounds: Rect2 = Rect2(Vector2.ZERO,size).grow(sp)
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for index: int in range(rails.size()):
			var pair: Array = rails[index]
			var k: float = minf(revealed(pair[0],t),revealed(pair[1],t))
			if k <= 0.0: continue
			var a: Vector2 = to_view(Vector2(pair[0]))
			var b: Vector2 = to_view(Vector2(pair[1]))
			if not bounds.has_point(a) and not bounds.has_point(b): continue
			points.append(a)
			points.append(b)
			var ink: Color = rail_inks[index]
			ink.a *= k
			colors.append(ink)
		if not points.is_empty(): draw_multiline_colors(points,colors,RAIL_WIDTH,true)
		for cell: MinimapModel.Cell in model.cells:
			if not cell.in_bounds: continue
			var k: float = revealed(cell.coord,t)
			if k <= 0.0: continue
			var at: Vector2 = to_view(Vector2(cell.coord))
			if not bounds.has_point(at): continue
			var s: float = UiMotion.out_back(k)
			if cell.current: pass # the overlay draws it, pulsing
			elif _inks.has(cell.coord):
				var ink: Color = _inks[cell.coord]
				draw_circle(at,r*1.6*s,Color(ink,0.07*k))
				draw_circle(at,r*s,Color(ink,0.92*k),true,-1.0,true)
				draw_arc(at,r*s,0.0,TAU,24,Color(ink.lerp(Color.WHITE,0.45),0.9*k),1.0,true)
			else:
				draw_circle(at,r*0.5*s,Color(CORE,k),true,-1.0,true)
				draw_arc(at,r*0.5*s,0.0,TAU,16,Color(0.46,0.53,0.66,0.34*k),1.0,true)
			if cell.is_boss:
				draw_arc(at,r*1.75*s,0.0,TAU,32,Color(GOLD,0.95*k),1.5,true)
				for quarter: int in range(4):
					var dir: Vector2 = Vector2.from_angle(TAU*0.25*quarter+PI*0.25)
					draw_line(at+dir*r*2.2*s,at+dir*r*2.75*s,Color(GOLD,0.8*k),1.5,true)
				var px: int = UiLayout.text_px(11)
				var word_w: float = _font.get_string_size("BOSS",HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
				draw_string(_font,at+Vector2(-word_w*0.5,-r*2.9-4.0),"BOSS",HORIZONTAL_ALIGNMENT_LEFT,-1,px,Color(GOLD,k))

	## What animates every frame: the bearing, the boss ring's breath, the current node's pulse and
	## the focus reticle. UI clock, so a paused tree still animates.
	func _draw_overlay() -> void:
		var t: float = elapsed()
		var clock: float = float(Time.get_ticks_msec())/1000.0
		var r: float = node_radius()
		var here: Vector2 = to_view(Vector2(model.current_coord))
		var boss: Vector2 = to_view(Vector2(model.boss_coord))
		if model.boss_coord != model.current_coord:
			var dir: Vector2 = (boss-here).normalized()
			var side := Vector2(-dir.y,dir.x)
			var from: Vector2 = here+dir*(r*2.9+17.0)
			var to: Vector2 = boss-dir*r*2.4
			if (to-from).dot(dir) > 6.0: _overlay.draw_dashed_line(from,to,Color(GOLD,0.36),1.25,5.0,true,true)
			# The arrow sits just outside the focus reticle's reach.
			var base: Vector2 = here+dir*(r*2.9+4.0)
			_overlay.draw_colored_polygon(PackedVector2Array([base+dir*13.0,base+side*7.0,base+dir*4.0,base-side*7.0]),GOLD)
			var breath: float = 0.5+0.5*sin(clock*2.4)
			_overlay.draw_arc(boss,r*(2.3+0.35*breath),0.0,TAU,40,Color(GOLD,(0.18+0.2*(1.0-breath))*revealed(model.boss_coord,t)),1.0,true)
		var phase: float = fposmod(clock*0.7,1.0)
		_overlay.draw_arc(here,r*(1.4+1.8*phase),0.0,TAU,32,Color(BLUE,0.65*(1.0-phase)),1.5,true)
		_overlay.draw_circle(here,r*2.0,Color(BLUE,0.12))
		_overlay.draw_circle(here,r*1.05,BLUE,true,-1.0,true)
		_overlay.draw_circle(here,r*0.42,Color.WHITE,true,-1.0,true)
		if revealed(focus,t) <= 0.0: return
		var at: Vector2 = to_view(Vector2(focus))
		var half: float = r*2.1+1.0*sin(clock*4.0)
		var arm: float = maxf(4.0,r*0.8)
		var ink := Color(1,1,1,0.92 if has_focus() else 0.6)
		for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var tip: Vector2 = at+corner*half
			_overlay.draw_polyline(PackedVector2Array([tip-Vector2(0,corner.y*arm),tip,tip-Vector2(corner.x*arm,0)]),ink,1.5,true)

	## The legend's samples, drawn the way the lattice draws each kind.
	static func draw_legend_glyph(canvas: CanvasItem, kind: String, at: Vector2) -> void:
		var r: float = 5.0
		match kind:
			"current":
				canvas.draw_arc(at,r*1.9,0.0,TAU,24,Color(BLUE,0.45),1.25,true)
				canvas.draw_circle(at,r*1.05,BLUE,true,-1.0,true)
				canvas.draw_circle(at,r*0.42,Color.WHITE,true,-1.0,true)
			"explored":
				# One dot per element colour: an explored node wears its own.
				for i: int in range(3):
					var ink: Color = [VisualStyle.CORAL,VisualStyle.ACCENT,VisualStyle.VIOLET][i]
					canvas.draw_circle(at+Vector2(7.0*(i-1),0.0),3.2,Color(ink,0.92),true,-1.0,true)
			"unexplored":
				canvas.draw_circle(at,r*0.6,CORE,true,-1.0,true)
				canvas.draw_arc(at,r*0.6,0.0,TAU,16,Color(0.46,0.53,0.66,0.8),1.0,true)
			"boss":
				canvas.draw_circle(at,r*0.6,CORE,true,-1.0,true)
				canvas.draw_arc(at,r*0.6,0.0,TAU,16,Color(0.46,0.53,0.66,0.8),1.0,true)
				canvas.draw_arc(at,r*1.75,0.0,TAU,32,GOLD,1.5,true)
