class_name CoinArt
extends RefCounted
## Paints a bullion coin face in relief: reeded edge, raised rim, bead ring,
## mirror field, frosted device, legends and a few bag marks.
## Counterfeits get a mushy strike, plating wear or misprinted text, as their kind dictates.

## Device masks: '#' raised, 'v' engraved groove, '.' field.
const MOTIFS := {
	"eagle": [
		"............#............",
		"...........###...........",
		"...........#.#...........",
		"...........###...........",
		"#...........#...........#",
		"##.........###.........##",
		"#v#.......#####.......#v#",
		".#v#.....#######.....#v#.",
		".##v#...#########...#v##.",
		"..##v#.###########.#v##..",
		"..###v#############v###..",
		"...###v###########v###...",
		"...####v#########v####...",
		"....#################....",
		".....###############.....",
		"......#############......",
		".......###########.......",
		"........##.###.##........",
		".......##..#.#..##.......",
		"......##...#.#...##......",
		".....#.#...#.#...#.#.....",
	],
	"leaf": [
		"...........#...........",
		"..........###..........",
		"..........###..........",
		".....#....###....#.....",
		".....##..#####..##.....",
		"......##.##v##.##......",
		"..#....####v####....#..",
		"..##...v###v###v...##..",
		"...#####v##v##v#####...",
		"....#####v#v#v#####....",
		"#...#######v#######...#",
		"##.v#######v#######v.##",
		".###v######v######v###.",
		"..###v#####v#####v###..",
		"...####v###v###v####...",
		"....#####v#v#v#####....",
		".....######v######.....",
		"......#####v#####......",
		"........###v###........",
		"...........#...........",
		"...........#...........",
		"...........#...........",
	],
	"springbok": [
		".................#.#......",
		"................#..#......",
		"................#.#.......",
		"................####......",
		"...............######.....",
		"...............###..##....",
		"..............###.........",
		"..#..........###..........",
		"...###########v#..........",
		"....##########v#..........",
		"....###########...........",
		".....##########...........",
		"......########............",
		"......##....##............",
		".....##......##...........",
		"....##........##..........",
		"...##..........##.........",
		"..##............#.........",
		".#...............#........",
	],
	"britannia": [
		"............#............",
		"..........#.#.#..........",
		"..........#####..........",
		"............#............",
		"....#################....",
		"....########v########....",
		"....########v########....",
		"....########v########....",
		"....vvvvvvvvvvvvvvvvv....",
		"....########v########....",
		".....#######v#######.....",
		"......######v######......",
		".......#####v#####.......",
		"........####v####........",
		"..........##v##..........",
		"............#............",
		"............#............",
	],
}
## Light comes from the top left.
## MOTIFS as plain copies, safe to read from the grading loupe's worker thread while the
## main thread paints coins (see PixelFont._glyphs).
static var _motifs: Dictionary = MOTIFS.duplicate(true)
const LIGHT := Vector2(-0.6, -0.8)
const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
## Pixels per millimetre of coin diameter on the testing bench.
const PX_PER_MM := 1.45


