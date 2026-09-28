class_name CircularArena
extends RefCounted
## Circular boundary shared by movement, shots, rendering and exits.
## Replaces RoundedArena (spec v3 §11): a node is a circle, not a rounded rectangle.
const ANCHOR_INSET: float = 26.0
const ENTRY_INSET: float = 44.0
## Modernization M3: an arrival keeps its reflected offset only within this many radians of the
## bearing opposite its travel direction (a folded edge/corner arc can be far wider than 45 deg).
const ENTRY_CLAMP: float = PI*0.25
## Modernization M3: an arrival heading more than this far off the travel direction is rotated,
## minimally, back onto the cone's edge (cos 60 deg = 0.5).
const ENTRY_CONE: float = PI/3.0
var center: Vector2 = GameTuning.ARENA_CENTER
var radius: float = GameTuning.ARENA_RADIUS
## Every bearing this node's rim leads to (modernization M3: the whole rim is an exit; an interior
## node has all 8). Read live by `arc_of`, so a test that edits it directly is still honoured.
var exits: Array[Vector2i] = CampaignState.NEIGHBOURS.duplicate()
## `{dir, from, to, center}` per exit in ascending angle, split at the angular bisectors between
## neighbouring bearings (radians, `from` < `to`, possibly beyond PI). Rebuilt by `set_exits`;
## the renderers read it, the sim reads `arc_of`.
var arcs: Array[Dictionary] = []
## A node whose rim leads nowhere: `arc_of` returns ZERO everywhere. Never set in play (exits are
## never locked, not in waves nor at bosses); a seam for tests and the benchmark.
var sealed: bool = false
var bounds: Rect2:
 get: return Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
 set(value): center=value.get_center(); radius=value.size.x*0.5

func _init() -> void:
 _build_arcs()

func contains(point: Vector2, margin: float = 0.0) -> bool:
 var r: float=maxf(0.0,radius-margin)
 return point.distance_squared_to(center)<=r*r

func clamp_point(point: Vector2, margin: float = 0.0) -> Vector2:
 var r: float=maxf(0.0,radius-margin)
 var offset: Vector2=point-center
 if offset.length_squared()<=r*r: return point
 var direction: Vector2=offset.normalized() if offset.length_squared()>0.000001 else Vector2.RIGHT
 return center+direction*r

func boundary_hit(from: Vector2, to: Vector2, margin: float = 0.0) -> Dictionary:
 if contains(to,margin): return {}
 if not contains(from,margin):
  var p: Vector2=clamp_point(from,margin)
  return {"t":0.0,"point":p,"normal":normal_at(p,margin)}
 var r: float=maxf(0.0,radius-margin)
 var d: Vector2=to-from
 var f: Vector2=from-center
 var a: float=d.length_squared()
 if a<0.000001: return {}
 var b: float=2.0*f.dot(d)
 var c: float=f.length_squared()-r*r
 var disc: float=b*b-4.0*a*c
 if disc<0.0: return {}
 var sq: float=sqrt(disc)
 var t: float=clampf((-b+sq)/(2.0*a),0.0,1.0)
 var point: Vector2=from.lerp(to,t)
 return {"t":t,"point":point,"normal":normal_at(point,margin)}

func normal_at(point: Vector2, margin: float = 0.0) -> Vector2:
 var offset: Vector2=point-center
 return offset.normalized() if offset.length_squared()>0.000001 else Vector2.RIGHT

func direction_angle(direction: Vector2i) -> float:
 return CampaignState.bearing_angle(direction)

## The one writer of `exits` from a sector descriptor. Takes Vector2i entries or [x, y] pairs (the
## JSON form a snapshot restores); anything else is skipped. Refills the same array in place.
func set_exits(dirs: Array) -> void:
 exits.clear()
 for direction: Variant in dirs:
  if direction is Vector2i: exits.append(direction)
  elif direction is Array and direction.size()==2: exits.append(Vector2i(int(direction[0]),int(direction[1])))
 _build_arcs()

