class_name EvolutionScreen
extends UiScreen
## The evolution cards (moved from main.gd's `_show_evolution` in M2). main.gd still decides
## whether the screen may open and rolls `pending_offers`; this draws them. Choosing a card calls
## main.gd's `_choose_evolution`, which applies the hull, plays the transformation and queues the
## companion line.
##
## M12: the cards are picked in slow motion, not over a paused game (ScreenRouter's "evolution"
## policy: sim at 0.25, a light dim with no blur and the world desaturated, fire and warp engage
## held, movement free). Picking: a click (instant), keys 1/2/3 (instant), or the pad's A held for
## HOLD_SECONDS on a focused card, with a radial filling on its button. B/Esc is "decide later",
## and the cards close by themselves after AUTO_CLOSE_SECONDS of real time (the offers stay). Each
## card slides up CARD_STAGGER after the one before it and shows the hull's element chip, a live
## preview, its weapon and passive glyph rows (AbilityGlyphs) and its stats against the current hull
## (green up, coral down). Focus - which is hover - lifts a card CARD_LIFT px, lights its edge and
## speeds its preview.
##
## M19: the cards keep clear of the player's ship, because the player is still dodging in the slow
## motion. When the centred row would cover the ship (its animated radius + SHIP_CLEARANCE), the
## row splits around the ship's projected position - the cards on each side of a clear corridor,
## scaled down only as far as the corridor needs (never below MIN_CARD_SCALE) - and it splits again
## if the ship flies into a card. The focused card's hull is ghosted over the ship (HullGhost).

const TITLE_BOTTOM: float = 94.0
const SUBTITLE_Y: float = 104.0
const TABS_Y: float = 131.0
## A card: its box on the design canvas, and the design y of each block inside it (card-local).
const CARD_Y: float = 165.0
const CARD_SIZE: Vector2 = Vector2(330, 497)
const NAME_Y: float = 46.0
const PREVIEW_Y: float = 84.0
const PREVIEW_SIZE: Vector2 = Vector2(290, 168)
const WEAPONS_Y: float = 262.0
const PASSIVES_Y: float = 318.0
const STATS_Y: float = 376.0
const BUTTON_Y: float = 443.0
const ROW_GLYPH: float = 26.0
const FOOTER_Y: float = 679.0
const LATER_Y: float = 720.0

const AUTO_CLOSE_SECONDS: float = 8.0
const HOLD_SECONDS: float = 0.25
const CARD_STAGGER: float = 0.035
const CARD_SLIDE: float = 56.0
const CARD_LIFT: float = 8.0
const GLOW_PX: float = 6.0
const PREVIEW_HOVER_SPEED: float = 2.5
const PICK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
## M19: the clear margin kept around the ship's disc, the cards' pitch (a card and its gap), the
## smallest the cards shrink to open the corridor, and how long a re-split glides.
const SHIP_CLEARANCE: float = 44.0
const CARD_PITCH: float = 350.0
const MIN_CARD_SCALE: float = 0.6
const RESPLIT_SECONDS: float = 0.18
## Test seams, each with its own control: the corridor (off: the pre-M19 centred row) and the ghost.
static var avoid_ship: bool = true
static var ghost_enabled: bool = true

var _title: Label
var _subtitle: Label
var _footer: Label
var _later: Button
var _countdown: ColorRect
var _tabs: Array[Button] = []
## One entry per card: {id, card, lift, panel, button, preview, ink, rows (Array of [row node,
## names label]), stats (Array of [value label, delta label]), design_x}.
var _cards: Array[Dictionary] = []
var _open_elapsed: float = 0.0
var _hold_index: int = -1
var _hold_elapsed: float = 0.0
var _picked: bool = false
var _ring: HoldRing
## The keys' hints on the cards, shown for keyboard and mouse only; the device they were drawn for.
var _key_hints: Array[Label] = []
var _device: String = ""
## The HUD's ability dock, faded out while the cards are up (it sits under DECIDE LATER).
var _dock: CanvasItem
## M19: the focused offer's hull over the ship, and the ship's animated radius (world px).
var _ghost: HullGhost
var _ship_radius: float = 0.0
var _resplit: Tween

