class_name DayPanels
extends PanelContainer
## The panels over the shop floor between shop hours: the morning briefing, the
## upgrades, staff and expansion page, and the end-of-day summary. Rebuilt each time one opens.

signal open_requested
signal next_day_requested
signal new_game_requested

const AREA := Rect2(12, 18, 292, 208)
const METAL_NAMES := {"XAU": "Gold", "XAG": "Silver", "XPT": "Platinum", "XPD": "Palladium"}

var page := "" # "morning", "upgrades", "summary" or "" when hidden
## The morning's Open the shop button, for the tutorial to point at.
var open_button: Button
var _box: VBoxContainer
var _hint: Label
var _confirm_new := false


func _ready() -> void:
	position = AREA.position
	size = AREA.size
	add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 8, 6))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	add_child(_box)
	visible = false
	Progress.changed.connect(_refresh_page)
	Shop.changed.connect(_refresh_page)
	Staff.changed.connect(_refresh_page)


func hide_panel() -> void:
	page = ""
	visible = false


func show_morning() -> void:
	page = "morning"
	_confirm_new = false
	_build_morning()


func show_upgrades() -> void:
	page = "upgrades"
	_build_upgrades()


func show_summary(report: Dictionary) -> void:
	page = "summary"
	_build_summary(report)


func _refresh_page() -> void:
	# keep requirement ticks and buy buttons in step with cash and stars
	if page == "morning":
		_build_morning()
	elif page == "upgrades":
		_build_upgrades()


func _clear() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	visible = true


# ---------------------------------------------------------------- morning

func _build_morning() -> void:
	_clear()
	_title("%s, day %d" % [Day.weekday(), Shop.day])
	_text("%s · morning. Set your prices on the right, then open up." % Progress.tier_name(), Pal.INK_DIM)
	_text(_market_hint(), Pal.INK)
	_text(RushHours.summary(Shop.day), Pal.WARN)
	_gap()
	_heading("BILLS")
	var grid := _grid()
	_pair(grid, "Upkeep tonight", Market.format_money(Progress.daily_upkeep()))
	if not Staff.hired.is_empty():
		_pair(grid, "Staff wages tonight", Market.format_money(Staff.daily_wages()))
	var weekly := 0.0
	for bill in Day.upcoming_bills():
		weekly += bill.usd
	var due := Day.days_until_bills()
	_pair(grid, "Rent and insurance", Market.format_money(weekly), Pal.BAD if due == 0 else Pal.INK)
	_pair(grid, "Due", "tonight" if due == 0 else "%s (in %d day%s)" % [Day.weekday(Shop.day + due), due, "" if due == 1 else "s"], Pal.INK_DIM)
	_gap()
	if Progress.goal_reached():
		_heading("YOU RUN THE BIGGEST STORE IN TOWN")
		_text("Keep growing your vault and reputation.", Pal.INK_DIM)
	else:
		var next := Progress.tier_info(Progress.tier + 1)
		_heading("NEXT: %s" % next.name.to_upper())
		var req := _grid()
		_requirement(req, "Net worth", Shop.net_worth(), next.need_worth, true)
		_requirement(req, "Reputation", Shop.reputation, next.need_rep, false)
		_requirement(req, "Cash to move", Shop.cash, next.cost, true)
	_spacer()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	open_button = _button(row, "Open the shop", "PrimaryButton", func(): open_requested.emit())
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := Progress.available_upgrades().size() + Staff.ROLES.size() - Staff.hired.size()
	var expand_ready := Progress.expand_blocker() == "" and not Progress.is_top_tier()
	_button(row, "Upgrades (%d)%s" % [count, " !" if expand_ready else ""], "Button", show_upgrades)
	_button(row, "Sure? Click again" if _confirm_new else "New game", "DangerButton", _on_new_game)


func _market_hint() -> String:
	var best := ""
	var best_change := 0.0
	for metal in ["XAU", "XAG", "XPT"]:
		var change := Market.day_change_percent(metal)
		if absf(change) > absf(best_change):
			best = metal
			best_change = change
	if best == "" or absf(best_change) < 0.3:
		return "Metals are calm this morning. Expect a normal day."
	if best_change > 0.0:
		return "%s is up %.1f%%. Expect more sellers cashing in." % [METAL_NAMES[best], best_change]
	return "%s is down %.1f%%. Bargain hunters will be out." % [METAL_NAMES[best], absf(best_change)]


func _requirement(grid: GridContainer, caption: String, have: float, need: float, money: bool) -> void:
	var ok := have >= need
	var fmt := func(v): return Market.format_money(v) if money else "%.1f stars" % v
	_pair(grid, ("● " if ok else "○ ") + caption, "%s / %s" % [fmt.call(have), fmt.call(need)], Pal.GOOD if ok else Pal.INK)


func _on_new_game() -> void:
	if not _confirm_new:
		_confirm_new = true
		_build_morning()
		return
	_confirm_new = false
	new_game_requested.emit()


# ---------------------------------------------------------------- upgrades

