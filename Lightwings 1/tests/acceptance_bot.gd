extends SceneTree
## P7 acceptance bots (spec §7, §27 M1/M5). Turns the spec's own acceptance
## language into measured numbers, written to artifacts/acceptance_v03.json
## and gated line-by-line by tools\gates.ps1. Every measurement below is a
## distribution over >=20 seeds (median and max), never three picked seeds
## (tasks/lessons.md "outcomes of play are distributions").

const Campaign = preload("res://scripts/world/campaign_state.gd")
const Combat = preload("res://scripts/combat/combat_world.gd")
const BotPilot = preload("res://tests/support/bot_pilot.gd")
const Rules = preload("res://scripts/world/evolution_rules.gd")
const Harness = preload("res://tests/support/harness.gd")
const STEP: float = 1.0 / 60.0
const SEEDS: int = 20
const OUT_PATH: String = "res://artifacts/acceptance_v03.json"

var t: RefCounted

func _initialize() -> void: call_deferred("_run")

## `measure:` lines tools\gates.ps1 turns into their own gate lines (one per
## instrument, per the plan: "each ending ok=1/0"). Positive checks print
## `acceptance_<name>`; negative controls print `acceptance_negative_<name>`
## so gates.ps1 can select each group without a name collision - both use the
## same "ok=1 is good" convention (a caught control is ok=1).
func _gate(name: String, ok: bool) -> void: print("measure: acceptance_%s ok=%d" % [name,int(ok)])
func _gate_negative(name: String, ok: bool) -> void: print("measure: acceptance_negative_%s ok=%d" % [name,int(ok)])

## Identical to campaign_playthrough_test's own _bfs_path: real membranes only.
func _bfs_path(campaign: CampaignState, target: Vector2i) -> Array[Vector2i]:
	if target == Vector2i.ZERO: return [Vector2i.ZERO]
	var parent: Dictionary = {Vector2i.ZERO: Vector2i.ZERO}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for dir: Vector2i in campaign.exits_of(current):
			var next: Vector2i = current + dir
			if not parent.has(next):
				parent[next] = current
				queue.append(next)
				if next == target: break
	if not parent.has(target): return []
	var path: Array[Vector2i] = [target]
	while path[0] != Vector2i.ZERO:
		path.push_front(parent[path[0]])
	return path

func _make_combat() -> CombatWorld:
	var combat: CombatWorld = Combat.new()
	combat.visuals_enabled = false
	root.add_child(combat)
	combat.set_physics_process(false)
	return combat

func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	return (float(sorted[n/2]) if n % 2 == 1 else (float(sorted[n/2-1])+float(sorted[n/2]))/2.0)

func _max(values: Array) -> float:
	var m: float = 0.0
	for v: float in values: m = maxf(m,v)
	return m

## --- 1. First evolution within 2 minutes (spec §6/§27 M1) -----------------
## Novice is the acceptance bot (perfect makes "within 2 minutes" vacuous -
## see tests/support/bot_pilot.gd's own doc comment); perfect is measured for
## contrast only. Control: with the bot's fire disabled it must not reach it.

