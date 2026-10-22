class_name PlanArt
extends RefCounted
## The floor plan: a cut-away isometric model of the whole building, seen from above.
## The shop floor and the strong room are there from day one; each room upgrade
## (Progress.upgrades with "line": "room") builds another. A room's plot is a gravel
## lot next door until the shop reaches its tier, then a bare shell until it is built.

const SIZE := Vector2i(236, 126)
const ORIGIN := Vector2(88, 14)
const WALL_H := 13.0
## Plan units to tiles: plots and furniture are laid out in plan units.
const K := 1.2
## Plots in plan units: [i, j, width, depth]. "upgrade" is "" for the rooms every shop has.
const ROOMS := [
	{"id": "strong_room", "label": "VAULT", "upgrade": "", "plot": [0.0, 0.0, 2.0, 1.6]},
	{"id": "shop_floor", "label": "SHOP", "upgrade": "", "plot": [0.0, 1.6, 3.4, 2.4]},
	{"id": "testing_lab", "label": "LAB", "upgrade": "testing_lab", "plot": [2.0, 0.0, 1.4, 1.6]},
	{"id": "workshop", "label": "FORGE", "upgrade": "workshop", "plot": [3.4, 0.0, 2.0, 1.6]},
	{"id": "lounge", "label": "LOUNGE", "upgrade": "lounge", "plot": [3.4, 1.6, 2.0, 2.4]},
	{"id": "trading_desk", "label": "DESK", "upgrade": "trading_desk", "plot": [5.4, 0.0, 1.8, 4.0]},
]
const FRONT_J := 4.0 * K
const SIDEWALK := 0.5 * K
const LOT_I := 7.2 * K


## "built", "shell" (inside the building, not built yet) or "lot" (not reached that tier).
static func state(room: Dictionary, tier: int, owned: Array) -> String:
	var id: String = room.upgrade
	if id == "" or owned.has(id):
		return "built"
	var u: Dictionary = Progress.upgrades.get(id, {})
	return "shell" if int(u.get("tier", 99)) <= tier else "lot"


static func paint(tier: int, owned: Array) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := Iso.new(c, ORIGIN)
	# the pavement out front
	iso.top(0, FRONT_J, LOT_I, FRONT_J + SIDEWALK, 0, func(i, j):
		if j > FRONT_J + SIDEWALK - 0.06:
			return Color("#8a8f99")
		return Color("#6b7079") if fmod(i, 0.6) < 0.04 else Color("#5b6069"))
	var states := {}
	for room in ROOMS:
		states[room.id] = state(room, tier, owned)
	for room in ROOMS:
		_floor(iso, room, states[room.id])
	for room in ROOMS:
		_back_walls(iso, room, states[room.id])
	for room in ROOMS:
		if states[room.id] == "built":
			_furnish(iso, room)
		elif states[room.id] == "lot":
			_lot_sign(iso, room)
	for room in ROOMS:
		_front_walls(iso, room, states[room.id])
	for room in ROOMS:
		_label(iso, room, states[room.id])
	if tier >= Progress.TIERS.size() - 1:
		_flag(iso)
	return c


## A room's plot in tiles.
static func _plot(room: Dictionary) -> Rect2:
	var p: Array = room.plot
	return Rect2(p[0] * K, p[1] * K, p[2] * K, p[3] * K)


## A box of furniture placed in plan units from the room's corner `r`.
static func _box(iso: Iso, r: Rect2, di: float, dj: float, w: float, d: float, h: float, cols: Dictionary, z := 0.0) -> void:
	iso.box(r.position.x + di * K, r.position.y + dj * K, w * K, d * K, h, cols, z)


## The screen point at plan units (di, dj) from the room's corner, height z.
static func _at(iso: Iso, r: Rect2, di: float, dj: float, z := 0.0) -> Vector2:
	return iso.p(r.position.x + di * K, r.position.y + dj * K, z).round()


static func _floor(iso: Iso, room: Dictionary, st: String) -> void:
	var r := _plot(room)
	var shade: Callable
	match st:
		"lot":
			shade = func(i, j):
				var n := _noise(int(i * 20.0), int(j * 20.0))
				return Color("#4a5a36") if n > 0.7 else (Color("#5a4a34") if n > 0.35 else Color("#524430"))
		"shell":
			shade = func(i, j):
				var edge := minf(minf(i - r.position.x, r.end.x - i), minf(j - r.position.y, r.end.y - j))
				if edge < 0.07 and fmod(i + j, 0.3) < 0.15:
					return Pal.WARN.darkened(0.2) # chalk line where the walls will go
				return Color("#6e6a62") if _noise(int(i * 16.0), int(j * 16.0)) > 0.85 else Color("#7a766d")
		_:
			shade = _room_floor(room.id)
	iso.top(r.position.x, r.position.y, r.end.x, r.end.y, 0, shade)


