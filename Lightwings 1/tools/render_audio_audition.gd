extends SceneTree
## Offline mono listening reel using the actual samples, defaults and voice policy.
## It omits spatial attenuation and the master chain (compressor, limiter, ducking, low-pass are
## not emulated except where a file says so); enemy levels therefore represent the near-field maximum.
## `-- --stems` first renders the four procedural music stems into assets/audio/music/.

class OfflineSound extends Soundscape:
	var seconds: float = 0.0
	func _now_seconds() -> float: return seconds

var failures: int = 0
var report: Array[Dictionary] = []
const OUTPUT: String = "res://artifacts/audio-review"
const RATE: int = Soundscape.RATE
const DUCK_THRESHOLD_DB: float = -30.0
const DUCK_RATIO: float = 2.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--stems" in OS.get_cmdline_user_args(): _render_stems()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_render("00-isolated-fire", 0.6, [{"at":0.1,"cue":"fire"}])
	var ui_events: Array[Dictionary] = []
	var at: float = 0.4
	for cue: String in ["ui_move", "ui_move", "ui_move", "ui_confirm", "ui_back", "ui_error", "ui_slider_tick", "ui_slider_tick", "ui_slider_tick", "ui_slider_tick"]:
		ui_events.append({"at":at,"cue":cue})
		at += 0.35
	_render("01-interface", at + 0.6, ui_events)
	var fight: Array[Dictionary] = []
	for tick: int in range(40):
		at = 0.5 + tick * 0.14
		fight.append({"at":at,"cue":["fire","lightning","void","corruption","plasma"][tick % 5],"source":"player"})
		for enemy: int in range(7):
			fight.append({"at":at,"cue":["fire","lightning","void","corruption","plasma"][enemy % 5],"source":"enemy"})
		for pickup: int in range(8): fight.append({"at":at,"cue":"pickup"})
		if tick in [12, 25]: fight.append({"at":at,"cue":"hurt"})
	fight.append({"at":6.4,"cue":"clear"})
	_render("02-dense-combat-default-mix", 8.0, fight, false, true)
	var collecting: Array[Dictionary] = []
	for tick: int in range(100): collecting.append({"at":0.5 + tick * 0.025,"cue":"pickup"})
	_render("03-optional-pickups", 4.0, collecting, true)
	_render("05-default-pickups-silent", 4.0, collecting)
	var catalogue: Array[Dictionary] = []
	at = 0.3
	for cue: String in ["dash", "dash_ready", "warp_snap", "warp_rush", "warp_arrive", "combo_tier", "combo_break", "boss_engage", "boss_phase", "boss_death", "evolve_ready", "evolve_pick", "evolve_assemble", "death", "reboot", "level_complete", "hurt", "ability"]:
		catalogue.append({"at":at,"cue":cue})
		at += 1.6 if cue.begins_with("boss") else 1.0
	_render("07-cue-catalogue", at + 1.0, catalogue)
	var warp: Array[Dictionary] = []
	for step: int in range(6): warp.append({"at":0.3 + step * 0.1,"cue":"warp_strain","params":{"strain":step / 5.0}})
	warp.append_array([{"at":1.4,"cue":"warp_snap"},{"at":1.5,"cue":"warp_rush"},{"at":2.3,"cue":"warp_arrive"}])
	_render("08-warp-sequence", 3.5, warp)
	var combo: Array[Dictionary] = []
	for step: int in range(10): combo.append({"at":0.3 + step * 0.22,"cue":"combo_step","params":{"step":step}})
	combo.append_array([{"at":2.6,"cue":"combo_tier"},{"at":3.8,"cue":"combo_break"}])
	_render("09-combo", 4.8, combo)
	_render_low_light()
	_render_music("06-music-intensity-default-mix", 0.15)
	_render_music("06b-music-intensity-ambience-100", 1.0)
	var manifest: FileAccess = FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"note":"Offline mono at actual default gains, 44.1 kHz; no normalization, spatial attenuation, master compressor/limiter or OS output processing. No automatic claim of listening approval.", "files":report}, "\t"))
	else: failures += 1
	await process_frame
	await create_timer(0.1).timeout
	print("AUDIO AUDITION: ", report.size(), " files, ", failures, " failures")
	quit(1 if failures else 0)

