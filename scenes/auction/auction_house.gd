class_name AuctionHouse
extends RefCounted
## Ashworth & Finch, the town's auction rooms. Twice a week (Wednesday and Saturday
## mornings) they sell a few lots, and you can go and bid against the rival shops and the
## collectors in town (see AuctionSale for the bidding itself):
##   estate lots   a late collector's coins: some laid out to see, some in sealed pouches.
##                 The catalogue guesses at the pouches. At the viewing you may open a few
##                 of them: a pouch can hold more coins, a rare coin (a sleeper!) or brass
##                 copies worth nothing. Sterling has his own spies and sometimes knows too.
##   rare coins    one coin for collectors. Worth most when a special order wants it.
##   dealer stock  a dealer's surplus everyday coins, all on show.
##   your lots     rare coins you consign from the vault; Ashworth & Finch keep a fee.
## The winner pays the hammer price plus the buyer's premium. What you win goes in the
## vault. Lots and the sale's progress are saved with the game.

const NAME := "Ashworth & Finch"
## Sale days, in English (see Day.weekday_key), and the first day there is one.
const SALE_DAYS := ["Wednesday", "Saturday"]
const FROM_DAY := 3
## The buyer's premium on top of the hammer price, and the fee on lots you sell.
const BUYERS_PREMIUM := 0.12
const SELLERS_FEE := 0.1
## Lots in a sale, and pouches you may open at the viewing, per shop tier.
const LOT_COUNT: Array[int] = [4, 5, 5, 6]
const VIEWINGS: Array[int] = [2, 3, 3, 4]
## Rare coins you can put in one sale.
const MAX_CONSIGN := 2
## Odds a lot is a single rare coin, or a dealer's surplus (the rest are estates). Rare
## coins come up more often while an order wants one.
const RARE_ODDS := 0.2
const RARE_WANTED_ODDS := 0.45
const BULK_ODDS := 0.25
## What a sealed pouch holds: more coins, a rare coin, or brass copies.
const POUCH_RARE := 0.15
const POUCH_JUNK := 0.35
## The catalogue values a pouch at this share of what a pouch of coins would be worth.
const POUCH_GUESS := 0.45
## How much of a rare coin's collector premium the catalogue counts in its estimate.
const RARE_ESTIMATE := 0.5
## Coins per group (before Progress.deal_size()).
const QTY := {"XAU": Vector2i(1, 3), "XAG": Vector2i(6, 20), "XPT": Vector2i(1, 2)}
const BULK_QTY := {"XAU": Vector2i(3, 6), "XAG": Vector2i(30, 80), "XPT": Vector2i(2, 4)}
const ESTATES := ["Agatha Crane", "Harold Voss", "Ellen Marsh", "Rupert Hay", "Ivy Lambert", "Otto Brandt",
	"Rosa Bell", "Walter Pike", "Nora Quill", "Felix Durand"]
const DEALERS := ["Mr. Okafor", "Mrs. Lindgren", "Mr. Petrakis", "Ms. Abara"]

## The day of the catalogue in `lots`, and the day the sale was held (0 if not yet).
static var catalogue_day := 0
static var held_day := 0
## The sale's lots, in order: {"n", "kind" ("estate", "rare", "bulk" or "mine"), "who", "items",
## "seed", "result": {} until sold: {"winner", "name", "hammer"}}. An item:
## {"coin": id, "qty", "pouch": bool, "seen": bool, "junk": bool, "guess": USD, "cost": USD each (yours)}.
static var lots: Array[Dictionary] = []
## Pouches you may still open at this sale's viewing.
static var views_left := 0
## Lifetime: lots won, what they cost, sleepers found, and what your lots sold for.
static var won := 0
static var spent := 0.0
static var sleepers := 0
static var sold_for := 0.0
static var _hooked := false


static func hook_up() -> void:
	if _hooked:
		return
	_hooked = true
	SaveGame.register("auction", func(): return to_dict(), func(d): from_dict(d))
	SaveGame.new_game_started.connect(func(): from_dict({}))
	Day.day_started.connect(func(_d): refresh_catalogue())
	Day.shop_opened.connect(func(_d): return_unsold())
	if SaveGame.has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("auction")) == TYPE_DICTIONARY:
			from_dict(data.auction)


