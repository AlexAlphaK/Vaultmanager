class_name BenchArt
extends RefCounted
## Shared painters for the close-up testing benches: the oak bench top, felt, instrument
## housings with screws and brushed metal, soft shadows, and the warm pool of the desk lamp.

const WOOD_BASE: Array[Color] = [Color("#5e3b1d"), Color("#623e1f"), Color("#5a381b")]
const PLANK := 18
## Where the desk lamp hangs over every bench, in bench pixels.
const LAMP := Vector2(110, 40)
const LAMP_RADIUS := 300.0
## 4x4 ordered dither thresholds, 0 to 1.
const BAYER := [0.0, 0.5, 0.125, 0.625, 0.75, 0.25, 0.875, 0.375, 0.1875, 0.6875, 0.0625, 0.5625, 0.9375, 0.4375, 0.8125, 0.3125]


## The bench top: oak planks with flowing grain, knots, bevelled joints, nails and wear.
static func wood(w: int, h: int) -> PixelCanvas:
	var c := PixelCanvas.new(w, h, WOOD_BASE[0])
	var knots := []
	for p in range(h / PLANK + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4111 + p * 97
		for k in rng.randi_range(0, 2):
			knots.append(Vector3(rng.randf_range(10, w - 10), p * PLANK + rng.randf_range(5, PLANK - 5), rng.randf_range(2.0, 3.5)))
	for y in h:
		var p := y / PLANK
		var in_plank := y % PLANK
		var base: Color = WOOD_BASE[posmod(p * 7, 3)]
		var seam_x := posmod(p * 137 + 61, maxi(w - 40, 1)) + 20
		for x in w:
			var col := base
			# grain: wavy lines that bend round the knots
			var g := in_plank + 2.2 * sin(x * 0.031 + p * 1.7) + 0.9 * sin(x * 0.097 + p * 2.3)
			for kn in knots:
				var d := Vector2((x - kn.x) / (kn.z * 2.2), (y - kn.y) / kn.z)
				var r := d.length()
				if r < 1.0:
					g = r * 4.0 # the knot's own rings
					col = col.darkened(0.12)
				elif r < 3.0:
					g += (y - kn.y) / maxf(r, 0.1) * (3.0 - r) * 0.6
			var ring := fposmod(g, 3.4)
			if ring < 0.55:
				col = col.darkened(0.2)
			elif ring < 0.9:
				col = col.darkened(0.08)
			elif ring > 2.8 and ShopArt._noise(x / 3, y) > 0.4:
				col = col.lightened(0.07)
			var n := ShopArt._noise(x / 4 + p * 31, y)
			if n > 0.96:
				col = col.lightened(0.07)
			elif n < 0.04:
				col = col.darkened(0.1)
			# joints: a dark gap, a lit bevel below it, and a butt joint with two nails
			if in_plank == 0:
				col = Color("#2e1c0c")
			elif in_plank == 1:
				col = base.lightened(0.12)
			elif in_plank == PLANK - 1:
				col = col.darkened(0.12)
			if x == seam_x and in_plank > 0:
				col = Color("#3a2410")
			elif x == seam_x + 1 and in_plank > 0:
				col = base.lightened(0.08)
			if (x == seam_x - 3 or x == seam_x + 4) and (in_plank == 4 or in_plank == PLANK - 5):
				col = Color("#2a1a0c")
			c.px(x, y, col)
	# scratches from years of coins and tools
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for s in w * h / 1800:
		var a := Vector2(rng.randf_range(0, w), rng.randf_range(0, h))
		var b := a + Vector2.from_angle(rng.randf_range(-0.6, 0.6)) * rng.randf_range(4, 12)
		c.line(a, b, Color("#8a5a30", 0.35))
	return c


## A bevelled instrument housing: soft drop shadow, brushed face, lit top-left edges,
## darker bottom-right edges, rounded corners and a screw in each corner.
static func housing(c: PixelCanvas, r: Rect2i, body: Color, screws := true) -> void:
	c.rect(r.position.x + 3, r.position.y + 4, r.size.x, r.size.y, Color(0, 0, 0, 0.14))
	c.rect(r.position.x + 1, r.position.y + 2, r.size.x + 1, r.size.y + 1, Color(0, 0, 0, 0.24))
	for y in range(r.position.y, r.end.y):
		var streak := ShopArt._noise(y * 3, 11)
		for x in range(r.position.x, r.end.x):
			var col := body
			var n := ShopArt._noise(x / 6 + y * 17, y)
			if n > 0.9 or streak > 0.92:
				col = body.lightened(0.05)
			elif n < 0.08:
				col = body.darkened(0.05)
			c.px(x, y, col)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x - 1
	var y1 := r.end.y - 1
	c.rect(x0 + 1, y0, r.size.x - 2, 1, body.lightened(0.38))
	c.rect(x0, y0 + 1, 1, r.size.y - 2, body.lightened(0.22))
	c.rect(x0 + 1, y1, r.size.x - 2, 1, body.darkened(0.5))
	c.rect(x1, y0 + 1, 1, r.size.y - 2, body.darkened(0.38))
	c.rect(x0 + 1, y0 + 1, r.size.x - 2, 1, body.lightened(0.12))
	# rounded corners show the bench through
	for q in [Vector2i(x0, y0), Vector2i(x1, y0), Vector2i(x0, y1), Vector2i(x1, y1)]:
		c.px(q.x, q.y, Color(0, 0, 0, 0.3))
	if screws and r.size.x > 30 and r.size.y > 30:
		for q in [Vector2i(x0 + 3, y0 + 3), Vector2i(x1 - 4, y0 + 3), Vector2i(x0 + 3, y1 - 4), Vector2i(x1 - 4, y1 - 4)]:
			screw(c, q.x, q.y, body)


## A 2x2 cross-head screw at (x, y), lit from the top left.
static func screw(c: PixelCanvas, x: int, y: int, body: Color) -> void:
	c.px(x, y, body.lightened(0.5))
	c.px(x + 1, y, body.lightened(0.15))
	c.px(x, y + 1, body.darkened(0.2))
	c.px(x + 1, y + 1, body.darkened(0.55))


## Felt: a fine nap of fibres in three tones, laid diagonally.
static func felt(c: PixelCanvas, r: Rect2i, base: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var v := ShopArt._noise(x, y)
			var col := base
			if v < 0.1:
				col = base.darkened(0.22)
			elif v > 0.93:
				col = base.lightened(0.16)
			elif ShopArt._noise(x - y, (x + y) / 3) > 0.86:
				col = base.lightened(0.07) # a fibre lying across the nap
			c.px(x, y, col)


## Warms and brightens everything under the lamp in soft dithered bands, and darkens
## the corners away from it. Call last, over the finished bench.
static func lamp_light(c: PixelCanvas, centre := LAMP, radius := LAMP_RADIUS) -> void:
	var warm := Color("#ffd890")
	for y in c.height:
		for x in c.width:
			var col := c.image.get_pixel(x, y)
			if col.a == 0.0:
				continue
			var f := 1.0 - Vector2(x, y).distance_to(centre) / radius
			# many fine steps, ordered-dithered, so the light falls off without rings
			var level := floori(f * 10.0 + BAYER[(y % 4) * 4 + x % 4])
			if level > 0:
				col = col.lerp(warm, 0.012 * level).lightened(0.01 * level)
			elif level < 0:
				col = col.darkened(0.04 * mini(-level, 6))
			c.image.set_pixel(x, y, Color(col, col.a))


## A shadow for `art`: its silhouette, plus a fainter one-pixel penumbra round it.
static func soft_shadow(art: PixelCanvas, alpha := 0.4) -> PixelCanvas:
	var c := PixelCanvas.new(art.width + 2, art.height + 2)
	for y in c.height:
		for x in c.width:
			if art.get_px(x - 1, y - 1).a > 0.0:
				c.image.set_pixel(x, y, Color(0, 0, 0, alpha))
				continue
			for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-2, -1), Vector2i(-1, -2)]:
				if art.get_px(x + o.x, y + o.y).a > 0.0:
					c.image.set_pixel(x, y, Color(0, 0, 0, alpha * 0.45))
					break
	return c


## Dust drifting through the lamp light over a bench.
static func draw_motes(ci: CanvasItem, time: float, area: Rect2, count := 18) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for n in count:
		var home := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var phase := rng.randf() * TAU
		var speed := rng.randf_range(0.1, 0.3)
		var at := home + Vector2(sin(time * speed + phase) * 10.0, fposmod(-time * speed * 6.0 + phase * 20.0, 40.0) - 20.0)
		if not area.has_point(at):
			continue
		var a := 0.12 + 0.3 * (0.5 + 0.5 * sin(time * 1.7 + phase * 5.0))
		ci.draw_rect(Rect2(at.floor(), Vector2.ONE), Color("#fff2d0", a))
