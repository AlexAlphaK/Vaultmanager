class_name ShopArt
extends RefCounted
## Paints the isometric shop in layers, so characters can stand between them:
## room (floor, walls, vault door, window, shelves) -> keeper -> front (counter,
## display case, lamps) -> customers. Stock on the shelf and in the case is painted
## separately because it changes during play.

const ORIGIN := Vector2(142, 86)
const IW := 10.0
const JW := 8.0
const WALL_H := 64.0
const SIZE := Vector2i(316, 232)

const COUNTER := Rect2(2.6, 3.2, 6.0, 1.0) # i, j, w, d
const COUNTER_H := 18.0
## Where the long counter starts: it reaches back to the display case.
const LONG_COUNTER_I := 1.0
const CASE := Rect2(0.3, 4.2, 1.3, 3.2)
const CASE_H := 12.0
const SHELF := Rect2(4.6, 0.15, 4.0, 0.6)
const SHELF_H := 14.0
const KEEPER_SPOT := Vector2(5.6, 2.5)
## Staff: the clerk's till at the left end of the counter, its customer spot, and the guard by the door.
## On a vault run the keeper steps back to the safe by the shelf.
const CLERK_SPOT := Vector2(3.4, 2.5)
const CLERK_SLOT := Vector2(3.4, 4.8)
const GUARD_SPOT := Vector2(9.9, 4.3)
const KEEPER_AWAY := Vector2(8.2, 1.4)
## Where the queue stands, front first. The corner counter uses the first BASE_SLOTS;
## queue ropes and bigger counters open the second row (Progress.queue_slots()).
const SLOTS := [Vector2(6.2, 4.8), Vector2(7.4, 5.5), Vector2(8.5, 6.2), Vector2(9.4, 6.9),
	Vector2(8.4, 7.5), Vector2(7.3, 6.9), Vector2(6.2, 6.3), Vector2(5.1, 5.7)]
const BASE_SLOTS := 4
## Brass posts of the queue rope between the two rows.
const ROPE_POSTS := [Vector2(5.4, 5.3), Vector2(6.5, 5.87), Vector2(7.6, 6.43), Vector2(8.7, 7.0)]
const ROPE_H := 10.0
const ENTRANCE := Vector2(10.7, 5.6)
const EXIT := Vector2(10.7, 7.0)
const BOARD := Rect2(4.6, 24.0, 4.1, 38.0) # i0, z0, width in tiles, height px
const CLOCK := Vector3(9.35, 0.0, 50.0)

const WOOD := {"top": Color("#8a5a30"), "left": Color("#5e3b1d"), "right": Color("#71482a"), "edge": Color("#b88a4c")}
const STEEL := {"top": Color("#59606b"), "left": Color("#2f343c"), "right": Color("#3f454f"), "edge": Color("#7d8591")}


static func iso_on(canvas: PixelCanvas) -> Iso:
	return Iso.new(canvas, ORIGIN)


## Floor, walls and everything fixed to them. `dusk` swaps the window view and lamp glow,
## `season` (a Calendar season id) dresses the street outside.
static func paint_room(dusk: bool, season := "spring") -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y, Color("#0e0c0a"))
	var iso := iso_on(c)
	iso.top(0, 0, IW, JW, 0, _floor)
	iso.top(3.4, 4.6, 9.2, 7.6, 0, _rug)
	iso.top(9.25, 5.0, IW, 7.4, 0, _doormat)
	_scuffs(iso)
	for r in [COUNTER, CASE, SHELF]:
		_contact_shadow(iso, r)
	iso.face_j(0, 0, IW, 0, WALL_H, func(i, z): return _wall(i * 16.0, z, false))
	iso.face_i(0, 0, JW, 0, WALL_H, func(j, z): return _wall(j * 16.0, z, true))
	# corner post and crown moulding
	c.line(iso.p(0, 0, 0), iso.p(0, 0, WALL_H), Color("#2a2018"))
	c.line(iso.p(0, 0, WALL_H), iso.p(IW, 0, WALL_H), Pal.GOLD)
	c.line(iso.p(0, 0, WALL_H), iso.p(0, JW, WALL_H), Pal.GOLD.darkened(0.15))
	_vault_door(iso)
	_window(iso, dusk, season)
	_sign(iso)
	_board_frame(iso)
	_clock_face(iso)
	_shelf(iso)
	_certificate(iso)
	_camera(iso)
	_plant(iso, 9.0, 0.3)
	_plant(iso, 0.25, 7.2)
	# soft shadow along the wall bases
	iso.top(0, 0, IW, 0.25, 0, func(_i, _j): return Color(0, 0, 0, 0.18))
	iso.top(0, 0.25, 0.25, JW, 0, func(_i, _j): return Color(0, 0, 0, 0.18))
	return c


## Counter, display case body and pendant lamps: drawn in front of the keeper.
## `fit` is how the counter is fitted out (see fit_out()): {"counter": 0-2, "gauges", "sigma"}.
static func paint_front(dusk: bool, fit := {}) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := iso_on(c)
	_counter(iso, int(fit.get("counter", 0)))
	if fit.get("gauges", false):
		_gauges(iso)
	if fit.get("sigma", false):
		_sigma(iso)
	_case_body(iso)
	_ledger(iso)
	for lamp_i in [4.2, 7.0]:
		_lamp(iso, lamp_i, 3.7, dusk)
	return c


