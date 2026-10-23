class_name ShopCat
extends Button
## The shop cat, asleep on the end of the counter, can be petted. This is an invisible
## button over it: on the cat the pointer turns into a hand (and a little hand shows over
## the cat), a click gives it a stroke and holding the button keeps stroking. Each stroke
## wakes it up happy for a moment, sends a heart up and starts it purring. The pad's
## pointer and A button work too, and the d-pad stops at the cat like any other button.

## Seconds between strokes while the button is held down.
const STROKE_EVERY := 0.6

## The shop floor the cat sleeps on (shop_room.gd).
var room: Node2D
var _next_stroke := 0.0
var _purr: AudioStreamPlayer


func _init(on_room: Node2D) -> void:
	room = on_room


func _ready() -> void:
	var r: Rect2 = room.cat_rect()
	position = r.position + room.position
	size = r.size
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Pet the cat"
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style, empty)
	_purr = AudioStreamPlayer.new()
	_purr.stream = ShopSfx.purr()
	_purr.volume_db = -4.0
	_purr.bus = "SFX"
	add_child(_purr)
	button_down.connect(stroke)
	mouse_entered.connect(func(): room.cat_hover = true)
	mouse_exited.connect(func(): room.cat_hover = false)


func _process(delta: float) -> void:
	if not is_pressed() or not is_hovered():
		_next_stroke = 0.0
		return
	_next_stroke -= delta
	if _next_stroke <= 0.0:
		stroke()


## One stroke: hearts, the happy face, the purr (a little chirp first if it was asleep).
func stroke() -> void:
	if not room.cat_is_happy():
		Sfx.play(self, ShopSfx.mrrp(), -6.0)
	room.pet_cat()
	_next_stroke = STROKE_EVERY
	if not _purr.playing:
		_purr.play()
	Records.pet_cat()