func _render(name: String, duration: float, events: Array[Dictionary], pickups: bool = false, measure_duck: bool = false) -> void:
	var sound := OfflineSound.new()
	sound.configure({"music":false,"pickup_cues":pickups})
	root.add_child(sound)
	sound.set_process(false)
	var records: Dictionary = {}
	var accepted: int = 0
	for event: Dictionary in events:
		sound.seconds = float(event.at)
		var params: Dictionary = event.get("params", {}).duplicate()
		if event.has("source"):
			params.source = event.source
			params.position = Vector2.ZERO
		var ok: bool = sound.play_cue(str(event.cue), params)
		var active: Dictionary = {}
		for entry: Dictionary in sound.mix_snapshot():
			var key: String = "%s:%s:%.6f" % [entry.cue, entry.source, entry.started]
			active[key] = true
			if not records.has(key):
				records[key] = entry.duplicate()
				records[key].stream = sound.stream_for(str(entry.cue), int(entry.variant))
		for key: String in records:
			if not active.has(key) and float(records[key].until) > sound.seconds: records[key].until = sound.seconds
		if ok: accepted += 1
	var samples := PackedFloat32Array()
	samples.resize(int(duration * RATE))
	for entry: Dictionary in records.values():
		var clip: PackedFloat32Array = Soundscape.render_stream(entry.stream, float(entry.pitch))
		var start: int = int(float(entry.started) * RATE)
		var length: int = mini(clip.size(), int((float(entry.until) - float(entry.started)) * RATE))
		for index: int in range(length):
			if start + index < samples.size(): samples[start + index] += clip[index] * float(entry.gain)
	var metadata: Dictionary = {"requested":events.size(),"accepted":accepted,"pickup_cues":pickups}
	if measure_duck: metadata.estimated_music_duck_db = _estimated_duck(samples)
	_write(name, samples, metadata)
	sound.shutdown()
	sound.queue_free()

## Median gain reduction the Music bus's sidechain compressor would apply over 50 ms windows where
## SFX sound, from its own threshold and ratio. A hypothesis: the engine's detector is not emulated.
func _estimated_duck(samples: PackedFloat32Array) -> float:
	var reductions: Array[float] = []
	var window: int = RATE / 20
	for start: int in range(0, samples.size() - window, window):
		var peak: float = 0.0
		for index: int in range(start, start + window): peak = maxf(peak, absf(samples[index]))
		if peak > 0.001: reductions.append(maxf(0.0, linear_to_db(peak) - DUCK_THRESHOLD_DB) * (1.0 - 1.0 / DUCK_RATIO))
	reductions.sort()
	return reductions[reductions.size() / 2] if not reductions.is_empty() else 0.0

## Heartbeat and effects through a one-pole 900 Hz low-pass, as the SFX bus sounds in low light.
func _render_low_light() -> void:
	var beat: PackedFloat32Array = Soundscape.render_stream(Soundscape.heartbeat_loop())
	var samples := PackedFloat32Array()
	samples.resize(RATE * 5)
	var gain: float = 0.7 * 0.55
	for index: int in range(samples.size()): samples[index] = beat[index % beat.size()] * 0.5 * gain
	var fire: PackedFloat32Array = Soundscape.render_stream(Soundscape.make_clip("fire", 1))
	for hit: int in range(4):
		var start: int = int((0.6 + hit * 1.1) * RATE)
		for index: int in range(fire.size()): samples[start + index] += fire[index] * 0.30 * gain
	var alpha: float = 1.0 - exp(-TAU * 900.0 / RATE)
	var state: float = 0.0
	for index: int in range(samples.size()):
		state += alpha * (samples[index] - state)
		samples[index] = state
	_write("10-low-light", samples, {"note":"heartbeat loop + fire, one-pole 900 Hz low-pass emulating the SFX bus in low light"})

## Two bars at each intensity 0..3, through the real set_music_intensity cross-fade.
func _render_music(name: String, ambience: float) -> void:
	var stems: Array[PackedFloat32Array] = []
	var synced: AudioStreamSynchronized = Soundscape.music_stream()
	if synced == null:
		failures += 1
		return
	for index: int in range(synced.stream_count): stems.append(Soundscape.render_stream(synced.get_sync_stream(index)))
	var sound := OfflineSound.new()
	var bar: int = roundi(Soundscape.bar_seconds() * RATE)
	var loop: int = bar * Soundscape.MUSIC_BARS
	var samples := PackedFloat32Array()
	samples.resize(bar * 8)
	var block: int = 512
	for start: int in range(0, samples.size(), block):
		sound.set_music_intensity(start / (bar * 2))
		sound._step_stems(float(block) / RATE)
		var gains: PackedFloat32Array = sound.stem_gains()
		for index: int in range(start, mini(start + block, samples.size())):
			var value: float = 0.0
			for stem: int in range(stems.size()): value += stems[stem][index % loop] * gains[stem]
			samples[index] = value * 0.7 * ambience
	sound.free()
	_write(name, samples, {"ambience":ambience,"note":"2 bars each at intensity 0,1,2,3; cross-fades over %.1f bars" % Soundscape.MUSIC_FADE_BARS})

