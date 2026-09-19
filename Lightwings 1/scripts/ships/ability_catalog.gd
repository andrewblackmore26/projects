class_name AbilityCatalog
extends RefCounted
## Shared component balance, editor costs and runtime parameters.
static var catalog_root: String = "res://content/ships/abilities"
static var _cache: Dictionary = {}
# slot, cooldown, damage (DPS for continuous effects), range, TP, min tier, color, duration
const DEFINITIONS: Dictionary = {
 "pulse_cannon": ["primary",0.20,13.0,0.0,1.0,1,"red",0.0],
 "beam": ["primary",0.0,65.0,0.0,2.0,2,"red",0.0],
 "homing_beam": ["primary",0.0,39.0,0.0,2.0,2,"violet",0.0],
 "ricochet": ["primary",0.26,18.0,0.0,2.0,2,"yellow",0.0],
 "flame_cone": ["primary",0.16,5.0,220.0,2.0,2,"yellow",0.0],
 "bolt": ["primary",0.28,23.0,180.0,2.0,2,"violet",0.0],
 "virus": ["secondary",7.0,40.0,650.0,2.0,2,"green",0.0],
 "seeker_missiles": ["secondary",3.0,22.0,0.0,2.0,2,"red",0.0],
 "rocket_launcher": ["secondary",4.0,30.0,0.0,2.0,2,"red",0.0],
 "shield": ["secondary",8.0,0.0,65.0,2.0,2,"yellow",2.0],
 "explosives": ["secondary",3.0,50.0,95.0,2.0,2,"red",1.2],
 "laser_prong": ["secondary",1.55,31.0,0.0,2.0,2,"red",0.25],
 "poison_cloud": ["secondary",5.0,14.0,110.0,2.0,2,"green",4.0],
 "mine_layer": ["secondary",2.0,45.0,65.0,2.0,2,"red",12.0],
 "orbital_blockers": ["secondary",7.0,0.0,60.0,2.0,2,"yellow",5.0],
 "orbital_seekers": ["passive",3.0,22.0,320.0,2.0,4,"red",0.0],
 "radar": ["passive",0.0,0.0,0.0,1.0,4,"yellow",0.0],
 "health_readout": ["passive",0.0,0.0,0.0,1.0,4,"yellow",0.0],
 "magnet": ["passive",0.0,0.0,1.5,1.0,4,"yellow",0.0],
 "siphon": ["passive",0.0,0.0,1.25,1.0,4,"green",0.0],
 "thrusters": ["passive",0.0,0.0,1.2,1.0,4,"yellow",0.0],
 "forcefield": ["passive",0.0,18.0,45.0,2.0,4,"red",0.0],
 "egg": ["enemy",4.0,15.0,0.0,2.0,1,"red",0.0],
 "droid_bay": ["enemy",6.0,24.0,0.0,2.0,1,"green",0.0],
 "deployment_ramp": ["enemy",8.0,0.0,0.0,2.0,1,"yellow",0.0],
 "turret_ring": ["enemy",1.4,10.0,80.0,2.0,1,"red",0.0]
}
static func get_definition(id: String) -> AbilityDefinition:
 var key: String=catalog_root+":"+id
 if _cache.has(key): return _cache[key]
 var value: AbilityDefinition=build_definition(id)
 var path: String=catalog_root.path_join(id+".tres")
 if DEFINITIONS.has(id) and ResourceLoader.exists(path):
  var resource: Resource=ResourceLoader.load(path)
  if resource is AbilityDefinition and resource.id==id: value=resource
 _cache[key]=value
 return value
static func invalidate_cache() -> void:
 _cache.clear()
static func build_definition(id: String) -> AbilityDefinition:
 var a: AbilityDefinition = AbilityDefinition.new()
 a.id = id
 a.display_name = id.replace("_", " ").capitalize()
 if not DEFINITIONS.has(id): return a
 var d: Array = DEFINITIONS[id]
 a.slot_kind = str(d[0])
 a.trigger = str(d[0])
 a.cooldown = float(d[1])
 a.damage = float(d[2])
 a.range_pixels = float(d[3])
 a.tp_cost = float(d[4])
 a.minimum_tier = int(d[5])
 a.visual_color = str(d[6])
 a.duration = float(d[7])
 a.description = a.display_name
 if a.slot_kind == "enemy": a.allowed_factions = ["enemy", "elite", "rival"]
 return a
static func all_definitions() -> Array[AbilityDefinition]:
 var result: Array[AbilityDefinition] = []
 for id: String in DEFINITIONS: result.append(build_definition(id))
 return result
