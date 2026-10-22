extends Node
## Headless checks for the shop, the coin test, the jewellery appraisal, the bar test, the vault lock-up,
## the customers (archetypes, haggling, regulars' stories), staff and rush hours, counter, bench
## and room upgrades with the floor plan, the menus, settings and music, the tutorial, the
## ledger of records and achievements, robberies (hold-ups and burglar crews) and the trading
## desk. Run:
##   godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 when everything passes, 1 otherwise.

var failures := 0


func _ready() -> void:
	# never touch the player's real saves
	SaveGame.slot_prefix = "user://smoke_test_slot_"
	SaveGame.meta_path = "user://smoke_test_slots.cfg"
	SaveGame.legacy_path = "user://smoke_test_legacy.json"
	_clear_slots()
	SaveGame.set_slot(1)
	_check_coins()
	_check_fakes_are_detectable()
	_check_stock()
	_check_bills_and_upgrades()
	_check_save_load()
	_check_save_slots()
	_check_records()
	_check_jewellery()
	_check_bars()
	_check_vault_layout()
	_check_market_events()
	_check_customers()
	await _check_vault_scene()
	await _check_shop_day()
	await _check_jewellery_deals()
	await _check_bar_deals()
	_check_staff()
	_check_wholesaler()
	_check_rush_hours()
	await _check_rush_day()
	await _check_shop_upgrades()
	await _check_trading_desk()
	_check_burglar_crews()
	await _check_holdups()
	_check_settings()
	_check_music()
	await _check_menus()
	await _check_tutorial()
	_clear_slots()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.meta_path))
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


func _clear_slots() -> void:
	for n in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete_slot(n)


func _check_save_slots() -> void:
	_clear_slots()
	expect(SaveGame.first_empty_slot() == 1 and SaveGame.continue_slot() == 0, "no saves: slot 1 is free, nothing to continue")
	SaveGame.set_slot(1)
	SaveGame.new_game()
	Shop.day = 4
	SaveGame.save_game()
	SaveGame.set_slot(2)
	SaveGame.new_game()
	Shop.day = 11
	SaveGame.save_game()
	expect(SaveGame.peek(1).day == 4 and SaveGame.peek(2).day == 11, "each slot keeps its own shop")
	expect(SaveGame.first_empty_slot() == 3, "the next new game goes in the empty slot")
	SaveGame.set_slot(1)
	expect(SaveGame.load_game() and Shop.day == 4, "switching slots loads that slot's shop")
	expect(SaveGame.continue_slot() == 1, "Continue opens the slot played last")
	var cfg := ConfigFile.new()
	cfg.load(SaveGame.meta_path)
	expect(int(cfg.get_value("saves", "last_slot", 0)) == 1, "the last slot played is remembered")
	SaveGame.delete_slot(1)
	expect(not SaveGame.slot_has_save(1) and SaveGame.slot_has_save(2), "deleting a slot leaves the others alone")
	expect(SaveGame.continue_slot() == 2, "Continue falls back to the newest save")
	expect(SaveGame.format_time(1761060240) != "", "save times format for the slots page")
	# the single save from before slots becomes slot 1
	var f := FileAccess.open(SaveGame.legacy_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "shop": {"day": 7}}))
	f.close()
	SaveGame._migrate_legacy_save()
	expect(SaveGame.peek(1).get("day", 0) == 7 and not FileAccess.file_exists(SaveGame.legacy_path), "an old save moves into slot 1")
	_clear_slots()
	SaveGame.set_slot(1)
	SaveGame.new_game()


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


func _check_customers() -> void:
	Shop.reset()
	Customers.reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	Shop.day = 5
	# every archetype makes a customer with its personality
	for id in ["walk_in", "haggler", "crypto_bro", "collector", "shady"]:
		for n in 10:
			var c := Customer.create(Shop.day, 3.0, Shop.coin_list(), rng)
			Customers.apply_archetype(c, id, rng)
			expect(c.archetype == id and c.frames.size() == PeopleArt.FRAMES, "%s customer is painted" % id)
			expect(c.say != "" and c.patience > 0.0, "%s customer talks and waits" % id)
			match id:
				"collector":
					expect(c.kind == "buyer" and c.wanted_exact and c.max_premium >= 0.12, "collectors pay well for one coin")
				"shady":
					expect(c.kind == "seller" and c.piece == null and c.reserve <= 0.84, "shady sellers come cheap")
				"crypto_bro":
					expect(c.item.metal == "XAU" and c.patience < 70.0, "crypto bros want gold, fast")
				"haggler":
					expect(c.haggle > 0.0, "hagglers bargain")
	for n in 50:
		var id := Customers.pick_archetype(rng)
		expect(id in ["walk_in", "haggler", "crypto_bro", "collector", "shady"], "archetype pick is known")
	var crypto_rush := {"id": "btc_crash", "measure": "crypto:BTC"}
	for n in 20:
		expect(Customers.pick_archetype(rng, crypto_rush) in ["walk_in", "crypto_bro"], "a crypto rush brings crypto folk")

	# a haggling seller comes down a step each time you hold firm, then deals
	var s := Customer.create(1, 2.5, Shop.coin_list(), rng)
	s.kind = "seller"
	s.piece = null
	s.fake = ""
	s.archetype = "haggler"
	s.reserve = 0.9
	s.set_haggle(0.06, 0.02)
	expect(is_equal_approx(s.reserve, 0.96) and is_equal_approx(s.floor_reserve, 0.9), "hagglers open high")
	Shop.buy_percent = 0.92
	expect(not s.hear_offer(s.offer_total()), "first offer is countered")
	expect(s.say.contains("94%"), "the counter names a number: " + s.say)
	expect(s.hear_offer(s.offer_total()), "holding firm closes the deal")
	var stubborn := Customer.create(1, 2.5, Shop.coin_list(), rng)
	stubborn.kind = "seller"
	stubborn.piece = null
	stubborn.reserve = 0.9
	stubborn.set_haggle(0.04, 0.02)
	Shop.buy_percent = 0.8
	for n in 5:
		expect(not stubborn.hear_offer(stubborn.offer_total()), "a lowball never lands")
	expect(is_equal_approx(stubborn.reserve, 0.9), "sellers stop at their floor")
	# a haggling buyer comes up toward their ceiling
	var b := Customer.create(1, 2.5, Shop.coin_list(), rng)
	b.kind = "buyer"
	b.max_premium = 0.08
	b.set_haggle(0.04, 0.02)
	expect(not b.hear_price(0.07), "buyer balks at first")
	expect(b.hear_price(0.07) or b.hear_price(0.07), "buyer comes round")
	expect(not b.hear_price(0.12), "buyer never goes past the ceiling")
	Shop.buy_percent = 0.92

	# collectors take only their coin
	Shop.add_stock(Shop.coins["silver_maple"], 5, 30.0)
	var eagles := Shop.count_of_item(Shop.coins["silver_eagle"])
	Shop.take_stock("XAG", 3, Shop.coins["silver_maple"])
	expect(Shop.count_of_item(Shop.coins["silver_maple"]) == 2 and Shop.count_of_item(Shop.coins["silver_eagle"]) == eagles, "exact coins leave for collectors")

	# Grandpa Lev's story plays out over visits a couple of days apart
	Shop.day = 1
	expect("lev" in Customers.due_regulars() and not "vance" in Customers.due_regulars(), "Lev is due on day 1, the collector later")
	var rep := Shop.reputation
	var beats: int = Customers.REGULARS[0].beats.size()
	for n in beats:
		var c := Customers.regular_customer("lev", rng)
		expect(c.archetype == "regular" and c.beat == n and Customers.tag(c) == "regular", "Lev visit %d" % n)
		expect(not "lev" in Customers.due_regulars(), "regulars come once a day at most")
		c.dealt = true
		Customers.on_leave(c)
		Shop.day += 2
	expect(Customers.state.lev.done and Customers.state.lev.loyalty == beats, "Lev's story ends")
	expect(Shop.reputation > rep, "the finale lifts reputation")
	# a regular treated badly finds another shop
	Shop.day = 1
	for n in 2:
		var c := Customers.regular_customer("okafor", rng)
		Customers.on_leave(c)
		Shop.day += 2
	expect(Customers.state.okafor.gone and not "okafor" in Customers.due_regulars(), "a spurned regular stops coming")
	# out of stock is no one's fault: Dr. Vance comes back for it
	var v := Customers.regular_customer("vance", rng)
	Shop.confiscate(v.item, "")
	Customers.on_leave(v)
	expect(Customers.state.vance.beat == 0 and Customers.state.vance.loyalty == 0, "out of stock keeps the collector's story")
	# catch Vinnie twice and the detective pays the reward
	for caught in [true, true, false]:
		var c := Customers.regular_customer("vinnie", rng)
		expect(c.fake != "", "Vinnie's coins are fake")
		c.caught = caught
		Customers.on_leave(c)
	var ruiz := Customers.regular_customer("vinnie", rng)
	expect(ruiz.kind == "visit" and ruiz.name == "Detective Ruiz" and ruiz.note.begins_with("Reward"), "the detective visits")
	var cash := Shop.cash
	Customers.on_leave(ruiz)
	expect(Shop.cash > cash and Customers.state.vinnie.done, "the detective pays the reward")
	Customers.state.vinnie = Customers._fresh()
	Customers.state.vinnie.beat = 3
	expect(Customers.regular_customer("vinnie", rng).say.contains("Test your coins"), "no reward if Vinnie got away with it")
	# story lines reach the summary, and stories survive a save
	var report := {"lines": []}
	Customers._on_day_ended(Shop.day, report)
	expect(report.lines.size() >= beats, "story lines reach the day summary")
	SaveGame.save_game()
	Customers.reset()
	expect(SaveGame.load_game() and Customers.state.lev.done and Customers.state.okafor.gone, "regulars' stories are saved")
	SaveGame.delete_save()
	Customers.reset()
	Shop.reset()


