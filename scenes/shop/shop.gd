extends Node2D
## The shop floor: runs the day clock, brings customers in, and settles deals at
## live market prices. Coin testing opens the CoinTest minigame over the shop,
## jewellery opens the JewelleryTest appraisal and bullion bars open the BarTest.
## Each day runs morning (prices, upgrades) -> open -> closing -> vault lock-up ->
## after hours (summary), following the Day autoload. The game saves every morning.
## In the rush hours (RushHours) the clock keeps running while you test, so you juggle
## the counter, the benches and runs to the vault with the till; staff (Staff) help out.
## Now and then a robber walks in with the customers (Security): the guard may stop
## them at the door, otherwise you hand over the till or hit the panic button.
## Rival shops (Rivals) compete for every customer: when your prices or stars look worse
## than theirs, some cross the street before they reach your door.
## On day 1 of a new game the Coach walks the player through it.
## Once the trading desk room is built, the morning panel opens the TradingDesk minigame,
## and once the melting furnace is bought, the Smelter (scrap lots melted into bars).
## Seasons and town events (Calendar) change who comes in: tax season sellers, gold
## fever buyers, coin show collectors and holiday gift shoppers.

signal bench_opened(bench: Control, c: Customer)
signal bench_closed(verdict: String, c: Customer)
signal customer_left(c: Customer)
signal vault_opened(vault: Control)
signal summary_shown
signal desk_opened(desk: Control)
signal smelter_opened(smelter: Control)
signal auction_opened(auction: Control)

const DAY_SECONDS := 120.0 # 09:00 to 17:00; daily bills are sized for this length (see README, Balance)
const WALK_SPEED := 1.8 # tiles per second
const CoinTestScene := preload("res://scenes/coin_test/coin_test.tscn")
const VaultScene := preload("res://scenes/vault/vault.tscn")
const NewsBanner := preload("res://scenes/shop/news_banner.gd")
const RUSH_GAP := 1.5 # seconds between customers in a news rush
const JewelleryTestScene := preload("res://scenes/jewellery_test/jewellery_test.tscn")
const BarTestScene := preload("res://scenes/bar_test/bar_test.tscn")
const GradingScene := preload("res://scenes/grading/grading_bench.tscn")
const TradingDeskScene := preload("res://scenes/trading_desk/trading_desk.tscn")
const SmelterScene := preload("res://scenes/smelter/smelter.tscn")
const AuctionScene := preload("res://scenes/auction/auction_room.tscn")
const DemoEndScene := "res://scenes/menu/demo_end.tscn"
const STONE_NAMES := {"cz": "cubic zirconia", "glass": "glass", "moissanite": "moissanite"}
const VAULT_RUN_SECONDS := 3.0 # away from the counter while you take the till to the vault

@onready var room: Node2D = $Room
@onready var hud: Control = $Hud/Root

var time := 0.0
var closing := false
## True while the shop clock is stopped: before opening, after hours and during a minigame.
var paused := true
var queue: Array[Customer] = []
var leaving: Array[Customer] = []
var pending_fakes: Array[Dictionary] = []
## Jewellery bought today, on its way to the refiner: {"at", "piece", "paid", "name"}.
var pending_pieces: Array[Dictionary] = []
## Bars bought today, on their way to the bullion dealer: {"at", "bar", "paid", "name"}.
var pending_bars: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
## Today's busy hour from RushHours, or {} when the shop is calm.
var rush := {}
## Cash taken at the counter since the last vault run, and seconds left on a run under way.
var till := 0.0
var away := 0.0
## The buyer at the clerk's till, and seconds left on their sale.
var at_clerk: Customer
var clerk_left := 0.0
## The robber in the shop, if any, and whether they have pulled their gun yet.
var robber: Customer
var robber_revealed := false

var _testing: Customer
var _next_spawn := 3.0
var _rush_left := 0
var _shown: Customer
var _test: Control
var _vault: Control
var _desk: Control
var _smelter: Control
var _auction: Control
var _pause: PauseMenu
var coach: Coach
## Particles, reactions and their sounds over the room.
var fx: ShopFx


