extends Node
## Market events: real price moves become news headlines and rushes of customers.
## Metals are measured over the last real day (from the price service, or the in-game
## day when there is none), crypto and stocks by the provider's daily change.
## While an event runs, most new customers come because of it: panic sellers when gold
## dips, crypto converts when Bitcoin crashes, and so on.
## Debug builds: press F9 to play the next event without waiting for the market.

signal started(event: Dictionary)
signal ended(event: Dictionary)

## Shop-floor seconds an event lasts, and the quiet gap before the next one can start.
const EVENT_SECONDS := 70.0
const COOLDOWN_SECONDS := 30.0
## After firing, an event re-arms once its move has faded below this share of the trigger.
const REARM_SHARE := 0.5

## measure: "metal:XAU", "crypto:BTC" or "stock:SPY". `at` is the trigger move in percent
## (falls when negative, rises when positive). For the customers it brings:
##   kind: "seller" or "buyer", metal: "" keeps the usual mix, share: odds a new customer
##   comes for the event, rush: customers who walk in at once, spawn: arrival gap factor,
##   reserve: change to the share of melt sellers accept, premium: change to what buyers pay,
##   qty: quantity factor.
const EVENTS: Array[Dictionary] = [
	{"id": "gold_dip", "measure": "metal:XAU", "at": -1.0, "mood": "bad",
		"headline": "GOLD SLIDES {move}. Panic sellers want out before it drops further.",
		"kind": "seller", "metal": "XAU", "share": 0.75, "rush": 3, "spawn": 0.5, "reserve": -0.06, "qty": 1.5,
		"lines": ["Gold's crashing! Take them before they're worth nothing.", "Saw it on the news. I'm getting out now.",
			"My broker isn't picking up. You'll buy these, right?"]},
	{"id": "gold_rally", "measure": "metal:XAU", "at": 1.0, "mood": "good",
		"headline": "GOLD JUMPS {move}. Folks dig out old coins to cash in at the top.",
		"kind": "seller", "metal": "XAU", "share": 0.65, "rush": 2, "spawn": 0.6, "reserve": 0.03, "qty": 1.3,
		"lines": ["Gold's up again. Time to cash in.", "Heard spot is flying today. What'll you give me?"]},
	{"id": "silver_squeeze", "measure": "metal:XAG", "at": 2.0, "mood": "good",
		"headline": "SILVER SQUEEZE: SILVER {move}. Stackers storm the shops.",
		"kind": "buyer", "metal": "XAG", "share": 0.75, "rush": 3, "spawn": 0.5, "premium": 0.05, "qty": 1.6,
		"lines": ["Silver's going to the moon. I need tubes, now.", "Forums say buy physical. How many do you have?"]},
	{"id": "silver_slump", "measure": "metal:XAG", "at": -2.0, "mood": "bad",
		"headline": "SILVER ON SALE: SILVER {move}. Bargain hunters line up.",
		"kind": "buyer", "metal": "XAG", "share": 0.65, "rush": 2, "spawn": 0.6, "premium": 0.02, "qty": 1.4,
		"lines": ["Silver's on sale. I'll take some.", "Buying the dip, like my dad taught me."]},
	{"id": "platinum_pop", "measure": "metal:XPT", "at": 2.0, "mood": "good",
		"headline": "PLATINUM POPS {move}. Owners rush to sell.",
		"kind": "seller", "metal": "XPT", "share": 0.6, "rush": 2, "spawn": 0.6, "reserve": 0.02, "qty": 1.0,
		"lines": ["Platinum's finally moving. Selling while it lasts."]},
	{"id": "btc_crash", "measure": "crypto:BTC", "at": -4.0, "mood": "bad",
		"headline": "BITCOIN CRASHES {move}. Burned crypto traders want something real.",
		"kind": "buyer", "metal": "XAU", "share": 0.75, "rush": 3, "spawn": 0.5, "premium": 0.05, "qty": 1.0,
		"lines": ["My coins halved overnight. Gold doesn't do that, right?", "Done with crypto. Give me something I can hold.",
			"Sold my Bitcoin at the bottom. Never again."]},
	{"id": "btc_boom", "measure": "crypto:BTC", "at": 4.0, "mood": "good",
		"headline": "BITCOIN SOARS {move}. Gold bugs sell up to chase crypto.",
		"kind": "seller", "metal": "", "share": 0.6, "rush": 2, "spawn": 0.6, "reserve": -0.03, "qty": 1.2,
		"lines": ["Need cash fast, Bitcoin's taking off without me.", "My nephew says gold is a boomer rock. Buy these?"]},
	{"id": "doge_moon", "measure": "crypto:DOGE", "at": 10.0, "mood": "good",
		"headline": "DOGECOIN MOONS {move}. Lucky winners want to lock in their gains in gold.",
		"kind": "buyer", "metal": "XAU", "share": 0.6, "rush": 2, "spawn": 0.6, "premium": 0.07, "qty": 1.0,
		"lines": ["Much profit. Very gold. Wow.", "Dog money paid off. Turning it into real money."]},
	{"id": "stock_selloff", "measure": "stock:SPY", "at": -1.2, "mood": "bad",
		"headline": "STOCKS TUMBLE: S&P 500 {move}. Investors run to safe-haven gold.",
		"kind": "buyer", "metal": "XAU", "share": 0.7, "rush": 3, "spawn": 0.55, "premium": 0.04, "qty": 1.0,
		"lines": ["The market's a bloodbath. I want gold.", "My retirement account is red. Something safe, please."]},
	{"id": "stock_rally", "measure": "stock:SPY", "at": 1.2, "mood": "good",
		"headline": "STOCKS RALLY: S&P 500 {move}. Metal holders sell to buy shares.",
		"kind": "seller", "metal": "", "share": 0.55, "rush": 2, "spawn": 0.7, "reserve": -0.02, "qty": 1.0,
		"lines": ["Stocks are flying. Moving my stack into the market.", "Gold's boring. Selling to buy tech."]},
	{"id": "tech_crash", "measure": "stock:NVDA", "at": -5.0, "mood": "bad",
		"headline": "CHIP STOCKS PLUNGE: NVIDIA {move}. Tech money looks for shelter in silver.",
		"kind": "buyer", "metal": "XAG", "share": 0.65, "rush": 2, "spawn": 0.6, "premium": 0.04, "qty": 1.3,
		"lines": ["Lost a month's pay on chips today. Silver, please.", "Tech's crashing. I want something shiny I can hold."]},
]

