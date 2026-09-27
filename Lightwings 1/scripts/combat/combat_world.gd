class_name CombatWorld
extends Node2D
## World-space deterministic combat; camera and menus are external consumers.
signal energy_collected(element: String, amount: int)
signal light_collected(element: String, raw_amount: float)
signal player_died
signal player_regressed(from_tier: int, to_tier: int)
signal sector_cleared
signal rival_reward(component: String, mirror_root: String)
signal boss_defeated(level_id: String)
signal event_message(text: String)
signal attack_performed(element: String, ability: String)
signal shot_fired(position: Vector2, element: String, ability: String)
signal shot_audio_requested(position: Vector2, element: String, ability: String, actor_id: int)
signal boundary_contact(position: Vector2)
## Spec §12: fired the instant push depth crosses the threshold (control
## locks, projectiles discarded, player invulnerable). The listener (today
## `main.gd`, eventually `run_controller.gd`) is expected to swap the sector
## SYNCHRONOUSLY inside its handler (call `start_sector` then
## `confirm_warp_swap()`) - GDScript signal emission is synchronous, so this
## happens before `_warp_commit` returns. If nothing calls
## `confirm_warp_swap()` by the end of the travel phase, the warp springs
## back instead of deadlocking (see `_update_warp`).
signal warp_committed(direction: Vector2i)
signal warp_arrived
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const CombatAI = preload("res://scripts/combat/combat_ai.gd")
const BulletCanvas = preload("res://scripts/combat/combat_canvas.gd")
const TrailCanvas = preload("res://scripts/combat/trail_canvas.gd")
const FxCanvas = preload("res://scripts/combat/fx_canvas.gd")
const PickupCanvas = preload("res://scripts/combat/pickup_canvas.gd")
const Arena = preload("res://scripts/combat/circular_arena.gd")
const FX = preload("res://scripts/combat/combat_fx.gd")
const ELEMENTS: Array[String] = Elements.INDEX_ORDER
const COLORS: Array[Color] = Elements.RIM_BY_INDEX
const PLAYER_COLOR: Color = Elements.PLAYER_RIM
const MAX_PICKUPS: int = 400
const MAX_ACTORS: int = 100
const MAX_DRONES: int = 80
const DECODED_CACHE_LIMIT: int = 32
var arena = Arena.new()
var bounds: Rect2:
 get: return arena.bounds
 set(value): arena.bounds=value
var light_total: float = 40.0
var hull_id: String = "player_seed"
var hull_history: Array[String] = ["player_seed"]
var absorption: Dictionary = {}
var player_hp: float:
 get: return light_total
 set(value): light_total=value
var player_energy: float:
 get: return light_total
 set(value): light_total=value
var player_max_hp: float:
 get: return GameTuning.capacity(player_tier,max_player_tier)
var player_position: Vector2 = Vector2(896,560):
 set(value):
  player_position=value
  if not player.is_empty(): player.pos=value
var max_player_tier: int = GameTuning.MAX_TIER
var player_tier: int = 1
var player_element: String = "neutral"
var player_stolen: Array = [] # Deprecated read-only empty compatibility surface.
var player_invulnerable: float = 0.0
var reshape_remaining: float = 0.0
var elapsed: float = 0.0
var active: bool = true
var bullet_count: int = 0
var enemies: Array = []
var pickups: Array = []
var drones: Array = []
## Pooled, batched attack/impact effects (spec §19/§23 "not nodes", P8). The
## single choke point for creating one is `fx.emit(...)`; nothing else builds
## an entry in `fx`'s SoA arrays directly. `_fx_rng` is FX's OWN RNG (never
## `_rng`, the sim's) so a fragment spread can never perturb sim state -
## `tests/combat_fx_test.gd` asserts a sim trace is identical with FX draws
## enabled and disabled.
var fx: CombatFX = FX.new()
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var telegraphs: Array = []
var viruses: Array = []
var clouds: Array = []
var beams: Array = []
var sector: Dictionary = {}
var player: Dictionary = {}
var bullets: LightBulletPool = Pool.new()
var command: ShipCommand = ShipCommand.new()
var _broadphase: CombatBroadphase = CombatBroadphase.new()
var actors_by_id: Dictionary = {}
var next_actor_id: int = 1
var cleared_emitted: bool = false
var contact_timer: float = 0.0
var tick: int = 0
var benchmark_mode: bool = false
var benchmark_target: int = 0
var benchmark_stats: Dictionary = {}
var simulation_ms: float = 0.0
var profile_sections: bool = false
var section_ms: Dictionary = {}
## Activations per ability id since this world was made. Instrumentation only: bot runs read it to
## prove every mounted weapon actually fires in play (lessons: a mechanic can pass its unit test and
## never happen).
var ability_events: Dictionary = {}
## Live black-hole shots. The pull pass walks the bullet list only while this is above zero, so the
## hot loop pays nothing when no such weapon is in the fight.
var black_holes: int = 0
var visuals_enabled: bool = true
var show_element_labels: bool = false
## Spec §24: "Damage numbers off by default." Set from main.gd's settings.
var show_damage_numbers: bool = false
var sector_energy_remaining: int = 10000
var sector_energy_paid: int = 0
var sector_cache: Dictionary = {}
var encounter_records: Dictionary = {}
var encounter_epoch: int = -1
var debris: Array = [] # P4a detachment: each entry is one destroyed circle's subtree, see `_destroy_part`
var _ability_cache: Dictionary = {}
var _bullet_canvas: Node2D
var trail_pool: TrailPool = TrailPool.new()
var _trail_canvas: Node2D
## Batched MultiMesh draw for `fx` (P9 perf pass): see `fx_canvas.gd` header.
## Synced once per tick from `_physics_process`, same shape as `_bullet_canvas`.
var _fx_canvas: Node2D
## Batched MultiMesh draw for pickups (see `pickup_canvas.gd`): the immediate per-pickup arcs it
## replaced measured ~17 ms of frame time at the 400-pickup cap.
var _pickup_canvas: Node2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Test-only negative controls for the human-like AI limits (spec §14) - never
## toggled by gameplay code. `enemy_ai_test.gd` flips these to prove the
## reaction-delay/aim-error instruments can actually fail.
var ai_reaction_disabled: bool = false
var ai_aim_error_disabled: bool = false
## Play-census negative control (spec plan: "a mechanic can pass its unit test
## and never happen in play"): every enemy fire path funnels through
## `_fire_primary`/`_use_secondary`/`_update_guns`, so gating those three is
## the single choke point that makes every archetype's fire count (and every
## enemy-only component event, which all fire from inside these) go to 0.
var ai_firing_disabled: bool = false
var _pickup_collectors: Array = []
var _shot_source: Dictionary={"id":-1,"faction":-1,"element":"fire"}
var _last_dt: float = 1.0/60.0
## --- Dash (spec §13/§26, plan P6 item 2) ------------------------------
const DASH_BURST_SECONDS: float = 0.18
const DASH_COOLDOWN_SECONDS: float = 1.2
const DASH_SPEED_MULT: float = 3.0
## --- The warp (spec §12, plan P6 item 5) -------------------------------
## Phases in order; WARP_FADE replaces ZOOM_IN..ZOOM_OUT wholesale when the
## accessibility "reduced warp" option is on (0.25 s fade, no zoom, no streaks).
enum {WARP_NONE=0, WARP_PUSH=1, WARP_ZOOM_IN=2, WARP_TRAVEL=3, WARP_ARRIVAL=4, WARP_ZOOM_OUT=5, WARP_FADE=6}
const WARP_PUSH_SECONDS: float = 0.30
const WARP_ZOOM_IN_SECONDS: float = 0.12
const WARP_TRAVEL_SECONDS: float = 0.55
const WARP_ARRIVAL_SECONDS: float = 0.15
const WARP_ZOOM_OUT_SECONDS: float = 0.20
const WARP_REDUCED_SECONDS: float = 0.25
const WARP_PUSH_SPEED_SCALE: float = 0.4
const WARP_PUSH_RELEASE_RATE: float = 2.0 # spring-back drains twice as fast as push fills
var warp_phase: int = WARP_NONE
var warp_progress: float = 0.0
var warp_direction: Vector2i = Vector2i.ZERO
## Accessibility option (spec §12): settable externally (main.gd options).
var warp_reduced: bool = false
var warp_commit_speed: float = 0.0
var warp_entry_speed: float = 0.0
## Seconds the most recently completed warp actually held control locked for
## (zoom-in..zoom-out or the reduced fade) - read by `tests/warp_test.gd`
## instead of asserting the constants sum to what the spec says.
var warp_locked_measured: float = 0.0
var _warp_push_depth: float = 0.0
var _warp_timer: float = 0.0
var _warp_locked_accum: float = 0.0
var _warp_swap_done: bool = false
## --- Pace (spec §7, plan P7) -------------------------------------------
## Decay suppression counts down from GameTuning.DECAY_SUPPRESSION_SECONDS on
## every kill or absorb; light only bleeds while this is at 0.
var decay_suppress_timer: float = 0.0
## Consecutive-kill combo (spec §7.2). combo_count in [0, COMBO_MAX_COUNT];
## combo_timer resets to COMBO_WINDOW_SECONDS on each kill, then counts down;
## once it hits 0 the count drains via _combo_drain_accum instead of resetting.
var combo_count: int = 0
var combo_timer: float = 0.0
var _combo_drain_accum: float = 0.0
## Run stats for the death card (spec §7.6/§24): kills this life, elapsed
## time this life. Reset in setup_player (a fresh life, not a fresh sector).
var run_kills: int = 0
## Enemies that died this sector, waiting on ENEMY_RESPAWN_COOLDOWN to
## reappear (spec §7.3: "enemies respawn on a cooldown; the pool does not
## follow"). Cleared whenever a fresh sector starts (start_sector).
var _dead_enemy_records: Array = []
var _respawn_timer: float = 0.0

func _ready() -> void:
 _rng.seed=734927
 _fx_rng.randomize() # FX-only RNG (never the sim's `_rng`): visuals must not perturb the trace.
 # Startup choke point (spec item 2): a template shorter than the §16 0.25s
 # minimum visible lifetime is a hard, loud engine error every test runner's
 # log grep catches (tools/lib.ps1 greps for "ERROR:").
 for message: String in FX.validate_templates(): push_error(message)
 _broadphase.world=self
 _ensure_canvas()
 if player.is_empty(): setup_player("neutral",1,40,[],arena.center)
func _ensure_canvas() -> void:
 if is_instance_valid(_bullet_canvas): return
 _bullet_canvas=BulletCanvas.new()
 _bullet_canvas.world=self
 _bullet_canvas.z_index=40
 add_child(_bullet_canvas)
 _trail_canvas=TrailCanvas.new()
 _trail_canvas.world=self
 _trail_canvas.pool=trail_pool
 _trail_canvas.z_index=5
 add_child(_trail_canvas)
 _fx_canvas=FxCanvas.new()
 add_child(_fx_canvas)
 _pickup_canvas=PickupCanvas.new()
 add_child(_pickup_canvas)
func setup_player(element: String, tier: int, energy: float, _stolen: Array, position: Vector2 = Vector2(896,560)) -> void:
 if not player.is_empty():
  _remove_visual(player)
  _break_actor_cycles(player)
 player_position=position
 light_total=maxf(0.0,energy)
 player=_make_actor(0,element,tier,position,0,false)
 actors_by_id[0]=player
 hull_history=["player_seed"]
 for t: int in range(2,clampi(tier,1,GameTuning.MAX_TIER)+1): hull_history.append("player_%s_t%d_standard_a" % [element,t])
 set_player_hull(hull_history[-1])
 absorption={}
 player_invulnerable=0.0
 active=true
 elapsed=0.0
 # Review finding 4: `tick` (not `elapsed`) is the one clock ShipMotion.step
 # reads (combat_world.gd:1130), so it drives every orbit/drift/breathe
 # group - hence collider positions and gun muzzles. It is a process-global
 # counter otherwise (only ever `tick+=1`), so a new life inherited whatever
 # tick the PREVIOUS life left behind. Reset it alongside `elapsed` here.
 tick=0
 run_kills=0
 decay_suppress_timer=GameTuning.DECAY_SUPPRESSION_SECONDS
 combo_count=0
 combo_timer=0.0
 _combo_drain_accum=0.0
func set_player_hull(id: String, animate: bool = false) -> bool:
 var definition: ShipDefinition=ShipCatalog.get_ship(id)
 if definition==null or not definition.is_player: return false
 if player.is_empty(): player=_make_actor(0,definition.element,definition.tier,player_position,0,false)
 while hull_history.size()<definition.tier:
  var tier: int=hull_history.size()+1
  hull_history.append("player_%s_t%d_standard_a" % [definition.element,tier])
 hull_history[definition.tier-1]=id
 hull_id=id
 player_tier=definition.tier
 player_element=definition.element
 player.hull_id=id
 player.tier=player_tier
 player.element=player_element
 player.dead=false
 player.hp=light_total
 player.max_hp=GameTuning.capacity(player_tier,max_player_tier)
 _configure_actor(player,definition,true)
 actors_by_id[0]=player
 _update_visual(player,animate)
 if animate:
  reshape_remaining=GameTuning.RESHAPE_SECONDS
  player_invulnerable=maxf(player_invulnerable,reshape_remaining)
 return true
func evolve_hull(id: String) -> bool:
 var definition: ShipDefinition=ShipCatalog.get_ship(id)
 if definition==null or definition.tier!=player_tier+1 or light_total<GameTuning.capacity(player_tier,max_player_tier) or player_tier>=max_player_tier: return false
 var tier: int=definition.tier
 if not set_player_hull(id,true): return false
 hull_history.resize(tier)
 hull_history[tier-1]=id
 absorption.clear()
 return true
func evolve_player(element: String, tier: int, _stolen: Array) -> void:
 # Transitional test/editor adapter; production evolution uses evolve_hull.
 var id: String="player_seed" if tier==1 else "player_%s_t%d_standard_a" % [element,clampi(tier,1,GameTuning.MAX_TIER)]
 set_player_hull(id,true)
 while hull_history.size()<tier: hull_history.append("player_%s_t%d_standard_a" % [element,hull_history.size()+1])
 hull_history[tier-1]=id
func set_command(value: ShipCommand) -> void: command=value
func collect_light(raw_amount: float, element: String) -> float:
 if raw_amount<=0.0 or not active: return 0.0
 var multiplier: float=1.25 if _has_ability(player,"siphon") else 1.0
 var consumed: float=minf(raw_amount,maxf(0.0,GameTuning.capacity(player_tier,max_player_tier)-light_total)/multiplier)
 if consumed<=0.0: return 0.0
 light_total+=consumed*multiplier
 player.hp=light_total
 decay_suppress_timer=GameTuning.DECAY_SUPPRESSION_SECONDS # spec §7.1: any absorb suppresses decay
 absorption[element]=float(absorption.get(element,0.0))+consumed
 light_collected.emit(element,consumed)
 energy_collected.emit(element,int(consumed))
 return consumed
func collect_energy(amount: float, element: String) -> void: collect_light(amount,element)
## Combo multiplier (spec §7.2): x1.0 at 0 kills -> x2.5 at COMBO_MAX_COUNT.
func combo_multiplier() -> float:
 return lerpf(1.0,GameTuning.COMBO_MULTIPLIER_MAX,float(combo_count)/float(GameTuning.COMBO_MAX_COUNT))
## Run stats for the death card (spec §7.6/§24).
func run_stats() -> Dictionary:
 return {"kills":run_kills,"elapsed":elapsed}

func _make_actor(id: int, element: String, tier: int, position: Vector2, faction: int, rival: bool) -> Dictionary:
 var hp: float=(140.0+80.0*tier) if rival else (24.0+14.0*tier)
 return {"id":id,"element":element,"tier":clampi(tier,1,GameTuning.MAX_TIER),"pos":position,"vel":Vector2.ZERO,"aim":Vector2.DOWN,"faction":faction,"native_faction":faction,"rival":rival,"elite":false,"hp":hp,"max_hp":hp,"energy":40.0,"fire_cd":0.0,"primary_cd":0.0,"secondary_cd":0.0,"decision_cd":0.0,"target":0,"desired":Vector2.ZERO,"age":_rng.randf()*TAU,"dead":false,"renderer":null,"invulnerable":0.0,"reward_remaining":(80+30*tier) if rival else 24+10*tier,"reward_damage":0.0,"reward_unpaid_limb":0.0,"cooldowns":{},"guns":[],"shield":0.0,"blockers":0.0,"blocker_hits":0,"orbit_stock":0,"orbit_cd":0.0,"slow":0.0,"stored":0,"stolen":[],"infected":0.0,"charge":0.0}
## Convenience spawner for callers that only have (element, tier) - not a
## specific roster hull id - such as a deployment_ramp reinforcement, the
## benchmark's stress population, or a test fixture. Resolves a plain drone
## hull for the element via ShipGenerator.hull_id (drone is every element's
## richest secondary loadout - a sentry's secondaries are overwritten with
## laser_prong, see ship_generator.gd build_enemy_sentry) and caps it to the
## requested tier's slot budget.
func _spawn_enemy(element: String, tier: int, position: Vector2, rival: bool) -> Dictionary:
 var hull_id: String=ShipGenerator.hull_id("boss" if rival else "enemy","boss" if rival else "drone",element,tier)
 return _spawn_named_enemy(hull_id,element,tier,position,rival,false)
func _spawn_elite(element: String, tier: int, position: Vector2) -> Dictionary:
 var kinds: Array[String]=["radial","irregular"]
 var hull_id: String=ShipGenerator.hull_id("elite",kinds[tier%2],element,tier)
 return _spawn_named_enemy(hull_id,element,tier,position,false,true)
## The world descriptor names an exact hull id directly (spec P5 "the
## descriptor names the hulls to spawn directly" - no runtime nearest-tier
## guessing). `tier` here is the node's Chebyshev DIFFICULTY tier, used for
## HP/reward scaling (_make_actor) and for ShipCatalog.cap_to_tier, which may
## differ from the resolved hull's own authored tier when an element's roster
## band does not cover this difficulty (see ShipGenerator.ELEMENT_TIER_BAND).
func _spawn_named_enemy(hull_id: String, element: String, tier: int, position: Vector2, rival: bool, elite: bool) -> Dictionary:
 if hull_id.is_empty(): push_error("No roster hull for element=%s tier=%d rival=%s elite=%s" % [element,tier,rival,elite]); return {}
 var template: ShipDefinition=ShipCatalog.get_ship(hull_id)
 if template==null: push_error("Unknown roster hull id: %s" % hull_id); return {}
 if enemies.size()>=MAX_ACTORS: return {}
 var actor: Dictionary=_make_actor(next_actor_id,template.element,tier,arena.clamp_point(position,30.0),ELEMENTS.find(template.element)+1,rival)
 next_actor_id+=1
 actor.hull_id=hull_id
 actor.archetype=template.archetype # "" on a v0.3 hull: CombatAI then falls back to the id prefix
 actor.elite=elite
 if elite:
  actor.max_hp=180.0+110.0*tier
  actor.hp=actor.max_hp
  actor.reward_remaining=150+60*tier
 _configure_actor(actor,ShipCatalog.cap_to_tier(template,int(actor.tier)),true)
 enemies.append(actor)
 actors_by_id[int(actor.id)]=actor
 _update_visual(actor)
 return actor
