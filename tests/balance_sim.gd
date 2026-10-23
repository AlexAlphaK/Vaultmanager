extends Node
## Balance check: bot players of three skill levels run the real shop scene for many
## days, and the numbers show how fast each one grows. The bots stand in for the
## player's hands: they pick up the counter card, test (or don't), haggle with the
## -/+ buttons, grade jewellery, pack the vault and buy upgrades in the morning.
## Everything else (customers, bills, reputation, fakes, the assay lab, the refiner,
## break-ins) is the game's own code. Run:
##   godot --headless --path . res://tests/balance_sim.tscn -- --runs=8 --days=120
## Options: --runs=N seeds per bot, --days=N days per run, --bots=novice,average,expert,
## --seed=N first seed, --csv=PATH writes one row per bot per day.

const STEP := 0.25 # shop-clock seconds per tick

## How each bot plays. Detection odds are per test it runs; `slow` is shop-clock seconds
## the bot takes per button at the counter (customers lose patience meanwhile),
## `pack` is seconds per piece in the vault, and `bench` is seconds per coin test (half
## again for jewellery and bars), which only costs shop time in a rush. `till_run` is how
## full the till gets, as a share of its limit, before the bot takes it to the vault, and
## `hire` lists [role, from tier] for the staff the bot takes on, and `restock` scales how
## many coins of each metal the bot keeps on the shelf with the morning wholesaler.
## Every bot takes collectors' special orders; `dealer_days` is how close to the due day
## the bot gives up waiting for a walk-in seller and buys a rare coin from the dealer
## network (-1: never). The average and expert bots book a booth at the coin show.
const BOTS := {
	"novice": {
		"test": 0.75, "fake_easy": 0.8, "fake_hard": 0.45, "false_alarm": 0.1,
		"grade": 0.5, "plated": 0.7, "stone": 0.5, "bar_easy": 0.8, "bar_hard": 0.4, "bar_core": 0.2,
		"buy": 0.9, "max_buy": 0.97, "premium": 0.06, "min_premium": 0.03, "holds": 0,
		"slow": 6.0, "pack": 4.0, "pack_order": "random", "buffer": 1.0, "shady_refuse": 0.0,
		"bench": 25.0, "till_run": 2.0, "hire": [], "restock": 0.5, "dealer_days": -1,
	},
	"average": {
		"test": 0.85, "fake_easy": 0.95, "fake_hard": 0.75, "false_alarm": 0.04,
		"grade": 0.75, "plated": 0.88, "stone": 0.75, "bar_easy": 0.95, "bar_hard": 0.7, "bar_core": 0.5,
		"buy": 0.9, "max_buy": 0.95, "premium": 0.07, "min_premium": 0.04, "holds": 1,
		"slow": 4.0, "pack": 2.5, "pack_order": "value", "buffer": 1.5, "shady_refuse": 0.3,
		"bench": 15.0, "till_run": 0.9, "hire": [["clerk", 1]], "restock": 1.0, "dealer_days": 1,
	},
	"expert": {
		"test": 1.0, "fake_easy": 0.99, "fake_hard": 0.95, "false_alarm": 0.01,
		"grade": 0.95, "plated": 0.98, "stone": 0.95, "bar_easy": 0.99, "bar_hard": 0.92, "bar_core": 0.85,
		"buy": 0.88, "max_buy": 0.93, "premium": 0.08, "min_premium": 0.05, "holds": 2,
		"slow": 2.5, "pack": 1.5, "pack_order": "value", "buffer": 2.0, "shady_refuse": 0.0,
		"bench": 9.0, "till_run": 0.7, "hire": [["clerk", 0], ["guard", 1]], "restock": 1.0, "dealer_days": 1,
	},
}
## The XRF analyzer reads the surface: plated and low-fineness bars stop fooling the bot.
const XRF_BONUS := 0.5
## Digital gauges flag out-of-spec readings (most use to the hard fakes); the sigma
## verifier reads through plating and finds tungsten, so few coin fakes get past it.
const GAUGE_BONUS := 0.3
const SIGMA_BONUS := 0.7
const HARD_COIN_FAKES := ["clad", "tungsten"]
const EASY_BAR_FAKES := ["brass", "copper"]
const CORE_BAR_FAKES := ["lead_core", "tungsten_core"]
## Expert's upgrade order; the others buy the cheapest they can afford.
## Coins of each metal a bot keeps on the shelf (times its `restock` and the deal size),
## and cash it keeps back for sellers on top of the rent reserve.
const SHELF := {"XAU": 8, "XAG": 40, "XPT": 3}
const RESTOCK_RESERVE := 5000.0
const EXPERT_ORDER := ["alarm", "cctv", "window_sign", "digital_gauges", "queue_ropes", "bench", "xrf_gun", "fraud_cover",
	"case_lights", "long_counter", "sigma_verifier", "big_safe", "testing_lab", "radio_ads", "bar_dealer", "time_lock",
	"lounge", "marble_counter", "workshop", "billboard", "trading_desk"]

