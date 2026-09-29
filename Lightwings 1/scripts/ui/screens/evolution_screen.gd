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
## (green up, coral down). Focus - which is hover - lifts a card CARD_LIFT px, draws its white and
## gold double stroke and speeds its preview. The focused card's hull is ghosted over the ship
## (HullGhost, M19).
##
## M19 review: the cards keep clear of the player's ship - the player is still dodging in the slow
## motion - WITHOUT shrinking (a card at 0.6 scale set its stats at ~7 px). The row is docked in the
## lower band at full size, and the camera frames the ship in the clear band above it
## (CombatCompositor.set_frame: the view slides the ship up and, only if the ship is too big for the
## band, zooms out, never below FRAME_MIN_ZOOM). If the ship drifts into the cards or the header the
## framing glides after it. The header (title, hint, DECIDE LATER with its auto-close ring) sits
## just above the row, under the HUD band, and the HUD's top clusters dim while the cards are up.

## The row: three cards at full size, CARD_GAP apart, docked above the bottom edge's threat
## chevrons. A card's blocks are laid out by relayout from these design values (card-local).
const CARD_Y: float = 390.0
const CARD_SIZE: Vector2 = Vector2(380, 332)
const CARD_GAP: float = 18.0
const CARD_PITCH: float = CARD_SIZE.x + CARD_GAP
const PAD: float = 18.0
const NAME_Y: float = 40.0
const BODY_Y: float = 80.0
const PREVIEW_SIZE: Vector2 = Vector2(150, 150)
const COLUMN_X: float = PAD + PREVIEW_SIZE.x + 12.0
const COLUMN_WIDTH: float = CARD_SIZE.x - COLUMN_X - PAD
const STATS_GAP: float = 10.0
const BUTTON_HEIGHT: float = 36.0
const ROW_GLYPH: float = 26.0
## The header above the row: its bottom HEADER_GAP over the cards; the tabs (dev mode) over it.
const HEADER_GAP: float = 16.0
const LATER_SIZE: Vector2 = Vector2(236, 40)
const TABS_HEIGHT: float = 30.0

const AUTO_CLOSE_SECONDS: float = 8.0
const HOLD_SECONDS: float = 0.25
const CARD_STAGGER: float = 0.035
const CARD_SLIDE: float = 56.0
const CARD_LIFT: float = 8.0
## The focus double stroke: the card's own 2 px white edge, then a gold ring FOCUS_RING_GAP px out.
const FOCUS_RING_GAP: float = 3.0
const PREVIEW_HOVER_SPEED: float = 2.5
const PICK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
## The framing: the band the ship is framed in runs from under the HUD's top band to
## SHIP_CLEARANCE over the header; the view zooms out no further than FRAME_MIN_ZOOM to fit it, and
## the framing glides in over FRAME_SECONDS (a re-frame over RESPLIT_SECONDS).
const SHIP_CLEARANCE: float = 16.0
const FRAME_MIN_ZOOM: float = 0.7
const FRAME_SECONDS: float = 0.36
const RESPLIT_SECONDS: float = 0.18
## Test seams, each with its own control: the framing (off: the ship stays at the screen's centre,
## under the row) and the ghost.
static var avoid_ship: bool = true
static var ghost_enabled: bool = true

var _title: Label
var _hint: Label
var _later: Button
var _countdown: Countdown
var _tabs: Array[Button] = []
## One entry per card: {id, ship, card, lift, panel, backing, glow, button, preview, ink, rows (Array
## of [row node, names label]), stats (Array of [value label, delta label]), chip, kicker, key}.
var _cards: Array[Dictionary] = []
var _open_elapsed: float = 0.0
var _hold_index: int = -1
var _hold_elapsed: float = 0.0
var _picked: bool = false
var _ring: HoldRing
## The keys' hints on the cards, shown for keyboard and mouse only; the device they were drawn for.
var _key_hints: Array[Label] = []
var _device: String = ""
## The HUD's ability dock, faded out while the cards are up (it sits under the row).
var _dock: CanvasItem
## M19: the focused offer's hull over the ship, and the ship's animated radius (world px).
var _ghost: HullGhost
var _ship_radius: float = 0.0
## The framing's glide - one for every screen instance, so a reopened screen's glide replaces the
## last one's glide home instead of fighting it - and whether this screen has framed the ship yet
## (the first framing glides, a later layout snaps unless a glide is still running).
static var _frame_motion: Tween
var _framed: bool = false

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
		draw_arc(middle, radius, 0.0, TAU, 40, Color(UiTokens.FOCUS, 0.25), 3.0, true)
		draw_arc(middle, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40, UiTokens.FOCUS, 3.0, true)