func _configure_actor(actor: Dictionary, definition: ShipDefinition, reset: bool = false) -> void:
 if definition==null: return
 var geometry_state: Dictionary={}
 var previous_definition: ShipDefinition=actor.get("definition")
 if not reset and previous_definition!=null and previous_definition.id==definition.id and previous_definition.geometry_revision<definition.geometry_revision:
  geometry_state=CombatPersistence.encode_parts(actor)
 actor.definition=definition
 actor.speed=definition.speed
 actor.turn_rate=definition.turn_rate
 actor.accel=definition.accel
 actor.drag=definition.drag
 actor.footprint=definition.footprint
 actor.hp_buffer=definition.hp_buffer
 actor.damage_multiplier=definition.damage_multiplier
 actor.magnet_radius=definition.magnet_radius
 actor.primary=definition.primary
 actor.secondaries=definition.secondaries.duplicate()
 actor.passives=definition.passives.duplicate()
 var enabled: Dictionary={}
 actor.mounts={}
 actor.body_features={}
 # P4a: capture the previous per-circle state BY ID before the rig is
 # replaced, so a mid-fight definition edit (or a save restore) carries
 # damage/cooldowns across, keyed by circle id rather than array index
 # (a definition edit can reorder or add/remove circles).
 var previous_rig: ShipMotion.ShipRig=actor.get("rig")
 var previous_chain: Dictionary=ShipMotion.encode_chain_state(previous_rig,actor.get("pose")) if previous_rig!=null and not reset else {}
 var old_hp: Dictionary={}
 var old_attached: Dictionary={}
 var old_cd: Dictionary={}
 var old_egg: Dictionary={}
 var old_aim: Dictionary={}
 var old_share: Dictionary={}
 if previous_rig!=null and actor.has("part_hp"):
  for i: int in range(previous_rig.ids.size()):
   var pid: String=previous_rig.ids[i]
   old_hp[pid]=float(actor.part_hp[i])
   old_attached[pid]=bool(actor.part_attached[i])
   old_cd[pid]=float(actor.part_cd[i])
   old_egg[pid]=float(actor.part_egg_cd[i])
   old_aim[pid]=actor.part_aim[i]
   if actor.has("part_reward_share") and i<actor.part_reward_share.size(): old_share[pid]=float(actor.part_reward_share[i])
 actor.rig=ShipMotion.get_rig(definition)
 actor.pose=ShipMotion.ShipPose.new(actor.rig)
 if not previous_chain.is_empty(): ShipMotion.restore_chain_state(actor.rig,actor.pose,previous_chain)
 for part: PartDefinition in definition.parts:
  if not part.mount_id.is_empty() and not actor.mounts.has(part.mount_id): actor.mounts[part.mount_id]=part.position
  if part.stat_id in ["bullet_eater","void_pull","projectile_orbit"]:
   actor.body_features[part.stat_id]={"offset":part.position,"value":part.stat_value,"part_id":part.id}
 for id: String in definition.mounted_components(): enabled[id]=true
 actor.ability_set=enabled
 if reset:
  actor.cooldowns={}
  actor.shield=0.0
  actor.blockers=0.0
  actor.orbit_stock=0
  actor.orbit_cd=0.0
  actor.fire_cd=0.0
  actor.erase("beam_contact")
 _configure_parts(actor,old_hp,old_attached,old_cd,old_egg,old_aim,old_share,reset)
 if not geometry_state.is_empty(): CombatPersistence.apply_parts(self,actor,geometry_state)
 _rebuild_part_views(actor)
## Per-circle HP rule (spec §14/§16): the core's toughness is unchanged -
## it mirrors `actor.hp`/`actor.max_hp` exactly as before. A peripheral
## circle uses its authored `PartDefinition.hp` where the generator set one
## (elite/boss weapon and sub-core circles); an unauthored circle (ordinary
## structural/mount circles on every hull, ordinary enemy weapon mounts)
## derives armour from its radius and tier: `radius*(4+3*tier)`, chosen to
## sit in the same order of magnitude as the authored elite weapon curve
## (`24+15*tier` at radius 6 -> ~4+2.5*tier per radius unit) so giving every
## circle HP does not multiply total fight length - see tasks/todo.md P4a
## review for the measured before/after time-to-kill.
func _configure_parts(actor: Dictionary, old_hp: Dictionary, old_attached: Dictionary, old_cd: Dictionary, old_egg: Dictionary, old_aim: Dictionary, old_share: Dictionary, reset: bool) -> void:
 var rig: ShipMotion.ShipRig=actor.rig
 var n: int=rig.ids.size()
 var part_hp: PackedFloat32Array=PackedFloat32Array()
 var part_max_hp: PackedFloat32Array=PackedFloat32Array()
 var part_cd: PackedFloat32Array=PackedFloat32Array()
 var part_egg: PackedFloat32Array=PackedFloat32Array()
 var part_aim: PackedVector2Array=PackedVector2Array()
 var part_attached: PackedByteArray=PackedByteArray()
 var part_flare: PackedFloat32Array=PackedFloat32Array() # P8 target feedback; decays via `_step_motion`
 part_hp.resize(n)
 part_max_hp.resize(n)
 part_cd.resize(n)
 part_egg.resize(n)
 part_aim.resize(n)
 part_attached.resize(n)
 part_flare.resize(n)
 var mount_index: Dictionary={}
 var mount_twins: Dictionary={} # mount id -> rig indices of every hub carrying it (mirror twins share one)
 var gun_indices: PackedInt32Array=PackedInt32Array()
 # id -> authored PartDefinition.stat_id (P4b: sub_core / shield_generator are
 # not carried by ShipRig, which only knows geometry/motion, so this is read
 # once here from the ShipDefinition and turned into index arrays below - the
 # single choke point boss rules (`_boss_shield_active`, `_boss_can_die`) read).
 var stat_by_id: Dictionary={}
 var hp_by_id: Dictionary={}
 for part: PartDefinition in actor.definition.parts:
  if part.shape=="circle":
   hp_by_id[part.id]=ShipCompiler.part_max_hp(part,int(actor.tier))
   if not part.stat_id.is_empty(): stat_by_id[part.id]=part.stat_id
 var sub_core_indices: PackedInt32Array=PackedInt32Array()
 var shield_generator_indices: PackedInt32Array=PackedInt32Array()
 var part_aim_error: PackedFloat32Array=PackedFloat32Array()
 part_aim_error.resize(n)
 # Cosmetic circles must not advance encounter RNG or change another gun's cadence/aim.
 # One seed per actor, then stable identity-based streams per circle, including across saves.
 if not actor.has("part_seed"): actor.part_seed=int(_rng.randi())
 var part_rng: RandomNumberGenerator=RandomNumberGenerator.new()
 for i: int in range(n):
  var pid: String=rig.ids[i]
  part_rng.seed=hash([int(actor.part_seed),actor.definition.id,pid])
  var initial_cd: float=part_rng.randf_range(0.2,1.2)
  var max_hp: float=float(actor.max_hp) if i==0 else float(hp_by_id.get(pid,0.0))
  # A non-solid circle (rail ring, inner core ring, passive ring, set-piece circle) is scenery:
  # no HP, so no reward share below either. Without this a 184 px rail ring would be given
  # radius*(4+3*tier) HP and most of the hull's limb reward. Every v0.3 circle is solid.
  if i>0 and rig.solid[i]==0: max_hp=0.0
  part_max_hp[i]=max_hp
  part_hp[i]=float(old_hp[pid]) if old_hp.has(pid) else max_hp
  part_attached[i]=(1 if bool(old_attached[pid]) else 0) if old_attached.has(pid) else 1
  part_cd[i]=float(old_cd[pid]) if old_cd.has(pid) else initial_cd
  part_egg[i]=float(old_egg[pid]) if old_egg.has(pid) else 0.0
  part_aim[i]=old_aim[pid] if old_aim.has(pid) else Vector2.DOWN
  part_aim_error[i]=CombatAI.sample_aim_error(part_rng)
  if not rig.mount_id[i].is_empty():
   mount_index[rig.mount_id[i]]=i
   var twins: PackedInt32Array=mount_twins.get(rig.mount_id[i],PackedInt32Array())
   twins.append(i)
   mount_twins[rig.mount_id[i]]=twins
  if i>0 and rig.solid[i]==1 and not rig.ability_id[i].is_empty(): gun_indices.append(i)
  match str(stat_by_id.get(pid,"")):
   "sub_core": sub_core_indices.append(i)
   "shield_generator": shield_generator_indices.append(i)
 part_hp[0]=float(actor.hp)
 part_max_hp[0]=float(actor.max_hp)
 part_attached[0]=1
 actor.part_hp=part_hp
 actor.part_flare=part_flare
 actor.part_max_hp=part_max_hp
 actor.part_cd=part_cd
 actor.part_egg_cd=part_egg
 actor.part_aim=part_aim
 actor.part_aim_error=part_aim_error
 actor.part_attached=part_attached
 actor.mount_index=mount_index
 actor.mount_twins=mount_twins
 actor.gun_indices=gun_indices
 actor.sub_core_indices=sub_core_indices
 actor.shield_generator_indices=shield_generator_indices
 # Recomputed on every fresh configure (`reset` - a spawn or a hull swap,
 # e.g. `_spawn_elite`'s second `_configure_actor` call after `_spawn_enemy`'s
 # first one), never mid-fight: "retreat when fewer than half the weapon
 # circles remain" needs a stable denominator, not one that shrinks as guns
 # die - a hull that started with 6 guns and has 3 left is exactly at the
 # threshold, not permanently safe because `gun_indices.size()` also fell to 3.
 if reset: actor.gun_total=gun_indices.size()
 # Reward split (spec item 5): computed once at spawn, never re-derived on a
 # later reconfigure (a mid-fight definition edit must not re-halve an
 # already-halved pool) - remapped by id like every other per-circle array.
 # Player (id 0) never carries a reward.
 var share: PackedFloat32Array=PackedFloat32Array()
 share.resize(n)
 for i: int in range(n):
  if old_share.has(rig.ids[i]): share[i]=float(old_share[rig.ids[i]])
 if reset and int(actor.id)!=0 and not actor.has("_reward_split"):
  actor._reward_split=true
  var peripheral_sum: float=0.0
  for i: int in range(1,n): peripheral_sum+=part_max_hp[i]
  var total_reward: float=float(actor.get("reward_remaining",0.0))
  var limb_pool: float=total_reward*0.5 if peripheral_sum>0.0 else 0.0
  if peripheral_sum>0.0:
   for i: int in range(1,n): share[i]=limb_pool*part_max_hp[i]/peripheral_sum
  actor.reward_unpaid_limb=limb_pool
  actor.reward_remaining=total_reward-limb_pool
 actor.part_reward_share=share
func _reward_multiplier(actor: Dictionary) -> float: return pow(1.5,maxi(0,int(actor.tier)-player_tier))
## Single choke point for "what is currently visible on this hull" -
## rebuilt from the packed per-circle arrays instead of scanned every tick
## (see `_sync_visuals`, which previously rebuilt this every physics frame).
## A guide disappears with its last cluster. All spokes now end on the core, so another
## rail never depends on this guide's visibility. Guides carry no health or reward.
func _retire_dead_rails(actor: Dictionary, rig: ShipMotion.ShipRig) -> void:
 var rings: Array[int]=[]
 for i: int in range(1,rig.ids.size()):
  var id: String=rig.ids[i]
  if rig.parent_index[i]==0 and rig.solid[i]==0 and id.length()==2 and id.begins_with("r") and id.substr(1).is_valid_int(): rings.append(i)
 var alive: Array[bool]=[]
 for ring: int in rings:
  var any: bool=false
  for c: int in range(ring+1,ring+rig.subtree_size[ring]):
   if rig.parent_index[c]==ring and bool(actor.part_attached[c]) and float(actor.part_hp[c])>0.0: any=true
  alive.append(any)
 for k: int in range(rings.size()):
  actor.part_attached[rings[k]]=1 if alive[k] else 0

func _rebuild_part_views(actor: Dictionary) -> void:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 if rig==null: return
 if not rig.legacy: _retire_dead_rails(actor,rig)
 var guns: Array=[]
 for i: int in actor.gun_indices:
  guns.append({"index":i,"id":rig.ids[i],"mount":rig.mount_id[i],"ability":rig.ability_id[i],"hp":actor.part_hp[i],"max_hp":actor.part_max_hp[i],"cd":actor.part_cd[i],"aim":actor.part_aim[i],"egg_cd":actor.part_egg_cd[i],"offset":rig.rest[i],"radius":rig.radius[i]})
 actor.guns=guns
 var hidden: PackedStringArray=PackedStringArray()
 for i: int in range(1,rig.ids.size()):
  if not bool(actor.part_attached[i]): hidden.append(rig.ids[i])
 for k: int in range(rig.line_from.size()):
  var lf: int=rig.line_from[k]
  var lt: int=rig.line_to[k]
  if (lf>0 and not bool(actor.part_attached[lf])) or (lt>0 and not bool(actor.part_attached[lt])): hidden.append(rig.line_ids[k])
 actor.hidden_ids=hidden
func _update_visual(actor: Dictionary, animate: bool = false) -> void:
 if not visuals_enabled: return
 var definition: ShipDefinition=actor.get("definition")
 if definition==null: return
 var renderer: ShipRenderer=actor.get("renderer") as ShipRenderer
 if not is_instance_valid(renderer):
  renderer=ShipRenderer.new()
  renderer.z_index=10
  add_child(renderer)
  actor.renderer=renderer
 renderer.set_ship(definition,animate)
 renderer.external_pose=actor.get("pose")
 renderer.hidden_part_ids=actor.get("hidden_ids",PackedStringArray())
 renderer.set_motion_tick(tick)
 renderer.position=actor.pos
 renderer.rotation=Vector2(actor.aim).angle()+PI/2.0
func _has_ability(actor: Dictionary, id: String) -> bool: return actor.get("ability_set",{}).has(id)
func has_passive(id: String) -> bool: return _has_ability(player,id)
func _ability(id: String) -> AbilityDefinition:
 if not _ability_cache.has(id): _ability_cache[id]=AbilityCatalog.get_definition(id)
 return _ability_cache[id]

func start_sector(description: Dictionary, fresh: bool = true) -> void:
 var epoch: int=int(description.get("encounter_epoch",0))
 if epoch!=encounter_epoch:
  sector_cache.clear()
  encounter_records.clear()
  encounter_epoch=epoch
 elif not sector.is_empty():
  _flush_debris() # so a mid-fade limb's light lands in the cached encounter, not nowhere
  CombatPersistence.cache_encounter(self,_sector_key(sector),CombatPersistence.encounter_snapshot(self,false))
 _clear_encounter()
 sector=description.duplicate(true)
 _rng.seed=int(sector.get("encounter_seed",734927))
 _configure_arena_exits()
 active=true
 cleared_emitted=false
 sector_energy_remaining=int(sector.get("resource_budget",200))
 sector_energy_paid=0
 _dead_enemy_records.clear()
 _respawn_timer=GameTuning.ENEMY_RESPAWN_COOLDOWN
 if not fresh: return
 var key: String=_sector_key(sector)
 if encounter_records.has(key) or sector_cache.has(key):
  CombatPersistence.restore_encounter(self,CombatPersistence.read_cached_encounter(self,key))
  return
 var kind: String=str(sector.get("kind","regular"))
 # Spec §8: the origin's freebies must never exceed what the level has
 # revealed - the descriptor names them, never a hard-coded element list.
 if kind=="origin":
  var starters: Array=sector.get("starter_pickups",[])
  for i: int in range(starters.size()): _drop_pickup(arena.center+Vector2((i-1)*64,190),str(starters[i]),5)
  cleared_emitted=true
  return
 # A defeated boss never respawns; regular/elite content always repopulates
 # on return (spec §7: enemies respawn on a cooldown, the light pool does
 # not follow - the pool itself is reflected in resource_budget, below).
 if kind=="boss" and bool(sector.get("boss_down",false)):
  cleared_emitted=true
  return
 var element: String=str(sector.get("element","lightning"))
 var tier: int=clampi(int(sector.get("tier",1)),1,GameTuning.MAX_TIER)
 var enemy_hulls: Array=sector.get("enemy_hulls",[])
 for i: int in range(enemy_hulls.size()):
  var p: Vector2=arena.center+Vector2.from_angle(TAU*i/maxi(1,enemy_hulls.size()))*(arena.radius*0.55)
  if p.distance_to(player_position)<180.0: p=arena.center*2.0-p
  _spawn_named_enemy(str(enemy_hulls[i]),element,tier,p,false,false)
 var elite_hulls: Array=sector.get("elite_hulls",[])
 for i: int in range(elite_hulls.size()):
  _spawn_named_enemy(str(elite_hulls[i]),element,tier,arena.center+Vector2(150*(i-1),-200),false,true)
 var boss_hull: String=str(sector.get("boss_hull",""))
 if kind=="boss" and not boss_hull.is_empty():
  _spawn_named_enemy(boss_hull,element,tier,arena.center+Vector2(0,-230),true,false)
 for i: int in range(3): _drop_pickup(arena.center+Vector2(_rng.randf_range(-400,400),_rng.randf_range(-220,220)),element,1)

