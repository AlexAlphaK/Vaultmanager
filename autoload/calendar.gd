extends Node
## The town's year: four seasons of two weeks each, and the town event each one brings.
##   Spring  tax season: folks sell metal to pay the taxman, then Tax Day takes its cut
##           of your own profit since the last one, after bills and spending (so upgrades
##           bought before Tax Day cut the bill).
##   Summer  gold fever week: the town's Prospector Days festival, and everyone wants gold.
##   Autumn  the town coin show on the second weekend: collectors everywhere. Book a booth
##           in the morning and even more of them come, paying more.
##   Winter  the holiday gift rush: shoppers buy small coins as presents and pay well.
## Seasons also nudge how busy the street is (sunny summer, cold winter). Day 1 of a new
## game is the first Monday of spring; the year starts again every YEAR_DAYS days.
## Town event customers come through shop._spawn like a market event's (see MarketEvents),
## only for the whole day. The morning panel shows what is on and what is coming.
## Debug builds: press F10 in the morning to skip ahead to the next town event.

signal changed

const SEASON_DAYS := 14
const YEAR_DAYS := SEASON_DAYS * 4
## `traffic` multiplies how fast customers arrive; `outside` is the window view.
const SEASONS: Array[Dictionary] = [
	{"id": "spring", "name": "Spring", "traffic": 1.0},
	{"id": "summer", "name": "Summer", "traffic": 1.06},
	{"id": "autumn", "name": "Autumn", "traffic": 1.0},
	{"id": "winter", "name": "Winter", "traffic": 0.92},
]
## Town events, on days `from`-`to` of their season. The customer keys work like a
## market event's (see MarketEvents.EVENTS): kind, metal ("" keeps the usual mix), share
## (odds a new customer comes for the event), spawn (arrival gap factor), reserve, premium,
## qty and lines. Also: seller_share (that share of them sell instead, saying
## seller_lines), short (the morning panel's one-line tip), archetype (who they are, see Customers), rush (customers waiting at the
## door when you open), tax (Tax Day is the last day) and booth (a booth can be booked:
## booth_bonus replaces those keys while it is).
const EVENTS: Array[Dictionary] = [
	{"id": "tax_season", "season": "spring", "from": 8, "to": 11, "name": "Tax season", "mood": "bad",
		"banner": "TAX SEASON: the town is selling metal to pay the taxman. Tax Day is {last}.",
		"hint": "Sellers want cash for their tax bills. Keep cash in the safe.",
		"short": "tax of about {tax} due {tax_day}.",
		"kind": "seller", "metal": "", "share": 0.35, "spawn": 0.85, "reserve": -0.03, "qty": 1.3, "rush": 1, "tax": true,
		"lines": ["The taxman wants his cut. These have to go.", "Owe more than I thought this year. Cash, please.",
			"My accountant says sell. So I'm selling."]},
	{"id": "gold_fever", "season": "summer", "from": 1, "to": 7, "name": "Gold fever week", "mood": "good",
		"banner": "GOLD FEVER: Prospector Days are on and the whole town wants gold.",
		"hint": "Gold buyers pay more all week. Stock up on gold coins.",
		"short": "gold buyers pay more.",
		"kind": "buyer", "seller_share": 0.3, "metal": "XAU", "share": 0.45, "spawn": 0.8, "premium": 0.04, "rush": 2,
		"lines": ["Prospector Days! I want real gold, not the fudge kind.", "Gold fever, they call it. I've caught it.",
			"Saw the parade. Now I want a gold coin of my own."],
		"seller_lines": ["Panned this lot at the festival. Well, my grandpa did.", "Everyone's paying up for gold this week. My turn."]},
	{"id": "coin_show", "season": "autumn", "from": 13, "to": 14, "name": "Town coin show", "mood": "good",
		"banner": "COIN SHOW: collectors from three counties are in town for the weekend.",
		"hint": "Collectors pay well for exact coins and rare ones. A booth brings more of them.",
		"short": "collectors pay well.",
		"kind": "buyer", "archetype": "collector", "share": 0.4, "spawn": 0.85, "premium": 0.0, "rush": 2, "booth": true,
		"booth_bonus": {"share": 0.6, "spawn": 0.65, "premium": 0.04, "rush": 3},
		"lines": ["In town for the show. What have you got?"]},
	{"id": "gift_rush", "season": "winter", "from": 6, "to": 12, "name": "Holiday gift rush", "mood": "good",
		"banner": "HOLIDAY RUSH: shoppers want coins to give as gifts, and they pay for the wrapping.",
		"hint": "Gift buyers want small coins and pay a good premium. Keep the shelves full.",
		"short": "small gifts sell well.",
		"kind": "buyer", "metal": "", "share": 0.55, "spawn": 0.7, "premium": 0.05, "qty": 0.45, "rush": 2,
		"lines": ["A silver coin for my nephew's stocking, please.", "Something gold for my wife. Not too big, I'm not made of money.",
			"Gift-wrapped, if you can. It's for my mum.", "Last-minute present. You're a lifesaver."]},
]
## Share of your taxable profit (deal profit less every expense) that Tax Day takes.
const TAX_RATE := 0.1
## A booth at the coin show, times the deal size.
const BOOTH_COST := 1500.0
const BOOTH_REPUTATION := 0.05

