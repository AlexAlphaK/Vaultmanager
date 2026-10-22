extends Control
## Coin testing minigame. The customer's coin lies on a felt mat; weigh it, measure it
## with calipers, ping it, try a magnet and inspect it under a loupe, then call it.
## Bench upgrades: digital gauges colour each reading against the spec, and the sigma
## verifier (key 6) reads the metal's conductivity through plating.
## Readings come from Counterfeit.readings(); the coin's look from CoinArt.

signal finished(verdict: String) # "genuine", "fake" or "cancel"

const BENCH_W := 316
const HOME := Vector2(112, 146)
const PAN := Vector2(252, 166)
const PAN_R := 40
const SCALE_RECT := Rect2i(196, 102, 112, 158)
const SCALE_LCD := Rect2i(214, 236, 76, 12)
const SCOPE := Rect2i(10, 20, 104, 40)
const INSET := Rect2i(196, 20, 110, 44)
const LOUPE_SIZE := 64
const LOUPE_ZOOM := 4.0
const TOOLS := ["scale", "calipers", "ping", "magnet", "loupe"]
const TOOL_NAMES := {"scale": "Scale", "calipers": "Calipers", "ping": "Ping", "magnet": "Magnet", "loupe": "Loupe", "sigma": "Sigma"}
## The sigma verifier's dial on the mat, and what it reads for each kind of coin.
const SIGMA := Rect2i(12, 196, 104, 34)
const SIGMA_READS := {"": "in band", "steel": "ferrous", "brass": "too low", "clad": "too low", "tungsten": "too low"}
## How far off the spec a reading may be and still count as genuine (digital gauges).
const TOLERANCE := {"g": 0.05, "mm": 0.1, "thick": 0.1}
const LOUPE_SHADER := """
shader_type canvas_item;
uniform sampler2D coin_tex : filter_nearest;
uniform vec2 center_uv;
uniform float span;
uniform vec4 backdrop : source_color;
void fragment() {
	vec2 d = UV - vec2(0.5);
	if (length(d) > 0.5) discard;
	vec2 uv = center_uv + d * span;
	vec4 c = texture(coin_tex, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) c = vec4(0.0);
	COLOR = vec4(mix(backdrop.rgb, c.rgb, c.a), 1.0);
}
"""

var customer: Customer
var item: BullionItem
var fake := ""
var readings := {}
var used := {}

var _bench: Texture2D
var _coin: Texture2D
var _coin_r := 0
var _shadow: Texture2D
var _coin_pos := HOME
var _time := 0.0
var _t := {"scale": -99.0, "calipers": -99.0, "ping": -99.0, "magnet": -99.0, "sigma": -99.0}
var _active := ""
var _on_scale := false
var _move_tween: Tween
var _snapped := false
var _beeped := false
var _loupe: ColorRect
var _loupe_rim: TextureRect
var _cells := {}
var _tool_buttons := {}
var _pad_tool := -1


func start(c: Customer) -> void:
	customer = c
	item = c.item
	fake = c.fake
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed
	readings = Counterfeit.readings(item, fake, rng)
	_coin = CoinArt.paint(item, fake, c.seed).texture()
	_coin_r = CoinArt.radius_of(item, fake)
	_shadow = _paint_shadow(_coin_r).texture()
	(_loupe.material as ShaderMaterial).set_shader_parameter("coin_tex", _coin)
	_build_panel()


func _ready() -> void:
	add_to_group("pad_hooks")
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bench = _paint_bench().texture()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LOUPE_SHADER
	mat.shader = shader
	mat.set_shader_parameter("backdrop", Color("#275c40"))
	mat.set_shader_parameter("span", 0.2)
	_loupe = ColorRect.new()
	_loupe.size = Vector2(LOUPE_SIZE, LOUPE_SIZE)
	_loupe.material = mat
	_loupe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loupe.visible = false
	add_child(_loupe)
	_loupe_rim = TextureRect.new()
	_loupe_rim.texture = _paint_loupe_rim().texture()
	_loupe_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loupe_rim.visible = false
	add_child(_loupe_rim)


