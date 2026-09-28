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
 "infection_owner","infection_faction","charge","hull_id","beam_contact","core_id","part_seed"
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
 var definition: ShipDefinition = actor.get("definition")
 return {"version": PARTS_VERSION, "geometry_revision": definition.geometry_revision if definition != null else 1, "hp": hp, "max_hp": max_hp, "cd": cd, "egg_cd": egg_cd, "aim": aim, "attached": attached, "reward_share": share}

## Lossless revision-1 pod consolidation. Detached shares have already been paid; only attached
## sources contribute HP/rewards. Leave actor-level reward pools alone, and never revive a host.
static func migrate_parts(encoded: Dictionary, definition: ShipDefinition) -> Dictionary:
 var result: Dictionary = encoded.duplicate(true)
 if encoded.is_empty() or int(encoded.get("geometry_revision", 1)) >= definition.geometry_revision: return result
 var hp: Dictionary = result.get("hp", {})
 var maximum: Dictionary = result.get("max_hp", {})
 var attached: Dictionary = result.get("attached", {})
 var share: Dictionary = result.get("reward_share", {})
 for source: String in definition.removed_part_map:
  var target: String = str(definition.removed_part_map[source])
  if not maximum.has(source): continue
  maximum[target] = float(maximum.get(target, 0.0)) + float(maximum[source])
  var alive: bool = bool(attached.get(source, false)) and bool(attached.get(target, false))
  if alive:
   hp[target] = float(hp.get(target, 0.0)) + maxf(0.0, float(hp.get(source, 0.0)))
   share[target] = float(share.get(target, 0.0)) + float(share.get(source, 0.0))
  for key: String in ["hp", "max_hp", "cd", "egg_cd", "aim", "attached", "reward_share"]:
   if result.has(key): (result[key] as Dictionary).erase(source)
 result.geometry_revision = definition.geometry_revision
 return result

## Applied AFTER `_configure_actor` has rebuilt the packed arrays from the
## (possibly different) restored/edited ShipDefinition, so this only
## overlays the values that actually exist by id - a circle added since the
## save was written keeps its fresh spawn state, not a crash.
static func apply_parts(world: Node, actor: Dictionary, encoded: Dictionary) -> void:
 var rig: ShipMotion.ShipRig = actor.get("rig")
 if rig == null or encoded.is_empty(): return
 encoded = migrate_parts(encoded, actor.definition)
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
 # New glyph circles inherit the restored host's visibility. A saved dead hub must never grow
 # fresh decorations when a weapon's drawing changes between versions.
 for i: int in range(1, rig.ids.size()):
  var parent: int = rig.parent_index[i]
  if parent >= 0 and not bool(actor.part_attached[parent]):
   actor.part_attached[i] = 0
   actor.part_hp[i] = 0.0
 world._rebuild_part_views(actor)

