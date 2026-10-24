extends Node
## Special orders: collectors who walk in and ask the shop to find coins for them by a
## set day. Most want a rare coin (a 1924 Double Hawk, an 1881 Frontier Dollar...) that
## the wholesaler doesn't stock; some want a big lot of one everyday coin.
##
## Finding the coins is the hunt:
##   walk-in sellers  while a rare order is open, now and then a seller brings an old coin
##                    without knowing what it is, and sells it for about melt. Test it:
##                    rare coins are faked too.
##   dealer network   on the Restock page, some mornings a dealer has one, at a fee that
##                    eats most of the collector's premium.
##   wholesaler       everyday coins for bulk orders, at the usual markup.
## Coins a collector is waiting for are set aside: buyers off the street can't have them.
## The collector comes back on the day you agreed (or sooner, once you hold the coins)
## and pays the agreed price. Fill the order for reputation; miss it and you lose some.
## Open orders are saved with the game.

signal changed

## Odds that a day brings a collector with a new order (at most one a day), and the
## odds that each everyday arrival on such a day is them, while there is room for an order.
## Tuned with tests/balance_sim.tscn to about one order every two or three days.
const ORDER_DAY_ODDS := 0.4
const ORDER_ODDS := 0.08
## No orders before this day, nor below this many stars.
const MIN_DAY := 3
const MIN_REP := 2.0
## Open orders at once, per shop tier.
const MAX_OPEN: Array[int] = [1, 2, 3, 3]
## Days the collector gives you to find the coins.
const DAYS := Vector2i(3, 6)
## Share of orders that are for a rare coin rather than a bulk lot of everyday coins, per
## shop tier: corner counter collectors mostly want coins the wholesaler has.
const RARE_SHARE: Array[float] = [0.3, 0.6, 0.65, 0.65]
## Bulk orders: coins per order (before Progress.deal_size()) and premium over melt.
const BULK_QTY := {"XAU": Vector2i(2, 5), "XAG": Vector2i(25, 60), "XPT": Vector2i(2, 4)}
const BULK_PREMIUM := Vector2(0.1, 0.14)
## Rare orders pay the coin's collector premium times a draw from this range.
const RARE_PREMIUM := Vector2(0.9, 1.15)
## Odds that an everyday coin seller brings a rare coin instead: while a rare order is
## open (for that coin), and otherwise.
const RARE_SELLER_ODDS := 0.06
const RARE_SELLER_STRAY := 0.015
## Odds the dealer network has a wanted rare coin on a given morning, and its fee as a
## share of the coin's collector premium.
const DEALER_ODDS := 0.5
const DEALER_SHARE := 0.85
const COLLECTOR_NAMES := ["Professor Hale", "Mr. Whitcombe", "Dr. Ng", "Mrs. Pemberton-Cross", "Colonel Ashby",
	"Ms. Delacroix", "Judge Amari", "Mr. Lindqvist"]
const RARE_ASKS := ["I've hunted a %s for years. Find me one?", "My collection is missing a %s. Can you track one down?",
	"A %s, in decent condition. I'll pay a collector's price."]
const BULK_ASKS := ["I'm buying for a client. Can you get me %d %s coins?", "Wedding gifts for the whole family: %d %s coins.",
	"Our company is giving %d %s coins to its staff. Can you source them?"]
const PICKUP_LINES := ["Did you find my %s? We agreed on today.", "I'm here for the %s. Tell me you found it.",
	"Today's the day. Have you got my %s?"]
const EARLY_LINES := ["I heard you found my %s already!", "Word is my %s came in. Is it ready?"]
const RARE_SELLER_LINES := ["Found this old coin in grandad's desk. Is it worth anything?",
	"Some old coin from a box of junk. Melt price is fine.", "It was my aunt's. Gold's gold, right?",
	"Dug this out of the garden, believe it or not."]

## Open orders, oldest first: {"id", "name", "look", "item", "qty", "premium", "placed", "due", "visited"}.
## "look" is the seed of the collector's look, "visited" the last day they came by.
var open: Array[Dictionary] = []
## The dealer network's rare coins this morning: id -> coins left.
var dealer := {}
## Whether a collector with a new order is still to come today.
var order_today := false
var _next_id := 1


func _ready() -> void:
	reset()
	SaveGame.register("orders", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_on_day_started)


func reset() -> void:
	open.clear()
	dealer.clear()
	_next_id = 1
	changed.emit()


## How many orders the shop can take at once.
func max_open() -> int:
	return MAX_OPEN[clampi(Progress.tier, 0, MAX_OPEN.size() - 1)]


## Coins of `item` set aside for open orders.
func set_aside(item: BullionItem) -> int:
	var n := 0
	for o in open:
		if o.item == item.id:
			n += int(o.qty)
	return n


