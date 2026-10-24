extends Node
## Live market data: precious metals (USD per troy ounce), crypto and stocks (USD),
## and exchange rates for showing money in the player's currency.
## Asks the price service for a real quote only a few times a day (on launch when the
## cached one is old or from an earlier day, then every few hours), and caches it on disk.
## Between quotes the game draws believable moves itself: when a new real day's quote
## arrives, each price walks from the previous close to today's real price over
## DAY_PATH_SECONDS of play (a Brownian bridge), then keeps ticking gently around it.
## So the charts look live while one quote covers hours of play.
## `prices`, `metals_change`, `crypto` and `stocks` hold these shown values; the real
## quote stays in `_paths`. Offline for more than a day, each "day" walks to a random close.
## All game logic works in USD; convert only for display with format_money().

signal prices_changed(prices: Dictionary)
signal source_changed(source: String) # "live", "cached" or "simulated"
signal currency_changed(code: String)

const METALS: Array[String] = ["XAU", "XAG", "XPT", "XPD"]
## How old the real quote may get before the next request, and how often to check.
const REFRESH_SECONDS := 4 * 3600
const CHECK_SECONDS := 600.0
const SIM_STEP_SECONDS := 3.0
## Play time one real day's move is spread over, and the shorter walk to a same-day update.
const DAY_PATH_SECONDS := 30 * 60
const RETARGET_SECONDS := 3 * 60
## Once a walk ends, prices wander around the real one with this share of a day's volatility.
const SETTLE_VOL_SHARE := 0.25
const SETTLE_PULL := 0.03
## A shown price further than this many daily volatilities from a new quote snaps to it.
const SNAP_VOLS := 4.0
const SIMULATE_AFTER_OFFLINE_SECONDS := 24 * 3600
const CACHE_PATH := "user://last_prices.json"
const SETTINGS_PATH := "user://settings.cfg"
const TROY_OZ_GRAMS := 31.1034768
## Typical daily volatility, used only by the offline simulation.
const DAILY_VOL := {"XAU": 0.012, "XAG": 0.02, "XPT": 0.018, "XPD": 0.022}
const CRYPTO_DAILY_VOL := 0.04
const STOCK_DAILY_VOL := 0.015
## Currencies the player can pick (all covered by the ECB reference rates).
const CURRENCY_SYMBOLS := {
	"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CAD": "C$", "AUD": "A$", "NZD": "NZ$",
	"CHF": "CHF ", "SEK": "kr ", "NOK": "kr ", "DKK": "kr ", "PLN": "zł ", "CZK": "Kč ",
	"HUF": "Ft ", "INR": "₹", "CNY": "¥", "HKD": "HK$", "SGD": "S$", "KRW": "₩",
	"BRL": "R$", "MXN": "MX$", "ZAR": "R ", "TRY": "₺",
}
const COUNTRY_CURRENCY := {
	"US": "USD", "GB": "GBP", "CA": "CAD", "AU": "AUD", "NZ": "NZD", "JP": "JPY", "CH": "CHF",
	"SE": "SEK", "NO": "NOK", "DK": "DKK", "PL": "PLN", "CZ": "CZK", "HU": "HUF", "IN": "INR",
	"CN": "CNY", "HK": "HKD", "SG": "SGD", "KR": "KRW", "BR": "BRL", "MX": "MXN", "ZA": "ZAR",
	"TR": "TRY", "DE": "EUR", "FR": "EUR", "IT": "EUR", "ES": "EUR", "NL": "EUR", "BE": "EUR",
	"AT": "EUR", "IE": "EUR", "PT": "EUR", "FI": "EUR", "GR": "EUR", "SK": "EUR", "SI": "EUR",
	"EE": "EUR", "LV": "EUR", "LT": "EUR", "LU": "EUR", "MT": "EUR", "CY": "EUR", "HR": "EUR",
}
## Last-resort seed when there is no network and no cache (first launch offline).
## Thousands and decimal marks per language.
const DIGIT_MARKS := {"en": [",", "."], "de": [".", ","], "es": [".", ","], "fr": [" ", ","]}
const SEED_PRICES := {"XAU": 4131.55, "XAG": 57.59, "XPT": 1631.85, "XPD": 1092.36}

