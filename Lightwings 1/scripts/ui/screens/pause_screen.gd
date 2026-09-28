class_name PauseScreen
extends UiScreen
## The in-game pause menu (moved from main.gd's `_show_pause` in M2). Options opens over it and
## returns to it (ScreenRouter policy `returns`).
##
## M15: over the blurred live game (policy backdrop dim_blur). Left, the actions: RESUME (focused),
## OPTIONS, SAVE & MAIN MENU, SAVE & QUIT. Right, the build the player is flying - hull, element,
## tier, every weapon and passive as its HUD glyph with the input that fires it, and the run's
## numbers. This is where the build readout lives now that the floating HUD dropped its text block
## (the same data as main.gd's `_component_controls`: each secondary's bound input and name).

const ACTIONS: Rect2 = Rect2(110, 130, 440, 560)
const BUILD: Rect2 = Rect2(580, 130, 590, 560)
const ROW_HEIGHT: float = 52.0
## The live hull preview's square, and the width the text beside it may take.
const PREVIEW: float = 160.0
const TEXT_WIDTH: float = 330.0

func build() -> void:
	UiKit.glass(host, ACTIONS).name = "ActionsCard"
	var kicker: Label = UiKit.label(host, "RUN PAUSED", ACTIONS.position + Vector2(32, 30), Vector2(376, 18), UiTokens.TEXT_XS, GOLD)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	UiKit.label(host, "PAUSED", ACTIONS.position + Vector2(32, 50), Vector2(376, 52), UiTokens.TEXT_2XL, WHITE).autowrap_mode = TextServer.AUTOWRAP_OFF
	UiKit.label(host, _where(), ACTIONS.position + Vector2(32, 120), Vector2(376, 22), UiTokens.TEXT_S, MUTED)
	var x: float = ACTIONS.position.x + 32
	_focus = button(host, "RESUME", Rect2(x, 290, 376, 56), app._close_overlay)
	_focus.theme_type_variation = UiTokens.PRIMARY_BUTTON
	var options: Button = button(host, "OPTIONS & CONTROLS", Rect2(x, 362, 376, 50), app._show_options)
	var menu: Button = button(host, "SAVE & MAIN MENU", Rect2(x, 426, 376, 50), func() -> void: app._save_game(); app._show_menu())
	var quit: Button = button(host, "SAVE & QUIT", Rect2(x, 490, 376, 50), app._quit)
	FocusChain.rows([[_focus], [options], [menu], [quit]])
	var hints := PromptHints.new([["ui_accept", "SELECT"], ["ui_cancel", "RESUME"]])
	hints.position = ACTIONS.position + Vector2(32, ACTIONS.size.y - 54)
	host.add_child(hints)
	_build_summary()

## "Level 2 · node 1,-2 · ring 3" for the run that is paused.
func _where() -> String:
	var campaign: CampaignState = app.campaign
	if campaign == null: return ""
	return "%s · level %d · node %s · ring %d" % [app.mode_config.menu_label().capitalize(), campaign.level, CampaignState.coord_key(campaign.current_sector), campaign.ring_reached]

