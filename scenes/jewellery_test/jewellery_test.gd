extends Control
## Jewellery appraisal minigame. The customer's piece lies on a velvet pad: weigh it,
## streak it on the touchstone and drop test acids on the streak, put the thermal
## tester on its stone, try a magnet and read the hallmark under the loupe. Then grade
## the metal and the stone; the offer follows from your grading at live prices.
## Readings come from JewelleryPiece; the piece's look from JewelleryArt.

signal finished(verdict: String) # "genuine", "fake" (graded as plated) or "cancel"

const BENCH_W := 316
const PAD := Rect2i(6, 14, 204, 182)
const HOME := Vector2(108, 105)
const PAN := Vector2(263, 62)
const PAN_R := 42
const SCALE_RECT := Rect2i(214, 14, 98, 116)
const SCALE_LCD := Rect2i(240, 112, 54, 11)
const TESTER := Rect2i(214, 136, 98, 56)
const LEDS_AT := Vector2i(226, 156)
const PROBE_REST := Vector2(236, 184)
const TOUCHSTONE := Rect2i(8, 202, 108, 44)
const LANE_W := 17
const BOTTLE := Rect2i(121, 210, 14, 22) # first bottle; the rest follow every BOTTLE_STEP
const BOTTLE_STEP := 16
const MAGNET_REST := Vector2(236, 226)
const LOUPE_SIZE := 64
const TOOLS := ["scale", "acid", "tester", "magnet", "loupe"]
const TOOL_NAMES := {"scale": "Scale", "acid": "Acid", "tester": "Tester", "magnet": "Magnet", "loupe": "Loupe"}
const ACID_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y]
const RUB_SECONDS := 0.7
const DROP_FALL := 0.25
const REACT_SECONDS := 1.6
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
var piece: JewelleryPiece
var used := {}
var grade := ""
var diamond := true

var _bench: Texture2D
var _tex := {} # scale -> Texture2D
var _shadow := {}
var _layout := {}
var _piece_pos := HOME
var _piece_scale := 2.0
var _on_scale := false
var _move_tween: Tween
var _time := 0.0
var _t := {"scale": -99.0, "rub": -99.0, "tester": -99.0, "magnet": -99.0}
var _drops := {} # acid -> time the drop lands
var _active := ""
var _snapped := false
var _beeped := false
var _loupe: ColorRect
var _loupe_rim: TextureRect
var _cells := {}
var _pad_tool := -1
var _grade_button: Button
var _stone_button: Button
var _values: Array[Label] = []


func start(c: Customer) -> void:
	customer = c
	piece = c.piece
	grade = piece.claimed_grade
	_layout = JewelleryArt.layout(piece)
	for s in [1, JewelleryArt.BENCH_SCALE]:
		var canvas := JewelleryArt.paint(piece, s)
		_tex[s] = canvas.texture()
		_shadow[s] = JewelleryArt.shadow_of(canvas)
	var detail := JewelleryArt.paint(piece, JewelleryArt.DETAIL_SCALE).texture()
	(_loupe.material as ShaderMaterial).set_shader_parameter("detail_tex", detail)
	_build_panel()


func _ready() -> void:
	add_to_group("pad_hooks")
	add_to_group("pad_targets")
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bench = _paint_bench().texture()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LOUPE_SHADER
	mat.shader = shader
	mat.set_shader_parameter("backdrop", Color("#1a1520"))
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
	var acid := ACID_KEYS.find(event.keycode)
	if acid >= 0:
		drop_acid(JewelleryPiece.ACIDS[acid])
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			use_tool("scale")
		KEY_2, KEY_KP_2:
			use_tool("acid")
		KEY_3, KEY_KP_3:
			use_tool("tester")
		KEY_4, KEY_KP_4:
			use_tool("magnet")
		KEY_5, KEY_KP_5:
			use_tool("loupe")
		KEY_G:
			cycle_grade(1)
		KEY_D:
			toggle_stone()
		KEY_ENTER, KEY_KP_ENTER:
			finish()
		KEY_ESCAPE:
			finished.emit("cancel")
		_:
			return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var at: Vector2 = event.position
	for i in JewelleryPiece.ACIDS.size():
		if _bottle_rect(i).grow(2).has_point(at) or _lane_rect(i).has_point(at):
			drop_acid(JewelleryPiece.ACIDS[i])
			accept_event()
			return