var shop: Node
var bot := {}
var rng := RandomNumberGenerator.new()
var _busy := 0.0
## A test in progress during a rush: {"c", "verdict", "left"}.
var _bench := {}
var _csv: FileAccess


func _ready() -> void:
	var args := _args()
	var runs := int(args.get("runs", 8))
	var days := int(args.get("days", 120))
	var first_seed := int(args.get("seed", 1))
	var names: PackedStringArray = String(args.get("bots", "novice,average,expert")).split(",")
	# each process gets its own save, so several sims (other bots or seeds) can run side by side
	SaveGame.path = "user://balance_sim_%s_%d.json" % [String(args.get("bots", "all")).replace(",", "_"), first_seed]
	SaveGame.delete_save()
	_quiet_market()
	if args.has("csv"):
		_csv = FileAccess.open(args.csv, FileAccess.WRITE)
		_csv.store_line("bot,seed,day,tier,cash,net_worth,reputation,bought,sold,profit,caught,scammed,stolen,bills,served")
	shop = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	shop.set_process(false)
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var all := {}
	for name in names:
		all[name] = []
		for r in runs:
			all[name].append(await run(name, first_seed + r, days))
	print("\nBalance check: %d runs x %d days per bot (%.1f s)\n" % [runs, days, (Time.get_ticks_msec() - t0) / 1000.0])
	for name in names:
		_print_summary(name, all[name], days)
	SaveGame.delete_save()
	if _csv:
		_csv.close()
	get_tree().quit()


## One playthrough. Returns the day each tier was reached and the totals.
func run(bot_name: String, seed: int, days: int) -> Dictionary:
	bot = BOTS[bot_name]
	rng.seed = seed * 7919
	seed(seed)
	Market.prices = Market.SEED_PRICES.duplicate()
	Market.start_new_day()
	shop._new_game()
	shop.coach.skip()
	shop.rng.seed = seed
	var out := {"tier_day": [1, -1, -1, -1], "worth": [], "rep": [], "break_ins": 0, "stolen": 0.0, "fakes_bought": 0,
		"caught": 0, "served": 0, "bills": 0.0, "overdrawn_days": 0, "upgrades": {}, "profit": 0.0,
		"premium_income": 0.0, "lowest_cash": Shop.cash, "losses": {}, "gains": {}, "short_cash": 0, "out_of_stock": 0, "walked_by": 0,
		"holdups": 0, "robbers_stopped": 0, "restocked": 0.0, "lost_to_rivals": 0, "tip_offs": 0, "rank": [],
		"orders_taken": 0, "orders_filled": 0, "orders_failed": 0, "dealer": 0.0, "chapter_day": [-1, -1, -1, -1, -1],
		"town_served": {}, "booths": 0}
	for d in days:
		_morning(out)
		_play_day(out)
		var report := _lock_up(out)
		_tally(out, report, bot_name, seed)
		if Progress.goal_reached() and d > 0 and out.tier_day[3] > 0 and Shop.day >= out.tier_day[3] + 7:
			break
		_walk_prices()
		shop._open_next_day()
		# let the engine flush its deferred calls, or the message queue overflows on long runs
		await get_tree().process_frame
	return out


## Spot moves between game days. A player fits a few game days into a real one, so
## each game day gets about half a real day's volatility.
func _walk_prices() -> void:
	for metal in Market.METALS:
		Market.prices[metal] = float(Market.prices[metal]) * (1.0 + randfn(0.0, Market.DAILY_VOL[metal] * 0.5))


