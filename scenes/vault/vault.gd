extends Control
## Vault lock-up minigame, played at closing time. Tonight's stock and cash spill onto
## the counter tray; drag them into the wall safe and the floor safe before the clock
## runs out. Whatever stays out draws burglars, and the wall safe can be cracked.
## Run this scene on its own (F6 in the editor) to play it with the starting stock.

signal finished(report: Dictionary)

const PANEL_X := 316
const CELL := VaultArt.CELL

var layout: VaultLayout
var limit := 30.0
var elapsed := 0.0
var locked := false
## Stops the clock and the hands, while the tutorial explains the lock-up.
var paused := false
var report := {}
var rng := RandomNumberGenerator.new()

var _room: Texture2D
var _room_shut: Texture2D
var _doors := {}
var _art := {} # "kind:rot" -> Texture2D
var _held := {}
var _held_rot := 0
var _grab := Vector2.ZERO
var _hover := {}
var _time := 0.0
var _last_tick := -1
var _ui := {}
var _result: PanelContainer


func _ready() -> void:
	add_to_group("pad_targets")
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if get_tree().current_scene == self:
		start.call_deferred()
		finished.connect(func(_r): get_tree().reload_current_scene())


## Packs the shop's stock onto the tray and starts the clock. A fixed `seed` replays a night.
func start(seed := 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	layout = VaultLayout.from_shop(rng)
	limit = clampf(14.0 + 2.5 * layout.pieces.size(), 20.0, 60.0)
	_room = VaultArt.paint_room(layout.areas).texture()
	_room_shut = VaultArt.paint_room(layout.areas, false).texture()
	for area in [VaultLayout.WALL, VaultLayout.FLOOR]:
		_doors[area] = VaultArt.paint_door(area, layout.areas[area].size).texture()
	_build_panel()
	Sfx.play(self, Sfx.click(), -8.0)


func _process(delta: float) -> void:
	if layout == null:
		return
	_time += delta
	if not locked and not paused:
		elapsed += delta
		var left := ceili(limit - elapsed)
		if left <= 5 and left != _last_tick and left > 0:
			_last_tick = left
			Sfx.play(self, Sfx.tick(), -6.0)
		if elapsed >= limit:
			lock_up()
	_refresh_panel()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if layout == null or locked or paused:
		return
	var m := Pad.mouse_in(self)
	if event is InputEventMouseMotion:
		_hover = _piece_under(m)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pick_up(m)
		else:
			drop(m)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		turn(m)
	else:
		return
	accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if layout == null or locked or paused or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			turn(Pad.mouse_in(self))
		KEY_ENTER, KEY_KP_ENTER:
			lock_up()
		_:
			return
	get_viewport().set_input_as_handled()


## Where the d-pad stops: on each piece, or cell by cell while carrying one.
func pad_targets() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if layout == null or locked or paused:
		return out
	var xf := get_global_transform_with_canvas()
	if _held.is_empty():
		for p in layout.pieces:
			if p.cell.x >= 0:
				var c: Vector2i = VaultLayout.cells_of(p.kind, p.rot)[0]
				out.append(xf * Rect2(_piece_pos(p) + Vector2(c * CELL), Vector2(CELL, CELL)))
	else:
		for area in layout.areas:
			var o := _origin(area)
			var cells: Vector2i = layout.areas[area].size
			for y in cells.y:
				for x in cells.x:
					out.append(xf * Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)))
	return out


func pick_up(at: Vector2) -> void:
	var p := _piece_under(at)
	if p.is_empty():
		return
	_held = p
	_held_rot = p.rot
	_grab = at - _piece_pos(p)
	Sfx.play(self, Sfx.click(), -10.0)


## Drops the held piece where the mouse is; it goes back where it was if it won't fit.
func drop(at: Vector2) -> void:
	if _held.is_empty():
		return
	var target := _drop_target(at)
	if target.ok:
		layout.place(_held, target.area, target.cell, _held_rot)
		Sfx.play(self, Sfx.safe_clunk() if target.area != VaultLayout.TRAY else Sfx.click(), -14.0)
	_held = {}
	_hover = _piece_under(at)