func _build_summary() -> void:
	UiKit.glass(host, BUILD).name = "BuildCard"
	var combat: CombatWorld = app.combat
	var ship: ShipDefinition = combat.player.get("definition") if is_instance_valid(combat) else null
	var origin: Vector2 = BUILD.position + Vector2(32, 30)
	var kicker: Label = UiKit.label(host, "CURRENT BUILD", origin, Vector2(300, 18), UiTokens.TEXT_XS, GOLD)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	if ship == null:
		UiKit.label(host, "No ship is flying.", origin + Vector2(0, 30), Vector2(400, 24), UiTokens.TEXT_M, MUTED)
		return
	# The hull itself, live, in the card's top-right corner.
	var preview := ShipPreview.new()
	preview.name = "BuildHull"
	preview.focus_mode = Control.FOCUS_NONE
	preview.fit_margin = 22.0
	preview.position = Vector2(BUILD.end.x - 32 - PREVIEW, BUILD.position.y + 12)
	host.add_child(preview)
	preview.initialize(ship, Vector2(PREVIEW, PREVIEW), 0.9)
	var name_label: Label = UiKit.label(host, ship.display_name, origin + Vector2(0, 20), Vector2(TEXT_WIDTH, 40), UiTokens.TEXT_XL, WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The element chip: its glyph in its colour, then "ELEMENT · T3 STANDARD".
	var element: String = ship.element if not ship.element.is_empty() else str(combat.player_element)
	var chip := MenuDraw.new(func(canvas: MenuDraw) -> void:
		var centre: Vector2 = canvas.size * 0.5
		var ink: Color = ElementStyle.color(element)
		canvas.draw_circle(centre, canvas.size.x * 0.5, Color(ink.darkened(0.85), 0.95))
		canvas.draw_arc(centre, canvas.size.x * 0.5 - 0.75, 0.0, TAU, 32, Color(ink, 0.8), 1.5, true)
		ElementStyle.draw_glyph(canvas, element, centre, canvas.size.x * 0.3, ink, 1.75))
	chip.name = "ElementChip"
	chip.position = origin + Vector2(0, 68)
	chip.size = Vector2(28, 28)
	host.add_child(chip)
	var element_label: Label = UiKit.label(host, "%s · T%d %s" % [ElementStyle.display_name(element).to_upper(), ship.tier, ship.role.to_upper()], origin + Vector2(38, 72), Vector2(TEXT_WIDTH - 38, 20), UiTokens.TEXT_XS, ElementStyle.color(element))
	element_label.theme_type_variation = UiTokens.KICKER_LABEL
	element_label.add_theme_color_override("font_color", ElementStyle.color(element))
	# The light bar toward the next tier.
	var next: int = EvolutionRules.threshold(combat.player_tier)
	var capped: bool = next < 0 or combat.player_tier >= app.mode_config.max_tier()
	var light_text: String = "LIGHT %d · MAX TIER" % roundi(combat.light_total) if capped else "LIGHT %d / %d · NEXT T%d" % [roundi(combat.light_total), next, combat.player_tier + 1]
	UiKit.label(host, light_text, origin + Vector2(0, 110), Vector2(TEXT_WIDTH, 20), UiTokens.TEXT_S, UiTokens.PLAYER).autowrap_mode = TextServer.AUTOWRAP_OFF
	var fill: float = 1.0 if capped else clampf(combat.light_total / maxf(1.0, float(next)), 0.0, 1.0)
	var bar := MenuDraw.new(func(canvas: MenuDraw) -> void:
		var rect := Rect2(Vector2.ZERO, canvas.size)
		canvas.draw_rect(rect, UiTokens.TRACK)
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill * canvas.progress, rect.size.y)), UiTokens.PLAYER))
	bar.name = "LightBar"
	bar.position = origin + Vector2(0, 136)
	bar.size = Vector2(TEXT_WIDTH, 4)
	bar.progress = 0.0
	host.add_child(bar)
	UiMotion.tween(bar).tween_property(bar, "progress", 1.0, UiMotion.duration(UiTokens.CINE)).set_delay(UiMotion.duration(UiTokens.FAST)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	# One row per mounted ability: glyph, name, kind, and the input that fires it.
	var y: float = origin.y + 160
	var rows: Array = [[ship.primary, "PRIMARY WEAPON", "fire"]]
	for index: int in range(ship.secondaries.size()):
		rows.append([ship.secondaries[index], "SECONDARY %d" % (index + 1), InputPrompts.SLOT_ACTIONS[index] if index < InputPrompts.SLOT_ACTIONS.size() else ""])
	for passive: String in ship.passives: rows.append([passive, "PASSIVE", ""])
	var room: int = int((BUILD.end.y - 84 - y) / ROW_HEIGHT)
	for index: int in range(mini(rows.size(), room)):
		_ability_row(str(rows[index][0]), str(rows[index][1]), str(rows[index][2]), Vector2(origin.x, y + index * ROW_HEIGHT))
	# The life's numbers along the bottom.
	var stats: String = "KILLS %d   ·   TIME %s   ·   REBOOTS %d" % [combat.run_kills, _clock(combat.elapsed), app.campaign.deaths if app.campaign != null else 0]
	var stats_label: Label = UiKit.label(host, stats, Vector2(origin.x, BUILD.end.y - 48), Vector2(526, 20), UiTokens.TEXT_XS, MUTED)
	stats_label.theme_type_variation = UiTokens.KICKER_LABEL
	stats_label.add_theme_color_override("font_color", MUTED)

func _ability_row(id: String, kind: String, action: String, at: Vector2) -> void:
	var glyph := MenuDraw.new(func(canvas: MenuDraw) -> void:
		var centre: Vector2 = canvas.size * 0.5
		var definition: AbilityDefinition = AbilityCatalog.get_definition(id)
		var ink: Color = ShipCatalog.get_color(definition.visual_color) if definition != null else UiTokens.INK_MUTED
		canvas.draw_circle(centre, 17.0, Color(ink.r * 0.1, ink.g * 0.1, ink.b * 0.1))
		canvas.draw_arc(centre, 17.0, 0.0, TAU, 32, Color(ink, 0.9), 1.5, true)
		AbilityGlyphs.draw(canvas, id, centre, 13.0))
	glyph.name = "Glyph_" + id
	glyph.position = at
	glyph.size = Vector2(36, 36)
	host.add_child(glyph)
	UiKit.label(host, UiKit.ability_name(id), at + Vector2(50, -4), Vector2(380, 22), UiTokens.TEXT_M, WHITE).autowrap_mode = TextServer.AUTOWRAP_OFF
	var kind_label: Label = UiKit.label(host, kind, at + Vector2(50, 24), Vector2(300, 16), UiTokens.TEXT_XS, MUTED)
	kind_label.theme_type_variation = UiTokens.KICKER_LABEL
	kind_label.add_theme_color_override("font_color", MUTED)
	if action.is_empty(): return
	var prompt: Dictionary = InputPrompts.shared().prompt_for(action)
	if prompt.texture != null:
		var binding := TextureRect.new()
		binding.name = "Binding_" + action
		binding.texture = prompt.texture
		binding.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		binding.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		binding.position = at + Vector2(490, 2)
		binding.size = Vector2(32, 32)
		host.add_child(binding)
	else:
		var text: Label = UiKit.label(host, str(prompt.text), at + Vector2(430, 8), Vector2(92, 20), UiTokens.TEXT_XS, VisualStyle.CORAL if bool(prompt.missing) else WHITE)
		text.theme_type_variation = UiTokens.MONO_LABEL
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

static func _clock(seconds: float) -> String:
	var whole: int = int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]