static func _room_floor(id: String) -> Callable:
	match id:
		"strong_room":
			return func(i, j): return Color("#4c535e") if (int(i * 4.0) + int(j * 4.0)) % 2 else Color("#454b55")
		"shop_floor":
			return func(i, j):
				if i > 0.8 * K and i < 2.9 * K and j > 2.5 * K and j < 3.7 * K:
					return Color("#8e342c") if (int(i * 6.0) + int(j * 6.0)) % 5 else Color("#c9a24a")
				return Color("#73492a") if int(j * 5.0) % 2 else Color("#6b4526")
		"testing_lab":
			return func(i, j): return Color("#d8dde2") if (int(i * 5.0) + int(j * 5.0)) % 2 else Color("#c4cad1")
		"workshop":
			return func(i, j): return Color("#5a5650") if _noise(int(i * 12.0), int(j * 12.0)) > 0.8 else Color("#66625a")
		"lounge":
			return func(i, j): return Color("#5a1f24") if (int(i * 3.0) + int(j * 3.0)) % 2 else Color("#64262b")
		"trading_desk":
			return func(i, j): return Color("#2f4a6b") if int((i + j) * 3.0) % 2 else Color("#2a4260")
	return func(_i, _j): return Color("#6b4526")


## The building's outer walls stand tall at the back; a room's other sides are low partitions.
static func _back_walls(iso: Iso, room: Dictionary, st: String) -> void:
	if st == "lot":
		return
	var r := _plot(room)
	var col := Color("#3d4a3f") if st == "built" else Color("#8a857a")
	var top := Color("#8a5a30") if st == "built" else Color("#a8a294")
	if r.position.y == 0.0:
		iso.face_j(0, r.position.x, r.end.x, 0, WALL_H, func(i, z):
			if z > WALL_H - 1.5:
				return top
			if st == "shell" and fmod(i * 16.0 + z, 6.0) < 1.0:
				return col.darkened(0.15) # bare blockwork
			return col if z > 4.0 else col.darkened(0.25))
	if r.position.x == 0.0:
		iso.face_i(0, r.position.y, r.end.y, 0, WALL_H, func(j, z):
			if z > WALL_H - 1.5:
				return top
			return col.darkened(0.08) if z > 4.0 else col.darkened(0.3))
	if room.id == "strong_room":
		# the round vault door on the back wall
		iso.face_j(0, 0.4 * K, 1.4 * K, 1.0, WALL_H - 1.0, func(i, z):
			var d := Vector2((i - 0.9 * K) * 16.0, z - 6.5)
			if d.length() > 5.5:
				return null
			if d.length() > 4.5:
				return Color("#a0a8b4")
			return Pal.GOLD if d.length() < 1.2 else Color("#59606b"))


static func _front_walls(iso: Iso, room: Dictionary, st: String) -> void:
	if st == "lot":
		return
	var r := _plot(room)
	var col := Color("#5e3b1d") if st == "built" else Color("#9a9486")
	var cap := Color("#b88a4c") if st == "built" else Color("#bdb6a6")
	var h := 3.0
	iso.face_j(r.end.y, r.position.x, r.end.x, 0, h, func(i, z):
		# a gap for the shop's front door
		if room.id == "shop_floor" and absf(i - 2.7 * K) < 0.3 * K:
			return null
		return cap if z > h - 1.0 else col)
	iso.face_i(r.end.x, r.position.y, r.end.y, 0, h, func(_j, z): return cap if z > h - 1.0 else col.lightened(0.1))


