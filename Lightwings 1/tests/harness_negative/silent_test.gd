extends SceneTree
## Negative control for `tools\test.ps1 -SelfTest`: exits 0 without ever reporting a result,
## which is what a test looks like when it returns early before its assertions run.
## The runner must report it failed with "no summary line".

func _initialize() -> void:
	quit(0)
