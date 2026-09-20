class_name CombatWorld
extends Node2D
## World-space deterministic combat; camera and menus are external consumers.
signal energy_collected(element: String, amount: int)
signal light_collected(element: String, raw_amount: float)
signal player_died
signal player_regressed(from_tier: int, to_tier: int)
signal sector_cleared
signal rival_reward(component: String, mirror_root: String)
signal rival_defeated(core_id: String) # V02-ADAPTER: kept for campaign_state.gd; P5 consumes boss_defeated instead.
signal boss_defeated(level_id: String)
signal event_message(text: String)
signal attack_performed(element: String, ability: String)
signal shot_fired(position: Vector2, element: String, ability: String)
signal boundary_contact(position: Vector2)
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const CombatAI = preload("res://scripts/combat/combat_ai.gd")
const BulletCanvas = preload("res://scripts/combat/combat_canvas.gd")
const Arena = preload("res://scripts/combat/circular_arena.gd")
const ELEMENTS: Array[String] = ["fire","lightning","void","corruption","plasma"]
const COLORS: Array[Color] = [Color("ff5436"),Color("ffd23f"),Color("9aa3b3"),Color("45e06a"),Color("a97dff")]
const PLAYER_COLOR: Color = Color("6fd3ff")
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
var effects: Array = []
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
var visuals_enabled: bool = true
var show_element_labels: bool = false
var sector_energy_remaining: int = 10000
var sector_energy_paid: int = 0
var sector_cache: Dictionary = {}
var encounter_records: Dictionary = {}
var encounter_epoch: int = -1
var debris: Array = [] # P4a detachment: each entry is one destroyed circle's subtree, see `_destroy_part`
var _ability_cache: Dictionary = {}
var _bullet_canvas: Node2D
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

func _ready() -> void:
 _rng.seed=734927
 _broadphase.world=self
 _ensure_canvas()
 if player.is_empty(): setup_player("neutral",1,40,[],arena.center)
func _ensure_canvas() -> void:
 if is_instance_valid(_bullet_canvas): return
 _bullet_canvas=BulletCanvas.new()
 _bullet_canvas.world=self
 _bullet_canvas.z_index=40
 add_child(_bullet_canvas)
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
 absorption[element]=float(absorption.get(element,0.0))+consumed
 light_collected.emit(element,consumed)
 energy_collected.emit(element,int(consumed))
 return consumed
func collect_energy(amount: float, element: String) -> void: collect_light(amount,element)

func _make_actor(id: int, element: String, tier: int, position: Vector2, faction: int, rival: bool) -> Dictionary:
 var hp: float=(140.0+80.0*tier) if rival else (24.0+14.0*tier)
 return {"id":id,"element":element,"tier":clampi(tier,1,GameTuning.MAX_TIER),"pos":position,"vel":Vector2.ZERO,"aim":Vector2.DOWN,"faction":faction,"native_faction":faction,"rival":rival,"elite":false,"hp":hp,"max_hp":hp,"energy":40.0,"fire_cd":0.0,"primary_cd":0.0,"secondary_cd":0.0,"decision_cd":0.0,"target":0,"desired":Vector2.ZERO,"age":_rng.randf()*TAU,"dead":false,"renderer":null,"invulnerable":0.0,"reward_remaining":(80+30*tier) if rival else 24+10*tier,"reward_damage":0.0,"reward_unpaid_limb":0.0,"cooldowns":{},"guns":[],"shield":0.0,"blockers":0.0,"blocker_hits":0,"orbit_stock":0,"orbit_cd":0.0,"slow":0.0,"stored":0,"stolen":[],"infected":0.0,"charge":0.0}