## The counter and bench upgrades the player owns, for paint_front().
static func fit_out() -> Dictionary:
	var level := 2 if Progress.has_upgrade("marble_counter") else (1 if Progress.has_upgrade("long_counter") else 0)
	return {"counter": level, "gauges": Progress.has_upgrade("digital_gauges"), "sigma": Progress.has_upgrade("sigma_verifier")}


## One brass post of the queue rope, with the velvet rope sagging to the next post.
## Drawn live, sorted in with the customers so people stand in front of or behind it.
static func draw_rope_post(ci: CanvasItem, iso: Iso, n: int) -> void:
	var at: Vector2 = ROPE_POSTS[n]
	var foot := iso.p(at.x, at.y).round()
	var top := foot + Vector2(0, -ROPE_H)
	if n + 1 < ROPE_POSTS.size():
		var next: Vector2 = ROPE_POSTS[n + 1]
		var to := iso.p(next.x, next.y).round() + Vector2(0, -ROPE_H + 1)
		var from := top + Vector2(0, 1)
		var steps := int(absf(to.x - from.x))
		for k in steps + 1:
			var t := k / float(maxi(steps, 1))
			var q := from.lerp(to, t) + Vector2(0, roundf(sin(t * PI) * 3.0))
			ci.draw_rect(Rect2(q.round(), Vector2.ONE), Color("#8e1f2c"))
			ci.draw_rect(Rect2(q.round() + Vector2(0, 1), Vector2.ONE), Color("#5a1220"))
	ci.draw_rect(Rect2(foot + Vector2(-2, -1), Vector2(5, 2)), Color("#7d5a20")) # base
	ci.draw_rect(Rect2(foot + Vector2(-1, -1), Vector2(3, 1)), Color("#c9a24a"))
	ci.draw_rect(Rect2(top + Vector2(0, 1), Vector2(1, ROPE_H - 2)), Color("#c9a24a"))
	ci.draw_rect(Rect2(top + Vector2(-1, 1), Vector2(1, ROPE_H - 2)), Color("#8a6a2a"))
	ci.draw_rect(Rect2(top + Vector2(-1, -1), Vector2(3, 2)), Pal.GOLD)
	ci.draw_rect(Rect2(top + Vector2(0, -1), Vector2(1, 1)), Color("#fff2be"))


## Glass of the display case, drawn over the coins inside it.
static func paint_case_glass() -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := iso_on(c)
	var r := CASE
	var z0 := CASE_H
	var glass_h := 9.0
	iso.face_j(r.end.y, r.position.x, r.end.x, z0, z0 + glass_h, func(i, z): return _glass(i * 16.0 - z, 0.20))
	iso.face_i(r.end.x, r.position.y, r.end.y, z0, z0 + glass_h, func(j, z): return _glass(j * 16.0 - z, 0.26))
	iso.top(r.position.x, r.position.y, r.end.x, r.end.y, z0 + glass_h, func(i, j): return _glass((i - j) * 16.0, 0.14))
	var edge := Color("#d8f0ff", 0.7)
	iso.line3(Vector3(r.position.x, r.end.y, z0 + glass_h), Vector3(r.end.x, r.end.y, z0 + glass_h), edge)
	iso.line3(Vector3(r.end.x, r.position.y, z0 + glass_h), Vector3(r.end.x, r.end.y, z0 + glass_h), edge)
	iso.line3(Vector3(r.end.x, r.end.y, z0), Vector3(r.end.x, r.end.y, z0 + glass_h), edge)
	return c


## Bars stacked on the back shelf: one bar per `bar_oz` troy ounces held of each metal.
static func paint_shelf_stock(oz_by_metal: Dictionary) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := iso_on(c)
	var slots := {"XAU": [4.75, 1.0], "XAG": [6.0, 10.0], "XPT": [7.4, 1.0]}
	for metal in slots:
		var start: float = slots[metal][0]
		var per_bar: float = slots[metal][1]
		var bars := mini(int(ceil(float(oz_by_metal.get(metal, 0.0)) / per_bar)), 9)
		var pal := Pal.for_metal(metal)
		for n in bars:
			var layer := n / 3
			var k := n % 3
			var i := start + k * 0.38 + layer * 0.12
			var z := SHELF_H + layer * 3.0
			iso.box(i, SHELF.position.y + 0.12, 0.32, 0.34, 3.0, {
				"top": Pal.metal(pal, 4), "left": Pal.metal(pal, 2), "right": Pal.metal(pal, 3), "edge": Pal.metal(pal, 5),
			}, z)
	return c


## Coins on the velvet inside the display case, up to 36, coloured by item.
static func paint_case_stock(coins: Array) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := iso_on(c)
	for n in mini(coins.size(), 36):
		var item: BullionItem = coins[n]
		var pal := item.palette_name()
		var i := CASE.position.x + 0.22 + (n % 4) * 0.27
		var j := CASE.position.y + 0.25 + (n / 4) * 0.33
		var q := iso.p(i, j, CASE_H)
		var x := roundi(q.x)
		var y := roundi(q.y)
		c.rect(x - 2, y, 5, 2, Pal.metal(pal, 3))
		c.rect(x - 1, y - 1, 3, 1, Pal.metal(pal, 4))
		c.rect(x - 1, y + 2, 3, 1, Pal.metal(pal, 1))
		c.px(x - 1, y, Pal.metal(pal, 5))
	return c


# ---------------------------------------------------------------- surfaces

