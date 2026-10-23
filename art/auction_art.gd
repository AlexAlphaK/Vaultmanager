class_name AuctionArt
extends RefCounted
## The Ashworth & Finch saleroom, seen from a seat in the back row: damask walls over
## walnut panelling, a herringbone parquet floor, the bid board, an oil landscape and a
## portrait of old Mr. Ashworth in gilt frames, the chandelier, the rostrum, and the lot
## plinth under its spotlight. In front of you, the backs of the other bidders on gilt
## chairs. Also the bidders and the auctioneer, the coins and sealed pouches on the
## viewing tray, and your paddle. The board's figures, the paddles, the gavel, the
## spotlight and the lot on the plinth are drawn live by AuctionRoom.

const W := 316
const H := 270
const WAINSCOT_Y := 96
const FLOOR_Y := 124
## The bid board on the wall: the lot, the bid and who holds it.
const BOARD := Rect2i(8, 14, 98, 56)
const BOARD_GLASS := Rect2i(13, 19, 88, 46)
const SIGN := Rect2i(124, 2, 104, 13)
const PORTRAIT := Rect2i(118, 22, 26, 34)
const LANDSCAPE := Rect2i(238, 16, 68, 46)
const CHANDELIER := Vector2(186, 0)
const ROSTRUM := Rect2i(160, 70, 64, 62)
## Where the auctioneer's figure stands: the top left of his canvas.
const AUCTIONEER_AT := Vector2(168, 30)
const AUCTIONEER_SIZE := Vector2i(48, 44)
const PLINTH := Rect2i(48, 92, 64, 44)
## The top of the plinth, where the lot sits.
const PLINTH_TOP := Vector2(80, 98)
## The bidders' seats: the middle of each chair, left to right.
const SEATS := [30, 88, 146, 204, 262]
const SEAT_Y := 150
const BIDDER_SIZE := Vector2i(56, 78)
const CHAIR_TOP := 206
## Your paddle, at rest and raised.
const PADDLE_REST := Vector2(296, 228)
const PADDLE_UP := Vector2(296, 150)
## The viewing tray over the room before the sale.
const TRAY := Rect2i(10, 26, 296, 214)
const OUTLINE := Color("#1a1410")
const GILT: Array[Color] = [Color("#4a3410"), Color("#8a6420"), Color("#c8963a"), Color("#f0cc6a"), Color("#fff0b0")]
const VELVET := Color("#7a1a26")
const PAPER := Color("#efe6d0")


static func paint() -> PixelCanvas:
	var c := PixelCanvas.new(W, H, Color("#2a1416"))
	_wall(c)
	_wainscot(c)
	_floor(c)
	_sign(c)
	_board_frame(c)
	_portrait(c)
	_landscape(c)
	_sconces(c)
	_plinth(c)
	_rostrum(c)
	BenchArt.lamp_light(c, Vector2(176, 70), 330.0)
	return c


# ---------------------------------------------------------------- the room

## Burgundy damask: a repeating medallion in two tones, with a picture rail.
static func _wall(c: PixelCanvas) -> void:
	var base := Color("#5a1e26")
	var hi := Color("#6e2a32")
	var lo := Color("#4a161e")
	for y in WAINSCOT_Y:
		for x in W:
			# a lozenge medallion every 16 x 20 pixels, the rows offset by half
			var row := y / 20
			var u := posmod(x + (8 if row % 2 else 0), 16) - 8
			var v := posmod(y, 20) - 10
			var d := absf(u) / 8.0 + absf(v) / 10.0
			var col := base
			if d < 0.35:
				col = hi
			elif d < 0.5 and (u + v) % 2 == 0:
				col = hi
			elif d > 0.92 and d < 1.0:
				col = lo
			# a fleur in the middle of the medallion
			if absi(u) <= 1 and v >= -6 and v <= -2:
				col = lo
			if ShopArt._noise(x, y) > 0.96:
				col = col.lightened(0.05)
			c.px(x, y, col)
	# the picture rail, brass
	c.rect(0, 10, W, 1, GILT[3])
	c.rect(0, 11, W, 1, GILT[1])


## Walnut panelling: raised panels between stiles, a moulded chair rail on top.
static func _wainscot(c: PixelCanvas) -> void:
	var wood := Color("#3e2414")
	for y in range(WAINSCOT_Y, FLOOR_Y):
		for x in W:
			var col := wood
			var grain := ShopArt._noise(x / 3, y)
			if grain > 0.8:
				col = col.lightened(0.06)
			elif grain < 0.15:
				col = col.darkened(0.08)
			c.px(x, y, col)
	for p in range(0, W, 40):
		var r := Rect2i(p + 5, WAINSCOT_Y + 6, 30, FLOOR_Y - WAINSCOT_Y - 11)
		c.rect(r.position.x, r.position.y, r.size.x, 1, Color("#5a3820"))
		c.rect(r.position.x, r.position.y, 1, r.size.y, Color("#5a3820"))
		c.rect(r.position.x, r.end.y - 1, r.size.x, 1, Color("#24140a"))
		c.rect(r.end.x - 1, r.position.y, 1, r.size.y, Color("#24140a"))
		c.rect(r.position.x + 3, r.position.y + 3, r.size.x - 6, r.size.y - 6, Color("#46291a"))
	c.rect(0, WAINSCOT_Y, W, 2, Color("#6a4226"))
	c.rect(0, WAINSCOT_Y, W, 1, Color("#8a5a34"))
	c.rect(0, WAINSCOT_Y + 2, W, 1, Color("#24140a"))
	# the skirting board
	c.rect(0, FLOOR_Y - 3, W, 3, Color("#2a180c"))
	c.rect(0, FLOOR_Y - 3, W, 1, Color("#5a3820"))


