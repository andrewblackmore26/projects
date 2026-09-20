class_name CombatFX
extends RefCounted
## Pooled, batched impact/attack effects (spec v0.3 §19). Struct-of-arrays, no
## per-frame allocation once warmed (`CAPACITY` slots reused via a free list,
## the same shape as `bullet_pool.gd`/`trail_pool.gd`). `emit()` is the ONE
## choke point that creates an effect: every visible event in the game goes
## through a named entry in `TEMPLATES`, and `validate_templates()` is the
## single place §16's "any hit, absorb or short event is drawn for at least
## 0.25 s" is enforced - called once at world startup (`combat_world.gd`
## `_ready`), which pushes a loud engine error (caught by every test runner's
## log grep, tasks/lessons.md "a shader that fails to compile renders black"
## sibling rule: a template that is too short must not pass quietly either)
## if any template's total `duration` sits below `MIN_VISIBLE_LIFETIME`. A
## short BEAT inside a longer templated event is fine (the 0.15 s muzzle ring
## is one beat of the "muzzle" template, whose own duration IS 0.15 - it is
## not a "hit, absorb or short event" on its own, it is the emitter snap; the
## events the spec actually names - hits, absorbs, destructions - all carry
## >= 0.25 s templates below).
##
## Two draw passes, because collars must sit UNDER the ship renderers
## (z_index 10) while rings/fragments/lines sit above everything (spec §19
## "darken a collar... below the playfield value"): `draw_below()` is called
## from `CombatWorld._draw()` (z_index 0, under ships), `draw_above()` from
## `draw_projectiles()` (the bullet canvas, z_index 40, above ships).

const CAPACITY: int = 512
const MIN_VISIBLE_LIFETIME: float = 0.25

enum Kind { RING, DISC, LINE, FRAGMENTS, COLLAR, TEXT }

