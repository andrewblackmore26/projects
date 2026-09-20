extends Node2D
## Batched MultiMesh draw for `CombatFX` (spec v0.3 §19/§23, P9 perf pass).
## Diagnosis (tasks/todo.md P9): `combat_fx.gd`'s old `draw_below`/`draw_above`
## issued one `canvas.draw_arc`/`draw_circle` PER live effect in immediate
## mode; at the pool's 512-slot capacity that is up to ~12,000 line segments
## every frame, measured at ~105ms of a 133ms frame with 2000 live bullets.
## This uploads the same per-instance data `combat_canvas.gd` already uploads
## for bullets (STRIDE floats: 2D transform, colour, custom) into two
## `MultiMeshInstance2D`s shaped by `fx_instances.gdshader`'s ring/disc SDF -
## one draw call per pass instead of one per effect.
##
## Two passes, same reason `combat_fx.gd`'s old two methods existed: the dark
## collar must sit UNDER the ship renderers (z_index 10, spec §19 "darken a
## collar... below the playfield value"); rings/discs/fragments sit above
## everything. Both are children of `CombatWorld` directly (not nested in
## `combat_canvas.gd`) so their z_index is plain and absolute: `below_mesh` at
## 1 (above the world's own z=0 immediate draws, still under ships at 10),
## `above_mesh` at 41 (above the bullet canvas at 40).
##
## `combat_fx.gd`'s own `draw_below`/`draw_above` are UNCHANGED and still used
## by `tests/combat_fx_render_test.gd`, which builds a bare FX+canvas fixture
## with no `CombatWorld` and exercises the immediate-mode ring/collar shapes
## directly - this canvas is only wired into the real per-frame path
## (`CombatWorld._physics_process` -> `FxCanvas.sync`), never called by those
## tests. Lines and the (off-by-default) damage-number text stay immediate,
## drawn by `combat_fx.gd`'s new `draw_lines_and_text` from
## `CombatWorld.draw_projectiles` - few per frame, not worth a third pass.

const FxShader = preload("res://scripts/combat/fx_instances.gdshader")
const STRIDE: int=16 # 2D transform (8), instance color (4), custom data (4).
const INITIAL_CAPACITY: int=128
const RING_WIDTH_PX: float=1.5 # Matches the old `canvas.draw_arc(...,1.5,true)` stroke width.

var above_mesh: MultiMeshInstance2D
var below_mesh: MultiMeshInstance2D
var above_buffer: PackedFloat32Array=PackedFloat32Array()
var below_buffer: PackedFloat32Array=PackedFloat32Array()
var above_capacity: int=INITIAL_CAPACITY
var below_capacity: int=INITIAL_CAPACITY
var above_count: int=0
var below_count: int=0
var upload_ms: float=0.0

func _ready() -> void:
 _ensure_meshes()

func _ensure_meshes() -> void:
 if is_instance_valid(above_mesh): return
 above_mesh=_make_pass("FxAbove",41)
 below_mesh=_make_pass("FxBelow",1)
 above_buffer.resize(above_capacity*STRIDE)
 below_buffer.resize(below_capacity*STRIDE)

func _make_pass(label: String, order: int) -> MultiMeshInstance2D:
 var instance: MultiMeshInstance2D=MultiMeshInstance2D.new()
 instance.name=label
 instance.z_index=order
 var geometry: QuadMesh=QuadMesh.new()
 geometry.size=Vector2(2,2)
 var batch: MultiMesh=MultiMesh.new()
 batch.transform_format=MultiMesh.TRANSFORM_2D
 batch.use_colors=true
 batch.use_custom_data=true
 batch.mesh=geometry
 batch.instance_count=INITIAL_CAPACITY
 batch.visible_instance_count=0
 # Fixed, generous AABB (tasks/lessons.md: a MultiMeshInstance2D caches its
 # culling rect from the instances present at its first draw, which in live
 # play is empty - same box `combat_canvas.gd` uses for bullets).
 batch.custom_aabb=AABB(Vector3(-400,-800,-1),Vector3(2600,2800,2))
 instance.multimesh=batch
 var material: ShaderMaterial=ShaderMaterial.new()
 material.shader=FxShader
 instance.material=material
 add_child(instance)
 return instance

