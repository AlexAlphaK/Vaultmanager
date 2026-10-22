class_name DayPanels
extends PanelContainer
## The panels over the shop floor between shop hours: the morning briefing, the
## upgrades, staff and expansion page, the floor plan where rooms are built, the town
## map with the rival shops, the collectors' special orders, the ledger of records and achievements, and the
## end-of-day summary. Rebuilt each time one opens.

signal open_requested
signal next_day_requested
signal new_game_requested
signal desk_requested

const AREA := Rect2(12, 18, 292, 208)
const METAL_NAMES := {"XAU": "Gold", "XAG": "Silver", "XPT": "Platinum", "XPD": "Palladium"}

var page := "" # "morning", "upgrades", "plan", "wholesale", "town", "orders", "ledger", "achievements", "summary" or "" when hidden
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
	Wholesaler.changed.connect(_refresh_page)
	Orders.changed.connect(_refresh_page)
	Records.changed.connect(_refresh_page)
	Rivals.changed.connect(_refresh_page)


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


func show_plan() -> void:
	page = "plan"
	_build_plan()


func show_wholesale() -> void:
	page = "wholesale"
	_build_wholesale()


func show_town() -> void:
	page = "town"
	_build_town()


func show_orders() -> void:
	page = "orders"
	_build_orders()


func show_ledger() -> void:
	page = "ledger"
	_build_ledger()


func show_achievements() -> void:
	page = "achievements"
	_build_achievements()


func show_summary(report: Dictionary) -> void:
	page = "summary"
	_build_summary(report)


func _refresh_page() -> void:
	# keep requirement ticks and buy buttons in step with cash and stars
	if page == "morning":
		_build_morning()
	elif page == "upgrades":
		_build_upgrades()
	elif page == "plan":
		_build_plan()
	elif page == "wholesale":
		_build_wholesale()
	elif page == "town":
		_build_town()
	elif page == "orders":
		_build_orders()
	elif page == "ledger":
		_build_ledger()
	elif page == "achievements":
		_build_achievements()


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
	if not Orders.open.is_empty():
		_text(_orders_hint(), Pal.GOLD)
	if not Rivals.news.is_empty():
		_text("Town: " + Rivals.news[0], Pal.WARN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	_box.add_child(pages)
	var count := Progress.available_upgrades().size() + Staff.ROLES.size() - Staff.hired.size()
	var expand_ready := Progress.expand_blocker() == "" and not Progress.is_top_tier()
	_button(pages, "Upgrades (%d)%s" % [count, " !" if expand_ready else ""], "Button", show_upgrades)
	_button(pages, "Restock", "Button", show_wholesale).tooltip_text = "Buy coins from the wholesaler before you open."
	_button(pages, "Town map%s" % (" !" if not Rivals.news.is_empty() else ""), "Button", show_town).tooltip_text = "The rival shops, their prices and what they are up to."
	if not Orders.open.is_empty():
		_button(pages, "Orders (%d)" % Orders.open.size(), "Button", show_orders).tooltip_text = "Collectors' special orders and the dealer network."
	_button(pages, "Ledger", "Button", show_ledger)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	open_button = _button(row, "Open the shop", "PrimaryButton", func(): open_requested.emit())
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Progress.has_upgrade("trading_desk"):
		var desk := _button(row, "Trading desk", "Button", func(): desk_requested.emit())
		desk.disabled = not DeskSession.available()
		desk.tooltip_text = "Trade at the desk this morning." if not desk.disabled else "The desk has traded today. Back tomorrow morning."
	_button(row, "Sure? Click again" if _confirm_new else "New game", "DangerButton", _on_new_game)


## The order due soonest, for the morning briefing.
func _orders_hint() -> String:
	var next: Dictionary = Orders.open[0]
	for o in Orders.open:
		if int(o.due) < int(next.due):
			next = o
	var have := Orders.have_for(next)
	var when := "today" if Orders.days_left(next) <= 0 else Day.weekday(int(next.due))
	return "%s wants %d × %s %s. You hold %d." % [next.name, next.qty, Orders.item_of(next).display_name, when, have]


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
	# the list outgrows the panel as the shop grows, so it scrolls
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var grid := _grid(3)
	_box.remove_child(grid)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	if not Progress.is_top_tier():
		var next := Progress.tier_info(Progress.tier + 1)
		var blocker := Progress.expand_blocker()
		_upgrade_row(grid, "Move to %s" % next.name, next.cost, blocker == "", "Move",
			"Rent %s a week. More customers, bigger deals and more upgrades. %s" % [Market.format_money(next.rent), blocker],
			func(): Progress.expand(), Pal.GOLD)
	# rooms are built on the floor plan page
	for id in Progress.owned:
		var u: Dictionary = Progress.upgrades.get(id, {})
		if not u.is_empty() and Progress.line_of(id) != "room":
			_upgrade_row(grid, u.name, -1.0, false, "Owned", u.desc, Callable(), Pal.GOOD)
	for id in Progress.available_upgrades():
		var u: Dictionary = Progress.upgrades[id]
		if Progress.line_of(id) == "room":
			continue
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
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 17)
	if not Progress.is_top_tier() and Progress.expand_blocker() != "":
		_hint.text = "To move up: %s." % Progress.expand_blocker().to_lower()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	var rooms := Progress.available_upgrades("room").size()
	_button(row, "Floor plan%s" % (" (%d to build)" % rooms if rooms > 0 else ""), "Button", show_plan)


