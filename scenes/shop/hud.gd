extends Control
## Shop HUD at 480x270: live ticker on top, the day's numbers and the counter card on
## the right, and the shop log under the room. Laid out by hand to the pixel.

signal action(name: String) # "test", "offer", "refuse", "sell", "decline", "vault_run"
signal open_requested
signal next_day_requested
signal new_game_requested
signal menu_requested
signal desk_requested
signal smelter_requested
signal auction_requested

const SIDE_X := 318
const SIDE_W := 160
const TICKER := ["XAU", "XAG", "XPT", "XPD"]
const TICKER_NAMES := {"XAU": "AU", "XAG": "AG", "XPT": "PT", "XPD": "PD"}

var _ticker_labels := {}
var _feed: Label
var _day: Label
var _clock: Label
var _stars: Label
var _tier: Label
var _cash: Label
var _stock_value: Label
var _net: Label
var _goal: ProgressBar
var _goal_text: Label
var _till: Label
var _till_button: Button
var _avatar: TextureRect
var _who: Label
var _wants: Label
var _quote: Label
var _deal: Array[Label] = []
var _buttons := {}
var _buy_label: Label
var _sell_label: Label
var _stock_lines: Array[Label] = []
var _stock_values: Array[Label] = []
var _log_lines: Array[Label] = []
var _panels: DayPanels
var _decor: DecorPanel
## The shop floor, for decorating (set by shop.gd).
var room: Node2D
var _customer: Customer
## The cash figure rolls towards Shop.cash and flashes green or red as it moves.
var _cash_shown := NAN
var _cash_flash := 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ticker()
	_build_side()
	_build_log()
	_panels = DayPanels.new()
	add_child(_panels)
	_panels.open_requested.connect(func(): open_requested.emit())
	_panels.next_day_requested.connect(func(): next_day_requested.emit())
	_panels.new_game_requested.connect(func(): new_game_requested.emit())
	_panels.desk_requested.connect(func(): desk_requested.emit())
	_panels.smelter_requested.connect(func(): smelter_requested.emit())
	_panels.auction_requested.connect(func(): auction_requested.emit())
	_panels.decorate_requested.connect(open_decor)
	_decor = DecorPanel.new()
	add_child(_decor)
	_decor.closed.connect(func():
		if Day.phase == Day.MORNING:
			_panels.show_upgrades())
	Market.prices_changed.connect(func(_p): _refresh())
	Market.source_changed.connect(func(_s): _refresh())
	Market.currency_changed.connect(func(_c): _refresh())
	Shop.changed.connect(_refresh)
	Progress.changed.connect(_refresh)
	Shop.logged.connect(add_log)
	_refresh()
	show_customer(null, "Quiet for now. Customers arrive every few seconds.")


func _process(delta: float) -> void:
	if is_nan(_cash_shown) or is_equal_approx(_cash_shown, Shop.cash):
		return
	var gap := Shop.cash - _cash_shown
	_cash_flash = signf(gap)
	# most of the way in a third of a second, then snap
	_cash_shown = Shop.cash if absf(gap) < 1.0 else _cash_shown + gap * minf(1.0, delta * 9.0)
	_cash.text = Market.format_money(_cash_shown)
	var settled := _cash_shown == Shop.cash
	_cash.add_theme_color_override("font_color", Pal.INK if settled else (Pal.GOOD if _cash_flash > 0.0 else Pal.BAD))


func set_clock(day: int, minutes: int, closing: bool, rush := false) -> void:
	_day.text = tr("Day %d/%d") % [day, Demo.DAYS] if Demo.enabled else tr("Day %d") % day
	var when := tr("closing") if closing else (tr("RUSH") if rush else Day.weekday(day).substr(0, 3))
	_clock.text = "%s %02d:%02d" % [when, minutes / 60, minutes % 60]
	_clock.add_theme_color_override("font_color", Pal.WARN if rush else Pal.INK)


