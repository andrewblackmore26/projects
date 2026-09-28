class_name PauseScreen
extends UiScreen
## The in-game pause menu (moved from main.gd's `_show_pause` in M2). Options opens over it and
## returns to it (ScreenRouter policy `returns`).

func build() -> void:
	UiKit.glass(host,Rect2(420,180,440,425))
	centered_label(host,"INSTANCE PAUSED",Vector2(400,205),Vector2(480,58),UiTokens.TEXT_2XL,WHITE)
	_focus = button(host,"RESUME",Rect2(450,320,380,52),app._close_overlay)
	_focus.theme_type_variation = UiTokens.PRIMARY_BUTTON
	button(host,"OPTIONS & CONTROLS",Rect2(450,387,380,52),app._show_options)
	button(host,"SAVE & MAIN MENU",Rect2(450,454,380,52),func() -> void: app._save_game(); app._show_menu())
	button(host,"SAVE & QUIT",Rect2(450,521,380,52),app._quit)