func _spawn_enemy(element: String, tier: int, position: Vector2, rival: bool) -> Dictionary:
 if enemies.size()>=MAX_ACTORS: return {}
 var actor: Dictionary=_make_actor(next_actor_id,element,tier,arena.clamp_point(position,30.0),ELEMENTS.find(element)+1,rival)
 next_actor_id+=1
 # V02-ADAPTER: v0.2 asked for ids by formula ("enemy_%s_t%d" / "rival_%s_t5");
 # those ids no longer exist under the P2b-1 roster. ShipCatalog.pick_enemy
 # maps (faction, element, tier) onto the nearest roster hull for that
 # archetype; it hard-errors (returns null) rather than silently
 # substituting a wrong tier. Removed with the rest of the shim in P5.
 actor.hull_id=ShipCatalog.pick_enemy("boss" if rival else "enemy",element,tier)
 if actor.hull_id.is_empty(): push_error("V02-ADAPTER: no roster hull for faction=%s element=%s tier=%d" % ["boss" if rival else "enemy",element,tier])
 var definition: ShipDefinition=ShipCatalog.trim_to_tier(ShipCatalog.get_ship(actor.hull_id),int(actor.tier)) # V02-ADAPTER
 if definition==null: definition=ShipCatalog.make_ship(element,tier,false)
 _configure_actor(actor,definition,true)
 enemies.append(actor)
 actors_by_id[int(actor.id)]=actor
 _update_visual(actor)
 return actor
func _spawn_elite(element: String, tier: int, position: Vector2) -> Dictionary:
 var actor: Dictionary=_spawn_enemy(element,tier,position,false)
 if actor.is_empty(): return actor
 actor.elite=true
 actor.hull_id=ShipCatalog.pick_enemy("elite",element,tier) # V02-ADAPTER
 if actor.hull_id.is_empty(): push_error("V02-ADAPTER: no roster hull for faction=elite element=%s tier=%d" % [element,tier])
 actor.max_hp=180.0+110.0*tier
 actor.hp=actor.max_hp
 actor.reward_remaining=150+60*tier
 _configure_actor(actor,ShipCatalog.trim_to_tier(ShipCatalog.get_ship(actor.hull_id),int(actor.tier)),true) # V02-ADAPTER
 _update_visual(actor)
 return actor
