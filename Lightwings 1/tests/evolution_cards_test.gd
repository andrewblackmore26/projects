extends SceneTree
## Modernization M19: the evolution cards never hide the player's ship, and the focused offer is
## ghosted over it. Through the real main.gd, headless (the pixels are
## evolution_cards_render_test.gd's).
## - CORRIDOR: at every size of tests/support/viewport_matrix.gd, with the ship where the camera
##   keeps it (the centre) and pushed off-centre, no card's rect (as drawn: position, scale and the
##   canvas fit) touches the ship's disc (its animated radius on screen). The cards shrink only as
##   far as the corridor needs: the scale is measured and must stay >= MIN_CARD_SCALE.
## - RE-SPLIT: a ship that flies under a card while the cards are up gets its corridor back.
## - GHOST: focusing a card puts that hull over the ship (HullGhost, in the compositor's
##   foreground, at the player's position); moving focus swaps it; closing the cards removes it.
## Controls, one per line: the pre-M19 centred row (EvolutionScreen.avoid_ship off) covers the ship
## at 1280x800 (CORRIDOR) and never re-splits (RE-SPLIT); the ghost switched off (GHOST).

const Harness = preload("res://tests/support/harness.gd")
const ViewportMatrix = preload("res://tests/support/viewport_matrix.gd")

var t: RefCounted
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("EVOLUTION CARDS")
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://evolution-cards-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	await _corridor()
	await _resplit()
	await _ghost()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	t.finish(self)

func _open() -> EvolutionScreen:
	app._close_overlay()
	app._new_game(false)
	var combat: CombatWorld = app.combat
	combat.set_physics_process(false)
	combat.player_invulnerable = 1000.0
	combat.light_total = EvolutionRules.threshold(combat.player_tier)
	app._show_evolution()
	return app.screen_router.stack.back().screen as EvolutionScreen if app.overlay_kind == "evolution" else null

func _size(size: Vector2i) -> void:
	root.size = size
	app.apply_settings()
	await process_frame
	await process_frame

## The ship's disc in viewport px: (x, y, radius).
func _ship() -> Vector3:
	var compositor: CombatCompositor = app.compositor
	var at: Vector2 = compositor.get_global_transform_with_canvas() * compositor.world_to_screen(app.combat.player_position)
	return Vector3(at.x, at.y, ShipPreview.animated_radius(app.combat.player.definition) * compositor.zoom)

## Every card whose drawn rect (viewport px) touches the ship's disc, by name.
func _covering(screen: EvolutionScreen) -> Array[String]:
	var ship: Vector3 = _ship()
	var result: Array[String] = []
	for entry: Dictionary in screen._cards:
		var card: Control = entry.card
		var rect: Rect2 = card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
		if EvolutionScreen._disc_hits(rect, Vector2(ship.x, ship.y), ship.z): result.append(str(card.name))
	return result

func _smallest_scale(screen: EvolutionScreen) -> float:
	var smallest: float = 1.0
	for entry: Dictionary in screen._cards: smallest = minf(smallest, (entry.card as Control).scale.x)
	return smallest

## Moves the camera so the ship sits `offset` px (world) from the view's centre, and lays out again.
func _offset_ship(offset: Vector2) -> void:
	var compositor: CombatCompositor = app.compositor
	compositor.rig.reset(app.combat.player_position - offset)
	await process_frame
	app.screen_router.relayout()
	await process_frame

