extends Control
## Bar testing minigame. The customer's bar lies on a rubber mat: weigh it, measure it,
## sweep an ultrasound probe across it, shoot it with the XRF gun and read its marks
## under the loupe, then call it. Tungsten fakes weigh right and look right; only the
## sound inside them and the metal on their surface give them away.
## Readings come from BullionBar; the bar's look from BarArt.

signal finished(verdict: String) # "genuine", "fake" or "cancel"

const BENCH_W := 316
const UT := Rect2i(8, 16, 146, 56)
const UT_PLOT := Rect2i(12, 26, 96, 42)
const UT_MAP := Rect2i(114, 30, 36, 20)
const XRF := Rect2i(162, 16, 146, 56)
const XRF_PLOT := Rect2i(166, 26, 98, 42)
const MAT := Rect2i(6, 78, 304, 186)
const HOME := Vector2(86, 178)
const SCALE_RECT := Rect2i(168, 96, 140, 164)
const PAN := Rect2i(174, 104, 128, 104)
const SCALE_LCD := Rect2i(208, 230, 76, 12)
const INSET := Rect2i(10, 84, 132, 30)
const SCAN_CELLS := Vector2i(8, 4)
const PROBE_START := Vector2(0.1, 0.5)
const XRF_SECONDS := 2.4
const XRF_KEV := 26.0
const LOUPE_SIZE := 64
const TOOLS := ["scale", "calipers", "ultrasound", "xrf", "loupe"]
const TOOL_NAMES := {"scale": "Scale", "calipers": "Calipers", "ultrasound": "Ultrasound", "xrf": "XRF", "loupe": "Loupe"}
const LOUPE_SHADER := """
shader_type canvas_item;
uniform sampler2D detail_tex : filter_nearest;
uniform vec2 center_uv;
uniform vec2 span;
uniform vec4 backdrop : source_color;
void fragment() {
	vec2 d = UV - vec2(0.5);
	if (length(d) > 0.5) discard;
	vec2 uv = center_uv + d * span;
	vec4 c = texture(detail_tex, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) c = vec4(0.0);
	COLOR = vec4(mix(backdrop.rgb, c.rgb, c.a), 1.0);
}
"""

var customer: Customer
var bar: BullionBar
var readings := {}
var used := {}
## Scan map: cell -> true when the echo there was off the gate or doubled.
var scan := {}
var probe_on := false
var probe_uv := PROBE_START
var serial_read := false

var _bench: Texture2D
var _bar: Texture2D
var _shadow: Texture2D
var _detail_task := -1
var _detail: PixelCanvas
var _zoom := 2.0
var _serial_rect := Rect2()
var _bar_pos := HOME
var _time := 0.0
var _t := {"scale": -99.0, "calipers": -99.0, "xrf": -99.0, "ping": -99.0}
var _active := ""
var _on_scale := false
var _beeped := false
var _xrf_done := false
var _move_tween: Tween
var _spectrum := PackedFloat32Array()
var _loupe: ColorRect
var _loupe_rim: TextureRect
var _cells := {}
var _tool_buttons := {}


func start(c: Customer) -> void:
	customer = c
	bar = c.bar
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed
	readings = bar.readings(rng)
	_spectrum = _build_spectrum(readings.surface, rng)
	var art := BarArt.paint(bar, BarArt.bench_ppm(bar))
	_bar = art.texture()
	_shadow = BenchArt.soft_shadow(art).texture()
	# the loupe's detailed painting is big: paint it off the main thread
	var b := bar
	var ppm := BarArt.detail_ppm(b)
	_zoom = ppm / BarArt.bench_ppm(b)
	_serial_rect = BarArt.serial_rect(b).grow(0.04)
	_detail_task = WorkerThreadPool.add_task(func(): _detail = BarArt.paint(b, ppm))
	_build_panel()


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bench = _paint_bench().texture()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LOUPE_SHADER
	mat.shader = shader
	mat.set_shader_parameter("backdrop", Color("#2c3038"))
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _detail_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_detail_task)
		_detail_task = -1


func _process(delta: float) -> void:
	_time += delta
	_finish_detail()
	_follow_probe()
	_update_xrf()
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
			use_tool("ultrasound")
		KEY_4, KEY_KP_4:
			use_tool("xrf")
		KEY_5, KEY_KP_5:
			use_tool("loupe")
		KEY_ESCAPE:
			finished.emit("cancel")
		_:
			return
	get_viewport().set_input_as_handled()


func has_xrf() -> bool:
	return Progress.has_upgrade("xrf_gun")