static func actor_snapshot(world: Node, actor: Dictionary) -> Dictionary:
 var copy: Dictionary = {}
 for key: String in ACTOR_ALLOW:
  if actor.has(key): copy[key] = actor[key]
 copy.parts = encode_parts(actor)
 copy.hull_definition = ShipCatalog.encode_definition(actor.get("definition"))
 var rig: ShipMotion.ShipRig = actor.get("rig")
 var pose: ShipMotion.ShipPose = actor.get("pose")
 if rig != null and pose != null:
  var chain: Dictionary = ShipMotion.encode_chain_state(rig, pose)
  if not chain.is_empty(): copy.chain_motion = chain
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
  var definition: ShipDefinition=ShipCatalog.get_ship_revision(str(actor.get("hull_id","")), int(parts.get("geometry_revision", 1)), actor.get("hull_definition", {}))
  if definition==null: continue
  world._configure_actor(actor,definition,false)
  apply_parts(world,actor,parts)
  _restore_chain(world, actor, actor.get("chain_motion", {}))
  actor.erase("hull_definition")
  actor.erase("chain_motion")
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
 result.merge({"version":3,"light_total":world.light_total,"hull_id":world.hull_id,"hull_history":world.hull_history,"absorption":world.absorption,"player":actor_snapshot(world,world.player),"position":[world.player_position.x,world.player_position.y],"element":world.player_element,"tier":world.player_tier,"energy":world.light_total,"hp":world.light_total,"stolen":[],"elapsed":world.elapsed,"tick":world.tick,"sector":json_value(world.sector),"encounter_records":world.encounter_records,"encounter_epoch":world.encounter_epoch,"next_actor_id":world.next_actor_id,"player_invulnerable":world.player_invulnerable,"reshape_remaining":world.reshape_remaining,"rng_state":str(world._rng.state),"active":world.active,"max_player_tier":world.max_player_tier,"warp_phase":world.warp_phase,"warp_direction":[world.warp_direction.x,world.warp_direction.y],"warp_commit_speed":world.warp_commit_speed,"warp_reduced":world.warp_reduced,"warp_exit_point":[world.warp_exit_point.x,world.warp_exit_point.y],"warp_exit_velocity":[world.warp_exit_velocity.x,world.warp_exit_velocity.y],"warp_heading":[world.warp_heading.x,world.warp_heading.y]})
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
 world.tick=int(data.get("tick",0))
 world.elapsed=float(data.get("elapsed",0.0))
 world.set_player_hull(str(data.get("hull_id","player_seed")))
 world.hull_id=str(data.get("hull_id","player_seed"))
 world.hull_history.assign(data.get("hull_history",["player_seed"]))
 world.absorption=data.get("absorption",{}).duplicate(true)
 var restored: Dictionary=decode_value(data.get("player",{}))
 var player_parts: Dictionary=restored.get("parts",{})
 restored.erase("parts")
 for key: String in restored:
  if key in ACTOR_ALLOW: world.player[key]=restored[key]
 var player_definition: ShipDefinition = ShipCatalog.get_ship_revision(world.hull_id, int(player_parts.get("geometry_revision", 1)), restored.get("hull_definition", {}))
 if player_definition == null:
  push_error("Saved player geometry is unavailable: %s revision %d" % [world.hull_id, int(player_parts.get("geometry_revision", 1))])
  return
 world._configure_actor(world.player,player_definition,false)
 apply_parts(world,world.player,player_parts)
 _restore_chain(world, world.player, restored.get("chain_motion", {}))
 world.light_total=float(data.get("light_total",40.0))
 world.player.hp=world.light_total
 world.player_position=world.player.pos
 world.elapsed=float(data.get("elapsed",0.0))
 # Review finding 4: `tick` is the clock ShipMotion.step actually reads (not
 # `elapsed`, which decides nothing geometric) - it drives every orbit/
 # drift/breathe group, hence every collider position and gun muzzle.
 # P1's own todo promised this snapshot field "in P2" and it never landed,
 # so restore was never idempotent: the same bytes restored at tick 1000 vs
 # tick 5000 produced different limb/muzzle positions, and a boss's orbiting
 # weapon circles visibly jumped on load.
 world.tick=int(data.get("tick",0))
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
 # Modernization M3: the committed rim point and velocity the arrival reflects, and the locked
 # phases' heading. A save from before M3 has none of them; it falls back to the zero-offset
 # arrival along the travel bearing, exactly what that save's warp would have done.
 var bearing: Vector2=Vector2(world.warp_direction).normalized()
 world.warp_exit_point=_vector2_field(data,"warp_exit_point",world.arena.center+bearing*world.arena.radius)
 world.warp_exit_velocity=_vector2_field(data,"warp_exit_velocity",bearing*world.warp_commit_speed)
 world.warp_heading=_vector2_field(data,"warp_heading",bearing)
 world._warp_timer=0.0
 world._warp_locked_accum=0.0
 world._warp_push_depth=0.0
 # Review finding 3: a save can only ever land on a phase past WARP_PUSH via
 # `_on_warp_committed`, which calls `confirm_warp_swap()` SYNCHRONOUSLY
 # before `_save_game()` even runs (main.gd:796 then :812) - the sector swap
 # (campaign.on_enter + combat.start_sector) always happens before the warp
 # locks the player in. So whenever the saved phase is past PUSH, the swap
 # is a settled fact of the save, not something to re-derive from the phase
 # - the previous formula had this backwards (false exactly when it needed
 # to be true), which meant _update_warp's own TRAVEL-phase check
 # (`if not _warp_swap_done: _warp_spring_back()`) fired on every restore
 # taken past commit, pushing the player out along the exit direction into
 # a phantom warp instead of ever reaching `_warp_arrive()`.
 world._warp_swap_done=not (world.warp_phase==world.WARP_NONE or world.warp_phase==world.WARP_PUSH)
static func _vector2_field(data: Dictionary, key: String, fallback: Vector2) -> Vector2:
 var value: Variant=data.get(key)
 if value is Array and value.size()==2: return Vector2(float(value[0]),float(value[1]))
 return fallback
static func _restore_chain(world: Node, actor: Dictionary, encoded: Dictionary) -> void:
 var rig: ShipMotion.ShipRig = actor.get("rig")
 var pose: ShipMotion.ShipPose = actor.get("pose")
 if rig == null or pose == null or encoded.is_empty(): return
 ShipMotion.restore_chain_state(rig, pose, decode_value(encoded))
 # Cached encounters remain frozen while absent. Resume their saved shape at the live clock.
 pose.chain_tick = world.tick
 ShipMotion.step(rig, pose, world.tick, Vector2(actor.pos), Vector2(actor.aim).angle() + PI * 0.5, actor.part_attached)
 world._rebuild_part_views(actor)

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
