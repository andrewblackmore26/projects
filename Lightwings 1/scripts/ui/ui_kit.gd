## Generic immediate-mode UI builders shared by main.gd and any screen code.
## Pure static builders: no game state, no signals beyond the optional click callback.
class_name UiKit
extends RefCounted

const THEME_PATH: String = "res://theme/lightship_theme.tres"
## The body font baked alone: project.godot's gui/theme/custom_font, so ThemeDB.fallback_font (every
## draw_string outside a themed Control) is Inter too.
const BODY_FONT_PATH: String = "res://theme/lightship_body_font.tres"
## The Control types whose states the theme styles, and the stylebox names each must carry.
## ui_theme_test holds every Control a screen builds against this table.
const STATEFUL_TYPES: Array[String] = ["Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton"]
const BUTTON_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]

## The game's theme: theme/lightship_theme.tres, which tools/build_theme.gd bakes from
## build_theme(). Every UI root (main.gd, the ship workshop and atlas) uses this one resource.
static func make_theme() -> Theme:
	var baked: Theme = load(THEME_PATH) as Theme if ResourceLoader.exists(THEME_PATH) else null
	if baked == null:
		push_error("UiKit: %s is missing; bake it with tools/build_theme.gd" % THEME_PATH)
		return build_theme()
	return baked

