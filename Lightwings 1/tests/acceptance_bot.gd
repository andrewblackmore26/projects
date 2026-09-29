extends SceneTree
## P7 acceptance bots (spec §7, §27 M1/M5). Turns the spec's own acceptance
## language into measured numbers, written to artifacts/acceptance_v03.json
## and gated line-by-line by tools\gates.ps1. Every measurement below is a
## distribution over >=20 seeds (median and max), never three picked seeds
## (tasks/lessons.md "outcomes of play are distributions").
##
## Modernization M18: every bot now TRAVELS the way a player does - it flies to an exit arc and
## presses through the rim (`BotPilot.route_to`), and a `warp_committed` listener swaps the sector
## exactly as RunController.on_warp_committed does. Before M18 every bot teleported with
## `start_sector`, so no warp, rim dwell or accidental exit was ever part of a measurement.
## Dev seam: `-- --only=<section>[,<section>]` and `-- --seeds=N` (gates.ps1 passes neither).

const Campaign = preload("res://scripts/world/campaign_state.gd")
const Combat = preload("res://scripts/combat/combat_world.gd")
const BotPilot = preload("res://tests/support/bot_pilot.gd")
const Rules = preload("res://scripts/world/evolution_rules.gd")
const Harness = preload("res://tests/support/harness.gd")
const STEP: float = 1.0 / 60.0
const OUT_PATH: String = "res://artifacts/acceptance_v03.json"
## A route that has not committed in this long is a failed route (counted, and re-planned).
const ROUTE_TIMEOUT_S: float = 30.0

var SEEDS: int = 20
var t: RefCounted
var _only: PackedStringArray = []
## >= 0 overrides `CombatWorld.warp_engage_band` in every world `_make_combat` builds (the accidental
## lines' second control: the pre-M18 60 px press zone).
var _engage_band: float = -1.0

func _initialize() -> void: call_deferred("_run")

## `measure:` lines tools\gates.ps1 turns into their own gate lines (one per
## instrument, per the plan: "each ending ok=1/0"). Positive checks print
## `acceptance_<name>`; negative controls print `acceptance_negative_<name>`
## so gates.ps1 can select each group without a name collision - both use the
## same "ok=1 is good" convention (a caught control is ok=1).
func _gate(name: String, ok: bool) -> void: print("measure: acceptance_%s ok=%d" % [name,int(ok)])
func _gate_negative(name: String, ok: bool) -> void: print("measure: acceptance_negative_%s ok=%d" % [name,int(ok)])

func _make_combat() -> CombatWorld:
	var combat: CombatWorld = Combat.new()
	if _engage_band >= 0.0: combat.warp_engage_band = _engage_band
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

func _min(values: Array) -> float:
	if values.is_empty(): return 0.0
	var m: float = INF
	for v: float in values: m = minf(m,v)
	return m

## --- Travel (M18): the one driver every bot run steps through ---------------
## `travel` is one run's record, written by `_step` and by the warp listener:
##   warps / accidental - commits the pilot asked for / did not ask for (no route, or another arc);
##   accidental_at      - run seconds of each accidental commit (60 s windows are cut from these);
##   accidental_how     - the same commits described (direction, route, distance out) for the log;
##   dwell              - seconds within BotPilot.RIM_ZONE px of the rim before each intended commit;
##   route_s            - seconds from `route_to` to its commit (a node crossing, fighting included);
##   route_failures     - routes that did not commit within ROUTE_TIMEOUT_S;
##   secondary_uses     - secondary activations (a rising `secondary_<i>` cooldown on the player).

func _new_travel() -> Dictionary:
	return {"seconds":0.0,"warps":0,"accidental":0,"accidental_at":[],"accidental_how":[],"dwell":[],"route_s":[],"route_failures":0,
		"zone_ticks":0,"route_ticks":0,"secondary_uses":0}

## The node swap RunController.on_warp_committed makes, synchronously inside the signal, then
## `confirm_warp_swap` (without it the membrane springs the ship back - the time-to-boss control).
func _wire_warps(combat: CombatWorld, campaign: CampaignState, pilot: RefCounted, travel: Dictionary, confirm: bool = true) -> void:
	combat.warp_committed.connect(func(direction: Vector2i) -> void:
		if pilot.route == direction:
			travel.warps += 1
			travel.dwell.append(float(travel.zone_ticks)*STEP)
			travel.route_s.append(float(travel.route_ticks)*STEP)
		else:
			travel.accidental += 1
			travel.accidental_at.append(float(travel.seconds))
			var out: Vector2 = (combat.player_position-combat.arena.center).normalized()
			var approach: Vector2 = combat.warp_approach
			travel.accidental_how.append("%s while routing %s at %.0f px, %.1fs; input.out %.2f, aim.out %.2f, approach radial %.0f lateral %.0f px/s" % [direction,pilot.route,combat.player_position.distance_to(combat.arena.center),float(travel.seconds),
				combat.command.movement.limit_length(1.0).dot(out),Vector2(combat.player.aim).dot(out),approach.dot(out),absf(approach.dot(out.orthogonal()))])
		travel.zone_ticks = 0
		travel.route_ticks = 0
		if not confirm: return
		campaign.record_node_left(campaign.current_sector,combat.elapsed,float(combat.sector_energy_remaining))
		var destination: Vector2i = campaign.current_sector+direction
		campaign.on_enter(destination)
		combat.start_sector(campaign.sector_at(destination,combat.elapsed))
		combat.confirm_warp_swap())

## Asks the pilot to fly out toward `next` (an adjacent coordinate), unless it is already routing
## or a warp is under way. Returns true when a route was set.
func _route(pilot: RefCounted, combat: CombatWorld, campaign: CampaignState, travel: Dictionary, next: Vector2i) -> bool:
	if pilot.routing() or combat.warp_phase != CombatWorld.WARP_NONE or next == campaign.current_sector: return false
	pilot.route_to(next-campaign.current_sector)
	travel.route_ticks = 0
	travel.zone_ticks = 0
	return true

