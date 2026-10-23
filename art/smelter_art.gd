class_name SmelterArt
extends RefCounted
## The melting workshop close-up: a sooty firebrick wall under an extraction hood, a gas
## furnace with its front port open on the crucible, the burner, gas valve and propane
## tank, the pyrometer, a shelf with the borax jar, tongs on a hook, and on the brick
## hearth a cast-iron ingot mould and a quench bucket. Also the crucible, the scrap pieces
## for the sorting tray and the finished, hallmarked bar. Flames, glow, the melt, the
## pour and the pyrometer's needle are drawn live by Smelter.

const W := 316
const H := 270
const HEARTH_Y := 170
const HOOD := Rect2i(18, 0, 156, 30)
const FURNACE := Rect2i(36, 50, 120, 128)
## The open port in the furnace's front, where the crucible shows.
const PORT := Rect2i(60, 82, 72, 80)
## Where the crucible sits in the furnace: the middle of its base.
const CRUCIBLE_HOME := Vector2(96, 158)
const CRUCIBLE_SIZE := Vector2i(36, 40)
const BURNER_Y := 146
const VALVE := Vector2i(172, 146)
const TANK := Rect2i(178, 104, 20, 70)
const PYRO := Rect2i(206, 8, 102, 70)
const DIAL := Vector2(236, 44)
const DIAL_R := 24.0
const LED := Rect2i(266, 30, 36, 13)
const SHELF_Y := 98
const JAR := Rect2i(212, 80, 28, 18)
## The close-up view down into the crucible, drawn live while it melts.
const INSET := Rect2i(212, 108, 76, 56)
const MOULD := Rect2i(192, 192, 84, 32)
const CAVITY := Rect2i(204, 199, 60, 17)
const BUCKET := Rect2i(280, 212, 30, 40)
const TRAY := Rect2i(14, 184, 172, 80)
## Dial: degrees shown on the pyrometer, and the needle's sweep in radians.
const DIAL_MAX := 1400.0
const DIAL_FROM := PI * 0.8
const DIAL_SWEEP := PI * 1.4

const BRICK := [Color("#7a3a24"), Color("#86412a"), Color("#6e3320"), Color("#8c4a2e")]
const MORTAR := Color("#3a2a22")
const IRON := Color("#3b3d42")


static func paint() -> PixelCanvas:
	var c := PixelCanvas.new(W, H, Color("#2a1a14"))
	_wall(c)
	_hood(c)
	_hearth(c)
	_shelf(c)
	_tongs(c)
	_inset_frame(c)
	_pyrometer(c)
	_tank(c)
	_furnace(c)
	_burner(c)
	_mould(c)
	_bucket(c)
	BenchArt.lamp_light(c, Vector2(96, 120), 300.0)
	return c


# ---------------------------------------------------------------- the room

## Firebrick in running bond, each brick its own shade with a lit top edge, chips and
## soot that darkens toward the hood and the furnace.
static func _wall(c: PixelCanvas) -> void:
	for y in HEARTH_Y:
		var row := y / 7
		var in_row := y % 7
		for x in W:
			var shifted := x + (8 if row % 2 else 0)
			var bx := shifted / 16
			var in_brick := shifted % 16
			var col: Color = BRICK[posmod(bx * 7 + row * 3, BRICK.size())]
			var n := ShopArt._noise(x, y)
			if n > 0.93:
				col = col.lightened(0.1)
			elif n < 0.06:
				col = col.darkened(0.15)
			if in_row == 0 or in_brick == 0:
				col = MORTAR
			elif in_row == 1:
				col = col.lightened(0.12)
			elif in_row == 6:
				col = col.darkened(0.12)
			elif in_brick == 15:
				col = col.darkened(0.1)
			# soot: heavy round the hood and above the furnace, fading out to the right
			var soot := clampf(1.0 - y / 90.0, 0.0, 1.0) * clampf(1.0 - absf(x - 96.0) / 120.0, 0.0, 1.0)
			soot = maxf(soot, clampf(1.0 - Vector2(x - 96.0, (y - 60.0) * 1.4).length() / 90.0, 0.0, 1.0) * 0.8)
			if soot > 0.0:
				var level := floori(soot * 6.0 + BenchArt.BAYER[(y % 4) * 4 + x % 4])
				col = col.darkened(0.09 * level)
			c.px(x, y, col)