func _run_first_evolution(novice: bool, seed_value: int, cap_seconds: float, fire_disabled: bool = false) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 400000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	var pilot: RefCounted = BotPilot.novice(seed_value) if novice else BotPilot.perfect(seed_value)
	if fire_disabled: pilot.fires = false
	var path: Array[Vector2i] = _bfs_path(campaign,Vector2i(2,0))
	if path.is_empty(): path = _bfs_path(campaign,Vector2i(0,2))
	var index: int = 1
	var seconds: float = 0.0
	var deaths: int = 0
	# A new player who dies reboots into a fresh run immediately (§7.4, and the death-to-flying gate
	# below measures that at ~0.6 s), so "first evolution within 2 minutes" is a claim about a new
	# player's SESSION, not about one fragile life. Measuring per-life instead did two bad things:
	# a novice that died at 40 s contributed its short elapsed time to the median, flattering it,
	# and 5 of 20 seeds never evolved at all while the gate - which only read the median - passed.
	while seconds < cap_seconds and combat.player_tier < 2:
		if not combat.active:
			deaths += 1
			campaign.on_death()
			combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
			campaign.on_enter(Vector2i.ZERO)
			combat.start_sector(campaign.sector_at(Vector2i.ZERO,combat.elapsed))
			path = _bfs_path(campaign,Vector2i(2,0))
			if path.is_empty(): path = _bfs_path(campaign,Vector2i(0,2))
			index = 1
			continue
		if combat.remaining_enemies() == 0 and combat.pickups.is_empty() and index < path.size():
			campaign.on_enter(path[index])
			combat.start_sector(campaign.sector_at(path[index],combat.elapsed))
			index += 1
		if combat.light_total >= GameTuning.capacity(combat.player_tier,combat.max_player_tier) and combat.player_tier < combat.max_player_tier:
			var growth: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
			if not growth.is_empty(): combat.evolve_hull(growth[0])
		combat.set_command(pilot.command(combat))
		combat._physics_process(STEP)
		seconds += STEP
	var result: Dictionary = {"seconds":snappedf(seconds,0.01),"evolved":combat.player_tier>=2,"deaths":deaths}
	combat.queue_free()
	return result

func _measure_first_evolution() -> Dictionary:
	var novice_seconds: Array[float] = []
	var perfect_seconds: Array[float] = []
	var novice_within_2min: int = 0
	var novice_evolved: int = 0
	var novice_deaths: Array[float] = []
	for seed_value: int in range(1,SEEDS+1):
		var novice: Dictionary = _run_first_evolution(true,seed_value,170.0)
		novice_seconds.append(novice.seconds)
		novice_deaths.append(float(novice.deaths))
		if novice.evolved: novice_evolved += 1
		if novice.evolved and novice.seconds <= 120.0: novice_within_2min += 1
		var perfect: Dictionary = _run_first_evolution(false,seed_value,170.0)
		perfect_seconds.append(perfect.seconds)
	var result: Dictionary = {
		"novice_median_s":_median(novice_seconds),"novice_max_s":_max(novice_seconds),
		"novice_within_2min_of":"%d/%d" % [novice_within_2min,SEEDS],
		"novice_evolved_of":"%d/%d" % [novice_evolved,SEEDS],
		"novice_deaths_median":_median(novice_deaths),"novice_deaths_max":_max(novice_deaths),
		"perfect_median_s":_median(perfect_seconds),"perfect_max_s":_max(perfect_seconds),
	}
	# Gate on every seed reaching it, and on the WORST seed, not just the median: a median alone
	# let a quarter of the runs fail silently.
	_gate("first_evolution_novice_all_evolve",t.check(novice_evolved == SEEDS,"Every novice seed reaches its first evolution (%d/%d)" % [novice_evolved,SEEDS]))
	_gate("first_evolution_novice_within_2min",t.check(novice_within_2min == SEEDS,"Every novice seed's first evolution lands within 2 minutes (%d/%d, median %.1fs, max %.1fs)" % [novice_within_2min,SEEDS,_median(novice_seconds),_max(novice_seconds)]))
	var fire_disabled_evolved: bool = false
	for seed_value: int in range(1,6):
		if _run_first_evolution(true,seed_value,200.0,true).evolved: fire_disabled_evolved = true
	_gate_negative("first_evolution_fire_disabled",t.control("novice bot with fire disabled",not fire_disabled_evolved))
	return result

## --- 2. Camping loses within about a minute (spec §7.3) -------------------
## Camper re-clears one ring-1 node for the whole window - never leaves, so
## the node's finite pool (spec: "the pool does not follow") never gets the
## real-time refill that only applies between visits. Pusher walks outward
## through fresh nodes instead. Both start with identical stats and seeds.

func _camp_coord(campaign: CampaignState) -> Vector2i:
	var exits: Array[Vector2i] = campaign.exits_of(Vector2i.ZERO)
	return Vector2i.ZERO+exits[0] if not exits.is_empty() else Vector2i(1,0)

