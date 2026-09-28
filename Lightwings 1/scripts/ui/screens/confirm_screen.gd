class_name ConfirmScreen
extends UiScreen
## The two confirmation dialogs (moved from main.gd in M2); the save work behind them stays in
## main.gd (`_replace_game`, `_perform_import`, which archive the old save first).
## args: {variant: "new_game", is_demo} or {variant: "import_demo"}.
##
## M15: one card in the modal style every dialog shares (kicker, title, body, a coral outline on the
## action that replaces progress, CANCEL focused so a stray confirm can never destroy anything).

const CARD: Rect2 = Rect2(330, 220, 620, 340)

func build() -> void:
	var is_demo: bool = bool(args.get("is_demo", false))
	var copy: Dictionary = {
		"new_game": {"kicker": "NEW DEMO" if is_demo else "NEW CAMPAIGN", "title": "BEGIN A NEW DEMO?" if is_demo else "BEGIN A NEW CAMPAIGN?", "body": "Your current progress is kept in a separate archive.", "action": "NEW DEMO" if is_demo else "NEW CAMPAIGN", "call": app._replace_game.bind(is_demo)},
		"import_demo": {"kicker": "IMPORT DEMO", "title": "REPLACE CAMPAIGN WITH DEMO PROGRESS?", "body": "The current campaign will remain in a separate archive.", "action": "IMPORT DEMO", "call": app._perform_import},
	}.get(str(args.variant), {})
	if copy.is_empty(): return
	card(host, CARD, str(copy.kicker), str(copy.title), str(copy.body))
	var y: float = CARD.end.y - 84
	var action: Button = button(host, str(copy.action), Rect2(CARD.position.x + 40, y, 260, 52), copy.call)
	danger(action)
	_focus = button(host, "CANCEL", Rect2(CARD.end.x - 300, y, 260, 52), app._close_overlay)
	FocusChain.rows([[action, _focus]])
	hints(host, CARD)

## The shared modal card: a glass panel with a gold kicker, a display title and a muted body.
## Returns {panel, kicker, title, body}.
static func card(parent: Control, rect: Rect2, kicker_text: String, title_text: String, body_text: String) -> Dictionary:
	var panel: Panel = UiKit.glass(parent, rect)
	panel.name = "Card"
	var kicker: Label = centered_label(parent, kicker_text, rect.position + Vector2(40, 36), Vector2(rect.size.x - 80, 18), UiTokens.TEXT_XS, GOLD)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	var title: Label = centered_label(parent, title_text, rect.position + Vector2(40, 60), Vector2(rect.size.x - 80, 88), UiTokens.TEXT_XL, WHITE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var body: Label = centered_label(parent, body_text, rect.position + Vector2(40, 156), Vector2(rect.size.x - 80, 48), UiTokens.TEXT_M, MUTED)
	return {"panel": panel, "kicker": kicker, "title": title, "body": body}

## A destructive action: a coral outline at rest, coral fill when lit.
static func danger(target: Button) -> void:
	var rest: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.DANGER, 0.08), Color(UiTokens.DANGER, 0.8), 1, UiTokens.CAPSULE)
	var lit: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.DANGER, 0.9), UiTokens.DANGER, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE)
	var focus: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.DANGER, 0.9), UiTokens.FOCUS, UiTokens.FOCUS_BORDER, UiTokens.CAPSULE, true)
	for style: StyleBoxFlat in [rest, lit, focus]:
		style.content_margin_left = UiTokens.SPACE_5
		style.content_margin_right = UiTokens.SPACE_5
	target.add_theme_stylebox_override("normal", rest)
	target.add_theme_stylebox_override("hover", lit)
	target.add_theme_stylebox_override("pressed", lit)
	target.add_theme_stylebox_override("focus", focus)
	target.add_theme_color_override("font_color", UiTokens.DANGER.lightened(0.25))
	for ink: String in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(ink, UiTokens.CANVAS)

## The footer hints under a card.
static func hints(parent: Control, rect: Rect2) -> PromptHints:
	var result := PromptHints.new([["change", "CHOOSE"], ["ui_accept", "CONFIRM"], ["ui_cancel", "CANCEL"]])
	result.position = Vector2(rect.position.x + 8, rect.end.y + 16)
	parent.add_child(result)
	return result