var active := {} # the running event, with "move" (percent) and "left" (seconds); empty when quiet
var _cooldown := 0.0
var _armed := {} # id -> can fire again
var _check_in := 0.0
var _day := 0
var _debug_index := 0


func _ready() -> void:
	for e in EVENTS:
		_armed[e.id] = true
	Market.prices_changed.connect(func(_p): evaluate())
	# wait for the shop scene so the first headline has somewhere to show
	evaluate.call_deferred()


## The move in percent that `measure` reads right now. 0 when there is no data.
func move_of(measure: String) -> float:
	var parts := measure.split(":")
	match parts[0]:
		"metal":
			return Market.metal_move_percent(parts[1])
		"crypto":
			return float(Market.crypto.get(parts[1], {}).get("change_pct", 0.0))
		"stock":
			return float(Market.stocks.get(parts[1], {}).get("change_pct", 0.0))
	return 0.0


## Starts the strongest triggered event, if none is running.
func evaluate() -> void:
	var best := {}
	var best_strength := 1.0
	for e in EVENTS:
		var move := move_of(e.measure)
		var strength: float = move / e.at
		if strength < REARM_SHARE:
			_armed[e.id] = true
		if active.is_empty() and _cooldown <= 0.0 and _armed[e.id] and strength >= best_strength:
			best = e
			best_strength = strength
	if not best.is_empty():
		start(best, move_of(best.measure))


func start(event: Dictionary, move: float) -> void:
	if not active.is_empty():
		stop()
	_armed[event.id] = false
	active = event.duplicate()
	active.move = move
	active.left = EVENT_SECONDS
	_day = Shop.day
	started.emit(active)
	Shop.log_event("NEWS: " + headline(active), active.get("mood", ""))


func stop() -> void:
	if active.is_empty():
		return
	var e := active
	active = {}
	_cooldown = COOLDOWN_SECONDS
	ended.emit(e)


## The headline with its real move filled in, e.g. "GOLD SLIDES -1.4%. ...".
static func headline(event: Dictionary) -> String:
	var move := float(event.get("move", event.at))
	return String(event.headline).format({"move": "%s%.1f%%" % ["+" if move >= 0.0 else "", move]})


## Shop clock. The shop calls this while it is open, so events pause with the shop.
func advance(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not active.is_empty():
		active.left -= delta
		if active.left <= 0.0 or Shop.day != _day:
			stop()
	_check_in -= delta
	if _check_in <= 0.0:
		_check_in = 1.0
		evaluate()


## The event a newly arriving customer comes for, or {} for an everyday customer.
func customer_event(rng: RandomNumberGenerator) -> Dictionary:
	if active.is_empty() or rng.randf() >= float(active.share):
		return {}
	return active


## Multiplies the gap between customers while an event runs.
func spawn_factor() -> float:
	return 1.0 if active.is_empty() else float(active.spawn)


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F9:
		var e: Dictionary = EVENTS[_debug_index % EVENTS.size()]
		_debug_index += 1
		_cooldown = 0.0
		start(e, e.at * 1.4)
		get_viewport().set_input_as_handled()
