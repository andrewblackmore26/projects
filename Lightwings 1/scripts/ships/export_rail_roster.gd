extends SceneTree
## Writes the rail roster (RailRoster.manifest through ShipRecipe) into a catalog root.
##   tools\godot.ps1 -Arguments '--headless --script "res://scripts/ships/export_rail_roster.gd"'
##   ... -- --root=res://content/ships        (the cutover; the default is the staging root)
## Every hull must pass the style check or nothing is reported as a success.

func _initialize() -> void:
	var root: String = RailRoster.STAGING_ROOT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--root="): root = argument.trim_prefix("--root=")
	var result: Dictionary = RailRoster.write_all(root)
	for failure: String in result.failures: push_error(failure)
	print("Rail roster -> %s: %d written, %d stale removed, %d failures" % [root, result.written, result.removed, (result.failures as PackedStringArray).size()])
	quit(1 if not (result.failures as PackedStringArray).is_empty() else 0)