func _ready() -> void:
	rng.randomize()
	BullionBar.hook_up()
	Security.hook_up()
	DeskSession.hook_up()
	ScrapYard.hook_up()
	CoinGrade.hook_up()
	hud.room = room
	# under the HUD's panels, so the morning briefing and the benches cover it
	var cat := ShopCat.new(room)
	hud.add_child(cat)
	hud.move_child(cat, 0)
	AuctionHouse.hook_up()
	hud.action.connect(_on_action)
	hud.open_requested.connect(_open_shop)
	hud.next_day_requested.connect(_open_next_day)
	hud.new_game_requested.connect(_new_game)
	hud.menu_requested.connect(open_pause_menu)
	hud.desk_requested.connect(open_desk)
	hud.smelter_requested.connect(open_smelter)
	hud.auction_requested.connect(open_auction)
	_pause = PauseMenu.new()
	add_child(_pause)
	Music.play("shop")
	var banner := NewsBanner.new()
	hud.add_child(banner)
	add_child(RushStrip.new(self))
	fx = ShopFx.new(self)
	room.add_child(fx)
	MarketEvents.started.connect(_on_market_event)
	if SaveGame.load_game():
		if SaveGame.day_over: # saved at the end of the day: carry on with the next morning
			Shop.next_day()
		Shop.log_event(tr("Welcome back. Day %d at your %s.") % [Shop.day, Progress.tier_name()])
	else:
		Shop.log_event(tr("Welcome to your shop. Test coins before you buy them."))
	if Demo.enabled and not Demo.is_over():
		Shop.log_event(tr_n("Demo: %d day left to play.", "Demo: %d days left to play.", Demo.days_left()) % Demo.days_left())
	coach = Coach.new()
	add_child(coach)
	coach.attach(self)
	_start_morning()


func _process(delta: float) -> void:
	if not paused:
		_tick(delta)
	_walk(delta)
	var front := _front()
	if front != _shown:
		_shown = front
		_show_front()
	room.front_customer = front
	room.customers.assign(_everyone())
	room.day_fraction = clampf(time / DAY_SECONDS, 0.0, 1.0)
	room.keeper_away = away > 0.0
	room.clerk_busy = at_clerk != null and not at_clerk.walking
	hud.set_clock(Shop.day, int(minutes()), closing, not rush.is_empty())
	hud.set_till(till, RushHours.till_limit(), away)


## The shop clock in minutes after midnight: 09:00 at opening, 17:00 at closing time.
func minutes() -> float:
	return 9.0 * 60.0 + clampf(time / DAY_SECONDS, 0.0, 1.0) * 8.0 * 60.0


## Everyone in the shop: the queue, the clerk's customer and those on their way out.
func _everyone() -> Array[Customer]:
	var out: Array[Customer] = []
	out.append_array(queue)
	out.append_array(leaving)
	if at_clerk:
		out.append(at_clerk)
	return out


## Esc opens the pause menu, except in the coin and jewellery benches, where it means "back".
func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _test == null and _desk == null and _smelter == null and _auction == null \
			and not hud.is_decorating():
		open_pause_menu()
		get_viewport().set_input_as_handled()


func open_pause_menu() -> void:
	_pause.open()


func _tick(delta: float) -> void:
	# the clock waits while the tutorial walks through its first customers
	if not coach.holds_clock():
		time += delta
	if not closing and time >= DAY_SECONDS:
		closing = true
		Day.close_shop()
		Shop.log_event(tr("Closing time. Serving the last customers."))
	_update_rush()
	MarketEvents.advance(delta)
	_next_spawn -= delta
	if not closing and _next_spawn <= 0.0 and not coach.holds_clock():
		if queue.size() < Progress.queue_slots():
			_spawn()
			if _rush_left > 0:
				_rush_left -= 1
				_next_spawn = RUSH_GAP
			elif not rush.is_empty():
				_next_spawn = RushHours.SPAWN_GAP / Progress.traffic() * rng.randf_range(0.75, 1.25)
			else:
				_next_spawn = maxf(5.0, 15.0 - Shop.reputation * 2.0) / Progress.traffic() / Rivals.traffic_factor() * rng.randf_range(0.7, 1.3) * MarketEvents.spawn_factor() * Calendar.spawn_factor()
		elif not rush.is_empty():
			# in a rush nobody waits outside: a full queue turns them away
			Shop.note("walked_by")
			_next_spawn = RushHours.SPAWN_GAP / Progress.traffic() * rng.randf_range(0.75, 1.25)
	if away > 0.0:
		away -= delta
		if away <= 0.0:
			_finish_vault_run()
	_clerk_tick(delta)
	if not closing and rng.randf() < RushHours.grab_chance(till, not rush.is_empty()) * delta:
		_till_grab()
	if not closing and robber == null and Tutorial.first_day_done and rng.randf() < Security.holdup_chance(till) * delta:
		_robber_walks_in()
	_robber_tick(delta)
	# with a testing lab the queue frets less while you are at the bench
	var calm := 1.0 - (clampf(Progress.effect("calm_queue"), 0.0, 1.0) if _test != null else 0.0)
	for c in queue.duplicate():
		# whoever is on the testing bench is watching you work
		if c.walking or c == _testing or c == robber:
			continue
		c.patience -= (delta if c == _front() else delta * 0.5) * calm
		if c.patience <= 0.0:
			Shop.reputation_for("walked_out")
			_dismiss(c, tr("%s got tired of waiting and left.") % c.name, "bad")
	for f in pending_fakes.duplicate():
		if time >= f.at or closing:
			pending_fakes.erase(f)
			Shop.confiscate(f.item, f.fake)
			Shop.note("scammed")
			Shop.reputation_for("scammed")
			Shop.log_event(tr("Assay lab: the %d × %s were %s. Lost %s.") % [f.qty, f.item.display_name, Counterfeit.label(f.fake), Market.format_money(f.paid)], "bad")
			var cover := Progress.effect("fraud_refund")
			if cover > 0.0:
				Day.add_income(tr("Fraud insurance payout"), f.paid * minf(cover, 1.0))
	for j in pending_pieces.duplicate():
		if time >= j.at or closing:
			pending_pieces.erase(j)
			_settle_piece(j)
	for j in pending_bars.duplicate():
		if time >= j.at or closing:
			pending_bars.erase(j)
			_settle_bar(j)
	if closing and queue.is_empty() and leaving.is_empty() and at_clerk == null and away <= 0.0 and _test == null:
		paused = true
		_open_vault()