## The auto-close, shown as a ring on DECIDE LATER: a stroke round the capsule that drains
## clockwise from the top centre as the AUTO_CLOSE_SECONDS run out. Neutral ink: it is a timer, not
## focus.
class Countdown extends Control:
	var left: float = 1.0
	func _draw() -> void:
		var inset: float = 1.0
		var box := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		var radius: float = box.size.y * 0.5
		var straight: float = maxf(0.0, box.size.x - 2.0 * radius)
		var perimeter: float = 2.0 * straight + TAU * radius
		if left <= 0.0: return
		var points := PackedVector2Array()
		var steps: int = maxi(2, ceili(96.0 * left))
		for step: int in range(steps + 1):
			points.append(_along(box, radius, straight, perimeter * left * float(step) / float(steps), perimeter))
		draw_polyline(points, Color(UiTokens.INK, 0.55), 2.0, true)
	## The point `s` px clockwise round the capsule from the middle of its top edge.
	static func _along(box: Rect2, radius: float, straight: float, s: float, perimeter: float) -> Vector2:
		var d: float = fposmod(s, perimeter)
		var half: float = straight * 0.5
		var top_y: float = box.position.y
		var middle_x: float = box.position.x + box.size.x * 0.5
		if d <= half: return Vector2(middle_x + d, top_y)
		d -= half
		var right := Vector2(box.end.x - radius, box.position.y + radius)
		if d <= PI * radius: return right + Vector2.from_angle(-PI * 0.5 + d / radius) * radius
		d -= PI * radius
		if d <= straight: return Vector2(right.x - d, box.end.y)
		d -= straight
		var left_centre := Vector2(box.position.x + radius, box.position.y + radius)
		if d <= PI * radius: return left_centre + Vector2.from_angle(PI * 0.5 + d / radius) * radius
		d -= PI * radius
		return Vector2(box.position.x + radius + d, top_y)

## M6: every block sits under the one above it however far its text wraps at the current text
## scale. Inside each card the glyph rows stack in the column right of the preview, the stats
## follow the taller of the two, then the button and the card's box. The header grows UP from its
## bottom HEADER_GAP over the row. At text scale 1 everything stays at the design's coordinates.
## All from the design y, not position.y: an entrance tween may be moving the cards (their inner
## nodes never move). Then the canvas is fitted and the ship framed above the row.
func relayout() -> void:
	var bottom: float = CARD_Y
	for entry: Dictionary in _cards:
		_layout_card(entry)
		bottom = maxf(bottom, CARD_Y + (entry.card as Control).size.y)
	var row: Rect2 = _row_rect()
	var header_bottom: float = CARD_Y - HEADER_GAP
	_later.size = Vector2(maxf(LATER_SIZE.x, _later.get_minimum_size().x), LATER_SIZE.y)
	_later.position = Vector2(row.end.x - _later.size.x, header_bottom - _later.size.y)
	_countdown.position = _later.position
	_countdown.size = _later.size
	# One line each, as wide as the text (a trimming Label reports no text width as its minimum), and
	# never into DECIDE LATER: past that they trim.
	var text_width: float = maxf(20.0, _later.position.x - 24.0 - row.position.x)
	for label: Label in [_title, _hint]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size = Vector2(minf(ceilf(UiLayout.text_width(label, label.text)) + 2.0, text_width), _line_height(label))
	_hint.position = Vector2(row.position.x, header_bottom - _hint.size.y)
	_title.position = Vector2(row.position.x, _hint.position.y - 4.0 - _title.size.y)
	for index: int in range(_tabs.size()):
		_tabs[index].position = Vector2(_tabs[index].position.x, minf(_title.position.y, _later.position.y) - 12.0 - TABS_HEIGHT)
	_place_cards()
	var area: Vector2 = (host.get_parent() as Control).size if host.get_parent() is Control else UiLayout.BASE_SIZE
	UiLayout.fit_canvas(host, area)
	_frame(_framed and not (is_instance_valid(_frame_motion) and _frame_motion.is_running()))
	_framed = true