## Herringbone parquet in three oak tones, polished: lighter where the room's light falls.
static func _floor(c: PixelCanvas) -> void:
	var tones: Array[Color] = [Color("#7a4c28"), Color("#87572e"), Color("#6c4222")]
	for y in range(FLOOR_Y, H):
		for x in W:
			# blocks 12 x 4 laid at 45 degrees, alternating direction each column
			var col_n := x / 12
			var flip := col_n % 2 == 0
			var sx := posmod(x, 12)
			var sy := y + (sx if flip else 11 - sx)
			var block := sy / 4
			var col: Color = tones[posmod(block * 5 + col_n * 3, 3)]
			if posmod(sy, 4) == 0:
				col = col.darkened(0.25)
			elif sx == 0:
				col = col.darkened(0.18)
			elif ShopArt._noise(x, y / 2) > 0.9:
				col = col.lightened(0.06)
			# the polish catches the chandelier
			var sheen := 1.0 - Vector2((x - 186.0) / 120.0, (y - FLOOR_Y) / 40.0).length()
			if sheen > 0.0:
				col = col.lightened(0.1 * sheen)
			c.px(x, y, col)


## A gilt sign over the rostrum with the house's name.
static func _sign(c: PixelCanvas) -> void:
	var r := SIGN
	c.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#1c1210"))
	_gilt_frame(c, r, 1)
	var text := "ASHWORTH & FINCH"
	var tx := r.position.x + (r.size.x - PixelFont.measure(text)) / 2
	PixelFont.plot_text(text, func(x, y):
		c.px(tx + x + 1, r.position.y + 4 + y, Color("#0a0604"))
		c.px(tx + x, r.position.y + 3 + y, GILT[3] if y < 3 else GILT[2]))


## A carved gilt frame `width` pixels deep round `r`, lit from the top left.
static func _gilt_frame(c: PixelCanvas, r: Rect2i, width := 3) -> void:
	for k in width:
		var o := r.grow(-k) if k > 0 else r
		var lit: Color = GILT[3] if k == 0 else (GILT[2] if k < width - 1 else GILT[1])
		var dark: Color = GILT[1] if k == 0 else GILT[0]
		c.rect(o.position.x, o.position.y, o.size.x, 1, lit)
		c.rect(o.position.x, o.position.y, 1, o.size.y, lit)
		c.rect(o.position.x, o.end.y - 1, o.size.x, 1, dark)
		c.rect(o.end.x - 1, o.position.y, 1, o.size.y, dark)
	# beading along the top and the corners' rosettes
	for x in range(r.position.x + 2, r.end.x - 2, 3):
		c.px(x, r.position.y + 1, GILT[4])
	for p in [r.position, Vector2i(r.end.x - 2, r.position.y), Vector2i(r.position.x, r.end.y - 2), r.end - Vector2i(2, 2)]:
		c.rect(p.x, p.y, 2, 2, GILT[4])


## The bid board's black lacquer case; the figures are lit live.
static func _board_frame(c: PixelCanvas) -> void:
	var r := BOARD
	c.rect(r.position.x + 2, r.position.y + 3, r.size.x, r.size.y, Color(0, 0, 0, 0.35))
	c.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#16110e"))
	_gilt_frame(c, r, 2)
	var g := BOARD_GLASS
	c.rect(g.position.x - 1, g.position.y - 1, g.size.x + 2, g.size.y + 2, Color("#050404"))
	c.rect(g.position.x, g.position.y, g.size.x, g.size.y, Color("#0c0a08"))
	# the unlit dot matrix
	for y in range(g.position.y + 1, g.end.y - 1, 2):
		for x in range(g.position.x + 1, g.end.x - 1, 2):
			c.px(x, y, Color("#1e1610"))
	# rows of cable down to the skirting
	c.rect(r.position.x + r.size.x / 2, r.end.y, 1, WAINSCOT_Y - r.end.y, Color("#1a0e10"))


