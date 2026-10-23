class_name DayPanels
extends PanelContainer
## The panels over the shop floor between shop hours: the morning briefing, the
## upgrades, staff and expansion page, the floor plan where rooms are built, the town
## map with the rival shops, the staff and how they are getting on, the collectors' special orders, the story's chapter and goals,
## the angel investor's offer and stake, the bank's credit line and loans, the ledger of records and achievements, and the end-of-day summary. Rebuilt each time one opens.

signal open_requested
signal next_day_requested
signal new_game_requested
signal desk_requested
signal smelter_requested
signal decorate_requested
signal auction_requested

const AREA := Rect2(12, 18, 292, 208)
const METAL_NAMES := {"XAU": "Gold", "XAG": "Silver", "XPT": "Platinum", "XPD": "Palladium"}

var page := "" # "morning", "upgrades", "staff", "plan", "wholesale", "town", "orders", "story", "investor", "bank", "ledger", "achievements", "summary" or "" when hidden
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
	Calendar.changed.connect(_refresh_page)
	Story.changed.connect(_refresh_page)
	Investor.changed.connect(_refresh_page)
	Bank.changed.connect(_refresh_page)


func hide_panel() -> void:
	page = ""
	visible = false


func show_morning() -> void:
	_confirm_new = false
	# a fresh offer from the investor comes first, once a morning
	if Investor.has_offer() and not Investor.offer_seen:
		Investor.offer_seen = true
		show_investor()
		return
	page = "morning"
	_build_morning()


func show_upgrades() -> void:
	page = "upgrades"
	_build_upgrades()


func show_staff() -> void:
	page = "staff"
	_build_staff()


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


func show_story() -> void:
	Story.mark_read()
	page = "story"
	_build_story()


func show_investor() -> void:
	page = "investor"
	_build_investor()