func item_of(o: Dictionary) -> BullionItem:
	return Shop.coins.get(o.item)


## Coins held for order `o`, out of o.qty.
func have_for(o: Dictionary) -> int:
	return mini(Shop.count_of_item(item_of(o)), int(o.qty))


## What the collector pays for order `o` at today's prices.
func price_of(o: Dictionary) -> float:
	return item_of(o).melt_value() * int(o.qty) * (1.0 + float(o.premium))


func days_left(o: Dictionary) -> int:
	return int(o.due) - Shop.day


# ---------------------------------------------------------------- customers

## The customer for an order that needs one today: a collector coming to pick up their
## coins, or someone coming in to place a new order. Null when nobody is due.
func next_customer(rng: RandomNumberGenerator, event := {}) -> Customer:
	for o in open:
		if int(o.visited) == Shop.day:
			continue
		if Shop.day >= int(o.due) or (Shop.day > int(o.placed) and have_for(o) >= int(o.qty)):
			return pickup_customer(o, rng)
	if event.is_empty() and order_today and can_take() and rng.randf() < ORDER_ODDS:
		order_today = false
		return offer_customer(rng)
	return null


## True when a new order may walk in.
func can_take() -> bool:
	return Shop.day >= MIN_DAY and Shop.reputation >= MIN_REP and open.size() < max_open() and Tutorial.first_day_done


## A collector who wants to place an order (kind "order"). Taking it is accept().
func offer_customer(rng: RandomNumberGenerator) -> Customer:
	var o := {"id": _next_id, "name": COLLECTOR_NAMES[rng.randi() % COLLECTOR_NAMES.size()], "look": rng.randi(),
		"placed": Shop.day, "due": Shop.day + rng.randi_range(DAYS.x, DAYS.y), "visited": Shop.day}
	var rares := Shop.rare_list().filter(func(it): return set_aside(it) == 0)
	var item: BullionItem
	if not rares.is_empty() and rng.randf() < RARE_SHARE[clampi(Progress.tier, 0, RARE_SHARE.size() - 1)]:
		item = rares[rng.randi() % rares.size()]
		o.qty = 1 if item.metal != "XAG" else rng.randi_range(1, 3)
		o.premium = snappedf(item.collector_premium * rng.randf_range(RARE_PREMIUM.x, RARE_PREMIUM.y), 0.01)
	else:
		var coins := Shop.coin_list()
		item = coins[rng.randi() % coins.size()]
		var r: Vector2i = BULK_QTY.get(item.metal, Vector2i(2, 4))
		o.qty = maxi(1, roundi(rng.randi_range(r.x, r.y) * Progress.deal_size()))
		o.premium = snappedf(rng.randf_range(BULK_PREMIUM.x, BULK_PREMIUM.y) + Progress.effect("premium"), 0.01)
	o.item = item.id
	var c := _collector(o, rng)
	c.kind = "order"
	c.say = (tr(RARE_ASKS[rng.randi() % RARE_ASKS.size()]) % item.display_name) if item.rare else \
		(tr(BULK_ASKS[rng.randi() % BULK_ASKS.size()]) % [o.qty, item.display_name])
	return c


## A collector back for order `o`. They pay the agreed price, no haggling.
func pickup_customer(o: Dictionary, rng: RandomNumberGenerator) -> Customer:
	o.visited = Shop.day
	var c := _collector(o, rng)
	c.kind = "buyer"
	c.wanted_exact = true
	c.max_premium = float(o.premium)
	c.ceiling_premium = c.max_premium
	var lines := PICKUP_LINES if Shop.day >= int(o.due) else EARLY_LINES
	c.say = tr(lines[rng.randi() % lines.size()]) % item_of(o).display_name
	return c


func _collector(o: Dictionary, rng: RandomNumberGenerator) -> Customer:
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng)
	c.archetype = "collector"
	c.order = o
	c.name = o.name
	c.item = item_of(o)
	c.qty = int(o.qty)
	c.piece = null
	c.bar = null
	c.fake = ""
	c.haggle = 0.0
	c.max_patience = 9999.0
	c.patience = c.max_patience
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = int(o.look)
	var look := PeopleArt.random_look(look_rng)
	look.glasses = true
	look.top = 1
	c.set_look(look)
	return c


