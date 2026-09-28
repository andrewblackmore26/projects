class_name Rumble
extends RefCounted
## Modernization M16: controller vibration behind one injectable backend. FeelDirector is the only
## caller; `pulse()` is the one place the rumble setting scales (and, at 0, silences) every call.
##
## The default backend vibrates every connected joypad through `Input.start_joy_vibration`. When no
## joypad is visible to Godot but Steam Input owns the controller (GodotSteam present and
## SteamInputService active), it falls back to `Steam.triggerVibration`, which has no duration, so
## `step()` sends the matching stop. A test passes its own Callable to record the calls instead.

## (weak: float, strong: float, seconds: float) -> void, weak/strong already scaled to 0..1.
var backend: Callable
## The player's rumble setting, 0..1.
var scale: float = 1.0
var call_count: int = 0
## Optional: a SteamInputService (scripts/platform/steam_input_service.gd) for the fallback.
var steam_input: RefCounted
var _steam_stop_in: float = -1.0

func _init(custom_backend: Callable = Callable()) -> void:
	backend = custom_backend if custom_backend.is_valid() else _default_backend

## Returns true when a vibration was sent.
func pulse(weak: float, strong: float, seconds: float) -> bool:
	var amount: float = clampf(scale, 0.0, 1.0)
	var w: float = clampf(weak, 0.0, 1.0) * amount
	var s: float = clampf(strong, 0.0, 1.0) * amount
	if seconds <= 0.0 or (w <= 0.001 and s <= 0.001):
		return false
	call_count += 1
	backend.call(w, s, seconds)
	return true

func step(dt: float) -> void:
	if _steam_stop_in < 0.0: return
	_steam_stop_in -= dt
	if _steam_stop_in <= 0.0:
		_steam_stop_in = -1.0
		_steam_vibrate(0.0, 0.0)

func _default_backend(weak: float, strong: float, seconds: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	for device: int in pads:
		Input.start_joy_vibration(device, weak, strong, seconds)
	if pads.is_empty() and _steam_vibrate(weak, strong):
		_steam_stop_in = seconds

func _steam_vibrate(weak: float, strong: float) -> bool:
	if steam_input == null or not bool(steam_input.get("active")): return false
	var steam: Object = steam_input.get("steam")
	var controller: int = int(steam_input.get("controller"))
	if steam == null or controller == 0 or not steam.has_method("triggerVibration"): return false
	steam.call("triggerVibration", controller, int(strong * 65535.0), int(weak * 65535.0))
	return true