@export var service_url := "https://vault-manager-prices.price-service.workers.dev/prices"

var prices := {}
var crypto := {} # symbol -> {"price": USD, "change_pct": 24h %}
var stocks := {} # symbol -> {"price": USD, "change_pct": % since last close}
var metals_change := {} # metal -> % change over the last real day, from the price service
var fx := {"USD": 1.0} # currency -> units per 1 USD
var currency := "USD"
var day_open := {}
var source := "cached"
var last_live_unix := 0 # when the last real quote arrived
var quote_day := "" # UTC date of that quote, e.g. "2026-10-24"

## "metal:XAU", "crypto:BTC" or "stock:SPY" -> {"target": real price, "ref": previous close
## (0 when unknown), "left": walk steps to go (0 once settled), "vol": daily volatility}
var _paths := {}

var _http: HTTPRequest


func _ready() -> void:
	_load_cache()
	if prices.is_empty():
		# first launch: play on seed prices until the first quote arrives
		prices = SEED_PRICES.duplicate()
		source = "simulated"
	else:
		source = _source_for_age()
	start_new_day()
	_load_currency()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)
	_add_timer(CHECK_SECONDS, refresh_if_stale)
	_add_timer(SIM_STEP_SECONDS, step)
	refresh_if_stale()


## Asks for a new quote only when ours is old or from an earlier real day.
func refresh_if_stale() -> void:
	if needs_refresh(int(Time.get_unix_time_from_system()), Time.get_date_string_from_system(true)):
		refresh()
	elif source == "simulated" or source == "cached":
		_set_source(_source_for_age())


func needs_refresh(now_unix: int, today: String) -> bool:
	return now_unix - last_live_unix >= REFRESH_SECONDS or quote_day != today


func refresh() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if _http.request(service_url) != OK:
		_go_offline()


## Value of `troy_oz` fine ounces of `metal` at the current price.
func value_of(metal: String, troy_oz: float) -> float:
	return troy_oz * float(prices.get(metal, 0.0))


## Percent change since the in-game day opened. Drives customer mood.
func day_change_percent(metal: String) -> float:
	var open := float(day_open.get(metal, 0.0))
	if open <= 0.0:
		return 0.0
	return (float(prices.get(metal, open)) / open - 1.0) * 100.0


## Percent change over the last real day when the price service knows it, otherwise
## since the in-game day opened. Drives market events.
func metal_move_percent(metal: String) -> float:
	if source != "simulated" and metals_change.has(metal):
		return float(metals_change[metal])
	return day_change_percent(metal)


func start_new_day() -> void:
	day_open = prices.duplicate()


## Picks the display currency and remembers it. Falls back to USD without a rate.
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


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_go_offline()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("prices")) != TYPE_DICTIONARY:
		_go_offline()
		return
	take_quote(data, int(Time.get_unix_time_from_system()), Time.get_date_string_from_system(true))
	_set_source("live")
	_save_cache()
	_emit()


