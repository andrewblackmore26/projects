extends SceneTree
## Modernization M15: every screen M15 owns can be driven with a pad or arrow keys alone.
##
## For each screen, built in the real main.gd, the test replays ui_up/ui_down/ui_left/ui_right
## (InputEventActions pushed through the viewport, so a row that consumes left/right is exercised
## as the player meets it) from the default focus until the set of reached controls stops growing:
## - REACH: every visible, enabled, focusable Control of the screen is reached;
## - RETURN: from every reached control the default focus can be reached again (no dead-end cycle);
## - INSIDE: focus never leaves the screen (onto the title or the HUD behind a modal);
## - CANCEL: ui_cancel closes the screen exactly when its policy (ScreenRouter `escape_closes`) says
##   so, and never touches a screen that says no.
## A press that changes a setting, a toggle or a tab is undone before the next press, so the walk
## measures navigation, not the side effects of a spinner.
## Plus: the launch -> control time (process start to the title's primary action holding focus),
## the rebinding modal (it opens on a press, holds focus away from the screen, Escape closes it and
## focus returns to the row), and the dialogue box's skip input and auto-hide timing.
## Negative controls, one per instrument line: an orphan button (REACH), a button whose four
## neighbours are itself (RETURN), a neighbour pointed at the HUD behind Pause (INSIDE), the cancel
## check run against Ending (escape_closes = false) as if it should close (CANCEL), a title whose
## primary action takes focus only after a 2.6 s intro (launch), a skip that does not finish the
## typing (skip).
const Harness = preload("res://tests/support/harness.gd")
const ViewportMatrix = preload("res://tests/support/viewport_matrix.gd")

const SCREENS: Array[String] = ["title", "title_saves", "level_select_campaign", "level_select_dev", "options_audio", "options_display", "options_gameplay", "options_controls", "options_accessibility", "options_over_pause", "pause", "level_complete", "ending_campaign", "ending_demo", "confirm_new", "import_confirm", "cloud"]
const DIRECTIONS: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
const LAUNCH_BUDGET_MS: int = 2500

var h := Harness.new("UI focus nav")
var settings_file: String = ""
var measured: Dictionary = {"screens": 0, "controls": 0, "presses": 0}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	settings_file = "user://ui-focus-nav-%d.cfg" % Time.get_ticks_usec()
	await _launch()
	for screen: String in SCREENS:
		await _screen(screen)
	print("measure: %d screens walked, %d focusable controls, %d presses" % [measured.screens, measured.controls, measured.presses])
	await _rebind_modal()
	await _dialogue()
	await _controls()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))
	h.finish(self)

func _new_app() -> Node:
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://ui-focus-nav-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	app.settings_path = settings_file
	root.add_child(app)
	return app

func _free(app: Node) -> void:
	await app._stop_audio()
	app.queue_free()
	await process_frame
	await process_frame

func _step(app: Node, ticks: int) -> void:
	app.combat.set_physics_process(false)
	for tick: int in range(ticks): app.combat._physics_process(1.0 / 60.0)

func _write_saves(app: Node) -> void:
	app._new_game(true)
	SaveService.save_snapshot(app.campaign.to_dict(), {}, "demo")
	app._new_game(false)
	SaveService.save_snapshot(app.campaign.to_dict(), {}, "campaign")

func _build(app: Node, screen: String) -> void:
	match screen:
		"title": pass
		"title_saves":
			_write_saves(app)
			app._show_menu()
		"level_select_campaign": app._show_level_select("campaign")
		"level_select_dev": app._show_level_select("dev")
		"options_audio", "options_display", "options_gameplay", "options_controls", "options_accessibility":
			app.options_tab = OptionsScreen.TAB_TITLES.find(screen.trim_prefix("options_").capitalize())
			app._show_options()
		"options_over_pause", "pause":
			app._new_game(false)
			_step(app, 1)
			app._close_overlay()
			app._show_pause()
			if screen == "options_over_pause": app._show_options()
		"level_complete":
			app._new_game(false)
			_step(app, 1)
			app._show_level_complete({"next_level": 2, "revealed_element": "fire"})
		"ending_campaign", "ending_demo":
			app._new_game(screen == "ending_demo")
			_step(app, 1)
			app._show_ending(screen == "ending_demo")
		"confirm_new": app._confirm_new(false)
		"import_confirm":
			_write_saves(app)
			app._show_menu()
			app._import_demo()
		"cloud":
			app.cloud_review = {"state": "conflict", "local_summary": "Level 2 · T3 · 14 nodes", "remote_summary": "Level 1 · T2 · 6 nodes"}
			app._show_cloud_review()

