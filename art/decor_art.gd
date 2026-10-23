class_name DecorArt
extends RefCounted
## Pictures of the decoration pieces (see Decor.CATALOG), each painted in the shop's
## isometric projection on its own small canvas with the foot of the piece at FOOT, so
## shop_room can draw it on any floor spot and sort it in with the customers.

const SIZE := Vector2i(56, 80)
const FOOT := Vector2(28, 70)

const TERRACOTTA := {"top": Color("#3a2216"), "left": Color("#8e4a2c"), "right": Color("#a85a36"), "edge": Color("#c87048")}
const WALNUT := {"top": Color("#5a3418"), "left": Color("#3a2010"), "right": Color("#4a2a14"), "edge": Color("#8a5a30")}
const MARBLE := {"top": Color("#ece6dc"), "left": Color("#b8b0a4"), "right": Color("#d2cabe"), "edge": Color("#ffffff")}
const BLACK := {"top": Color("#2a2a30"), "left": Color("#141418"), "right": Color("#1e1e24"), "edge": Color("#4a4a54")}
const LEAF := [Color("#24502a"), Color("#2f6a36"), Color("#3f8a46"), Color("#6fc277")]

static var _cache := {}


## The piece as a texture, cached.
static func texture(id: String) -> Texture2D:
	if not _cache.has(id):
		_cache[id] = paint(id).texture()
	return _cache[id]


static func paint(id: String) -> PixelCanvas:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var iso := Iso.new(c, FOOT)
	match id:
		"fern":
			_fern(iso)
		"a_board":
			_a_board(iso)
		"fig_tree":
			_fig_tree(iso)
		"floor_lamp":
			_floor_lamp(iso)
		"coin_pedestal":
			_coin_pedestal(iso)
		"armchair":
			_armchair(iso)
		"neon_sign":
			_neon_sign(iso)
		"palm":
			_palm(iso)
		"vitrine":
			_vitrine(iso)
		"grandfather_clock":
			_grandfather_clock(iso)
		"bar_pyramid":
			_bar_pyramid(iso)
		"bust":
			_bust(iso)
		"chandelier_lamp":
			_torchere(iso)
		"fountain":
			_fountain(iso)
		"eagle":
			_eagle(iso)
	return c


## A soft shadow on the floor under a piece `r` tiles across.
static func _shadow(iso: Iso, r: float) -> void:
	iso.top(-r, -r, r + 0.12, r + 0.12, 0, func(i, j):
		var e: float = Vector2(i, j).length() / (r + 0.1)
		return Color(0, 0, 0, 0.28) if e < 0.8 else (Color(0, 0, 0, 0.14) if e < 1.0 else null))


## A pot or urn: a box centred on the foot, `w` tiles wide.
static func _pot(iso: Iso, w: float, h: float, cols: Dictionary) -> void:
	iso.box(-w / 2.0, -w / 2.0, w, w, h, cols)
	# dark soil
	iso.top(-w / 2.0 + 0.05, -w / 2.0 + 0.05, w / 2.0 - 0.05, w / 2.0 - 0.05, h, func(_i, _j): return Color("#2a1a10"))


## Leaves fanning out from `base`: `n` fronds of up to `reach` px, arching up then drooping.
static func _fronds(c: PixelCanvas, base: Vector2, n: int, reach: float, rng: RandomNumberGenerator, droop := 0.0) -> void:
	for k in n:
		var a := lerpf(-PI * 0.95, -PI * 0.05, (k + rng.randf_range(0.0, 0.8)) / float(n))
		var len := rng.randf_range(reach * 0.55, reach)
		var prev := base
		var steps := int(len)
		for s in steps:
			var t := float(s + 1) / steps
			var q := base + Vector2(cos(a) * len * t * 0.75, sin(a) * len * t + droop * t * t * len * 0.08)
			c.line(prev, q, LEAF[1])
			if s % 2 == 0:
				c.px(roundi(q.x), roundi(q.y) + 1, LEAF[0])
				c.px(roundi(q.x) + (1 if cos(a) > 0.0 else -1), roundi(q.y), LEAF[2])
			prev = q
		c.rect(roundi(prev.x) - 1, roundi(prev.y) - 1, 2, 2, LEAF[2])
		c.px(roundi(prev.x), roundi(prev.y) - 1, LEAF[3])


