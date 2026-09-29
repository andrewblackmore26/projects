class_name UiLayout
extends RefCounted
## How the interface fits the window (modernization M6). The one place that knows the stretch
## rule, the safe margin, the UI scale and the text scale.
##
## - **Aspect.** project.godot stretches `canvas_items` with aspect "expand" at a logical height of
##   800: the logical width is 1280 at 16:10, 1422 at 16:9 and 1896 at 21:9, and a screen taller
##   than 16:10 (4:3) grows the logical height instead. Beyond MAX_ASPECT (wider than 21:9) the
##   window is pillarboxed at 1920x800 (`apply_aspect`), so nothing is ever laid out wider.
## - **Safe rect.** Every visible Control stays SAFE_MARGIN px inside the UI rect, except the ones
##   marked full-bleed (`mark_bleed`: backdrops and the HUD's bar panels).
## - **UI scale** (setting `ui_scale`, 0.8-1.4) scales the UI CanvasLayer only; the world is not
##   touched. The UI root is sized to the visible rect divided by the scale (`fit_root`), so every
##   anchor and layout below works in "UI px".
## - **Canvas screens.** The modal screens are laid out in design coordinates on a 1280x800 canvas
##   (the router's overlay host). `fit_canvas` centres that canvas and scales it DOWN, never up,
##   only as far as its content needs to stay inside the safe rect; at 1280x800 and scale 1 it is
##   the identity, so the composition is exactly the design's.
## - **Text scale** (setting `text_scale`, 0.9-1.3, M15 adds its Options row) multiplies every
##   Label/Button font size under a node (`scale_text`); draw_string callers use `text_px`.

const BASE_SIZE: Vector2 = Vector2(1280, 800)
## 1920x800 logical. 21:9 panels (2560x1080 = 2.370, 3440x1440 = 2.389) stay expanded; 32:9 is
## pillarboxed.
const MAX_ASPECT: float = 2.4
const SAFE_MARGIN: float = 24.0
const UI_SCALE_MIN: float = 0.8
const UI_SCALE_MAX: float = 1.4
const TEXT_SCALE_MIN: float = 0.9
const TEXT_SCALE_MAX: float = 1.3
const BLEED_META: StringName = &"ui_bleed"
const BASE_FONT_META: StringName = &"ui_base_font_size"
const BASE_BOX_META: StringName = &"ui_base_box"

## The text scale every `scale_text` applies (main.gd's apply_settings sets it from `text_scale`).
static var text_scale: float = 1.0

## Expand below MAX_ASPECT, pillarbox (keep, at 1920x800) above it. Idempotent: it only writes the
## window's content scale when the rule's answer changes.
static func apply_aspect(window: Window) -> void:
	var size := Vector2(window.size)
	if size.x <= 0.0 or size.y <= 0.0: return
	var wide: bool = size.x / size.y > MAX_ASPECT + 0.0005
	var aspect: Window.ContentScaleAspect = Window.CONTENT_SCALE_ASPECT_KEEP if wide else Window.CONTENT_SCALE_ASPECT_EXPAND
	var base := Vector2i(roundi(BASE_SIZE.y * MAX_ASPECT), int(BASE_SIZE.y)) if wide else Vector2i(BASE_SIZE)
	if window.content_scale_aspect != aspect: window.content_scale_aspect = aspect
	if window.content_scale_size != base: window.content_scale_size = base

static func clamp_ui_scale(value: float) -> float:
	return clampf(value, UI_SCALE_MIN, UI_SCALE_MAX)

static func clamp_text_scale(value: float) -> float:
	return clampf(value, TEXT_SCALE_MIN, TEXT_SCALE_MAX)

## Scales the UI layer by `ui_scale` and sizes `root` (the layer's full-screen Control) to the
## visible rect in UI px.
static func fit_root(layer: CanvasLayer, root: Control, ui_scale: float) -> void:
	var s: float = clamp_ui_scale(ui_scale)
	layer.scale = Vector2(s, s)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = root.get_viewport().get_visible_rect().size / s

## The rect every visible Control must stay inside, for a UI of `size`.
static func safe_rect(size: Vector2) -> Rect2:
	return Rect2(Vector2(SAFE_MARGIN, SAFE_MARGIN), size - Vector2(SAFE_MARGIN, SAFE_MARGIN) * 2.0)

## Marks a Control as deliberately edge to edge (a backdrop, a HUD bar): exempt from the safe rect.
static func mark_bleed(control: Control) -> Control:
	control.set_meta(BLEED_META, true)
	return control

static func is_bleed(control: Control) -> bool:
	return control.has_meta(BLEED_META)