## A procedural ability glyph (AbilityGlyphs) on a faint disc.
class Glyph extends Control:
	var id: String = ""
	var ink: Color = Color.WHITE
	func _draw() -> void:
		var middle: Vector2 = size * 0.5
		draw_circle(middle, size.x * 0.5, Color(ink, 0.12))
		draw_arc(middle, size.x * 0.5 - 0.5, 0.0, TAU, 32, Color(ink, 0.35), 1.0, true)
		AbilityGlyphs.draw(self, id, middle, size.x * 0.5 - 3.0)

## The pad's hold-to-confirm: a ring that fills over HOLD_SECONDS on the held card's button.
class HoldRing extends Control:
	var progress: float = 0.0
	func _draw() -> void:
		if progress <= 0.0: return
		var middle: Vector2 = size * 0.5
		var radius: float = size.x * 0.5 - 2.0
		draw_arc(middle, radius, 0.0, TAU, 40, Color(VisualStyle.ACCENT, 0.25), 3.0, true)
		draw_arc(middle, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40, VisualStyle.ACCENT, 3.0, true)

## M6: the header grows up into its top margin (the title keeps its bottom at TITLE_BOTTOM), then
## pushes the subtitle and dev mode's tabs down. Inside each card every block sits under the one
## above however far its text wraps at the current text scale, the button and the card's box
## follow, and the footer sits under the tallest card. At text scale 1 everything stays at the
## design's coordinates. All from the design y, not position.y: an entrance tween may be moving
## the cards (their inner nodes never move).
func relayout() -> void:
	var title_height: float = _title.get_minimum_size().y
	var title_y: float = maxf(UiLayout.SAFE_MARGIN,minf(45.0,TITLE_BOTTOM-title_height))
	_title.position.y = title_y
	var subtitle_y: float = maxf(SUBTITLE_Y,title_y+title_height+2.0)
	_subtitle.position.y = subtitle_y
	for tab: Button in _tabs: tab.position.y = maxf(TABS_Y,subtitle_y+_subtitle.get_minimum_size().y+4.0)
	var bottom: float = CARD_Y+CARD_SIZE.y if _cards.is_empty() else CARD_Y
	for entry: Dictionary in _cards:
		var chip: Label = entry.chip
		UiLayout.hug(chip)
		var kicker: Label = entry.kicker
		kicker.position.x = chip.position.x+chip.size.x+8.0
		kicker.size = Vector2(maxf(20.0,280.0-kicker.position.x),kicker.get_minimum_size().y)
		var y: float = WEAPONS_Y
		var rows: Array = entry.rows
		for index: int in range(rows.size()):
			var row: Control = rows[index][0]
			var names: Label = rows[index][1]
			row.position.y = maxf(PASSIVES_Y if index == 1 else WEAPONS_Y,y)
			names.position.y = row.position.y+ROW_GLYPH+3.0
			names.size.y = 0.0
			y = names.position.y+names.get_minimum_size().y+6.0
		var stats_y: float = maxf(STATS_Y,y)
		var stats: Array = entry.stats
		for index: int in range(stats.size()):
			var value: Label = stats[index][0]
			var delta: Label = stats[index][1]
			UiLayout.hug(value)
			UiLayout.hug(delta)
			var row_height: float = maxf(value.get_minimum_size().y,delta.get_minimum_size().y)
			value.position = Vector2(20.0+float(index % 2)*150.0,stats_y+float(index/2)*(row_height+2.0))
			delta.position = Vector2(value.position.x+value.size.x+5.0,value.position.y)
		var last: Label = stats[-1][0]
		var button: Button = entry.button
		button.position.y = maxf(BUTTON_Y,last.position.y+last.get_minimum_size().y+8.0)
		var height: float = maxf(CARD_SIZE.y,button.position.y+button.size.y+14.0)
		(entry.panel as Control).size.y = height
		(entry.backing as Control).size.y = height
		(entry.glow as Control).size.y = height
		(entry.card as Control).size.y = height
		(entry.lift as Control).size.y = height
	# M19: split the row around the ship. The split reads the canvas fit and the fit reads the
	# cards, so place, fit, and place again (the router's own fit then changes nothing).
	var area: Vector2 = (host.get_parent() as Control).size if host.get_parent() is Control else UiLayout.BASE_SIZE
	for fit_pass: int in range(2):
		_place_cards(_card_targets())
		UiLayout.fit_canvas(host,area)
	_place_cards(_card_targets())
	for entry: Dictionary in _cards:
		var card: Control = entry.card
		bottom = maxf(bottom,CARD_Y+card.size.y*card.scale.y)
	_footer.position.y = maxf(FOOTER_Y,bottom+17.0)
	_later.position.y = maxf(LATER_Y,_footer.position.y+_footer.get_minimum_size().y+14.0)
	_countdown.position.y = _later.position.y-6.0