static func _floor(i: float, j: float) -> Color:
	var plank := floori(j * 2.0)
	var along := i + plank * 1.37
	var seam := fmod(j * 2.0, 1.0) < 0.07
	var joint := fmod(along, 2.6) < 0.045
	var base: Color = [Color("#6b4526"), Color("#73492a"), Color("#674223"), Color("#704727")][posmod(plank * 7 + floori(along / 2.6) * 3, 4)]
	if seam:
		return Color("#4a2e16")
	if joint:
		return Color("#53351a")
	var grain := _noise(floori(along * 16.0 / 3.0), plank * 5 + floori(fmod(j * 2.0, 1.0) * 4.0))
	if grain > 0.82:
		base = base.darkened(0.12)
	elif grain < 0.06:
		base = base.lightened(0.08)
	# nail heads next to each joint
	if fmod(along, 2.6) < 0.16 and fmod(along, 2.6) > 0.1 and absf(fmod(j * 2.0, 1.0) - 0.5) < 0.12:
		return Color("#3a2410")
	return base


static func _rug(i: float, j: float) -> Variant:
	var u := (i - 3.4) / 5.8
	var v := (j - 4.6) / 3.0
	var edge := minf(minf(u, 1.0 - u) * 5.8, minf(v, 1.0 - v) * 3.0) # distance to edge in tiles
	if u < 0.012 or u > 0.988:
		return Color("#d9c9a8") if int(j * 24.0) % 2 == 0 else null # fringe
	if edge < 0.08:
		return Color("#c9a24a")
	if edge < 0.3:
		var t := int((i + j) * 10.0) % 4
		return [Color("#5a1f24"), Color("#7a2a24"), Color("#c9a24a"), Color("#7a2a24")][t]
	if edge < 0.36:
		return Color("#c9a24a")
	var du := absf(u - 0.5) * 5.8
	var dv := absf(v - 0.5) * 3.0
	var diamond := du * 0.55 + dv
	if diamond < 0.32:
		return Color("#e8b84a") if diamond > 0.24 else Color("#2f4a6b")
	if diamond < 0.38:
		return Color("#e8b84a")
	return Color("#8e342c") if (int(i * 8.0) + int(j * 8.0)) % 5 else Color("#7a2a24")


static func _doormat(i: float, j: float) -> Color:
	if fmod(j * 6.0, 1.0) < 0.2:
		return Color("#3b2c1e")
	return Color("#5a4630") if int(i * 12.0 + j * 4.0) % 2 else Color("#524028")


static func _wall(u: float, z: float, left: bool) -> Color:
	var shade := 0.06 if left else 0.0
	if z >= WALL_H - 3.0:
		return Color("#5e3b1d").darkened(shade) if z < WALL_H - 1.0 else Color("#8a5a30")
	if z < 18.0:
		# wainscot: raised panels with a top rail
		if z >= 15.5:
			return Color("#8a5a30").darkened(shade) if z < 17.0 else Color("#b88a4c").darkened(shade)
		if z < 2.0:
			return Color("#3a2410")
		var pu := fmod(u, 24.0)
		if pu < 2.0 or z < 4.0 or z > 13.5:
			return Color("#4a2f1b").darkened(shade)
		if pu < 3.0 or z > 12.5:
			return Color("#3a2414").darkened(shade)
		if pu > 22.0 or z < 5.0:
			return Color("#6a4424").darkened(shade)
		return Color("#57381f").darkened(shade)
	# damask wallpaper
	var base := Color("#3d4a3f").darkened(shade)
	var tx := posmod(int(u), 12)
	var tz := posmod(int(z) - 18 + (6 if posmod(int(u) / 12, 2) == 1 else 0), 12)
	var dx := absi(tx - 6)
	var dz := absi(tz - 6)
	if dx + dz == 3 or (dx == 0 and dz <= 1):
		return Color("#4c5c4e").darkened(shade)
	if dx + dz == 5 and (dx == 0 or dz == 0):
		return Color("#465548").darkened(shade)
	return base


static func _glass(t: float, alpha: float) -> Color:
	var streak := fmod(t + 400.0, 22.0)
	if streak < 1.5:
		return Color("#f4fbff", alpha + 0.35)
	if streak < 3.0:
		return Color("#d8f0ff", alpha + 0.12)
	return Color("#aad7eb", alpha)


# ---------------------------------------------------------------- fixtures