func _write(name: String, samples: PackedFloat32Array, metadata: Dictionary) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var peak: float = 0.0
	var energy: float = 0.0
	for index: int in range(samples.size()):
		peak = maxf(peak, absf(samples[index]))
		energy += samples[index] * samples[index]
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = Soundscape._wav(bytes)
	var path: String = OUTPUT + "/" + name + ".wav"
	if stream.save_to_wav(ProjectSettings.globalize_path(path)) != OK: failures += 1
	if peak > db_to_linear(-1.0): failures += 1
	metadata.path = path
	metadata.peak_dbfs = snappedf(linear_to_db(maxf(peak, 0.000001)), 0.01)
	metadata.rms_dbfs = snappedf(linear_to_db(maxf(sqrt(energy / maxf(1.0, samples.size())), 0.000001)), 0.01)
	metadata.seconds = float(samples.size()) / RATE
	report.append(metadata)

# ---- Procedural music stems -------------------------------------------------------------------
# A minor, i-VI-III-VII (Am F C G), one chord per bar. Every note is added modulo the loop length,
# so each stem is circular: its last sample runs straight into its first.

const CHORDS: Array = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
const ROOTS: Array = [33, 29, 36, 31]
const BASS_PATTERN: Array = [0, 0, 12, 0, 0, 7, 12, 0]
const ARP_PATTERN: Array = [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 3, 1, 2]
const STEM_WEIGHTS: Array = [0.24, 0.30, 0.34, 0.17]

static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

static func _table(harmonics: Array) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(2048)
	for index: int in range(2048):
		var value: float = 0.0
		for harmonic: int in range(harmonics.size()): value += sin(TAU * (harmonic + 1) * index / 2048.0) * float(harmonics[harmonic])
		table[index] = value
	return table