func _configure_actor(actor: Dictionary, definition: ShipDefinition, reset: bool = false) -> void:
 if definition==null: return
 actor.definition=definition
 actor.speed=definition.speed
 actor.turn_rate=definition.turn_rate
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
 part_hp.resize(n)
 part_max_hp.resize(n)
 part_cd.resize(n)
 part_egg.resize(n)
 part_aim.resize(n)
 part_attached.resize(n)
 var mount_index: Dictionary={}
 var gun_indices: PackedInt32Array=PackedInt32Array()
 # id -> authored PartDefinition.stat_id (P4b: sub_core / shield_generator are
 # not carried by ShipRig, which only knows geometry/motion, so this is read
 # once here from the ShipDefinition and turned into index arrays below - the
 # single choke point boss rules (`_boss_shield_active`, `_boss_can_die`) read).
 var stat_by_id: Dictionary={}
 for part: PartDefinition in actor.definition.parts:
  if part.shape=="circle" and not part.stat_id.is_empty(): stat_by_id[part.id]=part.stat_id
 var sub_core_indices: PackedInt32Array=PackedInt32Array()
 var shield_generator_indices: PackedInt32Array=PackedInt32Array()
 var part_aim_error: PackedFloat32Array=PackedFloat32Array()
 part_aim_error.resize(n)
 for i: int in range(n):
  var pid: String=rig.ids[i]
  var max_hp: float=float(actor.max_hp) if i==0 else (rig.authored_hp[i] if rig.authored_hp[i]>0.0 else rig.radius[i]*(4.0+3.0*float(actor.tier)))
  part_max_hp[i]=max_hp
  part_hp[i]=float(old_hp[pid]) if old_hp.has(pid) else max_hp
  part_attached[i]=(1 if bool(old_attached[pid]) else 0) if old_attached.has(pid) else 1
  part_cd[i]=float(old_cd[pid]) if old_cd.has(pid) else _rng.randf_range(0.2,1.2)
  part_egg[i]=float(old_egg[pid]) if old_egg.has(pid) else 0.0
  part_aim[i]=old_aim[pid] if old_aim.has(pid) else Vector2.DOWN
  part_aim_error[i]=CombatAI.sample_aim_error(_rng)
  if not rig.mount_id[i].is_empty(): mount_index[rig.mount_id[i]]=i
  if i>0 and not rig.ability_id[i].is_empty(): gun_indices.append(i)
  match str(stat_by_id.get(pid,"")):
   "sub_core": sub_core_indices.append(i)
   "shield_generator": shield_generator_indices.append(i)
 part_hp[0]=float(actor.hp)
 part_max_hp[0]=float(actor.max_hp)
 part_attached[0]=1
 actor.part_hp=part_hp
 actor.part_max_hp=part_max_hp
 actor.part_cd=part_cd
 actor.part_egg_cd=part_egg
 actor.part_aim=part_aim
 actor.part_aim_error=part_aim_error
 actor.part_attached=part_attached
 actor.mount_index=mount_index
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
func _rebuild_part_views(actor: Dictionary) -> void:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 if rig==null: return
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
 if not fresh: return
 var key: String=_sector_key(sector)
 if encounter_records.has(key) or sector_cache.has(key):
  CombatPersistence.restore_encounter(self,CombatPersistence.read_cached_encounter(self,key))
  return
 var kind: String=str(sector.get("kind","regular"))
 if kind=="origin":
  for i: int in range(3): _drop_pickup(arena.center+Vector2((i-1)*64,190),["fire","corruption","plasma"][i],5)
  cleared_emitted=true
  return
 if bool(sector.get("cleared",false)):
  cleared_emitted=true
  return
 var element: String=str(sector.get("element","fire"))
 var tier: int=clampi(int(sector.get("tier",1)),1,GameTuning.MAX_TIER)
 var distance: float=float(sector.get("distance",tier*3))
 var population: int=mini(45,int(sector.get("enemy_count",4+int(distance)*0.7)))
 for i: int in range(population):
  var p: Vector2=arena.center+Vector2.from_angle(TAU*i/maxi(1,population))*(arena.radius*0.55)
  if p.distance_to(player_position)<180.0: p=arena.center*2.0-p
  _spawn_enemy(element,tier,p,false)
 var elite_count: int=int(sector.get("elite_count",1 if distance>=6.0 and _rng.randf()<minf(0.65,distance*0.02) else 0))
 for i: int in range(elite_count): _spawn_elite(element,tier,arena.center+Vector2(150*(i-1),-200))
 if kind in ["core","demo_core"] and not bool(sector.get("core_defeated",false)):
  var rival: Dictionary=_spawn_enemy(element,tier,arena.center+Vector2(0,-230),true)
  if not rival.is_empty(): rival.core_id=str(sector.get("core_id",element))
 for i: int in range(3): _drop_pickup(arena.center+Vector2(_rng.randf_range(-400,400),_rng.randf_range(-220,220)),element,1)

func _physics_process(delta: float) -> void:
 if not active or player.is_empty(): return
 tick+=1
 var began: int=Time.get_ticks_usec()
 var dt: float=minf(delta,0.05)
 _last_dt=dt
 _step_motion(player)
 for actor: Dictionary in enemies: _step_motion(actor)
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
 _rebuild_actor_grid()
 _update_telegraphs(dt)
 if profile_sections:
  section_ms.status_grid_telegraphs=(Time.get_ticks_usec()-section_start)/1000.0
  section_start=Time.get_ticks_usec()
 _update_bullets(dt)
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
 simulation_ms=(Time.get_ticks_usec()-began)/1000.0
 if profile_sections:
  section_ms.upload=(Time.get_ticks_usec()-section_start)/1000.0
  section_ms.total=simulation_ms