## The header, footer and tabs enter through the router's stagger; the cards slide up on their own
## (`_slide_in`), CARD_STAGGER apart.
func motion_items() -> Array:
	var cards: Array = _cards.map(func(entry: Dictionary) -> Node: return entry.card)
	return super().filter(func(node: Node) -> bool: return not cards.has(node))

func build() -> void:
	_title = centered_label(host,"BECOME SOMETHING NEW",Vector2(110,45),Vector2(1060,52),UiTokens.TEXT_2XL,WHITE)
	# M6: 6 px higher and one line tall, so dev mode's tab strip (y 131) no longer sits on it.
	_subtitle = centered_label(host,"Choose a lightship. Every weapon and passive shown belongs to that hull.",Vector2(110,SUBTITLE_Y),Vector2(1060,22),UiTokens.TEXT_M,MUTED)
	# With every hull on offer (dev mode) the cards are grouped behind a one-element-at-a-time tab
	# strip: 20 cards will not fit, and 20 live ShipPreviews would mean 20 HDR SubViewports.
	var shown: Array[String] = app.pending_offers
	if app.pending_offers.size() > 3:
		var by_element: Dictionary = {}
		for id: String in app.pending_offers:
			var ship: ShipDefinition = ShipCatalog.get_ship(id)
			if ship == null: continue
			if not by_element.has(ship.element): by_element[ship.element] = [] as Array[String]
			by_element[ship.element].append(id)
		var elements: Array = by_element.keys()
		if not elements.has(app.evolution_tab): app.evolution_tab = str(elements[0]) if not elements.is_empty() else ""
		var tab_x: float = 125.0
		for element: String in elements:
			var tab: Button = button(host,element.to_upper(),Rect2(tab_x,TABS_Y,190,30),func() -> void:
				app.evolution_tab = element
				app._close_overlay()
				app._show_evolution())
			tab.disabled = element == app.evolution_tab
			_tabs.append(tab)
			tab_x += 200.0
		shown = by_element.get(app.evolution_tab,[] as Array[String])
	var current: ShipDefinition = null
	if is_instance_valid(app.combat): current = ShipCatalog.get_ship(str(app.combat.hull_id))
	if is_instance_valid(app.combat): _ship_radius = ShipPreview.animated_radius(app.combat.player.get("definition") as ShipDefinition)
	# M6: the row of cards is centred on the canvas (three cards start at the design's x = 125). Dev
	# mode's four-card tabs are wider than 16:10, and the canvas scales them down to fit.
	var x: float = 640.0-(float(shown.size())*350.0-20.0)*0.5
	for id: String in shown:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship == null: continue
		_cards.append(_build_card(ship,current,x,_cards.size()))
		x += 350.0
	if not _cards.is_empty(): _focus = _cards[0].button
	_footer = centered_label(host,_footer_text(),Vector2(100,FOOTER_Y),Vector2(1080,25),UiTokens.TEXT_XS,MUTED)
	_footer.theme_type_variation = UiTokens.KICKER_LABEL
	_later = button(host,"DECIDE LATER",Rect2(520,LATER_Y,240,43),app._close_overlay)
	# The auto-close, shown: a hairline over DECIDE LATER that drains toward its middle.
	_countdown = ColorRect.new()
	_countdown.name = "Countdown"
	_countdown.color = Color(VisualStyle.ACCENT,0.55)
	_countdown.position = Vector2(520,LATER_Y-6.0)
	_countdown.size = Vector2(240,2)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_countdown)
	_ring = HoldRing.new()
	_ring.name = "HoldRing"
	_ring.size = Vector2(34,34)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false # shown only while a hold runs (hidden, it takes no part in the canvas fit)
	host.add_child(_ring)
	for index: int in range(_cards.size()): _slide_in(_cards[index].card,index)
	_device = InputPrompts.shared().device
	var hud_view: Object = app.get("hud_view")
	var dock: Object = hud_view.get("dock") if hud_view != null else null
	_dock = dock.get("root") as CanvasItem if dock != null else null
	if is_instance_valid(_dock): UiMotion.tween(_dock).tween_property(_dock,"modulate:a",0.0,UiMotion.duration(UiTokens.FAST,true))

