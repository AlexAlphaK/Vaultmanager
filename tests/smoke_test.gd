extends Node
## Headless checks for the shop, the coin test, the jewellery appraisal and the vault lock-up. Run:
##   godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 when everything passes, 1 otherwise.

var failures := 0


func _ready() -> void:
	# never touch the player's real save
	SaveGame.path = "user://smoke_test_save.json"
	SaveGame.delete_save()
	_check_coins()
	_check_fakes_are_detectable()
	_check_stock()
	_check_bills_and_upgrades()
	_check_save_load()
	_check_jewellery()
	_check_vault_layout()
	_check_market_events()
	await _check_vault_scene()
	await _check_shop_day()
	await _check_jewellery_deals()
	SaveGame.delete_save()
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


func _check_bills_and_upgrades() -> void:
	SaveGame.new_game()
	Day.begin_day()
	var cash := Shop.cash
	Day.open_shop()
	Day.close_shop()
	var report := Day.end_day()
	expect(is_equal_approx(Shop.cash, cash - Progress.daily_upkeep()), "a weekday only costs upkeep")
	expect(report.ledger.size() == 1 and report.next_bills_in == 6, "report lists upkeep and the next bill day")
	Shop.day = 7
	Day.begin_day()
	cash = Shop.cash
	var insurance := Progress.weekly_insurance()
	Day.end_day()
	expect(is_equal_approx(Shop.cash, cash - Progress.daily_upkeep() - Progress.weekly_rent() - insurance), "rent and insurance are due on day 7")
	expect(Day.phase == Day.AFTER_HOURS, "the day ends after hours")
	# upgrades
	Day.begin_day()
	expect(Progress.buy("bench"), "buy an upgrade")
	expect(not Progress.buy("bench"), "an upgrade is bought once")
	expect(not Progress.can_buy("radio_ads"), "tier 2 upgrades are locked at the corner counter")
	var rng := RandomNumberGenerator.new()
	var c := Customer.create(1, 2.5, Shop.coin_list(), rng)
	expect(is_equal_approx(c.max_patience, 70.0 * 1.25), "the bench makes customers more patient")
	# expansion needs net worth, stars and cash
	expect(Progress.expand_blocker() != "", "cannot expand on day one")
	Shop.cash = 200000.0
	Shop.reputation = 3.5
	expect(Progress.expand() and Progress.tier == 1, "expand to Main Street")
	expect(Progress.can_buy("radio_ads"), "Main Street unlocks more upgrades")
	expect(Progress.weekly_rent() > Progress.TIERS[0].rent, "a bigger shop costs more rent")
	SaveGame.new_game()
	expect(Progress.tier == 0 and Progress.owned.is_empty() and Shop.day == 1, "new game resets progress")


func _check_save_load() -> void:
	SaveGame.new_game()
	Shop.day = 5
	Shop.cash = 12345.0
	Shop.reputation = 3.2
	Shop.add_stock(Shop.coins["krugerrand"], 2, 3000.0, "tungsten")
	Progress.tier = 1
	Progress.owned.append("alarm")
	expect(SaveGame.save_game(), "the game saves")
	var lots := Shop.stock.size()
	Shop.reset()
	Progress.reset()
	expect(SaveGame.load_game(), "the save loads")
	expect(Shop.day == 5 and is_equal_approx(Shop.cash, 12345.0) and is_equal_approx(Shop.reputation, 3.2), "day, cash and stars come back")
	expect(Shop.stock.size() == lots and Shop.count_of("XAU") >= 2, "stock comes back")
	expect(Shop.stock.any(func(l): return l.fake == "tungsten"), "hidden fakes stay hidden fakes")
	expect(Progress.tier == 1 and Progress.has_upgrade("alarm"), "tier and upgrades come back")
	SaveGame.new_game()
	expect(not SaveGame.has_save(), "new game deletes the save")