## The Control the screen's nodes live under: the router's host, or the title's group.
func _host(app: Node) -> Control:
	return app.overlay if app.overlay.visible else app.menu

## Every visible, enabled, focusable Control under `host` (internal children included: a
## TabContainer's tab strip is one).
func _focusables(host: Control) -> Array[Control]:
	var result: Array[Control] = []
	var pending: Array[Node] = [host]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children(true))
		if not node is Control or node == host: continue
		var control: Control = node
		if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE: continue
		if control is BaseButton and (control as BaseButton).disabled: continue
		result.append(control)
	return result

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	root.push_input(release)
	measured.presses += 1

## Everything a press may change besides focus, so the walk can put it back.
func _state(app: Node) -> Dictionary:
	var tabs: TabContainer = app.overlay.get_node_or_null("OptionsTabs") if app.overlay.visible else null
	return {"settings": app.settings.duplicate(true), "tab": tabs.current_tab if tabs != null else -1, "kind": app.overlay_kind}

func _restore(app: Node, before: Dictionary, focused: Control) -> void:
	if app.settings != before.settings:
		for key: Variant in before.settings: app.settings[key] = before.settings[key]
		app.apply_settings()
		app.save_settings()
		if focused is OptionRow:
			var row: OptionRow = focused
			row.index = row._nearest(app.settings.get(str(row.name).trim_prefix("Row_")))
			row._refresh()
		elif focused is CheckButton:
			(focused as CheckButton).set_pressed_no_signal(bool(app.settings.get(str(focused.name).trim_prefix("Row_"))))
	var tabs: TabContainer = app.overlay.get_node_or_null("OptionsTabs") if app.overlay.visible else null
	if tabs != null and int(before.tab) >= 0 and tabs.current_tab != int(before.tab):
		tabs.current_tab = int(before.tab)
		await process_frame

## The focus graph from `start`: {control: {direction: control}} for every control reached, and
## every target that left `host` (as "outside" strings).
func walk(app: Node, host: Control, start: Control) -> Dictionary:
	var edges: Dictionary = {}
	var outside: PackedStringArray = []
	var queue: Array[Control] = [start]
	while not queue.is_empty():
		var at: Control = queue.pop_front()
		if edges.has(at): continue
		edges[at] = {}
		for direction: String in DIRECTIONS:
			if not is_instance_valid(at) or not at.is_visible_in_tree(): break
			at.grab_focus()
			var before: Dictionary = _state(app)
			_press(direction)
			var owner: Control = root.gui_get_focus_owner()
			await _restore(app, before, at)
			if owner == null: owner = at
			if not host.is_ancestor_of(owner):
				outside.append("%s --%s--> %s" % [at.name, direction, owner.get_path()])
				continue
			edges[at][direction] = owner
			if not edges.has(owner): queue.append(owner)
	return {"edges": edges, "outside": outside}

## The controls from which `target` can be reached, over `edges`.
static func reaching(edges: Dictionary, target: Control) -> Dictionary:
	var result: Dictionary = {target: true}
	var grew: bool = true
	while grew:
		grew = false
		for from: Variant in edges:
			if result.has(from): continue
			for to: Variant in edges[from].values():
				if result.has(to):
					result[from] = true
					grew = true
					break
	return result

