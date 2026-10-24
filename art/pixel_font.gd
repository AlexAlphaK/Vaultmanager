class_name PixelFont
extends RefCounted
## The game's bitmap font, built in code so text stays pixel-perfect at any window size.
## Caps are 5 px tall, lowercase has a 4 px x-height, and descenders drop 2 px.
## Use size 8 for body text and 16 for titles (whole-number scaling only).

const SIZE := 8
const ASCENT := 6
const DESCENT := 2
## Rows 0-4 sit above the baseline, rows 5-6 are descenders.
const GLYPHS := {
	"A": [".##.", "#..#", "####", "#..#", "#..#"],
	"B": ["###.", "#..#", "###.", "#..#", "###."],
	"C": [".###", "#...", "#...", "#...", ".###"],
	"D": ["###.", "#..#", "#..#", "#..#", "###."],
	"E": ["####", "#...", "###.", "#...", "####"],
	"F": ["####", "#...", "###.", "#...", "#..."],
	"G": [".###", "#...", "#.##", "#..#", ".###"],
	"H": ["#..#", "#..#", "####", "#..#", "#..#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"J": ["..##", "...#", "...#", "#..#", ".##."],
	"K": ["#..#", "#.#.", "##..", "#.#.", "#..#"],
	"L": ["#...", "#...", "#...", "#...", "####"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": [".##.", "#..#", "#..#", "#..#", ".##."],
	"P": ["###.", "#..#", "###.", "#...", "#..."],
	"Q": [".##.", "#..#", "#..#", "#.#.", ".#.#"],
	"R": ["###.", "#..#", "###.", "#.#.", "#..#"],
	"S": [".###", "#...", ".##.", "...#", "###."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#..#", "#..#", "#..#", "#..#", ".##."],
	"V": ["#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"X": ["#..#", "#..#", ".##.", "#..#", "#..#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["####", "...#", ".##.", "#...", "####"],
	"a": ["....", ".###", "#..#", "#..#", ".###"],
	"b": ["#...", "###.", "#..#", "#..#", "###."],
	"c": ["...", ".##", "#..", "#..", ".##"],
	"d": ["...#", ".###", "#..#", "#..#", ".###"],
	"e": ["....", ".##.", "####", "#...", ".###"],
	"f": [".##", "#..", "###", "#..", "#.."],
	"g": ["....", ".###", "#..#", "#..#", ".###", "...#", ".##."],
	"h": ["#...", "###.", "#..#", "#..#", "#..#"],
	"i": ["#", ".", "#", "#", "#"],
	"j": [".#", "..", ".#", ".#", ".#", ".#", "#."],
	"k": ["#..", "#.#", "##.", "#.#", "#.#"],
	"l": ["#.", "#.", "#.", "#.", ".#"],
	"m": [".....", "####.", "#.#.#", "#.#.#", "#.#.#"],
	"n": ["....", "###.", "#..#", "#..#", "#..#"],
	"o": ["....", ".##.", "#..#", "#..#", ".##."],
	"p": ["....", "###.", "#..#", "#..#", "###.", "#...", "#..."],
	"q": ["....", ".###", "#..#", "#..#", ".###", "...#", "...#"],
	"r": ["...", "#.#", "##.", "#..", "#.."],
	"s": ["...", ".##", "#..", "..#", "##."],
	"t": [".#.", "###", ".#.", ".#.", "..#"],
	"u": ["....", "#..#", "#..#", "#..#", ".###"],
	"v": ["...", "#.#", "#.#", "#.#", ".#."],
	"w": [".....", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"x": ["...", "#.#", ".#.", ".#.", "#.#"],
	"y": ["....", "#..#", "#..#", "#..#", ".###", "...#", ".##."],
	"z": ["....", "####", "..#.", ".#..", "####"],
	"0": [".##.", "#..#", "#.##", "##.#", ".##."],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###.", "...#", ".##.", "#...", "####"],
	"3": ["###.", "...#", ".##.", "...#", "###."],
	"4": ["#..#", "#..#", "####", "...#", "...#"],
	"5": ["####", "#...", "###.", "...#", "###."],
	"6": [".##.", "#...", "###.", "#..#", ".##."],
	"7": ["####", "...#", "..#.", ".#..", ".#.."],
	"8": [".##.", "#..#", ".##.", "#..#", ".##."],
	"9": [".##.", "#..#", ".###", "...#", ".##."],
	".": [".", ".", ".", ".", "#"],
	",": ["..", "..", "..", "..", ".#", "#."],
	":": [".", "#", ".", "#", "."],
	";": ["..", ".#", "..", ".#", "#."],
	"!": ["#", "#", "#", ".", "#"],
	"?": ["###.", "...#", ".##.", "....", ".#.."],
	"'": ["#", "#"],
	"\"": ["#.#", "#.#"],
	"-": ["...", "...", "###"],
	"_": ["....", "....", "....", "....", "....", "####"],
	"+": ["...", ".#.", "###", ".#."],
	"=": ["...", "###", "...", "###"],
	"*": ["#.#", ".#.", "#.#"],
	"/": ["..#", "..#", ".#.", "#..", "#.."],
	"\\": ["#..", "#..", ".#.", "..#", "..#"],
	"(": [".#", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", "#."],
	"[": ["##", "#.", "#.", "#.", "##"],
	"]": ["##", ".#", ".#", ".#", "##"],
	"<": ["..#", ".#.", "#..", ".#.", "..#"],
	">": ["#..", ".#.", "..#", ".#.", "#.."],
	"#": [".#.#.", "#####", ".#.#.", "#####", ".#.#."],
	"&": [".#..", "#.#.", ".#.#", "#.#.", ".#.#"],
	"@": [".###.", "#.###", "#.#.#", "#.###", ".##.."],
	"%": ["##..#", "##.#.", "..#..", ".#.##", "#..##"],
	"$": ["..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#.."],
	"€": ["..###", "####.", ".#...", "####.", "..###"],
	"£": ["..##", ".#..", "###.", ".#..", "####"],
	"¥": ["#.#", "#.#", "###", ".#.", "###"],
	"₹": ["####", "..#.", "####", ".#..", "..##"],
	"₩": ["#...#", "#####", "#.#.#", "#####", ".#.#."],
	"₺": [".#..", ".##.", "###.", ".#.#", ".##."],
	"ł": [".#.", ".#.", ".##", "##.", ".#."],
	"č": ["#.#", ".##", "#..", "#..", ".##"],
	"×": ["...", "#.#", ".#.", "#.#"],
	"·": [".", ".", "#"],
	"●": ["...", ".#.", "###", ".#."],
	"°": ["###", "#.#", "###"],
	"★": ["..#..", "#####", ".###.", ".#.#.", "#...#"],
	"☆": ["..#..", "##.##", "#...#", ".#.#.", "#.#.#"],
	"▲": [".....", ".....", "..#..", ".###.", "#####"],
	"▼": [".....", "#####", ".###.", "..#..", "....."],
	"♪": ["..##", "..#.", "..#.", "###.", "##.."],
	"ß": [".##.", "#..#", "#.#.", "#..#", "#.#."],
	"ç": ["...", ".##", "#..", "#..", ".##", ".#.", "##."],
	"Ç": [".###", "#...", "#...", "#...", ".###", "..#.", ".##."],
	"œ": [".....", ".#.#.", "#.###", "#.#..", ".#.##"],
	"Œ": [".####", "#.#..", "#.###", "#.#..", ".####"],
	"¿": [".#.", "...", ".#.", "#..", "#..", ".##"],
	"¡": ["#", ".", "#", "#", "#", "#"],
	"«": ["....", ".#.#", "#.#.", ".#.#"],
	"»": ["....", "#.#.", ".#.#", "#.#."],
}
## Accented letters for German, Spanish and French. Their first row sits one pixel above
## the cap line (the font's ascent leaves room for it); the rest lines up with GLYPHS.
const ACCENTED := {
	"à": [".#..", "....", ".###", "#..#", "#..#", ".###"],
	"á": ["..#.", "....", ".###", "#..#", "#..#", ".###"],
	"â": [".##.", "....", ".###", "#..#", "#..#", ".###"],
	"ä": ["#..#", "....", ".###", "#..#", "#..#", ".###"],
	"è": [".#..", "....", ".##.", "####", "#...", ".###"],
	"é": ["..#.", "....", ".##.", "####", "#...", ".###"],
	"ê": [".##.", "....", ".##.", "####", "#...", ".###"],
	"ë": ["#..#", "....", ".##.", "####", "#...", ".###"],
	"ì": ["#.", "..", "..", ".#", ".#", ".#"],
	"í": [".#", "..", "..", "#.", "#.", "#."],
	"î": [".#.", "#.#", "...", ".#.", ".#.", ".#."],
	"ï": ["#.#", "...", "...", ".#.", ".#.", ".#."],
	"ñ": ["####", "....", "###.", "#..#", "#..#", "#..#"],
	"ò": [".#..", "....", ".##.", "#..#", "#..#", ".##."],
	"ó": ["..#.", "....", ".##.", "#..#", "#..#", ".##."],
	"ô": [".##.", "....", ".##.", "#..#", "#..#", ".##."],
	"ö": ["#..#", "....", ".##.", "#..#", "#..#", ".##."],
	"ù": [".#..", "....", "#..#", "#..#", "#..#", ".###"],
	"ú": ["..#.", "....", "#..#", "#..#", "#..#", ".###"],
	"û": [".##.", "....", "#..#", "#..#", "#..#", ".###"],
	"ü": ["#..#", "....", "#..#", "#..#", "#..#", ".###"],
	"À": [".#..", ".##.", "#..#", "####", "#..#", "#..#"],
	"Á": ["..#.", ".##.", "#..#", "####", "#..#", "#..#"],
	"Â": [".##.", ".##.", "#..#", "####", "#..#", "#..#"],
	"Ä": ["#..#", ".##.", "#..#", "####", "#..#", "#..#"],
	"È": [".#..", "####", "#...", "###.", "#...", "####"],
	"É": ["..#.", "####", "#...", "###.", "#...", "####"],
	"Ê": [".##.", "####", "#...", "###.", "#...", "####"],
	"Ë": ["#..#", "####", "#...", "###.", "#...", "####"],
	"Ì": ["#..", "###", ".#.", ".#.", ".#.", "###"],
	"Í": ["..#", "###", ".#.", ".#.", ".#.", "###"],
	"Î": [".#.", "###", ".#.", ".#.", ".#.", "###"],
	"Ï": ["#.#", "###", ".#.", ".#.", ".#.", "###"],
	"Ñ": ["####", "#..#", "##.#", "#.##", "#..#", "#..#"],
	"Ò": [".#..", ".##.", "#..#", "#..#", "#..#", ".##."],
	"Ó": ["..#.", ".##.", "#..#", "#..#", "#..#", ".##."],
	"Ô": [".##.", ".##.", "#..#", "#..#", "#..#", ".##."],
	"Ö": ["#..#", ".##.", "#..#", "#..#", "#..#", ".##."],
	"Ù": [".#..", "#..#", "#..#", "#..#", "#..#", ".##."],
	"Ú": ["..#.", "#..#", "#..#", "#..#", "#..#", ".##."],
	"Û": [".##.", "#..#", "#..#", "#..#", "#..#", ".##."],
	"Ü": ["#..#", "....", "#..#", "#..#", "#..#", ".##."],
}
const SPACE_ADVANCE := 3

static var _font: FontFile
## GLYPHS and ACCENTED again as plain copies, which every lookup reads. In Godot 4.3 each
## item read from a const array goes through one scratch slot that array shares, so two
## threads reading the same glyph at once free it under each other and crash the game
## later. The loupe paintings (BarArt, GradeArt) run on a worker thread while the main
## thread draws text; plain arrays are safe to read from both.
static var _glyphs: Dictionary = GLYPHS.duplicate(true)
static var _accented: Dictionary = ACCENTED.duplicate(true)
## Chinese characters (CjkGlyphs, baked from a CJK pixel font), 7 rows from one pixel above
## the cap line down to the row under the baseline, like the accented letters.
static var _cjk: Dictionary = _decode(CjkGlyphs.ROWS)


## The shared font, built on first use.
static func get_font() -> FontFile:
	if _font == null:
		_font = _build()
	return _font


## Width in pixels of `text` at size 8.
static func measure(text: String) -> int:
	var w := 0
	for ch in text:
		w += SPACE_ADVANCE if ch == " " else glyph_width(ch) + 1
	return maxi(w - 1, 0)


static func glyph_width(ch: String) -> int:
	return rows_of(ch)[0].length()


## The glyph's rows ('#' lit), accented capitals and Chinese included; '?' for a character it lacks.
static func rows_of(ch: String) -> Array:
	return _accented.get(ch, _cjk.get(ch, _glyphs.get(ch, _glyphs["?"])))


## True when the font draws `ch` (space included).
static func has_glyph(ch: String) -> bool:
	return ch == " " or _glyphs.has(ch) or _accented.has(ch) or _cjk.has(ch)


## True for glyphs whose first row sits one pixel above the cap line.
static func is_tall(ch: String) -> bool:
	return _accented.has(ch) or _cjk.has(ch)


## Like rows_of(), without the accented capitals (a bar stamp has none).
static func plain_rows_of(ch: String) -> Array:
	return _glyphs.get(ch, _glyphs["?"])


## Calls `plot.call(x, y)` for every lit pixel of `text`, top-left at the cap line.
## Used to paint text straight into images and onto skewed walls.
static func plot_text(text: String, plot: Callable) -> void:
	var x := 0
	for ch in text:
		if ch == " ":
			x += SPACE_ADVANCE
			continue
		var rows := rows_of(ch)
		var top := -1 if is_tall(ch) else 0
		for y in rows.size():
			var row: String = rows[y]
			for px in row.length():
				if row[px] == "#":
					plot.call(x + px, y + top)
		x += rows[0].length() + 1


## CjkGlyphs.ROWS entries ("7" then a hex byte per row) as '#'/'.' rows.
static func _decode(packed: Dictionary) -> Dictionary:
	var out := {}
	for ch in packed:
		var code: String = packed[ch]
		var w := code.left(1).to_int()
		var rows := []
		for y in (code.length() - 1) / 2:
			var bits := code.substr(1 + y * 2, 2).hex_to_int()
			var row := ""
			for x in w:
				row += "#" if bits & (1 << x) else "."
			rows.append(row)
		out[ch] = rows
	return out


static func _build() -> FontFile:
	var keys := GLYPHS.keys() + ACCENTED.keys() + _cjk.keys()
	var cell_w := 8
	var cols := 32
	var atlas := Image.create(cols * cell_w, ceili(keys.size() / float(cols)) * 8, false, Image.FORMAT_RGBA8)
	var font := FontFile.new()
	font.fixed_size = SIZE
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	var size := Vector2i(SIZE, 0)
	font.set_cache_ascent(0, SIZE, ASCENT)
	font.set_cache_descent(0, SIZE, DESCENT)
	for n in keys.size():
		var ch: String = keys[n]
		var tall := is_tall(ch)
		var rows: Array = rows_of(ch)
		var w: int = rows[0].length()
		var h := 8 if tall else 7
		var origin := Vector2i((n % cols) * cell_w, (n / cols) * 8)
		for y in rows.size():
			for x in w:
				if rows[y][x] == "#":
					atlas.set_pixel(origin.x + x, origin.y + y, Color.WHITE)
		var glyph := ch.unicode_at(0)
		font.set_glyph_advance(0, SIZE, glyph, Vector2(w + 1, 0))
		font.set_glyph_offset(0, size, glyph, Vector2(0, -6 if tall else -5))
		font.set_glyph_size(0, size, glyph, Vector2(w, h))
		font.set_glyph_uv_rect(0, size, glyph, Rect2(origin.x, origin.y, w, h))
		font.set_glyph_texture_idx(0, size, glyph, 0)
	var space := " ".unicode_at(0)
	font.set_glyph_advance(0, SIZE, space, Vector2(SPACE_ADVANCE, 0))
	font.set_glyph_size(0, size, space, Vector2.ZERO)
	font.set_glyph_texture_idx(0, size, space, -1)
	font.set_texture_image(0, size, 0, atlas)
	return font
