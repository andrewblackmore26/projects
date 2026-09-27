extends SceneTree
## Offline mono listening reel using the actual samples, defaults and voice policy.
## It omits spatial attenuation; enemy levels therefore represent the near-field maximum.

class OfflineSound extends Soundscape:
	var seconds: float = 0.0
	func _now_seconds() -> float: return seconds

var failures: int = 0
var report: Array[Dictionary] = []
const OUTPUT: String = "res://artifacts/audio-review"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_render("00-isolated-fire", 0.5, [{"at":0.1,"cue":"fire"}])
	var ui_events: Array[Dictionary] = [
		{"at":0.5,"cue":"click"},{"at":1.2,"cue":"click"},{"at":2.0,"cue":"evolve"},
		{"at":3.2,"cue":"hurt"},{"at":4.3,"cue":"clear"},{"at":5.4,"cue":"death"},
	]
	_render("01-interface-and-feedback", 7.0, ui_events)
	var fight: Array[Dictionary] = []
	for tick: int in range(40):
		var at: float = 0.5 + tick * 0.14
		fight.append({"at":at,"cue":["fire","lightning","void","corruption","plasma"][tick % 5],"source":"player"})
		for enemy: int in range(7):
			fight.append({"at":at,"cue":["fire","lightning","void","corruption","plasma"][enemy % 5],"source":"enemy"})
		for pickup: int in range(8): fight.append({"at":at,"cue":"pickup"})
		if tick in [12, 25]: fight.append({"at":at,"cue":"hurt"})
	fight.append({"at":6.4,"cue":"clear"})
	_render("02-dense-combat-default-mix", 8.0, fight)
	var collecting: Array[Dictionary] = []
	for tick: int in range(100): collecting.append({"at":0.5 + tick * 0.025,"cue":"pickup"})
	_render("03-optional-pickups", 4.0, collecting, true)
	_render("05-default-pickups-silent", 4.0, collecting)
	_render_ambience()
	var manifest: FileAccess = FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"note":"Offline mono samples at actual default gains; no normalization, spatial attenuation or OS output processing. No automatic claim of listening approval.", "files":report}, "\t"))
	else: failures += 1
	await process_frame
	await create_timer(0.1).timeout
	print("AUDIO AUDITION: ", report.size(), " files, ", failures, " failures")
	quit(1 if failures else 0)

func _render(name: String, duration: float, events: Array[Dictionary], pickups: bool = false) -> void:
	var sound := OfflineSound.new()
	sound.configure({"music":false,"pickup_cues":pickups})
	root.add_child(sound)
	sound.set_process(false)
	var records: Dictionary = {}
	var accepted: int = 0
	for event: Dictionary in events:
		sound.seconds = float(event.at)
		var source: String = str(event.get("source", "player"))
		var ok: bool = sound.play_at(str(event.cue), Vector2.ZERO, source) if event.has("source") else sound.play(str(event.cue))
		var active: Dictionary = {}
		for entry: Dictionary in sound.mix_snapshot():
			var key: String = "%s:%s:%.6f" % [entry.cue, entry.source, entry.started]
			active[key] = true
			if not records.has(key): records[key] = entry.duplicate()
		for key: String in records:
			if not active.has(key) and float(records[key].until) > sound.seconds: records[key].until = sound.seconds
		if ok: accepted += 1
	var samples := PackedFloat32Array()
	samples.resize(int(duration * Soundscape.RATE))
	for entry: Dictionary in records.values():
		var stream: AudioStreamWAV = Soundscape.make_clip(str(entry.cue), int(entry.variant))
		var bytes: PackedByteArray = stream.data
		var start: int = int(float(entry.started) * Soundscape.RATE)
		var length: int = mini(bytes.size() / 2, int((float(entry.until) - float(entry.started)) * Soundscape.RATE))
		for index: int in range(length):
			if start + index < samples.size(): samples[start + index] += float(bytes.decode_s16(index * 2)) / 32767.0 * float(entry.gain)
	_write(name, samples, {"requested":events.size(),"accepted":accepted,"pickup_cues":pickups})
	sound.shutdown()
	sound.queue_free()

func _render_ambience() -> void:
	var bytes: PackedByteArray = Soundscape.ambient().data
	var samples := PackedFloat32Array()
	samples.resize(bytes.size() / 2)
	for index: int in range(samples.size()):
		samples[index] = float(bytes.decode_s16(index * 2)) / 32767.0 * 0.7 * 0.15 * 0.85
	_write("04-menu-ambience", samples, {"seconds":24,"note":"Long silent gaps are intentional."})

func _write(name: String, samples: PackedFloat32Array, metadata: Dictionary) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var peak: float = 0.0
	for index: int in range(samples.size()):
		peak = maxf(peak, absf(samples[index]))
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = Soundscape._wav(bytes)
	var path: String = OUTPUT + "/" + name + ".wav"
	if stream.save_to_wav(ProjectSettings.globalize_path(path)) != OK: failures += 1
	if peak >= 1.0: failures += 1
	metadata.path = path
	metadata.peak = peak
	metadata.seconds = float(samples.size()) / Soundscape.RATE
	report.append(metadata)
