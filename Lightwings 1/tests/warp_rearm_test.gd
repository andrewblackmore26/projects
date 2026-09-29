extends SceneTree
## Modernization M18: the warp's re-arm latch (`CombatWorld.warp_rearm`). A direction held through a
## warp must not warp the ship again the moment ARRIVAL ends. At an edge node the out-of-bounds arc
## folds into a neighbour and the arrival lands 44 px inside a rim point where the held input is
## still > 0.5 outward: before the latch, holding east at (R,0) bounced between two nodes (8 warps
## in 6 s; NE at a corner, 5).
##
##   edge     hold east from the centre of (R,0) for 6 s -> exactly 1 warp (control: latch off -> > 1)
##   corner   hold NE from the centre of (R,-R) for 6 s -> exactly 1 warp (control: latch off -> > 1)
##   re-arm   release for 5 ticks after arriving, press again -> the second press warps
##            (control: the same press never released -> it does not)
##   crossing hold east from the centre of the origin for 9 s -> 2 warps: leaving the rim zone
##            re-arms, so crossing a node and pressing the far rim is never blocked; latch off at the
##            same interior node gives the same count (the latch acts only at the rim it arrived on)

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("WARP REARM")
	GameTuning.reset_feel()
	var edge: Vector2i = Vector2i(CampaignState.new().level_radius(), 0)
	var corner: Vector2i = Vector2i(edge.x, -edge.x)
	var held: int = _hold(edge, Vector2.RIGHT, true).warps
	t.check(held == 1, "Holding east at the edge node %s for 6 s warps exactly once (%d)" % [edge, held])
	var bounced: int = _hold(edge, Vector2.RIGHT, false).warps
	t.control("re-arm latch off at the edge (%d warps in 6 s)" % bounced, bounced > 1)
	var ne: Vector2 = Vector2(1, -1).normalized()
	var held_corner: int = _hold(corner, ne, true).warps
	t.check(held_corner == 1, "Holding NE at the corner node %s for 6 s warps exactly once (%d)" % [corner, held_corner])
	var bounced_corner: int = _hold(corner, ne, false).warps
	t.control("re-arm latch off at the corner (%d warps in 6 s)" % bounced_corner, bounced_corner > 1)
	var rearmed: int = _hold(edge, Vector2.RIGHT, true, 5).warps
	t.check(rearmed >= 2, "Releasing for 5 ticks after the arrival re-arms: pressing again warps (%d warps)" % rearmed)
	t.control("the same press never released (%d warps)" % held, held < 2)
	var crossing: int = _hold(Vector2i.ZERO, Vector2.RIGHT, true, 0, 9.0).warps
	var crossing_off: int = _hold(Vector2i.ZERO, Vector2.RIGHT, false, 0, 9.0).warps
	t.check(crossing == 2, "Holding east from the origin's centre crosses and warps again at the far rim (%d warps in 9 s)" % crossing)
	t.check(crossing_off == crossing, "The latch changes nothing about an interior crossing: latch off gives the same count (%d vs %d)" % [crossing_off, crossing])
	print("rearm: warps edge %d (latch off %d), corner %d (latch off %d), release-and-press %d, crossing %d (latch off %d)" % [held, bounced, held_corner, bounced_corner, rearmed, crossing, crossing_off])
	GameTuning.reset_feel()
	await process_frame
	t.finish(self)

## A calm copy of the node at `coord` (no enemies, waves or pickups), so only the warp acts.
func _calm(campaign: CampaignState, coord: Vector2i) -> Dictionary:
	var sector: Dictionary = campaign.sector_at(coord)
	sector.enemy_hulls = []
	sector.elite_hulls = []
	sector.waves = []
	sector.starter_pickups = []
	sector.boss_hull = ""
	return sector

## From the centre of `coord`, holds `direction` for 6 s through RunController's own swap. With
## `release_ticks` > 0 the input lets go for that many ticks right after the first arrival.
func _hold(coord: Vector2i, direction: Vector2, latch: bool, release_ticks: int = 0, seconds: float = 6.0) -> Dictionary:
	var campaign := CampaignState.new()
	campaign.on_enter(coord)
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2.ZERO)
	w.warp_rearm_enabled = latch
	w.start_sector(_calm(campaign, coord))
	w.player_position = w.arena.center
	var state: Dictionary = {"warps": 0, "arrivals": 0}
	w.warp_committed.connect(func(dir: Vector2i) -> void:
		state.warps += 1
		var destination: Vector2i = campaign.current_sector + dir
		campaign.on_enter(destination)
		w.start_sector(_calm(campaign, destination))
		w.confirm_warp_swap())
	w.warp_arrived.connect(func() -> void: state.arrivals += 1)
	var released: int = 0
	for i: int in range(roundi(seconds / STEP)):
		var letting_go: bool = release_ticks > 0 and state.arrivals >= 1 and released < release_ticks and w.warp_phase != CombatWorld.WARP_ARRIVAL
		if letting_go: released += 1
		w.command.movement = Vector2.ZERO if letting_go else direction
		w.command.aim = direction
		w._physics_process(STEP)
	w._clear_encounter()
	w.free()
	return state
