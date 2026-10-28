extends Node
## Market prices: precious metals (USD per troy ounce), crypto and stocks (USD), and
## exchange rates for showing money in the player's currency. No network: every save
## replays a stretch of real metal price history, one historical day per game day, so
## a long campaign never outruns the real world.
##
## A new game picks a random past date (1972 on, at least MIN_YEARS_LEFT of data ahead)
## on the same weekday as game day 1. Each game day is the next calendar day of history,
## so game weekends are market weekends and the metals sit still. Prices follow the real
## moves but are scaled to start at today's level (SEED_PRICES), because the shop's bills,
## wages and budgets are tuned to it; decade-long trends are softened by TREND_DAMP so a
## save that starts in 2001 doesn't end with gold at six times the price. The year stays
## hidden. If a save reaches the end of the data, it carries on from another random date,
## scaled so the prices continue where they were.
##
## History is monthly (see PriceHistory); the days between months follow a Brownian
## bridge with a typical day's volatility, seeded by the date, so a date always has the
## same price. Crypto and stocks are made up: a mean-reverting walk per save.
##
## Within a game day: in the morning prices sit at yesterday's close (the change shown is
## yesterday's move); while the shop is open they walk to today's close along a path
## timed to the shop clock (`day_fraction`, set by the shop scene); after closing they
## sit at today's close.
## All game logic works in USD; convert only for display with format_money().

signal prices_changed(prices: Dictionary)
signal currency_changed(code: String)

const METALS: Array[String] = ["XAU", "XAG", "XPT", "XPD"]
const STEP_SECONDS := 1.5
## Points on a day's path from yesterday's close to today's, spread over the open hours.
const PATH_STEPS := 80
## Typical daily volatility of a trading day. The metals use it between monthly prices.
const DAILY_VOL := {"XAU": 0.011, "XAG": 0.019, "XPT": 0.015, "XPD": 0.02}
const CRYPTO_DAILY_VOL := 0.04
const STOCK_DAILY_VOL := 0.015
## A save starts with at least this many years of history ahead of it.
const MIN_YEARS_LEFT := 12
## Share of the slow trend (a TREND_MONTHS moving average) taken out of the replay.
const TREND_DAMP := 0.7
const TREND_MONTHS := 36
## Pull of made-up crypto and stock prices back toward their starting level, per day.
const SIM_PULL := 0.002
## Where the made-up crypto and stocks start.
const SIM_START := {
	"crypto": {"BTC": 108000.0, "ETH": 3900.0, "SOL": 190.0, "DOGE": 0.2},
	"stocks": {"SPY": 660.0, "NVDA": 185.0, "AAPL": 250.0, "TSLA": 430.0},
}
const SETTINGS_PATH := "user://settings.cfg"
const TROY_OZ_GRAMS := 31.1034768
## Currencies the player can pick (all covered by the ECB reference rates).
const CURRENCY_SYMBOLS := {
	"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CAD": "C$", "AUD": "A$", "NZD": "NZ$",
	"CHF": "CHF ", "SEK": "kr ", "NOK": "kr ", "DKK": "kr ", "PLN": "zł ", "CZK": "Kč ",
	"HUF": "Ft ", "INR": "₹", "CNY": "¥", "HKD": "HK$", "SGD": "S$", "KRW": "₩",
	"BRL": "R$", "MXN": "MX$", "ZAR": "R ", "TRY": "₺",
}
## ECB reference rates, units per 1 USD (27 October 2026). Only for display.
const FX := {
	"USD": 1.0, "EUR": 0.89686, "GBP": 0.7503, "JPY": 157.82, "CAD": 1.4023, "AUD": 1.4221,
	"NZD": 1.7535, "CHF": 0.82861, "SEK": 9.9368, "NOK": 9.317, "DKK": 6.7033, "PLN": 3.948,
	"CZK": 21.837, "HUF": 329.58, "INR": 95.12, "CNY": 6.6675, "HKD": 7.8445, "SGD": 1.2812,
	"KRW": 1327.75, "BRL": 5.3474, "MXN": 18.6368, "ZAR": 16.6487, "TRY": 49.787,
}
const COUNTRY_CURRENCY := {
	"US": "USD", "GB": "GBP", "CA": "CAD", "AU": "AUD", "NZ": "NZD", "JP": "JPY", "CH": "CHF",
	"SE": "SEK", "NO": "NOK", "DK": "DKK", "PL": "PLN", "CZ": "CZK", "HU": "HUF", "IN": "INR",
	"CN": "CNY", "HK": "HKD", "SG": "SGD", "KR": "KRW", "BR": "BRL", "MX": "MXN", "ZA": "ZAR",
	"TR": "TRY", "DE": "EUR", "FR": "EUR", "IT": "EUR", "ES": "EUR", "NL": "EUR", "BE": "EUR",
	"AT": "EUR", "IE": "EUR", "PT": "EUR", "FI": "EUR", "GR": "EUR", "SK": "EUR", "SI": "EUR",
	"EE": "EUR", "LV": "EUR", "LT": "EUR", "LU": "EUR", "MT": "EUR", "CY": "EUR", "HR": "EUR",
}
## Thousands and decimal marks per language.
const DIGIT_MARKS := {"en": [",", "."], "de": [".", ","], "es": [".", ","], "fr": [" ", ","]}
## Today's level: a new game opens at these prices.
const SEED_PRICES := {"XAU": 4131.55, "XAG": 57.59, "XPT": 1631.85, "XPD": 1092.36}