## Old Mr. Ashworth in oils: grey whiskers, a dark coat, a dark ground.
static func _portrait(c: PixelCanvas) -> void:
	var r := PORTRAIT
	c.rect(r.position.x + 2, r.position.y + 2, r.size.x, r.size.y, Color(0, 0, 0, 0.35))
	c.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#1e2418"))
	var inner := r.grow(-3)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var u := float(x - inner.position.x) / inner.size.x
			var v := float(y - inner.position.y) / inner.size.y
			var col := Color("#2a3020").lerp(Color("#3c3a24"), 1.0 - Vector2(u - 0.4, v - 0.3).length())
			var head := Vector2((u - 0.5) / 0.22, (v - 0.36) / 0.2).length()
			if v > 0.62:
				col = Color("#16141a") if absf(u - 0.5) > 0.06 or v > 0.75 else Color("#e8e0d0") # coat and stock
				if absf(u - 0.5) < 0.42 - (1.0 - v) * 0.3:
					col = col
				else:
					col = Color("#2a3020")
			elif head < 1.0:
				col = Color("#d8a880").lerp(Color("#a87050"), clampf(u - 0.35, 0.0, 1.0) * 1.6)
				if v > 0.42 and absf(u - 0.5) > 0.12:
					col = Color("#c8c4bc") # whiskers
				if v < 0.22:
					col = Color("#d0ccc4") # white hair
			if ShopArt._noise(x * 3, y * 3) > 0.9:
				col = col.lightened(0.05) # brush texture
			c.px(x, y, col)
	_gilt_frame(c, r, 3)


## A river landscape at sunset in a wide gilt frame.
static func _landscape(c: PixelCanvas) -> void:
	var r := LANDSCAPE
	c.rect(r.position.x + 2, r.position.y + 3, r.size.x, r.size.y, Color(0, 0, 0, 0.35))
	var inner := r.grow(-4)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var u := float(x - inner.position.x) / inner.size.x
			var v := float(y - inner.position.y) / inner.size.y
			var col := Color("#3a5a7a").lerp(Color("#e8a860"), clampf(v * 1.6, 0.0, 1.0))
			var hill := 0.52 + sin(u * 7.0) * 0.06 + sin(u * 17.0 + 1.0) * 0.02
			if v > hill:
				col = Color("#3a4a2a").lerp(Color("#24301c"), (v - hill) * 2.0)
			if v > 0.7 and v < 0.82 and absf(u - 0.55 - (v - 0.7) * 0.8) < 0.18:
				col = Color("#d89a58").lerp(Color("#5a7a9a"), (v - 0.7) * 6.0) # the river
			# a tree against the sky
			if absf(u - 0.22) < 0.015 and v > 0.3 and v < hill + 0.02:
				col = Color("#1a140c")
			if Vector2((u - 0.22) * 1.6, v - 0.3).length() < 0.11:
				col = Color("#1e2a16") if ShopArt._noise(x, y) > 0.3 else Color("#2c3a1e")
			# the sun going down
			if Vector2((u - 0.75) * 1.5, v - 0.42).length() < 0.06:
				col = Color("#fff0b0")
			if ShopArt._noise(x * 5, y * 3) > 0.92:
				col = col.lightened(0.07)
			c.px(x, y, col)
	_gilt_frame(c, r, 4)
	# a little brass plate under it
	c.rect(r.position.x + r.size.x / 2 - 8, r.end.y + 2, 16, 3, GILT[2])
	c.rect(r.position.x + r.size.x / 2 - 8, r.end.y + 2, 16, 1, GILT[3])


## Two brass wall sconces with candle bulbs either side of the rostrum.
static func _sconces(c: PixelCanvas) -> void:
	for x in [150, 232]:
		c.rect(x - 1, 52, 3, 10, GILT[1])
		c.rect(x - 4, 60, 9, 2, GILT[2])
		c.rect(x - 4, 60, 9, 1, GILT[3])
		for dx in [-3, 3]:
			c.rect(x + dx, 54, 1, 6, Color("#efe6d0"))
			c.px(x + dx, 53, Color("#ffe8a0"))
		# the glow on the damask
		for y in range(40, 70):
			for xx in range(x - 14, x + 15):
				var d := Vector2(xx - x, (y - 54) * 1.3).length()
				if d < 14.0 and BenchArt.BAYER[(y % 4) * 4 + xx % 4] < (1.0 - d / 14.0) * 0.6:
					c.px(xx, y, c.get_px(xx, y).lerp(Color("#ffcf80"), 0.18))


## The round lot plinth, draped in green velvet, with a brass turntable top.
static func _plinth(c: PixelCanvas) -> void:
	var r := PLINTH
	var cx := r.position.x + r.size.x / 2.0
	# a shadow on the floor
	c.ellipse(cx + 3, r.end.y + 1, r.size.x / 2.0 + 4, 5, Color(0, 0, 0, 0.35))
	# the drum: velvet in vertical folds
	for y in range(r.position.y + 6, r.end.y):
		for x in range(r.position.x, r.end.x):
			var u := (x - r.position.x) / float(r.size.x)
			var fold := sin(u * 22.0) * 0.5 + 0.5
			var col := Color("#1e4a32").lerp(Color("#2e6a48"), fold * 0.7 * (1.0 - u * 0.6))
			if u > 0.8:
				col = col.darkened(0.25)
			c.px(x, y, col)
	# the hem with a gold fringe
	for x in range(r.position.x, r.end.x):
		c.px(x, r.end.y - 2, GILT[2])
		if x % 2 == 0:
			c.px(x, r.end.y - 1, GILT[1])
	# the top: an ellipse of brass round black baize
	c.ellipse(cx, r.position.y + 6, r.size.x / 2.0, 6, GILT[1])
	c.ellipse(cx, r.position.y + 5, r.size.x / 2.0, 5.5, GILT[2])
	c.ellipse(cx, r.position.y + 5, r.size.x / 2.0 - 3, 4, Color("#14201a"))