## One line of `label` at its current font and size (its cached minimum can lag a text-scale change).
static func _line_height(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var size: int = label.get_theme_font_size(&"font_size")
	return ceilf(font.get_height(size)) if font != null else label.get_minimum_size().y

func _layout_card(entry: Dictionary) -> void:
	var chip: Label = entry.chip
	UiLayout.hug(chip)
	var kicker: Label = entry.kicker
	var key: Label = entry.get("key")
	var kicker_end: float = (key.position.x - 8.0) if key != null else CARD_SIZE.x - PAD
	kicker.position.x = chip.position.x + chip.size.x + 8.0
	kicker.size = Vector2(maxf(20.0, kicker_end - kicker.position.x), kicker.get_minimum_size().y)
	var y: float = BODY_Y
	var rows: Array = entry.rows
	for index: int in range(rows.size()):
		var row: Control = rows[index][0]
		var names: Label = rows[index][1]
		_layout_glyphs(row)
		row.position.y = y
		names.position.y = row.position.y + ROW_GLYPH + 3.0
		names.size = Vector2(COLUMN_WIDTH, 0.0)
		y = names.position.y + names.get_minimum_size().y + 8.0
	var stats_y: float = maxf(BODY_Y + PREVIEW_SIZE.y, y - 8.0) + STATS_GAP
	var stats: Array = entry.stats
	var column: float = (CARD_SIZE.x - 2.0 * PAD) * 0.5
	for index: int in range(stats.size()):
		var value: Label = stats[index][0]
		var delta: Label = stats[index][1]
		UiLayout.hug(value)
		UiLayout.hug(delta)
		var row_height: float = maxf(value.get_minimum_size().y, delta.get_minimum_size().y)
		value.position = Vector2(PAD + float(index % 2) * column, stats_y + float(index / 2) * (row_height + 2.0))
		delta.position = Vector2(value.position.x + value.size.x + 5.0, value.position.y)
	var last: Label = stats[-1][0]
	var button: Button = entry.button
	button.position.y = last.position.y + last.get_minimum_size().y + 10.0
	var height: float = maxf(CARD_SIZE.y, button.position.y + button.size.y + 14.0)
	for key_name: String in ["panel", "backing", "glow", "card", "lift"]: (entry[key_name] as Control).size.y = height

## The header, the tabs and the hold ring enter through the router's stagger; the cards slide up
## on their own (`_slide_in`), CARD_STAGGER apart.
func motion_items() -> Array:
	var cards: Array = _cards.map(func(entry: Dictionary) -> Node: return entry.card)
	return super().filter(func(node: Node) -> bool: return not cards.has(node))

func build() -> void:
	_title = UiKit.label(host, "BECOME SOMETHING NEW", Vector2(0, 0), Vector2.ZERO, UiTokens.TEXT_XL, WHITE)
	_title.name = "Title"
	_hint = UiKit.label(host, "", Vector2(0, 0), Vector2.ZERO, UiTokens.TEXT_XS, UiTokens.KICKER)
	_hint.name = "Hint"
	_hint.theme_type_variation = UiTokens.KICKER_LABEL
	for label: Label in [_title, _hint]: label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		var tab_x: float = 640.0 - (float(elements.size()) * 200.0 - 10.0) * 0.5
		for element: String in elements:
			var tab: Button = button(host, element.to_upper(), Rect2(tab_x, 0, 190, TABS_HEIGHT), func() -> void:
				app.evolution_tab = element
				app._close_overlay()
				app._show_evolution())
			tab.disabled = element == app.evolution_tab
			_tabs.append(tab)
			tab_x += 200.0
		shown = by_element.get(app.evolution_tab, [] as Array[String])
	var current: ShipDefinition = null
	if is_instance_valid(app.combat): current = ShipCatalog.get_ship(str(app.combat.hull_id))
	if is_instance_valid(app.combat): _ship_radius = ShipPreview.animated_radius(app.combat.player.get("definition") as ShipDefinition)
	for id: String in shown:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship == null: continue
		_cards.append(_build_card(ship, current, _cards.size()))
	if not _cards.is_empty(): _focus = _cards[0].button
	_later = button(host, "DECIDE LATER", Rect2(Vector2.ZERO, LATER_SIZE), app._close_overlay)
	_later.name = "DecideLater"
	_countdown = Countdown.new()
	_countdown.name = "Countdown"
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_countdown)
	_ring = HoldRing.new()
	_ring.name = "HoldRing"
	_ring.size = Vector2(34, 34)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false # shown only while a hold runs (hidden, it takes no part in the canvas fit)
	host.add_child(_ring)
	_device = InputPrompts.shared().device
	_refresh_prompts()
	_place_cards()
	for index: int in range(_cards.size()): _slide_in(_cards[index].card, index)
	var hud_view: Object = app.get("hud_view")
	var dock: Object = hud_view.get("dock") if hud_view != null else null
	_dock = dock.get("root") as CanvasItem if dock != null else null
	if is_instance_valid(_dock): UiMotion.tween(_dock).tween_property(_dock, "modulate:a", 0.0, UiMotion.duration(UiTokens.FAST, true))
	if hud_view != null and hud_view.has_method("set_dimmed"): hud_view.call("set_dimmed", true)

