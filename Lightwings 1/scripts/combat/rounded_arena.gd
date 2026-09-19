class_name RoundedArena
extends RefCounted
## Rounded rectangle boundary shared by movement, shots, rendering and exits.
var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(1792,1120))
var corner_radius: float = 160.0
var opening_half_width: float = 64.0
var exits: Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]

func contains(point: Vector2, margin: float = 0.0) -> bool:
 var half: Vector2=bounds.size*0.5-Vector2.ONE*margin
 var local: Vector2=(point-bounds.get_center()).abs()
 if local.x>half.x or local.y>half.y: return false
 var r: float=maxf(0.0,corner_radius-margin)
 if local.x<=half.x-r or local.y<=half.y-r: return true
 return (local-(half-Vector2.ONE*r)).length_squared()<=r*r

func clamp_point(point: Vector2, margin: float = 0.0) -> Vector2:
 if contains(point,margin): return point
 var center: Vector2 = bounds.get_center()
 var half: Vector2 = bounds.size * 0.5 - Vector2.ONE * margin
 var r: float = maxf(0.0,corner_radius-margin)
 var local: Vector2 = point-center
 var base: Vector2 = Vector2(clampf(local.x,-half.x+r,half.x-r),clampf(local.y,-half.y+r,half.y-r))
 var offset: Vector2 = local-base
 return center+base+offset.limit_length(r)

func boundary_hit(from: Vector2, to: Vector2, radius: float = 0.0) -> Dictionary:
 if contains(to,radius): return {}
 if not contains(from,radius):
  var p: Vector2 = clamp_point(from,radius)
  return {"t":0.0,"point":p,"normal":normal_at(p,radius)}
 var lo: float = 0.0
 var hi: float = 1.0
 for i: int in range(20):
  var mid: float = (lo+hi)*0.5
  if contains(from.lerp(to,mid),radius): lo=mid
  else: hi=mid
 var p: Vector2 = from.lerp(to,lo)
 return {"t":lo,"point":p,"normal":normal_at(p,radius)}

func normal_at(point: Vector2, margin: float = 0.0) -> Vector2:
 var local: Vector2 = point-bounds.get_center()
 var half: Vector2 = bounds.size*0.5-Vector2.ONE*margin
 var r: float = maxf(0.0,corner_radius-margin)
 var base: Vector2 = Vector2(clampf(local.x,-half.x+r,half.x-r),clampf(local.y,-half.y+r,half.y-r))
 var n: Vector2 = local-base
 return n.normalized() if n.length_squared()>0.001 else Vector2.RIGHT

func exit_direction(point: Vector2) -> Vector2i:
 var c: Vector2 = bounds.get_center()
 for d: Vector2i in exits:
  if d.x != 0 and absf(point.y-c.y)<=opening_half_width:
   if (d.x<0 and point.x<bounds.position.x) or (d.x>0 and point.x>bounds.end.x): return d
  if d.y != 0 and absf(point.x-c.x)<=opening_half_width:
   if (d.y<0 and point.y<bounds.position.y) or (d.y>0 and point.y>bounds.end.y): return d
 return Vector2i.ZERO

func entry_position(travel_direction: Vector2i) -> Vector2:
 var p: Vector2 = bounds.get_center()
 if travel_direction.x<0: p.x=bounds.end.x-44.0
 if travel_direction.x>0: p.x=bounds.position.x+44.0
 if travel_direction.y<0: p.y=bounds.end.y-44.0
 if travel_direction.y>0: p.y=bounds.position.y+44.0
 return p

func outline(steps: int = 12) -> PackedVector2Array:
 var result: PackedVector2Array = []
 for corner: int in range(4):
  var angle: float = PI*0.5*corner
  var center: Vector2 = bounds.get_center()+Vector2(1 if corner in [0,3] else -1,1 if corner in [0,1] else -1)*(bounds.size*0.5-Vector2.ONE*corner_radius)
  for i: int in range(steps+1): result.append(center+Vector2.from_angle(angle+PI*0.5*i/steps)*corner_radius)
 result.append(result[0])
 return result

func in_opening(point: Vector2) -> bool:
 var c: Vector2=bounds.get_center()
 for d: Vector2i in exits:
  if d.x!=0 and absf(point.y-c.y)<=opening_half_width and (point.x-c.x)*d.x>=bounds.size.x*0.5-40.0: return true
  if d.y!=0 and absf(point.x-c.x)<=opening_half_width and (point.y-c.y)*d.y>=bounds.size.y*0.5-40.0: return true
 return false
