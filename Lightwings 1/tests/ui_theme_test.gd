extends SceneTree
## Modernization M4: the baked theme styles every Control the screens build.
## - theme/lightship_theme.tres is what UiKit.build_theme() produces today (not stale);
## - every stateful Control (buttons, toggles, tabs, sliders, panels, fields) on the menu, all four
##   Options tabs, Pause, Evolution and Map resolves normal/hover/focus/pressed (or its type's own
##   states) to a style of OUR theme, not the engine default;
## - every text-drawing Control resolves a font of assets/fonts/, never ThemeDB.fallback_font;
## - the variable-font axes and the tabular-figure feature take effect.
## Negative controls: a theme with one stylebox deleted; a theme with no fonts; a theme that
## differs from the bake by one colour; a font without tabular figures; one weight twice.
var failures: int = 0
var checks: int = 0
var caught: int = 0
var app: Node

## The states each Control class must resolve from our theme.
const STATES: Dictionary = {
	"Button": ["normal", "hover", "focus", "pressed", "disabled"],
	"CheckButton": ["normal", "hover", "focus", "pressed"],
	"CheckBox": ["normal", "hover", "focus", "pressed"],
	"OptionButton": ["normal", "hover", "focus", "pressed"],
	"TabContainer": ["panel", "tab_selected", "tab_unselected", "tab_hovered", "tab_focus"],
	"HSlider": ["slider", "grabber_area", "grabber_area_highlight", "focus"],
	"Panel": ["panel"],
	"PanelContainer": ["panel"],
	"LineEdit": ["normal", "focus"],
}
const TEXT_TYPES: Array[String] = ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "TabContainer", "LineEdit"]

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## A negative control: `problems` must be non-empty.
func control(problems: Array, label: String) -> void:
	checks += 1
	if problems.is_empty():
		failures += 1
		push_error("negative control NOT caught: " + label)
	else:
		caught += 1
		print("negative control caught: %s (%s)" % [label, problems[0]])

func _descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in node.get_children():
		nodes.append(child)
		nodes.append_array(_descendants(child))
	return nodes