func _build_upgrades() -> void:
	_clear()
	_title("Upgrades and staff")
	_text("Cash %s. Hover an upgrade to see what it does." % Market.format_money(Shop.cash), Pal.INK_DIM)
	_gap()
	var grid := _grid(3)
	if not Progress.is_top_tier():
		var next := Progress.tier_info(Progress.tier + 1)
		var blocker := Progress.expand_blocker()
		_upgrade_row(grid, "Move to %s" % next.name, next.cost, blocker == "", "Move",
			"Rent %s a week. More customers, bigger deals and more upgrades. %s" % [Market.format_money(next.rent), blocker],
			func(): Progress.expand(), Pal.GOLD)
	for id in Progress.owned:
		var u: Dictionary = Progress.upgrades.get(id, {})
		if not u.is_empty():
			_upgrade_row(grid, u.name, -1.0, false, "Owned", u.desc, Callable(), Pal.GOOD)
	for id in Progress.available_upgrades():
		var u: Dictionary = Progress.upgrades[id]
		_upgrade_row(grid, u.name, u.cost, Progress.can_buy(id), "Buy", u.desc, func(): Progress.buy(id))
	for id in Staff.ROLES:
		var role: Dictionary = Staff.ROLES[id]
		var desc := "%s Wage %s a day." % [role.desc, Market.format_money(Staff.wage(id))]
		if Staff.has(id):
			_upgrade_row(grid, "%s, %s" % [role.name, role.title.to_lower()], -1.0, true, "Let go", desc, func(): Staff.let_go(id), Pal.GOOD)
		elif int(role.tier) <= Progress.tier:
			_upgrade_row(grid, "Hire a %s" % role.title.to_lower(), role.fee, Staff.can_hire(id), "Hire", desc, func(): Staff.hire(id))
	var locked := Progress.locked_upgrade_count()
	if locked > 0:
		_text("%d more upgrade%s unlock as the shop grows." % [locked, "" if locked == 1 else "s"], Pal.INK_FAINT)
	_spacer()
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 17)
	if not Progress.is_top_tier() and Progress.expand_blocker() != "":
		_hint.text = "To move up: %s." % Progress.expand_blocker().to_lower()
	var row := HBoxContainer.new()
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)


func _upgrade_row(grid: GridContainer, title: String, cost: float, enabled: bool, verb: String, desc: String, on_buy: Callable, col := Pal.INK) -> void:
	var name_label := _cell(grid, title, col)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cell(grid, Market.format_money(cost) if cost >= 0.0 else "", Pal.INK_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var b := Button.new()
	b.text = verb
	b.custom_minimum_size = Vector2(34, 11)
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "PrimaryButton" if enabled else "Button"
	b.disabled = not enabled
	b.tooltip_text = desc
	if on_buy.is_valid():
		b.pressed.connect(on_buy)
	grid.add_child(b)
	var hover := func():
		if _hint:
			_hint.text = desc
	b.mouse_entered.connect(hover)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.mouse_entered.connect(hover)


# ---------------------------------------------------------------- summary

func _build_summary(report: Dictionary) -> void:
	_clear()
	var stats: Dictionary = report.get("stats", {})
	_title("Day %d closed" % report.get("day", Shop.day))
	var grid := _grid()
	_pair(grid, "Bought from customers", Market.format_money(stats.get("bought", 0.0)))
	_pair(grid, "Sold to customers", Market.format_money(stats.get("sold", 0.0)))
	var profit: float = stats.get("profit", 0.0)
	_pair(grid, "Profit on sales", Market.format_money(profit), Pal.GOOD if profit >= 0.0 else Pal.BAD)
	_pair(grid, "Fakes caught / missed", "%d / %d" % [int(stats.get("caught", 0)), int(stats.get("scammed", 0))])
	for entry in report.get("ledger", []):
		var usd: float = entry.usd
		_pair(grid, entry.label, ("+" if usd > 0.0 else "") + Market.format_money(usd), Pal.GOOD if usd > 0.0 else Pal.BAD)
	var cash_change: float = report.get("cash_change", 0.0)
	_pair(grid, "Cash change today", ("+" if cash_change > 0.0 else "") + Market.format_money(cash_change), Pal.GOOD if cash_change >= 0.0 else Pal.BAD)
	_pair(grid, "Net worth at today's prices", Market.format_money(Shop.net_worth()), Pal.GOLD)
	for line in report.get("lines", []):
		_text(str(line), Pal.WARN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bills_in: int = report.get("next_bills_in", 0)
	_text("Next rent and insurance in %d day%s." % [bills_in, "" if bills_in == 1 else "s"], Pal.INK_FAINT)
	_spacer()
	var row := HBoxContainer.new()
	_box.add_child(row)
	var go := _button(row, "Lock up and go home", "PrimaryButton", func(): next_day_requested.emit())
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# ---------------------------------------------------------------- helpers

func _title(text: String) -> Label:
	var l := _text(text, Pal.GOLD)
	l.add_theme_font_size_override("font_size", 16)
	return l


func _heading(text: String) -> Label:
	return _text(text, Pal.INK_FAINT)


func _text(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.custom_minimum_size = Vector2(AREA.size.x - 16, 0)
	_box.add_child(l)
	return l


func _gap() -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 2)
	_box.add_child(c)


func _spacer() -> void:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(c)


func _grid(columns := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 1)
	_box.add_child(g)
	return g


func _cell(grid: GridContainer, text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(l)
	return l


func _pair(grid: GridContainer, caption: String, value: String, col := Pal.INK) -> void:
	_cell(grid, caption, Pal.INK_DIM).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cell(grid, value, col).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _button(parent: Control, text: String, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
