extends Node2D
## Draws the isometric shop: baked layers, the live LED price board, the wall clock,
## the keeper and the customers. Customers are owned by shop.gd; this only draws them.

const BOARD_ROWS := [["XAU", "AU", Color("#ffb43a")], ["XAG", "AG", Color("#e6ecf4")], ["XPT", "PT", Color("#b8c8e6")], ["XPD", "PD", Color("#c8b8e6")]]

var customers: Array[Customer] = []
var front_customer: Customer
## 0 at opening, 1 at closing time.
var day_fraction := 0.0

var _iso := ShopArt.iso_on(PixelCanvas.new(1, 1))
var _room := {}
var _front := {}
var _glass: Texture2D
var _shelf_stock: Texture2D
var _case_stock: Texture2D
var _keeper: Array[Texture2D] = []
var _time := 0.0


func _ready() -> void:
	for dusk in [false, true]:
		_room[dusk] = ShopArt.paint_room(dusk).texture()
		_front[dusk] = ShopArt.paint_front(dusk).texture()
	_glass = ShopArt.paint_case_glass().texture()
	var look := PeopleArt.keeper_look()
	_keeper.append(PeopleArt.paint(look, 0).texture())
	_refresh_stock()
	Shop.changed.connect(_refresh_stock)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func screen_pos(i: float, j: float, z := 0.0) -> Vector2:
	return _iso.p(i, j, z)


func _refresh_stock() -> void:
	_shelf_stock = ShopArt.paint_shelf_stock(Shop.ounces_by_metal()).texture()
	_case_stock = ShopArt.paint_case_stock(Shop.coins_on_display()).texture()


func _draw() -> void:
	var dusk := clampf((day_fraction - 0.7) * 3.3, 0.0, 1.0)
	draw_texture(_room[dusk > 0.5], Vector2.ZERO)
	_draw_board()
	_draw_clock()
	draw_texture(_shelf_stock, Vector2.ZERO)
	var kp := screen_pos(ShopArt.KEEPER_SPOT.x, ShopArt.KEEPER_SPOT.y).round()
	var breathe := 1.0 if fmod(_time, 2.4) < 1.2 else 0.0
	draw_texture(_keeper[0], kp + Vector2(-8, -28 + breathe))
	draw_texture(_front[dusk > 0.5], Vector2.ZERO)
	draw_texture(_case_stock, Vector2.ZERO)
	draw_texture(_glass, Vector2.ZERO)
	_draw_customers()
	if dusk > 0.0:
		draw_rect(Rect2(Vector2.ZERO, ShopArt.SIZE), Color(0.08, 0.06, 0.22, dusk * 0.28))


func _draw_board() -> void:
	var z := ShopArt.BOARD.position.y + ShopArt.BOARD.size.y - 4.0
	for row in BOARD_ROWS:
		var metal: String = row[0]
		if not Market.prices.has(metal):
			continue
		var price := float(Market.prices[metal])
		var text := "%s %s" % [row[1], Market.format_money(price, 2 if metal == "XAG" else 0)]
		var col: Color = row[2]
		var plot := func(x, y): draw_rect(Rect2(x, y, 1, 1), col)
		_iso.text_on_j_wall(text, ShopArt.BOARD.position.x + 0.15, z, col, plot)
		var change := Market.day_change_percent(metal)
		var arrow := "▲" if change >= 0.0 else "▼"
		var arrow_col := Pal.GOOD if change >= 0.0 else Pal.BAD
		var arrow_i := ShopArt.BOARD.position.x + ShopArt.BOARD.size.x - 0.5
		_iso.text_on_j_wall(arrow, arrow_i, z, arrow_col, func(x, y): draw_rect(Rect2(x, y, 1, 1), arrow_col))
		z -= 9.0


func _draw_clock() -> void:
	var minutes := 9.0 * 60.0 + day_fraction * 8.0 * 60.0
	var hour_angle := fmod(minutes / 60.0, 12.0) / 12.0 * TAU
	var minute_angle := fmod(minutes, 60.0) / 60.0 * TAU
	_wall_hand(hour_angle, 3.2, Color("#2a1a0c"))
	_wall_hand(minute_angle, 4.8, Color("#5e3b1d"))