## Every template's `duration` is the total time the LONGEST beat in it stays
## on screen (delay + life). Beats: `kind`, `delay` (s, before the beat starts
## animating), `life` (s), `r0`/`r1` (px, RING/COLLAR/fragment spawn), `a0`/`a1`
## (alpha), `width` (LINE), `count_min`/`count_max`/`speed_min`/`speed_max`/
## `drag` (FRAGMENTS, spec Appendix B: 5-7 fragments, 1.4-3.6 px/frame, drag
## 0.95), `dark` (COLLAR only - multiplies the playfield instead of adding).
const TEMPLATES: Dictionary = {
 # Beat 1 of the spec's three-beat shot (§19.1): "a ring at the emitter
 # snapping outward and fading over ~0.15 s" (Appendix B: 10 -> 23 px).
 # `floor_exempt`: this is explicitly "one beat of a longer shot event" (the
 # spec's own wording) - the emitter-side flash, not the target-side
 # hit/absorb/short EVENT §16's 0.25 s floor is about. Muzzle and impact
 # happen at different times and (usually) different positions - a bullet
 # that never lands never gets an impact at all - so they cannot be one
 # literal delayed emit() the way "destruction"'s collapse-then-burst is.
 # `validate_templates()` skips exempted templates; the negative control
 # test sabotages an ordinary (non-exempt) template to prove the floor
 # still holds everywhere it is supposed to.
 "muzzle": {"duration":0.15,"floor_exempt":true,"beats":[
  {"kind":Kind.RING,"delay":0.0,"life":0.15,"r0":10.0,"r1":23.0,"a0":1.0,"a1":0.0},
 ]},
 # Beat 3: two rings at different speeds plus 5-7 decelerating fragments
 # (Appendix B exact numbers).
 "impact": {"duration":0.55,"beats":[
  {"kind":Kind.RING,"delay":0.0,"life":0.30,"r0":4.0,"r1":30.0,"a0":1.0,"a1":0.0},
  {"kind":Kind.RING,"delay":0.0,"life":0.30,"r0":4.0,"r1":48.0,"a0":0.5,"a1":0.0},
  {"kind":Kind.FRAGMENTS,"delay":0.0,"life":0.55,"count_min":5,"count_max":7,"speed_min":1.4,"speed_max":3.6,"drag":0.95},
 ]},
 # A large hit additionally darkens a collar (§19 "on large hits"); its own
 # template so `_damage_actor`/`_damage_part` can emit it independently of
 # the impact rings (a graze can flare without collaring).
 "collar": {"duration":0.35,"beats":[
  {"kind":Kind.COLLAR,"delay":0.0,"life":0.35,"r0":0.0,"r1":26.0,"a0":0.55,"a1":0.0},
 ]},
 # Destruction (§19): "collapses inward for 0.1 s, then bursts into fragment
 # circles". The collapse is a shrinking disc; the burst is delayed exactly
 # past it.
 "destruction": {"duration":0.65,"beats":[
  {"kind":Kind.DISC,"delay":0.0,"life":0.1,"r0":18.0,"r1":1.0,"a0":0.9,"a1":0.5},
  {"kind":Kind.FRAGMENTS,"delay":0.1,"life":0.55,"count_min":6,"count_max":7,"speed_min":2.0,"speed_max":4.2,"drag":0.94},
 ]},
 # "Its lines snap from both ends" - two segments collapsing toward their
 # own midpoints from each end simultaneously.
 "line_snap": {"duration":0.25,"beats":[
  {"kind":Kind.LINE,"delay":0.0,"life":0.25,"width":2.0,"a0":0.9,"a1":0.0},
 ]},
 # "Absorbing a pickup pulls a short line from the pickup into the core."
 "absorb": {"duration":0.25,"beats":[
  {"kind":Kind.LINE,"delay":0.0,"life":0.25,"width":2.2,"a0":1.0,"a1":0.0},
 ]},
 # Chain-bolt arc between two hostiles (distinct call site from
 # "line_snap"/destruction, same visual shape: a bright momentary connector).
 "chain_line": {"duration":0.25,"beats":[
  {"kind":Kind.LINE,"delay":0.0,"life":0.25,"width":2.0,"a0":0.9,"a1":0.0},
 ]},
 # "Dash emits a compression ring" (the trail's own kink is drawn by
 # `trail_pool.gd`/`trail_canvas.gd`, not here).
 "dash_ring": {"duration":0.25,"beats":[
  {"kind":Kind.RING,"delay":0.0,"life":0.25,"r0":8.0,"r1":26.0,"a0":0.9,"a1":0.0},
 ]},
 # Ricochet: "fragments thrown on each bounce."
 "ricochet_kink": {"duration":0.4,"beats":[
  {"kind":Kind.FRAGMENTS,"delay":0.0,"life":0.4,"count_min":3,"count_max":4,"speed_min":1.0,"speed_max":2.4,"drag":0.93},
 ]},
 # Beam: "impact sparking continuously at the far end" - one small burst per
 # call, thrown by the caller at a throttled rate (see `_beam` in
 # `combat_world.gd`), not a delay chain of its own.
 "beam_spark": {"duration":0.25,"beats":[
  {"kind":Kind.RING,"delay":0.0,"life":0.25,"r0":3.0,"r1":11.0,"a0":1.0,"a1":0.0},
  {"kind":Kind.FRAGMENTS,"delay":0.0,"life":0.25,"count_min":3,"count_max":3,"speed_min":0.8,"speed_max":1.6,"drag":0.9},
 ]},
 # Migrated from the old one-`draw_arc` effect list (unchanged visual role,
 # now on the same choke point and all at/above the 0.25 s floor).
 "wall_flash": {"duration":0.25,"beats":[{"kind":Kind.RING,"delay":0.0,"life":0.25,"r0":18.0,"r1":18.0,"a0":0.9,"a1":0.0}]},
 "explosion": {"duration":0.35,"beats":[
  {"kind":Kind.RING,"delay":0.0,"life":0.30,"r0":4.0,"r1":48.0,"a0":1.0,"a1":0.0},
  {"kind":Kind.FRAGMENTS,"delay":0.0,"life":0.35,"count_min":5,"count_max":6,"speed_min":1.6,"speed_max":3.0,"drag":0.93},
 ]},
 "spawn_telegraph": {"duration":0.5,"beats":[{"kind":Kind.RING,"delay":0.0,"life":0.5,"r0":10.0,"r1":40.0,"a0":0.8,"a1":0.0}]},
 "damage_number": {"duration":0.6,"beats":[{"kind":Kind.TEXT,"delay":0.0,"life":0.6}]},
}