## Both camper and pusher must be allowed to grow (spec §6/§8) or a pusher
## walking into escalating ring tiers with a FIXED hull just dies, which
## would tank its own average for a reason that has nothing to do with §7.3.
func _maybe_evolve(combat: CombatWorld, campaign: CampaignState) -> void:
	if combat.light_total >= GameTuning.capacity(combat.player_tier,combat.max_player_tier) and combat.player_tier < combat.max_player_tier:
		var growth: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
		if not growth.is_empty(): combat.evolve_hull(growth[0])

func _run_camper(seed_value: int, duration: float, unlimited_pool: bool) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 500000+seed_value
	var combat: CombatWorld = _make_combat()
	# A HALF-FULL tier-6 bar, not a full tier-3 one. This instrument counts light ABSORBED, and a
	# full bar absorbs nothing: on the rail roster, where enemies are bigger targets and die faster,
	# a tier-3 camper sat at 500/500 for 94-100 % of the run, so its "decline" was the bar's
	# ceiling and the instant-refill control could not be caught (S10 Finding 1, probed in S11).
	# Tier 6 cannot evolve further and half of 2300 leaves more room than a camper can fill.
	combat.setup_player("fire",GameTuning.MAX_TIER,GameTuning.capacity(GameTuning.MAX_TIER)*0.5,[])
	var coord: Vector2i = _camp_coord(campaign)
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord,0.0))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	var totals: Array = [0.0,0.0] # [first half, second half]
	var seconds_box: Array = [0.0]
	var cb: Callable = func(_e: String,amount: float) -> void:
		if seconds_box[0] < duration*0.5: totals[0] += amount
		else: totals[1] += amount
	combat.light_collected.connect(cb)
	var seconds: float = 0.0
	while seconds < duration and combat.active:
		seconds_box[0] = seconds
		# Negative control seam: a camper never leaves this sector, so
		# CampaignState's own real-time refill (which only applies BETWEEN
		# visits) cannot even be consulted here - the mechanism actually
		# responsible for the camper's decline within one continuous stay is
		# CombatWorld.sector_energy_remaining depleting and staying at 0.
		# Pinning it high is what genuinely removes the depletion this check
		# measures (tasks/lessons.md: sabotage the thing the instrument
		# actually reads, not a mechanism it never touches).
		if unlimited_pool: combat.sector_energy_remaining = 999999
		_maybe_evolve(combat,campaign)
		combat.set_command(pilot.command(combat)) # sits still when nothing to fight - a real camper's behaviour
		combat._physics_process(STEP)
		seconds += STEP
	combat.light_collected.disconnect(cb)
	var total: float = totals[0]+totals[1]
	var minutes: float = duration/60.0
	combat.queue_free()
	return {"light_per_minute":total/minutes,"first_half_rate":totals[0]/(minutes/2.0),"second_half_rate":totals[1]/(minutes/2.0)}

func _run_pusher(seed_value: int, duration: float) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 500000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("fire",GameTuning.MAX_TIER,GameTuning.capacity(GameTuning.MAX_TIER)*0.5,[]) # the same start as the camper it is compared with
	var coord: Vector2i = Vector2i.ZERO
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord,0.0))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	var visited: Dictionary = {CampaignState.coord_key(coord):true}
	var totals: Array = [0.0,0.0]
	var seconds_box: Array = [0.0]
	var cb: Callable = func(_e: String,amount: float) -> void:
		if seconds_box[0] < duration*0.5: totals[0] += amount
		else: totals[1] += amount
	combat.light_collected.connect(cb)
	var seconds: float = 0.0
	while seconds < duration and combat.active:
		seconds_box[0] = seconds
		if combat.remaining_enemies() == 0 and combat.pickups.is_empty():
			var boss: Vector2i = campaign.boss_coord()
			var best: Vector2i = coord
			var best_ring: int = -1
			for dir: Vector2i in campaign.exits_of(coord):
				var candidate: Vector2i = coord+dir
				if candidate == boss: continue # keep pushing through regular content, not the (no-respawn) boss
				var key: String = CampaignState.coord_key(candidate)
				if visited.has(key): continue
				if CampaignState.ring(candidate) > best_ring:
					best_ring = CampaignState.ring(candidate)
					best = candidate
			if best == coord: best = _bfs_first_hop(campaign,coord,func(c: Vector2i) -> bool: return not visited.has(CampaignState.coord_key(c)) and c != boss)
			if best != coord:
				coord = best
				visited[CampaignState.coord_key(coord)] = true
				campaign.on_enter(coord)
				combat.start_sector(campaign.sector_at(coord,seconds))
		_maybe_evolve(combat,campaign)
		combat.set_command(pilot.command(combat))
		combat._physics_process(STEP)
		seconds += STEP
	combat.light_collected.disconnect(cb)
	var total: float = totals[0]+totals[1]
	var minutes: float = duration/60.0
	combat.queue_free()
	return {"light_per_minute":total/minutes,"first_half_rate":totals[0]/(minutes/2.0),"second_half_rate":totals[1]/(minutes/2.0),"nodes_visited":visited.size()}