func _physics_process(delta: float) -> void:
 if not active or player.is_empty(): return
 tick+=1
 var began: int=Time.get_ticks_usec()
 var dt: float=minf(delta,0.05)
 _last_dt=dt
 # `motion` had no section until S0: it ran before the first section_start, so the cost every
 # rail-grammar hull will add was invisible to the benchmark.
 var motion_start: int=Time.get_ticks_usec() if profile_sections else 0
 if not _uses_follow_motion(player): _step_motion(player)
 for actor: Dictionary in enemies:
  if not _uses_follow_motion(actor): _step_motion(actor)
 if profile_sections: section_ms.motion=(Time.get_ticks_usec()-motion_start)/1000.0
 elapsed+=dt
 player_invulnerable=maxf(0.0,player_invulnerable-dt)
 reshape_remaining=maxf(0.0,reshape_remaining-dt)
 contact_timer=maxf(0.0,contact_timer-dt)
 player.pos=player_position
 player.hp=light_total
 player.invulnerable=player_invulnerable
 beams.clear()
 if benchmark_mode:
  var target_position: Vector2=arena.center+Vector2(cos(elapsed*0.35)*360.0,sin(elapsed*0.35)*200.0)
  command.movement=((target_position-Vector2(player.pos))/100.0).limit_length(1.0)
  command.aim=Vector2.from_angle(elapsed*0.55)
  command.fire=true
  command.secondaries.assign([true,true,true])
 var section_start: int=Time.get_ticks_usec() if profile_sections else 0
 _update_player(dt)
 for actor: Dictionary in enemies:
  if not bool(actor.dead): _update_ai(actor,dt)
 if profile_sections:
  section_ms.ai=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_actor_status(player,dt)
 for actor: Dictionary in enemies: _update_actor_status(actor,dt)
 _update_pace(dt)
 var grid_start: int=Time.get_ticks_usec() if profile_sections else 0
 _rebuild_actor_grid()
 if profile_sections: section_ms.grid=(Time.get_ticks_usec()-grid_start)/1000.0 # also inside status_grid_telegraphs
 _update_telegraphs(dt)
 if profile_sections:
  section_ms.status_grid_telegraphs=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_bullets(dt)
 _update_black_holes(dt)
 if profile_sections:
  section_ms.bullets=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_viruses(dt)
 _update_clouds(dt)
 if profile_sections:
  section_ms.viruses_clouds=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_drones(dt)
 if profile_sections:
  section_ms.drones=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_pickups(dt)
 if profile_sections:
  section_ms.pickups=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_contact()
 _cleanup_dead()
 if profile_sections:
  section_ms.drones_pickups_cleanup=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_effects(dt)
 _update_debris(dt)
 _update_trails(dt)
 _sync_visuals()
 player_position=player.pos
 player.hp=light_total
 bullet_count=bullets.count()
 if benchmark_mode and bullet_count<benchmark_target: _fill_benchmark(benchmark_target-bullet_count)
 if profile_sections:
  section_ms.visual_sync_refill=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 queue_redraw()
 if is_instance_valid(_bullet_canvas):
  _bullet_canvas.sync_pool(bullets)
  _bullet_canvas.queue_redraw()
 if is_instance_valid(_trail_canvas): _trail_canvas.queue_redraw()
 # `_fx_canvas.sync` runs from `_draw()` (render/idle step), NOT here: the OLD
 # immediate `fx.draw_below`/`fx.draw_above` it replaces also ran on the
 # render step, outside `simulation_ms` - `tests/combat_benchmark.gd`'s
 # headless sim-only gate budgets (2000 bullets: mean<=9.0/p95<=12.0) proved
 # this the hard way: syncing here folded ~1-2ms of FX MultiMesh upload into
 # the sim budget and regressed it to mean 11.7/p95 16.9, a real, avoidable
 # cost that has nothing to do with simulating a tick.
 simulation_ms=(Time.get_ticks_usec()-began)/1000.0
 if profile_sections:
  section_ms.upload=(Time.get_ticks_usec()-section_start)/1000.0
  section_ms.total=simulation_ms
func _update_player(dt: float) -> void:
 _tick_cooldowns(player,dt)
 _update_warp(dt) # phase machine first: settles warp_phase/warp_direction/warp_commit_speed for this tick
 var locked: bool=warp_locked()
 if locked:
  # Control locked (spec §12 commit..zoom-out): momentum carries straight
  # through in the travel direction at the speed measured at commit. Position
  # during the locked phases is owned entirely by `_update_warp` (it must
  # keep moving through the node swap, at a speed `_update_player`'s own
  # arena-relative clamp cannot reason about mid-swap), so nothing else here
  # touches position, aim or firing.
  player.vel=Vector2(warp_direction).normalized()*warp_commit_speed
  _finish_follow_motion(player)
  return
 var thrusters: float=1.2 if _has_ability(player,"thrusters") else 1.0
 var input_dir: Vector2=command.movement.limit_length(1.0)
 var warp_scale: float=WARP_PUSH_SPEED_SCALE if warp_phase==WARP_PUSH else 1.0
 var top_speed: float=float(player.speed)*thrusters*warp_scale
 var accel: float=float(player.get("accel",1200.0))*thrusters
 var drag: float=float(player.get("drag",5.0))
 var slow: float=_slow_multiplier(player)
 var vel: Vector2=Vector2(player.vel)
 vel+=(accel*input_dir*slow-drag*vel)*dt
 if vel.length()>top_speed*slow: vel=vel.limit_length(maxf(0.001,top_speed*slow))
 vel=_update_dash(dt,input_dir,vel,float(player.speed)*thrusters)
 player.vel=vel
 var desired: Vector2=Vector2(player.pos)+vel*dt
 # While pushing into a membrane (spec §12: "the rim arc deforms outward at
 # the contact point"), the rim is soft, not a wall - skip the sealed-wall
 # clamp/friction entirely rather than fighting the 40% speed scale with a
 # second, contradictory resistance. Bounded on its own: PUSH lasts <=0.30s
 # at <=40% top speed, so the overshoot (well under 40px for every current
 # role) stays inside the 80px dead-space margin outside the rim.
 if arena.contains(desired,3.0) or warp_phase==WARP_PUSH:
  player.pos=desired
 else:
  var clamped: Vector2=arena.clamp_point(desired,3.0)
  if clamped.distance_squared_to(desired)>0.01:
   boundary_contact.emit(clamped)
   _add_effect("wall",clamped,PLAYER_COLOR,0.2,18.0)
   # Rim contact (spec §13/plan item 1): remove the velocity component INTO
   # the wall and scale the tangential component, instead of only clamping
   # position - so a fast rim graze keeps most of its speed along the wall.
   var normal: Vector2=arena.normal_at(clamped)
   var into_wall: float=vel.dot(normal)
   if into_wall>0.0:
    vel=(vel-normal*into_wall)*0.9
    player.vel=vel
  player.pos=clamped
 if command.aim.length_squared()>0.01:
  var speed_turn: float=float(player.turn_rate)*thrusters
  player.aim=Vector2.from_angle(rotate_toward(Vector2(player.aim).angle(),command.aim.angle(),speed_turn*dt))
 _finish_follow_motion(player)
 if command.fire: _fire_primary(player,dt)
 for index: int in range(mini(command.secondaries.size(),player.secondaries.size())):
  if command.secondaries[index]: _use_secondary(player,index)
 _passives(player,dt)
## Dash (spec §13/§26): 0.18 s burst at 3x top speed along the input
## direction (falling back to aim, then facing, if there is no input),
## exits at top speed (so it blends back into the accel/drag model rather
## than snapping), 1.2 s cooldown measured from the START of the dash.
## Deliberately touches nothing about `player_invulnerable` - "Not
## invulnerable" (spec §13) is a property of what this function does NOT do,
## not a flag it clears; `tests/handling_test.gd` proves a bullet on the
## core mid-dash still damages, with a forced-invulnerable negative control.
func _update_dash(dt: float, input_dir: Vector2, vel: Vector2, top_speed: float) -> Vector2:
 player.dash_cooldown=maxf(0.0,float(player.get("dash_cooldown",0.0))-dt)
 var timer: float=float(player.get("dash_timer",0.0))
 if timer>0.0:
  timer=maxf(0.0,timer-dt)
  player.dash_timer=timer
  var dash_dir: Vector2=player.get("dash_dir",Vector2.DOWN)
  return dash_dir*top_speed if timer<=0.0 else dash_dir*top_speed*DASH_SPEED_MULT
 if bool(command.dash) and float(player.get("dash_cooldown",0.0))<=0.0:
  var dir: Vector2=input_dir
  if dir.length_squared()<=0.0001: dir=command.aim
  if dir.length_squared()<=0.0001: dir=Vector2(player.aim)
  dir=dir.normalized()
  player.dash_dir=dir
  player.dash_timer=DASH_BURST_SECONDS
  player.dash_cooldown=DASH_COOLDOWN_SECONDS
  _add_effect("dash_ring",player.pos,PLAYER_COLOR,0.2,20.0)
  _trail_kink(0)
  return dir*top_speed*DASH_SPEED_MULT
 return vel
## --- The warp (spec §12) ------------------------------------------------
func warp_locked() -> bool: return warp_phase!=WARP_NONE and warp_phase!=WARP_PUSH
## Called once per tick from `_update_player`, before the locked check, so
## `warp_phase`/`warp_direction`/`warp_commit_speed` are settled before the
## rest of the tick reads them. Owns every phase transition.
func _update_warp(dt: float) -> void:
 if warp_phase==WARP_NONE or warp_phase==WARP_PUSH:
  _update_warp_push(dt)
  return
 _warp_timer+=dt
 _warp_locked_accum+=dt
 var direction: Vector2=Vector2(warp_direction).normalized()
 match warp_phase:
  WARP_ZOOM_IN:
   warp_progress=clampf(_warp_timer/WARP_ZOOM_IN_SECONDS,0.0,1.0)
   if _warp_timer>=WARP_ZOOM_IN_SECONDS:
    warp_phase=WARP_TRAVEL
    _warp_timer=0.0
  WARP_TRAVEL:
   warp_progress=clampf(_warp_timer/WARP_TRAVEL_SECONDS,0.0,1.0)
   player.pos=Vector2(player.pos)+direction*warp_commit_speed*dt
   if _warp_timer>=WARP_TRAVEL_SECONDS:
    if not _warp_swap_done:
     _warp_spring_back()
     return
    warp_phase=WARP_ARRIVAL
    _warp_timer=0.0
    _warp_arrive()
  WARP_ARRIVAL:
   warp_progress=clampf(_warp_timer/WARP_ARRIVAL_SECONDS,0.0,1.0)
   player.pos=Vector2(player.pos)+direction*warp_commit_speed*dt
   if _warp_timer>=WARP_ARRIVAL_SECONDS:
    warp_phase=WARP_ZOOM_OUT
    _warp_timer=0.0
  WARP_ZOOM_OUT:
   warp_progress=clampf(_warp_timer/WARP_ZOOM_OUT_SECONDS,0.0,1.0)
   player.pos=Vector2(player.pos)+direction*warp_commit_speed*dt
   if _warp_timer>=WARP_ZOOM_OUT_SECONDS: _warp_finish()
  WARP_FADE:
   warp_progress=clampf(_warp_timer/WARP_REDUCED_SECONDS,0.0,1.0)
   if _warp_timer>=WARP_REDUCED_SECONDS:
    if not _warp_swap_done:
     _warp_spring_back()
     return
    _warp_arrive()
    _warp_finish()
## Places the player just inside the OPPOSITE membrane at entry speed (spec
## §12: "moving at entry speed, so momentum carries through") - the same
## `entry_position` the pre-P6 instant cut used, just timed to the end of the
## travel phase instead of the whole transition.
func _warp_arrive() -> void:
 warp_entry_speed=warp_commit_speed
 player.pos=arena.entry_position(warp_direction)
 player.vel=Vector2(warp_direction).normalized()*warp_commit_speed
 warp_arrived.emit()
## Push accumulation while the player presses into an open membrane arc
## (spec §12 Push: 0.30 s, resists, ~40% speed, releasing before the
## threshold springs back). Reads the CURRENT position/input directly so it
## has no ordering dependency on the accel/drag movement computed afterward.
func _update_warp_push(dt: float) -> void:
 var dir: Vector2i=_warp_engage_direction()
 if warp_phase==WARP_NONE:
  if dir==Vector2i.ZERO: return
  warp_phase=WARP_PUSH
  warp_direction=dir
  _warp_push_depth=0.0
 if dir==warp_direction and dir!=Vector2i.ZERO:
  _warp_push_depth=minf(WARP_PUSH_SECONDS,_warp_push_depth+dt)
 else:
  _warp_push_depth=maxf(0.0,_warp_push_depth-dt*WARP_PUSH_RELEASE_RATE)
 warp_progress=_warp_push_depth/WARP_PUSH_SECONDS
 if _warp_push_depth<=0.0:
  warp_phase=WARP_NONE
  warp_direction=Vector2i.ZERO
  warp_progress=0.0
  return
 if _warp_push_depth>=WARP_PUSH_SECONDS: _warp_commit()
func _warp_engage_direction() -> Vector2i:
 var pos: Vector2=Vector2(player.pos)
 var offset: Vector2=pos-arena.center
 var dist: float=offset.length()
 if dist<arena.radius-60.0: return Vector2i.ZERO
 var dir: Vector2i=arena.membrane_at(pos)
 if dir==Vector2i.ZERO: return Vector2i.ZERO
 var outward: Vector2=offset.normalized() if dist>0.001 else Vector2(dir)
 if command.movement.limit_length(1.0).dot(outward)<=0.2: return Vector2i.ZERO
 return dir
## Commit (spec §12): control locks, player becomes invulnerable for exactly
## the locked window's length (so the EXISTING `player_invulnerable` decay in
## `_physics_process` is what ends the lock - no second timer), and every
## enemy projectile in the old node is discarded.
func _warp_commit() -> void:
 var reduced: bool=warp_reduced
 warp_phase=WARP_FADE if reduced else WARP_ZOOM_IN
 warp_progress=0.0
 _warp_timer=0.0
 _warp_locked_accum=0.0
 _warp_swap_done=false
 warp_commit_speed=Vector2(player.vel).length()
 var locked_total: float=WARP_REDUCED_SECONDS if reduced else (WARP_ZOOM_IN_SECONDS+WARP_TRAVEL_SECONDS+WARP_ARRIVAL_SECONDS+WARP_ZOOM_OUT_SECONDS)
 player_invulnerable=maxf(player_invulnerable,locked_total)
 _discard_enemy_projectiles()
 warp_committed.emit(warp_direction)
## Enemy-only discard (spec §12: "all enemy projectiles in the old node are
## discarded" - the player's own shots are not enemy projectiles). Returns
## the count discarded so callers/tests can measure it directly.
func _discard_enemy_projectiles() -> int:
 var discarded: int=0
 for slot: int in range(bullets.active_indices.size()-1,-1,-1):
  var index: int=bullets.active_indices[slot]
  if bullets.factions[index]!=0:
   bullets.remove_at(slot)
   discarded+=1
 bullet_count=bullets.count()
 return discarded
## Called by the node-swap listener (spec P6 item 5, main.gd/run_controller)
## once the sector has actually been swapped. If this never arrives before
## the travel phase ends, `_update_warp` springs back instead of deadlocking.
func confirm_warp_swap() -> void: _warp_swap_done=true
func _warp_spring_back() -> void:
 warp_phase=WARP_NONE
 warp_progress=0.0
 warp_direction=Vector2i.ZERO
 _warp_push_depth=0.0
 _warp_timer=0.0
 _warp_swap_done=false
 player_invulnerable=0.0
 warp_commit_speed=0.0
func _warp_finish() -> void:
 warp_locked_measured=_warp_locked_accum
 warp_phase=WARP_NONE
 warp_progress=0.0
 warp_direction=Vector2i.ZERO
 _warp_push_depth=0.0
 _warp_timer=0.0
 _warp_swap_done=false
 warp_commit_speed=0.0
## Trails (spec §13/§19/§23): the player always leaves one, longer at higher
## speed (see trail_pool.gd's sampling rule); enemies leave shorter ones and
## compete for the 40-trail budget by priority (nearest to the player
## survives a crowded fight; the player is never dropped).
func _update_trails(dt: float) -> void:
 if not visuals_enabled: return
 var ribbon: bool=warp_phase==WARP_TRAVEL or warp_phase==WARP_ZOOM_IN
 var player_speed: float=Vector2(player.vel).length()
 var player_width: float=2.6*clampf(player_speed/float(maxf(1.0,player.speed)),0.35,1.0)
 if ribbon: player_width*=1.8
 trail_pool.request(0,player.pos,1.0e9,player_width,PLAYER_COLOR,TrailPool.PLAYER_MAX_POINTS*(3 if ribbon else 1))
 for actor: Dictionary in enemies:
  if bool(actor.dead): continue
  var speed: float=Vector2(actor.vel).length()
  if speed<1.0: continue
  var width: float=1.6*clampf(speed/float(maxf(1.0,actor.speed)),0.3,1.0)
  var priority: float=(500.0 if bool(actor.get("elite",false)) or bool(actor.get("rival",false)) else 100.0)-Vector2(actor.pos).distance_to(player.pos)*0.05
  trail_pool.request(int(actor.id),actor.pos,priority,width,_actor_color(actor),TrailPool.ENEMY_MAX_POINTS)
 trail_pool.update(dt)
func _trail_kink(owner_id: int) -> void: trail_pool.kink(owner_id)
func _tick_cooldowns(actor: Dictionary, dt: float) -> void:
 actor.fire_cd=maxf(0.0,float(actor.fire_cd)-dt)
 for id: String in actor.cooldowns: actor.cooldowns[id]=maxf(0.0,float(actor.cooldowns[id])-dt)
 actor.shield=maxf(0.0,float(actor.shield)-dt)
 actor.blockers=maxf(0.0,float(actor.blockers)-dt)
 actor.orbit_cd=maxf(0.0,float(actor.orbit_cd)-dt)
 for i: int in range(actor.get("part_cd",PackedFloat32Array()).size()):
  actor.part_cd[i]=maxf(0.0,float(actor.part_cd[i])-dt)
  actor.part_egg_cd[i]=maxf(0.0,float(actor.part_egg_cd[i])-dt)
## Archetype behaviour lives in combat_ai.gd (P4b, spec §14); this stays the
## per-tick entry point so `_physics_process` and every existing test/tool
## that calls `_update_ai` directly keeps working unchanged.
func _update_ai(actor: Dictionary, dt: float) -> void:
 _tick_cooldowns(actor,dt)
 actor.age=float(actor.age)+dt
 CombatAI.update(self,actor,dt)
 _passives(actor,dt)
func _choose_target(actor: Dictionary) -> Dictionary:
 var best: Dictionary=player
 var score: float=-INF
 for candidate: Dictionary in actors_by_id.values():
  if not _hostile(actor,candidate): continue
  var distance: float=Vector2(candidate.pos).distance_to(actor.pos)
  var value: float=float(candidate.get("footprint",24.0))*4.0-distance*0.18 if bool(actor.rival) else -distance
  if value>score:
   best=candidate
   score=value
 return best
func _hostile(source: Dictionary, target: Dictionary) -> bool:
 return not target.is_empty() and not bool(target.dead) and int(source.get("id",-1))!=int(target.id) and int(source.get("faction",-1))!=int(target.faction)
func _hostiles(actor: Dictionary) -> Array:
 var result: Array=[]
 for target: Dictionary in actors_by_id.values():
  if _hostile(actor,target): result.append(target)
 return result
func _nearest(source: Dictionary, at: Vector2, excluded: Array = []) -> Dictionary:
 var best: Dictionary={}
 var distance: float=INF
 for target: Dictionary in actors_by_id.values():
  if not _hostile(source,target) or int(target.id) in excluded: continue
  var d: float=at.distance_squared_to(target.pos)
  if d<distance:
   best=target
   distance=d
 return best

func _mount_alive(actor: Dictionary, mount: String) -> bool:
 # A destroyed circle's weapon never fires again (spec §14/§19). The player
 # has no per-circle hitbox (§16), so its mounts are never marked destroyed.
 var index: int=int(actor.get("mount_index",{}).get(mount,-1))
 if index<=0: return true
 return bool(actor.part_attached[index]) and float(actor.part_hp[index])>0.0