func _check_shop_day() -> void:
	Tutorial.skip_all() # the guided first day has its own check
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
	c.bar = null
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
	g.bar = null
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
	var night_save := SaveGame.peek()
	expect(night_save.get("day_over", false) and night_save.get("day", 0) == 1, "the end of the day is autosaved")
	# quit on the summary and launch again: the game carries on with the next morning
	shop.queue_free()
	await get_tree().process_frame
	shop = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	expect(Shop.day == 2 and shop.paused and Day.phase == Day.MORNING, "a save from the night opens on the next morning")
	expect(not SaveGame.peek().get("day_over", true), "the next morning is saved as a fresh day")
	shop._open_shop()
	expect(not shop.paused, "day 2 opens")
	shop.queue_free()


## Every jewellery fraud must show up on at least one bench test, values must follow
## the claim and the truth, and every kind of piece must paint at every scale.
func _check_records() -> void:
	if get_node_or_null("/root/Records") == null:
		expect(false, "the Records autoload loads")
		return
	SaveGame.new_game()
	expect(Records.earned.is_empty() and Records.totals.days == 0, "a new game starts an empty ledger")
	Day.begin_day()
	Day.open_shop()
	Shop.note("bought", 1200.0)
	Shop.note("sold", 2000.0)
	Shop.note("profit", 6000.0)
	Shop.note("served")
	Shop.note("caught")
	expect(Records.is_earned("first_sale") and Records.is_earned("first_catch"), "first sale and first catch are earned on the spot")
	expect(Records.is_earned("day_5k"), "a big day is earned as soon as the profit is in")
	expect(not Records.is_earned("catch_25") and is_equal_approx(Records.progress_of("catch_25"), 1.0 / 25.0), "progress counts toward the next goal")
	expect(is_equal_approx(Records.total("bought"), 1200.0) and Records.total("buys") == 1, "today's deals count before closing")
	Day.close_shop()
	var report := Day.end_day()
	expect(Records.totals.days == 1 and is_equal_approx(Records.total("profit"), 6000.0), "a closed day joins the totals once")
	expect(Records.total("caught") == 1 and Records.total("sales") == 1, "counts are not doubled after closing")
	expect(Records.best_days.size() == 1 and Records.streak == 1, "a profitable day is ranked and starts a streak")
	expect(report.lines.any(func(l): return str(l).begins_with("Achievement earned: Sharp eye")), "the summary lists today's achievements")
	# a day with a missed fake breaks the clean streak, a losing day breaks the profit streak
	Shop.next_day()
	Day.begin_day()
	Day.open_shop()
	Shop.note("scammed")
	Shop.note("profit", -500.0)
	Day.close_shop()
	Day.end_day()
	expect(Records.streak == 0 and Records.clean_streak == 0 and Records.peaks.streak == 1, "streaks reset and the best is kept")
	expect(Records.best_days.size() == 1 and is_equal_approx(Records.catch_rate(), 0.5), "losing days are not best days; catch rate is 50%")
	expect(SaveGame.save_game(), "the ledger saves")
	Records.reset()
	expect(SaveGame.load_game() and Records.totals.days == 2 and Records.is_earned("first_catch") and Records.best_days.size() == 1, "the ledger comes back from the save")
	# the ledger and achievements pages build
	var panels := DayPanels.new()
	add_child(panels)
	panels.show_morning()
	panels.show_ledger()
	expect(panels.page == "ledger" and panels.visible, "the ledger page opens")
	panels.show_achievements()
	expect(panels.page == "achievements" and panels._box.get_child_count() > 3, "the achievements page opens")
	panels.queue_free()
	SaveGame.new_game()
	expect(Records.earned.is_empty() and Records.best_days.is_empty(), "a new game clears the ledger")


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
	Tutorial.skip_all() # the guided first day has its own check
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
	c.bar = null
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