## LB and RB step through the tools, the same as the number keys.
func pad_action(name: String) -> bool:
	if name != "lb" and name != "rb":
		return _pad_trigger(name)
	var list := TOOLS
	_pad_tool = posmod(_pad_tool + (1 if name == "rb" else -1), list.size())
	if _loupe.visible:
		use_tool("loupe")
	if list[_pad_tool] != "loupe" or not _loupe.visible:
		use_tool(list[_pad_tool])
	return true


func pad_help() -> Array:
	return [["LT", "Diamond or not"], ["RT", "Next grade"], ["LB / RB", "Previous / next tool"]]


## LT flips the stone call, RT steps the grade.
func _pad_trigger(name: String) -> bool:
	if name == "lt":
		toggle_stone()
	elif name == "rt":
		cycle_grade(1)
	else:
		return false
	return true


## The acid bottles are drawn, not buttons, so the d-pad is told where they are.
func pad_targets() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var xf := get_global_transform_with_canvas()
	for i in JewelleryPiece.ACIDS.size():
		out.append(xf * Rect2(_bottle_rect(i)))
	return out


func use_tool(tool: String) -> void:
	used[tool] = true
	if tool == "loupe":
		_loupe.visible = not _loupe.visible
		_loupe_rim.visible = _loupe.visible
		Pad.hide_cursor(_loupe.visible)
		Sfx.play(self, Sfx.click(), -10.0)
		return
	if tool == "tester" and piece.stone == "":
		Sfx.play(self, Sfx.click(), -10.0)
		return
	_active = tool
	if tool == "scale":
		_beeped = false
		_move_piece(PAN, 1.0, true)
		_t.scale = _time + 0.4
		return
	var delay := 0.0
	if _on_scale or _piece_scale != 2.0:
		_move_piece(HOME, 2.0, false)
		delay = 0.4
	_t[{"acid": "rub"}.get(tool, tool)] = _time + delay
	_snapped = false
	match tool:
		"acid":
			_drops.clear()
			get_tree().create_timer(delay).timeout.connect(func(): Sfx.play(self, JewellerySfx.rub(), -6.0))
		"tester":
			get_tree().create_timer(delay + 0.6).timeout.connect(func(): Sfx.play(self, JewellerySfx.tester(piece.tester_leds()), -8.0))


## Drops one of the test acids on its streak, rubbing fresh streaks first if needed.
func drop_acid(acid: String) -> void:
	used["acid"] = true
	var wait := 0.0
	if _t.rub < 0.0:
		use_tool("acid")
		wait = maxf(_t.rub - _time, 0.0) + RUB_SECONDS
	elif _time < _t.rub + RUB_SECONDS:
		wait = _t.rub + RUB_SECONDS - _time
	if _drops.has(acid):
		return
	var lands := _time + wait + DROP_FALL
	_drops[acid] = lands
	get_tree().create_timer(wait + DROP_FALL).timeout.connect(func():
		Sfx.play(self, JewellerySfx.drip(), -8.0)
		if piece.acid_reaction(acid) == "fizz":
			Sfx.play(self, JewellerySfx.fizz(), -6.0))


func cycle_grade(step: int) -> void:
	var options := piece.grade_options()
	grade = options[posmod(options.find(grade) + step, options.size())]
	Sfx.play(self, Sfx.click(), -12.0)
	_refresh_assessment()


func toggle_stone() -> void:
	if piece.stone == "":
		return
	diamond = not diamond
	Sfx.play(self, Sfx.click(), -12.0)
	_refresh_assessment()


## Weight the offer is based on: the scale's reading once weighed, else the claim.
func assessed_weight() -> float:
	return snappedf(piece.weight_g, 0.01) if used.has("scale") else piece.claimed_g


func finish() -> void:
	customer.assessed = {"grade": grade, "diamond": diamond and piece.stone != "", "weight": assessed_weight()}
	finished.emit("fake" if grade == "plated" else "genuine")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_bench, Vector2.ZERO)
	_draw_bottles()
	_draw_streaks()
	_draw_scale_lcd()
	_draw_leds()
	var rect := _piece_rect()
	var s := roundi(_piece_scale)
	if is_equal_approx(_piece_scale, float(s)) and _tex.has(s):
		draw_texture(_shadow[s], rect.position + Vector2(s, s * 2))
		draw_texture(_tex[s], rect.position)
	else:
		draw_texture_rect(_tex[JewelleryArt.BENCH_SCALE], rect, false)
	_draw_glint(rect)
	_draw_drop()
	_draw_probe()
	_draw_magnet()
	BenchArt.draw_motes(self, _time, Rect2(0, 0, BENCH_W, 270))