func use_tool(tool: String) -> void:
	if tool == "xrf" and not has_xrf():
		Sfx.play(self, Sfx.click(), -10.0)
		return
	used[tool] = true
	if tool == "loupe":
		_loupe.visible = not _loupe.visible
		_loupe_rim.visible = _loupe.visible
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if _loupe.visible else Input.MOUSE_MODE_VISIBLE
		Sfx.play(self, Sfx.click(), -10.0)
		return
	if tool == "ultrasound":
		probe_on = not probe_on
		if not probe_on:
			_active = ""
			return
		_active = "ultrasound"
		if _on_scale:
			_move_bar(HOME, false)
		Sfx.play(self, BarSfx.gel(), -6.0)
		probe_at(probe_uv)
		return
	probe_on = false
	_active = tool
	if tool == "scale":
		_beeped = false
		_move_bar(Vector2(PAN.get_center()), true)
		_t.scale = _time + 0.35
		return
	var delay := 0.0
	if _on_scale:
		_move_bar(HOME, false)
		delay = 0.35
	_t[tool] = _time + delay
	if tool == "xrf":
		_xrf_done = false
		get_tree().create_timer(delay).timeout.connect(func(): Sfx.play(self, BarSfx.xrf(XRF_SECONDS), -8.0))


## Puts the ultrasound probe on the bar at `uv` (0-1 across the top face) and
## records the echo there on the scan map.
func probe_at(uv: Vector2) -> void:
	probe_uv = uv.clamp(Vector2(0.02, 0.04), Vector2(0.98, 0.96))
	var cell := Vector2i(clampi(int(probe_uv.x * SCAN_CELLS.x), 0, SCAN_CELLS.x - 1), clampi(int(probe_uv.y * SCAN_CELLS.y), 0, SCAN_CELLS.y - 1))
	var off := bar.echo_off(probe_uv)
	var fresh := not scan.has(cell)
	scan[cell] = scan.get(cell, false) or off
	if fresh or _time - _t.ping > 0.6:
		_t.ping = _time
		Sfx.play(self, BarSfx.ping(not off), -10.0)


func scan_off_count() -> int:
	var n := 0
	for cell in scan:
		if scan[cell]:
			n += 1
	return n


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_bench, Vector2.ZERO)
	_draw_ultrasound()
	_draw_xrf_screen()
	_draw_scale_lcd()
	var r := _bar_rect()
	draw_texture(_shadow, r.position + Vector2(1, 2))
	draw_texture(_bar, r.position)
	_draw_glint(r)
	_draw_calipers()
	_draw_probe()
	_draw_xrf_gun()
	BenchArt.draw_motes(self, _time, Rect2(0, 0, BENCH_W, 270))


func _bar_rect() -> Rect2:
	var size := Vector2(_bar.get_width(), _bar.get_height())
	return Rect2((_bar_pos - size / 2.0).round(), size)


func _draw_glint(r: Rect2) -> void:
	var phase := fmod(_time, 3.6)
	if phase > 0.7:
		return
	var at := (r.position + Vector2(r.size.x * (0.1 + phase * 0.9), r.size.y * 0.12)).round()
	var s := 1.0 - absf(phase - 0.35) / 0.35
	draw_rect(Rect2(at, Vector2.ONE), Color(1, 1, 1, 0.9))
	if s > 0.4:
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_rect(Rect2(at + d, Vector2.ONE), Color(1, 1, 1, 0.7))
	if s > 0.8:
		for d in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
			draw_rect(Rect2(at + d, Vector2.ONE), Color(1, 1, 1, 0.45))


## The flaw detector: an A-scan of the echoes under the probe and the scan map.
func _draw_ultrasound() -> void:
	var p := UT_PLOT
	var base_y := p.end.y - 3
	var expected := bar.expected_echo_us()
	var span := expected * 3.3
	var x_of := func(us: float) -> float: return p.position.x + 2 + us / span * (p.size.x - 4)
	# the gate: where a genuine bar's back-wall echo lands
	var g0: float = x_of.call(expected * (1.0 - BullionBar.GATE))
	var g1: float = x_of.call(expected * (1.0 + BullionBar.GATE))
	var gate_col := Color("#7a5a20")
	for gy in range(p.position.y + 9, base_y, 2):
		draw_rect(Rect2(g0 - 1, gy, 1, 1), gate_col)
		draw_rect(Rect2(g1 + 1, gy, 1, 1), gate_col)
	draw_rect(Rect2(g0 - 1, p.position.y + 9, g1 - g0 + 3, 1), gate_col)
	_text("%.2f US" % expected, Vector2(p.end.x - 34, p.position.y - 8), Pal.INK_FAINT)
	_draw_map()
	if not probe_on:
		_text("PROBE OFF", Vector2(p.position.x + 2, p.position.y + 1), Color("#3d5a3d"))
		draw_rect(Rect2(p.position.x + 2, base_y, p.size.x - 4, 1), Color("#2e5a2e"))
		return
	var e := bar.echo_at(probe_uv)
	var peaks := [[0.0, 1.0]]
	for k in 3:
		peaks.append([e.back * (k + 1), e.amp * pow(0.62, k)])
	if e.interface > 0.0:
		peaks.append([e.interface, 0.75])
		peaks.append([e.interface * 2.0, 0.3])
	var jitter := int(_time * 30.0)
	for px in p.size.x - 4:
		var us: float = px / float(p.size.x - 4) * span
		var amp := CoinArt._hash(px, jitter, 5) * 0.06
		for pk in peaks:
			var d: float = absf(us - pk[0]) / span * (p.size.x - 4)
			if d < 2.5:
				amp = maxf(amp, pk[1] * (1.0 - d / 2.5) * (0.9 + CoinArt._hash(px, jitter, 9) * 0.1))
		var h := roundi(amp * (p.size.y - 6))
		draw_rect(Rect2(p.position.x + 2 + px, base_y - h, 1, h + 1), Pal.LED)
	var off := bar.echo_off(probe_uv)
	var bw := "BW %.2f" % e.back
	_text(bw, Vector2(p.end.x - 3 - PixelFont.measure(bw), p.position.y + 1), Pal.BAD if off else Pal.LED)


