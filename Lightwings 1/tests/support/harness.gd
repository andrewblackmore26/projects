extends RefCounted
## Shared assertions for the SceneTree tests. Load with:
##   const Harness = preload("res://tests/support/harness.gd")
## No class_name on purpose: nothing under tests/ should enter the game's global namespace.
##
## `check` is an ordinary assertion. `control` is a negative control: the test sabotages the thing
## it measures and reports whether its instrument noticed. An instrument that cannot fail proves
## nothing, so an uncaught control is a failure of the test itself.

var title: String
var checks: int = 0
var controls_caught: int = 0
var failures: Array[String] = []

func _init(name: String) -> void:
	title = name

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
	return ok

func control(what_was_sabotaged: String, instrument_noticed: bool) -> bool:
	checks += 1
	if instrument_noticed:
		controls_caught += 1
	else:
		var message: String = "Negative control not caught: " + what_was_sabotaged
		failures.append(message)
		push_error(message)
	return instrument_noticed

func finish(tree: SceneTree) -> void:
	print("%s: %d checks, %d failures (%d negative controls caught)" % [title, checks, failures.size(), controls_caught])
	tree.quit(0 if failures.is_empty() else 1)