## Every fake bar must fail the scale, the calipers or an ultrasound sweep (the XRF gun
## is an upgrade, so it can only confirm), and every genuine bar must pass them all.
func _check_bars() -> void:
	BullionBar.hook_up()
	expect(Progress.upgrades.has("xrf_gun") and Progress.upgrades.has("bar_dealer"), "bar upgrades are registered")
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	BullionBar.ledger.clear()
	var seen := {}
	for id in BullionBar.SPECS:
		var b := BullionBar.new()
		b.spec_id = id
		b.seed = rng.randi()
		b.serial = BullionBar.new_serial(b.spec().prefix, rng)
		expect(b.thickness_mm() > 0.5 and b.melt_value() > 0.0, "%s has a thickness and a melt value" % id)
		for n in 10:
			var r := b.readings(rng)
			expect(b.readings_pass(r) and b.surface_pass(r.surface), "genuine %s passes the scale, calipers and XRF" % id)
		expect(not _sweep_finds_fault(b), "genuine %s echoes inside the gate everywhere" % id)
		for kind in BullionBar.fakes_for(b.metal(), 99, id):
			seen[kind] = true
			b.fake = kind
			for n in 10:
				var r := b.readings(rng)
				expect(not b.readings_pass(r) or _sweep_finds_fault(b), "%s %s fails a base test" % [kind, id])
			expect(b.true_value() < b.melt_value(), "%s %s is worth less than it claims" % [kind, id])
			if not BullionBar.FAKES[kind].core:
				expect(not b.surface_pass(b.readings(rng).surface), "the XRF sees through %s %s" % [kind, id])
			b.fake = ""
		var art := BarArt.paint(b, BarArt.bench_ppm(b))
		expect(art.width >= 90 and art.width <= ceili(BarArt.BENCH_W) and not art.image.is_invisible(), "%s paints on the bench" % id)
		expect(BarArt.serial_rect(b).size.x > 0.0, "%s has a serial number" % id)
	for kind in BullionBar.FAKES:
		expect(seen.has(kind), "fake bar kind %s turns up" % kind)
	# a tungsten slug only shows in the middle of the bar
	var core := BullionBar.new()
	core.spec_id = "gold_100g"
	core.fake = "tungsten_core"
	expect(not core.echo_off(Vector2(0.08, 0.5)) and core.echo_off(Vector2(0.5, 0.5)), "a tungsten core hides from the edges")
	# serials of bought bars are remembered across a save
	var bought := BullionBar.new()
	bought.serial = "NS 123456"
	BullionBar.record(bought, 4)
	var saved := BullionBar.ledger_to_dict()
	BullionBar.ledger.clear()
	BullionBar.ledger_from_dict(JSON.parse_string(JSON.stringify(saved)))
	expect(BullionBar.ledger.get("NS 123456", 0) == 4, "the serial ledger saves and loads")
	# hooking up late (after a title screen loaded or wiped the save) still picks up the file
	SaveGame.save_game()
	BullionBar.ledger.clear()
	BullionBar._hooked = false
	BullionBar.hook_up()
	expect(BullionBar.ledger.get("NS 123456", 0) == 4, "a late hook-up reads the ledger from the save")
	SaveGame.delete_save()
	BullionBar._hooked = false
	BullionBar.hook_up()
	expect(BullionBar.ledger.is_empty(), "a late hook-up with no save starts an empty ledger")
	BullionBar.record(bought, 4)
	var clone := BullionBar.create(5, 0, rng, 1.0)
	var tries := 0
	while not clone.cloned and tries < 50:
		clone = BullionBar.create(5, 0, rng, 1.0)
		tries += 1
	expect(clone.cloned and BullionBar.ledger.has(clone.serial), "fakers copy serials you have seen")
	BullionBar.ledger.clear()


func _sweep_finds_fault(b: BullionBar) -> bool:
	for y in 5:
		for x in 9:
			if b.echo_off(Vector2((x + 0.5) / 9.0, (y + 0.5) / 5.0)):
				return true
	return false


func _check_bar_deals() -> void:
	Shop.reset()
	Progress.reset()
	Tutorial.skip_all() # the guided first day has its own check
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop.has_method("_open_shop"):
		return
	shop._open_shop()
	shop.queue.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# a plated tungsten bar bought as is: the bullion dealer finds out
	var c := _bar_seller(rng, "gold_1oz", "plated_tungsten")
	shop.queue.push_front(c)
	c.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	var hud: Control = shop.get_node("Hud/Root")
	expect(hud._buttons.test.text == "Test bar", "a bar seller offers a bar test")
	var cash := Shop.cash
	shop._on_action("offer")
	expect(Shop.cash < cash and shop.pending_bars.size() == 1, "buying a bar pays the seller")
	expect(BullionBar.ledger.has(c.bar.serial), "a bought bar's serial goes in the ledger")
	shop.time += 9.0
	shop._tick(0.0)
	expect(shop.pending_bars.is_empty() and Shop.stats.scammed == 1.0, "the bullion dealer catches a tungsten bar")
	# a tungsten-core bar on the bench: the scale and XRF pass, the probe over the middle does not
	Progress.owned.append("xrf_gun")
	var t := _bar_seller(rng, "gold_100g", "tungsten_core")
	shop.queue.push_front(t)
	t.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(t)
	var bench: Control = shop._test
	expect(bench.get_script().resource_path.ends_with("bar_test.gd"), "a bar opens the bar bench")
	for tool in ["scale", "calipers", "xrf", "loupe", "loupe"]:
		bench.use_tool(tool)
	await get_tree().create_timer(2.8).timeout
	expect(bench._xrf_done and t.bar.surface_pass(bench.readings.surface), "the XRF reads a clean gold shell")
	bench.use_tool("ultrasound")
	bench.probe_at(Vector2(0.1, 0.5))
	expect(bench.scan_off_count() == 0, "the edge of a cored bar echoes normally")
	bench.probe_at(Vector2(0.5, 0.5))
	expect(bench.scan_off_count() == 1, "the probe finds the tungsten core")
	await get_tree().process_frame
	bench.finished.emit("fake")
	expect(not shop.queue.has(t) and Shop.stats.caught >= 1.0, "calling the cored bar fake catches it")
	# a genuine bar passes and sells at a profit
	var g := _bar_seller(rng, "silver_10oz", "")
	shop.queue.push_front(g)
	g.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(g)
	shop._test.finished.emit("genuine")
	expect(g.tested, "a genuine verdict marks the bar tested")
	cash = Shop.cash
	shop._on_action("offer")
	shop.time += 9.0
	shop._tick(0.0)
	expect(Shop.cash > cash, "the bullion dealer pays more than the shop paid for a genuine bar")
	shop.queue_free()
	Progress.reset()
	Shop.reset()
	BullionBar.ledger.clear()


## Hiring costs a fee, wages go on the ledger at closing, the guard cuts robbery odds,
## and staff are saved and cleared by a new game.
func _check_staff() -> void:
	SaveGame.new_game()
	Day.begin_day()
	var risk := Progress.effect("robbery_risk")
	var cash := Shop.cash
	expect(Staff.hire("clerk") and Staff.hire("guard"), "hire a clerk and a guard")
	expect(not Staff.hire("clerk"), "the clerk is hired once")
	expect(is_equal_approx(Shop.cash, cash - Staff.ROLES.clerk.fee - Staff.ROLES.guard.fee), "hiring pays the signing fees")
	expect(Progress.effect("robbery_risk") < risk, "the guard cuts the robbery odds")
	expect(RushHours.grab_chance(RushHours.till_limit() * 2.0, true) < RushHours.GRAB_CHANCE, "the guard puts off till snatchers")
	Day.open_shop()
	expect(not Staff.can_hire("clerk"), "staff are hired in the morning")
	cash = Shop.cash
	Day.close_shop()
	var report := Day.end_day()
	expect(is_equal_approx(Shop.cash, cash - Staff.daily_wages() - Progress.daily_upkeep()), "wages are paid at closing")
	expect(report.ledger.any(func(e): return str(e.label).begins_with("Wages")), "wages show in the day's ledger")
	Progress.tier = 2
	expect(Staff.wage("clerk") > Staff.ROLES.clerk.wage, "wages rise with the shop")
	Progress.tier = 0
	expect(SaveGame.save_game(), "the game saves with staff")
	Staff.reset()
	expect(SaveGame.load_game() and Staff.has("clerk") and Staff.has("guard"), "staff come back from the save")
	expect(Staff.let_go("guard") and not Staff.has("guard") and is_equal_approx(Progress.effect("robbery_risk"), risk), "letting the guard go")
	SaveGame.new_game()
	expect(Staff.hired.is_empty(), "a new game starts with no staff")


