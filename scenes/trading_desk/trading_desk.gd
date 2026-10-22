class_name TradingDesk
extends Control
## Trading desk minigame, played in the morning once the trading desk room is built.
## A minute-long trading day runs on the big screen for the metals and the live crypto
## and stocks (DeskSession). Buy, sell short and close positions within the desk's limit;
## Hedge vault shorts the metals in your vault so a falling price doesn't hurt.
## At the closing bell every position closes and the result goes on today's ledger.
## Run this scene on its own (F6 in the editor) to play a session with the starting stock.

signal finished(pnl: float)

const PANEL_X := 316
const CHART := Rect2(16, 26, 284, 72)
const CLOCK_BAR := Rect2(16, 101, 284, 3)
const BOARD_Y := 109
const ROW_H := 9
## Board columns: [x, width, alignment]. Key, symbol, price, today, 24h, position, P&L.
const COLS := [[16, 8, 0], [24, 30, 0], [54, 50, 2], [106, 38, 2], [146, 40, 2], [188, 56, 2], [246, 54, 2]]
const HEADS := ["", "", "PRICE", "TODAY", "REAL 24H", "POSITION", "P&L"]
const LED_DIM := Color("#4f8a45")

var session: DeskSession
var selected := 0
var size_pick := 1
var closed := false
var rng := RandomNumberGenerator.new()

var _art: Texture2D
var _time := 0.0
var _last_tick := -1
var _marks: Array[Dictionary] = [] # {"i", "step", "side"}
var _ui := {}
var _cells: Array = [] # per row, one Label per column
var _result: PanelContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_hooks")
	add_to_group("pad_targets")
	if get_tree().current_scene == self:
		start.call_deferred()
		finished.connect(func(_p): get_tree().reload_current_scene())