func _draw_map() -> void:
	var m := UT_MAP
	draw_rect(Rect2(m.position - Vector2i(1, 1), m.size + Vector2i(2, 2)), Color("#2e5a2e"))
	draw_rect(Rect2(m), Color("#0b0e0a"))
	var cw := m.size.x / SCAN_CELLS.x
	var ch := m.size.y / SCAN_CELLS.y
	for cell in scan:
		var col := Pal.BAD if scan[cell] else Color("#3f9a4a")
		draw_rect(Rect2(m.position.x + cell.x * cw, m.position.y + cell.y * ch, cw - 1, ch - 1), col)
	if probe_on and fmod(_time, 0.5) < 0.3:
		var at := Vector2(m.position) + probe_uv * Vector2(m.size)
		draw_rect(Rect2(at.round() - Vector2(1, 1), Vector2(2, 2)), Pal.INK)
	_text("MAP", Vector2(m.position.x + 9, m.end.y + 3), Color("#3d5a3d"))


## The XRF analyzer's screen: the spectrum filling in, then what the surface is made of.
func _draw_xrf_screen() -> void:
	var p := XRF_PLOT
	if not has_xrf():
		_text("NO XRF GUN", Vector2(p.position.x + 22, p.position.y + 10), Color("#4a3f30"))
		_text("BUY ONE IN THE", Vector2(p.position.x + 14, p.position.y + 20), Color("#4a3f30"))
		_text("MORNING", Vector2(p.position.x + 32, p.position.y + 28), Color("#4a3f30"))
		return
	var el: float = _time - _t.xrf
	var base_y := p.end.y - 3
	draw_rect(Rect2(p.position.x + 2, base_y + 1, p.size.x - 4, 1), Color("#5a4a20"))
	if el < 0.0 or not used.has("xrf"):
		_text("READY", Vector2(p.position.x + 2, p.position.y + 1), Color("#7a5a20"))
		return
	var fill := clampf(el / XRF_SECONDS, 0.0, 1.0)
	var jitter := int(_time * 12.0) if fill < 1.0 else 0
	for n in _spectrum.size():
		var v := _spectrum[n] * fill
		v *= 1.0 + (CoinArt._hash(n, jitter, 4) - 0.5) * 0.5 * (1.0 - fill * 0.7)
		var h := roundi(clampf(v, 0.0, 1.0) * (p.size.y - 10))
		if h > 0:
			draw_rect(Rect2(p.position.x + 2 + n, base_y - h + 1, 1, h), Pal.WARN)
	_text("%.1f S" % minf(el, XRF_SECONDS) if fill < 1.0 else "DONE", Vector2(p.position.x + 2, p.position.y + 1), Pal.WARN)
	if fill < 1.0:
		return
	# readout: the elements found, biggest first
	var y := p.position.y - 4
	for entry in _surface_sorted():
		_text("%s %s" % [entry[0], _pct(entry[1])], Vector2(XRF.end.x - 42, y), Pal.WARN)
		y += 8
		if y > XRF.end.y - 8:
			break


func _surface_sorted() -> Array:
	var out := []
	for el in readings.surface:
		out.append([el, readings.surface[el]])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


static func _pct(v: float) -> String:
	return "%.2f" % v if v >= 99.0 else "%.1f" % v


