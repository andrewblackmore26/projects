class_name Hud
extends RefCounted
## The in-combat HUD (moved from main.gd's `_build_hud`/`_refresh_hud` and its draw callbacks in
## modernization M2): top bar with the light bar, tier ticks and combo; bottom bar with the build
## readout, slot icons and the evolve pill; the off-screen radar; the corner minimap
## (scripts/ui/hud/minimap.gd). Everything is built into main.gd's `hud` group at the same fixed
## 1280x800 positions as before (M6 does anchors). It reads the run through `app`.

const BLUE := VisualStyle.BLUE
const WHITE := VisualStyle.TEXT
const MUTED := VisualStyle.MUTED
const GOLD := VisualStyle.ACCENT

var app: Node
var root: Control
var energy_label: Label
var sector_label: Label
var build_label: Label
var evolution_button: Button
var energy_bar: ProgressBar
var tier_ticks: Control
var radar_overlay: Control
var slot_overlay: Control
var light_mix_label: Label
var light_mix_secondary: Label
var minimap: Minimap

func _init(owner: Node, hud_root: Control) -> void:
	app = owner
	root = hud_root

func build() -> void:
	UiKit.panel(root,Rect2(0,0,1280,78),VisualStyle.PANEL,Color("34343b"))
	UiKit.label(root,"L I G H T S H I P",Vector2(24,12),Vector2(290,27),20,WHITE)
	sector_label = UiKit.label(root,"ORIGIN",Vector2(25,43),Vector2(330,23),11,MUTED)
	energy_label = UiKit.label(root,"LIGHT · T1",Vector2(365,8),Vector2(590,25),15,BLUE)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_bar = UiKit.progress(root,Rect2(365,37,590,10),BLUE)
	tier_ticks = Control.new()
	tier_ticks.position = Vector2(365,37)
	tier_ticks.size = Vector2(590,10)
	tier_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tier_ticks)
	tier_ticks.draw.connect(_draw_tier_ticks)
	radar_overlay = Control.new()
	radar_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar_overlay)
	radar_overlay.draw.connect(_draw_radar)
	light_mix_label = UiKit.label(root,"",Vector2(365,51),Vector2(295,20),10,MUTED)
	light_mix_secondary = UiKit.label(root,"",Vector2(660,51),Vector2(295,20),10,MUTED)
	app.button(root,"MAP · TAB",Rect2(989,18,171,40),app._show_map)
	app.button(root,"Ⅱ",Rect2(1172,18,78,40),app._show_pause)
	UiKit.panel(root,Rect2(0,717,1280,83),VisualStyle.PANEL,Color("34343b"))
	build_label = UiKit.label(root,"SEED",Vector2(24,728),Vector2(790,62),13,MUTED)
	slot_overlay = Control.new()
	slot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slot_overlay)
	slot_overlay.draw.connect(_draw_slot_icons)
	## Pill under the bar (spec §24: slot icons and the evolve prompt must
	## coexist, not overlap -- moved off the slot-icon strip at y=752).
	evolution_button = app.button(root,"EVOLUTION READY · E",Rect2(845,690,405,22),app._show_evolution)
	evolution_button.add_theme_font_size_override("font_size",12)
	evolution_button.visible = false
	minimap = Minimap.new(app)
	minimap.build(root)
	root.visible = false

func refresh() -> void:
	var combat: CombatWorld = app.combat
	var campaign: CampaignState = app.campaign
	if not is_instance_valid(combat) or campaign == null: return
	var next: int = EvolutionRules.threshold(combat.player_tier)
	var capped: bool = combat.player_tier >= app.mode_config.max_tier()
	var capacity: float = GameTuning.capacity(combat.player_tier,app.mode_config.max_tier())
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	var readout: bool = "health_readout" in ship.passives
	energy_label.text = "LIGHT · T%d  %s" % [combat.player_tier,"MAX TIER" if capped else "NEXT T%d · %d" % [combat.player_tier+1,next]]
	if readout: energy_label.text += " · %.1f / %.0f" % [combat.light_total,capacity]
	energy_bar.value = combat.light_total/capacity*100.0
	tier_ticks.queue_redraw()
	radar_overlay.queue_redraw()
	slot_overlay.queue_redraw()
	sector_label.text = "%s · NODE %s · RING %d" % ["DEMO" if campaign.demo else "CAMPAIGN",CampaignState.coord_key(campaign.current_sector),CampaignState.ring(campaign.current_sector)]
	app.absorbed = combat.absorption
	var absorbed: Dictionary = app.absorbed
	var leading: Array = absorbed.keys()
	leading.sort_custom(func(a: String,b: String) -> bool: return float(absorbed[a])>float(absorbed[b]))
	var mix := PackedStringArray()
	for i: int in range(mini(3,leading.size())):
		mix.append("%s %.0f" % [str(leading[i]).to_upper(),float(absorbed[leading[i]])])
	light_mix_label.text = " / ".join(mix)
	light_mix_secondary.text = "ABSORBED SINCE EVOLUTION" if not mix.is_empty() else "ABSORB LIGHT TO HEAL AND GROW"
	build_label.text = "%s · T%d %s\nPrimary: %s  |  %s\nPassive: %s" % [ship.display_name,ship.tier,ship.role.capitalize(),UiKit.ability_name(ship.primary),component_controls(),UiKit.ability_names(ship.passives)]
	evolution_button.visible = not capped and combat.light_total >= next and combat.light_total > 0.0
	if is_instance_valid(combat.player.get("renderer")): combat.player.renderer.evolution_ready = evolution_button.visible
	if evolution_button.visible: evolution_button.modulate = Color.WHITE*(0.88+0.12*sin(app.elapsed_ui*3.0))
	minimap.redraw()