static func _vault_door(iso: Iso) -> void:
	var cu := 34.0
	var cz := 34.0
	iso.face_j(0, 0.35, 3.95, 3.0, 63.0, func(i, z):
		var u: float = i * 16.0
		var d := Vector2(u - cu, z - cz)
		var r := d.length()
		var plate_edge := minf(minf(u - 5.6, 63.2 - u), minf(z - 3.0, 63.0 - z))
		if r > 28.0:
			if plate_edge < 1.0:
				return Color("#7d8591")
			if plate_edge < 4.0 and plate_edge > 2.0 and posmod(int(u + 63.0 - z), 8) < 2 and posmod(int(u + z), 8) < 2:
				return Color("#9aa3b0") # rivets round the plate
			return Color("#3f454f")
		if r > 26.5: # frame bevel, lit from the top left
			return Color("#a0a8b4") if d.x + d.y * -1.0 < 0.0 else Color("#22262c")
		if r > 25.0:
			return Color("#141619")
		if r > 23.5: # door edge
			return Color("#7d8591") if d.x - d.y < 0.0 else Color("#4c535e")
		var ang := atan2(d.y, d.x)
		# locking bolts round the rim
		var step := TAU / 16.0
		var bolt := Vector2.from_angle(snappedf(ang, step)) * 20.5
		var bd := d - bolt
		if bd.length() < 2.0:
			return Color("#e8edf3") if bd.x - bd.y < -0.8 else (Color("#b3bcc8") if bd.length() < 1.2 else Color("#59606b"))
		# raised inner ring
		if r > 15.0 and r < 17.0:
			return Color("#9aa3b0") if d.x - d.y < 0.0 else Color("#2f343c")
		# combination dial in the middle
		if r < 5.5:
			if r > 4.6:
				return Color("#7d5a20")
			var tick := absf(fmod(ang + TAU, TAU / 10.0) - TAU / 20.0)
			if r > 3.4 and tick > TAU / 20.0 - 0.18:
				return Color("#2a1a0c")
			return Color("#f4cf6a") if d.x - d.y < 0.0 else Color("#c9a24a")
		# four-spoke wheel with ball handles
		for k in 4:
			var axis := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			var along := d.dot(axis)
			var off := absf(d.dot(axis.orthogonal()))
			var knob := d - axis * 12.5
			if knob.length() < 2.4:
				return Color("#fff2be") if knob.x - knob.y < -1.0 else (Color("#e8b84a") if knob.length() < 1.6 else Color("#7d5a20"))
			if along > 4.5 and along < 12.0 and off < 1.3:
				return Color("#f4cf6a") if d.dot(axis.orthogonal()) > 0.3 else Color("#a8761e")
		# brushed steel face
		return [Color("#59606b"), Color("#636a75"), Color("#545b66"), Color("#5e6570")][int(r * 1.3) % 4]
	)
	# heavy hinges on the left of the door
	for hz in [14.0, 54.0]:
		iso.face_j(0, 0.4, 0.75, hz - 4.0, hz + 4.0, func(i, z):
			var v: float = z - hz
			if absf(v) > 3.0:
				return Color("#1c1f24")
			return Color("#b3bcc8") if v > 1.5 else (Color("#7d8591") if v > -1.0 else Color("#3f454f"))
		)


static func _window(iso: Iso, dusk: bool, season := "spring") -> void:
	var j0 := 1.0
	var j1 := 3.6
	var z0 := 22.0
	var z1 := 54.0
	iso.face_i(0, j0, j1, z0, z1, func(j, z):
		var u: float = (j - j0) * 16.0
		var h: float = z - z0
		var width := (j1 - j0) * 16.0
		if u < 2.0 or u > width - 2.0 or h < 2.0 or h > (z1 - z0) - 2.0:
			return Color("#b88a4c") if (u < 1.0 or h > (z1 - z0) - 1.0) else Color("#8a5a30")
		if absf(u - width / 2.0) < 1.0 or absf(h - 17.0) < 0.8:
			return Color("#8a5a30")
		return _town(u, h, dusk, season)
	)
	# sill
	iso.box(0, j0 - 0.1, 0.22, j1 - j0 + 0.2, 2.0, WOOD, z0 - 2.0)


## The street outside: sky, the bank across the road, rooftops, a lamp post and a tree
## that follows the seasons. Winter puts snow on the roofs and the street.
static func _town(u: float, h: float, dusk: bool, season := "spring") -> Color:
	var skyline := [14, 14, 14, 18, 18, 18, 18, 11, 11, 11, 20, 20, 20, 20, 20, 20, 9, 9, 9, 15, 15, 15, 15, 12, 12, 12, 12, 16, 16, 16, 16, 16, 10, 10, 10, 13, 13, 13, 13, 13, 13, 13]
	var col := clampi(int(u), 0, skyline.size() - 1)
	var roof: int = skyline[col]
	var winter := season == "winter"
	var tree: Variant = _tree(u, h, season)
	if tree != null:
		var leaf: Color = tree
		return leaf.darkened(0.45) if dusk else leaf
	if h < 6.0:
		if winter:
			return Color("#d8dee8") if not dusk else Color("#5a6078") # snow on the street
		return Color("#2a2a2e") if not dusk else Color("#1a1a22") # street
	if h < 7.0:
		return Color("#5a5a60")
	if winter and h >= roof - 1.0 and h < roof:
		return Color("#eef2f8") if not dusk else Color("#8088a0") # snow on the roofs
	if h < roof:
		var lit := dusk and posmod(int(u) * 7 + int(h) * 3, 11) == 0 and int(h) % 3 == 1
		var wall := Color("#4a5468") if col % 2 else Color("#5a5068")
		if dusk:
			wall = wall.darkened(0.45)
		if lit:
			return Color("#ffd56a")
		if int(u) % 3 == 1 and int(h) % 3 == 1:
			return wall.darkened(0.3)
		return wall
	# lamp post
	if absf(u - 31.0) < 0.6 and h < 22.0:
		return Color("#2a2a30")
	if absf(u - 31.0) < 1.6 and absf(h - 22.0) < 1.0:
		return Color("#ffe9a0") if dusk else Color("#c8c8b0")
	var t := h / 30.0
	if dusk:
		return Color("#2b2a52").lerp(Color("#e0805a"), clampf(1.0 - t * 1.4, 0.0, 1.0))
	if winter:
		return Color("#c4d0dc").lerp(Color("#93a6ba"), t)
	if (int(u) / 3 + int(h)) % 9 == 0 and h > 20.0 and h < 24.0:
		return Color("#e8f2f8") # wisp of cloud
	return Color("#8cc0e0").lerp(Color("#5f97c4"), t)


