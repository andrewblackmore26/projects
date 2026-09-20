class_name CombatPersistence
extends RefCounted
## Owns encounter/world snapshot & restore, the JSON-safe value coder, and the
## compressed encounter cache (encounter_records + decoded sector_cache LRU).
## Pure functions that take the CombatWorld as their first argument; state
## that is saved (encounter_records, sector_cache, rng, etc.) stays on the
## world itself.
static func actor_snapshot(world: Node, actor: Dictionary) -> Dictionary:
 var copy: Dictionary={}
 for key: String in actor:
  if key in ["renderer","definition","core_collider","mouth_collider","blocker_0","blocker_1","blocker_2","guns","rig","pose"]: continue
  copy[key]=actor[key]
 var guns: Array=[]
 for gun: Dictionary in actor.get("guns",[]):
  var g: Dictionary={}
  for key: String in gun:
   if key!="collider": g[key]=gun[key]
  guns.append(g)
 copy.guns=guns
 return json_value(copy)
static func drone_snapshots(world: Node) -> Array:
 var result: Array=[]
 for drone: Dictionary in world.drones:
  var copy: Dictionary={}
  for key: String in drone:
   if key!="collider": copy[key]=drone[key]
  result.append(json_value(copy))
 return result
static func encounter_snapshot(world: Node, include_transients: bool = true) -> Dictionary:
 var actors: Array=[]
 for actor: Dictionary in world.enemies: actors.append(actor_snapshot(world,actor))
 return {"enemies":actors,"pickups":json_value(world.pickups),"drones":drone_snapshots(world) if include_transients else [],"telegraphs":json_value(world.telegraphs) if include_transients else [],"viruses":json_value(world.viruses) if include_transients else [],"clouds":json_value(world.clouds) if include_transients else [],"bullets":world.bullets.to_array() if include_transients else [],"cleared":world.cleared_emitted,"resource_remaining":world.sector_energy_remaining,"resource_paid":world.sector_energy_paid}
static func restore_encounter(world: Node, data: Dictionary) -> void:
 world._clear_encounter()
 for item: Variant in Array(data.get("enemies",[])).slice(0,world.MAX_ACTORS):
  if not item is Dictionary: continue
  var actor: Dictionary=decode_value(item)
  actor.renderer=null
  var definition: ShipDefinition=ShipCatalog.get_ship(str(actor.get("hull_id","")))
  if definition==null: continue
  world._configure_actor(actor,definition,false)
  world.enemies.append(actor)
  world.actors_by_id[int(actor.id)]=actor
  world.next_actor_id=maxi(world.next_actor_id,int(actor.id)+1)
  world._update_visual(actor)
 world.pickups=decode_value(data.get("pickups",[]))
 world.drones=decode_value(data.get("drones",[]))
 world.telegraphs=decode_value(data.get("telegraphs",[]))
 world.viruses=decode_value(data.get("viruses",[]))
 world.clouds=decode_value(data.get("clouds",[]))
 world.bullets.from_array(data.get("bullets",[]))
 world.cleared_emitted=bool(data.get("cleared",false))
 world.sector_energy_remaining=int(data.get("resource_remaining",0))
 world.sector_energy_paid=int(data.get("resource_paid",0))
 world.bullet_count=world.bullets.count()
static func snapshot(world: Node) -> Dictionary:
 var result: Dictionary=encounter_snapshot(world)
 result.merge({"version":2,"light_total":world.light_total,"hull_id":world.hull_id,"hull_history":world.hull_history,"absorption":world.absorption,"player":actor_snapshot(world,world.player),"position":[world.player_position.x,world.player_position.y],"element":world.player_element,"tier":world.player_tier,"energy":world.light_total,"hp":world.light_total,"stolen":[],"elapsed":world.elapsed,"sector":json_value(world.sector),"encounter_records":world.encounter_records,"encounter_epoch":world.encounter_epoch,"next_actor_id":world.next_actor_id,"player_invulnerable":world.player_invulnerable,"reshape_remaining":world.reshape_remaining,"rng_state":str(world._rng.state),"active":world.active,"max_player_tier":world.max_player_tier})
 return result
