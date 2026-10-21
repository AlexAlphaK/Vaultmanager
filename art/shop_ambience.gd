class_name ShopAmbience
extends RefCounted
## The shop's light and life: the sunbeam through the window, dust drifting in it,
## the neon OPEN sign, the security camera's LED and the shop cat asleep on the counter.
## The light is baked once per time of day; the rest is drawn every frame onto a CanvasItem.

## The window on the left wall (j range, z range), as painted by ShopArt._window.
const WIN_J := Vector2(1.0, 3.6)
const WIN_Z := Vector2(22.0, 54.0)
## Where the sun lands: floor i per pixel of window height, and how far it slants towards the front.
const SUN_DAY := Vector2(0.075, 0.09)
const SUN_DUSK := Vector2(0.12, 0.1)
const CAT_SPOT := Vector3(3.0, 3.72, ShopArt.COUNTER_H)
const CAMERA := Vector3(0.3, 0.3, 58.0)
const MOTES := 30


## The patch of sun on the floor and the faint shaft of light above it.
static func paint_light(dusk: bool) -> PixelCanvas:
	var c := PixelCanvas.new(ShopArt.SIZE.x, ShopArt.SIZE.y)
	var iso := ShopArt.iso_on(c)
	var sun := SUN_DUSK if dusk else SUN_DAY
	var tint := Color("#ff9a5a") if dusk else Color("#ffe9a8")
	# the shaft: hull of the window pane and its patch on the floor
	var pts := PackedVector2Array()
	for jw in [WIN_J.x + 0.15, WIN_J.y - 0.15]:
		for zw in [WIN_Z.x + 2.0, WIN_Z.y - 2.0]:
			pts.append(iso.p(0, jw, zw))
			pts.append(iso.p(zw * sun.x, jw + zw * sun.y, 0))
	var hull := Geometry2D.convex_hull(pts)
	var haze := PixelCanvas.new(c.width, c.height)
	haze.poly(hull, Color(tint, 1.0))
	for y in c.height:
		for x in c.width:
			if haze.image.get_pixel(x, y).a > 0.0:
				c.px(x, y, Color(tint, 0.035))
	# the patch: every floor pixel traced back through the window to see if it's lit
	iso.top(0, 0, ShopArt.IW, ShopArt.JW, 0, func(i, j):
		var zw: float = i / sun.x
		var jw: float = j - zw * sun.y
		var u := (jw - WIN_J.x) * 16.0
		var h := zw - WIN_Z.x
		var width := (WIN_J.y - WIN_J.x) * 16.0
		var tall := WIN_Z.y - WIN_Z.x
		if u < 2.0 or u > width - 2.0 or h < 2.0 or h > tall - 2.0:
			return null
		if absf(u - width / 2.0) < 1.0 or absf(h - 17.0) < 0.9:
			return null # the window bars' shadows
		var edge := minf(minf(u - 2.0, width - 2.0 - u), minf(h - 2.0, tall - 2.0 - h))
		var a := 0.26 if dusk else 0.3
		if edge < 1.5:
			a *= 0.5
		return Color(tint, a)
	)
	return c


## Specks of dust turning slowly in the sunbeam.
static func draw_motes(ci: CanvasItem, iso: Iso, time: float, dusk: bool) -> void:
	var sun := SUN_DUSK if dusk else SUN_DAY
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n in MOTES:
		var jw := rng.randf_range(WIN_J.x + 0.2, WIN_J.y - 0.2)
		var zw := rng.randf_range(WIN_Z.x + 3.0, WIN_Z.y - 3.0)
		var t := rng.randf_range(0.1, 0.9)
		var phase := rng.randf() * TAU
		var speed := rng.randf_range(0.15, 0.4)
		jw += sin(time * speed + phase) * 0.12
		zw += cos(time * speed * 0.7 + phase) * 3.0
		t = clampf(t + sin(time * speed * 0.5 + phase * 2.0) * 0.05, 0.02, 0.98)
		var q := iso.p(t * zw * sun.x, jw + t * zw * sun.y, zw * (1.0 - t)).floor()
		var a := 0.15 + 0.4 * (0.5 + 0.5 * sin(time * 2.0 + phase * 3.0))
		ci.draw_rect(Rect2(q, Vector2.ONE), Color("#fff6d8", a * (0.6 if dusk else 1.0)))


