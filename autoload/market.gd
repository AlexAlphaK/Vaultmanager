extends Node
## Live market data: precious metals (USD per troy ounce), crypto and stocks (USD),
## and exchange rates for showing money in the player's currency.
## Polls the price service every 5 minutes, caches the last quote on disk,
## and falls back to a simulated random walk when the game has been offline too long.
## All game logic works in USD; convert only for display with format_money().

signal prices_changed(prices: Dictionary)
signal source_changed(source: String) # "live", "cached" or "simulated"
signal currency_changed(code: String)

const METALS: Array[String] = ["XAU", "XAG", "XPT", "XPD"]
const POLL_SECONDS := 300.0
const SIM_STEP_SECONDS := 5.0
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
var last_live_unix := 0

var _http: HTTPRequest


func _ready() -> void:
	_load_cache()
	if prices.is_empty():
		# first launch: play on seed prices until the first quote arrives
		prices = SEED_PRICES.duplicate()
		source = "simulated"
	start_new_day()
	_load_currency()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)
	_add_timer(POLL_SECONDS, refresh)
	_add_timer(SIM_STEP_SECONDS, _simulate_step)
	refresh()


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


static func _group_digits(value: float, decimals: int) -> String:
	var text := ("%." + str(decimals) + "f") % value if decimals > 0 else str(roundi(value))
	var whole := text.get_slice(".", 0)
	var frac := text.substr(whole.length())
	var out := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			out += ","
		out += whole[i]
	return out + frac


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_go_offline()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("prices")) != TYPE_DICTIONARY:
		_go_offline()
		return
	_apply_quote(data)
	last_live_unix = int(Time.get_unix_time_from_system())
	_set_source("live")
	_save_cache()
	_emit()


func _go_offline() -> void:
	if prices.is_empty():
		prices = SEED_PRICES.duplicate()
		_set_source("simulated")
	elif Time.get_unix_time_from_system() - last_live_unix > SIMULATE_AFTER_OFFLINE_SECONDS:
		_set_source("simulated")
	else:
		_set_source("cached")
	_emit()


func _simulate_step() -> void:
	if source != "simulated":
		return
	var step_scale := sqrt(SIM_STEP_SECONDS / 86400.0)
	for metal in METALS:
		var vol: float = DAILY_VOL[metal] * step_scale
		prices[metal] = float(prices[metal]) * (1.0 + randfn(0.0, vol))
	for pair in [[crypto, CRYPTO_DAILY_VOL], [stocks, STOCK_DAILY_VOL]]:
		var quotes: Dictionary = pair[0]
		var vol: float = pair[1] * step_scale
		for sym in quotes:
			var q: Dictionary = quotes[sym]
			var price := float(q.price) * (1.0 + randfn(0.0, vol))
			q.change_pct = (1.0 + float(q.change_pct) / 100.0) * price / float(q.price) * 100.0 - 100.0
			q.price = price
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
			"prices": prices, "metals_change": metals_change, "crypto": crypto, "stocks": stocks, "fx": fx, "last_live_unix": last_live_unix,
		}))


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("prices")) == TYPE_DICTIONARY:
		_apply_quote(data)
		last_live_unix = int(data.get("last_live_unix", 0))


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
