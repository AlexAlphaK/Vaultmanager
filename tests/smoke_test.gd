extends Node
## Headless checks for the shop, the coin test, the jewellery appraisal, the bar test, the vault lock-up,
## the customers (archetypes, haggling, regulars' stories), staff and rush hours, counter, bench
## and room upgrades with the floor plan, the menus, settings and music, the tutorial, the
## ledger of records and achievements, robberies (hold-ups and burglar crews), the rival
## shops on the town map, the story campaign, the trading desk, the smelter and coin grading, the auction house,
## gamepad controls with screen scaling, the seasons and town events, and the angel investor. Run:
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
	TranslationServer.set_locale("en") # the checks read English text, whatever the device speaks
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
	_check_shop_sounds()
	await _check_vault_scene()
	await _check_shop_day()
	await _check_jewellery_deals()
	await _check_bar_deals()
	_check_staff()
	_check_staff_progression()
	_check_wholesaler()
	await _check_orders()
	_check_rush_hours()
	await _check_rush_day()
	await _check_shop_upgrades()
	await _check_trading_desk()
	await _check_smelter()
	await _check_grading()
	await _check_auction()
	_check_burglar_crews()
	await _check_holdups()
	await _check_rivals()
	await _check_calendar()
	await _check_story()
	_check_investor()
	_check_settings()
	_check_localization()
	await _check_translated_panels()
	_check_music()
	await _check_menus()
	await _check_pad()
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


func _check_shop_sounds() -> void:
	var streams := [Sfx.door_bell(), Sfx.register_chime(), ShopSfx.service_bell(), ShopSfx.sparkle(), ShopSfx.wrong(), ShopSfx.whoosh()]
	for take in 3:
		streams.append(ShopSfx.coin_clink(take))
	for mood in ShopSfx.MOODS:
		streams.append(ShopSfx.voice(mood, 0.75))
		streams.append(ShopSfx.voice(mood, 1.35))
	var quiet := 0
	for w in streams:
		var loud := 0
		for n in range(0, w.data.size() - 1, 64):
			loud = maxi(loud, absi(w.data.decode_s16(n)))
		if w.data.size() < 2000 or loud < 2000:
			quiet += 1
	expect(quiet == 0, "every shop sound renders and is audible (%d silent)" % quiet)
	expect(ShopSfx.voice("happy", ShopSfx.pitch_for(12)) == ShopSfx.voice("happy", ShopSfx.pitch_for(12)), "a customer's voice is cached")


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
	expect(shop.fx.coins.size() > 0, "a deal sends coins flying across the counter")
	shop.time += 9.0
	shop._tick(0.0)
	expect(shop.pending_fakes.is_empty() and Shop.stats.scammed == 1.0, "assay lab catches the fake")
	expect(shop.fx.parts.any(func(p): return p.get("text", "") == "FAKE!"), "the assay lab's verdict pops up over the till")
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


## Staff level up with work, ask for raises once their pay lags their level, sour and
## quit if refused for long, have bad days, and keep it all in the save.
func _check_staff_progression() -> void:
	SaveGame.new_game()
	Shop.day = 1
	Day.begin_day()
	Shop.cash = 50000.0
	expect(Staff.hire("clerk") and Staff.hire("guard"), "hire both for the progression check")
	expect(Staff.level("clerk") == 1 and Staff.raises_owed("clerk") == 0, "a new hire starts at level 1, fairly paid")
	var slow := Staff.clerk_seconds()
	var stop := Staff.guard_stop()
	Staff.gain_xp("clerk", Staff.LEVEL_XP[2])
	Staff.gain_xp("guard", Staff.LEVEL_XP[1])
	expect(Staff.level("clerk") == 3 and Staff.level("guard") == 2, "experience brings levels")
	expect(Staff.clerk_seconds() < slow and Staff.clerk_persuade() > 0.0, "a skilled clerk is quicker and talks buyers round")
	expect(Staff.guard_stop() > stop, "a seasoned guard stops more robbers")
	expect(Staff.raises_owed("clerk") == 2 and Staff.fair_wage("clerk") > Staff.wage("clerk"), "levels make the old wage unfair")
	# a day's work, underpaid: their mood slips and they ask in the morning
	var mood := float(Staff.info("clerk").mood)
	Day.open_shop()
	Day.close_shop()
	var report := Day.end_day()
	expect(float(Staff.info("clerk").mood) < mood, "underpaid staff sour")
	expect(report.lines.any(func(l): return str(l).contains("level")), "level-ups make the day's summary")
	Shop.next_day()
	Day.begin_day()
	expect(Staff.raise_requests().has("clerk") and Staff.morning_line().contains("raise"), "the clerk asks for a raise in the morning")
	var wage := Staff.wage("clerk")
	mood = float(Staff.info("clerk").mood)
	expect(Staff.agree_raise("clerk") and Staff.wage("clerk") > wage and float(Staff.info("clerk").mood) > mood, "a raise lifts pay and mood")
	expect(not Staff.agree_raise("clerk"), "one raise per request")
	Staff.info("guard").asking = true
	mood = float(Staff.info("guard").mood)
	expect(Staff.refuse_raise("guard") and float(Staff.info("guard").mood) < mood, "saying no stings")
	# the morning roll is fixed for the day, even when the day is replayed
	var before := Staff.to_dict()
	Staff.from_dict(before)
	Staff._rolled_day = 0
	Day.begin_day()
	expect(Staff.info("clerk").today == before.crew.clerk.today and Staff.info("guard").today == before.crew.guard.today, "a replayed morning rolls the same bad days")
	# bad days: sick staff stay home and are not paid
	Staff.info("guard").today = "sick"
	expect(not Staff.on_duty("guard") and Staff.guard_stop() == 0.0, "a guard off sick guards nothing")
	Staff.info("clerk").today = "grumpy"
	expect(Staff.clerk_persuade() == 0.0 and Staff.clerk_seconds() > Staff.CLERK_SECONDS / (1.0 + Progress.effect("clerk_speed")), "a grumpy clerk is slow and won't haggle")
	Day.open_shop()
	Day.close_shop()
	report = Day.end_day()
	expect(not report.ledger.any(func(e): return str(e.label) == "Wages: %s" % Staff.ROLES.guard.name), "no wages for a sick day")
	# saved and loaded with levels and mood
	expect(SaveGame.save_game(), "save with staff progress")
	var level := Staff.level("clerk")
	Staff.reset()
	expect(SaveGame.load_game() and Staff.level("clerk") == level and int(Staff.info("clerk").raises) == 1, "levels and raises come back from the save")
	# old saves without the crew section still load
	Staff.from_dict({"hired": ["clerk"]})
	expect(Staff.has("clerk") and Staff.level("clerk") == 1, "an old save's staff start at level 1")
	# fed up for good: they quit in the morning
	Staff.info("clerk").mood = 0.0
	Staff.info("clerk").days = 3
	Shop.next_day()
	Day.begin_day()
	expect(not Staff.has("clerk"), "staff with no patience left quit")
	# a veteran earns the achievement
	expect(Staff.hire("guard"), "hire a guard again")
	Staff.gain_xp("guard", Staff.LEVEL_XP[4])
	expect(Staff.level("guard") == 5 and Records.value_of("staff_level") == 5.0, "the ledger sees a veteran")
	SaveGame.new_game()
	expect(Staff.crew.is_empty(), "a new game clears staff progress")


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


