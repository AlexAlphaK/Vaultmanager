class_name DeskSession
extends RefCounted
## One morning at the trading desk: a minute-long tape of a trading day, 09:00 to 17:00,
## for gold, silver, platinum and the live crypto and stocks from Market. Each tape starts
## where the live price stood 24 hours ago and drifts toward a close near where it is now,
## so the real 24-hour move (shown on the board) is the trader's edge, but noise and a
## scaled move keep it from being a sure thing.
##
## The desk trades on its own limit (longs plus shorts), not cash: every position closes
## at the bell and only the profit or loss goes on the day's ledger. Shorting the metals
## held in the vault hedges them: when a metal falls the vault loses on paper and the desk
## makes it back. One session a day, in the morning, once the trading desk room is built.

const STEPS := 240
const SECONDS := 60.0
const METALS := ["XAU", "XAG", "XPT"]
## Crypto and stocks on the board, first ones the price service knows.
const CRYPTO_PICKS := ["BTC", "ETH", "SOL", "DOGE"]
const STOCK_PICKS := ["SPY", "NVDA", "AAPL", "TSLA"]
const MAX_CRYPTO := 2
const MAX_STOCKS := 2
## Quotes for the board before the price service has ever answered.
const FALLBACK := {"BTC": {"price": 108000.0, "change_pct": 0.0}, "ETH": {"price": 3900.0, "change_pct": 0.0},
	"SPY": {"price": 660.0, "change_pct": 0.0}, "NVDA": {"price": 185.0, "change_pct": 0.0}}
const NAMES := {"XAU": "Gold", "XAG": "Silver", "XPT": "Platinum", "BTC": "Bitcoin", "ETH": "Ether",
	"SOL": "Solana", "DOGE": "Dogecoin", "SPY": "S&P 500", "NVDA": "Nvidia", "AAPL": "Apple", "TSLA": "Tesla"}
## What a trade costs, as a share of its size: half the bid-ask spread plus commission.
const FEE := {"metal": 0.0008, "stock": 0.0005, "crypto": 0.0015}
## The real 24h move is scaled by MOVE_SCALE and gets noise of DRIFT_NOISE days of volatility.
const MOVE_SCALE := Vector2(0.5, 1.5)
const DRIFT_NOISE := 0.5
## The desk's limit on open positions, times the shop's deal size.
const BASE_LIMIT := 20000.0
## Hedge vault uses at most this share of the limit, leaving room to trade.
const HEDGE_SHARE := 0.5
## Share of the limit one Buy or Sell trades, picked with the size buttons.
const SIZES := [0.1, 0.25, 0.5]

## The day the desk last traded and its lifetime profit, saved with the game.
static var last_day := 0
static var lifetime := 0.0
static var _hooked := false

## One entry per row on the board: {"sym", "name", "kind", "path", "change", "units", "flow", "fees"}.
## `path` holds STEPS + 1 prices, `change` the real 24h move in percent, `units` the open
## position (negative is short) and `flow` the cash paid out (-) and in (+) by its trades.
var board: Array[Dictionary] = []
var limit := BASE_LIMIT
var elapsed := 0.0
var started := false
## Fine ounces of each metal in the vault when the session opened.
var vault_oz := {}


static func hook_up() -> void:
	if _hooked:
		return
	_hooked = true
	SaveGame.register("desk", func(): return to_dict(), func(d): from_dict(d))
	SaveGame.new_game_started.connect(func(): from_dict({}))
	# a title screen may have loaded the save before this ran
	if SaveGame.has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("desk")) == TYPE_DICTIONARY:
			from_dict(data.desk)


static func to_dict() -> Dictionary:
	return {"last_day": last_day, "lifetime": lifetime}


static func from_dict(d: Dictionary) -> void:
	last_day = int(d.get("last_day", 0))
	lifetime = float(d.get("lifetime", 0.0))


## Whether the desk can open now: the room is built, it's morning and today's session is unused.
static func available() -> bool:
	return Progress.has_upgrade("trading_desk") and Day.phase == Day.MORNING and last_day != Shop.day


## Puts the session's result on today's ledger and uses up today's session.
static func book(pnl: float) -> void:
	last_day = Shop.day
	lifetime += pnl
	if absf(pnl) < 0.5:
		return
	if pnl > 0.0:
		Day.add_income(Loc.t("Trading desk"), pnl)
		Shop.log_event(Loc.t("The trading desk made %s this morning.") % Market.format_money(pnl), "good")
	else:
		Day.add_expense(Loc.t("Trading desk"), pnl)
		Shop.log_event(Loc.t("The trading desk lost %s this morning.") % Market.format_money(-pnl), "bad")


## Today's board from the live quotes. A fixed `rng` seed replays a session.
static func from_market(rng: RandomNumberGenerator) -> DeskSession:
	var s := DeskSession.new()
	s.limit = BASE_LIMIT * Progress.deal_size()
	s.vault_oz = Shop.ounces_by_metal()
	for metal in METALS:
		if Market.prices.has(metal):
			s.add(metal, "metal", float(Market.prices[metal]), Market.metal_move_percent(metal),
				float(Market.DAILY_VOL.get(metal, 0.015)), rng)
	var crypto: Dictionary = Market.crypto if not Market.crypto.is_empty() else FALLBACK
	var stocks: Dictionary = Market.stocks if not Market.stocks.is_empty() else FALLBACK
	for pick in [[CRYPTO_PICKS, crypto, MAX_CRYPTO, "crypto", Market.CRYPTO_DAILY_VOL],
			[STOCK_PICKS, stocks, MAX_STOCKS, "stock", Market.STOCK_DAILY_VOL]]:
		var n := 0
		for sym in pick[0]:
			if n < pick[2] and pick[1].has(sym):
				var q: Dictionary = pick[1][sym]
				s.add(sym, pick[3], float(q.price), float(q.get("change_pct", 0.0)), pick[4], rng)
				n += 1
	return s