## The neon OPEN sign hanging in the window. It buzzes and flickers now and then.
static func draw_neon(ci: CanvasItem, iso: Iso, time: float, on: bool) -> void:
	var flicker := fmod(time, 7.3)
	var lit := on and not (flicker > 6.9 and flicker < 6.97) and not (flicker > 7.05 and flicker < 7.1)
	var tube := Color("#ff5a8a") if lit else Color("#5a2a3a")
	var core := Color("#ffd0e0") if lit else Color("#6a3446")
	var glow := Color("#ff3a7a", 0.22 + 0.04 * sin(time * 9.0))
	var pts: Array[Vector2i] = []
	iso.text_on_i_wall("OPEN", WIN_J.x, WIN_J.y, WIN_Z.x + 13.0, tube, func(x, y): pts.append(Vector2i(x, y)))
	if lit:
		var seen := {}
		for q in pts:
			seen[q] = true
		for q in pts:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var g: Vector2i = q + o
				if not seen.has(g):
					seen[g] = true
					ci.draw_rect(Rect2(g, Vector2.ONE), glow)
	for k in pts.size():
		ci.draw_rect(Rect2(pts[k], Vector2.ONE), core if k % 3 == 0 else tube)


## The camera's recording light: a short red blink every second and a half.
static func draw_camera_led(ci: CanvasItem, iso: Iso, time: float) -> void:
	if fmod(time, 1.5) > 0.25:
		return
	var q := iso.p(CAMERA.x, CAMERA.y, CAMERA.z).round() + Vector2(4, 1)
	ci.draw_rect(Rect2(q - Vector2.ONE, Vector2(3, 3)), Color("#ff3a2a", 0.3))
	ci.draw_rect(Rect2(q, Vector2.ONE), Color("#ff6a4a"))


## The cat asleep on the end of the counter: breathing, and flicking the tip of its tail.
## `frames` is from paint_cat_frames(); every so often a "z" floats up.
static func draw_cat(ci: CanvasItem, iso: Iso, frames: Array, time: float) -> void:
	var base := iso.p(CAT_SPOT.x, CAT_SPOT.y, CAT_SPOT.z).round()
	var breath := 1 if fmod(time, 2.6) < 1.3 else 0
	var flick := fmod(time, 5.0)
	var tail := 0
	if flick > 4.0:
		tail = 1 + int((flick - 4.0) * 6.0) % 2
	var tex: Texture2D = frames[breath * 3 + tail]
	ci.draw_rect(Rect2(base + Vector2(-8, 0), Vector2(17, 1)), Color(0, 0, 0, 0.25))
	ci.draw_texture(tex, base + Vector2(-9, -10))
	var zt := fmod(time, 4.0)
	if zt < 2.0:
		var a := 1.0 - zt / 2.0
		var at := base + Vector2(-6 + floorf(zt * 2.0), -14 - floorf(zt * 4.0))
		PixelFont.plot_text("z", func(x, y): ci.draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), Color(Pal.INK, a * 0.8)))


## Six frames: breathing out and in, each with the tail tip down, up and curled.
static func paint_cat_frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for breath in 2:
		for tail in 3:
			out.append(_paint_cat(breath, tail).texture())
	return out


static func _paint_cat(breath: int, tail: int) -> PixelCanvas:
	var c := PixelCanvas.new(19, 12)
	var fur := Color("#d9893a")
	var dark := Color("#a85a22")
	var light := Color("#f2b56a")
	var cream := Color("#f6e2c0")
	# body: a loaf, rising as it breathes
	c.ellipse(10.5, 7.2 - breath * 0.5, 6.5, 3.4 + breath * 0.5, fur)
	c.ellipse(11.0, 8.6, 5.0, 1.4, light)
	for sx in [9, 12, 15]:
		for y in range(4, 7):
			c.px(sx + (y - 4) / 2, y - breath + 1, dark)
	# head tucked on the left, eyes shut
	c.disc(5.0, 6.6, 3.4, fur)
	c.px(2, 3, fur)
	c.px(3, 3, fur)
	c.px(2, 2, dark)
	c.px(7, 3, fur)
	c.px(7, 2, dark)
	c.px(3, 4, Color("#e89a9a"))
	c.px(6, 4, Color("#e89a9a"))
	c.rect(4, 4, 2, 1, dark) # forehead stripes
	c.rect(3, 6, 2, 1, Color("#5a2e14"))
	c.rect(6, 6, 2, 1, Color("#5a2e14"))
	c.rect(4, 8, 3, 2, cream)
	c.px(5, 8, Color("#d07070"))
	# paws peeking out
	c.rect(7, 9, 2, 1, cream)
	# tail curled round the front, tip flicking
	var tip: Array[Vector2i] = [Vector2i(4, 10), Vector2i(3, 9), Vector2i(3, 8)]
	for x in range(5, 16):
		c.px(x, 10, fur if x % 3 else dark)
	c.px(16, 9, fur)
	c.rect(4, 10, 1, 1, fur)
	c.px(tip[tail].x, tip[tail].y, dark)
	if tail > 0:
		c.px(4, 9, fur)
	_outline(c)
	return c


static func _outline(c: PixelCanvas) -> void:
	var src := c.image.duplicate()
	for y in c.height:
		for x in c.width:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < c.width and q.y < c.height and src.get_pixelv(q).a > 0.0:
					c.image.set_pixel(x, y, PeopleArt.OUTLINE)
					break