func _fire_primary(actor: Dictionary, dt: float) -> void:
 if int(actor.id)!=0 and ai_firing_disabled: return
 if not _mount_alive(actor,"primary"): return
 var id: String=str(actor.primary)
 if AbilityCatalog.is_continuous(id):
  var beam_emitter: Dictionary=_resolve_muzzle(actor,"primary")
  _beam(actor,id,dt,beam_emitter.position,actor.aim)
  if float(actor.fire_cd)<=0.0:
   _emit_shot(actor,id,beam_emitter.position,beam_emitter.part)
   actor.fire_cd=0.16
  return
 if float(actor.fire_cd)>0.0: return
 var cooldown: float=_ability(id).cooldown
 actor.fire_cd=maxf(0.06,cooldown)*(1.0 if int(actor.id)==0 else (2.0 if bool(actor.rival) else 4.5))
 var emitter: Dictionary=_resolve_muzzle(actor,"primary")
 _activate_component(actor,id,emitter.position,actor.aim,"",emitter.part)
func _fire_basic(actor: Dictionary) -> void: _fire_primary(actor,_last_dt)
func _use_primary(actor: Dictionary) -> void: _fire_primary(actor,_last_dt)
func _use_secondary(actor: Dictionary, index: int = 0) -> void:
 if int(actor.id)!=0 and ai_firing_disabled: return
 if index<0 or index>=actor.secondaries.size(): return
 var id: String=str(actor.secondaries[index])
 var key: String="secondary_%d" % index
 if not _mount_alive(actor,key): return
 if float(actor.cooldowns.get(key,0.0))>0.0: return
 actor.cooldowns[key]=_ability(id).cooldown
 actor.secondary_cd=_ability(id).cooldown
 var emitter: Dictionary=_resolve_muzzle(actor,key)
 _activate_component(actor,id,emitter.position,actor.aim,key,emitter.part)
func _emit_shot(actor: Dictionary, id: String, at: Vector2, emitter_part: String = "") -> void:
 shot_fired.emit(at,str(actor.element),id)
 shot_audio_requested.emit(at,str(actor.element),id,int(actor.id))
 if int(actor.id)==0: attack_performed.emit(str(actor.element),id)
 _emit_muzzle(actor,id,at,emitter_part)
func _emit_muzzle(actor: Dictionary, id: String, at: Vector2, emitter_part: String = "") -> void:
 # Shot beat 1 (spec §19.1): "a ring at the emitter snapping outward and
 # fading over ~0.15 s" - fired once per ability activation (not once per
 # bullet in a spread), at the muzzle position the ability itself resolved.
 var firing_definition: ShipDefinition=actor.get("definition")
 if emitter_part=="" and firing_definition!=null and firing_definition.core_weapon!="" and SetPieceCatalog.ability_of(firing_definition.core_weapon)==id and at.distance_squared_to(Vector2(actor.pos))<0.001:
  emitter_part="core"
 var core_fire: bool=firing_definition!=null and firing_definition.core_weapon!="" and emitter_part=="core"
 var firing_color: Color=ShipCatalog.get_color(firing_definition.accent_color) if core_fire and firing_definition.accent_color!="" else Pool.ability_color(id)
 var binding: Dictionary={"emitter_owner":int(actor.id),"emitter_part":emitter_part} if emitter_part!="" else {}
 fx.emit("core_fire" if core_fire else "muzzle",at,firing_color,_fx_rng,binding)
func _damage_scale(actor: Dictionary) -> float:
 return float(actor.get("damage_multiplier",1.0))*(1.0+0.12*(int(actor.tier)-1))*(1.0 if int(actor.id)==0 or bool(actor.get("rival",false)) else 0.65)
func _activate_component(actor: Dictionary, id: String, at: Vector2, aim: Vector2, mount: String = "", emitter_part: String = "") -> void:
 var definition: AbilityDefinition=_ability(id)
 var damage: float=definition.damage*_damage_scale(actor)
 var rig: ShipMotion.ShipRig=actor.get("rig")
 if emitter_part=="" and rig!=null and rig.index_of(mount)>=0: emitter_part=mount
 _emit_shot(actor,id,at,emitter_part)
 actor.shots_fired=int(actor.get("shots_fired",0))+1 # play-census instrumentation only; not read by gameplay
 ability_events[id]=int(ability_events.get(id,0))+1 # census: a weapon that never fires in play is a content bug
 match id:
  "pulse_cannon":
   var regular: bool=int(actor.id)!=0 and not bool(actor.rival) and not bool(actor.elite)
   if regular and str(actor.element)=="plasma":
    for i: int in range(4): _shoot(actor,Vector2.from_angle(float(actor.age)*1.5+TAU*i/4.0),220.0,damage,-1.0,0,at)
    if actor.body_features.has("projectile_orbit") and float(actor.cooldowns.get("pattern_orbit",0.0))<=0.0:
     actor.cooldowns.pattern_orbit=3.0
     for i: int in range(3): _shoot(actor,Vector2.from_angle(TAU*i/3.0),220.0,damage,-1.0,Pool.ORBIT,at)
   elif regular and str(actor.element)=="void":
    for i: int in range(2): _shoot(actor,aim.rotated((i-0.5)*0.35),155.0,damage,-1.0,0,at)
   else:
    _shoot(actor,aim,570.0 if int(actor.id)==0 else 250.0,damage,-1.0,Pool.INFECT if regular and str(actor.element)=="corruption" else 0,at)
  "ricochet": _shoot(actor,aim,500.0,damage,-1.0,Pool.RICOCHET,at)
  "flame_cone":
   for i: int in range(7): _shoot(actor,aim.rotated((i-3)*0.12),420.0,damage,definition.range_pixels/420.0,0,at)
  "bolt": _shoot(actor,aim,780.0,damage,-1.0,Pool.CHAIN,at)
  "beam","homing_beam": _beam(actor,id,_last_dt,at,aim)
  "virus":
   var target: Dictionary=_nearest(actor,at)
   if not target.is_empty() and at.distance_to(target.pos)<=definition.range_pixels: _attach_virus(actor,int(target.id),damage,0)
  "seeker_missiles":
   for i: int in range(3): _shoot(actor,aim.rotated((i-1)*0.2),310.0,damage,-1.0,Pool.HOMING,at)
  "rocket_launcher":
   for i: int in range(5): _shoot(actor,aim.rotated((i-2)*0.15),220.0,damage,-1.0,Pool.WANDER|Pool.ROCKET,at)
  "shield": actor.shield=GameTuning.SHIELD_DURATION
  "explosives": _queue_attack(actor,"explosive",arena.clamp_point(at+aim*260.0,100.0),Vector2.ZERO,1.2,damage,definition.range_pixels,-1,mount)
  "laser_prong": _queue_attack(actor,"laser",at,_ray_end(at,aim),0.8,damage,0.0,-1,mount)
  "poison_cloud":
   if clouds.size()<80: clouds.append({"pos":arena.clamp_point(at+aim*100.0),"radius":definition.range_pixels,"time":definition.duration,"damage":damage,"owner":int(actor.id),"faction":int(actor.faction),"element":str(actor.element)})
  # Spec §16: "any attack that cannot be dodged on reaction shows a warning
  # >= 0.5 s before it lands" - was 0.35s (P8 carried-forward finding).
  "mine_layer": _queue_attack(actor,"mine",arena.clamp_point(at-aim*28.0),Vector2.ZERO,0.5,damage,definition.range_pixels,-1,mount)
  "orbital_blockers":
   actor.blockers=definition.duration
   actor.blocker_hits=6
  # ---- Ship design spec §6.3: the twenty weapons v0.3 did not have ------------------------
  # Every enemy-usable instant hit below goes through a telegraph of >= 0.5 s (v0.3 §16).
  "spiral_shot":
   if int(actor.id)==0:
    # Two shots weaving about the aim: the spiral is the sine of the shot count.
    var weave: float=0.30*sin(float(int(actor.get("shots_fired",0)))*0.9)
    _shoot(actor,aim.rotated(weave),520.0,damage,-1.0,0,at)
    _shoot(actor,aim.rotated(-weave),520.0,damage,-1.0,0,at)
   else:
    for i: int in range(4): _shoot(actor,Vector2.from_angle(float(actor.age)*1.5+TAU*i/4.0),220.0,damage,-1.0,0,at)
  "pulse_ring":
   for i: int in range(12): _shoot(actor,Vector2.from_angle(TAU*i/12.0),240.0,damage,definition.range_pixels/240.0,0,at)
  "chain_infection": _shoot(actor,aim,420.0,damage,-1.0,Pool.CHAIN|Pool.INFECT,at)
  "overcharge":
   # Every fourth shot is the charged one: triple damage and it chains.
   actor.charge=int(actor.get("charge",0))+1
   var charged: bool=int(actor.charge)%4==0
   _shoot(actor,aim,600.0,damage*(3.0 if charged else 1.0),-1.0,Pool.CHAIN if charged else 0,at)
  "phase_shot": _shoot(actor,aim,560.0 if int(actor.id)==0 else 250.0,damage,-1.0,Pool.PHASE,at)
  "void_orb": _shoot(actor,aim,155.0,damage,-1.0,Pool.PIERCING,at)
  "drone_hatch": _spawn_drones(actor,2,damage,at)
  "drone_swarm":
   var first: int=drones.size()
   _spawn_drones(actor,4,damage,at)
   for d: int in range(first,drones.size()):
    drones[d].hp=20.0
    drones[d].time=definition.duration
  "slow_field":
   # The player drops it where they stand; an enemy throws it ahead. It slows and does no damage.
   if clouds.size()<80: clouds.append({"pos":at if int(actor.id)==0 else arena.clamp_point(at+aim*160.0),"radius":definition.range_pixels,"time":definition.duration,"damage":0.0,"owner":int(actor.id),"faction":int(actor.faction),"element":str(actor.element),"kind":"slow"})
  "black_hole_shot":
   var hole: int=_shoot(actor,aim,120.0,damage,definition.duration,Pool.BLACK_HOLE,at)
   if hole>=0: black_holes+=1
  "arc_tether","siphon_tether","siphon_leech":
   var tethered: Dictionary=_nearest(actor,at)
   if not tethered.is_empty() and at.distance_to(tethered.pos)<=definition.range_pixels and viruses.size()<128:
    viruses.append({"target":int(tethered.id),"damage":damage,"generation":9,"owner":int(actor.id),"faction":int(actor.faction),"element":str(actor.element),"pos":tethered.pos,
     "kind":id,"time":definition.duration,"break_range":definition.range_pixels*1.3,"warn":0.0 if int(actor.id)==0 else 0.5})
  "ignition_lance": _beam(actor,id,_last_dt,at,aim)
  "discharge": _queue_attack(actor,"explosive",Vector2(actor.pos),Vector2.ZERO,maxf(0.5,definition.duration),damage,definition.range_pixels,-1,mount)
  "collapse_charge": _queue_attack(actor,"explosive",arena.clamp_point(at+aim*260.0,100.0),Vector2.ZERO,definition.duration,damage,definition.range_pixels,-1,mount)
  "nova_pulse": _queue_attack(actor,"nova",at,Vector2.ZERO,maxf(0.5,definition.duration),damage,0.0,-1,mount)
  "blink_mine": _queue_attack(actor,"mine",arena.clamp_point(at+aim*300.0),Vector2.ZERO,0.5,damage,definition.range_pixels,-1,mount)
  "refract_beam":
   # A beam with one bend: out along the aim, then from the elbow toward whoever is nearest it.
   var elbow: Vector2=arena.clamp_point(at+aim*definition.range_pixels)
   var struck: Dictionary=_nearest(actor,elbow)
   var onward: Vector2=(Vector2(struck.pos)-elbow).normalized() if not struck.is_empty() and Vector2(struck.pos).distance_to(elbow)>1.0 else aim
   var far_end: Vector2=_ray_end(elbow,onward)
   var first_segment: int=telegraphs.size()
   _queue_attack(actor,"laser",at,elbow,0.6,damage,0.0,-1,mount)
   _queue_attack(actor,"laser",elbow,far_end,0.6,damage,0.0,-1,mount)
   # Retain two independent damage/warning records. Their fired presentation
   # is one polyline so the four pulses travel continuously around the bend.
   if telegraphs.size()>first_segment:
    telegraphs[first_segment].beam_path=[at,elbow]
    if telegraphs.size()>first_segment+1:
     telegraphs[first_segment].beam_path.append(far_end)
     telegraphs[first_segment+1].beam_continuation=true
  "incendiary_spores":
   # Three spores land around the aim point and each blooms into a small burning cloud.
   for i: int in range(3):
    var landing: Vector2=arena.clamp_point(at+aim.rotated((i-1)*0.45)*180.0)
    _queue_attack(actor,"spore",landing,Vector2.ZERO,0.8,damage,definition.range_pixels,-1,mount)
  "egg": pass # Reactive damage event activates this mount.
  "droid_bay": _spawn_drones(actor,2,damage,at)
  "deployment_ramp":
   var unit: Dictionary=_spawn_enemy(str(actor.element),maxi(1,int(actor.tier)-1),at+aim*60.0,false)
   if not unit.is_empty(): unit.reward_remaining=0
  "turret_ring":
   for i: int in range(6):
    var direction: Vector2=Vector2.from_angle(float(actor.age)*0.5+TAU*i/6.0)
    _shoot(actor,direction,250.0,damage,-1.0,0,at+direction*definition.range_pixels)
## Per-weapon visual size (spec §19 "projectile interiors ... above ~7 px").
## Collision radius (the 3.0 passed to `bullets.add` below) is UNCHANGED by
## this - only the drawn size moves, via `BulletPool.visual_radii`.
func _visual_radius(special: int) -> float:
 if (special & Pool.ROCKET)!=0: return 9.0
 if (special & Pool.HOMING)!=0: return 4.5
 if (special & Pool.RICOCHET)!=0: return 5.0
 if (special & Pool.CHAIN)!=0: return 3.5
 return 4.0
func _shoot(actor: Dictionary, direction: Vector2, speed: float, damage: float, life: float = -1.0, special: int = 0, at: Vector2 = Vector2.INF) -> int:
 var origin: Vector2=Vector2(actor.pos)+direction*8.0 if at==Vector2.INF else at
 return bullets.add(origin,direction.normalized()*speed,life,damage,3.0,int(actor.id),int(actor.faction),maxi(0,ELEMENTS.find(str(actor.element))),special,_visual_radius(special))
func _ray_end(at: Vector2, direction: Vector2) -> Vector2:
 var endpoint: Vector2=at+direction.normalized()*4000.0
 var hit: Dictionary=arena.boundary_hit(at,endpoint)
 return hit.get("point",endpoint)
func _beam(actor: Dictionary, id: String, dt: float, origin: Vector2 = Vector2.INF, direction: Vector2 = Vector2.INF) -> void:
 var at: Vector2=actor.pos if origin==Vector2.INF else origin
 var aim: Vector2=actor.aim if direction==Vector2.INF else direction
 var path: PackedVector2Array=[at]
 if id=="homing_beam":
  var target: Dictionary=_nearest(actor,at)
  if not target.is_empty():
   # Sample a quadratic curve; retarget every simulation tick at contact.
   var contact: Vector2=actor.get("beam_contact",at)
   target=_nearest(actor,contact)
   var end: Vector2=target.pos
   var control: Vector2=at+aim*minf(180.0,at.distance_to(end)*0.5)
   for i: int in range(1,13):
    var t: float=i/12.0
    path.append(at.lerp(control,t).lerp(control.lerp(end,t),t))
   actor.beam_contact=end
   path.append(_ray_end(end,(end-control).normalized()))
  else: path.append(_ray_end(at,aim))
 elif id=="ignition_lance":
  # A SHORT beam: it stops at its range, or at the wall if that is nearer.
  var wall: Vector2=_ray_end(at,aim)
  path.append(at+aim.normalized()*minf(_ability(id).range_pixels,at.distance_to(wall)))
 else: path.append(_ray_end(at,aim))
 var damage: float=_ability(id).damage*_damage_scale(actor)*dt
 var hit_ids: Dictionary={}
 for i: int in range(path.size()-1): _damage_segment(actor,path[i],path[i+1],damage,hit_ids)
 beams.append({"points":path,"faction":int(actor.faction),"element":str(actor.element)})
 # Beam interior (spec §19 table): "impact sparking continuously at the far
 # end" - one small burst per call would spam the pool at 60/s, so it is
 # throttled to ~10/s per actor via its own cooldown field.
 actor.beam_spark_cd=maxf(0.0,float(actor.get("beam_spark_cd",0.0))-dt)
 if float(actor.beam_spark_cd)<=0.0 and path.size()>0:
  actor.beam_spark_cd=0.1
  fx.emit("beam_spark",path[path.size()-1],Pool.BEAM_COLOR,_fx_rng,{"direction":Vector2(path[path.size()-1]-path[maxi(0,path.size()-2)])})
func _damage_segment(source: Dictionary, from: Vector2, to: Vector2, amount: float, hit_ids: Dictionary) -> void:
 for target: Dictionary in actors_by_id.values():
  if not _hostile(source,target): continue
  var rig: ShipMotion.ShipRig=target.get("rig")
  if rig!=null and int(target.id)!=0:
   for i: int in range(1,rig.ids.size()):
    if float(target.part_hp[i])<=0.0: continue
    var key: String="%d:%d" % [target.id,i]
    if not hit_ids.has(key) and Pool.segment_circle_t(from,to,_part_position(target,i),float(rig.radius[i])+2.0)>=0.0:
     _damage_part(target,i,amount,source)
     hit_ids[key]=true
  var core_key: String=str(target.id)
  if not hit_ids.has(core_key) and Pool.segment_circle_t(from,to,target.pos,5.0)>=0.0:
   _damage_actor(target,amount,int(source.id),int(source.faction))
   hit_ids[core_key]=true
func _part_position(actor: Dictionary, index: int) -> Vector2:
 var pose: ShipMotion.ShipPose=actor.get("pose")
 var local: Vector2=pose.local[index] if pose!=null and index>=0 and index<pose.local.size() else Vector2.ZERO
 return Vector2(actor.pos)+local.rotated(Vector2(actor.aim).angle()+PI/2.0)
func _gun_position(actor: Dictionary, gun: Dictionary) -> Vector2: return _part_position(actor,int(gun.get("index",-1)))
func _uses_follow_motion(actor: Dictionary) -> bool:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 return rig!=null and not rig.follow_indices.is_empty()
## Called after movement and heading integration, before any weapon reads its origin.
func _finish_follow_motion(actor: Dictionary) -> void:
 if not _uses_follow_motion(actor): return
 if (actor.pose as ShipMotion.ShipPose).chain_tick<tick: _step_motion(actor)
 else: _refresh_follow_pose(actor)
## Late external impulses re-anchor once more without ticking aim/feedback or advancing history.
func _refresh_follow_pose(actor: Dictionary) -> void:
 if not _uses_follow_motion(actor): return
 ShipMotion.step(actor.rig,actor.pose,tick,Vector2(actor.pos),Vector2(actor.aim).angle()+PI/2.0,actor.part_attached)
