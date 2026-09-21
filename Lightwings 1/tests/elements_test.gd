extends SceneTree
## `Elements` is the single source for which elements exist, their wire order and their six ship
## colours (ship design spec §6.2, Appendix A). This keeps the consumers and the one duplication it
## still contains (RIM_BY_INDEX, a plain array the canvases index by a bullet's element int) honest.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("ELEMENTS")
	h.check(_same_set(GameTuning.ELEMENTS, Elements.INDEX_ORDER), "The campaign reveal order and the wire order name the same five elements")
	h.control("an element missing from the reveal order", not _same_set(GameTuning.ELEMENTS.slice(1), Elements.INDEX_ORDER))
	h.check(ShipCatalog.ELEMENTS == Elements.INDEX_ORDER and CombatWorld.ELEMENTS == Elements.INDEX_ORDER, "ShipCatalog and CombatWorld index elements in the wire order")
	h.check(_rim_by_index_problem(Elements.RIM_BY_INDEX) == "", "RIM_BY_INDEX is RIM read through INDEX_ORDER (%s)" % _rim_by_index_problem(Elements.RIM_BY_INDEX))
	var swapped: Array[Color] = Elements.RIM_BY_INDEX.duplicate()
	swapped[2] = Elements.RIM["violet"]
	h.control("void's indexed rim swapped for violet", _rim_by_index_problem(swapped) != "")
	h.check(CombatWorld.COLORS == Elements.RIM_BY_INDEX and CombatWorld.PLAYER_COLOR == Elements.RIM[Elements.PLAYER_COLOR_KEY], "CombatWorld's colours are the shared ones")
	for element: String in Elements.INDEX_ORDER:
		var key: String = Elements.color_key(element)
		h.check(Elements.ELEMENT_OF_COLOR.get(key, "") == element, "%s -> %s maps back" % [element, key])
		h.check(ShipCatalog.PALETTE[element] == Elements.RIM[key] and ShipCatalog.FILLS[element] == Elements.FILL[key] and ShipCatalog.LIGHTS[element] == Elements.LIGHT[key], "%s: the catalogue's rim, fill and light are Appendix A's %s" % [element, key])
	for key: String in Elements.COLOR_KEYS:
		h.check(ShipCatalog.PALETTE.has(key) and ShipCatalog.PALETTE[key] == Elements.RIM[key] and ShipCatalog.FILLS[key] == Elements.FILL[key] and ShipCatalog.LIGHTS[key] == Elements.LIGHT[key], "Colour key %s resolves in the catalogue palette" % key)
	h.control("a colour key the palette does not have", not ShipCatalog.PALETTE.has("teal"))
	h.check(Elements.COLOR_KEYS.size() == 6 and not Elements.COLOR_KEY.values().has(Elements.PLAYER_COLOR_KEY), "Six colours, and blue belongs to no element")
	h.finish(self)

func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for item: Variant in a:
		if not b.has(item): return false
	return true

func _rim_by_index_problem(rims: Array) -> String:
	if rims.size() != Elements.INDEX_ORDER.size(): return "size %d" % rims.size()
	for i: int in range(rims.size()):
		if rims[i] != Elements.RIM[Elements.color_key(Elements.INDEX_ORDER[i])]: return "index %d (%s)" % [i, Elements.INDEX_ORDER[i]]
	return ""