## Starts and ends the busy hours as the clock passes them.
func _update_rush() -> void:
	# no rush while the tutorial is still guiding the first day
	var now := {} if closing or not Tutorial.first_day_done else RushHours.at(Shop.day, minutes())
	if now.get("name", "") == rush.get("name", ""):
		return
	rush = now
	if rush.is_empty():
		Shop.log_event(tr("The rush is over. Catch your breath."))
		return
	_next_spawn = minf(_next_spawn, 1.0)
	Sfx.play(self, Sfx.door_bell(), -4.0)
	var help := "" if Staff.on_duty("clerk") else tr(" A clerk would help.")
	Shop.log_event(tr("%s! The queue keeps waiting while you test.%s") % [tr(rush.name), help], "bad")


func _spawn() -> void:
	# breaking news first, then whatever is on in town today (Calendar)
	var event := MarketEvents.customer_event(rng)
	if event.is_empty():
		event = Calendar.customer_event(rng)
	var c := Customers.next_customer(rng, event)
	var rival := Rivals.diverts(c, rng)
	if rival != "":
		Rivals.lose(c, rival)
		return
	admit(c)


## Sends customer `c` through the door and into the queue.
func admit(c: Customer) -> void:
	queue.append(c)
	Sfx.play(self, Sfx.door_bell(), -8.0)
	Shop.log_event(Customers.arrival(c))


func _walk(delta: float) -> void:
	for c in _everyone():
		var target: Vector2 = ShopArt.EXIT if c.leaving else ShopArt.SLOTS[mini(queue.find(c), ShopArt.SLOTS.size() - 1)]
		if c == at_clerk:
			target = ShopArt.CLERK_SLOT
		var to := target - c.pos
		var step := WALK_SPEED * delta
		c.walking = to.length() > 0.02
		c.pos = target if to.length() <= step else c.pos + to.normalized() * step
	for c in leaving.duplicate():
		if not c.walking:
			leaving.erase(c)


func _front() -> Customer:
	if queue.is_empty():
		return null
	var c := queue[0]
	return c if not c.walking and c.pos.distance_to(ShopArt.SLOTS[0]) < 0.05 else null


func _show_front() -> void:
	if away > 0.0:
		hud.show_customer(null, "Back in a moment: taking the till to the vault.")
	elif _shown:
		hud.show_customer(_shown)
	elif not queue.is_empty():
		hud.show_customer(null, "A customer is walking up to the counter.")
	elif closing:
		hud.show_customer(null, "Closing up for the day.")
	else:
		hud.show_customer(null, "Quiet for now. Customers arrive every few seconds.")


func _dismiss(c: Customer, text := "", mood := "") -> void:
	queue.erase(c)
	c.leaving = true
	leaving.append(c)
	Customers.on_leave(c)
	if text != "":
		Shop.log_event(text, mood)
	if c == _shown:
		_shown = null
		_show_front()
	customer_left.emit(c)


