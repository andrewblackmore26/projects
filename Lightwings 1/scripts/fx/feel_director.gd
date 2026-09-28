class_name FeelDirector
extends Node
## Modernization M16: the ONE mapping from `CombatWorld.feel_event` to presentation - post (PostFx),
## rumble (Rumble), world FX (CombatFX templates), audio cues (Soundscape.play_cue), big-kill
## slow motion and the boss intro card (M16b) - every channel scaled by the player's settings:
##   `flash_intensity` 0..1 (flashes; PostFx also caps the luminance delta at 0.25 x this),
##   `rumble` 0..1 (0 sends nothing), `reduced_motion` (no aberration, no heartbeat pulse, and the
##   boss card only fades).
## Camera shake and hitstop are NOT here: the camera rig and the hitstop broker own them (M10) and
## read the same signal.
##
## It is also the ONE gameplay caller of Soundscape.play_cue (M17 wiring): main.gd no longer plays
## `hurt`, `pickup` or `evolve` itself, so every hit is exactly one hurt cue.
##
## Presentation only. It holds no sim state and draws FX with its own RNG. The one thing it asks of
## the sim is a time-scale request (big kills), released on its timer, on a sector change, on death
## and when it lets go of the world, so it can never leak.

const FX = preload("res://scripts/combat/combat_fx.gd")

## kind -> channels. `flash`: requested luminance delta (PostFx caps it); `radial` centres it on the
## event. `hurt`: hurt tint + aberration strength (player only). `rumble`: [weak, strong, seconds].
## `fx`: a CombatFX template drawn at the event. `low_light`: enters/leaves the low-light post and
## audio state. `cue`: the Soundscape cue it plays; `positional` plays it where it happened;
## `stop_cue` cuts a sounding cue (the warp strain, when the press ends or snaps).
## `slow_mo`: [time scale, real seconds]. Magnitude (0..1, <= 0 read as 1) scales flash, hurt and
## rumble. Kinds with no cue on purpose: enemy_kill (every kill already sounds its combo_step),
## the low-light pair (the heartbeat loop is the sound), warp_strain is bent, not restarted.
const MAP: Dictionary = {
	&"player_hit": {"hurt": 1.0, "rumble": [0.35, 0.6, 0.12], "cue": "hurt"},
	&"regression": {"hurt": 1.0, "flash": 0.18, "rumble": [0.6, 0.9, 0.25], "cue": "boss_phase"},
	&"enemy_kill": {"rumble": [0.12, 0.0, 0.06]},
	&"elite_limb": {"rumble": [0.25, 0.2, 0.10], "cue": "warp_arrive", "positional": true},
	&"elite_kill": {"flash": 0.10, "radial": true, "rumble": [0.35, 0.45, 0.18], "cue": "death", "positional": true, "slow_mo": [0.35, 0.35]},
	&"boss_engage": {"rumble": [0.2, 0.35, 0.30], "cue": "boss_engage"},
	&"boss_phase": {"flash": 0.15, "rumble": [0.4, 0.6, 0.25], "cue": "boss_phase"},
	&"boss_kill": {"flash": 0.25, "radial": true, "rumble": [0.8, 1.0, 0.50], "cue": "boss_death", "slow_mo": [0.25, 0.8]},
	&"dash": {"rumble": [0.15, 0.0, 0.06], "cue": "dash"},
	&"warp_strain": {"rumble": [0.1, 0.2, 0.10], "cue": "warp_strain"},
	&"warp_release": {"stop_cue": "warp_strain"},
	&"warp_snap": {"flash": 0.12, "rumble": [0.4, 0.5, 0.12], "cue": "warp_snap", "stop_cue": "warp_strain"},
	&"warp_rush": {"rumble": [0.2, 0.3, 0.20], "cue": "warp_rush"},
	&"warp_arrive": {"rumble": [0.2, 0.1, 0.10], "cue": "warp_arrive"},
	&"pickup_collect": {"fx": "pickup_collect", "cue": "pickup"},
	&"combo_step": {"cue": "combo_step"},
	&"combo_break": {"cue": "combo_break"},
	&"evolved": {"flash": 0.20, "radial": true, "rumble": [0.3, 0.3, 0.30], "cue": "evolve_assemble"},
	&"low_light_enter": {"low_light": true},
	&"low_light_exit": {"low_light": false},
}
## Combo counts that sound `combo_tier` instead of the next `combo_step` (half and full multiplier).
const COMBO_TIERS: Array[int] = [5, 10]
const SLOW_MO_REASON: StringName = &"big_kill"
## The last part of a slow-motion eases back to full speed instead of snapping.
const SLOW_MO_EASE_FRACTION: float = 0.4
const EVOLVE_READY_CUE: String = "evolve_ready"

