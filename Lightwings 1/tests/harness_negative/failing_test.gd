extends SceneTree
## Negative control for `tools\test.ps1 -SelfTest`: prints a summary but exits 1.
## The runner must report it failed with "exit code 1".

func _initialize() -> void:
	print("HARNESS CONTROL FAIL: 1 checks, 1 failures")
	quit(1)