func _step_motion(actor: Dictionary) -> void:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 var pose: ShipMotion.ShipPose=actor.get("pose")
 if rig!=null and pose!=null and not rig.legacy: _slew_set_pieces(actor,rig,pose)
 if rig!=null and pose!=null: ShipMotion.step(rig,pose,tick,Vector2(actor.pos),Vector2(actor.aim).angle()+PI/2.0,actor.part_attached)
 # Target feedback (P8): `ShipMotion.step` always zeroes `pose.flare` (it is
 # a reserved slot with no sim-side owner of its own), so this actor's own
 # decaying `part_flare` is written in AFTER step, every tick, and handed to
 # the renderer separately (`ShipRenderer.part_flare`) since the renderer
 # keeps its own independent `ShipPose` for the mesh upload.
 if actor.has("part_flare"):
  # `.duplicate()` at every hand-off: a bare `pose.flare = flare` (sharing
  # the same PackedFloat32Array buffer) let `ShipMotion.step`'s own
  # `pose.flare[i] = 0.0` reach back and zero `actor.part_flare` too on the
  # VERY NEXT tick - PackedArray element writes do not reliably fork a
  # shared COW buffer the way whole-array reassignment does. Three
  # independent buffers (actor/pose/renderer) removes the aliasing outright.
  var flare: PackedFloat32Array=(actor.part_flare as PackedFloat32Array).duplicate()
  var decay: float=_last_dt/FLARE_DECAY_SECONDS
  for i: int in range(flare.size()): flare[i]=maxf(0.0,flare[i]-decay)
  actor.part_flare=flare
  if pose!=null and pose.flare.size()==flare.size(): pose.flare=flare.duplicate()
  var renderer: ShipRenderer=actor.get("renderer") as ShipRenderer
  if is_instance_valid(renderer):
   renderer.part_flare=flare.duplicate()
   # One pose per actor: the renderer draws from THIS pose instead of evaluating its own copy.
   # Handed over every tick because a hull swap replaces both the actor's pose and the renderer's
   # rig. Shared on purpose and safe: the renderer only reads it (the aliasing lesson is about a
   # second WRITER).
   renderer.external_pose=pose
## Spec §9.7: a set piece does not spin with its rail; it swings to track the aim at no more than
## 3.0 rad/s, and with nothing to aim at it returns to pointing outward. The heading is state, so
## it lives here, stepped once per sim tick, and the pose only reads it. WHAT a gun aims at is
## unchanged (its hub's `part_aim`, or the hull's aim for the player and regulars): the marking
## slews toward it, the shot still leaves along the sim's aim.
func _slew_set_pieces(actor: Dictionary, rig: ShipMotion.ShipRig, pose: ShipMotion.ShipPose) -> void:
 var hull: float=Vector2(actor.aim).angle()
 var limit: float=float(ShipGrammar.MOTION.aim_slew)*_last_dt
 var guns: PackedInt32Array=actor.get("gun_indices",PackedInt32Array())
 for joint: int in rig.aim_indices:
  var hub: int=rig.parent_index[joint]
  var outward: float=(pose.angle[hub] if hub<pose.angle.size() else 0.0)+rig.rest_heading[joint]
  var wants: Vector2=Vector2(actor.aim)
  if int(actor.id)!=0 and guns.has(hub): wants=Vector2(actor.part_aim[hub])
  # Headings are clockwise from the hull's forward; the hull itself is drawn turned to `actor.aim`.
  var target: float=outward if wants==Vector2.ZERO else wrapf(wants.angle()-hull,-PI,PI)
  var current: float=pose.aim_angle[joint]
  if is_nan(current): current=outward
  pose.aim_angle[joint]=rotate_toward(current,target,limit)

func _local_position(actor: Dictionary, id: String, fallback: Vector2) -> Vector2:
 # Fire from where the circle actually is: an orbiting group moves a mount
 # or gun exactly as far as the renderer moves it, both driven by the same
 # tick (ShipMotion). A hull with no groups on this part returns `fallback`
 # unchanged, so the golden trace cannot move for content that never orbits.
 var rig: ShipMotion.ShipRig=actor.get("rig")
 var pose: ShipMotion.ShipPose=actor.get("pose")
 if rig==null or pose==null: return fallback
 var index: int=rig.index_of(id)
 return pose.local[index] if index>=0 else fallback
## `new_decision` gates whether aim is re-measured this call (spec §14/§23:
## per-circle aim is resampled once per DECISION, 150-300 ms apart, with its
## own 2-5 deg error - never every tick, and never a per-frame allocation:
## `part_aim`/`part_aim_error` are the same packed arrays every call). Callers
## outside `combat_ai.gd` (tests, tools) that pass no third argument keep the
## old always-refresh behaviour so they are unaffected by this change.
func _update_guns(actor: Dictionary, dt: float, new_decision: bool = true) -> void:
 if ai_firing_disabled: return
 var rig: ShipMotion.ShipRig=actor.rig
 for index: int in actor.gun_indices:
  if float(actor.part_hp[index])<=0.0: continue
  var at: Vector2=_part_position(actor,index)
  if new_decision:
   var target: Dictionary=_nearest(actor,at)
   if target.is_empty(): continue
   var observed: Vector2=Vector2(target.pos) if bool(ai_reaction_disabled) or not actor.has("_delayed_pos") else Vector2(actor._delayed_pos)
   var error: float=0.0 if bool(ai_aim_error_disabled) else CombatAI.sample_aim_error(_rng)
   actor.part_aim_error[index]=error
   actor.part_aim[index]=(observed-at).normalized().rotated(error)
  var id: String=rig.ability_id[index]
  if id in ["beam","homing_beam"]:
   # Enemy continuous beams pulse between readable windows.
   var beam_phase: float=float(actor.age)+float(actor.part_max_hp[index])
   if fmod(beam_phase,3.0)<0.7:
    var windows: Dictionary=actor.get("_beam_visual_windows",{})
    var window: int=floori(beam_phase/3.0)
    if int(windows.get(rig.ids[index],-1))!=window:
     windows[rig.ids[index]]=window
     actor._beam_visual_windows=windows
     _emit_muzzle(actor,id,at,rig.ids[index])
    _beam(actor,id,dt,at,actor.part_aim[index])
  elif float(actor.part_cd[index])<=0.0:
   actor.part_cd[index]=maxf(0.55,_ability(id).cooldown*(2.5 if _ability(id).slot_kind=="primary" else 1.0))
   _activate_component(actor,id,at,actor.part_aim[index],rig.ids[index],rig.ids[index])
## Single choke point (spec item 3): damages one circle, and on death removes
## its collider, snaps its lines and detaches its subtree as one debris
## record via `_destroy_part`. Called from bullet/beam/radial damage and from
## the `_damage_gun` compatibility wrapper kept for existing call sites.
func _damage_part(actor: Dictionary, index: int, amount: float, source: Dictionary) -> void:
 if amount<=0.0 or index<=0 or index>=actor.part_hp.size() or float(actor.part_hp[index])<=0.0: return
 var rig: ShipMotion.ShipRig=actor.rig
 if rig.ability_id[index]=="egg" and not ai_firing_disabled and float(actor.part_egg_cd[index])<=0.0:
  actor.part_egg_cd[index]=2.0
  var aim: Vector2=actor.part_aim[index]
  for i: int in range(7): _shoot(actor,aim.rotated((i-3)*0.25),330.0,15.0,-1.0,Pool.HOMING,_part_position(actor,index))
 actor.part_hp[index]=maxf(0.0,float(actor.part_hp[index])-amount)
 _flare(actor,index)
 _maybe_collar(_part_position(actor,index),amount)
 if float(actor.part_hp[index])<=0.0:
  for i: int in range(telegraphs.size()-1,-1,-1):
   if int(telegraphs[i].owner)==int(actor.id) and str(telegraphs[i].mount)==str(rig.ids[index]): telegraphs.remove_at(i)
  _add_effect("gun_destroyed",_part_position(actor,index),_actor_color(actor),0.4,float(rig.radius[index]))
  _destroy_part(actor,index,source)
  # A boss whose core already sat at 0 hp waiting on its last sub_core (see
  # `_damage_actor`) dies the instant that sub_core does, not on some later
  # incidental core hit that may never come.
  if float(actor.hp)<=0.0 and not bool(actor.dead) and index in actor.get("sub_core_indices",PackedInt32Array()) and _boss_can_die(actor):
   actor.dead=true
   _kill_reward(actor,int(source.get("id",-1)),int(source.get("faction",-999)))
func _damage_gun(actor: Dictionary, gun: Dictionary, amount: float, source: Dictionary) -> void:
 # Compatibility wrapper: `gun` is a snapshot Dictionary from `actor.guns`
 # (see `_rebuild_part_views`); the packed arrays remain the source of truth.
 var index: int=int(gun.get("index",-1))
 if index<0: return
 _damage_part(actor,index,amount,source)
 gun.hp=float(actor.part_hp[index]) if index<actor.part_hp.size() else 0.0
## Detachment (spec §14/§19). The whole subtree rooted at `index` is a
## contiguous rig range (`ShipMotion.ShipRig.subtree_size`), so this is a
## range operation, not a second graph walk. Anything in the range still
## attached detaches as ONE debris record; its light is the sum of the
## per-circle reward shares reserved for those circles at spawn.
func _destroy_part(actor: Dictionary, index: int, _source: Dictionary) -> void:
 var rig: ShipMotion.ShipRig=actor.rig
 if index<=0 or index>=rig.ids.size() or not bool(actor.part_attached[index]): return
 var last: int=index+rig.subtree_size[index]
 var hidden: PackedStringArray=actor.get("hidden_ids",PackedStringArray())
 var offsets: PackedVector2Array=PackedVector2Array()
 var radii: PackedFloat32Array=PackedFloat32Array()
 var light: float=0.0
 var pose: ShipMotion.ShipPose=actor.pose
 var attached_before: PackedByteArray=actor.part_attached.duplicate()
 for i: int in range(index,last):
  if not bool(actor.part_attached[i]): continue
  actor.part_attached[i]=0
  actor.part_hp[i]=0.0
  hidden.append(rig.ids[i])
  offsets.append(pose.local[i] if pose!=null and i<pose.local.size() else rig.rest[i])
  radii.append(rig.radius[i])
  if i<actor.part_reward_share.size(): light+=float(actor.part_reward_share[i])
 for k: int in range(rig.line_from.size()):
  var lf: int=rig.line_from[k]
  var lt: int=rig.line_to[k]
  if (lf>=index and lf<last) or (lt>=index and lt<last):
   hidden.append(rig.line_ids[k])
   # "Its lines snap from both ends" (spec §19 "destruction").
   var from_pos: Vector2=_part_position(actor,lf)
   var to_pos: Vector2=_part_position(actor,lt)
   fx.emit("line_snap",from_pos,_actor_color(actor),_fx_rng,{"to":to_pos})
 if not rig.legacy:
  # A rail goes with its last cluster (spec §9.8). This function keeps its own hidden list, so the
  # rule has to run HERE as well as in _rebuild_part_views, or the ring outlives its rail on screen.
  _retire_dead_rails(actor,rig)
  for i: int in range(1,rig.ids.size()):
   if rig.solid[i]==0 and not bool(actor.part_attached[i]) and not hidden.has(rig.ids[i]): hidden.append(rig.ids[i])
 actor.hidden_ids=hidden
 if offsets.is_empty(): return
 actor.reward_unpaid_limb=maxf(0.0,float(actor.get("reward_unpaid_limb",0.0))-light)
 # The debris payout applies the same tier-gap multiplier a core kill does
 # (_kill_reward), so total light emitted does not depend on whether a limb
 # was paid out early (debris) or folded into the core-kill pool (spec item
 # 5/conservation). `reward_unpaid_limb` above stays in unmultiplied terms.
 var paid_light: float=light*_reward_multiplier(actor)
 var debris_rng: RandomNumberGenerator=RandomNumberGenerator.new()
 debris_rng.seed=hash([int(actor.get("part_seed",0)),int(actor.id),str(actor.definition.id),str(rig.ids[index]),tick])
 var piece: Dictionary={"offsets":offsets,"radii":radii,"color":_actor_color(actor),"element":str(actor.element),"position":Vector2(actor.pos),"velocity":Vector2(actor.vel),"angle":Vector2(actor.aim).angle()+PI/2.0,"spin":0.0,"age":0.0,"life":1.0,"light":paid_light}
 var rail_rig: ShipMotion.ShipRig=actor.get("rig")
 if rail_rig!=null and not rail_rig.legacy:
  # Spec §9.8: the detached subtree keeps its rail's velocity, gets a random spread, drifts
  # outward, spins at 0.5-1.5 rad/s and drops its light HALFWAY through its 1.0 s fade.
  var motion: Dictionary=ShipGrammar.MOTION
  var basis: float=Vector2(actor.aim).angle()+PI/2.0
  var arm: Vector2=(actor.pose as ShipMotion.ShipPose).local[index].rotated(basis)
  piece.velocity=Vector2(actor.vel)+arm.orthogonal()*-rail_rig.spin_speed[index]+Vector2.from_angle(debris_rng.randf()*TAU)*float(motion.debris_spread)*debris_rng.randf()
  piece.spin=debris_rng.randf_range(float(motion.debris_spin_min),float(motion.debris_spin_max))*(1.0 if debris_rng.randf()<0.5 else -1.0)
  piece.outward=arm.normalized()*float(motion.debris_outward_accel)
  piece.life=1.4
  piece.light_at=float(motion.debris_light_drop_seconds)
 else:
  piece.spin=debris_rng.randf_range(-1.2,1.2)
 if not piece.has("light_at"): piece.light_at=piece.life
 piece.release_delay=0.35
 piece.fade_duration=1.4
 piece.life=float(piece.release_delay)+float(piece.fade_duration)
 piece.pieces=_debris_circles(actor,index,last,pose,attached_before,debris_rng)
 debris.append(piece)

## One independently drifting body per surviving solid circle. Nested markings stay with their
## host, retaining their exact colour, radius and offset. The destroyed junction itself is gone.
func _debris_circles(actor: Dictionary, first: int, last: int, pose: ShipMotion.ShipPose, attached_before: PackedByteArray, rng: RandomNumberGenerator) -> Array:
 var rig: ShipMotion.ShipRig=actor.rig
 var definition: ShipDefinition=actor.definition
 var by_id: Dictionary={}
 for part: PartDefinition in definition.parts:
  if part.shape=="circle": by_id[part.id]=part
 var bodies: Dictionary={}
 var owners: Dictionary={}
 var basis: float=Vector2(actor.aim).angle()+PI/2.0
 for index: int in range(first+1,last):
  if attached_before[index]==0: continue
  if not by_id.has(rig.ids[index]): continue
  var part: PartDefinition=by_id[rig.ids[index]]
  if part.dashed or part.layer==0: continue
  var host: int=index
  while host>first and rig.solid[host]==0: host=rig.parent_index[host]
  if host<=first: continue
  if not bodies.has(host):
   var origin: Vector2=Vector2(actor.pos)+pose.local[host].rotated(basis)
   var velocity: Vector2=pose.world_velocity[host] if pose.world_tick>=0 else Vector2(actor.vel)
   var scatter: Vector2=Vector2(rng.randf_range(-42.0,42.0),rng.randf_range(30.0,66.0)).rotated(basis)
   bodies[host]={"position":origin,"velocity":velocity+scatter,"spin":rng.randf_range(-1.5,1.5),"angle":0.0,"outward":(origin-Vector2(actor.pos)).normalized()*float(ShipGrammar.MOTION.debris_outward_accel),"circles":[],"lines":[]}
  owners[index]=host
  var role: String=part.color_role
  if role=="chassis": role="player" if definition.is_player else definition.element
  var body: Dictionary=bodies[host]
  body.circles.append({"offset":(pose.local[index]-pose.local[host]).rotated(basis),"radius":part.radius,"filled":part.filled,"color":ShipCatalog.get_color(role),"fill":ShipCatalog.FILLS.get(role,VisualStyle.BG),"light":ShipCatalog.LIGHTS.get(role,Color.WHITE),"period":part.light_period,"phase":part.light_phase+elapsed})
 for part: PartDefinition in definition.parts:
  if part.shape!="line": continue
  var from_index: int=rig.index_of(part.from_id)
  var to_index: int=rig.index_of(part.to_id)
  if not owners.has(from_index) or not owners.has(to_index) or owners[from_index]!=owners[to_index]: continue
  var host: int=int(owners[from_index])
  var role: String=part.color_role
  if role=="chassis": role="player" if definition.is_player else definition.element
  bodies[host].lines.append({"from":(pose.local[from_index]-pose.local[host]).rotated(basis),"to":(pose.local[to_index]-pose.local[host]).rotated(basis),"color":ShipCatalog.get_color(role)})
 return bodies.values()

func _update_debris(dt: float) -> void:
 for i: int in range(debris.size()-1,-1,-1):
  var d: Dictionary=debris[i]
  d.age=float(d.age)+dt
  if d.has("outward"): d.velocity=Vector2(d.velocity)+Vector2(d.outward)*dt
  d.position=Vector2(d.position)+Vector2(d.velocity)*dt
  d.angle=float(d.angle)+float(d.spin)*dt
  if d.has("pieces") and float(d.age)>float(d.release_delay):
   var active_dt: float=minf(dt,float(d.age)-float(d.release_delay))
   for body: Dictionary in d.pieces:
    body.velocity=Vector2(body.velocity)+Vector2(body.outward)*active_dt
    body.position=Vector2(body.position)+Vector2(body.velocity)*active_dt
    body.angle=float(body.angle)+float(body.spin)*active_dt
  # A rail hull's debris drops its light at 0.5 s and goes on fading to 1.75 s; v0.3
  # debris pays at the end of its life. Either way it pays exactly once: `light` is zeroed.
  if float(d.age)>=float(d.get("light_at",d.life)) and float(d.light)>0.0:
   for size: int in _pickup_sizes(maxi(0,roundi(float(d.light)))): _drop_pickup(d.position,str(d.element),size,true)
   d.light=0.0
  if float(d.age)>=float(d.life):
   debris.remove_at(i)
## Debris must not silently lose light on a node exit mid-fade: whatever has
## not finished its fade yet pays out immediately as a pickup. Called
## before a sector is cleared/cached and before every snapshot, so light is
## conserved whether the fight continues, is saved, or the node is left.
func _flush_debris() -> void:
 for d: Dictionary in debris:
  for size: int in _pickup_sizes(maxi(0,roundi(float(d.light)))): _drop_pickup(d.position,str(d.element),size,true)
 debris.clear()
