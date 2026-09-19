class_name WorkshopCombatPreview
extends Control
## Real simulation and renderer, isolated from the campaign and persistence.
var ship: ShipDefinition
var world: CombatWorld
var actor: Dictionary
var dummy: Dictionary
var details: Label
var _time: float = 0
var pilot: bool = false
func _ready() -> void:
	var container: SubViewportContainer = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1
	environment.glow_intensity = 1.5
	environment.glow_strength = 0.35
	for index: int in range(7): environment.set_glow_level(index, 0.8 if index == 0 else 0)
	environment_node.environment = environment
	viewport.add_child(environment_node)
	world = CombatWorld.new()
	viewport.add_child(world)
	world.setup_player("neutral", 1, 1000, [], Vector2(490, 560))
	if ship.is_player:
		world.player_tier = ship.tier
		world.player_element = ship.element
		world._configure_actor(world.player, ship, true)
		world._update_visual(world.player)
		actor = world.player
		dummy = world._spawn_enemy("fire", 5, Vector2(960, 560), false)
	else:
		actor = world._spawn_enemy(ship.element, ship.tier, Vector2(960, 560), false)
		actor.elite = ship.faction == "elite"
		world._configure_actor(actor, ship, true)
		world._update_visual(actor)
		dummy = world.player
	var compositor: CombatCompositor = CombatCompositor.new()
	viewport.add_child(compositor)
	compositor.attach(world)
	details = Label.new()
	details.position = Vector2(12, 12)
	details.add_theme_color_override("font_color", Color.WHITE)
	add_child(details)
	var toggle: CheckButton = CheckButton.new()
	toggle.text = "Fire mounted components"
	toggle.button_pressed = true
	toggle.position = Vector2(12, 590)
	toggle.toggled.connect(func(value: bool) -> void: world.active = value)
	add_child(toggle)
	var pilot_toggle: CheckButton = CheckButton.new()
	pilot_toggle.text = "Pilot ship · WASD / mouse / Space Shift Q"
	pilot_toggle.position = Vector2(300, 590)
	pilot_toggle.toggled.connect(func(value: bool) -> void: pilot = value)
	add_child(pilot_toggle)
func _process(delta: float) -> void:
	if world == null or actor.is_empty(): return
	_time += delta
	world.player_invulnerable = 100
	world.light_total = 1000
	if pilot:
		world.command.movement = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length()
		world.command.aim = (get_local_mouse_position() - size * 0.5).normalized()
		world.command.fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		world.command.secondaries = [Input.is_physical_key_pressed(KEY_SPACE), Input.is_physical_key_pressed(KEY_SHIFT), Input.is_physical_key_pressed(KEY_Q)]
	else:
		world.player.pos = Vector2(490, 560)
		world.player_position = Vector2(490, 560)
		world.command.movement = Vector2.ZERO
		world.command.aim = Vector2.RIGHT
		world.command.fire = ship.is_player
		world.command.secondaries = [true, true, true]
	if not dummy.is_empty():
		dummy.hp = 100000
		dummy.max_hp = 100000
		if dummy != world.player: dummy.speed = 0
		dummy.fire_cd = 100
		dummy.primary_cd = 100
		dummy.secondary_cd = 100
		if dummy != world.player: dummy.pos = Vector2(960, 560)
	if not ship.is_player: actor.pos = Vector2(960, 560); actor.speed = 0
	var lines: PackedStringArray = [ship.display_name + " · live production combat", "Dummy HP is replenished; close to return to editing."]
	for gun: Dictionary in actor.get("guns", []): lines.append("%s  HP %.0f / %.0f  fire in %.2fs" % [gun.id, gun.hp, gun.max_hp, maxf(0, gun.cd)])
	details.text = "\n".join(lines)