## A galvanised extraction hood with seams and rivets, its duct going up out of frame.
static func _hood(c: PixelCanvas) -> void:
	var h := HOOD
	c.rect(76, 0, 40, 6, Color("#55595f"))
	for y in range(h.position.y + 6, h.end.y):
		var t := float(y - 6) / (h.size.y - 6)
		var inset := roundi((1.0 - t) * 26.0)
		for x in range(h.position.x + inset, h.end.x - inset):
			var u := float(x - h.position.x) / h.size.x
			var col := Color("#6b7078").lerp(Color("#9aa0a8"), 0.5 + 0.5 * sin(u * 9.0)) if (x / 22) % 2 else Color("#7d828a")
			if ShopArt._noise(x, y) > 0.95:
				col = col.darkened(0.25)
			c.px(x, y, col.darkened(t * 0.25))
	c.rect(h.position.x, h.end.y - 2, h.size.x, 2, Color("#3a3d42"))
	c.rect(h.position.x, h.end.y - 3, h.size.x, 1, Color("#b8bec6"))
	for x in range(h.position.x + 4, h.end.x - 2, 12):
		c.px(x, h.end.y - 5, Color("#d6dbe2"))
		c.px(x + 1, h.end.y - 4, Color("#3a3d42"))
	for x in [76, 115]:
		c.rect(x, 0, 1, 6, Color("#3a3d42"))


## Firebricks laid flat for the hearth, seen from above, scorched and dusted with sand.
static func _hearth(c: PixelCanvas) -> void:
	c.rect(0, HEARTH_Y - 2, W, 2, Color("#1d120d"))
	for y in range(HEARTH_Y, H):
		var depth := float(y - HEARTH_Y) / (H - HEARTH_Y)
		var row_h := 8 + roundi(depth * 6.0)
		var row := (y - HEARTH_Y) / 11
		var in_row := (y - HEARTH_Y) % 11
		for x in W:
			var shifted := x + (14 if row % 2 else 0)
			var in_brick := shifted % 28
			var col: Color = Color("#b8865a") if posmod(shifted / 28 + row, 3) else Color("#a9784e")
			var n := ShopArt._noise(x + 400, y)
			if n > 0.9:
				col = col.lightened(0.08)
			elif n < 0.1:
				col = col.darkened(0.1)
			if in_row == 0 or in_brick == 0:
				col = Color("#5a3e2a")
			elif in_row == 1:
				col = col.lightened(0.1)
			# scorch in front of the furnace and round the mould
			var scorch := clampf(1.0 - Vector2(x - 96.0, (y - HEARTH_Y) * 2.0).length() / 70.0, 0.0, 1.0)
			scorch = maxf(scorch, clampf(1.0 - Vector2(x - 234.0, (y - 208.0) * 1.6).length() / 60.0, 0.0, 1.0) * 0.6)
			if scorch > 0.0:
				col = col.darkened(0.12 * floori(scorch * 5.0 + BenchArt.BAYER[(y % 4) * 4 + x % 4]))
			if ShopArt._noise(x * 3, y * 5) > 0.985:
				col = Color("#d9c49a") # grains of sand
			c.px(x, y, col.darkened(0.05 * (1.0 - depth)))
		if row_h < 0:
			break


static func _shelf(c: PixelCanvas) -> void:
	c.rect(200, SHELF_Y, 108, 4, Color("#5e3b1d"))
	c.rect(200, SHELF_Y, 108, 1, Color("#8a5a30"))
	c.rect(200, SHELF_Y + 4, 108, 1, Color(0, 0, 0, 0.4))
	for bx in [210, 292]:
		c.rect(bx, SHELF_Y + 4, 2, 7, IRON)
		c.line(Vector2(bx + 1, SHELF_Y + 10), Vector2(bx + 6, SHELF_Y + 4), IRON)
	# the borax jar: a glass jar of white crystals with a paper label
	var j := JAR
	c.rect(j.position.x + 1, j.position.y + 3, j.size.x - 2, j.size.y - 3, Color("#c8d4d8", 0.5))
	for y in range(j.position.y + 5, j.end.y - 1):
		for x in range(j.position.x + 2, j.end.x - 2):
			c.px(x, y, Color("#f2f2ea") if ShopArt._noise(x, y) > 0.35 else Color("#d8dcd8"))
	c.rect(j.position.x + 2, j.position.y, j.size.x - 4, 4, Color("#4a5a6a"))
	c.rect(j.position.x + 2, j.position.y, j.size.x - 4, 1, Color("#7a8a9a"))
	c.rect(j.position.x + 1, j.position.y + 7, j.size.x - 2, 7, Color("#e8d8a8"))
	c.text("BORAX", j.position.x + 1, j.position.y + 8, Color("#5a3a1a"))
	c.rect(j.position.x + 2, j.position.y + 4, 1, j.size.y - 6, Color(1, 1, 1, 0.5))
	# a spare crucible and a graphite stirring rod
	_paint_crucible_on(c, Vector2(250, SHELF_Y), 0.42)
	c.line(Vector2(266, SHELF_Y - 1), Vector2(302, SHELF_Y - 3), Color("#2a2a2e"))
	c.line(Vector2(266, SHELF_Y - 2), Vector2(302, SHELF_Y - 4), Color("#55555c"))


