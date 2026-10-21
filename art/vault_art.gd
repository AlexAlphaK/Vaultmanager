class_name VaultArt
extends RefCounted
## The back room at closing time: steel-plated wall, the counter tray, a wall safe and a
## floor safe, plus every piece of stock that goes into them. Painted at load time.

const CELL := 16
const SIZE := Vector2i(316, 270)
## Top-left pixel of each area's grid in the room, for the starting safe sizes.
const ORIGINS := {"tray": Vector2i(10, 36), "wall": Vector2i(186, 42), "floor": Vector2i(174, 150)}

const STEEL := [Color("#1c1f24"), Color("#2f343c"), Color("#3f454f"), Color("#59606b"), Color("#7d8591"), Color("#b3bcc8")]
const INSIDE := Color("#121418")
const INSIDE_LINE := Color("#1d2026")


## The room with the safe doors standing open, or with no doors when `open` is false
## (the closed doors are drawn on top with paint_door).
## Top-left pixel of an area's grid. A wider floor safe grows to the left.
static func origin(area: String, grid: Vector2i) -> Vector2i:
	var o: Vector2i = ORIGINS[area]
	if area == "floor":
		o.x -= (grid.x - 5) * CELL
	return o


static func paint_room(areas: Dictionary, open := true) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	_wall(c)
	_floor(c)
	_tray(c, areas.tray.size)
	_wall_safe(c, areas.wall.size, open)
	_floor_safe(c, areas.floor.size, open)
	return c


## A closed door covering an area's grid, drawn over the safe once it is locked.
static func paint_door(area: String, grid: Vector2i) -> PixelCanvas:
	var w := grid.x * CELL + 4
	var h := grid.y * CELL + 4
	var c := PixelCanvas.new(w, h)
	c.rect(0, 0, w, h, STEEL[3])
	c.rect(0, 0, w, 1, STEEL[4])
	c.rect(0, 0, 1, h, STEEL[4])
	c.rect(0, h - 1, w, 1, STEEL[1])
	c.rect(w - 1, 0, 1, h, STEEL[1])
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			if ShopArt._noise(x * 3, y) > 0.9:
				c.px(x, y, STEEL[2])
	var r := 9.0 if area == "floor" else 6.0
	_dial(c, w / 2.0, h / 2.0, r)
	if area == "floor":
		_handle(c, w / 2.0 + r + 8.0, h / 2.0)
	return c


static func paint_piece(kind: String) -> PixelCanvas:
	var fp := VaultLayout.footprint(kind, 0)
	var c := PixelCanvas.new(fp.x * CELL, fp.y * CELL)
	match kind:
		"tube":
			_tube(c)
		"monster":
			_monster(c)
		"gold_box":
			_coin_box(c, Color("#1a1210"), "gold")
		"plat_box":
			_coin_box(c, Color("#141a2c"), "plat")
		"cash":
			for cell in VaultLayout.SHAPES.cash:
				_cash_strap(c, cell.x * CELL, cell.y * CELL)
		"ledger":
			_ledger(c)
	return c


## Rotates painted art clockwise `rot` quarter turns.
static func rotated(art: PixelCanvas, rot: int) -> PixelCanvas:
	var img := art.image.duplicate() as Image
	for n in posmod(rot, 4):
		img.rotate_90(CLOCKWISE)
	var out := PixelCanvas.new(img.get_width(), img.get_height())
	out.image = img
	return out


# ---------------------------------------------------------------- room

static func _wall(c: PixelCanvas) -> void:
	for y in SIZE.y:
		for x in SIZE.x:
			var px := x % 52
			var py := y % 40
			var col: Color = STEEL[2] if ShopArt._noise(x / 3, y) > 0.12 else Color("#3a4049")
			if px == 0 or py == 0:
				col = STEEL[1]
			elif px == 1 or py == 1:
				col = STEEL[3]
			elif (px == 4 or px == 47) and (py == 4 or py == 35):
				col = STEEL[4] # rivets
			elif (px == 5 or px == 48) and (py == 5 or py == 36):
				col = STEEL[1]
			c.px(x, y, col)
	# a warning stripe under the ceiling and the alarm box
	for x in SIZE.x:
		for y in range(16, 20):
			c.px(x, y, Color("#d9a53a") if posmod(x - y, 8) < 4 else Color("#22262c"))
	c.rect(282, 26, 20, 14, Color("#22262c"))
	c.rect(283, 27, 18, 12, Color("#8e2a20"))
	c.rect(283, 27, 18, 1, Color("#c0392b"))
	c.disc(292, 33, 3, Color("#e66b5c"))
	c.px(291, 32, Color("#ffd8d0"))


