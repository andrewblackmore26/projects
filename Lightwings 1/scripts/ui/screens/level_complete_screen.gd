class_name LevelCompleteScreen
extends UiScreen
## Level complete (spec §4/§11; moved from main.gd in M2): the next element is revealed and the
## next level unlocked by RunController.on_boss_defeated; this offers CONTINUE TO LEVEL N+1 /
## KEEP EXPLORING. args: {result} (CampaignState.complete_level()).

func build() -> void:
	var result: Dictionary = args.result
	var next_level: int = int(result.get("next_level",app.campaign.level+1))
	var revealed: String = str(result.get("revealed_element",""))
	centered_label(host,"LEVEL %d COMPLETE" % app.campaign.level,Vector2(100,220),Vector2(1080,70),35,WHITE)
	var text: String = "The rival's signal yields.\n%s light now reveals itself in the world." % revealed.capitalize() if not revealed.is_empty() else "The rival's signal yields."
	centered_label(host,text,Vector2(150,340),Vector2(980,80),22,MUTED)
	_focus = button(host,"CONTINUE TO LEVEL %d" % next_level,Rect2(440,470,400,55),app._begin_at_level.bind(app.mode_config.id,next_level))
	button(host,"KEEP EXPLORING",Rect2(440,545,400,48),app._close_overlay)
	button(host,"SAVE & MAIN MENU",Rect2(440,619,400,48),func() -> void: app._save_game(); app._show_menu())