## Where the piece's canvas sits on screen right now.
func _piece_rect() -> Rect2:
	var size := JewelleryArt.SIZE * _piece_scale
	return Rect2((_piece_pos + _magnet_pull() - size / 2.0).round(), size)


func _to_screen(base: Vector2) -> Vector2:
	var r := _piece_rect()
	return r.position + base * _piece_scale


func _draw_glint(rect: Rect2) -> void:
	var st: Vector3 = _layout.stone
	if st.z <= 0.0:
		return
	var phase := fmod(_time + 0.7, 2.6)
	if phase > 0.5:
		return
	var sq: float = _layout.squash
	var at := (rect.position + Vector2(st.x - st.z * 0.35, st.y - st.z * sq * 0.4) * _piece_scale).round()
	var k := 1.0 - absf(phase - 0.25) / 0.25
	var arm := roundi(1.0 + k * (2.0 + _piece_scale))
	draw_rect(Rect2(at, Vector2.ONE), Color(1, 1, 1))
	for n in range(1, arm + 1):
		var a := 0.9 * (1.0 - float(n) / (arm + 1))
		for d in [Vector2(n, 0), Vector2(-n, 0), Vector2(0, n), Vector2(0, -n)]:
			draw_rect(Rect2(at + d, Vector2.ONE), Color(1, 1, 1, a))


func _draw_scale_lcd() -> void:
	var text := "0.00 g"
	var st: float = _time - _t.scale
	if _on_scale and st >= 0.0:
		var g := piece.weight_g
		if st < 0.6:
			g *= st / 0.6
		elif st < 1.0:
			g += (0.01 if int(st * 20.0) % 2 == 0 else -0.01)
		elif not _beeped:
			_beeped = true
			Sfx.play(self, Sfx.scale_beep(), -10.0)
		text = "%.2f g" % g
	_text(text, Vector2(SCALE_LCD.end.x - 3 - PixelFont.measure(text), SCALE_LCD.position.y + 3), Pal.LED)


func _lane_rect(i: int) -> Rect2:
	return Rect2(TOUCHSTONE.position.x + 4 + i * LANE_W, TOUCHSTONE.position.y + 6, LANE_W - 4, TOUCHSTONE.size.y - 12)


func _bottle_rect(i: int) -> Rect2:
	return Rect2(BOTTLE.position + Vector2i(i * BOTTLE_STEP, 0), BOTTLE.size)