func _draw_scale_lcd() -> void:
	var text := "0.00 g"
	var st: float = _time - _t.scale
	if _on_scale and st >= 0.0:
		var g: float = readings.g
		if st < 0.7:
			g *= st / 0.7
		elif st < 1.1:
			g += (0.01 if int(st * 20.0) % 2 == 0 else -0.01)
		elif not _beeped:
			_beeped = true
			Sfx.play(self, Sfx.scale_beep(), -10.0)
		text = "%.2f g" % g
	var x := SCALE_LCD.end.x - 3 - PixelFont.measure(text)
	_text(text, Vector2(x, SCALE_LCD.position.y + 3), Pal.LED)


## Length first, then width, then the thickness in the edge-on inset.
func _draw_calipers() -> void:
	if _active != "calipers":
		return
	var ct: float = _time - _t.calipers
	if ct < 0.0:
		return
	var r := _bar_rect()
	var ppm := BarArt.bench_ppm(bar)
	var close := clampf(ct / 0.7, 0.0, 1.0)
	var gap := r.size.x / 2.0 + 1.0 + roundf((1.0 - close) * 18.0)
	var cx := r.get_center().x
	_draw_caliper_h(cx - gap, cx + gap, r.position.y - 14.0, r.size.y * 0.4 + 14.0, readings.l + (1.0 - close) * 12.0)
	var wt := clampf((ct - 0.8) / 0.6, 0.0, 1.0)
	if ct >= 0.8:
		var vgap := r.size.y / 2.0 + 1.0 + roundf((1.0 - wt) * 14.0)
		_draw_caliper_v(r.get_center().y - vgap, r.get_center().y + vgap, r.end.x + 6.0, readings.w + (1.0 - wt) * 10.0)
	if ct < 1.5:
		return
	var tt := clampf((ct - 1.5) / 0.5, 0.0, 1.0)
	draw_rect(INSET, Color("#14100c"))
	draw_rect(Rect2(INSET.position, Vector2(INSET.size.x, 1)), Pal.PANEL_EDGE)
	_text("EDGE", Vector2(INSET.position.x + 3, INSET.position.y + 3), Pal.INK_FAINT)
	var thick_px := maxf(2.0, roundf(readings.t * ppm * 1.4))
	var cy := INSET.position.y + 17
	var pal := bar.palette_name()
	var x0 := INSET.position.x + 24
	var w := INSET.size.x - 66
	for row in int(thick_px):
		var col := Pal.metal(pal, 4 if row == 0 else (2 if row == int(thick_px) - 1 else 3))
		# a cast bar's sides slope in towards the top
		var indent := roundi((thick_px - 1 - row) * 0.7) if bar.is_cast() else 0
		draw_rect(Rect2(x0 + indent, cy - thick_px / 2.0 + row, w - indent * 2, 1), col)
	var steel := Color("#c3cad4")
	var jaw_gap := thick_px / 2.0 + 1.0 + (1.0 - tt) * 6.0
	draw_rect(Rect2(x0 + w / 2.0 - 8, cy - jaw_gap - 3, 16, 3), steel)
	draw_rect(Rect2(x0 + w / 2.0 - 8, cy + jaw_gap, 16, 3), steel)
	var thick: float = readings.t + (1.0 - tt) * 2.0
	_text("%.2f" % thick, Vector2(INSET.end.x - 36, cy - 3), Pal.LED)
	_text("mm", Vector2(INSET.end.x - 14, cy - 3), Pal.INK_FAINT)


func _draw_caliper_h(left: float, right: float, y: float, jaw: float, mm: float) -> void:
	var steel := Color("#c3cad4")
	var dark := Color("#6b7380")
	draw_rect(Rect2(left - 6, y, right - left + 46, 5), steel)
	draw_rect(Rect2(left - 6, y, right - left + 46, 1), Color("#eef2f6"))
	draw_rect(Rect2(left - 6, y + 4, right - left + 46, 1), dark)
	var tick := left
	while tick < right + 38:
		draw_rect(Rect2(roundf(tick), y + 1, 1, 2), dark)
		tick += 4.0
	for jx in [left - 3, right]:
		draw_rect(Rect2(jx, y, 3, jaw), Color("#9aa3b0"))
		draw_rect(Rect2(jx, y, 1, jaw), Color("#dce2ea"))
		draw_rect(Rect2(jx + 2, y, 1, jaw), Color("#59606b"))
	var lcd := Rect2(right + 4, y - 12, 38, 11)
	draw_rect(lcd, Color("#2a2e35"))
	draw_rect(lcd.grow(-1), Pal.LED_BG)
	var t := "%.2f" % mm
	_text(t, Vector2(lcd.end.x - 2 - PixelFont.measure(t), lcd.position.y + 3), Pal.LED)


