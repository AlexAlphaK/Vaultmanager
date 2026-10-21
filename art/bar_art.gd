class_name BarArt
extends RefCounted
## Paints a bullion bar's top face. Minted bars are crisp, bevelled and mirror bright
## with raised lettering in a frame; cast bars have soft rounded edges, sloped sides, a
## rippled pour surface and letters punched into it. The marks are laid out in
## millimetres, so the same bar paints at bench size and at the loupe's detail size,
## where the small print becomes readable. Fakes get crude punches, misspellings and
## worn corners where the base metal shows through.

## The loupe magnifies at least this much, and enough to show the serial number's
## letters at this many pixels per font pixel.
const MIN_ZOOM := 2.0
const SERIAL_PX := 2.4
## Bars are shown between these widths on the bench, whatever their real size.
const BENCH_W := 150.0
const MAX_PPM := 2.6
const METAL_WORDS := {"XAU": "FINE GOLD", "XAG": "FINE SILVER", "XPT": "PLATINUM"}

var bar: BullionBar
var ppm := 2.0
var c: PixelCanvas
var ramp: Array[Color] = []
var wear_ramp: Array[Color] = []
var marks: Array[Dictionary] = []
var l_mm := 0.0
var w_mm := 0.0


## Pixels per millimetre on the bench: small bars are shown larger.
static func bench_ppm(b: BullionBar) -> float:
	return minf(MAX_PPM, BENCH_W / float(b.spec().l))


## Pixels per millimetre of the loupe's painting.
static func detail_ppm(b: BullionBar) -> float:
	var cell := 1.0
	for m in layout(b):
		if m.serial:
			cell = m.cell
	return maxf(bench_ppm(b) * MIN_ZOOM, SERIAL_PX / cell)


static func paint(b: BullionBar, px_per_mm: float) -> PixelCanvas:
	var art := BarArt.new()
	art.bar = b
	art.ppm = px_per_mm
	art.l_mm = b.spec().l
	art.w_mm = b.spec().w
	art.c = PixelCanvas.new(ceili(art.l_mm * px_per_mm), ceili(art.w_mm * px_per_mm))
	art.ramp = _ramp(b.palette_name())
	var wear: String = BullionBar.FAKES[b.fake].wear if b.fake != "" else ""
	art.wear_ramp = _ramp(wear if wear != "" else b.palette_name())
	art.marks = layout(b)
	art._paint()
	return art.c


## Where the serial number is, as a share of the top face (for the loupe).
static func serial_rect(b: BullionBar) -> Rect2:
	for m in layout(b):
		if m.get("serial", false):
			var s := b.spec()
			return Rect2(m.x0 / s.l, m.y0 / s.w, m.bw * m.cell / s.l, m.bh * m.cell / s.w)
	return Rect2()


## The marks on the bar: each a bitmap of text in millimetres. `depth` is +1 raised
## (minted) or -1 punched (cast).
static func layout(b: BullionBar) -> Array[Dictionary]:
	var s := b.spec()
	var crude: bool = b.fake != "" and BullionBar.FAKES[b.fake].crude
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var metal_word: String = METAL_WORDS[s.metal]
	var fine: String = s.fine_text
	if crude:
		# a cheap die: one word is wrong
		if rng.randf() < 0.5:
			metal_word = _misprint(metal_word)
		else:
			fine = _misprint(fine)
	var depth := -1 if s.cast else 1
	var w: float = s.w
	var lines: Array = []
	if s.cast:
		lines = [[s.maker, 0.026], [s.weight_text, 0.05], [metal_word + " " + fine, 0.026], ["ASSAYER MELTER", 0.014], [b.serial, 0.021]]
	else:
		lines = [[s.maker, 0.022], [s.weight_text, 0.04], [metal_word, 0.02], [fine, 0.027], ["ESSAYEUR FONDEUR", 0.012], [b.serial, 0.014]]
	var bitmaps: Array[Dictionary] = []
	var heights := 0.0
	for line in lines:
		var m := _bitmap(line[0], crude, rng)
		m.cell = minf(line[1] * w, s.l * 0.8 / m.bw)
		heights += m.cell * 5.0
		bitmaps.append(m)
	var gap := (w * (0.66 if s.cast else 0.72) - heights) / (lines.size() - 1)
	var y := (w - heights - gap * (lines.size() - 1)) / 2.0
	var out: Array[Dictionary] = []
	for n in bitmaps.size():
		var m := bitmaps[n]
		m.x0 = (s.l - m.bw * m.cell) / 2.0 + (rng.randf_range(-1.0, 1.0) * m.cell if crude else 0.0)
		m.y0 = y
		m.depth = depth
		m.serial = n == bitmaps.size() - 1
		out.append(m)
		y += m.cell * 5.0 + gap
	return out


static func _misprint(text: String) -> String:
	for s in [["GOLD", "GLOD"], ["SILVER", "SILVRE"], ["PLATINUM", "PLATNIUM"], ["999.9", "99.99"], ["999.5", "995.5"], ["999", "99.9"]]:
		if text.contains(s[0]):
			return text.replace(s[0], s[1])
	return text + "."


## A line of text as a bitmap, one byte per font pixel. Crude punches wander up and down.
static func _bitmap(text: String, crude: bool, rng: RandomNumberGenerator) -> Dictionary:
	var bw := PixelFont.measure(text)
	var bh := 7 if crude else 5
	var bits := PackedByteArray()
	bits.resize(maxi(bw, 1) * bh)
	var x := 0
	for ch in text:
		if ch == " ":
			x += PixelFont.SPACE_ADVANCE
			continue
		var rows: Array = PixelFont.GLYPHS.get(ch, PixelFont.GLYPHS["?"])
		var dy := rng.randi_range(0, 2) if crude else 0
		for gy in rows.size():
			for gx in rows[gy].length():
				if rows[gy][gx] == "#":
					bits[(gy + dy) * bw + x + gx] = 1
		x += rows[0].length() + 1
	return {"bits": bits, "bw": bw, "bh": bh}