static func is_sale_day(day := Shop.day) -> bool:
	return day >= FROM_DAY and Day.weekday_key(day) in SALE_DAYS


## The first sale day from `day` on.
static func next_sale_day(day := Shop.day) -> int:
	var d := maxi(day, FROM_DAY)
	while not is_sale_day(d):
		d += 1
	return d


## Whether you can go to the sale now: a sale morning you haven't been to yet.
static func available() -> bool:
	return is_sale_day() and Day.phase == Day.MORNING and held_day != Shop.day and Tutorial.first_day_done


## Draws the catalogue on a sale morning. Seeded by the day, so replaying a morning
## brings the same lots.
static func refresh_catalogue() -> void:
	if not is_sale_day() or catalogue_day == Shop.day:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Shop.day * 7717 + 29
	catalogue_day = Shop.day
	lots.clear()
	views_left = VIEWINGS[clampi(Progress.tier, 0, VIEWINGS.size() - 1)]
	var wanted := Orders.wanted_rare()
	for n in LOT_COUNT[clampi(Progress.tier, 0, LOT_COUNT.size() - 1)]:
		var roll := rng.randf()
		var rare_odds := RARE_WANTED_ODDS if not wanted.is_empty() else RARE_ODDS
		var lot: Dictionary
		if roll < rare_odds:
			var pool: Array[BullionItem] = wanted if not wanted.is_empty() and rng.randf() < 0.7 else Shop.rare_list()
			lot = {"kind": "rare", "who": "", "items": [_group(pool[rng.randi() % pool.size()], 1)]}
		elif roll < rare_odds + BULK_ODDS:
			lot = roll_bulk(rng)
		else:
			lot = roll_estate(rng)
		lot.seed = rng.randi() % 1000000
		lots.append(lot)
	_number()


static func roll_estate(rng: RandomNumberGenerator) -> Dictionary:
	var items: Array = []
	var metals := ["XAU", "XAG", "XAG", "XPT"] if Shop.day >= 6 else ["XAU", "XAG", "XAG"]
	for n in rng.randi_range(2, 3):
		var coin := _everyday(metals[rng.randi() % metals.size()], rng)
		items.append(_group(coin, _qty(QTY, coin.metal, rng)))
	for n in rng.randi_range(1, 2):
		items.append(roll_pouch(rng))
	return {"kind": "estate", "who": ESTATES[rng.randi() % ESTATES.size()], "items": items}


static func roll_bulk(rng: RandomNumberGenerator) -> Dictionary:
	var coin := _everyday(["XAU", "XAG", "XPT"][rng.randi() % 3] if Shop.day >= 6 else ["XAU", "XAG"][rng.randi() % 2], rng)
	return {"kind": "bulk", "who": DEALERS[rng.randi() % DEALERS.size()], "items": [_group(coin, _qty(BULK_QTY, coin.metal, rng))]}


## A sealed pouch. The catalogue's guess is a share of what a pouch of coins would hold;
## what is really inside is rolled now.
static func roll_pouch(rng: RandomNumberGenerator) -> Dictionary:
	var coin := _everyday(["XAU", "XAG"][rng.randi() % 2], rng)
	var qty := _qty(QTY, coin.metal, rng)
	var guess := coin.melt_value() * qty * POUCH_GUESS
	var roll := rng.randf()
	var p: Dictionary
	if roll < POUCH_RARE:
		var rares := Shop.rare_list()
		p = _group(rares[rng.randi() % rares.size()], 1)
	elif roll < POUCH_RARE + POUCH_JUNK:
		var gold := _everyday("XAU", rng)
		p = _group(gold, rng.randi_range(1, 4))
		p.junk = true
	else:
		p = _group(coin, qty)
	p.pouch = true
	p.guess = snappedf(guess, 1.0)
	return p


static func _group(coin: BullionItem, qty: int) -> Dictionary:
	return {"coin": coin.id, "qty": qty, "pouch": false, "seen": false, "junk": false, "guess": 0.0, "cost": 0.0}


