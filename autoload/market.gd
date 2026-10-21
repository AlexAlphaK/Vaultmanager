extends Node
## Live precious metal prices (USD per troy ounce).
## Polls the price service every 5 minutes, caches the last quote on disk,
## and falls back to a simulated random walk when the game has been offline too long.

signal prices_changed(prices: Dictionary)
signal source_changed(source: String) # "live", "cached" or "simulated"

const METALS: Array[String] = ["XAU", "XAG", "XPT", "XPD"]
const POLL_SECONDS := 300.0
const SIM_STEP_SECONDS := 5.0
const SIMULATE_AFTER_OFFLINE_SECONDS := 24 * 3600
const CACHE_PATH := "user://last_prices.json"
const TROY_OZ_GRAMS := 31.1034768
## Typical daily volatility, used only by the offline simulation.
const DAILY_VOL := {"XAU": 0.012, "XAG": 0.02, "XPT": 0.018, "XPD": 0.022}
## Last-resort seed when there is no network and no cache (first launch offline).
const SEED_PRICES := {"XAU": 4473.37, "XAG": 73.31, "XPT": 1879.64, "XPD": 1520.0}

@export var service_url := "http://127.0.0.1:8787/prices"

var prices := {}
var day_open := {}
var source := "cached"
var last_live_unix := 0

var _http: HTTPRequest


func _ready() -> void:
	_load_cache()
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


func start_new_day() -> void:
	day_open = prices.duplicate()


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_go_offline()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("prices")) != TYPE_DICTIONARY:
		_go_offline()
		return
	for metal in METALS:
		if data.prices.has(metal):
			prices[metal] = float(data.prices[metal])
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
		file.store_string(JSON.stringify({"prices": prices, "last_live_unix": last_live_unix}))


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("prices")) == TYPE_DICTIONARY:
		prices = data.prices
		last_live_unix = int(data.get("last_live_unix", 0))