## Collectors place special orders, the coins are set aside, and the collector comes back
## to pay the agreed price (or the order falls through). Rare coins come from walk-in
## sellers and the dealer network.
func _check_orders() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop.has_method("_open_shop") or get_node_or_null("/root/Orders") == null:
		expect(false, "the Orders autoload loads")
		return
	var double: BullionItem = Shop.coins.get("double_eagle_1924")
	expect(double != null and double.rare and not Shop.coin_list().has(double), "rare coins load but stay off the everyday list")
	expect(Shop.rare_list().size() >= 5 and Shop.rare_list().all(func(it): return it.collector_premium > 0.0), "every rare coin has a collector premium")
	Shop.day = 5
	Shop.reputation = 3.0
	shop._open_shop()
	shop.queue.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	expect(Orders.can_take(), "orders can walk in from day %d" % Orders.MIN_DAY)
	Orders.order_today = true
	var offers := 0
	for n in 200:
		var walk := Orders.next_customer(rng)
		if walk:
			offers += 1
	expect(offers == 1 and not Orders.order_today, "at most one new order a day")
	# a collector asks for a coin; taking the order puts it on the books
	var asks := Orders.offer_customer(rng)
	asks.item = double
	asks.qty = 1
	asks.order.item = double.id
	asks.order.qty = 1
	asks.order.premium = 0.5
	asks.order.due = Shop.day + 3
	asks.pos = ShopArt.SLOTS[0]
	shop.queue.append(asks)
	await get_tree().process_frame
	expect(asks.kind == "order" and shop._front() == asks, "a collector comes in with a special order")
	shop.hud.show_customer(asks)
	expect(shop.hud._buttons.sell.visible and shop.hud._buttons.sell.text == "Take order", "the counter card offers to take the order")
	shop._on_action("sell")
	expect(Orders.open.size() == 1 and not shop.queue.has(asks), "taking the order books it")
	expect(Orders.next_customer(rng) == null or Orders.open.size() == 1, "the collector does not come back the same day")
	# a seller may bring the wanted coin; it is set aside, not sold to walk-ins
	var found := false
	for n in 400:
		var c := Customer.create(Shop.day, 3.0, Shop.coin_list(), rng)
		c.kind = "seller"
		c.piece = null
		c.bar = null
		Orders.maybe_rare_seller(c, rng)
		if c.item == double:
			found = true
			expect(Customers.tag(c) == "old coin" or c.archetype == "shady", "the card tags an old coin")
			break
	expect(found, "walk-in sellers sometimes bring the coin a collector wants")
	Shop.add_stock(double, 1, double.melt_value())
	expect(Shop.count_of_item(double) == 1 and Shop.spare_of(double) == 0, "the rare coin is set aside for the order")
	var gold_before := Shop.count_of("XAU")
	var walk_in := Customer.create(Shop.day, 3.0, Shop.coin_list(), rng)
	walk_in.kind = "buyer"
	walk_in.item = Shop.coins["gold_eagle"]
	walk_in.wanted_exact = false
	walk_in.qty = 50
	expect(walk_in.stock_have() == gold_before, "a walk-in buyer never sees rare coins")
	# a bulk order sets everyday coins aside too
	var maple: BullionItem = Shop.coins["silver_maple"]
	Shop.add_stock(maple, 12, 25.0)
	var silver := Shop.count_of("XAG")
	Orders.open.append({"id": 99, "name": "Mr. Bulk", "look": 1, "item": maple.id, "qty": 10, "premium": 0.12,
		"placed": Shop.day, "due": Shop.day, "visited": 0})
	expect(Shop.count_of("XAG") == silver - 10 and Shop.spare_of(maple) == 2, "bulk order coins are held back")
	Shop.take_stock("XAG", 1000)
	expect(Shop.count_of_item(maple) == 10 and Shop.count_of_item(double) == 1, "selling to walk-ins leaves the set-aside coins")
	# the bulk collector is due today and picks up first, at the agreed price
	var pickup := Orders.next_customer(rng)
	expect(pickup != null and pickup.order.item == maple.id and pickup.kind == "buyer", "the collector comes back on the due day")
	Shop.sell_premium = 0.02
	expect(pickup.hear_price(Shop.sell_premium) and is_equal_approx(pickup.sale_total(), maple.melt_value() * 10 * 1.12), "they pay the agreed premium")
	var rep := Shop.reputation
	pickup.pos = ShopArt.SLOTS[0]
	shop.queue.append(pickup)
	await get_tree().process_frame
	shop._on_action("sell")
	expect(pickup.dealt and Shop.count_of_item(maple) == 0 and Orders.open.size() == 1, "the order is filled")
	expect(Shop.reputation > rep and Shop.stats.get("orders_filled", 0.0) == 1.0, "a filled order earns reputation")
	# the rare coin is already here, so its collector comes early, the next day
	expect(Orders.next_customer(rng) == null, "one visit a day")
	Shop.day += 1
	var early := Orders.next_customer(rng)
	expect(early != null and early.item == double, "the collector comes early once you hold the coin")
	early.pos = ShopArt.SLOTS[0]
	shop.queue.append(early)
	await get_tree().process_frame
	shop._on_action("decline")
	expect(Orders.open.size() == 1, "turning them away early keeps the order open")
	# save and load keep the order
	SaveGame.save_game()
	Orders.reset()
	SaveGame.load_game()
	expect(Orders.open.size() == 1 and Orders.open[0].item == double.id, "open orders are saved")
	# on the due day without the coin, the order falls through
	Shop.take_stock("XAU", 1, double)
	Shop.day = int(Orders.open[0].due)
	var due := Orders.next_customer(rng)
	expect(due != null and due.stock_have() == 0, "the collector comes on the due day")
	rep = Shop.reputation
	due.pos = ShopArt.SLOTS[0]
	shop.queue.append(due)
	await get_tree().process_frame
	shop._on_action("decline")
	expect(Orders.open.is_empty() and Shop.reputation < rep, "a missed order costs reputation")
	# the dealer network sells a wanted rare coin in the morning, at most of the premium
	Orders.open.append({"id": 100, "name": "Dr. Ng", "look": 2, "item": double.id, "qty": 1, "premium": 0.5,
		"placed": Shop.day, "due": Shop.day + 4, "visited": Shop.day})
	Day.phase = Day.MORNING
	Orders.dealer[double.id] = 1
	Shop.cash = 50000.0
	expect(Orders.dealer_price(double) > double.melt_value() * 1.3, "the dealer charges a finder's fee")
	expect(Orders.dealer_buy(double) and Shop.count_of_item(double) == 1 and not Orders.dealer_buy(double), "buy the one coin the dealer found")
	# a collector off the street pays a collector's price for a spare rare coin
	Orders.open.clear()
	var col := Customer.create(Shop.day, 3.0, Shop.coin_list(), rng)
	Customers.apply_archetype(col, "collector", rng)
	if col.item == double:
		expect(col.fixed_price() and col.sale_total() > double.melt_value() * 1.3, "collectors pay well for a rare coin")
	shop.queue_free()
	SaveGame.new_game()
