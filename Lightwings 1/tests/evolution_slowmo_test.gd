extends SceneTree
## Modernization M12: the evolution cards are picked in slow motion, through the real main.gd.
## - the sim runs at 0.25 while the cards are open: sim_q advances 180 +- 12 (one tick) over 60
##   steps of 1/60 s. Control: the dilation released while the cards stay open (the scale ignored);
## - the player still moves, but fires nothing. Control: the fire hold lifted;
## - no warp can be engaged, however long the player pushes into the rim. Control: the warp hold
##   lifted;
## - closing the cards releases the dilation and both holds;
## - keys 1/2/3 pick at once; the pad's A must be HELD for 0.25 s on a focused card (a released
##   hold never picks), and the d-pad walks the cards; Escape and the pad's B decide later; the cards
##   close by themselves after 8 s of real time and keep the offers;
## - the open latency (building the cards), measured and reported.
## The world is stepped by hand at a fixed 1/60 s and main.gd's own frames are off, so every
## number is exact.

const Harness = preload("res://tests/support/harness.gd")
const STEP: float = 1.0 / 60.0
const Q_PER_TICK: int = 12

var t: RefCounted
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("EVOLUTION SLOWMO")
	SaveService.storage_root = "user://evolution-slowmo-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	_rate()
	_move_and_fire()
	_warp()
	_keys()
	await _pad_hold()
	_decide_later_and_auto_close()
	_open_latency()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	t.finish(self)

## A fresh run with enough light to evolve, a world stepped only by hand, and the player out of
## harm's way (the origin's training wave must not end the life mid-measurement).
func _fresh_run() -> CombatWorld:
	app._close_overlay()
	app._new_game(false)
	var combat: CombatWorld = app.combat
	combat.set_physics_process(false)
	combat.collect_light(20.0,"fire")
	combat.collect_light(20.0,"corruption")
	combat.collect_light(20.0,"plasma")
	combat.player_invulnerable = 1000.0
	return combat

func _step(combat: CombatWorld, steps: int, command: ShipCommand = null) -> void:
	for index: int in range(steps):
		if command != null: combat.set_command(command)
		combat._physics_process(STEP)

func _sim_q_over(combat: CombatWorld, steps: int) -> int:
	var before: int = combat.sim_q
	_step(combat,steps)
	return combat.sim_q-before

func _rate() -> void:
	var combat: CombatWorld = _fresh_run()
	var full: int = _sim_q_over(combat,60)
	app._show_evolution()
	t.check(app.overlay_kind == "evolution" and not paused,"The cards open over a running (not paused) tree")
	var post: PostFx = (app.get_node("FeelDirector") as FeelDirector).post
	t.check(is_equal_approx(post.focus_desaturation,ScreenRouter.EVOLUTION_DESATURATE),"The world behind the cards is asked to desaturate to %.0f%% colour (got %.2f)" % [(1.0-ScreenRouter.EVOLUTION_DESATURATE)*100.0,post.focus_desaturation])
	var dilated: int = _sim_q_over(combat,60)
	var expected: int = roundi(60*Q_PER_TICK*ScreenRouter.EVOLUTION_DILATION)
	print("measure: 60 steps advance sim_q by %d at full speed and %d with the cards open (expected %d +- %d)" % [full,dilated,expected,Q_PER_TICK])
	t.check(full == 60*Q_PER_TICK,"Without the cards 60 steps are 720 sim_q (got %d)" % full)
	t.check(absi(dilated-expected) <= Q_PER_TICK,"With the cards open the sim advances at 0.25 +- 1 tick (got %d q, expected %d)" % [dilated,expected])
	# Control: the scale ignored - the router's request released while the cards stay up.
	app.run_controller.release_time_scale(ScreenRouter.DILATION_REASON)
	var ignored: int = _sim_q_over(combat,60)
	t.control("the dilation released while the cards stay open (%d q)" % ignored,absi(ignored-expected) > Q_PER_TICK)
	app._close_overlay()
	t.check(is_equal_approx(combat.time_scale(),1.0) and not combat.fire_suppressed and not combat.warp_engage_blocked and post.focus_desaturation == 0.0,"Closing the cards releases the dilation, both holds and the desaturation")

func _move_and_fire() -> void:
	var combat: CombatWorld = _fresh_run()
	app._show_evolution()
	var command := ShipCommand.new()
	command.movement = Vector2.LEFT
	command.aim = Vector2.UP
	command.fire = true
	command.secondaries.assign([true,true,true])
	var start: Vector2 = combat.player_position
	var shots: int = int(combat.player.get("shots_fired",0))
	_step(combat,120,command)
	var moved: float = combat.player_position.distance_to(start)
	var fired: int = int(combat.player.get("shots_fired",0))-shots
	print("measure: with the cards open the player moved %.1f px and fired %d shot(s) in 120 steps" % [moved,fired])
	t.check(moved > 5.0,"The player still moves while the cards are open (%.1f px)" % moved)
	t.check(fired == 0,"No shot is fired while the cards are open (%d)" % fired)
	# Control: the fire hold lifted, cards still open.
	combat.fire_suppressed = false
	shots = int(combat.player.get("shots_fired",0))
	_step(combat,120,command)
	t.control("the fire hold lifted with the cards open (%d shots)" % (int(combat.player.get("shots_fired",0))-shots),int(combat.player.get("shots_fired",0))-shots > 0)
	app._close_overlay()

