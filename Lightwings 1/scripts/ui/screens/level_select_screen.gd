class_name LevelSelectScreen
extends UiScreen
## Level select (spec §4: "Menu: Campaign and Dev mode, each with level
## select"). Campaign offers levels 1..completed+1; dev offers all five.
## This chooses where a NEW run starts; an existing "continue" resumes
## exactly where the profile left off and does not go through this screen.
## args: {mode_id}.

func build() -> void:
	var mode_id: String = str(args.mode_id)
	var config := ModeConfig.from_id(mode_id)
	var completed: Array = []
	var snapshot: Dictionary = SaveService.load_snapshot(config.save_slot())
	if not snapshot.is_empty(): completed.assign(snapshot.get("profile",{}).get("levels_completed",[]))
	centered_label(host,"SELECT A LEVEL · "+config.menu_label(),Vector2(200,120),Vector2(880,52),30,WHITE)
	var levels: Array[int] = config.selectable_levels(completed)
	for index: int in range(levels.size()):
		var level: int = levels[index]
		var choice: Button = button(host,"LEVEL %d · %s" % [level,GameTuning.ELEMENTS[mini(level-1,GameTuning.ELEMENTS.size()-1)].to_upper()],Rect2(200+float(index%2)*440,220+float(index/2)*70,400,52),app._begin_at_level.bind(mode_id,level))
		if _focus == null: _focus = choice
	button(host,"CANCEL",Rect2(480,560,320,45),app._close_overlay)
