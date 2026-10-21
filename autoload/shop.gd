extends Node
## The player's business: cash, reputation, stock and the day's results.
## Stock is valued at live market prices through BullionItem.melt_value().

signal changed
signal logged(text: String, mood: String) # mood: "", "good" or "bad"

const COIN_DIR := "res://data/coins/"

var day := 1
var cash := 25000.0
var reputation := 2.5 # 0 to 5 stars
## Percent of melt the shop pays sellers, and premium over melt it charges buyers.
var buy_percent := 0.92
var sell_premium := 0.06
## Each lot: {"item": BullionItem, "qty": int, "cost": USD per coin, "fake": kind or ""}
var stock: Array[Dictionary] = []
var stats := {}
var coins: Dictionary = {} # id -> BullionItem


func _ready() -> void:
	_load_coins()
	reset()


func reset() -> void:
	day = 1
	cash = 25000.0
	reputation = 2.5
	stock.clear()
	_reset_stats()
	if coins.has("silver_eagle"):
		add_stock(coins["silver_eagle"], 6, 0.0)
	if coins.has("gold_maple"):
		add_stock(coins["gold_maple"], 1, 0.0)
	# opening stock is valued at today's price
	for lot in stock:
		lot.cost = lot.item.melt_value()
	changed.emit()


func coin_list() -> Array[BullionItem]:
	var out: Array[BullionItem] = []
	for id in coins:
		out.append(coins[id])
	return out


func vault_value() -> float:
	var total := 0.0
	for lot in stock:
		total += lot.item.melt_value() * lot.qty
	return total


func net_worth() -> float:
	return cash + vault_value()


## Coins held of one metal.
func count_of(metal: String) -> int:
	var n := 0
	for lot in stock:
		if lot.item.metal == metal:
			n += lot.qty
	return n


## Fine troy ounces held per metal, for the shelf display.
func ounces_by_metal() -> Dictionary:
	var out := {}
	for lot in stock:
		out[lot.item.metal] = out.get(lot.item.metal, 0.0) + lot.item.fine_troy_oz() * lot.qty
	return out


## One entry per coin, for the display case.
func coins_on_display() -> Array:
	var out := []
	for lot in stock:
		for n in lot.qty:
			out.append(lot.item)
	return out


func add_stock(item: BullionItem, qty: int, cost_each: float, fake := "") -> void:
	for lot in stock:
		if lot.item == item and lot.fake == fake:
			lot.cost = (lot.cost * lot.qty + cost_each * qty) / (lot.qty + qty)
			lot.qty += qty
			changed.emit()
			return
	stock.append({"item": item, "qty": qty, "cost": cost_each, "fake": fake})
	changed.emit()


## Takes `qty` coins of `metal`, genuine lots first. Returns {"cost": USD, "fakes": count, "melt": USD}.
func take_stock(metal: String, qty: int) -> Dictionary:
	var result := {"cost": 0.0, "fakes": 0, "melt": 0.0}
	var lots := stock.filter(func(l): return l.item.metal == metal)
	lots.sort_custom(func(a, b): return a.fake == "" and b.fake != "")
	for lot in lots:
		if qty <= 0:
			break
		var n := mini(qty, lot.qty)
		lot.qty -= n
		qty -= n
		result.cost += lot.cost * n
		result.melt += lot.item.melt_value() * n
		if lot.fake != "":
			result.fakes += n
	stock = stock.filter(func(l): return l.qty > 0)
	changed.emit()
	return result


## Removes a fake lot that the assay lab caught. Returns how many coins were removed.
func confiscate(item: BullionItem, fake: String) -> int:
	for lot in stock:
		if lot.item == item and lot.fake == fake:
			var n: int = lot.qty
			stock.erase(lot)
			changed.emit()
			return n
	return 0


func add_cash(usd: float) -> void:
	cash += usd
	changed.emit()


func adjust_reputation(delta: float) -> void:
	reputation = clampf(reputation + delta, 0.0, 5.0)
	changed.emit()


func set_buy_percent(value: float) -> void:
	buy_percent = clampf(snappedf(value, 0.01), 0.70, 1.00)
	changed.emit()


func set_sell_premium(value: float) -> void:
	sell_premium = clampf(snappedf(value, 0.01), 0.0, 0.20)
	changed.emit()


func note(key: String, amount := 1.0) -> void:
	stats[key] = stats.get(key, 0.0) + amount


func log_event(text: String, mood := "") -> void:
	logged.emit(text, mood)


func next_day() -> void:
	day += 1
	_reset_stats()
	Market.start_new_day()
	changed.emit()


## Saved state. Stock lots refer to coins by id.
func to_dict() -> Dictionary:
	var lots := []
	for lot in stock:
		lots.append({"item": lot.item.id, "qty": lot.qty, "cost": lot.cost, "fake": lot.fake})
	return {"day": day, "cash": cash, "reputation": reputation, "buy_percent": buy_percent,
		"sell_premium": sell_premium, "stock": lots}


func from_dict(d: Dictionary) -> void:
	day = maxi(1, int(d.get("day", 1)))
	cash = float(d.get("cash", cash))
	reputation = clampf(float(d.get("reputation", reputation)), 0.0, 5.0)
	buy_percent = float(d.get("buy_percent", buy_percent))
	sell_premium = float(d.get("sell_premium", sell_premium))
	stock.clear()
	for lot in d.get("stock", []):
		if coins.has(lot.get("item", "")) and int(lot.get("qty", 0)) > 0:
			stock.append({"item": coins[lot.item], "qty": int(lot.qty), "cost": float(lot.get("cost", 0.0)), "fake": str(lot.get("fake", ""))})
	_reset_stats()
	changed.emit()


func _reset_stats() -> void:
	stats = {"bought": 0.0, "sold": 0.0, "profit": 0.0, "caught": 0.0, "scammed": 0.0, "served": 0.0}


func _load_coins() -> void:
	var dir := DirAccess.open(COIN_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		# exported builds list resources as *.tres.remap
		var path := COIN_DIR + file.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var item := load(path) as BullionItem
		if item:
			coins[item.id if item.id != "" else file.get_basename()] = item