## The cash at the counter since the last vault run. Over `limit` it is worth a snatch.
## `away` counts down the seconds of a vault run under way.
func set_till(usd: float, limit: float, away: float) -> void:
	if away > 0.0:
		_till.text = "Off to the vault..."
		_till.add_theme_color_override("font_color", Pal.INK_DIM)
	else:
		_till.text = tr("Till %s") % Market.format_money(usd)
		var hot := usd > limit
		var flash := hot and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
		_till.add_theme_color_override("font_color", Pal.BAD if flash else (Pal.WARN if hot else Pal.INK_DIM))
	_till_button.disabled = away > 0.0 or usd < 1.0


## Fills the counter card. `c` is null when nobody is at the counter.
func show_customer(c: Customer, idle_text := "") -> void:
	_customer = c
	for b in _buttons.values():
		b.visible = false
	for l in _deal:
		l.text = ""
	if c == null:
		_avatar.texture = null
		_who.text = ""
		_wants.text = ""
		_quote.text = idle_text
		_quote.add_theme_color_override("font_color", Pal.INK_DIM)
		return
	_avatar.texture = c.frames[0]
	_who.text = c.name
	var tag := Customers.tag(c)
	_wants.text = {"seller": tr("wants to sell"), "buyer": tr("wants to buy"), "visit": tr("stopped by to talk"), "robber": tr("HOLD-UP"),
		"order": tr("special order"), "grade": tr("wants a coin graded")}.get(c.kind, "")
	if tag != "":
		_wants.text = "%s · %s" % [tag, _wants.text]
	_quote.text = "\"%s\"" % c.say
	_quote.add_theme_color_override("font_color", Pal.INK)
	_refresh_deal()


func add_log(text: String, mood := "") -> void:
	for n in range(_log_lines.size() - 1, 0, -1):
		_log_lines[n].text = _log_lines[n - 1].text
		_log_lines[n].add_theme_color_override("font_color", _log_lines[n - 1].get_theme_color("font_color").darkened(0.12))
	_log_lines[0].text = text
	_log_lines[0].add_theme_color_override("font_color", {"good": Pal.GOOD, "bad": Pal.BAD}.get(mood, Pal.INK))


## The morning briefing over the shop floor, with upgrades one click away.
func show_morning() -> void:
	show_customer(null, "The shop opens when you press Open the shop.")
	_decor.close(false)
	_panels.show_morning()


func hide_panels() -> void:
	_panels.hide_panel()
	_decor.close(false)


## Decorating: the morning panel steps aside so the shop floor shows.
func open_decor() -> void:
	if room == null or Day.phase != Day.MORNING:
		return
	_panels.hide_panel()
	_decor.open(room)


func is_decorating() -> bool:
	return _decor.is_open()


## `report` comes from Day.end_day().
func show_day_summary(report: Dictionary) -> void:
	_decor.close(false)
	_panels.show_summary(report)


func _refresh() -> void:
	for metal in TICKER:
		var l: Label = _ticker_labels[metal]
		if not Market.prices.has(metal):
			l.text = ""
			continue
		var change := Market.day_change_percent(metal)
		l.text = "%s %s %s%.1f%%" % [TICKER_NAMES[metal], Market.format_money(Market.prices[metal], 2 if metal == "XAG" else 0), "▲" if change >= 0.0 else "▼", absf(change)]
		l.add_theme_color_override("font_color", Pal.GOOD if change >= 0.0 else Pal.BAD)
	_feed.text = {"live": tr("● LIVE"), "cached": tr("● CACHED"), "simulated": tr("● OFFLINE")}.get(Market.source, "")
	_feed.add_theme_color_override("font_color", {"live": Pal.GOOD, "cached": Pal.WARN}.get(Market.source, Pal.INK_FAINT))
	var full := int(Shop.reputation)
	var half := Shop.reputation - full >= 0.5
	_stars.text = "★".repeat(full) + ("☆" if half else "") + "  %.1f" % Shop.reputation
	if is_nan(_cash_shown):
		_cash_shown = Shop.cash
	_cash.text = Market.format_money(_cash_shown)
	_stock_value.text = Market.format_money(Shop.vault_value())
	var net := Shop.net_worth()
	_net.text = Market.format_money(net)
	_goal.value = Progress.next_tier_progress() * 100.0
	if Progress.is_top_tier():
		_goal_text.text = "Top of the town"
	elif Demo.tier_locked(Progress.tier + 1):
		_goal_text.text = "Full game"
	else:
		_goal_text.text = tr("Next %s") % Market.format_money(Progress.tier_info(Progress.tier + 1).need_worth)
	_tier.text = Progress.tier_name()
	_buy_label.text = tr("Pay sellers %d%% of melt") % roundi(Shop.buy_percent * 100.0)
	_sell_label.text = tr("Charge buyers +%d%%") % roundi(Shop.sell_premium * 100.0)
	var groups := {}
	for lot in Shop.stock:
		var key: String = lot.item.display_name
		groups[key] = groups.get(key, [0, 0.0])
		groups[key][0] += lot.qty
		groups[key][1] += lot.item.melt_value() * lot.qty
	var keys := groups.keys()
	for n in _stock_lines.size():
		var l := _stock_lines[n]
		if n < keys.size():
			l.text = "%d × %s" % [groups[keys[n]][0], keys[n]]
			_stock_values[n].text = Market.format_money(groups[keys[n]][1])
		else:
			l.text = "Empty vault." if n == 0 and keys.is_empty() else ""
			_stock_values[n].text = ""
	if _customer:
		_refresh_deal()


