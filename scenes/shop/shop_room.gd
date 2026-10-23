extends Node2D
## Draws the isometric shop: baked layers, the live LED price board, the wall clock,
## the keeper, the staff, the cat, the sunbeam and the customers. Customers are owned by
## shop.gd; this only draws and animates them (walk cycle, facing, blinking, moods).

const CLERK_LOOK := {
	"skin": "#c98f62", "hair": "#1a1a1a", "hair_style": 4, "shirt": "#8a5bb0", "top": 0,
	"pants": "#2f3442", "glasses": true, "beard": false, "hat": false, "apron": true,
}
const GUARD_LOOK := {
	"skin": "#7a4a2c", "hair": "#2a1a10", "hair_style": 3, "shirt": "#30406a", "top": 1,
	"pants": "#1f1f24", "glasses": false, "beard": false, "hat": true, "apron": false,
}
const BOARD_ROWS := [["XAU", "AU", Color("#ffb43a")], ["XAG", "AG", Color("#e6ecf4")], ["XPT", "PT", Color("#b8c8e6")], ["XPD", "PD", Color("#c8b8e6")]]

var customers: Array[Customer] = []
var front_customer: Customer
## 0 at opening, 1 at closing time.
var day_fraction := 0.0
## The keeper is off at the safe with the till, and the clerk is ringing someone up.
var keeper_away := false
var clerk_busy := false

var _iso := ShopArt.iso_on(PixelCanvas.new(1, 1))
var _room := {}
var _front := {}
var _glass: Texture2D
var _shelf_stock: Texture2D
var _case_stock: Texture2D
var _keeper: Array[Texture2D] = []
var _clerk: Texture2D
var _guard: Texture2D
var _light := {}
var _fit := {}
var _cat: Array[Texture2D] = []
var _season := ""
var _time := 0.0
## Per customer: where they were last frame, which way they face, when they started leaving.
var _last_pos := {}
var _facing_back := {}
var _left_at := {}
## Decorating in the morning: spot markers show, `held` is the piece being placed and
## `hover_spot` the spot under the pointer (-1 for none).
var decorating := false
var held := ""
var hover_spot := -1


func _ready() -> void:
	for dusk in [false, true]:
		_light[dusk] = ShopAmbience.paint_light(dusk).texture()
	_refresh_season()
	Day.day_started.connect(func(_d): _refresh_season())
	SaveGame.new_game_started.connect(_refresh_season)
	_glass = ShopArt.paint_case_glass().texture()
	var look := PeopleArt.keeper_look()
	_keeper.append(PeopleArt.paint(look, PeopleArt.STAND).texture())
	_keeper.append(PeopleArt.paint(look, PeopleArt.BLINK).texture())
	_cat = ShopAmbience.paint_cat_frames()
	_clerk = PeopleArt.paint(CLERK_LOOK, PeopleArt.STAND).texture()
	_guard = PeopleArt.paint(GUARD_LOOK, PeopleArt.STAND).texture()
	_refresh_stock()
	_refresh_fit()
	Shop.changed.connect(_refresh_stock)
	Progress.changed.connect(_refresh_fit)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func screen_pos(i: float, j: float, z := 0.0) -> Vector2:
	return _iso.p(i, j, z)


## Repaints the counter when the player buys a counter or bench upgrade.
func _refresh_fit() -> void:
	var fit := ShopArt.fit_out()
	if fit == _fit and not _front.is_empty():
		return
	_fit = fit
	for dusk in [false, true]:
		_front[dusk] = ShopArt.paint_front(dusk, fit).texture()


## Repaints the walls when the season outside the window changes.
func _refresh_season() -> void:
	var id: String = Calendar.season().id
	if id == _season:
		return
	_season = id
	for dusk in [false, true]:
		_room[dusk] = ShopArt.paint_room(dusk, id).texture()


func _refresh_stock() -> void:
	_shelf_stock = ShopArt.paint_shelf_stock(Shop.ounces_by_metal()).texture()
	_case_stock = ShopArt.paint_case_stock(Shop.coins_on_display()).texture()


func _draw() -> void:
	var dusk := clampf((day_fraction - 0.7) * 3.3, 0.0, 1.0)
	draw_texture(_room[dusk > 0.5], Vector2.ZERO)
	draw_texture(_light[dusk > 0.5], Vector2.ZERO)
	_draw_board()
	_draw_clock()
	_draw_weather(dusk > 0.5)
	ShopAmbience.draw_neon(self, _iso, _time, day_fraction < 1.0)
	ShopAmbience.draw_camera_led(self, _iso, _time)
	draw_texture(_shelf_stock, Vector2.ZERO)
	_draw_behind_counter()
	ShopAmbience.draw_motes(self, _iso, _time, dusk > 0.5)
	draw_texture(_front[dusk > 0.5], Vector2.ZERO)
	draw_texture(_case_stock, Vector2.ZERO)
	draw_texture(_glass, Vector2.ZERO)
	ShopAmbience.draw_cat(self, _iso, _cat, _time)
	_draw_customers()
	if decorating:
		_draw_spots()
	if dusk > 0.0:
		draw_rect(Rect2(Vector2.ZERO, ShopArt.SIZE), Color(0.08, 0.06, 0.22, dusk * 0.28))