func _morning(out: Dictionary) -> void:
	# move up first, then spend what's left on upgrades
	if Progress.expand_blocker() == "":
		var next := Progress.tier_info(Progress.tier + 1)
		if Shop.cash - next.cost >= next.rent * bot.buffer:
			Progress.expand()
			out.tier_day[Progress.tier] = Shop.day
	var order: Array = EXPERT_ORDER if bot == BOTS.expert else Progress.available_upgrades()
	for id in order:
		# the sim doesn't play the smelter, so its furnace would be dead money
		if id == "furnace" or not Progress.upgrades.has(id) or not Progress.can_buy(id):
			continue
		var reserve: float = Progress.weekly_rent() * bot.buffer + 8000.0 * bot.buffer
		# saving up for the move matters more than the next gadget
		if not Progress.is_top_tier() and Shop.net_worth() >= Progress.tier_info(Progress.tier + 1).need_worth * 0.8:
			reserve += Progress.tier_info(Progress.tier + 1).cost
		if Shop.cash - Progress.upgrades[id].cost >= reserve:
			Progress.buy(id)
			out.upgrades[id] = Shop.day
	for h in bot.hire:
		if Progress.tier >= h[1] and Staff.can_hire(h[0]) and Shop.cash - Staff.ROLES[h[0]].fee >= Progress.weekly_rent() * bot.buffer + 8000.0:
			Staff.hire(h[0])
			out.upgrades[h[0]] = Shop.day
	# the average and expert bots keep their staff happy; the novice never answers
	if bot != BOTS.novice:
		for id in Staff.raise_requests():
			Staff.agree_raise(id)
	_source_orders(out)
	_restock(out)
	# the average and expert bots read the town map and tip off the police
	if bot != BOTS.novice and Rivals.tip_off():
		out.tip_offs += 1
	if bot != BOTS.novice and Calendar.can_book_booth() and Shop.cash - Calendar.booth_cost() >= Progress.weekly_rent() * bot.buffer + 5000.0:
		Calendar.book_booth()
		out.booths += 1
	shop._open_shop()


## Finds the coins open special orders still need: everyday coins from the wholesaler,
## rare ones from the dealer network once the due day is close.
func _source_orders(out: Dictionary) -> void:
	var reserve: float = Progress.weekly_rent() * bot.buffer
	for o in Orders.open:
		var item := Orders.item_of(o)
		var missing := int(o.qty) - Orders.have_for(o)
		if missing <= 0:
			continue
		if not item.rare:
			missing = mini(missing, int((Shop.cash - reserve) / Wholesaler.price(item)))
			if missing > 0:
				out.restocked += Wholesaler.price(item) * Wholesaler.buy(item, missing)
		elif Orders.days_left(o) <= bot.dealer_days:
			for n in missing:
				var each := Orders.dealer_price(item)
				if Shop.cash - each < reserve or not Orders.dealer_buy(item):
					break
				out.dealer += each


## Tops each metal up to the bot's shelf level from the wholesaler, most plentiful coin first.
func _restock(out: Dictionary) -> void:
	var reserve: float = Progress.weekly_rent() * bot.buffer + RESTOCK_RESERVE * Progress.deal_size()
	for metal in SHELF:
		var target := roundi(SHELF[metal] * bot.restock * Progress.deal_size())
		var items := Wholesaler.coin_list().filter(func(it): return it.metal == metal)
		while Shop.count_of(metal) < target and not items.is_empty():
			items.sort_custom(func(a, b): return Wholesaler.left(a) > Wholesaler.left(b))
			var item: BullionItem = items[0]
			var qty := mini(Wholesaler.bulk(item), target - Shop.count_of(metal))
			if Wholesaler.left(item) <= 0 or Shop.cash - Wholesaler.price(item) * qty < reserve:
				break
			var n := Wholesaler.buy(item, qty)
			if n <= 0:
				break
			out.restocked += Wholesaler.price(item) * n