## REACH, RETURN and INSIDE for the screen as it stands. Returns the number of failed lines.
func judge(app: Node, where: String) -> Dictionary:
	var host: Control = _host(app)
	var start: Control = root.gui_get_focus_owner()
	var focusables: Array[Control] = _focusables(host)
	var report: Dictionary = {"unreached": [], "trapped": [], "outside": []}
	if start == null or not host.is_ancestor_of(start):
		h.check(false, "%s: the screen opens with focus on one of its own controls (got %s)" % [where, start])
		return report
	var graph: Dictionary = await walk(app, host, start)
	var edges: Dictionary = graph.edges
	for control: Control in focusables:
		if not edges.has(control): report.unreached.append(str(control.name))
	var back: Dictionary = reaching(edges, start)
	for control: Variant in edges:
		if not back.has(control): report.trapped.append(str((control as Control).name))
	report.outside = graph.outside
	measured.controls += focusables.size()
	return report

func _screen(screen: String) -> void:
	var app: Node = _new_app()
	await process_frame
	_build(app, screen)
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.1, true, false, true).timeout
	var built: String = app.overlay_kind
	var report: Dictionary = await judge(app, screen)
	measured.screens += 1
	h.check(report.unreached.is_empty(), "%s REACH: every focusable is reached from the default focus (unreached: %s)" % [screen, ", ".join(report.unreached)])
	h.check(report.trapped.is_empty(), "%s RETURN: every reached control leads back to the default focus (trapped: %s)" % [screen, ", ".join(report.trapped)])
	h.check(report.outside.is_empty(), "%s INSIDE: focus never leaves the screen (%s)" % [screen, "; ".join(report.outside)])
	# Also still laid out cleanly at 1280x800 once walked (spinners and tabs were exercised).
	var controls: Array[Control] = ViewportMatrix.visible_controls(app.ui)
	var problems: PackedStringArray = ViewportMatrix.safe_violations(controls, app.ui.size, [app.ui, app.hud, app.menu, app.overlay, app.dialogue])
	problems.append_array(ViewportMatrix.text_overflows(controls))
	problems.append_array(ViewportMatrix.text_collisions(controls))
	h.check(problems.is_empty(), "%s: safe rect and text fit after the walk (%s)" % [screen, "; ".join(problems.slice(0, 4))])
	# CANCEL obeys the policy of the screen on top (the title, which is no router screen, stays).
	var expected: bool = not built.is_empty() and bool(app.screen_router.top_policy().escape_closes)
	var observed: bool = await _cancel(app)
	h.check(observed == expected, "%s CANCEL: ui_cancel %s the screen (policy escape_closes=%s, it %s)" % [screen, "closes" if expected else "leaves", str(expected), "closed" if observed else "stayed"])
	await _free(app)

## Presses ui_cancel; true when the screen that was up is gone (closed, or popped to the one below).
## The title has no stack: it "closes" only if the press left the menu.
func _cancel(app: Node) -> bool:
	var id: String = app.screen_router.top_id()
	var depth: int = app.screen_router.stack.size()
	_press("ui_cancel")
	await process_frame
	if depth == 0: return app.mode != "menu"
	return app.screen_router.stack.size() < depth or app.screen_router.top_id() != id

## Launch -> control: from process start to the title's primary action holding focus.
func _launch() -> void:
	var created_ms: int = Time.get_ticks_msec()
	var app: Node = _new_app()
	await process_frame
	var primary: Control = app.menu.find_child("Primary", true, false)
	var launch_ms: int = TitleScreen.cta_focus_msec
	print("measure: launch -> control %d ms (process start to the primary action focused; main.gd created at %d ms; headless)" % [launch_ms, created_ms])
	h.check(primary != null and root.gui_get_focus_owner() == primary and primary.focus_mode != Control.FOCUS_NONE, "the title opens with its primary action focused")
	h.check(launch_ms >= 0 and launch_ms <= LAUNCH_BUDGET_MS, "launch -> control within %d ms (measured %d ms)" % [LAUNCH_BUDGET_MS, launch_ms])
	h.check(TitleScreen.cta_focus_msec >= 0 and app.title_screen.intro_running(), "the primary action is focusable while the intro is still playing")
	# Any press skips the intro.
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	root.push_input(key)
	h.check(not app.title_screen.intro_running(), "a press finishes the title intro at once")
	await _free(app)