## The street tree in front of the bank, or null where it isn't: blossom in spring,
## full green in summer, orange in autumn and bare branches in winter.
static func _tree(u: float, h: float, season: String) -> Variant:
	var dx := u - 36.5
	var trunk := absf(dx) < 0.8 and h >= 4.0 and h < 13.0
	if trunk:
		return Color("#4a3020")
	var dy := h - 17.0
	var inside := dx * dx / 22.0 + dy * dy / 36.0 <= 1.0
	if not inside:
		return null
	var speck := posmod(int(u) * 5 + int(h) * 3, 7)
	match season:
		"spring":
			return Color("#f4b8cc") if speck == 0 or speck == 4 else (Color("#6aa84a") if speck % 2 else Color("#4f8a3a"))
		"summer":
			return Color("#3f7a30") if speck % 3 else Color("#2c5e22")
		"autumn":
			return Color("#e08a2a") if speck % 3 == 0 else (Color("#c0502a") if speck % 3 == 1 else Color("#e8b040"))
	# winter: a few bare branches
	if absf(dx - dy * 0.6) < 0.6 or absf(dx + dy * 0.7) < 0.6 or (absf(dx) < 0.6 and dy < 2.0):
		return Color("#4a3020")
	return null


static func _sign(iso: Iso) -> void:
	var j0 := 4.4
	var j1 := 7.2
	iso.face_i(0, j0, j1, 32.0, 50.0, func(j, z):
		var u: float = (j - j0) * 16.0
		var h: float = z - 32.0
		if u < 1.0 or u > (j1 - j0) * 16.0 - 1.0 or h < 1.0 or h > 17.0:
			return Pal.GOLD.darkened(0.2)
		return Color("#1d1712")
	)
	iso.text_on_i_wall("BULLION", j0, j1, 46.0, Pal.GOLD)
	iso.text_on_i_wall("& COIN", j0, j1, 38.0, Pal.INK_DIM)


static func _board_frame(iso: Iso) -> void:
	var i0 := BOARD.position.x
	var z0 := BOARD.position.y
	iso.face_j(0, i0 - 0.12, i0 + BOARD.size.x + 0.12, z0 - 2.0, z0 + BOARD.size.y + 2.0, func(i, z):
		var u: float = (i - i0) * 16.0
		var h: float = z - z0
		if u < 0.0 or u > BOARD.size.x * 16.0 or h < 0.0 or h > BOARD.size.y:
			return Color("#2a2018")
		if int(u) % 2 == 0 and int(h) % 2 == 0:
			return Color("#16120e") # unlit LEDs
		return Color("#0b0907")
	)


static func _clock_face(iso: Iso) -> void:
	iso.face_j(0, CLOCK.x - 0.45, CLOCK.x + 0.45, CLOCK.z - 8.0, CLOCK.z + 8.0, func(i, z):
		var d := Vector2((i - CLOCK.x) * 16.0, z - CLOCK.z)
		var r := d.length()
		if r > 7.0:
			return null
		if r > 6.0:
			return Pal.GOLD.darkened(0.2)
		var tick := int(round(atan2(d.y, d.x) / (TAU / 12.0)))
		if r > 4.8 and absf(atan2(d.y, d.x) - tick * TAU / 12.0) < 0.18:
			return Color("#2a2018")
		return Color("#efe6d2")
	)


static func _shelf(iso: Iso) -> void:
	var r := SHELF
	iso.face_j(r.end.y, r.position.x, r.end.x, 0, SHELF_H, func(i, z):
		var u: float = (i - r.position.x) * 16.0
		if z > SHELF_H - 2.0:
			return Color("#7d8591")
		if fmod(u, 16.0) < 1.0 or z < 1.5:
			return Color("#1c1f24")
		if absf(z - 7.0) < 0.6:
			return Color("#2a2e35")
		if absf(fmod(u, 16.0) - 8.0) < 2.0 and (absf(z - 10.0) < 0.7 or absf(z - 3.6) < 0.7):
			return Color("#c9a24a") # drawer pulls
		return Color("#3f454f")
	)
	iso.face_i(r.end.x, r.position.y, r.end.y, 0, SHELF_H, func(_j, _z): return Color("#2f343c"))
	iso.top(r.position.x, r.position.y, r.end.x, r.end.y, SHELF_H, func(_i, _j): return Color("#59606b"))
	iso.line3(Vector3(r.position.x, r.end.y, SHELF_H), Vector3(r.end.x, r.end.y, SHELF_H), Color("#9aa3b0"))


static func _plant(iso: Iso, i: float, j: float) -> void:
	iso.box(i, j, 0.55, 0.55, 9.0, {"top": Color("#3a2216"), "left": Color("#8e4a2c"), "right": Color("#a85a36"), "edge": Color("#c87048")})
	var base := iso.p(i + 0.28, j + 0.28, 9.0)
	var c := iso.canvas
	var rng := RandomNumberGenerator.new()
	rng.seed = int(i * 100.0 + j)
	for n in 26:
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)
		var len := rng.randf_range(5.0, 17.0)
		var tip := base + Vector2(cos(a) * len * 0.6, sin(a) * len)
		c.line(base + Vector2(0, -1), tip, Color("#2f6a36"))
		c.rect(roundi(tip.x) - 1, roundi(tip.y) - 1, 3, 2, Color("#3f8a46"))
		c.px(roundi(tip.x), roundi(tip.y) - 1, Color("#6fc277"))


