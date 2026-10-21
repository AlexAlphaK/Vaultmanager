extends Node2D
## The shop floor: runs the day clock, brings customers in, and settles deals at
## live market prices. Coin testing opens the CoinTest minigame over the shop, and
## jewellery opens the JewelleryTest appraisal.
## Each day runs morning (prices, upgrades) -> open -> closing -> after hours (summary),
## following the Day autoload. The game saves every morning.

const DAY_SECONDS := 180.0
const WALK_SPEED := 1.8 # tiles per second
const CoinTestScene := preload("res://scenes/coin_test/coin_test.tscn")
const NewsBanner := preload("res://scenes/shop/news_banner.gd")
const RUSH_GAP := 1.5 # seconds between customers in a news rush
const JewelleryTestScene := preload("res://scenes/jewellery_test/jewellery_test.tscn")
const STONE_NAMES := {"cz": "cubic zirconia", "glass": "glass", "moissanite": "moissanite"}

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
var rng := RandomNumberGenerator.new()

var _next_spawn := 3.0
var _rush_left := 0
var _shown: Customer
var _test: Control


func _ready() -> void:
	rng.randomize()
	hud.action.connect(_on_action)
	hud.open_requested.connect(_open_shop)
	hud.next_day_requested.connect(_open_next_day)
	hud.new_game_requested.connect(_new_game)
	if SaveGame.load_game():
		Shop.log_event("Welcome back. Day %d at your %s." % [Shop.day, Progress.tier_name()])
	else:
		Shop.log_event("Welcome to your shop. Test coins before you buy them.")
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
	room.customers.assign(queue + leaving)
	room.day_fraction = clampf(time / DAY_SECONDS, 0.0, 1.0)
	hud.set_clock(Shop.day, int(9 * 60 + room.day_fraction * 8 * 60), closing)


func _tick(delta: float) -> void:
	time += delta
	if not closing and time >= DAY_SECONDS:
		closing = true
		Day.close_shop()
		Shop.log_event("Closing time. Serving the last customers.")
	MarketEvents.advance(delta)
	_next_spawn -= delta
	if not closing and _next_spawn <= 0.0 and queue.size() < ShopArt.SLOTS.size():
		_spawn()
		_next_spawn = maxf(5.0, 15.0 - Shop.reputation * 2.0) / Progress.traffic() * rng.randf_range(0.7, 1.3)
	for c in queue.duplicate():
		if c.walking:
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
	if closing and queue.is_empty() and leaving.is_empty():
		paused = true
		hud.show_day_summary(Day.end_day())


func _spawn() -> void:
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng, MarketEvents.customer_event(rng))
	queue.append(c)
	Sfx.play(self, Sfx.door_bell(), -8.0)
	Shop.log_event("%s walked in." % c.name)


func _walk(delta: float) -> void:
	for c in queue + leaving:
		var target: Vector2 = ShopArt.EXIT if c.leaving else ShopArt.SLOTS[mini(queue.find(c), ShopArt.SLOTS.size() - 1)]
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
	if _shown:
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
	if text != "":
		Shop.log_event(text, mood)
	if c == _shown:
		_shown = null
		_show_front()


func _on_action(id: String) -> void:
	var c := _front()
	if c == null or paused:
		return
	match id:
		"test":
			_open_test(c)
		"offer":
			_offer(c)
		"refuse":
			if c.tested:
				Shop.adjust_reputation(-0.05)
				_dismiss(c, "Passed on %s's coins." % c.name)
			else:
				Shop.adjust_reputation(0.05 if c.fake != "" or (c.piece and c.piece.scam) else -0.1)
				_dismiss(c, "Turned %s away without testing." % c.name)
		"sell":
			_sell(c)
		"decline":
			_dismiss(c, "%s left without buying." % c.name)


func _offer(c: Customer) -> void:
	var offer := c.offer_total()
	if offer < c.reserve * c.expected_total():
		c.tries += 1
		c.patience -= 15.0
		if c.piece:
			c.say = "No. I know what this is worth." if c.tries > 1 else "That's a lowball for a piece like this. Look again."
		else:
			c.say = "Still too low. I know what spot is today." if c.tries > 1 else \
				"That's a lowball. I was hoping for closer to %d%%." % roundi(c.reserve * 100.0 + rng.randf_range(0.0, 2.0))
		hud.show_customer(c)
		return
	if c.piece:
		_buy_piece(c, offer)
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
	if Shop.sell_premium > c.max_premium:
		c.tries += 1
		c.patience -= 15.0
		c.say = "The chain store downtown is cheaper." if c.tries > 1 else \
			"Spot plus %d%%? I'd pay maybe %d%% over." % [roundi(Shop.sell_premium * 100.0), maxi(1, floori(c.max_premium * 100.0))]
		hud.show_customer(c)
		return
	var price := c.sale_total()
	var taken := Shop.take_stock(c.item.metal, c.qty)
	Shop.add_cash(price)
	Shop.note("sold", price)
	Shop.note("profit", price - taken.cost)
	Shop.note("served")
	Shop.adjust_reputation(0.08)
	Sfx.play(self, Sfx.register_chime(), -6.0)
	if taken.fakes > 0:
		var refund: float = price / c.qty * taken.fakes
		Shop.add_cash(-refund)
		Shop.adjust_reputation(-0.6)
		Shop.log_event("%s came back: %d of the coins you sold were fake! Refunded %s." % [c.name, taken.fakes, Market.format_money(refund)], "bad")
	var profit: float = price - taken.cost
	_dismiss(c, "Sold %d coins for %s (profit %s)." % [c.qty, Market.format_money(price), Market.format_money(profit)], "good" if profit >= 0.0 else "bad")


## A headline breaks: the first few customers it brings come straight in.
func _on_market_event(event: Dictionary) -> void:
	if closing:
		return
	_rush_left = int(event.rush)
	_next_spawn = minf(_next_spawn, 1.0)
	Sfx.play(self, Sfx.door_bell(), -4.0)


func _open_test(c: Customer) -> void:
	paused = true
	_test = (JewelleryTestScene if c.piece else CoinTestScene).instantiate()
	hud.add_child(_test)
	_test.start(c)
	_test.finished.connect(_on_test_finished.bind(c))


func _on_test_finished(verdict: String, c: Customer) -> void:
	_test.queue_free()
	_test = null
	paused = false
	match verdict:
		"genuine":
			c.tested = true
			c.say = "Told you they were real. So, what's your offer?"
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
		"fake":
			if c.fake != "":
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
	paused = false
	hud.hide_panels()
	Day.open_shop()
	Shop.log_event("%s, day %d. Shop open." % [Day.weekday(), Shop.day])


func _new_game() -> void:
	for c in queue + leaving:
		c.leaving = true
	queue.clear()
	leaving.clear()
	pending_fakes.clear()
	SaveGame.new_game()
	Shop.log_event("A fresh start at the corner counter.")
	_start_morning()
