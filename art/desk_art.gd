class_name DeskArt
extends RefCounted
## The trading desk close-up: a big dealing-room monitor on a panelled wall, and the
## desk in front of it with a keyboard, a phone, a coffee mug and a gold bar paperweight.
## The chart, the board and the steam off the coffee are drawn live by TradingDesk.

const W := 316
const H := 270
## The monitor's housing and the glass inside it.
const BEZEL := Rect2i(6, 4, 304, 190)
const SCREEN := Rect2i(12, 10, 292, 176)
const DESK_Y := 202
const KEYBOARD := Rect2i(64, 218, 150, 30)
const PHONE := Rect2i(232, 212, 66, 40)
const MUG := Rect2i(18, 222, 20, 22)
const BAR := Rect2i(226, 256, 30, 9)
const SCREEN_BG := Color("#07110d")
const GRID := Color("#12261c")


static func paint() -> PixelCanvas:
	var c := PixelCanvas.new(W, H, Color("#1a2230"))
	_wall(c)
	_desk(c)
	_monitor(c)
	_keyboard(c)
	_phone(c)
	_mug(c)
	_gold_bar(c)
	BenchArt.lamp_light(c, Vector2(158, 236), 260.0)
	return c


## Dark blue panelling with a brass rail, glimpsed round the monitor.
static func _wall(c: PixelCanvas) -> void:
	for y in DESK_Y:
		for x in W:
			var col := Color("#1c2534") if (x / 38) % 2 == 0 else Color("#1f293a")
			if x % 38 == 0:
				col = Color("#121822")
			elif x % 38 == 1:
				col = Color("#2a3549")
			elif ShopArt._noise(x / 2, y) > 0.94:
				col = col.lightened(0.04)
			c.px(x, y, col)
	c.rect(0, DESK_Y - 12, W, 2, Color("#8a6a2a"))
	c.rect(0, DESK_Y - 12, W, 1, Color("#d0a84e"))
	# the monitor's stand
	c.rect(146, BEZEL.end.y, 24, DESK_Y - BEZEL.end.y + 4, Color("#2c3038"))
	c.rect(146, BEZEL.end.y, 2, DESK_Y - BEZEL.end.y + 4, Color("#4a505a"))
	c.rect(132, DESK_Y + 1, 52, 4, Color("#23262c"))
	c.rect(132, DESK_Y + 1, 52, 1, Color("#565c66"))


static func _desk(c: PixelCanvas) -> void:
	var wood := BenchArt.wood(W, H - DESK_Y)
	c.blit(wood, 0, DESK_Y)
	# the desk's front lip catches the light
	c.rect(0, DESK_Y, W, 1, Color("#b88a4c"))
	c.rect(0, DESK_Y + 1, W, 1, Color("#8a5a30"))
	# a leather blotter under the keyboard
	var blot := Rect2i(KEYBOARD.position.x - 12, KEYBOARD.position.y - 6, KEYBOARD.size.x + 24, KEYBOARD.size.y + 18)
	BenchArt.felt(c, blot, Color("#24402f"))
	c.rect(blot.position.x, blot.position.y, blot.size.x, 1, Color("#8a6a2a"))
	c.rect(blot.position.x, blot.end.y - 1, blot.size.x, 1, Color("#5a4418"))


static func _monitor(c: PixelCanvas) -> void:
	BenchArt.housing(c, BEZEL, Color("#2a2e36"))
	var g := SCREEN
	c.rect(g.position.x - 1, g.position.y - 1, g.size.x + 2, g.size.y + 2, Color("#0b0d10"))
	c.rect(g.position.x, g.position.y, g.size.x, g.size.y, SCREEN_BG)
	# a faint vignette at the glass corners
	for y in g.size.y:
		for x in g.size.x:
			var d := Vector2(float(x) / g.size.x - 0.5, float(y) / g.size.y - 0.5).length()
			if d > 0.62 and PixelCanvas.checker(x, y):
				c.px(g.position.x + x, g.position.y + y, Color("#040806"))
	# the maker's badge and the power light
	c.rect(150, BEZEL.end.y - 5, 16, 2, Color("#4a505a"))
	c.px(BEZEL.end.x - 10, BEZEL.end.y - 5, Pal.LED)
	c.px(BEZEL.end.x - 9, BEZEL.end.y - 5, Pal.LED.darkened(0.4))


