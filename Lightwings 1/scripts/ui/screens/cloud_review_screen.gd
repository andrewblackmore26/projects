class_name CloudReviewScreen
extends UiScreen
## The Steam Cloud conflict review (moved from main.gd in M2). Reads `app.cloud_review`, which the
## title screen fills from PlatformService.inspect_cloud.
##
## M15: the shared modal card (ConfirmScreen.card) with the two saves side by side, each in its own
## panel with its choice under it; DECIDE LATER is focused, so nothing is replaced by accident.

const CARD: Rect2 = Rect2(170, 110, 940, 590)

func build() -> void:
	var review: Dictionary = app.cloud_review
	ConfirmScreen.card(host, CARD, "STEAM CLOUD", "CHOOSE YOUR INSTANCE", "This device and Steam have different saves. Neither will be replaced until you choose.")
	var choices: Array = []
	var sides: Array = [["ON THIS DEVICE", str(review.get("local_summary", "No local save")), "KEEP THIS DEVICE", "keep_local"], ["IN STEAM CLOUD", str(review.get("remote_summary", "Cloud save available")), "USE STEAM CLOUD", "use_cloud"]]
	for index: int in range(sides.size()):
		var side: Array = sides[index]
		var rect := Rect2(CARD.position.x + 48 + index * 434, CARD.position.y + 224, 410, 190)
		var panel: Panel = UiKit.glass(host, rect, Color(UiTokens.STROKE.lightened(0.15), 1.0))
		panel.name = "Side%d" % index
		var heading: Label = UiKit.label(host, str(side[0]), rect.position + Vector2(24, 22), Vector2(362, 18), UiTokens.TEXT_XS, UiTokens.PLAYER if index == 0 else GOLD)
		heading.theme_type_variation = UiTokens.KICKER_LABEL
		heading.add_theme_color_override("font_color", UiTokens.PLAYER if index == 0 else GOLD)
		UiKit.label(host, str(side[1]), rect.position + Vector2(24, 48), Vector2(362, 60), UiTokens.TEXT_L, WHITE)
		choices.append(button(host, str(side[2]), Rect2(rect.position.x + 24, rect.end.y - 70, 362, 50), _resolve_cloud.bind(str(side[3]))))
	_focus = button(host, "DECIDE LATER", Rect2(CARD.get_center().x - 160, CARD.end.y - 84, 320, 48), app._close_overlay)
	FocusChain.rows([choices, [_focus]])
	var hints := PromptHints.new([["change", "CHOOSE"], ["ui_accept", "CONFIRM"], ["ui_cancel", "LATER"]])
	hints.position = Vector2(CARD.position.x + 8, CARD.end.y + 16)
	host.add_child(hints)

func _resolve_cloud(choice: String) -> void:
	var result: Error = app.platform.resolve_cloud(choice,"campaign",app.cloud_review.get("remote_bytes",PackedByteArray()))
	if result != OK:
		app._toast("Cloud save could not be changed: " + error_string(result))
		return
	app.cloud_sync_ready = true
	app._close_overlay()
	app._show_menu()
