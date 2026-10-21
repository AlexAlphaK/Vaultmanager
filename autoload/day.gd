extends Node
## The shop's calendar: the phases of each day, the week, and the day's ledger of
## bills and other money that is not a counter deal.
##
## Hooks for other systems:
##   phase_changed / day_started / shop_opened / shop_closed / day_ended signals.
##   add_income() and add_expense() put money on today's ledger (and in the summary).
##   day_ended hands out the report before it is shown: append strings to report.lines.

signal phase_changed(phase: String)
signal day_started(day: int)
signal shop_opened(day: int)
signal shop_closed(day: int)
signal day_ended(day: int, report: Dictionary)

## morning: set prices and buy upgrades. open: customers arrive. closing: the last
## customers are served. after_hours: the shop is shut and the summary is up.
const MORNING := "morning"
const OPEN := "open"
const CLOSING := "closing"
const AFTER_HOURS := "after_hours"
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
## Weekly bills are paid when the shop closes on the last day of the week.
const WEEK_DAYS := 7
## Daily interest on a negative cash balance.
const OVERDRAFT_RATE := 0.005

var phase := MORNING
## Today's money that is not a counter deal: {"label": String, "usd": signed USD}.
var ledger: Array[Dictionary] = []
var opening_cash := 0.0
var opening_worth := 0.0


func weekday(day := Shop.day) -> String:
	return WEEKDAYS[(day - 1) % WEEK_DAYS]


func is_bill_day(day := Shop.day) -> bool:
	return day % WEEK_DAYS == 0


## 0 on the day the bills are due.
func days_until_bills(day := Shop.day) -> int:
	return (WEEK_DAYS - day % WEEK_DAYS) % WEEK_DAYS


func is_open() -> bool:
	return phase == OPEN or phase == CLOSING


func add_income(label: String, usd: float) -> void:
	ledger.append({"label": label, "usd": absf(usd)})
	Shop.add_cash(absf(usd))


func add_expense(label: String, usd: float) -> void:
	ledger.append({"label": label, "usd": -absf(usd)})
	Shop.add_cash(-absf(usd))


## The bills the next bill day will bring, at today's vault value.
func upcoming_bills() -> Array[Dictionary]:
	return [
		{"label": "Rent", "usd": Progress.weekly_rent()},
		{"label": "Insurance", "usd": Progress.weekly_insurance()},
	]


## Starts the morning of the current day. Call Shop.next_day() first to move on a day.
func begin_day() -> void:
	ledger.clear()
	opening_cash = Shop.cash
	opening_worth = Shop.net_worth()
	_set_phase(MORNING)
	day_started.emit(Shop.day)


func open_shop() -> void:
	if phase != MORNING:
		return
	_set_phase(OPEN)
	shop_opened.emit(Shop.day)


func close_shop() -> void:
	if phase != OPEN:
		return
	_set_phase(CLOSING)
	shop_closed.emit(Shop.day)


## Pays the day's bills and returns the report for the summary screen:
## {"day", "stats", "ledger", "lines", "cash_change", "worth_change", "next_bills_in"}.
func end_day() -> Dictionary:
	if phase == AFTER_HOURS:
		return {}
	add_expense("Upkeep", Progress.daily_upkeep())
	if is_bill_day():
		for bill in upcoming_bills():
			add_expense(bill.label, bill.usd)
	if Shop.cash < 0.0:
		add_expense("Overdraft interest", -Shop.cash * OVERDRAFT_RATE)
	_set_phase(AFTER_HOURS)
	var report := {
		"day": Shop.day,
		"stats": Shop.stats.duplicate(),
		"ledger": ledger.duplicate(true),
		"lines": [],
		"cash_change": Shop.cash - opening_cash,
		"worth_change": Shop.net_worth() - opening_worth,
		"next_bills_in": days_until_bills(Shop.day + 1) + 1,
	}
	if Shop.cash < 0.0:
		report.lines.append("You are overdrawn. The bank charges interest every night.")
	day_ended.emit(Shop.day, report)
	return report


func reset() -> void:
	ledger.clear()
	phase = MORNING


func _set_phase(value: String) -> void:
	phase = value
	phase_changed.emit(value)
