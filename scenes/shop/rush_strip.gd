class_name RushStrip
extends CanvasLayer
## A strip across the top of a testing bench during a rush: who is still waiting at
## the counter, how patient they are, and whether the till needs a run to the vault.
## The clock keeps running at the bench in a rush, so this tells you when to hurry back.

const AREA := Rect2(118, 1, 196, 11)

var shop: Node
var _box: Panel
var _label: Label
var _bars: Control


func _init(owner_shop: Node) -> void:
	shop = owner_shop
	layer = 5


func _ready() -> void:
	_box = Panel.new()
	add_child(_box)
	_box.theme = UiTheme.get_theme()
	_box.position = AREA.position
	_box.size = AREA.size
	_box.add_theme_stylebox_override("panel", UiTheme.box(Color("#120e0a"), Pal.WARN))
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_box.add_child(_label)
	_label.position = Vector2(4, 1)
	_label.size = Vector2(120, 8)
	_label.add_theme_color_override("font_color", Pal.WARN)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars = Control.new()
	_box.add_child(_bars)
	_bars.position = Vector2(126, 0)
	_bars.size = Vector2(66, 11)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	_box.visible = false


func _process(_delta: float) -> void:
	_box.visible = shop._test != null and not shop.rush.is_empty()
	if not _box.visible:
		return
	var hot: bool = shop.till > RushHours.till_limit()
	_label.text = tr("%s · %d waiting%s") % [tr(shop.rush.name).to_upper(), _waiting().size(), tr(" · TILL!") if hot else ""]
	_bars.queue_redraw()


func _waiting() -> Array[Customer]:
	var out: Array[Customer] = []
	for c in shop.queue:
		if c != shop._testing and not c.walking:
			out.append(c)
	return out


func _draw_bars() -> void:
	var x := 0.0
	for c in _waiting():
		var f := clampf(c.patience / c.max_patience, 0.0, 1.0)
		var bar := Rect2(x, 4, 14, 3)
		_bars.draw_rect(bar, Color("#2a2018"))
		var col := Pal.GOOD if f > 0.5 else (Pal.WARN if f > 0.25 else Pal.BAD)
		_bars.draw_rect(Rect2(bar.position, Vector2(ceilf(14.0 * f), 3)), col)
		x += 16.0
