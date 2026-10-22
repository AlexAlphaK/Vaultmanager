extends Node
## The morning wholesaler: a bullion distributor who sells the shop coins at a small
## markup over live spot before it opens, so buyers do not find the shelves empty.
## Walk-in sellers are still the cheap way to stock up (they take about 90% of melt);
## the wholesaler costs a little over melt, so restocked coins earn only part of the
## premium a buyer pays. Coins arrive genuine and go straight into stock.
## Each morning's lots are drawn from the day number, so quitting mid-morning and
## coming back (the game saves at the start of the morning) offers the same lots.

signal changed

## Markup over melt per shop tier: a bigger shop buys in bulk and gets a better rate.
## Tuned with tests/balance_sim.tscn against buyers' 3-9% (plus reputation) premiums.
const MARKUP: Array[float] = [0.03, 0.025, 0.02, 0.015]
## Coins on offer each morning per metal, before Progress.deal_size().
const LOT_RANGE := {"XAU": Vector2i(2, 4), "XAG": Vector2i(20, 40), "XPT": Vector2i(1, 3)}
## How many coins one press of the bulk button buys.
const BULK := {"XAU": 2, "XAG": 10, "XPT": 1}

## id -> coins left to buy this morning.
var lots := {}
var bought_today := 0.0


func _ready() -> void:
	Day.day_started.connect(func(_day): restock_offer())


## Draws this morning's lots.
func restock_offer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Shop.day * 104729 + 17
	lots.clear()
	bought_today = 0.0
	for item in coin_list():
		var r: Vector2i = LOT_RANGE.get(item.metal, Vector2i(1, 2))
		lots[item.id] = maxi(1, roundi(rng.randi_range(r.x, r.y) * Progress.deal_size()))
	changed.emit()


## Coins on offer, gold first, then silver and platinum.
func coin_list() -> Array[BullionItem]:
	var out := Shop.coin_list()
	var order := {"XAU": 0, "XAG": 1, "XPT": 2}
	out.sort_custom(func(a, b):
		var oa: int = order.get(a.metal, 9)
		var ob: int = order.get(b.metal, 9)
		return oa < ob if oa != ob else a.display_name < b.display_name)
	return out


func markup() -> float:
	return MARKUP[clampi(Progress.tier, 0, MARKUP.size() - 1)]


## What one coin costs from the wholesaler right now.
func price(item: BullionItem) -> float:
	return item.melt_value() * (1.0 + markup())


func left(item: BullionItem) -> int:
	return int(lots.get(item.id, 0))


func bulk(item: BullionItem) -> int:
	return int(BULK.get(item.metal, 1))


## How many of `qty` coins the shop can buy now (limited by the lot and cash). The
## delivery comes before opening, so only in the morning.
func affordable(item: BullionItem, qty: int) -> int:
	var each := price(item)
	if each <= 0.0 or Day.phase != Day.MORNING:
		return 0
	return clampi(mini(qty, left(item)), 0, int(Shop.cash / each))


## Buys up to `qty` coins. Returns how many were bought.
func buy(item: BullionItem, qty: int) -> int:
	var n := affordable(item, qty)
	if n <= 0:
		return 0
	var each := price(item)
	Shop.add_cash(-each * n)
	Shop.add_stock(item, n, each)
	lots[item.id] = left(item) - n
	bought_today += each * n
	Shop.log_event("Wholesaler: %d x %s for %s." % [n, item.display_name, Market.format_money(each * n)])
	changed.emit()
	return n