## The owner (main.gd): read, never written, for `settings`, `combat`, `sound` and `campaign`
## (whose story_flags remember which boss cards were shown).
var app: Node
var post: PostFx
var rumble: Rumble
var boss_intro: BossIntro
var event_counts: Dictionary = {}
## Real seconds of big-kill slow motion left (0: none requested).
var slow_mo_remaining: float = 0.0
## Test seams, each with its own negative control: the timer's release, and the once-per-boss rule.
var slow_mo_release_enabled: bool = true
var boss_intro_once: bool = true
var _slow_mo_seconds: float = 0.0
var _slow_mo_scale: float = 1.0
var _slow_mo_sector: Dictionary = {}
var _intro_sector: Dictionary = {}
var _evolve_ready: bool = false
var _intros_seen: Dictionary = {}
var _combat: CombatWorld
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(owner_app: Node = null, rumble_backend: Callable = Callable()) -> void:
	app = owner_app
	name = "FeelDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	rumble = Rumble.new(rumble_backend)
	post = PostFx.new()
	add_child(post)
	boss_intro = BossIntro.new()
	add_child(boss_intro)
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
	step(delta)

func _exit_tree() -> void:
	release_slow_mo()

func configure(settings: Variant) -> void:
	if not settings is Dictionary: return
	post.flash_setting = clampf(float(settings.get("flash_intensity", 1.0)), 0.0, 1.0)
	post.reduced_motion = bool(settings.get("reduced_motion", false))
	post.scanlines = bool(settings.get("scanlines", false))
	boss_intro.reduced_motion = post.reduced_motion
	rumble.scale = clampf(float(settings.get("rumble", 1.0)), 0.0, 1.0)

## Follows the app's current CombatWorld (a new one per play session); idempotent.
func bind(world: CombatWorld) -> void:
	if world == _combat: return
	release_slow_mo()
	boss_intro.dismiss()
	if is_instance_valid(_combat):
		if _combat.feel_event.is_connected(on_feel_event): _combat.feel_event.disconnect(on_feel_event)
		if _combat.player_died.is_connected(_on_player_died): _combat.player_died.disconnect(_on_player_died)
	_combat = world
	if is_instance_valid(_combat):
		_combat.feel_event.connect(on_feel_event)
		_combat.player_died.connect(_on_player_died)
	_leave_low_light()
	_evolve_ready = _evolution_ready()

## Real-time upkeep (tests drive it directly): the slow-motion timer and the evolution-ready edge.
func step(dt: float) -> void:
	if boss_intro.active() and (not is_instance_valid(_combat) or not is_same(_combat.sector, _intro_sector)): boss_intro.dismiss()
	if slow_mo_remaining > 0.0:
		slow_mo_remaining = maxf(0.0, slow_mo_remaining - dt)
		if not is_instance_valid(_combat) or not is_same(_combat.sector, _slow_mo_sector): release_slow_mo()
		elif slow_mo_remaining <= 0.0:
			if slow_mo_release_enabled: release_slow_mo()
		else:
			var left: float = slow_mo_remaining / maxf(0.001, _slow_mo_seconds)
			var back: float = 1.0 - clampf(left / SLOW_MO_EASE_FRACTION, 0.0, 1.0)
			_combat.request_time_scale(SLOW_MO_REASON, lerpf(_slow_mo_scale, 1.0, back * back))
	var ready: bool = _evolution_ready()
	if ready and not _evolve_ready: _sound_call("play_cue", [EVOLVE_READY_CUE, {}])
	_evolve_ready = ready

func on_feel_event(kind: StringName, at: Vector2, magnitude: float, actor_id: int) -> void:
	var entry: Dictionary = MAP.get(kind, {})
	if entry.is_empty(): return
	event_counts[kind] = int(event_counts.get(kind, 0)) + 1
	var scale: float = 1.0 if magnitude <= 0.0 else clampf(magnitude, 0.0, 1.0)
	if entry.has("flash"):
		post.request_flash(float(entry.flash) * scale, _screen_uv(at) if bool(entry.get("radial", false)) else Vector2(-1.0, -1.0))
	if entry.has("hurt") and actor_id == 0: post.hurt(float(entry.hurt) * scale)
	if entry.has("rumble"):
		var r: Array = entry.rumble
		rumble.pulse(float(r[0]) * scale, float(r[1]) * scale, float(r[2]))
	if entry.has("low_light"):
		post.set_low_light(bool(entry.low_light))
		_sound_call("set_low_light", [bool(entry.low_light)])
	if entry.has("fx") and is_instance_valid(_combat):
		_combat.fx.emit(str(entry.fx), at, CombatWorld.PLAYER_COLOR, _fx_rng)
	if entry.has("slow_mo"): _begin_slow_mo(float(entry.slow_mo[0]), float(entry.slow_mo[1]))
	if entry.has("stop_cue"): _sound_call("stop_cue", [str(entry.stop_cue)])
	if kind == &"boss_engage" and not _present_boss_intro(actor_id): return
	if entry.has("cue"): _play(kind, str(entry.cue), at, magnitude, bool(entry.get("positional", false)))

