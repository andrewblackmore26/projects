extends SceneTree
## P5a: absorb-to-unlock (spec §8) and the origin's descriptor-driven starters.
const Harness = preload("res://tests/support/harness.gd")
const Campaign = preload("res://scripts/world/campaign_state.gd")

func _initialize() -> void:
	var h: Harness = Harness.new("unlock_offers")

	var campaign: CampaignState = Campaign.new()
	h.check(campaign.unlocked == [GameTuning.ELEMENTS[0]], "A fresh campaign starts with only Lightning unlocked")

	var unlocked_event: bool = campaign.unlock_element("fire", 12.0)
	h.check(unlocked_event and campaign.unlocked == [GameTuning.ELEMENTS[0], "fire"], "Absorbing Fire's light unlocks exactly Fire and nothing else")
	h.check("corruption" not in campaign.unlocked and "void" not in campaign.unlocked and "plasma" not in campaign.unlocked, "No other element is unlocked as a side effect")

	# --- Negative controls -------------------------------------------------
	h.control("a zero-amount absorption", not campaign.unlock_element("corruption", 0.0))
	h.check("corruption" not in campaign.unlocked, "A zero-amount call produced no unlock event")
	h.control("re-absorbing an already-unlocked element", not campaign.unlock_element("fire", 50.0))
	h.control("an unknown element token", not campaign.unlock_element("not_an_element", 50.0))

	# --- The origin's starter pickups never exceed the level's reveal ------
	for level: int in range(1, 6):
		var fresh: CampaignState = Campaign.new()
		fresh.level = level
		var origin: Dictionary = fresh.sector_at(Vector2i.ZERO)
		var starters: Array = origin.get("starter_pickups", [])
		var revealed: Array = Array(GameTuning.ELEMENTS).slice(0, level)
		h.check(not starters.is_empty(), "Level %d's origin hands out starter pickups" % level)
		for element: String in starters:
			h.check(element in revealed, "Level %d starter pickup '%s' is inside the revealed prefix" % [level, element])
		# The starter element is always the level's OWN newest element. On a
		# LEGITIMATE playthrough that reached level N, elements 0..N-1 are
		# already unlocked (each one's own level's boss completion revealed
		# it, and it can only have been reached by absorbing it - spec §8).
		# Simulate that real progression, then confirm the starter pickup
		# unlocks nothing NEW on top of it.
		var probe: CampaignState = Campaign.new()
		probe.level = level
		for element: String in revealed: probe.unlock_element(element, 5.0)
		var probe_unlocked: bool = false
		for element: String in starters:
			if probe.unlock_element(element, 5.0): probe_unlocked = true
		h.check(not probe_unlocked, "Starter pickups never unlock anything beyond what legitimate progression to level %d already unlocked" % level)

	# --- No V02-ADAPTER marker remains anywhere in the source tree ---------
	var hits: Array[String] = []
	_scan_for_marker("res://scripts", "V02-ADAPTER", hits)
	h.check(hits.is_empty(), "No V02-ADAPTER marker remains under scripts/ (found: %s)" % str(hits))
	# Negative control for the scan itself: seed a temp file WITH the marker
	# and confirm the same scan function reports it, proving the check can
	# actually fail rather than vacuously passing on an empty scan.
	var probe_dir: String = "user://v02_adapter_probe_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(probe_dir)
	var probe_file: FileAccess = FileAccess.open(probe_dir.path_join("probe.gd"), FileAccess.WRITE)
	probe_file.store_string("# V02-ADAPTER marker for the negative control\n")
	probe_file.close()
	var probe_hits: Array[String] = []
	_scan_for_marker(probe_dir, "V02-ADAPTER", probe_hits)
	h.control("a file seeded with the marker string", not probe_hits.is_empty())
	DirAccess.remove_absolute(probe_dir.path_join("probe.gd"))
	DirAccess.remove_absolute(probe_dir)

	h.finish(self)

func _scan_for_marker(path: String, marker: String, hits: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null: return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = directory.get_next()
			continue
		var full: String = path.path_join(entry)
		if directory.current_is_dir():
			_scan_for_marker(full, marker, hits)
		elif entry.ends_with(".gd"):
			if FileAccess.get_file_as_string(full).contains(marker): hits.append(full)
		entry = directory.get_next()
	directory.list_dir_end()