## Every problem with the styles and fonts of the visible Controls under `root_node`.
func audit(root_node: Node, types_seen: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var engine: Theme = ThemeDB.get_default_theme()
	for node: Node in _descendants(root_node):
		if not node is Control or not node.is_visible_in_tree(): continue
		var control_node: Control = node
		var kind: String = control_node.get_class()
		types_seen[kind] = int(types_seen.get(kind, 0)) + 1
		for state: String in STATES.get(kind, []):
			var style: StyleBox = control_node.get_theme_stylebox(state)
			if style == null or style == engine.get_stylebox(state, kind):
				problems.append("%s '%s' has no themed '%s' style" % [kind, _name(control_node), state])
		if kind in TEXT_TYPES:
			var font: Font = control_node.get_theme_font("font")
			if font == null or font == ThemeDB.fallback_font or font == engine.default_font:
				problems.append("%s '%s' draws with the fallback font" % [kind, _name(control_node)])
			elif not _font_path(font).begins_with("res://assets/fonts/"):
				problems.append("%s '%s' font is not ours: %s" % [kind, _name(control_node), _font_path(font)])
	return problems

func _name(node: Control) -> String:
	var text: Variant = node.get("text")
	return str(text).left(24) if text != null and not str(text).is_empty() else str(node.name)

func _font_path(font: Font) -> String:
	if font is FontVariation: return _font_path(font.base_font) if font.base_font != null else ""
	return font.resource_path

## A comparable description of a theme: every stylebox's drawn properties, colour, constant, font
## size, font (file, axes, features, spacing) and icon size.
func fingerprint(theme: Theme) -> String:
	var lines := PackedStringArray()
	var types: PackedStringArray = theme.get_type_list()
	types.sort()
	for kind: String in types:
		var start: int = lines.size()
		lines.append("variation %s<-%s" % [kind, theme.get_type_variation_base(kind)])
		for style_name: String in theme.get_stylebox_list(kind):
			var style: StyleBox = theme.get_stylebox(style_name, kind)
			var parts: Array = [kind, style_name, style.get_class(), style.content_margin_left, style.content_margin_top, style.content_margin_right, style.content_margin_bottom]
			if style is StyleBoxFlat:
				parts.append_array([style.bg_color, style.border_color, style.border_width_left, style.border_width_top, style.border_width_right, style.border_width_bottom, style.corner_radius_top_left, style.shadow_color, style.shadow_size, style.shadow_offset])
			lines.append(str(parts))
		for color_name: String in theme.get_color_list(kind): lines.append("%s color %s %s" % [kind, color_name, theme.get_color(color_name, kind)])
		for constant_name: String in theme.get_constant_list(kind): lines.append("%s constant %s %d" % [kind, constant_name, theme.get_constant(constant_name, kind)])
		for size_name: String in theme.get_font_size_list(kind): lines.append("%s size %s %d" % [kind, size_name, theme.get_font_size(size_name, kind)])
		for font_name: String in theme.get_font_list(kind): lines.append("%s font %s %s" % [kind, font_name, _font_key(theme.get_font(font_name, kind))])
		for icon_name: String in theme.get_icon_list(kind): lines.append("%s icon %s %s" % [kind, icon_name, theme.get_icon(icon_name, kind).get_size()])
		# A saved theme lists its items in its own order; compare as sets per type.
		var block: PackedStringArray = lines.slice(start)
		block.sort()
		lines.resize(start)
		lines.append_array(block)
	lines.append("default %s %d" % [_font_key(theme.default_font), theme.default_font_size])
	return "\n".join(lines)

func _font_key(font: Font) -> String:
	if font is FontVariation: return "%s %s %s %d" % [_font_path(font), font.variation_opentype, font.opentype_features, font.spacing_glyph]
	return _font_path(font) if font != null else "<none>"

func _run() -> void:
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://ui-theme-%d" % Time.get_ticks_usec()
	# The bake.
	var baked: Theme = load(UiKit.THEME_PATH) as Theme
	check(baked != null, "theme/lightship_theme.tres loads")
	var built: Theme = UiKit.build_theme()
	var baked_print: String = fingerprint(baked)
	var built_print: String = fingerprint(built)
	if baked_print != built_print:
		var baked_lines: PackedStringArray = baked_print.split("\n")
		var built_lines: PackedStringArray = built_print.split("\n")
		for index: int in range(mini(baked_lines.size(), built_lines.size())):
			if baked_lines[index] != built_lines[index]:
				push_error("first difference: baked '%s' vs built '%s'" % [baked_lines[index], built_lines[index]])
				break
	check(baked_print == built_print, "the baked theme is what UiKit.build_theme() produces (rebake with tools/build_theme.gd)")
	var altered: Theme = UiKit.build_theme()
	altered.set_color("font_color", "Button", Color.RED)
	control(["fingerprints differ"] if fingerprint(altered) != baked_print else [], "a theme one colour away from the bake")
	check(UiKit.make_theme() == baked, "UiKit.make_theme() is the baked resource")

	# The fonts: families, the weight axis, tabular figures.
	var families: Dictionary = {UiTokens.FONT_DISPLAY: "Exo 2", UiTokens.FONT_BODY: "Inter", UiTokens.FONT_MONO: "JetBrains Mono"}
	for path: String in families:
		var file: FontFile = load(path) as FontFile
		check(file != null and file.get_font_name() == families[path], "%s is %s (got %s)" % [path, families[path], file.get_font_name() if file != null else "null"])
	check(_font_path(ThemeDB.fallback_font) == UiTokens.FONT_BODY, "ThemeDB.fallback_font (every raw draw_string) is Inter via gui/theme/custom_font (got '%s')" % _font_path(ThemeDB.fallback_font))
	var light: float = UiKit.font(UiTokens.FONT_BODY, 300).get_string_size("WWWWWWWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var heavy: float = UiKit.font(UiTokens.FONT_BODY, 800).get_string_size("WWWWWWWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var heavy_again: float = UiKit.font(UiTokens.FONT_BODY, 800).get_string_size("WWWWWWWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	print("measure: Inter 'WWWWWWWW' at 32 px: weight 300 = %.1f px, weight 800 = %.1f px" % [light, heavy])
	check(absf(heavy - light) > 2.0, "the wght axis changes the glyphs")
	control(["same weight, same width"] if absf(heavy_again - heavy) <= 2.0 else [], "one weight measured twice")
	var tabular: FontVariation = UiKit.font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY, true)
	var proportional: FontVariation = UiKit.font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY, false)
	var tab_ones: float = tabular.get_string_size("111111", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var tab_eights: float = tabular.get_string_size("888888", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var prop_ones: float = proportional.get_string_size("111111", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var prop_eights: float = proportional.get_string_size("888888", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	print("measure: Inter '111111' vs '888888' at 32 px: tabular %.1f / %.1f, proportional %.1f / %.1f" % [tab_ones, tab_eights, prop_ones, prop_eights])
	check(absf(tab_ones - tab_eights) < 0.5, "tabular figures: every digit is one width")
	control(["digits differ by %.1f px" % absf(prop_ones - prop_eights)] if absf(prop_ones - prop_eights) >= 0.5 else [], "a body font without tnum")

	# Every screen the theme must dress.
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	for i: int in range(3): await process_frame
	check(app.ui.theme == baked, "the game UI uses the baked theme")
	var seen: Dictionary = {}
	var problems: Array[String] = []
	var screens: Array[String] = []
	problems.append_array(audit(app.ui, seen)); screens.append("menu")
	for tab: int in range(4):
		app.options_tab = tab
		app._show_options()
		await process_frame
		problems.append_array(audit(app.ui, seen)); screens.append("options/%d" % tab)
		app._close_overlay()
	app._new_game(false)
	await process_frame
	app._show_pause()
	await process_frame
	problems.append_array(audit(app.ui, seen)); screens.append("pause")
	app._close_overlay()
	for element: String in ["fire", "corruption", "plasma"]: app.combat.collect_light(20.0, element)
	app._show_evolution()
	await process_frame
	problems.append_array(audit(app.ui, seen)); screens.append("evolution")
	app._close_overlay()
	app._show_map()
	await process_frame
	problems.append_array(audit(app.ui, seen)); screens.append("map")
	for problem: String in problems.slice(0, 12): push_error(problem)
	check(problems.is_empty(), "%d style/font problems across %s" % [problems.size(), ", ".join(screens)])
	var kinds: Array = seen.keys()
	kinds.sort()
	print("measure: Control types used: %s" % ", ".join(kinds.map(func(kind: String) -> String: return "%s×%d" % [kind, seen[kind]])))
	for required: String in ["Button", "CheckButton", "TabContainer", "HSlider", "Label", "Panel"]:
		check(seen.has(required), "the audit reached a %s" % required)

	# Controls: the same screen audited under a theme with one stylebox deleted, and under one
	# with no fonts at all.
	var stripped: Theme = UiKit.build_theme()
	stripped.clear_stylebox("hover", "Button")
	app.ui.theme = stripped
	await process_frame
	control(audit(app.ui, {}), "the Button hover stylebox deleted")
	var fontless: Theme = UiKit.build_theme()
	fontless.default_font = null
	for kind: String in fontless.get_type_list():
		for font_name: String in fontless.get_font_list(kind): fontless.clear_font(font_name, kind)
	app.ui.theme = fontless
	await process_frame
	control(audit(app.ui, {}).filter(func(problem: String) -> bool: return problem.contains("font")), "a theme with no fonts")
	app.ui.theme = baked

	print("UI theme: %d checks, %d failures (%d negative controls caught)" % [checks, failures, caught])
	app._close_overlay()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
