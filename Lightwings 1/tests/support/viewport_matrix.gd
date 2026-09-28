extends RefCounted
## The window sizes every layout claim is made at (modernization M6), and the instruments that
## judge a laid-out UI. Load with:
##   const ViewportMatrix = preload("res://tests/support/viewport_matrix.gd")
## No class_name on purpose: nothing under tests/ enters the game's global namespace.
##
## Under aspect "expand" at a logical height of 800 the UI rect of each size is known in advance
## (LOGICAL); a GPU capture at any of them must come back at exactly `root.size` (no letterbox).

## 16:9 at 720p (the smallest supported), 16:10 (the design size and Steam Deck), 16:9 1080p, 21:9.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(2560, 1080)]
## The logical (UI px at scale 1) rect each size stretches to.
const LOGICAL: Dictionary = {
	Vector2i(1280, 720): Vector2(1422, 800),
	Vector2i(1280, 800): Vector2(1280, 800),
	Vector2i(1920, 1080): Vector2(1422, 800),
	Vector2i(2560, 1080): Vector2(1896, 800),
}
const TEXT_SCALES: Array[float] = [1.0, 1.3]
const UI_SCALES: Array[float] = [0.8, 1.4]

static func label(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]

## Every visible Control under `node`, depth first (internal children excluded).
static func visible_controls(node: Node, into: Array[Control] = []) -> Array[Control]:
	for child: Node in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible: continue
		if child is Control: into.append(child)
		visible_controls(child, into)
	return into

## A Control's rect in UI px (its canvas layer's space): position and scale of every parent
## Control included, the layer's own UI scale not.
static func ui_rect(control: Control) -> Rect2:
	return control.get_global_rect()

## Controls that leave the safe rect of a UI of `ui_size`: "name rect" strings. Skips full-bleed
## controls (UiLayout.mark_bleed), `exempt` (the UI root, its groups and the canvas host, which
## are containers, not content) and MarginContainers (they inset their content; the content itself
## is checked).
static func safe_violations(controls: Array[Control], ui_size: Vector2, exempt: Array) -> PackedStringArray:
	var safe: Rect2 = UiLayout.safe_rect(ui_size).grow(0.5)
	var result := PackedStringArray()
	for control: Control in controls:
		if control in exempt or control is MarginContainer or UiLayout.is_bleed(control): continue
		var rect: Rect2 = ui_rect(control)
		if rect.size.x <= 0.0 and rect.size.y <= 0.0: continue
		if not safe.encloses(rect): result.append("%s %s" % [_describe(control), rect])
	return result

## Text that does not fit its box: a Label wider than its box on one line (font.get_string_size), a
## Button whose text and padding need more than its width. A Label that declares trimming
## (text_overrun_behavior) or wraps is judged by `text_collisions` instead.
static func text_overflows(controls: Array[Control]) -> PackedStringArray:
	var result := PackedStringArray()
	for control: Control in controls:
		if control is Label:
			var label := control as Label
			if label.text.strip_edges().is_empty(): continue
			var font: Font = label.get_theme_font(&"font")
			var font_size: int = label.get_theme_font_size(&"font_size")
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				var widest: float = 0.0
				for line: String in label.text.split("\n"): widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
				if widest > label.size.x + 0.5: result.append("%s needs %.0f px, box %.0f" % [_describe(label), widest, label.size.x])
		elif control is Button:
			var button := control as Button
			if button.text.strip_edges().is_empty(): continue
			var clipped: bool = button.clip_text
			button.clip_text = false
			var needed: float = button.get_minimum_size().x
			button.clip_text = clipped
			if needed > button.size.x + 0.5: result.append("%s needs %.0f px, box %.0f" % [_describe(button), needed, button.size.x])
	return result

## Text boxes that run into one another: two non-empty Labels/Buttons under the same parent whose
## rects overlap. A wrapped Label never hides a line - its box grows to hold every line (measured:
## a 200x20 box with four lines comes back 200x89) - so a wrapped line that does not fit shows up
## as a box grown into the text below it.
static func text_collisions(controls: Array[Control]) -> PackedStringArray:
	var by_parent: Dictionary = {}
	for control: Control in controls:
		var text: String = (control as Label).text if control is Label else ((control as Button).text if control is Button else "")
		if text.strip_edges().is_empty(): continue
		var parent: Node = control.get_parent()
		if not by_parent.has(parent): by_parent[parent] = []
		by_parent[parent].append(control)
	var result := PackedStringArray()
	for group: Array in by_parent.values():
		for i: int in range(group.size()):
			for j: int in range(i + 1, group.size()):
				var overlap: Rect2 = (group[i] as Control).get_rect().intersection((group[j] as Control).get_rect())
				if overlap.size.x > 1.0 and overlap.size.y > 1.0: result.append("%s x %s" % [_describe(group[i]), _describe(group[j])])
	return result

## Pairs of rects (name -> Rect2) that overlap by more than half a pixel each way.
static func overlaps(rects: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var names: Array = rects.keys()
	for i: int in range(names.size()):
		for j: int in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			var overlap: Rect2 = a.intersection(b)
			if overlap.size.x > 0.5 and overlap.size.y > 0.5: result.append("%s x %s" % [names[i], names[j]])
	return result

static func _describe(control: Control) -> String:
	var text: String = ""
	if control is Label: text = (control as Label).text
	elif control is Button: text = (control as Button).text
	text = text.replace("\n", " ").left(28)
	return "%s(%s%s)" % [control.get_class(), control.name, (" '" + text + "'") if not text.is_empty() else ""]