func _step(combat: CombatWorld, pilot: RefCounted, travel: Dictionary) -> void:
	if pilot.routing():
		travel.route_ticks += 1
		if combat.player_position.distance_to(combat.arena.center) >= combat.arena.radius-BotPilot.RIM_ZONE: travel.zone_ticks += 1
		if float(travel.route_ticks)*STEP > ROUTE_TIMEOUT_S+GameTuning.feel("warp.push_s"):
			travel.route_failures += 1
			pilot.route = Vector2i.ZERO
	var before: Dictionary = Dictionary(combat.player.get("cooldowns",{})).duplicate()
	combat.set_command(pilot.command(combat))
	combat._physics_process(STEP)
	var after: Dictionary = combat.player.get("cooldowns",{})
	for key: Variant in after:
		if str(key).begins_with("secondary_") and float(after[key]) > float(before.get(key,0.0)): travel.secondary_uses += 1
	travel.seconds += STEP

## Nothing left to fight, and no light left that the ship can still take (a full bar and a full
## bank leave light lying: waiting on it stalled a tier-6 run for 8 minutes in the first M18 run).
func _node_clear(combat: CombatWorld) -> bool: return combat.remaining_enemies() == 0 and (combat.pickups.is_empty() or not combat._player_can_collect())

## Accidental commits per 60 s window of a run of `duration` seconds.
func _accidental_windows(travel: Dictionary, duration: float) -> Array[float]:
	var windows: Array[float] = []
	windows.resize(maxi(1,floori(duration/60.0)))
	windows.fill(0.0)
	for at: float in travel.accidental_at: windows[mini(windows.size()-1,floori(at/60.0))] += 1.0
	return windows

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
	var travel: Dictionary = _new_travel()
	_wire_warps(combat,campaign,pilot,travel)
	var target: Vector2i = Vector2i(2,0)
	var seconds: float = 0.0
	var deaths: int = 0
	# A new player who dies reboots into a fresh run immediately (§7.4, and the death-to-flying gate
	# below measures that), so "first evolution within 2 minutes" is a claim about a new
	# player's SESSION, not about one fragile life. Measuring per-life instead did two bad things:
	# a novice that died at 40 s contributed its short elapsed time to the median, flattering it,
	# and 5 of 20 seeds never evolved at all while the gate - which only read the median - passed.
	while seconds < cap_seconds and combat.player_tier < 2:
		if not combat.active:
			deaths += 1
			pilot.route = Vector2i.ZERO
			campaign.on_death()
			combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
			campaign.on_enter(Vector2i.ZERO)
			combat.start_sector(campaign.sector_at(Vector2i.ZERO,combat.elapsed))
			continue
		# M18: out through the rim toward (2,0), one node at a time, each cleared first (the old
		# bot's pace rule, kept so the walk means the same thing).
		if campaign.current_sector != target and _node_clear(combat):
			_route(pilot,combat,campaign,travel,_bfs_first_hop(campaign,campaign.current_sector,func(c: Vector2i) -> bool: return c == target))
		_maybe_evolve(combat,campaign)
		_step(combat,pilot,travel)
		seconds += STEP
	var result: Dictionary = {"seconds":snappedf(seconds,0.01),"evolved":combat.player_tier>=2,"deaths":deaths,"travel":travel}
	combat.queue_free()
	return result

func _measure_first_evolution() -> Dictionary:
	var novice_seconds: Array[float] = []
	var perfect_seconds: Array[float] = []
	var novice_within_2min: int = 0
	var novice_evolved: int = 0
	var novice_deaths: Array[float] = []
	var novice_accidental: Array[float] = []
	for seed_value: int in range(1,SEEDS+1):
		var novice: Dictionary = _run_first_evolution(true,seed_value,170.0)
		novice_seconds.append(novice.seconds)
		novice_deaths.append(float(novice.deaths))
		novice_accidental.append(float(novice.travel.accidental))
		if novice.evolved: novice_evolved += 1
		if novice.evolved and novice.seconds <= 120.0: novice_within_2min += 1
		var perfect: Dictionary = _run_first_evolution(false,seed_value,170.0)
		perfect_seconds.append(perfect.seconds)
	var result: Dictionary = {
		"novice_median_s":_median(novice_seconds),"novice_max_s":_max(novice_seconds),
		"novice_within_2min_of":"%d/%d" % [novice_within_2min,SEEDS],
		"novice_evolved_of":"%d/%d" % [novice_evolved,SEEDS],
		"novice_deaths_median":_median(novice_deaths),"novice_deaths_max":_max(novice_deaths),
		"novice_accidental_warps_median":_median(novice_accidental),"novice_accidental_warps_max":_max(novice_accidental),
		"perfect_median_s":_median(perfect_seconds),"perfect_max_s":_max(perfect_seconds),
	}
	# Gate on every seed reaching it, and on the WORST seed, not just the median: a median alone
	# let a quarter of the runs fail silently.
	_gate("first_evolution_novice_all_evolve",t.check(novice_evolved == SEEDS,"Every novice seed reaches its first evolution (%d/%d)" % [novice_evolved,SEEDS]))
	_gate("first_evolution_novice_within_2min",t.check(novice_within_2min == SEEDS,"Every novice seed's first evolution lands within 2 minutes (%d/%d, median %.1fs, max %.1fs)" % [novice_within_2min,SEEDS,_median(novice_seconds),_max(novice_seconds)]))
	var fire_disabled_evolved: int = 0
	var fire_disabled_in_time: int = 0
	for seed_value: int in range(1,6):
		var disabled: Dictionary = _run_first_evolution(true,seed_value,200.0,true)
		if disabled.evolved: fire_disabled_evolved += 1
		if disabled.evolved and disabled.seconds <= 120.0: fire_disabled_in_time += 1
	# One sabotage, but each line is checked against it on its own terms (lessons: a control covers
	# only the lines it can reach).
	_gate_negative("first_evolution_fire_disabled",t.control("novice bot with fire disabled (all-evolve line: %d/5 evolved)" % fire_disabled_evolved,fire_disabled_evolved < 5))
	_gate_negative("first_evolution_within_2min_fire_disabled",t.control("novice bot with fire disabled (within-2-min line: %d/5 in time)" % fire_disabled_in_time,fire_disabled_in_time < 5))
	return result

