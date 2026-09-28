class_name DialogueBox
extends RefCounted
## The companion's dialogue box (moved from main.gd's `_update_dialogue` in modernization M2).
## DialogueDirector decides WHICH line may show and when (queue, dedupe, the between-fights gate);
## this draws it into main.gd's `dialogue` group and keeps its on-screen timer. The lines
## themselves are still queued from main.gd (tests/dialogue_coverage_test.gd scans it).

const SHOW_SECONDS: float = 11.0

var app: Node
var root: Control
## Seconds the current line stays up; main.gd forwards `dialogue_remaining` here.
var remaining: float = 0.0

func _init(owner: Node, dialogue_root: Control) -> void:
	app = owner
	root = dialogue_root

func dismiss() -> void:
	remaining = 0.0
	root.visible = false

func update(delta: float) -> void:
	if not app.overlay_kind.is_empty(): return
	if remaining > 0.0:
		remaining -= delta
		if remaining <= 0.0: root.visible = false
		return
	var combat: CombatWorld = app.combat
	var combat_clear: bool = is_instance_valid(combat) and combat.remaining_enemies() == 0
	var director: DialogueDirector = app.dialogue_director
	if not director.can_show_next(combat_clear): return
	var line: Dictionary = director.pop_next(combat_clear)
	UiKit.clear(root)
	root.visible = true
	UiKit.panel(root,Rect2(105,549,1070,154),VisualStyle.PANEL,Color("39393f"))
	var portrait := AIPortrait.new()
	portrait.element = str(line.element)
	portrait.position = Vector2(125,568)
	portrait.size = Vector2(98,112)
	root.add_child(portrait)
	UiKit.label(root,str(DialogueDirector.RIVAL_NAMES.get(line.element,"ECHO"))+"  /  "+str(line.title),Vector2(244,568),Vector2(840,25),13,VisualStyle.ACCENT)
	UiKit.label(root,str(line.text),Vector2(244,609),Vector2(840,70),17,VisualStyle.TEXT).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app.button(root,"×",Rect2(1118,561,40,30),dismiss)
	remaining = SHOW_SECONDS
