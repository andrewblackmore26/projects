class_name EvolutionScreen
extends UiScreen
## The evolution cards (moved from main.gd's `_show_evolution` in M2). main.gd still decides
## whether the screen may open and rolls `pending_offers`; this draws them. Choosing a card calls
## main.gd's `_choose_evolution`, which applies the hull and queues the companion line.

## Each card's nodes, so a card enters as one (motion_items).
var _cards: Array = []

func motion_items() -> Array:
	var in_cards: Dictionary = {}
	for card: Array in _cards:
		for node: Node in card: in_cards[node] = true
	var items: Array = super().filter(func(node: Node) -> bool: return not in_cards.has(node))
	var footer: int = items.size() - 2
	for index: int in range(_cards.size()): items.insert(footer + index, _cards[index])
	return items

func build() -> void:
	centered_label(host,"BECOME SOMETHING NEW",Vector2(110,45),Vector2(1060,52),UiTokens.TEXT_2XL,WHITE)
	centered_label(host,"Choose a lightship. Every weapon and passive shown belongs to that hull.",Vector2(110,110),Vector2(1060,35),UiTokens.TEXT_M,MUTED)
	var x: float = 125.0
	# With every hull on offer (dev mode) the cards are grouped behind a one-element-at-a-time tab
	# strip: 20 cards will not fit, and 20 live ShipPreviews would mean 20 HDR SubViewports.
	var shown: Array[String] = app.pending_offers
	if app.pending_offers.size() > 3:
		var by_element: Dictionary = {}
		for id: String in app.pending_offers:
			var ship: ShipDefinition = ShipCatalog.get_ship(id)
			if ship == null: continue
			if not by_element.has(ship.element): by_element[ship.element] = [] as Array[String]
			by_element[ship.element].append(id)
		var elements: Array = by_element.keys()
		if not elements.has(app.evolution_tab): app.evolution_tab = str(elements[0]) if not elements.is_empty() else ""
		var tab_x: float = 125.0
		for element: String in elements:
			var tab: Button = button(host,element.to_upper(),Rect2(tab_x,128,190,30),func() -> void:
				app.evolution_tab = element
				app._close_overlay()
				app._show_evolution())
			tab.disabled = element == app.evolution_tab
			tab_x += 200.0
		shown = by_element.get(app.evolution_tab,[] as Array[String])
	for id: String in shown:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship == null: continue
		var ink: Color = ShipCatalog.get_color(ship.element)
		var first: int = host.get_child_count()
		UiKit.glass(host,Rect2(x,165,330,497),Color(ink,0.45))
		UiKit.label(host,"%s · %s · T%d" % [ship.element.to_upper(),ship.role.to_upper(),ship.tier],Vector2(x+20,183),Vector2(290,25),UiTokens.TEXT_XS,ink).theme_type_variation = UiTokens.KICKER_LABEL
		UiKit.label(host,ship.display_name,Vector2(x+20,218),Vector2(290,48),UiTokens.TEXT_L,WHITE).theme_type_variation = UiTokens.DISPLAY_LABEL
		var preview := ShipPreview.new()
		preview.fit_margin = 14.0
		host.add_child(preview)
		preview.position = Vector2(x+20,267)
		preview.initialize(ship,Vector2(290,175),1.5)
		UiKit.label(host,"Primary: %s\nSecondary: %s\nPassive: %s" % [UiKit.ability_name(ship.primary),UiKit.ability_names(ship.secondaries),UiKit.ability_names(ship.passives)],Vector2(x+20,450),Vector2(290,92),14,WHITE)
		UiKit.label(host,"Speed %.0f · Buffer ×%.2f\nFootprint %.0f px · Magnet %.0f px" % [ship.speed,ship.hp_buffer,ship.footprint,ship.magnet_radius],Vector2(x+20,547),Vector2(290,45),12,MUTED)
		var choice: Button = button(host,"CHOOSE SHIP",Rect2(x+20,608,290,40),app._choose_evolution.bind(id))
		if _focus == null: _focus = choice
		_cards.append(host.get_children().slice(first))
		x += 350.0
	centered_label(host,"GAMEPLAY PAUSED · Choose your next form",Vector2(100,679),Vector2(1080,25),UiTokens.TEXT_XS,MUTED).theme_type_variation = UiTokens.KICKER_LABEL
	button(host,"DECIDE LATER",Rect2(520,720,240,43),app._close_overlay)