func _exit_tree() -> void:
	Pad.hide_cursor(false)


func _process(delta: float) -> void:
	_time += delta
	_update_loupe()
	_update_cells()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			use_tool("scale")
		KEY_2, KEY_KP_2:
			use_tool("calipers")
		KEY_3, KEY_KP_3:
			use_tool("ping")
		KEY_4, KEY_KP_4:
			use_tool("magnet")
		KEY_5, KEY_KP_5:
			use_tool("loupe")
		KEY_6, KEY_KP_6:
			if has_sigma():
				use_tool("sigma")
		KEY_ESCAPE:
			finished.emit("cancel")
		_:
			return
	get_viewport().set_input_as_handled()


func has_sigma() -> bool:
	return Progress.has_upgrade("sigma_verifier")


func has_gauges() -> bool:
	return Progress.has_upgrade("digital_gauges")


## The bench's tools: the five basics, plus the sigma verifier once bought.
func tools() -> Array:
	return TOOLS + ["sigma"] if has_sigma() else TOOLS


## What the sigma verifier reads for this coin.
func sigma_reading() -> String:
	return SIGMA_READS.get(fake, "too low")


## LB and RB step through the tools, the same as the number keys.
func pad_action(name: String) -> bool:
	if name != "lb" and name != "rb":
		return false
	var list := tools()
	_pad_tool = posmod(_pad_tool + (1 if name == "rb" else -1), list.size())
	if _loupe.visible:
		use_tool("loupe")
	if list[_pad_tool] != "loupe" or not _loupe.visible:
		use_tool(list[_pad_tool])
	return true


func pad_help() -> Array:
	return [["LB / RB", "Previous / next tool"]]


func use_tool(tool: String) -> void:
	if tool == "sigma" and not has_sigma():
		return
	used[tool] = true
	if tool == "loupe":
		_loupe.visible = not _loupe.visible
		_loupe_rim.visible = _loupe.visible
		Pad.hide_cursor(_loupe.visible)
		Sfx.play(self, Sfx.click(), -10.0)
		return
	_active = tool
	if tool == "scale":
		_beeped = false
		_move_coin(PAN, true)
		_t.scale = _time + 0.35
		return
	var delay := 0.0
	if _on_scale:
		_move_coin(HOME, false)
		delay = 0.35
	_t[tool] = _time + delay
	_snapped = false
	if tool == "ping":
		get_tree().create_timer(delay).timeout.connect(func():
			var clean: bool = fake == ""
			Sfx.play(self, Sfx.coin_ring(readings.hz, readings.ring, clean), -4.0))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_bench, Vector2.ZERO)
	_draw_scope()
	_draw_scale_lcd()
	var pos := _coin_pos + _coin_offset()
	var top_left := (pos - Vector2(_coin.get_width(), _coin.get_height()) / 2.0).round()
	draw_texture(_shadow, top_left + Vector2(2, 3))
	draw_texture(_coin, top_left)
	_draw_glint(pos.round())
	_draw_calipers()
	_draw_magnet()
	_draw_sigma()
	_draw_tap()
	BenchArt.draw_motes(self, _time, Rect2(0, 0, BENCH_W, 270))


func _coin_offset() -> Vector2:
	var off := Vector2.ZERO
	var pt: float = _time - _t.ping
	if pt >= 0.0 and pt < readings.ring:
		off.x += roundf(sin(pt * 90.0) * (1.0 - pt / readings.ring))
	var mt: float = _time - _t.magnet
	if _active == "magnet" and mt >= 0.0 and mt < 3.2:
		var hold := clampf((3.2 - mt) / 0.4, 0.0, 1.0)
		if readings.magnet == "strong":
			var snap := clampf((mt - 0.55) / 0.1, 0.0, 1.0)
			if snap > 0.0 and not _snapped:
				_snapped = true
				Sfx.play(self, Sfx.magnet_snap(), -4.0)
			off.x += roundf(snap * hold * 10.0)
		elif readings.magnet == "slight":
			off.x += roundf(clampf((mt - 0.6) / 1.6, 0.0, 1.0) * hold * 2.0)
	return off