func _draw_caliper_v(top: float, bottom: float, x: float, mm: float) -> void:
	var steel := Color("#c3cad4")
	draw_rect(Rect2(x + 10, top - 4, 5, bottom - top + 8), steel)
	draw_rect(Rect2(x + 10, top - 4, 1, bottom - top + 8), Color("#eef2f6"))
	for jy in [top - 3, bottom]:
		draw_rect(Rect2(x - 4, jy, 16, 3), Color("#9aa3b0"))
		draw_rect(Rect2(x - 4, jy, 16, 1), Color("#dce2ea"))
	var lcd := Rect2(x + 2, bottom + 6, 38, 11)
	draw_rect(lcd, Color("#2a2e35"))
	draw_rect(lcd.grow(-1), Pal.LED_BG)
	var t := "%.2f" % mm
	_text(t, Vector2(lcd.end.x - 2 - PixelFont.measure(t), lcd.position.y + 3), Pal.LED)


## The transducer on its cable, sitting in a dab of couplant gel.
func _draw_probe() -> void:
	if not probe_on:
		return
	var r := _bar_rect()
	var at := (r.position + probe_uv * r.size).round()
	draw_rect(Rect2(at - Vector2(4, 3), Vector2(9, 7)), Color(0.85, 0.92, 1.0, 0.35)) # gel
	# cable back up to the detector
	var from := Vector2(UT.position.x + 40, UT.end.y + 2)
	var steps := 24
	for k in steps:
		var t := k / float(steps)
		var p := from.lerp(at + Vector2(0, -10), t) + Vector2(0, sin(t * PI) * 10.0)
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color("#1c1f24"))
	draw_rect(Rect2(at + Vector2(-3, -12), Vector2(7, 10)), Color("#3a3f48"))
	draw_rect(Rect2(at + Vector2(-3, -12), Vector2(7, 1)), Color("#7d8591"))
	draw_rect(Rect2(at + Vector2(-2, -3), Vector2(5, 3)), Color("#c0392b"))
	draw_rect(Rect2(at + Vector2(-2, -3), Vector2(5, 1)), Color("#e0645a"))


## The XRF gun held over the bar, its window glowing while it reads.
func _draw_xrf_gun() -> void:
	if _active != "xrf":
		return
	var el: float = _time - _t.xrf
	if el < 0.0 or el > XRF_SECONDS + 0.6:
		return
	var r := _bar_rect()
	var target := r.get_center() + Vector2(10, -4)
	var travel := clampf(el / 0.35, 0.0, 1.0) - clampf((el - XRF_SECONDS - 0.2) / 0.4, 0.0, 1.0)
	var at := target.lerp(target + Vector2(90, -60), 1.0 - travel).round()
	# nose cone over the spot, pistol grip down to the right
	draw_rect(Rect2(at + Vector2(-2, -2), Vector2(5, 5)), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(at + Vector2(0, -10), Vector2(26, 10)), Color("#e3dccb"))
	draw_rect(Rect2(at + Vector2(0, -10), Vector2(26, 1)), Color("#fbf7ee"))
	draw_rect(Rect2(at + Vector2(0, -1), Vector2(26, 1)), Color("#9e9686"))
	draw_rect(Rect2(at + Vector2(-4, -8), Vector2(5, 7)), Color("#3a3f48"))
	draw_rect(Rect2(at + Vector2(18, 0), Vector2(7, 14)), Color("#2a2e35"))
	draw_rect(Rect2(at + Vector2(18, 0), Vector2(1, 14)), Color("#59606b"))
	draw_rect(Rect2(at + Vector2(8, -8), Vector2(9, 5)), Color("#14200f"))
	draw_rect(Rect2(at + Vector2(9, -7), Vector2(4, 1)), Pal.WARN)
	if el > 0.35 and el < XRF_SECONDS:
		var glow := 0.5 + 0.5 * sin(_time * 20.0)
		draw_rect(Rect2(at + Vector2(-6, -6), Vector2(2, 3)), Color(1.0, 0.7, 0.25, 0.5 + glow * 0.5))
		draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 2)), Color(1.0, 0.85, 0.5, 0.25 + glow * 0.3))
		draw_rect(Rect2(at + Vector2(21, -13), Vector2(2, 2)), Pal.BAD if fmod(_time, 0.4) < 0.25 else Color("#5a1a12"))


