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
## popping clears it and builds the screen below again. So the host's children are exactly the top
## screen's nodes (M12: Evolution groups each card under one node, so tests count ShipPreviews among
## the host's descendants). Today the
## stack is at most two deep: Options pushed over Pause (`returns`).
##
## Policy fields:
## - `kind`: the name main.gd's `overlay_kind` reports. Screens that shared an overlay kind before
##   the move keep sharing it (level select and the confirm dialogs are "confirm"; level complete
##   is "ending").
## - `pauses`: opening it in play pauses the tree.
## - `escape_closes`: Escape/ui_cancel is allowed to close it.
##   (M12 retired P7's death-card fields `freezes_sim`, `any_input_dismiss`, `auto_close` and
##   `input_guard`: death is a non-modal banner now, and RunController reboots on its own timer.)
## - `holds_fire` / `holds_warp` (M12): while it is up in play the player fires nothing / cannot
##   engage a warp (CombatWorld.fire_suppressed / warp_engage_blocked; movement is untouched).
## - `returns`: closing it (DONE, Escape) returns to the screen below in play, or restores the focus
##   it was opened from; every other screen closes the whole stack.
## - `sound`: the soundscape context while it is up in play (outside play it is always "menu").
## - `backdrop` (M5): what lies between the screen and the game. "opaque" is a full-screen BG
##   rect; "dim" darkens the game toward the scrim; "dim_blur" blurs and darkens it
##   (shaders/ui_backdrop.gdshader, which falls back to dim only at blur_lod 0); "none" is nothing.
##   Pause, Options, Evolution and Map sit over the live game; the others stay opaque until M15.
##   A dim backdrop fades in over UiTokens.FAST and fades back out when the stack closes.
## - `dim` (M12): how far a dim backdrop darkens toward the scrim; < 0 is UiTokens.SCRIM_DIM.
##   Evolution dims lightly, with no blur, so the threats behind the cards stay readable.
## - `desaturate` (M12): world desaturation asked of PostFx (below the UI) while it is up in play.
## - `dilation`: sim time scale requested while it is up; 0 = no request. M12: Evolution runs the
##   sim at 0.25 instead of pausing it.
## - `blocks_hud`: the screen covers the HUD (M11's floating HUD reads it). False for Evolution
##   and the death banner, which leave the run on screen.
## - `layout` (M6): "canvas" lays the screen out on a 1280x800 design canvas that UiLayout.fit_canvas
##   centres and scales down into the safe rect (every screen today); "fill" makes the host the
##   whole UI rect, for a screen that anchors its own nodes (the backdrop is full-bleed either way).