static func _everyday(metal: String, rng: RandomNumberGenerator) -> BullionItem:
	var pool := Shop.coin_list().filter(func(c): return c.metal == metal)
	if pool.is_empty():
		pool = Shop.coin_list()
	return pool[rng.randi() % pool.size()]


static func _qty(table: Dictionary, metal: String, rng: RandomNumberGenerator) -> int:
	var span: Vector2i = table.get(metal, Vector2i(1, 2))
	return maxi(1, roundi(rng.randi_range(span.x, span.y) * Progress.deal_size()))


static func _number() -> void:
	for n in lots.size():
		lots[n].n = n + 1
		if not lots[n].has("result"):
			lots[n].result = {}


# ---------------------------------------------------------------- what lots are worth

static func coin_of(it: Dictionary) -> BullionItem:
	return Shop.coins.get(it.coin)


## Melt value of one group: nothing for brass copies.
static func melt_of(it: Dictionary) -> float:
	return 0.0 if it.junk else coin_of(it).melt_value() * int(it.qty)


## What one group is really worth to a buyer who knows what it is: rare coins carry
## `rare_share` of their collector premium.
static func true_value(it: Dictionary, rare_share := RARE_ESTIMATE) -> float:
	if it.junk:
		return 0.0
	var coin := coin_of(it)
	return coin.melt_value() * int(it.qty) * (1.0 + (coin.collector_premium * rare_share if coin.rare else 0.0))


## What the catalogue thinks a group is worth: its guess for a sealed pouch.
static func catalogue_value(it: Dictionary, rare_share := RARE_ESTIMATE) -> float:
	return float(it.guess) if it.pouch else true_value(it, rare_share)


## The catalogue's value of a whole lot.
static func lot_catalogue(lot: Dictionary) -> float:
	var v := 0.0
	for it in lot.items:
		v += catalogue_value(it)
	return v


## The printed estimate, low and high, rounded like an auctioneer would.
static func estimate(lot: Dictionary) -> Vector2:
	var v := lot_catalogue(lot)
	return Vector2(nice(v * 0.8), nice(v * 1.1))


## Melt of everything in a lot that you have seen: what's on show and the pouches you opened.
static func known_melt(lot: Dictionary) -> float:
	var v := 0.0
	for it in lot.items:
		if not it.pouch or it.seen:
			v += melt_of(it)
	return v


static func pouches_unseen(lot: Dictionary) -> int:
	return lot.items.filter(func(it): return it.pouch and not it.seen).size()


## A rare coin in the lot that an open special order wants, or null.
static func wanted_in(lot: Dictionary) -> BullionItem:
	for it in lot.items:
		if it.junk or (it.pouch and not it.seen):
			continue
		var coin := coin_of(it)
		if coin.rare and coin in Orders.wanted_rare():
			return coin
	return null


## The step between bids at this price.
static func increment(price: float) -> float:
	for step in [[100.0, 5.0], [200.0, 10.0], [500.0, 20.0], [1000.0, 50.0], [2000.0, 100.0], [5000.0, 200.0],
			[10000.0, 500.0], [20000.0, 1000.0], [50000.0, 2000.0], [100000.0, 5000.0], [200000.0, 10000.0]]:
		if price < step[0]:
			return step[1]
	return 20000.0


## `usd` rounded to the bid step there.
static func nice(usd: float) -> float:
	var step := increment(usd)
	return maxf(step, roundf(usd / step) * step)


## What winning at `hammer` costs you, the buyer's premium included.
static func price_with_premium(hammer: float) -> float:
	return snappedf(hammer * (1.0 + BUYERS_PREMIUM), 0.01)


static func can_afford(hammer: float) -> bool:
	return Shop.cash >= price_with_premium(hammer)


# ---------------------------------------------------------------- the viewing and your lots

## Opens a sealed pouch at the viewing. True when it was opened.
static func view(lot: Dictionary, i: int) -> bool:
	if views_left <= 0 or i < 0 or i >= lot.items.size():
		return false
	var it: Dictionary = lot.items[i]
	if not it.pouch or it.seen:
		return false
	it.seen = true
	views_left -= 1
	return true