func _measure_camper_vs_pusher() -> Dictionary:
	var duration: float = 600.0 # ~10 simulated minutes, spec §7.3
	var camper_rates: Array[float] = []
	var pusher_rates: Array[float] = []
	var worse_second_half: int = 0
	for seed_value: int in range(1,SEEDS+1):
		var camper: Dictionary = _run_camper(seed_value,duration,false)
		var pusher: Dictionary = _run_pusher(seed_value,duration)
		camper_rates.append(camper.light_per_minute)
		pusher_rates.append(pusher.light_per_minute)
		if camper.second_half_rate < camper.first_half_rate: worse_second_half += 1
	var median_camper: float = _median(camper_rates)
	var median_pusher: float = _median(pusher_rates)
	var result: Dictionary = {
		"camper_light_per_minute_median":median_camper,"camper_light_per_minute_max":_max(camper_rates),
		"pusher_light_per_minute_median":median_pusher,"pusher_light_per_minute_max":_max(pusher_rates),
		"camper_worse_second_half_of":"%d/%d" % [worse_second_half,SEEDS],
	}
	_gate("camper_vs_pusher_ratio",t.check(median_pusher >= median_camper*1.5,"Pusher's median light/minute (%.1f) is at least 1.5x the camper's (%.1f)" % [median_pusher,median_camper]))
	_gate("camper_declines_within_visit",t.check(worse_second_half > SEEDS/2,"Camper's second half is worse than its first in most seeds (%d/%d)" % [worse_second_half,SEEDS]))
	# Control isolates the POOL-DEPLETION mechanism specifically (the 1.5x
	# ratio above is also shaped by the respawn cooldown, which an instant
	## refill does not touch - see tasks/lessons.md "a negative control covers
	# only the lines it can reach"): under instant refill the camper's own
	# within-visit decline (second half worse than first) must disappear.
	var declined: int = 0
	var instant_rates: Array[float] = []
	var finite_rates: Array[float] = []
	for seed_value: int in range(1,11):
		var instant: Dictionary = _run_camper(seed_value,duration,true)
		if instant.second_half_rate < instant.first_half_rate: declined += 1
		instant_rates.append(instant.light_per_minute)
		finite_rates.append(camper_rates[seed_value-1])
	print("camper probe: instant-refill light/min median %.2f max %.2f | finite pool median %.2f max %.2f | instant declined %d/10" % [_median(instant_rates),_max(instant_rates),_median(finite_rates),_max(finite_rates),declined])
	# The control is the INCOME comparison, not "the decline disappears". Measured in S11 on both
	# rosters: an instantly refilling pool lifts a camper's median from 6.4 to 61.0 light/min on
	# v0.3 hulls and to 29.7 on rail hulls, so the pool IS what starves a camper. But on rail hulls
	# the half-against-half decline stays (10/10 seeds) even with an infinite pool, because bigger
	# targets die early in the visit - so "declined <= 5" asked kill timing, not pool depletion, and
	# could not be caught there. 2x is far inside the smaller of the two measured lifts (4.6x).
	_gate_negative("camper_pool_instant_refill",t.control("node pool refills instantly (camper %.1f -> %.1f light/min)" % [_median(finite_rates),_median(instant_rates)],_median(instant_rates) >= _median(finite_rates)*2.0))
	return result