static func _tongs(c: PixelCanvas) -> void:
	c.rect(300, 108, 3, 3, IRON.lightened(0.3))
	for k in [-1, 1]:
		c.line(Vector2(301, 110), Vector2(301 + k * 4, 148), IRON)
		c.line(Vector2(301 + k * 4, 148), Vector2(301 + k * 2, 162), IRON)
		c.line(Vector2(302, 110), Vector2(302 + k * 4, 148), IRON.lightened(0.25))


## A black frame on the wall for the close-up down into the crucible.
static func _inset_frame(c: PixelCanvas) -> void:
	var r := INSET
	c.rect(r.position.x + 2, r.position.y + 3, r.size.x, r.size.y, Color(0, 0, 0, 0.35))
	c.rect(r.position.x - 2, r.position.y - 2, r.size.x + 4, r.size.y + 4, Color("#1c1f24"))
	c.rect(r.position.x - 2, r.position.y - 2, r.size.x + 4, 1, Color("#4a505c"))
	c.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#0c0a09"))
	c.text("LOOKING IN", r.position.x + 1, r.end.y + 4, Color("#cfc2a8"))


## The pyrometer: a panel instrument with a round dial, a red band to be filled in live,
## an LED readout and a thermocouple lead running down the wall to the furnace.
static func _pyrometer(c: PixelCanvas) -> void:
	var p := PYRO
	BenchArt.housing(c, p, Color("#3a3f48"))
	c.disc(DIAL.x, DIAL.y, DIAL_R + 3.0, Color("#1c1f24"))
	c.disc(DIAL.x, DIAL.y, DIAL_R + 1.5, Color("#9aa3b0"))
	c.disc(DIAL.x, DIAL.y, DIAL_R, Color("#f0ead8"))
	for deg in range(0, int(DIAL_MAX) + 1, 50):
		var a := dial_angle(deg)
		var major := deg % 200 == 0
		var r0 := DIAL_R - (5.0 if major else 2.5)
		c.line(DIAL + Vector2.from_angle(a) * r0, DIAL + Vector2.from_angle(a) * (DIAL_R - 1.0), Color("#2a2a2a") if major else Color("#7a7468"))
	for deg in [0, 400, 800, 1200]:
		var a := dial_angle(deg)
		var label := str(deg / 100)
		var at := DIAL + Vector2.from_angle(a) * (DIAL_R - 10.0) - Vector2(PixelFont.measure(label) / 2.0, 3)
		c.text(label, roundi(at.x), roundi(at.y), Color("#3a3630"))
	c.text("x100", roundi(DIAL.x) - 8, roundi(DIAL.y) + 8, Color("#8a8070"))
	c.text("PYROMETER", p.position.x + 50, p.position.y + 5, Color("#9aa3b0"))
	var l := LED
	c.rect(l.position.x - 2, l.position.y - 2, l.size.x + 4, l.size.y + 4, Color("#22262c"))
	c.rect(l.position.x, l.position.y, l.size.x, l.size.y, Pal.LED_BG)
	c.text("DEG C", l.position.x + 6, l.end.y + 4, Color("#848d9a"))
	c.disc(p.end.x - 8, p.end.y - 8, 2.0, Color("#79d184"))
	# the thermocouple lead
	var lead := [Vector2(p.position.x + 4, p.end.y - 6), Vector2(p.position.x - 6, p.end.y - 6), Vector2(p.position.x - 6, 86), Vector2(162, 86), Vector2(150, 96)]
	for k in lead.size() - 1:
		c.line(lead[k], lead[k + 1], Color("#c0392b"))
		c.line(lead[k] + Vector2(1, 0), lead[k + 1] + Vector2(1, 0), Color("#7a2018"))


## A propane cylinder beside the furnace: rounded shoulders, a collar and a hazard label.
static func _tank(c: PixelCanvas) -> void:
	var t := TANK
	for y in range(t.position.y, t.end.y):
		var shoulder := 0
		if y < t.position.y + 6:
			shoulder = 6 - (y - t.position.y)
		for x in range(t.position.x + shoulder / 2, t.end.x - shoulder / 2):
			var u := float(x - t.position.x) / t.size.x
			var col := Color("#d8d8d0").lerp(Color("#8a8a84"), absf(u - 0.35) * 1.6)
			if ShopArt._noise(x, y) > 0.96:
				col = col.darkened(0.2)
			c.px(x, y, col)
	c.rect(t.position.x + 5, t.position.y - 6, 10, 6, Color("#6b6b66"))
	c.rect(t.position.x + 7, t.position.y - 8, 6, 2, Color("#c8a040"))
	c.rect(t.position.x + 3, t.position.y + 26, t.size.x - 6, 12, Color("#c0392b"))
	c.text("LPG", t.position.x + 4, t.position.y + 29, Color("#fff0e0"))
	c.rect(t.position.x, t.end.y - 4, t.size.x, 4, Color("#4a4a46"))


