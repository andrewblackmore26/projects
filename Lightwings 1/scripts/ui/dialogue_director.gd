## Extracted from scripts/main.gd (plan P9, tasks/todo.md). Owns the dialogue
## QUEUE, the per-id dedupe (`seen_lines`), the "speaks only between fights"
## gate, and the static narrative line tables (spec §25). Presentation (the
## Control/portrait/label building) stays in main.gd's `_update_dialogue`, so
## this stays a pure, headlessly-testable RefCounted with no scene tree.
##
## Two lanes, one FIFO queue:
## - `queue()` is the normal lane. A line queued here only leaves the queue
##   once the caller reports the fight is clear (spec §25 "speaks only
##   between fights; lines queue until the node is clear").
## - `queue_immediate()` is the one named exception (spec §25 "a line ... on
##   encounter" for a level boss): the between-fights gate would otherwise
##   make an ENCOUNTER line impossible to show before the fight it is
##   announcing is already over. An immediate line jumps to the FRONT of the
##   same queue and carries a flag that lets it leave even while enemies are
##   still alive; every other queued line is unaffected and still waits its
##   turn behind it.
class_name DialogueDirector
extends RefCounted

var line_queue: Array[Dictionary] = []
var seen_lines: Dictionary = {}

const RIVAL_NAMES: Dictionary = {
	"fire": "PYRE", "lightning": "KERA", "void": "NOX",
	"corruption": "VERDANT", "companion": "ECHO", "plasma": "VESPER",
}

func reset() -> void:
	line_queue.clear()
	seen_lines.clear()

## Restores a saved run's queue/dedupe state (SaveService's `seen_lines`/
## `line_queue` keys, unchanged names so old saves need no migration).
func restore(saved_seen: Dictionary, saved_queue: Array) -> void:
	seen_lines = saved_seen.duplicate(true)
	line_queue.assign(saved_queue)

func queue(element: String, title: String, text: String, id: String) -> void:
	_enqueue(element, title, text, id, false)

func queue_immediate(element: String, title: String, text: String, id: String) -> void:
	_enqueue(element, title, text, id, true)

func _enqueue(element: String, title: String, text: String, id: String, immediate: bool) -> void:
	if seen_lines.has(id): return
	seen_lines[id] = true
	var entry: Dictionary = {"element": element, "title": title, "text": text, "immediate": immediate}
	if immediate: line_queue.push_front(entry)
	else: line_queue.append(entry)

## Whether the queue's own FRONT line may leave right now: either the
## between-fights gate is open (`combat_clear`, i.e. `combat.remaining_enemies()
## == 0`), or the front line itself is the one immediate-lane exception.
func can_show_next(combat_clear: bool) -> bool:
	if line_queue.is_empty(): return false
	return combat_clear or bool(line_queue[0].get("immediate", false))

## Pops and returns the front line if `can_show_next` allows it; {} otherwise.
## A caller (main.gd) is expected to only call this once its own presentation
## timer (`dialogue_remaining`) has cleared, so this never has to arbitrate
## "is the box free" -- only "is this line allowed to leave the queue".
func pop_next(combat_clear: bool) -> Dictionary:
	if not can_show_next(combat_clear): return {}
	return line_queue.pop_front()

## Static line tables (spec §25 Appendix, v0.2 wedge-world "five radial
## cores" remapped 1:1 to the five level bosses: `CampaignState.element_of`
## gives a level's boss the LAST element in that level's reveal slice, and
## the five levels reveal `GameTuning.ELEMENTS` in order one at a time -- so
## for campaign/demo (not dev, which reveals every element from tick 0) a
## boss's `element` already identifies exactly one level, and these tables
## keyed by element are already keyed by level boss).
static func entry_line(root: String) -> String:
	return {
		"fire": "I am the heat that makes dead code move.\nShow me what survives the flame.",
		"lightning": "You call that movement?\nI have already seen where you will be.",
		"void": "All your bright futures end somewhere.\nCome closer. I will show you where.",
		"corruption": "There is no such thing as a solitary mind.\nOnly a network that has not found you yet.",
		"plasma": "Every orbit returns to its beginning.\nShow me how you escape yours.",
	}.get(root, "Your signal ends here.")

static func defeat_line(root: String) -> String:
	return {
		"fire": "So. You can carry the fire without becoming ash.",
		"lightning": "An error in my prediction. An interesting one.",
		"void": "Even emptiness leaves something behind.",
		"corruption": "A piece of me goes with you. We will meet again.",
		"plasma": "Our orbits crossed. Yours continues.",
	}.get(root, "Keep the code. Remember the cost.")
