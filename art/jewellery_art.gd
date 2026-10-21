class_name JewelleryArt
extends RefCounted
## Paints a piece of jewellery at any whole-number scale from its JewelleryPiece:
## 1 on the scale pan, 2 on the bench and 6 under the loupe. Shapes are laid out in
## base units and shaded per pixel from a surface normal, so every scale shows the
## same piece. Hallmarks, facet junctions, inclusions, bubbles and plating wear only
## resolve at loupe scale; on the bench they are a few telltale pixels.

## Canvas size in base units.
const SIZE := Vector2(84, 64)
const BENCH_SCALE := 2
const DETAIL_SCALE := 6
## Light from the top left, slightly in front.
const LIGHT := Vector3(-0.45, -0.7, 0.56)
const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
## Lower karats are paler and greener; the rest come from Pal.METAL.
const RAMPS := {
	"gold10": ["#2a1f08", "#5e4c1c", "#94792e", "#c4a64a", "#e2cb7c", "#f8ecc0"],
	"gold14": ["#2c1d06", "#664816", "#9e7424", "#d0a23e", "#eec872", "#fdf0c4"],
	"nickel": ["#24241f", "#555549", "#82816f", "#adab97", "#d2d0bd", "#f2f0e2"],
}
const STONE_RAMP := ["#07080c", "#20252f", "#4a5364", "#8b98ae", "#cfd9ea", "#ffffff"]
const GLASS_RAMP := ["#1a2026", "#36424c", "#5a6a74", "#7f9098", "#a9b8bc", "#d4e0e0"]
const FIRE := ["#ff5a5a", "#ffae3a", "#fff26a", "#6aff8a", "#5ad2ff", "#b47aff"]
## Share of facets that flash spectral colour, by stone. Simulants show more fire.
const FIRE_ODDS := {"diamond": 0.1, "cz": 0.22, "moissanite": 0.32, "glass": 0.03}

var p: JewelleryPiece
var s := 1
var l := {}
var c: PixelCanvas
var ramp: Array[Color] = []
var base_ramp: Array[Color] = []


## Paints `piece` at scale `scale` (canvas SIZE * scale pixels, transparent background).
static func paint(piece: JewelleryPiece, scale: int) -> PixelCanvas:
	var art := JewelleryArt.new()
	art.p = piece
	art.s = scale
	art.l = layout(piece)
	art.c = PixelCanvas.new(int(SIZE.x) * scale, int(SIZE.y) * scale)
	art.ramp = _ramp(piece.palette_name())
	art.base_ramp = _ramp(piece.base_metal if piece.base_metal != "" else piece.palette_name())
	art._paint()
	return art.c


## A flat shadow the same shape as a painted canvas.
static func shadow_of(canvas: PixelCanvas, alpha := 0.42) -> ImageTexture:
	var out := PixelCanvas.new(canvas.width, canvas.height)
	for y in canvas.height:
		for x in canvas.width:
			if canvas.image.get_pixel(x, y).a > 0.0:
				out.image.set_pixel(x, y, Color(0, 0, 0, alpha))
	return out.texture()


