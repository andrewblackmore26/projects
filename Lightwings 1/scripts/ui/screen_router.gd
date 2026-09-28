class_name ScreenRouter
extends RefCounted
## The overlay screens (modernization M2): a stack of UiScreens drawn into one host Control
## (main.gd's `overlay` group), and the policy table that says what each screen does to the run.
## It replaces main.gd's SCREEN_POLICY and its _open_overlay/_close_overlay pair; main.gd keeps
## forwarders with the old names (`overlay_kind`, `_close_overlay`, `_close_options`, `_show_*`),
## because tests and package_validation.gd drive the game through them.
##
## This is the ONLY writer of `get_tree().paused` for overlays, and the only place a screen's
## time-scale request (`dilation`) is made, through RunController's broker.
##
## Only the top screen is ever built: pushing a screen clears the host and builds the new one, and
## popping clears it and builds the screen below again. So the host's DIRECT children are exactly
## the top screen's nodes (tests count ShipPreviews among `app.overlay.get_children()`). Today the
## stack is at most two deep: Options pushed over Pause (`returns`).
##
## Policy fields:
## - `kind`: the name main.gd's `overlay_kind` reports. Screens that shared an overlay kind before
##   the move keep sharing it (level select and the confirm dialogs are "confirm"; level complete
##   is "ending").
## - `pauses`: opening it in play pauses the tree.
## - `escape_closes`: Escape/ui_cancel is allowed to close it.
## - `freezes_sim` (P7, spec §7.4/§24 frictionless death): the sim is stopped WITHOUT pausing the
##   tree, so a timer and fresh-press detection can still run while it is up.
## - `any_input_dismiss`: a fresh press (not a hold, not motion) dismisses it.
## - `auto_close`: seconds after which it dismisses itself even with no input.
## - `input_guard`: seconds during which even a fresh press is ignored, so the press that caused
##   death cannot also dismiss the card the player never saw.
## - `returns`: closing it (DONE, Escape) returns to the screen below in play, or restores the focus
##   it was opened from; every other screen closes the whole stack.
## - `sound`: the soundscape context while it is up in play (outside play it is always "menu").
## - `backdrop`: "opaque" (a full-screen BG rect) for every screen today; M5 adds none/dim/dim_blur.
## - `dilation`: sim time scale requested while it is up; 0 = no request (every screen today; M12
##   slows the sim under Evolution with it).
## - `blocks_hud`: the screen covers the HUD. True for every screen today (the backdrop is opaque);
##   M11's floating HUD reads it.

const DEFAULT_POLICY: Dictionary = {"kind": "", "pauses": true, "escape_closes": true, "freezes_sim": false, "any_input_dismiss": false, "auto_close": 0.0, "input_guard": 0.0, "returns": false, "sound": "pause", "backdrop": "opaque", "dilation": 0.0, "blocks_hud": true}
const POLICY: Dictionary = {
	"evolution": {"pauses": true, "escape_closes": true},
	"map": {"pauses": true, "escape_closes": true},
	"pause": {"pauses": true, "escape_closes": true},
	"options": {"pauses": true, "escape_closes": true, "returns": true},
	"death": {"pauses": false, "escape_closes": false, "freezes_sim": true, "any_input_dismiss": true, "auto_close": GameTuning.DEATH_CARD_SECONDS, "input_guard": GameTuning.DEATH_INPUT_GUARD_SECONDS},
	"ending": {"pauses": true, "escape_closes": false},
	"level_complete": {"kind": "ending", "pauses": true, "escape_closes": false},
	"cloud": {"pauses": true, "escape_closes": true},
	"confirm": {"pauses": true, "escape_closes": true},
	"level_select": {"kind": "confirm", "pauses": true, "escape_closes": true},
}
const SCREENS: Dictionary = {
	"evolution": preload("res://scripts/ui/screens/evolution_screen.gd"),
	"map": preload("res://scripts/ui/screens/map_screen.gd"),
	"pause": preload("res://scripts/ui/screens/pause_screen.gd"),
	"options": preload("res://scripts/ui/screens/options_screen.gd"),
	"death": preload("res://scripts/ui/screens/death_card_screen.gd"),
	"ending": preload("res://scripts/ui/screens/ending_screen.gd"),
	"level_complete": preload("res://scripts/ui/screens/level_complete_screen.gd"),
	"cloud": preload("res://scripts/ui/screens/cloud_review_screen.gd"),
	"confirm": preload("res://scripts/ui/screens/confirm_screen.gd"),
	"level_select": preload("res://scripts/ui/screens/level_select_screen.gd"),
}
const DILATION_REASON: StringName = &"screen"

