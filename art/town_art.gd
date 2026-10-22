class_name TownArt
extends RefCounted
## The town map: a crossroads seen from above in isometric, with your shop on the
## corner, Sterling Bullion across the street, Lucky's Pawn across the side street,
## a café, a laundromat and the little park. Your building grows with the shop's tier.
## The rivals' moves show on their fronts: a SALE banner in a price war, police tape
## and a patrol car after a raid, a dark van while the pawn shop is fencing.

const SIZE := Vector2i(170, 112)
const ORIGIN := Vector2(76, 30)
## Main Street runs along i, the side street along j (in tiles).
const MAIN_J := Vector2(1.8, 2.6)
const SIDE_I := Vector2(2.8, 3.6)
const EXTENT := Vector2(6.0, 4.4)
## Footprints [i, j, w, d] of the three shops, for the labels.
const PLOTS := {
	"you": [1.5, 0.35, 1.2, 1.3],
	"pawn": [3.75, 0.45, 1.15, 1.2],
	"sterling": [1.25, 2.75, 1.45, 1.35],
}
const OUTLINE := Color("#14100c")
const ASPHALT := Color("#3a3d44")
const KERB := Color("#8a8f99")
const PAVING := Color("#6b7079")
const GRASS := Color("#4a6a36")
const GLOW := Color("#ffd98a")

## `view` keys: tier (your shop's), ranks {id: place}, sterling_move, pawn_move, pawn_closed.
static func paint(view: Dictionary) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := Iso.new(c, ORIGIN)
	_ground(iso)
	_cafe(iso)
	_your_shop(iso, int(view.get("tier", 0)))
	_pawn(iso, str(view.get("pawn_move", "")), bool(view.get("pawn_closed", false)))
	_laundromat(iso)
	_lamps(iso)
	_sterling(iso, str(view.get("sterling_move", "")))
	_park(iso)
	if bool(view.get("pawn_closed", false)):
		_car(iso, 4.4, 2.2, Color("#e8edf3"), true)
	elif str(view.get("pawn_move", "")) == "fencing":
		_car(iso, 4.6, 2.2, Color("#24262c"), false)
	var ranks: Dictionary = view.get("ranks", {})
	_label(iso, "you", "YOU", Pal.GOLD, ranks)
	_label(iso, "sterling", "STERLING", Pal.INK, ranks)
	_label(iso, "pawn", "LUCKY'S", Pal.INK, ranks)
	return c


static func _ground(iso: Iso) -> void:
	iso.top(0, 0, EXTENT.x, EXTENT.y, 0, func(i, j):
		var on_main: bool = j >= MAIN_J.x and j < MAIN_J.y
		var on_side: bool = i >= SIDE_I.x and i < SIDE_I.y
		if on_main or on_side:
			# zebra crossings either side of the junction
			if on_main and not on_side and (absf(i - SIDE_I.x + 0.2) < 0.2 or absf(i - SIDE_I.y - 0.2) < 0.2):
				return Color("#d8d8d0") if fmod(j * 10.0, 2.0) < 1.0 else ASPHALT
			if on_side and not on_main and (absf(j - MAIN_J.x + 0.2) < 0.2 or absf(j - MAIN_J.y - 0.2) < 0.2):
				return Color("#d8d8d0") if fmod(i * 10.0, 2.0) < 1.0 else ASPHALT
			# a dashed centre line
			if on_main and not on_side and absf(j - (MAIN_J.x + MAIN_J.y) / 2.0) < 0.04 and fmod(i, 0.5) < 0.25:
				return Pal.WARN.darkened(0.15)
			if on_side and not on_main and absf(i - (SIDE_I.x + SIDE_I.y) / 2.0) < 0.04 and fmod(j, 0.5) < 0.25:
				return Pal.WARN.darkened(0.15)
			return ASPHALT if _noise(int(i * 24.0), int(j * 24.0)) > 0.1 else ASPHALT.lightened(0.08)
		var near := minf(minf(absf(j - MAIN_J.x), absf(j - MAIN_J.y)), minf(absf(i - SIDE_I.x), absf(i - SIDE_I.y)))
		if near < 0.06:
			return KERB
		if i > SIDE_I.y and j > MAIN_J.y and near > 0.3:
			return GRASS if _noise(int(i * 16.0), int(j * 16.0)) > 0.2 else GRASS.lightened(0.12)
		return PAVING if fmod(i * 3.0, 1.0) > 0.08 and fmod(j * 3.0, 1.0) > 0.08 else PAVING.darkened(0.15))


