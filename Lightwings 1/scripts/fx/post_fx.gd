class_name PostFx
extends CanvasLayer
## Modernization M16: the ONE full-screen post pass (shaders/post_fx.gdshader) on CanvasLayer 5 -
## above the world and its glow (main.gd's environment glows layers <= 0), below the UI on 10.
## FeelDirector is the only caller in the game; this node owns the envelopes and the one rule
## every flash obeys:
##
## `request_flash()` is the single choke point for full-screen flashes (WCAG 2.3.1): at most
## `MAX_ONSETS_PER_SECOND` onsets in any rolling second, and a luminance delta of at most
## `MAX_FLASH_DELTA` x the player's flash setting. Nothing else writes the shader's `flash`.
##
## Envelopes run on this node's own presentation clock (`step`), never the sim's: post-processing
## moves no geometry, and the sim must not see it (the golden trace is identical with or without it).

const SHADER: Shader = preload("res://shaders/post_fx.gdshader")
const LAYER: int = 5
const MAX_ONSETS_PER_SECOND: int = 3
const MAX_FLASH_DELTA: float = 0.25
const FLASH_DECAY_SECONDS: float = 0.10
const HURT_SECONDS: float = 0.12
const MAX_ABERRATION_PX: float = 3.0
const VIGNETTE_DEFAULT: float = 0.16
const LOW_LIGHT_DESATURATION: float = 0.55
## Heartbeat rate of the low-light coral pulse (~72 bpm).
const HEARTBEAT_HZ: float = 1.2

## Settings (FeelDirector copies them in from the app's settings each frame).
var flash_setting: float = 1.0
var reduced_motion: bool = false
var vignette_strength: float = VIGNETTE_DEFAULT
var scanlines: bool = false
## Test seams: each limit can be switched off alone, so each has its own negative control.
var limit_rate: bool = true
var limit_luminance: bool = true

var rect: ColorRect
var material: ShaderMaterial
var flash_level: float = 0.0
var hurt_level: float = 0.0
var low_light: bool = false
var onset_count: int = 0
var rejected_count: int = 0
var _clock: float = 0.0
var _onsets: Array[float] = []
var _hurt_remaining: float = 0.0
var _hurt_peak: float = 0.0
var _low_light_mix: float = 0.0
## M12: world desaturation a screen asks for (ScreenRouter's `desaturate`, the evolution cards),
## eased toward over FOCUS_FADE_SECONDS; the stronger of it and the low-light state wins.
const FOCUS_FADE_SECONDS: float = 0.15
var focus_desaturation: float = 0.0
var _focus_mix: float = 0.0

func _init() -> void:
	layer = LAYER
	name = "PostFx"
	process_mode = Node.PROCESS_MODE_ALWAYS
	material = ShaderMaterial.new()
	material.shader = SHADER
	rect = ColorRect.new()
	rect.name = "PostPass"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	add_child(rect)
	_apply()

func _process(delta: float) -> void:
	step(delta)

## Advances every envelope by `dt` seconds and pushes the uniforms (tests drive this directly).
func step(dt: float) -> void:
	_clock += dt
	flash_level = move_toward(flash_level, 0.0, dt * MAX_FLASH_DELTA / FLASH_DECAY_SECONDS)
	_hurt_remaining = maxf(0.0, _hurt_remaining - dt)
	hurt_level = _hurt_peak * (_hurt_remaining / HURT_SECONDS)
	_low_light_mix = move_toward(_low_light_mix, 1.0 if low_light else 0.0, dt / 0.4)
	_focus_mix = move_toward(_focus_mix, focus_desaturation, dt / FOCUS_FADE_SECONDS)
	_apply()

## Returns true when the request became a flash onset. `strength` is the requested luminance
## delta (0..1 of full white); it is clamped to MAX_FLASH_DELTA x flash_setting. `center` (screen
## UV, M16b big kills) makes it radial: full strength there, falling to RADIAL_FLOOR of it far
## away (30 %, in the shader), so the cap still bounds the brightest pixel. Outside 0..1 (the default) it is uniform.
func request_flash(strength: float, center: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	var level: float = strength
	if limit_luminance:
		level = minf(strength, MAX_FLASH_DELTA * clampf(flash_setting, 0.0, 1.0))
	if level <= 0.001:
		return false
	while not _onsets.is_empty() and _clock - _onsets[0] >= 1.0:
		_onsets.pop_front()
	if limit_rate and _onsets.size() >= MAX_ONSETS_PER_SECOND:
		rejected_count += 1
		return false
	_onsets.append(_clock)
	onset_count += 1
	flash_level = maxf(flash_level, level)
	var radial: bool = Rect2(0.0, 0.0, 1.0, 1.0).has_point(center)
	material.set_shader_parameter("flash_radial", 1.0 if radial else 0.0)
	if radial: material.set_shader_parameter("flash_center", center)
	_apply()
	return true

## Hurt tint plus radial chromatic aberration for HURT_SECONDS. `strength` 0..1.
func hurt(strength: float = 1.0) -> void:
	_hurt_peak = maxf(clampf(strength, 0.0, 1.0), hurt_level)
	_hurt_remaining = HURT_SECONDS
	hurt_level = _hurt_peak
	_apply()

func set_low_light(on: bool) -> void:
	low_light = on

func _apply() -> void:
	if material == null: return
	var aberration: float = 0.0 if reduced_motion else MAX_ABERRATION_PX * hurt_level
	var pulse: float = 1.0 if reduced_motion else 0.55 + 0.45 * pow(absf(sin(PI * HEARTBEAT_HZ * _clock)), 6.0)
	material.set_shader_parameter("vignette_strength", vignette_strength)
	material.set_shader_parameter("aberration_px", minf(aberration, MAX_ABERRATION_PX))
	material.set_shader_parameter("hurt", hurt_level)
	material.set_shader_parameter("flash", flash_level)
	material.set_shader_parameter("desaturation", maxf(LOW_LIGHT_DESATURATION * _low_light_mix, _focus_mix))
	material.set_shader_parameter("low_light_edge", 0.5 * _low_light_mix * pulse)
	material.set_shader_parameter("scanlines", 1.0 if scanlines else 0.0)
	# A pass with nothing to do is skipped entirely.
	rect.visible = vignette_strength > 0.0 or flash_level > 0.0 or hurt_level > 0.0 or _low_light_mix > 0.0 or _focus_mix > 0.0 or scanlines