func exit() -> void:
	if is_instance_valid(_dock): UiMotion.tween(_dock).tween_property(_dock,"modulate:a",1.0,UiMotion.duration(UiTokens.FAST,true))
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null

## M19: the ship's position and radius on this screen's canvas: (x, y, radius), radius < 0 when there
## is no ship on screen (no world, or no compositor).
func ship_on_canvas() -> Vector3:
	var compositor: CombatCompositor = app.get("compositor") as CombatCompositor
	var combat: CombatWorld = app.get("combat") as CombatWorld
	if not is_instance_valid(compositor) or not is_instance_valid(combat) or combat.player.is_empty() or not host.is_inside_tree(): return Vector3(0,0,-1)
	var screen: Vector2 = compositor.get_global_transform_with_canvas()*compositor.world_to_screen(combat.player_position)
	var to_host: Transform2D = host.get_global_transform_with_canvas().affine_inverse()
	var at: Vector2 = to_host*screen
	return Vector3(at.x,at.y,_ship_radius*compositor.zoom*absf(to_host.get_scale().x))

## Each card's [x, scale] on the canvas: the centred row, or - when that row would cover the ship -
## the row split into a clear corridor through the ship. Of the ways to put k cards left of the
## corridor and the rest right, the one that lets the cards stay largest wins (the more even split
## on a tie). Dev mode's element tabs (four cards, already scaled to fit) keep the centred row.
func _card_targets() -> Array:
	var count: int = _cards.size()
	var result: Array = []
	var start: float = 640.0-(float(count)*CARD_PITCH-20.0)*0.5
	for index: int in range(count): result.append([start+float(index)*CARD_PITCH,1.0])
	if not avoid_ship or count == 0 or count > PICK_KEYS.size(): return result
	var ship: Vector3 = ship_on_canvas()
	if ship.z < 0.0: return result
	var at := Vector2(ship.x,ship.y)
	var reach: float = ship.z+SHIP_CLEARANCE
	var covered: bool = false
	for index: int in range(count):
		var card: Control = _cards[index].card
		if _disc_hits(Rect2(result[index][0],CARD_Y-CARD_LIFT,CARD_SIZE.x,card.size.y+CARD_LIFT),at,reach): covered = true
	if not covered: return result
	var bounds: Vector2 = _canvas_span()
	var best_left: int = 0
	var best_scale: float = -INF
	for left: int in range(count+1):
		var fit: float = 1.0
		if left > 0: fit = minf(fit,(at.x-reach-bounds.x)/_group_width(left))
		if count-left > 0: fit = minf(fit,(bounds.y-at.x-reach)/_group_width(count-left))
		if fit > best_scale+0.001 or (absf(fit-best_scale) <= 0.001 and absi(2*left-count) < absi(2*best_left-count)):
			best_scale = fit
			best_left = left
	var s: float = clampf(best_scale,MIN_CARD_SCALE,1.0)
	for index: int in range(count):
		var x: float = at.x-reach-_group_width(best_left)*s+float(index)*CARD_PITCH*s if index < best_left else at.x+reach+float(index-best_left)*CARD_PITCH*s
		result[index] = [x,s]
	return result

## The width of `cards` cards side by side at scale 1.
static func _group_width(cards: int) -> float:
	return float(cards)*CARD_PITCH-20.0