## The theme, built from UiTokens (modernization M4, "Luminous Instrument"): smoked-glass panels,
## capsule buttons whose hover and focus are gold, Exo 2 display type, Inter body text with tabular
## figures, JetBrains Mono for bindings. The source of truth for the baked .tres; ui_theme_test
## fails when the two disagree.
static func build_theme() -> Theme:
	var result := Theme.new()
	var body: FontVariation = font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY, true)
	var strong: FontVariation = font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY_STRONG, true)
	var display: FontVariation = font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_DISPLAY, true)
	var action: FontVariation = font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_BUTTON, true, 1)
	var kicker: FontVariation = font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_BUTTON, true, 3)
	var mono: FontVariation = font(UiTokens.FONT_MONO, UiTokens.WEIGHT_MONO)
	result.default_font = body
	result.default_font_size = UiTokens.TEXT_M
	for kind: String in ["Label", "RichTextLabel", "LineEdit", "TooltipLabel", "PopupMenu"]:
		result.set_font("font" if kind != "RichTextLabel" else "normal_font", kind, body)
		result.set_color("font_color" if kind != "RichTextLabel" else "default_color", kind, UiTokens.INK)
	result.set_type_variation(UiTokens.DISPLAY_LABEL, "Label")
	result.set_font("font", UiTokens.DISPLAY_LABEL, display)
	result.set_type_variation(UiTokens.KICKER_LABEL, "Label")
	result.set_font("font", UiTokens.KICKER_LABEL, kicker)
	result.set_font_size("font_size", UiTokens.KICKER_LABEL, UiTokens.TEXT_XS)
	result.set_color("font_color", UiTokens.KICKER_LABEL, UiTokens.FOCUS)
	result.set_type_variation(UiTokens.MONO_LABEL, "Label")
	result.set_font("font", UiTokens.MONO_LABEL, mono)

	# Capsule buttons. Hover and focus are both gold: hover lights the 2 px border, focus adds the
	# 12 px glow (StyleBoxFlat draws a shadow under a translucent fill, so the focus box carries a
	# near-opaque fill of its own that hides the glow inside the capsule).
	var lit: StyleBoxFlat = glass_box(UiTokens.GLASS_RAISED, UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE)
	var focus: StyleBoxFlat = glass_box(Color(UiTokens.GLASS_RAISED, 0.96), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE, true)
	var pressed: StyleBoxFlat = glass_box(UiTokens.GLASS_PRESSED, UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE)
	var idle: StyleBoxFlat = glass_box(UiTokens.GLASS_RAISED, UiTokens.STROKE, 1, UiTokens.CAPSULE)
	var disabled: StyleBoxFlat = glass_box(Color(UiTokens.GLASS, 0.5), Color(UiTokens.STROKE, 0.5), 1, UiTokens.CAPSULE)
	for style: StyleBoxFlat in [idle, lit, focus, pressed, disabled]:
		style.content_margin_left = UiTokens.SPACE_5
		style.content_margin_right = UiTokens.SPACE_5
		style.content_margin_top = UiTokens.SPACE_1 + 2
		style.content_margin_bottom = UiTokens.SPACE_1 + 2
	for kind: String in ["Button", "OptionButton", "MenuButton"]:
		_button_states(result, kind, idle, lit, pressed, focus, disabled)
		result.set_font("font", kind, action)
		result.set_font_size("font_size", kind, UiTokens.TEXT_S)
		_button_ink(result, kind, UiTokens.INK, Color.WHITE, UiTokens.FOCUS)

	# The primary action: gold outline at rest, a solid gold capsule with dark ink when lit.
	result.set_type_variation(UiTokens.PRIMARY_BUTTON, "Button")
	var primary_idle: StyleBoxFlat = glass_box(Color(UiTokens.FOCUS, 0.12), UiTokens.FOCUS, 1, UiTokens.CAPSULE)
	var primary_lit: StyleBoxFlat = glass_box(UiTokens.FOCUS, UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE)
	var primary_focus: StyleBoxFlat = glass_box(UiTokens.FOCUS, UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE, true)
	var primary_pressed: StyleBoxFlat = glass_box(UiTokens.FOCUS.darkened(0.18), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE)
	for style: StyleBoxFlat in [primary_idle, primary_lit, primary_focus, primary_pressed]:
		style.content_margin_left = UiTokens.SPACE_5
		style.content_margin_right = UiTokens.SPACE_5
	_button_states(result, UiTokens.PRIMARY_BUTTON, primary_idle, primary_lit, primary_pressed, primary_focus, disabled)
	_button_ink(result, UiTokens.PRIMARY_BUTTON, UiTokens.FOCUS, UiTokens.CANVAS, UiTokens.CANVAS)
	result.set_font_size("font_size", UiTokens.PRIMARY_BUTTON, UiTokens.TEXT_M)

	# Map tiles: the same gold states on a small radius (their resting fill is set per tile).
	result.set_type_variation(UiTokens.TILE_BUTTON, "Button")
	var tile_lit: StyleBoxFlat = glass_box(Color(UiTokens.FOCUS, 0.16), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_SMALL)
	var tile_focus: StyleBoxFlat = glass_box(UiTokens.GLASS_RAISED.lerp(UiTokens.FOCUS, 0.16), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_SMALL, true)
	var tile_idle: StyleBoxFlat = glass_box(UiTokens.GLASS, UiTokens.STROKE, 1, UiTokens.RADIUS_SMALL)
	for style: StyleBoxFlat in [tile_lit, tile_focus, tile_idle]: style.set_content_margin_all(0)
	_button_states(result, UiTokens.TILE_BUTTON, tile_idle, tile_lit, tile_lit, tile_focus, tile_idle)
	tile_focus.shadow_size = UiTokens.FOCUS_GLOW_SIZE / 2

	# Toggle rows: flat until hovered; ON is the switch, not the row, so `pressed` looks like normal.
	var row: StyleBoxFlat = glass_box(Color(UiTokens.GLASS, 0.0), Color(UiTokens.STROKE, 0.0), 0, UiTokens.RADIUS_SMALL)
	var row_lit: StyleBoxFlat = glass_box(Color(1, 1, 1, 0.04), Color(UiTokens.FOCUS, 0.55), 1, UiTokens.RADIUS_SMALL)
	var row_focus: StyleBoxFlat = glass_box(Color(UiTokens.GLASS_RAISED, 0.96), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_SMALL, true)
	row_focus.shadow_size = UiTokens.FOCUS_GLOW_SIZE / 2
	for style: StyleBoxFlat in [row, row_lit, row_focus]:
		style.content_margin_left = UiTokens.SPACE_3
		style.content_margin_right = UiTokens.SPACE_3
	for kind: String in ["CheckButton", "CheckBox"]:
		_button_states(result, kind, row, row_lit, row, row_focus, row)
		result.set_font("font", kind, body)
		_button_ink(result, kind, UiTokens.INK, Color.WHITE, UiTokens.INK)
		result.set_color("font_disabled_color", kind, UiTokens.INK_DISABLED)
	for state: Array in [["checked", true, false], ["unchecked", false, false], ["checked_disabled", true, true], ["unchecked_disabled", false, true]]:
		result.set_icon(str(state[0]), "CheckButton", switch_icon(bool(state[1]), bool(state[2])))
		result.set_icon(str(state[0]), "CheckBox", switch_icon(bool(state[1]), bool(state[2])))

	# Panels: smoked glass.
	var panel_glass: StyleBoxTexture = glass_panel()
	for kind: String in ["Panel", "PanelContainer", UiTokens.GLASS_PANEL]:
		result.set_stylebox("panel", kind, panel_glass)
	result.set_type_variation(UiTokens.GLASS_PANEL, "PanelContainer")
	var tooltip: StyleBoxFlat = glass_box(Color(UiTokens.GLASS_RAISED, 0.97), UiTokens.STROKE, 1, UiTokens.RADIUS_SMALL)
	tooltip.set_content_margin_all(UiTokens.SPACE_2)
	result.set_stylebox("panel", "TooltipPanel", tooltip)
	result.set_font_size("font_size", "TooltipLabel", UiTokens.TEXT_S)
	result.set_stylebox("panel", "PopupMenu", tooltip)
	result.set_stylebox("hover", "PopupMenu", glass_box(Color(UiTokens.FOCUS, 0.16), UiTokens.FOCUS, 1, UiTokens.RADIUS_SMALL))
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# Tabs: an underline, gold when selected.
	result.set_stylebox("panel", "TabContainer", panel_glass)
	var tab_idle := StyleBoxFlat.new()
	tab_idle.bg_color = Color(0, 0, 0, 0)
	tab_idle.border_color = Color(UiTokens.STROKE, 0.0)
	tab_idle.border_width_bottom = UiTokens.FOCUS_BORDER
	tab_idle.content_margin_left = UiTokens.SPACE_5
	tab_idle.content_margin_right = UiTokens.SPACE_5
	tab_idle.content_margin_top = UiTokens.SPACE_3
	tab_idle.content_margin_bottom = UiTokens.SPACE_3
	var tab_selected: StyleBoxFlat = tab_idle.duplicate()
	tab_selected.border_color = UiTokens.FOCUS
	var tab_hovered: StyleBoxFlat = tab_idle.duplicate()
	tab_hovered.border_color = Color(UiTokens.FOCUS, 0.4)
	var tab_focus: StyleBoxFlat = glass_box(Color(0, 0, 0, 0), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_SMALL)
	result.set_stylebox("tab_selected", "TabContainer", tab_selected)
	result.set_stylebox("tab_unselected", "TabContainer", tab_idle)
	result.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	result.set_stylebox("tab_disabled", "TabContainer", tab_idle)
	result.set_stylebox("tab_focus", "TabContainer", tab_focus)
	result.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	result.set_font("font", "TabContainer", action)
	result.set_font_size("font_size", "TabContainer", UiTokens.TEXT_S)
	result.set_color("font_selected_color", "TabContainer", Color.WHITE)
	result.set_color("font_hovered_color", "TabContainer", UiTokens.INK)
	result.set_color("font_unselected_color", "TabContainer", UiTokens.INK_MUTED)
	result.set_color("font_disabled_color", "TabContainer", UiTokens.INK_DISABLED)

	# Sliders: a thin rounded track, a gold fill and a round knob.
	var slider_track: StyleBoxFlat = glass_box(UiTokens.TRACK, Color(0, 0, 0, 0), 0, UiTokens.RADIUS_SMALL)
	slider_track.shadow_size = 0
	slider_track.content_margin_top = 3
	slider_track.content_margin_bottom = 3
	var slider_fill: StyleBoxFlat = slider_track.duplicate()
	slider_fill.bg_color = UiTokens.FOCUS
	var slider_fill_lit: StyleBoxFlat = slider_fill.duplicate()
	slider_fill_lit.bg_color = UiTokens.FOCUS.lightened(0.2)
	result.set_stylebox("slider", "HSlider", slider_track)
	result.set_stylebox("grabber_area", "HSlider", slider_fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", slider_fill_lit)
	result.set_stylebox("focus", "HSlider", glass_box(Color(0, 0, 0, 0), Color(UiTokens.FOCUS, 0.6), 1, UiTokens.CAPSULE))
	result.set_icon("grabber", "HSlider", knob_icon(UiTokens.INK))
	result.set_icon("grabber_highlight", "HSlider", knob_icon(UiTokens.FOCUS))
	result.set_icon("grabber_disabled", "HSlider", knob_icon(UiTokens.INK_DISABLED))

	# Text entry.
	var field: StyleBoxFlat = glass_box(UiTokens.GLASS, UiTokens.STROKE, 1, UiTokens.RADIUS_SMALL)
	var field_focus: StyleBoxFlat = glass_box(Color(0, 0, 0, 0), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.RADIUS_SMALL)
	result.set_stylebox("normal", "LineEdit", field)
	result.set_stylebox("read_only", "LineEdit", field)
	result.set_stylebox("focus", "LineEdit", field_focus)
	result.set_color("font_placeholder_color", "LineEdit", UiTokens.INK_MUTED)
	result.set_color("caret_color", "LineEdit", UiTokens.FOCUS)
	result.set_color("selection_color", "LineEdit", Color(UiTokens.FOCUS, 0.3))

	# Slim scrollbars.
	for kind: String in ["VScrollBar", "HScrollBar"]:
		var track: StyleBoxFlat = glass_box(Color(UiTokens.TRACK, 0.35), Color(0, 0, 0, 0), 0, UiTokens.RADIUS_SMALL)
		track.shadow_size = 0
		track.set_content_margin_all(3)
		var grab: StyleBoxFlat = track.duplicate()
		grab.bg_color = UiTokens.INK_MUTED
		var grab_lit: StyleBoxFlat = track.duplicate()
		grab_lit.bg_color = UiTokens.FOCUS
		result.set_stylebox("scroll", kind, track)
		result.set_stylebox("grabber", kind, grab)
		result.set_stylebox("grabber_highlight", kind, grab_lit)
		result.set_stylebox("grabber_pressed", kind, grab_lit)
	return result

## A font of `path` at `weight`, optionally with tabular figures and extra letter spacing.
static func font(path: String, weight: int, tabular: bool = false, spacing: int = 0) -> FontVariation:
	var result := FontVariation.new()
	result.base_font = load(path)
	# Keyed by the OpenType tag as an integer: a "wght" String key is accepted and silently ignored
	# (ui_theme_test measured identical widths at weights 300 and 800 with it).
	result.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if tabular: result.opentype_features = {"tnum": 1}
	result.spacing_glyph = spacing
	return result

## A smoked-glass panel as a nine-patch: GLASS fill, a 1 px `stroke`, and a 1 px highlight just
## inside the top edge. A texture, because StyleBoxFlat cannot draw a second edge colour, and
## faking the highlight with its shadow bleeds through the 82 % fill: in HDR 2D (linear blending)
## a 7 % white shadow lifted the whole panel from #0b0d14 to a flat grey #212225 (measured on the
## first M4 capture).
static func glass_panel(stroke: Color = UiTokens.STROKE) -> StyleBoxTexture:
	var key: String = stroke.to_html()
	if _glass_cache.has(key): return _glass_cache[key]
	var size: int = 48
	var radius: float = UiTokens.RADIUS_PANEL
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var corner := Vector2(clampf(p.x, radius, size - radius), clampf(p.y, radius, size - radius))
			var distance: float = p.distance_to(corner) - radius
			var outside: float = _cover(distance)
			var inner: float = _cover(distance + 1.0)
			var inner2: float = _cover(distance + 2.0)
			var upward: float = clampf(-(p - corner).normalized().y, 0.0, 1.0) if p != corner else 0.0
			var pixel := Color(UiTokens.GLASS, UiTokens.GLASS.a * inner)
			pixel = pixel.blend(Color(UiTokens.HIGHLIGHT, UiTokens.HIGHLIGHT.a * (inner - inner2) * upward * upward))
			pixel = pixel.blend(Color(stroke, stroke.a * (outside - inner)))
			image.set_pixel(x, y, pixel)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.set_texture_margin_all(16)
	style.content_margin_left = UiTokens.SPACE_4
	style.content_margin_right = UiTokens.SPACE_4
	style.content_margin_top = UiTokens.SPACE_3
	style.content_margin_bottom = UiTokens.SPACE_3
	_glass_cache[key] = style
	return style

static var _glass_cache: Dictionary = {}

## Flat glass: `fill` with a `width` px `stroke` and `radius` corners; with `glow`, the gold focus
## glow. A glow is a shadow and shows through a translucent fill, so glowing boxes are opaque.
static func glass_box(fill: Color = UiTokens.GLASS, stroke: Color = UiTokens.STROKE, width: int = 1, radius: int = UiTokens.RADIUS_PANEL, glow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	style.content_margin_left = UiTokens.SPACE_4
	style.content_margin_right = UiTokens.SPACE_4
	style.content_margin_top = UiTokens.SPACE_3
	style.content_margin_bottom = UiTokens.SPACE_3
	if glow:
		style.bg_color.a = 1.0
		style.shadow_color = UiTokens.FOCUS_GLOW
		style.shadow_size = UiTokens.FOCUS_GLOW_SIZE
	return style

static func _button_states(theme: Theme, kind: String, idle: StyleBox, lit: StyleBox, pressed: StyleBox, focus: StyleBox, disabled: StyleBox) -> void:
	theme.set_stylebox("normal", kind, idle)
	theme.set_stylebox("hover", kind, lit)
	theme.set_stylebox("pressed", kind, pressed)
	theme.set_stylebox("hover_pressed", kind, pressed if pressed != idle else lit)
	theme.set_stylebox("focus", kind, focus)
	theme.set_stylebox("disabled", kind, disabled)

static func _button_ink(theme: Theme, kind: String, rest: Color, lit: Color, pressed: Color) -> void:
	theme.set_color("font_color", kind, rest)
	theme.set_color("font_hover_color", kind, lit)
	theme.set_color("font_focus_color", kind, lit)
	theme.set_color("font_pressed_color", kind, pressed)
	theme.set_color("font_hover_pressed_color", kind, pressed)
	theme.set_color("font_disabled_color", kind, UiTokens.INK_DISABLED)

## Anti-aliased coverage of a signed distance (px), for the generated icons.
static func _cover(distance: float) -> float:
	return clampf(0.5 - distance, 0.0, 1.0)

## A toggle switch: a capsule track (gold when on) and a round knob at the end it is set to.
static func switch_icon(on: bool, is_disabled: bool) -> ImageTexture:
	var width: int = 42
	var height: int = 24
	var radius: float = height * 0.5
	var track: Color = UiTokens.FOCUS if on else UiTokens.TRACK
	var knob: Color = UiTokens.CANVAS if on else UiTokens.INK
	if is_disabled:
		track.a *= 0.4
		knob.a *= 0.4
	var knob_centre := Vector2(width - radius, radius) if on else Vector2(radius, radius)
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y: int in range(height):
		for x: int in range(width):
			var p := Vector2(x + 0.5, y + 0.5)
			var track_distance: float = p.distance_to(Vector2(clampf(p.x, radius, width - radius), radius)) - radius
			var base := Color(track, track.a * _cover(track_distance))
			var top := Color(knob, knob.a * _cover(p.distance_to(knob_centre) - (radius - 3.5)))
			image.set_pixel(x, y, base.blend(top))
	return ImageTexture.create_from_image(image)

## A slider knob: a filled disc of `ink` with a dark rim.
static func knob_icon(ink: Color) -> ImageTexture:
	var size: int = 20
	var centre := Vector2(size, size) * 0.5
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var rim := Color(UiTokens.CANVAS, 0.9 * _cover(distance - 9.0))
			image.set_pixel(x, y, rim.blend(Color(ink, ink.a * _cover(distance - 7.5))))
	return ImageTexture.create_from_image(image)

## Display names of ability ids, as the HUD and the evolution cards print them.
static func ability_name(id: String) -> String:
	var definition: AbilityDefinition = AbilityCatalog.get_definition(id)
	return definition.display_name if definition != null else id.replace("_"," ").capitalize()

static func ability_names(ids: Array) -> String:
	var names := PackedStringArray()
	for id: String in ids: names.append(ability_name(id))
	return ", ".join(names) if not names.is_empty() else "None"

static func group(parent: Node) -> Control:
	var result := Control.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	if parent == null: return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	var result := Panel.new()
	result.position = rect.position
	result.size = rect.size
	result.add_theme_stylebox_override("panel",box(fill,border))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

## A smoked-glass card (the theme's Panel style); a `tint` with alpha replaces the stroke colour
## (an evolution card edged in its element).
static func glass(parent: Node, rect: Rect2, tint: Color = Color(0, 0, 0, 0)) -> Panel:
	var result := Panel.new()
	result.position = rect.position
	result.size = rect.size
	if tint.a > 0.0: result.add_theme_stylebox_override("panel", glass_panel(tint))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text = text
	result.position = position
	result.size = size
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	type_role(result,font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

## The one place a label's size picks its family: display type (Exo 2) at UiTokens.DISPLAY_MIN
## and above, body type (Inter, the theme default) below.
static func type_role(target: Label, font_size: int) -> void:
	if font_size >= UiTokens.DISPLAY_MIN: target.theme_type_variation = UiTokens.DISPLAY_LABEL

static func button(parent: Node, text: String, rect: Rect2, action: Callable, on_click: Callable = Callable()) -> Button:
	var result := Button.new()
	result.clip_text = true
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(result)
	result.pressed.connect(func() -> void:
		if on_click.is_valid(): on_click.call()
		action.call())
	return result

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var result := ProgressBar.new()
	result.position = rect.position
	result.size = rect.size
	result.show_percentage = false
	result.add_theme_font_size_override("font_size",1)
	result.add_theme_stylebox_override("background",box(Color("1a202a"),Color(0,0,0,0),0))
	result.add_theme_stylebox_override("fill",box(color,Color(0,0,0,0),0))
	parent.add_child(result)
	result.size = rect.size
	return result