## The morning wholesaler sells genuine coins a little over melt, only before opening.
func _check_wholesaler() -> void:
	SaveGame.new_game()
	Day.begin_day()
	var eagle: BullionItem = Shop.coins["silver_eagle"]
	var left := Wholesaler.left(eagle)
	var lots := Wholesaler.lots.duplicate()
	expect(left >= Wholesaler.LOT_RANGE.XAG.x, "the wholesaler has silver eagles this morning")
	var each := Wholesaler.price(eagle)
	expect(each > eagle.melt_value() and each < eagle.melt_value() * 1.1, "wholesale is a little over melt")
	var cash := Shop.cash
	var have := Shop.count_of_item(eagle)
	expect(Wholesaler.buy(eagle, 10) == 10, "buy ten silver eagles")
	expect(Shop.count_of_item(eagle) == have + 10 and Wholesaler.left(eagle) == left - 10, "the coins go into stock")
	expect(is_equal_approx(Shop.cash, cash - each * 10), "the wholesaler is paid")
	expect(Wholesaler.buy(eagle, 1000) == left - 10, "the lot runs out")
	var platinum: BullionItem = Shop.coins["platinum_eagle"]
	Shop.cash = Wholesaler.price(platinum) * 0.5
	expect(Wholesaler.buy(platinum, 1) == 0, "no coins without the cash")
	Shop.cash = 25000.0
	Day.open_shop()
	expect(Wholesaler.affordable(platinum, 1) == 0, "the wholesaler only delivers in the morning")
	Day.begin_day()
	expect(Wholesaler.lots == lots, "replaying a morning offers the same lots")
	SaveGame.new_game()


func _check_rush_hours() -> void:
	expect(RushHours.at(1, 12 * 60).name == "Lunch rush", "lunch is busy on a Monday")
	expect(RushHours.at(1, 10 * 60).is_empty(), "mid-morning is calm on a Monday")
	expect(RushHours.at(6, 10 * 60).name == "Saturday crowd", "Saturday morning is busy")
	expect(RushHours.at(7, 16 * 60).is_empty(), "Sunday afternoon is quiet")
	expect(RushHours.summary(1).contains("lunch 11:45"), "the morning briefing lists the rushes")
	expect(RushHours.grab_chance(RushHours.till_limit() * 0.5, true) == 0.0, "a light till is safe")
	expect(RushHours.grab_chance(RushHours.till_limit() * 2.0, true) > RushHours.grab_chance(RushHours.till_limit() * 2.0, false), "a rush makes snatches likelier")