static func _floor(c: PixelCanvas) -> void:
	for y in range(236, SIZE.y):
		for x in SIZE.x:
			var n := ShopArt._noise(x, y)
			var col := Color("#2a2724") if n > 0.1 else Color("#24211e")
			if y == 236:
				col = Color("#141210")
			elif n > 0.95:
				col = Color("#35312c")
			c.px(x, y, col)


static func _tray(c: PixelCanvas, grid: Vector2i) -> void:
	var o := origin("tray", grid)
	var w := grid.x * CELL
	var h := grid.y * CELL
	c.text("COUNTER TRAY", o.x, o.y - 12, Color("#c6ccd4"))
	c.rect(o.x - 4, o.y - 3, w + 10, h + 9, Color(0, 0, 0, 0.35))
	c.rect(o.x - 5, o.y - 5, w + 10, h + 10, ShopArt.WOOD.left)
	c.rect(o.x - 5, o.y - 5, w + 10, 1, ShopArt.WOOD.edge)
	c.rect(o.x - 5, o.y - 5, 1, h + 10, ShopArt.WOOD.edge)
	c.rect(o.x - 3, o.y - 3, w + 6, h + 6, ShopArt.WOOD.top)
	for y in h:
		for x in w:
			var col := Color("#5a1e22") if ShopArt._noise(o.x + x, o.y + y) > 0.12 else Color("#4e1a1e")
			if x % CELL == 0 or y % CELL == 0:
				col = Color("#4a181c")
			c.px(o.x + x, o.y + y, col)


static func _wall_safe(c: PixelCanvas, grid: Vector2i, open: bool) -> void:
	var o := origin("wall", grid)
	var w := grid.x * CELL
	var h := grid.y * CELL
	_safe_body(c, Rect2i(o.x - 8, o.y - 8, w + 16, h + 16))
	_interior(c, o, grid)
	c.text("WALL SAFE", o.x + w / 2 - PixelFont.measure("WALL SAFE") / 2, o.y + h + 11, Color("#c6ccd4"))
	if not open:
		return
	# door swung open to the left, seen nearly edge-on
	var dx := o.x - 8 - 22
	for y in range(o.y - 10, o.y + h + 10):
		c.rect(dx, y, 20, 1, STEEL[4] if y == o.y - 10 else STEEL[3])
		c.px(dx, y, STEEL[4])
		c.px(dx + 19, y, STEEL[1])
		c.rect(dx + 16, y, 3, 1, STEEL[2]) # door thickness
	_dial(c, dx + 9, o.y + h / 2.0, 5.0)


static func _floor_safe(c: PixelCanvas, grid: Vector2i, open: bool) -> void:
	var o := origin("floor", grid)
	var w := grid.x * CELL
	var h := grid.y * CELL
	var body := Rect2i(o.x - 12, o.y - 12, w + 24, h + 50)
	c.rect(body.position.x + 3, body.end.y - 2, body.size.x, 4, Color(0, 0, 0, 0.4))
	_safe_body(c, body)
	_interior(c, o, grid)
	# a drawer with a brass name plate under the compartment
	var dy := o.y + h + 8
	c.rect(o.x, dy, w, 22, STEEL[2])
	c.rect(o.x, dy, w, 1, STEEL[1])
	c.rect(o.x, dy + 21, w, 1, STEEL[4])
	var plate := Rect2i(o.x + w / 2 - 28, dy + 7, 56, 9)
	c.rect(plate.position.x, plate.position.y, plate.size.x, plate.size.y, Pal.metal("brass", 3))
	c.rect(plate.position.x, plate.position.y, plate.size.x, 1, Pal.metal("brass", 5))
	c.rect(plate.position.x, plate.end.y - 1, plate.size.x, 1, Pal.metal("brass", 1))
	c.text("FLOOR SAFE", plate.position.x + 28 - PixelFont.measure("FLOOR SAFE") / 2, plate.position.y + 2, Pal.metal("brass", 0))
	# feet
	for fx in [body.position.x + 4, body.end.x - 14]:
		c.rect(fx, body.end.y, 10, 3, STEEL[0])
	if not open:
		return
	# the heavy door stands open to the right
	var dx := body.end.x + 2
	var dtop := body.position.y + 4
	var dh := body.size.y - 8
	for y in range(dtop, dtop + dh):
		c.rect(dx, y, 34, 1, STEEL[3])
		c.px(dx, y, STEEL[4])
		c.rect(dx + 28, y, 6, 1, STEEL[1]) # door thickness
		c.px(dx + 27, y, STEEL[4])
	c.rect(dx, dtop, 34, 1, STEEL[4])
	c.rect(dx, dtop + dh - 1, 34, 1, STEEL[0])
	for k in 6: # bolts sticking out of the door edge
		c.rect(dx + 34, dtop + 8 + k * ((dh - 16) / 5), 3, 4, STEEL[5])
	_dial(c, dx + 14, dtop + dh / 2.0 - 12, 8.0)
	_handle(c, dx + 14, dtop + dh / 2.0 + 14)