func exit() -> void:
	if is_instance_valid(_dock): UiMotion.tween(_dock).tween_property(_dock, "modulate:a", 1.0, UiMotion.duration(UiTokens.FAST, true))
	var hud_view: Object = app.get("hud_view")
	if hud_view != null and hud_view.has_method("set_dimmed"): hud_view.call("set_dimmed", false)
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	_glide_frame(Vector2.ZERO, 1.0, UiTokens.BASE)

## The row's rect on the canvas: `count` cards at full size, centred.
func _row_rect() -> Rect2:
	var width: float = float(_cards.size()) * CARD_PITCH - CARD_GAP if not _cards.is_empty() else CARD_SIZE.x
	return Rect2(640.0 - width * 0.5, CARD_Y, width, CARD_SIZE.y)

## The centred row, every card at scale 1 (the framing, not the cards, keeps the ship clear).
func _place_cards() -> void:
	var row: Rect2 = _row_rect()
	for index: int in range(_cards.size()):
		var card: Control = _cards[index].card
		card.position.x = row.position.x + float(index) * CARD_PITCH
		card.scale = Vector2.ONE

## M19: the ship's position and radius on this screen's canvas: (x, y, radius), radius < 0 when there
## is no ship on screen (no world, or no compositor).
func ship_on_canvas() -> Vector3:
	var compositor: CombatCompositor = app.get("compositor") as CombatCompositor
	var combat: CombatWorld = app.get("combat") as CombatWorld
	if not is_instance_valid(compositor) or not is_instance_valid(combat) or combat.player.is_empty() or not host.is_inside_tree(): return Vector3(0, 0, -1)
	var screen: Vector2 = compositor.get_global_transform_with_canvas() * compositor.world_to_screen(combat.player_position)
	var to_host: Transform2D = host.get_global_transform_with_canvas().affine_inverse()
	var at: Vector2 = to_host * screen
	return Vector3(at.x, at.y, _ship_radius * compositor.zoom * absf(to_host.get_scale().x))

## The framing that puts the ship in the clear band above the header: [offset (screen px), zoom
## factor]. The band runs from under the HUD's top band to SHIP_CLEARANCE over the header, on this
## canvas; the ship is centred in it, and the view zooms out only as far as the ship needs to fit
## (never below FRAME_MIN_ZOOM). No framing without a ship or with avoid_ship off. Dev mode's tabs
## sit over the header, so its band ends over them.
func _frame_target() -> Array:
	var compositor: CombatCompositor = app.get("compositor") as CombatCompositor
	var combat: CombatWorld = app.get("combat") as CombatWorld
	if not avoid_ship or _cards.is_empty(): return [Vector2.ZERO, 1.0]
	if not is_instance_valid(compositor) or not is_instance_valid(combat) or combat.player.is_empty() or not host.is_inside_tree(): return [Vector2.ZERO, 1.0]
	var from_host: Transform2D = host.get_global_transform_with_canvas()
	var to_screen: Transform2D = compositor.get_global_transform_with_canvas().affine_inverse()
	var hud_root: Control = app.get("hud") as Control
	var band_top: float = Hud.TOP_BAR + 8.0
	if is_instance_valid(hud_root):
		band_top = (from_host.affine_inverse() * (hud_root.get_global_transform_with_canvas() * Vector2(0.0, Hud.TOP_BAR + 8.0))).y
	var band_bottom: float = minf(_title.position.y, _later.position.y) - SHIP_CLEARANCE
	for tab: Button in _tabs: band_bottom = minf(band_bottom, tab.position.y - SHIP_CLEARANCE)
	# The band in screen px (the compositor's space).
	var top: float = (to_screen * (from_host * Vector2(0.0, band_top))).y
	var bottom: float = (to_screen * (from_host * Vector2(0.0, band_bottom))).y
	var radius: float = _ship_radius * compositor.rig.zoom
	var fit: float = clampf((bottom - top) * 0.5 / maxf(1.0, radius), FRAME_MIN_ZOOM, 1.0)
	var relative: Vector2 = (combat.player_position - compositor.rig.focus) * compositor.rig.zoom * fit
	var target_y: float = (top + bottom) * 0.5
	return [Vector2(0.0, target_y - compositor.screen_center().y - relative.y), fit]