## `level` 0 is the plain wooden counter, 1 the long counter that reaches back to the
## display case with a second till, 2 the marble showroom counter in mahogany and brass.
static func _counter(iso: Iso, level := 0) -> void:
	var r := COUNTER
	if level >= 1:
		r = Rect2(LONG_COUNTER_I, COUNTER.position.y, COUNTER.end.x - LONG_COUNTER_I, COUNTER.size.y)
	var h := COUNTER_H
	var marble := level >= 2
	# panel colours: frame, shadow, light edge, face, face grain
	var wood: Array = [Color("#4a2e16"), Color("#3a2410"), Color("#71482a"), Color("#5e3b1d"), Color("#56361a")]
	if marble:
		wood = [Color("#2e1410"), Color("#22100c"), Color("#5a2a20"), Color("#43201a"), Color("#3c1c16")]
	var lip := Color("#e8e2d6") if marble else Color("#b88a4c")
	iso.face_j(r.end.y, r.position.x, r.end.x, 0, h, func(i, z):
		var u: float = (i - r.position.x) * 16.0
		if z < 2.0:
			return Color("#2a1a0c")
		if z < 3.5:
			return Color("#c9a24a") if z > 2.7 else Color("#8a6a2a") # brass kick rail
		if z > h - 2.0:
			return lip
		var pu := fmod(u, 16.0)
		if pu < 1.5 or z < 5.0 or z > h - 4.0:
			return wood[0]
		if pu < 2.5 or z > h - 5.0:
			return wood[1]
		if pu > 14.5 or z < 6.0:
			return wood[2]
		if marble and (absf(pu - 8.5) < 0.6 and absf(z - 10.0) < 2.5 or absf(z - 10.0) < 0.5 and absf(pu - 8.5) < 2.5):
			return Pal.GOLD # brass inlay star on each panel
		var grain := _noise(int(u), int(z / 3.0))
		return wood[3] if grain > 0.2 else wood[4]
	)
	iso.face_i(r.end.x, r.position.y, r.end.y, 0, h, func(_j, z):
		if z < 2.0:
			return Color("#2a1a0c")
		if z < 3.5:
			return Color("#a8822a")
		return wood[2] if z < h - 2.0 else lip
	)
	iso.top(r.position.x, r.position.y, r.end.x, r.end.y, h, func(i, j):
		if marble:
			return _marble(i, j)
		var g := _noise(int(i * 24.0), int(j * 6.0))
		return Color("#9a6838") if g > 0.75 else Color("#8a5a30")
	)
	iso.line3(Vector3(r.position.x, r.end.y, h), Vector3(r.end.x, r.end.y, h), Color("#fff8ec") if marble else Color("#d0a060"))
	iso.line3(Vector3(r.end.x, r.position.y, h), Vector3(r.end.x, r.end.y, h), lip)
	if level >= 1:
		_second_till(iso, h)
	# testing mat with a tiny scale and loupe
	iso.top(3.5, 3.35, 5.0, 4.05, h, func(i, j):
		var edge := minf(minf(i - 3.5, 5.0 - i), minf(j - 3.35, 4.05 - j))
		if edge < 0.05:
			return Color("#1f4a33")
		return Color("#2b5a3a") if int(i * 20.0 + j * 20.0) % 7 else Color("#275436")
	)
	iso.box(4.35, 3.45, 0.45, 0.4, 2.0, {"top": Color("#b3bcc8"), "left": Color("#3a3f48"), "right": Color("#4c535e")}, h)
	var lcd := iso.p(4.6, 3.85, h + 1.0)
	iso.canvas.rect(roundi(lcd.x) - 1, roundi(lcd.y) - 1, 3, 1, Pal.LED)
	var loupe := iso.p(3.85, 3.7, h)
	iso.canvas.disc(loupe.x, loupe.y - 1.0, 2.0, Color("#1a1410"))
	iso.canvas.px(roundi(loupe.x) - 1, roundi(loupe.y) - 2, Color("#9fd0e8"))
	# cash register
	iso.box(7.3, 3.3, 1.0, 0.75, 6.0, {"top": Color("#2f343c"), "left": Color("#1c2026"), "right": Color("#262b32"), "edge": Color("#59606b")}, h)
	iso.box(7.45, 3.35, 0.7, 0.35, 5.0, {"top": Color("#3f454f"), "left": Color("#2a2e35"), "right": Color("#33383f"), "edge": Color("#7d8591")}, h + 6.0)
	var screen := iso.p(7.8, 3.7, h + 9.0)
	iso.canvas.rect(roundi(screen.x) - 3, roundi(screen.y) - 1, 6, 2, Pal.LED.darkened(0.3))
	for k in 6:
		var key := iso.p(7.42 + (k % 3) * 0.24, 3.55 + (k / 3) * 0.2, h + 6.0)
		iso.canvas.px(roundi(key.x), roundi(key.y), Color("#dce2ea"))
	# service bell
	var bell := iso.p(6.6, 3.85, h)
	iso.canvas.rect(roundi(bell.x) - 2, roundi(bell.y) - 1, 5, 1, Color("#7d5a20"))
	iso.canvas.rect(roundi(bell.x) - 1, roundi(bell.y) - 3, 3, 2, Pal.GOLD)
	iso.canvas.px(roundi(bell.x), roundi(bell.y) - 4, Color("#fff2be"))
	iso.canvas.px(roundi(bell.x) - 1, roundi(bell.y) - 3, Color("#fff2be"))


