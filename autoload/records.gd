extends Node
## The shop's long-term ledger: lifetime totals, best days, streaks and achievements.
## Totals are added up from each day's report when the shop closes, so quitting
## mid-day (which replays the day) never counts a deal twice. Achievements that
## depend on a single deal are checked live through Shop.noted.

signal changed
signal unlocked(id: String)

## How many days the history keeps for the ledger.
const HISTORY_DAYS := 60
const BEST_DAYS := 5
## Stats in Shop.stats that total() adds while the shop is trading.
const LIVE_STATS := ["bought", "sold", "profit", "caught", "scammed", "stolen", "robbers_stopped", "orders_filled",
	"bars_cast", "graded_exact"]

## id -> {"name", "desc", "key" (a value from value_of()), "goal"}. Checked in this order.
const ACHIEVEMENTS := {
	"first_sale": {"name": "Open for business", "desc": "Sell coins to your first customer.", "key": "sales", "goal": 1},
	"first_catch": {"name": "Sharp eye", "desc": "Catch your first fake.", "key": "caught", "goal": 1},
	"catch_25": {"name": "Fake finder", "desc": "Catch 25 fakes.", "key": "caught", "goal": 25},
	"catch_100": {"name": "Forger's nightmare", "desc": "Catch 100 fakes.", "key": "caught", "goal": 100},
	"deals_100": {"name": "Busy counter", "desc": "Close 100 deals, buying or selling.", "key": "deals", "goal": 100},
	"deals_500": {"name": "Town institution", "desc": "Close 500 deals, buying or selling.", "key": "deals", "goal": 500},
	"day_5k": {"name": "Good day", "desc": "Make $5,000 profit in one day.", "key": "best_day", "goal": 5000},
	"day_25k": {"name": "Record day", "desc": "Make $25,000 profit in one day.", "key": "best_day", "goal": 25000},
	"profit_100k": {"name": "Six figures", "desc": "Make $100,000 profit in total.", "key": "profit", "goal": 100000},
	"profit_1m": {"name": "Million in the till", "desc": "Make $1,000,000 profit in total.", "key": "profit", "goal": 1000000},
	"worth_100k": {"name": "Well stocked", "desc": "Reach a net worth of $100,000.", "key": "peak_worth", "goal": 100000},
	"worth_1m": {"name": "Millionaire", "desc": "Reach a net worth of $1,000,000.", "key": "peak_worth", "goal": 1000000},
	"stars_4": {"name": "Trusted name", "desc": "Reach 4 stars of reputation.", "key": "peak_rep", "goal": 4.0},
	"stars_5": {"name": "Five-star dealer", "desc": "Reach a full 5 stars.", "key": "peak_rep", "goal": 5.0},
	"streak_7": {"name": "Hot streak", "desc": "Make a profit 7 days in a row.", "key": "best_streak", "goal": 7},
	"clean_week": {"name": "Clean books", "desc": "Go 7 days in a row without buying a fake.", "key": "best_clean", "goal": 7},
	"week_1": {"name": "First week", "desc": "Finish your first week of trading.", "key": "days", "goal": 7},
	"day_100": {"name": "Old hand", "desc": "Trade for 100 days.", "key": "days", "goal": 100},
	"orders_5": {"name": "Collector's friend", "desc": "Fill 5 special orders for collectors.", "key": "orders_filled", "goal": 5},
	"staff_veteran": {"name": "Part of the family", "desc": "Keep someone on staff until they are a veteran (level 5).", "key": "staff_level", "goal": 5},
	"robber_1": {"name": "Not today", "desc": "Stop a robber, with the guard or the panic button.", "key": "robbers_stopped", "goal": 1},
	"tier_1": {"name": "Moving up", "desc": "Move the shop to Main Street.", "key": "tier", "goal": 1},
	"tier_top": {"name": "Biggest in town", "desc": "Open the town landmark store.", "key": "tier", "goal": 3},
	"pass_pawn": {"name": "Bigger than Lucky's", "desc": "End a day worth more than Lucky's Pawn & Loan.", "key": "passed_pawn", "goal": 1},
	"pass_sterling": {"name": "Top of the street", "desc": "End a day worth more than Sterling Bullion Co.", "key": "passed_sterling", "goal": 1},
	"story_done": {"name": "Apprentice no more", "desc": "Finish the story: Mags cuts the ribbon on your landmark.", "key": "chapters", "goal": 5},
	"tip_off": {"name": "Good citizen", "desc": "Tip off the police about Lucky's stolen goods.", "key": "tipped_off", "goal": 1},
	"year_1": {"name": "Four seasons", "desc": "Trade through a whole year, spring to winter.", "key": "days", "goal": 56},
	"booth": {"name": "Show table", "desc": "Book a booth at the town coin show.", "key": "booths", "goal": 1},
	"gift_rush": {"name": "Season's greetings", "desc": "Serve 40 gift shoppers in one holiday rush.", "key": "gift_best", "goal": 40},
	"smelter_10": {"name": "Hot metal", "desc": "Cast 10 bars at the smelter.", "key": "bars_cast", "goal": 10},
	"grader_10": {"name": "Eagle eye", "desc": "Grade 10 coins spot on for collectors.", "key": "graded_exact", "goal": 10},
}