func _on_action(id: String) -> void:
	if paused or _test != null or away > 0.0:
		return
	if id == "vault_run":
		_start_vault_run()
		return
	var c := _front()
	if c == null:
		return
	if c.kind == "visit" and id != "decline":
		return
	if c.kind == "order":
		_order_answer(c, id)
		return
	if c.kind == "grade":
		if id == "test":
			_open_test(c)
		elif id == "decline":
			_dismiss(c, tr("%s will find another grader.") % c.name)
		return
	if c == robber:
		if id == "decline":
			_hand_over()
		elif id == "sell":
			_panic_button()
		return
	match id:
		"test":
			_open_test(c)
		"offer":
			_offer(c)
		"refuse":
			# nobody holds it against you when you can't pay what you offered
			if c.offer_total() > Shop.cash:
				_dismiss(c, tr("Couldn't afford %s's %s today.") % [c.name, tr("bar") if c.bar else (tr("piece") if c.piece else tr("coins"))])
			elif c.tested:
				Shop.reputation_for("passed_tested")
				_dismiss(c, tr("Passed on %s's %s.") % [c.name, tr("bar") if c.bar else tr("coins")])
			else:
				Shop.reputation_for("refused_fake" if c.fake != "" or (c.piece and c.piece.scam) or (c.bar and c.bar.fake != "") else "refused_genuine")
				_dismiss(c, tr("Turned %s away without testing.") % c.name)
		"sell":
			_sell(c)
		"decline":
			_dismiss(c, tr("%s said goodbye.") % c.name if c.kind == "visit" else tr("%s left without buying.") % c.name)


## A collector asked for a special order: "sell" takes it, "decline" turns it down.
func _order_answer(c: Customer, id: String) -> void:
	if id == "sell":
		Orders.accept(c)
		Sfx.play(self, Sfx.click(), -6.0)
		_dismiss(c)
	elif id == "decline":
		_dismiss(c, tr("%s will ask another dealer.") % c.name)


func _offer(c: Customer) -> void:
	var offer := c.offer_total()
	if not c.hear_offer(offer):
		hud.show_customer(c)
		return
	c.dealt = true
	# sellers are paid from the till first, the rest from the safe
	till = maxf(0.0, till - offer)
	if c.piece:
		_buy_piece(c, offer)
		return
	if c.bar:
		_buy_bar(c, offer)
		return
	Shop.add_cash(-offer)
	Shop.note("bought", offer)
	Shop.add_stock(c.item, c.qty, offer / c.qty, c.fake)
	if c.fake != "":
		pending_fakes.append({"at": time + 8.0, "item": c.item, "fake": c.fake, "qty": c.qty, "paid": offer})
	Shop.reputation_for("bought")
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, tr("Bought %d × %s for %s.") % [c.qty, c.item.display_name, Market.format_money(offer)])


func _buy_piece(c: Customer, offer: float) -> void:
	Shop.add_cash(-offer)
	Shop.note("bought", offer)
	pending_pieces.append({"at": time + 8.0, "piece": c.piece, "paid": offer, "name": c.name})
	Shop.reputation_for("bought")
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, tr("Bought %s's %s for %s. Off to the refiner.") % [c.name, c.piece.short_title(), Market.format_money(offer)])


func _buy_bar(c: Customer, offer: float) -> void:
	Shop.add_cash(-offer)
	Shop.note("bought", offer)
	BullionBar.record(c.bar, Shop.day)
	pending_bars.append({"at": time + 8.0, "bar": c.bar, "paid": offer, "name": c.name})
	Shop.reputation_for("bought")
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, tr("Bought %s's %s for %s. Off to the bullion dealer.") % [c.name, c.bar.display_name(), Market.format_money(offer)])


## The bullion dealer checks every bar it buys from you, so a fake shows up here.
func _settle_bar(j: Dictionary) -> void:
	var b: BullionBar = j.bar
	var paid: float = j.paid
	var payout := b.dealer_payout(Progress.effect("bar_payout"))
	if payout > 0.0:
		Day.add_income(tr("Bullion dealer"), payout)
	Shop.note("profit", payout - paid)
	if b.fake == "":
		Shop.log_event(tr("Bullion dealer paid %s for %s's %s (profit %s).") % [Market.format_money(payout), j.name, b.display_name(), Market.format_money(payout - paid)], "good")
		return
	Shop.note("scammed")
	Shop.reputation_for("scammed")
	Shop.log_event(tr("Bullion dealer: %s's %s was %s. Lost %s.") % [j.name, b.display_name(), BullionBar.label(b.fake), Market.format_money(paid - payout)], "bad")
	var cover := Progress.effect("fraud_refund")
	if cover > 0.0 and paid > payout:
		Day.add_income(tr("Fraud insurance payout"), (paid - payout) * minf(cover, 1.0))


