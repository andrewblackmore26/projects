class_name EndingScreen
extends UiScreen
## The campaign and demo endings (moved from main.gd's `_show_ending` in M2). args: {is_demo}.

func build() -> void:
	var is_demo: bool = bool(args.is_demo)
	centered_label(host,"A SMALL LIGHT, AN OPEN WORLD" if is_demo else "YOU ARE MORE THAN YOUR ORIGIN",Vector2(100,220),Vector2(1080,70),35,WHITE)
	var text: String = "Lightning and Fire have both yielded.\nThe demo ends here. Keep exploring, try another form,\nor carry this progress into the full campaign." if is_demo else "Five level bosses have yielded. Their signals are yours.\nYou did not become a single perfect machine.\nYou became the sum of what you chose to absorb."
	centered_label(host,text,Vector2(150,340),Vector2(980,125),22,MUTED)
	_focus = button(host,"KEEP EXPLORING",Rect2(440,545,400,55),app._close_overlay)
	button(host,"SAVE & MAIN MENU",Rect2(440,619,400,48),func() -> void: app._save_game(); app._show_menu())