## The furnace: a steel drum lined with refractory, banded and riveted, its lid ajar,
## and a front port cut open so the crucible inside can be watched.
static func _furnace(c: PixelCanvas) -> void:
	var f := FURNACE
	c.ellipse(f.get_center().x + 4, f.end.y + 1, f.size.x / 2.0 + 6, 5, Color(0, 0, 0, 0.35))
	for y in range(f.position.y, f.end.y):
		for x in range(f.position.x, f.end.x):
			var u := float(x - f.position.x) / f.size.x
			# a cylinder: lit from the left, falling off to the right, with a highlight
			var shade := 0.45 + 0.5 * sin(u * PI) - u * 0.45
			if absf(u - 0.24) < 0.03:
				shade += 0.35
			elif absf(u - 0.24) < 0.06:
				shade += 0.15
			var level := floori(clampf(shade, 0.0, 1.0) * 7.0 + BenchArt.BAYER[(y % 4) * 4 + x % 4]) / 7.0
			var col := Color("#1e2024").lerp(Color("#a4abb4"), clampf(level, 0.0, 1.0))
			# brushed streaks running down the drum
			if ShopArt._noise(x, y / 6 + 900) > 0.8:
				col = col.lightened(0.05)
			var n := ShopArt._noise(x, y + 900)
			if n > 0.97:
				col = col.lightened(0.1)
			elif n < 0.04:
				col = Color("#5a3a2a").lerp(col, 0.4) # rusty spots
			# heat tint round the port: straw, then blue
			var d := Vector2(x - PORT.get_center().x, (y - PORT.get_center().y) * 0.8).length()
			if d < 52.0 and d > 40.0:
				col = col.lerp(Color("#6a5a8a"), 0.18)
			elif d <= 40.0:
				col = col.lerp(Color("#9a7a40"), 0.15)
			c.px(x, y, col)
	# rounded silhouette top and bottom
	for x in range(f.position.x, f.end.x):
		var u := (x - f.get_center().x) / (f.size.x / 2.0)
		var dip := roundi((1.0 - sqrt(maxf(0.0, 1.0 - u * u))) * 6.0)
		for k in dip:
			c.px(x, f.end.y - 1 - k, Color(0, 0, 0, 0))
	# bands and rivets
	for by in [f.position.y + 12, f.end.y - 14]:
		c.rect(f.position.x, by, f.size.x, 4, Color("#4a4e56"))
		c.rect(f.position.x, by, f.size.x, 1, Color("#9aa0a8"))
		c.rect(f.position.x, by + 3, f.size.x, 1, Color("#25282d"))
		for x in range(f.position.x + 6, f.end.x - 4, 14):
			c.px(x, by + 1, Color("#d6dbe2"))
			c.px(x + 1, by + 2, Color("#25282d"))
	# a brass maker's plate under the port
	var plate := Rect2i(roundi(f.get_center().x) - 20, f.end.y - 9, 40, 7)
	c.rect(plate.position.x, plate.position.y, plate.size.x, plate.size.y, Color("#a07a2a"))
	c.rect(plate.position.x, plate.position.y, plate.size.x, 1, Color("#e8c870"))
	c.rect(plate.position.x, plate.end.y - 1, plate.size.x, 1, Color("#5a4214"))
	c.text("VULCAN", plate.position.x + 6, plate.position.y + 1, Color("#3a2a0a"))
	# lid, pushed a little aside, with a vent hole and a handle
	var lid := Rect2i(f.position.x - 6, f.position.y - 10, f.size.x + 6, 10)
	for y in range(lid.position.y, lid.end.y):
		for x in range(lid.position.x, lid.end.x):
			var u := float(x - lid.position.x) / lid.size.x
			c.px(x, y, Color("#3a3d44").lerp(Color("#8a909a"), clampf(0.7 - u * 0.6 + (0.2 if y == lid.position.y else 0.0), 0.0, 1.0)))
	c.rect(lid.position.x, lid.end.y - 1, lid.size.x, 1, Color("#1a1c20"))
	c.rect(f.get_center().x - 12, lid.position.y - 5, 24, 3, Color("#2a2c30"))
	c.rect(f.get_center().x - 12, lid.position.y - 5, 2, 5, Color("#2a2c30"))
	c.rect(f.get_center().x + 10, lid.position.y - 5, 2, 5, Color("#2a2c30"))
	c.ellipse(f.get_center().x + 2, lid.position.y + 2, 10, 2, Color("#120a06"))
	# the port: an arched opening with a thick refractory rim, dark inside until it glows
	var p := PORT
	for y in range(p.position.y - 4, p.end.y + 3):
		for x in range(p.position.x - 4, p.end.x + 4):
			if _in_port(x, y, 4.0):
				var rim := not _in_port(x, y, 0.0)
				var col := Color("#cfc2a8") if rim else Color("#1a0d08")
				if rim and ShopArt._noise(x, y) > 0.7:
					col = Color("#b8aa90")
				c.px(x, y, col)
	# fibre lining inside the port, shaded into the depth
	for y in range(p.position.y, p.end.y):
		for x in range(p.position.x, p.end.x):
			if not _in_port(x, y, 0.0):
				continue
			var depth := absf(x - p.get_center().x) / (p.size.x / 2.0)
			var col := Color("#3a2418").lerp(Color("#1a0d08"), 1.0 - depth)
			if ShopArt._noise(x * 2, y * 2) > 0.8:
				col = col.lightened(0.06)
			c.px(x, y, col)
	# the plinth the crucible stands on
	c.rect(CRUCIBLE_HOME.x - 14, CRUCIBLE_HOME.y, 28, 4, Color("#6a5a48"))
	c.rect(CRUCIBLE_HOME.x - 14, CRUCIBLE_HOME.y, 28, 1, Color("#9a8a70"))