## Turns the held piece, or the one under the mouse when it has room to turn.
func turn(at: Vector2) -> void:
	if not _held.is_empty():
		_held_rot = (_held_rot + 1) % 4
		var fp := VaultLayout.footprint(_held.kind, _held_rot)
		_grab = Vector2(fp) * CELL / 2.0
		return
	var p := _piece_under(at)
	if p.is_empty():
		return
	if layout.place(p, p.area, p.cell, p.rot + 1):
		Sfx.play(self, Sfx.click(), -10.0)


## Shuts the safes and rolls the night. Stolen goods leave the shop right away.
func lock_up() -> void:
	if locked or layout == null:
		return
	locked = true
	_held = {}
	_hover = {}
	var chance := layout.risk(elapsed / limit)
	report = layout.resolve(chance, rng)
	report.risk = chance
	report.secured = 1.0 - layout.out_share()
	report.left_out = layout.value_in(VaultLayout.TRAY)
	layout.apply(report)
	Sfx.play(self, Sfx.safe_clunk(), -4.0)
	_ui.lock.disabled = true
	if is_inside_tree():
		get_tree().create_timer(0.9).timeout.connect(_show_result)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if layout == null:
		return
	draw_texture(_room_shut if locked else _room, Vector2.ZERO)
	for p in layout.pieces:
		if is_same(p, _held) or p.cell.x < 0:
			continue
		var pos := _piece_pos(p)
		var tex := _tex(p.kind, p.rot)
		draw_texture(tex, pos + Vector2(1, 2), Color(0, 0, 0, 0.35))
		draw_texture(tex, pos)
	if not _hover.is_empty() and _held.is_empty():
		_outline(_hover, _piece_pos(_hover), _hover.rot, Pal.GOLD)
	if locked:
		for area in _doors:
			var o := _origin(area)
			draw_texture(_doors[area], o - Vector2(2, 2))
	if not _held.is_empty():
		var m := Pad.mouse_in(self)
		var target := _drop_target(m)
		if target.area != "":
			var tint := Color(Pal.GOOD, 0.35) if target.ok else Color(Pal.BAD, 0.35)
			var o := _origin(target.area)
			for c in VaultLayout.cells_of(_held.kind, _held_rot):
				var cell: Vector2i = target.cell + c
				if cell.x >= 0 and cell.y >= 0 and cell.x < layout.areas[target.area].size.x and cell.y < layout.areas[target.area].size.y:
					draw_rect(Rect2(o + Vector2(cell * CELL), Vector2(CELL, CELL)), tint)
		var pos := (m - _grab).round()
		var tex := _tex(_held.kind, _held_rot)
		draw_texture(tex, pos + Vector2(3, 5), Color(0, 0, 0, 0.4))
		draw_texture(tex, pos - Vector2(0, 2))
	_draw_clock()


func _draw_clock() -> void:
	var share := clampf(1.0 - elapsed / limit, 0.0, 1.0)
	var bar := Rect2(8, 4, PANEL_X - 16, 6)
	draw_rect(bar, Color("#120e0a"))
	var col := Pal.GOLD
	if share < 0.25:
		col = Pal.BAD if int(_time * 4.0) % 2 == 0 or locked else Pal.WARN
	draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(roundf((bar.size.x - 2) * share), bar.size.y - 2)), col)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1)), Pal.PANEL_EDGE)


## A 1 px line round the outside of a piece's cells.
func _outline(p: Dictionary, pos: Vector2, rot: int, col: Color) -> void:
	var cells := VaultLayout.cells_of(p.kind, rot)
	for c in cells:
		var o := pos + Vector2(c * CELL)
		if not cells.has(c + Vector2i.UP):
			draw_rect(Rect2(o + Vector2(0, -1), Vector2(CELL, 1)), col)
		if not cells.has(c + Vector2i.DOWN):
			draw_rect(Rect2(o + Vector2(0, CELL), Vector2(CELL, 1)), col)
		if not cells.has(c + Vector2i.LEFT):
			draw_rect(Rect2(o + Vector2(-1, 0), Vector2(1, CELL)), col)
		if not cells.has(c + Vector2i.RIGHT):
			draw_rect(Rect2(o + Vector2(CELL, 0), Vector2(1, CELL)), col)


func _tex(kind: String, rot: int) -> Texture2D:
	var key := "%s:%d" % [kind, rot]
	if not _art.has(key):
		_art[key] = VaultArt.rotated(VaultArt.paint_piece(kind), rot).texture()
	return _art[key]


