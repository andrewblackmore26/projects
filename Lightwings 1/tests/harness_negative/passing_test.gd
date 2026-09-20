extends SceneTree
## Positive control for `tools\test.ps1 -SelfTest`: a well-behaved test the runner must PASS.
## Without it, a runner that fails everything would look healthy.

func _initialize() -> void:
	print("HARNESS CONTROL PASS: 1 checks, 0 failures")
	quit(0)