## A few pieces of furniture so each built room reads at a glance.
static func _furnish(iso: Iso, room: Dictionary) -> void:
	var r := _plot(room)
	var c := iso.canvas
	var gold := {"top": Pal.GOLD, "left": Color("#a8761e"), "right": Color("#d9a53a")}
	match room.id:
		"strong_room":
			for k in 3:
				_box(iso, r, 0.15 + k * 0.5, 1.05, 0.4, 0.35, 5.0, ShopArt.STEEL)
				_box(iso, r, 0.22 + k * 0.5, 1.12, 0.12, 0.12, 1.5, gold, 5.0)
		"shop_floor":
			_box(iso, r, 0.6, 0.35, 2.4, 0.4, 5.0, ShopArt.WOOD)
			_box(iso, r, 0.1, 0.9, 0.4, 1.2, 4.0, {"top": Color("#aad7eb"), "left": Color("#5e3b1d"), "right": Color("#71482a"), "edge": Color("#d8f0ff")})
			_box(iso, r, 1.6, 0.1, 0.3, 0.2, 7.0, {"top": Color("#e8edf3"), "left": Color("#59606b"), "right": Color("#7d8591")})
		"testing_lab":
			for k in 2:
				_box(iso, r, 0.15, 0.2 + k * 0.7, 1.1, 0.4, 5.0, ShopArt.STEEL)
				var screen := _at(iso, r, 0.5, 0.4 + k * 0.7, 5.0)
				c.rect(int(screen.x) - 1, int(screen.y) - 4, 3, 3, Color("#1c2026"))
				c.rect(int(screen.x), int(screen.y) - 3, 1, 1, Pal.LED)
			_box(iso, r, 0.9, 0.25, 0.25, 0.25, 3.0, {"top": Color("#ffd24a"), "left": Color("#a8761e"), "right": Color("#e8b020")}, 5.0)
		"workshop":
			_box(iso, r, 0.2, 0.2, 0.7, 0.6, 9.0, {"top": Color("#3a2a20"), "left": Color("#5a3a2a"), "right": Color("#6e4a36"), "edge": Color("#8a6048")})
			var mouth := _at(iso, r, 0.55, 0.8, 3.0)
			c.rect(int(mouth.x) - 2, int(mouth.y) - 2, 4, 2, Color("#ff8a2a"))
			c.px(int(mouth.x) - 1, int(mouth.y) - 2, Color("#ffe08a"))
			_box(iso, r, 1.2, 0.9, 0.4, 0.25, 4.0, {"top": Color("#3f454f"), "left": Color("#1c1f24"), "right": Color("#2f343c")})
			for k in 3:
				_box(iso, r, 1.15 + k * 0.15, 0.25, 0.12, 0.3, 1.0, gold)
		"lounge":
			var sofa := {"top": Color("#8e342c"), "left": Color("#5a1f24"), "right": Color("#7a2a24"), "edge": Color("#c25a4a")}
			_box(iso, r, 0.15, 0.3, 0.45, 1.6, 4.0, sofa)
			_box(iso, r, 0.9, 0.8, 0.6, 0.6, 2.5, ShopArt.WOOD)
			_box(iso, r, 1.5, 1.8, 0.4, 0.4, 4.0, sofa)
			var cup := _at(iso, r, 1.2, 1.1, 2.5)
			c.px(int(cup.x), int(cup.y) - 1, Color("#f0e7d7"))
		"trading_desk":
			for k in 3:
				_box(iso, r, 0.3, 0.4 + k * 1.2, 1.2, 0.5, 4.0, ShopArt.WOOD)
				for n in 2:
					var screen := _at(iso, r, 0.6 + n * 0.5, 0.5 + k * 1.2, 4.0)
					c.rect(int(screen.x) - 2, int(screen.y) - 4, 4, 3, Color("#1c2026"))
					c.rect(int(screen.x) - 1, int(screen.y) - 3, 2, 1, Pal.GOOD if n == 0 else Pal.BAD)


## A little "SOLD" style board on a plot the shop hasn't grown into yet.
static func _lot_sign(iso: Iso, room: Dictionary) -> void:
	var r := _plot(room)
	var foot := iso.p(r.get_center().x, r.get_center().y).round()
	var c := iso.canvas
	c.rect(int(foot.x), int(foot.y) - 6, 1, 6, Color("#3a2410"))
	c.rect(int(foot.x) - 3, int(foot.y) - 10, 7, 5, Color("#efe3c8"))
	c.rect(int(foot.x) - 2, int(foot.y) - 9, 5, 1, Pal.BAD)
	c.rect(int(foot.x) - 2, int(foot.y) - 7, 3, 1, Color("#8a7a62"))


static func _label(iso: Iso, room: Dictionary, st: String) -> void:
	var r := _plot(room)
	var text: String = room.label
	var at := iso.p(r.get_center().x, r.get_center().y).round()
	var w := PixelFont.measure(text)
	var x := int(at.x) - w / 2
	var y := int(at.y) + (2 if st == "lot" else -3)
	var col := Pal.INK if st == "built" else (Pal.WARN if st == "shell" else Pal.INK_FAINT)
	var c := iso.canvas
	PixelFont.plot_text(text, func(px, py):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if c.get_px(x + px + d.x, y + py + d.y) != Color("#14100c"):
				c.px(x + px + d.x, y + py + d.y, Color("#14100c", 0.85))
	)
	PixelFont.plot_text(text, func(px, py): c.px(x + px, y + py, col))


## The town landmark flies a gold flag over the corner.
static func _flag(iso: Iso) -> void:
	var c := iso.canvas
	var top := iso.p(LOT_I, 0.0, WALL_H).round()
	c.rect(int(top.x), int(top.y) - 14, 1, 14, Color("#c6ccd4"))
	c.rect(int(top.x) + 1, int(top.y) - 14, 7, 4, Pal.GOLD)
	c.rect(int(top.x) + 1, int(top.y) - 11, 7, 1, Color("#a8761e"))


static func _noise(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0