const DEFAULT_POLICY: Dictionary = {"kind": "", "pauses": true, "escape_closes": true, "holds_fire": false, "holds_warp": false, "returns": false, "sound": "pause", "backdrop": "opaque", "dim": -1.0, "desaturate": 0.0, "dilation": 0.0, "blocks_hud": true, "layout": "canvas"}
## M12: the evolution cards' sim scale, and the share of colour the world keeps behind them (~40%).
const EVOLUTION_DILATION: float = 0.25
const EVOLUTION_DESATURATE: float = 0.6
const POLICY: Dictionary = {
	"evolution": {"pauses": false, "escape_closes": true, "backdrop": "dim", "dim": 0.35, "desaturate": EVOLUTION_DESATURATE, "dilation": EVOLUTION_DILATION, "holds_fire": true, "holds_warp": true, "blocks_hud": false},
	"map": {"pauses": true, "escape_closes": true, "backdrop": "dim_blur", "layout": "fill"},
	"pause": {"pauses": true, "escape_closes": true, "backdrop": "dim_blur"},
	"options": {"pauses": true, "escape_closes": true, "returns": true, "backdrop": "dim_blur"},
	"death": {"pauses": false, "escape_closes": false, "backdrop": "none", "sound": "play", "blocks_hud": false},
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
const BACKDROP_SHADER: Shader = preload("res://shaders/ui_backdrop.gdshader")

var app: Node
var host: Control
## Bottom first. Each entry: {id, args, screen, focus (WeakRef or null)}.
var stack: Array[Dictionary] = []
var _dilated: bool = false
## Screens that have exited, held until idle time: a screen's own button callback (a tab that
## closes and reopens Evolution, Options' DONE) is still running when the stack lets go of it.
var _retired: Array[UiScreen] = []
## The backdrop kind of the screen that is up ("" when the stack is closed), and the backdrop of a
## just-closed stack while it fades out (M5).
var _backdrop_kind: String = ""
var _backdrop_dim: float = -1.0
var _ghost: ColorRect

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
	if not stack.is_empty(): UiScreen.ui_cue(app, "ui_back") # M17
	if bool(current.returns): pop()
	else: close_all()
	return true

## M12: an input event for the top screen first (main.gd's `_input`, before the GUI sees it), for a
## screen with its own keys (Evolution's 1/2/3 and the pad's hold-to-confirm). True: consumed.
func input(event: InputEvent) -> bool:
	if stack.is_empty() or stack.back().screen == null: return false
	var screen: UiScreen = stack.back().screen
	return screen.has_method("handle_input") and bool(screen.call("handle_input", event))

## M12: real-time upkeep for the top screen (main.gd's `_process`): Evolution's hold ring and its
## auto-close. Real seconds, never the sim's: the sim is slowed underneath.
func tick(delta: float) -> void:
	if stack.is_empty() or stack.back().screen == null: return
	var screen: UiScreen = stack.back().screen
	if screen.has_method("tick"): screen.call("tick", delta)

## M12: what the top screen asks of the run underneath (`holds_fire`, `holds_warp`, `desaturate`),
## applied on every build and cleared by close_all. Outside play nothing is held.
func _apply_run_holds(current: Dictionary) -> void:
	var playing: bool = app.mode == "play"
	if is_instance_valid(app.combat):
		app.combat.fire_suppressed = playing and bool(current.holds_fire)
		app.combat.warp_engage_blocked = playing and bool(current.holds_warp)
	var director: Node = app.get_node_or_null("FeelDirector")
	if director != null and director.get("post") != null:
		director.post.focus_desaturation = float(current.desaturate) if playing else 0.0

func close_all() -> void:
	for entry: Dictionary in stack: _exit(entry)
	stack.clear()
	UiKit.clear(host)
	host.visible = false
	_fade_out_backdrop()
	app.rebind_action = ""
	app.get_tree().paused = false
	if _dilated:
		app.run_controller.release_time_scale(DILATION_REASON)
		_dilated = false
	_apply_run_holds(DEFAULT_POLICY)
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
	# A backdrop that was already up (Options pushed over Pause, or Pause built again when Options
	# returns) stays at full strength instead of fading in a second time.
	var continuing: bool = is_instance_valid(_ghost) or not _backdrop_kind.is_empty()
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	_backdrop_kind = str(current.backdrop)
	_backdrop_dim = float(current.dim)
	var backdrop: ColorRect = make_backdrop(_backdrop_kind, _backdrop_dim)
	if backdrop != null:
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		host.add_child(backdrop)
		if not continuing and _backdrop_kind != "opaque":
			backdrop.modulate.a = 0.0
			UiMotion.tween(backdrop).tween_property(backdrop, "modulate:a", 1.0, UiMotion.duration(UiTokens.FAST, true)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	app.get_tree().paused = app.mode == "play" and bool(current.pauses)
	if float(current.dilation) > 0.0:
		app.run_controller.request_time_scale(DILATION_REASON, float(current.dilation))
		_dilated = true
	elif _dilated:
		app.run_controller.release_time_scale(DILATION_REASON)
		_dilated = false
	_apply_run_holds(current)
	app.sound.set_context(str(current.sound) if app.mode == "play" else "menu")
	app.dialogue.visible = false
	var screen: UiScreen = SCREENS[id].new()
	entry.screen = screen
	screen.request_pop.connect(pop)
	screen.enter({"app": app, "host": host, "args": entry.args})
	UiLayout.scale_text(host)
	relayout()
	UiMotion.stagger(screen.motion_items())
	var focus: Control = screen.default_focus()
	if focus != null: focus.grab_focus()
	return screen

## M6: fits the host to the UI rect for the top screen's `layout` (UiLayout.fit_canvas for
## "canvas"; the whole rect for "fill"). Runs after every build and on every resize (main.gd's
## layout_ui).
func relayout() -> void:
	if host == null or host.get_parent() == null: return
	if not stack.is_empty() and stack.back().screen != null: (stack.back().screen as UiScreen).relayout()
	var area: Vector2 = (host.get_parent() as Control).size
	if stack.is_empty() or str(top_policy().layout) == "canvas":
		UiLayout.fit_canvas(host, area)
	else:
		host.scale = Vector2.ONE
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for child: Node in host.get_children():
			if child is Control and UiLayout.is_bleed(child): child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## The node behind a screen for a policy `backdrop` kind, full screen, named "Backdrop"; null for
## "none". dim_blur is shaders/ui_backdrop.gdshader; dim is the same shader at blur_lod 0. `dim`
## below 0 is UiTokens.SCRIM_DIM (the policy's `dim`).
static func make_backdrop(kind: String, dim: float = -1.0) -> ColorRect:
	if kind == "none" or kind.is_empty(): return null
	var result := ColorRect.new()
	result.name = "Backdrop"
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiLayout.mark_bleed(result)
	if kind == "opaque":
		result.color = VisualStyle.BG
		return result
	var material := ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	material.set_shader_parameter("scrim", UiTokens.SCRIM)
	material.set_shader_parameter("dim", UiTokens.SCRIM_DIM if dim < 0.0 else dim)
	material.set_shader_parameter("blur_lod", UiTokens.SCRIM_BLUR_LOD if kind == "dim_blur" else 0.0)
	result.material = material
	return result

## The backdrop of a stack that just closed, fading out over the resumed game. Pushing a screen in
## the same frame (pop, then build the screen below) removes it again.
func _fade_out_backdrop() -> void:
	var kind: String = _backdrop_kind
	_backdrop_kind = ""
	if kind not in ["dim", "dim_blur"] or host.get_parent() == null: return
	_ghost = make_backdrop(kind, _backdrop_dim)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.get_parent().add_child(_ghost)
	host.get_parent().move_child(_ghost, host.get_index())
	UiMotion.exit(_ghost, true, false)