## A clock hand on the back wall, angle 0 pointing to 12, length in wall pixels.
func _wall_hand(angle: float, length: float, col: Color) -> void:
	var steps := int(length * 2.0)
	for s in steps + 1:
		var t := s / float(steps) * length
		var u := sin(angle) * t
		var z := cos(angle) * t
		var q := screen_pos(ShopArt.CLOCK.x + u / 16.0, 0.0, ShopArt.CLOCK.z + z).floor()
		draw_rect(Rect2(q, Vector2.ONE), col)


func _draw_customers() -> void:
	var order := customers.duplicate()
	order.sort_custom(func(a, b): return a.pos.x + a.pos.y < b.pos.x + b.pos.y)
	for c in order:
		var base := screen_pos(c.pos.x, c.pos.y).round()
		var frame := 0
		if c.walking:
			frame = 1 + int(_time * 6.0) % 2
		draw_rect(Rect2(base + Vector2(-5, -1), Vector2(11, 2)), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(base + Vector2(-3, 0), Vector2(7, 1)), Color(0, 0, 0, 0.2))
		draw_texture(c.frames[frame], base + Vector2(-8, -27))
		if c.leaving or c.walking:
			continue
		var f := clampf(c.patience / c.max_patience, 0.0, 1.0)
		var bar := Rect2(base + Vector2(-6, -32), Vector2(12, 2))
		draw_rect(bar, Color("#1a1410"))
		var bar_col := Pal.GOOD if f > 0.5 else (Pal.WARN if f > 0.25 else Pal.BAD)
		draw_rect(Rect2(bar.position, Vector2(ceilf(12.0 * f), 2)), bar_col)
		if c == front_customer:
			_draw_bubble(c, base + Vector2(5, -46))


func _draw_bubble(c: Customer, at: Vector2) -> void:
	var bob := Vector2(0, -1) if fmod(_time, 1.0) < 0.5 else Vector2.ZERO
	at += bob
	draw_rect(Rect2(at, Vector2(13, 11)), Pal.INK)
	draw_rect(Rect2(at + Vector2(1, 11), Vector2(3, 1)), Pal.INK)
	draw_rect(Rect2(at + Vector2(1, 12), Vector2(1, 1)), Pal.INK)
	if c.kind == "seller" and c.piece:
		# a little ring with a stone
		var pal := Pal.for_metal(c.piece.metal)
		for d in [Vector2(4, 5), Vector2(5, 4), Vector2(7, 4), Vector2(8, 5), Vector2(4, 6), Vector2(8, 6), Vector2(5, 7), Vector2(6, 7), Vector2(7, 7)]:
			draw_rect(Rect2(at + d + Vector2(0, 1), Vector2.ONE), Pal.metal(pal, 3 if d.y < 6 else 2))
		draw_rect(Rect2(at + Vector2(6, 2), Vector2(1, 2)), Color("#cfe6ff"))
		draw_rect(Rect2(at + Vector2(5, 3), Vector2(3, 1)), Color("#9cc0e8"))
	elif c.kind == "seller" and c.bar:
		# a little bar with a bevel
		var pal := c.bar.palette_name()
		draw_rect(Rect2(at + Vector2(2, 4), Vector2(9, 5)), Pal.metal(pal, 1))
		draw_rect(Rect2(at + Vector2(2, 4), Vector2(8, 4)), Pal.metal(pal, 3))
		draw_rect(Rect2(at + Vector2(3, 4), Vector2(6, 1)), Pal.metal(pal, 5))
		draw_rect(Rect2(at + Vector2(3, 5), Vector2(6, 2)), Pal.metal(pal, 4))
	elif c.kind == "seller":
		var pal := c.item.palette_name()
		draw_rect(Rect2(at + Vector2(3, 2), Vector2(7, 7)), Pal.metal(pal, 1))
		draw_rect(Rect2(at + Vector2(3, 2), Vector2(6, 6)), Pal.metal(pal, 3))
		draw_rect(Rect2(at + Vector2(4, 3), Vector2(4, 4)), Pal.metal(pal, 4))
		draw_rect(Rect2(at + Vector2(4, 3), Vector2(1, 1)), Pal.metal(pal, 5))
	else:
		PixelFont.plot_text("$", func(x, y): draw_rect(Rect2(at + Vector2(4 + x, 2 + y), Vector2.ONE), Color("#2b5a3a")))