var kind: PackedInt32Array = PackedInt32Array()
var pos: PackedVector2Array = PackedVector2Array()
var to: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()
var color: Array[Color] = []
var r0: PackedFloat32Array = PackedFloat32Array()
var r1: PackedFloat32Array = PackedFloat32Array()
var a0: PackedFloat32Array = PackedFloat32Array()
var a1: PackedFloat32Array = PackedFloat32Array()
var width: PackedFloat32Array = PackedFloat32Array()
var drag: PackedFloat32Array = PackedFloat32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var delay: PackedFloat32Array = PackedFloat32Array()
var age: PackedFloat32Array = PackedFloat32Array()
var text: Array[String] = []
var active_indices: Array[int] = []
var free_indices: Array[int] = []
var next_unused: int = 0
var dropped_count: int = 0
## Test-only kill switch: sim state must be identical whether FX draws or
## not (tasks/lessons.md "FX and trails must use their own RNG and never
## perturb the sim"). Gameplay code never touches this.
var enabled: bool = true

func _init() -> void:
 kind.resize(CAPACITY)
 pos.resize(CAPACITY)
 to.resize(CAPACITY)
 vel.resize(CAPACITY)
 color.resize(CAPACITY)
 r0.resize(CAPACITY)
 r1.resize(CAPACITY)
 a0.resize(CAPACITY)
 a1.resize(CAPACITY)
 width.resize(CAPACITY)
 drag.resize(CAPACITY)
 life.resize(CAPACITY)
 delay.resize(CAPACITY)
 age.resize(CAPACITY)
 text.resize(CAPACITY)
 for i: int in range(CAPACITY): color[i]=Color.WHITE

## Startup choke point (spec item 2). Returns an empty array when every
## template's `duration` clears `MIN_VISIBLE_LIFETIME`; otherwise one message
## per offending template. Takes an explicit table so a test can validate a
## deliberately-sabotaged copy without touching the real `TEMPLATES` constant.
static func validate_templates(table: Dictionary = TEMPLATES) -> Array[String]:
 var errors: Array[String] = []
 for template_name: String in table:
  if bool(table[template_name].get("floor_exempt",false)): continue
  var duration: float = float(table[template_name].get("duration",0.0))
  if duration < MIN_VISIBLE_LIFETIME - 0.0001:
   errors.append("CombatFX template '%s' duration %.3fs is below the %.2fs minimum visible lifetime (spec §16)" % [template_name,duration,MIN_VISIBLE_LIFETIME])
 return errors

## The single choke point (spec item 2/3): every visible attack/impact event
## in the game is created here, from a named `TEMPLATES` entry. `rng` is the
## caller's OWN RandomNumberGenerator (fragments need a spread), never the
## sim's `_rng` - FX must not perturb sim state (tasks/lessons.md "FX and
## trails must use their own RNG and never perturb the sim").
func emit(template_name: String, at: Vector2, tint: Color, rng: RandomNumberGenerator, extra: Dictionary = {}) -> void:
 if not enabled: return
 var template: Dictionary = TEMPLATES.get(template_name,{})
 if template.is_empty():
  push_error("CombatFX.emit: unknown template '%s'" % template_name)
  return
 for beat: Dictionary in template.get("beats",[]):
  match int(beat.get("kind",Kind.RING)):
   Kind.FRAGMENTS: _spawn_fragments(beat,at,tint,rng,extra)
   Kind.LINE: _spawn_one(Kind.LINE,at,Vector2(extra.get("to",at)),tint,beat,extra)
   Kind.COLLAR: _spawn_one(Kind.COLLAR,at,at,tint,beat,extra)
   Kind.TEXT: _spawn_text(at,tint,beat,str(extra.get("text","")))
   _: _spawn_one(int(beat.get("kind",Kind.RING)),at,at,tint,beat,extra)

func _slot() -> int:
 if not free_indices.is_empty(): return free_indices.pop_back()
 if next_unused<CAPACITY:
  var index: int=next_unused
  next_unused+=1
  return index
 dropped_count+=1
 return -1

