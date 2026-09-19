class_name LightBulletPool
extends RefCounted

## Dense active indices over a reusable struct-of-arrays pool. No projectile Nodes.
const CAPACITY: int = 8192
const NORMAL: int = 0
const MINE: int = 1
const BLACK_HOLE: int = 2
const PIERCING: int = 4
const RETURNED: int = 8
const RICOCHET: int = 16
const HOMING: int = 32
const WANDER: int = 64
const CHAIN: int = 128
const ROCKET: int = 256
const ORBIT: int = 512
const INFECT: int = 1024

var positions: PackedVector2Array = PackedVector2Array()
var previous: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var lives: PackedFloat32Array = PackedFloat32Array()
var ages: PackedFloat32Array = PackedFloat32Array()
var damages: PackedFloat32Array = PackedFloat32Array()
var radii: PackedFloat32Array = PackedFloat32Array()
var owners: PackedInt32Array = PackedInt32Array()
var factions: PackedInt32Array = PackedInt32Array()
var elements: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var active_indices: Array[int] = []
var free_indices: Array[int] = []
var next_unused: int = 0
var rejected: int = 0

func _init() -> void:
	positions.resize(CAPACITY)
	previous.resize(CAPACITY)
	velocities.resize(CAPACITY)
	lives.resize(CAPACITY)
	ages.resize(CAPACITY)
	damages.resize(CAPACITY)
	radii.resize(CAPACITY)
	owners.resize(CAPACITY)
	factions.resize(CAPACITY)
	elements.resize(CAPACITY)
	flags.resize(CAPACITY)

func add(pos: Vector2, velocity: Vector2, life: float, damage: float, radius: float, owner: int, faction: int, element: int, special: int = NORMAL) -> int:
	var index: int = -1
	if not free_indices.is_empty():
		index = free_indices.pop_back()
	elif next_unused < CAPACITY:
		index = next_unused
		next_unused += 1
	else:
		rejected += 1
		return -1
	positions[index] = pos
	previous[index] = pos
	velocities[index] = velocity
	lives[index] = life
	ages[index] = 0.0
	damages[index] = damage
	radii[index] = radius
	owners[index] = owner
	factions[index] = faction
	elements[index] = element
	flags[index] = special
	active_indices.append(index)
	return index

func remove_at(active_position: int) -> void:
	var index: int = active_indices[active_position]
	free_indices.append(index)
	lives[index] = 0.0
	var last: int = active_indices.size() - 1
	if active_position != last:
		active_indices[active_position] = active_indices[last]
	active_indices.pop_back()

func clear() -> void:
	active_indices.clear()
	free_indices.clear()
	next_unused = 0
	rejected = 0

func count() -> int:
	return active_indices.size()

static func segment_circle_t(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> float:
	## Earliest hit parameter, or -1. Handles tunnelling and stationary projectiles.
	var relative: Vector2 = start - center
	var direction: Vector2 = finish - start
	var squared_radius: float = radius * radius
	if relative.length_squared() <= squared_radius:
		return 0.0
	var a: float = direction.length_squared()
	if a <= 0.000001:
		return -1.0
	var b: float = 2.0 * relative.dot(direction)
	var c: float = relative.length_squared() - squared_radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0

func to_array() -> Array:
	var result: Array = []
	for index: int in active_indices:
		result.append({"p": [positions[index].x, positions[index].y], "v": [velocities[index].x, velocities[index].y], "life": lives[index], "age": ages[index], "damage": damages[index], "radius": radii[index], "owner": owners[index], "faction": factions[index], "element": elements[index], "flags": flags[index]})
	return result

func from_array(data: Array) -> void:
	clear()
	for entry: Variant in data.slice(0, CAPACITY):
		if not entry is Dictionary:
			continue
		var item: Dictionary = entry
		var p: Array = item.get("p", [0.0, 0.0])
		var v: Array = item.get("v", [0.0, 0.0])
		if p.size() != 2 or v.size() != 2:
			continue
		var restored: int = add(Vector2(float(p[0]), float(p[1])), Vector2(float(v[0]), float(v[1])), clampf(float(item.get("life", -1.0)), -1.0, 30.0), clampf(float(item.get("damage", 0.0)), 0.0, 500.0), clampf(float(item.get("radius", 2.0)), 0.5, 30.0), int(item.get("owner", -1)), int(item.get("faction", 1)), int(item.get("element", 0)), int(item.get("flags", 0)))
		if restored >= 0: ages[restored] = maxf(0.0, float(item.get("age", 0.0)))

