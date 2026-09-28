extends SceneTree
## Real pixels (modernization M5): the modal backdrop (shaders/ui_backdrop.gdshader, built by
## ScreenRouter.make_backdrop) blurs and dims what is behind it, on this project's renderer.
## A 6 px checkerboard fills the screen; the luma variance of a 96 px patch is measured
## - raw (no backdrop),
## - under the backdrop at blur_lod 0 (dim only: the negative control, "blur radius 0"),
## - under the real dim_blur backdrop.
## Baseline = raw variance x (1 - dim)^2, the variance a dim-only backdrop leaves. The blur must
## leave at most 40 % of it; the control must not get under 40 %.
## Then the live game: Pause over a new run must show the game through the backdrop (not black,
## not the untouched frame).
var failures: int = 0
var checks: int = 0
var caught: int = 0
const PATCH: Rect2i = Rect2i(592, 352, 96, 96)
const CELL: int = 6
const MAX_RATIO: float = 0.40

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frame() -> Image:
	for i: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == root.size, "capture is root.size %s (got %s)" % [root.size, image.get_size()])
	return image

func _luma(pixel: Color) -> float: return pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722

## [mean, variance] of luma over `rect`.
func _stats(image: Image, rect: Rect2i) -> Vector2:
	var total: float = 0.0
	var squares: float = 0.0
	var count: int = rect.size.x * rect.size.y
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var value: float = _luma(image.get_pixel(x, y))
			total += value
			squares += value * value
	var mean: float = total / count
	return Vector2(mean, squares / count - mean * mean)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ui_backdrop_render_test needs a GPU window")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	DisplayServer.window_move_to_foreground()
	var checker := Image.create_empty(1280, 800, false, Image.FORMAT_RGBA8)
	for y: int in range(800):
		for x: int in range(1280):
			checker.set_pixel(x, y, Color(0.9, 0.9, 0.9) if ((x / CELL) + (y / CELL)) % 2 == 0 else Color(0.05, 0.05, 0.05))
	var board := TextureRect.new()
	board.texture = ImageTexture.create_from_image(checker)
	board.size = Vector2(1280, 800)
	root.add_child(board)
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)

	var raw: Vector2 = _stats(await _frame(), PATCH)
	var dim: float = UiTokens.SCRIM_DIM
	var baseline: float = raw.y * (1.0 - dim) * (1.0 - dim)
	var results: Dictionary = {}
	for kind: String in ["dim", "dim_blur"]:
		var backdrop: ColorRect = ScreenRouter.make_backdrop(kind)
		layer.add_child(backdrop)
		results[kind] = _stats(await _frame(), PATCH)
		backdrop.queue_free()
		await process_frame
	var blurred: Vector2 = results.dim_blur
	var dim_only: Vector2 = results.dim
	print("measure: patch luma variance raw %.5f (mean %.3f); baseline x(1-%.2f)^2 = %.5f" % [raw.y, raw.x, dim, baseline])
	print("measure: dim_blur variance %.5f = %.1f%% of baseline (mean %.3f); dim only (blur_lod 0) %.5f = %.1f%% (mean %.3f)" % [blurred.y, 100.0 * blurred.y / baseline, blurred.x, dim_only.y, 100.0 * dim_only.y / baseline, dim_only.x])
	check(raw.y > 0.05, "the checkerboard has contrast to lose (variance %.4f)" % raw.y)
	check(blurred.y <= MAX_RATIO * baseline, "dim_blur leaves <= 40%% of the baseline variance (%.1f%%)" % [100.0 * blurred.y / baseline])
	check(blurred.x < raw.x * (1.0 - dim * 0.5) and blurred.x > raw.x * (1.0 - dim) * 0.5, "dim_blur dims without blacking out (mean %.3f vs raw %.3f)" % [blurred.x, raw.x])
	checks += 1
	if dim_only.y > MAX_RATIO * baseline:
		caught += 1
		print("negative control caught: blur radius 0 keeps %.1f%% of the baseline variance" % [100.0 * dim_only.y / baseline])
	else:
		failures += 1
		push_error("negative control NOT caught: blur radius 0 passed the blur gate")
	board.queue_free()
	layer.queue_free()

	# The live game behind Pause.
	SaveService.storage_root = "user://ui-backdrop-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	app._new_game(false)
	for i: int in range(10): await process_frame
	app.set_process(false)
	var hud_rect := Rect2i(0, 0, 1280, 80)
	var live: Vector2 = _stats(await _frame(), hud_rect)
	app._show_pause()
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.1, true, false, true).timeout
	var behind: Vector2 = _stats(await _frame(), hud_rect)
	print("measure: live HUD strip luma mean %.4f var %.5f; under Pause mean %.4f var %.5f" % [live.x, live.y, behind.x, behind.y])
	check(behind.x > 0.0005, "the game shows through the Pause backdrop (not black)")
	check(behind.y < live.y * 0.5, "the HUD strip under Pause is blurred and dimmed (variance %.5f vs %.5f)" % [behind.y, live.y])
	app._close_overlay()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	print("UI backdrop render: %d checks, %d failures (%d negative controls caught)" % [checks, failures, caught])
	quit(1 if failures else 0)