## Whether (x, y) is inside the arched port, grown by `grow` pixels.
static func _in_port(x: int, y: int, grow: float) -> bool:
	var p := PORT
	var cx := p.get_center().x
	var r := p.size.x / 2.0 + grow
	var top := p.position.y + p.size.x / 2.0
	if y + 0.5 > p.end.y + grow or absf(x + 0.5 - cx) > r:
		return false
	if y + 0.5 >= top:
		return true
	return Vector2(x + 0.5 - cx, y + 0.5 - top).length() <= r


## The burner's pipe into the furnace's side, the valve with its red wheel and the hose
## from the propane tank.
static func _burner(c: PixelCanvas) -> void:
	var y := BURNER_Y
	c.rect(FURNACE.end.x - 4, y - 3, VALVE.x - FURNACE.end.x + 6, 6, Color("#4a4e56"))
	c.rect(FURNACE.end.x - 4, y - 3, VALVE.x - FURNACE.end.x + 6, 1, Color("#a0a6ae"))
	c.rect(FURNACE.end.x - 4, y + 2, VALVE.x - FURNACE.end.x + 6, 1, Color("#202226"))
	c.rect(VALVE.x - 4, y - 5, 8, 10, Color("#b08a3a"))
	c.rect(VALVE.x - 4, y - 5, 8, 1, Color("#e8c870"))
	c.rect(VALVE.x - 1, y - 11, 2, 6, Color("#6b6b66"))
	# the hose
	var a := Vector2(VALVE.x + 4, y)
	var b := Vector2(TANK.get_center().x, TANK.position.y - 7)
	for k in 24:
		var t := k / 23.0
		var p := a.lerp(b, t) + Vector2(0, sin(t * PI) * 10.0)
		c.px(roundi(p.x), roundi(p.y), Color("#1a1a1a"))
		c.px(roundi(p.x), roundi(p.y) + 1, Color("#3a3a3a"))


## The cast-iron ingot mould: a heavy block with a tapered cavity, sooted inside.
static func _mould(c: PixelCanvas) -> void:
	var m := MOULD
	c.rect(m.position.x + 3, m.position.y + 4, m.size.x, m.size.y, Color(0, 0, 0, 0.4))
	for y in range(m.position.y, m.end.y):
		for x in range(m.position.x, m.end.x):
			var col := IRON
			var n := ShopArt._noise(x, y + 300)
			if n > 0.85:
				col = col.lightened(0.08)
			elif n < 0.12:
				col = col.darkened(0.15)
			c.px(x, y, col)
	c.rect(m.position.x, m.position.y, m.size.x, 1, IRON.lightened(0.45))
	c.rect(m.position.x, m.position.y + 1, 1, m.size.y - 1, IRON.lightened(0.25))
	c.rect(m.position.x, m.end.y - 6, m.size.x, 6, IRON.darkened(0.3))
	c.rect(m.position.x, m.end.y - 6, m.size.x, 1, IRON.lightened(0.15))
	# handles at each end
	for hx in [m.position.x - 6, m.end.x]:
		c.rect(hx, m.position.y + 8, 6, 4, IRON.darkened(0.1))
		c.rect(hx, m.position.y + 8, 6, 1, IRON.lightened(0.3))
	paint_cavity(c, 0.0)