func _check_market_events() -> void:
	var saved_source := Market.source
	var saved_crypto := Market.crypto.duplicate(true)
	var saved_change := Market.metals_change.duplicate()
	MarketEvents.stop()
	MarketEvents.advance(MarketEvents.COOLDOWN_SECONDS + 1.0)
	Market.source = "live"
	# calm markets make no news
	Market.crypto = {"BTC": {"price": 60000.0, "change_pct": 1.0}}
	Market.metals_change = {"XAU": 0.2, "XAG": -0.4, "XPT": 0.0}
	MarketEvents.evaluate()
	expect(MarketEvents.active.is_empty(), "a calm market starts no event")
	# a Bitcoin crash brings crypto converts who buy gold
	Market.crypto.BTC.change_pct = -7.5
	MarketEvents.evaluate()
	expect(MarketEvents.active.get("id") == "btc_crash", "a Bitcoin crash starts the crypto convert rush")
	expect(MarketEvents.headline(MarketEvents.active).contains("-7.5%"), "the headline shows the real move")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ev := MarketEvents.active.duplicate()
	ev.share = 1.0
	var c := Customer.create(1, 2.5, Shop.coin_list(), rng, ev)
	expect(c.kind == "buyer" and c.item.metal == "XAU" and c.event_id == "btc_crash", "event customers follow the event")
	expect(ev.lines.has(c.say), "event customers talk about the news")
	expect(MarketEvents.spawn_factor() < 1.0, "events bring customers faster")
	# it runs out, and does not fire again until the move fades
	MarketEvents.advance(MarketEvents.EVENT_SECONDS + 1.0)
	expect(MarketEvents.active.is_empty(), "the event ends on its own")
	MarketEvents.advance(MarketEvents.COOLDOWN_SECONDS + 1.0)
	expect(MarketEvents.active.is_empty(), "a news story does not repeat while it is still true")
	Market.crypto.BTC.change_pct = -1.0
	MarketEvents.evaluate()
	# a gold dip over the last real day: panic sellers who take less
	Market.metals_change.XAU = -1.8
	MarketEvents.evaluate()
	expect(MarketEvents.active.get("id") == "gold_dip", "a gold dip starts the panic sellers")
	ev = MarketEvents.active.duplicate()
	ev.share = 1.0
	var reserves := 0.0
	for n in 20:
		var s := Customer.create(1, 2.5, Shop.coin_list(), rng, ev)
		expect(s.kind == "seller" and s.item.metal == "XAU", "panic sellers bring gold")
		reserves += s.reserve
	expect(reserves / 20.0 < 0.86, "panic sellers accept less than usual")
	MarketEvents.stop()
	MarketEvents.advance(MarketEvents.COOLDOWN_SECONDS + 1.0)
	Market.source = saved_source
	Market.crypto = saved_crypto
	Market.metals_change = saved_change


func _check_shop_day() -> void:
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	# a script that fails to parse leaves a bare node, and every check below would error out silently
	if not shop.has_method("_open_shop"):
		expect(false, "the shop script loads")
		return
	expect(shop.paused and Day.phase == Day.MORNING, "the day starts in the morning, shop shut")
	expect(SaveGame.has_save(), "the morning is saved")
	shop._open_shop()
	expect(not shop.paused and Day.phase == Day.OPEN, "open the shop")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# a seller with fakes, bought untested: the assay lab catches it later
	var c := Customer.create(1, 2.5, Shop.coin_list(), rng)
	c.kind = "seller"
	c.item = Shop.coins["gold_maple"]
	c.fake = "steel"
	c.piece = null
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
	g.piece = null
	shop.queue.push_front(g)
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
	expect(shop.paused and shop._vault != null, "closing time opens the vault lock-up")
	shop._vault.lock_up()
	shop._vault.finished.emit(shop._vault.report)
	expect(shop._vault == null and Day.phase == Day.AFTER_HOURS, "the day closes after the lock-up")
	expect(shop.hud._panels.page == "summary", "the end-of-day summary is up")
	shop._open_next_day()
	expect(Shop.day == 2 and shop.paused and Day.phase == Day.MORNING, "next morning starts")
	shop._open_shop()
	expect(not shop.paused, "day 2 opens")
	shop.queue_free()