func _render_stems() -> void:
	var loop: int = roundi(Soundscape.bar_seconds() * RATE) * Soundscape.MUSIC_BARS
	var bar: int = loop / Soundscape.MUSIC_BARS
	var eighth: int = bar / 8
	var sixteenth: int = bar / 16
	var random := RandomNumberGenerator.new()
	random.seed = 96
	var saw: PackedFloat32Array = _table([1.0, 0.35, 0.18, 0.09, 0.05, 0.025])
	var square: PackedFloat32Array = _table([1.0, 0.0, 0.3, 0.0, 0.14, 0.0, 0.06])
	var stems: Array[PackedFloat32Array] = []
	for index: int in range(4):
		var stem := PackedFloat32Array()
		stem.resize(loop)
		stems.append(stem)
	for chord: int in range(Soundscape.MUSIC_BARS):
		# Pad: each chord tone as two slightly detuned soft saws, slow attack, release into the next bar.
		for note: int in CHORDS[chord]:
			for detune: float in [-0.0012, 0.0012]:
				var step: float = _hz(note) * (1.0 + detune) * 2048.0 / RATE
				var phase: float = 1024.0 * (detune + 0.0012) / 0.0024
				var length: int = bar + int(0.8 * RATE)
				for index: int in range(length):
					var seconds: float = float(index) / RATE
					var envelope: float = smoothstep(0.0, 0.45, seconds) * (1.0 - smoothstep(float(bar) / RATE - 0.1, float(length) / RATE, seconds))
					stems[0][(chord * bar + index) % loop] += saw[int(phase) & 2047] * envelope
					phase += step
		# Bass: an eighth-note pulse on the root, plucked.
		for pulse: int in range(8):
			var hz: float = _hz(ROOTS[chord] + BASS_PATTERN[pulse])
			var length: int = eighth
			for index: int in range(length):
				var seconds: float = float(index) / RATE
				var envelope: float = smoothstep(0.0, 0.004, seconds) * exp(-seconds * 7.0) * smoothstep(0.0, 0.01, float(length - index) / RATE)
				var tone: float = sin(TAU * hz * seconds) + 0.35 * sin(TAU * 2.0 * hz * seconds)
				stems[1][(chord * bar + pulse * eighth + index) % loop] += tanh(tone * 1.4) * envelope * (1.0 if pulse % 2 == 0 else 0.75)
		# Drums: kick on 1, 3 and the and-of-3; snare on 2 and 4; hats on every eighth.
		for hit: int in range(8):
			var start: int = chord * bar + hit * eighth
			if hit in [0, 4, 5]: _kick(stems[2], start, loop, 1.0 if hit != 5 else 0.6)
			if hit in [2, 6]: _snare(stems[2], start, loop, random)
			_hat(stems[2], start, loop, random, 0.55 if hit % 2 == 1 else 0.3)
		# Lead: a sixteenth-note arpeggio an octave up with a dotted-eighth echo.
		for arp: int in range(16):
			var tones: Array = CHORDS[chord]
			var pick: int = ARP_PATTERN[arp]
			var midi: float = float(tones[pick % 3]) + 12.0 + (12.0 if pick == 3 else 0.0)
			var step: float = _hz(midi) * 2048.0 / RATE
			var phase: float = 0.0
			var length: int = sixteenth * 2
			for index: int in range(length):
				var seconds: float = float(index) / RATE
				var envelope: float = smoothstep(0.0, 0.003, seconds) * exp(-seconds * 11.0) * smoothstep(0.0, 0.01, float(length - index) / RATE)
				var value: float = square[int(phase) & 2047] * envelope
				var at: int = chord * bar + arp * sixteenth + index
				stems[3][at % loop] += value
				stems[3][(at + sixteenth * 3) % loop] += value * 0.35
				stems[3][(at + sixteenth * 6) % loop] += value * 0.12
				phase += step
	var mixed := PackedFloat32Array()
	mixed.resize(loop)
	for stem: int in range(4):
		var peak: float = 0.0
		for value: float in stems[stem]: peak = maxf(peak, absf(value))
		var scale: float = float(STEM_WEIGHTS[stem]) / maxf(peak, 0.0001)
		for index: int in range(loop):
			stems[stem][index] *= scale
			mixed[index] += stems[stem][index]
	var total: float = 0.0
	for value: float in mixed: total = maxf(total, absf(value))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Soundscape.STEM_DIR))
	for stem: int in range(4):
		# One guard frame repeating the first: see Soundscape.music_stream() on loop_end.
		var bytes := PackedByteArray()
		bytes.resize((loop + 1) * 2)
		for index: int in range(loop + 1): bytes.encode_s16(index * 2, int(clampf(stems[stem][index % loop] * 0.7 / total, -1.0, 1.0) * 32767.0))
		var path: String = Soundscape.STEM_DIR + Soundscape.STEMS[stem] + ".wav"
		if Soundscape._wav(bytes).save_to_wav(ProjectSettings.globalize_path(path)) != OK: failures += 1
	print("AUDIO STEMS: ", loop, " samples per stem (", Soundscape.MUSIC_BARS, " bars at ", Soundscape.MUSIC_BPM, " bpm), full-mix peak scaled to 0.7")

func _kick(stem: PackedFloat32Array, start: int, loop: int, level: float) -> void:
	var phase: float = 0.0
	for index: int in range(int(0.34 * RATE)):
		var seconds: float = float(index) / RATE
		phase += TAU * lerpf(45.0, 125.0, exp(-seconds * 28.0)) / RATE
		stem[(start + index) % loop] += sin(phase) * smoothstep(0.0, 0.002, seconds) * exp(-seconds * 11.0) * smoothstep(0.0, 0.02, 0.34 - seconds) * level

func _snare(stem: PackedFloat32Array, start: int, loop: int, random: RandomNumberGenerator) -> void:
	var low: float = 0.0
	for index: int in range(int(0.22 * RATE)):
		var seconds: float = float(index) / RATE
		var white: float = random.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.3)
		var body: float = sin(TAU * 190.0 * seconds) * exp(-seconds * 30.0)
		stem[(start + index) % loop] += ((white - low * 0.5) * exp(-seconds * 17.0) * 0.55 + body * 0.5) * smoothstep(0.0, 0.001, seconds) * smoothstep(0.0, 0.02, 0.22 - seconds)

func _hat(stem: PackedFloat32Array, start: int, loop: int, random: RandomNumberGenerator, level: float) -> void:
	var low: float = 0.0
	for index: int in range(int(0.06 * RATE)):
		var seconds: float = float(index) / RATE
		var white: float = random.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.5)
		stem[(start + index) % loop] += (white - low) * exp(-seconds * 70.0) * smoothstep(0.0, 0.01, 0.06 - seconds) * level * 0.5
