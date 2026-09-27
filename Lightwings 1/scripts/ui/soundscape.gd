class_name Soundscape
extends Node
## Quiet, bounded feedback. Every request represents an activation, never a projectile.

const EFFECT_LIMIT: int = 8
const ENEMY_LIMIT: int = 4
const INTERFACE_LIMIT: int = 2
const PICKUP_INTERVAL: float = 0.25
const RATE: int = 22050
## frequency, seconds, filtered-noise blend, gain, ending pitch ratio
const CUES: Dictionary = {
	"pickup": [310.0, 0.085, 0.10, 0.13, 1.02],
	"evolve": [196.0, 0.48, 0.03, 0.42, 1.08],
	"hurt": [105.0, 0.15, 0.40, 0.48, 0.90],
	"clear": [246.94, 0.38, 0.025, 0.32, 1.03],
	"click": [240.0, 0.05, 0.24, 0.32, 0.96],
	"death": [98.0, 0.42, 0.08, 0.38, 0.90],
	"fire": [155.0, 0.095, 0.34, 0.33, 0.92],
	"lightning": [290.0, 0.075, 0.36, 0.29, 0.97],
	"void": [88.0, 0.13, 0.12, 0.35, 0.94],
	"corruption": [180.0, 0.10, 0.32, 0.29, 0.98],
	"plasma": [225.0, 0.10, 0.21, 0.30, 0.96],
	"ability": [130.0, 0.18, 0.23, 0.36, 1.04],
}

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var positional_voices: Array[AudioStreamPlayer2D] = []
var sounds: Dictionary = {}
var enabled: bool = true
var volume: float = 0.7
var music_enabled: bool = true
var effects_volume: float = 0.55
var interface_volume: float = 0.45
var ambience_volume: float = 0.15
var pickup_cues: bool = false
var voice_index: int = 0
var _variants: Dictionary = {}
var _active: Array[Dictionary] = []
var _last_cue: Dictionary = {}
var _shutting_down: bool = false
var _retiring_audio: Array[WeakRef] = []
var _context: String = "menu"
var _ambient_gain: float = 0.0
var _ambient_target: float = 0.0
var _applied_ambient_level: float = -1.0

## Safe before add_child(): legacy volume/music keys remain authoritative.
func configure(settings: Dictionary) -> void:
	if _shutting_down: return
	volume = clampf(float(settings.get("volume", 0.7)), 0.0, 1.0)
	music_enabled = bool(settings.get("music", true))
	effects_volume = clampf(float(settings.get("effects_volume", 0.55)), 0.0, 1.0)
	interface_volume = clampf(float(settings.get("interface_volume", 0.45)), 0.0, 1.0)
	ambience_volume = clampf(float(settings.get("ambience_volume", 0.15)), 0.0, 1.0)
	pickup_cues = bool(settings.get("pickup_cues", false))
	apply_settings()

func _ready() -> void:
	if _shutting_down: return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue: String in CUES:
		var variants: Array[AudioStreamWAV] = []
		for variant: int in range(3): variants.append(make_clip(cue, variant))
		_variants[cue] = variants
		sounds[cue] = variants[0]
	for index: int in range(EFFECT_LIMIT + INTERFACE_LIMIT):
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	for index: int in range(EFFECT_LIMIT):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 1350.0
		player.attenuation = 1.5
		add_child(player)
		positional_voices.append(player)
	music = AudioStreamPlayer.new()
	music.stream = ambient()
	music.volume_linear = 0.0
	add_child(music)
	apply_settings()

func set_context(context: String) -> void:
	_context = context
	_ambient_target = _target_ambient_gain()

func _target_ambient_gain() -> float:
	var context_gain: float = 0.65 if _context == "pause" else (0.85 if _context == "menu" else 1.0)
	return volume * ambience_volume * context_gain if enabled and music_enabled else 0.0

func _process(delta: float) -> void:
	if _shutting_down: return
	_prune()
	if is_instance_valid(music) and music.playing:
		_ambient_gain = move_toward(_ambient_gain, _ambient_target, delta * 0.075)
		music.volume_linear = _ambient_gain