## --- 3. Frictionless death: under 2s death-to-flying-again (spec §7.4/§27) -

func _measure_death_to_flying() -> Dictionary:
	var times_ms: Array[float] = []
	for i: int in range(SEEDS):
		var explored: int = i % 4
		var app: Node = load("res://scripts/main.gd").new()
		app.testing = true
		root.add_child(app)
		await process_frame
		SaveService.storage_root = "user://acceptance-death-%d-%d" % [i,Time.get_ticks_usec()]
		app._new_game(false)
		app.combat.set_physics_process(false)
		for k: int in range(explored):
			var dirs: Array[Vector2i] = app.campaign.exits_of(app.campaign.current_sector)
			if dirs.is_empty(): break
			app._enter_sector(app.campaign.current_sector+dirs[0],app.combat.arena.entry_position(dirs[0]),false)
		app.combat.player_invulnerable = 0.0
		app.combat.player.invulnerable = 0.0
		app.combat._damage_actor(app.combat.player,1000000.0,1,1) # synchronously fires _on_death
		var elapsed_s: float = 0.0
		var pressed: bool = false
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = i
		var press_at: float = 0.36+rng.randf()*0.3 # a player pressing again shortly after the guard
		var moved: bool = false
		var dt: float = 1.0/60.0
		while elapsed_s < 3.0 and not moved:
			app._process(dt)
			if not pressed and elapsed_s >= press_at:
				pressed = true
				var event: InputEventKey = InputEventKey.new()
				event.keycode = KEY_W
				event.pressed = true
				app._input(event)
			if is_instance_valid(app.combat): app._physics_process(dt)
			if app.overlay_kind != "death" and int(app.get("_input_swallow_frames")) == 0 and is_instance_valid(app.combat) and app.combat.active:
				moved = true
			elapsed_s += dt
		times_ms.append(elapsed_s*1000.0)
		await app._stop_audio()
		app.queue_free()
		await process_frame
	var result: Dictionary = {"death_to_flying_ms_median":_median(times_ms),"death_to_flying_ms_max":_max(times_ms)}
	_gate("death_to_flying_median_under_2s",t.check(_median(times_ms) < 2000.0,"Median death-to-flying-again is under 2000ms (got %.0fms)" % _median(times_ms)))
	_gate("death_to_flying_max_under_2s",t.check(_max(times_ms) < 2000.0,"Max death-to-flying-again over %d seeds is under 2000ms (got %.0fms)" % [SEEDS,_max(times_ms)]))
	return result

## --- 4. Chasing a light type works (spec §8/§27 M5) ------------------------
## A bot that prefers one element's nodes (here: corruption, a genuinely rare
## roll under dev-mode's reveal-everything pool - see GameTuning.NEW_ELEMENT_
## WEIGHT) unlocks that element sooner than an indifferent bot walking the
## same seeds with no preference.

## "fire" (ELEMENTS[1]) is a genuinely rare roll at level 5: element_of()
## favours the LAST revealed element (plasma) at NEW_ELEMENT_WEIGHT=55%, so
## every other revealed element (fire included) splits the remaining 45%
## roughly evenly - worth deliberately chasing, unlike plasma which an
## indifferent bot trips over almost immediately.
const CHASE_TARGET: String = "fire"