func _play_day(out: Dictionary) -> void:
	_busy = 0.0
	_bench = {}
	var guard := 0
	while guard < 20000 and shop._vault == null:
		guard += 1
		# the shop opens the vault itself once the last customer is gone
		shop._tick(STEP)
		shop._walk(STEP)
		_busy -= STEP
		if not _bench.is_empty():
			_bench.left -= STEP
			if _bench.left <= 0.0:
				_finish_test(_bench.c, _bench.verdict, out)
				_bench = {}
			continue
		if _busy > 0.0 or shop.away > 0.0:
			continue
		if shop.till > RushHours.till_limit() * bot.till_run:
			shop._on_action("vault_run")
			continue
		var c: Customer = shop._front()
		if c != null:
			_serve(c, out)
	out.walked_by += int(Shop.stats.get("walked_by", 0.0))
	out.holdups += int(Shop.stats.get("holdups", 0.0))
	out.robbers_stopped += int(Shop.stats.get("robbers_stopped", 0.0))
	out.lost_to_rivals += int(Shop.stats.get("lost_to_rival", 0.0))
	# the bot plays the vault itself, so the shop's own vault scene goes
	if shop._vault:
		shop._vault.get_parent().remove_child(shop._vault)
		shop._vault.free()
		shop._vault = null


## One button press (or a whole test) for the customer at the counter.
func _serve(c: Customer, out: Dictionary) -> void:
	_busy = bot.slow
	Shop.set_buy_percent(bot.buy)
	Shop.set_sell_premium(bot.premium)
	if c.kind == "visit":
		shop._on_action("decline")
		return
	if c.kind == "order":
		out.orders_taken += 1
		shop._on_action("sell")
		return
	if c.kind == "robber":
		_face_robber()
		return
	if c.kind == "grade":
		_grade(c)
		return
	if c.kind == "buyer":
		_sell_to(c, out)
		return
	if not c.tested:
		if c.archetype == "shady" and rng.randf() < bot.shady_refuse:
			shop._on_action("refuse")
			return
		# the counter card tags nervous sellers, and the tutorial's Slick teaches to test them
		if rng.randf() < (maxf(bot.test, 0.95) if c.archetype == "shady" else bot.test):
			_test(c, out)
			return
	_buy_from(c, out)


## A coin to grade: right as often as the bot reads jewellery grades, else a step or two off.
func _grade(c: Customer) -> void:
	var g := c.grading
	var call := g.grade
	if rng.randf() >= bot.grade:
		call = clampi(g.grade + (1 if rng.randf() < 0.5 else -1) * (2 if rng.randf() < 1.0 - bot.grade else 1), 0, CoinGrade.GRADES.size() - 1)
	var cleaned := g.cleaned if rng.randf() < bot.grade else not g.cleaned
	c.assessed = {"grade": call, "cleaned": cleaned}
	_finish_test(c, "graded", {})


## A hold-up. The novice guesses; the others weigh the till against what a failed
## panic button costs (the till plus the best coins in the case).
func _face_robber() -> void:
	var panic := rng.randf() < 0.5
	if bot != BOTS.novice:
		var p := Security.panic_odds()
		panic = (1.0 - p) * (shop.till + Security.grab_value(Security.case_grab())) < shop.till
	shop._on_action("sell" if panic else "decline")


## Runs the bench for the customer's coins, piece or bar, and calls it.
func _test(c: Customer, out: Dictionary) -> void:
	var fake := false
	if c.piece:
		var p := c.piece
		var plated := p.true_grade == "plated"
		if plated and rng.randf() < bot.plated:
			_finish_test(c, "fake", out)
			return
		var grade := p.true_grade if rng.randf() < bot.grade else p.claimed_grade
		if plated:
			grade = p.claimed_grade
		var diamond := p.stone == "diamond" if rng.randf() < bot.stone else p.stone != ""
		var weight := p.weight_g if rng.randf() < bot.grade else p.claimed_g
		c.assessed = {"grade": grade, "diamond": diamond and p.stone != "", "weight": weight}
	elif c.bar:
		var f := c.bar.fake
		if f != "":
			var odds: float = bot.bar_easy if f in EASY_BAR_FAKES else (bot.bar_core if f in CORE_BAR_FAKES else bot.bar_hard)
			if Progress.has_upgrade("xrf_gun") and not f in CORE_BAR_FAKES:
				odds += (1.0 - odds) * XRF_BONUS
			if c.bar.cloned:
				odds += (1.0 - odds) * 0.5 # the panel flags a serial you have bought
			fake = rng.randf() < odds
		else:
			fake = rng.randf() < bot.false_alarm
	else:
		if c.fake != "":
			var odds: float = bot.fake_hard if c.fake in HARD_COIN_FAKES else bot.fake_easy
			if Progress.has_upgrade("digital_gauges"):
				odds += (1.0 - odds) * (GAUGE_BONUS if c.fake in HARD_COIN_FAKES else GAUGE_BONUS * 0.5)
			if Progress.has_upgrade("sigma_verifier"):
				odds += (1.0 - odds) * SIGMA_BONUS
			fake = rng.randf() < odds
		else:
			fake = rng.randf() < bot.false_alarm
	var verdict := "fake" if fake else "genuine"
	if shop.rush.is_empty():
		_finish_test(c, verdict, out)
		return
	# in a rush the shop clock runs on while the bot is at the bench
	shop._testing = c
	shop._test = Control.new()
	_bench = {"c": c, "verdict": verdict, "left": bot.bench * (1.5 if c.piece or c.bar else 1.0)}


