class_name HullGhost
extends CanvasGroup
## Modernization M19 (plan M12, "hovering a card ghosts the new hull over the player's ship"): a
## translucent silhouette of the focused evolution offer, drawn where the player's ship is, so the
## player sees what they would become at the size they would fly it. Render only: it reads the
## world's player position and aim each frame and writes nothing.
##
## It is the combat renderer (ShipRenderer, the same mesh and outline shader as the real ship) in a
## CanvasGroup, so ALPHA fades the whole hull as one image - the shader's own per-part alphas
## would otherwise stack where parts overlap. The hull's black occluding disc is off: the ship
## under the ghost stays visible. It sits in the compositor's foreground, under the bullets.

const ALPHA: float = 0.42
const FADE_SECONDS: float = 0.12
const Z_INDEX: int = 3

var renderer: ShipRenderer
var combat: CombatWorld
var hull_id: String = ""
var _fade: Tween

func _init() -> void:
	name = "HullGhost"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = Z_INDEX
	modulate.a = 0.0
	renderer = ShipRenderer.new()
	renderer.name = "GhostRenderer"
	renderer.draw_hull = false
	add_child(renderer)

## A ghost over `world`'s player, in `compositor`'s foreground. Null when there is no world to draw on.
static func attach(compositor: CombatCompositor, world: CombatWorld) -> HullGhost:
	if not is_instance_valid(compositor) or not is_instance_valid(world) or compositor.foreground == null: return null
	var ghost := HullGhost.new()
	ghost.combat = world
	compositor.add_world_overlay(ghost)
	ghost._follow()
	return ghost

## Shows `ship` (null: fades out). Switching hulls keeps the ghost up and swaps the mesh.
func show_hull(ship: ShipDefinition) -> void:
	if is_instance_valid(_fade): _fade.kill()
	_fade = UiMotion.tween(self)
	if ship == null:
		hull_id = ""
		_fade.tween_property(self, "modulate:a", 0.0, UiMotion.duration(FADE_SECONDS, true))
		return
	if ship.id != hull_id:
		hull_id = ship.id
		renderer.set_ship(ship)
	_fade.tween_property(self, "modulate:a", ALPHA, UiMotion.duration(FADE_SECONDS, true))

func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	if not is_instance_valid(combat) or combat.player.is_empty(): return
	position = combat.player_position
	rotation = Vector2(combat.player.get("aim", Vector2.UP)).angle() + PI / 2.0
