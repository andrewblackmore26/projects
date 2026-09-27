class_name CircularArena
extends RefCounted
## Circular boundary shared by movement, shots, rendering and exits.
## Replaces RoundedArena (spec v3 §11): a node is a circle, not a rounded rectangle.
const OPENING_HALF_WIDTH: float = 64.0
const ANCHOR_INSET: float = 26.0
const ENTRY_INSET: float = 44.0
var center: Vector2 = GameTuning.ARENA_CENTER
var radius: float = GameTuning.ARENA_RADIUS
var membrane_half_angle: float = asin(clampf(OPENING_HALF_WIDTH/GameTuning.ARENA_RADIUS,-1.0,1.0))
var exits: Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
## Modernization M1 seam for M3 (whole-rim exits): a node whose exits are closed. Nothing reads it yet.
var sealed: bool = false
var bounds: Rect2:
 get: return Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
 set(value): center=value.get_center(); radius=value.size.x*0.5

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
 return Vector2(direction).angle()

## The one writer of `exits` from a sector descriptor. Takes Vector2i entries or [x, y] pairs (the
## JSON form a snapshot restores); anything else is skipped. Refills the same array in place.
func set_exits(dirs: Array) -> void:
 exits.clear()
 for direction: Variant in dirs:
  if direction is Vector2i: exits.append(direction)
  elif direction is Array and direction.size()==2: exits.append(Vector2i(int(direction[0]),int(direction[1])))

func membrane_at(point: Vector2) -> Vector2i:
 var angle: float=(point-center).angle()
 for d: Vector2i in exits:
  if absf(wrapf(angle-direction_angle(d),-PI,PI))<=membrane_half_angle: return d
 return Vector2i.ZERO

func membrane_anchor(direction: Vector2i) -> Vector2:
 return center+Vector2(direction).normalized()*(radius-ANCHOR_INSET)

func exit_direction(point: Vector2) -> Vector2i:
 if point.distance_to(center)<=radius: return Vector2i.ZERO
 return membrane_at(point)

func entry_position(travel_direction: Vector2i) -> Vector2:
 var away: Vector2=Vector2(travel_direction)
 if away.length_squared()<0.001: return center
 return center-away.normalized()*(radius-ENTRY_INSET)

func outline(steps: int = 64) -> PackedVector2Array:
 var result: PackedVector2Array=[]
 for i: int in range(steps+1): result.append(center+Vector2.from_angle(TAU*i/steps)*radius)
 return result

func in_opening(point: Vector2) -> bool:
 if point.distance_to(center)<radius-40.0: return false
 return membrane_at(point)!=Vector2i.ZERO