## The keeper, the clerk and the decor behind the counter, back to front.
func _draw_behind_counter() -> void:
	var spot := ShopArt.KEEPER_AWAY if keeper_away else ShopArt.KEEPER_SPOT
	var order: Array = [["keeper", spot]]
	if Staff.on_duty("clerk"):
		order.append(["clerk", ShopArt.CLERK_SPOT])
	for n in Decor.placed:
		if _behind_counter(n):
			order.append([n, Decor.spot_at(n)])
	order.sort_custom(func(a, b): return a[1].x + a[1].y < b[1].x + b[1].y)
	var breathe := 1.0 if fmod(_time, 2.4) < 1.2 else 0.0
	for e in order:
		var at := screen_pos(e[1].x, e[1].y).round()
		if e[0] is int:
			_draw_decor(e[0])
		elif e[0] == "keeper":
			draw_texture(_keeper[1 if _blinking(_time, 0.0) else 0], at + Vector2(-8, -28 + breathe))
		else:
			var bob := (1.0 if fmod(_time, 0.5) < 0.25 else 0.0) if clerk_busy else breathe
			draw_texture(_clerk, at + Vector2(-8, -28 + bob))


## Spots behind the counter are drawn before it, the rest in with the customers.
func _behind_counter(spot: int) -> bool:
	return Decor.spot_at(spot).y < ShopArt.COUNTER.position.y


func _draw_decor(spot: int) -> void:
	var id := Decor.piece_on(spot)
	if id == "" or not Decor.spot_open(spot):
		return
	var at := Decor.spot_at(spot)
	var tex := DecorArt.texture(id)
	var pos := screen_pos(at.x, at.y).round() - DecorArt.FOOT
	if decorating and spot == hover_spot and held == "":
		draw_texture(tex, pos, Color(1.25, 1.2, 1.0)) # lifts when you can pick it up
	else:
		draw_texture(tex, pos)


## Diamonds on the floor where pieces can go: gold for a free spot, the held piece as a
## ghost on the spot under the pointer.
func _draw_spots() -> void:
	var pulse := 0.55 + 0.25 * sin(_time * 5.0)
	for n in Decor.spot_count():
		var at := Decor.spot_at(n)
		var hot := n == hover_spot
		var col := Color(Pal.GOLD, pulse) if hot else Color(Pal.GOLD, 0.35)
		if Decor.piece_on(n) != "" and not hot:
			col = Color(Pal.INK, 0.2)
		var r := 0.42
		var pts := [screen_pos(at.x - r, at.y - r), screen_pos(at.x + r, at.y - r), screen_pos(at.x + r, at.y + r), screen_pos(at.x - r, at.y + r)]
		for k in 4:
			var a: Vector2 = pts[k].round()
			var b: Vector2 = pts[(k + 1) % 4].round()
			var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
			for t in steps:
				if t % 2 == 0 or hot:
					draw_rect(Rect2(a.lerp(b, t / float(maxi(steps, 1))).round(), Vector2.ONE), col)
		if hot and held != "":
			draw_texture(DecorArt.texture(held), screen_pos(at.x, at.y).round() - DecorArt.FOOT, Color(1, 1, 1, 0.6))


## Where a floor spot sits on screen (room coordinates), for clicking and the pad.
func spot_rect(spot: int) -> Rect2:
	var at := Decor.spot_at(spot)
	var foot := screen_pos(at.x, at.y).round()
	return Rect2(foot + Vector2(-12, -22), Vector2(24, 28))


