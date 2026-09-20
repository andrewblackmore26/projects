class_name CombatPersistence
extends RefCounted
## Owns encounter/world snapshot & restore, the JSON-safe value coder, and the
## compressed encounter cache (encounter_records + decoded sector_cache LRU).
## Pure functions that take the CombatWorld as their first argument; state
## that is saved (encounter_records, sector_cache, rng, etc.) stays on the
## world itself.
##
## P4a: actor snapshotting is an ALLOW-list, not an exclusion list (an
## exclusion list fails open - a new field silently serialises a renderer or
## a rig the day someone adds one). Per-circle mutable state (`part_hp` etc.)
## is encoded separately, keyed by CIRCLE ID rather than rig index, so a
## mid-fight definition edit remaps by identity instead of position.
const ACTOR_ALLOW: Array = [
 "id","element","tier","pos","vel","aim","faction","native_faction","rival","elite",
 "hp","max_hp","energy","fire_cd","primary_cd","secondary_cd","decision_cd","target",
 "desired","desired_aim","age","dead","invulnerable","reward_remaining","reward_damage",
 "reward_unpaid_limb","_reward_split","cooldowns","shield","blockers","blocker_hits",
 "orbit_stock","orbit_cd","slow","stored","stolen","infected","infection_damage",
 "infection_owner","infection_faction","charge","hull_id","beam_contact","core_id"
]
const PARTS_VERSION: int = 1

static func encode_parts(actor: Dictionary) -> Dictionary:
 var rig: ShipMotion.ShipRig = actor.get("rig")
 if rig == null or not actor.has("part_hp"): return {}
 var hp: Dictionary = {}
 var max_hp: Dictionary = {}
 var cd: Dictionary = {}
 var egg_cd: Dictionary = {}
 var aim: Dictionary = {}
 var attached: Dictionary = {}
 var share: Dictionary = {}
 for i in range(rig.ids.size()):
  var id: String = rig.ids[i]
  hp[id] = float(actor.part_hp[i])
  max_hp[id] = float(actor.part_max_hp[i])
  cd[id] = float(actor.part_cd[i])
  egg_cd[id] = float(actor.part_egg_cd[i])
  aim[id] = json_value(actor.part_aim[i])
  attached[id] = bool(actor.part_attached[i])
  share[id] = float(actor.part_reward_share[i]) if i < actor.part_reward_share.size() else 0.0
 return {"version": PARTS_VERSION, "hp": hp, "max_hp": max_hp, "cd": cd, "egg_cd": egg_cd, "aim": aim, "attached": attached, "reward_share": share}

## Applied AFTER `_configure_actor` has rebuilt the packed arrays from the
## (possibly different) restored/edited ShipDefinition, so this only
## overlays the values that actually exist by id - a circle added since the
## save was written keeps its fresh spawn state, not a crash.
static func apply_parts(world: Node, actor: Dictionary, encoded: Dictionary) -> void:
 var rig: ShipMotion.ShipRig = actor.get("rig")
 if rig == null or encoded.is_empty(): return
 var hp: Dictionary = encoded.get("hp", {})
 var max_hp: Dictionary = encoded.get("max_hp", {})
 var cd: Dictionary = encoded.get("cd", {})
 var egg_cd: Dictionary = encoded.get("egg_cd", {})
 var aim: Dictionary = encoded.get("aim", {})
 var attached: Dictionary = encoded.get("attached", {})
 var share: Dictionary = encoded.get("reward_share", {})
 for i in range(rig.ids.size()):
  var id: String = rig.ids[i]
  if hp.has(id): actor.part_hp[i] = float(hp[id])
  if max_hp.has(id): actor.part_max_hp[i] = float(max_hp[id])
  if cd.has(id): actor.part_cd[i] = float(cd[id])
  if egg_cd.has(id): actor.part_egg_cd[i] = float(egg_cd[id])
  if aim.has(id): actor.part_aim[i] = decode_value(aim[id])
  if attached.has(id): actor.part_attached[i] = 1 if bool(attached[id]) else 0
  if share.has(id) and i < actor.part_reward_share.size(): actor.part_reward_share[i] = float(share[id])
 actor.part_hp[0] = float(actor.hp)
 actor.part_max_hp[0] = float(actor.max_hp)
 actor.part_attached[0] = 1
 world._rebuild_part_views(actor)