## Rare coins in the vault you could put in this sale (not set aside for an order).
static func consignable() -> Array[BullionItem]:
	var out: Array[BullionItem] = []
	if lots.filter(func(l): return l.kind == "mine").size() >= MAX_CONSIGN:
		return out
	for coin in Shop.rare_list():
		if Shop.spare_of(coin) > 0:
			out.append(coin)
	return out


## Takes one rare coin out of the vault and adds it to the end of the sale.
static func consign(coin: BullionItem) -> bool:
	if not coin in consignable() or held_day == Shop.day:
		return false
	var taken := Shop.take_stock(coin.metal, 1, coin)
	if taken.fakes > 0:
		# a fake that slipped past you: Ashworth & Finch's expert spots it and hands it back
		Shop.add_stock(coin, 1, taken.cost, _fake_kind(coin))
		Shop.log_event(Loc.t("Ashworth & Finch's expert says your %s is a fake. They won't sell it.") % coin.display_name, "bad")
		return false
	var it := _group(coin, 1)
	it.cost = taken.cost
	lots.append({"kind": "mine", "who": "", "items": [it], "seed": coin.id.hash() % 1000000})
	_number()
	Shop.log_event(Loc.t("Consigned your %s to today's sale.") % coin.display_name)
	return true


## Rare coins you consigned to a sale you never sat down at go back in the vault.
static func return_unsold() -> void:
	for lot in lots:
		if lot.kind == "mine" and lot.result.is_empty():
			var it: Dictionary = lot.items[0]
			Shop.add_stock(coin_of(it), 1, float(it.cost))
			lot.result = {"winner": "", "name": "", "hammer": 0.0}


static func _fake_kind(coin: BullionItem) -> String:
	for lot in Shop.stock:
		if lot.item == coin and lot.fake != "":
			return lot.fake
	return "brass"


# ---------------------------------------------------------------- the sale

## The people in the room, seats left to right: Victor Sterling, Lucky Lou unless the
## pawn shop is shut, a dealer and two collectors. Seeded by the day.
static func attendees() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = Shop.day * 4241 + 3
	var out: Array[Dictionary] = []
	var collectors := Orders.COLLECTOR_NAMES.duplicate()
	var c1: String = collectors.pop_at(rng.randi() % collectors.size())
	var c2: String = collectors.pop_at(rng.randi() % collectors.size())
	out.append({"who": "collector", "name": c1, "look": rng.randi()})
	out.append({"who": "sterling", "name": Rivals.SHOPS.sterling.owner, "look": 0})
	if Rivals.is_open("pawn"):
		out.append({"who": "pawn", "name": Rivals.SHOPS.pawn.owner, "look": 0})
	out.append({"who": "dealer", "name": DEALERS[rng.randi() % DEALERS.size()], "look": rng.randi()})
	out.append({"who": "collector", "name": c2, "look": rng.randi()})
	return out


## Marks the sale as held today (going in starts it; leaving sells what's left).
static func begin() -> void:
	held_day = Shop.day


## Books a lot's result: your winnings into the vault, your lot's proceeds, or a rival's buy.
static func settle(lot: Dictionary, winner: String, name: String, hammer: float, rival_value := 0.0) -> void:
	lot.result = {"winner": winner, "name": name, "hammer": hammer}
	if lot.kind == "mine":
		_settle_mine(lot, winner, hammer)
		return
	if winner == "you":
		_settle_won(lot, hammer)
	elif winner == "sterling" or winner == "pawn":
		# the rival's shop gains what the lot is worth over what they paid
		var gain := rival_value - price_with_premium(hammer)
		Rivals.state[winner].worth = maxf(0.0, Rivals.worth_of(winner) + gain)
		Rivals.changed.emit()