func _build_arcs() -> void:
 arcs.clear()
 var sorted: Array[Vector2i]=[]
 for d: Vector2i in exits:
  if d!=Vector2i.ZERO and d not in sorted: sorted.append(d)
 sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return fposmod(direction_angle(a),TAU)<fposmod(direction_angle(b),TAU))
 var n: int=sorted.size()
 for i: int in range(n):
  var here: float=fposmod(direction_angle(sorted[i]),TAU)
  var before: float=fposmod(direction_angle(sorted[(i-1+n)%n]),TAU)
  var after: float=fposmod(direction_angle(sorted[(i+1)%n]),TAU)
  if before>=here: before-=TAU
  if after<=here: after+=TAU
  var from: float=here-(here-before)*0.5 if n>1 else here-PI
  var to: float=here+(after-here)*0.5 if n>1 else here+PI
  arcs.append({"dir":sorted[i],"from":from,"to":to,"center":(from+to)*0.5})

## The bearing the rim at `angle` leads to: the nearest exit bearing, through the one choke point
## (`CampaignState.nearest_bearing`), so the arcs split exactly at the bisectors. ZERO only when
## `sealed` or when there are no exits at all.
func arc_of(angle: float) -> Vector2i:
 if sealed: return Vector2i.ZERO
 return CampaignState.nearest_bearing(exits,angle)

func arc_for(direction: Vector2i) -> Dictionary:
 for arc: Dictionary in arcs:
  if arc.dir==direction: return arc
 return {}

func membrane_anchor(direction: Vector2i) -> Vector2:
 return center+Vector2(direction).normalized()*(radius-ANCHOR_INSET)

## Zero-offset arrival for a travel `direction`: just inside the rim, opposite the bearing. The
## golden trace and the fixtures teleport with it; `entry_point` is the general case.
func entry_position(travel_direction: Vector2i) -> Vector2:
 var away: Vector2=Vector2(travel_direction)
 if away.length_squared()<0.001: return center
 return center-away.normalized()*(radius-ENTRY_INSET)

## Where a warp through `exit_point` in `travel_direction` arrives in the neighbour: the exit's
## offset reflected across the axis perpendicular to the travel direction (rel - 2(rel.d)d, so an
## exit at 45 deg + u enters at 225 deg - u), its angle clamped to ENTRY_CLAMP of the opposite
## bearing, inset ENTRY_INSET px. The reflection is its own inverse, so flying straight back out
## the way you came lands where you started.
func entry_point(travel_direction: Vector2i, exit_point: Vector2) -> Vector2:
 var d: Vector2=Vector2(travel_direction)
 if d.length_squared()<0.001: return center
 d=d.normalized()
 var rel: Vector2=exit_point-center
 if rel.length_squared()<0.000001: return entry_position(travel_direction)
 var reflected: Vector2=rel-2.0*rel.dot(d)*d
 var opposite: float=(-d).angle()
 var off: float=clampf(angle_difference(opposite,reflected.angle()),-ENTRY_CLAMP,ENTRY_CLAMP)
 return center+Vector2.from_angle(opposite+off)*(radius-ENTRY_INSET)

## The arrival velocity for a warp in `travel_direction` carrying `velocity`: unchanged when it is
## within ENTRY_CONE of the travel direction, else rotated by the minimum angle that puts it on the
## cone's edge. Magnitude is always kept.
func entry_velocity(travel_direction: Vector2i, velocity: Vector2) -> Vector2:
 var d: Vector2=Vector2(travel_direction)
 if d.length_squared()<0.001 or velocity.length_squared()<0.000001: return velocity
 d=d.normalized()
 if velocity.dot(d)>=cos(ENTRY_CONE)*velocity.length(): return velocity
 var off: float=angle_difference(d.angle(),velocity.angle())
 return Vector2.from_angle(d.angle()+signf(off)*ENTRY_CONE)*velocity.length()

func outline(steps: int = 64) -> PackedVector2Array:
 var result: PackedVector2Array=[]
 for i: int in range(steps+1): result.append(center+Vector2.from_angle(TAU*i/steps)*radius)
 return result