## A building: two visible walls with a pattern, a flat roof and a parapet.
## `front(i, z)` and `side(j, z)` return a colour or null for the plain wall.
static func _building(iso: Iso, i: float, j: float, w: float, d: float, h: float, wall: Color, roof: Color,
		front := Callable(), side := Callable()) -> void:
	iso.face_j(j + d, i, i + w, 0, h, func(a, z):
		var col = front.call(a, z) if front.is_valid() else null
		return col if col != null else (wall.darkened(0.25) if z < 1.0 else wall))
	iso.face_i(i + w, j, j + d, 0, h, func(b, z):
		var col = side.call(b, z) if side.is_valid() else null
		return col if col != null else (wall.lightened(0.08).darkened(0.25) if z < 1.0 else wall.lightened(0.08)))
	iso.top(i, j, i + w, j + d, h, func(a, b):
		var edge := minf(minf(a - i, i + w - a), minf(b - j, j + d - b))
		return roof.lightened(0.15) if edge < 0.07 else roof)
	iso.canvas.line(iso.p(i, j + d, h), iso.p(i + w, j + d, h), roof.lightened(0.3))
	iso.canvas.line(iso.p(i + w, j, h), iso.p(i + w, j + d, h), roof.lightened(0.3))


## Shop windows along a wall: lit glass between `z0` and `z1`, in bays of `bay` tiles.
static func _windows(t: float, z: float, z0: float, z1: float, bay: float, glass: Color, frame: Color):
	if z < z0 or z >= z1:
		return null
	var f := fmod(t, bay) / bay
	if f < 0.15 or f > 0.85:
		return frame
	if z < z0 + 0.8 or z > z1 - 0.8:
		return frame
	return glass.lightened(0.25) if fmod(t * 16.0 + z, 7.0) < 1.0 else glass


static func _cafe(iso: Iso) -> void:
	var wall := Color("#c9b48a")
	_building(iso, 0.15, 0.4, 1.1, 1.25, 12.0, wall, Color("#5a4a3a"), func(a, z):
		if z >= 7.0 and z < 9.0:
			return Color("#2f8f5a") if fmod(a * 8.0, 1.0) < 0.5 else Color("#e8e2d0") # striped awning
		return _windows(a, z, 1.0, 6.5, 0.55, Color("#e8c070"), Color("#5e3b1d")))


static func _your_shop(iso: Iso, tier: int) -> void:
	var p: Array = PLOTS.you
	var h := 14.0 + tier * 4.0
	var walls := [Color("#8a5a30"), Color("#9a4a34"), Color("#8e8a80"), Color("#d8d2c4")]
	var wall: Color = walls[clampi(tier, 0, 3)]
	var trim := Pal.GOLD if tier >= 2 else Color("#e8e2d0")
	var front := func(a, z):
		if z >= h - 2.0:
			return trim if z >= h - 1.0 else wall.darkened(0.15)
		if z >= 8.0 and z < 10.0:
			return Color("#8e342c") if fmod(a * 8.0, 1.0) < 0.5 else Color("#efe3c8")
		if absf(a - (p[0] + p[2] * 0.7)) < 0.14 and z < 7.0:
			return Color("#3a2410") if z < 6.0 else trim # the door
		var glass = _windows(a, z, 1.0, 7.0, 0.5, GLOW, Color("#3a2410"))
		if glass != null:
			return glass
		if tier >= 1 and z >= 11.0 and z < h - 2.0:
			return _windows(a + 0.1, z, 11.0, minf(h - 3.0, 15.0), 0.4, Color("#aad7eb").darkened(0.3), wall.darkened(0.2))
		return null
	var side := func(b, z):
		if z >= h - 2.0:
			return trim if z >= h - 1.0 else wall.darkened(0.1)
		return _windows(b, z, 1.0, 7.0, 0.65, GLOW, Color("#3a2410"))
	_building(iso, p[0], p[1], p[2], p[3], h, wall, Color("#4a3a2e"), front, side)
	if tier >= 3:
		# the landmark flies the gold flag
		var top := iso.p(p[0] + p[2] * 0.5, p[1] + p[3] * 0.5, h).round()
		iso.canvas.rect(int(top.x), int(top.y) - 10, 1, 10, Color("#c6ccd4"))
		iso.canvas.rect(int(top.x) + 1, int(top.y) - 10, 6, 4, Pal.GOLD)


