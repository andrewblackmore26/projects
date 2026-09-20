extends SceneTree
## Coverage for spec §25 (narrative) and scripts/ui/dialogue_director.gd (plan P9).
## Two kinds of proof, deliberately kept separate:
## - Static wiring: main.gd actually calls a trigger for every required id (a source
##   scan, the same technique tests/facade_contract_test.gd already uses in this
##   codebase for exactly this reason -- proving main.gd is WIRED without paying for
##   a full Node/audio/SceneTree instantiation of the whole game).
## - Behavioural: DialogueDirector itself (queue, dedupe, the between-fights gate,
##   the immediate lane) exercised directly, since it is a plain RefCounted.
const Harness = preload("res://tests/support/harness.gd")

## Spec §25 triggers that fire with a literal, unparametrized id.
const REQUIRED_LITERAL_IDS: Array[String] = [
	"welcome_v2", "map_tutorial_v2", "first_elite_v2", "first_threshold_v2",
	"first_regression_v2", "first_evolution_v2",
]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("DIALOGUE COVERAGE")
	_test_static_wiring(h)
	_test_boss_per_level(h)
	_test_between_fights_gate(h)
	_test_immediate_lane(h)
	_test_never_shown_twice(h)
	h.finish(self)

func _test_static_wiring(h: RefCounted) -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	h.check(not source.is_empty(), "scripts/main.gd can be read")
	for id: String in REQUIRED_LITERAL_IDS:
		h.check(source.contains('"%s"' % id), "main.gd queues a line for trigger '%s'" % id)
	h.check(source.contains('"unlocked_"+element'), "main.gd queues a line on the absorb-unlock path (P5a's CampaignState.unlock_element)")
	h.check(source.contains('"reboot_v2_"+str(campaign.deaths)'), "main.gd queues a per-death reboot line whose id includes the death count, so the story advances each death")
	h.check(source.contains('"boss_intro_"+str(sector.element)'), "main.gd queues a boss ENCOUNTER line keyed by element")
	h.check(source.contains('"defeat_v2_"+element'), "main.gd queues a boss DEFEAT line keyed by element")
	h.check(source.contains('"boss_intro_"+str(sector.element),true)'), "the boss encounter line is queued through the immediate lane (5th arg true)")
	h.control("a fabricated trigger id is not actually wired into main.gd", not source.contains('"definitely_not_a_real_trigger_id"'))

## Spec §25 "each level boss" via the v0.2 wedge world's "five radial cores"
## remap: CampaignState.element_of gives a level's boss the LAST element of
## that level's reveal slice, and the five campaign/demo levels reveal
## GameTuning.ELEMENTS one at a time -- so a boss's own `element` already
## identifies exactly one level, and the element-keyed dialogue ids
## (boss_intro_<element> / defeat_v2_<element>) are therefore per-level.
func _test_boss_per_level(h: RefCounted) -> void:
	var campaign := CampaignState.new()
	campaign.configure_mode("campaign")
	var seen: Dictionary = {}
	for level: int in range(1, GameTuning.LEVEL_RADIUS.size() + 1):
		campaign.level = level
		var boss_element: String = str(campaign.sector_at(campaign.boss_coord()).get("element", ""))
		h.check(not boss_element.is_empty(), "Level %d has a boss element" % level)
		h.check(not seen.has(boss_element), "Level %d's boss element ('%s') is distinct from every earlier level's" % [level, boss_element])
		seen[boss_element] = level
	h.check(seen.size() == GameTuning.LEVEL_RADIUS.size(), "All five levels produce five distinct boss dialogue ids (%d found)" % seen.size())
	var dev_campaign := CampaignState.new()
	dev_campaign.configure_mode("dev")
	var dev_seen: Dictionary = {}
	for level: int in range(1, GameTuning.LEVEL_RADIUS.size() + 1):
		dev_campaign.level = level
		dev_seen[str(dev_campaign.sector_at(dev_campaign.boss_coord()).get("element", ""))] = true
	h.control("dev mode (which reveals every element from tick 0) collapses to ONE boss element across all five levels, proving the per-level distinctness above is a real campaign/demo property and not an artifact of how sector_at() is called", dev_seen.size() == 1)

