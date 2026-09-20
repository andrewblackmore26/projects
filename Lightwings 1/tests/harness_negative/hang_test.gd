extends SceneTree
## Negative control for `tools\test.ps1 -SelfTest`: never quits, like Godot falling back to the
## project manager. The runner must kill it and report "timed out".

func _initialize() -> void:
	print("HARNESS CONTROL: 0 checks, 0 failures (and then it never exits)")