var prices := {}
var crypto := {} # symbol -> {"price": USD, "change_pct": % since the previous close}
var stocks := {} # symbol -> {"price": USD, "change_pct": % since the previous close}
var metals_change := {} # metal -> % since the previous close
var fx := FX.duplicate() # currency -> units per 1 USD
var currency := "USD"
var day_open := {}
## How far through today's open hours the shop clock is, 0 to 1. The shop scene sets it.
var day_fraction := 0.0
## Tests and tools set this to keep prices where they put them.
var held := false

## The save's replay: game day `era_day` is historical day `era_date` (days since
## 1970-01-01), and each metal's replayed price is multiplied by `scale`.
var seed := 0
var era_day := 1
var era_date := 0
var scale := {}

var _anchors := PackedInt64Array() # epoch day of the 15th of each month of history
var _logs := {} # metal -> log monthly price
var _trend := {} # metal -> log moving average around each month
var _bridges := {} # "metal:month" -> log prices for each calendar day between anchors
var _sim := {} # "crypto:BTC" -> log level against SIM_START for each game day
## Today's rows: key -> {"prev": close two days ago, "ref": yesterday's close, "path": log prices}
var _today := {}
var _today_day := -1
var _stage := "morning" # "morning", "open" or "closed"


func _ready() -> void:
	_load_history()
	_load_currency()
	randomize()
	new_era()
	_hook_up.call_deferred()
	var timer := Timer.new()
	timer.wait_time = STEP_SECONDS
	timer.autostart = true
	timer.timeout.connect(step)
	add_child(timer)


func _hook_up() -> void:
	Day.day_started.connect(func(_d): _set_stage("morning"))
	Day.shop_opened.connect(func(_d): _set_stage("open"))
	Day.shop_closed.connect(func(_d): _set_stage("closed"))
	Day.day_ended.connect(func(_d, _r): _set_stage("closed"))
	_sync()


## Starts a fresh replay at a random past date, opening at today's prices.
func new_era(at_seed := -1) -> void:
	seed = at_seed if at_seed >= 0 else randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	era_day = 1
	era_date = _random_date(rng, 1)
	scale = {}
	for metal in METALS:
		scale[metal] = SEED_PRICES[metal] / exp(_raw_log(metal, era_date - 1))
	_sim.clear()
	_today_day = -1
	_stage = "morning"
	if is_inside_tree() and get_node_or_null("/root/Shop") != null:
		_sync()