## --- 2. Camping loses within about a minute (spec §7.3) -------------------
## Camper re-clears one ring-1 node for the whole window - never leaves, so
## the node's finite pool (spec: "the pool does not follow") never gets the
## real-time refill that only applies between visits. Pusher flies outward
## through fresh nodes instead. Both start with identical stats and seeds.
## M18: the camper is also the FIGHTER policy for the accidental-warp line - it never asks to
## leave, so every warp it makes is one it did not intend; if one happens it flies straight back.

func _camp_coord(campaign: CampaignState) -> Vector2i:
	var exits: Array[Vector2i] = campaign.neighbours_of(Vector2i.ZERO)
	return Vector2i.ZERO+exits[0] if not exits.is_empty() else Vector2i(1,0)

## Both camper and pusher must be allowed to grow (spec §6/§8) or a pusher
## walking into escalating ring tiers with a FIXED hull just dies, which
## would tank its own average for a reason that has nothing to do with §7.3.
func _maybe_evolve(combat: CombatWorld, campaign: CampaignState) -> void:
	if combat.light_total >= GameTuning.capacity(combat.player_tier,combat.max_player_tier) and combat.player_tier < combat.max_player_tier:
		var growth: Array[String] = Rules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,[],campaign.world_seed)
		if not growth.is_empty(): combat.evolve_hull(growth[0])

## `fighter` replaces the camper's pilot and `at` its node (ZERO keeps the ring-1 camp node; the
## origin itself is never a fighter's node, it holds only the training wave).
func _run_camper(seed_value: int, duration: float, unlimited_pool: bool, fighter: RefCounted = null, at: Vector2i = Vector2i.ZERO) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 500000+seed_value
	var combat: CombatWorld = _make_combat()
	# A HALF-FULL tier-6 bar, not a full tier-3 one. This instrument counts light ABSORBED, and a
	# full bar absorbs nothing: on the rail roster, where enemies are bigger targets and die faster,
	# a tier-3 camper sat at 500/500 for 94-100 % of the run, so its "decline" was the bar's
	# ceiling and the instant-refill control could not be caught (S10 Finding 1, probed in S11).
	# Tier 6 cannot evolve further and half of 2300 leaves more room than a camper can fill.
	combat.setup_player("fire",GameTuning.MAX_TIER,GameTuning.capacity(GameTuning.MAX_TIER)*0.5,[])
	var coord: Vector2i = _camp_coord(campaign) if at == Vector2i.ZERO else at
	campaign.on_enter(coord)
	combat.start_sector(campaign.sector_at(coord,0.0))
	var pilot: RefCounted = fighter if fighter != null else BotPilot.perfect(seed_value)
	var travel: Dictionary = _new_travel()
	_wire_warps(combat,campaign,pilot,travel)
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
		# Blown out of its node by an accidental warp: fly back the way it came.
		if campaign.current_sector != coord: _route(pilot,combat,campaign,travel,_bfs_first_hop(campaign,campaign.current_sector,func(c: Vector2i) -> bool: return c == coord))
		_maybe_evolve(combat,campaign)
		_step(combat,pilot,travel) # sits still when nothing to fight - a real camper's behaviour
		seconds += STEP
	combat.light_collected.disconnect(cb)
	var total: float = totals[0]+totals[1]
	var minutes: float = duration/60.0
	combat.queue_free()
	return {"light_per_minute":total/minutes,"first_half_rate":totals[0]/(minutes/2.0),"second_half_rate":totals[1]/(minutes/2.0),"travel":travel,"seconds":seconds}

func _run_pusher(seed_value: int, duration: float, fly: bool = true, secondaries: bool = true, fires: bool = true, drained: bool = false) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 500000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("fire",GameTuning.MAX_TIER,GameTuning.capacity(GameTuning.MAX_TIER)*0.5,[]) # the same start as the camper it is compared with
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO,0.0))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	pilot.fires_secondaries = secondaries
	pilot.fires = fires
	var travel: Dictionary = _new_travel()
	_wire_warps(combat,campaign,pilot,travel)
	var visited: Dictionary = {CampaignState.coord_key(Vector2i.ZERO):true}
	var totals: Array = [0.0,0.0]
	var seconds_box: Array = [0.0]
	var cb: Callable = func(_e: String,amount: float) -> void:
		if seconds_box[0] < duration*0.5: totals[0] += amount
		else: totals[1] += amount
	combat.light_collected.connect(cb)
	var seconds: float = 0.0
	var teleports: int = 0
	while seconds < duration and combat.active:
		seconds_box[0] = seconds
		var coord: Vector2i = campaign.current_sector
		visited[CampaignState.coord_key(coord)] = true
		if _node_clear(combat) and not pilot.routing() and combat.warp_phase == CombatWorld.WARP_NONE:
			var boss: Vector2i = campaign.boss_coord()
			var best: Vector2i = coord
			var best_ring: int = -1
			for dir: Vector2i in campaign.neighbours_of(coord):
				var candidate: Vector2i = coord+dir
				if candidate == boss: continue # keep pushing through regular content, not the (no-respawn) boss
				var key: String = CampaignState.coord_key(candidate)
				if visited.has(key): continue
				if CampaignState.ring(candidate) > best_ring:
					best_ring = CampaignState.ring(candidate)
					best = candidate
			if best == coord: best = _bfs_first_hop(campaign,coord,func(c: Vector2i) -> bool: return not visited.has(CampaignState.coord_key(c)) and c != boss)
			if best != coord:
				if fly: _route(pilot,combat,campaign,travel,best)
				else:
					# The pre-M18 bot (warps/min control): a teleport, no warp.
					teleports += 1
					campaign.on_enter(best)
					combat.start_sector(campaign.sector_at(best,combat.elapsed))
		# Ratio-line control seam: every node's pool pinned empty, so a fresh node pays no more than
		# a camped-out one (the camper's own seam, the other way round).
		if drained: combat.sector_energy_remaining = 0
		_maybe_evolve(combat,campaign)
		_step(combat,pilot,travel)
		seconds += STEP
	combat.light_collected.disconnect(cb)
	var total: float = totals[0]+totals[1]
	var minutes: float = duration/60.0
	var result: Dictionary = {"light_per_minute":total/minutes,"first_half_rate":totals[0]/(minutes/2.0),"second_half_rate":totals[1]/(minutes/2.0),
		"nodes_visited":visited.size(),"kills_per_minute":float(combat.run_kills)/minutes,"warps_per_minute":float(travel.warps)/minutes,
		"secondaries_per_minute":float(travel.secondary_uses)/minutes,"teleports":teleports,"travel":travel,"seconds":seconds,"survived":combat.active}
	combat.queue_free()
	return result