static func _safe_body(c: PixelCanvas, r: Rect2i) -> void:
	c.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#4c535e"))
	c.rect(r.position.x, r.position.y, r.size.x, 1, STEEL[5])
	c.rect(r.position.x, r.position.y, 1, r.size.y, STEEL[4])
	c.rect(r.position.x, r.end.y - 1, r.size.x, 1, STEEL[0])
	c.rect(r.end.x - 1, r.position.y, 1, r.size.y, STEEL[1])
	for k in [Vector2i(3, 3), Vector2i(r.size.x - 4, 3), Vector2i(3, r.size.y - 4), Vector2i(r.size.x - 4, r.size.y - 4)]:
		c.px(r.position.x + k.x, r.position.y + k.y, STEEL[5])


static func _interior(c: PixelCanvas, o: Vector2i, grid: Vector2i) -> void:
	var w := grid.x * CELL
	var h := grid.y * CELL
	c.rect(o.x - 2, o.y - 2, w + 4, h + 4, STEEL[0])
	c.rect(o.x - 2, o.y + h + 1, w + 4, 1, STEEL[4])
	for y in h:
		for x in w:
			var col := INSIDE
			if x % CELL == 0 or y % CELL == 0:
				col = INSIDE_LINE
			if y < 3:
				col = col.darkened(0.4) # shadow under the top lip
			c.px(o.x + x, o.y + y, col)


static func _dial(c: PixelCanvas, cx: float, cy: float, r: float) -> void:
	c.disc(cx, cy, r + 1.0, STEEL[0])
	c.disc(cx, cy, r, Pal.metal("gold", 2))
	c.disc(cx - 0.5, cy - 0.5, r - 1.0, Pal.metal("gold", 4))
	c.disc(cx, cy, r - 2.5, Pal.metal("gold", 3))
	for k in 10:
		var a := k * TAU / 10.0
		c.px(roundi(cx + cos(a) * (r - 1.5)), roundi(cy + sin(a) * (r - 1.5)), Pal.metal("gold", 1))
	c.px(roundi(cx), roundi(cy - r + 1.0), Pal.BAD)


static func _handle(c: PixelCanvas, cx: float, cy: float) -> void:
	for k in 3:
		var a := k * TAU / 3.0 - PI / 2.0
		c.line(Vector2(cx, cy), Vector2(cx + cos(a) * 8.0, cy + sin(a) * 8.0), STEEL[5])
		c.disc(cx + cos(a) * 8.0, cy + sin(a) * 8.0, 1.6, Pal.metal("gold", 4))
	c.disc(cx, cy, 2.0, STEEL[4])


# ---------------------------------------------------------------- pieces