func _passives(actor: Dictionary, dt: float) -> void:
 if _has_ability(actor,"orbital_seekers"):
  if float(actor.orbit_cd)<=0.0 and int(actor.orbit_stock)<3:
   actor.orbit_stock=int(actor.orbit_stock)+1
   actor.orbit_cd=1.0
  var target: Dictionary=_nearest(actor,actor.pos)
  if not target.is_empty() and Vector2(target.pos).distance_to(actor.pos)<320.0 and int(actor.orbit_stock)>0:
   _shoot(actor,(Vector2(target.pos)-Vector2(actor.pos)).normalized(),320.0,_ability("orbital_seekers").damage*_damage_scale(actor),-1.0,Pool.HOMING)
   actor.orbit_stock=int(actor.orbit_stock)-1
 if _has_ability(actor,"forcefield"): _radial_damage(actor,actor.pos,45.0,18.0*_damage_scale(actor)*dt)
 # Element pattern identity for regular enemies is separate from player presets.
 if actor.get("body_features",{}).has("void_pull"):
  for target: Dictionary in _hostiles(actor):
   var toward: Vector2=Vector2(actor.pos)-Vector2(target.pos)
   if toward.length_squared()<pow(float(actor.body_features.void_pull.value),2):
    target.pos=arena.clamp_point(Vector2(target.pos)+toward.normalized()*35.0*dt,3.0)
    _refresh_follow_pose(target)
func _slow_multiplier(actor: Dictionary) -> float: return 0.7 if float(actor.get("slow",0.0))>0.0 else 1.0
func _update_actor_status(actor: Dictionary, dt: float) -> void:
 actor.slow=maxf(0.0,float(actor.slow)-dt)
 if int(actor.id)!=0: actor.invulnerable=maxf(0.0,float(actor.invulnerable)-dt)
 if float(actor.get("infected",0.0))>0.0:
  actor.infected=maxf(0.0,float(actor.infected)-dt)
  _damage_actor(actor,float(actor.get("infection_damage",3.0))*dt,int(actor.get("infection_owner",-1)),int(actor.get("infection_faction",-1)))
 # Absorption is the only healing path. No delayed or passive regeneration.
## Spec §7, one system: decay, combo drain and enemy respawn all live here,
## called once per tick from _physics_process right after actor status.
func _update_pace(dt: float) -> void:
 if not active or player.is_empty(): return
 # Combo (spec §7.2): the 2.5s window resets on every kill (_kill_reward);
 # once it expires the count drains 1 per 0.25s instead of resetting hard.
 if combo_timer>0.0:
  combo_timer=maxf(0.0,combo_timer-dt)
 elif combo_count>0:
  _combo_drain_accum+=dt
  while _combo_drain_accum>=GameTuning.COMBO_DRAIN_INTERVAL_SECONDS and combo_count>0:
   combo_count-=1
   _combo_drain_accum-=GameTuning.COMBO_DRAIN_INTERVAL_SECONDS
 else:
  _combo_drain_accum=0.0
 # Decay (spec §7.1): 0.4%/s of the CURRENT TIER'S MAXIMUM, suppressed for
 # 3s after any kill or absorb, inactive during the reshape and the warp
 # lock (both invulnerable set-pieces, not "idling"). Floors at DECAY_FLOOR
 # and can regress a tier, but per the approved preamble can never kill.
 decay_suppress_timer=maxf(0.0,decay_suppress_timer-dt)
 if decay_suppress_timer<=0.0 and reshape_remaining<=0.0 and not warp_locked():
  var rate: float=GameTuning.DECAY_RATE_PER_SECOND*GameTuning.capacity(player_tier,max_player_tier)
  if light_total>GameTuning.DECAY_FLOOR:
   light_total=maxf(GameTuning.DECAY_FLOOR,light_total-rate*dt)
   player.hp=light_total
   _check_regression()
 _update_respawns(dt)
## Spec §7.3: "enemies respawn on a cooldown; the pool does not follow" - a
## defeated enemy comes back on ENEMY_RESPAWN_COOLDOWN regardless of how
## depleted the node's light pool is; what depletes is the LOOT (routed
## through _spend_energy/_drop_pickup), not the enemy count. Bosses never
## respawn (spec §14 "no respawn"); their kind never appends to the list.
func _update_respawns(dt: float) -> void:
 if _dead_enemy_records.is_empty(): return
 _respawn_timer-=dt
 if _respawn_timer>0.0: return
 _respawn_timer=GameTuning.ENEMY_RESPAWN_COOLDOWN
 var record: Dictionary=_dead_enemy_records.pop_front()
 var point: Vector2=arena.center+Vector2.from_angle(_rng.randf()*TAU)*arena.radius*0.85
 if point.distance_to(player.pos)<400.0: point=arena.center*2.0-point
 var spawned: Dictionary=_spawn_named_enemy(str(record.hull_id),str(record.element),int(record.tier),point,false,bool(record.elite))
 if not spawned.is_empty(): _add_effect("spawn",point,_actor_color(spawned),0.5,40.0)
func _attach_virus(source: Dictionary, target_id: int, damage: float, generation: int) -> void:
 if viruses.size()<128: viruses.append({"target":target_id,"damage":damage,"generation":generation,"owner":int(source.id),"faction":int(source.faction),"element":str(source.element),"pos":actors_by_id[target_id].pos})
func _update_viruses(dt: float) -> void:
 for i: int in range(viruses.size()-1,-1,-1):
  var virus: Dictionary=viruses[i]
  var target: Dictionary=actors_by_id.get(int(virus.target),{})
  var source: Dictionary={"id":int(virus.owner),"faction":int(virus.faction),"element":str(virus.element)}
  if target.is_empty() or bool(target.dead):
   viruses.remove_at(i)
   if int(virus.generation)<2:
    var excluded: Array=[]
    for child: int in range(2):
     var next: Dictionary=_nearest(source,virus.pos,excluded)
     if next.is_empty(): break
     excluded.append(int(next.id))
     _attach_virus(source,int(next.id),float(virus.damage)*0.5,int(virus.generation)+1)
   continue
  virus.pos=target.pos
  if virus.has("kind"):
   # A tether (ship design spec: arc_tether, siphon_tether, siphon_leech). It lasts `time`, snaps
   # past `break_range`, and an ENEMY's tether spends `warn` seconds drawing in before it hurts, so
   # the player can break away on reaction (v0.3 §16). It never splits.
   var caster: Dictionary=actors_by_id.get(int(virus.owner),{})
   virus.time=float(virus.time)-dt
   var snapped: bool=caster.is_empty() or bool(caster.get("dead",false)) or Vector2(caster.pos).distance_to(target.pos)>float(virus.break_range)
   if float(virus.time)<=0.0 or snapped:
    viruses.remove_at(i)
    continue
   virus.warn=float(virus.warn)-dt
   if float(virus.warn)>0.0: continue
   var drained: float=float(virus.damage)*dt
   _damage_actor(target,drained,int(virus.owner),int(virus.faction))
   # The two siphons give some of it back: light to the player, hull to an enemy.
   if str(virus.kind)=="siphon_tether" and int(virus.owner)==0: collect_light(drained*0.25,str(target.get("element","neutral")))
   elif str(virus.kind)=="siphon_leech" and not caster.is_empty(): caster.hp=minf(float(caster.max_hp),float(caster.hp)+drained*0.5)
   continue
  # A plain virus latches "until it dies" - which on the PLAYER meant for ever. It now lets go of
  # the player after four seconds; on enemies it is unchanged.
  if int(virus.target)==0:
   virus.held=float(virus.get("held",0.0))+dt
   if float(virus.held)>=4.0:
    viruses.remove_at(i)
    continue
  _damage_actor(target,float(virus.damage)*dt,int(virus.owner),int(virus.faction))
func _update_clouds(dt: float) -> void:
 for i: int in range(clouds.size()-1,-1,-1):
  var cloud: Dictionary=clouds[i]
  cloud.time=float(cloud.time)-dt
  var source: Dictionary={"id":cloud.owner,"faction":cloud.faction}
  for target: Dictionary in _hostiles(source):
   if Vector2(target.pos).distance_to(cloud.pos)<float(cloud.radius):
    target.slow=0.12
    _damage_actor(target,float(cloud.damage)*dt,int(cloud.owner),int(cloud.faction))
  if float(cloud.time)<=0.0: clouds.remove_at(i)
func _queue_attack(actor: Dictionary, kind: String, from: Vector2, to: Vector2, warn: float, damage: float, radius: float = 0.0, target: int = -1, mount: String = "") -> void:
 if telegraphs.size()>=160: return
 telegraphs.append({"kind":kind,"from":from,"to":to,"time":warn,"warn":warn,"damage":damage,"radius":radius,"owner":int(actor.id),"faction":int(actor.faction),"element":str(actor.element),"target":target,"mount":mount,"fired":false,"hold":0.25,"hit_ids":{}})
func _update_telegraphs(dt: float) -> void:
 for i: int in range(telegraphs.size()-1,-1,-1):
  var attack: Dictionary=telegraphs[i]
  attack.time=float(attack.time)-dt
  var owner: Dictionary=actors_by_id.get(int(attack.owner),{})
  if owner.is_empty() or bool(owner.dead):
   telegraphs.remove_at(i)
   continue
  if float(attack.time)<=0.0:
   if not bool(attack.fired):
    attack.fired=true
    if attack.kind=="mine": bullets.add(attack.from,Vector2.ZERO,12.0,float(attack.damage),float(attack.radius),int(attack.owner),int(attack.faction),maxi(0,ELEMENTS.find(attack.element)),Pool.MINE)
    # `nova_pulse`: after its warning, two staggered rings of twelve shots from where it was cast.
    elif attack.kind=="nova":
     for ring: int in range(2):
      for shot: int in range(12):
       bullets.add(attack.from,Vector2.from_angle(TAU*(float(shot)+0.5*float(ring))/12.0)*(230.0-40.0*float(ring)),-1.0,float(attack.damage),3.0,int(attack.owner),int(attack.faction),maxi(0,ELEMENTS.find(attack.element)),0)
    # `incendiary_spores`: each spore blooms into a small burning cloud where it lands.
    elif attack.kind=="spore" and clouds.size()<80:
     clouds.append({"pos":attack.from,"radius":float(attack.radius),"time":3.0,"damage":float(attack.damage),"owner":int(attack.owner),"faction":int(attack.faction),"element":str(attack.element)})
   if attack.kind=="laser": _damage_segment(owner,attack.from,attack.to,float(attack.damage),attack.hit_ids)
   elif attack.kind=="explosive":
    for target: Dictionary in _hostiles(owner):
     var key: String=str(target.id)
     if not attack.hit_ids.has(key) and Vector2(target.pos).distance_to(attack.from)<=float(attack.radius):
      _damage_actor(target,float(attack.damage),int(attack.owner),int(attack.faction))
      attack.hit_ids[key]=true
  if float(attack.time)<=-float(attack.hold): telegraphs.remove_at(i)
func _radial_damage(actor: Dictionary, at: Vector2, radius: float, amount: float) -> void:
 for target: Dictionary in _hostiles(actor):
  if Vector2(target.pos).distance_to(at)<=radius: _damage_actor(target,amount,int(actor.id),int(actor.faction))
  var rig: ShipMotion.ShipRig=target.get("rig")
  if rig!=null and int(target.id)!=0:
   for i: int in range(1,rig.ids.size()):
    if float(target.part_hp[i])>0.0 and _part_position(target,i).distance_to(at)<=radius: _damage_part(target,i,amount,actor)
func _spawn_drones(actor: Dictionary, count: int, damage: float = 24.0, at: Vector2 = Vector2.INF) -> void:
 for i: int in range(count):
  if drones.size()>=MAX_DRONES: break
  drones.append({"pos":Vector2(actor.pos) if at==Vector2.INF else at,"owner":int(actor.id),"faction":int(actor.faction),"element":str(actor.element),"damage":damage,"hp":40.0,"time":20.0,"phase":_rng.randf()*TAU})
func _update_drones(dt: float) -> void:
 for i: int in range(drones.size()-1,-1,-1):
  var drone: Dictionary=drones[i]
  drone.time=float(drone.time)-dt
  var source: Dictionary={"id":drone.owner,"faction":drone.faction}
  var target: Dictionary=_nearest(source,drone.pos)
  if not target.is_empty():
   drone.pos=Vector2(drone.pos).move_toward(target.pos,dt*170.0)
   if Vector2(drone.pos).distance_to(target.pos)<14.0:
    _damage_actor(target,float(drone.damage),int(drone.owner),int(drone.faction))
    drone.hp=0.0
  if float(drone.time)<=0.0 or float(drone.hp)<=0.0: drones.remove_at(i)

## `black_hole_shot`: a slow shot that drags hostiles toward itself while it lives. Kept OUT of the
## per-bullet hot loop: it runs only while a black hole exists, and recounts them as it goes so the
## counter cannot drift when one expires or hits something.
const BLACK_HOLE_REACH: float = 171.0 # the reach the projectile shader already draws
const BLACK_HOLE_PULL: float = 60.0   # px/s
func _update_black_holes(dt: float) -> void:
 if black_holes<=0: return
 var alive: int=0
 for index: int in bullets.active_indices:
  if (bullets.flags[index] & Pool.BLACK_HOLE)==0: continue
  alive+=1
  var at: Vector2=bullets.positions[index]
  var source: Dictionary={"id":bullets.owners[index],"faction":bullets.factions[index]}
  for target: Dictionary in _hostiles(source):
   var gap: Vector2=at-Vector2(target.pos)
   if gap.length()>BLACK_HOLE_REACH or gap.length()<4.0: continue
   var pulled: Vector2=arena.clamp_point(Vector2(target.pos)+gap.normalized()*BLACK_HOLE_PULL*dt)
   target.pos=pulled
   _refresh_follow_pose(target)
   if int(target.id)==0: player_position=pulled
 black_holes=alive

func _rebuild_actor_grid() -> void: _broadphase.rebuild()
func _update_bullets(dt: float) -> void:
 for slot: int in range(bullets.active_indices.size()-1,-1,-1):
  var index: int=bullets.active_indices[slot]
  var flag: int=bullets.flags[index]
  var from: Vector2=bullets.positions[index]
  var velocity: Vector2=bullets.velocities[index]
  var source: Dictionary=_shot_source
  if (flag & (Pool.HOMING|Pool.MINE))!=0: _prepare_shot_source(index)
  if (flag & Pool.HOMING)!=0:
   var target: Dictionary=_nearest(source,from)
   if not target.is_empty():
    var angle: float=rotate_toward(velocity.angle(),(Vector2(target.pos)-from).angle(),2.8*dt)
    # Path identity (spec §19 table): "weaving sine, tightening near the
    # target" - the weave's own amplitude shrinks as range closes, so the
    # seeker still reads as a seeker right up to impact but does not swing
    # wildly at point-blank range.
    var tighten: float=clampf(Vector2(target.pos).distance_to(from)/220.0,0.15,1.0)
    angle+=sin(elapsed*9.0+index*2.3)*0.35*tighten
    velocity=Vector2.from_angle(angle)*velocity.length()
  if (flag & Pool.WANDER)!=0:
   # Path identity: rocket's "slow wallow, wide curve" - slower and wider
   # than a generic wander would be (WANDER is only ever paired with ROCKET,
   # see `_activate_component`'s `rocket_launcher` case).
   velocity=velocity.rotated(sin(elapsed*1.6+index*1.7)*2.2*dt)
  bullets.velocities[index]=velocity
  if bullets.lives[index]>=0.0:
   bullets.lives[index]-=dt
   if bullets.lives[index]<=0.0:
    bullets.remove_at(slot)
    continue
  if (flag & Pool.MINE)!=0:
   var target: Dictionary=_nearest(source,from)
   if not target.is_empty() and Vector2(target.pos).distance_to(from)<bullets.radii[index]:
    _radial_damage(source,from,bullets.radii[index],bullets.damages[index])
    _add_effect("explosion",from,COLORS[bullets.elements[index]],0.25,bullets.radii[index])
    bullets.remove_at(slot)
   continue
  bullets.previous[index]=from
  var remaining: float=dt
  bullets.ages[index]+=dt
  if (flag & Pool.ORBIT)!=0:
   var owner: Dictionary=actors_by_id.get(bullets.owners[index],{})
   if bullets.ages[index]<1.5 and not owner.is_empty():
    var orbit_radius: float=float(owner.get("body_features",{}).get("projectile_orbit",{}).get("value",65.0))
    var orbital: Vector2=Vector2(owner.pos)+Vector2.from_angle(elapsed*2.5+index*1.1)*orbit_radius
    velocity=(orbital-from)/maxf(dt,0.000001)
   else:
    velocity=Vector2.from_angle(elapsed*2.5+index*1.1+PI/2.0)*250.0
    bullets.flags[index]=flag & ~Pool.ORBIT
  var removed: bool=false
  # Sweep each reflected segment, so a fast shot cannot hit through a corner.
  for bounce: int in range(8):
   var to: Vector2=from+velocity*remaining
   var wall: Dictionary=arena.boundary_hit(from,to,bullets.radii[index])
   if not wall.is_empty(): to=wall.point
   var nearest: float=INF
   var hit: Dictionary={}
   var hit_part: int=0
   for c: Dictionary in _broadphase.query_segment(from,to,bullets.radii[index]):
    var faction: int=int(c.drone.faction) if not c.drone.is_empty() else int(c.actor.faction)
    if faction==bullets.factions[index]: continue
    if not c.actor.is_empty() and bool(c.actor.dead): continue
    if bool(c.get("void_eater",false)) and (from-Vector2(c.actor.pos)).dot(Vector2(c.actor.aim))<0.0: continue
    var t: float=Pool.segment_circle_t(from,to,c.pos,float(c.radius)+bullets.radii[index])
    if t<0.0: continue
    if int(c.get("part_index",0))>0 and float(c.actor.part_hp[int(c.part_index)])<=0.0: continue
    # `phase_shot` ignores limbs: it reaches the core through the armour (a blocker still stops it).
    if (flag & Pool.PHASE)!=0 and int(c.get("part_index",0))>0: continue
    if t<nearest:
     nearest=t
     hit=c
     hit_part=int(c.get("part_index",0))
   if not hit.is_empty():
    _prepare_shot_source(index)
    var impact_point: Vector2=from.lerp(to,nearest)
    var bullet_color: Color=Pool.projectile_color(flag)
    # Shot beat 3 (spec §19.1/Appendix B): two rings plus 5-7 decelerating
    # fragments thrown ALONG THE INCOMING VECTOR.
    fx.emit("impact",impact_point,bullet_color,_fx_rng,{"direction":velocity})
    if not hit.drone.is_empty(): hit.drone.hp=float(hit.drone.hp)-bullets.damages[index]
    elif bool(hit.get("blocker",false)):
     hit.actor.blocker_hits=maxi(0,int(hit.actor.blocker_hits)-1)
    elif float(hit.actor.shield)>0.0 or bool(hit.get("void_eater",false)): pass
    elif hit_part>0: _damage_part(hit.actor,hit_part,bullets.damages[index],source)
    else:
     _damage_actor(hit.actor,bullets.damages[index],bullets.owners[index],bullets.factions[index])
     if (flag & Pool.INFECT)!=0: _infect(hit.actor,source,3.0,3.0)
     if (flag & Pool.CHAIN)!=0:
      var target: Dictionary=_nearest(source,hit.actor.pos,[int(hit.actor.id)])
      if not target.is_empty() and Vector2(target.pos).distance_to(hit.actor.pos)<=180.0:
       _damage_actor(target,bullets.damages[index]*0.65,bullets.owners[index],bullets.factions[index])
       _add_line_effect(hit.actor.pos,target.pos,bullet_color,0.15)
    if (flag & Pool.ROCKET)!=0: _radial_damage(source,impact_point,55.0,bullets.damages[index]*0.5)
    bullets.remove_at(slot)
    removed=true
    break
   if wall.is_empty():
    from=to
    break
   if (flag & Pool.RICOCHET)==0:
    bullets.remove_at(slot)
    removed=true
    break
   var normal: Vector2=wall.normal
   velocity=velocity.bounce(normal)
   remaining*=1.0-float(wall.t)
   from=Vector2(wall.point)-normal*0.01
   # Path identity: "hard bounces off the rim, fragments thrown on each
   # bounce" and the trail "kinks at each bounce" (spec §19 table).
   fx.emit("impact",Vector2(wall.point),Pool.RICOCHET_COLOR,_fx_rng,{"direction":normal})
   bullets.positions[index]=wall.point
   bullets.sample_history(index) # retain the actual corner, not a shortcut across it
   if remaining<=0.000001: break
  if not removed:
   bullets.positions[index]=from
   bullets.velocities[index]=velocity
   bullets.sample_history(index)