## Adds a row whose tape runs from 24h ago to a close near `live`.
func add(sym: String, kind: String, live: float, change_pct: float, vol: float, rng: RandomNumberGenerator) -> void:
	var open := live / (1.0 + change_pct / 100.0)
	var move := change_pct / 100.0 * rng.randf_range(MOVE_SCALE.x, MOVE_SCALE.y) + rng.randfn(0.0, vol * DRIFT_NOISE)
	board.append({"sym": sym, "name": NAMES.get(sym, sym), "kind": kind, "change": change_pct,
		"path": tape(open, open * maxf(0.5, 1.0 + move), vol, rng), "units": 0.0, "flow": 0.0, "fees": 0.0})


## A random walk from `open` to `close` (a Brownian bridge in log price) with `vol` per day.
static func tape(open: float, close: float, vol: float, rng: RandomNumberGenerator) -> PackedFloat64Array:
	var walk := PackedFloat64Array([0.0])
	var sd := vol / sqrt(float(STEPS))
	for k in STEPS:
		walk.append(walk[k] + rng.randfn(0.0, sd))
	var drift := log(close / open)
	var out := PackedFloat64Array()
	for k in STEPS + 1:
		var t := float(k) / STEPS
		out.append(open * exp(drift * t + walk[k] - t * walk[STEPS]))
	return out


func step() -> int:
	return clampi(floori(elapsed / SECONDS * STEPS), 0, STEPS)


func is_over() -> bool:
	return elapsed >= SECONDS


## Runs the clock once the bell has rung. Returns true on the step the session ends.
func advance(delta: float) -> bool:
	if not started or is_over():
		return false
	elapsed = minf(elapsed + delta, SECONDS)
	return is_over()


func price(i: int) -> float:
	return board[i].path[step()]


func open_price(i: int) -> float:
	return board[i].path[0]


## Percent move since the session opened.
func move_percent(i: int) -> float:
	return (price(i) / open_price(i) - 1.0) * 100.0


## Signed size of a position at today's price: positive long, negative short.
func position(i: int) -> float:
	return board[i].units * price(i)


func pnl_of(i: int) -> float:
	return board[i].flow + board[i].units * price(i)


func pnl() -> float:
	var total := 0.0
	for i in board.size():
		total += pnl_of(i)
	return total


func fees() -> float:
	var total := 0.0
	for row in board:
		total += row.fees
	return total


## Longs plus shorts at today's prices.
func exposure() -> float:
	var total := 0.0
	for i in board.size():
		total += absf(position(i))
	return total


## Buys (`usd` > 0) or sells (`usd` < 0) that much of row `i`, as far as the limit allows.
## Trades that shrink a position always go through. Returns the size traded.
func trade(i: int, usd: float) -> float:
	if i < 0 or i >= board.size() or absf(usd) < 0.01:
		return 0.0
	var now := position(i)
	var after := now + usd
	var room := limit - (exposure() - absf(now))
	if absf(after) > absf(now) and absf(after) > room:
		after = signf(after) * maxf(room, absf(now))
		usd = after - now
	if absf(usd) < 0.01:
		return 0.0
	var row: Dictionary = board[i]
	var p := price(i)
	var fee := absf(usd) * float(FEE[row.kind])
	row.units += usd / p
	row.flow -= usd + fee
	row.fees += fee
	return usd


## Closes row `i`.
func flatten(i: int) -> void:
	trade(i, -position(i))


func flatten_all() -> void:
	for i in board.size():
		flatten(i)


## What the vault's metal has gained (+) or lost (-) on paper since the session opened.
func vault_swing() -> float:
	var total := 0.0
	for i in board.size():
		var sym: String = board[i].sym
		if vault_oz.has(sym):
			total += float(vault_oz[sym]) * (price(i) - open_price(i))
	return total


## The desk's profit on the metals the vault holds.
func metal_pnl() -> float:
	var total := 0.0
	for i in board.size():
		if vault_oz.has(board[i].sym):
			total += pnl_of(i)
	return total


## Shorts each metal the vault holds, ounce for ounce, scaled down to fit HEDGE_SHARE
## of the limit (or what other positions leave free).
func hedge_vault() -> void:
	var need := 0.0
	var free := limit
	for i in board.size():
		if board[i].kind == "metal":
			need += float(vault_oz.get(board[i].sym, 0.0)) * price(i)
		else:
			free -= absf(position(i))
	free = minf(free, limit * HEDGE_SHARE)
	var scale := clampf(free / need, 0.0, 1.0) if need > 0.0 else 0.0
	for i in board.size():
		if board[i].kind == "metal":
			var target := -float(vault_oz.get(board[i].sym, 0.0)) * price(i) * scale
			trade(i, target - position(i))


## Share of the vault's paper move the desk made back, 0 to 1. -1 when the vault didn't move.
func hedge_cover() -> float:
	var swing := vault_swing()
	if absf(swing) < 1.0:
		return -1.0
	return clampf(-metal_pnl() / swing, 0.0, 1.0)


## Whether any trade was made today.
func traded() -> bool:
	return board.any(func(r): return r.fees > 0.0)