## Takes a real quote as the place prices walk to. The first quote of a real day walks
## from the previous close over DAY_PATH_SECONDS; a later one re-aims within RETARGET_SECONDS.
func take_quote(data: Dictionary, now_unix: int, today: String) -> void:
	var new_day := today != quote_day
	var real := {} # key -> [real price, real change % or null, daily volatility]
	var changes: Dictionary = data.metals_change if typeof(data.get("metals_change")) == TYPE_DICTIONARY else {}
	for metal in METALS:
		if data.prices.has(metal):
			real["metal:" + metal] = [float(data.prices[metal]), changes.get(metal), DAILY_VOL[metal]]
	for key in ["crypto", "stocks"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			continue
		for sym in data[key]:
			var q = data[key][sym]
			if typeof(q) == TYPE_DICTIONARY and q.has("price"):
				real[("crypto:" if key == "crypto" else "stock:") + sym] = [float(q.price), q.get("change_pct"),
					CRYPTO_DAILY_VOL if key == "crypto" else STOCK_DAILY_VOL]
	for k in real:
		var target: float = real[k][0]
		if target <= 0.0:
			continue
		var ref := target / (1.0 + float(real[k][1]) / 100.0) if real[k][1] != null else 0.0
		var vol: float = real[k][2]
		var shown := _shown(k)
		var old: Dictionary = _paths.get(k, {})
		var steps := int(RETARGET_SECONDS / SIM_STEP_SECONDS)
		if new_day:
			steps = int(DAY_PATH_SECONDS / SIM_STEP_SECONDS)
			# open the day at the previous close, unless we are already near it
			if shown <= 0.0 or (ref > 0.0 and absf(log(shown / ref)) > SNAP_VOLS * vol):
				shown = ref if ref > 0.0 else target
		else:
			steps = maxi(steps, int(old.get("left", 0)))
		if shown <= 0.0 or absf(log(shown / target)) > SNAP_VOLS * vol * 2.0:
			shown = ref if ref > 0.0 else target
		_set_shown(k, shown)
		_paths[k] = {"target": target, "ref": ref, "left": steps, "vol": vol}
		_update_change(k)
	if typeof(data.get("fx")) == TYPE_DICTIONARY:
		for code in data.fx:
			fx[code] = float(data.fx[code])
	last_live_unix = now_unix
	quote_day = today


## One tick of the shown prices: walk toward the real quote, or wander around it.
func step() -> void:
	if source == "simulated":
		_invent_days()
	for k in _paths.keys():
		var p: Dictionary = _paths[k]
		var shown := _shown(k)
		if shown <= 0.0:
			continue
		var x := log(shown)
		var goal := log(float(p.target))
		var sigma := float(p.vol) * sqrt(SIM_STEP_SECONDS / DAY_PATH_SECONDS)
		var n := int(p.left)
		if n > 0:
			# exact Brownian bridge step: lands on the target when n reaches 1
			x += (goal - x) / n + sigma * sqrt(float(n - 1) / n) * randfn(0.0, 1.0)
			p.left = n - 1
		else:
			# settled: pulled back toward the real price, a stationary wobble around it
			var wobble := float(p.vol) * SETTLE_VOL_SHARE * sqrt(2.0 * SETTLE_PULL)
			x += SETTLE_PULL * (goal - x) + wobble * randfn(0.0, 1.0)
		_set_shown(k, exp(x))
		_update_change(k)
	_emit()


## Offline: once a walk ends, the next one heads for an invented close a day's move away.
func _invent_days() -> void:
	for metal in METALS:
		if prices.has(metal) and not _paths.has("metal:" + metal):
			_paths["metal:" + metal] = {"target": float(prices[metal]), "ref": 0.0, "left": 0, "vol": DAILY_VOL[metal]}
	for k in _paths:
		var p: Dictionary = _paths[k]
		if int(p.left) == 0 and _shown(k) > 0.0:
			var shown := _shown(k)
			p.ref = shown
			p.target = shown * exp(randfn(0.0, float(p.vol)))
			p.left = int(DAY_PATH_SECONDS / SIM_STEP_SECONDS)


func _shown(k: String) -> float:
	var sym := k.get_slice(":", 1)
	match k.get_slice(":", 0):
		"metal":
			return float(prices.get(sym, 0.0))
		"crypto":
			return float(crypto.get(sym, {}).get("price", 0.0))
		"stock":
			return float(stocks.get(sym, {}).get("price", 0.0))
	return 0.0


func _set_shown(k: String, value: float) -> void:
	var sym := k.get_slice(":", 1)
	match k.get_slice(":", 0):
		"metal":
			prices[sym] = value
		"crypto", "stock":
			var group: Dictionary = crypto if k.begins_with("crypto") else stocks
			if not group.has(sym):
				group[sym] = {"price": value, "change_pct": 0.0}
			group[sym].price = value


## The shown change since the previous close, so headlines and tickers match the chart.
func _update_change(k: String) -> void:
	var ref := float(_paths[k].ref)
	if ref <= 0.0:
		return
	var pct := (_shown(k) / ref - 1.0) * 100.0
	var sym := k.get_slice(":", 1)
	match k.get_slice(":", 0):
		"metal":
			metals_change[sym] = pct
		"crypto":
			crypto[sym].change_pct = pct
		"stock":
			stocks[sym].change_pct = pct


func _source_for_age() -> String:
	var age := Time.get_unix_time_from_system() - last_live_unix
	if age < REFRESH_SECONDS * 2:
		return "live"
	return "cached" if age < SIMULATE_AFTER_OFFLINE_SECONDS else "simulated"


func _go_offline() -> void:
	if prices.is_empty():
		prices = SEED_PRICES.duplicate()
		_set_source("simulated")
	elif Time.get_unix_time_from_system() - last_live_unix > SIMULATE_AFTER_OFFLINE_SECONDS:
		_set_source("simulated")
	else:
		_set_source("cached")
	_emit()


func _emit() -> void:
	if day_open.is_empty() and not prices.is_empty():
		start_new_day()
	prices_changed.emit(prices)


func _set_source(value: String) -> void:
	if value != source:
		source = value
		source_changed.emit(source)


func _add_timer(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.autostart = true
	timer.timeout.connect(callback)
	add_child(timer)


func _save_cache() -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"prices": prices, "metals_change": metals_change, "crypto": crypto, "stocks": stocks, "fx": fx,
			"last_live_unix": last_live_unix, "quote_day": quote_day, "paths": _paths,
		}))