## Every jewellery fraud must show up on at least one bench test, values must follow
## the claim and the truth, and every kind of piece must paint at every scale.
func _check_jewellery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var frauds := {}
	for n in 400:
		var p := JewelleryPiece.create(1 + n % 5, rng)
		var claimed := JewelleryPiece.new()
		claimed.metal = p.metal
		claimed.true_grade = p.claimed_grade
		var acid_differs := false
		for acid in JewelleryPiece.ACIDS:
			if p.acid_reaction(acid) != claimed.acid_reaction(acid):
				acid_differs = true
		if p.true_grade != p.claimed_grade:
			frauds["grade"] = true
			expect(acid_differs, "%s %s claimed %s shows on the acids" % [p.true_grade, p.kind, p.claimed_grade])
		else:
			expect(not acid_differs, "honest %s %s passes the acids" % [p.claimed_grade, p.kind])
		if p.stone != "" and p.stone != "diamond":
			frauds[p.stone] = true
			expect(p.tester_leds() < 10 or p.stone == "moissanite", "%s fails the thermal tester" % p.stone)
		if p.true_grade == "plated" and p.base_metal == "steel":
			expect(p.magnet() == "strong", "plated steel snaps to the magnet")
		expect(p.claimed_g > 0.0 and p.weight_g > 0.0, "%s has a weight" % p.kind)
		if p.true_grade == p.claimed_grade and p.stone in ["", "diamond"]:
			expect(is_equal_approx(p.value_as(p.claimed_grade, p.stone != "", p.weight_g), p.true_value()), "honest %s is worth its claim" % p.kind)
		expect(p.expected_value() <= p.true_value() + 0.01, "nobody expects more than a piece is worth")
	for kind in ["grade", "cz", "glass", "moissanite"]:
		expect(frauds.has(kind), "fraud kind %s turns up" % kind)
	for kind in ["ring", "chain", "bracelet", "pendant"]:
		var p := JewelleryPiece.new()
		p.kind = kind
		p.stone = "diamond" if kind in ["ring", "pendant"] else ""
		p.carat = 0.5
		p.seed = 3
		for scale in [1, JewelleryArt.BENCH_SCALE, JewelleryArt.DETAIL_SCALE]:
			var art := JewelleryArt.paint(p, scale)
			expect(art.width == int(JewelleryArt.SIZE.x) * scale, "%s paints at scale %d" % [kind, scale])
			expect(not art.image.is_invisible(), "%s has pixels at scale %d" % [kind, scale])


func _check_jewellery_deals() -> void:
	Shop.reset()
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop.has_method("_open_shop"):
		return
	shop._open_shop()
	shop.queue.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# a plated ring bought as is: the refiner finds out
	var c := _jewellery_seller(rng, "XAU", "18K")
	c.piece.apply_fraud("plated", 1, rng)
	c.piece.claimed_g = c.piece.weight_g
	shop.queue.push_front(c)
	c.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	var cash := Shop.cash
	shop._on_action("offer")
	expect(Shop.cash < cash and shop.pending_pieces.size() == 1, "buying a piece pays the seller")
	shop.time += 9.0
	shop._tick(0.0)
	expect(shop.pending_pieces.is_empty() and Shop.stats.scammed == 1.0, "the refiner catches plating")
	# an under-karat ring, appraised with the bench tools
	var u := _jewellery_seller(rng, "XAU", "18K")
	u.piece.apply_fraud("underkarat", 1, rng)
	shop.queue.push_front(u)
	u.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(u)
	var bench: Control = shop._test
	for tool in ["scale", "acid", "tester", "magnet", "loupe"]:
		bench.use_tool(tool)
	for acid in JewelleryPiece.ACIDS:
		bench.drop_acid(acid)
	await get_tree().create_timer(3.2).timeout
	var summary: String = bench._acid_summary()
	expect(summary.contains("<") and not summary.contains("18K+"), "acid dissolves an under-karat streak (%s)" % summary)
	while bench.grade != u.piece.true_grade:
		bench.cycle_grade(1)
	bench.finish()
	expect(u.tested and u.assessed.grade == u.piece.true_grade, "the appraisal is recorded")
	expect(is_equal_approx(u.melt_total(), u.piece.true_value()), "an accurate appraisal values the piece truly")
	cash = Shop.cash
	shop._on_action("offer")
	expect(Shop.cash < cash, "the seller takes a fair offer at the true karat")
	shop.time += 9.0
	shop._tick(0.0)
	expect(Shop.cash > cash - u.offer_total() * 0.5, "the refiner pays out for a fairly bought piece")
	# calling a genuine piece plated sends the customer away
	var g := _jewellery_seller(rng, "XAU", "14K")
	shop.queue.push_front(g)
	g.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(g)
	shop._test.grade = "plated"
	shop._test.finish()
	expect(not shop.queue.has(g), "an insulted customer leaves")
	shop.queue_free()
	Shop.reset()


