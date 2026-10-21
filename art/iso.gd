class_name Iso
extends RefCounted
## 2:1 isometric projection and face painters. A tile is 32x16 px; i runs down-right,
## j runs down-left, z is height in pixels. Faces are painted by inverting the
## projection per screen pixel, so textures on walls and boxes skew pixel-perfectly.

const HALF_W := 16.0
const HALF_H := 8.0

var origin: Vector2
var canvas: PixelCanvas


func _init(target: PixelCanvas, screen_origin: Vector2) -> void:
	canvas = target
	origin = screen_origin


func p(i: float, j: float, z := 0.0) -> Vector2:
	return Vector2(origin.x + (i - j) * HALF_W, origin.y + (i + j) * HALF_H - z)


## Paints the horizontal plane at height `z` over [i0,i1]x[j0,j1]. `shade(i, j)` returns a Color or null.
func top(i0: float, j0: float, i1: float, j1: float, z: float, shade: Callable) -> void:
	var box := _bounds([p(i0, j0, z), p(i1, j0, z), p(i1, j1, z), p(i0, j1, z)])
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var a := (x + 0.5 - origin.x) / HALF_W
			var b := (y + 0.5 + z - origin.y) / HALF_H
			var i := (a + b) / 2.0
			var j := (b - a) / 2.0
			if i >= i0 and i < i1 and j >= j0 and j < j1:
				_put(x, y, shade.call(i, j))


## Paints the vertical plane j = `j` (it faces down-left) over [i0,i1]x[z0,z1]. `shade(i, z)`.
func face_j(j: float, i0: float, i1: float, z0: float, z1: float, shade: Callable) -> void:
	var box := _bounds([p(i0, j, z0), p(i1, j, z0), p(i1, j, z1), p(i0, j, z1)])
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var i := (x + 0.5 - origin.x) / HALF_W + j
			var z := origin.y + (i + j) * HALF_H - (y + 0.5)
			if i >= i0 and i < i1 and z >= z0 and z < z1:
				_put(x, y, shade.call(i, z))


## Paints the vertical plane i = `i` (it faces down-right) over [j0,j1]x[z0,z1]. `shade(j, z)`.
func face_i(i: float, j0: float, j1: float, z0: float, z1: float, shade: Callable) -> void:
	var box := _bounds([p(i, j0, z0), p(i, j1, z0), p(i, j1, z1), p(i, j0, z1)])
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var j := i - (x + 0.5 - origin.x) / HALF_W
			var z := origin.y + (i + j) * HALF_H - (y + 0.5)
			if j >= j0 and j < j1 and z >= z0 and z < z1:
				_put(x, y, shade.call(j, z))


## A solid box with flat colours: {top, left, right} and an optional highlight `edge`.
func box(i: float, j: float, w: float, d: float, h: float, cols: Dictionary, z0 := 0.0) -> void:
	face_j(j + d, i, i + w, z0, z0 + h, func(_a, _b): return cols.left)
	face_i(i + w, j, j + d, z0, z0 + h, func(_a, _b): return cols.right)
	top(i, j, i + w, j + d, z0 + h, func(_a, _b): return cols.top)
	if cols.has("edge"):
		canvas.line(p(i, j + d, z0 + h), p(i + w, j + d, z0 + h), cols.edge)
		canvas.line(p(i + w, j, z0 + h), p(i + w, j + d, z0 + h), cols.edge)


## Text painted flat on the wall i = 0, centred between j0 and j1, cap line at height `z_top`.
func text_on_i_wall(text: String, j0: float, j1: float, z_top: float, c: Color, plot := Callable()) -> void:
	var w := PixelFont.measure(text)
	var start := j1 - ((j1 - j0) * HALF_W - w) / 2.0 / HALF_W
	var base := p(0, start, z_top)
	var put := plot if plot.is_valid() else func(x, y): canvas.px(x, y, c)
	PixelFont.plot_text(text, func(x, y): put.call(floori(base.x) + x, floori(base.y) - floori(x / 2.0) + y))


## Text painted flat on the wall j = 0, starting at `i0`, cap line at height `z_top`.
func text_on_j_wall(text: String, i0: float, z_top: float, c: Color, plot := Callable()) -> void:
	var base := p(i0, 0, z_top)
	var put := plot if plot.is_valid() else func(x, y): canvas.px(x, y, c)
	PixelFont.plot_text(text, func(x, y): put.call(floori(base.x) + x, floori(base.y) + floori(x / 2.0) + y))


func line3(a: Vector3, b: Vector3, c: Color) -> void:
	canvas.line(p(a.x, a.y, a.z), p(b.x, b.y, b.z), c)


func _put(x: int, y: int, c) -> void:
	if c != null:
		canvas.px(x, y, c)


func _bounds(points: Array) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in points:
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2i(Vector2i(floori(lo.x) - 1, floori(lo.y) - 1), Vector2i(ceili(hi.x - lo.x) + 3, ceili(hi.y - lo.y) + 3))
