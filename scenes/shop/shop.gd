extends Node2D
## The shop floor: runs the day clock, brings customers in, and settles deals at
## live market prices. Coin testing opens the CoinTest minigame over the shop,
## jewellery opens the JewelleryTest appraisal and bullion bars open the BarTest.
## Each day runs morning (prices, upgrades) -> open -> closing -> vault lock-up ->
## after hours (summary), following the Day autoload. The game saves every morning.
## In the rush hours (RushHours) the clock keeps running while you test, so you juggle
## the counter, the benches and runs to the vault with the till; staff (Staff) help out.
## On day 1 of a new game the Coach walks the player through it.

signal bench_opened(bench: Control, c: Customer)
signal bench_closed(verdict: String, c: Customer)
signal customer_left(c: Customer)
signal vault_opened(vault: Control)
signal summary_shown

const DAY_SECONDS := 180.0
const WALK_SPEED := 1.8 # tiles per second
const CoinTestScene := preload("res://scenes/coin_test/coin_test.tscn")
const VaultScene := preload("res://scenes/vault/vault.tscn")
const NewsBanner := preload("res://scenes/shop/news_banner.gd")
const RUSH_GAP := 1.5 # seconds between customers in a news rush
const JewelleryTestScene := preload("res://scenes/jewellery_test/jewellery_test.tscn")
const BarTestScene := preload("res://scenes/bar_test/bar_test.tscn")
const STONE_NAMES := {"cz": "cubic zirconia", "glass": "glass", "moissanite": "moissanite"}
const CLERK_SECONDS := 5.0 # how long the clerk takes to ring up a sale
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

var _testing: Customer
var _next_spawn := 3.0
var _rush_left := 0
var _shown: Customer
var _test: Control
var _vault: Control
var _pause: PauseMenu
var coach: Coach


func _ready() -> void:
	rng.randomize()
	BullionBar.hook_up()
	hud.action.connect(_on_action)
	hud.open_requested.connect(_open_shop)
	hud.next_day_requested.connect(_open_next_day)
	hud.new_game_requested.connect(_new_game)
	hud.menu_requested.connect(open_pause_menu)
	_pause = PauseMenu.new()
	add_child(_pause)
	Music.play("shop")
	var banner := NewsBanner.new()
	hud.add_child(banner)
	add_child(RushStrip.new(self))
	MarketEvents.started.connect(_on_market_event)
	if SaveGame.load_game():
		Shop.log_event("Welcome back. Day %d at your %s." % [Shop.day, Progress.tier_name()])
	else:
		Shop.log_event("Welcome to your shop. Test coins before you buy them.")
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
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _test == null:
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
		Shop.log_event("Closing time. Serving the last customers.")
	_update_rush()
	MarketEvents.advance(delta)
	_next_spawn -= delta
	if not closing and _next_spawn <= 0.0 and not coach.holds_clock():
		if queue.size() < ShopArt.SLOTS.size():
			_spawn()
			if _rush_left > 0:
				_rush_left -= 1
				_next_spawn = RUSH_GAP
			elif not rush.is_empty():
				_next_spawn = RushHours.SPAWN_GAP / Progress.traffic() * rng.randf_range(0.75, 1.25)
			else:
				_next_spawn = maxf(5.0, 15.0 - Shop.reputation * 2.0) / Progress.traffic() * rng.randf_range(0.7, 1.3) * MarketEvents.spawn_factor()
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
	for c in queue.duplicate():
		# whoever is on the testing bench is watching you work
		if c.walking or c == _testing:
			continue
		c.patience -= delta if c == _front() else delta * 0.5
		if c.patience <= 0.0:
			Shop.adjust_reputation(-0.12)
			_dismiss(c, "%s got tired of waiting and left." % c.name, "bad")
	for f in pending_fakes.duplicate():
		if time >= f.at or closing:
			pending_fakes.erase(f)
			Shop.confiscate(f.item, f.fake)
			Shop.note("scammed")
			Shop.adjust_reputation(-0.3)
			Shop.log_event("Assay lab: the %d × %s were %s. Lost %s." % [f.qty, f.item.display_name, Counterfeit.label(f.fake), Market.format_money(f.paid)], "bad")
			var cover := Progress.effect("fraud_refund")
			if cover > 0.0:
				Day.add_income("Fraud insurance payout", f.paid * minf(cover, 1.0))
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
		Shop.log_event("The rush is over. Catch your breath.")
		return
	_next_spawn = minf(_next_spawn, 1.0)
	Sfx.play(self, Sfx.door_bell(), -4.0)
	var help := "" if Staff.has("clerk") else " A clerk would help."
	Shop.log_event("%s! The queue keeps waiting while you test.%s" % [rush.name, help], "bad")


