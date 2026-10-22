extends Control
## Breaking-news strip over the shop floor while a market event runs.
## The headline scrolls when it is wider than the strip; the line under it shows time left.
## On a town event day (Calendar) it shows the event under a TOWN tag while no news breaks.

const RECT := Rect2(2, 14, 312, 13)
const TAG_W := 25
const SCROLL_SPEED := 24.0 # px per second
const HOLD_SECONDS := 1.5 # the start of the headline stays still this long
const GAP := "   ●   "

var _bg: Panel
var _tag: Panel
var _tag_label: Label
var _clip: Control
var _text: Label
var _bar: ColorRect
var _period := 0
var _t := 0.0
## The town event on show, or "" when the strip shows market news or nothing.
var _town_id := ""


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = _panel(Rect2(Vector2.ZERO, size), Color("#120e0a"), Pal.PANEL_EDGE)
	_tag = _panel(Rect2(0, 0, TAG_W, size.y), Pal.BAD.darkened(0.45), Pal.BAD)
	_tag_label = Label.new()
	_tag.add_child(_tag_label)
	_tag_label.text = "NEWS"
	_tag_label.position = Vector2(4, 2)
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new()
	add_child(_clip)
	_clip.clip_contents = true
	_clip.position = Vector2(TAG_W + 3, 1)
	_clip.size = Vector2(size.x - TAG_W - 5, size.y - 3)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = Label.new()
	_clip.add_child(_text)
	_text.position = Vector2(0, 1)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = ColorRect.new()
	add_child(_bar)
	_bar.position = Vector2(1, size.y - 2)
	_bar.size = Vector2(size.x - 2, 1)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MarketEvents.started.connect(_show)
	MarketEvents.ended.connect(func(_e): visible = false)
	Day.phase_changed.connect(func(_p): _town_id = "")
	visible = false
	if not MarketEvents.active.is_empty():
		_show(MarketEvents.active)


func _process(delta: float) -> void:
	var e := MarketEvents.active
	if e.is_empty():
		_show_town()
	if not visible:
		return
	_t += delta
	if _town_id == "":
		_bar.size.x = floorf((size.x - 2) * clampf(float(e.left) / MarketEvents.EVENT_SECONDS, 0.0, 1.0))
		# blink the tag while the story is breaking
		_tag.visible = _t > 3.0 or fmod(_t, 0.5) < 0.35
	if _period > 0:
		var shift := maxf(0.0, _t - HOLD_SECONDS) * SCROLL_SPEED
		_text.position.x = -floorf(fmod(shift, _period))


## While the shop is open on a town event day and no market news is breaking.
func _show_town() -> void:
	var town := Calendar.today() if Day.is_open() else {}
	if town.is_empty():
		_town_id = ""
		visible = false
		return
	if _town_id == town.id and visible:
		return
	_town_id = town.id
	_set_text(Calendar.banner(town), "TOWN", Pal.GOLD)
	_tag.visible = true
	_bar.size.x = size.x - 2


func _show(e: Dictionary) -> void:
	_town_id = ""
	var good: bool = e.get("mood", "") == "good"
	_set_text(MarketEvents.headline(e), "NEWS", Pal.GOOD if good else Pal.BAD)


func _set_text(line: String, tag: String, accent: Color) -> void:
	_tag_label.text = tag
	_tag.add_theme_stylebox_override("panel", UiTheme.box(accent.darkened(0.55), accent))
	_tag_label.add_theme_color_override("font_color", accent.lightened(0.5))
	_bar.color = accent.darkened(0.2)
	_text.add_theme_color_override("font_color", Pal.INK)
	if PixelFont.measure(line) > _clip.size.x:
		_period = PixelFont.measure(line + GAP) + 1
		_text.text = line + GAP + line
	else:
		_period = 0
		_text.text = line
	_text.size = Vector2(PixelFont.measure(_text.text) + 8, 8)
	_text.position.x = 0
	_t = 0.0
	visible = true


func _panel(r: Rect2, bg: Color, edge: Color) -> Panel:
	var p := Panel.new()
	add_child(p)
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", UiTheme.box(bg, edge))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