func _update_player(dt: float) -> void:
 _tick_cooldowns(player,dt)
 var speed: float=float(player.speed)*(1.2 if _has_ability(player,"thrusters") else 1.0)
 var movement: Vector2=command.movement.limit_length(1.0)*speed*_slow_multiplier(player)
 player.vel=movement
 var desired: Vector2=Vector2(player.pos)+movement*dt
 if arena.in_opening(desired): player.pos=desired
 else:
  var clamped: Vector2=arena.clamp_point(desired,3.0)
  if clamped.distance_squared_to(desired)>0.01:
   boundary_contact.emit(clamped)
   _add_effect("wall",clamped,PLAYER_COLOR,0.2,18.0)
  player.pos=clamped
 if command.aim.length_squared()>0.01:
  var speed_turn: float=float(player.turn_rate)*(1.2 if _has_ability(player,"thrusters") else 1.0)
  player.aim=Vector2.from_angle(rotate_toward(Vector2(player.aim).angle(),command.aim.angle(),speed_turn*dt))
 if command.fire: _fire_primary(player,dt)
 for index: int in range(mini(command.secondaries.size(),player.secondaries.size())):
  if command.secondaries[index]: _use_secondary(player,index)
 _passives(player,dt)
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
 if id in ["beam","homing_beam"]:
  _beam(actor,id,dt,_muzzle(actor,"primary"),actor.aim)
  if float(actor.fire_cd)<=0.0:
   _emit_shot(actor,id,actor.pos)
   actor.fire_cd=0.16
  return
 if float(actor.fire_cd)>0.0: return
 var cooldown: float=_ability(id).cooldown
 actor.fire_cd=maxf(0.06,cooldown)*(1.0 if int(actor.id)==0 else (2.0 if bool(actor.rival) else 4.5))
 _activate_component(actor,id,_muzzle(actor,"primary"),actor.aim)
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
 _activate_component(actor,id,_muzzle(actor,key),actor.aim,key)
func _emit_shot(actor: Dictionary, id: String, at: Vector2) -> void:
 shot_fired.emit(at,str(actor.element),id)
 if int(actor.id)==0: attack_performed.emit(str(actor.element),id)
func _damage_scale(actor: Dictionary) -> float:
 return float(actor.get("damage_multiplier",1.0))*(1.0+0.12*(int(actor.tier)-1))*(1.0 if int(actor.id)==0 or bool(actor.get("rival",false)) else 0.65)
func _activate_component(actor: Dictionary, id: String, at: Vector2, aim: Vector2, mount: String = "") -> void:
 var definition: AbilityDefinition=_ability(id)
 var damage: float=definition.damage*_damage_scale(actor)
 _emit_shot(actor,id,at)
 actor.shots_fired=int(actor.get("shots_fired",0))+1 # play-census instrumentation only; not read by gameplay
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
  "mine_layer": _queue_attack(actor,"mine",arena.clamp_point(at-aim*28.0),Vector2.ZERO,0.35,damage,definition.range_pixels,-1,mount)
  "orbital_blockers":
   actor.blockers=definition.duration
   actor.blocker_hits=6
  "egg": pass # Reactive damage event activates this mount.
  "droid_bay": _spawn_drones(actor,2,damage,at)
  "deployment_ramp":
   var unit: Dictionary=_spawn_enemy(str(actor.element),maxi(1,int(actor.tier)-1),at+aim*60.0,false)
   if not unit.is_empty(): unit.reward_remaining=0
  "turret_ring":
   for i: int in range(6):
    var direction: Vector2=Vector2.from_angle(float(actor.age)*0.5+TAU*i/6.0)
    _shoot(actor,direction,250.0,damage,-1.0,0,at+direction*definition.range_pixels)