func _refresh_deal() -> void:
	var c := _customer
	if c == null:
		return
	if c.kind == "visit":
		_deal[0].text = c.note
		_deal[0].add_theme_color_override("font_color", Pal.GOLD)
		_buttons.decline.visible = true
		_buttons.decline.text = "Goodbye"
		return
	if c.kind == "robber":
		_deal[0].text = "Wants the till and the case"
		_deal[0].add_theme_color_override("font_color", Pal.BAD)
		_deal[1].text = "He won't wait long."
		_deal[1].add_theme_color_override("font_color", Pal.INK)
		_deal[2].text = tr("Panic button works %d%%") % roundi(Security.panic_odds() * 100.0)
		_deal[2].add_theme_color_override("font_color", Pal.WARN)
		_buttons.decline.visible = true
		_buttons.decline.text = "Hand over till"
		_buttons.sell.visible = true
		_buttons.sell.disabled = false
		_buttons.sell.text = "Panic button"
		return
	_deal[0].add_theme_color_override("font_color", Pal.INK)
	if c.kind == "order":
		var days: int = int(c.order.due) - Shop.day
		_deal[0].text = "%d × %s" % [c.qty, c.item.display_name]
		_deal[1].text = tr_n("By %s (%d day)  You hold %d", "By %s (%d days)  You hold %d", days) % [Day.weekday(int(c.order.due)), days, Shop.count_of_item(c.item)]
		_deal[1].add_theme_color_override("font_color", Pal.INK)
		_deal[2].text = tr("Pays %s  (+%d%%)") % [Market.format_money(c.sale_total()), roundi(float(c.order.premium) * 100.0)]
		_deal[2].add_theme_color_override("font_color", Pal.GOLD)
		_buttons.sell.visible = true
		_buttons.sell.disabled = false
		_buttons.sell.text = "Take order"
		_buttons.decline.visible = true
		_buttons.decline.text = "Not now"
		return
	if c.kind == "grade":
		_deal[0].text = c.item.display_name
		_deal[1].text = tr("Hopes for %s") % CoinGrade.grade_id(c.grading.hoped)
		_deal[1].add_theme_color_override("font_color", Pal.INK)
		_deal[2].text = tr("Fee %s if you grade it right") % Market.format_money(CoinGrade.fee())
		_deal[2].add_theme_color_override("font_color", Pal.GOLD)
		_buttons.test.visible = true
		_buttons.test.text = "Grade it"
		_buttons.decline.visible = true
		_buttons.decline.text = "Not now"
		return
	if c.kind == "seller":
		if c.piece:
			_deal[0].text = c.piece.short_title() + (tr(" with stone") if c.piece.stone != "" else "")
			_deal[1].text = "%s  %s" % [tr("Appraised") if c.tested else tr("As claimed"), Market.format_money(c.melt_total())]
		elif c.bar:
			_deal[0].text = c.bar.display_name()
			_deal[1].text = tr("Melt today  %s") % Market.format_money(c.melt_total())
		else:
			_deal[0].text = "%d × %s" % [c.qty, c.item.display_name]
			_deal[1].text = tr("Melt today  %s") % Market.format_money(c.melt_total())
		_deal[2].text = tr("Your offer  %s%s") % [Market.format_money(c.offer_total()), tr("  tested") if c.tested else ""]
		_deal[2].add_theme_color_override("font_color", Pal.GOLD)
		_buttons.test.visible = not c.tested
		_buttons.test.text = "Examine" if c.piece else ("Test bar" if c.bar else "Test coin")
		_buttons.offer.visible = true
		_buttons.offer.text = "Make offer" if c.tested else "Buy as is"
		var short := c.offer_total() > Shop.cash
		_buttons.offer.disabled = short
		if short:
			_deal[1].text = tr("Not enough cash: %s") % Market.format_money(Shop.cash)
			_deal[1].add_theme_color_override("font_color", Pal.BAD)
		else:
			_deal[1].add_theme_color_override("font_color", Pal.INK)
		# always leave a way out, even when the offer can't be paid
		_buttons.refuse.visible = true
		_buttons.refuse.text = "No thanks" if c.tested else "Refuse"
	else:
		var have := c.stock_have()
		if c.wanted_exact:
			_deal[0].text = "%d × %s" % [c.qty, c.item.display_name]
		else:
			_deal[0].text = tr("%d × %s coins") % [c.qty, tr({"XAU": "gold", "XAG": "silver", "XPT": "platinum"}.get(c.item.metal, ""))]
		var can := c.can_sell()
		var short := can > 0 and can < c.qty
		_deal[1].text = tr("You hold only %d") % have if short else tr("You hold %d") % have
		_deal[1].add_theme_color_override("font_color", Pal.INK)
		# short of what they want, the price is for the coins you can hand over
		_deal[2].text = "%s  %s" % [tr("Agreed") if not c.order.is_empty() else (tr("Pays") if c.fixed_price() else tr("Price")),
			Market.format_money(c.sale_total() * (float(can) / c.qty if short else 1.0))]
		_deal[2].add_theme_color_override("font_color", Pal.GOLD)
		_buttons.sell.visible = true
		# short of what they want: offer what you have
		if short:
			_buttons.sell.text = tr("Sell %d") % can
		else:
			_buttons.sell.text = "Sell"
		_buttons.sell.disabled = can <= 0
		_buttons.decline.visible = true
		_buttons.decline.text = "Out of stock" if can <= 0 else "Decline"