func _finish_test(c: Customer, verdict: String, out: Dictionary) -> void:
	if shop._test == null:
		shop._test = Control.new()
	shop._on_test_finished(verdict, c)
	if verdict == "fake":
		out.caught += 1


## Offers the bot's buy rate, holds firm a few times, then meets the seller or walks.
func _buy_from(c: Customer, out: Dictionary) -> void:
	var value := c.melt_total()
	if value <= 0.0:
		shop._on_action("refuse")
		return
	var share: float = bot.buy
	if c.tries > bot.holds:
		share = ceilf(c.reserve * c.expected_total() / value * 100.0) / 100.0
		if share > bot.max_buy:
			shop._on_action("refuse")
			return
	Shop.set_buy_percent(share)
	var offer := c.offer_total()
	if offer > Shop.cash:
		out.short_cash += 1
		shop._on_action("refuse")
		return
	shop._on_action("offer")
	if not c.dealt:
		return
	if c.fake != "" or (c.bar and c.bar.fake != "") or (c.piece and c.piece.true_grade == "plated"):
		out.fakes_bought += 1
	# what the deal adds to net worth once the lab, refiner or dealer has had a look
	var worth := 0.0
	var what := "coins"
	if c.piece:
		worth = c.piece.refiner_payout()
		what = "jewellery"
	elif c.bar:
		worth = c.bar.dealer_payout(Progress.effect("bar_payout"))
		what = "bars"
	elif c.fake == "":
		worth = c.melt_total()
	var gain := worth - offer
	if c.fake != "" or (c.bar and c.bar.fake != "") or (c.piece and (c.piece.true_grade == "plated" or gain < 0.0)):
		_add(out.losses, what, -gain)
	else:
		_add(out.gains, what, gain)


func _sell_to(c: Customer, out: Dictionary) -> void:
	if c.stock_have() < c.qty:
		out.out_of_stock += 1
		shop._on_action("decline")
		return
	var premium: float = bot.premium
	if c.tries > bot.holds:
		premium = floorf(c.max_premium * 100.0 + 0.01) / 100.0
		if premium < bot.min_premium:
			shop._on_action("decline")
			return
	Shop.set_sell_premium(premium)
	shop._on_action("sell")
	if c.dealt:
		out.served += 1
		_add(out.gains, "selling", c.melt_total() * premium)


## The vault minigame: the bot drags pieces into the safes, most valuable first,
## taking `pack` seconds each, and locks up when nothing else fits.
func _lock_up(out: Dictionary) -> Dictionary:
	var vrng := RandomNumberGenerator.new()
	vrng.seed = rng.randi()
	var layout := VaultLayout.from_shop(vrng)
	var limit: float = clampf(14.0 + 2.5 * layout.pieces.size(), 20.0, 60.0)
	var order := layout.pieces.duplicate()
	if bot.pack_order == "value":
		order.sort_custom(func(a, b): return (a.value if a.kind != "ledger" else 1e12) > (b.value if b.kind != "ledger" else 1e12))
	else:
		order.shuffle()
	var elapsed := 0.0
	for p in order:
		if elapsed + bot.pack > limit:
			break
		if _stow(layout, p):
			elapsed += bot.pack
	var chance: float = layout.risk(elapsed / limit)
	var night := layout.resolve(chance, vrng)
	night.risk = chance
	layout.apply(night)
	if night.break_in:
		out.break_ins += 1
		out.stolen += night.value
		_add(out.losses, "break-ins", night.value)
	shop._vault = Control.new()
	# _on_vault_finished shows the summary; read the report back from Day's signal
	var holder := {}
	var grab := func(_d, r): holder.report = r
	Day.day_ended.connect(grab)
	shop._on_vault_finished(night)
	Day.day_ended.disconnect(grab)
	return holder.get("report", {})


