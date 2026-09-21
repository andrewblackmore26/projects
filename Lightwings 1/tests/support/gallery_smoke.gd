extends SceneTree
## Ad hoc, not part of the gated suite: instantiate the gallery scene and print engine errors.
func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var packed: PackedScene = load("res://scenes/gallery.tscn")
	var screen: Node = packed.instantiate()
	root.add_child.call_deferred(screen)
	_wait.call_deferred()

func _wait() -> void:
	await process_frame
	await process_frame
	await process_frame
	print("GALLERY SMOKE OK")
	quit(0)