var app: Node
var host: Control
## Bottom first. Each entry: {id, args, screen, focus (WeakRef or null)}.
var stack: Array[Dictionary] = []
var _dilated: bool = false
## Screens that have exited, held until idle time: a screen's own button callback (a tab that
## closes and reopens Evolution, Options' DONE) is still running when the stack lets go of it.
var _retired: Array[UiScreen] = []

func _init(owner: Node, overlay_host: Control) -> void:
	app = owner
	host = overlay_host

## Every field for `id`, the defaults filled in; `kind` defaults to the id itself.
static func policy(id: String) -> Dictionary:
	var result: Dictionary = DEFAULT_POLICY.duplicate()
	result.kind = id
	result.merge(POLICY.get(id, {}), true)
	return result

func top_id() -> String:
	return str(stack.back().id) if not stack.is_empty() else ""

## The legacy overlay kind of the top screen ("" when nothing is open).
func kind() -> String:
	return str(policy(top_id()).kind) if not stack.is_empty() else ""

func top_policy() -> Dictionary:
	return policy(top_id())

## Opens `id` over the current screen, which comes back when this one returns (`returns`).
func push(id: String, args: Dictionary = {}) -> UiScreen:
	var focused: Control = app.get_viewport().gui_get_focus_owner()
	if not stack.is_empty(): _exit(stack.back())
	stack.append({"id": id, "args": args, "screen": null, "focus": weakref(focused) if focused != null else null})
	return _build(stack.back())

## Swaps the top screen for `id` (or opens it on an empty stack). The screens below stay.
func replace(id: String, args: Dictionary = {}) -> UiScreen:
	if stack.is_empty(): return push(id, args)
	var entry: Dictionary = stack.back()
	_exit(entry)
	entry.id = id
	entry.args = args
	return _build(entry)

## Closes the top screen. In play, the screen below is built again; otherwise the focus the top
## screen was opened from comes back (Options over the main menu).
func pop() -> void:
	if stack.is_empty(): return
	var popped: Dictionary = stack.back()
	var below: Dictionary = stack[stack.size() - 2] if stack.size() > 1 else {}
	var focus: Control = popped.focus.get_ref() as Control if popped.focus != null else null
	close_all()
	if not below.is_empty() and app.mode == "play": push(str(below.id), below.args)
	elif is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()

## Escape/ui_cancel on the top screen: nothing when its policy forbids it, else pop a screen that
## returns and close everything otherwise.
func escape() -> bool:
	var current: Dictionary = top_policy()
	if not bool(current.escape_closes): return false
	if bool(current.returns): pop()
	else: close_all()
	return true

func close_all() -> void:
	for entry: Dictionary in stack: _exit(entry)
	stack.clear()
	UiKit.clear(host)
	host.visible = false
	app.rebind_action = ""
	app.get_tree().paused = false
	if _dilated:
		app.run_controller.release_time_scale(DILATION_REASON)
		_dilated = false
	if app.sound != null: app.sound.set_context("play" if app.mode == "play" else "menu")
	if is_instance_valid(app.combat): app.combat.set_command(ShipCommand.new())

func _exit(entry: Dictionary) -> void:
	var screen: UiScreen = entry.screen
	if screen == null: return
	entry.screen = null
	screen.exit()
	if _retired.is_empty(): _release_retired.call_deferred()
	_retired.append(screen)

func _release_retired() -> void:
	_retired.clear()

func _build(entry: Dictionary) -> UiScreen:
	var id: String = str(entry.id)
	var current: Dictionary = policy(id)
	UiKit.clear(host)
	host.visible = true
	if str(current.backdrop) == "opaque":
		var shade := ColorRect.new()
		shade.color = VisualStyle.BG
		shade.size = Vector2(1280, 800)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		host.add_child(shade)
	app.get_tree().paused = app.mode == "play" and bool(current.pauses)
	if float(current.dilation) > 0.0:
		app.run_controller.request_time_scale(DILATION_REASON, float(current.dilation))
		_dilated = true
	elif _dilated:
		app.run_controller.release_time_scale(DILATION_REASON)
		_dilated = false
	app.sound.set_context(str(current.sound) if app.mode == "play" else "menu")
	app.dialogue.visible = false
	var screen: UiScreen = SCREENS[id].new()
	entry.screen = screen
	screen.request_pop.connect(pop)
	screen.enter({"app": app, "host": host, "args": entry.args})
	var focus: Control = screen.default_focus()
	if focus != null: focus.grab_focus()
	return screen