## Deal profit less expenses (bills, wages, upgrades, losses) of the days closed since
## the last Tax Day. A loss carries over.
var taxable := 0.0
## Start day of the coin show you have a booth at, or 0.
var booth_day := 0
var booths := 0
## Event customers served in the event's current run, and the best run of each event.
var served := {}
var best := {}

var _by_id := {}
var _report_lines: Array[String] = []


func _ready() -> void:
	for e in EVENTS:
		_by_id[e.id] = e
	reset()
	SaveGame.register("calendar", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_on_day_started)
	Day.shop_closed.connect(_on_shop_closed)
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	taxable = 0.0
	booth_day = 0
	booths = 0
	served = {}
	best = {}
	_report_lines.clear()
	changed.emit()


# ---------------------------------------------------------------- the calendar

func season_index(day := Shop.day) -> int:
	return ((day - 1) / SEASON_DAYS) % SEASONS.size()


func season(day := Shop.day) -> Dictionary:
	return SEASONS[season_index(day)]


## 1 on the first day of a season, SEASON_DAYS on the last.
func day_of_season(day := Shop.day) -> int:
	return (day - 1) % SEASON_DAYS + 1


func year(day := Shop.day) -> int:
	return (day - 1) / YEAR_DAYS + 1


## "Spring, day 9 of 14".
func label(day := Shop.day) -> String:
	return tr("%s, day %d of %d") % [tr(season(day).name), day_of_season(day), SEASON_DAYS]


## The town event on `day`, or {}.
func event_on(day := Shop.day) -> Dictionary:
	var s: String = season(day).id
	var d := day_of_season(day)
	for e in EVENTS:
		if e.season == s and d >= int(e.from) and d <= int(e.to):
			return e
	return {}


## The town event running today, once the tutorial is done; {} on a normal day.
func today() -> Dictionary:
	return event_on(Shop.day) if Tutorial.first_day_done else {}


func is_town_event(id: String) -> bool:
	return _by_id.has(id)


## First and last day of the run of event `e` that includes or follows `day`.
func first_day(e: Dictionary, day := Shop.day) -> int:
	var d := day
	if event_on(d).get("id", "") == e.id:
		while event_on(d - 1).get("id", "") == e.id:
			d -= 1
		return d
	for n in YEAR_DAYS:
		if event_on(day + n).get("id", "") == e.id:
			return day + n
	return day


func last_day(e: Dictionary, day := Shop.day) -> int:
	var d := first_day(e, day)
	while event_on(d + 1).get("id", "") == e.id:
		d += 1
	return d


## The next town event starting after today: {"event", "day"} (its first day), or {}.
func next_event(day := Shop.day) -> Dictionary:
	var current: String = event_on(day).get("id", "")
	for n in range(1, YEAR_DAYS + 1):
		var e := event_on(day + n)
		if not e.is_empty() and e.id != current:
			return {"event": e, "day": day + n}
		if e.is_empty():
			current = ""
	return {}


## Days from today, as a word: "today", "tomorrow" or the weekday with the count.
func when(day: int) -> String:
	var n := day - Shop.day
	if n <= 0:
		return tr("today")
	if n == 1:
		return tr("tomorrow")
	return tr("%s (in %d days)") % [Day.weekday(day), n]


## The morning panel's line about event `e`, which runs today or starts on `day`:
## "Gold fever week, 5 more days: gold buyers pay more." Fits on one line.
func morning_line(e: Dictionary, day := Shop.day) -> String:
	var when := ""
	if day > Shop.day:
		when = tr("tomorrow") if day == Shop.day + 1 else tr("on %s") % Day.weekday(day)
	else:
		var left := last_day(e) - Shop.day
		when = tr("last day") if left == 0 else tr_n("%d more day", "%d more days", left) % left
	var tax_day := last_day(e, day)
	var tip := tr(e.short).format({"tax": Market.format_money(tax_due()),
		"tax_day": tr("tonight") if tax_day == Shop.day else Day.weekday(tax_day)})
	return "%s %s: %s" % [tr(e.name), when, tip] if day > Shop.day else "%s, %s: %s" % [tr(e.name), when, tip]


## The event's banner line with its dates filled in.
func banner(e: Dictionary) -> String:
	var last := last_day(e)
	return tr(e.banner).format({"last": tr("today") if last == Shop.day else Day.weekday(last)})


# ---------------------------------------------------------------- customers

## The event a newly arriving customer comes for, or {} for an everyday customer.
## Shaped like a market event, with the kind decided and a booth's bonus applied.
func customer_event(rng: RandomNumberGenerator) -> Dictionary:
	var e := _dressed(today())
	if e.is_empty() or rng.randf() >= float(e.share):
		return {}
	if rng.randf() < float(e.get("seller_share", 0.0)):
		e.kind = "seller"
		e.lines = e.get("seller_lines", e.lines)
	return e


## Multiplies the gap between customers: the season's weather and today's event.
func spawn_factor() -> float:
	var e := _dressed(today())
	return float(e.get("spawn", 1.0)) / float(season().traffic)


