extends SceneTree
## Modernization M15: every setting the Options screen writes survives a restart, and the ones that
## act on the game take effect when applied.
## - ROUND TRIP: each key M15 added (and the M6 scales it now exposes) is set to a non-default
##   value, saved through main.gd's save_settings, and read back by a FRESH main.gd through
##   load_settings - value and type (an int stays an int).
## - APPLY: apply_settings hands them on: UiMotion.reduced, ElementStyle.colorblind, Engine.max_fps,
##   the FeelDirector's flash and rumble scales, UiLayout's text scale, the UI layer's scale, and
##   reduced motion implying the reduced warp.
## - MIGRATE: a v0.2-era device.cfg holding only `fullscreen = true` loads as a borderless window;
##   one that already names a window mode keeps it.
## Negative controls, one per line: a key the defaults table does not list (it is saved but never
## read back: ROUND TRIP), the apply check run with reduced motion off (APPLY), and the migration run
## on a file that already has `window_mode` (MIGRATE).
const Harness = preload("res://tests/support/harness.gd")

## key -> a value different from its default.
const CHANGED: Dictionary = {
	"window_mode": "exclusive", "resolution": "1600x900", "vsync": "adaptive", "fps_cap": 144,
	"screen_shake": 0.3, "flash_intensity": 0.2, "reduced_motion": true, "colorblind": true,
	"rumble": 0.4, "text_scale": 1.2, "ui_scale": 1.3, "volume": 0.25, "ambience_volume": 0.6,
	"effects_volume": 0.8, "interface_volume": 0.1, "damage_numbers": true, "reduced_warp": true,
}

var h := Harness.new("Settings persistence")
var files: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _app(path: String) -> Node:
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://settings-persist-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	app.settings_path = path
	root.add_child(app)
	return app

func _free(app: Node) -> void:
	await app._stop_audio()
	app.queue_free()
	await process_frame

func _path(tag: String) -> String:
	var path: String = "user://settings-persist-%s-%d.cfg" % [tag, Time.get_ticks_usec()]
	files.append(path)
	return path

func _run() -> void:
	var path: String = _path("round")
	var first: Node = _app(path)
	await process_frame
	var defaults: Dictionary = first.settings.duplicate(true)
	for key: String in CHANGED:
		h.check(defaults.has(key), "%s has a default in main.gd's settings table" % key)
		h.check(defaults.get(key) != CHANGED[key], "the test value of %s differs from its default %s" % [key, str(defaults.get(key))])
		first.settings[key] = CHANGED[key]
	first.settings["m15_unlisted_probe"] = 7
	first.save_settings()
	await _free(first)
	# ROUND TRIP: a fresh app, the same file.
	var second: Node = _app(path)
	await process_frame
	var lost: PackedStringArray = []
	for key: String in CHANGED:
		var back: Variant = second.settings.get(key)
		if typeof(back) != typeof(CHANGED[key]) or back != CHANGED[key]: lost.append("%s=%s (%s)" % [key, str(back), type_string(typeof(back))])
	h.check(lost.is_empty(), "ROUND TRIP: every setting comes back with its value and type (lost: %s)" % ", ".join(lost))
	h.control("a key missing from the defaults table is not read back (got %s)" % str(second.settings.get("m15_unlisted_probe")), second.settings.get("m15_unlisted_probe") != 7)
	# APPLY: _ready applied what it loaded.
	var director: Node = null
	for child: Node in second.get_children():
		if child is FeelDirector: director = child
	var applied: Dictionary = _applied(second, director)
	print("measure: applied %s" % JSON.stringify(applied))
	var wrong: PackedStringArray = []
	for key: String in applied:
		if not bool(applied[key]): wrong.append(key)
	h.check(wrong.is_empty(), "APPLY: the loaded settings are in effect (wrong: %s)" % ", ".join(wrong))
	second.settings.reduced_motion = false
	second.apply_settings()
	h.control("the apply check with reduced motion switched off", not bool(_applied(second, director).reduced_motion))
	await _free(second)
	Engine.max_fps = 0
	UiMotion.reduced = false
	ElementStyle.colorblind = false
	UiLayout.text_scale = 1.0
	# MIGRATE: an old file with only `fullscreen = true`.
	var old_path: String = _path("old")
	var old := ConfigFile.new()
	old.set_value("device", "fullscreen", true)
	old.set_value("device", "volume", 0.5)
	old.save(old_path)
	var migrated: Node = _app(old_path)
	await process_frame
	h.check(migrated.settings.window_mode == "borderless" and bool(migrated.settings.fullscreen) and is_equal_approx(float(migrated.settings.volume), 0.5), "MIGRATE: a v0.2 device.cfg with fullscreen = true loads as a borderless window (got %s)" % migrated.settings.window_mode)
	await _free(migrated)
	var new_path: String = _path("new")
	var current := ConfigFile.new()
	current.set_value("device", "fullscreen", true)
	current.set_value("device", "window_mode", "windowed")
	current.save(new_path)
	var kept: Node = _app(new_path)
	await process_frame
	h.control("the migration on a file that already names its window mode (got %s)" % kept.settings.window_mode, kept.settings.window_mode != "borderless")
	h.check(kept.settings.window_mode == "windowed" and not bool(kept.settings.fullscreen), "a saved window mode wins over the old flag, and the flag follows it")
	await _free(kept)
	for file: String in files: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	h.finish(self)

## Whether each applied effect matches CHANGED, by name.
func _applied(app: Node, director: Node) -> Dictionary:
	var result: Dictionary = {
		"reduced_motion": UiMotion.reduced == bool(CHANGED.reduced_motion),
		"colorblind": ElementStyle.colorblind == bool(CHANGED.colorblind) and ElementStyle.color("fire") == ElementStyle.SAFE.fire,
		"fps_cap": Engine.max_fps == int(CHANGED.fps_cap),
		"text_scale": is_equal_approx(UiLayout.text_scale, float(CHANGED.text_scale)),
		"ui_scale": app.ui_layer.scale.is_equal_approx(Vector2.ONE * float(CHANGED.ui_scale)),
	}
	if director != null:
		result.flash_intensity = is_equal_approx(director.post.flash_setting, float(CHANGED.flash_intensity))
		result.rumble = is_equal_approx(director.rumble.scale, float(CHANGED.rumble))
	else:
		result.feel_director = false
	return result
