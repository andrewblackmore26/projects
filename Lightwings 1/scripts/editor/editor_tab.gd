class_name EditorTab
extends RefCounted
## Base for a flat editor tab (ship design spec §11 / S5). A tab never mutates `working` itself: it
## calls back into the editor's ONE choke point, `edit(label, mutate)`, so every change goes through
## one undo step and one refresh. `build(parent)` runs once; `refresh(working, compiled, selection)`
## runs after every edit (including someone else's tab) to redraw this tab's own controls.

## The editor that owns this tab. Set by ShipEditor right after construction.
var editor: Control

func _init(owner: Control) -> void:
	editor = owner

## Builds this tab's controls under `parent`. Override.
func build(_parent: Control) -> void:
	pass

## Redraws this tab's controls from the current ship state. Override.
func refresh(_working: ShipDefinition, _compiled: ShipDefinition, _selection: Dictionary) -> void:
	pass

## Convenience: route a mutation through the editor's one choke point.
func edit(label: String, mutate: Callable) -> void:
	editor.edit(label, mutate)