func _stow(layout: VaultLayout, p: Dictionary) -> bool:
	for area in [VaultLayout.FLOOR, VaultLayout.WALL]:
		var size: Vector2i = layout.areas[area].size
		for rot in 4:
			for y in size.y:
				for x in size.x:
					if layout.place(p, area, Vector2i(x, y), rot):
						return true
	return false


func _tally(out: Dictionary, report: Dictionary, bot_name: String, seed: int) -> void:
	out.worth.append(Shop.net_worth())
	out.rep.append(Shop.reputation)
	out.rank.append(Rivals.rank())
	for ch in Story.chapters_done():
		if out.chapter_day[ch] < 0:
			out.chapter_day[ch] = Shop.day
	out.lowest_cash = minf(out.lowest_cash, Shop.cash)
	if Shop.cash < 0.0:
		out.overdrawn_days += 1
	var bills := 0.0
	for e in report.get("ledger", []):
		if e.label in ["Upkeep", "Rent", "Insurance", "Overdraft interest"] or String(e.label).begins_with("Wages"):
			bills -= e.usd
		elif e.label == "Snatched from the till":
			_add(out.losses, "till snatches", -e.usd)
		elif e.label in ["Handed over in a hold-up", "Taken in a hold-up"]:
			_add(out.losses, "hold-ups", -e.usd)
		elif e.label == "Police recovered stolen goods":
			_add(out.gains, "police recovered", e.usd)
		elif e.label == "Insurance payout":
			_add(out.gains, "insurance", e.usd)
		elif e.label == "Tax Day":
			_add(out.losses, "tax", -e.usd)
		elif e.label == "Coin show booth":
			_add(out.losses, "coin show booths", -e.usd)
		elif e.label == "Gift from Mags":
			_add(out.gains, "story rewards", e.usd)
	var town := Calendar.event_on(Shop.day)
	if not town.is_empty() and Calendar.last_day(town) == Shop.day:
		_add(out.town_served, town.id, Calendar.served.get(town.id, 0))
	out.bills += bills
	_add(out.losses, "bills", bills)
	for e in report.get("ledger", []):
		if Progress.upgrades.values().any(func(u): return u.name == e.label) or String(e.label).begins_with("Moving") \
				or String(e.label).begins_with("Hired"):
			_add(out.losses, "upgrades and moves", -e.usd)
	var st: Dictionary = report.get("stats", {})
	out.profit += float(st.get("profit", 0.0))
	out.orders_filled += int(st.get("orders_filled", 0.0))
	out.orders_failed += int(st.get("orders_failed", 0.0))
	if _csv:
		_csv.store_line("%s,%d,%d,%d,%.0f,%.0f,%.2f,%.0f,%.0f,%.0f,%d,%d,%.0f,%.0f,%d" % [bot_name, seed, Shop.day, Progress.tier,
			Shop.cash, Shop.net_worth(), Shop.reputation, st.get("bought", 0.0), st.get("sold", 0.0), st.get("profit", 0.0),
			st.get("caught", 0.0), st.get("scammed", 0.0), st.get("stolen", 0.0), bills, st.get("served", 0.0)])