## Saved with the game. The scales go as their exact bytes, since the save's JSON rounds numbers.
func to_dict() -> Dictionary:
	var scales := {}
	for metal in scale:
		scales[metal] = Marshalls.raw_to_base64(PackedFloat64Array([scale[metal]]).to_byte_array())
	return {"seed": seed, "era_day": era_day, "era_date": era_date, "scale": scales}


func from_dict(d: Dictionary) -> void:
	if not d.has("era_date") or typeof(d.get("scale")) != TYPE_DICTIONARY:
		return
	seed = int(d.seed)
	era_day = int(d.era_day)
	era_date = int(d.era_date)
	for metal in METALS:
		var v = d.scale.get(metal)
		scale[metal] = Marshalls.base64_to_raw(v).to_float64_array()[0] if v is String else scale.get(metal, 1.0)
	_sim.clear()
	_today_day = -1
	_sync.call_deferred()


## The historical date (days since 1970-01-01) a game day replays.
func date_of(day: int) -> int:
	return era_date + day - era_day


## Whether the metals trade today: game weekends are market weekends.
func is_trading_day(day := -1) -> bool:
	return _weekday(date_of(day if day > 0 else _current_day())) < 5


## Value of `troy_oz` fine ounces of `metal` at the current price.
func value_of(metal: String, troy_oz: float) -> float:
	return troy_oz * float(prices.get(metal, 0.0))


## Percent change since the in-game day opened. Drives customer mood.
func day_change_percent(metal: String) -> float:
	var open := float(day_open.get(metal, 0.0))
	if open <= 0.0:
		return 0.0
	return (float(prices.get(metal, open)) / open - 1.0) * 100.0


## Percent change since the previous close (in the morning: yesterday's move). Drives
## market events.
func metal_move_percent(metal: String) -> float:
	return float(metals_change.get(metal, 0.0))


## A new game day: prices open at yesterday's close. Shop.next_day() calls this.
func start_new_day() -> void:
	if not held:
		_stage = "morning"
		_sync()
	day_open = prices.duplicate()


## Picks the display currency and remembers it.
func set_currency(code: String) -> void:
	if not CURRENCY_SYMBOLS.has(code):
		return
	currency = code
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "currency", code)
	cfg.save(SETTINGS_PATH)
	currency_changed.emit(code)


## Formats a USD amount in the player's currency, e.g. "€4,120".
func format_money(usd: float, decimals := 0) -> String:
	var code := currency if fx.has(currency) else "USD"
	var amount := usd * float(fx.get(code, 1.0))
	var minus := "-" if amount < 0.0 else ""
	return minus + CURRENCY_SYMBOLS[code] + _group_digits(absf(amount), decimals)


## Currency for the device's region, e.g. "de_DE" -> EUR. USD when unknown.
static func currency_for_locale(locale: String) -> String:
	var parts := locale.split("_")
	if parts.size() >= 2:
		return COUNTRY_CURRENCY.get(parts[1].substr(0, 2).to_upper(), "USD")
	return "USD"


## Digits grouped the way the game's language writes them: 1,234.50 in English,
## 1.234,50 in German and Spanish, 1 234,50 in French.
static func _group_digits(value: float, decimals: int) -> String:
	var text := ("%." + str(decimals) + "f") % value if decimals > 0 else str(roundi(value))
	var whole := text.get_slice(".", 0)
	var frac := text.substr(whole.length())
	var marks: Array = DIGIT_MARKS.get(TranslationServer.get_locale().get_slice("_", 0), DIGIT_MARKS.en)
	var out := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			out += marks[0]
		out += whole[i]
	return out + frac.replace(".", marks[1])