# ---------------------------------------------------------------- floor plan

func _build_plan() -> void:
	_clear()
	_title("Floor plan")
	var map := TextureRect.new()
	map.texture = PlanArt.paint(Progress.tier, Progress.owned).texture()
	map.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	map.custom_minimum_size = Vector2(PlanArt.SIZE)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(map)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	for room in PlanArt.ROOMS:
		if room.upgrade == "":
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
		_room_entry(cell, room)
	var back := _button(row, "Back", "Button", show_upgrades)
	back.size_flags_vertical = Control.SIZE_SHRINK_END
	_hint = _text("Each move up opens a plot next door. Build a room there to add it to your shop.", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A room's short name and its Build button, or where it stands when it can't be built.
func _room_entry(list: VBoxContainer, room: Dictionary) -> void:
	var id: String = room.upgrade
	var u: Dictionary = Progress.upgrades[id]
	var st := PlanArt.state(room, Progress.tier, Progress.owned)
	var label := Label.new()
	label.text = room.label
	label.add_theme_color_override("font_color", Pal.GOOD if st == "built" else (Pal.INK if st == "shell" else Pal.INK_FAINT))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(label)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 11)
	b.focus_mode = Control.FOCUS_NONE
	var desc: String
	match st:
		"built":
			b.text = "Built"
			b.disabled = true
			desc = "%s. %s" % [u.name, u.desc]
		"shell":
			b.text = "Build"
			b.theme_type_variation = "PrimaryButton" if Progress.can_buy(id) else "Button"
			b.disabled = not Progress.can_buy(id)
			b.pressed.connect(func(): Progress.buy(id))
			desc = "%s, %s. %s" % [u.name, Market.format_money(u.cost), u.desc]
		_:
			b.text = "Locked"
			b.disabled = true
			desc = "%s: the plot next door opens when you move to the %s. %s" % [u.name, Progress.tier_name(int(u.tier)), u.desc]
	b.tooltip_text = desc
	list.add_child(b)
	var hover := func():
		if _hint:
			_hint.text = desc
	b.mouse_entered.connect(hover)
	label.mouse_entered.connect(hover)


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


# ---------------------------------------------------------------- wholesaler