## The auctioneer's rostrum: carved walnut, a brass plate and the sounding block.
static func _rostrum(c: PixelCanvas) -> void:
	var r := ROSTRUM
	c.rect(r.position.x + 4, r.end.y - 2, r.size.x, 6, Color(0, 0, 0, 0.3))
	var wood := Color("#4a2c18")
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var col := wood
			var g := ShopArt._noise(x / 2, y * 3)
			if g > 0.82:
				col = col.lightened(0.07)
			elif g < 0.12:
				col = col.darkened(0.1)
			if x - r.position.x < 2:
				col = col.lightened(0.12)
			elif r.end.x - x <= 3:
				col = col.darkened(0.25)
			c.px(x, y, col)
	# the top board overhangs the front
	c.rect(r.position.x - 3, r.position.y, r.size.x + 6, 5, Color("#5a3820"))
	c.rect(r.position.x - 3, r.position.y, r.size.x + 6, 1, Color("#8a5a34"))
	c.rect(r.position.x - 3, r.position.y + 5, r.size.x + 6, 1, Color("#24140a"))
	# a carved front panel with an arch
	var p := Rect2i(r.position.x + 8, r.position.y + 12, r.size.x - 16, r.size.y - 20)
	c.rect(p.position.x, p.position.y, p.size.x, p.size.y, Color("#3e2414"))
	c.rect(p.position.x, p.position.y, p.size.x, 1, Color("#24140a"))
	c.rect(p.position.x, p.position.y, 1, p.size.y, Color("#24140a"))
	c.rect(p.position.x, p.end.y - 1, p.size.x, 1, Color("#6a4226"))
	c.rect(p.end.x - 1, p.position.y, 1, p.size.y, Color("#6a4226"))
	# the house's crest: crossed gavels on a shield, in brass
	var sx := p.position.x + p.size.x / 2
	var sy := p.position.y + 8
	c.poly(PackedVector2Array([Vector2(sx - 8, sy), Vector2(sx + 9, sy), Vector2(sx + 9, sy + 10), Vector2(sx + 0.5, sy + 17), Vector2(sx - 8, sy + 10)]), GILT[1])
	c.poly(PackedVector2Array([Vector2(sx - 7, sy + 1), Vector2(sx + 8, sy + 1), Vector2(sx + 8, sy + 9), Vector2(sx + 0.5, sy + 15), Vector2(sx - 7, sy + 9)]), GILT[2])
	c.line(Vector2(sx - 5, sy + 3), Vector2(sx + 5, sy + 11), GILT[0])
	c.line(Vector2(sx + 5, sy + 3), Vector2(sx - 5, sy + 11), GILT[0])
	c.rect(sx - 6, sy + 2, 3, 2, GILT[0])
	c.rect(sx + 4, sy + 2, 3, 2, GILT[0])
	c.px(sx - 6, sy + 1, GILT[4])
	# the brass plate
	c.rect(p.position.x + 4, p.end.y - 9, p.size.x - 8, 5, GILT[2])
	c.rect(p.position.x + 4, p.end.y - 9, p.size.x - 8, 1, GILT[3])
	PixelFont.plot_text("A&F", func(x, y):
		if y % 2 == 0 or y > 3:
			return
		c.px(sx - 6 + x, p.end.y - 8 + y / 2 + 1, GILT[0]))
	# the sounding block on the top board
	c.rect(r.end.x - 18, r.position.y - 3, 12, 3, Color("#6a4226"))
	c.rect(r.end.x - 18, r.position.y - 3, 12, 1, Color("#a0703e"))


# ---------------------------------------------------------------- the chairs and the people

## The backs of the gilt chairs in the row in front of you, over the bidders. Transparent
## around them.
static func chairs() -> PixelCanvas:
	var c := PixelCanvas.new(W, H)
	for sx in SEATS:
		var r := Rect2i(sx - 22, CHAIR_TOP, 44, H - CHAIR_TOP + 4)
		# the frame: an arched top rail
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var u := (x - r.position.x) / float(r.size.x) - 0.5
				var arch := r.position.y + absf(u) * absf(u) * 22.0
				if y < arch:
					continue
				var edge := y < arch + 3 or absf(u) > 0.43
				var col: Color
				if edge:
					col = GILT[2] if u < 0.0 else GILT[1]
					if y < arch + 1:
						col = GILT[3]
					if ShopArt._noise(x, y) > 0.85:
						col = GILT[4] if u < 0.0 else GILT[2]
				else:
					# the velvet back, buttoned
					col = VELVET.lerp(Color("#9a2a36"), clampf(0.4 - u, 0.0, 1.0) * 0.6)
					var bx := posmod(x - r.position.x - 6, 10)
					var by := posmod(y - r.position.y - 9, 10)
					if (bx == 0 and by == 0) or (bx == 5 and by == 5):
						col = Color("#4a0e16")
					elif (bx == 1 and by == 1) or (bx == 6 and by == 6):
						col = col.lightened(0.15)
				c.px(x, y, col)
		# a carved finial at the top of the rail
		c.rect(sx - 2, CHAIR_TOP - 3, 5, 4, GILT[2])
		c.rect(sx - 1, CHAIR_TOP - 4, 3, 1, GILT[3])
		c.px(sx - 1, CHAIR_TOP - 3, GILT[4])
	return c