## Paints one coin. `fake` is a Counterfeit kind or "". `seed` varies bag marks and misprints.
static func paint(item: BullionItem, fake := "", seed := 1) -> PixelCanvas:
	var k: Dictionary = Counterfeit.KINDS.get(fake, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mm := item.diameter_mm + float(k.get("d_mm", 0.0))
	var r := roundf(mm * PX_PER_MM)
	var size := int(r) * 2 + 4
	var c := PixelCanvas.new(size, size)
	var cx := size / 2.0
	var cy := size / 2.0
	var pal: String = k.get("palette", "") if k.get("palette", "") != "" else item.palette_name()
	var wear: String = k.get("wear", "")
	var soft: bool = k.get("soft_strike", false)
	var inner := r - (16.0 if item.bead_ring else 14.0)
	var height := _device_heights(item.motif, cx, cy, inner)
	var tones := {}

	for y in size:
		for x in size:
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r:
				continue
			var n := Vector2(dx, dy) / maxf(d, 0.001)
			var facing := -n.dot(LIGHT) # 1 on the lit top-left edge, -1 bottom-right
			var tone: int
			if d > r - 0.8:
				tone = 0 if facing < 0.3 else 1
			elif d > r - 2.0:
				var reed := int(floor((n.angle() + PI) * r / 1.3)) % 2
				tone = 2 + reed + (1 if facing > 0.2 else 0)
				if wear == "copper" and rng.randf() < 0.85:
					tone = -tone # marks a copper pixel, resolved below
			elif d > r - 5.0:
				tone = 4 if facing > -0.1 else 3
				if facing > 0.55 and d > r - 3.0:
					tone = 5
			elif d > r - 6.0:
				tone = 1 if facing > 0.0 else 4
			else:
				tone = _field_tone(x, y, dx, dy, r, item.radial_lines and fake == "", n)
				var h := _h(height, x, y)
				if h > 0.42:
					var lit := _h(height, x + 1, y + 1) - _h(height, x - 1, y - 1)
					if soft:
						lit *= 0.45
					tone = 4
					if lit > 0.22:
						tone = 5
					elif lit < -0.3:
						tone = 2
					elif lit < -0.1:
						tone = 3
					var frost := _hash(x, y, seed)
					if soft:
						if frost < 0.22:
							tone = 3
					elif tone == 4 and frost < 0.18:
						tone = 5
					elif tone == 5 and frost < 0.08:
						tone = 4
				elif _h(height, x - 1, y - 1) > 0.42 or _h(height, x - 2, y - 2) > 0.6:
					tone -= 1 # shadow cast by the device onto the field
			tones[Vector2i(x, y)] = tone

	if item.bead_ring:
		_bead_ring(tones, cx, cy, r - 8.0, soft)
	var legend := item.legend
	var fineness := item.fineness_text
	if rng.randf() < float(k.get("misprint", 0.0)):
		fineness = _misprint(fineness, rng)
	_arc_text(tones, legend, cx, cy, r - 12.5, -PI / 2.0, soft)
	_arc_text(tones, fineness, cx, cy, r - 12.5, PI / 2.0, soft)
	var year_w := PixelFont.measure(item.year)
	_flat_text(tones, item.year, roundi(cx - year_w / 2.0), roundi(cy + inner * 0.56), soft)
	_bag_marks(tones, cx, cy, inner, rng)

	for key in tones:
		var t: int = tones[key]
		var col: Color
		if t < 0:
			col = Pal.metal("copper", -t)
		elif wear == "steel" and t >= 4 and rng.randf() < 0.08:
			col = Pal.metal("steel", t - 1)
		else:
			col = Pal.metal(pal, t)
		c.px(key.x, key.y, col)
	return c


## Radius in pixels of the painted coin for this item and fake kind.
static func radius_of(item: BullionItem, fake := "") -> int:
	var k: Dictionary = Counterfeit.KINDS.get(fake, {})
	return int(roundf((item.diameter_mm + float(k.get("d_mm", 0.0))) * PX_PER_MM))


static func _field_tone(x: int, y: int, dx: float, dy: float, r: float, radial: bool, n: Vector2) -> int:
	# Mirror field: darker overall with a bright diagonal reflection band, dithered.
	var diag := (dx - dy) / (r * 1.6)
	var band := exp(-pow((dx + dy) / r + 0.35, 2.0) * 6.0)
	var v := 2.0 + band * 1.6 - diag * 0.2
	if radial and int(floor((n.angle() + PI) * 64.0 / PI)) % 2 == 0:
		v -= 0.45
	var threshold: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0
	return clampi(int(floor(v)) + (1 if fmod(v, 1.0) > threshold else 0), 1, 4)


## The motif's device mask, one string per row (the eagle for an unknown motif).
static func motif_rows(motif: String) -> Array:
	return _motifs.get(motif, _motifs["eagle"])


static func _device_heights(motif: String, cx: float, cy: float, inner: float) -> Dictionary:
	var rows := motif_rows(motif)
	var cols: int = rows[0].length()
	var aspect := float(rows.size()) / cols
	var w := inner * 1.45
	var h := w * aspect
	if h > inner * 1.3:
		h = inner * 1.3
		w = h / aspect
	var bx := cx - w / 2.0
	var by := cy - inner * 0.82
	var s := w / cols
	var raw := {}
	for y in range(floori(by) - 2, ceili(by + h) + 3):
		for x in range(floori(bx) - 2, ceili(bx + w) + 3):
			raw[Vector2i(x, y)] = _sample(rows, (x + 0.5 - bx) / s - 0.5, (y + 0.5 - by) / s - 0.5)
	var smooth := {}
	for key in raw:
		var sum := 0.0
		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				sum += raw.get(key + Vector2i(ox, oy), 0.0)
		smooth[key] = sum / 9.0
	return smooth


static func _sample(rows: Array, u: float, v: float) -> float:
	var x0 := floori(u)
	var y0 := floori(v)
	var fx := u - x0
	var fy := v - y0
	var a := _cell(rows, x0, y0) * (1.0 - fx) + _cell(rows, x0 + 1, y0) * fx
	var b := _cell(rows, x0, y0 + 1) * (1.0 - fx) + _cell(rows, x0 + 1, y0 + 1) * fx
	return a * (1.0 - fy) + b * fy


static func _cell(rows: Array, x: int, y: int) -> float:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return 0.0
	match rows[y][x]:
		"#":
			return 1.0
		"v":
			return 0.35
	return 0.0


static func _h(height: Dictionary, x: int, y: int) -> float:
	return height.get(Vector2i(x, y), 0.0)


static func _bead_ring(tones: Dictionary, cx: float, cy: float, radius: float, soft: bool) -> void:
	var count := int(TAU * radius / 3.0)
	for i in count:
		if soft and i % 7 == 3:
			continue
		var a := TAU * i / count
		var p := Vector2i(roundi(cx + cos(a) * radius - 0.5), roundi(cy + sin(a) * radius - 0.5))
		tones[p] = 5
		var shadow := p + Vector2i(1, 1)
		if tones.has(shadow) and not soft:
			tones[shadow] = 1


## Upright glyphs spaced along an arc centred on `centre_angle` (-PI/2 top, PI/2 bottom).
static func _arc_text(tones: Dictionary, text: String, cx: float, cy: float, radius: float, centre_angle: float, soft: bool) -> void:
	if text == "":
		return
	var advance := 5.6
	var span := text.length() * advance / radius
	var dir := 1.0 if centre_angle < 0.0 else -1.0 # read left to right at top and bottom
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			continue
		var a := centre_angle - dir * span / 2.0 + dir * span * (i + 0.5) / text.length()
		var gx := roundi(cx + cos(a) * radius - PixelFont.glyph_width(ch) / 2.0)
		var gy := roundi(cy + sin(a) * radius - 2.5)
		_flat_text(tones, ch, gx, gy, soft)


static func _flat_text(tones: Dictionary, text: String, x: int, y: int, soft: bool) -> void:
	var lit: Array[Vector2i] = []
	PixelFont.plot_text(text, func(gx, gy): lit.append(Vector2i(x + gx, y + gy)))
	for p in lit:
		if not tones.has(p):
			continue
		tones[p] = 4 if soft else 5
		var shadow := p + Vector2i(1, 1)
		if not soft and tones.has(shadow) and not lit.has(shadow):
			tones[shadow] = 1


static func _bag_marks(tones: Dictionary, cx: float, cy: float, inner: float, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 5):
		var a := rng.randf() * TAU
		var dist := rng.randf_range(0.3, 1.0) * inner
		var p := Vector2(cx + cos(a) * dist, cy + sin(a) * dist)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for step in rng.randi_range(2, 4):
			var q := Vector2i(roundi(p.x + dir.x * step), roundi(p.y + dir.y * step))
			if tones.has(q) and tones[q] >= 0 and tones[q] <= 3:
				tones[q] = 4 if step % 2 == 0 else 1


static func _misprint(text: String, rng: RandomNumberGenerator) -> String:
	var swaps := [["9999", "999"], ["GOLD", "GLOD"], ["SILVER", "SILVRE"], ["OZ", "0Z"], ["FINE", "FlNE"], ["999", "99.9"]]
	swaps.shuffle()
	for s in swaps:
		if text.contains(s[0]):
			return text.replace(s[0], s[1])
	return text + "."


## 0..1 hash for per-pixel noise that stays stable across repaints.
static func _hash(x: int, y: int, seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10000) / 10000.0
