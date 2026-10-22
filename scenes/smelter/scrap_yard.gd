class_name ScrapYard
extends RefCounted
## The scrap side of the business, once the melting furnace is bought. Each morning the
## scrap dealer offers a few lots (broken chains, dental gold, sterling flatware) for less
## than the metal they should hold, and what you buy waits in the scrap bin until you
## melt it into a bar at the Smelter. A lot is honest about its weight, not always about
## its karat, and steel hides in it (clasp springs, knife blades, the rods in candlesticks):
## only the bar's assay tells the truth. The bullion dealer buys cast bars at CAST_SHARE
## of spot, plus the bullion dealer account's bonus.

## Lot templates. grams: alloy weight range at the corner counter; steel: how many steel
## bits and grams each; dirt: dross the scrap brings into the melt (enamel, porcelain,
## solder, pitch); art: what the pieces look like on the sorting tray.
const LOTS := {
	"XAU": [
		{"name": "Broken gold chains", "stamp": "14K", "claimed": 0.585, "grams": Vector2(25, 70), "steel": Vector2i(2, 5), "steel_g": 0.4, "dirt": 0.15, "art": "chain"},
		{"name": "Odd earrings and rings", "stamp": "mostly 14K", "claimed": 0.585, "grams": Vector2(15, 45), "steel": Vector2i(0, 3), "steel_g": 0.3, "dirt": 0.25, "art": "ring"},
		{"name": "Old class rings", "stamp": "10K", "claimed": 0.417, "grams": Vector2(30, 80), "steel": Vector2i(0, 0), "steel_g": 0.0, "dirt": 0.4, "art": "class_ring"},
		{"name": "Dental gold", "stamp": "16K", "claimed": 0.667, "grams": Vector2(8, 25), "steel": Vector2i(0, 2), "steel_g": 0.5, "dirt": 0.6, "art": "dental"},
	],
	"XAG": [
		{"name": "Sterling flatware", "stamp": "STERLING", "claimed": 0.925, "grams": Vector2(300, 900), "steel": Vector2i(2, 5), "steel_g": 9.0, "dirt": 0.25, "art": "spoon"},
		{"name": "Coin silver spoons", "stamp": "COIN", "claimed": 0.9, "grams": Vector2(150, 450), "steel": Vector2i(0, 0), "steel_g": 0.0, "dirt": 0.2, "art": "spoon"},
		{"name": "Broken silver chains", "stamp": "925", "claimed": 0.925, "grams": Vector2(80, 300), "steel": Vector2i(2, 6), "steel_g": 0.4, "dirt": 0.15, "art": "chain"},
		{"name": "Tarnished candlesticks", "stamp": "STERLING", "claimed": 0.925, "grams": Vector2(250, 700), "steel": Vector2i(1, 2), "steel_g": 12.0, "dirt": 0.65, "art": "candle"},
	],
}
## What the dealer asks, as a share of the metal the lot's stamp promises.
const PRICE_SHARE := Vector2(0.8, 0.88)
## A lot's true fineness against its stamp, and the odds it was salted with plated junk.
const TRUTH := Vector2(0.95, 1.01)
const SALTED_ODDS := 0.12
const SALTED_SHARE := 0.8
## What the bullion dealer pays for a cast bar, as a share of the fine metal's spot value,
## before the bullion dealer account (bar_payout) adds its bit.
const CAST_SHARE := 0.97
## Odds of a third lot on the dealer's van.
const EXTRA_LOT_ODDS := 0.25

## Lots bought and not yet melted, and the lots on offer this morning. Each lot:
## {"name", "metal", "stamp", "claimed", "purity", "grams", "steel", "steel_g", "dirt", "cost", "art", "seed"}
## (`cost` is the price paid, or the asking price for an offer). Saved with the game.
static var bin: Array[Dictionary] = []
static var offers: Array[Dictionary] = []
static var offer_day := 0
## Lifetime: bars cast, and what the dealer paid for them less what their scrap cost.
static var bars_cast := 0
static var lifetime := 0.0
static var _hooked := false


static func hook_up() -> void:
	if _hooked:
		return
	_hooked = true
	Progress.register_upgrade("furnace", {"name": "Melting furnace", "cost": 9000.0, "tier": 1, "line": "tools",
		"desc": "A gas furnace in the back. Each morning the scrap dealer offers broken gold and silver: melt it into bars at the Smelter and sell them to the bullion dealer.",
		"effects": {}})
	SaveGame.register("scrap", func(): return to_dict(), func(d): from_dict(d))
	SaveGame.new_game_started.connect(func(): from_dict({}))
	Day.day_started.connect(func(_d): refresh_offers())
	Progress.upgrade_bought.connect(func(id):
		if id == "furnace":
			refresh_offers())
	# a title screen may have loaded the save before this ran
	if SaveGame.has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("scrap")) == TYPE_DICTIONARY:
			from_dict(data.scrap)


static func owned() -> bool:
	return Progress.has_upgrade("furnace")


## Whether the Smelter can open now: the furnace is bought and it's morning.
static func available() -> bool:
	return owned() and Day.phase == Day.MORNING