func _test_between_fights_gate(h: RefCounted) -> void:
	var d := DialogueDirector.new()
	h.control("can_show_next on an empty queue reports ready-to-show, which would let _update_dialogue pop nothing into something", not d.can_show_next(true))
	d.queue("companion", "T", "normal line", "normal_id")
	h.check(d.line_queue.size() == 1, "A normal line enters the queue")
	h.check(not d.can_show_next(false), "Between-fights gate: a normal line cannot leave while enemies remain")
	h.check(d.pop_next(false).is_empty(), "pop_next refuses a normal line while enemies remain")
	h.check(d.line_queue.size() == 1, "The refused line stays queued, not dropped")
	h.check(d.can_show_next(true), "Between-fights gate opens once the caller reports the node clear")
	var shown: Dictionary = d.pop_next(true)
	h.check(str(shown.get("text", "")) == "normal line" and d.line_queue.is_empty(), "A normal line leaves the queue once the node is clear")

## Spec §25's one named exception: a level boss's own ENCOUNTER line must be
## able to appear WITH enemies still alive, or it could only ever show after
## the fight it announces is already over.
func _test_immediate_lane(h: RefCounted) -> void:
	var d := DialogueDirector.new()
	d.queue("companion", "T", "queued first", "already_waiting")
	d.queue_immediate("lightning", "Rival", "boss line", "boss_intro_lightning")
	h.check(d.line_queue.size() == 2 and str(d.line_queue[0].get("text", "")) == "boss line", "queue_immediate jumps to the FRONT of the queue, ahead of an already-waiting normal line")
	h.check(d.can_show_next(false), "The boss encounter line appears with enemies still alive (combat_clear=false)")
	var shown: Dictionary = d.pop_next(false)
	h.check(str(shown.get("text", "")) == "boss line", "pop_next returns exactly the immediate line while enemies remain")
	h.check(not d.can_show_next(false), "Once the immediate line is gone, the next (ordinary) line is gated again")
	h.check(d.pop_next(false).is_empty(), "The remaining queued line still cannot leave while enemies remain")
	h.check(d.can_show_next(true) and str(d.pop_next(true).get("text", "")) == "queued first", "The ordinary line leaves once the node is clear")
	var normal_only := DialogueDirector.new()
	normal_only.queue("lightning", "Rival", "boss line", "boss_intro_lightning")
	h.control("a boss line queued through the ORDINARY lane (queue(), not queue_immediate()) cannot show while enemies remain, proving the immediate lane -- not the element or text -- is what grants the exception", not normal_only.can_show_next(false))

func _test_never_shown_twice(h: RefCounted) -> void:
	var d := DialogueDirector.new()
	d.queue("companion", "T", "once", "dup_id")
	d.queue("companion", "T", "twice", "dup_id")
	h.check(d.line_queue.size() == 1, "A line is never shown twice: re-queuing the same id is a no-op")
	d.queue_immediate("companion", "T", "thrice", "dup_id")
	h.check(d.line_queue.size() == 1, "The dedupe also blocks the immediate lane for an id already seen")
	var shown: Dictionary = d.pop_next(true)
	d.queue("companion", "T", "fourth attempt, after showing", "dup_id")
	h.check(str(shown.get("text", "")) == "once" and d.line_queue.is_empty(), "The id stays blocked even after the line has already been shown and the queue has drained")
	var bypass := DialogueDirector.new()
	bypass.queue("companion", "T", "once", "dup_id_2")
	bypass.line_queue.append({"element": "companion", "title": "T", "text": "twice", "immediate": false}) # bypasses _enqueue's dedupe on purpose
	h.control("appending to line_queue directly (bypassing queue()/seen_lines) lets a duplicate id slip through, proving the dedupe lives in _enqueue and is not incidental", bypass.line_queue.size() == 2)
	var bypass2 := DialogueDirector.new()
	bypass2.queue("companion", "T", "first showing", "dup_id_3")
	bypass2.pop_next(true)
	bypass2.seen_lines.erase("dup_id_3") # bypass: forget it was ever shown
	bypass2.queue("companion", "T", "second attempt", "dup_id_3")
	h.control("erasing seen_lines lets an already-shown id re-queue, proving seen_lines (not queue position) is what prevents repeats", bypass2.line_queue.size() == 1)
