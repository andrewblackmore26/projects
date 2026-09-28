class_name ToastStack
extends RefCounted
## Short event messages above the bottom bar (moved from main.gd's `_toast` in modernization M2).
## One message at a time today, the newest replacing the last; M15 turns it into a real stack.

const GOLD := VisualStyle.ACCENT
const DEFAULT_SECONDS: float = 4.0

var label: Label
var remaining: float = 0.0

func _init(parent: Control) -> void:
	label = UiKit.label(parent,"",Vector2(200,672),Vector2(880,32),17,GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func show(text: String, seconds: float = DEFAULT_SECONDS) -> void:
	label.text = text
	remaining = seconds

func tick(delta: float) -> void:
	remaining = maxf(0.0,remaining-delta)
	label.visible = remaining > 0.0
