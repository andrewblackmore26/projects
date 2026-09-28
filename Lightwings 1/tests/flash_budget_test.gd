extends SceneTree
## M16: `PostFx.request_flash` is the one choke point for full-screen flashes (WCAG 2.3.1): at most
## 3 onsets in any rolling second and a luminance delta of at most 0.25 x the flash setting. Each
## limit has its own negative control (the limit switched off alone). No pixels here; the shader's
## own flash delta is measured by post_fx_render_test.

const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var t: RefCounted = Harness.new("FLASH_BUDGET")
	_rate(t)
	_luminance(t)
	t.finish(self)

## 20 requests spread evenly over one second.
func _burst(post: PostFx) -> int:
	var before: int = post.onset_count
	for i: int in range(20):
		post.request_flash(0.2)
		post.step(0.05)
	return post.onset_count - before

func _rate(t: RefCounted) -> void:
	var post := PostFx.new()
	var onsets: int = _burst(post)
	print("measure: 20 requests in 1 s -> %d onsets, %d rejected" % [onsets, post.rejected_count])
	t.check(onsets <= PostFx.MAX_ONSETS_PER_SECOND, "20 flash requests in 1 s give <= 3 onsets (got %d)" % onsets)
	t.check(onsets == PostFx.MAX_ONSETS_PER_SECOND, "the budget is spent, not starved: exactly 3 onsets (got %d)" % onsets)
	# Rolling, not a lifetime cap: a second burst a second later gets its own 3.
	post.step(1.0)
	var again: int = _burst(post)
	t.check(again == PostFx.MAX_ONSETS_PER_SECOND, "a later second earns a fresh budget of 3 (got %d)" % again)
	# The window is rolling: 3 onsets at t=0.0/0.1/0.2, then a request at 0.95 must still be refused.
	var rolling := PostFx.new()
	for i: int in range(3):
		rolling.request_flash(0.2)
		rolling.step(0.1)
	rolling.step(0.65)
	t.check(not rolling.request_flash(0.2), "a 4th onset 0.95 s after the first is refused")
	rolling.step(0.06)
	t.check(rolling.request_flash(0.2), "and granted once the first onset is over 1 s old")
	post.free()
	rolling.free()
	var open := PostFx.new()
	open.limit_rate = false
	var uncapped: int = _burst(open)
	t.control("rate limiter off (%d onsets)" % uncapped, uncapped > PostFx.MAX_ONSETS_PER_SECOND)
	open.free()

func _luminance(t: RefCounted) -> void:
	var post := PostFx.new()
	for setting: float in [1.0, 0.5]:
		post.flash_setting = setting
		post.step(2.0)
		post.request_flash(1.0)
		print("measure: flash setting %.2f, full-white request -> luminance delta %.3f" % [setting, post.flash_level])
		t.check(post.flash_level <= PostFx.MAX_FLASH_DELTA * setting + 0.0001, "flash setting %.2f caps a full-white request at %.3f (got %.3f)" % [setting, PostFx.MAX_FLASH_DELTA * setting, post.flash_level])
		t.check(post.flash_level > 0.0, "flash setting %.2f still flashes" % setting)
	post.flash_setting = 0.0
	post.step(2.0)
	t.check(not post.request_flash(1.0) and post.flash_level == 0.0, "flash setting 0 gives no onset and no delta")
	post.flash_setting = 1.0
	post.step(2.0)
	post.request_flash(0.1)
	t.check(is_equal_approx(post.flash_level, 0.1), "a request under the cap keeps its own strength (got %.3f)" % post.flash_level)
	post.step(PostFx.FLASH_DECAY_SECONDS + 0.01)
	t.check(post.flash_level == 0.0, "a flash is gone within %.2f s" % PostFx.FLASH_DECAY_SECONDS)
	post.free()
	var open := PostFx.new()
	open.limit_luminance = false
	open.request_flash(1.0)
	t.control("luminance cap off (delta %.3f)" % open.flash_level, open.flash_level > PostFx.MAX_FLASH_DELTA)
	open.free()