## The mould's cavity, sooted black; `fill` (0-1) is left to the live drawing.
static func paint_cavity(c: PixelCanvas, _fill: float) -> void:
	var k := CAVITY
	for y in range(k.position.y, k.end.y):
		var t := float(y - k.position.y) / k.size.y
		var inset := roundi(t * 4.0)
		for x in range(k.position.x + inset, k.end.x - inset):
			var col := Color("#141416") if ShopArt._noise(x, y) > 0.2 else Color("#202024")
			if y == k.position.y:
				col = Color("#0a0a0c")
			c.px(x, y, col)
	c.rect(k.position.x, k.end.y, k.size.x, 1, IRON.lightened(0.35))


## A wooden quench bucket with iron hoops, full of water.
static func _bucket(c: PixelCanvas) -> void:
	var b := BUCKET
	c.ellipse(b.get_center().x + 2, b.end.y, b.size.x / 2.0 + 2, 3, Color(0, 0, 0, 0.35))
	for y in range(b.position.y + 4, b.end.y):
		var t := float(y - b.position.y) / b.size.y
		var inset := roundi(t * 3.0)
		for x in range(b.position.x + inset, b.end.x - inset):
			var stave := (x - b.position.x) % 5
			var col := Color("#7a5230") if stave else Color("#4a3018")
			if stave == 1:
				col = col.lightened(0.1)
			c.px(x, y, col.darkened(float(x - b.position.x) / b.size.x * 0.3))
	for hy in [b.position.y + 9, b.end.y - 8]:
		c.rect(b.position.x + 1, hy, b.size.x - 2, 2, IRON)
		c.rect(b.position.x + 1, hy, b.size.x - 2, 1, IRON.lightened(0.3))
	c.ellipse(b.get_center().x, b.position.y + 4, b.size.x / 2.0, 4, Color("#4a3018"))
	c.ellipse(b.get_center().x, b.position.y + 4, b.size.x / 2.0 - 2, 3, Color("#2a4a5a"))
	c.ellipse(b.get_center().x - 3, b.position.y + 3, 5, 1, Color("#6a9aaa"))


# ---------------------------------------------------------------- crucible and pieces

## The clay-graphite crucible on its own canvas, base at the bottom middle.
static func crucible() -> PixelCanvas:
	var c := PixelCanvas.new(CRUCIBLE_SIZE.x, CRUCIBLE_SIZE.y)
	_paint_crucible_on(c, Vector2(CRUCIBLE_SIZE.x / 2.0, CRUCIBLE_SIZE.y), 1.0)
	return c


## A tapered pot with a rolled lip, graphite grey with a clay bloom, `s` times full size,
## standing with its base centred on `base`.
static func _paint_crucible_on(c: PixelCanvas, base: Vector2, s: float) -> void:
	var h := roundi(38 * s)
	var top_w := 34.0 * s
	var bot_w := 24.0 * s
	for y in h:
		var t := float(y) / h
		var w := lerpf(top_w, bot_w, t)
		if y < roundi(3 * s):
			w = top_w + 1.0 # the rolled lip
		var py := roundi(base.y) - h + y
		for x in range(roundi(base.x - w / 2.0), roundi(base.x + w / 2.0)):
			var u := (x + 0.5 - (base.x - w / 2.0)) / w
			var col := Color("#2e2e32").lerp(Color("#77777f"), clampf(0.75 - absf(u - 0.3) * 1.5, 0.0, 1.0))
			var n := ShopArt._noise(x * 3, py * 2)
			if n > 0.9:
				col = Color("#8a6a50") # clay showing through
			elif n < 0.05:
				col = col.darkened(0.3)
			if y < roundi(3 * s) and y == 0:
				col = col.lightened(0.3)
			c.px(x, py, col)
	# the mouth, dark until something is in it
	c.ellipse(base.x, base.y - h + 1.5 * s, top_w / 2.0 - 2.0 * s, 3.0 * s, Color("#0c0806"))


## Where the crucible's mouth is relative to its base, and the mouth's half size.
static func mouth_offset() -> Vector2:
	return Vector2(0, -CRUCIBLE_SIZE.y + 2.0)


static func mouth_radius() -> Vector2:
	return Vector2(15.0, 3.0)