## White marble with soft grey veins.
static func _marble(i: float, j: float) -> Color:
	var v := sin(i * 3.1 + j * 7.3 + sin(j * 4.0) * 1.7)
	if absf(v) < 0.06:
		return Color("#a9a49c")
	if absf(v) < 0.14:
		return Color("#cfc9bf")
	return Color("#ebe6dc") if _noise(int(i * 24.0), int(j * 8.0)) > 0.2 else Color("#e2ddd2")


## The long counter's second till, where the clerk rings up sales.
static func _second_till(iso: Iso, h: float) -> void:
	iso.box(1.8, 3.35, 0.6, 0.5, 4.0, {"top": Color("#2f343c"), "left": Color("#1c2026"), "right": Color("#262b32"), "edge": Color("#59606b")}, h)
	var screen := iso.p(2.1, 3.6, h + 5.0)
	iso.canvas.rect(roundi(screen.x) - 2, roundi(screen.y) - 1, 4, 1, Pal.LED.darkened(0.3))


## Digital gauges beside the scale on the testing mat: a little box with a green readout.
static func _gauges(iso: Iso) -> void:
	var h := COUNTER_H
	iso.box(3.55, 3.4, 0.4, 0.3, 3.0, {"top": Color("#3a3f48"), "left": Color("#1c2026"), "right": Color("#2a2e35"), "edge": Color("#7d8591")}, h)
	var lcd := iso.p(3.75, 3.7, h + 2.0).round()
	iso.canvas.rect(int(lcd.x) - 2, int(lcd.y) - 1, 4, 1, Color("#6fe39a"))


## The sigma verifier: a yellow handset on the mat with its flat sensor pad.
static func _sigma(iso: Iso) -> void:
	var h := COUNTER_H
	iso.top(4.85, 3.45, 5.25, 3.85, h + 0.5, func(_i, _j): return Color("#1c2026"))
	iso.box(4.9, 3.5, 0.3, 0.3, 1.0, {"top": Color("#7d8591"), "left": Color("#3f454f"), "right": Color("#59606b")}, h)
	var body := iso.p(4.75, 3.55, h).round()
	var c := iso.canvas
	c.rect(int(body.x) - 2, int(body.y) - 6, 4, 6, Color("#e8b020"))
	c.rect(int(body.x) - 2, int(body.y) - 6, 4, 1, Color("#ffd24a"))
	c.rect(int(body.x) - 1, int(body.y) - 5, 2, 2, Color("#1a1410"))
	c.px(int(body.x) - 1, int(body.y) - 5, Color("#6fe39a"))


static func _case_body(iso: Iso) -> void:
	var r := CASE
	iso.face_j(r.end.y, r.position.x, r.end.x, 0, CASE_H, func(i, z):
		if z > CASE_H - 1.5:
			return Color("#b88a4c")
		if z < 1.5:
			return Color("#2a1a0c")
		var u: float = (i - r.position.x) * 16.0
		return Color("#5e3b1d") if fmod(u, 10.0) > 1.0 else Color("#4a2e16")
	)
	iso.face_i(r.end.x, r.position.y, r.end.y, 0, CASE_H, func(j, z):
		if z > CASE_H - 1.5:
			return Color("#b88a4c")
		if z < 1.5:
			return Color("#2a1a0c")
		var u: float = (j - r.position.y) * 16.0
		if fmod(u, 17.0) < 1.0 or z < 3.0 or z > CASE_H - 3.0:
			return Color("#5e3b1d")
		return Color("#71482a")
	)
	iso.top(r.position.x, r.position.y, r.end.x, r.end.y, CASE_H, func(i, j):
		var edge := minf(minf(i - r.position.x, r.end.x - i), minf(j - r.position.y, r.end.y - j))
		if edge < 0.08:
			return Color("#8a5a30")
		return Color("#5a1f24") if int(i * 30.0 + j * 7.0) % 9 else Color("#64262b")
	)