## `extra.r0`/`extra.r1` (e.g. a destroyed circle's own authored radius, or a
## collar's actual hit-radius) override the template's default numbers for
## this one call; the template still supplies the shape (RING/DISC/COLLAR)
## and timing.
func _spawn_one(beat_kind: int, at: Vector2, target: Vector2, tint: Color, beat: Dictionary, extra: Dictionary = {}) -> void:
 var index: int=_slot()
 if index<0: return
 kind[index]=beat_kind
 pos[index]=at
 to[index]=target
 vel[index]=Vector2.ZERO
 color[index]=tint
 r0[index]=float(extra.get("r0",beat.get("r0",0.0)))
 r1[index]=float(extra.get("r1",beat.get("r1",0.0)))
 a0[index]=float(beat.get("a0",1.0))
 a1[index]=float(beat.get("a1",0.0))
 width[index]=float(beat.get("width",2.0))
 drag[index]=1.0
 life[index]=float(beat.get("life",0.25))
 delay[index]=float(beat.get("delay",0.0))
 age[index]=0.0
 active_indices.append(index)

func _spawn_text(at: Vector2, tint: Color, beat: Dictionary, message: String) -> void:
 var index: int=_slot()
 if index<0: return
 kind[index]=Kind.TEXT
 pos[index]=at
 color[index]=tint
 life[index]=float(beat.get("life",0.6))
 delay[index]=0.0
 age[index]=0.0
 text[index]=message
 active_indices.append(index)

## Fragments thrown "along the incoming vector" (§19): `extra.direction`
## (default: random) sets the cone's centre; each fragment samples its own
## angle/speed from the caller's RNG so 512 slots never look identical.
func _spawn_fragments(beat: Dictionary, at: Vector2, tint: Color, rng: RandomNumberGenerator, extra: Dictionary) -> void:
 var direction: Vector2 = Vector2(extra.get("direction",Vector2.RIGHT))
 if direction.length_squared()<0.0001: direction=Vector2.RIGHT
 var base_angle: float = direction.angle()
 var count: int = rng.randi_range(int(beat.get("count_min",5)),int(beat.get("count_max",7)))
 for i: int in range(count):
  var index: int=_slot()
  if index<0: return
  var spread: float = rng.randf_range(-0.9,0.9)
  var speed_frames: float = rng.randf_range(float(beat.get("speed_min",1.4)),float(beat.get("speed_max",3.6)))
  kind[index]=Kind.FRAGMENTS
  pos[index]=at
  to[index]=at
  vel[index]=Vector2.from_angle(base_angle+spread)*speed_frames*60.0
  color[index]=tint
  r0[index]=rng.randf_range(1.5,3.0)
  r1[index]=r0[index]
  a0[index]=1.0
  a1[index]=0.0
  width[index]=0.0
  drag[index]=float(beat.get("drag",0.95))
  life[index]=float(beat.get("life",0.55))
  delay[index]=float(beat.get("delay",0.0))
  age[index]=0.0
  active_indices.append(index)

func update(dt: float) -> void:
 for slot: int in range(active_indices.size()-1,-1,-1):
  var index: int=active_indices[slot]
  age[index]+=dt
  var local_t: float=age[index]-delay[index]
  if local_t<0.0: continue
  if local_t>=life[index]:
   _remove(slot,index)
   continue
  if kind[index]==Kind.FRAGMENTS:
   pos[index]=pos[index]+vel[index]*dt
   var decay: float=pow(clampf(drag[index],0.0,1.0),dt*60.0)
   vel[index]=vel[index]*decay

func _remove(slot: int, index: int) -> void:
 free_indices.append(index)
 var last: int=active_indices.size()-1
 if slot!=last: active_indices[slot]=active_indices[last]
 active_indices.pop_back()

func clear() -> void:
 active_indices.clear()
 free_indices.clear()
 next_unused=0
 dropped_count=0

func live_count() -> int: return active_indices.size()