## The rival shops: who wins the town's customers, Sterling's repricing, the rivals'
## moves and your answers, their books and the town map.
func _check_rivals() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	Day.begin_day()
	var share := Rivals.overall_share()
	expect(share > 0.4 and share < 0.65, "a new shop gets about a fair share of the town (%.2f)" % share)
	expect(Rivals.traffic_factor() >= 1.0 and Rivals.traffic_factor() <= Rivals.MAX_BOOST, "the traffic factor stays in range")
	var sellers := Rivals.share("seller")
	Shop.set_buy_percent(0.95)
	expect(Rivals.share("seller") > sellers, "paying sellers more wins more of them")
	Shop.set_buy_percent(0.9)
	var buyers := Rivals.share("buyer")
	Shop.set_sell_premium(0.03)
	expect(Rivals.share("buyer") > buyers, "a smaller premium wins more buyers")
	Shop.set_sell_premium(0.06)
	Shop.reputation = 4.5
	expect(Rivals.overall_share() > share, "stars win customers too")
	expect(Rivals.share("seller", "shady") < Rivals.share("seller"), "shady sellers drift to the pawn shop")
	var quiet := true
	for d in range(3, 40):
		Rivals._on_day_started(d)
		quiet = quiet and Rivals.move_of("sterling") == ""
	expect(Progress.tier == 0 and quiet, "Sterling leaves a corner counter alone")
	Rivals.reset()
	# terrible prices and a bad name send people across the street
	Shop.reputation = 0.5
	Shop.set_buy_percent(0.7)
	Shop.set_sell_premium(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var c := Customer.create(5, 0.5, Shop.coin_list(), rng)
	# the corner counter's customers are mostly locals, so at most MAX_DIVERT[0] cross the street
	expect(Rivals.divert_odds(c) > 0.15, "a bad deal sends customers to the rivals")
	c.regular_id = "lev"
	expect(Rivals.divert_odds(c) == 0.0, "regulars always come in")
	c.regular_id = ""
	c.event_id = "news"
	expect(Rivals.divert_odds(c) == 0.0, "customers a headline sent always come in")
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop.coach.skip()
	shop._open_shop()
	shop.rng.seed = 3
	for n in 40:
		shop._spawn()
		shop.queue.clear()
	var lost := int(Shop.stats.get("lost_to_rival", 0.0))
	expect(lost >= 4, "the shop loses customers to the rivals (%d of 40)" % lost)
	expect(int(Rivals.lost_today.get("sterling", 0)) + int(Rivals.lost_today.get("pawn", 0)) == lost, "each lost customer is booked to a rival")
	# the rivals' books: they grow, and the summary says where the customers went
	var worth := Rivals.worth_of("sterling")
	var report := {"lines": []}
	Rivals._on_day_ended(Shop.day, report)
	expect(Rivals.worth_of("sterling") > worth, "Sterling grows overnight")
	expect(report.lines.any(func(l): return "went to the competition" in l), "the summary counts customers lost to rivals")
	shop.queue_free()
	await get_tree().process_frame
	# Sterling reprices against a winning shop, once per morning
	Shop.reputation = 4.0
	Shop.set_buy_percent(0.9)
	Shop.set_sell_premium(0.06)
	Rivals.last_share = 0.8
	var margin := Rivals.buy_of("sterling") - Rivals.premium_of("sterling")
	Shop.day += 1
	Day.begin_day()
	var after := Rivals.buy_of("sterling") - Rivals.premium_of("sterling")
	expect(is_equal_approx(after, margin + 0.01) or Rivals.move_of("sterling") == "price_war", "Sterling cuts a point when you are winning")
	var ad_cost := Rivals.ad_cost()
	Day.begin_day()
	expect(is_equal_approx(Rivals.buy_of("sterling") - Rivals.premium_of("sterling"), after), "replaying a morning does not reprice twice")
	# moves: a price war beats your board, and Beat Sterling answers it
	Rivals.state.sterling.move = "price_war"
	Rivals.state.sterling.move_days = 3
	expect(Rivals.buy_of("sterling") == 0.92 and Rivals.premium_of("sterling") == 0.03, "a price war pays 92% and sells at +3%")
	var warred := Rivals.overall_share()
	Rivals.beat_sterling()
	expect(Shop.buy_percent == 0.93 and Shop.sell_premium == 0.02, "Beat Sterling sets your board a point better")
	expect(Rivals.overall_share() > warred, "beating Sterling's prices wins customers back")
	# a newspaper ad
	Shop.cash = 50000.0
	expect(Rivals.run_ad() and is_equal_approx(Shop.cash, 50000.0 - ad_cost) and Rivals.ad_days == Rivals.AD_DAYS, "run a newspaper ad")
	expect(not Rivals.can_run_ad(), "one ad at a time")
	# the pawn shop's fencing racket and the tip-off
	Rivals.state.pawn.move = ""
	expect(not Rivals.can_tip_off(), "nothing to tip off about yet")
	Rivals.state.pawn.move = "fencing"
	Rivals.state.pawn.move_days = 4
	var stars := Shop.reputation
	expect(Rivals.tip_off(), "tip off the police")
	expect(not Rivals.is_open("pawn") and Shop.reputation > stars, "the raid shuts Lucky's and your name grows")
	expect(Records.is_earned("tip_off"), "the tip earns Good citizen")
	var no_pawn := Rivals.share("seller", "shady")
	expect(no_pawn > 0.3, "with Lucky's shut, shady sellers come to you")
	# save and load
	var saved := Rivals.to_dict()
	Rivals.reset()
	Rivals.from_dict(JSON.parse_string(JSON.stringify(saved)))
	expect(not Rivals.is_open("pawn") and Rivals.ad_days == Rivals.AD_DAYS and Rivals.move_of("sterling") == "price_war", "the rivals save and load")
	# passing the rivals in net worth
	Shop.cash = 1000000.0
	report = {"lines": []}
	Rivals._on_day_ended(Shop.day, report)
	Records.check()
	expect(Rivals.passed.has("sterling") and Rivals.passed.has("pawn") and Rivals.rank() == 1, "a millionaire shop passes both rivals")
	expect(Records.is_earned("pass_sterling") and Records.is_earned("pass_pawn"), "passing the rivals earns achievements")
	expect(report.lines.any(func(l): return "bigger than Sterling" in l), "the summary celebrates passing Sterling")
	# the town map paints in every state, and the page builds
	for view in [{}, {"tier": 3, "pawn_closed": true, "sterling_move": "price_war"}, {"pawn_move": "fencing"}, {"pawn_move": "clearance"}]:
		var town := TownArt.paint(view)
		expect(town.width == TownArt.SIZE.x and town.height == TownArt.SIZE.y, "the town map paints")
	var panels := DayPanels.new()
	add_child(panels)
	panels.show_town()
	expect(panels.visible and panels.page == "town", "the town map page opens")
	panels.queue_free()
	SaveGame.new_game()
	expect(Rivals.is_open("pawn") and Rivals.passed.is_empty() and Rivals.ad_days == 0, "a new game resets the rivals")


func _check_calendar() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	# the year: spring, summer, autumn and winter of two weeks each, then spring again
	expect(Calendar.season(1).id == "spring" and Calendar.day_of_season(1) == 1, "day 1 is the first day of spring")
	expect(Calendar.season(15).id == "summer" and Calendar.season(29).id == "autumn" and Calendar.season(56).id == "winter", "the seasons follow each other")
	expect(Calendar.season(57).id == "spring" and Calendar.year(57) == 2, "a new year starts after winter")
	expect(Calendar.label(9) == "Spring, day 9 of 14", "the morning names the season")
	expect(Calendar.event_on(1).is_empty() and Calendar.event_on(8).id == "tax_season" and Calendar.event_on(11).id == "tax_season", "tax season in spring")
	expect(Calendar.event_on(15).id == "gold_fever" and Calendar.event_on(21).id == "gold_fever" and Calendar.event_on(22).is_empty(), "gold fever week opens summer")
	expect(Calendar.event_on(41).id == "coin_show" and Day.weekday(41) == "Saturday" and Day.weekday(42) == "Sunday", "the coin show is on autumn's second weekend")
	expect(Calendar.event_on(48).id == "gift_rush" and Calendar.event_on(54).id == "gift_rush" and Calendar.event_on(105).id == "gift_rush", "the holiday rush comes every winter")
	var next := Calendar.next_event(1)
	expect(next.event.id == "tax_season" and int(next.day) == 8, "the next event is tax season on day 8")
	next = Calendar.next_event(9)
	expect(next.event.id == "gold_fever" and int(next.day) == 15, "the next event skips the one under way")
	expect(Calendar.first_day(Calendar.EVENTS[3], 50) == 48 and Calendar.last_day(Calendar.EVENTS[3], 50) == 54, "an event knows its first and last day")
	# no events while the tutorial still runs
	Shop.day = 48
	Tutorial.first_day_done = false
	expect(Calendar.today().is_empty(), "no town events during the tutorial")
	Tutorial.first_day_done = true
	# the holiday rush: gift buyers who want small coins and pay a premium
	expect(Calendar.today().id == "gift_rush", "the holiday rush is on today")
	expect(Calendar.spawn_factor() < 0.9, "the holiday rush brings customers faster")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var gifts := 0
	var silver_qty := 0
	for n in 200:
		var e := Calendar.customer_event(rng)
		if e.is_empty():
			continue
		var c := Customers.next_customer(rng, e)
		if c.event_id == "gift_rush":
			gifts += 1
			expect(c.kind == "buyer", "gift shoppers buy")
			if c.item.metal == "XAG":
				silver_qty = maxi(silver_qty, c.qty)
	expect(gifts > 80 and gifts < 140, "about half the customers come for the holiday rush (%d of 200)" % gifts)
	expect(silver_qty > 0 and silver_qty <= 14, "gift shoppers want small amounts (%d silver at most)" % silver_qty)
	# a winter day without an event is quieter than a spring one
	Shop.day = 45
	expect(Calendar.today().is_empty() and Calendar.spawn_factor() > 1.0, "winter keeps people at home")
	# gold fever: gold buyers, with some sellers cashing in
	Shop.day = 16
	var kinds := {}
	for n in 200:
		var e := Calendar.customer_event(rng)
		if not e.is_empty():
			var c := Customers.next_customer(rng, e)
			expect(c.item.metal == "XAU", "gold fever is all about gold")
			kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
	expect(int(kinds.get("buyer", 0)) > int(kinds.get("seller", 0)) and int(kinds.get("seller", 0)) > 0, "gold fever brings buyers and some sellers (%s)" % kinds)
	# town crowds shop around: with a bad board they may cross the street
	Shop.reputation = 0.5
	Shop.set_sell_premium(0.2)
	var shopper := Customers.next_customer(rng, {"id": "gold_fever", "kind": "buyer", "metal": "XAU", "lines": ["Gold!"]})
	expect(Rivals.divert_odds(shopper) > 0.0, "town event customers can go to the rivals")
	Shop.reputation = 2.5
	Shop.set_sell_premium(Shop.DEFAULT_SELL_PREMIUM)
	# the coin show: collectors, and more of them with a booth
	Shop.day = 40
	Shop.cash = 20000.0
	Day.begin_day()
	var show := Calendar.booth_event()
	expect(show.get("id", "") == "coin_show" and Calendar.today().is_empty(), "the booth can be booked the morning before the show")
	var cost := Calendar.booth_cost()
	var stars := Shop.reputation
	expect(Calendar.book_booth() and is_equal_approx(Shop.cash, 20000.0 - cost) and Shop.reputation > stars, "book a booth at the coin show")
	expect(not Calendar.can_book_booth() and Calendar.booths == 1 and Records.is_earned("booth"), "one booth per show, and it earns Show table")
	Shop.day = 41
	Day.begin_day()
	expect(Calendar.has_booth(Calendar.today()), "the booth is yours on the show's first day")
	var collectors := 0
	for n in 100:
		var e := Calendar.customer_event(rng)
		if not e.is_empty():
			var c := Customers.next_customer(rng, e)
			if c.archetype == "collector" and c.event_id == "coin_show":
				collectors += 1
	expect(collectors > 45, "a booth at the show brings collectors (%d of 100)" % collectors)
	expect(Calendar.opening_rush() == 3, "collectors wait at the door")
	Shop.day = 42
	expect(Calendar.has_booth(Calendar.today()), "the booth lasts the whole weekend")
	Shop.day = 97
	expect(not Calendar.has_booth(Calendar.today()), "next year's show needs a new booth")
	# Tax Day takes its share of the profit since the last one
	Shop.day = 11
	Shop.cash = 20000.0
	Calendar.taxable = 0.0
	Day.begin_day()
	# the days closed since the last Tax Day: deal profit, less every cost
	Calendar._on_day_ended(10, {"lines": [], "stats": {"profit": 12000.0},
		"ledger": [{"label": "Upkeep", "usd": -500.0}, {"label": "Bench", "usd": -1500.0}, {"label": "Refiner", "usd": 900.0}]})
	expect(is_equal_approx(Calendar.taxable, 10000.0), "taxable profit is deal profit less bills and spending")
	expect(is_equal_approx(Calendar.tax_due(), 1000.0) and int(Calendar.next_tax().day) == 11, "tax is 10% of the profit since the last Tax Day")
	Day.open_shop()
	Day.close_shop()
	var report := Day.end_day()
	expect(Day.ledger.any(func(l): return l.label == "Tax Day" and is_equal_approx(l.usd, -1000.0)), "Tax Day is paid when the shop closes")
	expect(report.lines.any(func(l): return str(l).begins_with("Tax Day: you paid")), "the summary explains the tax")
	expect(report.lines.any(func(l): return str(l).to_lower().begins_with("tax season is over")), "the summary closes the event")
	expect(int(Calendar.next_tax(12).day) == 67, "the next Tax Day is next spring")
	expect(Calendar.taxable < 0.0, "Tax Day's own bill is not a cost, the day's upkeep is (%.0f)" % Calendar.taxable)
	# served event customers are counted, and the best rush earns an achievement
	Shop.day = 48
	Day.begin_day()
	for n in 40:
		var c := Customer.new()
		c.event_id = "gift_rush"
		c.dealt = true
		Calendar.on_leave(c)
	Records.check()
	expect(Calendar.best_of("gift_rush") == 40 and Records.is_earned("gift_rush"), "40 gift shoppers in one rush earns Season's greetings")
	# the summary warns about tomorrow's event, and the season's end
	report = {"lines": []}
	Calendar._on_day_ended(47, report)
	expect(report.lines.any(func(l): return str(l).to_lower().begins_with("tomorrow: holiday gift rush")), "the summary warns about tomorrow's event")
	report = {"lines": []}
	Calendar._on_day_ended(42, report)
	expect(report.lines.any(func(l): return "Autumn is over" in str(l)), "the summary marks the end of a season")
	# save and load
	var saved := Calendar.to_dict()
	Calendar.reset()
	Calendar.from_dict(JSON.parse_string(JSON.stringify(saved)))
	expect(Calendar.booths == 1 and Calendar.best_of("gift_rush") == 40 and Calendar.booth_day == 41, "the calendar saves and loads")
	# the window dresses for each season
	for id in ["spring", "summer", "autumn", "winter"]:
		var room := ShopArt.paint_room(false, id)
		expect(room.width == ShopArt.SIZE.x, "the shop paints in %s" % id)
	# the morning panel and the shop floor on an event day
	Shop.day = 40
	Day.begin_day()
	var panels := DayPanels.new()
	add_child(panels)
	panels.show_morning()
	var texts := []
	for child in panels._box.get_children():
		if child is Label:
			texts.append(child.text)
		for b in child.get_children():
			if b is Button:
				texts.append(b.text)
	expect(texts.any(func(t): return str(t).begins_with("Town coin show tomorrow")), "the morning warns about the coin show")
	expect(texts.any(func(t): return str(t).begins_with("Booth booked")), "the morning shows the booked booth")
	panels.queue_free()
	# every morning line fits on one line of the panel, even with the biggest tax bill
	Calendar.taxable = 9999999.0
	for d in range(1, Calendar.YEAR_DAYS + 1):
		Shop.day = d
		var line := panels._town_hint()
		expect(PixelFont.measure(line) <= DayPanels.AREA.size.x - 16, "the morning line fits: " + line)
	Calendar.taxable = 0.0
	Shop.day = 48
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop.coach.skip()
	expect(shop.room._season == "winter", "the shop window shows winter")
	shop._open_shop()
	expect(shop._rush_left == 2, "holiday shoppers wait at the door")
	await get_tree().process_frame
	var banner: Node = null
	for child in shop.hud.get_children():
		if child.get_script() == shop.NewsBanner:
			banner = child
	expect(banner != null and banner.visible and banner._tag_label.text == "TOWN", "the news strip shows the town event")
	MarketEvents.start(MarketEvents.EVENTS[0], -1.5)
	await get_tree().process_frame
	expect(banner._tag_label.text == "NEWS", "breaking market news takes over the strip")
	MarketEvents.stop()
	await get_tree().process_frame
	expect(banner.visible and banner._tag_label.text == "TOWN", "the town event comes back after the news")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()
	expect(Calendar.booths == 0 and Calendar.taxable == 0.0, "a new game resets the calendar")


func _check_story() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	Day.begin_day()
	expect(Story.synced and Story.chapter == 0 and Story.pending.size() == 1, "a new game queues Mags's first visit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	Day.open_shop()
	expect(Story.next_customer(rng) == null, "Mags waits until day 2")
	Day.close_shop()
	Day.end_day()
	Shop.next_day()
	Day.begin_day()
	expect(Story.next_customer(rng) == null, "nobody visits before the shop opens")
	Day.open_shop()
	var c := Customers.next_customer(rng)
	expect(c.story == "mags_hello" and c.kind == "visit" and c.name == "Mags Holloway", "Mags walks in on day 2")
	expect(Customers.tag(c) == "mentor", "the card calls Mags your mentor")
	expect(Rivals.divert_odds(c) == 0.0, "story visitors never cross the street")
	expect(Customers.next_customer(rng).story == "", "one story visitor at a time")
	Customers.on_leave(c)
	expect(Story.pending.is_empty(), "the visit plays once")
	expect(Story.has_new_letter(), "the story button flags Mags's new note")
	# chapter 1's goals, met one by one
	Records.totals.caught = 3
	Story._check()
	expect(Story.goal_met(0) and Story.chapter == 0, "a goal ticks off on its own")
	expect(Story.goal_count(1) == "0 / 15", "the page counts a goal's progress")
	Records.totals.buys = 15
	Records.totals.days = 7
	Story._check()
	expect(Story.chapter == 1 and Story.met.is_empty(), "meeting every goal closes the chapter")
	expect(Story.pending.size() == 2 and float(Story.pending[0].reward.get("cash", 0.0)) == 1000.0, "Mags brings the reward, then Sterling comes over")
	var cash := Shop.cash
	c = Customers.next_customer(rng)
	expect(c.story == "mags_name" and "Reward" in c.note, "the card shows Mags's reward")
	Customers.on_leave(c)
	expect(is_equal_approx(Shop.cash, cash + 1000.0), "Mags's reward is paid when she leaves")
	c = Customers.next_customer(rng)
	expect(c.story == "sterling_sneer" and c.name == "Victor Sterling" and Customers.tag(c) == "rival", "Victor Sterling, the rival owner, walks in")
	Customers.on_leave(c)
	# chapter 2, and Sterling's price war at the start of chapter 3
	Records.peaks.rep = 3.2
	Rivals.passed.append("pawn")
	Progress.tier = 1
	Rivals.state.sterling.move = ""
	Story._check()
	expect(Story.chapter == 2, "moving to Main Street closes chapter 2")
	Customers.on_leave(Customers.next_customer(rng))
	c = Customers.next_customer(rng)
	expect(c.story == "sterling_war", "Sterling comes to declare war")
	Customers.on_leave(c)
	expect(Rivals.move_of("sterling") == "price_war", "Sterling's visit starts a price war")
	# save and load mid-chapter
	var saved := Story.to_dict()
	Story.reset()
	Story.from_dict(JSON.parse_string(JSON.stringify(saved)))
	expect(Story.synced and Story.chapter == 2 and Story.pending.is_empty(), "the story saves and loads")
	# the rest of the way, in one go
	Records.totals.orders_filled = 3
	Staff.hired.append("clerk")
	Progress.tier = 3
	Rivals.passed.append("sterling")
	Records.peaks.rep = 4.6
	Records.peaks.worth = 500000.0
	Story._check()
	expect(Story.is_finished() and Story.chapters_done() == Story.CHAPTERS.size(), "a shop that has done it all finishes the story")
	expect(Records.is_earned("story_done"), "finishing the story earns Apprentice no more")
	expect(Story.pending.back().beat == "mags_ribbon", "Mags comes to cut the ribbon")
	var report := {"lines": []}
	Story._on_day_ended(Shop.day, report)
	expect(report.lines.any(func(l): return "is done!" in l), "the summary says when a chapter is done")
	Staff.hired.erase("clerk")
	# the story page and the morning panel build at every stage
	var panels := DayPanels.new()
	add_child(panels)
	panels.show_story()
	expect(panels.visible and panels.page == "story", "the story page opens at the end")
	Story.reset()
	Story.synced = true
	panels.show_story()
	expect(not Story.has_new_letter(), "reading the page clears the new note flag")
	panels.show_morning()
	expect(panels.page == "morning", "the morning panel shows the chapter")
	panels.queue_free()
	# a save from before the story skips the chapters it has already done, unpaid
	SaveGame.new_game()
	Tutorial.skip_all()
	Shop.day = 40
	Records.totals.caught = 10
	Records.totals.buys = 50
	Records.totals.days = 39
	Records.peaks.rep = 3.4
	Rivals.passed.append("pawn")
	Progress.tier = 1
	Story.synced = false
	Day.begin_day()
	expect(Story.chapter == 2 and Story.pending.size() == 2, "an old save starts at the first unfinished chapter")
	expect(Story.pending.all(func(p): return p.reward.is_empty()), "skipped chapters pay no rewards")
	SaveGame.new_game()
	expect(Story.chapter == 0 and not Story.synced and Story.pending.is_empty(), "a new game resets the story")


func _check_investor() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	Shop.cash = -2500.0
	Day.begin_day()
	expect(not Investor.has_offer(), "the investor never calls on day 1")
	Day.open_shop()
	Day.close_shop()
	Day.end_day()
	Shop.next_day()
	Shop.cash = 20000.0
	Day.begin_day()
	expect(not Investor.has_offer() and Investor.morning_line() == "", "a shop that can pay its bills gets no offer")
	Day.open_shop()
	Day.close_shop()
	Day.end_day()
	Shop.next_day()
	Shop.cash = -2500.0
	Day.begin_day()
	expect(Investor.has_offer(), "an overdrawn shop gets an offer")
	expect(float(Investor.offer.stake) == Investor.STAKE[0] + 3000.0, "the stake clears the overdraft, in thousands (%s)" % Investor.offer.get("stake"))
	expect(float(Investor.offer.share) == Investor.SHARES[0], "the first stake asks for the first share")
	# the morning replays from its save with the same offer
	var saved = JSON.parse_string(JSON.stringify(Investor.to_dict()))
	Investor.reset()
	Investor.from_dict(saved)
	Shop.cash = -2400.0
	Day.begin_day()
	expect(Investor.has_offer() and float(Investor.offer.stake) == Investor.STAKE[0] + 3000.0, "a replayed morning keeps its offer")
	# the offer page opens first, once
	var panels := DayPanels.new()
	add_child(panels)
	panels.show_morning()
	expect(panels.page == "investor", "a fresh offer opens before the morning panel")
	panels.show_morning()
	expect(panels.page == "morning", "the offer page opens on its own only once a morning")
	var stake := float(Investor.offer.stake)
	expect(Investor.accept(), "the offer can be taken")
	expect(not Investor.accept() and not Investor.has_offer(), "one stake at a time")
	expect(is_equal_approx(Shop.cash, -2400.0 + stake), "the stake is paid in cash")
	expect(Day.ledger.any(func(e): return e.label == "Angel investment"), "the stake goes on the ledger")
	expect(not Story.pending.is_empty() and Story.pending[0].beat == "investor_deal", "Celeste drops by the day she buys in")
	expect(Investor.morning_line().begins_with(Investor.NAME), "the morning panel shows her share")
	panels.show_investor()
	expect(panels.page == "investor" and panels.visible, "the stake page opens")
	# her share of a good day
	Day.open_shop()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var visitor := Customers.next_customer(rng)
	expect(visitor.story == "investor_deal" and visitor.name == Investor.NAME and Customers.tag(visitor) == "investor", "Celeste walks in as a story visitor")
	Customers.on_leave(visitor)
	Shop.stats.profit = 1000.0
	Day.close_shop()
	var report := Day.end_day()
	var share := 1000.0 * Investor.SHARES[0]
	expect(report.ledger.any(func(e): return e.label == "Investor's share" and is_equal_approx(e.usd, -share)), "she takes her share of the day's profit")
	expect(is_equal_approx(float(Investor.deal.paid), share), "her share counts towards what she is owed")
	# a day without profit costs nothing
	Shop.next_day()
	Day.begin_day()
	expect(not Investor.has_offer(), "no second offer while she holds a stake")
	Day.open_shop()
	Shop.stats.profit = -300.0
	Day.close_shop()
	report = Day.end_day()
	expect(not report.ledger.any(func(e): return e.label == "Investor's share"), "a day without profit costs nothing")
	# buying her out
	Shop.next_day()
	Day.begin_day()
	var owed := Investor.owed()
	expect(is_equal_approx(owed, stake * Investor.RETURN - share), "she is owed her return less what she has had")
	Shop.cash = owed - 1.0
	expect(not Investor.can_buy_out(), "a buy-out needs the cash")
	Shop.cash = owed + 5000.0
	panels.show_investor()
	expect(Investor.buy_out(), "she can be bought out in the morning")
	expect(is_equal_approx(Shop.cash, 5000.0) and not Investor.has_deal(), "the buy-out pays what she is owed")
	expect(Investor.repaid == 1 and Records.is_earned("investor_out"), "buying her out earns Own it outright")
	expect(Story.pending[0].beat == "investor_done", "Celeste comes to say goodbye")
	expect(Investor.next_offer_day == Shop.day + Investor.WAIT_AFTER, "she waits a while before offering again")
	panels.show_ledger()
	panels.queue_free()
	# paid off through her share
	Investor.deal = {"stake": 1000.0, "share": 0.5, "cap": 1750.0, "paid": 1700.0, "day": Shop.day}
	Day.open_shop()
	Shop.stats.profit = 1000.0
	Day.close_shop()
	report = Day.end_day()
	expect(report.ledger.any(func(e): return e.label == "Investor's share" and is_equal_approx(e.usd, -50.0)), "her last share stops at what she is owed")
	expect(not Investor.has_deal() and Investor.repaid == 2, "she is out once paid in full")
	expect(report.lines.any(func(l): return Investor.NAME in l), "the summary says she is out")
	# turning her down, and the limit
	Investor.next_offer_day = 0
	Shop.next_day()
	Shop.cash = -100.0
	Day.begin_day()
	expect(Investor.has_offer() and float(Investor.offer.share) == Investor.SHARES[1], "the next stake asks for a bigger share")
	Day.open_shop()
	expect(not Investor.has_offer() and Investor.next_offer_day == Shop.day + Investor.WAIT_DECLINED, "opening without shaking on it turns her down")
	Day.close_shop()
	Day.end_day()
	Investor.next_offer_day = 0
	Investor.deals = Investor.MAX_DEALS
	Shop.next_day()
	Day.begin_day()
	expect(not Investor.has_offer(), "she offers %d stakes a game at most" % Investor.MAX_DEALS)
	SaveGame.new_game()
	expect(Investor.deals == 0 and Investor.repaid == 0 and not Investor.has_deal(), "a new game resets the investor")
	Shop.reset()


func _check_rush_hours() -> void:
	expect(RushHours.at(1, 12 * 60).name == "Lunch rush", "lunch is busy on a Monday")
	expect(RushHours.at(1, 10 * 60).is_empty(), "mid-morning is calm on a Monday")
	expect(RushHours.at(6, 10 * 60).name == "Saturday crowd", "Saturday morning is busy")
	expect(RushHours.at(7, 16 * 60).is_empty(), "Sunday afternoon is quiet")
	expect(RushHours.summary(1).contains("lunch 11:45"), "the morning briefing lists the rushes")
	expect(RushHours.grab_chance(RushHours.till_limit() * 0.5, true) == 0.0, "a light till is safe")
	expect(RushHours.grab_chance(RushHours.till_limit() * 2.0, true) > RushHours.grab_chance(RushHours.till_limit() * 2.0, false), "a rush makes snatches likelier")
	var limit := RushHours.till_limit()
	expect(RushHours.grab_chance(limit * 1.1, false) < RushHours.grab_chance(limit * 2.0, false), "a till just over the limit is safer than an overflowing one")
	expect(RushHours.grab_amount(limit * 6.0) <= limit * RushHours.GRAB_CAP + 0.01, "one snatch takes at most half a till")


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
	shop._tick(Staff.CLERK_SECONDS + 0.1)
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
		# the insurer pays back a quarter of what was left on the tray
		v.apply(kids)
		expect(absf(kids.insured - kids.value * VaultLayout.INSURED.tray * (1.0 - Security.recover_share())) < 1.0, "insurance pays back part of a tray burglary")
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
	# a flat session (under half a dollar either way) books nothing
	expect(absf(desk.session.pnl()) < 0.5 and booked.is_empty() \
		or booked.size() == 1 and absf(absf(booked[0].usd) - absf(desk.session.pnl())) < 0.01, "the result goes on today's ledger")
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
	expect(is_equal_approx(Shop.cash, before - cash[0].cash + report.insured), "stolen cash leaves the till (the insurer pays for coins, not cash)")
	expect(is_equal_approx(report.insured, tube.value * VaultLayout.INSURED.tray * (1.0 - Security.recover_share())), "insurance pays back part of the tube")
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
	TranslationServer.set_locale("en")


## The language setting, and every translation: complete, drawable in the pixel font, and with
## the same %d / %s / {name} slots as the English, so formatting never breaks.
func _check_localization() -> void:
	var real_path := Settings.path
	Settings.path = "user://smoke_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.load_settings()
	expect(Settings.language == "auto" and TranslationServer.get_locale().begins_with(Settings.device_language()), "the language follows the device until one is picked")
	Settings.set_language("de")
	expect(tr("Settings") == "Einstellungen" and Loc.t("Settings") == "Einstellungen", "German shows German")
	expect(Loc.n("%d more day", "%d more days", 1) == "noch %d Tag" and Loc.n("%d more day", "%d more days", 3) == "noch %d Tage", "German plurals")
	expect(Market.format_money(1234567.0, 0).contains("1.234.567"), "German groups thousands with dots")
	expect(Day.weekday_key(1) == "Monday" and Day.weekday(1) == "Montag", "weekday logic stays in English under German names")
	Settings.language = "en"
	Settings.load_settings()
	expect(Settings.language == "de" and TranslationServer.get_locale().begins_with("de"), "the language comes back from disk")
	Settings.set_language("fr")
	expect(Loc.n("%d more day", "%d more days", 0) == "encore %d jour", "French counts zero as singular")
	Settings.set_language("es")
	expect(tr("Settings") != "Settings", "Spanish shows Spanish")
	Settings.set_language("bogus")
	expect(Settings.language == "es", "unknown languages are ignored")
	Settings.set_language("en")
	expect(tr("Settings") == "Settings", "English is the source text")

	var slots := RegEx.create_from_string("%[-+0-9.]*[a-zA-Z%]|\\{[a-z_]+\\}")
	var english := {}
	for path in ProjectSettings.get_setting("internationalization/locale/translations"):
		var t: Translation = load(path)
		var bad_chars := {}
		var bad_slots := []
		for id in t.get_message_list():
			english[id] = true
			var text := String(t.get_message(id))
			if text == "":
				continue # not translated yet: the game shows the English
			var want := []
			for m in slots.search_all(id):
				want.append(m.get_string())
			var got := []
			for m in slots.search_all(text):
				got.append(m.get_string())
			if want.filter(func(x): return x.begins_with("%")) != got.filter(func(x): return x.begins_with("%")):
				bad_slots.append(id)
			want.sort()
			got.sort()
			if want != got:
				bad_slots.append(id)
			for ch in slots.sub(text, "", true):
				if ch != " " and ch != "\n" and not PixelFont.GLYPHS.has(ch) and not PixelFont.ACCENTED.has(ch):
					bad_chars[ch] = true
		expect(bad_slots.is_empty(), "%s keeps the format slots in order: %s" % [t.locale, bad_slots])
		expect(bad_chars.is_empty(), "the pixel font draws every %s letter: %s" % [t.locale, bad_chars.keys()])
	expect(english.size() > 1000, "the translations cover the game (%d strings)" % english.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = real_path
	Settings.load_settings()
	TranslationServer.set_locale("en")



## Longer translations must not push the morning pages wider than their area, or buttons
## run off screen (the bug bots caught the dealer's Buy buttons doing that in German).
func _check_translated_panels() -> void:
	Tutorial.skip_all()
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var panels: Control = shop.hud._panels
	for item in Shop.rare_list().slice(0, Orders.MAX_OPEN.max()):
		Orders.open.append({"id": Orders.open.size(), "name": "Professor Okonkwo-Hargreaves", "qty": 3, "item": item.id,
			"due": Shop.day + 2, "premium": 0.5})
		Orders.dealer[item.id] = 2
	Investor.offer = {"day": Shop.day, "stake": 13000.0, "share": 0.15}
	Investor.offer_seen = true
	Investor.total_paid = 1234.0
	for lang in ["en", "de", "es", "fr"]:
		TranslationServer.set_locale(lang)
		for page in ["show_morning", "show_upgrades", "show_plan", "show_wholesale", "show_town", "show_orders", "show_ledger", "show_investor"]:
			panels.call(page)
			await get_tree().process_frame
			expect(panels.size.x <= panels.AREA.size.x, "%s %s fits the panel width (%d px)" % [lang, page, panels.size.x])
			if page == "show_investor":
				expect(panels.size.y <= panels.AREA.size.y, "%s %s fits the panel height (%d px)" % [lang, page, panels.size.y])
	# and with her stake in the shop
	Investor.offer = {}
	Investor.deal = {"stake": 13000.0, "share": 0.15, "cap": 22750.0, "paid": 1234.0, "day": Shop.day}
	for lang in ["en", "de", "es", "fr"]:
		TranslationServer.set_locale(lang)
		for page in ["show_morning", "show_ledger", "show_investor"]:
			panels.call(page)
			await get_tree().process_frame
			expect(panels.size.x <= panels.AREA.size.x and (page != "show_investor" or panels.size.y <= panels.AREA.size.y),
				"%s %s with a stake fits the panel (%d x %d px)" % [lang, page, panels.size.x, panels.size.y])
	TranslationServer.set_locale("en")
	Investor.reset()
	Orders.reset()
	shop.queue_free()
	await get_tree().process_frame
	Shop.reset()


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


## Gamepad controls: the pointer, d-pad jumps that skip what is hidden behind menus,
## A clicks, B goes back, the bench and desk shortcuts, and the screen scaling choice.
func _check_pad() -> void:
	expect(InputMap.action_get_events("ui_up").all(func(e): return not (e is InputEventJoypadButton or e is InputEventJoypadMotion)),
		"the pad does not also move the keyboard focus")
	_clear_slots()
	SaveGame.set_slot(1)
	var title: Control = load("res://scenes/menu/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	var new_game: Button = title._new
	Pad.set_cursor(new_game.get_global_rect().get_center())
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	expect(Pad.using_pad, "pressing a pad button switches to the pad")
	var on: Variant = _pad_target_under_cursor()
	expect(on is Button and on.text == "Settings", "d-pad down jumps from New game to Settings")
	var names: Array = Pad.targets().map(func(t): return t.node.text if t.node is Button else "")
	expect(not names.has("Continue"), "the d-pad skips a disabled button")
	await _pad_press(JOY_BUTTON_A)
	expect(title._settings != null, "A clicks the button under the pointer")
	var panel: SettingsPanel = title._settings
	await get_tree().process_frame
	var all_in_panel := Pad.targets().all(func(t): return panel.is_ancestor_of(t.node))
	expect(all_in_panel, "with Settings open the d-pad only stops on its controls")
	var sliders := Pad.targets().filter(func(t): return t.node is HSlider)
	expect(sliders.size() == 3, "the d-pad reaches the three volume sliders")
	var real_path := Settings.path
	Settings.path = "user://smoke_test_settings.cfg"
	var master: float = Settings.volume["Master"]
	Pad.set_cursor(sliders[0].rect.get_center())
	await _pad_press(JOY_BUTTON_DPAD_LEFT)
	expect(Settings.volume["Master"] < master, "d-pad left on a slider turns it down")
	Settings.set_volume("Master", master)
	await _pad_press(JOY_BUTTON_B)
	expect(title._settings == null and title._menu.visible, "B backs out of Settings")
	title.queue_free()
	await get_tree().process_frame

	# screen scaling: the Steam Deck's 1280x800 fills, 16:9 screens keep whole pixels
	expect(Settings.scaling == "auto", "scaling starts on auto")
	expect(not Settings.whole_pixels(Vector2(1280, 800)) and not Settings.whole_pixels(Vector2(1366, 768)), "auto fills a Steam Deck or a laptop screen")
	expect(Settings.whole_pixels(Vector2(1920, 1080)) and Settings.whole_pixels(Vector2(1440, 810)) and Settings.whole_pixels(Vector2(2560, 1440)), "auto keeps whole pixels where they nearly fill")
	Settings.set_scaling("pixel")
	expect(Settings.whole_pixels(Vector2(1280, 800)), "Pixel perfect always keeps whole pixels")
	Settings.set_scaling("fill")
	Settings.scaling = "auto"
	Settings.load_settings()
	expect(Settings.scaling == "fill" and not Settings.whole_pixels(Vector2(1920, 1080)), "the scaling choice is saved")
	expect(get_tree().root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "Fill screen scales by fractions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = real_path
	Settings.load_settings()

	# the pause menu hides the shop's buttons from the d-pad
	SaveGame.new_game()
	Tutorial.skip_all()
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop._open_shop()
	await get_tree().process_frame
	expect(Pad.targets().size() > 0, "the shop has buttons for the d-pad")
	await _pad_press(JOY_BUTTON_START)
	expect(shop._pause.is_open(), "Start opens the pause menu")
	var paused_targets := Pad.targets()
	expect(paused_targets.size() >= 3 and paused_targets.all(func(t): return shop._pause.is_ancestor_of(t.node)),
		"while paused the d-pad only stops on the pause menu")
	await _pad_press(JOY_BUTTON_B)
	expect(not shop._pause.is_open() and not get_tree().paused, "B closes the pause menu")

	# bench shortcuts: LB / RB step through the tools; the pointer counts as the mouse
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var c := Customer.create(3, 4.0, Shop.coin_list(), rng)
	c.kind = "seller"
	c.piece = null
	c.bar = null
	c.item = Shop.coins["gold_eagle"]
	c.fake = ""
	var bench: Control = load("res://scenes/coin_test/coin_test.tscn").instantiate()
	shop.hud.add_child(bench)
	bench.start(c)
	await get_tree().process_frame
	expect(Pad.action("rb") and bench.used.has("scale"), "RB picks the first tool on the coin bench")
	Pad.action("rb")
	expect(bench.used.has("calipers"), "RB again picks the next tool")
	Pad.action("lb")
	Pad.action("lb")
	expect(bench._loupe.visible, "LB goes back round to the loupe")
	Pad.action("lb")
	expect(not bench._loupe.visible, "leaving the loupe puts it away")
	Pad.set_cursor(Vector2(100, 80))
	expect(Pad.mouse_in(bench).is_equal_approx(Vector2(100, 80)), "the benches read the pad's pointer as the mouse")
	await _pad_press(JOY_BUTTON_START)
	expect(not shop._pause.is_open() and is_instance_valid(bench) and bench.is_inside_tree(), "Start does nothing on a bench")
	bench.queue_free()
	await get_tree().process_frame

	# the trading desk: rows on the bumpers, buy and sell on the triggers, rows on the d-pad
	var desk: TradingDesk = load("res://scenes/trading_desk/trading_desk.tscn").instantiate()
	shop.hud.add_child(desk)
	desk.start(7)
	await get_tree().process_frame
	Pad.action("rb")
	expect(desk.selected == 1, "RB selects the next row")
	Pad.action("lb")
	Pad.action("lb")
	expect(desk.selected == desk.session.board.size() - 1, "LB wraps round to the last row")
	Pad.action("rt")
	expect(desk.session.position(desk.selected) > 0.0, "RT buys the selected row")
	expect(Pad.targets().filter(func(t): return t.node == desk).size() == desk.session.board.size(), "the d-pad stops on each row of the board")
	expect(desk.pad_help().size() == 3 and Pad.help_rows().size() > 9, "the controls list shows the desk's shortcuts")
	desk.queue_free()
	shop.queue_free()
	await get_tree().process_frame

	# a real mouse takes over again
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(5, 5)
	Input.parse_input_event(click)
	await get_tree().process_frame
	expect(not Pad.using_pad, "using the mouse switches back from the pad")
	SaveGame.delete_save()
	Shop.reset()


func _pad_press(button: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func _pad_target_under_cursor() -> Variant:
	for t in Pad.targets():
		if t.rect.has_point(Pad.cursor):
			return t.node
	return null


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


## Plays a melt the way a careful player would: every steel bit out, the furnace held in
## the middle of the pour band till it's all molten, borax until the scum is gone, then a
## steady pour below the splash line. `heat` shifts the furnace's target from mid-band.
func _careful_melt(m: Melt, heat := 0.0, flow_tilt := 0.66) -> void:
	while m.pull_steel():
		pass
	m.load_crucible()
	var b := m.band()
	m.set_gas(((b.x + b.y) / 2.0 + heat - Melt.AMBIENT) / (Melt.MAX_TEMP - Melt.AMBIENT))
	for n in 600:
		if m.molten >= 1.0 and (heat > 0.0 or m.in_band()):
			break
		m.advance(0.05, false)
	# an impatient player leaves the gas up while they reach for the borax
	for n in (120 if heat > 0.0 else 0):
		m.advance(0.05, false)
	while m.dross > 0.001:
		m.add_flux()
	for n in 1200:
		if m.done:
			break
		m.advance(0.05, m.tilt < flow_tilt)


func _check_smelter() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	expect(absf(Melt.melting_point_of("XAG", 0.999) - 961.0) < 1.0 and Melt.melting_point_of("XAU", 0.585) < Melt.melting_point_of("XAU", 0.916),
		"fine silver melts at 961 C, and 22K gold melts hotter than 14K")
	# the dealer's lots
	for metal in ["XAU", "XAG"]:
		for n in 20:
			var lot := ScrapYard.roll_lot(metal, rng)
			var share: float = lot.cost / ScrapYard.claimed_value(lot)
			expect(share >= ScrapYard.PRICE_SHARE.x - 0.001 and share <= ScrapYard.PRICE_SHARE.y + 0.001, "a %s lot costs %d%% of its stamped metal" % [metal, roundi(share * 100.0)])
			expect(float(lot.purity) <= float(lot.claimed) * ScrapYard.TRUTH.y + 0.0001, "a lot is never better than its stamp says by much")
	# a careful melt of an honest lot makes money and a clean bar
	var lot := ScrapYard.roll_lot("XAU", rng)
	lot.purity = lot.claimed
	lot.steel = 3
	var good := Melt.of([lot] as Array[Dictionary], 3)
	_careful_melt(good)
	var r := good.result()
	expect(good.done and good.steel_pulled == 3 and r.flaws.is_empty(), "a careful melt pours a clean bar")
	expect(r.recovery > 0.98 and r.skull.is_empty(), "a careful melt recovers over 98%% of the gold (%.1f%%)" % (r.recovery * 100.0))
	expect(r.payout > r.cost, "a careful melt of an honest lot makes a profit")
	expect(absf(r.fine - good.fine * 0.997) / good.fine < 0.02, "the assay finds the gold that went in")
	# sloppy work costs metal
	var hot := Melt.of([lot] as Array[Dictionary], 3)
	_careful_melt(hot, 220.0)
	expect(hot.fumed > 0.0 and hot.result().recovery < r.recovery, "an overheated melt fumes metal away")
	var fast := Melt.of([lot] as Array[Dictionary], 3)
	_careful_melt(fast, 0.0, 1.0)
	expect(fast.splashed > 0.0 and fast.result().recovery < r.recovery, "pouring flat out splashes")
	var steel := Melt.of([lot] as Array[Dictionary], 3)
	steel.load_crucible()
	expect(steel.dross >= 3 * Melt.STEEL_DROSS, "steel left in the scrap adds dross")
	var cold := Melt.of([lot] as Array[Dictionary], 3)
	cold.load_crucible()
	cold.set_gas((cold.melting_point + 40.0 - Melt.AMBIENT) / (Melt.MAX_TEMP - Melt.AMBIENT))
	for n in 400:
		cold.advance(0.05, false)
		if cold.molten >= 1.0:
			break
	for n in 400:
		if cold.done:
			break
		cold.advance(0.05, cold.tilt < 0.45)
	var cr := cold.result()
	expect(cold.frozen and not cr.skull.is_empty() and cr.skull.grams > 0.0, "a pour started too cold freezes in the crucible")
	expect(absf(cr.cost + float(cr.skull.cost) - cold.cost) < 0.01, "the frozen metal goes back to the bin with its share of the cost")
	var shut := Melt.of([lot] as Array[Dictionary], 3)
	_careful_melt(shut, 0.0, 0.0)
	shut.molten = 1.0
	shut.temp = shut.melting_point + 120.0
	for n in 12:
		shut.advance(0.05, true)
	for n in 20:
		shut.advance(0.05, false)
	for n in 300:
		if shut.done:
			break
		shut.advance(0.05, shut.tilt < 0.66)
	expect("cold_shut" in shut.result().flaws, "a long pause mid-pour leaves a cold shut")
	# the furnace, the morning's lots and the bin
	ScrapYard.hook_up()
	expect(not ScrapYard.available() and ScrapYard.offers.is_empty(), "no smelter or lots before the furnace")
	Shop.cash = 200000.0
	expect(not Progress.can_buy("furnace"), "the furnace waits for Main Street")
	Progress.tier = 1
	expect(Progress.buy("furnace"), "buy the melting furnace")
	expect(ScrapYard.offers.size() >= 2 and ScrapYard.offer_day == Shop.day, "the scrap dealer brings lots once the furnace is in")
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	expect(ScrapYard.available(), "the smelter opens in the morning")
	var opened := []
	shop.smelter_opened.connect(func(sm): opened.append(sm))
	shop.open_smelter()
	expect(opened.size() == 1 and shop._smelter != null, "the morning panel opens the smelter")
	var sm: Smelter = shop._smelter
	var worth := Shop.net_worth()
	var offered := ScrapYard.offers.size()
	var first: Dictionary = ScrapYard.offers[0]
	sm.buy(0)
	expect(ScrapYard.bin.size() == 1 and ScrapYard.offers.size() == offered - 1, "a bought lot goes in the scrap bin")
	expect(absf(Shop.net_worth() - worth) < 0.01, "scrap in the bin counts in net worth at cost")
	expect(SaveGame.save_game(), "save with scrap in the bin")
	ScrapYard.from_dict({})
	expect(SaveGame.load_game() and ScrapYard.bin.size() == 1 and ScrapYard.bin[0].name == first.name, "the scrap bin is saved")
	sm.begin(first.metal)
	expect(sm.phase == "sort" and ScrapYard.bin.is_empty() and not sm.pieces.is_empty(), "melting takes the bin's lots onto the tray")
	expect(sm.pieces.filter(func(p): return p.steel).size() == int(first.steel), "the tray shows the steel hidden in the lot")
	sm.back()
	expect(sm.phase == "yard" and ScrapYard.bin.size() == 1, "Esc puts the scrap back in the bin")
	sm.begin(first.metal)
	sm.load_crucible()
	expect(sm.phase == "melt", "load the crucible")
	_careful_melt(sm.melt)
	sm._process(0.05)
	expect(sm.phase == "result" and not sm.assay.is_empty(), "the pour ends in the assay")
	var booked := Day.ledger.filter(func(e): return e.label == "Bullion dealer (cast bars)")
	expect(booked.size() == 1 and absf(booked[0].usd - sm.assay.payout) < 0.01, "the bullion dealer pays for the bar on today's ledger")
	expect(ScrapYard.bars_cast == 1 and Shop.stats.get("bars_cast", 0.0) == 1.0, "the bar is counted")
	sm._show_yard()
	sm.finished.emit()
	expect(shop._smelter == null and shop.hud._panels.page == "morning", "the smelter closes back to the morning")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()
	expect(ScrapYard.bin.is_empty() and ScrapYard.bars_cast == 0, "a new game empties the scrap bin")



func _check_auction() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	AuctionHouse.hook_up()
	Shop.day = 1
	expect(not AuctionHouse.is_sale_day(1) and AuctionHouse.is_sale_day(3) and AuctionHouse.is_sale_day(6) and not AuctionHouse.is_sale_day(7),
		"sales on Wednesdays and Saturdays from day 3")
	expect(AuctionHouse.next_sale_day(4) == 6 and AuctionHouse.next_sale_day(7) == 10, "the next sale day")
	# the catalogue
	Shop.day = 6
	AuctionHouse.catalogue_day = 0
	AuctionHouse.refresh_catalogue()
	expect(AuctionHouse.lots.size() == AuctionHouse.LOT_COUNT[0] and AuctionHouse.views_left == AuctionHouse.VIEWINGS[0], "a sale morning brings the catalogue")
	var first: Dictionary = AuctionHouse.lots[0].duplicate(true)
	AuctionHouse.catalogue_day = 0
	AuctionHouse.refresh_catalogue()
	expect(AuctionHouse.lots[0].items == first.items, "replaying a morning brings the same lots")
	for lot in AuctionHouse.lots:
		var est := AuctionHouse.estimate(lot)
		expect(est.x > 0.0 and est.y > est.x and AuctionHouse.title_of(lot) != "", "lot %d has a title and an estimate" % lot.n)
		for it in lot.items:
			expect(AuctionHouse.coin_of(it) != null and int(it.qty) > 0, "lot %d's coins are real" % lot.n)
			if it.pouch:
				expect(float(it.guess) > 0.0, "a pouch has a catalogue guess")
	expect(AuctionHouse.increment(150.0) == 10.0 and AuctionHouse.increment(4000.0) == 200.0 and AuctionHouse.nice(4130.0) == 4200.0, "bid steps")
	# looking inside a pouch
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var estate := AuctionHouse.roll_estate(rng)
	estate.n = 1
	estate.seed = 1
	estate.result = {}
	var p := -1
	for i in estate.items.size():
		if estate.items[i].pouch:
			p = i
	var before := AuctionHouse.known_melt(estate)
	AuctionHouse.views_left = 1
	expect(AuctionHouse.view(estate, p) and estate.items[p].seen and AuctionHouse.views_left == 0, "open a pouch at the viewing")
	expect(is_equal_approx(AuctionHouse.known_melt(estate), before + AuctionHouse.melt_of(estate.items[p])), "what's in an opened pouch counts as seen")
	expect(not AuctionHouse.view(estate, 0), "no more looks once they're used")
	# a lot under the hammer: the room bids it up and the gavel comes down
	var seats := AuctionHouse.attendees()
	expect(seats.size() >= 4 and seats.any(func(s): return s.who == "sterling"), "Sterling is in the room")
	var sold := 0
	var passed := 0
	for n in 40:
		rng.seed = n + 1
		var lot := AuctionHouse.roll_bulk(rng)
		lot.n = 1
		lot.seed = n
		lot.result = {}
		var sale := AuctionSale.of(lot, seats, n + 1)
		var steps := 0
		var last := 0.0
		var rising := true
		while not sale.advance(0.05) and steps < 4000:
			steps += 1
			if sale.high < last:
				rising = false
			last = sale.high
		expect(sale.done and rising, "the bidding only goes up and ends")
		if sale.winner() != "":
			sold += 1
			var w := int(sale.leader)
			expect(sale.high <= float(sale.bidders[w].limit), "nobody bids past their limit")
		else:
			passed += 1
	expect(sold > 30, "most dealer lots sell (%d of 40)" % sold)
	# you bid, a jump bid, and winning
	Shop.cash = 1000000.0
	rng.seed = 77
	var lot := AuctionHouse.roll_bulk(rng)
	lot.n = 1
	lot.seed = 3
	lot.result = {}
	var sale := AuctionSale.of(lot, seats, 9)
	var ask := sale.ask
	expect(sale.bid_you() and sale.leader == "you" and sale.high == ask and not sale.can_bid(), "your paddle takes the ask")
	var jump := sale.jump_amount()
	expect(jump > AuctionSale.next_ask(sale.ask), "a jump bid skips steps")
	sale.leader = ""
	expect(sale.bid_you(true) and sale.high == jump, "jump bid")
	for b in sale.bidders:
		b.in = false # the room gives up
	var cash := Shop.cash
	var held := Shop.count_of_item(AuctionHouse.coin_of(lot.items[0]))
	while not sale.advance(0.1):
		pass
	expect(sale.winner() == "you" and sale.calls == 3, "going once, going twice, sold to you")
	sale.settle()
	expect(is_equal_approx(cash - Shop.cash, AuctionHouse.price_with_premium(jump)), "you pay the hammer and the buyer's premium")
	expect(Shop.count_of_item(AuctionHouse.coin_of(lot.items[0])) == held + int(lot.items[0].qty), "the coins go in the vault")
	expect(Day.ledger.any(func(e): return e.label == "Auction house"), "the auction is on today's ledger")
	expect(AuctionHouse.won == 1 and Shop.stats.get("auction_won", 0.0) == 1.0, "the win is counted")
	# a sleeper in a won pouch
	var rare := Shop.rare_list()[0]
	var sleeper := {"n": 2, "kind": "estate", "who": "Test", "seed": 1, "result": {}, "items": [AuctionHouse._group(rare, 1)]}
	sleeper.items[0].pouch = true
	AuctionHouse.settle(sleeper, "you", "", 500.0)
	expect(AuctionHouse.sleepers == 1 and Records.value_of("sleepers") >= 1.0 and Records.is_earned("sleeper"), "a rare coin in a pouch is a sleeper")
	# your lot: consigned, not sold under its reserve, and sold
	Shop.day = 10
	AuctionHouse.catalogue_day = 0
	AuctionHouse.held_day = 0
	AuctionHouse.refresh_catalogue()
	var count := AuctionHouse.lots.size()
	expect(rare in AuctionHouse.consignable() and AuctionHouse.consign(rare), "consign a rare coin")
	expect(AuctionHouse.lots.size() == count + 1 and AuctionHouse.lots[-1].kind == "mine" and Shop.count_of_item(rare) == 0, "your coin leaves the vault for the sale")
	var mine: Dictionary = AuctionHouse.lots[-1]
	var mine_sale := AuctionSale.of(mine, seats, 4)
	expect(not mine_sale.bid_you(), "you can't bid on your own lot")
	AuctionHouse.settle(mine, "", "", 0.0)
	expect(Shop.count_of_item(rare) == 1, "an unsold lot comes back to the vault")
	expect(AuctionHouse.consign(rare), "consign it again")
	cash = Shop.cash
	AuctionHouse.settle(AuctionHouse.lots[-1], "collector", "Dr. Ng", 6000.0)
	expect(is_equal_approx(Shop.cash - cash, 6000.0 * (1.0 - AuctionHouse.SELLERS_FEE)), "your lot's price less the fee")
	expect(AuctionHouse.consign(Shop.rare_list()[1]) == false, "only coins you hold can be consigned")
	# a rival's buy adds to their worth
	var worth := Rivals.worth_of("sterling")
	AuctionHouse.settle(AuctionHouse.lots[0], "sterling", "Victor Sterling", 1000.0, 5000.0)
	expect(Rivals.worth_of("sterling") > worth, "Sterling's bargains make his shop worth more")
	# saved with the game
	expect(SaveGame.save_game(), "save with a catalogue")
	var saved := AuctionHouse.lots.size()
	var won := AuctionHouse.won
	AuctionHouse.from_dict({})
	expect(SaveGame.load_game() and AuctionHouse.lots.size() == saved and AuctionHouse.won == won and won == 2 and AuctionHouse.sleepers == 1, "the auction is saved")
	# the saleroom from the town map
	SaveGame.new_game()
	Tutorial.skip_all()
	Shop.day = 13
	Shop.cash = 500000.0
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	expect(AuctionHouse.available(), "the auction is on this Saturday morning")
	var opened := []
	shop.auction_opened.connect(func(a): opened.append(a))
	shop.open_auction()
	expect(opened.size() == 1 and shop._auction != null, "the town map opens the saleroom")
	var room: AuctionRoom = shop._auction
	expect(room.phase == "viewing" and room.seats.size() >= 4 and not AuctionHouse.lots.is_empty(),
		"the viewing shows the lots")
	room.take_seat()
	expect(room.phase == "sale" and AuctionHouse.held_day == Shop.day and not AuctionHouse.available(), "taking a seat starts the sale")
	room._process(AuctionRoom.INTRO + 0.1)
	room.bid()
	expect(room.sale.leader == "you" or room.sale.done, "Space bids")
	var guard := 0
	while room.phase == "sale" and guard < 20000:
		room._process(0.05)
		guard += 1
	expect(room.phase == "done", "the sale runs to the end")
	expect(AuctionHouse.lots.all(func(l): return not l.result.is_empty()), "every lot has a result")
	room.finished.emit()
	expect(shop._auction == null and shop.hud._panels.page == "morning", "the saleroom closes back to the morning")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()
	expect(AuctionHouse.lots.is_empty() and AuctionHouse.won == 0, "a new game clears the auction")

func _check_grading() -> void:
	SaveGame.new_game()
	Tutorial.skip_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var morgan: BullionItem = Shop.coins["morgan_dollar_1881"]
	# wear planes the design flat and takes the lustre with it
	var lustrous := {}
	for g in [0, 4, 8]:
		var cg := CoinGrade.create(rng, morgan, g)
		cg.cleaned = false
		var art: Dictionary = GradeArt.bake(cg, 1)
		expect(art.relief.get_width() == GradeArt.SIZE and art.surface.get_width() == GradeArt.SIZE, "the grading coin bakes at bench size")
		var n := 0
		for y in range(0, GradeArt.SIZE, 2):
			for x in range(0, GradeArt.SIZE, 2):
				if art.surface.get_pixel(x, y).r > 0.1:
					n += 1
		lustrous[g] = n
	expect(lustrous[0] == 0 and lustrous[4] < lustrous[8], "worn coins have less lustre than mint-state ones")
	var loupe: Dictionary = GradeArt.bake(CoinGrade.create(rng, morgan, 8), GradeArt.LOUPE_SCALE)
	expect(loupe.relief.get_width() == GradeArt.SIZE * GradeArt.LOUPE_SCALE, "the loupe's coin bakes at 3x")
	var cleaned := CoinGrade.create(rng, morgan, 6)
	cleaned.cleaned = true
	var hair: Image = GradeArt.bake(cleaned, GradeArt.LOUPE_SCALE).surface
	var lines := 0
	for y in range(0, hair.get_height(), 3):
		for x in range(0, hair.get_width(), 3):
			if hair.get_pixel(x, y).g > 0.5:
				lines += 1
	expect(lines > 20, "a cleaned coin shows hairlines under the loupe")
	# the collector's verdict
	var cg := CoinGrade.create(rng, morgan, 6)
	cg.cleaned = false
	var exact := cg.judge(6, false, "Dr. Ng")
	expect(exact.steps == 0 and is_equal_approx(exact.pay, CoinGrade.fee() * (1.0 + CoinGrade.TIP)) and exact.rep > 0.0, "the exact grade earns the fee and a tip")
	var near := cg.judge(5, false, "Dr. Ng")
	expect(is_equal_approx(near.pay, CoinGrade.fee()), "a grade one off earns the fee")
	var far := cg.judge(2, false, "Dr. Ng")
	expect(far.pay == 0.0 and far.rep < 0.0, "a grade far off earns nothing and costs stars")
	cg.cleaned = true
	expect(cg.judge(6, false, "Dr. Ng").pay == 0.0, "missing a cleaned coin earns nothing")
	expect(cg.judge(6, true, "Dr. Ng").pay > 0.0, "calling it cleaned, at the right grade, earns the fee")
	# collectors only come once the lamp is bought
	CoinGrade.hook_up()
	var none := 0
	for n in 200:
		if CoinGrade.next_customer(rng) != null:
			none += 1
	expect(none == 0, "no grading customers before the grading lamp")
	Shop.cash = 100000.0
	Shop.day = 5
	expect(Progress.buy("grading_lamp"), "buy the grading lamp")
	var came := 0
	for n in 400:
		if CoinGrade.next_customer(rng) != null:
			came += 1
	expect(came > 10 and came < 70, "collectors bring coins to grade now and then (%d of 400)" % came)
	# at the counter and on the bench
	var shop: Node = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop.hud.open_requested.emit()
	var c := CoinGrade.customer(rng, 7)
	c.grading.cleaned = false
	shop.queue.append(c)
	c.pos = ShopArt.SLOTS[0]
	shop._process(0.01)
	expect(shop._front() == c, "the collector waits at the counter")
	shop._on_action("test")
	expect(shop._test is GradingBench, "Grade it opens the grading bench")
	var bench: GradingBench = shop._test
	var m: Array = c.grading.marks[0]
	expect(bench.tag_at(GradingBench.COIN_AT + (m[0] + m[1]) / 2.0) and bench.tagged.size() == 1, "clicking a bag mark under the loupe tags it")
	expect(not bench.tag_at(GradingBench.COIN_AT + Vector2(200, 0)), "clicking bare velvet tags nothing")
	bench.move_lamp(GradingBench.COIN_AT + Vector2(140, 0))
	var low := bench.light_dir()
	bench.move_lamp(GradingBench.COIN_AT + Vector2(10, 0))
	expect(low.z < 0.3 and bench.light_dir().z > 0.9, "the lamp rakes low far out and shines from above close in")
	var stars := Shop.reputation
	bench.set_grade(7)
	bench.finish()
	expect(shop._test == null and not shop.queue.has(c), "grading sends the collector on their way")
	var fees := Day.ledger.filter(func(e): return e.label == "Grading fees")
	expect(fees.size() == 1 and fees[0].usd > CoinGrade.fee(), "the exact grade's fee and tip go on today's ledger")
	expect(Shop.reputation > stars and Shop.stats.get("graded_exact", 0.0) == 1.0, "a spot-on grade earns stars and counts")
	shop.queue_free()
	await get_tree().process_frame
	SaveGame.new_game()