func show_bank() -> void:
	page = "bank"
	_build_bank()


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
	elif page == "staff":
		_build_staff()
	elif page == "plan":
		_build_plan()
	elif page == "wholesale":
		_build_wholesale()
	elif page == "town":
		_build_town()
	elif page == "orders":
		_build_orders()
	elif page == "story":
		_build_story()
	elif page == "investor":
		_build_investor()
	elif page == "bank":
		_build_bank()
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
	_title(tr("%s, day %d") % [Day.weekday(), Shop.day])
	# a busy morning (and the longer languages) can hold more lines than the panel: they
	# scroll, and the buttons stay on screen
	var outer := _begin_scroll()
	_text(tr("%s · %s. Set your prices, then open up.") % [Progress.tier_name(), Calendar.label()], Pal.INK_DIM)
	var town := _town_hint()
	if town != "":
		_text(town, Pal.GOLD)
	else:
		_text(_market_hint(), Pal.INK)
	_text(RushHours.summary(Shop.day), Pal.WARN)
	var staff := Staff.morning_line()
	if staff != "":
		_text(staff, Pal.WARN)
	var angel := Investor.morning_line()
	if angel != "":
		_text(angel, Pal.GOLD if Investor.has_offer() else Pal.INK_DIM)
	if not Orders.open.is_empty():
		_text(_orders_hint(), Pal.GOLD)
	if not Rivals.news.is_empty():
		# one line, so a busy morning still fits; the town map has the whole story
		var rivals := _text(tr("Town: ") + Rivals.news[0], Pal.WARN)
		rivals.clip_text = true
		rivals.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	if Story.synced and not Story.is_finished():
		_text(tr("%s · %d/%d goals") % [Story.chapter_title(), Story.goals_met_count(), Story.current().goals.size()], Pal.GOLD)
	_gap()
	# the bank's button sits by the bills: the button rows below are full
	var bills := HBoxContainer.new()
	_box.add_child(bills)
	var heading := _heading("BILLS")
	heading.reparent(bills)
	heading.custom_minimum_size.x = 0.0
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bank := _button(bills, tr("Bank") + (" !" if Shop.cash < 0.0 else ""), "Button", show_bank)
	bank.tooltip_text = "Your credit line, bank loans and credit rating."
	bank.custom_minimum_size.y = 0.0 # no taller than the heading
	var grid := _grid()
	# the bank's payments share the upkeep's row: a busy morning has no room for another
	if Bank.due_tonight() > 0.0:
		_pair(grid, "Upkeep and bank payments tonight", Market.format_money(Progress.daily_upkeep() + Bank.due_tonight()))
	else:
		_pair(grid, "Upkeep tonight", Market.format_money(Progress.daily_upkeep()))
	if not Staff.hired.is_empty():
		_pair(grid, "Staff wages tonight", Market.format_money(Staff.daily_wages()))
	var weekly := 0.0
	for bill in Day.upcoming_bills():
		weekly += bill.usd
	var due := Day.days_until_bills()
	# when they fall due shares the row, so the bank's row doesn't push the buttons down
	var when := tr("tonight") if due == 0 else tr_n("%s (in %d day)", "%s (in %d days)", due) % [Day.weekday(Shop.day + due), due]
	_pair(grid, "Rent and insurance", tr("%s, %s") % [Market.format_money(weekly), when], Pal.BAD if due == 0 else Pal.INK)
	_gap()
	if Progress.goal_reached():
		_heading("YOU RUN THE BIGGEST STORE IN TOWN")
		_text("Keep growing your vault and reputation.", Pal.INK_DIM)
	else:
		var next := Progress.tier_info(Progress.tier + 1)
		_heading(tr("NEXT: %s") % tr(next.name).to_upper())
		var req := _grid()
		_requirement(req, "Net worth", Shop.net_worth(), next.need_worth, true)
		_requirement(req, "Reputation", Shop.reputation, next.need_rep, false)
		_requirement(req, "Cash to move", Shop.cash, next.cost, true)
	_end_scroll(outer)
	# the button rows flow onto a second line when a full morning (or a long translation) runs out of width
	var pages := HFlowContainer.new()
	pages.add_theme_constant_override("h_separation", 4)
	pages.add_theme_constant_override("v_separation", 3)
	_box.add_child(pages)
	var count := Progress.available_upgrades().size() + Staff.ROLES.size() - Staff.hired.size()
	var expand_ready := Progress.expand_blocker() == "" and not Progress.is_top_tier()
	_button(pages, tr("Upgrades (%d)%s") % [count, " !" if expand_ready else ""], "Button", show_upgrades)
	if not Staff.hired.is_empty():
		_button(pages, tr("Staff%s") % (" !" if not Staff.raise_requests().is_empty() else ""), "Button", show_staff).tooltip_text = "How your staff are getting on: levels, mood and pay."
	_button(pages, "Restock", "Button", show_wholesale).tooltip_text = "Buy coins from the wholesaler before you open."
	_button(pages, tr("Town map%s") % (" !" if not Rivals.news.is_empty() or AuctionHouse.available() else ""), "Button", show_town).tooltip_text = "The rival shops, their prices and what they are up to."
	if not Orders.open.is_empty():
		_button(pages, tr("Orders (%d)") % Orders.open.size(), "Button", show_orders).tooltip_text = "Collectors' special orders and the dealer network."
	# the investor's page hangs off the ledger: the morning rows are full
	_button(pages, tr("Ledger") + (" !" if Investor.has_offer() else ""), "Button", show_ledger)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 3)
	_box.add_child(row)
	open_button = _button(row, "Open the shop", "PrimaryButton", func(): open_requested.emit())
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Progress.has_upgrade("trading_desk"):
		var desk := _button(row, "Trading desk", "Button", func(): desk_requested.emit())
		desk.disabled = not DeskSession.available()
		desk.tooltip_text = "Trade at the desk this morning." if not desk.disabled else tr("The desk has traded today. Back tomorrow morning.")
	if ScrapYard.owned():
		var fresh := ScrapYard.offers.size() > 0 or not ScrapYard.bin.is_empty()
		_button(row, tr("Smelter") + (" !" if fresh else ""), "Button", func(): smelter_requested.emit()).tooltip_text = \
			"Buy the scrap dealer's lots and melt scrap into bars."
	var show := Calendar.booth_event()
	if not show.is_empty():
		var booked := Calendar.has_booth(show)
		var booth := _button(row, tr("Booth booked") if booked else tr("Booth ") + Market.format_money(Calendar.booth_cost()),
			"Button" if booked else "PrimaryButton", func(): Calendar.book_booth())
		booth.disabled = not Calendar.can_book_booth()
		booth.tooltip_text = tr("Your table at the coin show %s.") % Calendar.when(Calendar.first_day(show)) if booked \
			else tr("Book a table at the coin show: more collectors come, and they pay more.")
	_button(row, tr("Story") + ("!" if Story.has_new_letter() else ""), "Button", show_story).tooltip_text = "Mags's goals for this chapter of the story."
	_button(row, tr("Sure? Click again") if _confirm_new else tr("New game"), "DangerButton", _on_new_game)