## In a rush the clock runs on through a test, a full queue turns people away, the clerk
## serves buyers, and a vault run empties the till.
func _check_rush_day() -> void:
	SaveGame.new_game()
	Tutorial.skip_all() # the guided first day has its own check
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop.has_method("_open_shop"):
		return
	shop._open_shop()
	shop.queue.clear()
	# jump to lunch on a Monday
	shop.time = (12.0 * 60.0 - 9.0 * 60.0) / (8.0 * 60.0) * shop.DAY_SECONDS
	shop._tick(0.0)
	expect(shop.rush.get("name", "") == "Lunch rush", "the lunch rush starts at noon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seller := Customer.create(1, 2.5, Shop.coin_list(), rng)
	seller.kind = "seller"
	seller.piece = null
	seller.bar = null
	seller.pos = ShopArt.SLOTS[0]
	shop.queue.append(seller)
	var waiting := Customer.create(1, 2.5, Shop.coin_list(), rng)
	waiting.kind = "seller"
	waiting.pos = ShopArt.SLOTS[1]
	shop.queue.append(waiting)
	await get_tree().process_frame
	shop._open_test(seller)
	expect(not shop.paused, "the clock keeps running at the bench in a rush")
	var t: float = shop.time
	var patience: float = seller.patience
	var other: float = waiting.patience
	shop._tick(1.0)
	expect(shop.time > t and is_equal_approx(seller.patience, patience) and waiting.patience < other, "the queue waits while you test, the customer on the bench does not")
	shop._test.finished.emit("genuine")
	expect(not shop.paused and shop._test == null, "back at the counter")
	# a full queue turns walk-ins away
	while shop.queue.size() < Progress.queue_slots():
		var extra := Customer.create(1, 2.5, Shop.coin_list(), rng)
		extra.kind = "seller"
		shop.queue.append(extra)
	shop._next_spawn = 0.0
	shop._tick(0.01)
	expect(Shop.stats.get("walked_by", 0.0) >= 1.0 and shop.queue.size() == Progress.queue_slots(), "a full queue in a rush turns people away")
	# the clerk serves a buyer at the second till
	shop.queue.clear()
	Day.phase = Day.MORNING
	Shop.cash = 50000.0
	expect(Staff.hire("clerk"), "hire the clerk")
	Day.phase = Day.OPEN
	Shop.add_stock(Shop.coins["silver_maple"], 10, 30.0)
	var front := Customer.create(1, 2.5, Shop.coin_list(), rng)
	front.kind = "seller"
	front.piece = null
	front.bar = null
	front.pos = ShopArt.SLOTS[0]
	var buyer := Customer.create(1, 2.5, Shop.coin_list(), rng)
	buyer.kind = "buyer"
	buyer.item = Shop.coins["silver_maple"]
	buyer.qty = 4
	buyer.wanted_exact = false
	buyer.max_premium = 0.5
	buyer.ceiling_premium = 0.5
	buyer.pos = ShopArt.SLOTS[1]
	shop.queue.append(front)
	shop.queue.append(buyer)
	await get_tree().process_frame
	shop._tick(0.01)
	expect(shop.at_clerk == buyer and not shop.queue.has(buyer), "the clerk takes the buyer behind your customer")
	buyer.pos = ShopArt.CLERK_SLOT
	buyer.walking = false
	var sold: float = Shop.stats.sold
	shop._tick(shop.CLERK_SECONDS + 0.1)
	expect(shop.at_clerk == null and Shop.stats.sold > sold and buyer.dealt, "the clerk rings up the sale")
	expect(shop.till > 0.0, "the sale goes in the till")
	# a vault run empties the till; the counter is shut while you are away
	shop._on_action("vault_run")
	expect(shop.away > 0.0, "off to the vault with the till")
	var queued: int = shop.queue.size()
	shop._on_action("refuse")
	expect(shop.queue.size() == queued, "nobody is served while you are at the vault")
	shop._tick(shop.VAULT_RUN_SECONDS + 0.1)
	expect(shop.away <= 0.0 and shop.till == 0.0, "the till is locked in the safe")
	# an overfull till can be snatched
	shop.till = RushHours.till_limit() * 3.0
	var cash := Shop.cash
	shop._till_grab()
	expect(Shop.cash < cash and shop.till < RushHours.till_limit() * 3.0, "a snatch takes cash from the till")
	shop.queue_free()
	SaveGame.new_game()


## Night crews: kids carry off a few pieces from the tray, crews and pros work the
## wall safe, nobody opens the floor safe; the cameras get some of it back.
func _check_burglar_crews() -> void:
	SaveGame.new_game()
	Security.hook_up()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for tier in 4:
		for n in 200:
			seen[Security.pick_crew(rng, tier)] = true
	expect(seen.has("kids") and seen.has("crew") and seen.has("pros"), "all three crews turn up")
	for n in 200:
		expect(Security.pick_crew(rng, 0) != "pros", "no professionals at the corner counter")
	expect(Security.crack_chance("kids", 0.4) == 0.0, "kids leave the safes alone")
	expect(Security.crack_chance("pros", 0.4) > Security.crack_chance("crew", 0.4), "professionals crack safes more often")
	expect(Security.crack_chance("pros", 0.0) == 0.0, "the floor safe always holds")
	expect(Security.crack_chance("kids", 1.0) == 1.0, "the tray is always open")
	# five silver tubes and two gold boxes on the tray: kids take the three most valuable
	Shop.reset()
	Shop.cash = 0.0
	Shop.add_stock(Shop.coins["silver_maple"], 50, 30.0)
	Shop.add_stock(Shop.coins["gold_maple"], 10, 2000.0)
	var v := VaultLayout.from_shop(rng)
	var kids := {}
	for n in 400:
		var r := v.resolve(1.0, rng)
		if r.crew == "kids":
			kids = r
			break
	expect(not kids.is_empty() and kids.stolen.size() == 3, "kids carry off three pieces")
	if not kids.is_empty():
		var values := v.pieces.map(func(p): return p.value)
		values.sort()
		expect(kids.stolen.all(func(p): return p.value >= values[-3]), "kids grab the most valuable pieces")
	# with the wall safe full and the tray empty, kids get nothing and pros usually crack it
	for p in v.pieces:
		p.area = VaultLayout.WALL
	var pros_hit := 0
	var kids_hit := 0
	for n in 400:
		var r := v.resolve(1.0, rng)
		if r.crew == "kids" and r.value > 0.0:
			kids_hit += 1
		if r.crew == "pros" and r.value > 0.0:
			pros_hit += 1
	expect(kids_hit == 0, "kids never get into the wall safe")
	Progress.tier = 3
	pros_hit = 0
	var pros := 0
	for n in 400:
		var r := v.resolve(1.0, rng)
		if r.crew == "pros":
			pros += 1
			pros_hit += 1 if r.value > 0.0 else 0
	expect(pros > 0 and pros_hit > pros / 2, "professionals usually crack the wall safe")
	Progress.tier = 0
	# the cameras recover a third
	Progress.owned.assign(["cctv"])
	Day.begin_day()
	var cash := Shop.cash
	var report := {"break_in": true, "crew": "crew", "stolen": [], "value": 3000.0, "cracked": {}}
	v.apply(report)
	expect(is_equal_approx(Shop.cash, cash + 1000.0 * Security.recover_share() * 3.0) and report.recovered > 0.0, "police recover a third with cameras")
	Progress.owned.clear()
	SaveGame.new_game()


## Daytime hold-ups: the guard stops most at the door; at the counter you hand over the
## till, or hit the panic button and risk the display case; freezing costs both.
func _check_holdups() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop.has_method("_robber_walks_in"):
		expect(false, "the shop has hold-ups")
		return
	shop._open_shop()
	shop.queue.clear()
	expect(Progress.upgrades.has("cctv"), "the cameras are for sale")
	expect(Security.holdup_chance(RushHours.till_limit() * 3.0) > Security.holdup_chance(0.0), "a full till draws robbers")
	var base := Security.holdup_chance(0.0)
	Progress.owned.assign(["cctv"])
	expect(Security.holdup_chance(0.0) < base, "the cameras put robbers off")
	Progress.owned.clear()
	var odds := Security.panic_odds()
	Progress.owned.assign(["alarm"])
	expect(Security.panic_odds() > odds, "the alarm makes the panic button work more often")
	Progress.owned.clear()
	# the robber queues like anyone, and pulls a gun at the counter; half the queue flees
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for n in 4:
		var c := Customer.create(1, 2.5, Shop.coin_list(), rng)
		c.kind = "seller"
		c.pos = ShopArt.SLOTS[n]
		shop.queue.append(c)
	shop._robber_walks_in()
	var robber: Customer = shop.robber
	expect(robber != null and shop.queue.back() == robber, "the robber joins the end of the queue")
	shop.queue.erase(robber)
	shop.queue.push_front(robber)
	robber.pos = ShopArt.SLOTS[0]
	shop.rng.seed = 1
	shop._tick(0.01)
	expect(shop.robber_revealed and Shop.stats.get("holdups", 0.0) == 1.0, "the hold-up starts at the counter")
	expect(shop.queue.size() < 5, "customers run for the door")
	shop.hud.show_customer(robber)
	expect(shop.hud._buttons.sell.visible and shop.hud._buttons.sell.text == "Panic button" and shop.hud._buttons.decline.visible, "the counter card offers the panic button and handing over")
	# hand over the till: lose the till, keep the stock
	Shop.add_stock(Shop.coins["gold_maple"], 3, 2000.0)
	shop.till = 4000.0
	var cash := Shop.cash
	var gold := Shop.count_of("XAU")
	shop._on_action("decline")
	expect(shop.robber == null and robber.leaving, "the robber leaves")
	expect(is_equal_approx(Shop.cash, cash - 4000.0) and shop.till == 0.0 and Shop.count_of("XAU") == gold, "handing over costs the till only")
	# freeze: the robber takes the till and coins from the case
	shop._robber_walks_in()
	robber = shop.robber
	shop.queue.clear()
	shop.queue.append(robber)
	robber.pos = ShopArt.SLOTS[0]
	shop.till = 2000.0
	cash = Shop.cash
	var stock_value := Shop.vault_value()
	shop._tick(0.01)
	shop._tick(Security.ROBBER_PATIENCE + 0.1)
	expect(shop.robber == null and is_equal_approx(Shop.cash, cash - 2000.0) and Shop.vault_value() < stock_value, "freezing loses the till and coins from the case")
	# the panic button: a sure thing with the odds forced up
	shop._robber_walks_in()
	robber = shop.robber
	shop.queue.clear()
	shop.queue.append(robber)
	robber.pos = ShopArt.SLOTS[0]
	shop._tick(0.01)
	shop.till = 3000.0
	cash = Shop.cash
	Progress.owned.assign(["alarm", "time_lock"])
	Day.phase = Day.MORNING
	Shop.cash += 5000.0
	Staff.hire("guard")
	Day.phase = Day.OPEN
	cash = Shop.cash
	expect(is_equal_approx(Security.panic_odds(), 0.9), "the panic button tops out at 90%")
	var stopped: float = Shop.stats.get("robbers_stopped", 0.0)
	shop.rng.seed = 2
	shop._on_action("sell")
	expect(shop.robber == null, "the panic button ends the hold-up")
	expect(Shop.stats.get("robbers_stopped", 0.0) > stopped or Shop.cash < cash, "the alarm either scares him off or he robs you")
	# the guard stops most robbers at the door
	var at_door := 0
	for n in 100:
		shop._robber_walks_in()
		if shop.robber == null:
			at_door += 1
		else:
			shop.queue.erase(shop.robber)
			shop.robber = null
	expect(at_door > 50 and at_door < 90, "the guard stops most robbers at the door")
	expect(Records.is_earned("robber_1"), "stopping a robber earns Not today")
	Progress.owned.clear()
	shop.queue_free()
	SaveGame.new_game()


## Counter, bench and room upgrades: what each one changes, and the floor plan.
func _check_shop_upgrades() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	Shop.cash = 1000000.0
	expect(Progress.queue_slots() == ShopArt.BASE_SLOTS, "the corner counter has room for 4 in the queue")
	var till := RushHours.till_limit()
	expect(Progress.buy("queue_ropes") and Progress.queue_slots() == ShopArt.BASE_SLOTS + 2, "queue ropes make room for 2 more")
	expect(not Progress.can_buy("long_counter") and not Progress.can_buy("testing_lab"), "the long counter and the lab wait for Main Street")
	var rooms := {}
	for room in PlanArt.ROOMS:
		rooms[room.id] = room
	expect(PlanArt.state(rooms.shop_floor, 0, Progress.owned) == "built" and PlanArt.state(rooms.testing_lab, 0, Progress.owned) == "lot",
		"the corner counter has a shop floor and a vault; the lab is a lot next door")
	Progress.tier = 1
	expect(PlanArt.state(rooms.testing_lab, 1, Progress.owned) == "shell", "Main Street opens the lab's plot")
	expect(Progress.buy("long_counter"), "buy the long counter")
	expect(is_equal_approx(RushHours.till_limit(), till * Progress.deal_size() / Progress.TIERS[0].deal_size * 1.5), "the long counter's till holds 50% more")
	expect(Progress.queue_slots() == ShopArt.BASE_SLOTS + 3, "the long counter adds a spot in the queue")
	expect(Progress.buy("testing_lab") and PlanArt.state(rooms.testing_lab, 1, Progress.owned) == "built", "build the testing lab")
	Progress.tier = 2
	expect(Progress.unlocked("marble_counter"), "the marble counter follows the long counter")
	Progress.owned.erase("long_counter")
	expect(not Progress.unlocked("marble_counter"), "the marble counter needs the long counter first")
	Progress.owned.append("long_counter")
	expect(Progress.buy("marble_counter") and Progress.queue_slots() == ShopArt.SLOTS.size(), "a marble counter fills the queue's second row")
	Progress.tier = 3
	var deal := Progress.deal_size()
	expect(Progress.buy("trading_desk") and is_equal_approx(Progress.deal_size(), deal * 1.25), "the trading desk makes deals 25% bigger")
	var plan := PlanArt.paint(Progress.tier, Progress.owned)
	expect(plan.width == PlanArt.SIZE.x and plan.height == PlanArt.SIZE.y, "the floor plan paints")
	var front := ShopArt.paint_front(false, ShopArt.fit_out())
	expect(front.width == ShopArt.SIZE.x, "the marble counter paints")
	# the benches: gauges colour the readings, the sigma verifier finds plated steel
	expect(Progress.buy("digital_gauges") and Progress.buy("sigma_verifier"), "buy the bench tools")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := Customer.create(3, 4.0, Shop.coin_list(), rng)
	c.kind = "seller"
	c.piece = null
	c.bar = null
	c.item = Shop.coins["gold_eagle"]
	c.fake = "steel"
	var bench: Control = load("res://scenes/coin_test/coin_test.tscn").instantiate()
	add_child(bench)
	bench.start(c)
	expect(bench.tools().has("sigma") and bench._cells.has("sigma"), "the sigma verifier joins the coin bench")
	expect(bench.sigma_reading() == "ferrous" and bench.in_spec("weight") == false and bench.in_spec("sigma") == false, "the gauges and sigma flag plated steel")
	bench.use_tool("sigma")
	bench._process(1.5)
	expect(bench._cells.sigma.text == "ferrous", "the sigma reading shows on the panel")
	bench.queue_free()
	c.fake = ""
	bench = load("res://scenes/coin_test/coin_test.tscn").instantiate()
	add_child(bench)
	bench.start(c)
	expect(bench.sigma_reading() == "in band" and bench.in_spec("weight") == true and bench.in_spec("diameter") == true, "a genuine coin reads in spec")
	bench.queue_free()
	# the testing lab calms the queue while you are at the bench in a rush
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop._open_shop()
	shop.queue.clear()
	shop.time = (12.0 * 60.0 - 9.0 * 60.0) / (8.0 * 60.0) * shop.DAY_SECONDS
	shop._tick(0.0)
	var seller := Customer.create(1, 2.5, Shop.coin_list(), rng)
	seller.kind = "seller"
	seller.piece = null
	seller.bar = null
	seller.fake = ""
	seller.pos = ShopArt.SLOTS[0]
	var waiting := Customer.create(1, 2.5, Shop.coin_list(), rng)
	waiting.kind = "seller"
	waiting.pos = ShopArt.SLOTS[1]
	shop.queue.append(seller)
	shop.queue.append(waiting)
	await get_tree().process_frame
	shop._open_test(seller)
	var before: float = waiting.patience
	shop._tick(1.0)
	expect(is_equal_approx(before - waiting.patience, 0.25), "with a lab the queue frets half as fast while you test")
	shop._test.finished.emit("cancel")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()


func _check_trading_desk() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# a tape runs from 24h ago to its close
	var tape := DeskSession.tape(100.0, 103.0, 0.02, rng)
	expect(tape.size() == DeskSession.STEPS + 1 and is_equal_approx(tape[0], 100.0) and absf(tape[DeskSession.STEPS] - 103.0) < 0.001,
		"a desk tape starts at the open and ends at the close")
	var crypto := Market.crypto.duplicate(true)
	var stocks := Market.stocks.duplicate(true)
	Market.crypto = {"BTC": {"price": 100000.0, "change_pct": 4.0}, "ETH": {"price": 4000.0, "change_pct": -2.0}, "DOGE": {"price": 0.2, "change_pct": 1.0}}
	Market.stocks = {"SPY": {"price": 650.0, "change_pct": 0.5}}
	var s := DeskSession.from_market(rng)
	var syms := s.board.map(func(r): return r.sym)
	expect(syms == ["XAU", "XAG", "XPT", "BTC", "ETH", "SPY"], "the board lists the metals, two cryptos and the live stocks")
	var btc := syms.find("BTC")
	expect(absf(s.price(btc) - 100000.0 / 1.04) < 0.01, "bitcoin's tape opens where it stood 24 hours ago")
	Market.crypto = crypto
	Market.stocks = stocks
	expect(is_equal_approx(s.limit, DeskSession.BASE_LIMIT * Progress.deal_size()), "the desk's limit follows the deal size")
	# trading within the limit
	expect(is_equal_approx(s.trade(btc, s.limit * 0.6), s.limit * 0.6), "buy bitcoin with 60% of the limit")
	expect(s.trade(0, -s.limit) < -0.0 and absf(s.exposure() - s.limit) < 0.01, "a short is cut down to what the limit leaves")
	expect(absf(s.trade(1, 1000.0)) < 0.01, "nothing more fits at the limit")
	s.flatten(0)
	expect(absf(s.position(0)) < 0.01 and s.pnl_of(0) < 0.0, "closing a position at the same price costs its fees")
	s.started = true
	s.advance(DeskSession.SECONDS / 2.0)
	expect(s.step() == DeskSession.STEPS / 2 and not s.is_over(), "the clock runs once the bell rings")
	var expected := s.pnl() - absf(s.position(btc)) * DeskSession.FEE.crypto
	s.flatten_all()
	expect(absf(s.exposure()) < 0.01 and absf(s.pnl() - expected) < 0.01, "closing out books the open profit, less the fee")
	expect(absf(s.pnl() - (s.board[btc].flow + s.board[0].flow)) < 0.01, "once flat, the profit is the cash in and out")
	expect(s.advance(DeskSession.SECONDS) and s.is_over(), "the closing bell ends the session")
	# hedging the vault: a full hedge cancels the vault's paper move, fees aside
	var h := DeskSession.new()
	h.limit = 10000000.0
	h.vault_oz = {"XAU": 10.0}
	h.add("XAU", "metal", 4000.0, -8.0, 0.012, rng)
	h.add("BTC", "crypto", 100000.0, 2.0, 0.04, rng)
	h.hedge_vault()
	expect(absf(h.position(0) + 10.0 * h.price(0)) < 0.01 and absf(h.position(1)) < 0.01, "hedge vault shorts the vault's gold ounce for ounce")
	h.started = true
	h.advance(DeskSession.SECONDS)
	expect(absf(h.vault_swing() + h.metal_pnl()) < 10.0 * h.open_price(0) * DeskSession.FEE.metal * 1.01 and h.hedge_cover() > 0.95,
		"the hedge makes back what the vault loses on paper")
	h.limit = 10000.0
	h.flatten_all()
	h.elapsed = 0.0
	h.hedge_vault()
	expect(absf(h.exposure() - h.limit * DeskSession.HEDGE_SHARE) < 0.01, "a hedge uses at most half the desk's limit")
	# the room, one session a morning, and the ledger
	DeskSession.hook_up()
	expect(not DeskSession.available(), "no desk before the room is built")
	Shop.cash = 1000000.0
	Progress.tier = 1
	expect(not Progress.can_buy("trading_desk"), "the trading desk waits for the bullion house")
	Progress.tier = 2
	expect(Progress.buy("trading_desk"), "build the trading desk")
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	expect(DeskSession.available(), "the desk opens in the morning")
	var opened := []
	shop.desk_opened.connect(func(d): opened.append(d))
	shop.open_desk()
	expect(opened.size() == 1 and shop._desk != null, "the morning panel opens the trading desk")
	var desk: TradingDesk = shop._desk
	desk._process(0.1)
	expect(desk.session.board.size() >= 3 and desk.session.vault_oz == Shop.ounces_by_metal(), "the desk reads the board and the vault")
	desk.select(0)
	desk.buy()
	expect(desk.session.position(0) > 0.0, "Buy goes long the selected row")
	desk.ring_bell()
	desk._process(DeskSession.SECONDS + 1.0)
	expect(desk.closed and absf(desk.session.exposure()) < 0.01, "at the bell every position closes")
	var booked := Day.ledger.filter(func(e): return e.label == "Trading desk")
	expect(booked.size() == 1 and absf(absf(booked[0].usd) - absf(desk.session.pnl())) < 0.01, "the result goes on today's ledger")
	expect(DeskSession.last_day == Shop.day and not DeskSession.available(), "one session a morning")
	desk.finished.emit(desk.session.pnl())
	expect(shop._desk == null and shop.hud._panels.page == "morning", "the desk closes back to the morning")
	expect(SaveGame.save_game(), "save after trading")
	DeskSession.from_dict({})
	expect(SaveGame.load_game() and DeskSession.last_day == Shop.day, "the desk's day is saved")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()
	expect(DeskSession.last_day == 0 and DeskSession.lifetime == 0.0, "a new game resets the desk")


func _bar_seller(rng: RandomNumberGenerator, spec_id: String, fake: String) -> Customer:
	var c := Customer.create(3, 2.5, Shop.coin_list(), rng)
	c.kind = "seller"
	c.fake = ""
	c.piece = null
	c.reserve = 0.85
	c.qty = 1
	var b := BullionBar.new()
	b.spec_id = spec_id
	b.seed = rng.randi()
	b.serial = BullionBar.new_serial(b.spec().prefix, rng)
	b.fake = fake
	c.bar = b
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


func _check_settings() -> void:
	var real_path := Settings.path
	Settings.path = "user://smoke_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	expect(AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("SFX") != -1, "the Music and SFX buses exist")
	Settings.set_volume("Music", 0.25)
	var music := AudioServer.get_bus_index("Music")
	expect(is_equal_approx(AudioServer.get_bus_volume_db(music), linear_to_db(0.25)), "the music slider sets the bus volume")
	Settings.set_volume("SFX", 0.0)
	expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "effects at zero are muted")
	Settings.set_fullscreen(true)
	Settings.volume["Music"] = 1.0
	Settings.fullscreen = false
	Settings.load_settings()
	expect(is_equal_approx(Settings.volume["Music"], 0.25) and Settings.fullscreen, "settings come back from disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = real_path
	Settings.load_settings()


func _check_music() -> void:
	for track in MusicSynth.TRACKS:
		var w := MusicSynth.render(track, 1)
		var frames := w.data.size() / 2
		expect(w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_end == frames, "%s music loops" % track)
		var peak := 0
		for n in range(0, frames, 7):
			peak = maxi(peak, absi(w.data.decode_s16(n * 2)))
		expect(peak > 3000 and peak < 32767, "%s music is audible and does not clip" % track)
	expect(MusicSynth.midi_hz(69) == 440.0, "A4 is 440 Hz")


func _check_menus() -> void:
	SaveGame.new_game()
	Shop.day = 9
	SaveGame.save_game()
	expect(SaveGame.peek().get("day", 0) == 9, "the title screen can read the saved day")
	var title: Control = load("res://scenes/menu/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	if not title.has_method("_go_to_shop"):
		expect(false, "the title script loads")
		return
	expect(not title._continue.disabled and "Day 9" in title._save_info.text, "Continue shows the saved shop")
	expect(SaveGame.first_empty_slot() == 2, "New game would start in a free slot, keeping day 9")
	title._open_settings()
	await get_tree().process_frame
	expect(title._settings != null and not title._menu.visible, "Settings opens from the title")
	title._settings.close()
	expect(title._settings == null and title._menu.visible, "Settings closes back to the menu")
	# fill every slot: New game then opens the slots page instead of erasing one
	for n in range(2, SaveGame.SLOTS + 1):
		SaveGame.set_slot(n)
		SaveGame.save_game()
	SaveGame.set_slot(1)
	title._on_new_game()
	await get_tree().process_frame
	expect(title._slots != null and not title._menu.visible and "full" in title._slots._hint.text, "New game with every slot full opens the slots page")
	expect(title._slots._rows.get_child_count() == SaveGame.SLOTS, "the slots page lists every slot")
	title._slots._on_delete(3)
	expect(SaveGame.slot_has_save(3), "Delete asks first")
	title._slots._on_delete(3)
	expect(not SaveGame.slot_has_save(3) and SaveGame.slot_has_save(2), "pressing Delete again clears only that slot")
	title._slots.close()
	await get_tree().process_frame
	expect(title._slots == null and title._menu.visible and not title._continue.disabled, "the slots page closes back to the menu")
	title.queue_free()
	_clear_slots()
	SaveGame.set_slot(1)
	title = load("res://scenes/menu/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	expect(title._continue.disabled, "Continue is off without a save")
	title.queue_free()

	Tutorial.skip_all() # the guided first day has its own check
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop._open_shop()
	shop.open_pause_menu()
	expect(get_tree().paused and shop._pause.is_open(), "the pause menu pauses the game")
	var clock: float = shop.time
	await get_tree().process_frame
	await get_tree().process_frame
	expect(is_equal_approx(shop.time, clock), "the shop clock stops while paused")
	shop._pause.close()
	expect(not get_tree().paused and not shop._pause.is_open(), "Resume unpauses")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.delete_save()
	Shop.reset()


## The guided first day from the welcome card to the summary, the bench intros, and Skip.
func _check_tutorial() -> void:
	SaveGame.new_game()
	expect(not Tutorial.first_day_done, "a new game starts the tutorial")
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	await get_tree().process_frame
	if not shop.has_method("admit") or shop.coach == null:
		expect(false, "the shop has a coach")
		return
	var coach: Coach = shop.coach
	expect(coach.guiding and coach.step == "welcome" and coach._card.visible, "the morning opens on the welcome card")
	_press_card(coach, 0)
	expect(coach.step == "prices", "Show me moves on to the ticker")
	_press_card(coach, 0)
	_press_card(coach, 0)
	expect(coach.step == "open", "the cards lead to Open the shop")
	await get_tree().process_frame
	expect(coach._target is Callable and coach._target.call() is Rect2, "the card points at Open the shop")
	shop._open_shop()
	expect(coach.step == "june_walk" and shop.queue.size() == 1, "the first scripted customer walks in")
	expect(coach.holds_clock(), "the clock waits during the guided customers")
	# June: test her genuine coins and buy them
	var june: Customer = shop.queue[0]
	june.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	await get_tree().process_frame
	expect(coach.step == "june_counter" and is_zero_approx(shop.time), "June reaches the counter and the clock hasn't moved")
	shop._on_action("test")
	expect(coach.step == "june_tools", "the coin test explains the tools")
	shop._test.use_tool("scale")
	shop._test.use_tool("calipers")
	await get_tree().create_timer(2.0).timeout
	expect(coach.step == "june_call", "after measuring, the coach says to call it genuine")
	shop._test.finished.emit("genuine")
	expect(coach.step == "june_offer", "back at the counter, make an offer")
	var cash := Shop.cash
	shop._on_action("offer")
	expect(Shop.cash < cash and june.dealt, "June takes the offer")
	expect(coach.step == "between", "the coach waits before the next customer")
	_press_card(coach, 0)
	# Slick: the magnet catches his steel fakes
	expect(coach.step == "slick_walk", "the nervous seller walks in")
	var slick: Customer = shop.queue[0]
	expect(slick.fake == "steel", "his coins are fake")
	slick.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	await get_tree().process_frame
	shop._on_action("test")
	expect(coach.step == "slick_tools", "the coach points at the magnet")
	shop._test.use_tool("magnet")
	await get_tree().create_timer(1.6).timeout
	expect(coach.step == "slick_call", "the magnet snaps and the coach says to call it fake")
	shop._test.finished.emit("fake")
	expect(slick.caught and not shop.queue.has(slick), "Slick is caught and leaves")
	_press_card(coach, 0)
	# Priya buys from the vault
	expect(coach.step == "priya_walk", "the buyer walks in")
	var priya: Customer = shop.queue[0]
	priya.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	await get_tree().process_frame
	expect(coach.step == "priya_counter", "the coach points at Sell")
	cash = Shop.cash
	shop._on_action("sell")
	expect(Shop.cash > cash and coach.step == "free", "Priya buys and the guided part ends")
	_press_card(coach, 0)
	expect(not coach.holds_clock() and coach.step == "open_day", "Got it hands the shop back")
	await get_tree().process_frame
	expect(shop.time > 0.0, "the clock runs again")
	# a jewellery seller in free play gets the bench intro once
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var j := _jewellery_seller(rng, "XAU", "14K")
	shop.queue.push_front(j)
	j.pos = ShopArt.SLOTS[0]
	await get_tree().process_frame
	shop._open_test(j)
	expect(coach._card.visible and coach._title.text == "Jewellery appraisal", "the jewellery bench gets an intro")
	shop._test.finished.emit("cancel")
	expect(Tutorial.has_seen("jewellery") and not coach._card.visible, "the intro is shown only once")
	shop._open_test(j)
	expect(not coach._card.visible, "no intro the second time")
	shop._test.finished.emit("cancel")
	# closing: the coach holds the vault clock until Start
	shop.queue.clear()
	shop.leaving.clear()
	shop.time = shop.DAY_SECONDS + 1.0
	shop._tick(0.0)
	expect(coach.step == "vault" and shop._vault.paused, "the vault waits for the lock-up card")
	await get_tree().process_frame
	await get_tree().process_frame
	expect(is_zero_approx(shop._vault.elapsed), "the vault clock waits")
	_press_card(coach, 0)
	expect(not shop._vault.paused, "Start the clock starts the lock-up")
	shop._vault.lock_up()
	shop._vault.finished.emit(shop._vault.report)
	expect(coach.step == "summary", "the summary gets the last card")
	_press_card(coach, 0)
	expect(Tutorial.first_day_done and not coach.guiding, "Finish ends the tutorial")
	shop._open_next_day()
	await get_tree().process_frame
	expect(not coach._card.visible, "day 2 has no cards")
	expect(SaveGame.load_game() and Tutorial.first_day_done and Tutorial.has_seen("jewellery"), "the tutorial is saved")
	shop.queue_free()
	await get_tree().process_frame
	# Skip tutorial, straight from the welcome card
	SaveGame.new_game()
	shop = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	await get_tree().process_frame
	coach = shop.coach
	expect(coach._card.visible, "the welcome card is up again in a new game")
	_press_card(coach, coach._row.get_child_count() - 1)
	expect(Tutorial.first_day_done and Tutorial.has_seen("bar") and not coach._card.visible, "Skip tutorial skips everything")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
	expect(saved.get("tutorial", {}).get("first_day_done", false), "skipping is saved right away")
	shop._open_shop()
	expect(shop.queue.is_empty() and not coach.holds_clock(), "no scripted customers after skipping")
	shop.queue_free()
	# let the button clicks finish playing
	await get_tree().create_timer(0.4).timeout
	SaveGame.delete_save()
	Shop.reset()


func _press_card(coach: Coach, index: int) -> void:
	var b: Button = coach._row.get_child(index)
	b.pressed.emit()