## One piece of scrap for the sorting tray: `kind` from ScrapYard.LOTS' art, or "spring",
## "blade" or "rod" for steel, painted in `metal`'s colours.
static func piece(kind: String, metal: String, seed: int) -> PixelCanvas:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pal := "gold" if metal == "XAU" else "silver"
	match kind:
		"chain":
			var c := PixelCanvas.new(26, 14)
			var pts: Array[Vector2] = []
			var p := Vector2(3, rng.randf_range(4, 10))
			for k in 8:
				pts.append(p)
				p += Vector2(2.8, rng.randf_range(-1.6, 1.6))
				p.y = clampf(p.y, 3, 10)
			for k in pts.size():
				var q := pts[k]
				if k % 2 == 0:
					c.ellipse(q.x, q.y, 2.2, 1.6, Pal.metal(pal, 2))
					c.px(roundi(q.x), roundi(q.y), Color(0, 0, 0, 0))
					c.px(roundi(q.x) - 1, roundi(q.y) - 1, Pal.metal(pal, 5))
				else:
					c.rect(roundi(q.x) - 1, roundi(q.y) - 2, 2, 4, Pal.metal(pal, 3))
					c.px(roundi(q.x) - 1, roundi(q.y) - 2, Pal.metal(pal, 5))
			return c
		"ring", "class_ring":
			var c := PixelCanvas.new(14, 14)
			c.disc(7, 7, 5.5, Pal.metal(pal, 2))
			c.disc(7, 7, 4.5, Pal.metal(pal, 4))
			c.disc(7, 7, 3.0, Color(0, 0, 0, 0))
			for y in 14:
				for x in 14:
					var d := Vector2(x - 6.5, y - 6.5).length()
					if d < 3.0:
						c.image.set_pixel(x, y, Color(0, 0, 0, 0))
			c.px(4, 3, Pal.metal(pal, 5))
			if kind == "class_ring":
				c.rect(4, 0, 6, 4, Pal.metal(pal, 3))
				c.rect(5, 0, 4, 3, Color("#2050c0") if rng.randf() < 0.5 else Color("#a02030"))
				c.px(5, 0, Color("#a0c0ff"))
			elif rng.randf() < 0.5:
				c.disc(7, 2, 1.5, Color("#e8f0ff"))
			return c
		"dental":
			var c := PixelCanvas.new(12, 10)
			c.rect(2, 2, 8, 6, Pal.metal(pal, 3))
			c.rect(1, 3, 10, 4, Pal.metal(pal, 3))
			c.rect(3, 1, 2, 2, Pal.metal(pal, 4))
			c.rect(7, 1, 2, 2, Pal.metal(pal, 4))
			c.px(3, 1, Pal.metal(pal, 5))
			c.rect(2, 7, 8, 2, Color("#e8e4d8")) # a little porcelain still stuck to it
			c.rect(4, 4, 2, 2, Pal.metal(pal, 2))
			return c
		"spoon":
			var c := PixelCanvas.new(30, 12)
			c.ellipse(6, 6, 5, 4, Pal.metal(pal, 3))
			c.ellipse(5, 5, 3, 2, Pal.metal(pal, 4))
			c.px(4, 4, Pal.metal(pal, 5))
			c.line(Vector2(10, 6), Vector2(28, 5), Pal.metal(pal, 3))
			c.line(Vector2(11, 7), Vector2(28, 6), Pal.metal(pal, 2))
			c.rect(25, 4, 4, 3, Pal.metal(pal, 3))
			c.px(26, 4, Pal.metal(pal, 5))
			for x in range(12, 24, 3):
				if rng.randf() < 0.5:
					c.px(x, 6, Color("#3a3018", 0.6)) # tarnish
			return c
		"candle":
			var c := PixelCanvas.new(14, 28)
			c.ellipse(7, 25, 6, 2, Pal.metal(pal, 2))
			c.rect(5, 6, 4, 19, Pal.metal(pal, 3))
			c.rect(5, 6, 1, 19, Pal.metal(pal, 4))
			c.rect(3, 12, 8, 2, Pal.metal(pal, 3))
			c.ellipse(7, 5, 4, 2, Pal.metal(pal, 3))
			c.rect(6, 1, 2, 4, Pal.metal(pal, 4))
			for y in range(8, 24, 2):
				c.px(8, y, Color("#2a2010", 0.7)) # tarnish down the stem
			return c
		"skull":
			var c := PixelCanvas.new(16, 10)
			c.ellipse(8, 5, 7, 4, Pal.metal(pal, 2))
			c.ellipse(7, 4, 5, 2, Pal.metal(pal, 3))
			c.px(5, 3, Pal.metal(pal, 5))
			return c
		"spring":
			var c := PixelCanvas.new(10, 6)
			for x in range(1, 9):
				c.px(x, 1 + (x % 2) * 3, Pal.metal("steel", 4))
				c.px(x, 2 + (x % 2), Pal.metal("steel", 2))
			return c
		"blade":
			var c := PixelCanvas.new(24, 6)
			c.poly(PackedVector2Array([Vector2(0, 1), Vector2(20, 1), Vector2(24, 3), Vector2(20, 5), Vector2(0, 5)]), Pal.metal("steel", 3))
			c.rect(0, 1, 20, 1, Pal.metal("steel", 5))
			c.rect(0, 4, 22, 1, Pal.metal("steel", 1))
			return c
		_:
			var c := PixelCanvas.new(4, 20)
			c.rect(1, 0, 2, 20, Pal.metal("steel", 3))
			for y in range(0, 20, 2):
				c.px(1, y, Pal.metal("steel", 5))
				c.px(2, y + 1, Pal.metal("steel", 1))
			return c