func _now_seconds() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0

func _prune() -> void:
	var now: float = _now_seconds()
	for index: int in range(_active.size() - 1, -1, -1):
		if float(_active[index].until) <= now:
			_active[index].player.stop()
			_active.remove_at(index)

func _gain(category: String, source: String, cue: String) -> float:
	if not enabled: return 0.0
	var category_gain: float = interface_volume if category == "interface" else effects_volume
	var distance_priority: float = 0.42 if source == "enemy" else 1.0
	return volume * category_gain * float(CUES[cue][3]) * distance_priority

func apply_settings() -> void:
	if _shutting_down: return
	for index: int in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[index]
		var gain: float = _gain(str(entry.category), str(entry.source), str(entry.cue))
		if gain <= 0.0 or (entry.cue == "pickup" and not pickup_cues):
			entry.player.stop()
			_active.remove_at(index)
		else:
			entry.player.volume_linear = gain
	var ambient_level: float = volume * ambience_volume if enabled and music_enabled else 0.0
	var mix_changed: bool = not is_equal_approx(ambient_level, _applied_ambient_level)
	_applied_ambient_level = ambient_level
	_ambient_target = _target_ambient_gain()
	if not is_instance_valid(music): return
	if _ambient_target <= 0.0:
		music.stop()
		music.volume_linear = 0.0
		_ambient_gain = 0.0
	else:
		# User mix changes take effect now. Starting playback and menu/play/pause
		# transitions still fade; unrelated settings must not interrupt that fade.
		if music.playing and mix_changed: _ambient_gain = _ambient_target
		elif not music.playing: _ambient_gain = 0.0
		music.volume_linear = _ambient_gain
		if not music.playing: music.play()

func play(cue: String, priority: int = -1, source: String = "player") -> bool:
	return _request(cue, Vector2.ZERO, false, source, priority)

func play_at(cue: String, relative_position: Vector2, source: String = "enemy", priority: int = -1) -> bool:
	return _request(cue if CUES.has(cue) else "ability", relative_position, true, source, priority)

func _request(cue: String, position: Vector2, positional: bool, source: String, priority: int) -> bool:
	if _shutting_down or not enabled or not sounds.has(cue): return false
	if cue == "pickup" and not pickup_cues: return false
	var category: String = "interface" if cue == "click" else "effects"
	var gain: float = _gain(category, source, cue)
	if gain <= 0.0: return false
	if positional and source == "enemy" and position.length() >= 1350.0: return false
	var now: float = _now_seconds()
	var cooldown: float = PICKUP_INTERVAL if cue == "pickup" else (0.12 if cue == "hurt" else (0.075 if source == "enemy" else 0.035))
	var key: String = "pickup" if cue == "pickup" else source + ":" + cue
	if now - float(_last_cue.get(key, -1000.0)) < cooldown: return false
	_prune()
	if priority < 0:
		priority = 100 if cue in ["hurt", "death", "evolve", "clear"] else (10 if source == "enemy" else (5 if cue == "pickup" else 50))
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _active:
		if entry.category == category: candidates.append(entry)
	var limit: int = INTERFACE_LIMIT if category == "interface" else EFFECT_LIMIT
	var enemies: Array[Dictionary] = []
	if source == "enemy":
		for entry: Dictionary in candidates:
			if entry.source == "enemy": enemies.append(entry)
	var constrained: Array[Dictionary] = enemies if enemies.size() >= ENEMY_LIMIT else candidates
	if candidates.size() >= limit or enemies.size() >= ENEMY_LIMIT:
		var victim: Dictionary = {}
		for entry: Dictionary in constrained:
			if int(entry.priority) < priority and (victim.is_empty() or int(entry.priority) < int(victim.priority)):
				victim = entry
		if victim.is_empty(): return false
		victim.player.stop()
		_active.erase(victim)
	var player: Node = _free_player(positional)
	if player == null: return false
	var variant: int = voice_index % 3
	voice_index += 1
	player.stream = _variants[cue][variant]
	player.volume_linear = gain
	if positional: player.position = get_viewport().get_visible_rect().size * 0.5 + position
	player.play()
	_active.append({"player": player, "cue": cue, "source": source, "category": category, "priority": priority, "variant": variant, "started": now, "until": now + float(CUES[cue][1])})
	_last_cue[key] = now
	return true

