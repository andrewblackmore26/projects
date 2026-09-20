extends SceneTree
## Negative control for `tools\test.ps1 -SelfTest`: reports success and exits 0, but the engine
## logged an error on the way. The runner must report it failed with "engine error".

func _initialize() -> void:
	push_error("harness negative control: deliberate engine error")
	print("HARNESS CONTROL: 1 checks, 0 failures")
	quit(0)