## Now and then an everyday coin seller has a rare coin instead, more often while a
## collector is waiting for one. They don't know what it is and want about melt.
func maybe_rare_seller(c: Customer, rng: RandomNumberGenerator) -> void:
	if c.kind != "seller" or c.piece or c.bar or c.event_id != "" or c.archetype == "crypto_bro":
		return
	var wanted := Shop.rare_list().filter(func(it): return set_aside(it) > Shop.count_of_item(it))
	var pool := wanted
	if wanted.is_empty() or rng.randf() >= RARE_SELLER_ODDS:
		if rng.randf() >= RARE_SELLER_STRAY:
			return
		pool = Shop.rare_list()
	if pool.is_empty():
		return
	var item: BullionItem = pool[rng.randi() % pool.size()]
	var was_fake := c.fake
	c.item = item
	c.qty = 1 if item.metal != "XAG" else rng.randi_range(1, 3)
	# forgers love a famous date: a rare coin is faked a little more often than bullion
	var kinds := Counterfeit.kinds_for(item.metal, Shop.day)
	c.fake = ""
	if not kinds.is_empty() and (was_fake != "" or rng.randf() < Customer.fake_odds_on(Shop.day) * 0.5):
		c.fake = kinds[rng.randi() % kinds.size()]
	if c.archetype != "shady":
		c.say = tr(RARE_SELLER_LINES[rng.randi() % RARE_SELLER_LINES.size()])


## The player took the order on customer `c`'s card.
func accept(c: Customer) -> void:
	var o: Dictionary = c.order
	o.id = _next_id
	_next_id += 1
	open.append(o)
	Shop.log_event(tr("%s ordered %d × %s by %s. Pays %s.") % [o.name, o.qty, item_of(o).display_name,
		Day.weekday(int(o.due)), Market.format_money(price_of(o))])
	changed.emit()


## Called as each customer leaves (from Customers.on_leave).
func on_leave(c: Customer) -> void:
	if c.order.is_empty() or c.kind != "buyer" or not open.has(c.order):
		return
	var o := c.order
	if c.dealt:
		open.erase(o)
		Shop.reputation_for("order_filled")
		Shop.note("orders_filled")
		Shop.log_event(tr("%s collected their %s. Order filled!") % [o.name, item_of(o).display_name], "good")
		Customers.add_story(tr("%s picked up the %s you found for them. Collectors talk.") % [o.name, item_of(o).display_name])
		changed.emit()
	elif Shop.day >= int(o.due):
		open.erase(o)
		Shop.reputation_for("order_failed")
		Shop.note("orders_failed")
		Shop.log_event(tr("%s's order fell through. They won't forget it.") % o.name, "bad")
		Customers.add_story(tr("You let %s down: no %s on the day you promised.") % [o.name, item_of(o).display_name])
		changed.emit()
	else:
		Shop.log_event(tr("%s will come back on %s.") % [o.name, Day.weekday(int(o.due))])


# ---------------------------------------------------------------- dealer network

func _on_day_started(day: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 6151 + 11
	order_today = rng.randf() < ORDER_DAY_ODDS
	dealer_offer()


## Draws this morning's dealer coins for the open rare orders.
func dealer_offer() -> void:
	dealer.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = Shop.day * 7919 + 3
	for item in wanted_rare():
		if rng.randf() < DEALER_ODDS:
			dealer[item.id] = maxi(1, set_aside(item) - Shop.count_of_item(item))
	changed.emit()


## Rare coins open orders still need.
func wanted_rare() -> Array[BullionItem]:
	var out: Array[BullionItem] = []
	for item in Shop.rare_list():
		if set_aside(item) > Shop.count_of_item(item):
			out.append(item)
	return out


func dealer_left(item: BullionItem) -> int:
	return int(dealer.get(item.id, 0))


func dealer_price(item: BullionItem) -> float:
	return item.melt_value() * (1.0 + item.collector_premium * DEALER_SHARE)


## Buys one coin from the dealer network (mornings only). True when bought.
func dealer_buy(item: BullionItem) -> bool:
	var each := dealer_price(item)
	if Day.phase != Day.MORNING or dealer_left(item) <= 0 or Shop.cash < each:
		return false
	Shop.add_cash(-each)
	Shop.add_stock(item, 1, each)
	dealer[item.id] = dealer_left(item) - 1
	Shop.log_event(tr("Dealer network: 1 × %s for %s.") % [item.display_name, Market.format_money(each)])
	changed.emit()
	return true


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"open": open.duplicate(true), "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	reset()
	_next_id = int(d.get("next_id", 1))
	for o in d.get("open", []):
		if typeof(o) != TYPE_DICTIONARY or not Shop.coins.has(o.get("item", "")):
			continue
		open.append({"id": int(o.get("id", 0)), "name": str(o.get("name", tr("A collector"))), "look": int(o.get("look", 0)),
			"item": o.item, "qty": maxi(1, int(o.get("qty", 1))), "premium": float(o.get("premium", 0.1)),
			"placed": int(o.get("placed", 0)), "due": int(o.get("due", 0)), "visited": int(o.get("visited", 0))})
	changed.emit()
