class_name EndingScreen
extends UiScreen
## The campaign and demo endings (moved from main.gd's `_show_ending` in M2). args: {is_demo}.
##
## M15: the level-complete beat at full size - every element the mode holds floods the ring in turn,
## the run's numbers count up, and KEEP EXPLORING is focused at once.

func build() -> void:
	var is_demo: bool = bool(args.is_demo)
	var kicker: Label = centered_label(host, "DEMO COMPLETE" if is_demo else "CAMPAIGN COMPLETE", Vector2(240, 86), Vector2(800, 20), UiTokens.TEXT_XS, UiTokens.KICKER)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	centered_label(host, "A SMALL LIGHT, AN OPEN WORLD" if is_demo else "YOU ARE MORE THAN YOUR ORIGIN", Vector2(100, 108), Vector2(1080, 56), UiTokens.TEXT_2XL, WHITE)
	var text: String = "Lightning and Fire have both yielded. The demo ends here. Keep exploring, try another form, or carry this progress into the full campaign." if is_demo else "Five level bosses have yielded. Their signals are yours. You did not become a single perfect machine. You became the sum of what you chose to absorb."
	centered_label(host, text, Vector2(240, 170), Vector2(800, 52), UiTokens.TEXT_M, MUTED)
	var elements: Array = GameTuning.ELEMENTS.slice(0, app.mode_config.level_cap())
	LevelCompleteScreen.flood_ring(host, LevelCompleteScreen.RING, elements, "%d SIGNALS HELD" % elements.size())
	var kills: int = app.combat.run_kills if is_instance_valid(app.combat) else 0
	LevelCompleteScreen.stat_row(host, [["LEVELS CLEARED", app.campaign.levels_completed.size()], ["NODES CHARTED", app.campaign.discovered.size()], ["KILLS", kills], ["REBOOTS", app.campaign.deaths]], LevelCompleteScreen.STATS_Y)
	_focus = button(host, "KEEP EXPLORING", Rect2(440, 540, 400, 56), app._close_overlay)
	_focus.theme_type_variation = UiTokens.PRIMARY_BUTTON
	var menu: Button = button(host, "SAVE & MAIN MENU", Rect2(490, 612, 300, 44), func() -> void: app._save_game(); app._show_menu())
	FocusChain.rows([[_focus], [menu]])
	LevelCompleteScreen.footer_hints(host, PromptHints.new([["ui_accept", "CONTINUE"], ["navigate", "MOVE"]]))
