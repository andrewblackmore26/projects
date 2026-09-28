class_name CloudReviewScreen
extends UiScreen
## The Steam Cloud conflict review (moved from main.gd in M2). Reads `app.cloud_review`, which the
## title screen fills from PlatformService.inspect_cloud.

func build() -> void:
	var review: Dictionary = app.cloud_review
	centered_label(host,"CHOOSE YOUR INSTANCE",Vector2(180,165),Vector2(920,65),34,WHITE)
	centered_label(host,"This device and Steam have different saves. Neither will be replaced until you choose.",Vector2(200,250),Vector2(880,70),18,MUTED)
	UiKit.label(host,"ON THIS DEVICE\n"+str(review.get("local_summary","No local save")),Vector2(215,350),Vector2(385,160),16,WHITE)
	UiKit.label(host,"IN STEAM CLOUD\n"+str(review.get("remote_summary","Cloud save available")),Vector2(675,350),Vector2(385,160),16,WHITE)
	button(host,"KEEP THIS DEVICE",Rect2(215,550,385,52),_resolve_cloud.bind("keep_local"))
	button(host,"USE STEAM CLOUD",Rect2(675,550,385,52),_resolve_cloud.bind("use_cloud"))
	_focus = button(host,"DECIDE LATER",Rect2(480,658,320,45),app._close_overlay)

func _resolve_cloud(choice: String) -> void:
	var result: Error = app.platform.resolve_cloud(choice,"campaign",app.cloud_review.get("remote_bytes",PackedByteArray()))
	if result != OK:
		app._toast("Cloud save could not be changed: " + error_string(result))
		return
	app.cloud_sync_ready = true
	app._close_overlay()
	app._show_menu()