func _measure_camper_vs_pusher() -> Dictionary:
	var duration: float = 600.0 # ~10 simulated minutes, spec §7.3
	var camper_rates: Array[float] = []
	var pusher_rates: Array[float] = []
	var worse_second_half: int = 0
	var pushers: Array = []
	for seed_value: int in range(1,SEEDS+1):
		var camper: Dictionary = _run_camper(seed_value,duration,false)
		var pusher: Dictionary = _run_pusher(seed_value,duration)
		pushers.append(pusher)
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
	# refill does not touch - see tasks/lessons.md "a negative control covers
	# only the lines it can reach"): under instant refill the camper's own
	# within-visit decline (second half worse than first) must disappear.
	var declined: int = 0
	var instant_rates: Array[float] = []
	var finite_rates: Array[float] = []
	for seed_value: int in range(1,mini(10,SEEDS)+1):
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
	# The ratio line's own control (M18: it had none). Not the instant refill: measured at M18 the
	# pusher (300 light/min) still out-earns an instant-refill camper (176) by 1.7x, so it cannot
	# reach this line. What makes pushing pay is the fresh node's pool: pinned empty everywhere, the
	# pusher must fall under 1.5x the camper. 5 seeds x 300 s.
	var drained_rates: Array[float] = []
	for seed_value: int in range(1,mini(5,SEEDS)+1): drained_rates.append(float(_run_pusher(seed_value,300.0,true,true,true,true).light_per_minute))
	print("camper probe: pools-drained pusher light/min median %.2f max %.2f against camper median %.2f" % [_median(drained_rates),_max(drained_rates),median_camper])
	_gate_negative("camper_vs_pusher_ratio_pools_drained",t.control("every node's pool pinned empty (pusher %.1f vs camper %.1f light/min)" % [_median(drained_rates),median_camper],not (_median(drained_rates) >= median_camper*1.5)))
	result["travel"] = _measure_travel(pushers)
	return result

## --- 3. Travel at the new pace (M18) --------------------------------------
## warps/min, kills/min, secondaries/min and rim dwell are read off §2's pusher runs (the
## traveller). Accidental warps need their own FIGHTER: the camper's pilot keeps the original wall
## steer ~200 px short of the rim, so it never reaches the warp zone and could not be caught even
## at PRESS = 1 tick (measured: 0 accidental commits in 5 x 120 s). The fighter is the novice pilot
## (15-tick reaction, no dodge, 10 deg aim error) that uses the whole node and steers off the rim
## only once inside the warp zone (`wall_margin` = RIM_ZONE), fighting in the camper's setup at an
## interior (the camp node), an edge and a corner node.

## New bands, each set from the first M18 measurement (20 pusher seeds x 600 s, 328 warps) with the
## headroom stated; no band existed before (every earlier bot teleported).
## warps/min: median 1.75, worst seed 0.70, best 2.30 -> every seed >= 0.50 (29 % under the worst).
const WARPS_PER_MIN_FLOOR: float = 0.5
## kills/min: median 15.35, best 20.3 -> median >= 10 (35 % under).
const KILLS_PER_MIN_FLOOR: float = 10.0
## rim dwell (s within 60 px of the rim before an intended commit; PRESS alone is 0.20): median
## 0.283, max 0.583 -> median <= 0.40 (41 % over), max <= 0.90 (54 % over).
const DWELL_MEDIAN_MAX_S: float = 0.40
const DWELL_MAX_S: float = 0.90
## The plan's design target, not a measurement: median 0, max 1 per 60 s.
const ACCIDENTAL_MAX_PER_WINDOW: float = 1.0

## One 60 s window a run: 20 seeds x 3 nodes = 60 windows (the run time of the whole bot is a
## budget: acceptance runs inside gates.ps1's timeout).
const FIGHTER_SECONDS: float = 60.0

## The fighter policy over `seeds` seeds at node `at` (ZERO = the camp node): accidental commits
## per 60 s per seed, per 60 s window, and each one described.
func _run_fighters(seeds: int, duration: float, wall_margin: float = BotPilot.RIM_ZONE, at: Vector2i = Vector2i.ZERO) -> Dictionary:
	var rates: Array[float] = []
	var windows: Array[float] = []
	var how: Array = []
	for seed_value: int in range(1,seeds+1):
		var pilot: RefCounted = BotPilot.novice(seed_value)
		pilot.wall_margin = wall_margin
		var run: Dictionary = _run_camper(seed_value,duration,false,pilot,at)
		rates.append(float(run.travel.accidental)*60.0/maxf(1.0,float(run.seconds)))
		windows.append_array(_accidental_windows(run.travel,duration))
		for line: String in run.travel.accidental_how: how.append("seed %d: %s" % [seed_value,line])
	return {"rates":rates,"windows":windows,"how":how}