# ---------------------------------------------------------------- behaviour

func _piece_pos(p: Dictionary) -> Vector2:
	return _origin(p.area) + Vector2(p.cell * CELL)


func _origin(area: String) -> Vector2:
	return Vector2(VaultArt.origin(area, layout.areas[area].size))


func _piece_under(at: Vector2) -> Dictionary:
	for area in layout.areas:
		var cell := Vector2i(((at - _origin(area)) / CELL).floor())
		var p := layout.piece_at(area, cell)
		if not p.is_empty() and not is_same(p, _held):
			return p
	return {}


## Where the held piece would land: {"area", "cell", "ok"}. Area is "" off every grid.
func _drop_target(at: Vector2) -> Dictionary:
	var top_left := at - _grab
	var fallback := {"area": "", "cell": Vector2i.ZERO, "ok": false}
	for area in layout.areas:
		var o := _origin(area)
		var cell := Vector2i(((top_left - o) / CELL).round())
		if layout.can_place(_held, area, cell, _held_rot):
			return {"area": area, "cell": cell, "ok": true}
		if Rect2(o, Vector2(layout.areas[area].size * CELL)).has_point(at):
			fallback = {"area": area, "cell": cell, "ok": false}
	return fallback


# ---------------------------------------------------------------- panel

func _build_panel() -> void:
	var x := PANEL_X + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(480 - PANEL_X, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label("VAULT LOCK-UP", Vector2(x, 4), Pal.INK_FAINT)
	_label("Closing time", Vector2(x, 13), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18).add_theme_font_size_override("font_size", 16)
	_label("Lights out in", Vector2(x, 34), Pal.INK_DIM)
	_ui.clock = _label("", Vector2(x + 80, 34), Pal.INK, 76, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Locked away", Vector2(x, 46), Pal.INK_DIM)
	_ui.secured = _label("", Vector2(x + 60, 46), Pal.GOOD, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Left on the tray", Vector2(x, 55), Pal.INK_DIM)
	_ui.out = _label("", Vector2(x + 60, 55), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Break-in risk", Vector2(x, 64), Pal.INK_DIM)
	_ui.risk = _label("", Vector2(x + 60, 64), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("FLOOR SAFE", Vector2(x, 78), Pal.INK_FAINT)
	_label("Burglars can't crack it", Vector2(x, 87), Pal.INK_DIM, 156)
	if layout.risk_scale < 1.0:
		_label("Alarm: -%d%% risk" % roundi((1.0 - layout.risk_scale) * 100.0), Vector2(x + 96, 78), Pal.GOOD, 60, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("WALL SAFE", Vector2(x, 98), Pal.INK_FAINT)
	var crack: float = layout.areas[VaultLayout.WALL].crack
	var text := "Crews crack it %d%% of the time" % roundi(Security.crack_chance("crew", crack) * 100.0)
	if Progress.tier >= 1:
		text = "Crews crack it %d%%, pros %d%%" % [roundi(Security.crack_chance("crew", crack) * 100.0), roundi(Security.crack_chance("pros", crack) * 100.0)]
	_label(text, Vector2(x, 107), Pal.INK_DIM, 156)
	_ui.title = _label("", Vector2(x, 122), Pal.GOLD, 156)
	_ui.lines = []
	for n in 3:
		_ui.lines.append(_label("", Vector2(x, 131 + n * 9), Pal.INK, 156))
	_ui.value = _label("", Vector2(x, 158), Pal.INK_DIM, 156)
	_label("Drag stock into the safes. Right-click or R turns a piece. What's left on the tray is easy pickings, and the longer the lights stay on, the likelier a break-in.",
		Vector2(x, 174), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 56)
	var b := Button.new()
	add_child(b)
	b.text = "Lock up now"
	b.theme_type_variation = "PrimaryButton"
	b.position = Vector2(x, 236)
	b.size = Vector2(156, 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(lock_up)
	_ui.lock = b
	_label("Enter locks up. At zero it locks itself.", Vector2(x, 256), Pal.INK_FAINT, 156)


func _refresh_panel() -> void:
	if _ui.is_empty():
		return
	var left := maxf(limit - elapsed, 0.0)
	_ui.clock.text = "0:%02d" % ceili(left) if left < 60.0 else "1:00"
	_ui.clock.add_theme_color_override("font_color", Pal.BAD if left < limit * 0.25 else Pal.INK)
	var out := layout.value_in(VaultLayout.TRAY)
	_ui.secured.text = Market.format_money(layout.total_value() - out)
	_ui.out.text = Market.format_money(out)
	_ui.out.add_theme_color_override("font_color", Pal.WARN if out > 0.0 else Pal.INK_DIM)
	var risk: float = report.risk if locked else layout.risk(elapsed / limit)
	_ui.risk.text = "%d%%" % roundi(risk * 100.0)
	_ui.risk.add_theme_color_override("font_color", Pal.BAD if risk >= 0.3 else (Pal.WARN if risk >= 0.12 else Pal.GOOD))
	var p: Dictionary = _held if not _held.is_empty() else _hover
	_ui.title.text = p.get("title", "")
	for n in 3:
		var lines: Array = p.get("contents", [])
		_ui.lines[n].text = lines[n] if n < lines.size() else ("and more" if n == 2 and lines.size() > 3 else "")
	_ui.value.text = "Worth %s today" % Market.format_money(p.value) if p.get("value", 0.0) > 0.0 else ""


func _show_result() -> void:
	var stolen_from := {}
	for p in report.stolen:
		stolen_from[p.area] = stolen_from.get(p.area, 0.0) + p.value
	var lines: Array[String] = []
	var title := "Quiet night"
	if not report.break_in:
		if report.left_out > 0.0:
			lines.append("Nobody came. Lucky: %s sat out on the counter all night." % Market.format_money(report.left_out))
		else:
			lines.append("Nobody came, and everything was locked away.")
		Shop.log_event("Quiet night. The vault was untouched.", "good")
	else:
		title = "Break-in!"
		Sfx.play(self, Sfx.alarm(), -6.0)
		var crew: Dictionary = Security.CREWS[report.crew]
		title = "Break-in: %s!" % crew.name.to_lower() if report.crew != "crew" else "Break-in!"
		lines.append(crew.line)
		if stolen_from.has(VaultLayout.TRAY):
			var all_out := layout.value_in(VaultLayout.TRAY)
			if stolen_from.tray < all_out - 0.5:
				lines.append("Grabbed the best of the counter tray: %s. They left the rest." % Market.format_money(stolen_from.tray))
			else:
				lines.append("Took everything on the counter tray: %s." % Market.format_money(stolen_from.tray))
		if float(crew.wall) <= 0.0:
			lines.append("They never touched the safes.")
		elif report.cracked.get(VaultLayout.WALL, false):
			lines.append("Cracked the wall safe: %s." % Market.format_money(stolen_from.get(VaultLayout.WALL, 0.0)))
		else:
			lines.append("They couldn't crack the wall safe.")
		lines.append("The floor safe held.")
		if report.stolen.any(func(p): return p.kind == "ledger"):
			lines.append("The customer ledger is gone. Reputation -%.1f." % VaultLayout.LEDGER_REPUTATION)
		lines.append("Total lost: %s." % Market.format_money(report.value))
		if report.get("recovered", 0.0) >= 1.0:
			lines.append("The cameras caught them. Police got back %s." % Market.format_money(report.recovered))
		Shop.log_event("Break-in overnight! Lost %s." % Market.format_money(report.value), "bad")
	_result = PanelContainer.new()
	add_child(_result)
	_result.position = Vector2(38, 70)
	_result.custom_minimum_size = Vector2(240, 0)
	_result.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.BAD if report.break_in else Pal.GOLD, 8, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_result.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Pal.BAD if report.break_in else Pal.GOOD)
	box.add_child(head)
	for text in lines:
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(224, 0)
		box.add_child(l)
	var odds := Label.new()
	odds.text = "Break-in risk was %d%%, with %d%% of the value locked away." % [roundi(report.risk * 100.0), roundi(report.secured * 100.0)]
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds.custom_minimum_size = Vector2(224, 0)
	odds.add_theme_color_override("font_color", Pal.INK_FAINT)
	box.add_child(odds)
	var b := Button.new()
	b.text = "See the day's results"
	b.theme_type_variation = "PrimaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): finished.emit(report))
	box.add_child(b)


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