## Looks for the people in the room. Sterling: slicked silver hair, a charcoal suit. Lucky
## Lou: a flat cap and a loud checked jacket. Others from `seed`.
static func bidder_look(who: String, seed: int) -> Dictionary:
	match who:
		"sterling":
			return {"skin": "#e3b48a", "hair": "#c8ccd0", "style": 5, "jacket": "#33363d", "pattern": 3, "collar": "#f4f0e8"}
		"pawn":
			return {"skin": "#c98f62", "hair": "#2a1a10", "style": 4, "jacket": "#b8473a", "pattern": 1, "collar": "#e2cc8a", "cap": "#6b5a3a"}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jackets := ["#30406a", "#4a3a2a", "#2f5a4a", "#5a4a6a", "#6b5a40", "#3a3a3a", "#6a2a30"]
	return {"skin": PeopleArt.SKINS[rng.randi() % PeopleArt.SKINS.size()], "hair": PeopleArt.HAIRS[rng.randi() % PeopleArt.HAIRS.size()],
		"style": [0, 1, 2, 3, 6][rng.randi() % 5], "jacket": jackets[rng.randi() % jackets.size()],
		"pattern": 2 if who == "dealer" else rng.randi() % 3, "collar": "#f0ece4", "cap": ["#2a2a2a", "#5a4a30", "#6a2a30"][rng.randi() % 3]}


## A bidder from behind, head and shoulders. `turn` -1 or 1 turns the head a little
## (to look at a neighbour or shake it no).
static func bidder(look: Dictionary, turn := 0) -> PixelCanvas:
	var c := PixelCanvas.new(BIDDER_SIZE.x, BIDDER_SIZE.y)
	var skin := Color(look.skin)
	var hair := Color(look.hair)
	var jacket := Color(look.jacket)
	var cx := 28.0 + turn
	var style := int(look.style)
	# the shoulders and back of the jacket
	var back := PackedVector2Array([Vector2(13, 32), Vector2(43, 32), Vector2(53, 42), Vector2(55, 78), Vector2(1, 78), Vector2(3, 42)])
	c.poly(back, jacket)
	for y in range(30, BIDDER_SIZE.y):
		for x in BIDDER_SIZE.x:
			var col := c.get_px(x, y)
			if col.a == 0.0:
				continue
			var u := (x - 28.0) / 28.0
			col = jacket.lightened(0.12) if u < -0.55 else (jacket.darkened(0.22) if u > 0.5 else jacket)
			match int(look.pattern):
				1: # a loud check
					if x % 8 == 0 or y % 8 == 0:
						col = col.lerp(Color("#e8c84a"), 0.55)
					elif (x / 4 + y / 4) % 2 == 0:
						col = col.darkened(0.1)
				2: # tweed
					if ShopArt._noise(x, y) > 0.7:
						col = col.lightened(0.1)
					elif ShopArt._noise(x + 9, y) < 0.15:
						col = col.darkened(0.12)
				3: # a fine pinstripe
					if x % 5 == 0:
						col = col.lightened(0.14)
			# the centre seam and the folds under the arms
			if x == 28 and y > 40:
				col = col.darkened(0.2)
			if (x == 9 or x == 47) and y > 50:
				col = col.darkened(0.15)
			c.px(x, y, col)
	# the jacket's collar, the shirt collar above it, and the neck
	c.rect(roundi(cx) - 7, 26, 14, 6, skin.darkened(0.08))
	c.rect(roundi(cx) - 8, 29, 16, 3, Color(look.collar))
	c.rect(roundi(cx) - 9, 31, 18, 3, jacket.darkened(0.3))
	c.rect(roundi(cx) - 9, 31, 18, 1, jacket.lightened(0.1))
	# the head, from behind: ears and the back of the skull
	c.ellipse(cx, 16, 10, 12, skin)
	c.rect(roundi(cx) - 11 - turn, 14, 2, 6, skin.darkened(0.12))
	c.rect(roundi(cx) + 10 - turn, 14, 2, 6, skin.darkened(0.2))
	match style:
		0: # short
			c.ellipse(cx, 13, 10, 10, hair)
			c.rect(roundi(cx) - 8, 18, 17, 6, hair)
		1: # long, over the collar
			c.ellipse(cx, 14, 11, 11, hair)
			c.rect(roundi(cx) - 11, 16, 23, 17, hair)
		2: # bald with a fringe round the back
			c.rect(roundi(cx) - 10, 16, 21, 7, hair)
			c.px(roundi(cx) - 3, 7, skin.lightened(0.35))
			c.px(roundi(cx) - 2, 7, skin.lightened(0.25))
			c.px(roundi(cx) - 4, 8, skin.lightened(0.25))
		3: # a bun
			c.ellipse(cx, 14, 10.5, 11, hair)
			c.disc(cx, 6, 5, hair)
		4: # a flat cap
			c.ellipse(cx, 16, 10, 9, hair)
			c.ellipse(cx, 9, 12, 7, Color(look.get("cap", "#5a4a30")))
			c.rect(roundi(cx) - 12, 10, 25, 2, Color(look.get("cap", "#5a4a30")).darkened(0.25))
		5: # slicked back, comb lines
			c.ellipse(cx, 13, 10.5, 11, hair)
			c.rect(roundi(cx) - 9, 18, 19, 5, hair)
			for x in range(roundi(cx) - 8, roundi(cx) + 9, 3):
				c.line(Vector2(x, 5), Vector2(x, 21), hair.darkened(0.2))
		6: # a hat with a band
			c.ellipse(cx, 18, 10, 8, hair)
			c.rect(roundi(cx) - 9, 1, 19, 10, Color(look.get("cap", "#2a2a2a")))
			c.rect(roundi(cx) - 9, 8, 19, 2, Color("#6a2a30"))
			c.rect(roundi(cx) - 14, 11, 29, 2, Color(look.get("cap", "#2a2a2a")).darkened(0.2))
	# hair shine on the lit side
	if style != 2:
		for y in range(4, 12):
			var x := roundi(cx) - 6 + (y - 4) / 3
			if c.get_px(x, y) == hair:
				c.px(x, y, hair.lightened(0.25))
	_shade_right(c, cx)
	_outline(c)
	return c