## The refiner melts a bought piece and the stone dealer takes any diamond.
## This is where a wrong appraisal shows up.
func _settle_piece(j: Dictionary) -> void:
	var p: JewelleryPiece = j.piece
	var payout := p.refiner_payout() * (1.0 + Progress.effect("refine"))
	var paid: float = j.paid
	Day.add_income(tr("Refiner and stone dealer"), payout)
	Shop.note("profit", payout - paid)
	var what := tr("%s's %s") % [j.name, p.short_title()]
	var reasons: Array[String] = []
	if p.true_grade == "plated":
		reasons.append(tr("it was plated %s") % tr(p.base_metal))
	elif p.true_grade != p.claimed_grade:
		reasons.append(tr("it was %s") % tr(p.true_grade))
	if p.stone != "" and p.stone != "diamond":
		reasons.append(tr("the stone was %s") % tr(STONE_NAMES[p.stone]))
	if p.true_grade == "plated" or payout < paid * 0.97:
		if p.true_grade == "plated":
			Shop.note("scammed")
			Shop.reputation_for("scammed")
		Shop.log_event(tr("Refiner: %s%s. Lost %s.") % [what, ": " + ", ".join(reasons) if not reasons.is_empty() else "", Market.format_money(paid - payout)], "bad")
	else:
		Shop.log_event(tr("Refiner paid %s for %s (profit %s).") % [Market.format_money(payout), what, Market.format_money(payout - paid)], "good")


func _sell(c: Customer) -> void:
	var have := c.can_sell()
	if have <= 0:
		hud.show_customer(c)
		return
	c.settle_for(have)
	if not c.hear_price(Shop.sell_premium):
		hud.show_customer(c)
		return
	var sale := _ring_up(c)
	_dismiss(c, sale.text, sale.mood)


## Hands a buyer their coins and puts the money in the till.
## Returns the log line and its mood: {"text", "mood"}.
func _ring_up(c: Customer) -> Dictionary:
	c.dealt = true
	var price := c.sale_total()
	var taken := Shop.take_stock(c.item.metal, c.qty, c.item if c.wanted_exact else null)
	Shop.add_cash(price)
	till += price
	Shop.note("sold", price)
	Shop.note("profit", price - taken.cost)
	Shop.note("served")
	Shop.reputation_for("sold_short" if c.short_sale() else "sold")
	Sfx.play(self, Sfx.register_chime(), -6.0)
	if taken.fakes > 0:
		var refund: float = price / c.qty * taken.fakes
		Shop.add_cash(-refund)
		till = maxf(0.0, till - refund)
		Shop.reputation_for("sold_fake")
		Shop.log_event(tr("%s came back: %d of the coins you sold were fake! Refunded %s.") % [c.name, taken.fakes, Market.format_money(refund)], "bad")
	var profit: float = price - taken.cost
	if c.short_sale():
		return {"text": tr("Sold %d of the %d coins %s wanted for %s (profit %s).") % [c.qty, c.wanted, c.name, Market.format_money(price), Market.format_money(profit)],
			"mood": "good" if profit >= 0.0 else "bad"}
	return {"text": tr("Sold %d coins for %s (profit %s).") % [c.qty, Market.format_money(price), Market.format_money(profit)],
		"mood": "good" if profit >= 0.0 else "bad"}


## The clerk takes a buyer from the queue to the second till. They leave you the
## customer at your counter, sellers (they don't test) and anyone they already sent back.
func _clerk_tick(delta: float) -> void:
	if not Staff.on_duty("clerk"):
		return
	if at_clerk:
		if not at_clerk.walking:
			clerk_left -= delta
			if clerk_left <= 0.0:
				_clerk_finish()
		return
	var busy := _test != null or away > 0.0
	for c in queue:
		if c.walking or c == _testing or c.kind != "buyer" or c.clerk_tried or c.stock_have() < c.qty:
			continue
		if c == _front() and not busy:
			continue
		queue.erase(c)
		at_clerk = c
		clerk_left = Staff.clerk_seconds()
		if c == _shown:
			_shown = null
			_show_front()
		return