## One tick of the shown prices: where today's path stands on the shop clock.
func step() -> void:
	if held:
		return
	if _today_day != _current_day():
		_sync()
	else:
		_show()


func _show() -> void:
	var f := 0.0
	match _stage:
		"open":
			f = clampf(day_fraction, 0.0, 1.0)
		"closed":
			f = 1.0
	for k in _today:
		var row: Dictionary = _today[k]
		var shown := float(row.ref)
		var ref := float(row.prev)
		if _stage != "morning":
			var path: PackedFloat64Array = row.path
			var x := f * PATH_STEPS
			var i := mini(int(x), PATH_STEPS - 1)
			shown = exp(lerpf(path[i], path[i + 1], x - i))
			ref = float(row.ref)
		_set_shown(k, shown, ref)
	prices_changed.emit(prices)


## The close of every metal, crypto and stock on a game day.
func closes(day: int) -> Dictionary:
	var out := {}
	for metal in METALS:
		out["metal:" + metal] = float(scale[metal]) * exp(_raw_log(metal, date_of(day)))
	for group in SIM_START:
		for sym in SIM_START[group]:
			var k: String = ("crypto:" if group == "crypto" else "stock:") + sym
			out[k] = float(SIM_START[group][sym]) * exp(_sim_log(k, day))
	return out


## Builds today's paths and shows the prices for where the day stands.
func _sync() -> void:
	var day := _current_day()
	if date_of(day) + 1 >= _anchors[_anchors.size() - 1]:
		_next_era(day)
	var prev := closes(day - 2)
	var ref := closes(day - 1)
	var close := closes(day)
	_today.clear()
	for k in close:
		var vol: float = _vol_of(k)
		var trading: bool = k.begins_with("crypto:") or is_trading_day(day)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, k, day])
		_today[k] = {"prev": prev[k], "ref": ref[k],
			"path": _bridge(log(float(ref[k])), log(float(close[k])), PATH_STEPS, vol / sqrt(PATH_STEPS) if trading else 0.0, rng)}
	_today_day = day
	if not held:
		_show()


## The save ran out of history: carry on from another random date, the prices
## continuing from where yesterday closed.
func _next_era(day: int) -> void:
	var before := {}
	for metal in METALS:
		before[metal] = float(scale[metal]) * exp(_raw_log(metal, date_of(day - 1)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, day])
	era_day = day
	era_date = _random_date(rng, day)
	for metal in METALS:
		scale[metal] = before[metal] / exp(_raw_log(metal, date_of(day - 1)))


## A random date with MIN_YEARS_LEFT of history ahead, on the weekday of game `day`.
func _random_date(rng: RandomNumberGenerator, day: int) -> int:
	var first := _anchors[0] + 7
	var last := _anchors[_anchors.size() - 1] - MIN_YEARS_LEFT * 365
	var d := rng.randi_range(first, last)
	var want := (day - 1) % 7 # game day 1 is a Monday
	return d + posmod(want - _weekday(d), 7)


## 0 for Monday to 6 for Sunday. 1970-01-01 was a Thursday.
static func _weekday(date: int) -> int:
	return posmod(date + 3, 7)


func _current_day() -> int:
	var shop := get_node_or_null("/root/Shop")
	return int(shop.day) if shop else 1


func _set_stage(stage: String) -> void:
	_stage = stage
	if not held:
		step()


func _vol_of(k: String) -> float:
	if k.begins_with("metal:"):
		return DAILY_VOL[k.get_slice(":", 1)]
	return CRYPTO_DAILY_VOL if k.begins_with("crypto:") else STOCK_DAILY_VOL


