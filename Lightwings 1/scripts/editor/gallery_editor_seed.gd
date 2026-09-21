class_name GalleryEditorSeed
extends RefCounted
## Static hand-off from the gallery to the editor (§12.6): "open in editor" for a specific file, or
## an empty coverage cell pre-seeded with an element, tier and suggested archetype/family.

static var pending_path: String = ""
static var pending_seed: Dictionary = {}

static func take_path() -> String:
	var value: String = pending_path
	pending_path = ""
	return value

static func take_seed() -> Dictionary:
	var value: Dictionary = pending_seed
	pending_seed = {}
	return value