## The fighter at an interior node (the camp node, ring 1), an edge node and a corner node (an edge
## or corner rim folds its out-of-bounds arcs into neighbours), pooled; plus, not gated, the same
## fighter ignoring the rim altogether (wall_margin 0).
func _measure_fighters() -> Dictionary:
	var edge: int = CampaignState.new().level_radius()
	var places: Dictionary = {"interior":Vector2i.ZERO,"edge":Vector2i(edge,0),"corner":Vector2i(edge,-edge)}
	var rates: Array[float] = []
	var windows: Array[float] = []
	var by_place: Dictionary = {}
	for place: String in places:
		var fighters: Dictionary = _run_fighters(SEEDS,FIGHTER_SECONDS,BotPilot.RIM_ZONE,places[place])
		rates.append_array(fighters.rates)
		windows.append_array(fighters.windows)
		by_place[place] = {"coord":"%s" % places[place],"per_minute_median":_median(fighters.rates),"per_minute_max":_max(fighters.rates),"max_per_60s":_max(fighters.windows)}
		for line: String in fighters.how: print("fighter accidental warp (%s): %s" % [place,line])
	var oblivious: Dictionary = _run_fighters(mini(5,SEEDS),FIGHTER_SECONDS,0.0)
	print("fighter probe: pooled median %.2f/min, max %d per 60 s; by node %s; rim-oblivious median %.2f/min max %d per 60 s" % [_median(rates),int(_max(windows)),JSON.stringify(by_place),_median(oblivious.rates),int(_max(oblivious.windows))])
	return {"rates":rates,"windows":windows,"by_place":by_place,"oblivious":oblivious}

func _measure_travel(pushers: Array) -> Dictionary:
	var warps_per_min: Array[float] = []
	var kills_per_min: Array[float] = []
	var secondaries_per_min: Array[float] = []
	var route_s: Array[float] = []
	var dwell: Array[float] = []
	var fighters: Dictionary = _measure_fighters()
	var fighter_rates: Array[float] = fighters.rates
	var fighter_windows: Array[float] = fighters.windows
	var by_place: Dictionary = fighters.by_place
	var oblivious: Dictionary = fighters.oblivious
	var pusher_accidental: Array[float] = []
	var route_failures: int = 0
	var pusher_died: int = 0
	var secondary_seeds: int = 0
	for pusher: Dictionary in pushers:
		warps_per_min.append(pusher.warps_per_minute)
		kills_per_min.append(pusher.kills_per_minute)
		secondaries_per_min.append(pusher.secondaries_per_minute)
		if pusher.secondaries_per_minute > 0.0: secondary_seeds += 1
		route_s.append_array(pusher.travel.route_s)
		dwell.append_array(pusher.travel.dwell)
		route_failures += int(pusher.travel.route_failures)
		pusher_accidental.append(float(pusher.travel.accidental))
		if not pusher.survived: pusher_died += 1
		for line: String in pusher.travel.accidental_how: print("pusher accidental warp: %s" % line)
	var result: Dictionary = {
		"warps_per_minute_median":_median(warps_per_min),"warps_per_minute_min":_min(warps_per_min),"warps_per_minute_max":_max(warps_per_min),
		"kills_per_minute_median":_median(kills_per_min),"kills_per_minute_max":_max(kills_per_min),
		"secondaries_per_minute_median":_median(secondaries_per_min),"secondaries_per_minute_max":_max(secondaries_per_min),"secondaries_fired_seeds_of":"%d/%d" % [secondary_seeds,pushers.size()],
		"crossing_s_median":_median(route_s),"crossing_s_max":_max(route_s),"route_failures":route_failures,"pusher_died_of":"%d/%d" % [pusher_died,pushers.size()],
		"rim_dwell_s_median":_median(dwell),"rim_dwell_s_max":_max(dwell),"rim_dwell_samples":dwell.size(),"rim_dwell_m0_baseline":"none: every M0 bot teleported",
		"fighter_accidental_per_minute_median":_median(fighter_rates),"fighter_accidental_per_minute_max":_max(fighter_rates),"fighter_accidental_max_per_60s":_max(fighter_windows),"fighter_windows":fighter_windows.size(),"fighter_by_node":by_place,
		"rim_oblivious_fighter_accidental_per_minute_median":_median(oblivious.rates),"rim_oblivious_fighter_accidental_per_minute_max":_max(oblivious.rates),"rim_oblivious_fighter_max_per_60s":_max(oblivious.windows),
		"pusher_accidental_warps_median":_median(pusher_accidental),"pusher_accidental_warps_max":_max(pusher_accidental),
	}
	print("travel probe: ",JSON.stringify(result))
	var worst_warps: float = result.warps_per_minute_min
	_gate("warps_per_minute",t.check(worst_warps >= WARPS_PER_MIN_FLOOR and route_failures == 0,"Every pusher seed warps at least %.2f/min (median %.2f, worst %.2f, max %.2f; %d failed routes)" % [WARPS_PER_MIN_FLOOR,_median(warps_per_min),worst_warps,_max(warps_per_min),route_failures]))
	_gate("kills_per_minute",t.check(_median(kills_per_min) >= KILLS_PER_MIN_FLOOR,"Pusher kills/min median %.1f >= %.1f (max %.1f)" % [_median(kills_per_min),KILLS_PER_MIN_FLOOR,_max(kills_per_min)]))
	_gate("secondaries_fired",t.check(secondary_seeds == pushers.size(),"The bot fires its secondaries in every pusher seed (%d/%d, median %.1f/min)" % [secondary_seeds,pushers.size(),_median(secondaries_per_min)]))
	_gate("rim_dwell_median",t.check(not dwell.is_empty() and _median(dwell) <= DWELL_MEDIAN_MAX_S,"Rim dwell before a commit: median %.3fs <= %.2fs (%d warps)" % [_median(dwell),DWELL_MEDIAN_MAX_S,dwell.size()]))
	_gate("rim_dwell_max",t.check(not dwell.is_empty() and _max(dwell) <= DWELL_MAX_S,"Rim dwell before a commit: max %.3fs <= %.2fs" % [_max(dwell),DWELL_MAX_S]))
	_gate("accidental_warps_median",t.check(_median(fighter_rates) == 0.0,"Fighter accidental warps: median %.2f per 60 s over %d runs (%d seeds at an interior, an edge and a corner node; target 0)" % [_median(fighter_rates),fighter_rates.size(),SEEDS]))
	_gate("accidental_warps_max",t.check(_max(fighter_windows) <= ACCIDENTAL_MAX_PER_WINDOW,"Fighter accidental warps: max %d in any 60 s window of %d (target <= %d)" % [int(_max(fighter_windows)),fighter_windows.size(),int(ACCIDENTAL_MAX_PER_WINDOW)]))
	_measure_travel_controls()
	return result