## Streaks of the piece's metal on the touchstone, and what each acid did to them.
func _draw_streaks() -> void:
	var rt: float = _time - _t.rub
	if rt < 0.0 or _t.rub < 0.0:
		return
	var grow := clampf(rt / RUB_SECONDS, 0.0, 1.0)
	var ramp := JewelleryArt._ramp(piece.palette_name())
	for i in JewelleryPiece.ACIDS.size():
		var lane := _lane_rect(i)
		var acid: String = JewelleryPiece.ACIDS[i]
		var reaction := ""
		var rk := 0.0
		if _drops.has(acid) and _time >= _drops[acid]:
			reaction = piece.acid_reaction(acid)
			rk = clampf((_time - _drops[acid]) / REACT_SECONDS, 0.0, 1.0)
		var h := roundi(lane.size.y * grow)
		for y in h:
			for x in range(2, int(lane.size.x) - 2):
				var n := CoinArt._hash(x + i * 31, y, piece.seed)
				if n < 0.18 or (x == 2 or x == int(lane.size.x) - 3) and n < 0.6:
					continue
				var col := ramp[3] if n > 0.55 else (ramp[4] if n > 0.9 else ramp[2])
				match reaction:
					"fades":
						col.a = 1.0 - rk * (0.8 if n > 0.3 else 1.0)
					"fizz":
						col = col.lerp(Color("#3d6b3a"), minf(rk * 3.0, 1.0))
						col.a = 1.0 - rk
					"milky":
						col = col.lerp(Color("#e8e2cc"), rk * 0.85)
					"red":
						col = col.lerp(Color("#8a1418"), rk * 0.9)
					"green":
						col = col.lerp(Color("#3a8a7a"), rk * 0.9)
				if col.a > 0.02:
					draw_rect(Rect2(lane.position + Vector2(x, y), Vector2.ONE), col)
		# the wet drop sitting on the streak, and the bubbles when base metal fizzes
		if reaction != "":
			var wet := Vector2(lane.get_center().x, lane.position.y + lane.size.y * 0.45).round()
			var drop_col := Color(0.85, 0.9, 1.0, 0.35 * (1.0 - rk * 0.5))
			for d in [Vector2(-2, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
				draw_rect(Rect2(wet + d, Vector2.ONE), drop_col)
			draw_rect(Rect2(wet + Vector2(-1, -1), Vector2.ONE), Color(1, 1, 1, 0.7 * (1.0 - rk * 0.5)))
			if reaction == "fizz" and rk < 0.95:
				for b in 5:
					var bt := fmod(_time * 2.0 + b * 0.37, 1.0)
					var bx := roundf(wet.x - 4.0 + CoinArt._hash(b, i, 3) * 8.0)
					var by := roundf(wet.y + 3.0 - bt * 10.0)
					draw_rect(Rect2(bx, by, 1, 1), Color("#9be07a", 1.0 - bt))


func _draw_bottles() -> void:
	for i in JewelleryPiece.ACIDS.size():
		var r := _bottle_rect(i)
		var acid: String = JewelleryPiece.ACIDS[i]
		var lift := 0.0
		if _drops.has(acid):
			var dt: float = _time - (_drops[acid] - DROP_FALL)
			if dt > -0.15 and dt < 0.4:
				lift = 3.0
		var top := r.position + Vector2(0, -lift)
		# dropper bulb and collar
		draw_rect(Rect2(top + Vector2(4, -7), Vector2(5, 5)), Color("#1d1a1a"))
		draw_rect(Rect2(top + Vector2(5, -7), Vector2(1, 3)), Color("#4a4444"))
		draw_rect(Rect2(top + Vector2(3, -2), Vector2(7, 3)), Color("#2b2b2e"))
		# amber glass with a highlight and a paper label
		draw_rect(Rect2(top + Vector2(0, 1), Vector2(r.size.x, r.size.y - 1)), Color("#5a2f0c"))
		draw_rect(Rect2(top + Vector2(1, 2), Vector2(1, r.size.y - 4)), Color("#c47a2e"))
		draw_rect(Rect2(top + Vector2(r.size.x - 2, 2), Vector2(1, r.size.y - 4)), Color("#3a1d06"))
		draw_rect(Rect2(top + Vector2(0, 8), Vector2(r.size.x, 9)), Color("#e8dfc8"))
		var label_w := PixelFont.measure(acid)
		_text(acid, top + Vector2(roundf((r.size.x - label_w) / 2.0), 10), Color("#3a2414"))
		_text("QWERTY"[i], Vector2(r.position.x + 4, r.end.y + 3), Pal.INK_FAINT)


## The falling drop between a bottle and its lane.
func _draw_drop() -> void:
	for i in JewelleryPiece.ACIDS.size():
		var acid: String = JewelleryPiece.ACIDS[i]
		if not _drops.has(acid):
			continue
		var k: float = 1.0 - (_drops[acid] - _time) / DROP_FALL
		if k < 0.0 or k > 1.0:
			continue
		var from := _bottle_rect(i).position + Vector2(6, -9)
		var lane := _lane_rect(i)
		var to := Vector2(lane.get_center().x, lane.position.y + lane.size.y * 0.45)
		var at := from.lerp(to, k) + Vector2(0, -sin(k * PI) * 10.0)
		draw_rect(Rect2(at.round(), Vector2(1, 2)), Color(0.85, 0.92, 1.0, 0.9))


func _draw_leds() -> void:
	var lit := 0
	var tt: float = _time - _t.tester
	if _active == "tester" and tt > 0.5 and tt < 4.0:
		lit = mini(piece.tester_leds(), int((tt - 0.5) / 0.07) + 1)
	for k in 10:
		var col: Color = [Color("#3fae4a"), Color("#3fae4a"), Color("#3fae4a"), Color("#c8c23a"), Color("#c8c23a"), Color("#c8c23a"), Color("#c8c23a"), Color("#d8762e"), Color("#d8762e"), Color("#e04a3a")][k]
		var at := Vector2(LEDS_AT.x + k * 7, LEDS_AT.y)
		if k < lit:
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(7, 6)), Color(col, 0.25))
			draw_rect(Rect2(at, Vector2(5, 4)), col.lightened(0.25))
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(2, 1)), Color(1, 1, 1, 0.8))
		else:
			draw_rect(Rect2(at, Vector2(5, 4)), col.darkened(0.7))