func _print_summary(name: String, results: Array, days: int) -> void:
	print("== %s ==" % name)
	for t in range(1, Progress.TIERS.size()):
		var reached := results.filter(func(r): return r.tier_day[t] > 0).map(func(r): return r.tier_day[t])
		reached.sort()
		var txt := "never" if reached.is_empty() else "median day %d (range %d-%d), %d/%d runs" % [
			reached[reached.size() / 2], reached[0], reached[-1], reached.size(), results.size()]
		print("  %-17s %s" % [Progress.TIERS[t].name, txt])
	for check in [7, 14, 30, 60, days]:
		var worth := results.map(func(r): return r.worth[mini(check, r.worth.size()) - 1])
		worth.sort()
		var rep := results.map(func(r): return r.rep[mini(check, r.rep.size()) - 1])
		rep.sort()
		print("  day %-4d net worth median %9s  reputation %.2f" % [check, Market.format_money(worth[worth.size() / 2]), rep[rep.size() / 2]])
	var n := float(results.size())
	print("  per run: %.1f fakes bought, %.1f caught, %.1f break-ins (%s stolen), %.1f overdrawn days, lowest cash %s" % [
		_sum(results, "fakes_bought") / n, _sum(results, "caught") / n, _sum(results, "break_ins") / n,
		Market.format_money(_sum(results, "stolen") / n), _sum(results, "overdrawn_days") / n,
		Market.format_money(results.map(func(r): return r.lowest_cash).min())])
	for side in ["gains", "losses"]:
		var totals := {}
		for r in results:
			for k in r[side]:
				totals[k] = totals.get(k, 0.0) + r[side][k] / n
		var bits: Array[String] = []
		for k in totals:
			bits.append("%s %s" % [k, Market.format_money(totals[k])])
		print("  %s per run: %s" % [side, ", ".join(bits)])
	print("  per run: %.1f sellers turned away for lack of cash, %.1f buyers we had no stock for, %.1f walked by in rushes" % [
		_sum(results, "short_cash") / n, _sum(results, "out_of_stock") / n, _sum(results, "walked_by") / n])
	print("  per run: %.1f hold-ups at the counter, %.1f robbers stopped (guard or panic button)" % [
		_sum(results, "holdups") / n, _sum(results, "robbers_stopped") / n])
	print("  per run: %s bought from the wholesaler" % Market.format_money(_sum(results, "restocked") / n))
	print("  per run: %.1f special orders taken, %.1f filled, %.1f fell through, %s spent at the dealer network" % [
		_sum(results, "orders_taken") / n, _sum(results, "orders_filled") / n, _sum(results, "orders_failed") / n,
		Market.format_money(_sum(results, "dealer") / n)])
	var town := {}
	for r in results:
		for id in r.town_served:
			town[id] = town.get(id, 0.0) + r.town_served[id] / n
	var town_bits: Array[String] = []
	for id in town:
		town_bits.append("%s %.0f" % [id, town[id]])
	print("  per run: town event customers served: %s; %.1f coin show booths" % [", ".join(town_bits) if not town_bits.is_empty() else "none",
		_sum(results, "booths") / n])
	var passed := []
	for t in [7, 14, 30, 60, days]:
		var ranks := results.map(func(r): return r.rank[mini(t, r.rank.size()) - 1])
		ranks.sort()
		passed.append("day %d #%d" % [t, ranks[ranks.size() / 2]])
	print("  per run: %.1f customers went to a rival, %.1f tip-offs; median place in town: %s" % [
		_sum(results, "lost_to_rivals") / n, _sum(results, "tip_offs") / n, ", ".join(passed)])
	var chapters: Array[String] = []
	for ch in Story.CHAPTERS.size():
		var done := results.filter(func(r): return r.chapter_day[ch] > 0).map(func(r): return r.chapter_day[ch])
		done.sort()
		chapters.append("%d %s" % [ch + 1, "-" if done.is_empty() else "d%d (%d/%d)" % [done[done.size() / 2], done.size(), results.size()]])
	print("  story chapters done (median day, runs): %s" % ", ".join(chapters))
	var ups := {}
	for r in results:
		for id in r.upgrades:
			ups[id] = ups.get(id, []) + [r.upgrades[id]]
	var parts: Array[String] = []
	for id in ups:
		var d: Array = ups[id]
		d.sort()
		parts.append("%s d%d" % [id, d[d.size() / 2]])
	print("  upgrades (median day bought): %s\n" % ", ".join(parts))


func _add(d: Dictionary, key: String, usd: float) -> void:
	d[key] = d.get(key, 0.0) + usd


func _sum(results: Array, key: String) -> float:
	var total := 0.0
	for r in results:
		total += float(r[key])
	return total


## Fixed prices: no network, no random walk between ticks.
func _quiet_market() -> void:
	Market.service_url = "http://127.0.0.1:9/"
	for child in Market.get_children():
		if child is Timer:
			child.stop()
		elif child is HTTPRequest:
			child.cancel_request()
	Market.source = "simulated"


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