func _draw_glint(pos: Vector2) -> void:
	var phase := fmod(_time, 3.2)
	if phase > 0.6:
		return
	var a := -2.35 + phase * 1.2
	var at := pos + Vector2(cos(a), sin(a)) * (_coin_r - 4.0)
	var s := 1.0 - absf(phase - 0.3) / 0.3
	var col := Color(1, 1, 1, 0.9)
	draw_rect(Rect2(at.round(), Vector2.ONE), col)
	if s > 0.4:
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_rect(Rect2((at + d).round(), Vector2.ONE), Color(1, 1, 1, 0.7))
	if s > 0.8:
		for d in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
			draw_rect(Rect2((at + d).round(), Vector2.ONE), Color(1, 1, 1, 0.45))


func _draw_scope() -> void:
	if not used.has("ping"):
		return
	var el := clampf(_time - _t.ping, 0.0, 2.8)
	var w := SCOPE.size.x - 6
	var mid := SCOPE.position.y + 24
	var fake_scale := 1.0 if fake == "" else 0.55
	for px in w:
		var tt := px / float(w) * 2.8
		if tt > el:
			break
		var amp := exp(-tt * 3.0 / readings.ring) * 12.0 * fake_scale
		var y := roundi(sin(tt * readings.hz / 37.0) * amp)
		draw_rect(Rect2(SCOPE.position.x + 3 + px, mid + mini(0, y), 1, absi(y) + 1), Pal.WARN)
	if el >= 0.0:
		_text("%.1f s" % minf(el, readings.ring), Vector2(SCOPE.end.x - 30, SCOPE.position.y + 3), Pal.WARN)


func _draw_scale_lcd() -> void:
	var text := "0.00 g"
	var st: float = _time - _t.scale
	if _on_scale and st >= 0.0:
		var g: float = readings.g
		if st < 0.6:
			g *= st / 0.6
		elif st < 1.0:
			g += (0.01 if int(st * 20.0) % 2 == 0 else -0.01)
		elif not _beeped:
			_beeped = true
			Sfx.play(self, Sfx.scale_beep(), -10.0)
		text = "%.2f g" % g
	var x := SCALE_LCD.end.x - 3 - PixelFont.measure(text)
	_text(text, Vector2(x, SCALE_LCD.position.y + 3), Pal.LED)


