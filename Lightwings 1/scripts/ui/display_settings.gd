class_name DisplaySettings
extends RefCounted
## The settings that act on the window, the frame pacing and the interface as a whole
## (modernization M15), applied from main.gd's apply_settings in one call:
## - `window_mode`: "windowed" | "borderless" (Godot's WINDOW_MODE_FULLSCREEN, a borderless window
##   over the screen) | "exclusive" (WINDOW_MODE_EXCLUSIVE_FULLSCREEN). The old boolean
##   `fullscreen` is kept in step for anything that still reads it, and a v0.2-era device.cfg with
##   only `fullscreen = true` loads as "borderless" (what that flag always meant; `migrate`).
## - `resolution`: "auto" (leave the window as it is) or "WxH", applied only in windowed mode.
## - `vsync`: "on" | "adaptive" | "off".  `fps_cap`: Engine.max_fps (0 = unlimited).
## - `reduced_motion` -> UiMotion.reduced;  `colorblind` -> ElementStyle.colorblind.
## The window is touched only when one of its own keys changed since the last apply, so toggling an
## unrelated setting never resizes or re-centres a window the player moved. The benchmark keeps its
## own vsync-off, uncapped frame (main.gd's --benchmark), and headless runs touch no window.

const WINDOW_MODES: Dictionary = {
	"windowed": DisplayServer.WINDOW_MODE_WINDOWED,
	"borderless": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"exclusive": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
}
const VSYNC_MODES: Dictionary = {
	"on": DisplayServer.VSYNC_ENABLED,
	"adaptive": DisplayServer.VSYNC_ADAPTIVE,
	"off": DisplayServer.VSYNC_DISABLED,
}

## The window keys as last applied ({} before the first apply).
static var _applied: Dictionary = {}

static func apply(settings: Dictionary, benchmark: bool = false) -> void:
	UiMotion.reduced = bool(settings.get("reduced_motion", false))
	ElementStyle.colorblind = bool(settings.get("colorblind", false))
	Engine.max_fps = 0 if benchmark else maxi(0, int(settings.get("fps_cap", 0)))
	if DisplayServer.get_name() == "headless": return
	var wanted: Dictionary = {"window_mode": str(settings.get("window_mode", "windowed")), "resolution": str(settings.get("resolution", "auto")), "vsync": "off" if benchmark else str(settings.get("vsync", "on"))}
	if wanted == _applied: return
	var first: bool = _applied.is_empty()
	if first or wanted.vsync != _applied.get("vsync"):
		DisplayServer.window_set_vsync_mode(VSYNC_MODES.get(wanted.vsync, DisplayServer.VSYNC_ENABLED))
	if first or wanted.window_mode != _applied.get("window_mode"):
		DisplayServer.window_set_mode(WINDOW_MODES.get(wanted.window_mode, DisplayServer.WINDOW_MODE_WINDOWED))
	if wanted.window_mode == "windowed" and wanted.resolution != "auto" and (first or wanted.resolution != _applied.get("resolution") or wanted.window_mode != _applied.get("window_mode")):
		var size := Vector2i(int(wanted.resolution.get_slice("x", 0)), int(wanted.resolution.get_slice("x", 1)))
		if size.x > 0 and size.y > 0:
			var screen: int = DisplayServer.window_get_current_screen()
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - size) / 2)
	_applied = wanted

## A device.cfg written before `window_mode` existed: `fullscreen = true` meant a borderless
## fullscreen window. `has_window_mode`: the file already holds the new key.
static func migrate(settings: Dictionary, has_window_mode: bool) -> void:
	if not has_window_mode and bool(settings.get("fullscreen", false)): settings.window_mode = "borderless"
	settings.fullscreen = str(settings.get("window_mode", "windowed")) != "windowed"