static func _lamp(iso: Iso, i: float, j: float, dusk: bool) -> void:
	var c := iso.canvas
	var hang := iso.p(i, j, 58.0)
	c.line(Vector2(hang.x, 0), hang, Color("#1a1410"))
	var x := roundi(hang.x)
	var y := roundi(hang.y)
	c.rect(x - 1, y, 3, 2, Color("#2a2018"))
	c.rect(x - 4, y + 2, 9, 2, Color("#2f5a4a"))
	c.rect(x - 5, y + 4, 11, 2, Color("#3d6b58"))
	c.rect(x - 6, y + 6, 13, 1, Pal.GOLD.darkened(0.2))
	c.rect(x - 2, y + 7, 5, 1, Color("#fff2be") if dusk else Color("#f4e2a8"))
	c.px(x - 4, y + 3, Color("#5a8a76")) # glint on the enamel
	c.px(x - 3, y + 2, Color("#5a8a76"))
	if dusk:
		# a soft cone of light down to the counter
		var foot := iso.p(i, j - 0.1, COUNTER_H)
		var cone := PackedVector2Array([Vector2(x - 5, y + 7), Vector2(x + 6, y + 7), foot + Vector2(17, 0), foot + Vector2(-17, 0)])
		var mask := PixelCanvas.new(c.width, c.height)
		mask.poly(cone, Color.WHITE)
		for yy in range(y + 8, roundi(foot.y)):
			for xx in range(x - 18, x + 19):
				if mask.get_px(xx, yy).a > 0.0 and PixelCanvas.checker(xx, yy):
					c.px(xx, yy, Color("#ffe8a0", 0.13))
	# warm pool of light on the counter top
	var pool := iso.p(i, j - 0.1, COUNTER_H)
	var a := 0.16 if dusk else 0.08
	for yy in range(-5, 6):
		for xx in range(-18, 19):
			var e := Vector2(xx / 18.0, yy / 5.0).length()
			if e < 1.0 and PixelCanvas.checker(xx, yy) or e < 0.6:
				var q := Vector2i(roundi(pool.x) + xx, roundi(pool.y) + yy)
				if c.get_px(q.x, q.y).a > 0.0:
					c.px(q.x, q.y, Color("#ffe8a0", a * (1.0 - e)))


## A framed assay certificate with a wax seal, on the left wall by the case.
static func _certificate(iso: Iso) -> void:
	var j0 := 7.3
	var j1 := 7.95
	var z0 := 30.0
	var z1 := 44.0
	iso.face_i(0, j0, j1, z0, z1, func(j, z):
		var u: float = (j1 - j) * 16.0
		var h: float = z1 - z
		var w := (j1 - j0) * 16.0
		var tall := z1 - z0
		if u < 1.0 or h < 1.0 or u > w - 1.0 or h > tall - 1.0:
			return Pal.GOLD.darkened(0.25) if u < 1.0 or h < 1.0 else Color("#6a4a1c")
		if absf(u - w * 0.7) < 1.6 and absf(h - tall * 0.72) < 1.6:
			return Color("#a8302a") # seal
		if int(h) in [3, 5, 6, 8] and u > 2.0 and u < w - 2.0 - (3.0 if int(h) == 8 else 0.0):
			return Color("#8a7a62") if int(h) != 3 else Color("#3a2a1a")
		return Color("#efe3c8")
	)


## A security camera on a bracket up in the corner.
static func _camera(iso: Iso) -> void:
	var c := iso.canvas
	var q := iso.p(ShopAmbience.CAMERA.x, ShopAmbience.CAMERA.y, ShopAmbience.CAMERA.z).round()
	var x := int(q.x)
	var y := int(q.y)
	c.rect(x - 1, y - 4, 1, 4, Color("#2a2e35")) # bracket
	c.rect(x - 2, y - 5, 3, 1, Color("#3f454f"))
	c.rect(x - 1, y, 7, 4, Color("#c6ccd4"))
	c.rect(x - 1, y, 7, 1, Color("#e8edf3"))
	c.rect(x - 1, y + 3, 7, 1, Color("#7c838e"))
	c.rect(x + 5, y + 1, 2, 2, Color("#2a2e35")) # lens hood
	c.px(x + 6, y + 2, Color("#5a8ab0"))
	c.rect(x - 2, y - 1, 9, 1, Color("#7c838e")) # sun visor


## Ambient occlusion where a fixture meets the floor.
static func _contact_shadow(iso: Iso, r: Rect2) -> void:
	iso.top(r.position.x - 0.12, r.position.y - 0.12, r.end.x + 0.2, r.end.y + 0.2, 0, func(i, j):
		var out := maxf(maxf(r.position.x - i, i - r.end.x), maxf(r.position.y - j, j - r.end.y))
		if out < 0.0:
			return null
		return Color(0, 0, 0, 0.22 if out < 0.08 else 0.1)
	)


## Worn patches and scuffs on the boards where customers stand and walk.
static func _scuffs(iso: Iso) -> void:
	iso.top(9.2, 4.6, IW, 7.6, 0, func(i, j):
		var n := _noise(int(i * 22.0), int(j * 22.0))
		return Color(1, 0.9, 0.7, 0.06) if n > 0.6 else null
	)
	iso.top(2.6, 4.2, 3.4, 5.4, 0, func(i, j):
		var n := _noise(int(i * 30.0) + 7, int(j * 30.0))
		return Color(0, 0, 0, 0.08) if n > 0.75 else null
	)


## The day ledger lying open on the counter with a pen across it.
static func _ledger(iso: Iso) -> void:
	var h := COUNTER_H
	iso.box(5.35, 3.35, 0.95, 0.6, 1.0, {"top": Color("#efe3c8"), "left": Color("#7a2a24"), "right": Color("#5a1f24")}, h)
	iso.top(5.35, 3.35, 6.3, 3.95, h + 1.0, func(i, j):
		if absf(i - 5.82) < 0.04:
			return Color("#b8a888") # spine
		if int(j * 40.0) % 3 == 0 and absf(i - 5.82) > 0.12 and i > 5.45 and i < 6.2:
			return Color("#a89a86") # ruled lines
		return null
	)
	iso.line3(Vector3(5.55, 3.5, h + 1.5), Vector3(6.15, 3.85, h + 1.5), Color("#1d2a4a"))
	var cap := iso.p(6.15, 3.85, h + 1.5).round()
	iso.canvas.px(int(cap.x), int(cap.y), Pal.GOLD)


static func _noise(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0
