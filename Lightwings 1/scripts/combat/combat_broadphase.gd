class_name CombatBroadphase
extends RefCounted
## Owns the per-frame spatial hash used to resolve bullet/actor collisions.
## Collider Dictionaries are cached on actors/guns/drones exactly as before;
## this class only owns the grid, the collider list and the query state.
const CELL_SIZE: float = 96.0
var world: Node
var grid: Dictionary = {}
var colliders: Array = []
var query_results: Array = []
var empty_colliders: Array = []
var query_serial: int = 0

func clear() -> void:
 grid.clear()
 colliders.clear()
 query_results.clear()
func rebuild() -> void:
 for occupants: Array in grid.values(): occupants.clear()
 colliders.clear()
 for actor: Dictionary in world.actors_by_id.values():
  if bool(actor.dead): continue
  var c: Dictionary=actor.get("core_collider",{})
  if c.is_empty():
   c={"actor":actor,"gun":{},"drone":{},"query":-1,"radius":3.0}
   actor.core_collider=c
  c.pos=actor.pos
  c.radius=65.0 if float(actor.shield)>0.0 else 3.0
  c.void_eater=false
  insert(c)
  if actor.get("body_features",{}).has("bullet_eater"):
   var mouth: Dictionary=actor.get("mouth_collider",{})
   if mouth.is_empty():
    mouth={"actor":actor,"gun":{},"drone":{},"query":-1,"radius":9.0,"void_eater":true}
    actor.mouth_collider=mouth
   mouth.radius=float(actor.body_features.bullet_eater.value)
   mouth.pos=Vector2(actor.pos)+Vector2(actor.body_features.bullet_eater.offset).rotated(Vector2(actor.aim).angle()+PI/2.0)
   insert(mouth)
  for gun: Dictionary in actor.guns:
   if float(gun.hp)<=0.0: continue
   var g: Dictionary=gun.get("collider",{})
   if g.is_empty():
    g={"actor":actor,"gun":gun,"drone":{},"query":-1}
    gun.collider=g
   g.pos=world._gun_position(actor,gun)
   g.radius=gun.radius
   insert(g)
  if float(actor.blockers)>0.0 and int(actor.blocker_hits)>0:
   for i: int in range(3):
    var key: String="blocker_%d" % i
    var blocker: Dictionary=actor.get(key,{})
    if blocker.is_empty():
     blocker={"actor":actor,"gun":{},"drone":{},"query":-1,"radius":7.0,"blocker":true}
     actor[key]=blocker
    blocker.pos=Vector2(actor.pos)+Vector2.from_angle(world.elapsed*2.0+TAU*i/3.0)*60.0
    insert(blocker)
 for drone: Dictionary in world.drones:
  var c: Dictionary=drone.get("collider",{})
  if c.is_empty():
   c={"actor":{},"gun":{},"drone":drone,"query":-1,"radius":9.0}
   drone.collider=c
  c.pos=drone.pos
  insert(c)
func insert(c: Dictionary) -> void:
 colliders.append(c)
 var radius: float=float(c.radius)
 var p: Vector2=c.pos
 var lo: Vector2i=Vector2i(floori((p.x-radius)/CELL_SIZE),floori((p.y-radius)/CELL_SIZE))
 var hi: Vector2i=Vector2i(floori((p.x+radius)/CELL_SIZE),floori((p.y+radius)/CELL_SIZE))
 for y: int in range(lo.y,hi.y+1):
  for x: int in range(lo.x,hi.x+1):
   var key: Vector2i=Vector2i(x,y)
   if not grid.has(key): grid[key]=[]
   grid[key].append(c)
func query_segment(from: Vector2, to: Vector2, radius: float) -> Array:
 var lo: Vector2i=Vector2i(floori((minf(from.x,to.x)-radius)/CELL_SIZE),floori((minf(from.y,to.y)-radius)/CELL_SIZE))
 var hi: Vector2i=Vector2i(floori((maxf(from.x,to.x)+radius)/CELL_SIZE),floori((maxf(from.y,to.y)+radius)/CELL_SIZE))
 if lo==hi: return grid.get(lo,empty_colliders)
 query_results.clear()
 query_serial+=1
 for y: int in range(lo.y,hi.y+1):
  for x: int in range(lo.x,hi.x+1):
   for c: Dictionary in grid.get(Vector2i(x,y),empty_colliders):
    if int(c.query)!=query_serial:
     c.query=query_serial
     query_results.append(c)
 return query_results
