class_name GradingBench
extends Control
## Coin grading bench. The collector's coin lies on black velvet under a lamp:
##   1 Lamp    move the lamp round the coin. Close in, it shines from high above; far
##             out, it rakes across low. The lustre's cartwheel spins with it, worn high
##             points stay dull, and a low light shows hairlines and marks
##   2 Loupe   magnify the coin; click a bag mark to tag it and count it
##   3 Guide   the grading guide: what each grade looks like
## Pick a grade (Left/Right or the buttons), tick Cleaned if it has been, then Grade it.
## The coin's truth is CoinGrade; GradeArt paints its relief and the lamp shader lights it.

signal finished(verdict: String) # "graded" or "cancel"

const BENCH_W := 316
const COIN_AT := Vector2(150, 130)
const LOUPE_SIZE := 72
const TOOLS := ["lamp", "loupe", "guide"]
const TOOL_NAMES := {"lamp": "Lamp", "loupe": "Loupe", "guide": "Guide"}
## Lamp elevation: high overhead when close to the coin, raking low at the bench's edge.
const LAMP_HIGH := 1.25
const LAMP_LOW := 0.2
const LAMP_REACH := Vector2(30.0, 150.0)
const TAG_REACH := 3.0

var customer: Customer
var coin: CoinGrade
## The grade picked (index into CoinGrade.GRADES, -1 for none) and the Cleaned box.
var pick := -1
var cleaned := false
## Bag marks tagged under the loupe (indices into coin.marks), and tools used.
var tagged := {}
var used := {}
var lamp := COIN_AT + Vector2(-70, -60)
var guide_open := false

var _bench: Texture2D
var _coin: ColorRect
var _loupe: ColorRect
var _loupe_rim: TextureRect
var _detail_task := -1
var _detail := {}
var _active := "lamp"
var _time := 0.0
var _tool_buttons := {}
var _grade_buttons: Array[Button] = []
var _cells := {}
var _guide_text: Label
var _clean_button: Button
var _done_button: Button
var _miss_at := -99.0
var _pad_tool := 0


func start(c: Customer) -> void:
	customer = c
	coin = c.grading
	var pal := Pal.for_metal(coin.item.metal) if coin.item.palette == "" else coin.item.palette
	var art := GradeArt.bake(coin, 1)
	var mat := GradeArt.material(pal)
	mat.set_shader_parameter("relief", ImageTexture.create_from_image(art.relief))
	mat.set_shader_parameter("surface", ImageTexture.create_from_image(art.surface))
	_coin.material = mat
	var loupe_mat := GradeArt.material(pal)
	loupe_mat.set_shader_parameter("loupe", true)
	loupe_mat.set_shader_parameter("backdrop", Color("#101014"))
	loupe_mat.set_shader_parameter("relief", ImageTexture.create_from_image(art.relief))
	loupe_mat.set_shader_parameter("surface", ImageTexture.create_from_image(art.surface))
	_loupe.material = loupe_mat
	# the loupe's 3x painting takes a moment: paint it off the main thread
	var cg := coin
	_detail_task = WorkerThreadPool.add_task(func(): _detail = GradeArt.bake(cg, GradeArt.LOUPE_SCALE))
	_build_panel()
	_light()


func _ready() -> void:
	add_to_group("pad_hooks")
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bench = _paint_bench().texture()
	_coin = ColorRect.new()
	_coin.size = Vector2(GradeArt.SIZE, GradeArt.SIZE)
	_coin.position = COIN_AT - _coin.size / 2.0
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_coin)
	_loupe = ColorRect.new()
	_loupe.size = Vector2(LOUPE_SIZE, LOUPE_SIZE)
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
	if _detail_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_detail_task)
		_detail_task = -1