## The tester's pen: rests on its cradle, travels to the stone and touches it.
func _draw_probe() -> void:
	var tip := PROBE_REST
	var tt: float = _time - _t.tester
	var st: Vector3 = _layout.stone
	if _active == "tester" and tt >= 0.0 and tt < 3.0 and st.z > 0.0:
		var target := _to_screen(Vector2(st.x + st.z * 0.2, st.y)) + Vector2(1, 0)
		var go := clampf(tt / 0.5, 0.0, 1.0) - clampf((tt - 2.4) / 0.5, 0.0, 1.0)
		tip = PROBE_REST.lerp(target, go * go * (3.0 - 2.0 * go))
	tip = tip.round()
	var dir := Vector2(1, 0.55).normalized()
	# cable back to the box
	var tail := tip + dir * 30.0
	var box := Vector2(TESTER.end.x - 6, TESTER.end.y - 4)
	for k in 13:
		var t := k / 12.0
		var p := tail.lerp(box, t) + Vector2(0, sin(t * PI) * 6.0)
		draw_rect(Rect2(p.round(), Vector2(1, 1)), Color("#16161a"))
	for k in 31:
		var p := (tip + dir * k).round()
		var col := Color("#c3cad4") if k < 4 else (Color("#2a2e35") if k < 9 else Color("#d9d4c6"))
		var w := 1 if k < 4 else 3
		draw_rect(Rect2(p - Vector2(0, (w - 1) / 2), Vector2(1, w)), col)
		if k >= 9:
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color("#f2eee2"))
	draw_rect(Rect2(tip, Vector2(1, 1)), Color(1, 1, 1))


func _magnet_pull() -> Vector2:
	var mt: float = _time - _t.magnet
	if _active != "magnet" or mt < 0.0 or mt > 3.2:
		return Vector2.ZERO
	var hold := clampf((3.2 - mt) / 0.4, 0.0, 1.0)
	match piece.magnet():
		"strong":
			var snap := clampf((mt - 0.55) / 0.1, 0.0, 1.0)
			if snap > 0.0 and not _snapped:
				_snapped = true
				Sfx.play(self, Sfx.magnet_snap(), -4.0)
			return Vector2(roundf(snap * hold * 8.0), roundf(snap * hold * 4.0))
		"clasp":
			var tick := clampf((mt - 0.6) / 0.2, 0.0, 1.0)
			if tick > 0.0 and not _snapped:
				_snapped = true
				Sfx.play(self, Sfx.magnet_snap(), -18.0)
			return Vector2(roundf(tick * hold), 0)
	return Vector2.ZERO


func _draw_magnet() -> void:
	var mt: float = _time - _t.magnet
	var at := MAGNET_REST
	if _active == "magnet" and mt >= 0.0 and mt <= 3.2:
		var travel := clampf(mt / 0.6, 0.0, 1.0) - clampf((mt - 2.8) / 0.4, 0.0, 1.0)
		var clasp: Vector2 = _layout.clasp
		var target := HOME + (clasp - JewelleryArt.SIZE / 2.0) * 2.0 + Vector2(6, 2) + _magnet_pull()
		at = MAGNET_REST.lerp(target, travel * travel * (3.0 - 2.0 * travel))
	var x := roundf(at.x)
	var y := roundf(at.y)
	draw_rect(Rect2(x + 13, y + 6, 46, 8), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(x + 12, y + 4, 46, 8), Color("#8a5a30"))
	draw_rect(Rect2(x + 12, y + 4, 46, 1), Color("#b88a4c"))
	draw_rect(Rect2(x + 12, y + 11, 46, 1), Color("#5e3b1d"))
	draw_rect(Rect2(x + 12, y + 2, 3, 12), Color("#7d8591"))
	draw_rect(Rect2(x, y, 13, 16), Color("#9aa3b0"))
	draw_rect(Rect2(x, y, 13, 1), Color("#eef2f6"))
	draw_rect(Rect2(x, y, 1, 16), Color("#dce2ea"))
	draw_rect(Rect2(x + 1, y + 15, 12, 1), Color("#59606b"))
	draw_rect(Rect2(x + 12, y + 1, 1, 15), Color("#6b7380"))
	_text("N", Vector2(x + 5, y + 6), Color("#c0392b"))