func _build_wholesale() -> void:
	_clear()
	_title("Morning wholesaler")
	_text("Coins at spot plus %d%%, delivered before you open. Cash %s." % [roundi(Wholesaler.markup() * 100.0),
		Market.format_money(Shop.cash)], Pal.INK_DIM)
	_text("Walk-in sellers are cheaper. Restock what buyers ask for.", Pal.INK_FAINT)
	_gap()
	var grid := _grid(6)
	for caption in ["Coin", "Each", "Have", "Left", "", ""]:
		_cell(grid, caption, Pal.INK_FAINT)
	for item in Wholesaler.coin_list():
		var left := Wholesaler.left(item)
		_cell(grid, item.display_name, Pal.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cell(grid, Market.format_money(Wholesaler.price(item)), Pal.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cell(grid, str(Shop.count_of_item(item)), Pal.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cell(grid, str(left), Pal.INK_DIM if left > 0 else Pal.INK_FAINT).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var bulk := Wholesaler.bulk(item)
		for qty in ([1, bulk] if bulk > 1 else [1, 0]):
			if qty == 0:
				_cell(grid, "", Pal.INK)
				continue
			var b := Button.new()
			b.text = "+%d" % qty
			b.custom_minimum_size = Vector2(22, 11)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = Wholesaler.affordable(item, qty) < qty
			b.theme_type_variation = "Button" if b.disabled else "PrimaryButton"
			b.tooltip_text = "Buy %d for %s." % [qty, Market.format_money(Wholesaler.price(item) * qty)]
			b.pressed.connect(func(): Wholesaler.buy(item, qty))
			grid.add_child(b)
	if Wholesaler.bought_today > 0.0:
		_text("Bought this morning: %s." % Market.format_money(Wholesaler.bought_today), Pal.GOOD)
	_spacer()
	var row := HBoxContainer.new()
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)


# ---------------------------------------------------------------- town map

func _build_town() -> void:
	_clear()
	_title("Town map")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_box.add_child(row)
	var ranks := {}
	var ranking := Rivals.ranking()
	for n in ranking.size():
		ranks[ranking[n].id] = n + 1
	var map := TextureRect.new()
	map.texture = TownArt.paint({"tier": Progress.tier, "ranks": ranks, "sterling_move": Rivals.move_of("sterling"),
		"pawn_move": Rivals.move_of("pawn"), "pawn_closed": not Rivals.is_open("pawn")}).texture()
	map.custom_minimum_size = Vector2(TownArt.SIZE)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(map)
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 0)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cards)
	_shop_card(cards, "you", ranks.you)
	for id in Rivals.SHOPS:
		_shop_card(cards, id, ranks[id])
	for line in Rivals.news.slice(0, 2):
		_text(line, Pal.WARN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Rivals.news.is_empty():
		_text("A quiet morning on Main Street. Your share of the town's customers: %d%%." % roundi(Rivals.overall_share() * 100.0),
			Pal.INK_DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spacer()
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_box.add_child(buttons)
	_button(buttons, "Back", "Button", show_morning)
	var ad := "Ad runs %d more day%s" % [Rivals.ad_days, "" if Rivals.ad_days == 1 else "s"] if Rivals.ad_days > 0 \
		else "Newspaper ad %s" % Market.format_money(Rivals.ad_cost())
	_town_button(buttons, ad, Rivals.can_run_ad(), func(): Rivals.run_ad(),
		"An ad in the town paper: for %d days more customers pick your shop over the others." % Rivals.AD_DAYS)
	_town_button(buttons, "Beat Sterling", true, func(): Rivals.beat_sterling(),
		"Set your board a point better than Sterling's: pay %d%% of melt, sell at spot +%d%%." % [
			roundi(minf(1.0, Rivals.buy_of("sterling") + 0.01) * 100.0), roundi(maxf(0.0, Rivals.premium_of("sterling") - 0.01) * 100.0)])
	if Rivals.can_tip_off():
		_town_button(buttons, "Tip off police", true, func(): Rivals.tip_off(),
			"Tell Detective Ruiz about Lucky's stolen goods. A raid shuts the pawn shop for %d days." % Rivals.RAID_DAYS)


## One shop's line on the town map: its name and place, then stars, prices and worth.
func _shop_card(list: VBoxContainer, id: String, place: int) -> void:
	var you := id == "you"
	var name_label := Label.new()
	name_label.text = "#%d %s" % [place, "Your shop" if you else Rivals.name_of(id)]
	name_label.add_theme_color_override("font_color", Pal.GOLD if you else Pal.INK)
	list.add_child(name_label)
	var stars := Shop.reputation if you else Rivals.stars_of(id)
	var pays := Shop.buy_percent if you else Rivals.buy_of(id)
	var premium := Shop.sell_premium if you else Rivals.premium_of(id)
	var info := Label.new()
	if not you and not Rivals.is_open(id):
		info.text = "Raided: shut %d day%s" % [int(Rivals.state[id].closed), "" if int(Rivals.state[id].closed) == 1 else "s"]
		info.add_theme_color_override("font_color", Pal.BAD)
	else:
		info.text = "%.1f★  pays %d%%  +%d%%" % [stars, roundi(pays * 100.0), roundi(premium * 100.0)]
		info.add_theme_color_override("font_color", Pal.INK_DIM)
	list.add_child(info)
	var worth := Label.new()
	worth.text = "Worth %s" % Market.format_money(Shop.net_worth() if you else Rivals.worth_of(id))
	worth.add_theme_color_override("font_color", Pal.INK_FAINT)
	list.add_child(worth)


func _town_button(parent: Control, text: String, enabled: bool, on_press: Callable, desc: String) -> void:
	var b := _button(parent, text, "PrimaryButton" if enabled else "Button", on_press)
	b.disabled = not enabled
	b.tooltip_text = desc
	b.mouse_entered.connect(func():
		if _hint:
			_hint.text = desc)


# ---------------------------------------------------------------- special orders

func _build_orders() -> void:
	_clear()
	_title("Special orders")
	_text("Find the coins by the day agreed. Coins for an order are set aside.", Pal.INK_DIM)
	_gap()
	var grid := _grid(4)
	for caption in ["Collector", "Wants", "Have", "Due"]:
		_cell(grid, caption, Pal.INK_FAINT)
	for o in Orders.open:
		var have := Orders.have_for(o)
		var left := Orders.days_left(o)
		_cell(grid, o.name, Pal.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cell(grid, "%d × %s" % [o.qty, Orders.item_of(o).display_name], Pal.INK)
		_cell(grid, "%d/%d" % [have, o.qty], Pal.GOOD if have >= int(o.qty) else Pal.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cell(grid, "today" if left <= 0 else Day.weekday(int(o.due)).left(3), Pal.BAD if left <= 0 else (Pal.WARN if left == 1 else Pal.INK_DIM))
	var pays := 0.0
	for o in Orders.open:
		pays += Orders.price_of(o)
	_text("Pays %s in all on delivery." % Market.format_money(pays), Pal.GOLD)
	_gap()
	var wanted := Orders.wanted_rare()
	if not wanted.is_empty():
		_heading("DEALER NETWORK")
		var dealers := _grid(3)
		for item in wanted:
			var left := Orders.dealer_left(item)
			_cell(dealers, item.display_name, Pal.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if left <= 0:
				_cell(dealers, "none today", Pal.INK_FAINT)
				_cell(dealers, "", Pal.INK)
				continue
			_cell(dealers, Market.format_money(Orders.dealer_price(item)), Pal.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var b := Button.new()
			b.text = "Buy"
			b.custom_minimum_size = Vector2(22, 11)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = Shop.cash < Orders.dealer_price(item)
			b.theme_type_variation = "Button" if b.disabled else "PrimaryButton"
			b.pressed.connect(func(): Orders.dealer_buy(item))
			dealers.add_child(b)
		_text("Dealers charge most of the collector's premium. Sellers bring old coins too.", Pal.INK_FAINT)
	_spacer()
	var row := HBoxContainer.new()
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)


# ---------------------------------------------------------------- ledger

func _build_ledger() -> void:
	_clear()
	_title("The ledger")
	_text("%d day%s of trading. %d of %d achievements earned." % [Records.totals.days, "" if Records.totals.days == 1 else "s",
		Records.earned.size(), Records.ACHIEVEMENTS.size()], Pal.INK_DIM)
	_gap()
	var grid := _grid()
	_pair(grid, "Deals closed (buys / sales)", "%d / %d" % [Records.total("buys"), Records.total("sales")])
	_pair(grid, "Bought from customers", Market.format_money(Records.total("bought")))
	_pair(grid, "Sold to customers", Market.format_money(Records.total("sold")))
	var profit := Records.total("profit")
	_pair(grid, "Lifetime profit", Market.format_money(profit), Pal.GOOD if profit >= 0.0 else Pal.BAD)
	_pair(grid, "Fakes caught / missed", "%d / %d (%d%%)" % [Records.total("caught"), Records.total("scammed"), roundi(Records.catch_rate() * 100.0)])
	_pair(grid, "Lost to thieves", Market.format_money(Records.total("stolen")), Pal.BAD if Records.total("stolen") > 0.0 else Pal.INK)
	_pair(grid, "Highest net worth", Market.format_money(Records.peaks.worth), Pal.GOLD)
	_pair(grid, "Best reputation", "%.1f stars" % Records.peaks.rep)
	_pair(grid, "Profit streak", "%d day%s (best %d)" % [Records.streak, "" if Records.streak == 1 else "s", Records.peaks.streak])
	_gap()
	_heading("BEST DAYS")
	if Records.best_days.is_empty():
		_text("Close a day in profit to start the list.", Pal.INK_FAINT)
	else:
		var best := _grid()
		for entry in Records.best_days.slice(0, 3):
			var d := int(entry.day)
			_pair(best, "Day %d, %s · %d fake%s caught" % [d, Day.weekday(d), int(entry.caught), "" if int(entry.caught) == 1 else "s"],
				"+" + Market.format_money(entry.profit), Pal.GOOD)
	_spacer()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	_button(row, "Achievements (%d/%d)" % [Records.earned.size(), Records.ACHIEVEMENTS.size()], "PrimaryButton", show_achievements)


func _build_achievements() -> void:
	_clear()
	_title("Achievements")
	_text("%d of %d earned. Hover one to see how to earn it." % [Records.earned.size(), Records.ACHIEVEMENTS.size()], Pal.INK_DIM)
	_gap()
	var grid := _grid()
	for id in Records.ACHIEVEMENTS:
		var a: Dictionary = Records.ACHIEVEMENTS[id]
		var done := Records.is_earned(id)
		var label := _cell(grid, ("★ " if done else "☆ ") + a.name, Pal.GOLD if done else Pal.INK_FAINT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		var desc: String = a.desc
		if done:
			desc += " Earned on day %d." % Records.earned[id]
		else:
			desc += " %d%% there." % floori(Records.progress_of(id) * 100.0)
		label.tooltip_text = desc
		label.mouse_entered.connect(func():
			if _hint:
				_hint.text = desc)
	_spacer()
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 17)
	var row := HBoxContainer.new()
	_box.add_child(row)
	_button(row, "Back", "Button", show_ledger)


# ---------------------------------------------------------------- summary

func _build_summary(report: Dictionary) -> void:
	_clear()
	var stats: Dictionary = report.get("stats", {})
	_title("Day %d closed" % report.get("day", Shop.day))
	# a busy day can fill more lines than the panel holds: they scroll, and the
	# button stays in reach
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var outer := _box
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var grid := _grid()
	_pair(grid, "Bought from customers", Market.format_money(stats.get("bought", 0.0)))
	_pair(grid, "Sold to customers", Market.format_money(stats.get("sold", 0.0)))
	var profit: float = stats.get("profit", 0.0)
	_pair(grid, "Profit on sales", Market.format_money(profit), Pal.GOOD if profit >= 0.0 else Pal.BAD)
	_pair(grid, "Fakes caught / missed", "%d / %d" % [int(stats.get("caught", 0)), int(stats.get("scammed", 0))])
	for entry in _grouped(report.get("ledger", [])):
		var usd: float = entry.usd
		_pair(grid, entry.label, ("+" if usd > 0.0 else "") + Market.format_money(usd), Pal.GOOD if usd > 0.0 else Pal.BAD)
	var cash_change: float = report.get("cash_change", 0.0)
	_pair(grid, "Cash change today", ("+" if cash_change > 0.0 else "") + Market.format_money(cash_change), Pal.GOOD if cash_change >= 0.0 else Pal.BAD)
	_pair(grid, "Net worth at today's prices", Market.format_money(Shop.net_worth()), Pal.GOLD)
	for line in report.get("lines", []):
		_text(str(line), Pal.WARN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bills_in: int = report.get("next_bills_in", 0)
	_text("Next rent and insurance in %d day%s." % [bills_in, "" if bills_in == 1 else "s"], Pal.INK_FAINT)
	for l in _box.get_children():
		if l is Label:
			l.custom_minimum_size.x = 0.0 # the scroll bar takes some of the width
	_box = outer
	var row := HBoxContainer.new()
	_box.add_child(row)
	var go := _button(row, "Lock up and go home", "PrimaryButton", func(): next_day_requested.emit())
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Today's ledger with repeated entries (one per refined piece, say) added up into one line.
func _grouped(ledger: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := {}
	for entry in ledger:
		var label := String(entry.label)
		if at.has(label):
			var e: Dictionary = out[at[label]]
			e.usd += float(entry.usd)
			e.count += 1
		else:
			at[label] = out.size()
			out.append({"label": label, "usd": float(entry.usd), "count": 1})
	for e in out:
		if e.count > 1:
			e.label = "%s (×%d)" % [e.label, e.count]
	return out


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