## Straight from Pal.METAL rather than Pal.metal(), whose cache is not safe to fill
## from the loupe painting's worker thread.
static func _ramp(name: String) -> Array[Color]:
	var out: Array[Color] = []
	for hex in Pal.METAL.get(name, Pal.METAL["silver"]):
		out.append(Color(hex))
	return out


## Height of the relief at a point in millimetres: 0 on the face.
func _height(mx: float, my: float) -> int:
	if not bar.is_cast():
		# the raised frame of a minted bar
		var inset := minf(mx, l_mm - mx)
		inset = minf(inset, minf(my, w_mm - my))
		var f := w_mm * 0.06
		if inset >= f and inset < f + w_mm * 0.018:
			return 1
	for m in marks:
		var u: float = (mx - m.x0) / m.cell
		var v: float = (my - m.y0) / m.cell
		if u < 0.0 or v < 0.0 or u >= m.bw or v >= m.bh:
			continue
		if m.bits[int(v) * m.bw + int(u)]:
			return m.depth
	return 0


func _paint() -> void:
	var cast := bar.is_cast()
	var corner := w_mm * (0.14 if cast else 0.035)
	var slope := w_mm * (0.09 if cast else 0.025)
	var px := 1.0 / ppm
	var wear: bool = bar.fake != "" and BullionBar.FAKES[bar.fake].wear != ""
	var cw := c.width
	# relief heights, one per pixel with a border, so each pixel looks up its neighbours
	var hw := cw + 2
	var hmap := PackedByteArray()
	hmap.resize(hw * (c.height + 2))
	for y in c.height:
		for x in cw:
			hmap[(y + 1) * hw + x + 1] = _height((x + 0.5) * px, (y + 0.5) * px) + 1
	for y in c.height:
		var my := (y + 0.5) * px
		for x in cw:
			var mx := (x + 0.5) * px
			# distance into a rounded rectangle, and the outward direction
			var qx := maxf(corner - mx, mx - (l_mm - corner))
			var qy := maxf(corner - my, my - (w_mm - corner))
			var inside := 0.0
			var n := Vector2.ZERO
			if qx > 0.0 and qy > 0.0:
				inside = corner - Vector2(qx, qy).length()
				n = Vector2(signf(mx - l_mm / 2.0) * qx, signf(my - w_mm / 2.0) * qy).normalized()
			else:
				var dx := minf(mx, l_mm - mx)
				var dy := minf(my, w_mm - my)
				inside = minf(dx, dy)
				n = Vector2(signf(mx - l_mm / 2.0), 0.0) if dx < dy else Vector2(0.0, signf(my - w_mm / 2.0))
			if inside < 0.0:
				continue
			var noise := CoinArt._hash(x, y, bar.seed)
			var tone := 3
			if inside < slope:
				# bevel or sloped side, lit from the top left
				var lit := -(n.x + n.y)
				tone = 3 + roundi(lit * (1.6 if cast else 2.0))
				if inside < px * 1.2:
					tone -= 1
				if cast and noise > 0.86:
					tone -= 1
			else:
				tone = _face_tone(mx, my, noise, x, y)
				var at := (y + 1) * hw + x + 1
				var h := hmap[at]
				var up := hmap[at - hw - 1]
				var down := hmap[at + hw + 1]
				if h > 1:
					tone = 4 if noise > 0.3 else 3 # frosted letters
					if up < h:
						tone = 5
					elif down < h:
						tone = 1
				elif h < 1:
					tone = 2
					if up > h:
						tone = 1
					elif down > h:
						tone = 4
			var col := ramp[clampi(tone, 0, 5)]
			if wear and _worn(mx, my):
				col = wear_ramp[clampi(tone - 1, 0, 5)]
			c.image.set_pixel(x, y, col)


## The flat face: a mirror sheen across a minted bar, a rippled pour on a cast one.
func _face_tone(mx: float, my: float, noise: float, x: int, y: int) -> int:
	var u := mx / l_mm
	var v := my / w_mm
	if not bar.is_cast():
		var d := u * 0.7 + v * 0.3
		if d > 0.22 and d < 0.34:
			return 5 if absf(d - 0.28) < 0.02 else 4
		if d > 0.78:
			return 2
		return 3
	var ripple := sin(u * 23.0 + sin(v * 9.0) * 1.7) + sin(v * 17.0 - u * 5.0) * 0.6
	var tone := 3
	if ripple > 1.3:
		tone = 4
	elif ripple < -1.35:
		tone = 2
	if noise > 0.993:
		tone = 1 # a pit from the pour
	elif noise < 0.008:
		tone = 5
	var edge := minf(minf(u, 1.0 - u) * l_mm, minf(v, 1.0 - v) * w_mm)
	if edge < w_mm * 0.13 and CoinArt._hash(x / 2, y / 2, bar.seed + 7) > 0.7:
		tone -= 1 # shrinkage at the rim of the mould
	return tone


## Plating rubbed through at the corners.
func _worn(mx: float, my: float) -> bool:
	var r := w_mm * 0.16
	for corner in [Vector2(0, 0), Vector2(l_mm, 0), Vector2(0, w_mm), Vector2(l_mm, w_mm)]:
		var d := Vector2(mx, my).distance_to(corner)
		if d < r and CoinArt._hash(int(mx * 3.0), int(my * 3.0), bar.seed + 3) > 0.45 + d / r * 0.5:
			return true
	return false