## Customers already waiting at the door when the shop opens on an event day.
func opening_rush() -> int:
	return int(_dressed(today()).get("rush", 0))


## Counts the event customers you served.
func on_leave(c: Customer) -> void:
	if c.dealt and is_town_event(c.event_id):
		served[c.event_id] = int(served.get(c.event_id, 0)) + 1
		best[c.event_id] = maxi(int(best.get(c.event_id, 0)), int(served[c.event_id]))


## Most event customers served in one run of event `id`.
func best_of(id: String) -> int:
	return int(best.get(id, 0))


func _dressed(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {}
	var out := e.duplicate()
	if has_booth(e):
		out.merge(e.booth_bonus, true)
	return out


# ---------------------------------------------------------------- coin show booth

func booth_cost() -> float:
	return roundf(BOOTH_COST * Progress.deal_size() / 50.0) * 50.0


## The coin show you can book a booth for this morning (today's or tomorrow's), or {}.
func booth_event() -> Dictionary:
	for d in [Shop.day, Shop.day + 1]:
		var e := event_on(d)
		if e.get("booth", false) and Tutorial.first_day_done:
			return e
	return {}


func has_booth(e: Dictionary) -> bool:
	return not e.is_empty() and e.get("booth", false) and booth_day == first_day(e)


func can_book_booth() -> bool:
	var e := booth_event()
	return not e.is_empty() and not has_booth(e) and Day.phase == Day.MORNING and Shop.cash >= booth_cost()


func book_booth() -> bool:
	if not can_book_booth():
		return false
	var e := booth_event()
	Day.add_expense(tr("Coin show booth"), booth_cost())
	booth_day = first_day(e)
	booths += 1
	Shop.adjust_reputation(BOOTH_REPUTATION)
	Shop.note("booths")
	Shop.log_event(tr("You booked a booth at the coin show. Collectors will find you."), "good")
	changed.emit()
	return true


# ---------------------------------------------------------------- Tax Day

## The next Tax Day from `day` on: {"day", "usd"} at today's taxable profit.
func next_tax(day := Shop.day) -> Dictionary:
	for e in EVENTS:
		if e.get("tax", false):
			return {"day": last_day(e, day), "usd": tax_due()}
	return {}


func tax_due() -> float:
	return maxf(0.0, taxable) * TAX_RATE


func _on_shop_closed(day: int) -> void:
	var e := event_on(day)
	if not e.get("tax", false) or last_day(e, day) != day or not Tutorial.first_day_done:
		return
	var due := tax_due()
	if due >= 1.0:
		Day.add_expense(tr("Tax Day"), due)
		_report_lines.append(tr("Tax Day: you paid %s, %d%% of your %s profit (after costs) since the last one.") % [
			Market.format_money(due), roundi(TAX_RATE * 100.0), Market.format_money(taxable)])
	else:
		_report_lines.append(tr("Tax Day: no profit since the last one, so no tax to pay."))
	taxable = 0.0


# ---------------------------------------------------------------- days

func _on_day_started(day: int) -> void:
	var e := event_on(day)
	if not e.is_empty() and first_day(e, day) == day:
		served[e.id] = 0
	changed.emit()


## The summary: tonight's tax, how the event went, and what tomorrow brings.
func _on_day_ended(day: int, report: Dictionary) -> void:
	taxable += float(report.get("stats", {}).get("profit", 0.0))
	for entry in report.get("ledger", []):
		if float(entry.usd) < 0.0 and entry.label != tr("Tax Day"):
			taxable += float(entry.usd)
	report.lines.append_array(_report_lines)
	_report_lines.clear()
	if not Tutorial.first_day_done:
		return
	var e := event_on(day)
	if not e.is_empty() and last_day(e, day) == day:
		var n := int(served.get(e.id, 0))
		report.lines.append(tr("%s is over. You served %d of its customers.") % [tr(e.name), n])
	var next := event_on(day + 1)
	if not next.is_empty() and next.get("id", "") != e.get("id", ""):
		report.lines.append(tr("Tomorrow: %s. %s") % [tr(next.name), tr(next.hint)])
	if day_of_season(day) == SEASON_DAYS:
		report.lines.append(tr("%s is over. %s starts tomorrow.") % [tr(season(day).name), tr(season(day + 1).name)])


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F10 and Day.phase == Day.MORNING:
		var next := next_event()
		if next.is_empty():
			return
		Shop.day = int(next.day)
		Day.begin_day()
		Shop.changed.emit()
		Shop.log_event(tr("Debug: skipped ahead to day %d, %s.") % [Shop.day, String(next.event.name).to_lower()])
		get_viewport().set_input_as_handled()


func to_dict() -> Dictionary:
	return {"taxable": taxable, "booth_day": booth_day, "booths": booths, "served": served, "best": best}


func from_dict(d: Dictionary) -> void:
	taxable = float(d.get("taxable", 0.0))
	booth_day = int(d.get("booth_day", 0))
	booths = int(d.get("booths", 0))
	served = d.get("served", {})
	best = d.get("best", {})
	changed.emit()