## Frames the ship: a glide (the opening, a re-frame) or at once (a resize, a test's relayout).
func _frame(snap: bool) -> void:
	var target: Array = _frame_target()
	if snap:
		if is_instance_valid(_frame_motion): _frame_motion.kill()
		var compositor: CombatCompositor = app.get("compositor") as CombatCompositor
		if is_instance_valid(compositor): compositor.set_frame(target[0], target[1])
	else:
		_glide_frame(target[0], target[1], FRAME_SECONDS)

func _glide_frame(offset: Vector2, zoom_factor: float, seconds: float) -> void:
	var compositor: CombatCompositor = app.get("compositor") as CombatCompositor
	if not is_instance_valid(compositor): return
	if is_instance_valid(_frame_motion): _frame_motion.kill()
	var duration: float = UiMotion.duration(seconds)
	if duration <= 0.0:
		compositor.set_frame(offset, zoom_factor)
		return
	var from_offset: Vector2 = compositor.frame_offset
	var from_zoom: float = compositor.frame_zoom
	# On the compositor, which outlives this screen's host children, so the glide home on exit runs.
	_frame_motion = UiMotion.tween(compositor)
	_frame_motion.tween_method(func(t: float) -> void:
		if is_instance_valid(compositor): compositor.set_frame(from_offset.lerp(offset, t), lerpf(from_zoom, zoom_factor, t)), 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func _disc_hits(rect: Rect2, at: Vector2, radius: float) -> bool:
	var nearest := Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y))
	return nearest.distance_to(at) < radius

## True when the ship (its own disc, no clearance) is under a card as the cards stand now.
func ship_under_card() -> bool:
	var ship: Vector3 = ship_on_canvas()
	if ship.z < 0.0: return false
	for entry: Dictionary in _cards:
		var card: Control = entry.card
		if _disc_hits(Rect2(card.position, card.size * card.scale), Vector2(ship.x, ship.y), ship.z): return true
	return false

## True when the ship is under a card or the header (the title, hint, DECIDE LATER or a tab).
func _ship_blocked() -> bool:
	if ship_under_card(): return true
	var ship: Vector3 = ship_on_canvas()
	if ship.z < 0.0: return false
	var header: Array[Control] = [_title, _hint, _later]
	header.append_array(_tabs)
	for control: Control in header:
		if _disc_hits(control.get_rect(), Vector2(ship.x, ship.y), ship.z): return true
	return false

