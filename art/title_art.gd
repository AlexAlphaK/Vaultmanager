class_name TitleArt
extends RefCounted
## The title screen's art: a night sky over the town, the shop interior at dusk cut
## out of its backdrop, and the gold "VAULT MANAGER" logo.

const SKY_TOP := Color("#090b18")
const SKY_MID := Color("#1c1838")
const SKY_LOW := Color("#4a2a3a")
## Building heights across the screen, 8 px per entry.
const SKYLINE := [34, 34, 48, 48, 48, 26, 26, 60, 60, 60, 60, 40, 40, 30, 30, 30, 52, 52, 22, 22, 44, 44, 44, 70, 70, 70, 36, 36, 50, 50, 28, 28, 28, 46, 46, 58, 58, 58, 32, 32, 42, 42, 26, 26, 54, 54, 54, 38, 38, 30, 30, 48, 48, 36, 36, 36, 62, 62, 40, 40]


## The full 480x270 backdrop: sky, stars, moon and the town skyline with lit windows.
static func paint_sky(w := 480, h := 270) -> PixelCanvas:
	var c := PixelCanvas.new(w, h, SKY_TOP)
	var horizon := 190
	for y in h:
		var t := clampf(y / float(horizon), 0.0, 1.0)
		var col := SKY_TOP.lerp(SKY_MID, minf(t * 1.6, 1.0)).lerp(SKY_LOW, clampf((t - 0.6) * 2.5, 0.0, 1.0))
		for x in w:
			# dither the band edges so the gradient stays pixel art
			var d := col
			if PixelCanvas.checker(x, y) and fmod(t * 12.0, 1.0) > 0.5:
				d = col.lightened(0.04)
			c.px(x, y, d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for n in 140:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, horizon - 60)
		c.px(x, y, Color(1, 1, 1, rng.randf_range(0.25, 0.9)))
	# moon
	c.disc(262, 26, 9, Color("#f4ecd0"))
	c.disc(266, 23, 8, SKY_TOP.lerp(SKY_MID, 0.3))
	for x in w:
		var col := x / 8
		var roof: int = horizon - SKYLINE[col % SKYLINE.size()]
		for y in range(roof, h):
			var wall := Color("#141224") if col % 2 else Color("#18152a")
			var lit := (x % 8 == 3 or x % 8 == 4) and (y - roof) % 7 in [3, 4] and posmod(col * 13 + (y - roof) / 7 * 5, 9) < 2
			c.px(x, y, Color("#e8b85a") if lit and y < horizon + 10 else wall)
		c.px(x, roof, Color("#26213c"))
	return c


## Paints the shop at dusk with its dark backdrop removed, so the sky shows around it.
static func paint_shop() -> PixelCanvas:
	var room := ShopArt.paint_room(true)
	var backdrop := Color("#0e0c0a")
	for y in room.height:
		for x in room.width:
			if room.get_px(x, y).is_equal_approx(backdrop):
				room.image.set_pixel(x, y, Color(0, 0, 0, 0))
	return room


## The logo: each font pixel becomes a `scale` x `scale` block, shaded down the gold
## ramp, with a dark outline and a drop shadow.
static func paint_logo(text: String, scale: int) -> PixelCanvas:
	var w := PixelFont.measure(text) * scale + 4
	var h := 5 * scale + 4
	var mask := PixelCanvas.new(w, h)
	PixelFont.plot_text(text, func(gx, gy):
		mask.rect(2 + gx * scale, 1 + gy * scale, scale, scale, Color.WHITE))
	var c := PixelCanvas.new(w, h)
	var outline := Color("#1a0f04")
	for y in h:
		for x in w:
			if mask.get_px(x, y).a > 0.0:
				continue
			var near := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				if mask.get_px(x - d.x, y - d.y).a > 0.0:
					near = true
			if near:
				c.px(x, y, outline)
	for y in h:
		for x in w:
			if mask.get_px(x, y).a == 0.0:
				continue
			var t := (y - 1) / float(5 * scale)
			var tone := 5 if t < 0.12 else (4 if t < 0.45 else (3 if t < 0.75 else 2))
			# a diagonal glint across the letters
			if (x + y) % 23 in [0, 1] and tone < 5:
				tone += 1
			c.px(x, y, Pal.metal("gold", tone))
	return c