## Today's town event, or one coming in the next few days, for the morning briefing.
func _town_hint() -> String:
	var e := Calendar.today()
	if not e.is_empty():
		return Calendar.morning_line(e)
	if AuctionHouse.available():
		return tr("Auction day at %s: %d lots. Go from the Town map.") % [AuctionHouse.NAME, AuctionHouse.lots.size()]
	var next := Calendar.next_event()
	if Tutorial.first_day_done and not next.is_empty() and int(next.day) - Shop.day <= 3:
		return Calendar.morning_line(next.event, int(next.day))
	return ""


## The order due soonest, for the morning briefing.
func _orders_hint() -> String:
	var next: Dictionary = Orders.open[0]
	for o in Orders.open:
		if int(o.due) < int(next.due):
			next = o
	var have := Orders.have_for(next)
	var when := tr("today") if Orders.days_left(next) <= 0 else Day.weekday(int(next.due))
	return tr("%s wants %d × %s %s. You hold %d.") % [next.name, next.qty, Orders.item_of(next).display_name, when, have]


func _market_hint() -> String:
	var best := ""
	var best_change := 0.0
	for metal in ["XAU", "XAG", "XPT"]:
		var change := Market.day_change_percent(metal)
		if absf(change) > absf(best_change):
			best = metal
			best_change = change
	if best == "" or absf(best_change) < 0.3:
		return tr("Metals are calm this morning. Expect a normal day.")
	if best_change > 0.0:
		return tr("%s is up %.1f%%. Expect more sellers cashing in.") % [tr(METAL_NAMES[best]), best_change]
	return tr("%s is down %.1f%%. Bargain hunters will be out.") % [tr(METAL_NAMES[best]), absf(best_change)]


func _requirement(grid: GridContainer, caption: String, have: float, need: float, money: bool) -> void:
	var ok := have >= need
	var fmt := func(v): return Market.format_money(v) if money else tr("%.1f stars") % v
	_pair(grid, ("● " if ok else "○ ") + tr(caption), "%s / %s" % [fmt.call(have), fmt.call(need)], Pal.GOOD if ok else Pal.INK)


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
	_text(tr("Cash %s. Hover an upgrade to see what it does.") % Market.format_money(Shop.cash), Pal.INK_DIM)
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
		_upgrade_row(grid, tr("Move to %s") % tr(next.name), next.cost, blocker == "", "Move",
			tr("Rent %s a week. More customers, bigger deals and more upgrades. %s") % [Market.format_money(next.rent), blocker],
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
		var desc := tr("%s Wage %s a day.") % [tr(role.desc), Market.format_money(Staff.wage(id))]
		if Staff.has(id):
			_upgrade_row(grid, tr("%s, %s (level %d)") % [role.name, tr(role.title.to_lower()), Staff.level(id)], -1.0, true, "Staff", desc, show_staff, Pal.GOOD)
		elif int(role.tier) <= Progress.tier:
			_upgrade_row(grid, tr("Hire a %s") % tr(role.title.to_lower()), role.fee, Staff.can_hire(id), "Hire", desc, func(): Staff.hire(id))
	var locked := Progress.locked_upgrade_count()
	if locked > 0:
		_text(tr_n("%d more upgrade unlocks as the shop grows.", "%d more upgrades unlock as the shop grows.", locked) % locked, Pal.INK_FAINT)
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 17)
	if Demo.tier_locked(Progress.tier + 1):
		_hint.text = tr("The %s opens in the full game. Wishlist it on Steam!") % tr(Progress.tier_info(Progress.tier + 1).name)
	elif not Progress.is_top_tier() and Progress.expand_blocker() != "":
		_hint.text = tr("%s to move up.") % Progress.expand_blocker()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	if not Staff.hired.is_empty():
		_button(row, "Staff", "Button", show_staff)
	var rooms := Progress.available_upgrades("room").size()
	_button(row, tr("Floor plan%s") % (tr(" (%d to build)") % rooms if rooms > 0 else ""), "Button", show_plan)
	_button(row, "Decorate", "Button", func(): decorate_requested.emit()).tooltip_text = \
		"Place plants, display cases and signs on the shop floor. A handsome shop earns more stars."


# ---------------------------------------------------------------- staff