## Opens today's board. A fixed `seed` replays a session.
func start(seed := 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	session = DeskSession.from_market(rng)
	_art = DeskArt.paint().texture()
	_build_screen()
	_build_panel()
	Sfx.play(self, Sfx.click(), -8.0)


func _process(delta: float) -> void:
	if session == null:
		return
	_time += delta
	if not closed and session.advance(delta):
		close_out()
	if session.started and not closed:
		var left := ceili(DeskSession.SECONDS - session.elapsed)
		if left <= 5 and left != _last_tick and left > 0:
			_last_tick = left
			Sfx.play(self, Sfx.tick(), -6.0)
	_refresh()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if session == null or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var row := floori((event.position.y - BOARD_Y - ROW_H) / ROW_H)
	if event.position.x < DeskArt.SCREEN.end.x and event.position.y >= BOARD_Y + ROW_H and row >= 0 and row < session.board.size():
		select(row)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if session == null or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < session.board.size():
		select(k - KEY_1)
	else:
		match k:
			KEY_B, KEY_UP:
				buy()
			KEY_S, KEY_DOWN:
				sell()
			KEY_C, KEY_F:
				flatten()
			KEY_H:
				hedge()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_on_main_button()
			KEY_ESCAPE:
				if closed:
					finished.emit(session.pnl())
				elif session.started:
					close_out()
				else:
					leave()
			_:
				return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- actions

## Gamepad: LB and RB pick the row, RT buys and LT sells.
func pad_action(name: String) -> bool:
	if session == null:
		return false
	match name:
		"lb":
			select(posmod(selected - 1, session.board.size()))
		"rb":
			select(posmod(selected + 1, session.board.size()))
		"rt":
			buy()
		"lt":
			sell()
		_:
			return false
	return true


func pad_help() -> Array:
	return [["LB / RB", "Previous / next row"], ["RT", "Buy"], ["LT", "Sell"]]


## The board's rows are drawn, not buttons, so the d-pad is told where they are.
func pad_targets() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if session == null or closed:
		return out
	var xf := get_global_transform_with_canvas()
	for i in session.board.size():
		out.append(xf * Rect2(14, BOARD_Y + ROW_H * (i + 1), 288, ROW_H))
	return out


func select(i: int) -> void:
	selected = clampi(i, 0, session.board.size() - 1)
	Sfx.play(self, Sfx.click(), -14.0)


func trade_size() -> float:
	return session.limit * DeskSession.SIZES[size_pick]


func buy() -> void:
	_trade(trade_size())


func sell() -> void:
	_trade(-trade_size())


func _trade(usd: float) -> void:
	if closed:
		return
	var done := session.trade(selected, usd)
	if absf(done) < 0.01:
		_flash("At the desk's limit. Close something first.")
		return
	_marks.append({"i": selected, "step": session.step(), "side": signf(done)})
	Sfx.play(self, Sfx.register_chime() if done > 0.0 else Sfx.click(), -12.0)


func flatten() -> void:
	if closed or absf(session.position(selected)) < 0.01:
		return
	_marks.append({"i": selected, "step": session.step(), "side": -signf(session.position(selected))})
	session.flatten(selected)
	Sfx.play(self, Sfx.click(), -10.0)


func hedge() -> void:
	if closed:
		return
	if session.vault_oz.is_empty():
		_flash("No metal in the vault to hedge.")
		return
	session.hedge_vault()
	Sfx.play(self, Sfx.safe_clunk(), -14.0)
	_flash("Shorted the vault's metal with up to half the desk's limit.")


## Rings the opening bell, or closes out early once the day is running.
func _on_main_button() -> void:
	if closed:
		finished.emit(session.pnl())
	elif session.started:
		close_out()
	else:
		ring_bell()


func ring_bell() -> void:
	if session.started:
		return
	session.started = true
	Sfx.play(self, Sfx.door_bell(), -4.0)


## The closing bell: everything closes at the last price and the result is booked.
func close_out() -> void:
	if closed:
		return
	closed = true
	session.flatten_all()
	DeskSession.book(session.pnl())
	Sfx.play(self, Sfx.door_bell(), -4.0)
	if is_inside_tree():
		get_tree().create_timer(0.6).timeout.connect(_show_result)


## Walks away before the bell. Positions taken pre-market close at the open, for their fees.
func leave() -> void:
	if session.started or closed:
		return
	if session.traded():
		session.flatten_all()
		DeskSession.book(session.pnl())
	finished.emit(session.pnl())


func _flash(text: String) -> void:
	_ui.flash.text = text
	_ui.flash_until = _time + 2.5


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if session == null:
		return
	draw_texture(_art, Vector2.ZERO)
	_draw_chart()
	_draw_clock_bar()
	var row := Rect2(14, BOARD_Y + ROW_H * (selected + 1) - 1, 288, ROW_H)
	draw_rect(row, Color("#1d3a28"))
	draw_rect(Rect2(row.position, Vector2(1, row.size.y)), Pal.LED)
	_draw_scanlines()
	_draw_steam()


func _draw_chart() -> void:
	var path: PackedFloat64Array = session.board[selected].path
	var now := session.step()
	var open := path[0]
	# the scale only knows the tape so far, so it never gives away the close
	var lo := open
	var hi := open
	for k in now + 1:
		lo = minf(lo, path[k])
		hi = maxf(hi, path[k])
	var span := maxf(hi - lo, open * 0.004)
	lo -= span * 0.15
	hi += span * 0.15
	var y_of := func(p: float) -> float: return roundf(CHART.end.y - 1.0 - (p - lo) / (hi - lo) * (CHART.size.y - 2.0))
	var x_of := func(k: int) -> float: return roundf(CHART.position.x + float(k) / DeskSession.STEPS * (CHART.size.x - 1.0))
	# hour lines and price lines
	for h in range(1, 8):
		var x: float = CHART.position.x + roundf(CHART.size.x * h / 8.0)
		for y in range(int(CHART.position.y), int(CHART.end.y), 3):
			draw_rect(Rect2(x, y, 1, 1), DeskArt.GRID)
	for n in range(1, 4):
		var y: float = CHART.position.y + roundf(CHART.size.y * n / 4.0)
		for x in range(int(CHART.position.x), int(CHART.end.x), 3):
			draw_rect(Rect2(x, y, 1, 1), DeskArt.GRID)
	var oy: float = y_of.call(open)
	for x in range(int(CHART.position.x), int(CHART.end.x), 4):
		draw_rect(Rect2(x, oy, 2, 1), Pal.INK_FAINT)
	var up := path[now] >= open
	var line := Pal.LED if up else Pal.BAD
	# the area between the tape and the open, then the tape itself
	var prev := Vector2(x_of.call(0), y_of.call(path[0]))
	for k in range(1, now + 1):
		var p := Vector2(x_of.call(k), y_of.call(path[k]))
		if p.x != prev.x:
			var top := minf(p.y, oy)
			draw_rect(Rect2(prev.x, top, p.x - prev.x, absf(p.y - oy)), Color(line, 0.12))
		draw_line(prev, p, line, 1.0)
		prev = p
	if not closed and int(_time * 3.0) % 2 == 0:
		draw_rect(Rect2(prev - Vector2(1, 1), Vector2(3, 3)), Pal.INK)
	for m in _marks:
		if m.i != selected:
			continue
		var at := Vector2(x_of.call(m.step), y_of.call(path[m.step]))
		var col := Pal.GOOD if m.side > 0.0 else Pal.BAD
		var d := 3.0 if m.side > 0.0 else -3.0
		draw_colored_polygon(PackedVector2Array([at + Vector2(-2, d + signf(d) * 2), at + Vector2(2, d + signf(d) * 2), at + Vector2(0, d - signf(d))]), col)


func _draw_clock_bar() -> void:
	draw_rect(CLOCK_BAR, Color("#0e1c14"))
	var share := session.elapsed / DeskSession.SECONDS
	var col := Pal.LED
	if session.started and not closed and share > 0.85:
		col = Pal.BAD if int(_time * 4.0) % 2 == 0 else Pal.WARN
	draw_rect(Rect2(CLOCK_BAR.position, Vector2(roundf(CLOCK_BAR.size.x * share), CLOCK_BAR.size.y)), col)


func _draw_scanlines() -> void:
	var g := DeskArt.SCREEN
	for y in range(g.position.y, g.end.y, 2):
		draw_rect(Rect2(g.position.x, y, g.size.x, 1), Color(0, 0, 0, 0.16))
	# a slow bright band rolling down the glass
	var band := fposmod(_time * 30.0, g.size.y + 40.0) - 20.0
	draw_rect(Rect2(g.position.x, g.position.y + maxf(band, 0.0), g.size.x, clampf(minf(6.0, band + 6.0), 0.0, g.end.y - g.position.y - maxf(band, 0.0))), Color(1, 1, 1, 0.025))


func _draw_steam() -> void:
	var m := DeskArt.MUG
	for n in 7:
		var t := fposmod(_time * 0.6 + n / 7.0, 1.0)
		var at := Vector2(m.get_center().x + sin(t * 6.0 + n) * 3.0, m.position.y + 1 - t * 22.0).floor()
		draw_rect(Rect2(at, Vector2.ONE), Color(1, 1, 1, 0.3 * (1.0 - t)))


# ---------------------------------------------------------------- screen and panel

func _build_screen() -> void:
	_ui.head = _label("", Vector2(16, 13), Pal.LED, 160)
	_ui.head_price = _label("", Vector2(176, 13), Pal.LED, 124, HORIZONTAL_ALIGNMENT_RIGHT)
	for c in COLS.size():
		_label(HEADS[c], Vector2(COLS[c][0], BOARD_Y), LED_DIM, COLS[c][1], COLS[c][2])
	for i in session.board.size():
		var row := []
		for c in COLS.size():
			row.append(_label("", Vector2(COLS[c][0], BOARD_Y + ROW_H * (i + 1)), Pal.LED, COLS[c][1], COLS[c][2]))
		row[0].text = str(i + 1)
		row[0].add_theme_color_override("font_color", LED_DIM)
		row[1].text = session.board[i].sym
		_cells.append(row)


func _build_panel() -> void:
	var x := PANEL_X + 4
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(480 - PANEL_X, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label("TRADING DESK", Vector2(x, 4), Pal.INK_FAINT)
	_label("Morning session", Vector2(x, 13), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18).add_theme_font_size_override("font_size", 16)
	_ui.clock = _pair("Market", x, 34)
	_ui.used = _pair("Desk limit used", x, 43)
	_ui.pnl = _pair("Desk profit", x, 55)
	_ui.vault = _pair("Vault on paper", x, 64)
	_ui.net = _pair("Together", x, 73)
	_ui.pick = _label("", Vector2(x, 86), Pal.GOLD, 156)
	_ui.position = _pair("Position", x, 95)
	_ui.row_pnl = _pair("Its profit", x, 104)
	_ui.sizes = []
	for n in DeskSession.SIZES.size():
		var b := _button("", Rect2(x + n * 53, 116, 50, 12), "Button", func():
			size_pick = n
			Sfx.play(self, Sfx.click(), -14.0))
		b.tooltip_text = "Trade %d%% of the desk's limit per click." % roundi(DeskSession.SIZES[n] * 100.0)
		_ui.sizes.append(b)
	_ui.buy = _button("Buy (B)", Rect2(x, 131, 76, 13), "PrimaryButton", buy)
	_ui.sell = _button("Sell (S)", Rect2(x + 80, 131, 76, 13), "DangerButton", sell)
	_ui.flat = _button("Close (C)", Rect2(x, 147, 76, 13), "Button", flatten)
	_ui.hedge = _button("Hedge vault (H)", Rect2(x + 80, 147, 76, 13), "Button", hedge)
	_ui.hedge.tooltip_text = "Short the gold, silver and platinum in your vault, ounce for ounce, with up to half the desk's limit."
	_ui.flash = _label("", Vector2(x, 164), Pal.WARN, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_ui.flash_until = 0.0
	_ui.help = _label("", Vector2(x, 184), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 46)
	_ui.main = _button("", Rect2(x, 236, 156, 13), "PrimaryButton", _on_main_button)
	_ui.hint = _label("", Vector2(x, 254), Pal.INK_FAINT, 156)


func _refresh() -> void:
	if _ui.is_empty():
		return
	var s := session
	var row: Dictionary = s.board[selected]
	var move := s.move_percent(selected)
	_ui.head.text = "%s  %s" % [row.sym, row.name.to_upper()]
	_ui.head_price.text = "%s  %s" % [_price(s.price(selected)), _pct(move)]
	_ui.head_price.add_theme_color_override("font_color", Pal.LED if move >= 0.0 else Pal.BAD)
	for i in s.board.size():
		var cells: Array = _cells[i]
		var m := s.move_percent(i)
		var pos := s.position(i)
		var pnl := s.pnl_of(i)
		cells[2].text = _price(s.price(i))
		cells[3].text = _pct(m)
		cells[3].add_theme_color_override("font_color", Pal.LED if m >= 0.0 else Pal.BAD)
		var real: float = s.board[i].change
		cells[4].text = ("▲ " if real > 0.05 else ("▼ " if real < -0.05 else "")) + _pct(real)
		cells[4].add_theme_color_override("font_color", LED_DIM if real >= 0.0 else Pal.BAD.darkened(0.3))
		cells[5].text = "" if absf(pos) < 1.0 else ("long " if pos > 0.0 else "short ") + _money_k(absf(pos))
		cells[5].add_theme_color_override("font_color", Pal.LED if pos > 0.0 else Pal.WARN)
		cells[6].text = "" if absf(pnl) < 0.5 and absf(pos) < 1.0 else _signed(pnl)
		cells[6].add_theme_color_override("font_color", Pal.LED if pnl >= 0.0 else Pal.BAD)
	# the panel
	if closed:
		_ui.clock.text = "Closed"
	elif s.started:
		var minutes := 9 * 60 + roundi(s.elapsed / DeskSession.SECONDS * 8.0 * 60.0)
		_ui.clock.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	else:
		_ui.clock.text = "Pre-market"
	_ui.used.text = "%s / %s" % [_money_k(s.exposure()), _money_k(s.limit)]
	_ui.used.add_theme_color_override("font_color", Pal.WARN if s.exposure() > s.limit * 0.95 else Pal.INK)
	_set_money(_ui.pnl, s.pnl())
	_set_money(_ui.vault, s.vault_swing())
	_set_money(_ui.net, s.pnl() + s.vault_swing())
	_ui.pick.text = "%s · %s" % [row.name.to_upper(), row.sym]
	var pos := s.position(selected)
	_ui.position.text = "flat" if absf(pos) < 1.0 else "%s %s" % ["long" if pos > 0.0 else "short", Market.format_money(absf(pos))]
	_set_money(_ui.row_pnl, s.pnl_of(selected))
	for n in _ui.sizes.size():
		var b: Button = _ui.sizes[n]
		b.text = _money_k(s.limit * DeskSession.SIZES[n])
		b.theme_type_variation = "PrimaryButton" if n == size_pick else "Button"
	for b in [_ui.buy, _ui.sell, _ui.flat, _ui.hedge]:
		b.disabled = closed
	if _time > _ui.flash_until:
		_ui.flash.text = ""
	if closed:
		_ui.help.text = ""
		_ui.main.text = "Back to the morning"
		_ui.hint.text = ""
	elif s.started:
		_ui.help.text = "Buy if you think it rises, Sell to go short if you think it falls. At 17:00 everything closes and the result goes on today's ledger."
		_ui.main.text = "Close out now (Enter)"
		_ui.hint.text = "1-%d pick a row. Esc closes out." % s.board.size()
	else:
		_ui.help.text = "Each tape replays a day that ends near today's live price, so the real 24h move is your edge. Hedge vault protects your stock if metals fall."
		_ui.main.text = "Ring the opening bell"
		_ui.hint.text = "Esc leaves without trading."
	if Market.source == "simulated" and not closed:
		_ui.hint.text = "Offline: the tapes are simulated."


func _show_result() -> void:
	var s := session
	var pnl := s.pnl()
	var lines: Array[String] = []
	if not s.traded():
		lines.append("You watched the tape all day without a trade.")
	else:
		lines.append("Desk %s %s today, after %s in fees." % ["made" if pnl >= 0.0 else "lost", Market.format_money(absf(pnl)), Market.format_money(s.fees())])
	var swing := s.vault_swing()
	if absf(swing) >= 1.0:
		lines.append("On today's tape your vault %s %s on paper." % ["gained" if swing > 0.0 else "lost", Market.format_money(absf(swing))])
		var cover := s.hedge_cover()
		if cover > 0.0:
			lines.append("Your hedge offset %d%% of the vault's move." % roundi(cover * 100.0))
	lines.append("Lifetime at the desk: %s." % _signed(DeskSession.lifetime))
	_result = PanelContainer.new()
	add_child(_result)
	_result.position = Vector2(38, 60)
	_result.custom_minimum_size = Vector2(240, 0)
	_result.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD if pnl >= 0.0 else Pal.BAD, 8, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_result.add_child(box)
	var head := Label.new()
	head.text = "Closing bell: %s" % _signed(pnl)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Pal.GOOD if pnl >= 0.0 else Pal.BAD)
	box.add_child(head)
	for text in lines:
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(224, 0)
		box.add_child(l)
	var b := Button.new()
	b.text = "Back to the morning"
	b.theme_type_variation = "PrimaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): finished.emit(pnl))
	box.add_child(b)


# ---------------------------------------------------------------- helpers

static func _price(p: float) -> String:
	if p >= 10000.0:
		return Market.format_money(p)
	if p >= 100.0:
		return Market.format_money(p, 1)
	return Market.format_money(p, 2)


static func _pct(v: float) -> String:
	return "%s%.2f%%" % ["+" if v >= 0.0 else "-", absf(v)]


static func _signed(usd: float) -> String:
	return ("+" if usd >= 0.0 else "-") + Market.format_money(absf(usd))


## "$12.5k" for the narrow columns.
static func _money_k(usd: float) -> String:
	var rate := float(Market.fx.get(Market.currency, 1.0)) if Market.fx.has(Market.currency) else 1.0
	var code := Market.currency if Market.fx.has(Market.currency) else "USD"
	var v := usd * rate
	var sym: String = Market.CURRENCY_SYMBOLS[code]
	if v >= 1000000.0:
		return "%s%.2fM" % [sym, v / 1000000.0]
	if v >= 10000.0:
		return "%s%dk" % [sym, roundi(v / 1000.0)]
	if v >= 1000.0:
		return "%s%.1fk" % [sym, v / 1000.0]
	return "%s%d" % [sym, roundi(v)]


func _set_money(l: Label, usd: float) -> void:
	l.text = _signed(usd) if absf(usd) >= 0.5 else Market.format_money(0.0)
	l.add_theme_color_override("font_color", Pal.GOOD if usd > 0.5 else (Pal.BAD if usd < -0.5 else Pal.INK))


## A caption on the left of the panel and its value on the right. Returns the value label.
func _pair(caption: String, x: int, y: int) -> Label:
	_label(caption, Vector2(x, y), Pal.INK_DIM)
	return _label("", Vector2(x + 56, y), Pal.INK, 100, HORIZONTAL_ALIGNMENT_RIGHT)


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
	l.text = text
	l.position = pos
	if width > 0:
		l.size = Vector2(width, maxi(wrap_height, 8))
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
