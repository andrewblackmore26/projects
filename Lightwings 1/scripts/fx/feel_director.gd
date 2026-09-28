class_name FeelDirector
extends Node
## Modernization M16: the ONE mapping from `CombatWorld.feel_event` to presentation - post (PostFx),
## rumble (Rumble), world FX (CombatFX templates) and audio cues (Soundscape.play_cue, when it
## exists) - every channel scaled by the player's settings:
##   `flash_intensity` 0..1 (flashes; PostFx also caps the luminance delta at 0.25 x this),
##   `rumble` 0..1 (0 sends nothing), `reduced_motion` (no aberration, no heartbeat pulse).
## Camera shake and hitstop are NOT here: the camera rig and the hitstop broker own them (M10) and
## read the same signal.
##
## Presentation only. It holds no sim state, draws FX with its own RNG, and the golden trace is
## identical with it attached.

const FX = preload("res://scripts/combat/combat_fx.gd")

## kind -> channels. `flash`: requested luminance delta (PostFx caps it). `hurt`: hurt tint +
## aberration strength (player only). `rumble`: [weak, strong, seconds]. `fx`: a CombatFX template
## drawn at the event. `low_light`: enters/leaves the low-light post state. `audio`: send the kind to
## Soundscape.play_cue. Magnitude (0..1, <= 0 read as 1) scales flash, hurt and rumble.
const MAP: Dictionary = {
	&"player_hit": {"hurt": 1.0, "rumble": [0.35, 0.6, 0.12], "audio": true},
	&"regression": {"hurt": 1.0, "flash": 0.18, "rumble": [0.6, 0.9, 0.25], "audio": true},
	&"enemy_kill": {"rumble": [0.12, 0.0, 0.06]},
	&"elite_limb": {"rumble": [0.25, 0.2, 0.10], "audio": true},
	&"elite_kill": {"flash": 0.10, "rumble": [0.35, 0.45, 0.18], "audio": true},
	&"boss_engage": {"rumble": [0.2, 0.35, 0.30], "audio": true},
	&"boss_phase": {"flash": 0.15, "rumble": [0.4, 0.6, 0.25], "audio": true},
	&"boss_kill": {"flash": 0.25, "rumble": [0.8, 1.0, 0.50], "audio": true},
	&"dash": {"rumble": [0.15, 0.0, 0.06]},
	&"warp_strain": {"rumble": [0.1, 0.2, 0.10]},
	&"warp_snap": {"flash": 0.12, "rumble": [0.4, 0.5, 0.12], "audio": true},
	&"warp_rush": {"rumble": [0.2, 0.3, 0.20], "audio": true},
	&"warp_arrive": {"rumble": [0.2, 0.1, 0.10], "audio": true},
	&"pickup_collect": {"fx": "pickup_collect"},
	&"combo_step": {"audio": true},
	&"combo_break": {"audio": true},
	&"evolved": {"flash": 0.20, "rumble": [0.3, 0.3, 0.30], "audio": true},
	&"low_light_enter": {"low_light": true, "audio": true},
	&"low_light_exit": {"low_light": false, "audio": true},
}

## The owner (main.gd): read, never written, for `settings`, `combat` and `sound`.
var app: Node
var post: PostFx
var rumble: Rumble
var event_counts: Dictionary = {}
var _combat: CombatWorld
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(owner_app: Node = null, rumble_backend: Callable = Callable()) -> void:
	app = owner_app
	name = "FeelDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	rumble = Rumble.new(rumble_backend)
	post = PostFx.new()
	add_child(post)
	_fx_rng.randomize()

func _ready() -> void:
	var platform: Object = app.get("platform") if app != null else null
	if platform != null: rumble.steam_input = platform.get("steam_input")

func _process(delta: float) -> void:
	if app == null: return
	configure(app.get("settings"))
	var world: Variant = app.get("combat")
	bind(world as CombatWorld if is_instance_valid(world) else null)
	rumble.step(delta)

func configure(settings: Variant) -> void:
	if not settings is Dictionary: return
	post.flash_setting = clampf(float(settings.get("flash_intensity", 1.0)), 0.0, 1.0)
	post.reduced_motion = bool(settings.get("reduced_motion", false))
	post.scanlines = bool(settings.get("scanlines", false))
	rumble.scale = clampf(float(settings.get("rumble", 1.0)), 0.0, 1.0)

## Follows the app's current CombatWorld (a new one per sector); idempotent.
func bind(world: CombatWorld) -> void:
	if world == _combat: return
	if is_instance_valid(_combat) and _combat.feel_event.is_connected(on_feel_event):
		_combat.feel_event.disconnect(on_feel_event)
	_combat = world
	if is_instance_valid(_combat): _combat.feel_event.connect(on_feel_event)
	post.set_low_light(false)

func on_feel_event(kind: StringName, at: Vector2, magnitude: float, actor_id: int) -> void:
	var entry: Dictionary = MAP.get(kind, {})
	if entry.is_empty(): return
	event_counts[kind] = int(event_counts.get(kind, 0)) + 1
	var scale: float = 1.0 if magnitude <= 0.0 else clampf(magnitude, 0.0, 1.0)
	if entry.has("flash"): post.request_flash(float(entry.flash) * scale)
	if entry.has("hurt") and actor_id == 0: post.hurt(float(entry.hurt) * scale)
	if entry.has("rumble"):
		var r: Array = entry.rumble
		rumble.pulse(float(r[0]) * scale, float(r[1]) * scale, float(r[2]))
	if entry.has("low_light"):
		post.set_low_light(bool(entry.low_light))
		_sound_call("set_low_light", [bool(entry.low_light)])
	if entry.has("fx") and is_instance_valid(_combat):
		_combat.fx.emit(str(entry.fx), at, CombatWorld.PLAYER_COLOR, _fx_rng)
	if bool(entry.get("audio", false)):
		_sound_call("play_cue", [String(kind), {"at": at, "magnitude": scale, "actor_id": actor_id}])

func _sound_call(method: String, arguments: Array) -> void:
	var sound: Object = app.get("sound") if app != null else null
	if sound != null and sound.has_method(method): sound.callv(method, arguments)
