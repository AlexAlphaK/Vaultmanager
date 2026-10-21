extends Node
## Headless checks for the shop and the coin test. Run:
##   godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 when everything passes, 1 otherwise.

var failures := 0


func _ready() -> void:
	_check_coins()
	_check_fakes_are_detectable()
	_check_stock()
	await _check_shop_day()
	print("SMOKE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _check_coins() -> void:
	expect(Shop.coins.size() >= 7, "all coin specs load")
	for item in Shop.coin_list():
		expect(item.thickness_mm > 0.0 and item.diameter_mm > 0.0, "%s has dimensions" % item.id)
		expect(CoinArt.MOTIFS.has(item.motif), "%s has a motif" % item.id)
		var art := CoinArt.paint(item, "", 1)
		expect(art.width == CoinArt.radius_of(item) * 2 + 4, "%s paints at its radius" % item.id)
		expect(item.melt_value() > 0.0, "%s has a melt value at market prices" % item.id)


## Every counterfeit must fail at least one test a careful player can run.
func _check_fakes_are_detectable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for item in Shop.coin_list():
		var genuine := Counterfeit.readings(item, "", rng)
		expect(_looks_genuine(item, genuine), "genuine %s passes every test" % item.id)
		for kind in Counterfeit.kinds_for(item.metal, 99):
			for n in 20:
				var r := Counterfeit.readings(item, kind, rng)
				expect(not _looks_genuine(item, r), "%s %s fails a test" % [kind, item.id])


func _looks_genuine(item: BullionItem, r: Dictionary) -> bool:
	var ring := item.ring_seconds()
	return absf(r.g - item.weight_g) <= 0.05 and absf(r.mm - item.diameter_mm) <= 0.1 \
		and absf(r.thick - item.thickness_mm) <= 0.06 and r.ring >= ring.x - 0.01 \
		and r.magnet == ("slight" if item.metal == "XAG" else "none")


func _check_stock() -> void:
	Shop.reset()
	var cash := Shop.cash
	var eagle: BullionItem = Shop.coins["silver_eagle"]
	var before := Shop.count_of("XAG")
	Shop.add_stock(eagle, 4, 30.0, "clad")
	expect(Shop.count_of("XAG") == before + 4, "stock adds")
	var taken := Shop.take_stock("XAG", before)
	expect(taken.fakes == 0, "genuine coins leave first")
	expect(Shop.confiscate(eagle, "clad") == 4, "assay lab removes fakes")
	expect(Shop.count_of("XAG") == 0, "silver all gone")
	expect(is_equal_approx(Shop.cash, cash), "stock moves do not touch cash")
	Shop.reset()


func _check_shop_day() -> void:
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# a seller with fakes, bought untested: the assay lab catches it later
	var c := Customer.create(1, 2.5, Shop.coin_list(), rng)
	c.kind = "seller"
	c.item = Shop.coins["gold_maple"]
	c.fake = "steel"
	c.qty = 2
	c.reserve = 0.5
	shop.queue.append(c)
	c.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	expect(shop._front() == c, "customer reaches the counter")
	var cash := Shop.cash
	shop._on_action("offer")
	expect(Shop.cash < cash, "buying pays the seller")
	expect(shop.pending_fakes.size() == 1, "fake purchase is pending assay")
	shop.time += 9.0
	shop._tick(0.0)
	expect(shop.pending_fakes.is_empty() and Shop.stats.scammed == 1.0, "assay lab catches the fake")
	# a tested genuine seller via the minigame verdict
	var g := Customer.create(1, 2.5, Shop.coin_list(), rng)
	g.kind = "seller"
	g.fake = ""
	shop.queue.append(g)
	g.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(g)
	for tool in ["scale", "calipers", "ping", "magnet", "loupe"]:
		shop._test.use_tool(tool)
	await get_tree().create_timer(0.5).timeout
	shop._test.finished.emit("genuine")
	expect(g.tested, "verdict marks the coin tested")
	# a tested seller the shop can't afford can still be turned away
	var hud: Control = shop.get_node("Hud/Root")
	var cash_before := Shop.cash
	Shop.add_cash(-Shop.cash)
	hud.show_customer(g)
	expect(hud._buttons.offer.disabled and hud._buttons.refuse.visible, "an unaffordable seller can be refused")
	shop._on_action("refuse")
	expect(not shop.queue.has(g), "refusing sends the seller away")
	Shop.add_cash(cash_before)
	# a buyer
	Shop.add_stock(Shop.coins["silver_maple"], 10, 40.0)
	var b := Customer.create(1, 2.5, Shop.coin_list(), rng)
	b.kind = "buyer"
	b.item = Shop.coins["silver_maple"]
	b.qty = 5
	b.max_premium = 0.5
	shop.queue.push_front(b)
	b.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	cash = Shop.cash
	shop._on_action("sell")
	expect(Shop.cash > cash, "selling earns cash")
	# closing time ends the day
	shop.queue.clear()
	shop.leaving.clear()
	shop.time = shop.DAY_SECONDS + 1.0
	shop._tick(0.0)
	expect(shop.paused, "the day closes when the shop empties")
	shop._open_next_day()
	expect(Shop.day == 2 and not shop.paused, "next day opens")
	shop.queue_free()