static func actor_snapshot(world: Node, actor: Dictionary) -> Dictionary:
 var copy: Dictionary = {}
 for key: String in ACTOR_ALLOW:
  if actor.has(key): copy[key] = actor[key]
 copy.parts = encode_parts(actor)
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
  var parts: Dictionary=actor.get("parts",{})
  actor.erase("parts")
  actor.renderer=null
  var definition: ShipDefinition=ShipCatalog.get_ship(str(actor.get("hull_id","")))
  if definition==null: continue
  world._configure_actor(actor,definition,false)
  apply_parts(world,actor,parts)
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
 world._flush_debris() # light must not ride along as an object reference; pay it out first (spec item 3)
 var result: Dictionary=encounter_snapshot(world)
 result.merge({"version":3,"light_total":world.light_total,"hull_id":world.hull_id,"hull_history":world.hull_history,"absorption":world.absorption,"player":actor_snapshot(world,world.player),"position":[world.player_position.x,world.player_position.y],"element":world.player_element,"tier":world.player_tier,"energy":world.light_total,"hp":world.light_total,"stolen":[],"elapsed":world.elapsed,"sector":json_value(world.sector),"encounter_records":world.encounter_records,"encounter_epoch":world.encounter_epoch,"next_actor_id":world.next_actor_id,"player_invulnerable":world.player_invulnerable,"reshape_remaining":world.reshape_remaining,"rng_state":str(world._rng.state),"active":world.active,"max_player_tier":world.max_player_tier,"warp_phase":world.warp_phase,"warp_direction":[world.warp_direction.x,world.warp_direction.y],"warp_commit_speed":world.warp_commit_speed,"warp_reduced":world.warp_reduced})
 return result
static func restore(world: Node, data: Dictionary) -> void:
 # P4a bumped the schema to 3 (per-circle allow-listed state). An older
 # payload is rejected outright rather than half-read: it has no `parts`
 # block, so every enemy would silently spawn with full, unattached limbs.
 if int(data.get("version",0))<3:
  push_error("CombatPersistence.restore: payload version %d is older than the minimum supported version 3; refusing to half-read it." % int(data.get("version",0)))
  return
 world._clear_encounter()
 world.max_player_tier=clampi(int(data.get("max_player_tier",GameTuning.MAX_TIER)),1,GameTuning.MAX_TIER)
 var pos: Array=data.get("position",[896,560])
 world.setup_player("neutral",1,float(data.get("light_total",40.0)),[],Vector2(float(pos[0]),float(pos[1])))
 world.set_player_hull(str(data.get("hull_id","player_seed")))
 world.hull_history.assign(data.get("hull_history",["player_seed"]))
 world.absorption=data.get("absorption",{}).duplicate(true)
 var restored: Dictionary=decode_value(data.get("player",{}))
 var player_parts: Dictionary=restored.get("parts",{})
 restored.erase("parts")
 for key: String in restored:
  if key in ACTOR_ALLOW: world.player[key]=restored[key]
 world._configure_actor(world.player,ShipCatalog.get_ship(world.hull_id),false)
 apply_parts(world,world.player,player_parts)
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
 # Warp state (spec P6 item 6: saving must be safe DURING the locked phase).
 # Sub-phase timers are not carried across a save/restore boundary - a
 # restore mid-warp resumes the same phase from its start rather than the
 # exact millisecond, which is a deliberate simplification (a save only
 # happens at commit, not on every tick of the lock).
 world.warp_phase=int(data.get("warp_phase",world.WARP_NONE))
 var wd: Array=data.get("warp_direction",[0,0])
 world.warp_direction=Vector2i(int(wd[0]),int(wd[1]))
 world.warp_commit_speed=float(data.get("warp_commit_speed",0.0))
 world.warp_reduced=bool(data.get("warp_reduced",false))
 world._warp_timer=0.0
 world._warp_locked_accum=0.0
 world._warp_push_depth=0.0
 world._warp_swap_done=world.warp_phase==world.WARP_NONE or world.warp_phase==world.WARP_PUSH
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