## Where things are on the piece, in base units: "stone" (Vector3 x, y, radius, or
## zero), "squash" (stone's vertical squash), "stamp" (centre of the hallmark),
## "clasp" (where a magnet would grab) and the shape data the painter needs.
static func layout(piece: JewelleryPiece) -> Dictionary:
	var out := {"stone": Vector3.ZERO, "squash": 1.0, "stamp": Vector2(42, 32), "clasp": Vector2(42, 32)}
	var rs := clampf(5.9 * pow(maxf(piece.carat, 0.01), 1.0 / 3.0), 2.4, 7.0)
	match piece.kind:
		"ring":
			var d := 4.5 if piece.stone != "" else 7.0
			var centre := Vector2(42, 42)
			out.band = {"c": centre, "ro": 19.0, "ri": 15.5, "d": d}
			out.stamp = Vector2(42, centre.y + 15.5 - d / 2.0)
			out.clasp = centre + Vector2(0, 17)
			if piece.stone != "":
				var top := centre.y - d - 19.0
				out.squash = 0.62
				out.stone = Vector3(42, top - rs * 0.62 - 2.0, rs)
		"chain":
			var pts := _bezier_points(Vector2(10, 48), Vector2(22, 2), Vector2(58, 68), Vector2(68, 17))
			out.links = _links_along(pts, 2.3)
			out.link_size = Vector3(1.8, 1.25, 0.45)
			out.clasp_at = [pts[0], (pts[0] - pts[3]).normalized()]
			out.tag = Rect2(71, 14.5, 11, 5)
			out.ring_at = pts[pts.size() - 1]
			out.stamp = out.tag.get_center() + Vector2(1.2, 0)
			out.clasp = pts[0] + (pts[0] - pts[3]).normalized() * 3.0
		"bracelet":
			var pts: Array[Vector2] = []
			for n in 240:
				var a := 0.55 + (TAU - 0.75) * n / 239.0
				pts.append(Vector2(42 + cos(a) * 27.0, 33 + sin(a) * 20.0))
			out.links = _links_along(pts, 2.9)
			out.link_size = Vector3(2.3, 1.6, 0.6)
			var end_dir := (pts[pts.size() - 1] - pts[pts.size() - 4]).normalized()
			out.clasp_at = [pts[pts.size() - 1], end_dir]
			out.tag = Rect2(70, 41.5, 11, 5)
			out.ring_at = pts[0]
			out.stamp = out.tag.get_center() + Vector2(1.2, 0)
			out.clasp = pts[pts.size() - 1] + end_dir * 3.0
		"pendant":
			var left := _bezier_points(Vector2(3, 0), Vector2(14, 12), Vector2(30, 16), Vector2(40.6, 16.5))
			var right := _bezier_points(Vector2(81, 0), Vector2(70, 12), Vector2(54, 16), Vector2(43.4, 16.5))
			out.links = _links_along(left, 1.65) + _links_along(right, 1.65)
			out.link_size = Vector3(1.3, 0.9, 0.32)
			out.medallion = {"c": Vector2(42, 40), "rx": 12.5, "ry": 15.5}
			out.stamp = Vector2(42, 40 + 15.5 * 0.74)
			out.clasp = Vector2(42, 40)
			if piece.stone != "":
				out.stone = Vector3(42, 38, minf(rs, 6.5))
	return out


static func _ramp(name: String) -> Array[Color]:
	var out: Array[Color] = []
	if RAMPS.has(name):
		for hex in RAMPS[name]:
			out.append(Color(hex))
	else:
		for tone in 6:
			out.append(Pal.metal(name, tone))
	return out