func _text(text: String, at: Vector2, col: Color) -> void:
	PixelFont.plot_text(text, func(x, y): draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


# ---------------------------------------------------------------- behaviour

func _move_bar(to: Vector2, onto_scale: bool) -> void:
	if _move_tween:
		_move_tween.kill()
	_on_scale = false
	_move_tween = create_tween()
	_move_tween.tween_property(self, "_bar_pos", to, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if onto_scale:
		_move_tween.tween_callback(func(): _on_scale = true)


func _finish_detail() -> void:
	if _detail_task < 0 or not WorkerThreadPool.is_task_completed(_detail_task):
		return
	WorkerThreadPool.wait_for_task_completion(_detail_task)
	_detail_task = -1
	(_loupe.material as ShaderMaterial).set_shader_parameter("detail_tex", _detail.texture())


func _follow_probe() -> void:
	if not probe_on or _on_scale:
		return
	var r := _bar_rect()
	var m := get_local_mouse_position()
	if r.grow(2.0).has_point(m) and m.x < BENCH_W:
		var uv := (m - r.position) / r.size
		if uv.distance_to(probe_uv) > 0.01:
			probe_at(uv)


func _update_xrf() -> void:
	if used.has("xrf") and not _xrf_done and _time - _t.xrf > XRF_SECONDS:
		_xrf_done = true
		Sfx.play(self, BarSfx.xrf_done(), -8.0)


func _update_loupe() -> void:
	if not _loupe.visible:
		return
	var m := get_local_mouse_position()
	m.x = clampf(m.x, LOUPE_SIZE / 2.0, BENCH_W - LOUPE_SIZE / 2.0)
	m.y = clampf(m.y, LOUPE_SIZE / 2.0, size.y - LOUPE_SIZE / 2.0)
	_loupe.position = (m - Vector2(LOUPE_SIZE, LOUPE_SIZE) / 2.0).round()
	_loupe_rim.position = _loupe.position - Vector2(3, 3)
	var r := _bar_rect()
	var uv := (m - r.position) / r.size
	var mat := _loupe.material as ShaderMaterial
	mat.set_shader_parameter("center_uv", uv)
	mat.set_shader_parameter("span", Vector2(LOUPE_SIZE, LOUPE_SIZE) / _zoom / r.size)
	if _serial_rect.has_point(uv):
		serial_read = true


## What the ledger says about the serial number, once the player has read it.
func serial_note() -> String:
	if not BullionBar.ledger.has(bar.serial):
		return "new"
	return "seen day %d" % BullionBar.ledger[bar.serial]


func _update_cells() -> void:
	if _cells.is_empty():
		return
	_set_cell("weight", "%.2f g" % readings.g if used.has("scale") and _on_scale and _time - _t.scale > 1.1 else "", _gauge("weight"))
	var cal: float = _time - _t.calipers
	var measuring := _active == "calipers"
	_set_cell("length", "%.1f mm" % readings.l if used.has("calipers") and (cal > 0.8 or not measuring) else "", _gauge("length"))
	_set_cell("width", "%.1f mm" % readings.w if used.has("calipers") and (cal > 1.5 or not measuring) else "", _gauge("width"))
	_set_cell("thick", "%.2f mm" % readings.t if used.has("calipers") and (cal > 2.1 or not measuring) else "", _gauge("thick"))
	if probe_on:
		var e := bar.echo_at(probe_uv)
		_set_cell("echo", "%.2f us" % e.back, Pal.BAD if bar.echo_off(probe_uv) else Pal.INK)
	var off := scan_off_count()
	if not scan.is_empty():
		_set_cell("scan", "%d off gate" % off if off > 0 else "%d spots ok" % scan.size(), Pal.BAD if off > 0 else Pal.INK)
	if used.has("xrf") and _xrf_done:
		var top: Array = _surface_sorted()[0]
		_set_cell("xrf", "%s %s%s" % [top[0], _pct(top[1]), "+" if readings.surface.size() > 1 else ""],
			Pal.INK if bar.surface_pass(readings.surface) else Pal.BAD)
	if serial_read:
		_set_cell("serial", serial_note(), Pal.INK if serial_note() == "new" else Pal.BAD)


## With digital gauges, a scale or caliper reading shows green inside the bar's
## tolerance and red outside it; without them it stays plain.
func _gauge(key: String) -> Color:
	if not Progress.has_upgrade("digital_gauges"):
		return Pal.INK
	var s := bar.spec()
	var ok: bool
	match key:
		"weight":
			ok = readings.g >= s.g - 0.005 and readings.g <= s.g * (1.0 + BullionBar.WEIGHT_OVER)
		"length":
			ok = absf(readings.l - s.l) <= BullionBar.SIZE_TOL
		"width":
			ok = absf(readings.w - s.w) <= BullionBar.SIZE_TOL
		_:
			ok = absf(readings.t - bar.thickness_mm()) <= BullionBar.THICK_TOL
	return Pal.GOOD if ok else Pal.BAD


func _set_cell(key: String, text: String, col := Pal.INK) -> void:
	var l: Label = _cells[key]
	if text == "":
		if l.text == "" or l.get_meta("measured", false) == false:
			l.text = "-"
			l.add_theme_color_override("font_color", Pal.INK_FAINT)
		return
	l.set_meta("measured", true)
	l.text = text
	l.add_theme_color_override("font_color", col)


func _build_panel() -> void:
	var x := BENCH_W + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(BENCH_W, 0)
	panel.size = Vector2(480 - BENCH_W, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(panel, 0)
	var s := bar.spec()
	_label("BAR TEST", Vector2(x, 4), Pal.INK_FAINT)
	_label(bar.display_name(), Vector2(x, 13), Pal.GOLD, 156)
	_label("%s, from %s" % [s.maker.capitalize(), customer.name], Vector2(x, 23), Pal.INK_DIM, 156)
	_label("SPEC", Vector2(x + 50, 36), Pal.INK_FAINT, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("READING", Vector2(x + 104, 36), Pal.INK_FAINT, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	var rows := [
		["weight", "Weight", "%.2f g" % s.g],
		["length", "Length", "%.1f mm" % s.l],
		["width", "Width", "%.1f mm" % s.w],
		["thick", "Thick", "%.2f mm" % bar.thickness_mm()],
		["echo", "Echo", "%.2f us" % bar.expected_echo_us()],
		["scan", "Scan", "all in gate"],
		["xrf", "XRF", "%s %s" % [BullionBar.METAL_ELEMENT[s.metal], _pct(s.purity * 100.0)]],
		["serial", "Serial", "new"],
	]
	for n in rows.size():
		var y := 46 + n * 9
		_label(rows[n][1], Vector2(x, y), Pal.INK_DIM)
		_label(rows[n][2], Vector2(x + 34, y), Pal.INK_DIM, 68, HORIZONTAL_ALIGNMENT_RIGHT)
		_cells[rows[n][0]] = _label("-", Vector2(x + 104, y), Pal.INK_FAINT, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Melt today", Vector2(x, 122), Pal.INK_DIM)
	_label(Market.format_money(customer.melt_total()), Vector2(x + 60, 122), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Your offer", Vector2(x, 131), Pal.INK_DIM)
	_label(Market.format_money(customer.offer_total()), Vector2(x + 60, 131), Pal.GOLD, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	for n in TOOLS.size():
		var tool: String = TOOLS[n]
		var b := Button.new()
		add_child(b)
		b.text = "%d %s" % [n + 1, TOOL_NAMES[tool]]
		b.theme_type_variation = "ToolButton"
		b.position = Vector2(x + (n % 2) * 80, 144 + (n / 2) * 14)
		b.size = Vector2(76, 12)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(use_tool.bind(tool))
		if tool == "xrf" and not has_xrf():
			b.disabled = true
			b.tooltip_text = "Buy the XRF analyzer in the morning upgrades."
		_tool_buttons[tool] = b
	_label("Real bars weigh their stated weight to +0.1%, size within 0.2 mm. Sweep the probe all over: the echo must stay in the gate. Tungsten hides in the middle.",
		Vector2(x, 188), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 46)
	var genuine := Button.new()
	add_child(genuine)
	genuine.text = "Genuine"
	genuine.theme_type_variation = "PrimaryButton"
	genuine.position = Vector2(x, 238)
	genuine.size = Vector2(76, 13)
	genuine.focus_mode = Control.FOCUS_NONE
	genuine.pressed.connect(func(): finished.emit("genuine"))
	var fake_button := Button.new()
	add_child(fake_button)
	fake_button.text = "Fake"
	fake_button.theme_type_variation = "DangerButton"
	fake_button.position = Vector2(x + 80, 238)
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


## X-ray counts per channel across 0-26 keV, normalised so the tallest peak is 1:
## a gentle bremsstrahlung hump plus a peak for each line of each element found.
static func _build_spectrum(surface: Dictionary, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var bins := XRF_PLOT.size.x - 4
	var out := PackedFloat32Array()
	out.resize(bins)
	var top := 0.0
	for n in bins:
		var kev := (n + 0.5) / bins * XRF_KEV
		var v := 0.05 * sin(clampf(kev / XRF_KEV, 0.0, 1.0) * PI) + rng.randf() * 0.015
		for el in surface:
			var share: float = surface[el] / 100.0
			for line in BullionBar.XRF_LINES.get(el, []):
				var d: float = (kev - line[0]) / 0.22
				v += share * line[1] * exp(-d * d)
		out[n] = v
		top = maxf(top, v)
	for n in bins:
		out[n] /= top
	return out


# ---------------------------------------------------------------- baked art

## Wooden bench, grey rubber mat, the flaw detector, the XRF analyzer and a platform scale.
func _paint_bench() -> PixelCanvas:
	var c := BenchArt.wood(BENCH_W, 270)
	# rubber mat with a dimpled grip
	var mat := MAT
	c.rect(mat.position.x + 2, mat.position.y + 3, mat.size.x, mat.size.y, Color(0, 0, 0, 0.3))
	for y in range(mat.position.y, mat.end.y):
		for x in range(mat.position.x, mat.end.x):
			var col := Color("#2c3038")
			if (x + (y / 4) * 2) % 4 == 0 and y % 4 == 0:
				col = Color("#363b45")
			elif ShopArt._noise(x, y) > 0.96:
				col = Color("#262a31")
			c.px(x, y, col)
	c.rect(mat.position.x, mat.position.y, mat.size.x, 1, Color("#4a505c"))
	c.rect(mat.position.x, mat.end.y - 1, mat.size.x, 1, Color("#1a1d22"))
	# millimetre rule along the mat's bottom edge
	var ry := mat.end.y - 4
	for mm in range(0, 140, 2):
		var rx := mat.position.x + 6 + mm
		c.rect(rx, ry - (3 if mm % 10 == 0 else 1), 1, 3 if mm % 10 == 0 else 1, Color("#6b7380"))
	# the two instruments: a green-screen flaw detector and the XRF analyzer's dock
	for box in [UT, XRF]:
		BenchArt.housing(c, box, Color("#3a3f48"))
	for plot in [UT_PLOT, XRF_PLOT]:
		c.rect(plot.position.x - 1, plot.position.y - 1, plot.size.x + 2, plot.size.y + 2, Color("#1c1f24"))
		c.rect(plot.position.x, plot.position.y, plot.size.x, plot.size.y, Color("#0b0e0a") if plot == UT_PLOT else Color("#0e0b07"))
	for gx in range(UT_PLOT.position.x + 2, UT_PLOT.end.x - 1, 12):
		for gy in range(UT_PLOT.position.y + 2, UT_PLOT.end.y - 1, 2):
			c.px(gx, gy, Color("#16261a"))
	for gy in range(UT_PLOT.position.y + 4, UT_PLOT.end.y - 1, 10):
		for gx in range(UT_PLOT.position.x + 2, UT_PLOT.end.x - 1, 2):
			c.px(gx, gy, Color("#16261a"))
	# keV ticks under the spectrum
	for kev in [5, 10, 15, 20, 25]:
		var kx := XRF_PLOT.position.x + 2 + roundi(kev / XRF_KEV * (XRF_PLOT.size.x - 4))
		c.rect(kx, XRF_PLOT.end.y - 2, 1, 2, Color("#5a4a20"))
	c.text("ULTRASONIC", UT.position.x + 4, UT.position.y + 3, Color("#9aa3b0"))
	c.text("XRF", XRF.position.x + 4, XRF.position.y + 3, Color("#9aa3b0"))
	c.text("KEV", XRF_PLOT.end.x - 16, XRF_PLOT.position.y + 2, Color("#5a4a20"))
	for k in 3:
		c.rect(UT.end.x - 30 + k * 8, UT.end.y - 6, 5, 3, Color("#22262c"))
		c.rect(UT.end.x - 30 + k * 8, UT.end.y - 6, 5, 1, Color("#6b7380"))
	c.disc(XRF.end.x - 8, XRF.position.y + 5, 2.0, Color("#c0392b"))
	# platform scale
	var s := SCALE_RECT
	BenchArt.housing(c, s, Color("#3a3f48"))
	var pan := PAN
	c.rect(pan.position.x - 1, pan.position.y - 1, pan.size.x + 2, pan.size.y + 2, Color("#1c1f24"))
	for y in range(pan.position.y, pan.end.y):
		for x in range(pan.position.x, pan.end.x):
			var brushed := Color("#b3bcc8") if (x + y * 3) % 7 else Color("#a6afbb")
			c.px(x, y, brushed)
	c.rect(pan.position.x, pan.position.y, pan.size.x, 1, Color("#dce2ea"))
	c.rect(pan.position.x, pan.end.y - 1, pan.size.x, 1, Color("#6b7380"))
	var lcd := SCALE_LCD
	c.rect(lcd.position.x - 2, lcd.position.y - 2, lcd.size.x + 4, lcd.size.y + 4, Color("#22262c"))
	c.rect(lcd.position.x, lcd.position.y, lcd.size.x, lcd.size.y, Pal.LED_BG)
	c.text("AURUM 2000", s.position.x + 6, pan.end.y + 6, Color("#848d9a"))
	c.text("MAX 2KG", s.end.x - 40, pan.end.y + 6, Color("#5b616b"))
	for bx in [s.position.x + 8, s.end.x - 26]:
		c.rect(bx, lcd.end.y + 6, 18, 5, Color("#22262c"))
		c.rect(bx + 1, lcd.end.y + 6, 16, 1, Color("#6b7380"))
	BenchArt.lamp_light(c)
	return c


func _paint_loupe_rim() -> PixelCanvas:
	var size := LOUPE_SIZE + 6
	var c := PixelCanvas.new(size + 18, size + 18)
	var ctr := size / 2.0
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
	for k in 6:
		c.px(roundi(ctr - 18 + k), roundi(ctr - 22 + k / 2), Color(1, 1, 1, 0.5))
	return c