func component_controls() -> String:
	var combat: CombatWorld = app.combat
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return ""
	var labels := PackedStringArray()
	for index: int in range(ship.secondaries.size()):
		var id: String = ship.secondaries[index]
		var cooldowns: Dictionary = combat.player.get("cooldowns",{})
		var cooldown: float = float(cooldowns.get("secondary_%d" % index,0.0))
		labels.append("%s: %s%s" % [["Space/LB","Shift/RB","Q/X"][index],UiKit.ability_name(id)," %.1fs" % cooldown if cooldown>0 else ""])
	return " | ".join(labels) if not labels.is_empty() else "Secondary: None"

func _draw_slot_icons() -> void:
	## Spec §24: slot icons with cooldowns AND the evolve prompt are both
	## required on screen at once (P1 left this returning early because they
	## used to overlap -- the evolve pill moved in build() so they no
	## longer do; slot icons must stay visible regardless of its visibility).
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat): return
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	var components: Array[String] = ship.mounted_components()
	for index: int in range(components.size()):
		var definition: AbilityDefinition = AbilityCatalog.get_definition(components[index])
		var at: Vector2 = Vector2(867+index*68,752)
		var ink: Color = ShipCatalog.get_color(definition.visual_color)
		slot_overlay.draw_circle(at,13,Color(ink.r*0.1,ink.g*0.1,ink.b*0.1))
		slot_overlay.draw_arc(at,13,0,TAU,28,ink,1.5,true)
		var cooldown: float = float(combat.player.get("fire_cd",0.0)) if index==0 else float(combat.player.get("cooldowns",{}).get("secondary_%d" % (index-1),0.0))
		var fill: float = 1.0-clampf(cooldown/maxf(0.001,definition.cooldown),0,1)
		slot_overlay.draw_arc(at,17,-PI/2,-PI/2+TAU*maxf(fill,0.005),32,Color(ink,0.6),1.0,true)
		var text: String = "LMB" if index==0 else (["SPACE","SHIFT","Q"][index-1] if index<=ship.secondaries.size() else "PASSIVE")
		slot_overlay.draw_string(ThemeDB.fallback_font,at+Vector2(-22,35),text,HORIZONTAL_ALIGNMENT_CENTER,44,9,Color("9099a8"))
	_draw_dash_icon()

## Dash cooldown icon (spec §26/plan P6): next to the existing slot icons,
## one fixed slot to their left rather than indexed with `components` (the
## dash is not an ability mount).
func _draw_dash_icon() -> void:
	var at: Vector2 = Vector2(867-68,752)
	var cooldown: float = float(app.combat.player.get("dash_cooldown",0.0))
	var fill: float = 1.0-clampf(cooldown/CombatWorld.DASH_COOLDOWN_SECONDS,0,1)
	var ready: bool = cooldown<=0.0
	var ink: Color = BLUE if ready else MUTED
	slot_overlay.draw_circle(at,13,Color(ink.r*0.1,ink.g*0.1,ink.b*0.1))
	slot_overlay.draw_arc(at,13,0,TAU,28,ink,1.5,true)
	slot_overlay.draw_arc(at,17,-PI/2,-PI/2+TAU*maxf(fill,0.005),32,Color(ink,0.6),1.0,true)
	slot_overlay.draw_string(ThemeDB.fallback_font,at+Vector2(-22,35),"RMB",HORIZONTAL_ALIGNMENT_CENTER,44,9,Color("9099a8"))

func _draw_radar() -> void:
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat) or not combat.has_passive("radar"): return
	var visible_area: Rect2 = Rect2(22,94,1236,608)
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("dead",false)): continue
		var screen: Vector2 = Vector2(actor.pos)-combat.player_position+Vector2(640,400)
		if visible_area.has_point(screen): continue
		var direction: Vector2 = screen-Vector2(640,400)
		var scale_factor: float = minf(610.0/maxf(0.001,absf(direction.x)),294.0/maxf(0.001,absf(direction.y)))
		var at: Vector2 = Vector2(640,400)+direction*scale_factor
		radar_overlay.draw_circle(at,3.5,ShipCatalog.get_color(str(actor.element)))

func _draw_tier_ticks() -> void:
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat): return
	var capacity: float = GameTuning.capacity(combat.player_tier,app.mode_config.max_tier())
	for index: int in range(GameTuning.THRESHOLDS.size()):
		var threshold: float = GameTuning.THRESHOLDS[index]
		if threshold > capacity: continue
		var x: float = threshold/capacity*590.0
		tier_ticks.draw_line(Vector2(x,-3),Vector2(x,13),Color(WHITE,0.6),1.0)
	var floor_value: float = GameTuning.regression_floor(combat.player_tier)
	if floor_value > 0:
		var ink: Color = Color("ff5436")
		ink.a = 0.55+0.45*sin(app.elapsed_ui*7.0) if combat.light_total < floor_value*1.12 else 0.65
		var x: float = floor_value/capacity*590.0
		tier_ticks.draw_line(Vector2(x,-4),Vector2(x,14),ink,2.0)
	# Spec §24/§7.2: combo multiplier near the bar, decaying visibly - once
	# the 2.5s kill window lapses and the count is draining, the readout
	# pulses instead of holding solid.
	if combat.combo_count > 0:
		var draining: bool = combat.combo_timer <= 0.0
		var combo_alpha: float = (0.5+0.5*sin(app.elapsed_ui*9.0)) if draining else 1.0
		var combo_text: String = "COMBO x%.1f (%d)" % [combat.combo_multiplier(),combat.combo_count]
		tier_ticks.draw_string(ThemeDB.fallback_font,Vector2(590-160,-16),combo_text,HORIZONTAL_ALIGNMENT_RIGHT,160,13,Color(GOLD,combo_alpha))
