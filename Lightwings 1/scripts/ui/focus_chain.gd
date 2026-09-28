class_name FocusChain
extends RefCounted
## Explicit focus neighbours for a menu (modernization M15). Godot's own neighbour search looks at
## every focusable Control under the same top-level parent - which, for a screen over the title or
## over the HUD, includes the buttons BEHIND it: a pad could walk off a modal onto the menu under
## the blur. A screen that links its controls here never falls back to that search.
##
## `rows` is a list of rows, top to bottom, each a list of controls left to right. Left/right move
## within a row (clamped at its ends); up/down move to the nearest control (by centre x) in the row
## above/below, wrapping from the last row to the first; Tab/Shift+Tab walk the flattened order.
## Controls that consume left/right themselves (spinner rows, a tab strip) still get neighbours:
## they are simply never used.

static func rows(lines: Array) -> void:
	var clean: Array = []
	for line: Variant in lines:
		var kept: Array[Control] = []
		for control: Variant in (line if line is Array else [line]):
			if is_instance_valid(control) and control is Control and (control as Control).is_inside_tree(): kept.append(control)
		if not kept.is_empty(): clean.append(kept)
	var flat: Array[Control] = []
	for line: Array in clean: flat.append_array(line)
	for r: int in range(clean.size()):
		var line: Array = clean[r]
		var above: Array = clean[(r - 1 + clean.size()) % clean.size()]
		var below: Array = clean[(r + 1) % clean.size()]
		for c: int in range(line.size()):
			var control: Control = line[c]
			control.focus_neighbor_left = control.get_path_to(line[maxi(0, c - 1)])
			control.focus_neighbor_right = control.get_path_to(line[mini(line.size() - 1, c + 1)])
			control.focus_neighbor_top = control.get_path_to(_nearest(control, above))
			control.focus_neighbor_bottom = control.get_path_to(_nearest(control, below))
			var at: int = flat.find(control)
			control.focus_previous = control.get_path_to(flat[(at - 1 + flat.size()) % flat.size()])
			control.focus_next = control.get_path_to(flat[(at + 1) % flat.size()])

## The control in `line` whose centre is closest in x to `from`'s (the first on a tie). Positions
## are read in the shared canvas, so rows in different containers compare correctly.
static func _nearest(from: Control, line: Array) -> Control:
	var x: float = from.get_global_rect().get_center().x
	var best: Control = line[0]
	var gap: float = INF
	for candidate: Control in line:
		var d: float = absf(candidate.get_global_rect().get_center().x - x)
		if d < gap - 0.5:
			gap = d
			best = candidate
	return best
