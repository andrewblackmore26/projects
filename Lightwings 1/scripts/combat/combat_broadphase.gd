class_name CombatBroadphase
extends RefCounted
## Owns the per-frame spatial hash used to resolve bullet/actor collisions.
## Collider Dictionaries are cached on the actor (core, per circle, void mouth, blockers) and on the
## drone, so a rebuild reuses them rather than allocating.
##
## Spec §16 gives enemies per-circle hitboxes, which puts 2-3x more colliders in the grid than the
## v0.2 per-gun version, and the bullet phase pays for every candidate in a cell. Two alternatives
## were measured at 2000 bullets before settling here:
##   per-circle, 96 px cells  mean 8.64  p95 13.93   (the naive version)
##   one bound per enemy + a narrow phase over its circles   mean 9.29  p95 14.25
##   per-circle, 32 px cells  mean 6.92  p95  9.50   <- this
## The bound-plus-narrow-phase version lost because a hull's bound is large (up to ~180 px), so in a
## crowded node nearly every bullet fell inside one and re-tested all of its circles. Smaller cells
## win instead: a hull's circles spread across more cells, so a bullet near it tests few of them.
## Measured section split at 2000 bullets: bullets 5.17 ms, ai 1.54, grid rebuild 0.58, upload 1.06.
const CELL_SIZE: float = 32.0
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
   c={"actor":actor,"drone":{},"part_index":0,"query":-1,"radius":3.0}
   actor.core_collider=c
  c.pos=actor.pos
  c.radius=65.0 if float(actor.shield)>0.0 else 3.0
  c.void_eater=false
  insert(c)
  if actor.get("body_features",{}).has("bullet_eater"):
   var mouth: Dictionary=actor.get("mouth_collider",{})
   if mouth.is_empty():
    mouth={"actor":actor,"drone":{},"part_index":-1,"query":-1,"radius":9.0,"void_eater":true}
    actor.mouth_collider=mouth
   mouth.radius=float(actor.body_features.bullet_eater.value)
   var feature: Dictionary=actor.body_features.bullet_eater
   var local: Vector2=world._local_position(actor,str(feature.get("part_id","")),Vector2(feature.offset))
   mouth.pos=Vector2(actor.pos)+local.rotated(Vector2(actor.aim).angle()+PI/2.0)
   insert(mouth)
  # P4a: enemies have per-circle hitboxes (§16), but registering every circle put 5-10x the
  # colliders in the grid and every bullet paid for it (measured: 1000-bullet p95 4.3-4.8 -> 7.3 ms).
  # So the grid carries ONE conservative bound per enemy (BODY_BOUND) and the bullet resolver walks
  # that actor's alive circles only when a shot actually reaches the bound. The player keeps a
  # core-only hitbox, so it registers no body collider at all.
  var rig: ShipMotion.ShipRig=actor.get("rig")
  if rig!=null and int(actor.id)!=0:
   var cache: Dictionary=actor.get("part_colliders",{})
   var pose: ShipMotion.ShipPose=actor.get("pose")
   var hp: PackedFloat32Array=actor.part_hp
   # One rotation basis for the whole hull instead of an atan2/sin/cos per circle.
   var angle: float=Vector2(actor.aim).angle()+PI/2.0
   var ca: float=cos(angle)
   var sa: float=sin(angle)
   var origin: Vector2=actor.pos
   # The rig's solid circles, ascending. For a v0.3 hull that is every circle but the core, in the
   # same order as before. For a rail-grammar hull it leaves out the rail rings (a 184 px collider
   # would swallow the arena), inner core rings, passive rings and set-piece circles.
   for i: int in rig.solid_indices:
    if hp[i]<=0.0: continue
    var g: Dictionary=cache.get(i,{})
    if g.is_empty():
     g={"actor":actor,"drone":{},"part_index":i,"query":-1}
     cache[i]=g
    var l: Vector2=pose.local[i] if pose!=null and i<pose.local.size() else rig.rest[i]
    g.pos=origin+Vector2(l.x*ca-l.y*sa,l.x*sa+l.y*ca)
    g.radius=rig.radius[i]
    insert(g)
   actor.part_colliders=cache
  if float(actor.blockers)>0.0 and int(actor.blocker_hits)>0:
   for i: int in range(3):
    var key: String="blocker_%d" % i
    var blocker: Dictionary=actor.get(key,{})
    if blocker.is_empty():
     blocker={"actor":actor,"drone":{},"part_index":-1,"query":-1,"radius":7.0,"blocker":true}
     actor[key]=blocker
    blocker.pos=Vector2(actor.pos)+Vector2.from_angle(world.elapsed*2.0+TAU*i/3.0)*60.0
    insert(blocker)
 for drone: Dictionary in world.drones:
  var c: Dictionary=drone.get("collider",{})
  if c.is_empty():
   c={"actor":{},"drone":drone,"part_index":-1,"query":-1,"radius":9.0}
   drone.collider=c
  c.pos=drone.pos
  insert(c)
## Cell keys are plain ints, not Vector2i: with per-circle colliders (P4a) this grid is populated
## and probed several times more often per tick than the per-gun version, and hashing an int is
## measurably cheaper than hashing a Vector2i. CELL_BIAS keeps the index positive for the small
## negative coordinates a bullet reaches just outside the rim; CELL_STRIDE is comfortably wider than
## the arena in cells, so two different cells can never collide onto one key.
const CELL_BIAS: int = 64
const CELL_STRIDE: int = 256

static func cell_key(x: int, y: int) -> int:
 return (y+CELL_BIAS)*CELL_STRIDE+(x+CELL_BIAS)

func insert(c: Dictionary) -> void:
 colliders.append(c)
 var radius: float=float(c.radius)
 var p: Vector2=c.pos
 var lo_x: int=floori((p.x-radius)/CELL_SIZE)
 var lo_y: int=floori((p.y-radius)/CELL_SIZE)
 var hi_x: int=floori((p.x+radius)/CELL_SIZE)
 var hi_y: int=floori((p.y+radius)/CELL_SIZE)
 # Almost every circle is small enough to land in one cell; take that path without a range loop
 # and with a single dictionary probe instead of has()+[] (two lookups).
 if lo_x==hi_x and lo_y==hi_y:
  var key: int=cell_key(lo_x,lo_y)
  var cell: Variant=grid.get(key)
  if cell==null: grid[key]=[c]
  else: cell.append(c)
  return
 for y: int in range(lo_y,hi_y+1):
  for x: int in range(lo_x,hi_x+1):
   var key: int=cell_key(x,y)
   var cell: Variant=grid.get(key)
   if cell==null: grid[key]=[c]
   else: cell.append(c)
func query_segment(from: Vector2, to: Vector2, radius: float) -> Array:
 var lo_x: int=floori((minf(from.x,to.x)-radius)/CELL_SIZE)
 var lo_y: int=floori((minf(from.y,to.y)-radius)/CELL_SIZE)
 var hi_x: int=floori((maxf(from.x,to.x)+radius)/CELL_SIZE)
 var hi_y: int=floori((maxf(from.y,to.y)+radius)/CELL_SIZE)
 if lo_x==hi_x and lo_y==hi_y: return grid.get(cell_key(lo_x,lo_y),empty_colliders)
 query_results.clear()
 query_serial+=1
 for y: int in range(lo_y,hi_y+1):
  for x: int in range(lo_x,hi_x+1):
   for c: Dictionary in grid.get(cell_key(x,y),empty_colliders):
    if int(c.query)!=query_serial:
     c.query=query_serial
     query_results.append(c)
 return query_results