func _build_card(ship: ShipDefinition, current: ShipDefinition, index: int) -> Dictionary:
	var ink: Color = ElementStyle.color(ship.element)
	var card := Control.new()
	card.name = "Card%d" % (index + 1)
	card.position = Vector2(0, CARD_Y)
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host.add_child(card)
	var lift := Control.new()
	lift.name = "Lift"
	lift.size = CARD_SIZE
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lift)
	# Focus is a double stroke: the card's own edge turns white (the panel, below) and this gold ring
	# sits FOCUS_RING_GAP px outside it, faded in on focus. Drawn in the style's expand margin, so
	# the Control keeps the card's own rect (the canvas fit and the safe-rect check measure rects).
	var glow: Panel = UiKit.glass(lift, Rect2(Vector2.ZERO, CARD_SIZE))
	glow.name = "Glow"
	var ring: StyleBoxFlat = UiKit.glass_box(Color(0, 0, 0, 0), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_PANEL + int(FOCUS_RING_GAP + UiTokens.FOCUS_BORDER))
	ring.draw_center = false
	ring.shadow_size = 0
	ring.set_expand_margin_all(FOCUS_RING_GAP + UiTokens.FOCUS_BORDER)
	glow.add_theme_stylebox_override("panel", ring)
	glow.modulate.a = 0.0
	# An opaque backing under the glass: the world runs on behind the cards, and its HDR hulls (well
	# above 1.0 in linear light) showed through the glass, even over a 60% backing, as a ghost ship.
	var backing: Panel = UiKit.glass(lift, Rect2(Vector2.ZERO, CARD_SIZE))
	backing.name = "Backing"
	backing.add_theme_stylebox_override("panel", UiKit.glass_box(Color(UiTokens.GLASS, 1.0), Color(0, 0, 0, 0), 0, UiTokens.RADIUS_PANEL))
	var panel: Panel = UiKit.glass(lift, Rect2(Vector2.ZERO, CARD_SIZE), _rest_stroke(ink))
	# Element chip, tier and family, key hint.
	var chip: Label = UiKit.label(lift, ship.element.to_upper(), Vector2(PAD, 16), Vector2.ZERO, UiTokens.TEXT_XS, ink)
	chip.theme_type_variation = UiTokens.KICKER_LABEL
	var chip_box: StyleBoxFlat = UiKit.glass_box(Color(ink, 0.12), Color(ink, 0.55), 1, UiTokens.RADIUS_SMALL)
	chip_box.content_margin_left = 8
	chip_box.content_margin_right = 8
	chip_box.content_margin_top = 2
	chip_box.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", chip_box)
	UiLayout.hug(chip)
	# Placed after the chip by relayout (the chip's width follows the text scale).
	var kicker: Label = UiKit.label(lift, "T%d · %s" % [ship.tier, ship.family.replace("_", " ").to_upper()], Vector2(120, 18), Vector2(160, 20), UiTokens.TEXT_XS, MUTED)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	kicker.autowrap_mode = TextServer.AUTOWRAP_OFF
	kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var key: Label = null
	if index < PICK_KEYS.size():
		key = UiKit.label(lift, str(index + 1), Vector2(CARD_SIZE.x - PAD - 24.0, 15), Vector2(24, 22), UiTokens.TEXT_XS, WHITE)
		key.name = "KeyHint"
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var cap: StyleBoxFlat = UiKit.glass_box(UiTokens.GLASS_RAISED, UiTokens.STROKE, 1, UiTokens.RADIUS_SMALL)
		cap.content_margin_left = 0
		cap.content_margin_right = 0
		cap.content_margin_top = 0
		cap.content_margin_bottom = 0
		key.add_theme_stylebox_override("normal", cap)
		key.visible = InputPrompts.shared().device != InputPrompts.PAD
		_key_hints.append(key)
	var name_label: Label = UiKit.label(lift, ship.display_name, Vector2(PAD, NAME_Y), Vector2(CARD_SIZE.x - 2.0 * PAD, 30), UiTokens.TEXT_L, WHITE)
	name_label.theme_type_variation = UiTokens.DISPLAY_LABEL
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The live preview, square, the hull fitted to it by zoom (its animated radius, so no pose of it
	# ever leaves the frame).
	var preview := ShipPreview.new()
	preview.fit_margin = 6.0
	lift.add_child(preview)
	preview.position = Vector2(PAD, BODY_Y)
	preview.initialize(ship, PREVIEW_SIZE, 1.5)
	# Weapon and passive glyph rows, in the column right of the preview: the glyphs, then the names.
	var weapons: Array[String] = [ship.primary]
	weapons.append_array(ship.secondaries)
	var rows: Array = [_glyph_row(lift, "WEAPONS", weapons, BODY_Y, ink), _glyph_row(lift, "PASSIVE", ship.passives, BODY_Y, ink)]
	# Stats against the hull flying now: green up, coral down (footprint is size, not good or bad).
	var stats: Array = []
	for stat: Array in [["SPEED", "%.0f", ship.speed, current.speed if current != null else ship.speed, 1], ["BUFFER", "×%.2f", ship.hp_buffer, current.hp_buffer if current != null else ship.hp_buffer, 1], ["MAGNET", "%.0f px", ship.magnet_radius, current.magnet_radius if current != null else ship.magnet_radius, 1], ["SIZE", "%.0f px", ship.footprint, current.footprint if current != null else ship.footprint, 0]]:
		var value: Label = UiKit.label(lift, "%s %s" % [stat[0], str(stat[1]) % float(stat[2])], Vector2(PAD, 0), Vector2.ZERO, UiTokens.TEXT_XS, WHITE)
		var delta: Label = UiKit.label(lift, delta_text(float(stat[2]), float(stat[3]), str(stat[1])), Vector2(PAD, 0), Vector2.ZERO, UiTokens.TEXT_XS, delta_color(float(stat[2]) - float(stat[3]), int(stat[4])))
		stats.append([value, delta])
	var choice: Button = button(lift, "CHOOSE SHIP", Rect2(PAD, 0, CARD_SIZE.x - 2.0 * PAD, BUTTON_HEIGHT), _pick.bind(ship.id))
	var entry: Dictionary = {"id": ship.id, "ship": ship, "card": card, "lift": lift, "panel": panel, "backing": backing, "glow": glow, "button": choice, "preview": preview, "ink": ink, "rows": rows, "stats": stats, "chip": chip, "kicker": kicker, "key": key}
	card.mouse_entered.connect(func() -> void: if not choice.has_focus(): choice.grab_focus())
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			card.accept_event()
			_pick(ship.id))
	choice.focus_entered.connect(_on_card_focus.bind(entry, true))
	choice.focus_exited.connect(_on_card_focus.bind(entry, false))
	return entry