func _measure_travel_controls() -> void:
	var control_seeds: int = mini(5,SEEDS)
	# warps/min: the pre-M18 bot, which teleports - the same walk, no warp.
	var teleport_warps: Array[float] = []
	var no_secondary: Array[float] = []
	var no_fire_kills: Array[float] = []
	for seed_value: int in range(1,control_seeds+1):
		teleport_warps.append(float(_run_pusher(seed_value,120.0,false).warps_per_minute))
		no_secondary.append(float(_run_pusher(seed_value,60.0,true,false).secondaries_per_minute))
		no_fire_kills.append(float(_run_pusher(seed_value,60.0,true,true,false).kills_per_minute))
	_gate_negative("warps_per_minute_teleporting_bot",t.control("bot teleports between nodes (warps/min worst %.2f)" % _min(teleport_warps),_min(teleport_warps) < WARPS_PER_MIN_FLOOR))
	_gate_negative("secondaries_off",t.control("secondaries off (%.1f/min)" % _max(no_secondary),_max(no_secondary) == 0.0))
	_gate_negative("kills_per_minute_fire_disabled",t.control("pusher with fire disabled (kills/min median %.1f)" % _median(no_fire_kills),_median(no_fire_kills) < KILLS_PER_MIN_FLOOR))
	# Rim dwell: a PRESS stretched to 1.0 s must show up as dwell past both bands.
	GameTuning.set_feel("warp.push_s",1.0)
	var long_dwell: Array[float] = []
	for seed_value: int in range(1,control_seeds+1): long_dwell.append_array(_run_pusher(seed_value,120.0).travel.dwell)
	GameTuning.reset_feel()
	_gate_negative("rim_dwell_median_press_1s",t.control("PRESS = 1.0 s (dwell median %.3fs)" % _median(long_dwell),_median(long_dwell) > DWELL_MEDIAN_MAX_S))
	_gate_negative("rim_dwell_max_press_1s",t.control("PRESS = 1.0 s (dwell max %.3fs)" % _max(long_dwell),_max(long_dwell) > DWELL_MAX_S))
	# Accidental warps (the plan's control): PRESS = 1 tick. A fighter that grazes the rim now warps.
	GameTuning.set_feel("warp.push_s",STEP)
	var tick: Dictionary = _run_fighters(control_seeds,120.0)
	var tick_rates: Array[float] = tick.rates
	var tick_windows: Array[float] = tick.windows
	GameTuning.reset_feel()
	# The second control is the fix itself undone: the pre-M18 60 px press zone, at the edge node.
	_engage_band = CombatWorld.WARP_REARM_ZONE
	var zone: Dictionary = _run_fighters(control_seeds,120.0,BotPilot.RIM_ZONE,Vector2i(CampaignState.new().level_radius(),0))
	_engage_band = -1.0
	print("accidental control probe: 60 px press zone at the edge -> per-minute ",zone.rates," windows ",zone.windows)
	_gate_negative("accidental_warps_median_60px_zone",t.control("pre-M18 60 px press zone (fighter accidental median %.2f/60 s)" % _median(zone.rates),_median(zone.rates) > 0.0))
	_gate_negative("accidental_warps_max_60px_zone",t.control("pre-M18 60 px press zone (fighter accidental max %d per 60 s)" % int(_max(zone.windows)),_max(zone.windows) > ACCIDENTAL_MAX_PER_WINDOW))
	print("accidental control probe: PRESS 1 tick -> per-minute ",tick_rates," windows ",tick_windows)
	_gate_negative("accidental_warps_median_press_1_tick",t.control("PRESS = 1 tick (fighter accidental median %.2f/60 s)" % _median(tick_rates),_median(tick_rates) > 0.0))
	_gate_negative("accidental_warps_max_press_1_tick",t.control("PRESS = 1 tick (fighter accidental max %d per 60 s)" % int(_max(tick_windows)),_max(tick_windows) > ACCIDENTAL_MAX_PER_WINDOW))

## --- 4. Time to boss (M18) --------------------------------------------------
## A new player's session from the origin to the boss node, flying every hop: the BFS first hop
## toward the boss once the node is clear, evolving as it goes, a death rebooting at the origin
## (the session goes on; a fresh seed may move the boss). Capped; a run that never arrives is a
## failure, counted, and enters the median and the max as infinite (lessons.md).

const BOSS_CAP_S: float = 600.0
## Measured at M18 over 20 seeds: 20/20 arrive, median 139.3 s, worst 337.0 s, 6 warps median, 0-1
## deaths -> median <= 180 s (29 % over), worst <= 450 s (34 % over).
const BOSS_MEDIAN_MAX_S: float = 180.0
const BOSS_MAX_S: float = 450.0
const BOSS_SLOW_PRESS_S: float = 60.0

func _run_to_boss(seed_value: int, cap_seconds: float, confirm: bool = true) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.world_seed = 700000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	var travel: Dictionary = _new_travel()
	_wire_warps(combat,campaign,pilot,travel,confirm)
	var seconds: float = 0.0
	var deaths: int = 0
	while seconds < cap_seconds and campaign.current_sector != campaign.boss_coord():
		if not combat.active:
			deaths += 1
			pilot.route = Vector2i.ZERO
			campaign.on_death()
			combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
			campaign.on_enter(Vector2i.ZERO)
			combat.start_sector(campaign.sector_at(Vector2i.ZERO,combat.elapsed))
			continue
		if _node_clear(combat):
			var boss: Vector2i = campaign.boss_coord()
			_route(pilot,combat,campaign,travel,_bfs_first_hop(campaign,campaign.current_sector,func(c: Vector2i) -> bool: return c == boss))
		_maybe_evolve(combat,campaign)
		_step(combat,pilot,travel)
		seconds += STEP
	var reached: bool = campaign.current_sector == campaign.boss_coord()
	if not reached: print("time to boss: seed %d did not arrive - at %s, boss %s, %d warps, %d accidental, %d failed routes, %d deaths, tier %d, %d enemies left, %d pickups, routing %s" % [seed_value,campaign.current_sector,campaign.boss_coord(),travel.warps,travel.accidental,travel.route_failures,deaths,combat.player_tier,combat.remaining_enemies(),combat.pickups.size(),pilot.routing()])
	var result: Dictionary = {"seconds":snappedf(seconds,0.01),"reached":reached,"deaths":deaths,"warps":int(travel.warps),"tier":combat.player_tier,"travel":travel}
	combat.queue_free()
	return result