static func _sterling(iso: Iso, move: String) -> void:
	var p: Array = PLOTS.sterling
	var h := 22.0
	var stone := Color("#9aa0a8")
	# its doors face the side street, so the columns are on the i wall
	var side := func(b, z):
		if z >= h - 3.0:
			return Pal.GOLD if z < h - 2.0 else stone.lightened(0.2)
		if move == "price_war" and z >= 12.0 and z < 16.0:
			return Pal.BAD if fmod(b * 6.0 + z * 0.2, 1.0) < 0.85 else Color("#ffffff") # the SALE banner
		var f := fmod(b - p[1], 0.34) / 0.34
		if f < 0.22:
			return stone.lightened(0.28) if z > 1.0 else stone # columns
		if z < 9.0 and z >= 1.0:
			return Color("#1c2026") if absf(b - (p[1] + p[3] * 0.5)) < 0.17 else Color("#aad7eb").darkened(0.35)
		return null
	var front := func(a, z):
		if z >= h - 3.0:
			return Pal.GOLD if z < h - 2.0 else stone.lightened(0.2)
		return _windows(a, z, 11.0, 17.0, 0.5, Color("#aad7eb").darkened(0.4), stone.darkened(0.15))
	_building(iso, p[0], p[1], p[2], p[3], h, stone, Color("#5b616b"), front, side)
	# a gold bar sign over the door
	var sign := iso.p(p[0] + p[2], p[1] + p[3] * 0.5, 11.0).round()
	iso.canvas.rect(int(sign.x) - 3, int(sign.y) - 3, 7, 3, Pal.metal("gold", 3))
	iso.canvas.rect(int(sign.x) - 2, int(sign.y) - 3, 5, 1, Pal.metal("gold", 5))


static func _pawn(iso: Iso, move: String, closed: bool) -> void:
	var p: Array = PLOTS.pawn
	var h := 15.0
	var brick := Color("#8e3a2c")
	var front := func(a, z):
		if z >= h - 1.5:
			return Color("#c9b48a")
		if closed and absf(fmod(a * 4.0 + z * 0.12, 2.0) - 1.0) < 0.12 and z < 9.0:
			return Color("#ffd23a") # police tape
		if z >= 1.0 and z < 8.0:
			var bars := fmod(a * 16.0, 2.0) < 0.6
			var glass = _windows(a, z, 1.0, 8.0, 0.45, Color("#c9a24a") if not closed else Color("#3a3d44"), Color("#2a1a10"))
			if glass != null and bars and fmod(a, 0.45) / 0.45 > 0.15:
				return Color("#2a2a30") # bars over the windows
			return glass
		if fmod(z, 2.0) < 0.5 or fmod(a * 8.0 + (0.5 if fmod(z, 4.0) < 2.0 else 0.0), 1.0) < 0.12:
			return brick.darkened(0.2) # mortar
		return null
	_building(iso, p[0], p[1], p[2], p[3], h, brick, Color("#4a3a32"), front)
	# the three gold balls of a pawnbroker
	var hang := iso.p(p[0] + p[2] * 0.8, p[1] + p[3], 12.0).round()
	iso.canvas.rect(int(hang.x), int(hang.y) - 1, 5, 1, Color("#2a1a10"))
	for k in 3:
		var at := Vector2(hang.x + 2 + (k - 1) * 2.0, hang.y + 2 + (1 if k == 1 else 0))
		iso.canvas.disc(at.x, at.y, 1.4, Pal.metal("gold", 4))
	if closed:
		_board(iso.canvas, iso.p(p[0] + p[2] * 0.4, p[1] + p[3], 5.0).round(), "SHUT", Color("#efe3c8"), Pal.BAD)
	elif move == "clearance":
		_board(iso.canvas, iso.p(p[0] + p[2] * 0.4, p[1] + p[3], 3.0).round(), "SALE", Pal.WARN, OUTLINE)