func _jewellery_seller(rng: RandomNumberGenerator, metal: String, grade: String) -> Customer:
	var c := Customer.create(1, 2.5, Shop.coin_list(), rng)
	c.kind = "seller"
	c.fake = ""
	c.reserve = 0.85
	var p := JewelleryPiece.new()
	p.kind = "ring"
	p.metal = metal
	p.claimed_grade = grade
	p.true_grade = grade
	p.weight_g = 5.0
	p.claimed_g = 5.0
	p.stamp = grade
	p.seed = rng.randi()
	c.piece = p
	c.qty = 1
	return c


func _check_vault_layout() -> void:
	Shop.reset()
	Progress.tier = 0
	Progress.owned.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var v := VaultLayout.from_shop(rng)
	var kinds := v.pieces.map(func(p): return p.kind)
	expect(kinds.count("tube") == 1 and kinds.count("gold_box") == 1 and kinds.count("ledger") == 1, "starting stock packs into a tube, a gold box and the ledger")
	expect(kinds.count("cash") == 3, "cash splits into straps")
	expect(is_equal_approx(v.total_value(), Shop.net_worth()), "the pieces carry the whole net worth")
	expect(is_equal_approx(v.out_share(), 1.0), "everything starts on the tray")
	var seen := {}
	var overlap := false
	for p in v.pieces:
		for c in VaultLayout.cells_of(p.kind, p.rot):
			overlap = overlap or seen.has(p.cell + c)
			seen[p.cell + c] = true
	expect(not overlap, "nothing overlaps on the tray")
	expect(VaultLayout.footprint("tube", 1) == Vector2i(1, 3), "a tube turns upright")
	expect(VaultLayout.cells_of("cash", 4) == VaultLayout.cells_of("cash", 0), "four turns come back round")
	var tube: Dictionary = v.pieces.filter(func(p): return p.kind == "tube")[0]
	var gold: Dictionary = v.pieces.filter(func(p): return p.kind == "gold_box")[0]
	var cash: Array = v.pieces.filter(func(p): return p.kind == "cash")
	var ledger: Dictionary = v.pieces.filter(func(p): return p.kind == "ledger")[0]
	expect(v.place(tube, VaultLayout.FLOOR, Vector2i(0, 0), 0), "a tube fits the floor safe")
	expect(not v.can_place(gold, VaultLayout.FLOOR, Vector2i(1, 0), 0), "pieces can't overlap")
	expect(not v.can_place(gold, VaultLayout.WALL, Vector2i(3, 0), 0), "pieces can't hang out of a safe")
	var fits: bool = v.place(gold, VaultLayout.FLOOR, Vector2i(3, 0), 0) \
		and v.place(cash[0], VaultLayout.FLOOR, Vector2i(0, 1), 0) \
		and v.place(cash[1], VaultLayout.FLOOR, Vector2i(1, 1), 2) \
		and v.place(cash[2], VaultLayout.WALL, Vector2i(0, 0), 0) \
		and v.place(ledger, VaultLayout.WALL, Vector2i(2, 0), 0)
	expect(fits, "the starting stock fits in the two safes")
	expect(v.out_share() == 0.0 and is_equal_approx(v.risk(0.0), 0.04), "a tidy vault has the lowest risk")
	expect(v.risk(1.0) > v.risk(0.0), "staying open late raises the risk")
	var quiet := v.resolve(0.0, rng)
	expect(not quiet.break_in and quiet.stolen.is_empty(), "no break-in, nothing lost")
	# leave the tube and a strap out, and make the wall safe uncrackable
	v.areas[VaultLayout.WALL].crack = 0.0
	v.place(tube, VaultLayout.TRAY, Vector2i(0, 0), 0)
	v.place(cash[0], VaultLayout.TRAY, Vector2i(0, 2), 0)
	expect(v.risk(0.0) > 0.04, "stock left out raises the risk")
	var before := Shop.cash
	var report := v.resolve(1.0, rng)
	expect(report.break_in and report.stolen.size() == 2, "burglars take only what's on the tray")
	v.apply(report)
	expect(Shop.count_of("XAG") == 0 and Shop.count_of("XAU") == 1, "stolen coins leave the stock")
	expect(is_equal_approx(Shop.cash, before - cash[0].cash), "stolen cash leaves the till")
	expect(Shop.stats.get("stolen", 0.0) > 0.0, "the loss is counted")
	# a big silver stack packs into monster boxes
	Shop.reset()
	Shop.add_stock(Shop.coins["silver_maple"], 120, 30.0)
	var big := VaultLayout.from_shop(rng)
	var big_kinds := big.pieces.map(func(p): return p.kind)
	expect(big_kinds.count("monster") == 2 and big_kinds.count("tube") == 3, "126 silver coins make 2 monster boxes and 3 tubes")
	# upgrades: a bigger shop widens the floor safe, the second safe and the alarm help too
	Progress.tier = 1
	Progress.owned.assign(["big_safe", "alarm"])
	var up := VaultLayout.from_shop(rng)
	expect(up.areas.floor.size == Vector2i(6, 3) and up.areas.wall.size == Vector2i(4, 3), "upgrades enlarge the safes")
	expect(up.risk(0.0) < VaultLayout.from_shop(rng).risk_scale * 0.04 + 0.5, "the alarm cuts the risk")
	expect(is_equal_approx(up.risk_scale, 0.6), "the alarm takes 40% off the odds")
	Progress.tier = 0
	Progress.owned.clear()
	Shop.reset()