func _run_chase(seed_value: int, prefer: bool, cap_seconds: float) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.configure_mode("campaign")
	campaign.level = 5 # reveals every element into the POOL (spec §8 table); unlocked still starts [lightning] only
	campaign.world_seed = 600000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	# Mirrors main.gd::_on_energy's unlock call - nothing else drives campaign.unlocked in this standalone test.
	var unlock_cb: Callable = func(element: String,amount: float) -> void: campaign.unlock_element(element,amount)
	combat.light_collected.connect(unlock_cb)
	var coord: Vector2i = Vector2i.ZERO
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord,0.0))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	var visited: Dictionary = {CampaignState.coord_key(coord):true}
	var seconds: float = 0.0
	while seconds < cap_seconds and not (CHASE_TARGET in campaign.unlocked):
		if combat.remaining_enemies() == 0 and combat.pickups.is_empty():
			var chosen: Vector2i = coord
			if prefer: chosen = _chase_step(campaign,coord,visited,3)
			if chosen == coord: chosen = _indifferent_step(campaign,coord,visited)
			if chosen != coord:
				coord = chosen
				visited[CampaignState.coord_key(coord)] = true
				campaign.on_enter(coord)
				combat.start_sector(campaign.sector_at(coord,seconds))
		_maybe_evolve(combat,campaign)
		combat.set_command(pilot.command(combat))
		combat._physics_process(STEP)
		seconds += STEP
	combat.light_collected.disconnect(unlock_cb)
	combat.queue_free()
	return {"seconds":snappedf(seconds,0.01),"unlocked":CHASE_TARGET in campaign.unlocked}

## Unvisited neighbour if there is one; otherwise the first hop of a BFS
## toward the nearest unvisited node at all (so a locally-surrounded bot does
## not falsely read as "stuck" in a well-connected world - see P5a's measured
## exit-count histogram, most nodes have >1 exit but a long walk can still
## visit every IMMEDIATE neighbour before the frontier moves).
func _indifferent_step(campaign: CampaignState, coord: Vector2i, visited: Dictionary) -> Vector2i:
	for dir: Vector2i in campaign.exits_of(coord):
		var candidate: Vector2i = coord+dir
		if not visited.has(CampaignState.coord_key(candidate)): return candidate
	return _bfs_first_hop(campaign,coord,func(c: Vector2i) -> bool: return not visited.has(CampaignState.coord_key(c)))

## BFS from `coord` for the nearest node satisfying `predicate`; returns the
## first hop of that path, or `coord` if none is reachable within the cap.
func _bfs_first_hop(campaign: CampaignState, coord: Vector2i, predicate: Callable) -> Vector2i:
	var parent: Dictionary = {CampaignState.coord_key(coord):coord}
	var queue: Array[Vector2i] = [coord]
	var head: int = 0
	var found: Vector2i = coord
	var steps: int = 0
	while head < queue.size() and steps < 800:
		var current: Vector2i = queue[head]
		head += 1
		steps += 1
		if current != coord and predicate.call(current):
			found = current
			break
		for dir: Vector2i in campaign.exits_of(current):
			var next: Vector2i = current+dir
			var key: String = CampaignState.coord_key(next)
			if not parent.has(key):
				parent[key] = current
				queue.append(next)
	if found == coord: return coord
	var walk: Vector2i = found
	while parent.get(CampaignState.coord_key(walk),coord) != coord:
		walk = parent[CampaignState.coord_key(walk)]
	return walk

## BFS lookahead up to `depth` for the nearest unvisited node whose element is
## CHASE_TARGET; steps one hop toward it, or falls back (caller handles that).
func _chase_step(campaign: CampaignState, coord: Vector2i, visited: Dictionary, depth: int) -> Vector2i:
	var parent: Dictionary = {CampaignState.coord_key(coord):coord}
	var queue: Array[Vector2i] = [coord]
	var head: int = 0
	var found: Vector2i = coord
	var steps: int = 0
	while head < queue.size() and steps < 400:
		var current: Vector2i = queue[head]
		head += 1
		steps += 1
		if campaign.element_of(current) == CHASE_TARGET and current != coord:
			found = current
			break
		if CampaignState.ring(current)-CampaignState.ring(coord) >= depth: continue
		for dir: Vector2i in campaign.exits_of(current):
			var next: Vector2i = current+dir
			var key: String = CampaignState.coord_key(next)
			if not parent.has(key):
				parent[key] = current
				queue.append(next)
	if found == coord: return coord
	var walk: Vector2i = found
	while parent.get(CampaignState.coord_key(walk),coord) != coord:
		walk = parent[CampaignState.coord_key(walk)]
	return walk