## Snow, falling leaves or blossom drifting past the window, by season.
func _draw_weather(dusk: bool) -> void:
	var col: Color
	var count := 0
	var speed := 0.0
	match _season:
		"winter":
			col = Color("#f4f8ff") if not dusk else Color("#a0a8c0")
			count = 14
			speed = 5.0
		"autumn":
			col = Color("#e08a2a") if not dusk else Color("#80502a")
			count = 4
			speed = 7.0
		"spring":
			col = Color("#f4b8cc") if not dusk else Color("#8a6070")
			count = 3
			speed = 4.0
		_:
			return
	# inside the glass of ShopArt._window: j 1.0-3.6, z 22-54
	for n in count:
		var drift := sin(_time * 1.3 + n * 2.1) * 0.08
		var j := 1.2 + fmod(n * 0.61803, 1.0) * 2.2 + drift
		var z := 52.0 - fmod(_time * speed + n * 7.3, 28.0)
		draw_rect(Rect2(screen_pos(0.0, j, z).round(), Vector2.ONE), col)


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
	# untyped, so the guard's spot and the rope posts (by index) can be sorted in with the customers
	var order: Array = []
	order.append_array(customers)
	if Staff.on_duty("guard"):
		order.append(ShopArt.GUARD_SPOT)
	if Progress.has_upgrade("queue_ropes"):
		order.append_array(range(ShopArt.ROPE_POSTS.size()))
	# decor on the shop floor, as {"decor": spot}
	for n in Decor.placed:
		if not _behind_counter(n):
			order.append({"decor": n})
	order.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for key in _last_pos.keys():
		if not customers.has(key):
			_last_pos.erase(key)
			_facing_back.erase(key)
			_left_at.erase(key)
	for c in order:
		if c is Vector2:
			_draw_guard(c)
			continue
		if c is int:
			ShopArt.draw_rope_post(self, _iso, c)
			continue
		if c is Dictionary:
			_draw_decor(c.decor)
			continue
		var base := screen_pos(c.pos.x, c.pos.y).round()
		var frame := _frame_for(c)
		draw_rect(Rect2(base + Vector2(-5, -1), Vector2(11, 2)), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(base + Vector2(-3, 0), Vector2(7, 1)), Color(0, 0, 0, 0.2))
		draw_texture(c.frames[frame], base + Vector2(-8, -27))
		if c.leaving:
			_draw_mood(c, base)
		if c.leaving or c.walking:
			continue
		var f := clampf(c.patience / c.max_patience, 0.0, 1.0)
		var bar := Rect2(base + Vector2(-6, -32), Vector2(12, 2))
		draw_rect(bar, Color("#1a1410"))
		var bar_col := Pal.GOOD if f > 0.5 else (Pal.WARN if f > 0.25 else Pal.BAD)
		draw_rect(Rect2(bar.position, Vector2(ceilf(12.0 * f), 2)), bar_col)
		if c == front_customer:
			_draw_bubble(c, base + Vector2(5, -46))


func _depth(who) -> float:
	var p: Vector2
	if who is Vector2:
		p = who
	elif who is int:
		p = ShopArt.ROPE_POSTS[who]
	elif who is Dictionary:
		p = Decor.spot_at(who.decor)
	else:
		p = who.pos
	return p.x + p.y


func _draw_guard(at: Vector2) -> void:
	var base := screen_pos(at.x, at.y).round()
	draw_rect(Rect2(base + Vector2(-5, -1), Vector2(11, 2)), Color(0, 0, 0, 0.3))
	draw_texture(_guard, base + Vector2(-8, -27))
	# the badge
	draw_rect(Rect2(base + Vector2(-3, -16), Vector2(1, 1)), Pal.GOLD)


## Picks the customer's animation frame: walking towards or away from us, standing,
## blinking now and then, or arms folded and tapping a foot once their patience runs low.
func _frame_for(c: Customer) -> int:
	var phase := float(c.seed % 1000) / 1000.0
	var screen := screen_pos(c.pos.x, c.pos.y)
	var moved: Vector2 = screen - _last_pos.get(c, screen)
	_last_pos[c] = screen
	if moved.length() > 0.01:
		_facing_back[c] = moved.y < 0.0
	var back: bool = _facing_back.get(c, false)
	if c.leaving and not _left_at.has(c):
		_left_at[c] = _time
	if c.leaving and c.dealt and _time - float(_left_at[c]) < 0.5:
		return PeopleArt.HAPPY # a wave on the way out
	if c.walking:
		var step := int(_time * 7.0 + phase * 4.0) % 4
		return PeopleArt.BACK_WALK[step] if back else PeopleArt.WALK[step]
	if back:
		return PeopleArt.BACK
	if c.leaving:
		return PeopleArt.STAND
	if c.patience / c.max_patience < 0.3:
		return PeopleArt.TAP if fmod(_time + phase, 0.6) < 0.2 else PeopleArt.CROSS
	return PeopleArt.BLINK if _blinking(_time, phase) else PeopleArt.STAND


## True for a blink of 0.15 s every few seconds, offset by `phase` so people blink out of step.
func _blinking(t: float, phase: float) -> bool:
	return fmod(t + phase * 3.7, 3.7) < 0.15


## A heart floats up over someone who leaves with a deal, a grumble over someone who doesn't.
func _draw_mood(c: Customer, base: Vector2) -> void:
	var t: float = _time - _left_at[c]
	if t > 1.6:
		return
	var at := base + Vector2(-3, -36 - floorf(t * 6.0))
	var a := clampf(1.6 - t, 0.0, 1.0)
	var rows: Array
	var col: Color
	if c.dealt:
		rows = [".#.#.", "#####", "#####", ".###.", "..#.."]
		col = Color("#ff6a7a", a)
	else:
		rows = ["#.#.#", ".###.", "##.##", ".###.", "#.#.#"]
		col = Color("#9aa3b0", a)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), col)


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