## A card's edge at rest: the element's colour, faint, so no resting card reads as focused.
static func _rest_stroke(ink: Color) -> Color:
	return UiTokens.STROKE.lerp(ink, 0.35)

## A row of `ids`' glyphs after a kicker, and a label of their names under it, in the card's right
## column. Returns [row, names].
func _glyph_row(parent: Control, kicker_text: String, ids: Array, y: float, ink: Color) -> Array:
	var row := Control.new()
	row.name = kicker_text.capitalize() + "Row"
	row.position = Vector2(COLUMN_X, y)
	row.size = Vector2(COLUMN_WIDTH, ROW_GLYPH)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var kicker: Label = UiKit.label(row, kicker_text, Vector2(0, 5), Vector2(76, 18), UiTokens.TEXT_XS, MUTED)
	kicker.name = "Kicker"
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	kicker.autowrap_mode = TextServer.AUTOWRAP_OFF
	for id: Variant in ids:
		var glyph := Glyph.new()
		glyph.id = str(id)
		glyph.ink = ink
		glyph.size = Vector2(ROW_GLYPH, ROW_GLYPH)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)
	_layout_glyphs(row)
	var names: Label = UiKit.label(parent, UiKit.ability_names(ids).replace(", ", " · ") if not ids.is_empty() else "None", Vector2(COLUMN_X, y + ROW_GLYPH + 3.0), Vector2(COLUMN_WIDTH, 18), UiTokens.TEXT_S, WHITE if not ids.is_empty() else MUTED)
	return [row, names]

## A glyph row's kicker at its text-scaled width, the glyphs after it; a glyph that would leave the
## column is hidden (the names under the row still list every ability).
static func _layout_glyphs(row: Control) -> void:
	var kicker: Label = row.get_node("Kicker")
	UiLayout.hug(kicker)
	kicker.position.y = (ROW_GLYPH - kicker.size.y) * 0.5
	var glyph_x: float = kicker.size.x + 6.0
	for child: Node in row.get_children():
		if not child is Glyph: continue
		var glyph := child as Glyph
		glyph.position = Vector2(glyph_x, 0)
		glyph.visible = glyph_x + ROW_GLYPH <= row.size.x
		glyph_x += ROW_GLYPH + 4.0

## "↑20", "↓0.10", or "=" for the same value, in the stat's own format.
static func delta_text(value: float, current: float, format: String) -> String:
	var difference: float = value - current
	if absf(difference) < 0.005: return "="
	var amount: String = (format.replace("×", "").replace(" px", "")) % absf(difference)
	return ("↑" if difference > 0.0 else "↓") + amount

## Green for better, coral for worse; `sense` 0 is a stat that is neither (muted).
static func delta_color(difference: float, sense: int) -> Color:
	if absf(difference) < 0.005 or sense == 0: return MUTED
	return VisualStyle.GREEN if difference * float(sense) > 0.0 else VisualStyle.CORAL

## The hint and DECIDE LATER's caption for the device in hand.
func _refresh_prompts() -> void:
	if InputPrompts.shared().device == InputPrompts.PAD:
		_hint.text = "TIME SLOWED  ·  HOLD A ON A CARD"
		_later.text = "DECIDE LATER  ·  B"
	else:
		_hint.text = "TIME SLOWED  ·  CLICK A CARD OR PRESS 1–%d" % mini(_cards.size(), PICK_KEYS.size())
		_later.text = "DECIDE LATER  ·  ESC"