func _shoot(actor: Dictionary, direction: Vector2, speed: float, damage: float, life: float = -1.0, special: int = 0, at: Vector2 = Vector2.INF) -> int:
 var origin: Vector2=Vector2(actor.pos)+direction*8.0 if at==Vector2.INF else at
 return bullets.add(origin,direction.normalized()*speed,life,damage,3.0,int(actor.id),int(actor.faction),maxi(0,ELEMENTS.find(str(actor.element))),special)
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
 else: path.append(_ray_end(at,aim))
 var damage: float=_ability(id).damage*_damage_scale(actor)*dt
 var hit_ids: Dictionary={}
 for i: int in range(path.size()-1): _damage_segment(actor,path[i],path[i+1],damage,hit_ids)
 beams.append({"points":path,"faction":int(actor.faction),"element":str(actor.element)})
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
## Narrow phase for the broadphase's one-collider-per-enemy bound: returns the rig index of the
## earliest alive circle the swept segment touches (leaving its t in `_narrow_t`), or 0 for none.
## Circle positions come from the POSE, the same source the renderer and the muzzles use, so a
## hitbox can never sit where the circle is not drawn. The rotation basis is computed once here
## rather than per circle.
var _narrow_t: float=0.0
func _narrow_to_circle(actor: Dictionary, from: Vector2, to: Vector2, bullet_radius: float, limit: float) -> int:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 if rig==null: return 0
 var pose: ShipMotion.ShipPose=actor.get("pose")
 var hp: PackedFloat32Array=actor.part_hp
 var angle: float=Vector2(actor.aim).angle()+PI/2.0
 var ca: float=cos(angle)
 var sa: float=sin(angle)
 var origin: Vector2=actor.pos
 var best: int=0
 var best_t: float=limit
 for i: int in range(1,rig.ids.size()):
  if hp[i]<=0.0: continue
  var l: Vector2=pose.local[i] if pose!=null and i<pose.local.size() else rig.rest[i]
  var t: float=Pool.segment_circle_t(from,to,origin+Vector2(l.x*ca-l.y*sa,l.x*sa+l.y*ca),rig.radius[i]+bullet_radius)
  if t>=0.0 and t<best_t:
   best_t=t
   best=i
 if best>0: _narrow_t=best_t
 return best
func _step_motion(actor: Dictionary) -> void:
 var rig: ShipMotion.ShipRig=actor.get("rig")
 var pose: ShipMotion.ShipPose=actor.get("pose")
 if rig!=null and pose!=null: ShipMotion.step(rig,pose,tick)
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
   if fmod(float(actor.age)+float(actor.part_max_hp[index]),3.0)<0.7: _beam(actor,id,dt,at,actor.part_aim[index])
  elif float(actor.part_cd[index])<=0.0:
   actor.part_cd[index]=maxf(0.55,_ability(id).cooldown*(2.5 if _ability(id).slot_kind=="primary" else 1.0))
   _activate_component(actor,id,at,actor.part_aim[index],rig.ids[index])
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
  if (lf>=index and lf<last) or (lt>=index and lt<last): hidden.append(rig.line_ids[k])
 actor.hidden_ids=hidden
 if offsets.is_empty(): return
 actor.reward_unpaid_limb=maxf(0.0,float(actor.get("reward_unpaid_limb",0.0))-light)
 # The debris payout applies the same tier-gap multiplier a core kill does
 # (_kill_reward), so total light emitted does not depend on whether a limb
 # was paid out early (debris) or folded into the core-kill pool (spec item
 # 5/conservation). `reward_unpaid_limb` above stays in unmultiplied terms.
 var paid_light: float=light*_reward_multiplier(actor)
 debris.append({"offsets":offsets,"radii":radii,"color":_actor_color(actor),"element":str(actor.element),"position":Vector2(actor.pos),"velocity":Vector2(actor.vel),"angle":Vector2(actor.aim).angle()+PI/2.0,"spin":_rng.randf_range(-1.2,1.2),"age":0.0,"life":1.0,"light":paid_light})
