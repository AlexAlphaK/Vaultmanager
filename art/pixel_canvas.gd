class_name PixelCanvas
extends RefCounted
## A small software rasterizer over an Image. All the game's art is painted with it
## at load time (no image files), so every pixel lands exactly where it should.

var image: Image
var width: int
var height: int


func _init(w: int, h: int, fill := Color(0, 0, 0, 0)) -> void:
	width = w
	height = h
	image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(fill)


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


func px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	if c.a >= 1.0:
		image.set_pixel(x, y, c)
	elif c.a > 0.0:
		image.set_pixel(x, y, image.get_pixel(x, y).blend(c))


func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Color(0, 0, 0, 0)
	return image.get_pixel(x, y)


func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	if c.a >= 1.0:
		var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, width, height))
		if r.size.x > 0 and r.size.y > 0:
			image.fill_rect(r, c)
		return
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(xx, yy, c)


## Scanline polygon fill with pixel-centre sampling, so shared edges never overlap or gap.
func poly(points: PackedVector2Array, c: Color) -> void:
	var y0 := floori(_min_y(points))
	var y1 := ceili(_max_y(points))
	for y in range(maxi(y0, 0), mini(y1, height)):
		var sy := y + 0.5
		var xs: Array[float] = []
		for k in points.size():
			var a := points[k]
			var b := points[(k + 1) % points.size()]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		if xs.size() < 2:
			continue
		xs.sort()
		var i := 0
		while i + 1 < xs.size():
			var xa := roundi(xs[i])
			var xb := roundi(xs[i + 1])
			if xb > xa:
				rect(xa, y, xb - xa, 1, c)
			i += 2


## Bresenham line, inclusive of both ends.
func line(a: Vector2, b: Vector2, c: Color) -> void:
	var x0 := roundi(a.x)
	var y0 := roundi(a.y)
	var x1 := roundi(b.x)
	var y1 := roundi(b.y)
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		px(x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


func disc(cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				px(x, y, c)


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				px(x, y, c)


func text(str: String, x: int, y: int, c: Color) -> void:
	PixelFont.plot_text(str, func(gx, gy): px(x + gx, y + gy, c))


func blit(src: PixelCanvas, x: int, y: int) -> void:
	for yy in src.height:
		for xx in src.width:
			var c := src.image.get_pixel(xx, yy)
			if c.a > 0.0:
				px(x + xx, y + yy, c)


## Ordered 2x2 dither: true on half the pixels in a checkerboard.
static func checker(x: int, y: int) -> bool:
	return (x + y) % 2 == 0


static func _min_y(points: PackedVector2Array) -> float:
	var m := INF
	for p in points:
		m = minf(m, p.y)
	return m


static func _max_y(points: PackedVector2Array) -> float:
	var m := -INF
	for p in points:
		m = maxf(m, p.y)
	return m