static func _bezier_points(a: Vector2, b: Vector2, c2: Vector2, d: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for n in 240:
		var t := n / 239.0
		var u := 1.0 - t
		out.append(a * u * u * u + b * 3.0 * u * u * t + c2 * 3.0 * u * t * t + d * t * t * t)
	return out


## Link centres and directions every `spacing` units along a polyline.
static func _links_along(pts: Array[Vector2], spacing: float) -> Array:
	var out := []
	var travelled := spacing * 0.5
	for n in range(1, pts.size()):
		var seg := pts[n] - pts[n - 1]
		travelled += seg.length()
		if travelled >= spacing:
			travelled -= spacing
			out.append([pts[n], seg.normalized()])
	return out


# ---------------------------------------------------------------- painting

func _paint() -> void:
	match p.kind:
		"ring":
			_band()
			if p.stone != "":
				_head()
		"chain", "bracelet":
			_chain()
			_clasp(l.clasp_at[0], l.clasp_at[1])
			_jump_ring(l.ring_at)
			_tag(l.tag)
		"pendant":
			_chain()
			_bail()
			_medallion()
			if p.stone != "":
				_bezel(Vector2(l.stone.x, l.stone.y), l.stone.z)
				_stone(Vector2(l.stone.x, l.stone.y), l.stone.z, 1.0)
	_stamp()


## Per-pixel metal: tone from the normal, base metal where the plating has worn through.
func _metal(x: int, y: int, u: float, v: float, n: Vector3, occlusion := 1.0, outline := false) -> void:
	var tone := _tone(n, x, y, occlusion)
	if outline:
		tone = mini(tone, 1)
	var worn := p.true_grade == "plated" and n.z > 0.72 \
		and CoinArt._hash(floori(u * 1.4), floori(v * 1.4), p.seed) > 0.8 and CoinArt._hash(x, y, p.seed + 5) > 0.3
	c.px(x, y, base_ramp[tone] if worn else ramp[tone])


func _tone(n: Vector3, x: int, y: int, occlusion := 1.0) -> int:
	var light := LIGHT.normalized()
	var diffuse := maxf(n.dot(light), 0.0)
	var half := (light + Vector3(0, 0, 1)).normalized()
	var spec := pow(maxf(n.dot(half), 0.0), 28.0)
	var env := 0.5 - 0.45 * n.y - 0.1 * n.x
	var v := (0.1 + 0.33 * env + 0.45 * diffuse) * occlusion + spec
	var amp := 0.9 if s >= 4 else 0.4
	return clampi(floori(v * 5.0 + (BAYER[y % 4][x % 4] / 16.0 - 0.47) * amp), 0, 5)


## Canvas pixel range covering a base-unit rectangle.
func _span(r: Rect2) -> Rect2i:
	var x0 := maxi(floori(r.position.x * s), 0)
	var y0 := maxi(floori(r.position.y * s), 0)
	var x1 := mini(ceili(r.end.x * s), c.width)
	var y1 := mini(ceili(r.end.y * s), c.height)
	return Rect2i(x0, y0, maxi(x1 - x0, 0), maxi(y1 - y0, 0))


## A ring standing on its edge, seen from the front and a little above: the domed
## front face, the outer surface across the top and the inner surface at the bottom,
## where the hallmark is struck.
func _band() -> void:
	var b: Dictionary = l.band
	var centre: Vector2 = b.c
	var ro: float = b.ro
	var ri: float = b.ri
	var d: float = b.d
	var back := centre - Vector2(0, d)
	var area := _span(Rect2(centre.x - ro - 1, back.y - ro - 1, ro * 2 + 2, ro * 2 + d + 2))
	var mid := (ri + ro) / 2.0
	var half := (ro - ri) / 2.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var rel := Vector2(u, v) - centre
			var relb := Vector2(u, v) - back
			var rf := rel.length()
			var rb := relb.length()
			if rf >= ri and rf <= ro:
				var q := (rf - mid) / half
				var rad := rel / maxf(rf, 0.001)
				var n := Vector3(rad.x * q * 0.85, rad.y * q * 0.85, sqrt(maxf(1.0 - 0.72 * q * q, 0.0)))
				_metal(x, y, u, v, n.normalized(), 1.0, absf(q) > 0.93 and s <= 2)
			elif rf < ri and rb >= ri:
				var radb := relb / maxf(rb, 0.001)
				var depth := clampf((rb - ri) / d, 0.0, 1.0)
				var n := Vector3(-radb.x * 0.7, -radb.y * 0.7, 0.4).normalized()
				_metal(x, y, u, v, n, 0.55 + depth * 0.3)
			elif rf > ro and rb <= ro:
				var radb := relb / maxf(rb, 0.001)
				var across := clampf((rf - ro) / d, 0.0, 1.0)
				var n := Vector3(radb.x * 0.8, radb.y * 0.8 - (across - 0.5) * 0.3, 0.42).normalized()
				_metal(x, y, u, v, n, 1.0, rb > ro - 0.35 / s * 2.0 and s <= 2)


## Basket and four claw prongs holding the stone on top of the band.
func _head() -> void:
	var st: Vector3 = l.stone
	var sq: float = l.squash
	var centre := Vector2(st.x, st.y)
	var rs := st.z
	var band_top: float = l.band.c.y - l.band.d - l.band.ro + 0.8
	# basket: a tapered cup under the stone
	var top_y := centre.y + rs * sq * 0.3
	var area := _span(Rect2(centre.x - rs, top_y, rs * 2, band_top - top_y + 0.5))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var t := clampf((v - top_y) / maxf(band_top - top_y, 0.1), 0.0, 1.0)
			var hw := lerpf(rs * 0.78, rs * 0.42, t)
			var q := (u - centre.x) / hw
			if absf(q) > 1.0:
				continue
			_metal(x, y, u, v, Vector3(q * 0.9, 0.15, sqrt(maxf(1.0 - 0.81 * q * q, 0.0))).normalized(), 0.9, absf(q) > 0.9 and s <= 2)
	var k := 0.71
	for side in [-1.0, 1.0]:
		_prong(Vector2(centre.x + side * rs * k, centre.y - rs * sq * k - 0.7), centre.y + rs * sq * 0.3)
	_stone(centre, rs, sq)
	for side in [-1.0, 1.0]:
		_prong(Vector2(centre.x + side * rs * k, centre.y + rs * sq * k - 0.9), top_y + 1.0)


## A claw prong: a round wire from `tip` straight down to `bottom_y`, domed at the tip.
func _prong(tip: Vector2, bottom_y: float) -> void:
	var r := 0.6
	var area := _span(Rect2(tip.x - r, tip.y - r, r * 2, bottom_y - tip.y + r))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2(u - tip.x, minf(v - tip.y, 0.0)) / r
			if off.length() > 1.0:
				continue
			var n := Vector3(off.x, off.y, sqrt(maxf(1.0 - off.length_squared(), 0.0)))
			_metal(x, y, u, v, n, 1.0, off.length() > 0.88 and s <= 2)


func _chain() -> void:
	var size: Vector3 = l.link_size
	# twisted links first, so the flat ones lie over them like a curb chain
	for pass_flat in [false, true]:
		for n in l.links.size():
			if (n % 2 == 0) != pass_flat:
				continue
			var at: Vector2 = l.links[n][0]
			var dir: Vector2 = l.links[n][1]
			if pass_flat:
				_link(at, dir, size.x, size.y, size.z)
			else:
				_bar(at, dir, size.x * 0.95, size.z * 1.05)


## One oval link of round wire, centred at `at` with its long axis along `dir`.
func _link(at: Vector2, dir: Vector2, rx: float, ry: float, w: float) -> void:
	var nrm := Vector2(-dir.y, dir.x)
	var reach := rx + w + 0.2
	var area := _span(Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	var mean := minf(rx, ry)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2(u, v) - at
			var a := off.dot(dir)
			var b := off.dot(nrm)
			var e := sqrt(a * a / (rx * rx) + b * b / (ry * ry))
			var q := (e - 1.0) * mean / w
			if absf(q) > 1.0:
				continue
			var g := Vector2(a / (rx * rx), b / (ry * ry)).normalized()
			var gs := dir * g.x + nrm * g.y
			var n := Vector3(gs.x * q, gs.y * q, sqrt(maxf(1.0 - q * q, 0.0)))
			_metal(x, y, u, v, n, 1.0, absf(q) > 0.86 and s <= 2)


## A link seen edge-on: a round wire running along `dir`.
func _bar(at: Vector2, dir: Vector2, half_len: float, w: float) -> void:
	var nrm := Vector2(-dir.y, dir.x)
	var reach := half_len + w + 0.2
	var area := _span(Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2(u, v) - at
			var a := clampf(off.dot(dir), -half_len, half_len)
			var rel := off - dir * a
			var q := rel.dot(nrm) / w
			if rel.length() > w:
				continue
			var round := rel / w
			var n := Vector3(round.x, round.y, sqrt(maxf(1.0 - round.length_squared(), 0.0)))
			_metal(x, y, u, v, n, 0.95, absf(q) > 0.86 and s <= 2)


## A lobster clasp hanging off the end of the chain, pointing along `dir`.
func _clasp(at: Vector2, dir: Vector2) -> void:
	var nrm := Vector2(-dir.y, dir.x)
	var centre := at + dir * 3.2
	var rx := 3.2
	var ry := 2.1
	var area := _span(Rect2(centre - Vector2(4.5, 4.5), Vector2(9, 9)))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2(u, v) - centre
			var a := off.dot(dir)
			var b := off.dot(nrm)
			# teardrop: narrower towards the chain end
			var taper := lerpf(0.65, 1.0, clampf((a + rx) / (rx * 1.4), 0.0, 1.0))
			var e2 := a * a / (rx * rx) + b * b / (ry * ry * taper * taper)
			var lever := a > -1.2 and a < 1.0 and b < -ry * taper + 0.2 and b > -ry * taper - 0.7
			if e2 > 1.0 and not lever:
				continue
			if lever and e2 > 1.0:
				_metal(x, y, u, v, Vector3(0, -0.4, 0.9).normalized(), 0.9, s <= 2)
				continue
			var g := Vector2(a / rx, b / (ry * taper))
			var gs := dir * g.x + nrm * g.y
			var n := Vector3(gs.x * 0.9, gs.y * 0.9, sqrt(maxf(1.0 - minf(e2, 1.0) * 0.81, 0.0)))
			_metal(x, y, u, v, n.normalized(), 1.0, e2 > 0.86 and s <= 2)
			# the gate: a dark slit around the inside of the hook
			if absf(sqrt(e2) - 0.55) < 0.6 / (s * 1.6) + 0.04 and b > -0.2 and a > -rx * 0.5:
				c.px(x, y, ramp[0])
	_jump_ring(at)


func _jump_ring(at: Vector2) -> void:
	_link(at, Vector2.RIGHT, 1.0, 1.0, 0.35)


## A flat stamped tag by the clasp, with a hole for its jump ring.
func _tag(r: Rect2) -> void:
	var area := _span(r)
	var hole := Vector2(r.position.x + 1.3, r.get_center().y)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var dl := u - r.position.x
			var dr := r.end.x - u
			var dt := v - r.position.y
			var db := r.end.y - v
			# rounded corners
			var cx := minf(dl, dr)
			var cy := minf(dt, db)
			if cx < 0.8 and cy < 0.8 and Vector2(0.8 - cx, 0.8 - cy).length() > 0.8:
				continue
			if Vector2(u, v).distance_to(hole) < 0.55:
				continue
			var edge := minf(cx, cy)
			var n := Vector3(0.04 * (CoinArt._hash(y, 1, p.seed) - 0.5), -0.18, 0.98)
			if edge < 0.55:
				var out := Vector2(-1 if dl < dr else 1, 0) if cx < cy else Vector2(0, -1 if dt < db else 1)
				n = Vector3(out.x * 0.75, out.y * 0.75, 0.66)
			_metal(x, y, u, v, n.normalized(), 1.0, edge < 0.25 and s <= 2)
	_jump_ring(Vector2(r.position.x - 0.4, r.get_center().y))


## The loop at the top of a pendant that the chain runs through.
func _bail() -> void:
	var r := Rect2(39.8, 14.5, 4.4, 9.5)
	var area := _span(r)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var q := (u - r.get_center().x) / (r.size.x / 2.0)
			var top := r.position.y + 2.0
			if v < top and Vector2(q, (v - top) / 2.0).length() > 1.0:
				continue
			var n := Vector3(q * 0.85, -0.2 if v < top else 0.1, sqrt(maxf(1.0 - 0.72 * q * q, 0.0))).normalized()
			if absf(q) < 0.32 and v > r.position.y + 1.2 and v < r.position.y + 4.0:
				c.px(x, y, ramp[0]) # the slot the chain passes through
				continue
			_metal(x, y, u, v, n, 1.0, absf(q) > 0.9 and s <= 2)


## A domed oval medallion with a raised rim. Plain ones carry an engraved sunburst.
func _medallion() -> void:
	var m: Dictionary = l.medallion
	var centre: Vector2 = m.c
	var rx: float = m.rx
	var ry: float = m.ry
	var area := _span(Rect2(centre.x - rx, centre.y - ry, rx * 2, ry * 2))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2((u - centre.x) / rx, (v - centre.y) / ry)
			var e := off.length()
			if e > 1.0:
				continue
			var dir := off / maxf(e, 0.001)
			var n: Vector3
			var occlusion := 1.0
			if e > 0.86:
				var q := (e - 0.93) / 0.07
				n = Vector3(dir.x * q * 0.9, dir.y * q * 0.9, sqrt(maxf(1.0 - 0.81 * q * q, 0.0)))
			else:
				n = Vector3(dir.x * e * 0.4, dir.y * e * 0.4, 1.0)
				if p.stone == "" and e > 0.2 and fposmod(atan2(off.y, off.x) * 16.0 / TAU, 1.0) < 0.14:
					occlusion = 0.6 # engraved ray
			_metal(x, y, u, v, n.normalized(), occlusion, e > 0.97 and s <= 2)


func _bezel(centre: Vector2, rs: float) -> void:
	var area := _span(Rect2(centre - Vector2(rs + 1.2, rs + 1.2), Vector2(rs + 1.2, rs + 1.2) * 2.0))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var off := Vector2(u, v) - centre
			var q := (off.length() - rs - 0.4) / 0.75
			if absf(q) > 1.0:
				continue
			var dir := off.normalized()
			_metal(x, y, u, v, Vector3(dir.x * q, dir.y * q, sqrt(maxf(1.0 - q * q, 0.0))), 1.0, absf(q) > 0.85 and s <= 2)


# ---------------------------------------------------------------- stones

## A round brilliant seen from above, squashed vertically by `sq` when tilted.
## Diamonds have crisp facet junctions and a pinpoint or feather inclusion; CZ is
## flawless but scuffed across the table; moissanite doubles every facet edge; glass
## is dull, rounded, bubbly and chipped at the girdle.
func _stone(centre: Vector2, rs: float, sq: float) -> void:
	var kind := p.stone
	var tones := GLASS_RAMP if kind == "glass" else STONE_RAMP
	var fire: float = FIRE_ODDS.get(kind, 0.1)
	var detail := s >= 4
	var px_r := rs * s
	var area := _span(Rect2(centre.x - rs, centre.y - rs * sq, rs * 2, rs * sq * 2))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var u := (x + 0.5) / s
			var v := (y + 0.5) / s
			var dx := (u - centre.x) / rs
			var dy := (v - centre.y) / (rs * sq)
			var r := sqrt(dx * dx + dy * dy)
			if r > 1.0:
				continue
			var f := _facet(dx, dy, px_r)
			var facet: int = f.x
			var tone := _facet_tone(facet, r, dx, dy, kind)
			var col: Color = Color(tones[tone])
			if CoinArt._hash(facet, 9, p.seed) < fire and r > 0.3:
				col = col.lerp(Color(FIRE[int(CoinArt._hash(facet, 4, p.seed) * 6.0) % 6]), 0.75 if detail else 0.5)
			if r > 1.0 - 1.2 / px_r:
				col = Color(tones[1]) # girdle edge
			elif detail and kind != "glass":
				if f.y < 0.7:
					col = Color(tones[4 if kind == "cz" else 5]).lerp(col, 0.25)
				elif kind == "moissanite":
					var g := _facet((u + 1.4 / s - centre.x) / rs, (v + 0.8 / s - centre.y) / (rs * sq), px_r)
					if g.y < 0.6:
						col = Color(tones[4]).lerp(col, 0.35) # birefringence: every edge seen twice
			c.px(x, y, col)
	if detail:
		_stone_details(centre, rs, sq, kind, tones)


## Facet id and the distance in canvas pixels to the nearest facet junction.
func _facet(dx: float, dy: float, px_r: float) -> Vector2:
	var r := sqrt(dx * dx + dy * dy)
	var a := atan2(dy, dx) + PI
	var oct := 0.5 / cos(fposmod(a, PI / 4.0) - PI / 8.0)
	var step: float
	var offset := 0.0
	var base := 0
	var ring_in := 0.0
	var ring_out := 1.0
	if r < oct:
		step = TAU / 16.0
		ring_out = oct
	elif r < 0.74:
		step = PI / 4.0
		offset = PI / 8.0
		base = 16
		ring_in = oct
		ring_out = 0.74
	elif r < 0.88:
		step = TAU / 16.0
		base = 24
		ring_in = 0.74
		ring_out = 0.88
	else:
		step = TAU / 32.0
		offset = TAU / 64.0
		base = 40
		ring_in = 0.88
	var t := fposmod(a + offset, TAU)
	var sector := int(t / step)
	var ang := minf(fposmod(t, step), step - fposmod(t, step)) * r * px_r
	var rad := minf(r - ring_in, ring_out - r) * px_r
	if base == 0:
		rad = (ring_out - r) * px_r
	return Vector2(base + sector, minf(ang, rad))


func _facet_tone(facet: int, r: float, dx: float, dy: float, kind: String) -> int:
	var h := CoinArt._hash(facet, 3, p.seed)
	var lit := -(dx * 0.6 + dy * 0.8) # facets turned towards the light catch it
	if facet < 16:
		# under the table: the pavilion's dark arrows between bright reflections
		var t := (2 if facet % 2 == 0 else 4) - (1 if r < 0.2 else 0)
		if kind == "glass":
			t = 3 if facet % 2 == 0 else 2
		return clampi(t + (1 if lit > 0.3 and h > 0.5 else 0), 0, 5)
	var table: Array = [1, 2, 3, 3, 4] if kind == "glass" else [0, 1, 2, 4, 5, 5]
	var t: int = table[int(h * table.size()) % table.size()]
	if lit > 0.45:
		t += 1
	return clampi(t, 0, 5)


func _stone_details(centre: Vector2, rs: float, sq: float, kind: String, tones: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed + 31
	var to_px := func(dx: float, dy: float) -> Vector2i:
		return Vector2i(floori((centre.x + dx * rs) * s), floori((centre.y + dy * rs * sq) * s))
	match kind:
		"diamond":
			# a pinpoint crystal and a small feather: nature's fingerprint
			var at: Vector2i = to_px.call(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.35, 0.35))
			c.px(at.x, at.y, Color(tones[0]))
			c.px(at.x + 1, at.y, Color(tones[1]))
			var fe: Vector2i = to_px.call(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.4, 0.4))
			for k in 4:
				c.px(fe.x + k, fe.y - k / 2, Color(tones[4]).lerp(Color(tones[2]), 0.3))
		"cz":
			# soft stone: scuffs across the table from years in a jewellery box
			for n in 3:
				var a: Vector2i = to_px.call(rng.randf_range(-0.45, 0.2), rng.randf_range(-0.4, 0.4))
				var len := rng.randi_range(4, 8)
				for k in len:
					c.px(a.x + k, a.y + (k / 3 if n % 2 == 0 else -k / 4), Color(tones[4]).lerp(Color(tones[3]), 0.4))
		"glass":
			for n in rng.randi_range(3, 5):
				var b: Vector2i = to_px.call(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.55, 0.55))
				var br := rng.randi_range(1, 2)
				for oy in range(-br - 1, br + 2):
					for ox in range(-br - 1, br + 2):
						var d := Vector2(ox, oy).length()
						if d <= br + 0.5 and d > br - 0.5:
							c.px(b.x + ox, b.y + oy, Color(tones[5]) if ox + oy < 0 else Color(tones[1]))
						elif d <= br - 0.5:
							c.px(b.x + ox, b.y + oy, Color(tones[3]))
			for n in 3:
				var a := rng.randf() * TAU
				var at: Vector2i = to_px.call(cos(a) * 0.95, sin(a) * 0.95)
				for oy in 2:
					for ox in 3:
						c.px(at.x + ox - 1, at.y + oy, Color(tones[0]))


# ---------------------------------------------------------------- hallmark

## Strikes the hallmark. Up close it is the real stamp: crisp with a maker's mark
## when genuine, uneven and double-struck when faked. On the bench it is a few dots.
func _stamp() -> void:
	var at: Vector2 = l.stamp
	var text := p.stamp
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed + 11
	var maker: String = "" if p.crude_stamp else ["JW", "AR", "UNO", "MB", "OR"][rng.randi() % 5]
	var full_w := PixelFont.measure(text) + (PixelFont.measure(maker) + 6 if maker != "" else 0)
	if s < 4:
		# just a dotted dent where the letters are
		var w := maxi(roundi(full_w * s / float(DETAIL_SCALE)), 2)
		var x0 := roundi(at.x * s - w / 2.0)
		for k in w:
			if k % 2 == 0:
				var y := roundi(_stamp_y(at, x0 + k) * s)
				c.px(x0 + k, y, ramp[1])
		return
	var x0 := roundi(at.x * s - full_w / 2.0)
	var jitter := {}
	if p.crude_stamp:
		for i in text.length():
			jitter[i] = rng.randi_range(-1, 1)
	var glyph_x := 0
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			glyph_x += PixelFont.SPACE_ADVANCE
			continue
		var dy: int = jitter.get(i, 0)
		_strike(ch, x0 + glyph_x, at, dy, 0)
		if p.crude_stamp and i % 2 == 0:
			_strike(ch, x0 + glyph_x + 1, at, dy, 1) # a second, lighter strike
		glyph_x += PixelFont.glyph_width(ch) + 1 + (rng.randi_range(0, 1) if p.crude_stamp else 0)
	if maker != "":
		var mx := x0 + PixelFont.measure(text) + 4
		var mw := PixelFont.measure(maker) + 3
		var top := roundi(_stamp_y(at, mx) * s) - 4
		for k in mw + 1:
			c.px(mx + k - 1, top, ramp[1])
			c.px(mx + k - 1, top + 8, ramp[1])
		for k in 9:
			c.px(mx - 1, top + k, ramp[1])
			c.px(mx + mw, top + k, ramp[1])
		var gx := 0
		for ch in maker:
			_strike(ch, mx + 1 + gx, at, 0, 0)
			gx += PixelFont.glyph_width(ch) + 1


## Recessed letter: dark strokes with a bright lip on their lower right.
func _strike(ch: String, x0: int, at: Vector2, dy: int, faint: int) -> void:
	var lit: Array[Vector2i] = []
	PixelFont.plot_text(ch, func(gx, gy): lit.append(Vector2i(x0 + gx, gy)))
	for q in lit:
		var y := roundi(_stamp_y(at, q.x) * s) - 2 + q.y + dy
		c.px(q.x, y, ramp[faint * 2])
		if faint == 0 and not lit.has(Vector2i(q.x + 1, q.y + 1)):
			c.px(q.x + 1, y + 1, ramp[4])


## Middle of the stamped strip at canvas column `x`; it follows the inside of a ring.
func _stamp_y(at: Vector2, x: int) -> float:
	if p.kind != "ring":
		return at.y
	var b: Dictionary = l.band
	var cx: float = b.c.x
	var u := (x + 0.5) / s - cx
	return b.c.y + sqrt(maxf(b.ri * b.ri - u * u, 0.0)) - b.d / 2.0