func _update_debris(dt: float) -> void:
 for i: int in range(debris.size()-1,-1,-1):
  var d: Dictionary=debris[i]
  d.age=float(d.age)+dt
  d.position=Vector2(d.position)+Vector2(d.velocity)*dt
  d.angle=float(d.angle)+float(d.spin)*dt
  if float(d.age)>=float(d.life):
   _drop_pickup(d.position,str(d.element),maxi(0,roundi(float(d.light))))
   debris.remove_at(i)
## Debris must not silently lose light on a node exit mid-fade: whatever has
## not finished its 1s fade yet pays out immediately as a pickup. Called
## before a sector is cleared/cached and before every snapshot, so light is
## conserved whether the fight continues, is saved, or the node is left.
func _flush_debris() -> void:
 for d: Dictionary in debris:
  _drop_pickup(d.position,str(d.element),maxi(0,roundi(float(d.light))))
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
   if toward.length_squared()<pow(float(actor.body_features.void_pull.value),2): target.pos=arena.clamp_point(Vector2(target.pos)+toward.normalized()*35.0*dt,3.0)
func _slow_multiplier(actor: Dictionary) -> float: return 0.7 if float(actor.get("slow",0.0))>0.0 else 1.0
func _update_actor_status(actor: Dictionary, dt: float) -> void:
 actor.slow=maxf(0.0,float(actor.slow)-dt)
 if int(actor.id)!=0: actor.invulnerable=maxf(0.0,float(actor.invulnerable)-dt)
 if float(actor.get("infected",0.0))>0.0:
  actor.infected=maxf(0.0,float(actor.infected)-dt)
  _damage_actor(actor,float(actor.get("infection_damage",3.0))*dt,int(actor.get("infection_owner",-1)),int(actor.get("infection_faction",-1)))
 # Absorption is the only healing path. No delayed or passive regeneration.
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
    velocity=Vector2.from_angle(angle)*velocity.length()
  if (flag & Pool.WANDER)!=0: velocity=velocity.rotated(sin(elapsed*5.0+index*1.7)*1.2*dt)
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
    if t<nearest:
     nearest=t
     hit=c
     hit_part=int(c.get("part_index",0))
   if not hit.is_empty():
    _prepare_shot_source(index)
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
       _add_line_effect(hit.actor.pos,target.pos,PLAYER_COLOR if bullets.factions[index]==0 else COLORS[bullets.elements[index]],0.15)
    if (flag & Pool.ROCKET)!=0: _radial_damage(source,from.lerp(to,nearest),55.0,bullets.damages[index]*0.5)
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
   if remaining<=0.000001: break
  if not removed:
   bullets.positions[index]=from
   bullets.velocities[index]=velocity
