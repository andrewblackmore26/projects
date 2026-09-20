extends Node2D
## Batched MultiMesh draw for light pickups (spec v0.3 §10, §23).
##
## Diagnosis: `CombatWorld._draw()` ran `for pickup in pickups: _draw_pickup(pickup)`, and
## `_draw_pickup` issued two immediate `draw_arc` calls (24 and 8 segments) per pickup. The pool
## holds up to `MAX_PICKUPS = 400`, and in a sustained fight it saturates, so the frame paid for
## ~800 arcs. Measured: ~17 ms of frame time at 400 pickups against ~3 ms at 130, which made it the
## dominant remaining cost once the effects pool was batched (that was ~105 ms of a 133 ms frame).
## Same bug class, same fix: one draw call per pass instead of one per item.
##
## A pickup is a HOLLOW circle with a running light, and that shape rule is load-bearing (§10: "this
## holds everywhere, so a pickup is never mistaken for a bullet"), so the shader draws a rim plus a
## 13% lit arc rather than a disc. Void pickups also need an opaque black fill behind the rim
## (Appendix A gives void a black fill with a silver rim), which is the second pass.

const PickupShader = preload("res://scripts/combat/pickup_instances.gdshader")
const STRIDE: int=16 # 2D transform (8), instance color (4), custom data (4).
const INITIAL_CAPACITY: int=128

var rim_mesh: MultiMeshInstance2D
var fill_mesh: MultiMeshInstance2D
var rim_buffer: PackedFloat32Array=PackedFloat32Array()
var fill_buffer: PackedFloat32Array=PackedFloat32Array()
var rim_capacity: int=INITIAL_CAPACITY
var fill_capacity: int=INITIAL_CAPACITY
var rim_count: int=0
var fill_count: int=0
var upload_ms: float=0.0

func _ready() -> void:
 _ensure_meshes()

func _ensure_meshes() -> void:
 if is_instance_valid(rim_mesh): return
 # The black fill sits under the rim; both stay below the bullet canvas (z 40), because spec §16
 # orders enemy projectiles above player projectiles above pickups.
 fill_mesh=_make_pass("PickupFill",2)
 rim_mesh=_make_pass("PickupRim",3)
 rim_buffer.resize(rim_capacity*STRIDE)
 fill_buffer.resize(fill_capacity*STRIDE)

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
 # Fixed, generous AABB: a MultiMeshInstance2D caches its culling rect from the instances present
 # at its first draw, and in live play that frame is empty (tasks/lessons.md).
 batch.custom_aabb=AABB(Vector3(-400,-800,-1),Vector3(2600,2800,2))
 instance.multimesh=batch
 var material: ShaderMaterial=ShaderMaterial.new()
 material.shader=PickupShader
 instance.material=material
 add_child(instance)
 return instance

## Called from `CombatWorld._draw()` (the render step, NOT `_physics_process`): uploading from the
## physics tick would fold this cost into `simulation_ms` and regress the headless benchmark, which
## never renders at all.
func sync(world: Node) -> void:
 var began: int=Time.get_ticks_usec()
 _ensure_meshes()
 var pickups: Array=world.pickups
 var needed: int=pickups.size()
 if needed>rim_capacity:
  while needed>rim_capacity: rim_capacity*=2
  rim_buffer.resize(rim_capacity*STRIDE)
  rim_mesh.multimesh.instance_count=rim_capacity
  fill_capacity=rim_capacity
  fill_buffer.resize(fill_capacity*STRIDE)
  fill_mesh.multimesh.instance_count=fill_capacity
 rim_count=0
 fill_count=0
 var elapsed: float=world.elapsed
 for pickup: Dictionary in pickups:
  var color: Color=world.COLORS[maxi(0,world.ELEMENTS.find(str(pickup.element)))]
  # Radius reads SIZE, not the (possibly 3x-multiplied) value (spec §10).
  var size: int=int(pickup.get("size",pickup.value))
  var radius: float=3.0+(1.5 if size>=5 else 0.0)+(1.5 if size>=20 else 0.0)
  var light: Color=color.lerp(Color.WHITE,0.6)*1.8
  light.a=1.0
  # Where the 13% lit segment currently sits, as a fraction of the circumference.
  var phase: float=fposmod((elapsed*PI+float(pickup.phase))/TAU,1.0)
  if str(pickup.element)=="void":
   _write(fill_buffer,fill_count*STRIDE,pickup.pos,radius,Color.BLACK,0.0,0.0,0.0)
   fill_count+=1
  _write(rim_buffer,rim_count*STRIDE,pickup.pos,radius,color,1.0,phase,light.r*0.5+light.g*0.3+light.b*0.2)
  rim_count+=1
 if rim_count>0: rim_mesh.multimesh.buffer=rim_buffer
 if fill_count>0: fill_mesh.multimesh.buffer=fill_buffer
 rim_mesh.multimesh.visible_instance_count=rim_count
 fill_mesh.multimesh.visible_instance_count=fill_count
 upload_ms=float(Time.get_ticks_usec()-began)/1000.0

func _write(buffer: PackedFloat32Array, offset: int, pos: Vector2, radius: float, color: Color, mode: float, phase: float, glow: float) -> void:
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
 buffer[offset+13]=phase
 buffer[offset+14]=1.5/maxf(0.5,radius) # rim half-width in local units, a constant 1.5 px on screen
 buffer[offset+15]=glow

func clear_instances() -> void:
 rim_count=0
 fill_count=0
 if is_instance_valid(rim_mesh):
  rim_mesh.multimesh.visible_instance_count=0
  fill_mesh.multimesh.visible_instance_count=0
