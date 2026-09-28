extends SceneTree
## Bakes UiKit.build_theme() into theme/lightship_theme.tres (modernization M4), the one Theme
## every UI root loads through UiKit.make_theme(). Run it after changing UiTokens or build_theme;
## ui_theme_test fails while the baked file and the code disagree.
##   tools\godot.ps1 -Arguments '--headless --script "res://tools/build_theme.gd"'
## The fonts must be imported first (tools\test.ps1 -Only import).

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UiKit.THEME_PATH.get_base_dir()))
	var theme: Theme = UiKit.build_theme()
	var error: Error = ResourceSaver.save(theme, UiKit.THEME_PATH)
	# The body font on its own: project.godot's gui/theme/custom_font, which makes it
	# ThemeDB.fallback_font for every draw_string in the game (the HUD, combat numbers, the map).
	var font_error: Error = ResourceSaver.save(UiKit.font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY, true), UiKit.BODY_FONT_PATH)
	var types: int = theme.get_type_list().size()
	print("BUILD THEME: %s, %d types, %d styleboxes, error %d; %s error %d" % [UiKit.THEME_PATH, types, _stylebox_count(theme), error, UiKit.BODY_FONT_PATH, font_error])
	error = error if error != OK else font_error
	quit(0 if error == OK else 1)

func _stylebox_count(theme: Theme) -> int:
	var count: int = 0
	for kind: String in theme.get_type_list(): count += theme.get_stylebox_list(kind).size()
	return count