## The x range the cards may use on the canvas: the UI's safe rect, less the focus glow, mapped
## through the canvas as UiLayout.fit_canvas centres it BEFORE its nudge - cards inside this span
## never make the fit nudge the canvas off its design coordinates.
func _canvas_span() -> Vector2:
	var area: Vector2 = (host.get_parent() as Control).size if host.get_parent() is Control else UiLayout.BASE_SIZE
	var safe: Rect2 = UiLayout.safe_rect(area)
	var s: float = maxf(0.0001,host.scale.x)
	var origin: float = (area.x-UiLayout.BASE_SIZE.x*s)*0.5
	return Vector2((safe.position.x-origin)/s+GLOW_PX+2.0,(safe.end.x-origin)/s-GLOW_PX-2.0)

static func _disc_hits(rect: Rect2, at: Vector2, radius: float) -> bool:
	var nearest := Vector2(clampf(at.x,rect.position.x,rect.end.x),clampf(at.y,rect.position.y,rect.end.y))
	return nearest.distance_to(at) < radius

func _place_cards(targets: Array, glide: bool = false) -> void:
	if is_instance_valid(_resplit): _resplit.kill()
	if glide: _resplit = UiMotion.tween(host).set_parallel(true)
	for index: int in range(mini(targets.size(),_cards.size())):
		var card: Control = _cards[index].card
		var x: float = float(targets[index][0])
		var s := Vector2.ONE*float(targets[index][1])
		if not glide:
			card.position.x = x
			card.scale = s
			continue
		var motion: Tween = _resplit
		motion.tween_property(card,"position:x",x,UiMotion.duration(RESPLIT_SECONDS)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		motion.tween_property(card,"scale",s,UiMotion.duration(RESPLIT_SECONDS)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## True when the ship (its own disc, no clearance) is under a card as the cards stand now.
func ship_under_card() -> bool:
	var ship: Vector3 = ship_on_canvas()
	if ship.z < 0.0: return false
	for entry: Dictionary in _cards:
		var card: Control = entry.card
		if _disc_hits(Rect2(card.position,card.size*card.scale),Vector2(ship.x,ship.y),ship.z): return true
	return false

func _build_card(ship: ShipDefinition, current: ShipDefinition, x: float, index: int) -> Dictionary:
	var ink: Color = ShipCatalog.get_color(ship.element)
	var card := Control.new()
	card.name = "Card%d" % (index+1)
	card.position = Vector2(x,CARD_Y)
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host.add_child(card)
	var lift := Control.new()
	lift.name = "Lift"
	lift.size = CARD_SIZE
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lift)
	# The focus glow: a soft ring OUTSIDE the card, faded in on focus. Not a StyleBox shadow: a
	# shadow lies under the whole panel, and through the card's fade-in it tinted the card itself.
	# The ring is drawn in the style's expand margin, so the Control keeps the card's own rect (the
	# canvas fit and the safe-rect check measure rects, not ink).
	var glow: Panel = UiKit.glass(lift,Rect2(Vector2.ZERO,CARD_SIZE))
	glow.name = "Glow"
	var ring: StyleBoxFlat = UiKit.glass_box(Color(0,0,0,0),Color(ink,0.22),int(GLOW_PX),UiTokens.RADIUS_PANEL+int(GLOW_PX))
	ring.draw_center = false
	ring.set_expand_margin_all(GLOW_PX)
	glow.add_theme_stylebox_override("panel",ring)
	glow.modulate.a = 0.0
	# An opaque backing under the glass: the world runs on behind the cards, and its HDR hulls (well
	# above 1.0 in linear light) showed through the glass, even over a 60% backing, as a ghost ship.
	var backing: Panel = UiKit.glass(lift,Rect2(Vector2.ZERO,CARD_SIZE))
	backing.name = "Backing"
	backing.add_theme_stylebox_override("panel",UiKit.glass_box(Color(UiTokens.GLASS,1.0),Color(0,0,0,0),0,UiTokens.RADIUS_PANEL))
	var panel: Panel = UiKit.glass(lift,Rect2(Vector2.ZERO,CARD_SIZE),Color(ink,0.45))
	# Element chip, tier and family, key hint.
	var chip: Label = UiKit.label(lift,ship.element.to_upper(),Vector2(20,18),Vector2.ZERO,UiTokens.TEXT_XS,ink)
	chip.theme_type_variation = UiTokens.KICKER_LABEL
	var chip_box: StyleBoxFlat = UiKit.glass_box(Color(ink,0.14),Color(ink,0.6),1,UiTokens.RADIUS_SMALL)
	chip_box.content_margin_left = 8
	chip_box.content_margin_right = 8
	chip_box.content_margin_top = 2
	chip_box.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal",chip_box)
	UiLayout.hug(chip)
	# Placed after the chip by relayout (the chip's width follows the text scale).
	var kicker: Label = UiKit.label(lift,"T%d · %s" % [ship.tier,ship.family.replace("_"," ").to_upper()],Vector2(120,20),Vector2(160,20),UiTokens.TEXT_XS,MUTED)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	kicker.autowrap_mode = TextServer.AUTOWRAP_OFF
	kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if index < PICK_KEYS.size():
		var key: Label = UiKit.label(lift,str(index+1),Vector2(288,17),Vector2(24,22),UiTokens.TEXT_XS,WHITE)
		key.name = "KeyHint"
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var cap: StyleBoxFlat = UiKit.glass_box(UiTokens.GLASS_RAISED,UiTokens.STROKE,1,UiTokens.RADIUS_SMALL)
		cap.content_margin_left = 0
		cap.content_margin_right = 0
		cap.content_margin_top = 0
		cap.content_margin_bottom = 0
		key.add_theme_stylebox_override("normal",cap)
		key.visible = InputPrompts.shared().device != InputPrompts.PAD
		_key_hints.append(key)
	var name_label: Label = UiKit.label(lift,ship.display_name,Vector2(20,NAME_Y),Vector2(290,32),UiTokens.TEXT_L,WHITE)
	name_label.theme_type_variation = UiTokens.DISPLAY_LABEL
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var preview := ShipPreview.new()
	preview.fit_margin = 14.0
	lift.add_child(preview)
	preview.position = Vector2(20,PREVIEW_Y)
	preview.initialize(ship,PREVIEW_SIZE,1.5)
	# Weapon and passive glyph rows: the glyphs, then the names under them.
	var weapons: Array[String] = [ship.primary]
	weapons.append_array(ship.secondaries)
	var rows: Array = [_glyph_row(lift,"WEAPONS",weapons,WEAPONS_Y,ink),_glyph_row(lift,"PASSIVE",ship.passives,PASSIVES_Y,ink)]
	# Stats against the hull flying now: green up, coral down (footprint is size, not good or bad).
	var stats: Array = []
	for stat: Array in [["SPEED","%.0f",ship.speed,current.speed if current != null else ship.speed,1],["BUFFER","×%.2f",ship.hp_buffer,current.hp_buffer if current != null else ship.hp_buffer,1],["MAGNET","%.0f px",ship.magnet_radius,current.magnet_radius if current != null else ship.magnet_radius,1],["SIZE","%.0f px",ship.footprint,current.footprint if current != null else ship.footprint,0]]:
		var value: Label = UiKit.label(lift,"%s %s" % [stat[0],str(stat[1]) % float(stat[2])],Vector2(20,STATS_Y),Vector2.ZERO,UiTokens.TEXT_XS,WHITE)
		var delta: Label = UiKit.label(lift,delta_text(float(stat[2]),float(stat[3]),str(stat[1])),Vector2(20,STATS_Y),Vector2.ZERO,UiTokens.TEXT_XS,delta_color(float(stat[2])-float(stat[3]),int(stat[4])))
		stats.append([value,delta])
	var choice: Button = button(lift,"CHOOSE SHIP",Rect2(20,BUTTON_Y,290,40),_pick.bind(ship.id))
	var entry: Dictionary = {"id":ship.id,"ship":ship,"card":card,"lift":lift,"panel":panel,"backing":backing,"glow":glow,"button":choice,"preview":preview,"ink":ink,"rows":rows,"stats":stats,"chip":chip,"kicker":kicker}
	card.mouse_entered.connect(func() -> void: if not choice.has_focus(): choice.grab_focus())
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			card.accept_event()
			_pick(ship.id))
	choice.focus_entered.connect(_on_card_focus.bind(entry,true))
	choice.focus_exited.connect(_on_card_focus.bind(entry,false))
	return entry