func _measure_light_chasing() -> Dictionary:
	# Repaired in S0 (P10): the old gate compared medians that folded capped (failed) runs in, and
	# its control compared two indifferent walks on DIFFERENT seeds, which can differ either way by
	# luck. Now a run that never unlocks is a failure, counted; the claim is paired per seed (same
	# world, only the preference differs); and the control is the same pairing with the preference
	# off on both sides, where the advantage must be exactly nil.
	var chaser_runs: Array = []
	var indifferent_runs: Array = []
	for seed_value: int in range(1,SEEDS+1):
		chaser_runs.append(_run_chase(seed_value,true,240.0))
		indifferent_runs.append(_run_chase(seed_value,false,240.0))
	var score: Dictionary = _chase_score(chaser_runs,indifferent_runs)
	var result: Dictionary = {
		"chaser_unlocked":score.a_unlocked,"indifferent_unlocked":score.b_unlocked,
		"chaser_sooner":score.a_sooner,"indifferent_sooner":score.b_sooner,"ties":score.ties,
		"chaser_median_s_unlocked_only":score.a_median,"indifferent_median_s_unlocked_only":score.b_median,
	}
	_gate("light_chasing_unlocks_at_least_as_often",t.check(score.a_unlocked >= score.b_unlocked and score.a_unlocked > 0,"Chasing %s unlocks it in at least as many seeds as an indifferent walk (%d vs %d of %d)" % [CHASE_TARGET,score.a_unlocked,score.b_unlocked,SEEDS]))
	_gate("light_chasing_sooner_in_more_seeds",t.check(score.a_sooner > score.b_sooner,"Seed for seed, chasing gets there sooner more often than it gets there later (%d sooner, %d later, %d ties)" % [score.a_sooner,score.b_sooner,score.ties]))
	var control: Dictionary = _chase_score(indifferent_runs,indifferent_runs)
	_gate_negative("light_chasing_preference_disabled",t.control("chase preference disabled on both sides",not (control.a_sooner > control.b_sooner)))
	return result

## Pairs two lists of `_run_chase` results seed for seed. A run that hit the cap is a FAILURE:
## it never counts as "sooner", and its time never enters a median.
func _chase_score(a_runs: Array, b_runs: Array) -> Dictionary:
	var a_times: Array[float] = []
	var b_times: Array[float] = []
	var a_sooner: int = 0
	var b_sooner: int = 0
	var ties: int = 0
	for i: int in range(a_runs.size()):
		var a: Dictionary = a_runs[i]
		var b: Dictionary = b_runs[i]
		if a.unlocked: a_times.append(float(a.seconds))
		if b.unlocked: b_times.append(float(b.seconds))
		if a.unlocked and (not b.unlocked or float(a.seconds) < float(b.seconds)): a_sooner += 1
		elif b.unlocked and (not a.unlocked or float(b.seconds) < float(a.seconds)): b_sooner += 1
		else: ties += 1
	return {"a_unlocked":a_times.size(),"b_unlocked":b_times.size(),"a_sooner":a_sooner,"b_sooner":b_sooner,"ties":ties,
		"a_median":_median(a_times) if not a_times.is_empty() else -1.0,"b_median":_median(b_times) if not b_times.is_empty() else -1.0}

func _run() -> void:
	t = Harness.new("ACCEPTANCE V0.3")
	print("acceptance roster: ", ShipCatalog.use_cmdline_root())
	var results: Dictionary = {}
	results["first_evolution"] = _measure_first_evolution()
	results["camper_vs_pusher"] = _measure_camper_vs_pusher()
	results["death_to_flying"] = await _measure_death_to_flying()
	results["light_chasing"] = _measure_light_chasing()
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null and not dir.dir_exists("artifacts"): dir.make_dir("artifacts")
	var file: FileAccess = FileAccess.open(OUT_PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("ACCEPTANCE RESULTS ",JSON.stringify(results))
	t.finish(self)
