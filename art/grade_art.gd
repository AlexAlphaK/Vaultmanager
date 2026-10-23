class_name GradeArt
extends RefCounted
## Paints a coin for the grading bench as two maps the lamp shader lights live:
##   relief    normal x and y, height, and the coin's outline (RGBA)
##   surface   lustre, hairlines, bag marks (RGB)
## The relief is built from the coin's design (CoinArt.MOTIFS) as a dome with fine hair
## and feather ridges on top, raised letters and a rim. Wear planes the dome off from the
## top down: the more wear, the wider the flat plateaus, and the ridges and the lustre go
## with them. Bag marks are cut in; a cleaned coin gets hairlines all one way.
## bake() paints at any scale: 1x for the bench, LOUPE_SCALE for the loupe.

const RADIUS := 60.0
const SIZE := 124
const LOUPE_SCALE := 3
const RIM := 0.75
const LETTER := 0.5
## Dome of the design: base height at its edge, the rise toward its middle, and how far
## in (pixels) the rise takes.
const DOME := Vector3(0.4, 0.6, 7.0)
## Fine ridges on the design: height and pixels between them.
const RIDGE := Vector2(0.08, 2.4)
## Relief steepness for the normals.
const STEEP := 3.5
const SHADER := """
shader_type canvas_item;
uniform sampler2D relief : filter_nearest;
uniform sampler2D surface : filter_nearest;
uniform vec3 light = vec3(-0.5, -0.5, 0.7);
uniform vec2 center_uv = vec2(0.5);
uniform vec2 span = vec2(1.0);
uniform bool loupe = false;
uniform vec4 backdrop : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform vec4 r0 : source_color;
uniform vec4 r1 : source_color;
uniform vec4 r2 : source_color;
uniform vec4 r3 : source_color;
uniform vec4 r4 : source_color;
uniform vec4 r5 : source_color;

const float BAYER[16] = float[16](0.0, 0.5, 0.125, 0.625, 0.75, 0.25, 0.875, 0.375,
	0.1875, 0.6875, 0.0625, 0.5625, 0.9375, 0.4375, 0.8125, 0.3125);

vec4 ramp(int i) {
	if (i <= 0) return r0;
	if (i == 1) return r1;
	if (i == 2) return r2;
	if (i == 3) return r3;
	if (i == 4) return r4;
	return r5;
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	if (loupe && length(d) > 0.5) discard;
	vec2 uv = loupe ? center_uv + d * span : UV;
	vec4 rel = texture(relief, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0 || rel.a < 0.5) {
		if (!loupe) discard;
		COLOR = backdrop;
	} else {
		vec4 surf = texture(surface, uv);
		vec3 n = normalize(vec3(rel.r * 2.0 - 1.0, rel.g * 2.0 - 1.0, 0.6));
		vec3 l = normalize(light);
		float diffuse = max(dot(n, l), 0.0);
		float v = 0.12 + 0.85 * diffuse;
		// lustre: the cartwheel, two bright spokes along the light's direction
		vec2 radial = uv - vec2(0.5);
		float az = atan(l.y, l.x);
		float ang = atan(radial.y, radial.x);
		float spoke = pow(abs(cos(ang - az)), 10.0);
		float flat_part = clamp(n.z * 1.3 - 0.2, 0.0, 1.0);
		v += surf.r * (0.15 + spoke * 0.75) * flat_part;
		// without lustre the metal is a dull, even grey
		v = mix(v * 0.85 + 0.08, v, surf.r);
		// hairlines catch a low light coming across them
		float grazing = clamp((0.75 - l.z) * 2.0, 0.0, 1.0);
		v += surf.g * grazing * 0.9;
		// bag marks: a nick catches the light on one side
		v -= surf.b * 0.35;
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float t = BAYER[p.y * 4 + p.x];
		int tone = clamp(int(floor(v * 5.0 + t - 0.25)), 0, 5);
		COLOR = ramp(tone);
	}
}
"""