func _draw_calipers() -> void:
	if _active != "calipers":
		return
	var ct: float = _time - _t.calipers
	if ct < 0.0:
		return
	var close := clampf(ct / 0.7, 0.0, 1.0)
	var gap := _coin_r + 1.0 + roundf((1.0 - close) * 22.0)
	var y := HOME.y - _coin_r - 14.0
	var left := HOME.x - gap
	var right := HOME.x + gap
	var steel := Color("#c3cad4")
	var dark := Color("#6b7380")
	# beam with mm graduations
	draw_rect(Rect2(left - 6, y, right - left + 46, 5), steel)
	draw_rect(Rect2(left - 6, y, right - left + 46, 1), Color("#eef2f6"))
	draw_rect(Rect2(left - 6, y + 4, right - left + 46, 1), dark)
	var tick := left
	while tick < right + 38:
		draw_rect(Rect2(roundf(tick), y + 1, 1, 2 if int((tick - left) / CoinArt.PX_PER_MM) % 5 else 3), dark)
		tick += CoinArt.PX_PER_MM * 2.5
	# fixed jaw on the left, sliding jaw and readout on the right
	for jx in [left - 3, right]:
		draw_rect(Rect2(jx, y, 3, _coin_r + 16), Color("#9aa3b0"))
		draw_rect(Rect2(jx, y, 1, _coin_r + 16), Color("#dce2ea"))
		draw_rect(Rect2(jx + 2, y, 1, _coin_r + 16), Color("#59606b"))
	var lcd := Rect2(right + 4, y - 12, 38, 11)
	draw_rect(lcd, Color("#2a2e35"))
	draw_rect(lcd.grow(-1), Pal.LED_BG)
	var mm: float = readings.mm + (1.0 - close) * 15.0
	_text("%.2f" % mm, Vector2(lcd.end.x - 2 - PixelFont.measure("%.2f" % mm), lcd.position.y + 3), Pal.LED)
	# thickness: edge-on inset
	var tt := clampf((ct - 0.9) / 0.5, 0.0, 1.0)
	if ct < 0.9:
		return
	draw_rect(INSET, Color("#14100c"))
	draw_rect(Rect2(INSET.position, Vector2(INSET.size.x, 1)), Pal.PANEL_EDGE)
	_text("EDGE", Vector2(INSET.position.x + 3, INSET.position.y + 3), Pal.INK_FAINT)
	var thick_px := roundf(readings.thick * 6.0)
	var cy := INSET.position.y + 26
	var pal := item.palette_name()
	var x0 := INSET.position.x + 8
	var w := INSET.size.x - 52
	for row in int(thick_px):
		var col := Pal.metal(pal, 4 if row == 0 else (2 if row == int(thick_px) - 1 else 3))
		draw_rect(Rect2(x0, cy - thick_px / 2.0 + row, w, 1), col)
	for rx in range(x0, x0 + w, 2):
		draw_rect(Rect2(rx, cy - thick_px / 2.0 + 1, 1, thick_px - 2), Pal.metal(pal, 2))
	if fake == "clad":
		draw_rect(Rect2(x0, cy - 1, w, 2), Pal.metal("copper", 3)) # the copper core shows on the edge
	var jaw_gap := thick_px / 2.0 + 1.0 + (1.0 - tt) * 8.0
	draw_rect(Rect2(x0 + w / 2 - 8, cy - jaw_gap - 3, 16, 3), steel)
	draw_rect(Rect2(x0 + w / 2 - 8, cy + jaw_gap, 16, 3), steel)
	var thick: float = readings.thick + (1.0 - tt) * 1.3
	_text("%.2f" % thick, Vector2(INSET.end.x - 36, cy - 3), Pal.LED)
	_text("mm", Vector2(INSET.end.x - 14, cy - 3), Pal.INK_FAINT)


func _draw_magnet() -> void:
	if _active != "magnet":
		return
	var mt: float = _time - _t.magnet
	if mt < 0.0 or mt > 3.2:
		return
	var travel := clampf(mt / 0.6, 0.0, 1.0) - clampf((mt - 2.8) / 0.4, 0.0, 1.0)
	var touch := HOME.x + _coin_r + 12.0
	var x := roundf(lerpf(touch + 70.0, touch, travel))
	var y := HOME.y - 8.0
	# a neodymium block on a wooden handle
	draw_rect(Rect2(x + 13, y + 6, 56, 8), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(x + 12, y + 4, 56, 8), Color("#8a5a30"))
	draw_rect(Rect2(x + 12, y + 4, 56, 1), Color("#b88a4c"))
	draw_rect(Rect2(x + 12, y + 11, 56, 1), Color("#5e3b1d"))
	draw_rect(Rect2(x + 12, y + 2, 3, 12), Color("#7d8591"))
	draw_rect(Rect2(x, y, 13, 16), Color("#9aa3b0"))
	draw_rect(Rect2(x, y, 13, 1), Color("#eef2f6"))
	draw_rect(Rect2(x, y, 1, 16), Color("#dce2ea"))
	draw_rect(Rect2(x + 1, y + 15, 12, 1), Color("#59606b"))
	draw_rect(Rect2(x + 12, y + 1, 1, 15), Color("#6b7380"))
	_text("N", Vector2(x + 5, y + 6), Color("#c0392b"))