func _clerk_finish() -> void:
	var c := at_clerk
	var clerk: String = Staff.ROLES.clerk.name
	at_clerk = null
	if c.can_sell() <= 0:
		_dismiss(c, tr("%s left: the coins sold out before %s could ring them up.") % [c.name, clerk], "bad")
		return
	# someone else bought some first: they take what is left
	c.settle_for(c.can_sell())
	if c.hear_price(Shop.sell_premium):
		var sale := _ring_up(c)
		Staff.gain_xp("clerk", Staff.XP_PER_SALE)
		_dismiss(c, "%s: %s" % [clerk, sale.text], sale.mood)
		return
	# a seasoned clerk can sometimes talk them round
	if rng.randf() < Staff.clerk_persuade():
		var sold := _ring_up(c)
		Staff.gain_xp("clerk", Staff.XP_PER_SALE)
		_dismiss(c, tr("%s talked them round. %s") % [clerk, sold.text], sold.mood)
		return
	# they want a better price than the clerk may give: back to the queue for you
	c.clerk_tried = true
	if queue.size() < Progress.queue_slots():
		queue.append(c)
		Shop.log_event(tr("%s wants a better price. %s sent them to you.") % [c.name, clerk])
	else:
		_dismiss(c, tr("%s wouldn't pay your price and left.") % c.name, "bad")


func _start_vault_run() -> void:
	if till < 1.0:
		return
	away = VAULT_RUN_SECONDS
	Sfx.play(self, Sfx.click(), -6.0)
	_show_front()


func _finish_vault_run() -> void:
	away = 0.0
	Shop.log_event(tr("Locked %s from the till in the safe.") % Market.format_money(till), "good")
	till = 0.0
	_show_front()


## Someone reaches over the counter for an overfull till.
func _till_grab() -> void:
	var taken := RushHours.grab_amount(till)
	till -= taken
	Day.add_expense(tr("Snatched from the till"), taken)
	Shop.note("stolen", taken)
	Shop.log_event(tr("A thief grabbed %s from the till and ran! Take cash to the vault.") % Market.format_money(taken), "bad")


## A robber joins the queue looking like anyone else, unless the guard spots them first.
func _robber_walks_in() -> void:
	if rng.randf() < Staff.guard_stop():
		Shop.note("robbers_stopped")
		Shop.log_event(tr("%s stopped a man with a gun at the door. The police took him away.") % Staff.ROLES.guard.name, "good")
		Sfx.play(self, Sfx.door_bell(), -4.0)
		return
	robber = Security.robber(rng)
	robber_revealed = false
	queue.append(robber)
	Sfx.play(self, Sfx.door_bell(), -8.0)
	Shop.log_event(tr("A man in a cap walked in and kept his head down."))


## At the counter the robber pulls a gun, the queue scatters and the clock on them starts.
## If you don't answer in time, they help themselves.
func _robber_tick(delta: float) -> void:
	if robber == null or robber.leaving:
		return
	if robber != _front():
		return
	if not robber_revealed:
		robber_revealed = true
		Shop.note("holdups")
		Sfx.play(self, Sfx.alarm(), -12.0)
		Shop.log_event(tr("Hold-up! The man in the cap pulled a gun at the counter."), "bad")
		var fled := 0
		for c in queue.duplicate():
			if c != robber and c != _testing and rng.randf() < Security.QUEUE_FLEES:
				fled += 1
				_dismiss(c)
		if fled > 0:
			Shop.log_event(tr_n("%d customer ran for the door.", "%d customers ran for the door.", fled) % fled, "bad")
		hud.show_customer(robber)
		return
	robber.patience -= delta
	if robber.patience <= 0.0:
		_robbed(tr("You froze. He emptied the till"))


## Hands the till over: you lose the cash, and nobody gets hurt.
func _hand_over() -> void:
	var taken := till
	till = 0.0
	if taken > 0.0:
		Day.add_expense(tr("Handed over in a hold-up"), taken)
	Shop.note("stolen", taken)
	_police_recover(taken)
	_robber_leaves(tr("You handed over %s from the till. He ran.") % Market.format_money(taken))


## The panic button: the alarm may scare him off empty-handed, or he grabs everything in reach.
func _panic_button() -> void:
	Sfx.play(self, Sfx.alarm(), -6.0)
	if rng.randf() < Security.panic_odds():
		Shop.note("robbers_stopped")
		_robber_leaves(tr("The alarm wailed and he bolted empty-handed!"), "good")
		return
	_robbed(tr("The alarm didn't scare him. He emptied the till"))


## The robber takes the till and sweeps the best coins out of the display case.
func _robbed(how: String) -> void:
	var taken := till
	till = 0.0
	if taken > 0.0:
		Day.add_expense(tr("Taken in a hold-up"), taken)
	var grab := Security.case_grab()
	var coins := Security.grab_value(grab)
	for e in grab:
		Shop.remove_from_lot(e[0], e[1])
	Shop.note("stolen", taken + coins)
	_police_recover(taken + coins)
	var what := tr("%s: %s gone") % [how, Market.format_money(taken)]
	if coins > 0.0:
		what += tr(", plus %s in coins from the case") % Market.format_money(coins)
	_robber_leaves(what + ".", "bad")