## A low keyboard: a dark case and rows of keycaps with lit tops.
static func _keyboard(c: PixelCanvas) -> void:
	var k := KEYBOARD
	c.rect(k.position.x + 2, k.position.y + 3, k.size.x, k.size.y, Color(0, 0, 0, 0.3))
	c.rect(k.position.x, k.position.y, k.size.x, k.size.y, Color("#25282e"))
	c.rect(k.position.x, k.position.y, k.size.x, 1, Color("#4a4f58"))
	c.rect(k.position.x, k.end.y - 1, k.size.x, 1, Color("#141619"))
	var rows := [[14, 0], [13, 3], [12, 5], [11, 7]]
	for r in rows.size():
		var y: int = k.position.y + 3 + r * 6
		var x: int = k.position.x + 4 + rows[r][1]
		for n in rows[r][0]:
			_key(c, x, y, 8, Color("#3a3e46"))
			x += 10
		if r == 3:
			_key(c, x, y, k.end.x - x - 4, Color("#3a3e46"))
	# the space bar and the green Buy / red Sell keys every trader has
	_key(c, k.position.x + 40, k.position.y + 27 - 2, 60, Color("#3a3e46"))
	_key(c, k.position.x + 4, k.position.y + 25, 14, Color("#2f6a3c"))
	_key(c, k.end.x - 18, k.position.y + 25, 14, Color("#7a2e2a"))


static func _key(c: PixelCanvas, x: int, y: int, w: int, body: Color) -> void:
	c.rect(x, y, w, 4, body)
	c.rect(x, y, w, 1, body.lightened(0.3))
	c.rect(x, y + 4, w, 1, body.darkened(0.5))


## A desk phone: a cradle with a handset, a keypad and a coiled cord.
static func _phone(c: PixelCanvas) -> void:
	var p := PHONE
	var body := Color("#1f2226")
	c.rect(p.position.x + 2, p.position.y + 4, p.size.x, p.size.y - 6, Color(0, 0, 0, 0.3))
	c.rect(p.position.x, p.position.y + 10, p.size.x, p.size.y - 12, body)
	c.rect(p.position.x, p.position.y + 10, p.size.x, 1, body.lightened(0.35))
	# the handset
	c.rect(p.position.x + 4, p.position.y + 2, p.size.x - 8, 9, Color("#2a2e33"))
	c.rect(p.position.x + 4, p.position.y + 2, p.size.x - 8, 1, Color("#565c66"))
	c.rect(p.position.x + 2, p.position.y + 4, 8, 8, Color("#2a2e33"))
	c.rect(p.end.x - 10, p.position.y + 4, 8, 8, Color("#2a2e33"))
	# keypad and a little LCD
	for row in 4:
		for col in 3:
			_key(c, p.position.x + 30 + col * 9, p.position.y + 15 + row * 6, 6, Color("#4a4f58"))
	c.rect(p.position.x + 5, p.position.y + 15, 20, 7, Pal.LED_BG)
	c.rect(p.position.x + 7, p.position.y + 18, 12, 1, Pal.LED.darkened(0.3))
	c.px(p.position.x + 7, p.position.y + 27, Pal.BAD)
	# the coiled cord drops off the desk
	for n in 9:
		c.px(p.position.x - 2 - (n % 2), p.position.y + 14 + n * 3, Color("#15171a"))
		c.px(p.position.x - 3 + (n % 2), p.position.y + 15 + n * 3, Color("#2f333a"))


## A white mug of coffee.
static func _mug(c: PixelCanvas) -> void:
	var m := MUG
	c.ellipse(m.get_center().x + 2, m.end.y, 12, 3, Color(0, 0, 0, 0.3))
	c.rect(m.position.x, m.position.y + 3, m.size.x, m.size.y - 3, Color("#e6dfd2"))
	c.rect(m.position.x, m.position.y + 3, 2, m.size.y - 3, Color("#fff8ec"))
	c.rect(m.end.x - 3, m.position.y + 3, 3, m.size.y - 3, Color("#b8b0a2"))
	c.ellipse(m.get_center().x, m.position.y + 3, m.size.x / 2.0, 2.5, Color("#c8c0b2"))
	c.ellipse(m.get_center().x, m.position.y + 3, m.size.x / 2.0 - 2, 1.5, Color("#3a2010"))
	# handle and a gold stripe
	c.rect(m.end.x, m.position.y + 8, 4, 2, Color("#d6cfc2"))
	c.rect(m.end.x + 3, m.position.y + 9, 2, 8, Color("#d6cfc2"))
	c.rect(m.end.x, m.position.y + 16, 4, 2, Color("#b8b0a2"))
	c.rect(m.position.x, m.position.y + 12, m.size.x, 2, Pal.metal("gold", 3))


## A one-kilo gold bar used as a paperweight.
static func _gold_bar(c: PixelCanvas) -> void:
	var b := BAR
	c.rect(b.position.x + 2, b.position.y + 2, b.size.x, b.size.y, Color(0, 0, 0, 0.35))
	c.rect(b.position.x, b.position.y + 2, b.size.x, b.size.y - 2, Pal.metal("gold", 2))
	c.rect(b.position.x + 2, b.position.y, b.size.x - 4, 3, Pal.metal("gold", 4))
	c.rect(b.position.x + 2, b.position.y, b.size.x - 4, 1, Pal.metal("gold", 5))
	c.rect(b.position.x + 8, b.position.y + 4, b.size.x - 16, 2, Pal.metal("gold", 3))
	c.rect(b.end.x - 2, b.position.y + 2, 2, b.size.y - 2, Pal.metal("gold", 1))