## Spec §16: "Contact with an enemy body damages the core" - the enemy's
## whole visible hull, not just its core centre. `_rebuild_actor_grid()`
## (run earlier this same tick, see the `_step` order above) already
## populates `core_collider` and, for rigged hulls, `part_colliders` with
## every ALIVE circle's real world position and visual radius - the exact
## data bullets already collide against (combat_world.gd's bullet resolver,
## `_broadphase.query_segment`). Contact reuses those same colliders instead
## of testing only the core centre, so a 226px elite's outermost weapon
## circle (107px from its core) now actually touches the player standing on
## it, not just its core dot.
const PLAYER_CONTACT_RADIUS: float=3.0
func _update_contact() -> void:
 if contact_timer>0.0: return
 for actor: Dictionary in enemies:
  if not bool(actor.dead) and _actor_touches_player(actor):
   _damage_actor(player,12.0,int(actor.id),int(actor.faction))
   contact_timer=0.4
   break
func _actor_touches_player(actor: Dictionary) -> bool:
 var core: Dictionary=actor.get("core_collider",{})
 if not core.is_empty() and Vector2(core.pos).distance_to(player.pos)<float(core.radius)+PLAYER_CONTACT_RADIUS: return true
 for part: Dictionary in actor.get("part_colliders",{}).values():
  if Vector2(part.pos).distance_to(player.pos)<float(part.radius)+PLAYER_CONTACT_RADIUS: return true
 return false
## Target feedback (spec item 4/§19 "flare the target circle's own rim,
## don't just spawn a ring in front of it"): sets a per-circle flare
## intensity that decays over `FLARE_DECAY_SECONDS` (>= §16's 0.25s floor),
## read by `_step_motion` into the pose/renderer every tick. `index` 0 is
## always the core (the player's ONLY hitbox, spec §16).
const FLARE_DECAY_SECONDS: float = 0.25
## On large hits, darken a collar under the impact instead of a brighter
## flash (spec §19). Threshold is the raw incoming `amount` (the ability's
## own damage number, before hp_buffer scaling, so it reads the same across
## every hull regardless of buffer) - a chosen convention, not a measured
## player-feel tuning; stated plainly as unverified against real play, same
## as every other P8 number here.
const FX_COLLAR_DAMAGE_THRESHOLD: float = 30.0
func _flare(actor: Dictionary, index: int) -> void:
 # Direct chained subscript assignment (matches `actor.part_hp[index]=...`
 # elsewhere in this file): going through an intermediate local
 # PackedFloat32Array variable first would mutate a COW copy and never write
 # back into the Dictionary.
 if actor.has("part_flare") and index>=0 and index<actor.part_flare.size(): actor.part_flare[index]=1.0
func _maybe_collar(at: Vector2, amount: float) -> void:
 if amount>=FX_COLLAR_DAMAGE_THRESHOLD: fx.emit("collar",at,Color.BLACK,_fx_rng,{"r1":18.0+amount*0.35})
func _damage_actor(actor: Dictionary, amount: float, source_id: int, source_faction: int = -999) -> void:
 if amount<=0.0 or bool(actor.dead) or float(actor.invulnerable)>0.0: return
 if int(actor.id)==0:
  if player_invulnerable>0.0: return
  light_total=maxf(0.0,light_total-amount/maxf(0.1,float(actor.hp_buffer)))
  actor.hp=light_total
  if light_total<=0.0:
   actor.dead=true
   active=false
   player_died.emit()
   return
  _check_regression()
  _flare(actor,0)
  _maybe_collar(actor.pos,amount)
  return
 # P4a: the armoured-core rule ("reduced damage until half the guns are
 # destroyed") is REMOVED per spec §28 - the core is the kill target and
 # takes full damage from tick 0, regardless of surviving limbs. P4b adds ONE
 # exception, spec §14's "shielded core": while any shield_generator circle
 # of a boss lives, the core takes NO damage at all (the generator circles
 # themselves are ordinary per-circle hitboxes and take damage normally).
 if _boss_shield_active(actor): return
 var damage: float=amount/maxf(0.1,float(actor.hp_buffer))
 var actual: float=minf(float(actor.hp),damage)
 if show_damage_numbers and actual>0.0: fx.emit("damage_number",actor.pos+Vector2(_fx_rng.randf_range(-6,6),-10),Color.WHITE,_fx_rng,{"text":str(roundi(actual))})
 actor.hp=maxf(0.0,float(actor.hp)-damage)
 if actor.has("part_hp") and actor.part_hp.size()>0: actor.part_hp[0]=actor.hp
 _flare(actor,0)
 _maybe_collar(actor.pos,amount)
 actor.reward_damage=float(actor.reward_damage)+actual
 while float(actor.reward_damage)>=18.0 and int(actor.reward_remaining)>0:
  actor.reward_damage=float(actor.reward_damage)-18.0
  actor.reward_remaining=int(actor.reward_remaining)-1
  _drop_pickup(actor.pos,str(actor.element),1,true)
 # A boss's core reaching 0 hp is not enough on its own (spec §14: "multiple
 # cores"): every sub_core circle must ALSO be dead. The core can sit at 0 hp
 # indefinitely (further damage is a no-op, `actual` above is already 0) -
 # `_damage_part`'s sub_core branch re-checks this the moment the last one dies.
 if float(actor.hp)<=0.0 and _boss_can_die(actor):
  actor.dead=true
  _kill_reward(actor,source_id,source_faction)
## Single choke point (spec §14 "shielded core"): true while any
## `shield_generator` circle of `actor` is attached and alive. Non-bosses
## have no `shield_generator_indices` at all, so this is always false for them.
## Single choke point (spec §6/§7.1): a tier drop, whether caused by damage
## or by decay ("decay ... can regress a tier, that is the cost of
## camping" - approved preamble). Both `_damage_actor` and `_update_pace`
## call this instead of duplicating the threshold walk.
func _check_regression() -> void:
 var previous: int=player_tier
 var surviving: int=previous
 while surviving>1 and light_total<GameTuning.regression_floor(surviving): surviving-=1
 if surviving<previous:
  var id: String=hull_history[surviving-1] if hull_history.size()>=surviving else "player_seed"
  set_player_hull(id,true)
  player_invulnerable=GameTuning.RESHAPE_SECONDS+GameTuning.REGRESSION_GRACE
  player_regressed.emit(previous,surviving)
func _boss_shield_active(actor: Dictionary) -> bool:
 var indices: PackedInt32Array=actor.get("shield_generator_indices",PackedInt32Array())
 if indices.is_empty(): return false
 var hp: PackedFloat32Array=actor.get("part_hp",PackedFloat32Array())
 var attached: PackedByteArray=actor.get("part_attached",PackedByteArray())
 for i: int in indices:
  if i<hp.size() and hp[i]>0.0 and (i>=attached.size() or bool(attached[i])): return true
 return false
## Single choke point (spec §14 "multiple cores"): true once every sub_core
## circle is dead (or there are none, i.e. a shielded-core boss rather than a
## multi-core one, or a non-boss actor).
func _boss_can_die(actor: Dictionary) -> bool:
 var indices: PackedInt32Array=actor.get("sub_core_indices",PackedInt32Array())
 if indices.is_empty(): return true
 var hp: PackedFloat32Array=actor.get("part_hp",PackedFloat32Array())
 var attached: PackedByteArray=actor.get("part_attached",PackedByteArray())
 for i: int in indices:
  if i<hp.size() and hp[i]>0.0 and (i>=attached.size() or bool(attached[i])): return false
 return true
## Review finding 8 (spec §10: pickups come in exactly three sizes, 1/5/20).
## `_kill_reward` already split a reward this way; the debris path
## (`_update_debris`/`_flush_debris`) passed `d.light` straight through as
## `size`, so a limb worth e.g. 162 light dropped ONE pickup with
## `size=54,value=162` - `pickup_canvas.gd`'s radius saturates at 20, so it
## drew as an ordinary size-20 pickup while silently carrying 8x the light.
## Single choke point for both call sites.
func _pickup_sizes(amount: int) -> Array[int]:
 var sizes: Array[int]=[]
 var remaining: int=amount
 while remaining>0:
  var size: int=20 if remaining>=20 else (5 if remaining>=5 else 1)
  sizes.append(size)
  remaining-=size
 return sizes
func _kill_reward(actor: Dictionary, _source_id: int, _source_faction: int = -999) -> void:
 # Killing the core kills the enemy regardless of surviving limbs (spec
 # §14/§28); any limb reward share never paid because its circle was still
 # attached when the core died is folded in here so total light emitted is
 # the same whether the enemy is killed limb-by-limb or core-first.
 # Spec §7.2: chains pay more - the combo multiplier applies to the light
 # paid out at kill time, so the node's finite pool still bounds it (the
 # multiplied pool is spent through _spend_energy same as any other drop).
 if int(actor.id)!=0:
  decay_suppress_timer=GameTuning.DECAY_SUPPRESSION_SECONDS
  combo_count=mini(GameTuning.COMBO_MAX_COUNT,combo_count+1)
  combo_timer=GameTuning.COMBO_WINDOW_SECONDS
  run_kills+=1
  if not bool(actor.rival): _dead_enemy_records.append({"hull_id":str(actor.get("hull_id","")),"element":str(actor.element),"tier":int(actor.tier),"elite":bool(actor.elite)})
 var pool: float=float(actor.reward_remaining)+float(actor.get("reward_unpaid_limb",0.0))
 var reward: int=roundi(pool*_reward_multiplier(actor)*combo_multiplier())
 actor.reward_remaining=0
 actor.reward_unpaid_limb=0.0
 for size: int in _pickup_sizes(reward):
  _drop_pickup(Vector2(actor.pos)+Vector2.from_angle(_rng.randf()*TAU)*_rng.randf_range(3,30),str(actor.element),size,true)
 _add_effect("death",actor.pos,_actor_color(actor),0.4,35.0)
 if bool(actor.rival):
  boss_defeated.emit(str(actor.element))
## `size` is one of GameTuning.PICKUP_SIZES (1/5/20). `enemy_source` marks
## light shed by an enemy (on hit or on death), which is worth
## GameTuning.ENEMY_DROP_MULTIPLIER x a floating pickup of the same size
## (spec §7.2/§10). The draw radius reads `size`, never the multiplied
## `value`, so a 3x enemy drop never looks like a bigger pickup than its size.
func _drop_pickup(point: Vector2, element: String, size: int, enemy_source: bool = false) -> void:
 var requested: int=roundi(float(size)*(GameTuning.ENEMY_DROP_MULTIPLIER if enemy_source else 1.0))
 var amount: int=_spend_energy(requested)
 if amount<=0: return
 if pickups.size()>=MAX_PICKUPS:
  for pickup: Dictionary in pickups:
   if pickup.element==element:
    pickup.value=float(pickup.value)+amount
    pickup.size=maxi(int(pickup.get("size",size)),size)
    return
  # Review finding 7: the budget was already spent (line above) before this
  # cap check, so a pool at MAX_PICKUPS with no same-element pickup to merge
  # into used to drop the light on the floor - the node's finite light
  # budget spent for nothing anyone could ever collect. Refund it: the light
  # stays available in the node's remaining budget to be dropped again
  # later (when a slot frees up or a same-element pickup exists), rather
  # than merging into a DIFFERENT element (which would break spec §10's
  # colour rule: "a pickup's colour means exactly one thing: its element").
  sector_energy_remaining+=amount
  sector_energy_paid-=amount
  return
 pickups.append({"pos":arena.clamp_point(point,6.0),"vel":Vector2.from_angle(_rng.randf()*TAU)*_rng.randf_range(2,8),"element":element,"value":float(amount),"size":size,"phase":_rng.randf()*TAU})
func _spend_energy(requested: int) -> int:
 var amount: int=mini(maxi(0,requested),sector_energy_remaining)
 sector_energy_remaining-=amount
 sector_energy_paid+=amount
 return amount
func _update_pickups(dt: float) -> void:
 # Eligibility/passives are invariant across pickups for this tick.
 _pickup_collectors.clear()
 if light_total<GameTuning.capacity(player_tier,max_player_tier) and active:
  player.collect_radius_squared=pow(_magnet_radius(player),2)
  _pickup_collectors.append(player)
 for actor: Dictionary in enemies:
  if bool(actor.dead) or float(actor.hp)>=float(actor.max_hp): continue
  if not bool(actor.rival) and not _has_ability(actor,"magnet") and not _has_ability(actor,"siphon"): continue
  actor.collect_radius_squared=pow(_magnet_radius(actor),2)
  _pickup_collectors.append(actor)
 for i: int in range(pickups.size()-1,-1,-1):
  var pickup: Dictionary=pickups[i]
  var position: Vector2=pickup.pos
  var collector: Dictionary={}
  var nearest: float=INF
  for candidate: Dictionary in _pickup_collectors:
   var distance: float=position.distance_squared_to(candidate.pos)
   if distance<nearest and distance<float(candidate.collect_radius_squared):
    collector=candidate
    nearest=distance
  if collector.is_empty():
   pickup.pos=arena.clamp_point(position+Vector2(pickup.vel)*dt,5.0)
   continue
  position=position.move_toward(collector.pos,dt*330.0)
  pickup.pos=position
  if position.distance_squared_to(collector.pos)>=196.0: continue
  var consumed: float
  if int(collector.id)==0:
   consumed=collect_light(float(pickup.value),str(pickup.element))
   if light_total>=GameTuning.capacity(player_tier,max_player_tier): _pickup_collectors.erase(collector)
  else:
   var multiplier: float=1.25 if _has_ability(collector,"siphon") else 1.0
   consumed=minf(float(pickup.value),maxf(0.0,float(collector.max_hp)-float(collector.hp))/multiplier)
   collector.hp=float(collector.hp)+consumed*multiplier
   if float(collector.hp)>=float(collector.max_hp): _pickup_collectors.erase(collector)
  pickup.value=maxf(0.0,float(pickup.value)-consumed)
  # Spec §19 "movement effects": "absorbing a pickup pulls a short line from
  # the pickup into the core as it's consumed" - only on the tick it is
  # actually consumed (consumed>0), not every tick it merely sits in range.
  if consumed>0.0: fx.emit("absorb",position,COLORS[maxi(0,ELEMENTS.find(str(pickup.element)))],_fx_rng,{"to":collector.pos})
  if float(pickup.value)<=0.000001: pickups.remove_at(i)
func _magnet_radius(actor: Dictionary) -> float:
 return float(actor.magnet_radius)*(1.5 if _has_ability(actor,"magnet") else 1.0)
func _cleanup_dead() -> void:
 for i: int in range(enemies.size()-1,-1,-1):
  var actor: Dictionary=enemies[i]
  if bool(actor.dead):
   _remove_visual(actor)
   actors_by_id.erase(int(actor.id))
   _break_actor_cycles(actor)
   enemies.remove_at(i)
 if enemies.is_empty() and not cleared_emitted:
  cleared_emitted=true
  sector_cleared.emit()
func _break_actor_cycles(actor: Dictionary) -> void:
 actor.erase("core_collider")
 actor.erase("mouth_collider")
 for i: int in range(3): actor.erase("blocker_%d" % i)
 actor.erase("part_colliders")
func remaining_enemies() -> int:
 var count: int=0
 for actor: Dictionary in enemies:
  if not bool(actor.dead): count+=1
 return count
func _clamp_point(point: Vector2, margin: float = 0.0) -> Vector2: return arena.clamp_point(point,-margin)

func _remove_visual(actor: Dictionary) -> void:
 var renderer: Node=actor.get("renderer") as Node
 if is_instance_valid(renderer): renderer.queue_free()
 actor.renderer=null
func _sync_visuals() -> void:
 for actor: Dictionary in actors_by_id.values():
  var renderer: ShipRenderer=actor.get("renderer") as ShipRenderer
  if not is_instance_valid(renderer): continue
  renderer.position=actor.pos
  renderer.rotation=Vector2(actor.aim).angle()+PI/2.0
  renderer.set_motion_tick(tick)
  renderer.hidden_part_ids=actor.get("hidden_ids",PackedStringArray())
func _actor_color(actor: Dictionary) -> Color:
 return PLAYER_COLOR if int(actor.id)==0 else COLORS[maxi(0,ELEMENTS.find(str(actor.element)))]
## Back-compat call points, kept so existing call sites did not need to move,
## now routed through the ONE choke point (`fx.emit`) instead of a raw
## Dictionary Array. `duration`/`radius` map onto the named template's own
## `extra.r0`/`r1` overrides where the caller's radius is content (e.g. a
## destroyed circle's own authored size), not onto the template's timing -
## timing is the template's, per spec item 2/3, not the call site's.
const _EFFECT_TEMPLATE: Dictionary = {"wall":"wall_flash","dash_ring":"dash_ring","gun_destroyed":"destruction","spawn":"spawn_telegraph","explosion":"explosion","death":"destruction"}
func _add_effect(kind: String, at: Vector2, color: Color, _duration: float, radius: float) -> void:
 var template: String=str(_EFFECT_TEMPLATE.get(kind,""))
 if template.is_empty():
  push_error("_add_effect: unmapped effect kind '%s'" % kind)
  return
 var extra: Dictionary={}
 if template=="destruction": extra={"r0":maxf(4.0,radius),"r1":maxf(1.0,radius*0.1),"direction":Vector2.from_angle(_fx_rng.randf()*TAU)}
 elif template=="explosion": extra={"r1":maxf(8.0,radius),"direction":Vector2.from_angle(_fx_rng.randf()*TAU)}
 elif template=="spawn_telegraph" or template=="wall_flash": extra={"r0":radius*0.4,"r1":radius}
 fx.emit(template,at,color,_fx_rng,extra)
