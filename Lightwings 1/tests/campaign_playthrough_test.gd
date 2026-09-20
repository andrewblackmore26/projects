extends SceneTree

const Campaign = preload("res://scripts/world/campaign_state.gd")
const Combat = preload("res://scripts/combat/combat_world.gd")
const Rules = preload("res://scripts/world/evolution_rules.gd")
const STEP: float = 1.0 / 60.0
var checks: int = 0
var failures: Array[String] = []
var metrics: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func make_combat() -> CombatWorld:
	var combat: CombatWorld = Combat.new()
	combat.visuals_enabled = false
	combat.set_physics_process(false)
	root.add_child(combat)
	combat.set_physics_process(false)
	return combat

func _run() -> void:
	metrics["natural_first_evolution"] = _natural_first_evolution()
	metrics["natural_waypoint_recovery"] = _natural_first_evolution(true)
	_test_campaign_route(false)
	_test_campaign_route(true)
	_test_core_escape()
	await process_frame
	print("CAMPAIGN METRICS ",JSON.stringify(metrics))
	print("CAMPAIGN PLAYTHROUGH %s: %d assertions" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func _natural_first_evolution(returning: bool = false) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	if returning:
		# A prior-life fixture grants only persistent waypoint history.
		campaign.on_enter(Vector2i(12,0))
		campaign.on_death()
	var combat: CombatWorld = make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	var seconds: float = 0.0
	var target: float = 250.0 if returning else 100.0
	var limit: float = 180.0 if returning else 120.0
	var route: Array[Vector2i] = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]
	var index: int = 0
	while seconds < limit and combat.light_total < target and combat.light_total > 0.0:
		if combat.light_total >= GameTuning.capacity(combat.player_tier) and combat.player_tier < 5:
			var growth: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
			combat.evolve_hull(growth[0])
		if combat.remaining_enemies() == 0 and combat.pickups.is_empty() and index < route.size():
			campaign.on_enter(route[index])
			combat.start_sector(campaign.sector_at(route[index]))
			index += 1
		combat.set_command(_bot_command(combat))
		combat._physics_process(STEP)
		seconds += STEP
	var passed: bool = combat.light_total >= target
	expect(passed,"Ordinary controls and real combat reach %.0f light within %.0f seconds" % [target,limit])
	if passed:
		var options: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
		expect(options.size()==3 and combat.evolve_hull(options[0]),"Natural threshold enables actual three-hull evolution")
		if returning:
			campaign.current_sector = Vector2i.ZERO
			expect(campaign.can_teleport(Vector2i(12,0),combat.player_tier),"Actual regrowth meets saved waypoint tier requirement")
	var result: Dictionary = {"mode":"natural combat; starter light only; controller-command bot","prior_life_fixture":returning,"seconds":snappedf(seconds,0.01),"light":combat.light_total,"tier":combat.player_tier,"passed":passed}
	combat.queue_free()
	return result

func _bot_command(combat: CombatWorld) -> ShipCommand:
	var command: ShipCommand = ShipCommand.new()
	var position: Vector2 = combat.player_position
	var nearest: Dictionary = {}
	var distance: float = INF
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("dead",false)): continue
		var candidate: float = position.distance_to(actor.pos)
		if candidate < distance:
			nearest = actor
			distance = candidate
	if not nearest.is_empty():
		var toward: Vector2 = Vector2(nearest.pos)-position
		command.aim = (toward+Vector2(nearest.vel)*(distance/435.0)).normalized()
		command.fire = true
		command.ability_primary = true
		command.ability_secondary = true
		command.movement = toward.normalized() if distance > 280.0 else -toward.normalized() if distance < 200.0 else toward.normalized().orthogonal()
	var pickup_distance: float = INF
	var pickup_point: Vector2 = position
	for pickup: Dictionary in combat.pickups:
		var candidate: float = position.distance_to(pickup.pos)
		if candidate < pickup_distance:
			pickup_distance = candidate
			pickup_point = pickup.pos
	if pickup_distance < 180.0 or nearest.is_empty() and pickup_distance < INF:
		command.movement = (pickup_point-position).normalized()
	var avoidance: Vector2 = Vector2.ZERO
	for index: int in combat.bullets.active_indices:
		if combat.bullets.factions[index] == 0: continue
		var relative: Vector2 = position-combat.bullets.positions[index]
		var velocity: Vector2 = combat.bullets.velocities[index]
		if relative.length()>150.0 or velocity.length_squared()<1.0: continue
		var time: float = clampf(relative.dot(velocity)/velocity.length_squared(),0.0,0.4)
		var miss: Vector2 = relative-velocity*time
		if miss.length()<26.0: avoidance += miss.normalized() if miss.length()>1.0 else velocity.normalized().orthogonal()
	if not avoidance.is_zero_approx(): command.movement = (command.movement+avoidance*2.0).normalized()
	var center: Vector2 = GameTuning.ARENA_CENTER
	var edge: Vector2 = (position-center)/(GameTuning.ARENA_RADIUS-100.0)
	if edge.length()>0.85: command.movement = (command.movement-edge.normalized()*1.5).normalized()
	return command