func _free_player(positional: bool) -> Node:
	var pool: Array = positional_voices if positional else voices
	for player: Node in pool:
		var used: bool = false
		for entry: Dictionary in _active:
			if entry.player == player:
				used = true
				break
		if not used: return player
	return null

## Small diagnostics surface for policy tests and the offline listening reel.
func mix_snapshot() -> Array[Dictionary]:
	_prune()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _active:
		result.append({"cue": entry.cue, "source": entry.source, "category": entry.category, "priority": entry.priority, "variant": entry.variant, "started": entry.started, "until": entry.until, "gain": entry.player.volume_linear})
	return result

func _exit_tree() -> void:
	shutdown()

func audio_retired() -> bool:
	if not _shutting_down: return false
	for reference: WeakRef in _retiring_audio:
		if reference.get_ref() != null: return false
	return true

func shutdown() -> void:
	if _shutting_down: return
	_shutting_down = true
	enabled = false
	music_enabled = false
	for variants: Array in _variants.values():
		for stream: AudioStream in variants: _retiring_audio.append(weakref(stream))
	var players: Array = []
	players.append_array(voices)
	players.append_array(positional_voices)
	if is_instance_valid(music): players.append(music)
	for player: Node in players:
		if not is_instance_valid(player): continue
		if player.stream != null: _retiring_audio.append(weakref(player.stream))
		if player.has_stream_playback(): _retiring_audio.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	_active.clear()
	_last_cue.clear()
	_variants.clear()
	sounds.clear()

static func make_clip(cue: String, variant: int = 0) -> AudioStreamWAV:
	var profile: Array = CUES.get(cue, CUES.ability)
	var frequency: float = float(profile[0]) * [0.975, 1.0, 1.025][variant % 3]
	var duration: float = float(profile[1])
	var count: int = int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	var noise: float = 0.0
	var random := RandomNumberGenerator.new()
	random.seed = absi(cue.hash()) + variant * 173
	for index: int in range(count):
		var seconds: float = float(index) / RATE
		var t: float = float(index) / maxf(1.0, count - 1.0)
		phase += TAU * frequency * lerpf(1.0, float(profile[4]), t) / RATE
		noise = lerpf(noise, random.randf_range(-1.0, 1.0), 0.15)
		var envelope: float = smoothstep(0.0, 0.012, seconds) * pow(1.0 - t, 1.6) * smoothstep(0.0, 0.018, duration - seconds)
		var body: float = sin(phase) * 0.78 + sin(phase * 1.5) * 0.09
		if cue in ["evolve", "clear"]: body += sin(phase * 1.25) * 0.13
		var sample: float = lerpf(body, noise * 2.0, float(profile[2])) * envelope * 0.68
		bytes.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(bytes)

static func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

static func ambient() -> AudioStreamWAV:
	# Two quiet, rounded swells with long silent gaps; a seamless 24-second loop.
	const DURATION: int = 24
	var bytes := PackedByteArray()
	bytes.resize(RATE * DURATION * 2)
	for index: int in range(RATE * DURATION):
		var seconds: float = float(index) / RATE
		var envelope: float = 0.0
		for swell: Vector2 in [Vector2(3.0, 5.0), Vector2(15.0, 6.0)]:
			var t: float = (seconds - swell.x) / swell.y
			if t > 0.0 and t < 1.0: envelope += pow(sin(PI * t), 2.0)
		var sample: float = (sin(seconds * TAU * 82.0) * 0.10 + sin(seconds * TAU * 123.0) * 0.045) * envelope
		bytes.encode_s16(index * 2, int(sample * 32767.0))
	var stream: AudioStreamWAV = _wav(bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = RATE * DURATION
	return stream
