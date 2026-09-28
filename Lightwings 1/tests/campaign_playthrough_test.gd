extends SceneTree
## P5: a BFS bot walks real membranes from the origin to the level's boss,
## beats it, and checks that the next level and its element unlock (spec
## §8, §11). Replaces the v0.2 wedge-world "walk to core_coordinate" test.

const Campaign = preload("res://scripts/world/campaign_state.gd")
const Combat = preload("res://scripts/combat/combat_world.gd")
const Rules = preload("res://scripts/world/evolution_rules.gd")
const STEP: float = 1.0 / 60.0
var checks: int = 0
var failures: Array[String] = []
var metrics: Dictionary = {}
## NOTE: GDScript lambdas capture outer locals BY VALUE, so a signal handler
## that reassigns a local (`completion = ...`) never touches the caller's
## copy. A script member is a real reference (through implicit `self`), so
## the handler below mutates the same field the test later reads.
var _last_completion: Dictionary = {}

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
	# NOTE: these are coroutines (they `await` internally). Calling one
	# without `await` only starts it - it keeps running concurrently with
	# whatever runs next, and both then race over the shared
	# `_last_completion` field. Award every call so they run in sequence.
	await _test_boss_route(1)
	await _test_boss_route(3)
	await _test_full_campaign()
	await process_frame
	print("CAMPAIGN METRICS ",JSON.stringify(metrics))
	print("CAMPAIGN PLAYTHROUGH %s: %d assertions" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

## BFS path of coords from origin to `target`, following only real, open
## membranes (never an asserted straight line - a corridor world can force a
## detour), or an empty array if unreachable.
func _bfs_path(campaign: CampaignState, target: Vector2i) -> Array[Vector2i]:
	if target == Vector2i.ZERO: return [Vector2i.ZERO]
	var parent: Dictionary = {Vector2i.ZERO: Vector2i.ZERO}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == target: break
		for dir: Vector2i in campaign.neighbours_of(current):
			var next: Vector2i = current + dir
			if not parent.has(next):
				parent[next] = current
				queue.append(next)
	if not parent.has(target): return []
	var path: Array[Vector2i] = [target]
	while path[0] != Vector2i.ZERO:
		path.push_front(parent[path[0]])
	return path

func _natural_first_evolution() -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 734927
	var combat: CombatWorld = make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	var seconds: float = 0.0
	var target: float = 100.0
	var limit: float = 120.0
	var path: Array[Vector2i] = _bfs_path(campaign,Vector2i(2,0))
	if path.is_empty(): path = _bfs_path(campaign,Vector2i(0,2))
	var index: int = 1
	while seconds < limit and combat.light_total < target and combat.light_total > 0.0:
		if combat.light_total >= GameTuning.capacity(combat.player_tier) and combat.player_tier < 5:
			var growth: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
			if not growth.is_empty(): combat.evolve_hull(growth[0])
		if combat.remaining_enemies() == 0 and combat.pickups.is_empty() and index < path.size():
			campaign.on_enter(path[index])
			combat.start_sector(campaign.sector_at(path[index]))
			index += 1
		combat.set_command(_bot_command(combat))
		combat._physics_process(STEP)
		seconds += STEP
	var passed: bool = combat.light_total >= target
	expect(passed,"Ordinary controls and real combat reach %.0f light within %.0f seconds" % [target,limit])
	var result: Dictionary = {"mode":"natural combat; starter light only; controller-command bot","seconds":snappedf(seconds,0.01),"light":combat.light_total,"tier":combat.player_tier,"passed":passed}
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

## Walks a BFS path of REAL membranes from the origin to the boss cell,
## force-clearing each node's population (this validates progression
## plumbing, not combat balance - matching the old test's own scope note),
## then defeats the boss and checks the level-completion event.
func _test_boss_route(level: int) -> void:
	var campaign: CampaignState = Campaign.new()
	campaign.level = level
	campaign.world_seed = 55021 + level
	var boss: Vector2i = campaign.boss_coord()
	var path: Array[Vector2i] = _bfs_path(campaign,boss)
	expect(not path.is_empty(),"Level %d's boss is reachable by real membranes" % level)
	if path.is_empty(): return
	var combat: CombatWorld = make_combat()
	combat.setup_player("fire",5,1200,[])
	_last_completion = {}
	combat.boss_defeated.connect(func(_element: String) -> void: _last_completion = campaign.complete_level())
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	for step_index: int in range(1,path.size()):
		var coord: Vector2i = path[step_index]
		expect(campaign.can_enter(path[step_index-1],coord,0).allowed,"Boss route only uses real, open exits")
		campaign.on_enter(coord)
		combat.start_sector(campaign.sector_at(coord))
		if coord != boss: combat.debug_clear() # arrival node checked BELOW before clearing it
	expect(campaign.current_sector == boss,"The bot's route physically arrives at the boss node")
	# M13 restated: the boss no longer spawns inside start_sector; it is queued (telegraphed, landing
	# `wave_first_s` after arrival). "Spawns exactly one rival" became "landed or queued: exactly one".
	var rival_count: int = 0
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("rival",false)): rival_count += 1
	for entry: Dictionary in combat.spawn_queue:
		if bool(entry.get("rival",false)): rival_count += 1
	expect(rival_count == 1,"The boss node spawns (or has queued) exactly one rival encounter")
	combat.debug_clear()
	await process_frame
	expect(bool(_last_completion.get("level_completed",false)),"Beating the boss completes the level")
	if level < GameTuning.LEVEL_RADIUS.size():
		expect(str(_last_completion.get("revealed_element","")) == str(GameTuning.ELEMENTS[level]),"Completing level %d reveals %s (spec §8 table)" % [level,GameTuning.ELEMENTS[level]])
	metrics["boss_route_level_%d" % level] = {"path_length":path.size(),"ring":Campaign.ring(boss)}
	combat.queue_free()