## Paints coin `cg` at `scale` pixels per bench pixel. Returns {"relief", "surface"} Images.
static func bake(cg: CoinGrade, scale: int) -> Dictionary:
	var base := _base_layers(cg)
	var n := SIZE * scale
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var lustre := PackedFloat32Array()
	lustre.resize(n * n)
	var inside := PackedByteArray()
	inside.resize(n * n)
	var wear := cg.wear()
	var cap := 1.0 + RIDGE.x - wear * 0.62
	var rim_in := RADIUS - 5.0 - maxf(0.0, wear - 0.7) * 25.0
	var letter_h := LETTER * (1.0 - clampf((wear - 0.55) * 1.6, 0.0, 0.7))
	var rim_h := RIM - maxf(0.0, wear - 0.6) * 0.5
	var shine := cg.lustre()
	var ridge := RIDGE.x * (1.0 if scale > 1 else 0.45)
	var c := SIZE / 2.0
	var dev_centre: Vector2 = base.centre
	for y in n:
		for x in n:
			var u := (x + 0.5) / scale
			var v := (y + 0.5) / scale
			var dx := u - c
			var dy := v - c
			var d := sqrt(dx * dx + dy * dy)
			var i := y * n + x
			if d > RADIUS:
				continue
			inside[i] = 1
			var h := 0.0
			var lus := shine
			if d > rim_in:
				# the rim, rounded off on its outer edge
				h = rim_h * clampf((RADIUS - d) / 1.5, 0.3, 1.0)
				if d < rim_in + 1.0:
					h *= 0.85
				lus = 0.0 if wear > 0.3 else shine * 0.6
			else:
				var bx := int(u)
				var by := int(v)
				if base.letters.has(Vector2i(bx, by)):
					h = letter_h
				var dev := _bilinear(base.device, u, v)
				if dev > 0.02:
					var dist := _bilinear(base.dist, u, v)
					var dome := DOME.x + DOME.y * smoothstep(0.0, DOME.z, dist)
					var groove := _bilinear(base.groove, u, v)
					var p := Vector2(u, v) - dev_centre
					# hair and feathers: ridges running round the design's middle
					var ring := p.length() + sin(p.angle() * 7.0) * 1.2
					var fine := ridge * (0.5 + 0.5 * sin(ring / RIDGE.y * TAU))
					var top := (dome + fine) * smoothstep(0.0, 0.6, dev) - groove * 0.3
					if top > cap:
						top = cap
						lus = 0.0 # worn flat: dull, no lustre
					h = maxf(h, top)
			heights[i] = h
			lustre[i] = lus
	var surface := PackedByteArray()
	surface.resize(n * n * 4)
	# bag marks: short nicks cut into the surface
	for m in cg.marks:
		var a: Vector2 = (m[0] + Vector2(c, c)) * scale
		var b: Vector2 = (m[1] + Vector2(c, c)) * scale
		var steps := int(a.distance_to(b)) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			for o in ([Vector2i.ZERO] if scale == 1 else [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]):
				var q: Vector2i = Vector2i(p.floor()) + o
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
					continue
				var i: int = q.y * n + q.x
				heights[i] -= 0.12
				surface[i * 4 + 2] = 255
				lustre[i] = 0.0
	# hairlines from cleaning: fine scratches all one way, only fine enough to see close up
	if cg.cleaned and scale > 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = cg.seed + 3
		var dir := Vector2.from_angle(rng.randf_range(-0.6, 0.6))
		var across := Vector2(-dir.y, dir.x)
		for k in 70:
			var off := rng.randf_range(-RADIUS, RADIUS) * scale
			var start := Vector2(c, c) * scale + across * off + dir * rng.randf_range(-RADIUS, RADIUS) * scale
			var length := rng.randf_range(10.0, 40.0) * scale
			for t in int(length):
				var q := Vector2i((start + dir * t).floor())
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
					continue
				surface[(q.y * n + q.x) * 4 + 1] = 255
	var relief := PackedByteArray()
	relief.resize(n * n * 4)
	for y in n:
		for x in n:
			var i := y * n + x
			if inside[i] == 0:
				continue
			var hl := heights[i - 1] if x > 0 else heights[i]
			var hr := heights[i + 1] if x < n - 1 else heights[i]
			var hu := heights[i - n] if y > 0 else heights[i]
			var hd := heights[i + n] if y < n - 1 else heights[i]
			var sx := (hr - hl) * 0.5 * scale * STEEP
			var sy := (hd - hu) * 0.5 * scale * STEEP
			var nv := Vector3(-sx, -sy, 1.0).normalized()
			relief[i * 4] = clampi(roundi((nv.x * 0.5 + 0.5) * 255.0), 0, 255)
			relief[i * 4 + 1] = clampi(roundi((nv.y * 0.5 + 0.5) * 255.0), 0, 255)
			relief[i * 4 + 2] = clampi(roundi(clampf(heights[i], 0.0, 1.2) / 1.2 * 255.0), 0, 255)
			relief[i * 4 + 3] = 255
			surface[i * 4] = clampi(roundi(lustre[i] * 255.0), 0, 255)
			surface[i * 4 + 3] = 255
	return {"relief": Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, relief),
		"surface": Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, surface)}