func _slide_in(card: Control, index: int) -> void:
	var rest: Vector2 = card.position
	card.position = rest + Vector2(0, CARD_SLIDE if not UiMotion.reduced else 0.0)
	card.modulate.a = 0.0
	var motion: Tween = UiMotion.tween(card).set_parallel(true)
	var wait: float = UiMotion.duration(0.05 + CARD_STAGGER * index)
	# Only y: relayout owns x.
	motion.tween_property(card, "position:y", rest.y, UiMotion.duration(UiTokens.SLOW)).set_delay(wait).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	motion.tween_property(card, "modulate:a", 1.0, UiMotion.duration(UiTokens.BASE, true)).set_delay(wait).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)

## Focus is hover: the focused card lifts, draws its white and gold double stroke and runs its
## preview fast. Moving focus between cards also restarts the auto-close: the player is still
## choosing.
func _on_card_focus(entry: Dictionary, focused: bool) -> void:
	var lift: Control = entry.lift
	if not is_instance_valid(lift): return
	if focused: _open_elapsed = 0.0
	var motion: Tween = UiMotion.tween(lift)
	motion.tween_property(lift, "position:y", -CARD_LIFT if focused else 0.0, UiMotion.duration(UiTokens.FAST)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	var ink: Color = entry.ink
	var panel: Panel = entry.panel
	if focused: panel.add_theme_stylebox_override("panel", UiKit.glass_box(UiTokens.GLASS_RAISED, UiTokens.INK, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_PANEL))
	else: panel.add_theme_stylebox_override("panel", UiKit.glass_panel(_rest_stroke(ink)))
	var glow: Control = entry.glow
	UiMotion.tween(glow).tween_property(glow, "modulate:a", 1.0 if focused else 0.0, UiMotion.duration(UiTokens.FAST, true))
	(entry.preview as ShipPreview).preview_time_scale = PREVIEW_HOVER_SPEED if focused else 1.0
	# M19: the focused hull, ghosted over the ship. Focus leaving every card (to DECIDE LATER) fades
	# it; focus moving card to card swaps it (the exit of one card lands before the next one's entry).
	if not ghost_enabled: return
	if focused and not is_instance_valid(_ghost): _ghost = HullGhost.attach(app.get("compositor") as CombatCompositor, app.get("combat") as CombatWorld)
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
	if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		var from: int = maxi(0, _focused_card())
		var step: int = -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
		if not _cards.is_empty(): (_cards[clampi(from + step, 0, _cards.size() - 1)].button as Button).grab_focus()
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		ui_cue(app, "ui_back")
		app._close_overlay()
		return true
	if event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_A or event.is_action("ui_accept")):
		if event.pressed:
			var focused: int = _focused_card()
			if focused < 0: return false
			_hold_index = focused
			_hold_elapsed = 0.0
			var button: Button = _cards[focused].button
			_ring.position = host.get_global_transform().affine_inverse() * button.global_position + Vector2(8.0, (button.size.y - _ring.size.y) * 0.5)
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
		_refresh_prompts()
		for key: Label in _key_hints: key.visible = _device != InputPrompts.PAD
		relayout()
	# M19: the ship drifted under the row or the header - frame it in the clear band again.
	if avoid_ship and not (is_instance_valid(_frame_motion) and _frame_motion.is_running()) and _ship_blocked(): _glide_frame_to_target()
	if _hold_index >= 0:
		if _focused_card() != _hold_index:
			_cancel_hold()
		else:
			_hold_elapsed += delta
			_ring.progress = _hold_elapsed / HOLD_SECONDS
			_ring.queue_redraw()
			if _hold_elapsed >= HOLD_SECONDS: _pick(str(_cards[_hold_index].id))
			return
	_open_elapsed += delta
	if is_instance_valid(_countdown):
		_countdown.left = clampf(1.0 - _open_elapsed / AUTO_CLOSE_SECONDS, 0.0, 1.0)
		_countdown.queue_redraw()
	if _open_elapsed >= AUTO_CLOSE_SECONDS: app._close_overlay()

func _glide_frame_to_target() -> void:
	var target: Array = _frame_target()
	_glide_frame(target[0], target[1], RESPLIT_SECONDS)

func _cancel_hold() -> void:
	_hold_index = -1
	_hold_elapsed = 0.0
	_ring.progress = 0.0
	_ring.visible = false

func _pick(id: String) -> void:
	if _picked: return
	_picked = true
	ui_cue(app, "evolve_pick")
	app._choose_evolution(id)
	# Refused (the light fell below the threshold in the slow motion): the cards stay pickable.
	if app.overlay_kind == "evolution" and app.screen_router.stack.back().screen == self: _picked = false
