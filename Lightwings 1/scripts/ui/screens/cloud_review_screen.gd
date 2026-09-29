class_name CloudReviewScreen
extends UiScreen
## The Steam Cloud conflict review (moved from main.gd in M2). Reads `app.cloud_review`, which the
## title screen fills from PlatformService.inspect_cloud.
##
## M15: the shared modal card (ConfirmScreen.card) with the two saves side by side, each in its own
## panel with its choice under it; DECIDE LATER is focused, so nothing is replaced by accident.
## M19 review: each side also says when it was last played and how long it has been played (the
## save envelope's metadata, SaveService.read_meta), and the more recent one is marked; the two
## source labels are neutral, so neither side reads as the recommended one by colour.

const CARD: Rect2 = Rect2(170, 100, 940, 610)
const SIDE_HEIGHT: float = 236.0
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func build() -> void:
	var review: Dictionary = app.cloud_review
	ConfirmScreen.card(host, CARD, "STEAM CLOUD", "CHOOSE YOUR INSTANCE", "This device and Steam have different saves. Neither will be replaced until you choose.")
	var choices: Array = []
	var metas: Array = [review.get("local_meta", {}), review.get("remote_meta", {})]
	var newer: int = -1
	if int(metas[0].get("saved_at", -1)) >= 0 and int(metas[1].get("saved_at", -1)) >= 0 and int(metas[0].saved_at) != int(metas[1].saved_at):
		newer = 0 if int(metas[0].saved_at) > int(metas[1].saved_at) else 1
	var sides: Array = [["ON THIS DEVICE", str(review.get("local_summary", "No local save")), "KEEP THIS DEVICE", "keep_local"], ["IN STEAM CLOUD", str(review.get("remote_summary", "Cloud save available")), "USE STEAM CLOUD", "use_cloud"]]
	for index: int in range(sides.size()):
		var side: Array = sides[index]
		var rect := Rect2(CARD.position.x + 48 + index * 434, CARD.position.y + 224, 410, SIDE_HEIGHT)
		var panel: Panel = UiKit.glass(host, rect, Color(UiTokens.STROKE.lightened(0.15), 1.0))
		panel.name = "Side%d" % index
		var heading: Label = UiKit.label(host, str(side[0]), rect.position + Vector2(24, 22), Vector2(240, 18), UiTokens.TEXT_XS, UiTokens.INK_MUTED)
		heading.theme_type_variation = UiTokens.KICKER_LABEL
		heading.add_theme_color_override("font_color", UiTokens.INK_MUTED)
		if index == newer:
			var recent: Label = UiKit.label(host, "MOST RECENT", rect.position + Vector2(rect.size.x - 24 - 140, 22), Vector2(140, 18), UiTokens.TEXT_XS, UiTokens.INK)
			recent.theme_type_variation = UiTokens.KICKER_LABEL
			recent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UiKit.label(host, str(side[1]), rect.position + Vector2(24, 48), Vector2(362, 30), UiTokens.TEXT_L, WHITE).autowrap_mode = TextServer.AUTOWRAP_OFF
		var meta: Dictionary = metas[index]
		UiKit.label(host, "Last played   " + last_played(int(meta.get("saved_at", -1))), rect.position + Vector2(24, 88), Vector2(362, 20), UiTokens.TEXT_S, MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
		UiKit.label(host, "Play time   " + play_time(int(meta.get("play_seconds", -1))), rect.position + Vector2(24, 112), Vector2(362, 20), UiTokens.TEXT_S, MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
		choices.append(button(host, str(side[2]), Rect2(rect.position.x + 24, rect.end.y - 70, 362, 50), _resolve_cloud.bind(str(side[3]))))
	_focus = button(host, "DECIDE LATER", Rect2(CARD.get_center().x - 160, CARD.end.y - 84, 320, 48), app._close_overlay)
	FocusChain.rows([choices, [_focus]])
	var hints := PromptHints.new([["change", "CHOOSE"], ["ui_accept", "CONFIRM"], ["ui_cancel", "LATER"]])
	ConfirmScreen.centre_hints(host, hints, CARD)

## "28 Sep 2026 · 21:14" in the player's local time, or "unknown" for a save that never said.
static func last_played(saved_at: int) -> String:
	if saved_at < 0: return "unknown"
	var local: int = saved_at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(local)
	return "%d %s %d · %02d:%02d" % [int(date.day), MONTHS[clampi(int(date.month) - 1, 0, 11)], int(date.year), int(date.hour), int(date.minute)]

## "3 h 12 min", "12 min", "under a minute", or "not recorded" for a save from before M19.
static func play_time(seconds: int) -> String:
	if seconds < 0: return "not recorded"
	if seconds < 60: return "under a minute"
	var minutes: int = seconds / 60
	return "%d h %d min" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d min" % minutes

func _resolve_cloud(choice: String) -> void:
	var result: Error = app.platform.resolve_cloud(choice,"campaign",app.cloud_review.get("remote_bytes",PackedByteArray()))
	if result != OK:
		app._toast("Cloud save could not be changed: " + error_string(result))
		return
	app.cloud_sync_ready = true
	app._close_overlay()
	app._show_menu()