## The sigma verifier: its sensor pad pressed on the coin and a dial that settles in
## the green band for genuine metal, or swings out of it.
func _draw_sigma() -> void:
	if not used.has("sigma"):
		return
	var st: float = _time - _t.sigma
	var r := SIGMA
	draw_rect(Rect2(r.position + Vector2i(1, 2), r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, Color("#e8b020"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color("#ffd24a"))
	draw_rect(Rect2(r.position + Vector2i(0, r.size.y - 1), Vector2(r.size.x, 1)), Color("#9a6a10"))
	var dial := Rect2(r.position + Vector2i(4, 4), Vector2(r.size.x - 8, 14))
	draw_rect(dial, Color("#14100c"))
	var band := Rect2(dial.position + Vector2(dial.size.x * 0.55, 2), Vector2(dial.size.x * 0.2, dial.size.y - 4))
	draw_rect(band, Color("#1f4a33"))
	draw_rect(Rect2(band.position, Vector2(band.size.x, 1)), Pal.GOOD)
	var reading := sigma_reading()
	var target := {"in band": 0.65, "too low": 0.22, "ferrous": 0.97}[reading] as float
	# the needle sweeps up from the left, wobbles and settles
	var settle := clampf(st / 1.2, 0.0, 1.0)
	var at := lerpf(0.04, target, settle) + (sin(st * 18.0) * 0.03 * (1.0 - settle) if st < 1.2 else 0.0)
	var nx := roundf(dial.position.x + 1.0 + at * (dial.size.x - 3.0))
	draw_rect(Rect2(nx, dial.position.y + 1, 1, dial.size.y - 2), Color("#ff6a3a"))
	_text("SIGMA", Vector2(r.position.x + 4, r.end.y - 11), Color("#3a2a06"))
	if st > 1.2:
		_text(reading.to_upper(), Vector2(r.position.x + 38, r.end.y - 11), Color("#1f4a33") if reading == "in band" else Color("#8a1f1a"))
	# the sensor pad on its cable, pressed on the coin while it reads
	if _active == "sigma" and st >= 0.0 and st < 2.0 and not _on_scale:
		var pad := HOME + Vector2(-8, _coin_r * 0.3)
		draw_line(Vector2(r.position.x + 20, r.position.y), pad + Vector2(4, 8), Color("#1c2026"))
		draw_rect(Rect2(pad, Vector2(12, 10)), Color("#1c2026"))
		draw_rect(Rect2(pad + Vector2(1, 1), Vector2(10, 1)), Color("#59606b"))


func _draw_tap() -> void:
	var pt: float = _time - _t.ping
	if pt < 0.0 or pt > 0.25:
		return
	var at := HOME + Vector2(-_coin_r - 3, -6)
	var spark := Color(1, 1, 0.8, 1.0 - pt / 0.25)
	for d in [Vector2(-3, 0), Vector2(-2, -2), Vector2(-2, 2), Vector2(0, -3), Vector2(0, 3)]:
		draw_rect(Rect2((at + d * (1.0 + pt * 4.0)).round(), Vector2.ONE), spark)


func _text(text: String, at: Vector2, col: Color) -> void:
	PixelFont.plot_text(text, func(x, y): draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


# ---------------------------------------------------------------- behaviour

func _move_coin(to: Vector2, onto_scale: bool) -> void:
	if _move_tween:
		_move_tween.kill()
	_on_scale = false
	_move_tween = create_tween()
	_move_tween.tween_property(self, "_coin_pos", to, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if onto_scale:
		_move_tween.tween_callback(func(): _on_scale = true)


func _update_loupe() -> void:
	if not _loupe.visible:
		return
	var m := Pad.mouse_in(self)
	m.x = clampf(m.x, LOUPE_SIZE / 2.0, BENCH_W - LOUPE_SIZE / 2.0)
	m.y = clampf(m.y, LOUPE_SIZE / 2.0, size.y - LOUPE_SIZE / 2.0)
	_loupe.position = (m - Vector2(LOUPE_SIZE, LOUPE_SIZE) / 2.0).round()
	_loupe_rim.position = _loupe.position - Vector2(3, 3)
	var coin_size := Vector2(_coin.get_width(), _coin.get_height())
	var top_left := (_coin_pos + _coin_offset() - coin_size / 2.0).round()
	var mat := _loupe.material as ShaderMaterial
	mat.set_shader_parameter("center_uv", (m - top_left) / coin_size)
	mat.set_shader_parameter("span", LOUPE_SIZE / LOUPE_ZOOM / coin_size.x)


func _update_cells() -> void:
	if _cells.is_empty():
		return
	_set_cell("weight", "%.2f g" % readings.g if used.has("scale") and _on_scale and _time - _t.scale > 1.0 else "")
	var cal: float = _time - _t.calipers
	_set_cell("diameter", "%.2f mm" % readings.mm if used.has("calipers") and (cal > 0.8 or _active != "calipers") else "")
	_set_cell("thickness", "%.2f mm" % readings.thick if used.has("calipers") and (cal > 1.5 or _active != "calipers") else "")
	_set_cell("ring", "%.1f s" % readings.ring if used.has("ping") and _time - _t.ping > readings.ring else "")
	var magnet_text := {"strong": "snaps hard", "slight": "slight drag", "none": "no pull"}
	_set_cell("magnet", magnet_text[readings.magnet] if used.has("magnet") and _time - _t.magnet > 1.4 else "")
	if _cells.has("sigma"):
		_set_cell("sigma", sigma_reading() if used.has("sigma") and _time - _t.sigma > 1.2 else "")


## With digital gauges, whether a reading is inside the spec: true, false, or null without gauges.
func in_spec(key: String) -> Variant:
	if not has_gauges():
		return null
	var ring := item.ring_seconds()
	match key:
		"weight":
			return absf(readings.g - item.weight_g) <= TOLERANCE.g
		"diameter":
			return absf(readings.mm - item.diameter_mm) <= TOLERANCE.mm
		"thickness":
			return absf(readings.thick - item.thickness_mm) <= TOLERANCE.thick
		"ring":
			return readings.ring >= ring.x
		"magnet":
			return readings.magnet == ("slight" if item.metal == "XAG" else "none")
		"sigma":
			return sigma_reading() == "in band"
	return null


func _set_cell(key: String, text: String) -> void:
	var l: Label = _cells[key]
	if text == "":
		if l.text == "" or l.get_meta("measured", false) == false:
			l.text = "-"
			l.add_theme_color_override("font_color", Pal.INK_FAINT)
		return
	l.set_meta("measured", true)
	l.text = text
	var ok = in_spec(key)
	l.add_theme_color_override("font_color", Pal.INK if ok == null else (Pal.GOOD if ok else Pal.BAD))


func _build_panel() -> void:
	var x := BENCH_W + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(BENCH_W, 0)
	panel.size = Vector2(480 - BENCH_W, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(panel, 0)
	_label("COIN TEST", Vector2(x, 4), Pal.INK_FAINT)
	_label(item.display_name, Vector2(x, 13), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_label("%d coins from %s" % [customer.qty, customer.name], Vector2(x, 32), Pal.INK_DIM, 156)
	_label("SPEC", Vector2(x + 52, 46), Pal.INK_FAINT, 50, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("READING", Vector2(x + 104, 46), Pal.INK_FAINT, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	var ring := item.ring_seconds()
	var rows := [
		["weight", "Weight", "%.2f g" % item.weight_g],
		["diameter", "Diameter", "%.2f mm" % item.diameter_mm],
		["thickness", "Thick", "%.2f mm" % item.thickness_mm],
		["ring", "Ring", "%.1f-%.1f s" % [ring.x, ring.y]],
		["magnet", "Magnet", "slight drag" if item.metal == "XAG" else "no pull"],
	]
	if has_sigma():
		rows.append(["sigma", "Sigma", "in band"])
	for n in rows.size():
		var y := 56 + n * 9
		_label(rows[n][1], Vector2(x, y), Pal.INK_DIM)
		_label(rows[n][2], Vector2(x + 42, y), Pal.INK_DIM, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		_cells[rows[n][0]] = _label("-", Vector2(x + 104, y), Pal.INK_FAINT, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	var below := 56 + rows.size() * 9 + 5
	_label("Melt today", Vector2(x, below), Pal.INK_DIM)
	_label(Market.format_money(customer.melt_total()), Vector2(x + 60, below), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Your offer", Vector2(x, below + 9), Pal.INK_DIM)
	_label(Market.format_money(customer.offer_total()), Vector2(x + 60, below + 9), Pal.GOLD, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	var bench_tools := tools()
	for n in bench_tools.size():
		var tool: String = bench_tools[n]
		var b := Button.new()
		add_child(b)
		b.text = "%d %s" % [n + 1, TOOL_NAMES[tool]]
		b.theme_type_variation = "ToolButton"
		b.position = Vector2(x + (n % 2) * 80, below + 24 + (n / 2) * 14)
		b.size = Vector2(76, 12)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(use_tool.bind(tool))
		_tool_buttons[tool] = b
	_label("Genuine coins match the spec within 0.05 g and 0.1 mm, ring for over a second and ignore magnets. Silver drags a little. Look for a soft strike or typos under the loupe.",
		Vector2(x, below + 68), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 162 - below)
	var genuine := Button.new()
	add_child(genuine)
	genuine.text = "Genuine"
	genuine.theme_type_variation = "PrimaryButton"
	genuine.position = Vector2(x, 236)
	genuine.size = Vector2(76, 13)
	genuine.focus_mode = Control.FOCUS_NONE
	genuine.pressed.connect(func(): finished.emit("genuine"))
	var fake_button := Button.new()
	add_child(fake_button)
	fake_button.text = "Fake"
	fake_button.theme_type_variation = "DangerButton"
	fake_button.position = Vector2(x + 80, 236)
	fake_button.size = Vector2(76, 13)
	fake_button.focus_mode = Control.FOCUS_NONE
	fake_button.pressed.connect(func(): finished.emit("fake"))
	_label("Esc: back to the counter", Vector2(x, 256), Pal.INK_FAINT)
	move_child(_loupe, -1)
	move_child(_loupe_rim, -1)


func _label(text: String, pos: Vector2, col: Color, width := 0, align := HORIZONTAL_ALIGNMENT_LEFT, wrap_height := 0) -> Label:
	var l := Label.new()
	add_child(l)
	if wrap_height > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(width, wrap_height)
	l.text = text
	l.position = pos
	if width > 0:
		l.size = Vector2(width, maxi(wrap_height, 8))
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- baked art

## Wooden bench, green felt mat with a printed millimetre ruler, oscilloscope and scale.
func _paint_bench() -> PixelCanvas:
	var c := BenchArt.wood(BENCH_W, 270)
	var mat := Rect2i(6, 14, BENCH_W - 12, 250)
	c.rect(mat.position.x + 1, mat.position.y + 2, mat.size.x, mat.size.y, Color(0, 0, 0, 0.3))
	BenchArt.felt(c, mat, Color("#275c40"))
	for x in range(mat.position.x, mat.end.x):
		c.px(x, mat.position.y, Color("#1a3b2a"))
		c.px(x, mat.end.y - 1, Color("#1a3b2a"))
		if x % 4 < 2:
			c.px(x, mat.position.y + 2, Color("#3d7a58"))
			c.px(x, mat.end.y - 3, Color("#3d7a58"))
	for y in range(mat.position.y, mat.end.y):
		c.px(mat.position.x, y, Color("#1a3b2a"))
		c.px(mat.end.x - 1, y, Color("#1a3b2a"))
		if y % 4 < 2:
			c.px(mat.position.x + 2, y, Color("#3d7a58"))
			c.px(mat.end.x - 3, y, Color("#3d7a58"))
	# ruler printed along the bottom of the mat
	var ry := mat.end.y - 6
	var mm := 0
	while 12 + mm * CoinArt.PX_PER_MM < 178:
		var rx := roundi(12 + mm * CoinArt.PX_PER_MM)
		var h := 4 if mm % 10 == 0 else (3 if mm % 5 == 0 else 1)
		c.rect(rx, ry - h, 1, h, Color("#8fc0a4"))
		if mm % 10 == 0 and mm > 0:
			c.text(str(mm / 10), rx - 1, ry - 11, Color("#8fc0a4"))
		mm += 1
	c.text("CM", 180, ry - 6, Color("#5f9a7a"))
	# oscilloscope
	BenchArt.housing(c, SCOPE.grow(2), Color("#2a2e35"), false)
	c.rect(SCOPE.position.x, SCOPE.position.y, SCOPE.size.x, SCOPE.size.y, Color("#0b0907"))
	for gx in range(SCOPE.position.x + 3, SCOPE.end.x - 2, 10):
		for gy in range(SCOPE.position.y + 2, SCOPE.end.y - 1, 2):
			c.px(gx, gy, Color("#1e2a1e"))
	for gy in range(SCOPE.position.y + 4, SCOPE.end.y - 1, 10):
		for gx in range(SCOPE.position.x + 3, SCOPE.end.x - 2, 2):
			c.px(gx, gy, Color("#1e2a1e"))
	c.text("RING", SCOPE.position.x + 3, SCOPE.position.y + 3, Color("#7a5a20"))
	# precision scale
	var s := SCALE_RECT
	BenchArt.housing(c, s, Color("#3a3f48"))
	for y in range(s.position.y + 4, s.end.y - 4):
		for x in range(s.position.x + 4, s.end.x - 4):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(PAN)
			if d <= PAN_R:
				var ring := int(d * 1.5) % 3
				var lit := (PAN.x - x) + (PAN.y - y) > 0
				var col: Color = [Color("#b3bcc8"), Color("#a6afbb"), Color("#bcc4cf")][ring]
				if d > PAN_R - 1.5:
					col = Color("#dce2ea") if lit else Color("#6b7380")
				c.px(x, y, col)
			elif d <= PAN_R + 2:
				c.px(x, y, Color("#1c1f24"))
	var lcd := SCALE_LCD
	c.rect(lcd.position.x - 2, lcd.position.y - 2, lcd.size.x + 4, lcd.size.y + 4, Color("#22262c"))
	c.rect(lcd.position.x, lcd.position.y, lcd.size.x, lcd.size.y, Pal.LED_BG)
	c.text("AURUM 200", s.position.x + 6, PAN.y + PAN_R + 6, Color("#848d9a"))
	c.text("MAX 200G", s.end.x - 46, PAN.y + PAN_R + 6, Color("#5b616b"))
	for bx in [s.position.x + 6, s.end.x - 24]:
		c.rect(bx, PAN.y + PAN_R + 16, 18, 5, Color("#22262c"))
		c.rect(bx + 1, PAN.y + PAN_R + 16, 16, 1, Color("#6b7380"))
	BenchArt.lamp_light(c)
	return c


func _paint_shadow(r: int) -> PixelCanvas:
	var size := r * 2 + 4
	var c := PixelCanvas.new(size, size)
	c.disc(size / 2.0, size / 2.0, r + 1.0, Color(0, 0, 0, 0.16))
	c.disc(size / 2.0, size / 2.0, r, Color(0, 0, 0, 0.3))
	return c


func _paint_loupe_rim() -> PixelCanvas:
	var size := LOUPE_SIZE + 6
	var c := PixelCanvas.new(size + 18, size + 18)
	var ctr := size / 2.0
	# handle
	for t in 22:
		var p := Vector2(ctr, ctr) + Vector2(1, 1).normalized() * (ctr + t - 2.0)
		c.disc(p.x, p.y, 3.0, Color("#2a1a0c") if t < 3 else Color("#5e3b1d"))
		c.px(roundi(p.x) - 1, roundi(p.y) - 2, Color("#8a5a30"))
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - ctr, y + 0.5 - ctr)
			var r := d.length()
			if r > ctr or r < ctr - 3.0:
				continue
			var lit := d.x + d.y < 0.0
			var col := Color("#f4cf6a") if lit else Color("#a8761e")
			if r < ctr - 2.0:
				col = Color("#7d5a20")
			if r > ctr - 0.8:
				col = Color("#3a2510")
			c.px(x, y, col)
	# glass glare
	for k in 6:
		c.px(roundi(ctr - 18 + k), roundi(ctr - 22 + k / 2), Color(1, 1, 1, 0.5))
	return c
