class_name ConfirmScreen
extends UiScreen
## The two confirmation dialogs (moved from main.gd in M2); the save work behind them stays in
## main.gd (`_replace_game`, `_perform_import`, which archive the old save first).
## args: {variant: "new_game", is_demo} or {variant: "import_demo"}.

func build() -> void:
	match str(args.variant):
		"new_game":
			var is_demo: bool = bool(args.is_demo)
			centered_label(host,"BEGIN A NEW DEMO?" if is_demo else "BEGIN A NEW CAMPAIGN?",Vector2(300,270),Vector2(680,60),34,WHITE)
			centered_label(host,"Your current progress is kept in a separate archive.",Vector2(260,370),Vector2(760,45),18,MUTED)
			button(host,"NEW DEMO" if is_demo else "NEW CAMPAIGN",Rect2(340,470,280,52),app._replace_game.bind(is_demo))
			_focus = button(host,"CANCEL",Rect2(660,470,280,52),app._close_overlay)
		"import_demo":
			centered_label(host,"REPLACE CAMPAIGN WITH DEMO PROGRESS?",Vector2(180,260),Vector2(920,60),29,WHITE)
			centered_label(host,"The current campaign will remain in a separate archive.",Vector2(200,360),Vector2(880,50),18,MUTED)
			button(host,"IMPORT DEMO",Rect2(340,475,280,50),app._perform_import)
			_focus = button(host,"CANCEL",Rect2(660,475,280,50),app._close_overlay)
