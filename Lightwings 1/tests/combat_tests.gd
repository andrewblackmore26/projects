extends SceneTree
const World=preload("res://scripts/combat/combat_world.gd")
const Pool=preload("res://scripts/combat/bullet_pool.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
 checks+=1
 if not value:
  failures.append(message)
  push_error(message)
func make_world() -> CombatWorld:
 var w: CombatWorld=World.new()
 w.visuals_enabled=false
 root.add_child(w)
 w.set_physics_process(false)
 w.setup_player("neutral",1,40,[],Vector2(500,500))
 return w
func release(w: CombatWorld) -> void:
 w._clear_encounter()
 w.free()
func run() -> void:
 test_progression()
 test_arena_collision()
 test_elites()
 test_components()
 test_persistence()
 test_catalogue_execution()
 test_regular_patterns()
 test_cold_cache()
 test_authored_runtime_contract()
 print("COMBAT V2: %d checks, %d failures" % [checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
func test_progression() -> void:
 var w: CombatWorld=make_world()
 check(w.light_total==40 and w.hull_id=="player_seed","Seed starts with one 40-point bar")
 w._update_actor_status(w.player,30.0)
 check(w.light_total==40,"Waiting does not heal")
 var consumed: float=w.collect_light(80.0,"fire")
 check(consumed==60 and w.light_total==100,"Collection caps at next threshold and returns raw amount consumed")
 check(w.absorption.fire==60,"Only consumed light enters diet")
 check(w.evolve_hull("player_fire_t2_standard_a"),"Threshold unlocks next hull")
 check(w.light_total==100 and w.player_invulnerable==0.8,"Evolution preserves bar with reshape invulnerability")
 w.player_invulnerable=0
 w.player.invulnerable=0
 w._damage_actor(w.player,15,1)
 check(w.player_tier==2 and w.light_total==85,"Exact 85 percent retains current tier")
 w._damage_actor(w.player,0.1,1)
 check(w.player_tier==1 and w.hull_id=="player_seed","Crossing buffer regresses to historical hull")
 check(is_equal_approx(w.player_invulnerable,1.8),"Regression includes reshape plus post-reshape grace")
 var old: float=w.light_total
 w._damage_actor(w.player,30,1)
 check(is_equal_approx(old,w.light_total),"Grace prevents chain hits")
 for role: String in ["compact","standard_a","heavy"]:
  w.set_player_hull("player_fire_t3_"+role)
  w.light_total=400
  w.player_invulnerable=0
  w.player.invulnerable=0
  w._damage_actor(w.player,13,1)
  var expected: float=400.0-13.0/({"compact":0.8,"standard_a":1.0,"heavy":1.3}[role])
  check(is_equal_approx(w.light_total,expected),"Role damage divisor: "+role)
 w.setup_player("fire",5,900,[],Vector2(500,500))
 w._damage_actor(w.player,200,1)
 check(w.player_tier==4 and w.light_total==700,"Large hit applies once and selects surviving tier")
 w.setup_player("fire",5,900,[],Vector2(500,500))
 w._damage_actor(w.player,820,1)
 check(w.hull_id=="player_seed" and w.light_total==80,"One large hit may restore seed directly")
 w.setup_player("fire",5,900,[],Vector2(500,500))
 w._damage_actor(w.player,900,1)
 check(not w.active and w.light_total==0,"Zero bar dies directly")
 w.setup_player("fire",5,1499.5,[],Vector2(500,500))
 consumed=w.collect_light(20,"plasma")
 check(is_equal_approx(consumed,0.5) and w.light_total==1500,"Terminal capacity preserves fractional excess")
 check(not w.evolve_hull("player_fire_t5_heavy"),"Terminal tier cannot evolve")
 w.setup_player("corruption",4,899,[],Vector2(500,500))
 w.player.ability_set.siphon=true
 consumed=w.collect_light(5,"corruption")
 check(is_equal_approx(consumed,0.8) and w.light_total==900,"Siphon consumes raw quantity correctly at cap")
 check(is_equal_approx(w.absorption.corruption,0.8),"Siphon bonus does not fabricate elemental diet")
 release(w)
func test_arena_collision() -> void:
 var w: CombatWorld=make_world()
 check(w.arena.bounds.size==Vector2(1792,1120),"Arena is 1.4 viewport dimensions")
 check(not w.arena.contains(Vector2.ZERO),"Rounded corner excludes rectangular corner")
 check(w.arena.contains(w.arena.clamp_point(Vector2(-100,-100),3),3),"Corner clamp is inside wall")
 check(w.arena.exit_direction(Vector2(-1,560))==Vector2i.LEFT,"Only marked opening accepts exit")
 check(w.arena.exit_direction(Vector2(-1,300))==Vector2i.ZERO,"Wall between openings prevents exit")
 check(w.arena.entry_position(Vector2i.RIGHT).x==44,"East travel enters west edge")
 w.arena.exits.assign([Vector2i.LEFT,Vector2i.RIGHT])
 check(w.arena.exit_direction(Vector2(896,-1))==Vector2i.ZERO,"Unconnected direction has no exit")
 w._rebuild_actor_grid()
 w.bullets.add(Vector2(1750,560),Vector2(1000,0),-1,5,3,0,0,0)
 w._update_bullets(0.1)
 check(w.bullets.count()==0,"Ordinary shot dies exactly at wall")
 w.bullets.add(Vector2(1750,560),Vector2(1000,0),-1,5,3,0,0,0,Pool.RICOCHET)
 w._update_bullets(0.1)
 var idx: int=w.bullets.active_indices[0]
 check(w.bullets.velocities[idx].x<0 and w.arena.contains(w.bullets.positions[idx],3),"Ricochet reflects remaining movement inside wall")
 w.bullets.clear()
 var enemy: Dictionary=w._spawn_enemy("fire",1,Vector2(1000,500),false)
 var hp: float=enemy.hp
 w._rebuild_actor_grid()
 w.bullets.add(Vector2(800,500),Vector2(10000,0),-1,7,2,0,0,0)
 w._update_bullets(0.03)
 check(is_equal_approx(enemy.hp,hp-7),"Swept collision hits core without tunnelling")
 w.bullets.clear()
 w.bullets.add(Vector2(800,525),Vector2(10000,0),-1,7,2,0,0,0)
 w._update_bullets(0.03)
 check(is_equal_approx(enemy.hp,hp-7),"Decorative/body footprint is not player/regular hitbox")
 w.bullets.clear()
 enemy.shield=2
 w._rebuild_actor_grid()
 w.bullets.add(Vector2(800,500),Vector2(10000,0),-1,7,2,0,0,0)
 w._update_bullets(0.03)
 check(is_equal_approx(enemy.hp,hp-7) and w.bullets.count()==0,"Shield intercepts incoming projectile before core")
 release(w)
func test_elites() -> void:
 var w: CombatWorld=make_world()
 var elite: Dictionary=w._spawn_elite("fire",3,Vector2(1100,500))
 check(elite.guns.size()>=3 and elite.guns.size()<=8,"Elite has independent authored weapon circles")
 var hp: float=elite.hp
 w._damage_actor(elite,100,0,0)
 check(is_equal_approx(elite.hp,hp-15/float(elite.hp_buffer)),"Armored elite core takes reduced damage")
 var destroyed: int=ceili(elite.guns.size()*0.5)
 for i: int in range(destroyed): w._damage_gun(elite,elite.guns[i],10000,w.player)
 hp=elite.hp
 w._damage_actor(elite,100,0,0)
 check(is_equal_approx(elite.hp,hp-100/float(elite.hp_buffer)),"Half the guns destroyed exposes core")
 var pickups: int=w.pickups.size()
 w._damage_gun(elite,elite.guns[0],10000,w.player)
 check(w.pickups.size()==pickups,"Destroyed gun cannot drop light twice")
 w.bullets.clear()
 w.telegraphs.clear()
 for gun: Dictionary in elite.guns: gun.hp=0.0
 w._update_guns(elite,0.1)
 check(w.bullets.count()==0 and w.telegraphs.is_empty(),"Destroyed guns never fire")
 var saved: Dictionary=JSON.parse_string(JSON.stringify(w.snapshot()))
 w.restore(saved)
 check(w.enemies[0].guns[0].hp==0,"Destroyed mounts persist in save")
 release(w)
func test_components() -> void:
 var w: CombatWorld=make_world()
 var enemy: Dictionary=w._spawn_enemy("fire",1,Vector2(900,500),false)
 enemy.hp=1000.0
 enemy.max_hp=1000.0
 w.player.aim=Vector2.RIGHT
 var before: float=enemy.hp
 w._beam(w.player,"beam",1.0)
 var direct: float=before-float(enemy.hp)
 enemy.hp=before
 w._beam(w.player,"homing_beam",1.0)
 check(is_equal_approx(before-float(enemy.hp),direct*0.6),"Homing beam has 60 percent straight beam DPS")
 w.telegraphs.clear()
 w._queue_attack(w.player,"laser",Vector2(500,500),Vector2(1100,500),0.8,31)
 before=enemy.hp
 w._update_telegraphs(0.79)
 check(enemy.hp==before,"Laser warning causes no early damage")
 w._update_telegraphs(0.02)
 check(is_equal_approx(enemy.hp,before-31),"Laser hits exactly warned segment")
 w._update_telegraphs(0.1)
 check(is_equal_approx(enemy.hp,before-31),"Laser cannot repeatedly hit same target during display")
 w._update_telegraphs(0.25)
 check(w.telegraphs.is_empty(),"Laser hold ends after quarter second")
 w._activate_component(w.player,"shield",w.player.pos,Vector2.RIGHT)
 check(w.player.shield==2.0,"Shield starts two second duration")
 w._tick_cooldowns(w.player,2.1)
 check(w.player.shield==0,"Shield expires")
 w.clouds=[{"pos":w.player.pos,"radius":100.0,"time":4.0,"damage":1.0,"owner":enemy.id,"faction":enemy.faction,"element":"corruption"}]
 w._update_clouds(0.1)
 check(w._slow_multiplier(w.player)==0.7,"Poison slow caps at thirty percent")
 w.clouds.append(w.clouds[0].duplicate())
 w._update_clouds(0.1)
 check(w._slow_multiplier(w.player)==0.7,"Overlapping clouds do not stack slow")
 w.viruses.clear()
 w._attach_virus(w.player,int(enemy.id),40,2)
 enemy.dead=true
 w._update_viruses(0.1)
 check(w.viruses.is_empty(),"Virus generation two terminates without splitting")
 enemy.dead=false
 var other: Dictionary=w._spawn_enemy("plasma",1,Vector2(950,500),false)
 var third: Dictionary=w._spawn_enemy("void",1,Vector2(950,550),false)
 w._attach_virus(w.player,int(enemy.id),40,0)
 enemy.dead=true
 w._update_viruses(0.1)
 check(w.viruses.size()==2 and w.viruses[0].generation==1 and w.viruses[0].damage==20,"Virus splits into two half-DPS generation-one latches")
 check(other.id!=third.id,"Targets have stable identities")
 release(w)
func test_persistence() -> void:
 var w: CombatWorld=make_world()
 w.start_sector({"id":"origin","kind":"origin","cleared":true,"resource_budget":80,"encounter_epoch":0})
 check(w.pickups.size()==3,"Origin still supplies starter typed light when marked cleared")
 w.start_sector({"id":"a","kind":"regular","element":"fire","tier":1,"resource_budget":200,"encounter_epoch":0,"enemy_count":3})
 w.debug_clear()
 var budget: int=w.sector_energy_remaining
 var remaining: int=w.pickups.size()
 w.start_sector({"id":"b","kind":"regular","element":"plasma","tier":1,"resource_budget":200,"encounter_epoch":0,"enemy_count":3})
 w.elapsed+=10000
 w.start_sector({"id":"a","kind":"regular","element":"fire","tier":1,"resource_budget":200,"encounter_epoch":0,"enemy_count":3})
 check(w.enemies.is_empty() and w.sector_energy_remaining==budget and w.pickups.size()==remaining,"Same-life node return never respawns or replenishes")
 w.setup_player("fire",4,750,[],Vector2(500,500))
 w.absorption={"plasma":12.5}
 w.player_invulnerable=1.234
 w.reshape_remaining=0.234
 w.bullets.add(Vector2(600,400),Vector2.RIGHT*500,-1,12,3,0,0,0,Pool.RICOCHET)
 var snapshot: Dictionary=JSON.parse_string(JSON.stringify(w.snapshot()))
 w.restore(snapshot)
 check(w.hull_id=="player_fire_t4_standard_a" and w.hull_history.size()==4,"Hull and history survive JSON resume")
 check(w.light_total==750 and w.absorption.plasma==12.5,"Fractional bar/diet survive resume")
 check(is_equal_approx(w.player_invulnerable,1.234),"Resume preserves remaining grace without granting more")
 check(w.bullets.lives[w.bullets.active_indices[0]]==-1,"Boundary-lived projectile remains boundary-lived on resume")
 release(w)
func test_catalogue_execution() -> void:
 var w: CombatWorld=make_world()
 w.setup_player("fire",5,1200,[],Vector2(500,500))
 var target: Dictionary=w._spawn_enemy("void",5,Vector2(850,500),false)
 target.hp=100000
 target.max_hp=100000
 w.player.aim=Vector2.RIGHT
 check(AbilityCatalog.DEFINITIONS.size()==26,"All 26 specified components have canonical metadata")
 for id: String in AbilityCatalog.DEFINITIONS:
  var a: AbilityDefinition=AbilityCatalog.get_definition(id)
  if a.slot_kind in ["primary","secondary","enemy"]:
   w._activate_component(w.player,id,w.player.pos,Vector2.RIGHT)
  else:
   w.player.ability_set[id]=true
   w._passives(w.player,0.1)
  check(a.id==id and a.tp_cost>0,"Component executes with valid balance metadata: "+id)
 for i: int in range(20): w._physics_process(1.0/60)
 check(w.bullets.rejected==0,"Mixed catalogue combat stays within projectile pool")
 release(w)


func test_regular_patterns() -> void:
 var w: CombatWorld=make_world()
 var counts: Dictionary={}
 for element: String in World.ELEMENTS:
  w._clear_encounter()
  var actor: Dictionary=w._spawn_enemy(element,3,Vector2(1000,500),false)
  actor.aim=Vector2.LEFT
  actor.fire_cd=0.0
  w._regular_pattern(actor,0.016)
  for slot: int in range(actor.secondaries.size()): w._use_secondary(actor,slot)
  counts[element]=w.bullets.count()
  check(w.bullets.count()>0 and w.beams.is_empty(),"Regular "+element+" emits bullet pattern, not player continuous beam")
  if element=="fire": check(not w.telegraphs.is_empty() and w.telegraphs[0].kind=="mine","Fire also lays warned mines")
  if element=="lightning":
   var i: int=w.bullets.active_indices[0]
   check((w.bullets.flags[i]&Pool.CHAIN)!=0 and w.bullets.velocities[i].length()>=600,"Lightning has fast chain bolts")
  if element=="corruption":
   var i: int=w.bullets.active_indices[0]
   check((w.bullets.flags[i]&Pool.INFECT)!=0 and not w.drones.is_empty(),"Corruption combines infection shots and droids")
  if element=="plasma":
   var orbiting: int=0
   for i: int in w.bullets.active_indices:
    if (w.bullets.flags[i]&Pool.ORBIT)!=0: orbiting+=1
   check(orbiting==3 and w.bullets.count()>=7,"Plasma combines rotating spiral and three orbiting shots")
  if element=="void":
   actor.blockers=0.0
   actor.shield=0.0
   w.bullets.clear()
   w._rebuild_actor_grid()
   var hp: float=actor.hp
   w.bullets.add(Vector2(900,500),Vector2.RIGHT*1000,-1,7,2,0,0,0)
   w._update_bullets(0.2)
   check(actor.hp==hp,"Void mouth consumes frontal shots")
   w.bullets.add(Vector2(1100,500),Vector2.LEFT*1000,-1,7,2,0,0,0)
   w._update_bullets(0.2)
   check(actor.hp==hp-7,"Void core remains vulnerable from behind")
 w._clear_encounter()
 w.setup_player("fire",3,300,[],Vector2(4,560))
 w.player.slow=2.0
 w.command.movement=Vector2.LEFT
 for i: int in range(6): w._update_player(1.0/60.0)
 check(w.player.pos.x<0,"Slowed ships can traverse openings without getting trapped at collision margin")
 w.start_sector({"id":"beaten","kind":"core","core_defeated":true,"element":"fire","tier":5,"resource_budget":200,"enemy_count":2})
 var rivals: int=0
 for actor: Dictionary in w.enemies:
  if actor.rival: rivals+=1
 check(rivals==0 and w.enemies.size()>=2,"Beaten core does not respawn rival when soldiers repopulate after death")
 release(w)

func test_cold_cache() -> void:
 var w: CombatWorld=make_world()
 var first: Dictionary={"id":"cold0","kind":"regular","element":"fire","tier":3,"resource_budget":600,"enemy_count":1,"elite_count":1,"encounter_epoch":0}
 w.start_sector(first)
 var elite: Dictionary=w.enemies[-1]
 w._damage_gun(elite,elite.guns[0],10000.0,w.player)
 w._damage_gun(elite,elite.guns[1],11.0,w.player)
 var hp: float=elite.guns[1].hp
 var reward: int=w.sector_energy_remaining
 var pickups: int=w.pickups.size()
 for i: int in range(1,42):
  w.start_sector({"id":"cold%d" % i,"kind":"regular","element":"fire","tier":1,"resource_budget":100,"enemy_count":1,"elite_count":0,"encounter_epoch":0})
 check(w.sector_cache.size()<=32 and not w.sector_cache.has("cold0"),"Decoded encounter cache is bounded and evicts older full records")
 check(w.encounter_records.has("cold0"),"Cold storage retains authoritative evicted encounter")
 var saved: Dictionary=JSON.parse_string(JSON.stringify(w.snapshot()))
 check(not saved.has("sector_cache") and saved.has("encounter_records"),"Save persists compressed records without duplicate decoded cache")
 w.restore(saved)
 w.start_sector(first)
 elite=w.enemies[-1]
 check(elite.guns[0].hp==0 and elite.guns[1].hp==hp,"Cold-cache resume/revisit preserves destroyed and damaged elite guns")
 check(w.sector_energy_remaining==reward and w.pickups.size()==pickups,"Cold-cache revisit preserves earned pickups and depleted light budget")
 release(w)

func test_authored_runtime_contract() -> void:
 var w: CombatWorld=make_world()
 var actor: Dictionary=w._spawn_enemy("plasma",3,Vector2(1000,500),false)
 actor.aim=Vector2.UP
 var definition: ShipDefinition=actor.definition.duplicate(true)
 definition.primary="beam"
 for part: PartDefinition in definition.parts:
  if part.mount_id=="primary": part.ability_id="beam"
 w._configure_actor(actor,definition,true)
 w._regular_pattern(actor,0.1)
 check(not w.beams.is_empty() and w.bullets.count()==0,"Changing regular authored primary to Beam replaces bullet pattern with actual beam")
 definition.primary="ricochet"
 for part: PartDefinition in definition.parts:
  if part.mount_id=="primary":
   part.ability_id="ricochet"
   part.position=Vector2(25,-100)
 w._configure_actor(actor,definition,true)
 w.beams.clear()
 w._regular_pattern(actor,0.1)
 var bullet: int=w.bullets.active_indices[0]
 check((w.bullets.flags[bullet]&Pool.RICOCHET)!=0,"Changing actual primary mount changes projectile mechanic")
 check(w.bullets.positions[bullet]==Vector2(1025,400),"Projectiles originate at authored mounted circle position")
 w._clear_encounter()
 actor=w._spawn_enemy("corruption",3,Vector2(1000,500),false)
 w._update_ai(actor,0.016)
 check(not w.drones.is_empty() and actor.secondaries.has("droid_bay"),"Corruption droids originate from actual mounted droid bay")
 definition=actor.definition.duplicate(true)
 definition.secondaries.assign(["shield"])
 for part: PartDefinition in definition.parts:
  if part.mount_id=="secondary_0": part.ability_id="shield"
 w._configure_actor(actor,definition,true)
 w.drones.clear()
 w._update_ai(actor,0.016)
 check(w.drones.is_empty() and actor.shield>0,"Replacing authored droid bay with shield changes behavior; no intrinsic drones remain")
 definition.secondaries.clear()
 w._configure_actor(actor,definition,true)
 w._update_ai(actor,0.016)
 check(actor.shield==0 and w.drones.is_empty(),"Removing secondaries removes their effects")
 for element: String in World.ELEMENTS:
  for tier: int in range(1,6):
   var elite: Dictionary=w._spawn_elite(element,tier,Vector2(1400,700))
   var weapons: int=0
   var valid: bool=true
   for part: PartDefinition in elite.definition.parts:
    if not part.ability_id.is_empty() and AbilityCatalog.get_definition(part.ability_id).slot_kind!="passive":
     weapons+=1
     valid=valid and part.hp>0.0
   check(valid and weapons==elite.guns.size() and weapons>=3 and weapons<=8,"Every visible elite weapon is active/destructible: "+element+str(tier))
 w._clear_encounter()
 actor=w._spawn_enemy("plasma",3,Vector2(1000,500),false)
 definition=actor.definition.duplicate(true)
 for part: PartDefinition in definition.parts:
  if part.stat_id=="projectile_orbit": part.stat_id="structure"
 w._configure_actor(actor,definition,true)
 w._regular_pattern(actor,0.016)
 var orbit_count: int=0
 for i: int in w.bullets.active_indices:
  if (w.bullets.flags[i]&Pool.ORBIT)!=0: orbit_count+=1
 check(orbit_count==0,"Removing authored orbital body feature removes orbital projectiles")
 w._clear_encounter()
 actor=w._spawn_enemy("lightning",4,Vector2(1100,500),true)
 definition=actor.definition.duplicate(true)
 definition.passives.clear()
 w._configure_actor(actor,definition,true)
 actor.decision_cd=1.0
 actor.desired=Vector2.RIGHT
 actor.desired_aim=Vector2.RIGHT
 actor.aim=Vector2.UP
 actor.fire_cd=10.0
 w._update_ai(actor,0.01)
 var base_speed: float=Vector2(actor.vel).length()
 var base_turn: float=absf(Vector2.UP.angle_to(actor.aim))
 definition.passives.assign(["thrusters"])
 w._configure_actor(actor,definition,true)
 actor.decision_cd=1.0
 actor.desired=Vector2.RIGHT
 actor.desired_aim=Vector2.RIGHT
 actor.aim=Vector2.UP
 actor.fire_cd=10.0
 w._update_ai(actor,0.01)
 check(is_equal_approx(Vector2(actor.vel).length(),base_speed*1.2) and is_equal_approx(absf(Vector2.UP.angle_to(actor.aim)),base_turn*1.2),"NPC Thrusters changes both speed and turn rate")
 definition.passives.clear()
 w._configure_actor(actor,definition,true)
 actor.pos=Vector2(1100,500)
 actor.hp=float(actor.max_hp)-20
 actor.magnet_radius=90.0
 w.pickups=[{"pos":Vector2(1210,500),"vel":Vector2.ZERO,"element":"fire","value":10.0,"phase":0.0}]
 w._update_pickups(0.1)
 check(w.pickups[0].pos==Vector2(1210,500),"NPC base magnet cannot reach pickup outside authored radius")
 definition.passives.assign(["magnet"])
 w._configure_actor(actor,definition,true)
 actor.magnet_radius=90.0
 w._update_pickups(0.1)
 check(w.pickups[0].pos.x<1210,"NPC Magnet attracts within expanded pickup radius")
 definition.passives.assign(["siphon"])
 w._configure_actor(actor,definition,true)
 actor.hp=float(actor.max_hp)-4.0
 w.pickups=[{"pos":actor.pos,"vel":Vector2.ZERO,"element":"fire","value":10.0,"phase":0.0}]
 w._update_pickups(0.1)
 check(actor.hp==actor.max_hp and is_equal_approx(w.pickups[0].value,6.8),"NPC Siphon heals extra while preserving exact excess raw light")
 release(w)