func _build_staff() -> void:
	_clear()
	_title("Staff")
	_text(tr("Wages tonight %s. Pay staff what their level is worth.") % Market.format_money(Staff.daily_wages()), Pal.INK_DIM)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# the helpers add to _box, so point it at the list while the rows go in
	var outer := _box
	_box = list
	for id in Staff.ROLES:
		var role: Dictionary = Staff.ROLES[id]
		if not Staff.has(id):
			if int(role.tier) <= Progress.tier:
				var hire := _grid(3)
				_upgrade_row(hire, tr("Hire a %s") % tr(role.title.to_lower()), role.fee, Staff.can_hire(id), "Hire",
					tr("%s Wage %s a day.") % [tr(role.desc), Market.format_money(Staff.wage(id))], func(): Staff.hire(id))
			continue
		_staff_card(id)
	_box = outer
	# leave room for the scroll bar
	for child in list.get_children():
		if child is Label:
			child.custom_minimum_size.x = AREA.size.x - 26
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	_button(row, "Upgrades", "Button", show_upgrades)


func _staff_card(id: String) -> void:
	var role: Dictionary = Staff.ROLES[id]
	var p := Staff.info(id)
	_heading("%s, %s · %s" % [role.name.to_upper(), tr(role.title).to_upper(), tr(Staff.level_name(id)).to_upper()])
	var grid := _grid()
	var next := Staff.xp_to_next(id)
	_pair(grid, tr("Level %d") % Staff.level(id), tr("top level") if next == 0 else tr("%d xp to go") % next, Pal.GOLD)
	var mood := float(p.mood)
	_pair(grid, "Mood", "%s (%d)" % [Staff.mood_word(id), roundi(mood)], Pal.GOOD if mood >= 50.0 else (Pal.WARN if mood >= 25.0 else Pal.BAD))
	var owed := Staff.raises_owed(id)
	_pair(grid, "Wage", tr("%s a day%s") % [Market.format_money(Staff.wage(id)), "" if owed == 0 else tr(" (fair: %s)") % Market.format_money(Staff.fair_wage(id))],
		Pal.INK if owed == 0 else Pal.WARN)
	var today: String = {"sick": "Off sick (unpaid)", "grumpy": "In a foul mood"}.get(str(p.today), "At work")
	_pair(grid, "Today", tr(today), Pal.INK if str(p.today) == "" else Pal.BAD)
	_text(_skill_line(id), Pal.INK_DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(p.asking):
		var raise := Staff.wage(id) * Staff.RAISE / (1.0 + Staff.RAISE * int(p.raises))
		_text(tr("%s asks for a raise of %s a day.") % [role.name, Market.format_money(raise)], Pal.WARN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	if bool(p.asking):
		_button(row, "Give the raise", "PrimaryButton", func(): Staff.agree_raise(id))
		_button(row, "Say no", "Button", func(): Staff.refuse_raise(id))
	_button(row, "Let go", "DangerButton", func(): Staff.let_go(id)).tooltip_text = "They leave today. The signing fee is not refunded."
	_gap()


## What this level of skill does for the shop, in a sentence.
func _skill_line(id: String) -> String:
	var lvl := Staff.level(id)
	if id == "clerk":
		var line := tr("Rings up a buyer in %.1f s.") % Staff.clerk_seconds()
		if lvl > 1:
			line += tr(" Talks %d%% of fussy buyers round.") % roundi(float(Staff.SKILL.clerk.persuade) * (lvl - 1) * 100.0)
		return line
	if id == "guard":
		var odds := Security.GUARD_STOP + float(Staff.SKILL.guard.guard_stop) * (lvl - 1)
		return tr("Stops %d%% of robbers at the door.") % roundi(minf(odds, 0.95) * 100.0)
	return ""


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
			desc = "%s. %s" % [tr(u.name), tr(u.desc)]
		"shell":
			b.text = "Build"
			b.theme_type_variation = "PrimaryButton" if Progress.can_buy(id) else "Button"
			b.disabled = not Progress.can_buy(id)
			b.pressed.connect(func(): Progress.buy(id))
			desc = "%s, %s. %s" % [tr(u.name), Market.format_money(u.cost), tr(u.desc)]
		_:
			b.text = "Locked"
			b.disabled = true
			desc = tr("%s: the plot next door opens when you move to the %s. %s") % [tr(u.name), Progress.tier_name(int(u.tier)), tr(u.desc)]
	b.tooltip_text = desc
	list.add_child(b)
	var hover := func():
		if is_instance_valid(_hint):
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
		if is_instance_valid(_hint):
			_hint.text = desc
	b.mouse_entered.connect(hover)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.mouse_entered.connect(hover)


# ---------------------------------------------------------------- wholesaler

func _build_wholesale() -> void:
	_clear()
	_title("Morning wholesaler")
	_text(tr("Coins at spot plus %d%%, delivered before you open. Cash %s.") % [roundi(Wholesaler.markup() * 100.0),
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
			b.tooltip_text = tr("Buy %d for %s.") % [qty, Market.format_money(Wholesaler.price(item) * qty)]
			b.pressed.connect(func(): Wholesaler.buy(item, qty))
			grid.add_child(b)
	if Wholesaler.bought_today > 0.0:
		_text(tr("Bought this morning: %s.") % Market.format_money(Wholesaler.bought_today), Pal.GOOD)
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
		_text(tr("A quiet morning on Main Street. Your share of the town's customers: %d%%.") % roundi(Rivals.overall_share() * 100.0),
			Pal.INK_DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spacer()
	_hint = _text("", Pal.INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if AuctionHouse.available():
		var sale := HBoxContainer.new()
		sale.add_theme_constant_override("separation", 4)
		_box.add_child(sale)
		_town_button(sale, tr("Auction: %d lots") % AuctionHouse.lots.size(), true, func(): auction_requested.emit(),
			tr("%s's sale is this morning: estates, rare coins and dealer stock. Bid against Sterling and the collectors.") % AuctionHouse.NAME)
	else:
		_text(tr("%s's next sale: %s.") % [AuctionHouse.NAME, Day.weekday(AuctionHouse.next_sale_day(Shop.day + (1 if AuctionHouse.held_day == Shop.day else 0)))],
			Pal.INK_FAINT)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_box.add_child(buttons)
	_button(buttons, "Back", "Button", show_morning)
	var ad := tr_n("Ad runs %d more day", "Ad runs %d more days", Rivals.ad_days) % Rivals.ad_days if Rivals.ad_days > 0 \
		else tr("Newspaper ad %s") % Market.format_money(Rivals.ad_cost())
	_town_button(buttons, ad, Rivals.can_run_ad(), func(): Rivals.run_ad(),
		tr("An ad in the town paper: for %d days more customers pick your shop over the others.") % Rivals.AD_DAYS)
	_town_button(buttons, "Beat Sterling", true, func(): Rivals.beat_sterling(),
		tr("Set your board a point better than Sterling's: pay %d%% of melt, sell at spot +%d%%.") % [
			roundi(minf(1.0, Rivals.buy_of("sterling") + 0.01) * 100.0), roundi(maxf(0.0, Rivals.premium_of("sterling") - 0.01) * 100.0)])
	if Rivals.can_tip_off():
		_town_button(buttons, "Tip off police", true, func(): Rivals.tip_off(),
			tr("Tell Detective Ruiz about Lucky's stolen goods. A raid shuts the pawn shop for %d days.") % Rivals.RAID_DAYS)


## One shop's line on the town map: its name and place, then stars, prices and worth.
func _shop_card(list: VBoxContainer, id: String, place: int) -> void:
	var you := id == "you"
	var name_label := Label.new()
	name_label.text = "#%d %s" % [place, tr("Your shop") if you else Rivals.name_of(id)]
	name_label.add_theme_color_override("font_color", Pal.GOLD if you else Pal.INK)
	list.add_child(name_label)
	var stars := Shop.reputation if you else Rivals.stars_of(id)
	var pays := Shop.buy_percent if you else Rivals.buy_of(id)
	var premium := Shop.sell_premium if you else Rivals.premium_of(id)
	var info := Label.new()
	if not you and not Rivals.is_open(id):
		info.text = tr_n("Raided: shut %d day", "Raided: shut %d days", int(Rivals.state[id].closed)) % int(Rivals.state[id].closed)
		info.add_theme_color_override("font_color", Pal.BAD)
	else:
		info.text = tr("%.1f★  pays %d%%  +%d%%") % [stars, roundi(pays * 100.0), roundi(premium * 100.0)]
		info.add_theme_color_override("font_color", Pal.INK_DIM)
	list.add_child(info)
	var worth := Label.new()
	worth.text = tr("Worth %s") % Market.format_money(Shop.net_worth() if you else Rivals.worth_of(id))
	worth.add_theme_color_override("font_color", Pal.INK_FAINT)
	list.add_child(worth)


func _town_button(parent: Control, text: String, enabled: bool, on_press: Callable, desc: String) -> void:
	var b := _button(parent, text, "PrimaryButton" if enabled else "Button", on_press)
	b.disabled = not enabled
	b.tooltip_text = desc
	b.mouse_entered.connect(func():
		if is_instance_valid(_hint):
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
		_shrinkable(_cell(grid, o.name, Pal.INK))
		_cell(grid, "%d × %s" % [o.qty, Orders.item_of(o).display_name], Pal.INK)
		_cell(grid, "%d/%d" % [have, o.qty], Pal.GOOD if have >= int(o.qty) else Pal.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cell(grid, "today" if left <= 0 else Day.weekday(int(o.due)).left(3), Pal.BAD if left <= 0 else (Pal.WARN if left == 1 else Pal.INK_DIM))
	var pays := 0.0
	for o in Orders.open:
		pays += Orders.price_of(o)
	_text(tr("Pays %s in all on delivery.") % Market.format_money(pays), Pal.GOLD)
	_gap()
	var wanted := Orders.wanted_rare()
	if not wanted.is_empty():
		_heading("DEALER NETWORK")
		var dealers := _grid(3)
		for item in wanted:
			var left := Orders.dealer_left(item)
			_shrinkable(_cell(dealers, item.display_name, Pal.INK))
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


# ---------------------------------------------------------------- story

func _build_story() -> void:
	_clear()
	if Story.is_finished():
		_title("The end")
		_text("You run the biggest precious metal store in town. Mags tells everyone she taught you all you know, and Victor Sterling buys his scrap from you now.",
			Pal.INK).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_gap()
		_text("Keep trading: the town is yours.", Pal.INK_DIM)
	else:
		var ch := Story.current()
		_title(Story.chapter_title())
		_heading("A NOTE FROM MAGS HOLLOWAY")
		_text(ch.letter, Pal.INK).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_gap()
		_heading("GOALS")
		var grid := _grid()
		for i in ch.goals.size():
			var done := Story.goal_met(i)
			_pair(grid, ("● " if done else "○ ") + tr(ch.goals[i].text), tr("done") if done else Story.goal_count(i), Pal.GOOD if done else Pal.INK)
		var reward := Story.reward_text(ch.reward)
		if reward != "":
			_text(reward + tr(", when Mags drops by."), Pal.GOLD)
	_spacer()
	_heading("CHAPTERS")
	var marks := ""
	for n in Story.CHAPTERS.size():
		marks += ("★" if n < Story.chapter else "☆") + " "
	_text(marks.strip_edges(), Pal.GOLD)
	var row := HBoxContainer.new()
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)


# ---------------------------------------------------------------- investor

func _build_investor() -> void:
	_clear()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if Investor.has_offer():
		_title("An angel investor")
		_text(tr("%s heard the bank is calling. She backs small shops she believes in, and she believes in yours.") % Investor.NAME, Pal.INK)
		_gap()
		var grid := _grid()
		var stake := float(Investor.offer.stake)
		_pair(grid, "She puts in", Market.format_money(stake), Pal.GOOD)
		_pair(grid, "In return", Investor.share_text(float(Investor.offer.share)), Pal.WARN)
		_pair(grid, "Until she has had", Market.format_money(stake * Investor.RETURN))
		_pair(grid, "Cash now", Market.format_money(Shop.cash), Pal.BAD if Shop.cash < 0.0 else Pal.INK)
		_pair(grid, "Tonight's bills", Market.format_money(Investor.bills_tonight()))
		_gap()
		_text("A day without profit costs you nothing. Buy her out any morning for what she is still owed.", Pal.INK_DIM)
		_text("Open the shop without shaking on it and she walks away.", Pal.INK_FAINT)
		_spacer()
		_box.add_child(row)
		_button(row, "Take the money", "PrimaryButton", func():
			Investor.accept()
			show_morning()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(row, "Not now", "Button", show_morning)
		return
	_title(tr("%s's stake") % Investor.NAME)
	if Investor.has_deal():
		var d := Investor.deal
		_text(tr("She bought in on day %d. Her share comes off each day's profit when you lock up.") % int(d.day), Pal.INK_DIM)
		_gap()
		var grid := _grid()
		_pair(grid, "She put in", Market.format_money(float(d.stake)))
		_pair(grid, "Her share", Investor.share_text(float(d.share)), Pal.WARN)
		_pair(grid, "Paid so far", Market.format_money(float(d.paid)))
		_pair(grid, "Still owed", Market.format_money(Investor.owed()), Pal.GOLD)
		_gap()
		_text(tr("She is out once she has had %s. Or buy her out now for what she is still owed.") % Market.format_money(float(d.cap)), Pal.INK_DIM)
	else:
		_text("Nobody holds a stake in your shop.", Pal.INK_DIM)
	_spacer()
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	if Investor.has_deal():
		var out := _button(row, tr("Buy out for %s") % Market.format_money(Investor.owed()), "PrimaryButton", func(): Investor.buy_out())
		out.disabled = not Investor.can_buy_out()
		out.tooltip_text = "Pay her what she is still owed and keep all your profit from now on."


# ---------------------------------------------------------------- bank

func _build_bank() -> void:
	_clear()
	_title("The bank")
	_text(tr("Credit rating %s. Pay on time and the bank lends more, for less.") % Bank.grade(),
		Pal.GOOD if Bank.grade() == "A" else Pal.BAD if Bank.grade() == "D" else Pal.INK_DIM)
	_gap()
	_heading("CREDIT LINE")
	var grid := _grid()
	_pair(grid, "Drawn", tr("%s of %s") % [Market.format_money(Bank.line), Market.format_money(Bank.line_limit())],
		Pal.WARN if Bank.line > 0.0 else Pal.INK)
	_pair(grid, "Interest", Bank.rate_text(Bank.line_rate()), Pal.INK_DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	var take := minf(Bank.step(), Bank.headroom())
	var draw := _button(row, tr("Draw %s") % Market.format_money(take), "Button", func(): Bank.draw(take))
	draw.disabled = not Bank.can_draw(take)
	var back := minf(Bank.step(), Bank.repayable())
	var repay := _button(row, tr("Repay %s") % Market.format_money(back if back > 0.0 else minf(Bank.step(), Bank.line_limit())),
		"Button", func(): Bank.repay(back))
	repay.disabled = not Bank.can_repay(back)
	var cover := _button(row, tr("Cover overdrafts: on") if Bank.auto_cover else tr("Cover overdrafts: off"), "Button", func():
		Bank.auto_cover = not Bank.auto_cover
		_build_bank())
	cover.tooltip_text = "At night the line clears an overdraft, at the line's rate instead of the overdraft's."
	_gap()
	_heading("LOAN")
	if Bank.has_loan():
		var l := Bank.loan
		var lg := _grid()
		_pair(lg, "Left to pay", Market.format_money(float(l.balance)), Pal.GOLD)
		_pair(lg, "Nightly payment", tr_n("%s (%d day left)", "%s (%d days left)", int(l.days_left)) % [
			Market.format_money(Bank.loan_payment()), int(l.days_left)])
		var off := _button(_box, tr("Pay off %s") % Market.format_money(float(l.balance)), "Button", func(): Bank.pay_off())
		off.disabled = not Bank.can_pay_off()
		off.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	elif Bank.offers().is_empty():
		_text("The bank won't lend at a D rating. Stay out of the red to win back its trust.", Pal.INK_FAINT)
	else:
		var offers := _grid(3)
		var list := Bank.offers()
		for i in list.size():
			var o: Dictionary = list[i]
			_shrinkable(_cell(offers, tr("%s over %d days") % [Market.format_money(o.amount), o.term], Pal.INK))
			_cell(offers, tr("%s a night") % Market.format_money(o.payment), Pal.INK_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var b := _button(offers, "Borrow", "Button", func(): Bank.borrow(i))
			b.disabled = not Bank.can_borrow()
	_spacer()
	var bottom := HBoxContainer.new()
	_box.add_child(bottom)
	_button(bottom, "Back", "Button", show_morning)


# ---------------------------------------------------------------- ledger

func _build_ledger() -> void:
	_clear()
	_title("The ledger")
	_text(tr_n("%d day of trading. %d of %d achievements earned.", "%d days of trading. %d of %d achievements earned.", Records.totals.days) % [Records.totals.days,
		Records.earned.size(), Records.ACHIEVEMENTS.size()], Pal.INK_DIM)
	_gap()
	var grid := _grid()
	_pair(grid, "Deals closed (buys / sales)", "%d / %d" % [Records.total("buys"), Records.total("sales")])
	_pair(grid, "Bought from customers", Market.format_money(Records.total("bought")))
	_pair(grid, "Sold to customers", Market.format_money(Records.total("sold")))
	var profit := Records.total("profit")
	_pair(grid, "Lifetime profit", Market.format_money(profit), Pal.GOOD if profit >= 0.0 else Pal.BAD)
	_pair(grid, "Fakes caught / missed", "%d / %d (%d%%)" % [Records.total("caught"), Records.total("scammed"), roundi(Records.catch_rate() * 100.0)])
	if Bank.interest_paid > 0.0:
		_pair(grid, "Interest paid to the bank", Market.format_money(Bank.interest_paid), Pal.WARN)
	if Investor.total_paid > 0.0:
		_pair(grid, "Paid to investors", Market.format_money(Investor.total_paid), Pal.WARN)
	_pair(grid, "Lost to thieves", Market.format_money(Records.total("stolen")), Pal.BAD if Records.total("stolen") > 0.0 else Pal.INK)
	_pair(grid, "Highest net worth", Market.format_money(Records.peaks.worth), Pal.GOLD)
	_pair(grid, "Best reputation", tr("%.1f stars") % Records.peaks.rep)
	_pair(grid, "Profit streak", tr_n("%d day (best %d)", "%d days (best %d)", Records.streak) % [Records.streak, Records.peaks.streak])
	_gap()
	_heading("BEST DAYS")
	if Records.best_days.is_empty():
		_text("Close a day in profit to start the list.", Pal.INK_FAINT)
	else:
		var best := _grid()
		for entry in Records.best_days.slice(0, 3):
			var d := int(entry.day)
			_pair(best, tr_n("Day %d, %s · %d fake caught", "Day %d, %s · %d fakes caught", int(entry.caught)) % [d, Day.weekday(d), int(entry.caught)],
				"+" + Market.format_money(entry.profit), Pal.GOOD)
	_spacer()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_box.add_child(row)
	_button(row, "Back", "Button", show_morning)
	_button(row, tr("Achievements (%d/%d)") % [Records.earned.size(), Records.ACHIEVEMENTS.size()], "PrimaryButton", show_achievements)
	if Investor.has_offer() or Investor.has_deal():
		_button(row, tr("Investor") + (" !" if Investor.has_offer() else ""), "Button", show_investor).tooltip_text = \
			"Celeste Wren, the angel investor: her offer, or her stake in the shop."


func _build_achievements() -> void:
	_clear()
	_title("Achievements")
	_text(tr("%d of %d earned. Hover one to see how to earn it.") % [Records.earned.size(), Records.ACHIEVEMENTS.size()], Pal.INK_DIM)
	_gap()
	# the list outgrows the panel: it scrolls, and Back stays in reach
	var outer := _begin_scroll()
	var grid := _grid()
	for id in Records.ACHIEVEMENTS:
		var a: Dictionary = Records.ACHIEVEMENTS[id]
		var done := Records.is_earned(id)
		var label := _cell(grid, ("★ " if done else "☆ ") + tr(a.name), Pal.GOLD if done else Pal.INK_FAINT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		var desc: String = tr(a.desc)
		if done:
			desc += tr(" Earned on day %d.") % Records.earned[id]
		else:
			desc += tr(" %d%% there.") % floori(Records.progress_of(id) * 100.0)
		label.tooltip_text = desc
		label.mouse_entered.connect(func():
			if is_instance_valid(_hint):
				_hint.text = desc)
	_end_scroll(outer)
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
	_title(tr("Day %d closed") % report.get("day", Shop.day))
	# a busy day can fill more lines than the panel holds: they scroll, and the
	# button stays in reach
	var outer := _begin_scroll()
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
	_text(tr_n("Next rent and insurance in %d day.", "Next rent and insurance in %d days.", bills_in) % bills_in, Pal.INK_FAINT)
	_end_scroll(outer)
	var demo_over := Demo.last_day(int(report.get("day", Shop.day)))
	if demo_over: # outside the scroll, so it is never missed
		_text("That was the last day of the demo. Thanks for playing!", Pal.GOLD)
	var row := HBoxContainer.new()
	_box.add_child(row)
	var go := _button(row, "See how you did" if demo_over else "Lock up and go home", "PrimaryButton", func(): next_day_requested.emit())
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

## Puts what follows in a box that scrolls and takes the panel's spare height, until
## _end_scroll(). Returns the box to go back to.
func _begin_scroll() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var outer := _box
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	return outer


func _end_scroll(outer: VBoxContainer) -> void:
	for l in _box.get_children():
		if l is Label:
			l.custom_minimum_size.x = 0.0 # the scroll bar takes some of the width
	_box = outer


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
	# wrap to whatever width the page gives it, rather than widen the panel: translations
	# run longer than the English, and a scrolling page loses the scroll bar's width
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


## A cell that takes the spare width and cuts its text short rather than push the
## columns after it off the panel (long names, longer translations).
func _shrinkable(l: Label) -> Label:
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


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