## Times with each failed run as INF, so a failure can only make the median or the max worse.
func _boss_times(runs: Array) -> Array[float]:
	var times: Array[float] = []
	for run: Dictionary in runs: times.append(float(run.seconds) if run.reached else INF)
	return times

func _measure_time_to_boss() -> Dictionary:
	var runs: Array = []
	var times: Array[float] = []
	var deaths: Array[float] = []
	var warps: Array[float] = []
	var dwell: Array[float] = []
	var accidental: Array[float] = []
	var reached: int = 0
	for seed_value: int in range(1,SEEDS+1):
		var run: Dictionary = _run_to_boss(seed_value,BOSS_CAP_S)
		runs.append(run)
		deaths.append(float(run.deaths))
		warps.append(float(run.warps))
		dwell.append_array(run.travel.dwell)
		accidental.append(float(run.travel.accidental))
		for how: String in run.travel.accidental_how: print("time to boss: seed %d accidental warp %s" % [seed_value,how])
		if run.reached:
			reached += 1
			times.append(run.seconds)
	var result: Dictionary = {"reached_of":"%d/%d" % [reached,SEEDS],"median_s_reached_only":_median(times),"max_s_reached_only":_max(times),
		"deaths_median":_median(deaths),"deaths_max":_max(deaths),"warps_median":_median(warps),"warps_max":_max(warps),
		"rim_dwell_s_median":_median(dwell),"rim_dwell_s_max":_max(dwell),"accidental_median":_median(accidental),"accidental_max":_max(accidental)}
	print("boss probe: ",JSON.stringify(result))
	var all_times: Array[float] = _boss_times(runs)
	_gate("time_to_boss_all_reach",t.check(reached == SEEDS,"Every seed reaches the boss node within %.0fs (%d/%d)" % [BOSS_CAP_S,reached,SEEDS]))
	_gate("time_to_boss_median",t.check(_median(all_times) <= BOSS_MEDIAN_MAX_S,"Time to boss median %.1fs <= %.0fs (a failed run counts as infinite: %d/%d reached)" % [_median(all_times),BOSS_MEDIAN_MAX_S,reached,SEEDS]))
	_gate("time_to_boss_max",t.check(_max(all_times) <= BOSS_MAX_S,"Time to boss worst %.1fs <= %.0fs" % [_max(all_times),BOSS_MAX_S]))
	# Controls. All-reach: no node swap behind the warp (the membrane springs the ship back).
	var sprung: int = 0
	for seed_value: int in range(1,mini(3,SEEDS)+1):
		if _run_to_boss(seed_value,60.0,false).reached: sprung += 1
	_gate_negative("time_to_boss_no_swap",t.control("warp without a node swap (%d/3 reached)" % sprung,sprung < 3))
	# Median and max: travel slowed until it shows - every hop's PRESS held BOSS_SLOW_PRESS_S.
	# (The pre-M9 warp - 0.30 s PRESS, ~1.02 s locked - is ~1 s a hop over ~6 hops, inside the
	# node-clearing noise these bands carry; this control proves the lines can fail, not that
	# they resolve one second.)
	GameTuning.set_feel("warp.push_s",BOSS_SLOW_PRESS_S)
	var slow_runs: Array = []
	# Capped just past the max band: a run still going there has already failed both lines.
	for seed_value: int in range(1,mini(3,SEEDS)+1): slow_runs.append(_run_to_boss(seed_value,BOSS_MAX_S+10.0))
	GameTuning.reset_feel()
	var slow_times: Array[float] = _boss_times(slow_runs)
	_gate_negative("time_to_boss_median_slow_travel",t.control("PRESS %.0f s a hop (median %.1fs)" % [BOSS_SLOW_PRESS_S,_median(slow_times)],_median(slow_times) > BOSS_MEDIAN_MAX_S))
	_gate_negative("time_to_boss_max_slow_travel",t.control("PRESS %.0f s a hop (max %.1fs)" % [BOSS_SLOW_PRESS_S,_max(slow_times)],_max(slow_times) > BOSS_MAX_S))
	return result

## --- 5. Frictionless death: death-to-flying-again at the M12 pace (spec §7.4/§27) -

func _death_to_flying_ms(i: int, reboot_s: float = -1.0) -> float:
	var explored: int = i % 4
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	SaveService.storage_root = "user://acceptance-death-%d-%d" % [i,Time.get_ticks_usec()]
	app._new_game(false)
	app.combat.set_physics_process(false)
	if reboot_s >= 0.0: app.run_controller.death_reboot_s = reboot_s
	# Setup only, not travel: the death is measured from nodes 0-3 hops out. `_enter_sector` is the
	# app's own entry and this test needs a specific node, not a flight (M18 keeps it on purpose).
	for k: int in range(explored):
		var dirs: Array[Vector2i] = app.campaign.neighbours_of(app.campaign.current_sector)
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
	await app._stop_audio()
	app.queue_free()
	await process_frame
	return elapsed_s*1000.0

## Restated at M18 (retired: < 2000 ms median and max, spec §7.4's ceiling from before M12). M0
## measured 558 / 683 ms; M12's automatic 0.40 s reboot measures 416.7 ms median and max over 20
## seeds (it no longer waits for a press). The plan's pace target is < 0.5 s: median < 500 ms (20 %
## headroom), max < 600 ms (44 %).
const DEATH_MEDIAN_MAX_MS: float = 500.0
const DEATH_MAX_MS: float = 600.0