func _test_campaign_route(is_demo: bool) -> void:
	# This fixture validates real spawning/clear/progression plumbing, not balance.
	var campaign: CampaignState = Campaign.new()
	campaign.configure(is_demo)
	var combat: CombatWorld = make_combat()
	combat.setup_player("fire",3 if is_demo else 5,500 if is_demo else 1200,[])
	combat.sector_cleared.connect(func() -> void: campaign.clear_sector(campaign.current_sector))
	combat.rival_defeated.connect(func(core_id: String) -> void:
		if not core_id.is_empty(): campaign.defeat_core(core_id)
	)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	var transitions: int = 0
	var targets: Array = ["fire"] if is_demo else Array(GameTuning.ELEMENTS)
	for element: String in targets:
		var target: Vector2i = campaign.core_coordinate(element)
		while campaign.current_sector != target:
			var direction: Vector2i = Vector2i(signi(target.x-campaign.current_sector.x),0) if campaign.current_sector.x != target.x else Vector2i(0,signi(target.y-campaign.current_sector.y))
			var next: Vector2i = campaign.current_sector+direction
			expect(campaign.can_enter(campaign.current_sector,next,0).allowed,"Core route uses free cardinal exits")
			campaign.on_enter(next)
			combat.start_sector(campaign.sector_at(next))
			if next == target:
				var rival_count: int = 0
				for actor: Dictionary in combat.enemies:
					if bool(actor.get("rival",false)): rival_count += 1
				expect(rival_count > 0,"Core descriptor spawns real rival encounter")
			combat.debug_clear()
			transitions += 1
		expect(element in campaign.defeated_leaders,"Actual core encounter clear records its objective")
	expect(campaign.demo_completed if is_demo else campaign.completed,"Chosen campaign route reaches matching completion")
	var before: Array = campaign.defeated_leaders.duplicate()
	campaign.on_death()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	expect(campaign.defeated_leaders==before and combat.player_tier==1 and combat.light_total==GameTuning.START_LIGHT,"Reboot keeps cores while resetting seed hull and light")
	metrics["demo_route" if is_demo else "full_route"]={"mode":"forced clear; validates progression only","transitions":transitions,"cores":before.size(),"waypoints":campaign.checkpoints.size()}
	combat.queue_free()

func _test_core_escape() -> void:
	var campaign: CampaignState = Campaign.new()
	var combat: CombatWorld = make_combat()
	combat.setup_player("fire",3,400,[])
	combat.rival_defeated.connect(func(core_id: String) -> void: campaign.defeat_core(core_id))
	var coord: Vector2i = campaign.core_coordinate("fire")
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord))
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("rival",false)):
			# P4b: a boss's core is shielded/multi-cored (spec §14) - a single
			# massive hit no longer kills it outright; destroy the shield
			# generator and every sub-core first, exactly as a player would.
			for i: int in actor.get("shield_generator_indices",PackedInt32Array()): combat._damage_part(actor,i,1000000.0,combat.player)
			for i: int in actor.get("sub_core_indices",PackedInt32Array()): combat._damage_part(actor,i,1000000.0,combat.player)
			combat._damage_actor(actor,1000000.0,0,0)
	combat._cleanup_dead()
	expect("fire" in campaign.defeated_leaders and combat.remaining_enemies()>0,"Actual rival kill credits objective while other opponents survive")
	expect(not campaign.sector_at(coord).cleared,"Core kill alone does not erase the remaining encounter")
	var remaining: int = combat.remaining_enemies()
	campaign.on_enter(coord+Vector2i.RIGHT)
	combat.start_sector(campaign.sector_at(campaign.current_sector))
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord))
	expect(combat.remaining_enemies()==remaining,"Leaving and returning preserves surviving core-node opponents")
	campaign.on_death()
	combat.setup_player("neutral",1,40,[])
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord))
	var rivals: int = 0
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("rival",false)): rivals+=1
	expect(rivals==0 and combat.remaining_enemies()>0,"New life repopulates regular enemies without respawning defeated core")
	combat.queue_free()