func _police_recover(usd: float) -> void:
	var back := usd * Security.recover_share()
	if back >= 1.0:
		Day.add_income(tr("Police recovered stolen goods"), back)
		Shop.log_event(tr("The cameras caught his face. Police got back %s.") % Market.format_money(back), "good")


func _robber_leaves(text: String, mood := "bad") -> void:
	var c := robber
	robber = null
	robber_revealed = false
	_dismiss(c, text, mood)


## A headline breaks: the first few customers it brings come straight in.
func _on_market_event(event: Dictionary) -> void:
	if closing:
		return
	_rush_left = int(event.rush)
	_next_spawn = minf(_next_spawn, 1.0)
	Sfx.play(self, Sfx.door_bell(), -4.0)


func _open_test(c: Customer) -> void:
	# in a rush the clock keeps going: the queue waits, the clerk works on
	paused = rush.is_empty()
	_testing = c
	var scene: PackedScene = GradingScene if c.kind == "grade" else (JewelleryTestScene if c.piece else (BarTestScene if c.bar else CoinTestScene))
	_test = scene.instantiate()
	hud.add_child(_test)
	_test.start(c)
	_test.finished.connect(_on_test_finished.bind(c))
	bench_opened.emit(_test, c)


func _on_test_finished(verdict: String, c: Customer) -> void:
	_test.queue_free()
	_test = null
	_testing = null
	paused = false
	bench_closed.emit(verdict, c)
	match verdict:
		"graded":
			_graded(c)
		"genuine":
			c.tested = true
			c.say = tr("Told you it was real. So, what's your offer?") if c.bar else tr("Told you they were real. So, what's your offer?")
			if c.piece:
				_appraised(c)
			hud.show_customer(c)
		"fake" when c.piece:
			if c.piece.true_grade == "plated":
				Shop.note("caught")
				Shop.reputation_for("caught")
				_dismiss(c, tr("Caught %s's plated %s! Acid doesn't lie.") % [c.name, c.piece.short_title()], "good")
			else:
				Shop.reputation_for("wrong_call")
				_dismiss(c, tr("You called %s's real %s plated. They stormed out.") % [c.name, c.piece.short_title()], "bad")
		"fake" when c.bar:
			if c.bar.fake != "":
				Shop.note("caught")
				Shop.reputation_for("caught")
				_dismiss(c, tr("Caught %s's %s bar!%s") % [c.name, BullionBar.label(c.bar.fake), tr(" Its serial was cloned.") if c.bar.cloned else ""], "good")
			else:
				Shop.reputation_for("wrong_call")
				_dismiss(c, tr("You called %s's genuine bar fake. They stormed out.") % c.name, "bad")
		"fake":
			if c.fake != "":
				c.caught = true
				Shop.note("caught")
				Shop.reputation_for("caught")
				_dismiss(c, tr("Caught a %s fake from %s!") % [Counterfeit.label(c.fake), c.name], "good")
			else:
				Shop.reputation_for("wrong_call")
				_dismiss(c, tr("You called %s's genuine coins fake. They stormed out.") % c.name, "bad")


## A collector hears your grade: a fee (and a tip when it's spot on), and their verdict.
func _graded(c: Customer) -> void:
	var call := c.grading.judge(int(c.assessed.grade), bool(c.assessed.cleaned), c.name)
	c.dealt = true
	c.say = call.say
	if call.pay > 0.0:
		Day.add_income("Grading fees", call.pay)
		Shop.note("profit", call.pay)
		Sfx.play(self, Sfx.register_chime(), -8.0)
	Shop.adjust_reputation(call.rep)
	Shop.note("graded")
	if call.steps == 0 and call.cleaned_ok:
		Shop.note("graded_exact")
	_dismiss(c, call.log, call.mood)


## The customer's reaction to your grading, and credit for catching a bad claim.
func _appraised(c: Customer) -> void:
	var p := c.piece
	var a := c.assessed
	if a.grade == p.true_grade and p.true_grade != p.claimed_grade:
		if JewelleryPiece.PURITY[p.true_grade] > JewelleryPiece.PURITY[p.claimed_grade]:
			Shop.reputation_for("honest")
			c.say = tr("It's %s, not %s? You could have kept quiet. Thank you.") % [tr(p.true_grade), tr(p.claimed_grade)]
			Shop.log_event(tr("Told %s their piece is better than they thought.") % c.name, "good")
		else:
			c.say = tr("%s? Huh. My mother always said %s.") % [tr(p.true_grade), tr(p.claimed_grade)]
			Shop.note("caught")
			Shop.log_event(tr("The acid says %s's piece is %s, not %s.") % [c.name, tr(p.true_grade), tr(p.claimed_grade)], "good")
	elif p.stone != "" and p.stone != "diamond" and not a.diamond:
		Shop.note("caught")
		c.say = tr("Not a diamond? Well, the gold's still gold.") if not p.scam else tr("Fine. Pay me for the metal then.")
		Shop.log_event(tr("Spotted that %s's stone is %s.") % [c.name, tr(STONE_NAMES[p.stone])], "good")
	else:
		c.say = tr("So, what's it worth to you?")