## Lifetime sums of the day reports. Deal counts come from Shop.noted.
var totals := {}
## The best value ever seen of things that can fall back again.
var peaks := {}
## Profitable days and fake-free days in a row, ending with the last closed day.
var streak := 0
var clean_streak := 0
## {"day", "profit", "sold", "bought", "caught", "scammed", "worth"} per closed day, newest last.
var history: Array[Dictionary] = []
## The BEST_DAYS days with the highest profit, best first.
var best_days: Array[Dictionary] = []
## id -> day it was earned.
var earned := {}

## Deals noted today, before the day closes and they join the totals.
var _today := {}
var _unlocked_today: Array[String] = []


func _ready() -> void:
	reset()
	SaveGame.register("records", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Shop.noted.connect(_on_noted)
	Shop.changed.connect(_check_peaks)
	Progress.tier_changed.connect(func(_t): check())
	Day.day_started.connect(func(_d):
		_today.clear()
		_unlocked_today.clear())
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	totals = {"days": 0, "bought": 0.0, "sold": 0.0, "profit": 0.0, "caught": 0, "scammed": 0,
		"stolen": 0.0, "buys": 0, "sales": 0, "robbers_stopped": 0, "tipped_off": 0, "orders_filled": 0,
		"bars_cast": 0, "graded_exact": 0}
	peaks = {"worth": 0.0, "rep": 0.0, "best_day": 0.0, "streak": 0, "clean": 0}
	streak = 0
	clean_streak = 0
	history.clear()
	best_days.clear()
	earned.clear()
	_today.clear()
	_unlocked_today.clear()
	changed.emit()


## Lifetime total of one stat including today's deals so far.
func total(key: String) -> float:
	var sum := float(totals.get(key, 0)) + float(_today.get(key, 0))
	# once the day has closed its stats are already in the totals
	if key in LIVE_STATS and Day.phase != Day.AFTER_HOURS:
		sum += float(Shop.stats.get(key, 0.0))
	return sum


## Fakes caught out of all the fakes that reached the counter, 0 to 1 (1 when none have).
func catch_rate() -> float:
	var caught := total("caught")
	var seen := caught + total("scammed")
	return 1.0 if seen <= 0.0 else caught / seen


## The value an achievement's "key" is measured by.
func value_of(key: String) -> float:
	match key:
		"deals":
			return total("buys") + total("sales")
		"best_day":
			return maxf(peaks.best_day, float(Shop.stats.get("profit", 0.0)))
		"peak_worth":
			return peaks.worth
		"peak_rep":
			return peaks.rep
		"best_streak":
			return peaks.streak
		"best_clean":
			return peaks.clean
		"tier":
			return Progress.tier
		"passed_pawn":
			return 1.0 if Rivals.passed.has("pawn") else 0.0
		"passed_sterling":
			return 1.0 if Rivals.passed.has("sterling") else 0.0
		"tipped_off":
			return totals.get("tipped_off", 0) + float(_today.get("tipped_off", 0))
		"booths":
			return Calendar.booths
		"gift_best":
			return Calendar.best_of("gift_rush")
		"chapters":
			return Story.chapters_done()
		"staff_level":
			return Staff.top_level()
	return total(key)


func is_earned(id: String) -> bool:
	return earned.has(id)


## How far along an achievement is, 0 to 1.
func progress_of(id: String) -> float:
	var a: Dictionary = ACHIEVEMENTS[id]
	return 1.0 if is_earned(id) else clampf(value_of(a.key) / float(a.goal), 0.0, 1.0)


## Awards every achievement whose goal has been reached.
func check() -> void:
	for id in ACHIEVEMENTS:
		if is_earned(id):
			continue
		var a: Dictionary = ACHIEVEMENTS[id]
		if value_of(a.key) >= float(a.goal):
			earned[id] = Shop.day
			_unlocked_today.append(id)
			Shop.log_event(tr("Achievement: %s!") % tr(a.name), "good")
			unlocked.emit(id)
			changed.emit()


func _on_noted(key: String, _amount: float) -> void:
	match key:
		"bought":
			_today["buys"] = int(_today.get("buys", 0)) + 1
		"served":
			_today["sales"] = int(_today.get("sales", 0)) + 1
		"tipped_off":
			_today["tipped_off"] = int(_today.get("tipped_off", 0)) + 1
	check()


func _check_peaks() -> void:
	var worth := Shop.net_worth()
	var grew: bool = worth > peaks.worth or Shop.reputation > peaks.rep
	peaks.worth = maxf(peaks.worth, worth)
	peaks.rep = maxf(peaks.rep, Shop.reputation)
	if grew:
		check()


func _on_day_ended(day: int, report: Dictionary) -> void:
	var stats: Dictionary = report.get("stats", {})
	var profit := float(stats.get("profit", 0.0))
	var scammed := int(stats.get("scammed", 0.0))
	totals.days = int(totals.days) + 1
	for key in ["bought", "sold", "profit", "stolen"]:
		totals[key] = float(totals.get(key, 0.0)) + float(stats.get(key, 0.0))
	totals.caught = int(totals.caught) + int(stats.get("caught", 0.0))
	totals.scammed = int(totals.scammed) + scammed
	totals.robbers_stopped = int(totals.get("robbers_stopped", 0)) + int(stats.get("robbers_stopped", 0.0))
	totals.orders_filled = int(totals.get("orders_filled", 0)) + int(stats.get("orders_filled", 0.0))
	for key in ["bars_cast", "graded_exact"]:
		totals[key] = int(totals.get(key, 0)) + int(stats.get(key, 0.0))
	totals.buys = int(totals.buys) + int(_today.get("buys", 0))
	totals.sales = int(totals.sales) + int(_today.get("sales", 0))
	totals.tipped_off = int(totals.get("tipped_off", 0)) + int(_today.get("tipped_off", 0))
	_today.clear()
	streak = streak + 1 if profit > 0.0 else 0
	clean_streak = clean_streak + 1 if scammed == 0 else 0
	peaks.streak = maxi(int(peaks.streak), streak)
	peaks.clean = maxi(int(peaks.clean), clean_streak)
	peaks.best_day = maxf(float(peaks.best_day), profit)
	var entry := {"day": day, "profit": profit, "sold": float(stats.get("sold", 0.0)),
		"bought": float(stats.get("bought", 0.0)), "caught": int(stats.get("caught", 0.0)),
		"scammed": scammed, "worth": Shop.net_worth()}
	history.append(entry)
	if history.size() > HISTORY_DAYS:
		history = history.slice(history.size() - HISTORY_DAYS)
	_rank_best_day(entry)
	_check_peaks()
	check()
	if _rank_of(day) == 0 and history.size() > 1 and profit > 0.0:
		report.lines.append(tr("Your best day yet: %s profit.") % Market.format_money(profit))
	for id in _unlocked_today:
		report.lines.append(tr("Achievement earned: %s. %s") % [tr(ACHIEVEMENTS[id].name), tr(ACHIEVEMENTS[id].desc)])
	_unlocked_today.clear()
	changed.emit()


func _rank_best_day(entry: Dictionary) -> void:
	if entry.profit <= 0.0:
		return
	best_days.append(entry)
	best_days.sort_custom(func(a, b): return a.profit > b.profit)
	if best_days.size() > BEST_DAYS:
		best_days.resize(BEST_DAYS)


func _rank_of(day: int) -> int:
	for i in best_days.size():
		if int(best_days[i].day) == day:
			return i
	return -1


func to_dict() -> Dictionary:
	return {"totals": totals, "peaks": peaks, "streak": streak, "clean_streak": clean_streak,
		"history": history, "best_days": best_days, "earned": earned}


func from_dict(d: Dictionary) -> void:
	reset()
	for key in d.get("totals", {}):
		if totals.has(key):
			totals[key] = d.totals[key]
	for key in d.get("peaks", {}):
		if peaks.has(key):
			peaks[key] = d.peaks[key]
	streak = int(d.get("streak", 0))
	clean_streak = int(d.get("clean_streak", 0))
	for entry in d.get("history", []):
		if typeof(entry) == TYPE_DICTIONARY:
			history.append(entry)
	for entry in d.get("best_days", []):
		if typeof(entry) == TYPE_DICTIONARY:
			best_days.append(entry)
	for id in d.get("earned", {}):
		if ACHIEVEMENTS.has(id):
			earned[id] = int(d.earned[id])
	changed.emit()