## A clear coin tube with a blue screw cap; the coin edges show through.
static func _tube(c: PixelCanvas) -> void:
	var w := c.width
	c.rect(2, 4, w - 3, 10, Color(0, 0, 0, 0.3))
	c.rect(1, 3, w - 8, 10, Pal.metal("silver", 2))
	for x in range(2, w - 8):
		var ridge := 2 if x % 3 == 0 else (3 if x % 3 == 1 else 4)
		c.rect(x, 4, 1, 8, Pal.metal("silver", ridge))
	c.rect(1, 3, w - 8, 1, Color(1, 1, 1, 0.7))
	c.rect(1, 5, w - 8, 1, Color(1, 1, 1, 0.35))
	c.rect(1, 12, w - 8, 1, Pal.metal("silver", 1))
	c.rect(w - 8, 2, 7, 12, Color("#2c6fb0"))
	c.rect(w - 8, 2, 7, 1, Color("#6aa8e0"))
	c.rect(w - 8, 13, 7, 1, Color("#1a4270"))
	for y in range(4, 12, 2):
		c.px(w - 2, y, Color("#1a4270"))


## A green mint box with a strap and a white label.
static func _monster(c: PixelCanvas) -> void:
	var w := c.width
	var h := c.height
	c.rect(1, 1, w - 2, h - 2, Color("#2f7a3e"))
	c.rect(1, 1, w - 2, 1, Color("#5fb070"))
	c.rect(1, 1, 1, h - 2, Color("#4a9a5a"))
	c.rect(1, h - 2, w - 2, 1, Color("#1a4a24"))
	c.rect(w - 2, 1, 1, h - 2, Color("#1f5a2c"))
	c.rect(1, 6, w - 2, 1, Color("#1f5a2c")) # lid seam
	c.rect(w / 2 - 2, 1, 4, h - 2, Color("#1a1a1a"))
	c.rect(w / 2 - 2, 1, 1, h - 2, Color("#3a3a3a"))
	c.rect(5, 12, 22, 11, Color("#e8e2d0"))
	c.text("500", 7, 14, Color("#1f5a2c"))
	c.text("AG", 19, 14, Color("#5a6275"))


## A velvet presentation box holding coins in round capsules.
static func _coin_box(c: PixelCanvas, velvet: Color, metal: String) -> void:
	var w := c.width
	c.rect(1, 1, w - 2, 14, Color("#3a2a1a"))
	c.rect(1, 1, w - 2, 1, Color("#6e4a2a"))
	c.rect(2, 2, w - 4, 12, velvet)
	for k in 3:
		var cx := 6.5 + k * 9.5
		c.disc(cx, 8.0, 4.0, Color(1, 1, 1, 0.25))
		c.disc(cx, 8.0, 3.2, Pal.metal(metal, 3))
		c.disc(cx - 0.6, 7.4, 2.0, Pal.metal(metal, 4))
		c.px(roundi(cx) - 2, 6, Pal.metal(metal, 5))
		c.px(roundi(cx) + 1, 10, Pal.metal(metal, 1))


## A 16x16 brick of banknotes with a paper band.
static func _cash_strap(c: PixelCanvas, x: int, y: int) -> void:
	c.rect(x + 1, y + 2, 14, 12, Color("#4e7a46"))
	for row in range(3, 13, 2):
		c.rect(x + 1, y + row, 14, 1, Color("#7fa66a"))
	c.rect(x + 1, y + 2, 14, 1, Color("#a6c98e"))
	c.rect(x + 1, y + 13, 14, 1, Color("#2f4a2a"))
	c.rect(x + 6, y + 1, 4, 14, Color("#e8d9a8"))
	c.rect(x + 6, y + 1, 4, 1, Color("#fff4d8"))
	c.rect(x + 9, y + 1, 1, 14, Color("#b8a878"))
	c.px(x + 7, y + 7, Color("#7a5a20"))
	c.px(x + 8, y + 8, Color("#7a5a20"))


## A leather-bound ledger with a gold band; the page edges face right.
static func _ledger(c: PixelCanvas) -> void:
	var h := c.height
	c.rect(2, 1, 12, h - 2, Color("#6e2f1e"))
	c.rect(2, 1, 12, 1, Color("#9a4a32"))
	c.rect(2, 1, 1, h - 2, Color("#9a4a32"))
	c.rect(12, 2, 2, h - 4, Color("#efe6cc"))
	for y in range(3, h - 3, 2):
		c.px(13, y, Color("#c8bc98"))
	c.rect(3, 6, 9, 3, Pal.metal("gold", 3))
	c.rect(3, 6, 9, 1, Pal.metal("gold", 4))
	c.rect(3, h - 9, 9, 1, Pal.metal("gold", 2))
	c.rect(2, h - 2, 12, 1, Color("#3a1810"))