## Steel bits look like this in lots of `art`: springs in chains, blades in flatware, rods
## in candlesticks.
static func steel_kind(art: String) -> String:
	return {"spoon": "blade", "candle": "rod"}.get(art, "spring")


## The finished bar, hallmarked: a tapered ingot with its weight and fineness stamped in,
## and its flaws (a cold shut line, pits from inclusions, a rusty steel fleck).
static func bar(metal: String, grams: float, purity: float, flaws: Array, seed: int) -> PixelCanvas:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pal := "gold" if metal == "XAU" else "silver"
	if metal == "XAU" and purity < 0.5:
		pal = "brass"
	var w := 70
	var h := 30
	var c := PixelCanvas.new(w + 4, h + 4)
	# the top face, tapered: the mould is wider at the top
	for y in h:
		var t := float(y) / h
		var inset := roundi(t * 3.0)
		for x in range(inset, w - inset):
			var u := float(x) / w
			var tone := 3
			if y < 3 or x < inset + 2:
				tone = 4
			if y > h - 4 or x > w - inset - 3:
				tone = 2
			# a cast surface: orange-peel ripples rather than a mirror
			if ShopArt._noise(x * 2 + seed, y * 2) > 0.8:
				tone += 1
			elif ShopArt._noise(x * 3, y * 3 + seed) < 0.12:
				tone -= 1
			var col := Pal.metal(pal, tone)
			if u > 0.15 and u < 0.85 and absf(y - h * 0.45) < 2.5 and ShopArt._noise(x, y) > 0.4:
				col = Pal.metal(pal, tone + 1) # the shrink line down the middle
			c.px(x, y, col)
	if "cold_shut" in flaws:
		var y0 := rng.randi_range(8, h - 10)
		for x in range(6, w - 6):
			c.px(x, y0 + roundi(sin(x * 0.4) * 1.5), Pal.metal(pal, 1))
	if "inclusions" in flaws:
		for k in 14:
			c.px(rng.randi_range(6, w - 7), rng.randi_range(4, h - 5), Color("#3a3a30"))
	if "steel" in flaws:
		for k in 3:
			var p := Vector2i(rng.randi_range(8, w - 9), rng.randi_range(5, h - 6))
			c.rect(p.x, p.y, 3, 2, Color("#6a3a1a"))
			c.px(p.x, p.y, Color("#a0602a"))
	# the hallmark: a punched box with the fineness, the weight and the shop's mark
	var fineness := "%.0f" % (purity * 1000.0)
	var weight := ("%.1fG" % grams) if grams < 1000.0 else ("%.2fKG" % (grams / 1000.0))
	_stamp(c, fineness, 8, 6, pal)
	_stamp(c, weight, 8, 17, pal)
	_stamp(c, "VM", w - 22, 6, pal)
	return c


static func _stamp(c: PixelCanvas, text: String, x: int, y: int, pal: String) -> void:
	var tw := PixelFont.measure(text)
	c.rect(x - 2, y - 2, tw + 4, 9, Pal.metal(pal, 2))
	c.rect(x - 1, y - 1, tw + 2, 7, Pal.metal(pal, 3))
	PixelFont.plot_text(text, func(gx, gy):
		c.px(x + gx, y + gy, Pal.metal(pal, 1))
		c.px(x + gx + 1, y + gy + 1, Pal.metal(pal, 4)))


## The colour of metal at `temp` degrees: its own colour cold, then through dull and
## cherry red, orange and yellow toward white as it heats.
static func glow(temp: float, metal_col: Color) -> Color:
	const STOPS := [[450.0, Color(0, 0, 0, 0)], [600.0, Color("#5a0f08")], [750.0, Color("#a01e0c")],
		[900.0, Color("#e0461a")], [1050.0, Color("#ff8a2a")], [1200.0, Color("#ffc050")], [1400.0, Color("#fff4c0")]]
	if temp <= STOPS[0][0]:
		return metal_col
	for k in range(1, STOPS.size()):
		if temp <= STOPS[k][0]:
			var a: Array = STOPS[k - 1]
			var b: Array = STOPS[k]
			var t: float = (temp - a[0]) / (b[0] - a[0])
			var from: Color = metal_col if k == 1 else a[1]
			return from.lerp(b[1], t)
	return STOPS[-1][1]


static func dial_angle(deg: float) -> float:
	return DIAL_FROM + clampf(deg / DIAL_MAX, 0.0, 1.0) * DIAL_SWEEP
