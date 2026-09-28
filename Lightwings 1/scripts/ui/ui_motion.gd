class_name UiMotion
extends RefCounted
## The interface's motion system (modernization M5). Every UI tween is made here, from the timings
## and easings in UiTokens, and every one of them:
## - runs while the tree is paused (TWEEN_PAUSE_PROCESS): menus animate over a paused run;
## - ignores Engine.time_scale: a slowed or hit-stopped sim never slows the interface;
## - takes its length from duration(), the ONE place reduced motion is honoured: moves take no
##   time and fades are capped at UiTokens.REDUCED_FADE_CAP.
## Helpers animate modulate, scale and the position of free-standing controls only. A child of a
## Container only fades and scales, because the container owns its position.

## Reduced motion (an accessibility preference). Read only by duration().
static var reduced: bool = false

## The length a UI animation of `seconds` actually takes. `fade`: the animation only changes
## opacity, which reduced motion shortens instead of removing.
static func duration(seconds: float, fade: bool = false) -> float:
	if not reduced: return seconds
	return minf(seconds, UiTokens.REDUCED_FADE_CAP) if fade else 0.0

## A tween on `node` that runs while paused and ignores the time scale.
static func tween(node: Node) -> Tween:
	var result: Tween = node.create_tween()
	result.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	result.set_ignore_time_scale(true)
	return result

## Brings `node` in: a fade from clear and, unless a container owns its position, a short rise.
static func enter(node: CanvasItem, delay: float = 0.0) -> Tween:
	var result: Tween = tween(node).set_parallel(true)
	var wait: float = duration(delay)
	var shown: Color = node.modulate
	node.modulate.a = 0.0
	result.tween_property(node, "modulate:a", shown.a, duration(UiTokens.BASE, true)).set_delay(wait).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	if node is Control and not node.get_parent() is Container:
		var rest: Vector2 = node.position
		node.position = rest + Vector2(0.0, UiTokens.ENTER_RISE)
		result.tween_property(node, "position", rest, duration(UiTokens.SLOW)).set_delay(wait).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	return result

## Takes `node` out: a fast in-cubic fade (and, with `travel`, a short fall for a free-standing
## control), then frees it when `free_after`.
static func exit(node: CanvasItem, free_after: bool = true, travel: bool = true) -> Tween:
	var result: Tween = tween(node).set_parallel(true)
	result.tween_property(node, "modulate:a", 0.0, duration(UiTokens.FAST, true)).set_trans(UiTokens.EASE_OUT_TRANS).set_ease(UiTokens.EASE_OUT_EASE)
	if travel and node is Control and not node.get_parent() is Container:
		result.tween_property(node, "position", node.position + Vector2(0.0, UiTokens.ENTER_RISE * 0.5), duration(UiTokens.FAST)).set_trans(UiTokens.EASE_OUT_TRANS).set_ease(UiTokens.EASE_OUT_EASE)
	if free_after: result.chain().tween_callback(node.queue_free)
	return result

## Enters `items` one after another, UiTokens.STAGGER apart and never more than STAGGER_MAX in
## all. An item is a CanvasItem, or an Array of them that enter together (a card and its parts).
static func stagger(items: Array, delay: float = 0.0) -> Array[Tween]:
	var result: Array[Tween] = []
	var step: float = UiTokens.STAGGER
	if items.size() > 1: step = minf(step, UiTokens.STAGGER_MAX / float(items.size() - 1))
	for index: int in range(items.size()):
		var group: Array = items[index] if items[index] is Array else [items[index]]
		for node: Variant in group:
			if node is CanvasItem and is_instance_valid(node): result.append(enter(node, delay + step * index))
	return result

## Hover equals focus: pointing at `control` focuses it, and focus lifts it slightly.
static func hover(control: Control) -> void:
	control.mouse_entered.connect(func() -> void:
		if control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled): control.grab_focus())
	control.focus_entered.connect(func() -> void: _scale_to(control, UiTokens.HOVER_SCALE, UiTokens.FAST))
	control.focus_exited.connect(func() -> void: _scale_to(control, 1.0, UiTokens.FAST))

## A press dips `button` and springs it back with the out-back pop.
static func press(button: BaseButton) -> void:
	button.button_down.connect(func() -> void: _scale_to(button, UiTokens.PRESS_SCALE, UiTokens.MICRO))
	button.button_up.connect(func() -> void: pop(button, UiTokens.PRESS_SCALE, UiTokens.HOVER_SCALE if button.has_focus() else 1.0))

## Scales `control` from `from` to `to` with an out-back overshoot of UiTokens.POP_OVERSHOOT.
static func pop(control: Control, from: float = 0.85, to: float = 1.0) -> Tween:
	var result: Tween = tween(control)
	result.tween_method(func(t: float) -> void:
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2.ONE * lerpf(from, to, out_back(t)), 0.0, 1.0, duration(UiTokens.BASE))
	return result

## Shakes `control` sideways, decaying over two FAST beats. Reduced motion skips it.
static func shake(control: Control, magnitude: float = 8.0) -> Tween:
	var rest: Vector2 = control.position
	var result: Tween = tween(control)
	var beat: float = duration(UiTokens.FAST) * 2.0 / 6.0
	for index: int in range(6):
		var side: float = (1.0 if index % 2 == 0 else -1.0) * magnitude * (1.0 - index / 6.0)
		result.tween_property(control, "position", rest + Vector2(side, 0.0), beat)
	result.tween_property(control, "position", rest, beat)
	return result

## Counts `label` up from `from` to `to`, printing each value through `format`.
static func count_up(label: Label, from: float, to: float, format: String = "%d") -> Tween:
	var result: Tween = tween(label)
	result.tween_method(func(value: float) -> void: label.text = format % value, from, to, duration(UiTokens.SLOW)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	return result

## Moves `bar` to `value` on a critically damped spring of UiTokens.SPRING_OMEGA.
static func bar_to(bar: Range, value: float) -> Tween:
	var start: float = bar.value
	var result: Tween = tween(bar)
	result.tween_method(func(t: float) -> void: bar.value = lerpf(start, value, spring(t)), 0.0, 1.0, duration(UiTokens.SLOW))
	return result

## Out-back easing with the token overshoot: 0 at 0, 1 at 1, peaking past 1 on the way.
static func out_back(t: float) -> float:
	var s: float = UiTokens.POP_OVERSHOOT
	var u: float = t - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u

## A critically damped spring over UiMotion's SLOW window, normalised to land exactly on 1.
static func spring(t: float) -> float:
	var x: float = UiTokens.SPRING_OMEGA * UiTokens.SLOW * t
	var settle: float = UiTokens.SPRING_OMEGA * UiTokens.SLOW
	return (1.0 - (1.0 + x) * exp(-x)) / (1.0 - (1.0 + settle) * exp(-settle))

static func _scale_to(control: Control, target: float, seconds: float) -> Tween:
	if not is_instance_valid(control) or not control.is_inside_tree(): return null
	var from: float = control.scale.x
	var running: Tween = control.get_meta(&"ui_scale_tween") if control.has_meta(&"ui_scale_tween") else null
	if running != null and running.is_valid(): running.kill()
	var result: Tween = tween(control)
	control.set_meta(&"ui_scale_tween", result)
	# The pivot is re-read every step: a control a container has not sorted yet has no size.
	result.tween_method(func(value: float) -> void:
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2.ONE * value, from, target, duration(seconds)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	return result