# ---------------------------------------------------------------- layout

func _build_ticker() -> void:
	_panel(Rect2(0, 0, 480, 12), Color("#120e0a"), Pal.PANEL_EDGE)
	var x := 4
	for metal in TICKER:
		_ticker_labels[metal] = _label("", Vector2(x, 3), Vector2(86, 8))
		x += 84
	_feed = _label("", Vector2(342, 3), Vector2(52, 8))
	# the currency picker lives in Settings, behind this button and Esc
	var menu := _small_button("Menu", Rect2(440, 1, 38, 10), func(): menu_requested.emit())
	menu.tooltip_text = "Pause, settings and quit (Esc)"


func _build_side() -> void:
	_panel(Rect2(SIDE_X - 2, 12, SIDE_W + 4, 258), Pal.PANEL, Pal.PANEL_EDGE)
	var x := SIDE_X + 2
	_day = _label("Day 1", Vector2(x, 16), Vector2(80, 16), Pal.GOLD)
	_day.add_theme_font_size_override("font_size", 16)
	_clock = _label("09:00", Vector2(x + 76, 21), Vector2(78, 8), Pal.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_stars = _label("", Vector2(x, 33), Vector2(60, 8), Pal.GOLD)
	_tier = _label("", Vector2(x + 60, 33), Vector2(94, 8), Pal.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_cash = _row("Cash", 43)
	_stock_value = _row("Stock at spot", 52)
	_net = _row("Net worth", 61)
	_net.add_theme_color_override("font_color", Pal.GOLD)
	_goal = ProgressBar.new()
	add_child(_goal)
	_goal.show_percentage = false
	_goal.position = Vector2(x, 72)
	_goal.size = Vector2(80, 5)
	_goal_text = _label("", Vector2(x + 82, 70), Vector2(72, 8), Pal.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)

	_panel(Rect2(SIDE_X, 82, SIDE_W - 2, 116), Color("#241c15"), Pal.PANEL_EDGE)
	_avatar = TextureRect.new()
	add_child(_avatar)
	_avatar.position = Vector2(x + 1, 86)
	_avatar.size = Vector2(16, 28)
	_who = _label("", Vector2(x + 22, 88), Vector2(130, 8), Pal.GOLD)
	_wants = _label("", Vector2(x + 22, 97), Vector2(130, 8), Pal.INK_DIM)
	_quote = _label("", Vector2(x + 1, 117), Vector2(152, 27), Pal.INK)
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for n in 3:
		_deal.append(_label("", Vector2(x + 1, 145 + n * 9), Vector2(152, 8)))
	_buttons.test = _button("Test coin", Rect2(x, 177, 50, 12), "PrimaryButton", "test")
	_buttons.offer = _button("Make offer", Rect2(x + 52, 177, 52, 12), "Button", "offer")
	_buttons.refuse = _button("Refuse", Rect2(x + 106, 177, 48, 12), "DangerButton", "refuse")
	_buttons.sell = _button("Sell", Rect2(x, 177, 70, 12), "PrimaryButton", "sell")
	_buttons.decline = _button("Decline", Rect2(x + 74, 177, 80, 12), "Button", "decline")

	_buy_label = _label("", Vector2(x, 205), Vector2(124, 8))
	_small_button("-", Rect2(x + 130, 203, 11, 11), func(): Shop.set_buy_percent(Shop.buy_percent - 0.01))
	_small_button("+", Rect2(x + 143, 203, 11, 11), func(): Shop.set_buy_percent(Shop.buy_percent + 0.01))
	_sell_label = _label("", Vector2(x, 218), Vector2(124, 8))
	_small_button("-", Rect2(x + 130, 216, 11, 11), func(): Shop.set_sell_premium(Shop.sell_premium - 0.01))
	_small_button("+", Rect2(x + 143, 216, 11, 11), func(): Shop.set_sell_premium(Shop.sell_premium + 0.01))

	_label("IN THE VAULT", Vector2(x, 232), Vector2(60, 8), Pal.INK_FAINT)
	_till = _label("", Vector2(x + 50, 232), Vector2(62, 8), Pal.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_till_button = _button("To vault", Rect2(x + 116, 230, 38, 10), "Button", "vault_run")
	_till_button.tooltip_text = "Take the till's cash to the vault (3 seconds away from the counter)"
	for n in 3:
		_stock_lines.append(_label("", Vector2(x, 241 + n * 9), Vector2(110, 8), Pal.INK_DIM))
		_stock_values.append(_label("", Vector2(x + 104, 241 + n * 9), Vector2(50, 8), Pal.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT))


func _build_log() -> void:
	_panel(Rect2(0, 233, SIDE_X - 2, 37), Color("#120e0a"), Pal.PANEL_EDGE)
	for n in 4:
		_log_lines.append(_label("", Vector2(4, 235 + n * 8), Vector2(308, 8), Pal.INK))


func _row(caption: String, y: int) -> Label:
	_label(caption, Vector2(SIDE_X + 2, y), Vector2(80, 8), Pal.INK_DIM)
	return _label("", Vector2(SIDE_X + 76, y), Vector2(78, 8), Pal.INK, HORIZONTAL_ALIGNMENT_RIGHT)


func _label(text: String, pos: Vector2, size: Vector2, col := Pal.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	add_child(l)
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.clip_text = true
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(r: Rect2, bg: Color, edge: Color) -> Panel:
	var p := Panel.new()
	add_child(p)
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", UiTheme.box(bg, edge))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _button(text: String, r: Rect2, variation: String, id: String) -> Button:
	var b := Button.new()
	add_child(b)
	b.text = text
	b.theme_type_variation = variation
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sfx.play(self, Sfx.click(), -14.0)
		action.emit(id))
	return b


func _small_button(text: String, r: Rect2, on_press: Callable) -> Button:
	var b := Button.new()
	add_child(b)
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b