## The far side of a figure in shadow.
static func _shade_right(c: PixelCanvas, cx: float) -> void:
	for y in c.height:
		for x in range(roundi(cx) + 5, c.width):
			var col := c.get_px(x, y)
			if col.a > 0.0 and c.get_px(x + 3, y).a == 0.0:
				c.image.set_pixel(x, y, Color(col.darkened(0.18), col.a))


static func _outline(c: PixelCanvas) -> void:
	var src := c.image.duplicate()
	for y in c.height:
		for x in c.width:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + o
				if p.x >= 0 and p.y >= 0 and p.x < c.width and p.y < c.height and src.get_pixel(p.x, p.y).a > 0.0:
					c.image.set_pixel(x, y, OUTLINE)
					break


## The auctioneer behind the rostrum, waist up: grey fringe, half-moon glasses, a
## waxed moustache, a red bow tie, a tailcoat. `mouth` opens him mid-call.
static func auctioneer(mouth := false) -> PixelCanvas:
	var c := PixelCanvas.new(AUCTIONEER_SIZE.x, AUCTIONEER_SIZE.y)
	var skin := Color("#e8b890")
	var coat := Color("#1c1c24")
	c.poly(PackedVector2Array([Vector2(10, 24), Vector2(38, 24), Vector2(46, 32), Vector2(47, 44), Vector2(1, 44), Vector2(2, 32)]), coat)
	# shirt front, waistcoat and bow tie
	c.poly(PackedVector2Array([Vector2(18, 24), Vector2(30, 24), Vector2(27, 44), Vector2(21, 44)]), Color("#f4f0e8"))
	c.rect(19, 32, 10, 12, Color("#5a4a2a"))
	c.rect(23, 32, 2, 12, Color("#f4f0e8"))
	for y in [35, 39, 43]:
		c.px(21, y, GILT[3])
	c.poly(PackedVector2Array([Vector2(18, 24), Vector2(23, 26), Vector2(18, 29)]), Color("#b8202a"))
	c.poly(PackedVector2Array([Vector2(30, 24), Vector2(25, 26), Vector2(30, 29)]), Color("#b8202a"))
	c.rect(23, 25, 2, 2, Color("#8a1820"))
	# lapels
	c.line(Vector2(17, 25), Vector2(14, 38), Color("#3a3a46"))
	c.line(Vector2(31, 25), Vector2(34, 38), Color("#0e0e14"))
	# the head
	c.ellipse(24, 12, 9, 11, skin)
	c.rect(15, 11, 2, 5, skin.darkened(0.12))
	c.rect(32, 11, 2, 5, skin.darkened(0.15))
	c.rect(21, 22, 6, 3, skin.darkened(0.08))
	# a shiny dome with a grey fringe round the sides
	c.rect(15, 8, 3, 7, Color("#b8b8b8"))
	c.rect(31, 8, 3, 7, Color("#a0a0a0"))
	c.px(21, 3, skin.lightened(0.4))
	c.px(22, 3, skin.lightened(0.3))
	c.px(20, 4, skin.lightened(0.25))
	# eyebrows, half-moon glasses, nose
	c.rect(18, 9, 4, 1, Color("#9a9a9a"))
	c.rect(26, 9, 4, 1, Color("#9a9a9a"))
	c.rect(19, 11, 2, 1, Color("#2a1a10"))
	c.rect(27, 11, 2, 1, Color("#2a1a10"))
	c.rect(17, 12, 5, 1, GILT[2])
	c.rect(26, 12, 5, 1, GILT[2])
	c.rect(22, 12, 4, 1, GILT[1])
	c.rect(23, 12, 2, 4, skin.darkened(0.15))
	c.px(24, 15, skin.darkened(0.3))
	# the waxed moustache, curled at the tips
	c.rect(19, 17, 10, 2, Color("#b0b0b0"))
	c.px(18, 16, Color("#b0b0b0"))
	c.px(29, 16, Color("#b0b0b0"))
	c.px(17, 15, Color("#909090"))
	c.px(30, 15, Color("#909090"))
	if mouth:
		c.rect(22, 19, 4, 2, Color("#5a1a1a"))
	else:
		c.rect(22, 19, 4, 1, Color("#8a4a3a"))
	_shade_right(c, 24.0)
	_outline(c)
	return c