## Full five-level campaign: beat every boss in order, unlock every element
## along the way, and confirm campaign_complete() only fires at the end.
func _test_full_campaign() -> void:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 99001
	var combat: CombatWorld = make_combat()
	combat.setup_player("lightning",5,1500,[])
	var revealed: Array[String] = []
	for level: int in range(1,GameTuning.LEVEL_RADIUS.size()+1):
		campaign.level = level
		campaign.on_enter(Vector2i.ZERO)
		combat.start_sector(campaign.sector_at(Vector2i.ZERO))
		var boss: Vector2i = campaign.boss_coord()
		var path: Array[Vector2i] = _bfs_path(campaign,boss)
		expect(not path.is_empty(),"Level %d's boss is reachable" % level)
		_last_completion = {}
		var connection: Callable = func(_element: String) -> void: _last_completion = campaign.complete_level()
		combat.boss_defeated.connect(connection)
		for coord: Vector2i in path.slice(1):
			campaign.on_enter(coord)
			combat.start_sector(campaign.sector_at(coord))
			combat.debug_clear()
		combat.debug_clear()
		await process_frame
		combat.boss_defeated.disconnect(connection)
		expect(bool(_last_completion.get("level_completed",false)),"Level %d's boss completion fires exactly once" % level)
		if not str(_last_completion.get("revealed_element","")).is_empty(): revealed.append(str(_last_completion.revealed_element))
		expect(campaign.campaign_complete() == (level == GameTuning.LEVEL_RADIUS.size()),"Only the fifth level's completion finishes the campaign")
		if level < GameTuning.LEVEL_RADIUS.size(): campaign.travel_to_level(level+1)
	expect(revealed == Array(GameTuning.ELEMENTS).slice(1),"Levels 1-4 reveal Fire, Corruption, Void, Plasma in order (spec §8 table)")
	metrics["full_campaign"] = {"levels_completed":campaign.levels_completed.size(),"revealed":revealed}
	combat.queue_free()
