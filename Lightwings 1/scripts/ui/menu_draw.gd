class_name MenuDraw
extends Control
## A Control that draws through a Callable (modernization M15): the menus' procedural art (the
## title's sky, level select's rails, an element glyph, the level-complete ring) without a class per
## picture. `painter(self)` runs in _draw. With `animate`, `clock` advances by the real frame delta
## (never the sim's time scale) and the control redraws every frame, paused or not. `input_handler`
## sees every InputEvent first (the title's "any press skips the intro"); it never consumes one.

var painter: Callable
var input_handler: Callable
## Called with (self, delta) every animated frame before the redraw: moves child nodes (the title's
## orbiting hero), which a painter must not do mid-draw.
var on_tick: Callable
var animate: bool = false:
	set(value):
		animate = value
		set_process(value)
var clock: float = 0.0
## Free per-picture state (a ring's fill, a glyph's element) that tweens can drive.
var progress: float = 1.0:
	set(value):
		progress = value
		queue_redraw()

func _init(draw_with: Callable = Callable()) -> void:
	painter = draw_with
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _process(delta: float) -> void:
	clock += delta
	if on_tick.is_valid(): on_tick.call(self, delta)
	queue_redraw()

func _draw() -> void:
	if painter.is_valid(): painter.call(self)

func _input(event: InputEvent) -> void:
	if input_handler.is_valid(): input_handler.call(event)