## A row of `ids`' glyphs after a kicker, and a label of their names under it. Returns [row, names].
func _glyph_row(parent: Control, kicker_text: String, ids: Array, y: float, ink: Color) -> Array:
	var row := Control.new()
	row.name = kicker_text.capitalize()+"Row"
	row.position = Vector2(20,y)
	row.size = Vector2(290,ROW_GLYPH)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var kicker: Label = UiKit.label(row,kicker_text,Vector2(0,5),Vector2(76,18),UiTokens.TEXT_XS,MUTED)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	kicker.autowrap_mode = TextServer.AUTOWRAP_OFF
	var glyph_x: float = 80.0
	for id: Variant in ids:
		if glyph_x+ROW_GLYPH > row.size.x: break
		var glyph := Glyph.new()
		glyph.id = str(id)
		glyph.ink = ink
		glyph.position = Vector2(glyph_x,0)
		glyph.size = Vector2(ROW_GLYPH,ROW_GLYPH)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)
		glyph_x += ROW_GLYPH+6.0
	var names: Label = UiKit.label(parent,UiKit.ability_names(ids).replace(", "," · "),Vector2(20,y+ROW_GLYPH+3.0),Vector2(290,18),UiTokens.TEXT_S,WHITE if not ids.is_empty() else MUTED)
	return [row,names]