## Called once per physics tick from `CombatWorld._physics_process`, mirroring
## `combat_canvas.gd.sync_pool`. `fx` is the world's own `CombatFX`; reading
## its SoA arrays here does not mutate them, so this cannot perturb the sim
## (tasks/lessons.md "FX and trails must use their own RNG and never perturb
## the sim" - this path does not even touch RNG, it only reads positions
## already computed by `fx.update`).
func sync(fx: CombatFX) -> void:
 var began: int=Time.get_ticks_usec()
 _ensure_meshes()
 var above_needed: int=0
 var below_needed: int=0
 for index: int in fx.active_indices:
  var k: int=fx.kind[index]
  if k==fx.Kind.COLLAR: below_needed+=1
  elif k==fx.Kind.RING or k==fx.Kind.DISC or k==fx.Kind.FRAGMENTS: above_needed+=1
 if above_needed>above_capacity:
  while above_needed>above_capacity: above_capacity*=2
  above_buffer.resize(above_capacity*STRIDE)
  above_mesh.multimesh.instance_count=above_capacity
 if below_needed>below_capacity:
  while below_needed>below_capacity: below_capacity*=2
  below_buffer.resize(below_capacity*STRIDE)
  below_mesh.multimesh.instance_count=below_capacity
 above_count=0
 below_count=0
 for index: int in fx.active_indices:
  var beat_kind: int=fx.kind[index]
  var local_t: float=fx.age[index]-fx.delay[index]
  if local_t<0.0: continue
  var t: float=clampf(local_t/maxf(0.001,fx.life[index]),0.0,1.0)
  var alpha: float=lerpf(fx.a0[index],fx.a1[index],t)
  if beat_kind==fx.Kind.COLLAR:
   var radius: float=lerpf(fx.r0[index],fx.r1[index],t)
   if radius<=0.0 or alpha<=0.0: continue
   _write(below_buffer,below_count*STRIDE,fx.pos[index],radius,Color(0,0,0,alpha),1.0,0.0)
   below_count+=1
   continue
  if alpha<=0.0: continue
  var tint: Color=fx.color[index]
  tint.a=alpha
  match beat_kind:
   fx.Kind.RING:
    var radius: float=lerpf(fx.r0[index],fx.r1[index],t)
    if radius<=0.5: continue
    var bright: Color=tint*1.6
    bright.a=alpha
    _write(above_buffer,above_count*STRIDE,fx.pos[index],radius,bright,0.0,(RING_WIDTH_PX*0.5)/radius)
    above_count+=1
   fx.Kind.DISC:
    var radius: float=lerpf(fx.r0[index],fx.r1[index],t)
    if radius<=0.3: continue
    _write(above_buffer,above_count*STRIDE,fx.pos[index],radius,tint,1.0,0.0)
    above_count+=1
   fx.Kind.FRAGMENTS:
    var radius: float=maxf(0.6,fx.r0[index]*(1.0-t*0.3))
    _write(above_buffer,above_count*STRIDE,fx.pos[index],radius,tint,1.0,0.0)
    above_count+=1
 if above_count>0: above_mesh.multimesh.buffer=above_buffer
 if below_count>0: below_mesh.multimesh.buffer=below_buffer
 above_mesh.multimesh.visible_instance_count=above_count
 below_mesh.multimesh.visible_instance_count=below_count
 upload_ms=float(Time.get_ticks_usec()-began)/1000.0

func _write(buffer: PackedFloat32Array, offset: int, pos: Vector2, radius: float, color: Color, mode: float, ring_width_local: float) -> void:
 buffer[offset]=radius
 buffer[offset+1]=0.0
 buffer[offset+2]=0.0
 buffer[offset+3]=pos.x
 buffer[offset+4]=0.0
 buffer[offset+5]=radius
 buffer[offset+6]=0.0
 buffer[offset+7]=pos.y
 buffer[offset+8]=color.r
 buffer[offset+9]=color.g
 buffer[offset+10]=color.b
 buffer[offset+11]=color.a
 buffer[offset+12]=mode
 buffer[offset+13]=ring_width_local
 buffer[offset+14]=0.0
 buffer[offset+15]=0.0

func clear_instances() -> void:
 above_count=0
 below_count=0
 if is_instance_valid(above_mesh):
  above_mesh.multimesh.visible_instance_count=0
  below_mesh.multimesh.visible_instance_count=0
