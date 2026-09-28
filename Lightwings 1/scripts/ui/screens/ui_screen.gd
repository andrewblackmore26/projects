class_name UiScreen
extends RefCounted
## Base of every screen moved out of main.gd (modernization M2). A screen is a builder, not a
## node: `enter` adds its nodes straight into the host Control it is given, so the host's direct
## children are the screen's own (tests count ShipPreviews among `app.overlay.get_children()`),
## and the ScreenRouter clears the host when the screen goes away.
##
## ctx: {app: main.gd, host: Control, args: Dictionary}. Screens read and write run state through
## `app`, exactly as the code did when it lived in main.gd.

## Asks the router to close this screen and return to the one below (Options' DONE).
signal request_pop

const WHITE := VisualStyle.TEXT
const MUTED := VisualStyle.MUTED
const GOLD := VisualStyle.ACCENT

var app: Node
var host: Control
var args: Dictionary = {}
var _focus: Control

func enter(ctx: Dictionary) -> void:
	app = ctx.app
	host = ctx.host
	args = ctx.get("args", {})
	build()
	wire_sounds(host, app)

## Subclasses add their nodes to `host` here and set `_focus`.
func build() -> void:
	pass

func exit() -> void:
	pass

## M6: re-flows content whose size follows the text scale. The router runs it after applying the
## text scale and before fitting the canvas, on every build and every relayout.
func relayout() -> void:
	pass

## The control that takes focus once the screen is built (null: focus is left alone).
func default_focus() -> Control:
	return _focus

## What enters, in order, when the router builds the screen (UiMotion.stagger): each item a node,
## or an Array of nodes that enter together. Default: every direct child but the backdrop.
func motion_items() -> Array:
	var items: Array = []
	for child: Node in host.get_children():
		if child is CanvasItem and child.name != &"Backdrop": items.append(child)
	return items

## M17 wiring, the ONE place interface cues attach (every screen, the title included, runs it after
## build()): focus moving onto a control (keyboard, pad, or a hover, which is focus) sounds
## `ui_move`, and a slider's change sounds `ui_slider_tick` at most once per SLIDER_TICK_SECONDS.
## Presses already sound `ui_confirm` through app.button; Escape sounds `ui_back` in ScreenRouter.
## The focus a screen grabs as it opens is silent: it lands in the frame the screen was wired.
## Idempotent per control, so re-wiring a rebuilt page adds nothing twice.
const SLIDER_TICK_SECONDS: float = 0.05

static func wire_sounds(root: Node, owner_app: Node) -> void:
	var wired_frame: int = Engine.get_process_frames()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is Control or node.has_meta(&"ui_sounds"): continue
		var control: Control = node
		if control is Slider:
			var slider: Slider = control
			slider.set_meta(&"ui_sounds", true)
			slider.value_changed.connect(func(_value: float) -> void:
				var now: float = Time.get_ticks_msec() / 1000.0
				if now - float(slider.get_meta(&"ui_tick_at", -1.0)) < SLIDER_TICK_SECONDS: return
				slider.set_meta(&"ui_tick_at", now)
				ui_cue(owner_app, "ui_slider_tick"))
		if control.focus_mode != Control.FOCUS_NONE and (control is BaseButton or control is Slider or control is ItemList or control is TabBar):
			control.set_meta(&"ui_sounds", true)
			control.focus_entered.connect(func() -> void:
				if Engine.get_process_frames() != wired_frame: ui_cue(owner_app, "ui_move"))

static func ui_cue(owner_app: Node, cue: String) -> void:
	var sound: Object = owner_app.get("sound") if is_instance_valid(owner_app) else null
	if sound != null and sound.has_method("play_cue"): sound.play_cue(cue, {})

## A button that clicks through the soundscape, like every button main.gd builds, and animates
## hover (which is focus) and press.
func button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	var result: Button = app.button(parent, text, rect, action)
	UiMotion.hover(result)
	UiMotion.press(result)
	wire_sounds(result, app)
	return result

static func centered_label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var result: Label = UiKit.label(parent, text, position, size, font_size, color)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result

static func menu_label(parent: Node, text: String, font_size: int, ink: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", ink)
	UiKit.type_role(result, font_size)
	parent.add_child(result)
	return result

func menu_action(parent: Node, text: String, action: Callable) -> Button:
	var result: Button = button(parent, text, Rect2(0, 0, 0, 40), action)
	result.custom_minimum_size.y = 40
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", 14)
	return result