## "↑20", "↓0.10", or "=" for the same value, in the stat's own format.
static func delta_text(value: float, current: float, format: String) -> String:
	var difference: float = value-current
	if absf(difference) < 0.005: return "="
	var amount: String = (format.replace("×","").replace(" px","")) % absf(difference)
	return ("↑" if difference > 0.0 else "↓")+amount

## Green for better, coral for worse; `sense` 0 is a stat that is neither (muted).
static func delta_color(difference: float, sense: int) -> Color:
	if absf(difference) < 0.005 or sense == 0: return MUTED
	return VisualStyle.GREEN if difference*float(sense) > 0.0 else VisualStyle.CORAL

func _footer_text() -> String:
	if InputPrompts.shared().device == InputPrompts.PAD: return "TIME SLOWED  ·  HOLD A ON A CARD  ·  B TO DECIDE LATER"
	return "TIME SLOWED  ·  CLICK A CARD OR PRESS 1–%d  ·  ESC TO DECIDE LATER" % mini(_cards.size(),PICK_KEYS.size())

func _slide_in(card: Control, index: int) -> void:
	var rest: Vector2 = card.position
	card.position = rest+Vector2(0,CARD_SLIDE if not UiMotion.reduced else 0.0)
	card.modulate.a = 0.0
	var motion: Tween = UiMotion.tween(card).set_parallel(true)
	var wait: float = UiMotion.duration(0.05+CARD_STAGGER*index)
	# Only y: the corridor (relayout, and a re-split in tick) owns x.
	motion.tween_property(card,"position:y",rest.y,UiMotion.duration(UiTokens.SLOW)).set_delay(wait).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	motion.tween_property(card,"modulate:a",1.0,UiMotion.duration(UiTokens.BASE,true)).set_delay(wait).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)