## Below-ship pass: the dark collar only (spec §19 "darken a collar ... below
## the playfield value"). Drawn from `CombatWorld._draw()` (z_index 0).
func draw_below(canvas: CanvasItem) -> void:
 for index: int in active_indices:
  if kind[index]!=Kind.COLLAR: continue
  var local_t: float=age[index]-delay[index]
  if local_t<0.0: continue
  var t: float=clampf(local_t/maxf(0.001,life[index]),0.0,1.0)
  var radius: float=lerpf(r0[index],r1[index],t)
  var alpha: float=lerpf(a0[index],a1[index],t)
  if radius<=0.0 or alpha<=0.0: continue
  canvas.draw_circle(pos[index],radius,Color(0,0,0,alpha))

## Above-ship pass: rings, discs, lines, fragments, text. Drawn from
## `draw_projectiles()` (the bullet canvas, z_index 40).
func draw_above(canvas: CanvasItem, font: Font) -> void:
 for index: int in active_indices:
  var beat_kind: int=kind[index]
  if beat_kind==Kind.COLLAR: continue
  var local_t: float=age[index]-delay[index]
  if local_t<0.0: continue
  var t: float=clampf(local_t/maxf(0.001,life[index]),0.0,1.0)
  var alpha: float=lerpf(a0[index],a1[index],t)
  if alpha<=0.0 and beat_kind!=Kind.TEXT: continue
  var tint: Color=color[index]
  tint.a=alpha
  match beat_kind:
   Kind.RING:
    var radius: float=lerpf(r0[index],r1[index],t)
    if radius>0.5: canvas.draw_arc(pos[index],radius,0,TAU,24,tint*1.6,1.5,true)
   Kind.DISC:
    var radius: float=lerpf(r0[index],r1[index],t)
    if radius>0.3: canvas.draw_circle(pos[index],radius,tint)
   Kind.LINE:
    # Shrinks from both ends toward the midpoint (destruction's "snap") or
    # pulls the pickup toward the target (absorb) - both read the same way:
    # the SEGMENT itself shortens over its life.
    var mid: Vector2=pos[index].lerp(to[index],0.5)
    var segment_t: float=1.0-t
    canvas.draw_line(pos[index].lerp(mid,1.0-segment_t),to[index].lerp(mid,1.0-segment_t),tint*1.6,width[index],true)
   Kind.FRAGMENTS:
    canvas.draw_circle(pos[index],maxf(0.6,r0[index]*(1.0-t*0.3)),tint)
   Kind.TEXT:
    var rise: Vector2=Vector2(0,-16.0*t)
    canvas.draw_string(font,pos[index]+rise,text[index],HORIZONTAL_ALIGNMENT_CENTER,-1,13,tint)

## Real per-frame draw path (P9 perf pass, tasks/todo.md): rings, discs,
## fragments and the collar are batched by `fx_canvas.gd`'s MultiMesh
## (`CombatWorld._fx_canvas`, synced once per tick from `_physics_process`) -
## `draw_above`/`draw_below` above are kept ONLY for
## `tests/combat_fx_render_test.gd`, which builds a bare FX+canvas fixture
## with no `CombatWorld` and exercises those immediate shapes directly; the
## real game never calls them anymore. Lines and the (off-by-default)
## damage-number text are few per frame and stay immediate here, called from
## `CombatWorld.draw_projectiles`.
func draw_lines_and_text(canvas: CanvasItem, font: Font) -> void:
 for index: int in active_indices:
  var beat_kind: int=kind[index]
  if beat_kind!=Kind.LINE and beat_kind!=Kind.TEXT: continue
  var local_t: float=age[index]-delay[index]
  if local_t<0.0: continue
  var t: float=clampf(local_t/maxf(0.001,life[index]),0.0,1.0)
  var alpha: float=lerpf(a0[index],a1[index],t)
  if alpha<=0.0 and beat_kind!=Kind.TEXT: continue
  var tint: Color=color[index]
  tint.a=alpha
  match beat_kind:
   Kind.LINE:
    var mid: Vector2=pos[index].lerp(to[index],0.5)
    var segment_t: float=1.0-t
    canvas.draw_line(pos[index].lerp(mid,1.0-segment_t),to[index].lerp(mid,1.0-segment_t),tint*1.6,width[index],true)
   Kind.TEXT:
    var rise: Vector2=Vector2(0,-16.0*t)
    canvas.draw_string(font,pos[index]+rise,text[index],HORIZONTAL_ALIGNMENT_CENTER,-1,13,tint)