func _spawn() -> void:
	admit(Customers.next_customer(rng, MarketEvents.customer_event(rng)))


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
	match id:
		"test":
			_open_test(c)
		"offer":
			_offer(c)
		"refuse":
			if c.tested:
				Shop.adjust_reputation(-0.05)
				_dismiss(c, "Passed on %s's %s." % [c.name, "bar" if c.bar else "coins"])
			else:
				Shop.adjust_reputation(0.05 if c.fake != "" or (c.piece and c.piece.scam) or (c.bar and c.bar.fake != "") else -0.1)
				_dismiss(c, "Turned %s away without testing." % c.name)
		"sell":
			_sell(c)
		"decline":
			_dismiss(c, "%s said goodbye." % c.name if c.kind == "visit" else "%s left without buying." % c.name)


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
	Shop.adjust_reputation(0.05)
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, "Bought %d × %s for %s." % [c.qty, c.item.display_name, Market.format_money(offer)])


func _buy_piece(c: Customer, offer: float) -> void:
	Shop.add_cash(-offer)
	Shop.note("bought", offer)
	pending_pieces.append({"at": time + 8.0, "piece": c.piece, "paid": offer, "name": c.name})
	Shop.adjust_reputation(0.05)
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, "Bought %s's %s for %s. Off to the refiner." % [c.name, c.piece.short_title(), Market.format_money(offer)])


func _buy_bar(c: Customer, offer: float) -> void:
	Shop.add_cash(-offer)
	Shop.note("bought", offer)
	BullionBar.record(c.bar, Shop.day)
	pending_bars.append({"at": time + 8.0, "bar": c.bar, "paid": offer, "name": c.name})
	Shop.adjust_reputation(0.05)
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_dismiss(c, "Bought %s's %s for %s. Off to the bullion dealer." % [c.name, c.bar.display_name(), Market.format_money(offer)])


## The bullion dealer checks every bar it buys from you, so a fake shows up here.
func _settle_bar(j: Dictionary) -> void:
	var b: BullionBar = j.bar
	var paid: float = j.paid
	var payout := b.dealer_payout(Progress.effect("bar_payout"))
	if payout > 0.0:
		Day.add_income("Bullion dealer", payout)
	Shop.note("profit", payout - paid)
	if b.fake == "":
		Shop.log_event("Bullion dealer paid %s for %s's %s (profit %s)." % [Market.format_money(payout), j.name, b.display_name(), Market.format_money(payout - paid)], "good")
		return
	Shop.note("scammed")
	Shop.adjust_reputation(-0.3)
	Shop.log_event("Bullion dealer: %s's %s was %s. Lost %s." % [j.name, b.display_name(), BullionBar.label(b.fake), Market.format_money(paid - payout)], "bad")
	var cover := Progress.effect("fraud_refund")
	if cover > 0.0 and paid > payout:
		Day.add_income("Fraud insurance payout", (paid - payout) * minf(cover, 1.0))