## The cue a kind plays and its parameters: combo_step climbs a semitone per step and becomes
## combo_tier at a tier count; warp_strain bends with the push depth.
func _play(kind: StringName, cue: String, at: Vector2, magnitude: float, positional: bool) -> void:
	var params: Dictionary = {}
	if kind == &"combo_step":
		if roundi(magnitude) in COMBO_TIERS: cue = "combo_tier"
		else: params["step"] = maxi(0, roundi(magnitude) - 1)
	elif kind == &"warp_strain":
		params["strain"] = clampf(magnitude, 0.0, 1.0)
	if positional and is_instance_valid(_combat): params["position"] = at - _combat.player_position
	_sound_call("play_cue", [cue, params])

## Every kind in `kinds` that has no row here (the feel_director_test's source scan feeds it every
## kind the sim emits, so a new emit site cannot go silent unnoticed).
static func unmapped(kinds: Array) -> Array:
	var result: Array = []
	for kind: Variant in kinds:
		if not MAP.has(StringName(str(kind))): result.append(kind)
	return result

## The cue `kind` plays ("" for none), before the combo-tier and parameter rules.
static func cue_for(kind: StringName) -> String:
	return str(MAP.get(kind, {}).get("cue", ""))

## Big-kill slow motion: the lowest scale and the longest time win when two overlap.
func _begin_slow_mo(scale: float, seconds: float) -> void:
	if not is_instance_valid(_combat): return
	if slow_mo_remaining > 0.0:
		scale = minf(scale, _slow_mo_scale)
		seconds = maxf(seconds, slow_mo_remaining)
	_slow_mo_scale = scale
	_slow_mo_seconds = seconds
	slow_mo_remaining = seconds
	_slow_mo_sector = _combat.sector
	_combat.request_time_scale(SLOW_MO_REASON, scale)

func release_slow_mo() -> void:
	slow_mo_remaining = 0.0
	if is_instance_valid(_combat): _combat.release_time_scale(SLOW_MO_REASON)

func _on_player_died() -> void:
	release_slow_mo()
	boss_intro.dismiss()
	_leave_low_light()

func _leave_low_light() -> void:
	if post.low_light: _sound_call("set_low_light", [false])
	post.set_low_light(false)

## The boss card, once per rival per campaign (CampaignState.story_flags, saved with the run).
## Returns false when this rival's card was already shown, so the stinger does not repeat either.
func _present_boss_intro(actor_id: int) -> bool:
	if not is_instance_valid(_combat): return false
	var actor: Dictionary = _combat.actors_by_id.get(actor_id, {})
	var element: String = str(actor.get("element", _combat.sector.get("element", "")))
	var campaign: Object = app.get("campaign") if app != null else null
	var level: int = int(campaign.get("level")) if campaign != null else 1
	var key: String = "boss_intro_L%d_%s" % [level, element]
	var flags: Dictionary = campaign.get("story_flags") if campaign != null else _intros_seen
	if boss_intro_once and bool(flags.get(key, false)): return false
	flags[key] = true
	var title: String = str(DialogueDirector.RIVAL_NAMES.get(element, "RIVAL"))
	var color: Color = VisualStyle.PALETTE.get(element, VisualStyle.ACCENT)
	boss_intro.present(title, "RIVAL SIGNAL", "%s DIALECT  ·  LEVEL %d" % [element.to_upper(), level], color)
	_intro_sector = _combat.sector
	return true

func _evolution_ready() -> bool:
	if not is_instance_valid(_combat): return false
	return _combat.player_tier < _combat.max_player_tier and _combat.light_total >= EvolutionRules.threshold(_combat.player_tier)

## A world position as screen UV (0..1), through the world's canvas transform (camera and shake).
func _screen_uv(at: Vector2) -> Vector2:
	if not is_instance_valid(_combat) or not _combat.is_inside_tree(): return Vector2(0.5, 0.5)
	var size: Vector2 = _combat.get_viewport().get_visible_rect().size
	var uv: Vector2 = (_combat.get_global_transform_with_canvas() * at) / Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	return uv.clamp(Vector2.ZERO, Vector2.ONE)

func _sound_call(method: String, arguments: Array) -> void:
	var sound: Object = app.get("sound") if app != null else null
	if sound != null and sound.has_method(method): sound.callv(method, arguments)