## Replayed log price of `metal` on historical `date`, before scaling: the day on the
## bridge between monthly prices (weekends keep Friday's), less some of the slow trend.
func _raw_log(metal: String, date: int) -> float:
	var wd := _weekday(date)
	if wd >= 5:
		date -= wd - 4
	var i := clampi(_anchors.bsearch(date, true) - 1, 0, _anchors.size() - 2)
	var key := "%s:%d" % [metal, i]
	if not _bridges.has(key):
		var n := int(_anchors[i + 1] - _anchors[i])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var logs: PackedFloat64Array = _logs[metal]
		_bridges[key] = _bridge(logs[i], logs[i + 1], n, DAILY_VOL[metal] * sqrt(5.0 / 7.0), rng)
	var days: PackedFloat64Array = _bridges[key]
	var k := clampi(int(date - _anchors[i]), 0, days.size() - 1)
	var trend: PackedFloat64Array = _trend[metal]
	var t := lerpf(trend[i], trend[i + 1], float(k) / (days.size() - 1))
	return days[k] - TREND_DAMP * t


## A random walk of `n` steps of `sd` from `a` that lands exactly on `b`.
static func _bridge(a: float, b: float, n: int, sd: float, rng: RandomNumberGenerator) -> PackedFloat64Array:
	var walk := PackedFloat64Array([0.0])
	for k in n:
		walk.append(walk[k] + rng.randfn(0.0, sd))
	var out := PackedFloat64Array()
	for k in n + 1:
		var t := float(k) / n
		out.append(a + (b - a) * t + walk[k] - t * walk[n])
	return out


## Log level of a made-up price on game `day`, against where it started: a daily
## random move pulled gently back toward the start. Stocks rest on weekends.
func _sim_log(k: String, day: int) -> float:
	if day <= 0:
		return 0.0
	if not _sim.has(k):
		_sim[k] = PackedFloat64Array([0.0])
	var levels: PackedFloat64Array = _sim[k]
	var vol := _vol_of(k)
	var rng := RandomNumberGenerator.new()
	for d in range(levels.size(), day + 1):
		rng.seed = hash([seed, k, d, "sim"])
		if k.begins_with("stock:") and _weekday(date_of(d)) >= 5:
			levels.append(levels[d - 1])
		else:
			levels.append(levels[d - 1] * (1.0 - SIM_PULL) + rng.randfn(0.0, vol))
	_sim[k] = levels
	return levels[day]


func _set_shown(k: String, value: float, ref: float) -> void:
	var sym := k.get_slice(":", 1)
	var pct := (value / ref - 1.0) * 100.0 if ref > 0.0 else 0.0
	match k.get_slice(":", 0):
		"metal":
			prices[sym] = value
			metals_change[sym] = pct
		"crypto":
			crypto[sym] = {"price": value, "change_pct": pct}
		"stock":
			stocks[sym] = {"price": value, "change_pct": pct}


func _load_history() -> void:
	var rows: Array = PriceHistory.MONTHS
	for metal in METALS:
		_logs[metal] = PackedFloat64Array()
	for i in rows.size():
		var month := PriceHistory.FIRST_MONTH - 1 + i
		var unix := Time.get_unix_time_from_datetime_dict({"year": PriceHistory.FIRST_YEAR + month / 12,
			"month": month % 12 + 1, "day": 15})
		_anchors.append(unix / 86400)
		for m in METALS.size():
			_logs[METALS[m]].append(log(float(rows[i][m])))
	var half := TREND_MONTHS / 2
	for metal in METALS:
		var logs: PackedFloat64Array = _logs[metal]
		var trend := PackedFloat64Array()
		for i in logs.size():
			var lo := maxi(0, i - half)
			var hi := mini(logs.size() - 1, i + half)
			var total := 0.0
			for j in range(lo, hi + 1):
				total += logs[j]
			trend.append(total / (hi - lo + 1))
		_trend[metal] = trend


func _load_currency() -> void:
	var cfg := ConfigFile.new()
	var saved := ""
	if cfg.load(SETTINGS_PATH) == OK:
		saved = cfg.get_value("display", "currency", "")
	currency = saved if CURRENCY_SYMBOLS.has(saved) else currency_for_locale(OS.get_locale())