# ---------------------------------------------------------------- tier 0

static func _fern(iso: Iso) -> void:
	_shadow(iso, 0.3)
	_pot(iso, 0.42, 8.0, TERRACOTTA)
	iso.line3(Vector3(-0.21, 0.21, 6.0), Vector3(0.21, 0.21, 6.0), Color("#c87048")) # rim
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_fronds(iso.canvas, iso.p(0, 0, 8.0), 14, 12.0, rng, 3.0)


static func _a_board(iso: Iso) -> void:
	_shadow(iso, 0.32)
	var c := iso.canvas
	# the back leg leaning away, then the front board facing the street
	iso.face_j(-0.12, -0.3, 0.3, 0, 24.0, func(_i, _z): return Color("#4a2e16"))
	iso.face_j(0.12, -0.32, 0.32, 0, 25.0, func(i, z):
		var u: float = (i + 0.32) * 16.0
		if u < 1.2 or u > 9.0 or z < 3.0 or z > 23.5:
			return Color("#8a5a30") if z > 1.5 else Color("#4a2e16")
		return Color("#1f2a24") if PixelCanvas.checker(int(u * 3.0), int(z)) else Color("#23302a")
	)
	# chalk: a gold bar, a squiggle of writing and an arrow
	var o := iso.p(-0.24, 0.12, 20.0).round()
	for k in 7:
		c.px(int(o.x) + 1 + k, int(o.y) + 1 + k / 2, Color("#e6ecf4"))
	var bar := iso.p(-0.1, 0.12, 14.0).round()
	c.rect(int(bar.x), int(bar.y), 5, 2, Pal.GOLD)
	c.rect(int(bar.x) + 1, int(bar.y) - 1, 3, 1, Color("#fff4c8"))
	var arrow := iso.p(-0.2, 0.12, 8.0).round()
	for k in 5:
		c.px(int(arrow.x) + k, int(arrow.y) + k / 2, Color("#f4b8cc"))
	c.px(int(arrow.x) + 3, int(arrow.y), Color("#f4b8cc"))
	c.px(int(arrow.x) + 4, int(arrow.y) + 3, Color("#f4b8cc"))


