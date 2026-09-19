extends SceneTree

var ticks: int = 0
var screen: Node
var capture: String = "user://ship_editor.png"
var player_gallery: bool = false

func _initialize() -> void:
	var scene: String = "res://scenes/ship_editor.tscn"
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--gallery": scene = "res://scenes/gallery.tscn"
		if argument == "--player": player_gallery = true
		if argument.begins_with("--capture="): capture = argument.trim_prefix("--capture=")
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var packed: PackedScene = load(scene)
	screen = packed.instantiate()
	root.add_child.call_deferred(screen)

func _process(_delta: float) -> bool:
	ticks += 1
	if ticks == 3 and player_gallery:
		screen.set("_player", true)
		screen.call("_populate")
	if ticks == 20:
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	screenshot.convert(Image.FORMAT_RGB8)
	screenshot.linear_to_srgb()
	var result: Error = screenshot.save_png(capture)
	print("SHIP CAPTURE ", capture, " ", error_string(result))
	quit(0 if result == OK else 1)