func _measure_death_to_flying() -> Dictionary:
	var times_ms: Array[float] = []
	for i: int in range(SEEDS): times_ms.append(await _death_to_flying_ms(i))
	var result: Dictionary = {"death_to_flying_ms_median":_median(times_ms),"death_to_flying_ms_max":_max(times_ms)}
	_gate("death_to_flying_median",t.check(_median(times_ms) < DEATH_MEDIAN_MAX_MS,"Median death-to-flying-again is under %.0fms (got %.0fms)" % [DEATH_MEDIAN_MAX_MS,_median(times_ms)]))
	_gate("death_to_flying_max",t.check(_max(times_ms) < DEATH_MAX_MS,"Max death-to-flying-again over %d seeds is under %.0fms (got %.0fms)" % [SEEDS,DEATH_MAX_MS,_max(times_ms)]))
	# Controls (M18: this instrument had none): the pre-M12 wait, a reboot 2.5 s after the death.
	var slow_ms: Array[float] = []
	for i: int in range(mini(3,SEEDS)): slow_ms.append(await _death_to_flying_ms(i,2.5))
	_gate_negative("death_to_flying_median_slow_reboot",t.control("reboot 2.5 s after death (median %.0fms)" % _median(slow_ms),not (_median(slow_ms) < DEATH_MEDIAN_MAX_MS)))
	_gate_negative("death_to_flying_max_slow_reboot",t.control("reboot 2.5 s after death (max %.0fms)" % _max(slow_ms),not (_max(slow_ms) < DEATH_MAX_MS)))
	return result

## --- 6. Chasing a light type works (spec §8/§27 M5) ------------------------
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

func _run_chase(seed_value: int, prefer: bool, cap_seconds: float, unlock_wired: bool = true) -> Dictionary:
	var campaign: CampaignState = Campaign.new()
	campaign.configure_mode("campaign")
	campaign.level = 5 # reveals every element into the POOL (spec §8 table); unlocked still starts [lightning] only
	campaign.world_seed = 600000+seed_value
	var combat: CombatWorld = _make_combat()
	combat.setup_player("neutral",1,GameTuning.START_LIGHT,[])
	# Mirrors main.gd::_on_energy's unlock call - nothing else drives campaign.unlocked in this standalone test.
	var unlock_cb: Callable = func(element: String,amount: float) -> void: if unlock_wired: campaign.unlock_element(element,amount)
	combat.light_collected.connect(unlock_cb)
	campaign.on_enter(Vector2i.ZERO)
	combat.start_sector(campaign.sector_at(Vector2i.ZERO,0.0))
	var pilot: RefCounted = BotPilot.perfect(seed_value)
	var travel: Dictionary = _new_travel()
	_wire_warps(combat,campaign,pilot,travel)
	var visited: Dictionary = {CampaignState.coord_key(Vector2i.ZERO):true}
	var seconds: float = 0.0
	while seconds < cap_seconds and not (CHASE_TARGET in campaign.unlocked) and combat.active:
		var coord: Vector2i = campaign.current_sector
		visited[CampaignState.coord_key(coord)] = true
		if _node_clear(combat) and not pilot.routing() and combat.warp_phase == CombatWorld.WARP_NONE:
			var chosen: Vector2i = coord
			if prefer: chosen = _chase_step(campaign,coord,visited,3)
			if chosen == coord: chosen = _indifferent_step(campaign,coord,visited)
			if chosen != coord: _route(pilot,combat,campaign,travel,chosen)
		_maybe_evolve(combat,campaign)
		_step(combat,pilot,travel)
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
	for dir: Vector2i in campaign.neighbours_of(coord):
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
		for dir: Vector2i in campaign.neighbours_of(current):
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
		for dir: Vector2i in campaign.neighbours_of(current):
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
	# The unlock-count line's own control (M18: it had none; preference off on both sides ties, and a
	# tie passes ">="): the chaser's light no longer reaches `unlock_element`, first 5 seeds.
	var cut: Array = []
	for seed_value: int in range(1,mini(5,SEEDS)+1): cut.append(_run_chase(seed_value,true,240.0,false))
	var blind: Dictionary = _chase_score(cut,indifferent_runs.slice(0,cut.size()))
	_gate_negative("light_chasing_unlocks_unlock_cut",t.control("chaser's unlock hook cut (%d vs %d of %d)" % [blind.a_unlocked,blind.b_unlocked,cut.size()],not (blind.a_unlocked >= blind.b_unlocked and blind.a_unlocked > 0)))
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

func _wants(section: String) -> bool: return _only.is_empty() or section in _only

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): _only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--seeds="): SEEDS = int(argument.trim_prefix("--seeds="))
	t = Harness.new("ACCEPTANCE V0.3")
	print("acceptance roster: ", ShipCatalog.use_cmdline_root())
	var results: Dictionary = {}
	var watch: int = Time.get_ticks_msec()
	if _wants("evolution"): results["first_evolution"] = _measure_first_evolution()
	print("section seconds: evolution %.1f" % ((Time.get_ticks_msec()-watch)/1000.0))
	watch = Time.get_ticks_msec()
	if _wants("camper"): results["camper_vs_pusher"] = _measure_camper_vs_pusher()
	print("section seconds: camper+travel %.1f" % ((Time.get_ticks_msec()-watch)/1000.0))
	watch = Time.get_ticks_msec()
	if not _only.is_empty() and "fighters" in _only: _measure_fighters() # dev seam: the fighter alone
	if _wants("boss"): results["time_to_boss"] = _measure_time_to_boss()
	print("section seconds: boss %.1f" % ((Time.get_ticks_msec()-watch)/1000.0))
	watch = Time.get_ticks_msec()
	if _wants("death"): results["death_to_flying"] = await _measure_death_to_flying()
	print("section seconds: death %.1f" % ((Time.get_ticks_msec()-watch)/1000.0))
	watch = Time.get_ticks_msec()
	if _wants("chase"): results["light_chasing"] = _measure_light_chasing()
	print("section seconds: chase %.1f" % ((Time.get_ticks_msec()-watch)/1000.0))
	if _only.is_empty():
		var dir: DirAccess = DirAccess.open("res://")
		if dir != null and not dir.dir_exists("artifacts"): dir.make_dir("artifacts")
		var file: FileAccess = FileAccess.open(OUT_PATH,FileAccess.WRITE)
		file.store_string(JSON.stringify(results,"\t"))
		file.close()
	print("ACCEPTANCE RESULTS ",JSON.stringify(results))
	t.finish(self)