static func _fig_tree(iso: Iso) -> void:
	_shadow(iso, 0.34)
	_pot(iso, 0.46, 10.0, {"top": Color("#2a2a30"), "left": Color("#d8d0c4"), "right": Color("#ece6dc"), "edge": Color("#ffffff")})
	var c := iso.canvas
	var base := iso.p(0, 0, 10.0).round()
	c.line(base, base + Vector2(1, -22), Color("#5e3b1d"))
	c.line(base + Vector2(1, 0), base + Vector2(2, -20), Color("#71482a"))
	c.line(base + Vector2(1, -14), base + Vector2(-5, -24), Color("#5e3b1d"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 26:
		var q := base + Vector2(rng.randf_range(-11.0, 11.0), rng.randf_range(-46.0, -20.0))
		var r := rng.randf_range(2.5, 4.5)
		c.disc(q.x, q.y + 1, r, LEAF[0])
		c.disc(q.x, q.y, r - 0.8, LEAF[1])
	for k in 22:
		var q := base + Vector2(rng.randf_range(-10.0, 9.0), rng.randf_range(-46.0, -24.0))
		c.rect(roundi(q.x), roundi(q.y), 2, 1, LEAF[2])
		if k % 3 == 0:
			c.px(roundi(q.x), roundi(q.y) - 1, LEAF[3])


static func _floor_lamp(iso: Iso) -> void:
	_shadow(iso, 0.24)
	var c := iso.canvas
	var foot := iso.p(0, 0).round()
	c.ellipse(foot.x, foot.y - 1, 5.0, 2.0, Pal.metal("brass", 1))
	c.ellipse(foot.x, foot.y - 2, 4.0, 1.5, Pal.metal("brass", 3))
	c.rect(int(foot.x), int(foot.y) - 46, 1, 45, Pal.metal("brass", 3))
	c.rect(int(foot.x) - 1, int(foot.y) - 46, 1, 45, Pal.metal("brass", 1))
	c.px(int(foot.x), int(foot.y) - 30, Pal.metal("brass", 5))
	# a pleated cream shade with warm light underneath
	var top := foot + Vector2(0, -56)
	for row in 10:
		var half := 3 + row / 2
		for x in range(-half, half + 1):
			var col := Color("#f4e2b8") if (x + 20) % 3 != 0 else Color("#dcc89a")
			if x == -half:
				col = Color("#b8a478")
			c.px(int(top.x) + x, int(top.y) + row, col)
	c.rect(int(top.x) - 7, int(top.y) + 10, 15, 1, Pal.metal("brass", 4))
	for x in range(-6, 7):
		if PixelCanvas.checker(x, 0):
			c.px(int(top.x) + x, int(top.y) + 11, Color("#ffe8a0", 0.6))
	c.px(int(top.x), int(top.y) - 1, Pal.metal("brass", 4))


static func _coin_pedestal(iso: Iso) -> void:
	_shadow(iso, 0.32)
	iso.box(-0.26, -0.26, 0.52, 0.52, 16.0, WALNUT)
	iso.box(-0.3, -0.3, 0.6, 0.6, 2.0, {"top": Color("#4a2a14"), "left": Color("#2a1608"), "right": Color("#3a2010")})
	iso.line3(Vector3(-0.26, 0.26, 12.0), Vector3(0.26, 0.26, 12.0), Pal.GOLD.darkened(0.2)) # brass band
	iso.line3(Vector3(0.26, -0.26, 12.0), Vector3(0.26, 0.26, 12.0), Pal.GOLD.darkened(0.35))
	# velvet bed and coins under glass
	iso.top(-0.26, -0.26, 0.26, 0.26, 16.0, func(_i, _j): return Color("#5a1a2a"))
	var c := iso.canvas
	for spot in [[-0.12, -0.1, "gold"], [0.1, -0.12, "silver"], [-0.1, 0.12, "silver"], [0.12, 0.1, "gold"], [0.0, 0.0, "plat"]]:
		var q := iso.p(spot[0], spot[1], 16.5).round()
		c.ellipse(q.x, q.y, 2.2, 1.2, Pal.metal(spot[2], 2))
		c.ellipse(q.x, q.y - 0.5, 1.8, 0.9, Pal.metal(spot[2], 4))
		c.px(int(q.x) - 1, int(q.y) - 1, Pal.metal(spot[2], 5))
	var glass_h := 7.0
	iso.face_j(0.26, -0.26, 0.26, 16.0, 16.0 + glass_h, func(i, z): return Color("#cfe6ff", 0.16 if fmod(i * 16.0 - z, 6.0) > 1.0 else 0.4))
	iso.face_i(0.26, -0.26, 0.26, 16.0, 16.0 + glass_h, func(j, z): return Color("#cfe6ff", 0.22 if fmod(j * 16.0 - z, 6.0) > 1.0 else 0.45))
	iso.top(-0.26, -0.26, 0.26, 0.26, 16.0 + glass_h, func(_i, _j): return Color("#cfe6ff", 0.12))
	var edge := Color("#d8f0ff", 0.8)
	iso.line3(Vector3(-0.26, 0.26, 16.0 + glass_h), Vector3(0.26, 0.26, 16.0 + glass_h), edge)
	iso.line3(Vector3(0.26, -0.26, 16.0 + glass_h), Vector3(0.26, 0.26, 16.0 + glass_h), edge)
	iso.line3(Vector3(0.26, 0.26, 16.0), Vector3(0.26, 0.26, 16.0 + glass_h), edge)


# ---------------------------------------------------------------- tier 1

static func _armchair(iso: Iso) -> void:
	_shadow(iso, 0.36)
	var velvet := {"top": Color("#9a2a3a"), "left": Color("#5a1220"), "right": Color("#7a1a2c"), "edge": Color("#c84a5a")}
	var c := iso.canvas
	for leg in [Vector2(-0.3, 0.3), Vector2(0.3, 0.3), Vector2(0.3, -0.3)]:
		var q := iso.p(leg.x, leg.y).round()
		c.rect(int(q.x), int(q.y) - 3, 1, 3, Color("#2a1608"))
	iso.box(-0.34, -0.34, 0.68, 0.68, 7.0, velvet, 2.0) # seat base
	iso.box(-0.34, -0.34, 0.2, 0.68, 22.0, velvet, 2.0) # back, against the wall side
	iso.box(-0.14, -0.34, 0.48, 0.14, 8.0, velvet, 9.0) # arms
	iso.box(-0.14, 0.2, 0.48, 0.14, 8.0, velvet, 9.0)
	iso.top(-0.14, -0.2, 0.34, 0.2, 10.0, func(i, j): return Color("#b03a4a") if PixelCanvas.checker(int(i * 40.0), int(j * 20.0)) else Color("#a8344a"))
	# brass studs along the arm fronts and a button on the back
	for k in 4:
		var q := iso.p(0.34, -0.3 + k * 0.03, 15.0).round()
		c.px(int(q.x), int(q.y), Pal.GOLD)
		q = iso.p(0.34, 0.24 + k * 0.03, 15.0).round()
		c.px(int(q.x), int(q.y), Pal.GOLD)
	var b := iso.p(-0.14, 0.0, 19.0).round()
	c.px(int(b.x), int(b.y), Color("#3a0a14"))


static func _neon_sign(iso: Iso) -> void:
	_shadow(iso, 0.26)
	var c := iso.canvas
	var foot := iso.p(0, 0).round()
	c.ellipse(foot.x, foot.y - 1, 6.0, 2.5, Color("#1a1a20"))
	c.rect(int(foot.x), int(foot.y) - 22, 1, 21, Color("#4a4a54"))
	c.rect(int(foot.x) - 1, int(foot.y) - 22, 1, 21, Color("#2a2a30"))
	# a black panel with a gold bar in neon tubes, framed in pink neon
	var w := 0.84 * 16.0
	iso.face_j(0.05, -0.42, 0.42, 22.0, 44.0, func(i, z):
		var u: float = (i + 0.42) * 16.0
		var v: float = z - 22.0
		if u < 1.0 or u > w - 1.0 or v < 1.0 or v > 21.0:
			return Color("#ff7ab0") if PixelCanvas.checker(int(u * 2.0), int(v)) or v < 1.0 else Color("#ff9cc4")
		if u < 2.0 or u > w - 2.0 or v < 2.0 or v > 20.0:
			return Color("#5a2040")
		# the bar: a trapezoid, wide at the bottom
		var half := lerpf(5.0, 3.0, clampf((v - 6.0) / 9.0, 0.0, 1.0))
		var d := absf(u - w / 2.0)
		var on_edge := (absf(v - 6.0) < 0.6 or absf(v - 15.0) < 0.6) and d <= half + 0.5 or absf(d - half) < 0.6 and v > 6.0 and v < 15.0
		if on_edge:
			return Color("#ffe08a")
		if absf(d - half) < 1.6 and v > 5.0 and v < 16.0 or (absf(v - 6.0) < 1.6 or absf(v - 15.0) < 1.6) and d < half + 1.5:
			return Color("#4a3418")
		return Color("#141418")
	)
	iso.face_i(0.42, -0.05, 0.05, 22.0, 44.0, func(_j, _z): return Color("#24242a"))


static func _palm(iso: Iso) -> void:
	_shadow(iso, 0.34)
	var brass := {"top": Pal.metal("brass", 1), "left": Pal.metal("brass", 2), "right": Pal.metal("brass", 3), "edge": Pal.metal("brass", 5)}
	_pot(iso, 0.44, 12.0, brass)
	iso.line3(Vector3(-0.22, 0.22, 4.0), Vector3(0.22, 0.22, 4.0), Pal.metal("brass", 4))
	iso.line3(Vector3(0.22, -0.22, 4.0), Vector3(0.22, 0.22, 4.0), Pal.metal("brass", 4))
	var c := iso.canvas
	var base := iso.p(0, 0, 12.0).round()
	for k in 14:
		c.rect(int(base.x) - 1 + (k % 2), int(base.y) - k, 2, 1, Color("#7a5a30") if k % 3 else Color("#5e4020"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_fronds(c, base + Vector2(0, -14), 9, 22.0, rng, 10.0)


static func _vitrine(iso: Iso) -> void:
	_shadow(iso, 0.34)
	var c := iso.canvas
	iso.box(-0.3, -0.24, 0.6, 0.48, 7.0, WALNUT)
	var h0 := 7.0
	var h1 := 34.0
	# inside: the back panel, glass shelves with rings and chains catching the light
	iso.face_j(-0.24, -0.3, 0.3, h0, h1, func(_i, z): return Color("#3a1a20") if z < h1 - 2.0 else Color("#ffe8a0"))
	for shelf in [12.0, 20.0, 28.0]:
		iso.top(-0.28, -0.22, 0.28, 0.22, shelf, func(_i, _j): return Color("#cfe6ff", 0.35))
		for k in 3:
			var q := iso.p(-0.18 + k * 0.18, 0.0, shelf + 1.5).round()
			var tone := "gold" if (k + int(shelf)) % 3 else "silver"
			c.px(int(q.x) - 1, int(q.y), Pal.metal(tone, 3))
			c.px(int(q.x) + 1, int(q.y), Pal.metal(tone, 3))
			c.px(int(q.x), int(q.y) - 1, Pal.metal(tone, 4))
			c.px(int(q.x), int(q.y) + 1, Pal.metal(tone, 2))
			if k == 1:
				c.px(int(q.x), int(q.y) - 2, Color("#cfe6ff"))
	iso.face_j(0.24, -0.3, 0.3, h0, h1, func(i, z): return Color("#cfe6ff", 0.14 if fmod(i * 16.0 - z, 8.0) > 1.2 else 0.4))
	iso.face_i(0.3, -0.24, 0.24, h0, h1, func(j, z): return Color("#cfe6ff", 0.2 if fmod(j * 16.0 - z, 8.0) > 1.2 else 0.42))
	# walnut frame posts and the cap
	for corner in [Vector2(-0.3, 0.24), Vector2(0.3, 0.24), Vector2(0.3, -0.24)]:
		iso.line3(Vector3(corner.x, corner.y, h0), Vector3(corner.x, corner.y, h1), Color("#5a3418"))
	iso.box(-0.32, -0.26, 0.64, 0.52, 3.0, WALNUT, h1)
	iso.line3(Vector3(-0.32, 0.26, h1 + 3.0), Vector3(0.32, 0.26, h1 + 3.0), Pal.GOLD.darkened(0.2))


static func _grandfather_clock(iso: Iso) -> void:
	_shadow(iso, 0.26)
	var c := iso.canvas
	iso.box(-0.22, -0.2, 0.44, 0.4, 8.0, WALNUT)
	iso.box(-0.18, -0.16, 0.36, 0.32, 26.0, WALNUT, 8.0)
	iso.box(-0.22, -0.2, 0.44, 0.4, 14.0, WALNUT, 34.0)
	# a little pediment
	iso.box(-0.24, -0.22, 0.48, 0.44, 2.0, {"top": Color("#6a4020"), "left": Color("#3a2010"), "right": Color("#4a2a14"), "edge": Pal.GOLD.darkened(0.2)}, 48.0)
	# the pendulum window and the dial on the front
	iso.face_j(0.16, -0.08, 0.08, 14.0, 30.0, func(_i, _z): return Color("#1a0e06"))
	var bob := iso.p(0.0, 0.16, 18.0).round()
	c.line(bob, iso.p(0.0, 0.16, 29.0).round(), Pal.metal("brass", 3))
	c.disc(bob.x, bob.y, 2.0, Pal.GOLD)
	c.px(int(bob.x) - 1, int(bob.y) - 1, Color("#fff4c8"))
	var dial := iso.p(0.0, 0.2, 41.0)
	c.disc(dial.x, dial.y, 5.0, Pal.GOLD.darkened(0.25))
	c.disc(dial.x, dial.y, 4.0, Color("#f4ecd8"))
	c.line(dial, dial + Vector2(0, -3), Color("#1a1410"))
	c.line(dial, dial + Vector2(2, 1), Color("#1a1410"))
	for k in 4:
		var a := k * PI / 2.0
		c.px(roundi(dial.x + cos(a) * 3.0), roundi(dial.y + sin(a) * 3.0), Color("#5e3b1d"))


# ---------------------------------------------------------------- tier 2

static func _bar_pyramid(iso: Iso) -> void:
	_shadow(iso, 0.36)
	iso.box(-0.32, -0.32, 0.64, 0.64, 12.0, MARBLE)
	iso.line3(Vector3(-0.32, 0.32, 10.0), Vector3(0.32, 0.32, 10.0), Pal.GOLD)
	iso.line3(Vector3(0.32, -0.32, 10.0), Vector3(0.32, 0.32, 10.0), Pal.GOLD.darkened(0.2))
	var gold := {"top": Pal.metal("gold", 4), "left": Pal.metal("gold", 2), "right": Pal.metal("gold", 3), "edge": Pal.metal("gold", 5)}
	# three rows of bars, stacked log-cabin style
	var z := 12.0
	for row in [[-0.22, 0.0, 0.22], [-0.11, 0.11], [0.0]]:
		for i in row:
			iso.box(i - 0.09, -0.2, 0.18, 0.4, 4.0, gold, z)
		z += 4.0
	var c := iso.canvas
	var top := iso.p(0, 0, z + 1.0).round()
	c.px(int(top.x), int(top.y), Color.WHITE)
	# the glass dome
	var mid := iso.p(0, 0, 12.0)
	for y in range(-22, 1):
		for x in range(-14, 15):
			var e := Vector2(x / 14.0, y / 22.0).length()
			if e > 0.92 and e <= 1.0:
				c.px(int(mid.x) + x, int(mid.y) + y, Color("#d8f0ff", 0.55))
			elif e < 0.92 and x < -6 and absf(x + 9.0 + y * 0.25) < 0.8:
				c.px(int(mid.x) + x, int(mid.y) + y, Color("#ffffff", 0.35))


static func _bust(iso: Iso) -> void:
	_shadow(iso, 0.28)
	iso.box(-0.24, -0.24, 0.48, 0.48, 3.0, MARBLE)
	iso.box(-0.18, -0.18, 0.36, 0.36, 22.0, MARBLE, 3.0)
	iso.box(-0.24, -0.24, 0.48, 0.48, 3.0, MARBLE, 25.0)
	iso.line3(Vector3(-0.18, 0.18, 8.0), Vector3(-0.18, 0.18, 22.0), Color("#a8a094"))
	var c := iso.canvas
	var base := iso.p(0, 0, 28.0).round()
	var shade := Color("#a8a094")
	var mid := Color("#d2cabe")
	var light := Color("#f4f0ea")
	# shoulders and chest, draped
	c.ellipse(base.x, base.y - 3, 10.0, 4.5, mid)
	c.ellipse(base.x - 1, base.y - 4, 8.0, 3.0, light)
	c.line(base + Vector2(-6, -2), base + Vector2(2, -6), shade)
	# neck and head, lit from the window on the left
	c.rect(int(base.x) - 2, int(base.y) - 11, 4, 5, mid)
	c.rect(int(base.x) + 1, int(base.y) - 11, 1, 5, shade)
	c.ellipse(base.x, base.y - 15.0, 4.5, 5.0, mid)
	c.ellipse(base.x - 1.0, base.y - 15.5, 3.2, 4.0, light)
	# curly hair over the crown and the back of the head
	for q in [Vector2(-3, -19), Vector2(-1, -20), Vector2(1, -20), Vector2(3, -19), Vector2(4, -17), Vector2(4, -15)]:
		c.disc(base.x + q.x, base.y + q.y, 1.4, mid)
		c.px(int(base.x + q.x), int(base.y + q.y) + 1, shade)
	# profile: brow, nose and chin facing down-left
	c.px(int(base.x) - 4, int(base.y) - 15, mid)
	c.px(int(base.x) - 5, int(base.y) - 14, light)
	c.px(int(base.x) - 2, int(base.y) - 16, shade) # eye
	c.px(int(base.x) - 3, int(base.y) - 12, shade) # mouth
	c.px(int(base.x) + 2, int(base.y) - 15, shade) # ear


static func _torchere(iso: Iso) -> void:
	_shadow(iso, 0.24)
	var c := iso.canvas
	var foot := iso.p(0, 0).round()
	c.ellipse(foot.x, foot.y - 1, 5.0, 2.0, Pal.metal("gold", 2))
	c.ellipse(foot.x, foot.y - 2, 4.0, 1.5, Pal.metal("gold", 4))
	for k in 46:
		var w := 1 if k % 9 else 2
		c.rect(int(foot.x) - w + 1, int(foot.y) - 2 - k, w, 1, Pal.metal("gold", 3))
		c.px(int(foot.x) - 1, int(foot.y) - 2 - k, Pal.metal("gold", 1))
	# a gilt bowl and a cone of crystal drops catching the light
	var top := foot + Vector2(0, -48)
	c.ellipse(top.x, top.y, 7.0, 2.5, Pal.metal("gold", 3))
	c.ellipse(top.x, top.y - 1, 6.0, 1.5, Color("#fff2be"))
	for x in range(-6, 7, 2):
		var drop := 4 - absi(x) / 3
		for y in drop:
			c.px(int(top.x) + x, int(top.y) + 2 + y, Color("#d8f0ff") if y < drop - 1 else Color("#ffffff"))
	for k in 5:
		c.px(int(top.x) - 4 + k * 2, int(top.y) - 4 - k % 2, Color("#ffe8a0", 0.6))


# ---------------------------------------------------------------- tier 3

static func _fountain(iso: Iso) -> void:
	_shadow(iso, 0.44)
	var c := iso.canvas
	iso.box(-0.42, -0.42, 0.84, 0.84, 7.0, MARBLE)
	iso.top(-0.36, -0.36, 0.36, 0.36, 7.0, func(i, j):
		var ripple: float = sin((Vector2(i, j).length()) * 40.0)
		return Color("#5aa0d8") if ripple > 0.6 else Color("#3a78b8"))
	# a coin or two glinting under the water
	for q in [iso.p(0.2, 0.1, 7.0), iso.p(-0.15, 0.22, 7.0), iso.p(0.1, -0.24, 7.0)]:
		c.px(int(q.x), int(q.y), Pal.GOLD)
	# the column and the gilded lion's head
	iso.box(-0.12, -0.12, 0.24, 0.24, 18.0, MARBLE, 7.0)
	var head := iso.p(0, 0, 30.0).round()
	c.disc(head.x, head.y, 6.0, Pal.metal("gold", 2)) # mane
	c.disc(head.x - 0.5, head.y - 0.5, 5.0, Pal.metal("gold", 3))
	c.disc(head.x, head.y + 1, 3.0, Pal.metal("gold", 4)) # face
	c.px(int(head.x) - 1, int(head.y), Color("#2e1c05"))
	c.px(int(head.x) + 1, int(head.y), Color("#2e1c05"))
	c.px(int(head.x) - 2, int(head.y) - 2, Pal.metal("gold", 5))
	# water arcing from its mouth into the basin
	var mouth := head + Vector2(1, 3)
	for k in 12:
		var t := k / 11.0
		var q := mouth + Vector2(t * 10.0, t * t * 14.0 - t * 2.0)
		c.px(roundi(q.x), roundi(q.y), Color("#cfe6ff"))
		c.px(roundi(q.x) - 1, roundi(q.y), Color("#8ac0ec", 0.7))
	var splash := mouth + Vector2(10, 12)
	c.px(int(splash.x) - 1, int(splash.y) - 1, Color.WHITE)
	c.px(int(splash.x) + 1, int(splash.y) - 2, Color.WHITE)


static func _eagle(iso: Iso) -> void:
	_shadow(iso, 0.3)
	iso.box(-0.26, -0.26, 0.52, 0.52, 3.0, MARBLE)
	iso.box(-0.17, -0.17, 0.34, 0.34, 20.0, MARBLE, 3.0)
	iso.box(-0.24, -0.24, 0.48, 0.48, 3.0, MARBLE, 23.0)
	for k in 3:
		iso.line3(Vector3(-0.17 + 0.11 * (k + 0.5), 0.17, 5.0), Vector3(-0.17 + 0.11 * (k + 0.5), 0.17, 21.0), Color("#b8b0a4")) # fluting
	var c := iso.canvas
	var perch := iso.p(0, 0, 26.0).round()
	var g := [Pal.metal("gold", 1), Pal.metal("gold", 2), Pal.metal("gold", 3), Pal.metal("gold", 4), Pal.metal("gold", 5)]
	# wings spread wide and raised, feathers stepped along the lower edge
	for side in [-1, 1]:
		var pts := PackedVector2Array()
		pts.append(perch + Vector2(side * 2, -10))
		pts.append(perch + Vector2(side * 14, -30))
		pts.append(perch + Vector2(side * 16, -22))
		pts.append(perch + Vector2(side * 4, -4))
		c.poly(pts, g[2] if side < 0 else g[1])
		for k in 5:
			var q := perch + Vector2(side * (5 + k * 2), -6 - k * 4)
			c.rect(int(q.x) - (2 if side < 0 else 0), int(q.y), 3, 2, g[1] if side < 0 else g[0])
		c.line(perch + Vector2(side * 2, -10), perch + Vector2(side * 14, -30), g[4] if side < 0 else g[3])
	# body, head and beak
	c.ellipse(perch.x, perch.y - 7, 4.0, 7.0, g[2])
	c.ellipse(perch.x - 1, perch.y - 8, 2.5, 5.0, g[3])
	c.disc(perch.x, perch.y - 16, 3.0, g[3])
	c.px(int(perch.x) - 1, int(perch.y) - 17, g[4])
	c.rect(int(perch.x) + 2, int(perch.y) - 16, 2, 1, g[4])
	c.px(int(perch.x) + 3, int(perch.y) - 15, g[2])
	c.px(int(perch.x), int(perch.y) - 17, Color("#2e1c05"))
	# talons on the perch
	c.rect(int(perch.x) - 3, int(perch.y) - 1, 2, 1, g[0])
	c.rect(int(perch.x) + 1, int(perch.y) - 1, 2, 1, g[0])