func _update_contact() -> void:
 if contact_timer>0.0: return
 for actor: Dictionary in enemies:
  if not bool(actor.dead) and Vector2(actor.pos).distance_to(player.pos)<9.0:
   _damage_actor(player,12.0,int(actor.id),int(actor.faction))
   contact_timer=0.4
   break
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
  var previous: int=player_tier
  var surviving: int=previous
  while surviving>1 and light_total<GameTuning.regression_floor(surviving): surviving-=1
  if surviving<previous:
   var id: String=hull_history[surviving-1] if hull_history.size()>=surviving else "player_seed"
   set_player_hull(id,true)
   player_invulnerable=GameTuning.RESHAPE_SECONDS+GameTuning.REGRESSION_GRACE
   player_regressed.emit(previous,surviving)
  _add_effect("hit",actor.pos,Color.WHITE,0.15,8.0)
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
 actor.hp=maxf(0.0,float(actor.hp)-damage)
 if actor.has("part_hp") and actor.part_hp.size()>0: actor.part_hp[0]=actor.hp
 actor.reward_damage=float(actor.reward_damage)+actual
 while float(actor.reward_damage)>=18.0 and int(actor.reward_remaining)>0:
  actor.reward_damage=float(actor.reward_damage)-18.0
  actor.reward_remaining=int(actor.reward_remaining)-1
  _drop_pickup(actor.pos,str(actor.element),1)
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
func _kill_reward(actor: Dictionary, _source_id: int, _source_faction: int = -999) -> void:
 # Killing the core kills the enemy regardless of surviving limbs (spec
 # §14/§28); any limb reward share never paid because its circle was still
 # attached when the core died is folded in here so total light emitted is
 # the same whether the enemy is killed limb-by-limb or core-first.
 var pool: float=float(actor.reward_remaining)+float(actor.get("reward_unpaid_limb",0.0))
 var reward: int=roundi(pool*_reward_multiplier(actor))
 actor.reward_remaining=0
 actor.reward_unpaid_limb=0.0
 while reward>0:
  var size: int=20 if reward>=20 else (5 if reward>=5 else 1)
  _drop_pickup(Vector2(actor.pos)+Vector2.from_angle(_rng.randf()*TAU)*_rng.randf_range(3,30),str(actor.element),size)
  reward-=size
 _add_effect("death",actor.pos,_actor_color(actor),0.4,35.0)
 if bool(actor.rival):
  rival_defeated.emit(str(actor.get("core_id",""))) # V02-ADAPTER: campaign_state.gd still consumes this
  boss_defeated.emit(str(actor.get("core_id",actor.element)))
func _drop_pickup(point: Vector2, element: String, value: int) -> void:
 var amount: int=_spend_energy(value)
 if amount<=0: return
 if pickups.size()>=MAX_PICKUPS:
  for pickup: Dictionary in pickups:
   if pickup.element==element:
    pickup.value=float(pickup.value)+amount
    return
  return
 pickups.append({"pos":arena.clamp_point(point,6.0),"vel":Vector2.from_angle(_rng.randf()*TAU)*_rng.randf_range(2,8),"element":element,"value":float(amount),"phase":_rng.randf()*TAU})
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
func combat_status() -> Dictionary:
 return {"enemies":remaining_enemies(),"bullets":bullet_count,"pickups":pickups.size(),"primary_cooldown":float(player.get("fire_cd",0.0)),"secondary_cooldown":float(player.get("secondary_cd",0.0)),"cooldowns":player.get("cooldowns",{}),"simulation_ms":simulation_ms,"projectile_upload_ms":float(_bullet_canvas.get("upload_ms")) if is_instance_valid(_bullet_canvas) else 0.0,"pool_capacity":Pool.CAPACITY,"pool_rejected":bullets.rejected,"resource_remaining":sector_energy_remaining,"resource_paid":sector_energy_paid,"stored_bullets":0,"charge":0.0}
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
func _add_effect(kind: String, at: Vector2, color: Color, duration: float, radius: float) -> void:
 if effects.size()<250: effects.append({"kind":kind,"pos":at,"color":color,"time":duration,"duration":duration,"radius":radius})
func _add_line_effect(from: Vector2, to: Vector2, color: Color, duration: float) -> void:
 if effects.size()<250: effects.append({"kind":"line","pos":from,"to":to,"color":color,"time":duration,"duration":duration,"radius":0.0})
func _update_effects(dt: float) -> void:
 for i: int in range(effects.size()-1,-1,-1):
  effects[i].time=float(effects[i].time)-dt
  if float(effects[i].time)<=0.0: effects.remove_at(i)
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
 bullet_count=0
 pickups.clear()
 drones.clear()
 effects.clear()
 telegraphs.clear()
 viruses.clear()
 clouds.clear()
 beams.clear()
 debris.clear()
 _broadphase.clear()
 contact_timer=0.0
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