func _add_line_effect(from: Vector2, to: Vector2, color: Color, _duration: float) -> void:
 fx.emit("chain_line",from,color,_fx_rng,{"to":to})
func _update_effects(dt: float) -> void:
 fx.update(dt)
 _update_effect_attachments()
func _update_effect_attachments() -> void:
 for index: int in fx.active_indices:
  if fx.emitter_owner[index]<0: continue
  var actor: Dictionary=actors_by_id.get(fx.emitter_owner[index],{})
  var rig: ShipMotion.ShipRig=actor.get("rig")
  var part: int=rig.index_of(fx.emitter_part[index]) if rig!=null else -1
  if actor.is_empty() or bool(actor.get("dead",false)) or part<0 or (part>0 and (not bool(actor.part_attached[part]) or float(actor.part_hp[part])<=0.0)):
   # Keep its final world position while it fades. It cannot jump to a new
   # component, recycled actor or a different twin after its emitter is gone.
   fx.emitter_owner[index]=-1
   fx.emitter_part[index]=""
   continue
  fx.pos[index]=_part_position(actor,part)
func _clear_encounter() -> void:
 for actor: Dictionary in enemies:
  _remove_visual(actor)
  _break_actor_cycles(actor)
 for drone: Dictionary in drones: drone.erase("collider")
 enemies.clear()
 actors_by_id.clear()
 if not player.is_empty(): actors_by_id[0]=player
 bullets.clear()
 if is_instance_valid(_bullet_canvas): _bullet_canvas.clear_instances()
 if is_instance_valid(_fx_canvas): _fx_canvas.clear_instances()
 if is_instance_valid(_pickup_canvas): _pickup_canvas.clear_instances()
 bullet_count=0
 pickups.clear()
 drones.clear()
 fx.clear()
 telegraphs.clear()
 viruses.clear()
 clouds.clear()
 beams.clear()
 debris.clear()
 _broadphase.clear()
 contact_timer=0.0
 trail_pool.clear()
func _exit_tree() -> void:
 _flush_debris()
 for actor: Dictionary in actors_by_id.values(): _break_actor_cycles(actor)
 for drone: Dictionary in drones: drone.erase("collider")
 _broadphase.clear()
func _sector_key(description: Dictionary) -> String:
 if description.has("id"): return str(description.id)
 var coord: Vector2i=description.get("coord",Vector2i.ZERO)
 return "%d,%d" % [coord.x,coord.y]
func snapshot() -> Dictionary: return CombatPersistence.snapshot(self)
func restore(data: Dictionary) -> void: CombatPersistence.restore(self,data)
func debug_clear() -> void:
 for actor: Dictionary in enemies:
  for i: int in actor.gun_indices: actor.part_hp[i]=0.0
  # A boss's shield generator/sub-cores are not guns, but a debug full-clear
  # must still actually kill it (spec §14 boss rules) rather than leaving the
  # core shielded/undead forever.
  for i: int in actor.get("shield_generator_indices",PackedInt32Array()): actor.part_hp[i]=0.0
  for i: int in actor.get("sub_core_indices",PackedInt32Array()): actor.part_hp[i]=0.0
  actor.invulnerable=0.0
  _damage_actor(actor,1000000.0,0,0)
 _cleanup_dead()
func benchmark(count: int) -> void:
 _clear_encounter()
 setup_player("plasma",5,1500,[],arena.center)
 set_player_hull("player_plasma_t5_heavy")
 command.aim=Vector2.RIGHT
 benchmark_mode=true
 benchmark_target=clampi(count,1,6000)
 player_invulnerable=1000000.0
 active=true
 for i: int in range(16):
  var point: Vector2=Vector2(250+(i%4)*400,180+(i/4)*230)
  var actor: Dictionary=_spawn_elite(ELEMENTS[i%5],5,point) if i%4==0 else _spawn_enemy(ELEMENTS[i%5],4,point,false)
  actor.hp=10000000.0
  actor.max_hp=actor.hp
  actor.part_hp[0]=actor.hp
  actor.part_max_hp[0]=actor.hp
  for gi: int in actor.gun_indices:
   actor.part_hp[gi]=10000000.0
   actor.part_max_hp[gi]=10000000.0
 sector_energy_remaining=10000
 for i: int in range(80): _drop_pickup(Vector2(_rng.randf_range(200,1500),_rng.randf_range(200,900)),ELEMENTS[i%5],1)
 _fill_benchmark(benchmark_target)
func _fill_benchmark(count: int) -> void:
 for i: int in range(count):
  var p: Vector2=Vector2(_rng.randf_range(200,1500),_rng.randf_range(200,900))
  bullets.add(p,Vector2.from_angle(_rng.randf()*TAU)*220.0,-1.0,0.0,2.8,-1,i%6,i%5)

## Diagnostic-only (P9): cost of THIS node's own immediate _draw() (pickups,
## actor status overlays, drones, viruses, clouds, debris), which runs on the
## render/idle step, not `_physics_process` - invisible to `simulation_ms`.
var world_draw_ms: float=0.0
var projectiles_draw_ms: float=0.0 # Diagnostic-only (P9), same reason as `world_draw_ms`.
func _draw() -> void:
 var _p9_began: int=Time.get_ticks_usec()
 # FX MultiMesh upload (see the comment at the `_physics_process` call site
 # this replaced): kept on the render step so it never counts against the
 # headless sim-only benchmark budget.
 if is_instance_valid(_fx_canvas): _fx_canvas.sync(fx)
 # The dark collar (spec §19 "darken a collar... below the playfield value")
 # is drawn by `_fx_canvas` (z_index 1, under ships at z_index 10) as a
 # batched MultiMesh pass now (P9 perf pass) - see `fx_canvas.gd`'s header.
 # Pickups are batched for the same reason and were the dominant cost once the
 # effects pool stopped being the dominant cost - see `pickup_canvas.gd`.
 if is_instance_valid(_pickup_canvas): _pickup_canvas.sync(self)
 for actor: Dictionary in actors_by_id.values():
  if bool(actor.dead): continue
  var at: Vector2=actor.pos
  if not is_instance_valid(actor.get("renderer")):
   draw_arc(at,float(actor.get("footprint",24.0))*0.5,0,TAU,32,_actor_color(actor),1.5,true)
   draw_circle(at,3.0,Color.WHITE if int(actor.id)==0 else _actor_color(actor))
  if float(actor.get("infected",0.0))>0.0: draw_arc(at,10.0,elapsed*2,elapsed*2+TAU*0.7,24,Color("45e06a"),1.5,true)
  if float(actor.slow)>0.0:
   draw_arc(at,13.0,0,TAU,24,Color("45e06a"),2.6,true)
   draw_arc(at,17.0,elapsed*PI,elapsed*PI+PI,20,Color("caffd5")*1.8,2.6,true)
  if float(actor.shield)>0.0: draw_arc(at,65.0,0,TAU,48,PLAYER_COLOR if int(actor.id)==0 else _actor_color(actor),1.5,true)
  # Boss shielded core (spec §14): a visible ring so the player can see why
  # the core is absorbing damage, gone the instant the last generator dies.
  if _boss_shield_active(actor): draw_arc(at,float(actor.get("footprint",24.0))*0.62,0,TAU,48,Color("fff3b0",0.85),2.4,true)
  if float(actor.blockers)>0.0 and int(actor.blocker_hits)>0:
   for i: int in range(3):
    var p: Vector2=at+Vector2.from_angle(elapsed*2.0+TAU*i/3.0)*60.0
    draw_circle(p,7.0,Color("2a2206"))
    draw_arc(p,7.0,0,TAU,18,Color("ffd23f"),1.5,true)
  for i: int in range(int(actor.orbit_stock)):
   var p: Vector2=at+Vector2.from_angle(elapsed+TAU*i/3.0)*43.0
   draw_circle(p,3.0,_actor_color(actor)*1.8)
  if has_passive("health_readout") and int(actor.id)!=0:
   draw_string(ThemeDB.fallback_font,at+Vector2(-20,-28),"%d" % ceili(actor.hp),HORIZONTAL_ALIGNMENT_LEFT,-1,12,_actor_color(actor))
 for drone: Dictionary in drones:
  var color: Color=PLAYER_COLOR if int(drone.faction)==0 else COLORS[maxi(0,ELEMENTS.find(drone.element))]
  draw_circle(drone.pos,9.0,Color("062a12"))
  draw_arc(drone.pos,9.0,0,TAU,20,color,1.5,true)
  draw_arc(drone.pos,9.0,elapsed*PI+drone.phase,elapsed*PI+drone.phase+0.82,8,color*1.8,2.6,true)
 for virus: Dictionary in viruses:
  var color: Color=PLAYER_COLOR if int(virus.faction)==0 else Color("45e06a")
  draw_arc(virus.pos,8.0,elapsed*5,elapsed*5+TAU*0.8,20,color*1.8,2.6,true)
  # Spec §19 table: "latches, then a LINE TO THE HOST that pulses" (the
  # host's own rim flare on the infection tick is separate - `_flare`,
  # called every tick while `infected>0` from `_update_actor_status`).
  var owner: Dictionary=actors_by_id.get(int(virus.owner),{})
  if not owner.is_empty(): draw_line(owner.pos,virus.pos,Color(color,0.4+0.3*sin(elapsed*6.0)),1.5,true)
 for cloud: Dictionary in clouds:
  draw_arc(cloud.pos,float(cloud.radius),0,TAU,48,Color("45e06a"),1.5,true)
  for i: int in range(8):
   var p: Vector2=Vector2(cloud.pos)+Vector2.from_angle(i*TAU/8+elapsed*0.1)*float(cloud.radius)*0.6
   draw_arc(p,18.0,0,TAU,20,Color("45e06a",0.4),1.0,true)
 for d: Dictionary in debris: _draw_debris(d)
 world_draw_ms=float(Time.get_ticks_usec()-_p9_began)/1000.0
func _draw_debris(d: Dictionary) -> void:
 var alpha: float=clampf(1.0-float(d.age)/float(d.life),0.0,1.0)
 if d.has("pieces"):
  alpha=clampf(1.0-maxf(0.0,float(d.age)-float(d.release_delay))/float(d.fade_duration),0.0,1.0)
  var zoom: float=maxf(0.01,get_global_transform_with_canvas().x.length())
  for body: Dictionary in d.pieces:
   for line: Dictionary in body.lines:
    var from: Vector2=Vector2(body.position)+Vector2(line.from).rotated(float(body.angle))
    var to: Vector2=Vector2(body.position)+Vector2(line.to).rotated(float(body.angle))
    draw_line(from,to,Color(line.color,alpha*VisualStyle.CONNECTOR_OPACITY),VisualStyle.CONNECTOR_WIDTH/zoom,true)
   for circle: Dictionary in body.circles:
    var point: Vector2=Vector2(body.position)+Vector2(circle.offset).rotated(float(body.angle))
    var radius: float=float(circle.radius)
    if bool(circle.filled): draw_circle(point,radius,Color(circle.fill,alpha),true,-1,true)
    draw_arc(point,radius,0.0,TAU,48,Color(circle.color,alpha),VisualStyle.STROKE_WIDTH/zoom,true)
    var start: float=fposmod((float(d.age)+float(circle.phase))/maxf(0.05,float(circle.period)),1.0)*TAU
    draw_arc(point,radius,start,start+TAU*VisualStyle.LIGHT_FRACTION,12,Color(circle.light,alpha),VisualStyle.LIGHT_WIDTH/zoom,true)
  return
 var color: Color=d.color
 color.a=alpha
 var angle: float=float(d.angle)
 var offsets: PackedVector2Array=d.offsets
 var radii: PackedFloat32Array=d.radii
 for j: int in range(offsets.size()):
  var p: Vector2=Vector2(d.position)+offsets[j].rotated(angle)
  draw_circle(p,maxf(1.0,float(radii[j])*maxf(0.15,alpha)),color)
func draw_projectiles(canvas: Node2D) -> void:
 var _p9_began: int=Time.get_ticks_usec()
 # Player status sits above its foreground hull, including an opaque Void disc.
 if not player.is_empty():
  var p: Vector2=player.pos
  if float(player.slow)>0.0:
   canvas.draw_arc(p,19.0,elapsed*PI,elapsed*PI+PI*1.8,24,Color("caffd5")*1.8,2.6,true)
   canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-18,-28),"-30%",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("caffd5"))
  if float(player.shield)>0.0: canvas.draw_arc(p,65.0,0,TAU,48,PLAYER_COLOR,1.5,true)
  if float(player.blockers)>0.0 and int(player.blocker_hits)>0:
   for i: int in range(3):
    var point: Vector2=p+Vector2.from_angle(elapsed*2.0+TAU*i/3.0)*60.0
    canvas.draw_circle(point,7.0,Color("2a2206"))
    canvas.draw_arc(point,7.0,0,TAU,18,Color("ffd23f"),1.5,true)
  for i: int in range(int(player.orbit_stock)):
   canvas.draw_circle(p+Vector2.from_angle(elapsed+TAU*i/3.0)*43.0,3.0,PLAYER_COLOR*1.8)
  if has_passive("health_readout"):
   for enemy: Dictionary in enemies:
    if enemy.element=="void": canvas.draw_string(ThemeDB.fallback_font,Vector2(enemy.pos)+Vector2(-20,-30),"%d" % ceili(enemy.hp),HORIZONTAL_ALIGNMENT_LEFT,-1,12,COLORS[2])
 for beam: Dictionary in beams:
  preload("res://scripts/combat/combat_canvas.gd").draw_beam(canvas,beam.points,elapsed,int(beam.faction)==0)
 for attack: Dictionary in telegraphs:
  var color: Color=Color("ff5436")
  var progress: float=clampf(1.0-float(attack.time)/maxf(0.001,float(attack.warn)),0.0,1.0)
  if attack.kind=="laser":
   if bool(attack.fired):
    if bool(attack.get("beam_continuation",false)): continue
    var beam_path: PackedVector2Array=_fired_beam_path(attack)
    if beam_path.size()>1:
     preload("res://scripts/combat/combat_canvas.gd").draw_beam(canvas,beam_path,elapsed,int(attack.faction)==0)
   else: canvas.draw_line(attack.from,Vector2(attack.from).lerp(attack.to,progress),Color(color,0.8),1.5,true)
  else:
   canvas.draw_arc(attack.from,float(attack.radius),0,TAU,40,color,1.5,true)
   canvas.draw_arc(attack.from,maxf(0.5,float(attack.radius)*progress),0,TAU,40,color*1.8,2.6,true)
 # Rings/discs/fragments are drawn by `_fx_canvas` (z_index 41, above the
 # bullet canvas at 40) as a batched MultiMesh pass (P9 perf pass) - see
 # `fx_canvas.gd`'s header. Lines and (off-by-default) damage numbers are few
 # per frame and stay immediate here.
 fx.draw_lines_and_text(canvas,ThemeDB.fallback_font)
 if player_invulnerable>0.0: canvas.draw_arc(player.pos,12.0,elapsed*4,elapsed*4+PI*1.6,24,Color(PLAYER_COLOR,0.8),1.5,true)
 projectiles_draw_ms=float(Time.get_ticks_usec()-_p9_began)/1000.0
 # Spec §24: "Poison/slow state clearly marked on the player" - a corruption-
 # green pulsing ring, distinct from the white invulnerability flicker above.
 if not player.is_empty() and float(player.get("slow",0.0))>0.0: canvas.draw_arc(player.pos,17.0,0,TAU,20,Color("45e06a",0.55+0.35*sin(elapsed*10.0)),2.2,true)






func _fired_beam_path(attack: Dictionary) -> PackedVector2Array:
 if not bool(attack.get("fired",false)) or bool(attack.get("beam_continuation",false)): return PackedVector2Array()
 if attack.has("beam_path"): return PackedVector2Array(attack.beam_path)
 return PackedVector2Array([attack.from,attack.to]) if str(attack.get("kind",""))=="laser" else PackedVector2Array()

func _regular_pattern(actor: Dictionary, dt: float) -> void:
 # A regular's element varies its authored pulse pattern, never its loadout.
 _fire_primary(actor,dt)
func _infect(target: Dictionary, source: Dictionary, damage: float, duration: float) -> void:
 target.infected=maxf(float(target.get("infected",0.0)),duration)
 target.infection_damage=damage
 target.infection_owner=int(source.id)
 target.infection_faction=int(source.faction)
 for nearby: Dictionary in _hostiles(source):
  if int(nearby.id)!=int(target.id) and Vector2(nearby.pos).distance_to(target.pos)<75.0:
   nearby.infected=maxf(float(nearby.get("infected",0.0)),duration*0.5)
   nearby.infection_damage=damage*0.5
   nearby.infection_owner=int(source.id)
   nearby.infection_faction=int(source.faction)

func _configure_arena_exits() -> void:
 arena.exits.clear()
 for direction: Variant in sector.get("exits",[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]):
  if direction is Vector2i: arena.exits.append(direction)
  elif direction is Array and direction.size()==2: arena.exits.append(Vector2i(int(direction[0]),int(direction[1])))

func _muzzle(actor: Dictionary, mount: String) -> Vector2:
 return _resolve_muzzle(actor,mount).position
func _resolve_muzzle(actor: Dictionary, mount: String) -> Dictionary:
 # Rail hull: a mount is a HUB whose id is positional ("r2s1"), so it is found through the mount
 # table, never by treating the mount's name as a circle id. Mirror twins share one mount and
 # take turns (the muzzle alternates; damage does not double), skipping a twin that has died.
 var rig: ShipMotion.ShipRig=actor.get("rig")
 if rig!=null and not rig.legacy:
  var twins: PackedInt32Array=actor.get("mount_twins",{}).get(mount,PackedInt32Array())
  if not twins.is_empty():
   var turn: int=int(actor.get("twin_turn",0))
   actor.twin_turn=turn+1
   for step: int in range(twins.size()):
    var index: int=twins[(turn+step)%twins.size()]
    if index==0 or (bool(actor.part_attached[index]) and float(actor.part_hp[index])>0.0) or int(actor.id)==0:
     return {"position":_part_position(actor,index),"part":rig.ids[index]}
  var definition: ShipDefinition=actor.get("definition")
  return {"position":Vector2(actor.pos),"part":"core" if mount=="primary" and definition!=null and definition.core_weapon!="" else ""}
 var fallback: Vector2=Vector2(actor.get("mounts",{}).get(mount,Vector2.ZERO))
 return {"position":Vector2(actor.pos)+_local_position(actor,mount,fallback).rotated(Vector2(actor.aim).angle()+PI/2.0),"part":mount if rig!=null and rig.index_of(mount)>=0 else ""}

func _prepare_shot_source(index: int) -> void:
 _shot_source.id=bullets.owners[index]
 _shot_source.faction=bullets.factions[index]
 _shot_source.element=ELEMENTS[clampi(bullets.elements[index],0,4)]
