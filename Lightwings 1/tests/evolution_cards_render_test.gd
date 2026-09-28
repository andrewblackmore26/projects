extends SceneTree
## Modernization M19, real Vulkan pixels of the evolution cards over a live run (the real main.gd,
## 1280x800 - the project's 1.6 aspect, so the capture does not letterbox):
## - CORRIDOR: the ship's core is still seen through the open cards: the mean luminance of a patch
##   on the ship's core stays >= 60 % of the same patch with no cards up;
## - GHOST: focusing a card draws its hull over the ship: the light in a ring around the ship
##   (outside the ship's own hull, inside the offer's reach) rises when the ghost is up.
## Controls: the pre-M19 centred row (EvolutionScreen.avoid_ship off) puts an opaque card over the
## core (CORRIDOR); the ghost at alpha 0 (GHOST).
## Captures for a human look: artifacts/evolution_cards_corridor.png (ghost up) and
## artifacts/evolution_cards_centred_row.png (the control). The runner fails on any SHADER ERROR.

const Harness = preload("res://tests/support/harness.gd")

var t: RefCounted
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("EVOLUTION CARDS PIXELS")
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://evolution-cards-render-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_physics_process(false)
	for i: int in range(3): await process_frame
	app._new_game(false)
	app._close_overlay()
	app.line_queue.clear()
	var combat: CombatWorld = app.combat
	combat.set_physics_process(false)
	combat.player_invulnerable = 1000.0
	combat.light_total = EvolutionRules.threshold(combat.player_tier)
	await _settle(0.3)
	var ship: Vector2 = _ship_px()
	var bare: Image = _capture()
	app._show_evolution()
	await _settle(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.3)
	var screen: EvolutionScreen = app.screen_router.stack.back().screen as EvolutionScreen
	(screen._cards[1].button as Button).grab_focus()
	await _settle(HullGhost.FADE_SECONDS + 0.2)
	var ghosted: Image = _capture()
	var card_scale: float = (screen._cards[0].card as Control).scale.x
	var ghost: HullGhost = screen._ghost
	var reach: float = ShipPreview.animated_radius(ShipCatalog.get_ship(str(screen._cards[1].id)))
	var own: float = ShipPreview.animated_radius(combat.player.definition)
	if is_instance_valid(ghost) and ghost._fade != null: ghost._fade.kill()
	if is_instance_valid(ghost): ghost.modulate.a = 0.0
	await _settle(0.1)
	var unghosted: Image = _capture()
	if is_instance_valid(ghost): ghost.visible = false
	await _settle(0.1)
	var reference: Image = _capture()
	if is_instance_valid(ghost): ghost.visible = true
	EvolutionScreen.avoid_ship = false
	app.screen_router.relayout()
	await _settle(0.2)
	var centred: Image = _capture()
	EvolutionScreen.avoid_ship = true
	var core_bare: float = _lum(bare, ship, 3.0)
	var core_open: float = _lum(ghosted, ship, 3.0)
	var core_centred: float = _lum(centred, ship, 3.0)
	var ring_inner: float = minf(own * 0.5, reach * 0.4)
	var ring_ghost: float = _ring(ghosted, ship, ring_inner, reach)
	var ring_none: float = _ring(unghosted, ship, ring_inner, reach)
	var ring_reference: float = _ring(reference, ship, ring_inner, reach)
	var ring_base: float = _ring(bare, ship, ring_inner, reach)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	ghosted.save_png("res://artifacts/evolution_cards_corridor.png")
	unghosted.save_png("res://artifacts/evolution_cards_no_ghost.png")
	centred.save_png("res://artifacts/evolution_cards_centred_row.png")
	print("measure: ship at %s px; core luma no cards %.4f, corridor %.4f, centred row %.4f; ring %.0f-%.0f px luma ghost %.5f, ghost at alpha 0 %.5f, ghost hidden %.5f, no cards %.5f; card scale %.3f" % [ship, core_bare, core_open, core_centred, ring_inner, reach, ring_ghost, ring_none, ring_reference, ring_base, card_scale])
	t.check(bare.get_size() == root.size, "the capture is the full root.size (%s)" % bare.get_size())
	t.check(core_bare > 0.05, "the ship's core is lit with no cards up (%.4f)" % core_bare)
	t.check(core_open >= core_bare * 0.6, "with the cards up the ship's core is still seen: >= 60%% of its luma with none (%.4f of %.4f)" % [core_open, core_bare])
	t.control("the pre-M19 centred row over the ship (core %.4f)" % core_centred, core_centred < core_bare * 0.6)
	t.check(ring_ghost > ring_reference * 1.25 + 0.0005, "the focused offer's ghost lights the ring around the ship (%.5f vs %.5f with the ghost hidden)" % [ring_ghost, ring_reference])
	t.control("the ghost at alpha 0 (ring %.5f vs %.5f hidden)" % [ring_none, ring_reference], not (ring_none > ring_reference * 1.25 + 0.0005))
	await app._stop_audio()
	app.queue_free()
	await process_frame
	t.finish(self)

func _settle(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	await process_frame
	await RenderingServer.frame_post_draw

func _capture() -> Image:
	return root.get_texture().get_image()

func _ship_px() -> Vector2:
	var compositor: CombatCompositor = app.compositor
	return compositor.get_global_transform_with_canvas() * compositor.world_to_screen(app.combat.player_position)

func _linear(image: Image, c: Color) -> Color:
	return c.srgb_to_linear() if image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8] else c

func _luma(image: Image, x: int, y: int) -> float:
	var c: Color = _linear(image, image.get_pixel(x, y))
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## Mean luma of the disc of `radius` px at `at`.
func _lum(image: Image, at: Vector2, radius: float) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(floori(at.y - radius), ceili(at.y + radius) + 1):
		for x: int in range(floori(at.x - radius), ceili(at.x + radius) + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			if Vector2(x, y).distance_to(at) > radius: continue
			total += _luma(image, x, y)
			count += 1
	return total / maxf(1.0, float(count))

## Mean luma of the ring between `inner` and `outer` px around `at`.
func _ring(image: Image, at: Vector2, inner: float, outer: float) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(floori(at.y - outer), ceili(at.y + outer) + 1):
		for x: int in range(floori(at.x - outer), ceili(at.x + outer) + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var d: float = Vector2(x, y).distance_to(at)
			if d < inner or d > outer: continue
			total += _luma(image, x, y)
			count += 1
	return total / maxf(1.0, float(count))