## Restores the shown prices and their walks, so a relaunch carries on where play stopped.
## Older caches held only the real quote; it is shown as is.
func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("prices")) == TYPE_DICTIONARY:
		_apply_quote(data)
		last_live_unix = int(data.get("last_live_unix", 0))
		quote_day = str(data.get("quote_day", ""))
		if typeof(data.get("paths")) == TYPE_DICTIONARY:
			for k in data.paths:
				var p = data.paths[k]
				if typeof(p) == TYPE_DICTIONARY and p.has("target") and _shown(k) > 0.0:
					_paths[k] = {"target": float(p.target), "ref": float(p.get("ref", 0.0)),
						"left": int(p.get("left", 0)), "vol": float(p.get("vol", STOCK_DAILY_VOL))}
		_settle_missing()


## Prices without a walk (an older cache) wobble around where they are.
func _settle_missing() -> void:
	var keys := []
	for metal in METALS:
		if prices.has(metal):
			keys.append(["metal:" + metal, metals_change.get(metal), DAILY_VOL[metal]])
	for sym in crypto:
		keys.append(["crypto:" + sym, crypto[sym].get("change_pct"), CRYPTO_DAILY_VOL])
	for sym in stocks:
		keys.append(["stock:" + sym, stocks[sym].get("change_pct"), STOCK_DAILY_VOL])
	for entry in keys:
		var shown := _shown(entry[0])
		if _paths.has(entry[0]) or shown <= 0.0:
			continue
		var ref := shown / (1.0 + float(entry[1]) / 100.0) if entry[1] != null else 0.0
		_paths[entry[0]] = {"target": shown, "ref": ref, "left": 0, "vol": entry[2]}


func _apply_quote(data: Dictionary) -> void:
	for metal in METALS:
		if data.prices.has(metal):
			prices[metal] = float(data.prices[metal])
	if typeof(data.get("metals_change")) == TYPE_DICTIONARY:
		for metal in METALS:
			if data.metals_change.has(metal):
				metals_change[metal] = float(data.metals_change[metal])
	for key in ["crypto", "stocks"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = crypto if key == "crypto" else stocks
		for sym in data[key]:
			var q = data[key][sym]
			if typeof(q) == TYPE_DICTIONARY and q.has("price"):
				target[sym] = {"price": float(q.price), "change_pct": float(q.get("change_pct", 0.0))}
	if typeof(data.get("fx")) == TYPE_DICTIONARY:
		for code in data.fx:
			fx[code] = float(data.fx[code])


func _load_currency() -> void:
	var cfg := ConfigFile.new()
	var saved := ""
	if cfg.load(SETTINGS_PATH) == OK:
		saved = cfg.get_value("display", "currency", "")
	currency = saved if CURRENCY_SYMBOLS.has(saved) else currency_for_locale(OS.get_locale())