## A painted board with one word on it, centred on `at`.
static func _board(c: PixelCanvas, at: Vector2, word: String, bg: Color, ink: Color) -> void:
	var w := PixelFont.measure(word) + 4
	var x := int(at.x) - w / 2
	c.rect(x - 1, int(at.y) - 5, w + 2, 9, OUTLINE)
	c.rect(x, int(at.y) - 4, w, 7, bg)
	c.text(word, x + 2, int(at.y) - 3, ink)


static func _laundromat(iso: Iso) -> void:
	_building(iso, 5.05, 0.4, 0.85, 1.25, 11.0, Color("#6a8aa8"), Color("#3f454f"), func(a, z):
		if z >= 1.0 and z < 7.0:
			var f := fmod(a, 0.42) / 0.42
			if f > 0.2 and f < 0.8 and Vector2((f - 0.5) * 6.0, z - 4.0).length() < 2.2:
				return Color("#d8f0ff") # a washer's round door
		return _windows(a, z, 1.0, 7.0, 0.42, Color("#8ab0c8"), Color("#e8edf3")))


static func _park(iso: Iso) -> void:
	var c := iso.canvas
	for t in [[4.4, 3.2, 6.0], [5.4, 3.9, 7.0], [4.9, 4.1, 5.0]]:
		var foot := iso.p(t[0], t[1]).round()
		c.rect(int(foot.x), int(foot.y) - 4, 1, 4, Color("#4a3018"))
		c.disc(foot.x + 0.5, foot.y - 4 - t[2] * 0.5, t[2] * 0.5, Color("#2f5a2a"))
		c.disc(foot.x - 0.5, foot.y - 5 - t[2] * 0.5, t[2] * 0.35, Color("#3f7a36"))
	# a fountain
	var f := iso.p(5.2, 3.0).round()
	c.ellipse(f.x, f.y, 6.0, 3.0, Color("#a8a294"))
	c.ellipse(f.x, f.y, 4.5, 2.0, Color("#5a8ab0"))
	c.rect(int(f.x), int(f.y) - 4, 1, 4, Color("#d8f0ff"))


static func _lamps(iso: Iso) -> void:
	for at in [Vector2(0.9, MAIN_J.x - 0.12), Vector2(2.4, MAIN_J.x - 0.12), Vector2(4.6, MAIN_J.x - 0.12),
			Vector2(SIDE_I.y + 0.12, 3.6), Vector2(SIDE_I.x - 0.12, 0.5)]:
		var foot := iso.p(at.x, at.y).round()
		iso.canvas.rect(int(foot.x), int(foot.y) - 9, 1, 9, Color("#2a2d33"))
		iso.canvas.rect(int(foot.x) - 1, int(foot.y) - 10, 3, 1, GLOW)


## A parked car on Main Street; `police` adds the light bar and stripe.
static func _car(iso: Iso, i: float, j: float, body: Color, police: bool) -> void:
	iso.box(i, j - 0.15, 0.6, 0.3, 3.0, {"top": body, "left": body.darkened(0.3), "right": body.darkened(0.15)})
	iso.box(i + 0.15, j - 0.12, 0.3, 0.24, 2.0, {"top": body.lightened(0.1), "left": Color("#5a7a90"), "right": Color("#7a9ab0")}, 3.0)
	if police:
		var top := iso.p(i + 0.3, j, 5.0).round()
		iso.canvas.rect(int(top.x) - 2, int(top.y) - 1, 2, 1, Color("#e63a3a"))
		iso.canvas.rect(int(top.x), int(top.y) - 1, 2, 1, Color("#3a6ae6"))


## The shop's name over its roof, with its place in town by net worth.
static func _label(iso: Iso, id: String, text: String, col: Color, ranks: Dictionary) -> void:
	var p: Array = PLOTS[id]
	if ranks.has(id):
		text = "#%d %s" % [int(ranks[id]), text]
	var at := iso.p(p[0] + p[2] * 0.5, p[1] + p[3] * 0.5, 26.0 if id != "pawn" else 19.0).round()
	var c := iso.canvas
	var w := PixelFont.measure(text)
	var x := clampi(int(at.x) - w / 2, 1, SIZE.x - w - 1)
	var y := maxi(1, int(at.y) - 6)
	PixelFont.plot_text(text, func(px, py):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			c.px(x + px + d.x, y + py + d.y, OUTLINE))
	PixelFont.plot_text(text, func(px, py): c.px(x + px, y + py, col))


static func _noise(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0