func _draw() -> void:
 for pickup: Dictionary in pickups: _draw_pickup(pickup)
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
 for cloud: Dictionary in clouds:
  draw_arc(cloud.pos,float(cloud.radius),0,TAU,48,Color("45e06a"),1.5,true)
  for i: int in range(8):
   var p: Vector2=Vector2(cloud.pos)+Vector2.from_angle(i*TAU/8+elapsed*0.1)*float(cloud.radius)*0.6
   draw_arc(p,18.0,0,TAU,20,Color("45e06a",0.4),1.0,true)
 for d: Dictionary in debris: _draw_debris(d)
func _draw_debris(d: Dictionary) -> void:
 var alpha: float=clampf(1.0-float(d.age)/float(d.life),0.0,1.0)
 var color: Color=d.color
 color.a=alpha
 var angle: float=float(d.angle)
 var offsets: PackedVector2Array=d.offsets
 var radii: PackedFloat32Array=d.radii
 for j: int in range(offsets.size()):
  var p: Vector2=Vector2(d.position)+offsets[j].rotated(angle)
  draw_circle(p,maxf(1.0,float(radii[j])*maxf(0.15,alpha)),color)
func _draw_pickup(pickup: Dictionary) -> void:
 var color: Color=COLORS[maxi(0,ELEMENTS.find(str(pickup.element)))]
 var radius: float=3.0+(1.5 if float(pickup.value)>=5.0 else 0.0)+(1.5 if float(pickup.value)>=20.0 else 0.0)
 if pickup.element=="void": draw_circle(pickup.pos,radius,Color.BLACK)
 draw_arc(pickup.pos,radius,0,TAU,24,color,1.5,true)
 var angle: float=elapsed*PI+float(pickup.phase)
 draw_arc(pickup.pos,radius,angle,angle+TAU*0.13,8,color.lerp(Color.WHITE,0.6)*1.8,2.6,true)
func draw_projectiles(canvas: Node2D) -> void:
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
  var color: Color=PLAYER_COLOR if int(beam.faction)==0 else COLORS[maxi(0,ELEMENTS.find(beam.element))]
  canvas.draw_polyline(beam.points,color*1.8,2.6,true)
 for attack: Dictionary in telegraphs:
  var color: Color=Color("ff5436")
  var progress: float=clampf(1.0-float(attack.time)/maxf(0.001,float(attack.warn)),0.0,1.0)
  if attack.kind=="laser":
   if bool(attack.fired):
    canvas.draw_line(attack.from,attack.to,Color(1,0.25,0.15,0.35),7.0,true)
    canvas.draw_line(attack.from,attack.to,Color(1.8,1.55,1.45),2.6,true)
   else: canvas.draw_line(attack.from,Vector2(attack.from).lerp(attack.to,progress),Color(color,0.8),1.5,true)
  else:
   canvas.draw_arc(attack.from,float(attack.radius),0,TAU,40,color,1.5,true)
   canvas.draw_arc(attack.from,maxf(0.5,float(attack.radius)*progress),0,TAU,40,color*1.8,2.6,true)
 for effect: Dictionary in effects:
  var color: Color=effect.color
  color.a=clampf(float(effect.time)/float(effect.duration),0,1)
  if effect.kind=="line": canvas.draw_line(effect.pos,effect.to,color*1.8,2.6,true)
  else: canvas.draw_arc(effect.pos,maxf(2.0,float(effect.radius)*(1.0-color.a*0.4)),0,TAU,24,color*1.6,1.5,true)
 if player_invulnerable>0.0: canvas.draw_arc(player.pos,12.0,elapsed*4,elapsed*4+PI*1.6,24,Color(PLAYER_COLOR,0.8),1.5,true)






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
 var fallback: Vector2=Vector2(actor.get("mounts",{}).get(mount,Vector2.ZERO))
 return Vector2(actor.pos)+_local_position(actor,mount,fallback).rotated(Vector2(actor.aim).angle()+PI/2.0)

func _prepare_shot_source(index: int) -> void:
 _shot_source.id=bullets.owners[index]
 _shot_source.faction=bullets.factions[index]
 _shot_source.element=ELEMENTS[clampi(bullets.elements[index],0,4)]