func _check_vault_scene() -> void:
	Shop.reset()
	var vault: Control = load("res://scenes/vault/vault.tscn").instantiate()
	add_child(vault)
	vault.start(5)
	await get_tree().process_frame
	var tube: Dictionary = vault.layout.pieces.filter(func(p): return p.kind == "tube")[0]
	var grab: Vector2 = vault._piece_pos(tube) + Vector2(4, 4)
	vault.pick_up(grab)
	expect(is_same(vault._held, tube), "clicking a piece picks it up")
	var floor_at: Vector2 = vault._origin(VaultLayout.FLOOR) + Vector2(4, 4)
	while VaultLayout.footprint("tube", vault._held_rot).x != 3:
		vault.turn(floor_at)
	vault._grab = Vector2(4, 4)
	vault.drop(floor_at)
	expect(tube.area == VaultLayout.FLOOR and tube.cell == Vector2i.ZERO, "dropping it on the floor safe stores it")
	var risk_before: float = vault.layout.risk(0.0)
	expect(risk_before < 0.54, "storing stock lowers the risk")
	vault.lock_up()
	expect(vault.locked and vault.report.has("break_in"), "locking up rolls the night")
	await get_tree().create_timer(1.0).timeout
	expect(vault._result != null, "the night's result shows")
	vault.queue_free()
	Shop.reset()