## The refiner melts a bought piece and the stone dealer takes any diamond.
## This is where a wrong appraisal shows up.
func _settle_piece(j: Dictionary) -> void:
	var p: JewelleryPiece = j.piece
	var payout := p.refiner_payout()
	var paid: float = j.paid
	Day.add_income("Refiner and stone dealer", payout)
	Shop.note("profit", payout - paid)
	var what := "%s's %s" % [j.name, p.short_title()]
	var reasons: Array[String] = []
	if p.true_grade == "plated":
		reasons.append("it was plated %s" % p.base_metal)
	elif p.true_grade != p.claimed_grade:
		reasons.append("it was %s" % p.true_grade)
	if p.stone != "" and p.stone != "diamond":
		reasons.append("the stone was %s" % STONE_NAMES[p.stone])
	if p.true_grade == "plated" or payout < paid * 0.97:
		if p.true_grade == "plated":
			Shop.note("scammed")
			Shop.adjust_reputation(-0.3)
		Shop.log_event("Refiner: %s%s. Lost %s." % [what, ": " + ", ".join(reasons) if not reasons.is_empty() else "", Market.format_money(paid - payout)], "bad")
	else:
		Shop.log_event("Refiner paid %s for %s (profit %s)." % [Market.format_money(payout), what, Market.format_money(payout - paid)], "good")


func _sell(c: Customer) -> void:
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
	Shop.adjust_reputation(0.08)
	Sfx.play(self, Sfx.register_chime(), -6.0)
	if taken.fakes > 0:
		var refund: float = price / c.qty * taken.fakes
		Shop.add_cash(-refund)
		till = maxf(0.0, till - refund)
		Shop.adjust_reputation(-0.6)
		Shop.log_event("%s came back: %d of the coins you sold were fake! Refunded %s." % [c.name, taken.fakes, Market.format_money(refund)], "bad")
	var profit: float = price - taken.cost
	return {"text": "Sold %d coins for %s (profit %s)." % [c.qty, Market.format_money(price), Market.format_money(profit)],
		"mood": "good" if profit >= 0.0 else "bad"}


## The clerk takes a buyer from the queue to the second till. They leave you the
## customer at your counter, sellers (they don't test) and anyone they already sent back.
func _clerk_tick(delta: float) -> void:
	if not Staff.has("clerk"):
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
		clerk_left = CLERK_SECONDS
		if c == _shown:
			_shown = null
			_show_front()
		return


func _clerk_finish() -> void:
	var c := at_clerk
	var clerk: String = Staff.ROLES.clerk.name
	at_clerk = null
	if c.stock_have() < c.qty:
		_dismiss(c, "%s left: the coins sold out before %s could ring them up." % [c.name, clerk], "bad")
		return
	if c.hear_price(Shop.sell_premium):
		var sale := _ring_up(c)
		_dismiss(c, "%s: %s" % [clerk, sale.text], sale.mood)
		return
	# they want a better price than the clerk may give: back to the queue for you
	c.clerk_tried = true
	if queue.size() < ShopArt.SLOTS.size():
		queue.append(c)
		Shop.log_event("%s wants a better price. %s sent them to you." % [c.name, clerk])
	else:
		_dismiss(c, "%s wouldn't pay your price and left." % c.name, "bad")


func _start_vault_run() -> void:
	if till < 1.0:
		return
	away = VAULT_RUN_SECONDS
	Sfx.play(self, Sfx.click(), -6.0)
	_show_front()


func _finish_vault_run() -> void:
	away = 0.0
	Shop.log_event("Locked %s from the till in the safe." % Market.format_money(till), "good")
	till = 0.0
	_show_front()