## A bidder's paddle: a white oval with the number in black.
static func paddle(number: int, big := false) -> PixelCanvas:
	var w := 26 if big else 16
	var h := 20 if big else 12
	var stick := 14 if big else 8
	var c := PixelCanvas.new(w + 2, h + stick + 2)
	c.ellipse(w / 2.0 + 1, h / 2.0 + 1, w / 2.0, h / 2.0, OUTLINE)
	c.ellipse(w / 2.0 + 1, h / 2.0 + 1, w / 2.0 - 1, h / 2.0 - 1, PAPER)
	c.ellipse(w / 2.0, h / 2.0, w / 2.0 - 3, h / 2.0 - 3, Color("#fffaf0"))
	var text := str(number)
	var scale := 2 if big else 1
	var tx := roundi((w + 2 - PixelFont.measure(text) * scale) / 2.0)
	var ty := roundi((h + 2 - 6 * scale) / 2.0)
	PixelFont.plot_text(text, func(x, y):
		c.rect(tx + x * scale, ty + y * scale, scale, scale, Color("#141414")))
	c.rect(w / 2, h + 1, 3, stick, Color("#6a4226"))
	c.rect(w / 2, h + 1, 1, stick, Color("#9a6a3e"))
	return c


## Your hand, holding the paddle's handle from below.
static func hand() -> PixelCanvas:
	var c := PixelCanvas.new(20, 22)
	var skin := Color("#e3b48a")
	c.ellipse(10, 7, 7, 6, skin)
	for k in 4:
		c.rect(4 + k * 3, 2, 3, 5, skin.lightened(0.05 if k % 2 == 0 else 0.0))
		c.px(4 + k * 3, 2, skin.darkened(0.15))
	c.rect(4, 11, 13, 11, Color("#30406a")) # the cuff of your jacket
	c.rect(4, 11, 13, 2, Color("#f0ece4"))
	_shade_right(c, 10.0)
	_outline(c)
	return c


# ---------------------------------------------------------------- the lots

## A coin for the viewing tray: metal ramps, a rim, a bead ring and the motif in low
## relief. Rare coins wear an old toning; brass copies are too yellow and rubbed.
static func coin(item: BullionItem, r: int, brass := false) -> PixelCanvas:
	var size := r * 2 + 3
	var c := PixelCanvas.new(size, size)
	var cx := size / 2.0
	var pal := "brass" if brass else item.palette_name()
	var inner := r - 3.0
	var height := CoinArt._device_heights(item.motif, cx, cx, inner * 1.15)
	var light := Vector2(-0.6, -0.8)
	for y in size:
		for x in size:
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cx
			var d := sqrt(dx * dx + dy * dy)
			if d > r + 0.3:
				continue
			var n := Vector2(dx, dy) / maxf(d, 0.001)
			var facing := -n.dot(light)
			var tone: int
			if d > r - 1.0:
				tone = 1 if facing < 0.2 else 3
			elif d > r - 2.2:
				tone = 4 if facing > -0.1 else 2
				if facing > 0.6:
					tone = 5
			else:
				var band := exp(-pow((dx + dy) / r + 0.3, 2.0) * 5.0)
				var v := 2.1 + band * 1.5
				tone = clampi(int(v + BenchArt.BAYER[(y % 4) * 4 + x % 4]), 1, 4)
				var h := CoinArt._h(height, x, y)
				if h > 0.4:
					var lit := CoinArt._h(height, x + 1, y + 1) - CoinArt._h(height, x - 1, y - 1)
					tone = 5 if lit > 0.15 else (3 if lit < -0.2 else 4)
				elif CoinArt._h(height, x - 1, y - 1) > 0.4:
					tone -= 1
				# the bead ring
				if absf(d - (r - 3.6)) < 0.6 and posmod(int(n.angle() * r), 3) == 0:
					tone = 5 if facing > 0.0 else 4
			var col := Pal.metal(pal, tone)
			if item.rare and not brass:
				# old toning: amber and blue rings in toward the rim, darker in the hollows
				var t := clampf((d / r - 0.55) * 2.2, 0.0, 1.0)
				var tint := Color("#b87a3a") if item.metal == "XAU" else (Color("#6a5a9a") if posmod(int(d), 3) == 0 else Color("#b8904a"))
				col = col.lerp(tint, t * 0.35).darkened(0.06)
			if brass and ShopArt._noise(x * 7, y * 5) > 0.88 and tone >= 4:
				col = Pal.metal("copper", 3) # the plating rubbed through on the high points
			c.px(x, y, col)
	return c