func _text(text: String, at: Vector2, col: Color) -> void:
	PixelFont.plot_text(text, func(x, y): draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


# ---------------------------------------------------------------- behaviour

func _move_piece(to: Vector2, scale: float, onto_scale: bool) -> void:
	if _move_tween:
		_move_tween.kill()
	_on_scale = false
	_move_tween = create_tween().set_parallel()
	_move_tween.tween_property(self, "_piece_pos", to, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "_piece_scale", scale, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if onto_scale:
		_move_tween.chain().tween_callback(func(): _on_scale = true)


func _update_loupe() -> void:
	if not _loupe.visible:
		return
	var m := Pad.mouse_in(self)
	m.x = clampf(m.x, LOUPE_SIZE / 2.0, BENCH_W - LOUPE_SIZE / 2.0)
	m.y = clampf(m.y, LOUPE_SIZE / 2.0, size.y - LOUPE_SIZE / 2.0)
	_loupe.position = (m - Vector2(LOUPE_SIZE, LOUPE_SIZE) / 2.0).round()
	_loupe_rim.position = _loupe.position - Vector2(3, 3)
	var rect := _piece_rect()
	var detail_size := JewelleryArt.SIZE * JewelleryArt.DETAIL_SCALE
	var mat := _loupe.material as ShaderMaterial
	mat.set_shader_parameter("center_uv", (m - rect.position) / rect.size)
	mat.set_shader_parameter("span", Vector2(LOUPE_SIZE, LOUPE_SIZE) / detail_size)
	# reading the hallmark needs the loupe right over it
	var base := (m - rect.position) / _piece_scale
	var stamp: Vector2 = _layout.stamp
	if absf(base.x - stamp.x) < 7.0 and absf(base.y - stamp.y) < 3.5:
		used["stamp"] = true
	var st: Vector3 = _layout.stone
	if st.z > 0.0 and base.distance_to(Vector2(st.x, st.y)) < st.z + 1.5:
		used["stone_loupe"] = true


func _update_cells() -> void:
	if _cells.is_empty():
		return
	_set_cell("weight", "%.2f g" % piece.weight_g if used.has("scale") and _on_scale and _time - _t.scale > 1.0 else "")
	_set_cell("stamp", piece.stamp if used.has("stamp") else "")
	_set_cell("acid", _acid_summary())
	var magnet_text := {"strong": "snaps hard", "clasp": "clasp only", "none": "no pull"}
	_set_cell("magnet", magnet_text[piece.magnet()] if used.has("magnet") and _time - _t.magnet > 1.4 else "")
	var tt: float = _time - _t.tester
	if piece.stone != "":
		_set_cell("stone", ("DIAMOND" if piece.tester_leds() >= 10 else "SIMULANT") if used.has("tester") and tt > 1.4 else "")


## What the settled acid drops say, most telling first.
func _acid_summary() -> String:
	var settled := {}
	for acid in _drops:
		if _time - _drops[acid] > REACT_SECONDS * 0.8:
			settled[acid] = piece.acid_reaction(acid)
	if settled.is_empty():
		return ""
	if "fizz" in settled.values():
		return "fizzes!"
	var held := ""
	var failed := ""
	for acid in JewelleryPiece.GOLD_GRADES:
		if settled.get(acid, "") == "holds":
			held = acid
		elif settled.get(acid, "") in ["fades", "milky"] and failed == "":
			failed = acid
	if held != "" or failed != "":
		return ("%s+" % held if held != "" else "") + (" " if held != "" and failed != "" else "") + ("<%s" % failed if failed != "" else "")
	if settled.has("AG"):
		return "AG %s" % settled.AG
	return "PT %s" % settled.PT


func _set_cell(key: String, text: String) -> void:
	if not _cells.has(key):
		return
	var l: Label = _cells[key]
	if text == "":
		if l.text == "" or l.get_meta("measured", false) == false:
			l.text = "-"
			l.add_theme_color_override("font_color", Pal.INK_FAINT)
		return
	l.set_meta("measured", true)
	l.text = text
	l.add_theme_color_override("font_color", Pal.INK)


func _refresh_assessment() -> void:
	if _grade_button == null:
		return
	_grade_button.text = "Metal: %s" % ("plated" if grade == "plated" else grade)
	_grade_button.theme_type_variation = "DangerButton" if grade == "plated" else "ToolButton"
	var w := assessed_weight()
	var metal_value := piece.value_as(grade, false, w)
	var stone_value := JewelleryPiece.diamond_value(piece.carat) if piece.stone != "" and diamond else 0.0
	if _stone_button:
		_stone_button.text = "Stone: %s" % ("diamond" if diamond else "fake")
		_stone_button.theme_type_variation = "ToolButton" if diamond else "DangerButton"
	_values[0].text = "Metal %s" % ("(claimed weight)" if not used.has("scale") else "(%.2f g)" % w)
	_values[1].text = Market.format_money(metal_value)
	_values[2].text = Market.format_money(stone_value) if piece.stone != "" else "-"
	_values[3].text = Market.format_money((metal_value + stone_value) * Shop.buy_percent)


func _build_panel() -> void:
	var x := BENCH_W + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(BENCH_W, 0)
	panel.size = Vector2(480 - BENCH_W, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(panel, 0)
	_label("JEWELLERY APPRAISAL", Vector2(x, 4), Pal.INK_FAINT)
	_label(piece.title(), Vector2(x, 13), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 17)
	_label("from %s" % customer.name, Vector2(x, 31), Pal.INK_DIM, 156)
	_label("CLAIM", Vector2(x + 40, 41), Pal.INK_FAINT, 56, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("READING", Vector2(x + 100, 41), Pal.INK_FAINT, 56, HORIZONTAL_ALIGNMENT_RIGHT)
	var stamp_claim: String = "%s/%s" % [piece.claimed_grade, {"18K": "750", "14K": "585", "10K": "417", "22K": "916", "925": "STER", "PT950": "950"}[piece.claimed_grade]]
	var acid_claim: String = {"XAU": "%s+" % piece.claimed_grade, "XAG": "AG red", "XPT": "PT holds"}[piece.metal]
	var rows := [
		["weight", "Weight", "about %s g" % str(piece.claimed_g)],
		["stamp", "Stamp", stamp_claim],
		["acid", "Acid", acid_claim],
		["magnet", "Magnet", "clasp only" if piece.kind in ["chain", "bracelet"] else "no pull"],
		["stone", "Stone", "diamond" if piece.stone != "" else "none"],
	]
	for n in rows.size():
		var y := 50 + n * 9
		_label(rows[n][1], Vector2(x, y), Pal.INK_DIM)
		_label(rows[n][2], Vector2(x + 36, y), Pal.INK_DIM, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		_cells[rows[n][0]] = _label("-", Vector2(x + 100, y), Pal.INK_FAINT, 56, HORIZONTAL_ALIGNMENT_RIGHT)
	for n in TOOLS.size():
		var tool: String = TOOLS[n]
		var b := _button("%d %s" % [n + 1, TOOL_NAMES[tool]], Rect2(x + (n % 2) * 80, 97 + (n / 2) * 14, 76, 12), "ToolButton", use_tool.bind(tool))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if tool == "tester" and piece.stone == "":
			b.disabled = true
			b.tooltip_text = "No stone to test"
	_grade_button = _button("", Rect2(x, 140, 76, 12), "ToolButton", cycle_grade.bind(1))
	_grade_button.tooltip_text = "Click (or G) to change the grade you pay for"
	if piece.stone != "":
		_stone_button = _button("", Rect2(x + 80, 140, 76, 12), "ToolButton", toggle_stone)
		_stone_button.tooltip_text = "Click (or D) to pay for the stone or not"
	var captions := ["", "Stone", "Your offer"]
	for n in 3:
		var y := 156 + n * 9
		var caption := _label(captions[n], Vector2(x, y), Pal.INK_DIM, 100)
		if n == 0:
			_values.append(caption)
		_values.append(_label("", Vector2(x + 76, y), Pal.GOLD if n == 2 else Pal.INK, 80, HORIZONTAL_ALIGNMENT_RIGHT))
	_label("Read the stamp under the loupe. A streak survives acids up to its karat; base metal fizzes. Moissanite fools the tester: look for doubled facet edges.",
		Vector2(x, 186), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 46)
	_button("Finish appraisal", Rect2(x, 236, 156, 13), "PrimaryButton", finish)
	_label("Esc: back   G/D: grade   Q-Y: acids", Vector2(x, 256), Pal.INK_FAINT)
	_refresh_assessment()
	Shop.changed.connect(_refresh_assessment)
	move_child(_loupe, -1)
	move_child(_loupe_rim, -1)


func _button(text: String, r: Rect2, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	add_child(b)
	b.text = text
	b.theme_type_variation = variation
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


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

## Wooden bench with a black velvet pad, a slate touchstone, a pocket scale and
## the thermal tester's box. Bottles, LEDs, pen and magnet are drawn live.
func _paint_bench() -> PixelCanvas:
	var c := BenchArt.wood(BENCH_W, 270)
	# velvet pad: deep pile with a soft sheen towards the light
	var pad := PAD
	c.rect(pad.position.x + 2, pad.position.y + 3, pad.size.x, pad.size.y, Color(0, 0, 0, 0.4))
	for y in range(pad.position.y, pad.end.y):
		for x in range(pad.position.x, pad.end.x):
			var v := ShopArt._noise(x, y)
			var sheen := 1.0 - Vector2(x - pad.position.x, y - pad.position.y).length() / 240.0
			var col := Color("#1a1520").lerp(Color("#2a2233"), clampf(sheen * 0.6, 0.0, 1.0))
			if v > 0.9:
				col = col.lightened(0.06)
			elif v < 0.1:
				col = col.darkened(0.2)
			c.px(x, y, col)
	for x in range(pad.position.x, pad.end.x):
		c.px(x, pad.position.y, Color("#3a3044"))
		c.px(x, pad.end.y - 1, Color("#0e0b12"))
		if x % 4 < 2:
			c.px(x, pad.position.y + 3, Color("#4a3e57"))
			c.px(x, pad.end.y - 4, Color("#4a3e57"))
	for y in range(pad.position.y, pad.end.y):
		c.px(pad.position.x, y, Color("#3a3044"))
		c.px(pad.end.x - 1, y, Color("#0e0b12"))
		if y % 4 < 2:
			c.px(pad.position.x + 3, y, Color("#4a3e57"))
			c.px(pad.end.x - 4, y, Color("#4a3e57"))
	# touchstone: black slate, fine grain, bevelled edge, lane labels underneath
	var ts := TOUCHSTONE
	c.rect(ts.position.x + 2, ts.position.y + 3, ts.size.x, ts.size.y, Color(0, 0, 0, 0.4))
	for y in range(ts.position.y, ts.end.y):
		for x in range(ts.position.x, ts.end.x):
			var v := ShopArt._noise(x * 3, y * 2)
			c.px(x, y, Color("#18181b") if v > 0.2 else Color("#111113"))
	c.rect(ts.position.x, ts.position.y, ts.size.x, 1, Color("#3c3c42"))
	c.rect(ts.position.x, ts.position.y, 1, ts.size.y, Color("#2e2e33"))
	c.rect(ts.position.x, ts.end.y - 1, ts.size.x, 1, Color("#050506"))
	c.rect(ts.end.x - 1, ts.position.y, 1, ts.size.y, Color("#08080a"))
	for i in JewelleryPiece.ACIDS.size():
		var lane := _lane_rect(i)
		var label: String = JewelleryPiece.ACIDS[i]
		c.text(label, roundi(lane.get_center().x - PixelFont.measure(label) / 2.0), ts.end.y + 3, Color("#c9a77a"))
	c.text("TOUCHSTONE", ts.position.x + 2, ts.position.y - 9, Color("#a3815a"))
	c.text("ACIDS", BOTTLE.position.x, BOTTLE.position.y - 17, Color("#a3815a"))
	# pocket scale
	var s := SCALE_RECT
	BenchArt.housing(c, s, Color("#3a3f48"))
	for y in range(s.position.y + 3, s.end.y - 3):
		for x in range(s.position.x + 3, s.end.x - 3):
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
	c.text("CT/G", s.position.x + 5, lcd.position.y + 3, Color("#848d9a"))
	# thermal diamond tester
	var t := TESTER
	BenchArt.housing(c, t, Color("#2b2f36"))
	c.text("THERMAL TESTER", t.position.x + 5, t.position.y + 4, Color("#9aa3b0"))
	c.rect(LEDS_AT.x - 3, LEDS_AT.y - 3, 76, 10, Color("#14161a"))
	c.text("SIM", LEDS_AT.x - 2, LEDS_AT.y + 9, Color("#3fae4a"))
	c.text("DIA", LEDS_AT.x + 58, LEDS_AT.y + 9, Color("#e04a3a"))
	# pen cradle
	c.rect(PROBE_REST.x + 6, PROBE_REST.y + 2, 26, 3, Color("#1c1f24"))
	BenchArt.lamp_light(c)
	return c


func _paint_loupe_rim() -> PixelCanvas:
	var size := LOUPE_SIZE + 6
	var c := PixelCanvas.new(size + 18, size + 18)
	var ctr := size / 2.0
	for t in 22:
		var p := Vector2(ctr, ctr) + Vector2(1, 1).normalized() * (ctr + t - 2.0)
		c.disc(p.x, p.y, 3.0, Color("#16161a") if t < 3 else Color("#2b2b30"))
		c.px(roundi(p.x) - 1, roundi(p.y) - 2, Color("#55555e"))
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - ctr, y + 0.5 - ctr)
			var r := d.length()
			if r > ctr or r < ctr - 3.0:
				continue
			var lit := d.x + d.y < 0.0
			var col := Color("#dce2ea") if lit else Color("#6b7380")
			if r < ctr - 2.0:
				col = Color("#3b4048")
			if r > ctr - 0.8:
				col = Color("#16181c")
			c.px(x, y, col)
	for k in 6:
		c.px(roundi(ctr - 18 + k), roundi(ctr - 22 + k / 2), Color(1, 1, 1, 0.5))
	return c