## Someone reaches over the counter for an overfull till.
func _till_grab() -> void:
	var taken := till * 0.6
	till -= taken
	Day.add_expense("Snatched from the till", taken)
	Shop.note("stolen", taken)
	Shop.log_event("A thief grabbed %s from the till and ran! Take cash to the vault." % Market.format_money(taken), "bad")


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
	_test = (JewelleryTestScene if c.piece else (BarTestScene if c.bar else CoinTestScene)).instantiate()
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
		"genuine":
			c.tested = true
			c.say = "Told you it was real. So, what's your offer?" if c.bar else "Told you they were real. So, what's your offer?"
			if c.piece:
				_appraised(c)
			hud.show_customer(c)
		"fake" when c.piece:
			if c.piece.true_grade == "plated":
				Shop.note("caught")
				Shop.adjust_reputation(0.15)
				_dismiss(c, "Caught %s's plated %s! Acid doesn't lie." % [c.name, c.piece.short_title()], "good")
			else:
				Shop.adjust_reputation(-0.25)
				_dismiss(c, "You called %s's real %s plated. They stormed out." % [c.name, c.piece.short_title()], "bad")
		"fake" when c.bar:
			if c.bar.fake != "":
				Shop.note("caught")
				Shop.adjust_reputation(0.15)
				_dismiss(c, "Caught %s's %s bar!%s" % [c.name, BullionBar.label(c.bar.fake), " Its serial was cloned." if c.bar.cloned else ""], "good")
			else:
				Shop.adjust_reputation(-0.25)
				_dismiss(c, "You called %s's genuine bar fake. They stormed out." % c.name, "bad")
		"fake":
			if c.fake != "":
				c.caught = true
				Shop.note("caught")
				Shop.adjust_reputation(0.15)
				_dismiss(c, "Caught a %s fake from %s!" % [Counterfeit.label(c.fake), c.name], "good")
			else:
				Shop.adjust_reputation(-0.25)
				_dismiss(c, "You called %s's genuine coins fake. They stormed out." % c.name, "bad")


## The customer's reaction to your grading, and credit for catching a bad claim.
func _appraised(c: Customer) -> void:
	var p := c.piece
	var a := c.assessed
	if a.grade == p.true_grade and p.true_grade != p.claimed_grade:
		if JewelleryPiece.PURITY[p.true_grade] > JewelleryPiece.PURITY[p.claimed_grade]:
			Shop.adjust_reputation(0.1)
			c.say = "It's %s, not %s? You could have kept quiet. Thank you." % [p.true_grade, p.claimed_grade]
			Shop.log_event("Told %s their piece is better than they thought." % c.name, "good")
		else:
			c.say = "%s? Huh. My mother always said %s." % [p.true_grade, p.claimed_grade]
			Shop.note("caught")
			Shop.log_event("The acid says %s's piece is %s, not %s." % [c.name, p.true_grade, p.claimed_grade], "good")
	elif p.stone != "" and p.stone != "diamond" and not a.diamond:
		Shop.note("caught")
		c.say = "Not a diamond? Well, the gold's still gold." if not p.scam else "Fine. Pay me for the metal then."
		Shop.log_event("Spotted that %s's stone is %s." % [c.name, STONE_NAMES[p.stone]], "good")
	else:
		c.say = "So, what's it worth to you?"


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
		report.lines.append("Break-in overnight: lost %s." % Market.format_money(night.value))
	var missed := int(Shop.stats.get("walked_by", 0.0))
	if missed > 0:
		report.lines.append("%d customer%s saw the queue in the rush and walked on.%s" % [missed, "" if missed == 1 else "s",
			"" if Staff.has("clerk") else " A clerk would keep the line moving."])
	hud.show_day_summary(report)
	summary_shown.emit()


func _open_next_day() -> void:
	Shop.next_day()
	_start_morning()


func _start_morning() -> void:
	time = 0.0
	closing = false
	paused = true
	Day.begin_day()
	SaveGame.save_game()
	hud.show_morning()


func _open_shop() -> void:
	_next_spawn = 2.0
	rush = {}
	till = 0.0
	away = 0.0
	paused = false
	hud.hide_panels()
	Day.open_shop()
	Shop.log_event("%s, day %d. Shop open." % [Day.weekday(), Shop.day])


func _new_game() -> void:
	for c in queue + leaving:
		c.leaving = true
	queue.clear()
	leaving.clear()
	at_clerk = null
	pending_fakes.clear()
	pending_bars.clear()
	SaveGame.new_game()
	coach.restart()
	Shop.log_event("A fresh start at the corner counter.")
	_start_morning()