func _corridor() -> void:
	var screen: EvolutionScreen = _open()
	if not t.check(screen != null and screen._cards.size() == 3, "the three evolution cards are up"):
		return
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.1, true, false, true).timeout
	for size: Vector2i in ViewportMatrix.SIZES:
		await _size(size)
		for offset: Vector2 in [Vector2.ZERO, Vector2(-220, 0), Vector2(260, 60)]:
			await _offset_ship(offset)
			var ship: Vector3 = _ship()
			var covering: Array[String] = _covering(screen)
			var smallest: float = _smallest_scale(screen)
			print("measure: %s ship at (%.0f, %.0f) r %.0f: cards at scale %.3f, x %s" % [ViewportMatrix.label(size), ship.x, ship.y, ship.z, smallest, str(screen._cards.map(func(entry: Dictionary) -> int: return roundi((entry.card as Control).position.x)))])
			t.check(covering.is_empty(), "%s, ship offset %s: no card covers the ship (covering: %s)" % [ViewportMatrix.label(size), offset, ", ".join(covering)])
			t.check(smallest >= EvolutionScreen.MIN_CARD_SCALE - 0.0001, "%s, ship offset %s: the cards stay at scale >= %.2f (%.3f)" % [ViewportMatrix.label(size), offset, EvolutionScreen.MIN_CARD_SCALE, smallest])
	await _size(Vector2i(1280, 800))
	await _offset_ship(Vector2.ZERO)
	EvolutionScreen.avoid_ship = false
	app.screen_router.relayout()
	await process_frame
	var old: Array[String] = _covering(screen)
	t.control("the pre-M19 centred row at 1280x800 (covering: %s)" % ", ".join(old), not old.is_empty())
	EvolutionScreen.avoid_ship = true
	app._close_overlay()

## The ship flies under a card (the camera moved, the layout did not): the next tick glides the
## cards off it.
func _resplit() -> void:
	var screen: EvolutionScreen = _open()
	if screen == null: return
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.1, true, false, true).timeout
	var results: Array[bool] = []
	for avoid: bool in [true, false]:
		EvolutionScreen.avoid_ship = avoid
		await _offset_ship(Vector2.ZERO)
		app.compositor.rig.reset(app.combat.player_position + Vector2(-390, 0))
		await process_frame
		var under: bool = screen.ship_under_card()
		app.screen_router.tick(1.0 / 60.0)
		await create_timer(EvolutionScreen.RESPLIT_SECONDS + 0.15, true, false, true).timeout
		results.append(under and not screen.ship_under_card())
		print("measure: re-split (avoid %s): under a card before %s, after %s" % [avoid, under, screen.ship_under_card()])
	EvolutionScreen.avoid_ship = true
	t.check(results[0], "a ship that flies under a card gets its corridor back on the next tick")
	t.control("re-splitting off (the pre-M19 row)", not results[1])
	app._close_overlay()

func _ghost() -> void:
	var seen: Array = []
	for enabled: bool in [true, false]:
		EvolutionScreen.ghost_enabled = enabled
		var screen: EvolutionScreen = _open()
		if screen == null: return
		await process_frame
		var buttons: Array = screen._cards.map(func(entry: Dictionary) -> Button: return entry.button)
		(buttons[0] as Button).grab_focus()
		await create_timer(HullGhost.FADE_SECONDS + 0.1, true, false, true).timeout
		var ghost: HullGhost = screen._ghost
		var first: String = ghost.hull_id if is_instance_valid(ghost) else ""
		var up: bool = is_instance_valid(ghost) and ghost.get_parent() == app.compositor.foreground and is_equal_approx(ghost.modulate.a, HullGhost.ALPHA) and ghost.position.is_equal_approx(app.combat.player_position)
		(buttons[1] as Button).grab_focus()
		await create_timer(HullGhost.FADE_SECONDS + 0.1, true, false, true).timeout
		var second: String = ghost.hull_id if is_instance_valid(ghost) else ""
		var still_up: bool = is_instance_valid(ghost) and is_equal_approx(ghost.modulate.a, HullGhost.ALPHA)
		app._close_overlay()
		await process_frame
		await process_frame
		var gone: bool = not is_instance_valid(ghost) and app.compositor.foreground.find_children("*", "HullGhost", false, false).is_empty()
		seen.append({"first": first, "second": second, "up": up, "still_up": still_up, "gone": gone, "offers": [str(screen._cards[0].id), str(screen._cards[1].id)]})
	EvolutionScreen.ghost_enabled = true
	var on: Dictionary = seen[0]
	print("measure: ghost %s" % str(seen))
	t.check(on.up and on.first == on.offers[0], "focusing the first card ghosts its hull (%s) over the ship, at %.2f alpha" % [on.first, HullGhost.ALPHA])
	t.check(on.still_up and on.second == on.offers[1], "moving focus to the second card swaps the ghost to its hull (%s)" % on.second)
	t.check(on.gone, "closing the cards removes the ghost")
	t.control("the ghost switched off (first %s)" % str(seen[1].first), not (seen[1].up and seen[1].first == seen[1].offers[0]))