static func _settle_won(lot: Dictionary, hammer: float) -> void:
	var pay := price_with_premium(hammer)
	Day.add_expense("Auction house", pay)
	won += 1
	spent += pay
	Shop.note("auction_won")
	# the price is shared out over the coins by what they're really worth
	var worth := 0.0
	for it in lot.items:
		worth += true_value(it)
	var junk := 0
	for it in lot.items:
		if it.junk:
			junk += int(it.qty)
			continue
		var share: float = true_value(it) / worth if worth > 0.0 else 1.0 / lot.items.size()
		Shop.add_stock(coin_of(it), int(it.qty), pay * share / int(it.qty))
		if it.pouch and coin_of(it).rare:
			sleepers += 1
			Shop.note("sleepers")
			Shop.log_event(Loc.t("A sealed pouch held a %s! A sleeper.") % coin_of(it).display_name, "good")
	Shop.log_event(Loc.t("Won lot %d for %s with the buyer's premium.") % [lot.n, Market.format_money(pay)], "good")
	if junk > 0:
		Shop.log_event(Loc.n("A pouch held %d brass copy. Worthless.", "A pouch held %d brass copies. Worthless.", junk) % junk, "bad")


static func _settle_mine(lot: Dictionary, winner: String, hammer: float) -> void:
	var it: Dictionary = lot.items[0]
	if winner == "":
		Shop.add_stock(coin_of(it), 1, float(it.cost))
		Shop.log_event(Loc.t("Your %s didn't reach its reserve. It's back in the vault.") % coin_of(it).display_name)
		return
	var proceeds := snappedf(hammer * (1.0 - SELLERS_FEE), 0.01)
	Day.add_income("Auction house (your lots)", proceeds)
	sold_for += proceeds
	Shop.note("profit", proceeds - float(it.cost))
	Shop.log_event(Loc.t("Your %s sold for %s after the fee.") % [coin_of(it).display_name, Market.format_money(proceeds)], "good")


## The lowest price your own lot sells for: its melt.
static func reserve(lot: Dictionary) -> float:
	return nice(melt_of(lot.items[0])) if lot.kind == "mine" else 0.0


# ---------------------------------------------------------------- saving

static func to_dict() -> Dictionary:
	return {"catalogue_day": catalogue_day, "held_day": held_day, "lots": lots.duplicate(true), "views_left": views_left,
		"won": won, "spent": spent, "sleepers": sleepers, "sold_for": sold_for}


static func from_dict(d: Dictionary) -> void:
	lots.clear()
	for lot in d.get("lots", []):
		if typeof(lot) != TYPE_DICTIONARY or typeof(lot.get("items")) != TYPE_ARRAY:
			continue
		var items: Array = []
		for it in lot.items:
			if typeof(it) == TYPE_DICTIONARY and Shop.coins.has(it.get("coin", "")):
				items.append({"coin": it.coin, "qty": maxi(1, int(it.get("qty", 1))), "pouch": bool(it.get("pouch", false)),
					"seen": bool(it.get("seen", false)), "junk": bool(it.get("junk", false)), "guess": float(it.get("guess", 0.0)),
					"cost": float(it.get("cost", 0.0))})
		if items.is_empty():
			continue
		var result = lot.get("result", {})
		lots.append({"kind": str(lot.get("kind", "estate")), "who": str(lot.get("who", "")), "items": items,
			"seed": int(lot.get("seed", 0)), "result": result if typeof(result) == TYPE_DICTIONARY else {}})
	_number()
	catalogue_day = int(d.get("catalogue_day", 0))
	held_day = int(d.get("held_day", 0))
	views_left = int(d.get("views_left", 0))
	won = int(d.get("won", 0))
	spent = float(d.get("spent", 0.0))
	sleepers = int(d.get("sleepers", 0))
	sold_for = float(d.get("sold_for", 0.0))


# ---------------------------------------------------------------- display

## A lot's name in the catalogue, in the player's language.
static func title_of(lot: Dictionary) -> String:
	match str(lot.kind):
		"estate":
			return Loc.t("Estate of the late %s") % lot.who
		"bulk":
			return Loc.t("Dealer stock from %s") % lot.who
		"mine":
			return Loc.t("Your %s") % coin_of(lot.items[0]).display_name
	return coin_of(lot.items[0]).display_name


## One line of a lot's contents: "12 × Silver Eagle", or a sealed pouch until it's opened.
static func label_of(it: Dictionary) -> String:
	if it.pouch and not it.seen:
		return Loc.t("Sealed pouch")
	if it.junk:
		return Loc.n("%d brass copy", "%d brass copies", int(it.qty)) % int(it.qty)
	return "%d × %s" % [int(it.qty), coin_of(it).display_name]