## Focus is hover: the focused card lifts, lights its edge in its element and runs its preview fast.
## Moving focus between cards also restarts the auto-close: the player is still choosing.
func _on_card_focus(entry: Dictionary, focused: bool) -> void:
	var lift: Control = entry.lift
	if not is_instance_valid(lift): return
	if focused: _open_elapsed = 0.0
	var motion: Tween = UiMotion.tween(lift)
	motion.tween_property(lift,"position:y",-CARD_LIFT if focused else 0.0,UiMotion.duration(UiTokens.FAST)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	var ink: Color = entry.ink
	var panel: Panel = entry.panel
	if focused: panel.add_theme_stylebox_override("panel",UiKit.glass_box(UiTokens.GLASS_RAISED,ink,2,UiTokens.RADIUS_PANEL))
	else: panel.add_theme_stylebox_override("panel",UiKit.glass_panel(Color(ink,0.45)))
	var glow: Control = entry.glow
	UiMotion.tween(glow).tween_property(glow,"modulate:a",1.0 if focused else 0.0,UiMotion.duration(UiTokens.FAST,true))
	(entry.preview as ShipPreview).preview_time_scale = PREVIEW_HOVER_SPEED if focused else 1.0
	# M19: the focused hull, ghosted over the ship. Focus leaving every card (to DECIDE LATER) fades
	# it; focus moving card to card swaps it (the exit of one card lands before the next one's entry).
	if not ghost_enabled: return
	if focused and not is_instance_valid(_ghost): _ghost = HullGhost.attach(app.get("compositor") as CombatCompositor,app.get("combat") as CombatWorld)
	if is_instance_valid(_ghost):
		if focused: _ghost.show_hull(entry.ship as ShipDefinition)
		elif _ghost.hull_id == (entry.ship as ShipDefinition).id: _ghost.show_hull(null)

## The card whose button has focus (-1: none, e.g. a tab or DECIDE LATER).
func _focused_card() -> int:
	for index: int in range(_cards.size()):
		if (_cards[index].button as Button).has_focus(): return index
	return -1

## Keys 1/2/3 pick at once; the pad's A on a focused card starts the hold instead of pressing it.
## Called before the GUI sees the event (ScreenRouter.input). True: consumed.
func handle_input(event: InputEvent) -> bool:
	if _picked: return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var index: int = PICK_KEYS.find(key)
		if index >= 0 and index < _cards.size():
			_pick(str(_cards[index].id))
			return true
		return false
	# The pad's own keys, by button: the project's ui_* actions carry no pad buttons. The d-pad walks
	# the cards, B decides later.
	if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
		var from: int = maxi(0,_focused_card())
		var step: int = -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
		if not _cards.is_empty(): (_cards[clampi(from+step,0,_cards.size()-1)].button as Button).grab_focus()
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		ui_cue(app,"ui_back")
		app._close_overlay()
		return true
	if event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_A or event.is_action("ui_accept")):
		if event.pressed:
			var focused: int = _focused_card()
			if focused < 0: return false
			_hold_index = focused
			_hold_elapsed = 0.0
			var button: Button = _cards[focused].button
			_ring.position = host.get_global_transform().affine_inverse()*button.global_position+Vector2(8.0,(button.size.y-_ring.size.y)*0.5)
			_ring.visible = true
			return true
		if _hold_index >= 0:
			_cancel_hold()
			return true
	return false

## Real-time upkeep (ScreenRouter.tick): the hold ring, the countdown and the auto-close.
func tick(delta: float) -> void:
	if _picked: return
	if InputPrompts.shared().device != _device:
		_device = InputPrompts.shared().device
		_footer.text = _footer_text()
		for key: Label in _key_hints: key.visible = _device != InputPrompts.PAD
	# M19: the ship flew under a card - open the corridor where it is now.
	if avoid_ship and not (is_instance_valid(_resplit) and _resplit.is_running()) and ship_under_card(): _place_cards(_card_targets(),true)
	if _hold_index >= 0:
		if _focused_card() != _hold_index:
			_cancel_hold()
		else:
			_hold_elapsed += delta
			_ring.progress = _hold_elapsed/HOLD_SECONDS
			_ring.queue_redraw()
			if _hold_elapsed >= HOLD_SECONDS: _pick(str(_cards[_hold_index].id))
			return
	_open_elapsed += delta
	if is_instance_valid(_countdown):
		var left: float = clampf(1.0-_open_elapsed/AUTO_CLOSE_SECONDS,0.0,1.0)
		_countdown.size.x = 240.0*left
		_countdown.position.x = 640.0-_countdown.size.x*0.5
	if _open_elapsed >= AUTO_CLOSE_SECONDS: app._close_overlay()

func _cancel_hold() -> void:
	_hold_index = -1
	_hold_elapsed = 0.0
	_ring.progress = 0.0
	_ring.visible = false

func _pick(id: String) -> void:
	if _picked: return
	_picked = true
	ui_cue(app,"evolve_pick")
	app._choose_evolution(id)
	# Refused (the light fell below the threshold in the slow motion): the cards stay pickable.
	if app.overlay_kind == "evolution" and app.screen_router.stack.back().screen == self: _picked = false