## Rolls this morning's lots once a day, while the furnace is owned.
static func refresh_offers(rng: RandomNumberGenerator = null) -> void:
	if not owned() or offer_day == Shop.day:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	offer_day = Shop.day
	offers.clear()
	offers.append(roll_lot("XAU", rng))
	offers.append(roll_lot("XAG", rng))
	if rng.randf() < EXTRA_LOT_ODDS:
		offers.append(roll_lot("XAU" if rng.randf() < 0.5 else "XAG", rng))


## One lot of `metal` from the dealer's van, sized for the shop.
static func roll_lot(metal: String, rng: RandomNumberGenerator) -> Dictionary:
	var kinds: Array = LOTS[metal]
	var t: Dictionary = kinds[rng.randi() % kinds.size()]
	var size := Progress.deal_size() * (1.0 + Progress.effect("scrap_size"))
	var grams := snappedf(rng.randf_range(t.grams.x, t.grams.y) * size, 0.1)
	var steel := rng.randi_range(t.steel.x, t.steel.y)
	var purity: float = t.claimed * rng.randf_range(TRUTH.x, TRUTH.y)
	if rng.randf() < SALTED_ODDS:
		purity *= SALTED_SHARE
	var lot := {"name": t.name, "metal": metal, "stamp": t.stamp, "claimed": t.claimed, "purity": snappedf(purity, 0.0001),
		"grams": grams, "steel": steel, "steel_g": t.steel_g, "dirt": t.dirt, "art": t.art, "seed": rng.randi() % 1000000}
	lot["cost"] = snappedf(claimed_value(lot) * rng.randf_range(PRICE_SHARE.x, PRICE_SHARE.y), 0.01)
	return lot


## Gross weight of a lot: the precious alloy plus the steel in it.
static func gross(lot: Dictionary) -> float:
	return float(lot.grams) + int(lot.steel) * float(lot.steel_g)


## Spot value of the fine metal the lot's stamp promises, at its gross weight.
static func claimed_value(lot: Dictionary) -> float:
	return spot_per_gram(lot.metal) * gross(lot) * float(lot.claimed)


static func spot_per_gram(metal: String) -> float:
	return Market.value_of(metal, 1.0) / Market.TROY_OZ_GRAMS


## Share of spot the bullion dealer pays for a cast bar.
static func cast_share() -> float:
	return CAST_SHARE + Progress.effect("bar_payout")


static func can_buy(i: int) -> bool:
	return i >= 0 and i < offers.size() and Shop.cash >= float(offers[i].cost)


## Buys offer `i` into the scrap bin.
static func buy(i: int) -> bool:
	if not can_buy(i):
		return false
	var lot: Dictionary = offers[i]
	offers.remove_at(i)
	Day.add_expense("Scrap dealer", lot.cost)
	bin.append(lot)
	Shop.log_event("Bought %s (%s g) from the scrap dealer for %s." % [lot.name.to_lower(), _grams(gross(lot)), Market.format_money(lot.cost)])
	return true


## The scrap waiting to be melted, at what it cost (it counts in net worth).
static func bin_value() -> float:
	var total := 0.0
	for lot in bin:
		total += float(lot.cost)
	return total


## Lots in the bin of one metal.
static func lots_of(metal: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lot in bin:
		if lot.metal == metal:
			out.append(lot)
	return out


## Takes every lot of `metal` out of the bin for one melt.
static func take(metal: String) -> Array[Dictionary]:
	var out := lots_of(metal)
	bin = bin.filter(func(l): return l.metal != metal)
	return out


## Puts metal back in the bin: what froze in the crucible, or a melt you walked away from.
static func put_back(lot: Dictionary) -> void:
	if float(lot.grams) > 0.05 or int(lot.steel) > 0:
		bin.append(lot)


## Sells a finished bar to the bullion dealer and books it. `cost` is what its scrap cost.
static func sell_bar(payout: float, cost: float, metal: String) -> void:
	bars_cast += 1
	lifetime += payout - cost
	Shop.note("bars_cast")
	Shop.note("profit", payout - cost)
	if payout > 0.0:
		Day.add_income("Bullion dealer (cast bars)", payout)
	var what := "gold" if metal == "XAU" else "silver"
	Shop.log_event("The bullion dealer paid %s for your %s bar (%s %s)." % [Market.format_money(payout), what,
		"profit" if payout >= cost else "loss", Market.format_money(absf(payout - cost))], "good" if payout >= cost else "bad")


static func _grams(g: float) -> String:
	return "%.0f" % g if g >= 100.0 else "%.1f" % g


static func to_dict() -> Dictionary:
	return {"bin": bin.duplicate(true), "offers": offers.duplicate(true), "offer_day": offer_day,
		"bars_cast": bars_cast, "lifetime": lifetime}


static func from_dict(d: Dictionary) -> void:
	bin.clear()
	offers.clear()
	for lot in d.get("bin", []):
		if typeof(lot) == TYPE_DICTIONARY and lot.has("metal"):
			bin.append(lot)
	for lot in d.get("offers", []):
		if typeof(lot) == TYPE_DICTIONARY and lot.has("metal"):
			offers.append(lot)
	offer_day = int(d.get("offer_day", 0))
	bars_cast = int(d.get("bars_cast", 0))
	lifetime = float(d.get("lifetime", 0.0))