## Radius on the viewing tray of a coin, by its real size.
static func tray_radius(item: BullionItem) -> int:
	return clampi(roundi(item.diameter_mm * 0.42), 8, 15)


## A sealed velvet pouch with a drawstring and a paper tag, or opened and slumped.
static func pouch(seed: int, open := false) -> PixelCanvas:
	var c := PixelCanvas.new(34, 38)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cloth: Color = [Color("#2a2a6a"), Color("#6a1a2a"), Color("#2a4a2a"), Color("#4a2a5a")][rng.randi() % 4]
	if open:
		# slumped flat, the mouth gaping
		c.ellipse(17, 27, 15, 9, cloth)
		c.ellipse(17, 22, 10, 5, cloth.lightened(0.1))
		c.ellipse(17, 22, 7, 3, Color("#0c0808"))
		c.line(Vector2(6, 22), Vector2(2, 30), Color("#d8c8a0"))
	else:
		c.ellipse(17, 26, 14, 11, cloth)
		c.poly(PackedVector2Array([Vector2(11, 8), Vector2(23, 8), Vector2(26, 18), Vector2(8, 18)]), cloth)
		# gathered folds at the neck
		for x in range(11, 24, 3):
			c.line(Vector2(x, 9), Vector2(x - 1 + (x - 17) * 0.3, 18), cloth.darkened(0.25))
		c.ellipse(17, 8, 7, 2.5, cloth.lightened(0.15))
		# the drawstring, wound round and hanging with a tassel
		c.rect(10, 13, 15, 1, Color("#d8c8a0"))
		c.line(Vector2(24, 13), Vector2(28, 20), Color("#d8c8a0"))
		c.rect(27, 20, 3, 4, GILT[2])
	# the velvet's sheen, on the lit side
	for y in c.height:
		for x in c.width:
			var col := c.get_px(x, y)
			if col.a == 0.0 or col == Color("#0c0808") or col == Color("#d8c8a0"):
				continue
			var lit := Vector2(x - 10, y - 20).length()
			if lit < 7.0 and ShopArt._noise(x, y) > 0.35:
				c.px(x, y, col.lightened(0.18))
			elif x > 25:
				c.px(x, y, col.darkened(0.2))
	# a paper tag on a string
	c.line(Vector2(9, 13), Vector2(4, 17), Color("#d8c8a0"))
	c.rect(0, 17, 8, 6, PAPER)
	c.rect(0, 22, 8, 1, PAPER.darkened(0.2))
	c.px(2, 19, Color("#4a3a2a"))
	c.px(4, 19, Color("#4a3a2a"))
	c.px(3, 20, Color("#4a3a2a"))
	_outline(c)
	return c


## The viewing tray: green baize in a brass-bound walnut tray.
static func tray() -> PixelCanvas:
	var r := Rect2i(Vector2i.ZERO, TRAY.size)
	var c := PixelCanvas.new(r.size.x, r.size.y)
	c.rect(0, 0, r.size.x, r.size.y, Color("#3e2414"))
	c.rect(0, 0, r.size.x, 2, Color("#8a5a34"))
	c.rect(0, r.size.y - 2, r.size.x, 2, Color("#24140a"))
	BenchArt.felt(c, r.grow(-6), Color("#24503a"))
	_gilt_frame(c, r.grow(-4), 2)
	return c


## The lot on the plinth: an open walnut display box lined with cream silk, its coins
## in rows and its pouches beside them.
static func lot_mini(lot: Dictionary) -> PixelCanvas:
	var c := PixelCanvas.new(52, 24)
	# the lid standing open behind, then the box
	c.rect(8, 0, 36, 9, Color("#4a2c18"))
	c.rect(10, 1, 32, 7, Color("#e8dcc0"))
	c.rect(10, 1, 32, 1, Color("#fff4dc"))
	c.rect(6, 9, 40, 12, Color("#5a3820"))
	c.rect(6, 9, 40, 1, Color("#8a5a34"))
	c.rect(8, 10, 36, 9, Color("#e0d2b4"))
	c.rect(6, 20, 40, 2, Color("#3a2010"))
	var slots := 0
	for it in lot.items:
		if it.pouch and not it.seen:
			continue
		var coin: BullionItem = Shop.coins.get(it.coin)
		var pal := "brass" if it.junk else coin.palette_name()
		for n in mini(int(it.qty), 3):
			if slots >= 12:
				break
			var x := 10 + (slots % 6) * 6
			var y := 11 + (slots / 6) * 4
			c.rect(x, y, 5, 3, Pal.metal(pal, 3))
			c.rect(x + 1, y, 3, 1, Pal.metal(pal, 5))
			c.rect(x, y + 2, 5, 1, Pal.metal(pal, 1))
			slots += 1
	var px := 46
	for it in lot.items:
		if not it.pouch or it.seen:
			continue
		c.ellipse(px + 2, 19, 3, 3, Color("#2a2a6a"))
		c.rect(px + 1, 14, 3, 3, Color("#2a2a6a"))
		c.px(px + 1, 17, Color("#d8c8a0"))
		c.px(px + 2, 17, Color("#d8c8a0"))
		px -= 46 # the second pouch sits on the left of the box
	_outline(c)
	return c
