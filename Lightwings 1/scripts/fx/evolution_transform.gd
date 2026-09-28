class_name EvolutionTransform
extends Node
## Modernization M12: what the player sees after picking an evolution card, and when the ship dies.
## Render only - the sim has already swapped the hull (CombatWorld.evolve_hull) and granted the
## reshape invulnerability through `_grant_invulnerability`; nothing here reads or writes sim state.
##
## Over ASSEMBLY_SECONDS of REAL time (UiMotion tweens ignore the time scale and the pause):
## - the old hull bursts: the CombatFX destruction template in the player's tint, sized to the hull;
## - the new hull assembles core-out: ShipRenderer.assembly_t runs 0 -> 1 (ship_outline.gdshader);
## - a title card "LIGHTNING · T3 · STANDARD A" slams in (Exo 2), holds, and fades.
## The `evolve_pick` cue is the card's (EvolutionScreen); FeelDirector's `evolved` row plays the
## assembly cue, the flash and the rumble.

const ASSEMBLY_SECONDS: float = 0.6
## The title card: slams from SLAM_SCALE to 1 over SLAM_SECONDS, holds, fades over FADE_SECONDS.
const SLAM_SCALE: float = 1.18
const SLAM_SECONDS: float = 0.09
const CARD_HOLD_SECONDS: float = 1.1
const CARD_FADE_SECONDS: float = 0.35
## Where the card sits: this far down the UI rect, above the ship at the centre.
const CARD_HEIGHT_FRACTION: float = 0.24

var renderer: ShipRenderer
var card: Control
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Plays the transformation from hull `from` into the player's current hull. Returns the node (it
## frees itself when the card has faded), or null when there is no live world to draw it on.
static func begin(app: Node, from: ShipDefinition) -> EvolutionTransform:
	var combat: CombatWorld = app.get("combat") as CombatWorld
	if not is_instance_valid(combat) or combat.player.is_empty(): return null
	var result := EvolutionTransform.new()
	result.name = "EvolutionTransform"
	result.process_mode = Node.PROCESS_MODE_ALWAYS
	app.add_child(result)
	result._fx_rng.randomize()
	if from != null: burst(combat, from, Vector2(combat.player.pos), result._fx_rng)
	result._assemble(combat.player.get("renderer") as ShipRenderer)
	var to: ShipDefinition = combat.player.get("definition") as ShipDefinition
	var ui: Control = app.get("ui") as Control
	if to != null and ui != null: result._slam_card(ui, to)
	else: result._free_after(ASSEMBLY_SECONDS)
	return result

## The hull `definition` bursting at `at` in the player's tint: the destruction template (a collapse,
## then fragments), sized to the hull, plus an explosion ring. Shared with the death beat.
static func burst(combat: CombatWorld, definition: ShipDefinition, at: Vector2, rng: RandomNumberGenerator) -> void:
	if not is_instance_valid(combat) or combat.fx == null: return
	var radius: float = clampf(ShipPreview.animated_radius(definition) * 0.6, 14.0, 90.0)
	# The collapse is a small hot core (a hull-sized disc read as a flat blob); the ring and the
	# fragments carry the hull's size.
	combat.fx.emit("destruction", at, CombatWorld.PLAYER_COLOR, rng, {"r0": clampf(radius * 0.3, 8.0, 22.0), "r1": 2.0, "direction": Vector2.from_angle(rng.randf() * TAU)})
	combat.fx.emit("explosion", at, CombatWorld.PLAYER_COLOR, rng, {"r1": radius * 1.6, "direction": Vector2.from_angle(rng.randf() * TAU)})

## "LIGHTNING · T3 · STANDARD A": element, tier and family of `definition`.
static func title_for(definition: ShipDefinition) -> String:
	return "%s · T%d · %s" % [definition.element.to_upper(), definition.tier, definition.family.replace("_", " ").to_upper()]

func _assemble(target: ShipRenderer) -> void:
	renderer = target
	if not is_instance_valid(renderer): return
	renderer.assembly_t = 0.0
	UiMotion.tween(self).tween_method(func(t: float) -> void:
		if is_instance_valid(renderer): renderer.assembly_t = t, 0.0, 1.0, maxf(0.001, UiMotion.duration(ASSEMBLY_SECONDS))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _slam_card(ui: Control, definition: ShipDefinition) -> void:
	card = Control.new()
	card.name = "EvolutionTitle"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(card)
	var kicker: Label = UiKit.label(card, "EVOLVED", Vector2.ZERO, Vector2(ui.size.x, 24), UiTokens.TEXT_S, UiTokens.INK_MUTED)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.autowrap_mode = TextServer.AUTOWRAP_OFF
	var title: Label = UiKit.label(card, title_for(definition), Vector2(0, 24), Vector2(ui.size.x, 56), UiTokens.TEXT_2XL, ShipCatalog.get_color(definition.element))
	title.theme_type_variation = UiTokens.DISPLAY_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiLayout.scale_text(card)
	card.size = Vector2(ui.size.x, 80)
	card.position = Vector2(0, ui.size.y * CARD_HEIGHT_FRACTION - 40.0)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * (1.0 if UiMotion.reduced else SLAM_SCALE)
	card.modulate.a = 0.0
	var motion: Tween = UiMotion.tween(card).set_parallel(true)
	motion.tween_property(card, "scale", Vector2.ONE, UiMotion.duration(SLAM_SECONDS)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion.tween_property(card, "modulate:a", 1.0, UiMotion.duration(SLAM_SECONDS, true))
	motion.chain().tween_interval(CARD_HOLD_SECONDS)
	motion.chain().tween_property(card, "modulate:a", 0.0, UiMotion.duration(CARD_FADE_SECONDS, true)).set_trans(UiTokens.EASE_OUT_TRANS).set_ease(UiTokens.EASE_OUT_EASE)
	motion.chain().tween_callback(queue_free)

func _free_after(seconds: float) -> void:
	UiMotion.tween(self).tween_interval(maxf(0.001, seconds)).finished.connect(queue_free)

func _exit_tree() -> void:
	if is_instance_valid(renderer): renderer.assembly_t = 1.0
	if is_instance_valid(card): card.queue_free()