## Pushes into the right rim for `steps` steps; returns the furthest warp phase reached.
func _push_rim(combat: CombatWorld, steps: int) -> int:
	combat.player_position = combat.arena.center+Vector2.RIGHT*(combat.arena.radius-12.0)
	combat.player.vel = Vector2.ZERO
	var command := ShipCommand.new()
	command.movement = Vector2.RIGHT
	command.aim = Vector2.RIGHT
	var furthest: int = combat.warp_phase
	for index: int in range(steps):
		combat.set_command(command)
		combat._physics_process(STEP)
		furthest = maxi(furthest,combat.warp_phase)
	return furthest

func _warp() -> void:
	var combat: CombatWorld = _fresh_run()
	app._show_evolution()
	# 240 steps at 0.25 is a full second of pushing, several times the press it takes to commit.
	var phase: int = _push_rim(combat,240)
	t.check(phase == CombatWorld.WARP_NONE and combat.warp_push_q == 0,"No warp press even starts while the cards are open (phase %d, push %d q)" % [phase,combat.warp_push_q])
	t.check(app.campaign.current_sector == Vector2i.ZERO,"...and the node never changes")
	# Control: the warp hold lifted, cards still open (on a world of its own: a commit swaps nodes).
	combat = _fresh_run()
	app._show_evolution()
	combat.warp_engage_blocked = false
	var lifted: int = _push_rim(combat,240)
	t.control("the warp hold lifted with the cards open (phase %d)" % lifted,lifted != CombatWorld.WARP_NONE)
	app._close_overlay()

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _keys() -> void:
	var combat: CombatWorld = _fresh_run()
	app._show_evolution()
	var offers: Array = app.pending_offers.duplicate()
	app._input(_key(KEY_4))
	t.check(app.overlay_kind == "evolution" and combat.hull_id == "player_seed","Key 4 picks nothing when three cards are up")
	app._input(_key(KEY_2))
	t.check(combat.hull_id == str(offers[1]) and app.overlay_kind != "evolution","Key 2 picks the second card at once (%s)" % combat.hull_id)
	var transform: Node = app.get_node_or_null("EvolutionTransform")
	var renderer: ShipRenderer = combat.player.get("renderer") as ShipRenderer
	t.check(transform != null and renderer != null and renderer.assembly_t < 1.0,"The pick starts the transformation: the new hull is assembling (assembly_t %.2f)" % (renderer.assembly_t if renderer != null else -1.0))

func _pad(pressed: bool, button: JoyButton = JOY_BUTTON_A) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.device = 0
	return event

func _pad_hold() -> void:
	var combat: CombatWorld = _fresh_run()
	app._show_evolution()
	await process_frame # focus settles on the first card's button
	var offers: Array = app.pending_offers.duplicate()
	app._input(_pad(true))
	app.screen_router.tick(0.10)
	app.screen_router.tick(0.10)
	t.check(app.overlay_kind == "evolution" and combat.hull_id == "player_seed","A 0.20 s hold of A has not picked yet")
	app._input(_pad(false))
	app.screen_router.tick(0.20)
	t.check(app.overlay_kind == "evolution" and combat.hull_id == "player_seed","A hold released early never picks")
	app._input(_pad(true))
	for index: int in range(3): app.screen_router.tick(0.09)
	t.check(combat.hull_id == str(offers[0]) and app.overlay_kind != "evolution","Holding A for 0.25 s picks the focused card (%s)" % combat.hull_id)
	app._input(_pad(false))
	# The d-pad walks the cards; the hold then picks the card it landed on. B decides later.
	combat = _fresh_run()
	app._show_evolution()
	await process_frame
	offers = app.pending_offers.duplicate()
	app._input(_pad(true,JOY_BUTTON_DPAD_RIGHT))
	app._input(_pad(true,JOY_BUTTON_DPAD_RIGHT))
	app._input(_pad(true))
	for index: int in range(3): app.screen_router.tick(0.09)
	t.check(combat.hull_id == str(offers[2]),"D-pad right twice then a held A picks the third card (%s)" % combat.hull_id)
	app._input(_pad(false))
	combat = _fresh_run()
	app._show_evolution()
	offers = app.pending_offers.duplicate()
	app._input(_pad(true,JOY_BUTTON_B))
	t.check(app.overlay_kind == "" and app.pending_offers == offers and combat.hull_id == "player_seed","Pad B decides later and keeps the offers")

func _decide_later_and_auto_close() -> void:
	_fresh_run()
	app._show_evolution()
	var offers: Array = app.pending_offers.duplicate()
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	app._unhandled_input(escape)
	t.check(app.overlay_kind == "" and app.pending_offers == offers,"Escape decides later and keeps the offers")
	app._show_evolution()
	app.screen_router.tick(7.9)
	t.check(app.overlay_kind == "evolution","The cards are still up after 7.9 s")
	app.screen_router.tick(0.2)
	t.check(app.overlay_kind == "" and app.pending_offers == offers,"After 8 s of real time the cards close by themselves and keep the offers")

func _open_latency() -> void:
	var samples: Array[float] = []
	for index: int in range(5):
		_fresh_run()
		var began: int = Time.get_ticks_usec()
		app._show_evolution()
		samples.append(float(Time.get_ticks_usec()-began)/1000.0)
		app._close_overlay()
	samples.sort()
	print("measure: evolution open latency (headless build of three cards) median %.2f ms, max %.2f ms over %d opens" % [samples[samples.size()/2],samples[-1],samples.size()])
	t.check(samples[-1] < 250.0,"Opening the cards builds in under 250 ms headless (max %.2f ms)" % samples[-1])