## The design laid out at bench size: device coverage and grooves (bilinear grids),
## the distance in from the design's edge, the letter pixels and the design's middle.
static func _base_layers(cg: CoinGrade) -> Dictionary:
	var rows := CoinArt.motif_rows(cg.item.motif)
	var cols: int = rows[0].length()
	var c := SIZE / 2.0
	var inner := RADIUS - 16.0
	var aspect := float(rows.size()) / cols
	var w := inner * 1.5
	var h := w * aspect
	if h > inner * 1.35:
		h = inner * 1.35
		w = h / aspect
	var bx := c - w / 2.0
	var by := c - inner * 0.86
	var s := w / cols
	var device := PackedFloat32Array()
	device.resize(SIZE * SIZE)
	var groove := PackedFloat32Array()
	groove.resize(SIZE * SIZE)
	var solid := PackedByteArray()
	solid.resize(SIZE * SIZE)
	var sum := Vector2.ZERO
	var count := 0
	for y in SIZE:
		for x in SIZE:
			var u := (x + 0.5 - bx) / s - 0.5
			var v := (y + 0.5 - by) / s - 0.5
			var dv := _motif(rows, u, v, false)
			var gv := _motif(rows, u, v, true)
			device[y * SIZE + x] = dv
			groove[y * SIZE + x] = gv
			if dv > 0.5:
				solid[y * SIZE + x] = 1
				sum += Vector2(x + 0.5, y + 0.5)
				count += 1
	var dist := _distance(solid)
	var tones := {}
	for y in SIZE:
		for x in SIZE:
			if Vector2(x + 0.5 - c, y + 0.5 - c).length() <= RADIUS:
				tones[Vector2i(x, y)] = 0
	CoinArt._arc_text(tones, cg.item.legend, c, c, RADIUS - 12.5, -PI / 2.0, false)
	CoinArt._arc_text(tones, cg.item.fineness_text, c, c, RADIUS - 12.5, PI / 2.0, false)
	var year_w := PixelFont.measure(cg.item.year)
	CoinArt._flat_text(tones, cg.item.year, roundi(c - year_w / 2.0), roundi(c + inner * 0.62), false)
	var letters := {}
	for p in tones:
		if tones[p] == 5:
			letters[p] = true
	return {"device": device, "groove": groove, "dist": dist, "letters": letters,
		"centre": sum / maxf(count, 1) if count > 0 else Vector2(c, c)}


## Bilinear sample of a motif: '#' and 'v' cover the design; `grooves` reads 'v' only.
static func _motif(rows: Array, u: float, v: float, grooves: bool) -> float:
	var x0 := floori(u)
	var y0 := floori(v)
	var fx := u - x0
	var fy := v - y0
	var a := _cell(rows, x0, y0, grooves) * (1.0 - fx) + _cell(rows, x0 + 1, y0, grooves) * fx
	var b := _cell(rows, x0, y0 + 1, grooves) * (1.0 - fx) + _cell(rows, x0 + 1, y0 + 1, grooves) * fx
	return a * (1.0 - fy) + b * fy


static func _cell(rows: Array, x: int, y: int, grooves: bool) -> float:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return 0.0
	var ch: String = rows[y][x]
	if grooves:
		return 1.0 if ch == "v" else 0.0
	return 1.0 if ch == "#" or ch == "v" else 0.0


## Chamfer distance (in pixels) from each solid pixel to the nearest empty one.
static func _distance(solid: PackedByteArray) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE * SIZE)
	const BIG := 1e6
	for i in SIZE * SIZE:
		d[i] = BIG if solid[i] == 1 else 0.0
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			if d[i] == 0.0:
				continue
			var best := d[i]
			if x > 0:
				best = minf(best, d[i - 1] + 1.0)
			if y > 0:
				best = minf(best, d[i - SIZE] + 1.0)
				if x > 0:
					best = minf(best, d[i - SIZE - 1] + 1.414)
				if x < SIZE - 1:
					best = minf(best, d[i - SIZE + 1] + 1.414)
			d[i] = best
	for y in range(SIZE - 1, -1, -1):
		for x in range(SIZE - 1, -1, -1):
			var i := y * SIZE + x
			if d[i] == 0.0:
				continue
			var best := d[i]
			if x < SIZE - 1:
				best = minf(best, d[i + 1] + 1.0)
			if y < SIZE - 1:
				best = minf(best, d[i + SIZE] + 1.0)
				if x < SIZE - 1:
					best = minf(best, d[i + SIZE + 1] + 1.414)
				if x > 0:
					best = minf(best, d[i + SIZE - 1] + 1.414)
			d[i] = best
	return d


static func _bilinear(grid: PackedFloat32Array, u: float, v: float) -> float:
	var x := u - 0.5
	var y := v - 0.5
	var x0 := clampi(floori(x), 0, SIZE - 1)
	var y0 := clampi(floori(y), 0, SIZE - 1)
	var x1 := mini(x0 + 1, SIZE - 1)
	var y1 := mini(y0 + 1, SIZE - 1)
	var fx := clampf(x - x0, 0.0, 1.0)
	var fy := clampf(y - y0, 0.0, 1.0)
	var a := grid[y0 * SIZE + x0] * (1.0 - fx) + grid[y0 * SIZE + x1] * fx
	var b := grid[y1 * SIZE + x0] * (1.0 - fx) + grid[y1 * SIZE + x1] * fx
	return a * (1.0 - fy) + b * fy


## A material for the coin's lamp shader in `pal`'s colours.
static func material(pal: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	mat.shader = shader
	for k in 6:
		mat.set_shader_parameter("r%d" % k, Pal.metal(pal, k))
	return mat