func _rebind_modal() -> void:
	var app: Node = _new_app()
	await process_frame
	app.options_tab = OptionsScreen.TAB_TITLES.find("Controls")
	app._show_options()
	await process_frame
	var row: Button = app.overlay.find_child("Bind_dash", true, false)
	h.check(row != null, "the Controls tab has a row for Dash")
	if row == null:
		await _free(app)
		return
	row.grab_focus()
	_press("ui_accept")
	await process_frame
	h.check(app.rebind_action == "dash" and app.overlay.find_child("RebindCard", true, false) != null and root.gui_get_focus_owner() == null, "confirm on a binding opens the rebinding modal and takes focus off the screen")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await process_frame
	var back: Control = root.gui_get_focus_owner()
	h.check(app.rebind_action.is_empty() and app.overlay.find_child("RebindCard", true, false) == null and app.overlay_kind == "options", "Escape closes the modal and leaves Options open")
	h.check(back != null and back.name == &"Bind_dash", "focus returns to the row that was being rebound (got %s)" % (back.name if back != null else "nothing"))
	await _free(app)

## The dialogue box: the typewriter runs at 60 chars/s, the skip input finishes it, the line then
## holds for max(4 s, 0.05 s/char), and a second skip dismisses it.
func _dialogue() -> void:
	var app: Node = _new_app()
	await process_frame
	app._new_game(false)
	app.line_queue.clear()
	var text: String = "A companion line of exactly enough length to measure how the typewriter paces it out."
	app.dialogue_director.queue_immediate("fire", "TIMING", text, "m15_timing")
	app._update_dialogue(0.0)
	var box: DialogueBox = app.dialogue_box
	var chars: int = text.length()
	var expected: float = chars / DialogueBox.CHARS_PER_SECOND + maxf(DialogueBox.HOLD_MIN, DialogueBox.HOLD_PER_CHAR * chars)
	print("measure: dialogue line %d chars: typing %.2f s + hold %.2f s = %.2f s up" % [chars, chars / DialogueBox.CHARS_PER_SECOND, maxf(DialogueBox.HOLD_MIN, DialogueBox.HOLD_PER_CHAR * chars), box.remaining])
	h.check(app.dialogue.visible and is_equal_approx(box.remaining, expected), "the line stays up for its typing plus max(4 s, 0.05 s/char) (%.2f s, expected %.2f s)" % [box.remaining, expected])
	var panel: Control = app.dialogue.get_node_or_null("DialoguePanel")
	var safe: Rect2 = UiLayout.safe_rect(app.ui.size)
	h.check(panel != null and panel.size.x <= DialogueBox.WIDTH + 0.5 and absf(panel.position.x - safe.position.x) < 0.5, "the box is a compact bottom-left panel (%s)" % (panel.get_rect() if panel != null else "none"))
	h.check(box.typing(), "the line types in")
	var skip := InputEventAction.new()
	skip.action = DialogueBox.SKIP_ACTION
	skip.pressed = true
	root.push_input(skip)
	var line: Label = app.dialogue.get_node("Line")
	h.check(not box.typing() and is_equal_approx(line.visible_ratio, 1.0) and app.dialogue.visible, "the skip input finishes the typing and keeps the line up")
	root.push_input(skip)
	h.check(not app.dialogue.visible, "a second skip dismisses the line")
	await _free(app)

