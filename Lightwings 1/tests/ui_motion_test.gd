extends SceneTree
## Modernization M5: UiMotion's contract.
## - Every helper's tween runs while the tree is paused and ignores Engine.time_scale.
##   Control: a plain bound tween (the engine default) on the same node under the same pause.
## - Reduced motion (UiMotion.reduced) is honoured in ONE place, duration(): a whole screen's worth
##   of motion (a 20-item stagger, exit, pop, shake, count_up, bar_to) finishes within
##   UiTokens.REDUCED_FADE_CAP. Control: a helper-shaped tween that bypasses duration().
## - The real router: opening Pause over a paused run staggers its buttons in and they settle.
## Times are wall-clock; a frame adds up to FRAME_SLACK, stated in the summary.
var failures: int = 0
var checks: int = 0
var caught: int = 0
const FRAME_SLACK: float = 0.03

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func control(failed: bool, label: String, detail: String) -> void:
	checks += 1
	if failed:
		caught += 1
		print("negative control caught: %s (%s)" % [label, detail])
	else:
		failures += 1
		push_error("negative control NOT caught: " + label)

## Seconds until every tween in `tweens` has finished (or `limit`).
func _settle(tweens: Array, limit: float = 2.0) -> float:
	var start: int = Time.get_ticks_usec()
	while true:
		var running: bool = false
		for item: Tween in tweens:
			if item != null and item.is_valid() and item.is_running(): running = true
		var elapsed: float = (Time.get_ticks_usec() - start) / 1000000.0
		if not running or elapsed > limit: return elapsed
		await process_frame
	return limit

func _panel(parent: Node, at: Vector2) -> Control:
	var node := Panel.new()
	node.position = at
	node.size = Vector2(120, 40)
	parent.add_child(node)
	return node

## One screen's worth of every helper, on fresh nodes under `parent`. Returns the tweens.
func _everything(parent: Control) -> Array:
	var tweens: Array = []
	var items: Array = []
	for index: int in range(20): items.append(_panel(parent, Vector2(40, 30 + index * 30)))
	tweens.append_array(UiMotion.stagger(items))
	tweens.append(UiMotion.exit(_panel(parent, Vector2(400, 40))))
	tweens.append(UiMotion.pop(_panel(parent, Vector2(400, 100))))
	tweens.append(UiMotion.shake(_panel(parent, Vector2(400, 160))))
	var label := Label.new()
	parent.add_child(label)
	tweens.append(UiMotion.count_up(label, 0.0, 250.0))
	var bar := ProgressBar.new()
	parent.add_child(bar)
	tweens.append(UiMotion.bar_to(bar, 80.0))
	return tweens

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var stage := Control.new()
	root.add_child(stage)
	# The first frames carry the start-up time in their delta; measure after them.
	for i: int in range(5): await process_frame

	# 1. Paused tree and a 5 % time scale: the UI still animates at wall-clock speed.
	paused = true
	Engine.time_scale = 0.05
	var subject: Control = _panel(stage, Vector2(300, 300))
	var entering: Tween = UiMotion.enter(subject)
	var bound: Control = _panel(stage, Vector2(600, 300))
	bound.modulate.a = 0.0
	var plain: Tween = bound.create_tween()
	plain.tween_property(bound, "modulate:a", 1.0, UiTokens.BASE)
	var paused_seconds: float = await _settle([entering], 1.5)
	print("measure: enter under pause at time scale 0.05 settled in %.3f s (SLOW %.2f s)" % [paused_seconds, UiTokens.SLOW])
	check(is_equal_approx(subject.modulate.a, 1.0) and subject.position.is_equal_approx(Vector2(300, 300)), "enter completes while paused (alpha %.2f, y %.1f)" % [subject.modulate.a, subject.position.y])
	check(paused_seconds <= UiTokens.SLOW + FRAME_SLACK * 2.0 and paused_seconds >= UiTokens.SLOW - FRAME_SLACK, "enter takes its SLOW rise in wall-clock time despite the 5%% time scale (%.3f s)" % paused_seconds)
	control(bound.modulate.a < 0.5, "a plain bound tween under the same pause", "alpha %.2f after %.3f s" % [bound.modulate.a, paused_seconds])
	plain.kill()
	paused = false
	Engine.time_scale = 1.0

	# 2. Reduced motion: everything within the fade cap.
	var full: float = await _settle(_everything(stage))
	UiMotion.reduced = true
	var reduced_seconds: float = await _settle(_everything(stage))
	print("measure: one screen of motion takes %.3f s normally, %.3f s under reduced motion (cap %.2f s + %.2f s frame slack)" % [full, reduced_seconds, UiTokens.REDUCED_FADE_CAP, FRAME_SLACK])
	check(reduced_seconds <= UiTokens.REDUCED_FADE_CAP + FRAME_SLACK, "reduced motion: total %.3f s <= %.2f s" % [reduced_seconds, UiTokens.REDUCED_FADE_CAP])
	check(full > UiTokens.REDUCED_FADE_CAP + FRAME_SLACK, "the same motion takes longer without reduced motion (%.3f s)" % full)
	var rogue_node: Control = _panel(stage, Vector2(700, 500))
	var rogue: Tween = UiMotion.tween(rogue_node)
	rogue.tween_property(rogue_node, "position:y", 520.0, UiTokens.BASE)
	var rogue_seconds: float = await _settle([rogue])
	control(rogue_seconds > UiTokens.REDUCED_FADE_CAP + FRAME_SLACK, "a tween that bypasses duration()", "%.3f s under reduced motion" % rogue_seconds)
	UiMotion.reduced = false
	stage.queue_free()

	# 3. The router: Pause over a paused run enters, and settles within the stagger budget.
	SaveService.storage_root = "user://ui-motion-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	app._new_game(false)
	await process_frame
	app._show_pause()
	check(paused and app.overlay_kind == "pause", "Pause pauses the run")
	var buttons: Array[Button] = []
	for child: Node in app.overlay.get_children():
		if child is Button: buttons.append(child)
	var last: Button = buttons.back() if not buttons.is_empty() else null
	check(last != null and last.modulate.a < 0.5, "Pause's last button starts its entrance transparent")
	var budget: float = UiTokens.STAGGER_MAX + UiTokens.SLOW
	await create_timer(budget + FRAME_SLACK * 2.0, true, false, true).timeout
	var settled: bool = true
	for button: Button in buttons: settled = settled and is_equal_approx(button.modulate.a, 1.0)
	check(settled, "every Pause button is fully in after %.2f s while paused" % budget)
	var backdrop: Node = app.overlay.get_child(0)
	check(backdrop.name == &"Backdrop" and backdrop.material is ShaderMaterial and is_equal_approx(backdrop.modulate.a, 1.0), "Pause sits on the dim_blur backdrop, faded fully in")
	app._close_overlay()
	await process_frame
	await app._stop_audio()
	app.queue_free()
	await process_frame

	print("UI motion: %d checks, %d failures (%d negative controls caught)" % [checks, failures, caught])
	quit(1 if failures else 0)