static func restore(world: Node, data: Dictionary) -> void:
 if int(data.get("version",0))<2: return
 world._clear_encounter()
 world.max_player_tier=clampi(int(data.get("max_player_tier",GameTuning.MAX_TIER)),1,GameTuning.MAX_TIER)
 var pos: Array=data.get("position",[896,560])
 world.setup_player("neutral",1,float(data.get("light_total",40.0)),[],Vector2(float(pos[0]),float(pos[1])))
 world.set_player_hull(str(data.get("hull_id","player_seed")))
 world.hull_history.assign(data.get("hull_history",["player_seed"]))
 world.absorption=data.get("absorption",{}).duplicate(true)
 var restored: Dictionary=decode_value(data.get("player",{}))
 for key: String in restored:
  if key not in ["definition","renderer","core_collider","rig","pose"]: world.player[key]=restored[key]
 world._configure_actor(world.player,ShipCatalog.get_ship(world.hull_id),false)
 world.light_total=float(data.get("light_total",40.0))
 world.player.hp=world.light_total
 world.player_position=world.player.pos
 world.elapsed=float(data.get("elapsed",0.0))
 world.sector=decode_value(data.get("sector",{}))
 world._configure_arena_exits()
 world.sector_cache.clear()
 world.encounter_records=data.get("encounter_records",{}).duplicate(true)
 # Early v2 saves used full dictionaries. Upgrade losslessly on restore.
 for key: String in data.get("sector_cache",{}):
  cache_encounter(world,key,data.sector_cache[key])
 world.encounter_epoch=int(data.get("encounter_epoch",0))
 restore_encounter(world,data)
 world.next_actor_id=maxi(world.next_actor_id,int(data.get("next_actor_id",1)))
 world.player_invulnerable=float(data.get("player_invulnerable",0.0))
 world.reshape_remaining=float(data.get("reshape_remaining",0.0))
 world._rng.state=int(str(data.get("rng_state","1")))
 world.active=bool(data.get("active",true)) and world.light_total>0.0
 world.benchmark_mode=false
static func json_value(value: Variant) -> Variant:
 if value is Vector2: return {"$v2":[value.x,value.y]}
 if value is Vector2i: return {"$v2i":[value.x,value.y]}
 if value is Dictionary:
  var result: Dictionary={}
  for key: Variant in value: result[str(key)]=json_value(value[key])
  return result
 if value is Array:
  var result: Array=[]
  for item: Variant in value: result.append(json_value(item))
  return result
 return value
static func decode_value(value: Variant) -> Variant:
 if value is Dictionary:
  if value.has("$v2"): return Vector2(float(value["$v2"][0]),float(value["$v2"][1]))
  if value.has("$v2i"): return Vector2i(int(value["$v2i"][0]),int(value["$v2i"][1]))
  var result: Dictionary={}
  for key: Variant in value: result[key]=decode_value(value[key])
  return result
 if value is Array:
  var result: Array=[]
  for item: Variant in value: result.append(decode_value(item))
  return result
 return value
static func cache_encounter(world: Node, key: String, data: Dictionary) -> void:
 var compressed: PackedByteArray=var_to_bytes(data).compress(FileAccess.COMPRESSION_DEFLATE)
 world.encounter_records[key]=Marshalls.raw_to_base64(compressed)
 remember_decoded(world,key,data)
static func remember_decoded(world: Node, key: String, data: Dictionary) -> void:
 world.sector_cache.erase(key)
 world.sector_cache[key]=data
 while world.sector_cache.size()>world.DECODED_CACHE_LIMIT: world.sector_cache.erase(world.sector_cache.keys()[0])
static func read_cached_encounter(world: Node, key: String) -> Dictionary:
 if world.sector_cache.has(key):
  var data: Dictionary=world.sector_cache[key]
  remember_decoded(world,key,data)
  return data
 var compressed: PackedByteArray=Marshalls.base64_to_raw(str(world.encounter_records.get(key,"")))
 var raw: PackedByteArray=compressed.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_DEFLATE)
 var value: Variant=bytes_to_var(raw) if not raw.is_empty() else null
 if not value is Dictionary:
  push_error("Encounter record could not be decoded: "+key)
  return {"cleared":true,"enemies":[],"pickups":[],"resource_remaining":0,"resource_paid":0}
 remember_decoded(world,key,value)
 return value