## Each instrument line fails when its subject is sabotaged.
func _controls() -> void:
	# REACH: an orphan button (top_level, so no neighbour search and no explicit neighbour finds it).
	var app: Node = _new_app()
	await process_frame
	app._new_game(false)
	_step(app, 1)
	app._close_overlay()
	app._show_pause()
	await create_timer(0.1, true, false, true).timeout
	var resume: Button = root.gui_get_focus_owner() as Button
	var orphan := Button.new()
	orphan.name = "Orphan"
	orphan.text = "ORPHAN"
	orphan.top_level = true
	orphan.position = Vector2(600, 20)
	orphan.size = Vector2(120, 40)
	app.overlay.add_child(orphan)
	var report: Dictionary = await judge(app, "pause + orphan")
	h.control("an orphan button on Pause (REACH lists %s)" % str(report.unreached), "Orphan" in report.unreached)
	orphan.free()
	resume.grab_focus()
	# RETURN: a button every neighbour of which is itself, reachable from RESUME.
	var trap := Button.new()
	trap.name = "Trap"
	trap.text = "TRAP"
	trap.position = Vector2(150, 600)
	trap.size = Vector2(200, 40)
	app.overlay.add_child(trap)
	for side: String in ["focus_neighbor_left", "focus_neighbor_right", "focus_neighbor_top", "focus_neighbor_bottom"]: trap.set(side, NodePath("."))
	resume.focus_neighbor_left = resume.get_path_to(trap)
	resume.grab_focus()
	report = await judge(app, "pause + trap")
	h.control("a button whose four neighbours are itself (RETURN lists %s)" % str(report.trapped), "Trap" in report.trapped)
	trap.free()
	# INSIDE: RESUME's left neighbour pointed at the HUD's map button behind the blur.
	var hud_button: Control = null
	for node: Node in app.hud.find_children("*", "BaseButton", true, false):
		if (node as Control).is_visible_in_tree() and (node as Control).focus_mode != Control.FOCUS_NONE:
			hud_button = node
			break
	if hud_button == null:
		hud_button = Button.new()
		hud_button.name = "HudStandIn"
		hud_button.position = Vector2(20, 20)
		hud_button.size = Vector2(80, 30)
		app.hud.add_child(hud_button)
	resume.grab_focus()
	resume.focus_neighbor_left = resume.get_path_to(hud_button)
	report = await judge(app, "pause + escape hatch")
	h.control("RESUME's left neighbour on the HUD behind Pause (INSIDE lists %s)" % str(report.outside), not report.outside.is_empty())
	await _free(app)
	# CANCEL: Ending does not close on ui_cancel, so an instrument told it should reads a mismatch.
	app = _new_app()
	await process_frame
	app._new_game(false)
	_step(app, 1)
	app._show_ending(false)
	await process_frame
	var observed: bool = await _cancel(app)
	h.control("the cancel check run on Ending as if escape_closes were true (it %s)" % ("closed" if observed else "stayed"), observed != true)
	await _free(app)
	# Launch: a title whose primary action waits 2.6 s (a blocking intro) before it takes focus.
	var boot_ms: int = TitleScreen.cta_focus_msec
	TitleScreen.cta_focus_msec = -1
	app = _new_app()
	await process_frame
	var created: int = Time.get_ticks_msec()
	root.gui_release_focus()
	TitleScreen.cta_focus_msec = -1
	await create_timer(2.6, true, false, true).timeout
	app.title_screen.default_focus().grab_focus()
	var slow_ms: int = boot_ms + (TitleScreen.cta_focus_msec - created)
	h.control("a title that focuses its primary action after a 2.6 s intro (%d ms)" % slow_ms, slow_ms > LAUNCH_BUDGET_MS)
	await _free(app)
	# Skip: an "input" that leaves the typewriter running does not pass the skip line.
	app = _new_app()
	await process_frame
	app._new_game(false)
	app.line_queue.clear()
	app.dialogue_director.queue_immediate("fire", "TIMING", "A second line long enough to still be typing when it is checked.", "m15_skip_control")
	app._update_dialogue(0.0)
	var wrong := InputEventAction.new()
	wrong.action = "ui_focus_next"
	wrong.pressed = true
	root.push_input(wrong)
	h.control("a press of another action leaves the line typing", app.dialogue_box.typing())
	await _free(app)