## The union of `canvas`'s visible, non-bleed direct children, in canvas coordinates.
static func content_rect(canvas: Control) -> Rect2:
	var result := Rect2()
	var first: bool = true
	for child: Node in canvas.get_children():
		if not child is Control or not child.visible or is_bleed(child): continue
		var rect: Rect2 = (child as Control).get_rect()
		result = rect if first else result.merge(rect)
		first = false
	return result

## Places the design canvas `canvas` (BASE_SIZE, content in design coordinates) in a UI of `area`:
## centred, scaled down only as far as its content needs to fit the safe rect, then nudged inside
## it. Children marked full-bleed are stretched to cover the whole UI rect instead.
static func fit_canvas(canvas: Control, area: Vector2) -> void:
	canvas.set_anchors_preset(Control.PRESET_TOP_LEFT)
	canvas.size = BASE_SIZE
	var content: Rect2 = content_rect(canvas)
	var safe: Rect2 = safe_rect(area)
	var s: float = 1.0
	if content.size.x > 0.0: s = minf(s, safe.size.x / content.size.x)
	if content.size.y > 0.0: s = minf(s, safe.size.y / content.size.y)
	var origin: Vector2 = (area - BASE_SIZE * s) * 0.5
	var mapped := Rect2(origin + content.position * s, content.size * s)
	origin += _nudge(mapped, safe)
	canvas.scale = Vector2(s, s)
	canvas.position = origin
	for child: Node in canvas.get_children():
		if child is Control and is_bleed(child): cover(child, canvas, area)

## Stretches `control`, a child of `canvas`, over the whole UI rect of `area`.
static func cover(control: Control, canvas: Control, area: Vector2) -> void:
	var s: float = maxf(0.0001, canvas.scale.x)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = -canvas.position / s
	control.size = area / s

## The shift that moves `rect` inside `bounds` (per axis; a rect larger than bounds keeps its centre).
static func _nudge(rect: Rect2, bounds: Rect2) -> Vector2:
	var shift := Vector2.ZERO
	for axis: int in [0, 1]:
		if rect.size[axis] > bounds.size[axis]: shift[axis] = bounds.get_center()[axis] - rect.get_center()[axis]
		elif rect.position[axis] < bounds.position[axis]: shift[axis] = bounds.position[axis] - rect.position[axis]
		elif rect.end[axis] > bounds.end[axis]: shift[axis] = bounds.end[axis] - rect.end[axis]
	return shift

## A draw_string size under the text scale.
static func text_px(size: int) -> int:
	return maxi(1, roundi(size * text_scale))

## Applies `text_scale` to every text-bearing Control under `node` (and `node` itself). Each keeps
## its unscaled size in BASE_FONT_META, so applying again (a new scale) never compounds. At scale
## 1 a Control that was never scaled is left untouched.
static func scale_text(node: Node) -> void:
	if node is Control: _scale_font(node)
	for child: Node in node.get_children(): scale_text(child)

static func _scale_font(control: Control) -> void:
	var key: StringName = &""
	if control is Label or control is Button or control is TabContainer or control is LineEdit or control is TabBar: key = &"font_size"
	elif control is RichTextLabel: key = &"normal_font_size"
	if key.is_empty(): return
	if not control.has_meta(BASE_FONT_META):
		if is_equal_approx(text_scale, 1.0): return
		control.set_meta(BASE_FONT_META, control.get_theme_font_size(key))
		control.set_meta(BASE_BOX_META, control.size)
	var base: int = int(control.get_meta(BASE_FONT_META))
	control.add_theme_font_size_override(key, maxi(1, roundi(base * text_scale)))
	# A wrapped Label's box grows to hold its lines and never shrinks back on its own: give it its
	# authored box again, and let the new minimum grow it only as far as the new text needs.
	# (A font override does not invalidate the Control's cached minimum by itself; without the
	# explicit update the box was clamped to the OLD, larger minimum.)
	control.update_minimum_size()
	if control is Label and not control.get_parent() is Container: control.size = control.get_meta(BASE_BOX_META)
	elif control.get_parent() is Container:
		# M19: a container never shrinks a child it already made bigger (the title's wordmark letters
		# kept their 110 % widths at 100 % and overlapped by 3 px): drop the box to its new minimum
		# and let the container lay its children out again.
		control.size = Vector2.ZERO
		(control.get_parent() as Container).queue_sort()

## The width `label`'s text needs on one line, at its current font and size.
static func text_width(control: Control, text: String) -> float:
	var font: Font = control.get_theme_font(&"font")
	var size: int = control.get_theme_font_size(&"font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if font != null else 0.0

## Sizes a single-line label to its text (autowrap off), keeping its position.
static func hug(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size = Vector2.ZERO
	label.size = label.get_minimum_size()
	return label