func _process(delta: float) -> void:
	_time += delta
	_finish_detail()
	if _active == "lamp" and not guide_open:
		var m := Pad.mouse_in(self)
		if m.x < BENCH_W and Rect2(0, 0, BENCH_W, 270).has_point(m):
			lamp = m
			_light()
	_coin.visible = not guide_open
	_update_loupe()
	_update_cells()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _loupe.visible and event.position.x < BENCH_W:
			tag_at(_loupe_centre())
			accept_event()
		elif guide_open:
			guide_open = false
			accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			use_tool("lamp")
		KEY_2, KEY_KP_2:
			use_tool("loupe")
		KEY_3, KEY_KP_3:
			use_tool("guide")
		KEY_LEFT, KEY_Q:
			step_grade(-1)
		KEY_RIGHT, KEY_E:
			step_grade(1)
		KEY_C:
			toggle_cleaned()
		KEY_ENTER, KEY_KP_ENTER:
			finish()
		KEY_ESCAPE:
			if guide_open:
				guide_open = false
			else:
				finished.emit("cancel")
		_:
			return
	get_viewport().set_input_as_handled()


## LB and RB step through the tools, LT and RT through the grades.
func pad_action(name: String) -> bool:
	match name:
		"lb", "rb":
			_pad_tool = posmod(_pad_tool + (1 if name == "rb" else -1), TOOLS.size())
			use_tool(TOOLS[_pad_tool])
		"lt":
			step_grade(-1)
		"rt":
			step_grade(1)
		_:
			return false
	return true


func pad_help() -> Array:
	return [[tr("LB / RB"), tr("Previous / next tool")], [tr("LT / RT"), tr("Lower / higher grade")]]


# ---------------------------------------------------------------- actions

func use_tool(tool: String) -> void:
	used[tool] = true
	Sfx.play(self, Sfx.click(), -10.0)
	match tool:
		"lamp":
			_active = "lamp"
			guide_open = false
			if _loupe.visible:
				_set_loupe(false)
		"loupe":
			guide_open = false
			_set_loupe(not _loupe.visible)
			_active = "loupe" if _loupe.visible else "lamp"
		"guide":
			guide_open = not guide_open
			if _loupe.visible:
				_set_loupe(false)
			_active = "lamp"
	_refresh_tools()


func _set_loupe(on: bool) -> void:
	_loupe.visible = on
	_loupe_rim.visible = on
	Pad.hide_cursor(on)


## Puts the lamp at `at` on the bench and relights the coin.
func move_lamp(at: Vector2) -> void:
	lamp = at
	_light()


## The light's direction toward the lamp, with its height from how far out it stands.
func light_dir() -> Vector3:
	var off := lamp - COIN_AT
	var t := clampf((off.length() - LAMP_REACH.x) / (LAMP_REACH.y - LAMP_REACH.x), 0.0, 1.0)
	var el := lerpf(LAMP_HIGH, LAMP_LOW, t)
	var dir := off.normalized() if off.length() > 0.5 else Vector2(-0.7, -0.7)
	return Vector3(dir.x * cos(el), dir.y * cos(el), sin(el))


func _light() -> void:
	var l := light_dir()
	for r in [_coin, _loupe]:
		if r.material:
			(r.material as ShaderMaterial).set_shader_parameter("light", l)


## Tags the bag mark under bench point `at`, if there is one. Returns whether it found one.
func tag_at(at: Vector2) -> bool:
	var p := at - COIN_AT
	for i in coin.marks.size():
		if tagged.has(i):
			continue
		var m: Array = coin.marks[i]
		if Geometry2D.get_closest_point_to_segment(p, m[0], m[1]).distance_to(p) <= TAG_REACH:
			tagged[i] = true
			Sfx.play(self, Sfx.click(), -6.0)
			return true
	_miss_at = _time
	return false


## Moves the pick a grade down or up; the first press starts in the middle of the scale.
func step_grade(step: int) -> void:
	set_grade(5 if pick < 0 else pick + step)