## The morning session at the trading desk, over the morning panel.
func open_desk() -> void:
	if _desk != null or not DeskSession.available():
		return
	hud.hide_panels()
	_desk = TradingDeskScene.instantiate()
	hud.add_child(_desk)
	_desk.start()
	_desk.finished.connect(_on_desk_finished)
	desk_opened.emit(_desk)


func _on_desk_finished(_pnl: float) -> void:
	_desk.queue_free()
	_desk = null
	hud.show_morning()


## The Smelter, over the morning panel: the scrap dealer's lots and the furnace.
func open_smelter() -> void:
	if _smelter != null or not ScrapYard.available():
		return
	hud.hide_panels()
	_smelter = SmelterScene.instantiate()
	hud.add_child(_smelter)
	_smelter.start()
	_smelter.finished.connect(_on_smelter_finished)
	smelter_opened.emit(_smelter)


func _on_smelter_finished() -> void:
	_smelter.queue_free()
	_smelter = null
	hud.show_morning()


## The Ashworth & Finch saleroom, over the morning panel, on a sale morning.
func open_auction() -> void:
	if _auction != null or not AuctionHouse.available():
		return
	hud.hide_panels()
	_auction = AuctionScene.instantiate()
	hud.add_child(_auction)
	_auction.start()
	_auction.finished.connect(_on_auction_finished)
	auction_opened.emit(_auction)


func _on_auction_finished() -> void:
	_auction.queue_free()
	_auction = null
	hud.show_morning()


func _open_vault() -> void:
	_vault = VaultScene.instantiate()
	hud.add_child(_vault)
	_vault.start()
	_vault.finished.connect(_on_vault_finished)
	vault_opened.emit(_vault)


func _on_vault_finished(night: Dictionary) -> void:
	_vault.queue_free()
	_vault = null
	var report := Day.end_day()
	if night.get("break_in", false):
		report.lines.append(tr("Break-in overnight: lost %s.") % Market.format_money(night.value))
	var holdups := int(Shop.stats.get("holdups", 0.0))
	if holdups > 0:
		report.lines.append(tr("%s held up the counter today.%s") % [tr("A robber") if holdups == 1 else tr("%d robbers") % holdups,
			"" if Staff.on_duty("guard") else tr(" A guard stops most of them at the door.")])
	var missed := int(Shop.stats.get("walked_by", 0.0))
	if missed > 0:
		report.lines.append(tr_n("%d customer saw the queue in the rush and walked on.%s", "%d customers saw the queue in the rush and walked on.%s", missed) % [missed,
			"" if Staff.on_duty("clerk") else tr(" A clerk would keep the line moving.")])
	SaveGame.save_game() # autosave, so quitting on the summary does not replay the day
	hud.show_day_summary(report)
	summary_shown.emit()


func _open_next_day() -> void:
	Shop.next_day()
	_start_morning()


func _start_morning() -> void:
	if Demo.is_over(): # the demo's days are used up: no more mornings
		paused = true
		get_tree().change_scene_to_file(DemoEndScene)
		return
	time = 0.0
	closing = false
	paused = true
	Day.begin_day()
	SaveGame.save_game()
	hud.show_morning()


func _open_shop() -> void:
	_next_spawn = 2.0
	_rush_left = Calendar.opening_rush()
	rush = {}
	till = 0.0
	away = 0.0
	paused = false
	hud.hide_panels()
	Day.open_shop()
	Shop.log_event(tr("%s, day %d. Shop open.") % [Day.weekday(), Shop.day])
	var town := Calendar.today()
	if not town.is_empty():
		Shop.log_event(tr("TOWN: ") + Calendar.banner(town), town.mood)


func _new_game() -> void:
	for c in queue + leaving:
		c.leaving = true
	queue.clear()
	leaving.clear()
	at_clerk = null
	robber = null
	pending_fakes.clear()
	pending_bars.clear()
	SaveGame.new_game()
	coach.restart()
	Shop.log_event(tr("A fresh start at the corner counter."))
	_start_morning()