func set_grade(i: int) -> void:
	pick = clampi(i, 0, CoinGrade.GRADES.size() - 1)
	Sfx.play(self, Sfx.click(), -12.0)
	_refresh_grades()


func toggle_cleaned() -> void:
	cleaned = not cleaned
	Sfx.play(self, Sfx.click(), -10.0)
	_refresh_grades()


func finish() -> void:
	if pick < 0:
		return
	customer.assessed = {"grade": pick, "cleaned": cleaned}
	finished.emit("graded")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_bench, Vector2.ZERO)
	_draw_shadow()
	_draw_lamp()
	for i in tagged:
		var m: Array = coin.marks[i]
		var c: Vector2 = COIN_AT + (m[0] + m[1]) / 2.0
		draw_arc(c.floor() + Vector2(0.5, 0.5), 3.5, 0.0, TAU, 12, Color("#79d184"), 1.0)
	if _time - _miss_at < 0.5:
		var at := _loupe_centre()
		_text(tr("NO MARK"), at + Vector2(-PixelFont.measure(tr("NO MARK")) / 2.0, LOUPE_SIZE / 2.0 + 6), Pal.INK_DIM)
	if guide_open:
		_draw_guide()


## The coin's shadow on the velvet, thrown away from the lamp.
func _draw_shadow() -> void:
	var l := light_dir()
	var off := -Vector2(l.x, l.y) / maxf(l.z, 0.2) * 2.0
	off = off.limit_length(7.0)
	var r := GradeArt.RADIUS
	for k in 3:
		draw_circle(COIN_AT + off * (1.0 - k * 0.3), r + 1.0 - k, Color(0, 0, 0, 0.18))


## The lamp head, with its bulb glowing, wherever it stands round the coin.
func _draw_lamp() -> void:
	var p := lamp.floor()
	var toward := (COIN_AT - lamp).normalized()
	var high := 1.0 - clampf((lamp.distance_to(COIN_AT) - LAMP_REACH.x) / (LAMP_REACH.y - LAMP_REACH.x), 0.0, 1.0)
	# the arm reaches in from the bench's back edge
	draw_line(Vector2(p.x * 0.3 + 4, 0), p, Color("#2a2c30"), 2.0)
	draw_line(Vector2(p.x * 0.3 + 5, 0), p + Vector2(1, 0), Color("#5a5e66"), 1.0)
	var shade := PackedVector2Array([p + toward.rotated(PI / 2) * 6.0, p + toward.rotated(-PI / 2) * 6.0,
		p + toward * 6.0 + toward.rotated(-PI / 2) * 9.0, p + toward * 6.0 + toward.rotated(PI / 2) * 9.0])
	draw_colored_polygon(shade, Color("#3a5a48"))
	draw_polyline(shade, Color("#5a8a6a"), 1.0, true)
	draw_circle(p + toward * 6.0, 3.0, Color("#fff4c8"))
	# a cone of light falling on the bench, softer when it's high
	draw_circle(p + toward * 14.0, 6.0 + high * 4.0, Color(1.0, 0.95, 0.75, 0.08))


## The grading guide card over the bench.
func _draw_guide() -> void:
	var r := Rect2(10, 12, BENCH_W - 20, 246)
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.45))
	draw_rect(r, Color("#efe6cf"))
	draw_rect(r.grow(-2), Color("#e6dcc2"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color("#fffaf0"))
	_text(tr("GRADING GUIDE"), r.position + Vector2(8, 6), Color("#5a3a1a"))
	_text(tr("click or Esc to close"), r.position + Vector2(r.size.x - 4 - PixelFont.measure(tr("click or Esc to close")), 6), Color("#8a7a5a"))
	var y := r.position.y + 18
	for g in CoinGrade.GRADES:
		_text(g.id, Vector2(r.position.x + 8, y), Color("#7a1e12"))
		var lines := _wrap(tr(g.guide), 46)
		for k in lines.size():
			_text(lines[k], Vector2(r.position.x + 44, y + k * 8), Color("#3a2a1a"))
		y += 8 * lines.size() + 4
	var cleaned_lines := _wrap(tr("CLEANED: fine hairlines all one way, seen under the loupe with the lamp low. Dull, no cartwheel."), 54)
	for k in cleaned_lines.size():
		_text(cleaned_lines[k], Vector2(r.position.x + 8, y + 2 + k * 8), Color("#7a1e12"))


## Breaks `text` into lines of about `width` letters. Chinese has no spaces: it breaks
## between characters (never before its punctuation), each about 1.6 letters wide.
static func _wrap(text: String, width: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in _wrap_words(text):
		if line != "" and _wrap_width(line + word) > width:
			out.append(line)
			line = word.strip_edges()
		else:
			line = (line + word).strip_edges()
	if line != "":
		out.append(line)
	return out


## The words of `text`, each Chinese character a word of its own; a word that followed a
## space keeps it in front.
static func _wrap_words(text: String) -> Array[String]:
	var words: Array[String] = []
	for chunk in text.split(" ", false):
		var latin := " " if not words.is_empty() else ""
		for ch in chunk:
			if _is_cjk(ch):
				if latin.strip_edges() != "":
					words.append(latin)
				latin = ""
				if "，。、：；！？）".contains(ch) and not words.is_empty():
					words[-1] += ch
				else:
					words.append(ch)
			else:
				latin += ch
		if latin.strip_edges() != "":
			words.append(latin)
	return words


static func _is_cjk(s: String) -> bool:
	return s != "" and s.unicode_at(0) >= 0x2E80


static func _wrap_width(s: String) -> float:
	var w := 0.0
	for ch in s:
		w += 1.6 if _is_cjk(ch) else 1.0
	return w


func _text(text: String, at: Vector2, col: Color) -> void:
	PixelFont.plot_text(text, func(x, y): draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


# ---------------------------------------------------------------- behaviour

func _finish_detail() -> void:
	if _detail_task < 0 or not WorkerThreadPool.is_task_completed(_detail_task):
		return
	WorkerThreadPool.wait_for_task_completion(_detail_task)
	_detail_task = -1
	var mat := _loupe.material as ShaderMaterial
	mat.set_shader_parameter("relief", ImageTexture.create_from_image(_detail.relief))
	mat.set_shader_parameter("surface", ImageTexture.create_from_image(_detail.surface))


func _loupe_centre() -> Vector2:
	return _loupe.position + Vector2(LOUPE_SIZE, LOUPE_SIZE) / 2.0


func _update_loupe() -> void:
	if not _loupe.visible:
		return
	var m := Pad.mouse_in(self)
	m.x = clampf(m.x, LOUPE_SIZE / 2.0, BENCH_W - LOUPE_SIZE / 2.0)
	m.y = clampf(m.y, LOUPE_SIZE / 2.0, size.y - LOUPE_SIZE / 2.0)
	_loupe.position = (m - Vector2(LOUPE_SIZE, LOUPE_SIZE) / 2.0).round()
	_loupe_rim.position = _loupe.position - Vector2(3, 3)
	var uv := (m - _coin.position) / _coin.size
	var mat := _loupe.material as ShaderMaterial
	mat.set_shader_parameter("center_uv", uv)
	# at LOUPE_SCALE the loupe shows LOUPE_SIZE / LOUPE_SCALE bench pixels across
	mat.set_shader_parameter("span", Vector2.ONE * (LOUPE_SIZE / float(GradeArt.LOUPE_SCALE)) / _coin.size)


func _update_cells() -> void:
	if _cells.is_empty():
		return
	var l := light_dir()
	var el := rad_to_deg(asin(l.z))
	var from := ""
	if el < 70.0:
		var a := rad_to_deg(atan2(l.y, l.x))
		from = ", " + tr(["from the right", "from lower right", "from the bottom", "from lower left", "from the left", "from upper left", "from the top", "from upper right"][posmod(roundi(a / 45.0), 8)])
	_cells.light.text = (tr("high") if el > 55.0 else (tr("raking") if el < 25.0 else tr("low"))) + from
	_cells.marks.text = tr("%d tagged") % tagged.size()


# ---------------------------------------------------------------- the panel

func _build_panel() -> void:
	var x := BENCH_W + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(BENCH_W, 0)
	panel.size = Vector2(480 - BENCH_W, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(panel, 0)
	_label("COIN GRADING", Vector2(x, 4), Pal.INK_FAINT)
	_label(coin.item.display_name, Vector2(x, 13), Pal.GOLD, 156)
	_label(tr("The owner hopes for %s") % CoinGrade.grade_id(coin.hoped), Vector2(x, 23), Pal.INK_DIM, 156)
	_label(tr("Fee %s, more if you're spot on") % Market.format_money(CoinGrade.fee()), Vector2(x, 32), Pal.INK_DIM, 156)
	for n in TOOLS.size():
		var tool: String = TOOLS[n]
		var b := Button.new()
		add_child(b)
		b.text = "%d %s" % [n + 1, tr(TOOL_NAMES[tool])]
		b.theme_type_variation = "ToolButton"
		b.position = Vector2(x + n * 52, 44)
		b.size = Vector2(50, 12)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(use_tool.bind(tool))
		_tool_buttons[tool] = b
	_label("Lamp", Vector2(x, 60), Pal.INK_DIM)
	_cells.light = _label("", Vector2(x + 30, 60), Pal.INK, 126, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Bag marks", Vector2(x, 69), Pal.INK_DIM)
	_cells.marks = _label("", Vector2(x + 60, 69), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("GRADE", Vector2(x, 82), Pal.INK_FAINT)
	for i in CoinGrade.GRADES.size():
		var b := Button.new()
		add_child(b)
		b.text = CoinGrade.GRADES[i].id
		b.theme_type_variation = "Button"
		b.position = Vector2(x + (i % 2) * 80, 92 + (i / 2) * 13)
		b.size = Vector2(76, 11)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(set_grade.bind(i))
		_grade_buttons.append(b)
	_guide_text = _label("", Vector2(x, 160), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 34)
	_clean_button = Button.new()
	add_child(_clean_button)
	_clean_button.position = Vector2(x, 198)
	_clean_button.size = Vector2(156, 12)
	_clean_button.focus_mode = Control.FOCUS_NONE
	_clean_button.theme_type_variation = "ToolButton"
	_clean_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_clean_button.pressed.connect(toggle_cleaned)
	_clean_button.tooltip_text = "C: the coin has been cleaned (hairlines, no real lustre)"
	_done_button = Button.new()
	add_child(_done_button)
	_done_button.text = "Grade it"
	_done_button.theme_type_variation = "PrimaryButton"
	_done_button.position = Vector2(x, 238)
	_done_button.size = Vector2(156, 13)
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.pressed.connect(finish)
	_label("Esc: back to the counter", Vector2(x, 256), Pal.INK_FAINT)
	move_child(_loupe, -1)
	move_child(_loupe_rim, -1)
	_refresh_tools()
	_refresh_grades()


func _refresh_tools() -> void:
	for tool in _tool_buttons:
		var on: bool = (tool == "loupe" and _loupe.visible) or (tool == "guide" and guide_open) or (tool == "lamp" and _active == "lamp" and not guide_open)
		_tool_buttons[tool].add_theme_color_override("font_color", Pal.GOLD if on else Pal.INK)


func _refresh_grades() -> void:
	for i in _grade_buttons.size():
		_grade_buttons[i].set_pressed_no_signal(i == pick)
	_guide_text.text = tr(CoinGrade.GRADES[pick].guide) if pick >= 0 else "Pick a grade: Left/Right or click. 3 opens the guide."
	_clean_button.text = "[%s] " % ("x" if cleaned else " ") + tr("Cleaned (C)")
	_done_button.disabled = pick < 0
	if pick < 0:
		_done_button.text = tr("Grade it")
	elif cleaned:
		_done_button.text = tr("Grade it %s cleaned") % CoinGrade.grade_id(pick)
	else:
		_done_button.text = tr("Grade it %s") % CoinGrade.grade_id(pick)


func _label(text: String, pos: Vector2, col: Color, width := 0, align := HORIZONTAL_ALIGNMENT_LEFT, wrap_height := 0) -> Label:
	var l := Label.new()
	add_child(l)
	if wrap_height > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	l.position = pos
	if width > 0:
		l.size = Vector2(width, maxi(wrap_height, 8))
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- baked art

## The bench: oak, a square of black velvet under the coin, a printed scale card, a
## pair of cotton gloves and a 2x2 coin holder waiting for the slab.
func _paint_bench() -> PixelCanvas:
	var c := BenchArt.wood(BENCH_W, 270)
	var pad := Rect2i(int(COIN_AT.x) - 84, int(COIN_AT.y) - 84, 168, 168)
	c.rect(pad.position.x + 3, pad.position.y + 4, pad.size.x, pad.size.y, Color(0, 0, 0, 0.35))
	BenchArt.felt(c, pad, Color("#15151c"))
	c.rect(pad.position.x, pad.position.y, pad.size.x, 1, Color("#2a2a36"))
	c.rect(pad.position.x, pad.end.y - 1, pad.size.x, 1, Color("#0a0a0e"))
	# a printed scale card, propped at the side
	var card := Rect2i(256, 160, 52, 70)
	c.rect(card.position.x + 2, card.position.y + 3, card.size.x, card.size.y, Color(0, 0, 0, 0.35))
	c.rect(card.position.x, card.position.y, card.size.x, card.size.y, Color("#efe6cf"))
	c.text("SHELDON", card.position.x + 6, card.position.y + 4, Color("#7a1e12"))
	for k in 6:
		c.rect(card.position.x + 6, card.position.y + 14 + k * 9, 40, 1, Color("#b8ab8a"))
		c.text(["1", "12", "40", "58", "65", "70"][k], card.position.x + 6, card.position.y + 16 + k * 9, Color("#5a4a30"))
	# cotton gloves
	for g in [Vector2i(14, 196), Vector2i(26, 210)]:
		c.ellipse(g.x + 10, g.y + 10, 10, 7, Color("#e8e4da"))
		for f in 4:
			c.rect(g.x + 2 + f * 4, g.y, 3, 7, Color("#e8e4da"))
		c.ellipse(g.x + 10, g.y + 12, 7, 3, Color("#d4cfc2"))
	# an empty 2x2 holder
	var h := Rect2i(256, 22, 48, 48)
	c.rect(h.position.x, h.position.y, h.size.x, h.size.y, Color("#e0d8c4"))
	c.disc(h.get_center().x, h.get_center().y, 15.0, Color("#c8c0aa"))
	c.disc(h.get_center().x, h.get_center().y, 14.0, Color("#d8e0e8", 0.6))
	c.text("2X2", h.position.x + 3, h.end.y - 8, Color("#8a7a5a"))
	BenchArt.lamp_light(c)
	return c


func _paint_loupe_rim() -> PixelCanvas:
	var size := LOUPE_SIZE + 6
	var c := PixelCanvas.new(size, size)
	var ctr := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - ctr, y + 0.5 - ctr)
			var r := d.length()
			if r > ctr or r < ctr - 3.0:
				continue
			var lit := d.x + d.y < 0.0
			var col := Color("#c8ccd4") if lit else Color("#6a707a")
			if r > ctr - 0.8:
				col = Color("#2a2c30")
			c.px(x, y, col)
	return c
