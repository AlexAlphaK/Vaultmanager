extends Node
## The other shops in town, and the fight for its customers.
##   Sterling Bullion Co.  the established dealer across the street: fair prices, a good
##                         name, and a habit of undercutting you when you get popular.
##   Lucky's Pawn & Loan   next door: pays far less for metal, but takes jewellery and asks
##                         no questions, so shady sellers drift there. Sometimes fences
##                         stolen goods, and a tip to the police shuts it for a while.
## Every customer weighs the shops in town by what they pay or charge and by their stars
## (share_for). When yours looks worse than a fair share they may cross the street before
## they reach your door (diverts); when it looks better, word spreads and customers come
## a little faster (traffic_factor). Each morning the rivals answer: Sterling reprices
## against you and both may make a move (a price war, an ad blitz, a smear, a fencing
## racket). The town map page shows it all, with your answers: a newspaper ad, beating
## Sterling's prices, or tipping off the police. The rivals' net worth grows day by day;
## passing them is how you become the biggest store in town.

signal changed

## Starting state of each rival. `buy` is the share of melt paid to sellers, `premium`
## what buyers pay over melt, `stars` 0-5 and `worth` the shop's net worth in USD.
## `growth` is how much their worth grows a day on its own, `deal` what each customer
## who goes to them instead of you adds to it.
const SHOPS := {
	"sterling": {"name": "Sterling Bullion Co.", "short": "Sterling", "owner": "Victor Sterling",
		"buy": 0.88, "premium": 0.07, "stars": 3.0, "worth": 180000.0, "growth": 0.004, "deal": 120.0},
	"pawn": {"name": "Lucky's Pawn & Loan", "short": "Lucky's", "owner": "Lucky Lou",
		"buy": 0.75, "premium": 0.12, "stars": 1.8, "worth": 50000.0, "growth": 0.002, "deal": 120.0},
}
## How much a customer cares: utility per 100% of price, and per star.
const PRICE_WEIGHT := 30.0
const STAR_WEIGHT := 0.6
## Extra pull the pawn shop has on jewellery sellers and on shady sellers.
const PAWN_JEWELLERY := 2.0
const PAWN_SHADY := 4.0
## Your fair share of the town's customers. Below it some cross the street, up to
## MAX_DIVERT of them; above it they come faster, up to MAX_BOOST.
const FAIR_SHARE := 0.5
const MAX_DIVERT := 0.45
const MAX_BOOST := 1.15
## Sterling's prices move a point a morning, within these limits.
const STERLING_BUY := Vector2(0.85, 0.93)
const STERLING_PREMIUM := Vector2(0.03, 0.09)
## Sterling's stars creep up as the town grows, to this.
const STERLING_STARS_MAX := 4.3
## Odds a rival without a move under way makes one in the morning, and the day they start.
const MOVE_ODDS := {"sterling": 0.25, "pawn": 0.2}
const MOVE_FROM_DAY := {"sterling": 3, "pawn": 4}
## A rival's moves: `days` it lasts (0 = at once), what it does while it lasts.
const MOVES := {
	"price_war": {"rival": "sterling", "days": 3,
		"news": "Sterling Bullion slashed prices: it pays 92% of melt and sells at spot +3%."},
	"ad_blitz": {"rival": "sterling", "days": 3, "pull": 0.6,
		"news": "Sterling's ads are all over the radio. Expect fewer walk-ins."},
	"smear": {"rival": "sterling", "days": 0, "reputation": -0.1, "shrug_stars": 4.0,
		"news": "A one-star review of your shop went up overnight. It reads a lot like Sterling's ad copy.",
		"shrugged": "A nasty review of your shop went up overnight. With your name, nobody believed it."},
	"fencing": {"rival": "pawn", "days": 4, "shady": 2.0, "worth": 5000.0,
		"news": "Word is Lucky's is buying stolen goods. Shady sellers are going there. You could tip off the police."},
	"clearance": {"rival": "pawn", "days": 2, "premium": 0.02,
		"news": "Lucky's is clearing out coins at spot +2%. Bargain hunters are lining up next door."},
}
## A newspaper ad: what it costs (times the deal size), how long it runs and its pull.
const AD_COST := 1200.0
const AD_DAYS := 3
const AD_PULL := 0.6
## A police raid on the pawn shop: days it stays shut, and the stars you earn for the tip.
const RAID_DAYS := 5
const TIP_REPUTATION := 0.1

## Per rival: {"buy", "premium", "stars", "worth", "move", "move_days", "closed"}.
var state := {}
## Days left on your newspaper ad.
var ad_days := 0
## Rivals whose net worth you have passed at the end of a day.
var passed: Array[String] = []
## Customers lost to each rival today, and your share of the last full day.
var lost_today := {}
var last_share := FAIR_SHARE
## Today's headlines about the rivals, for the morning panel and the town map.
var news: Array[String] = []
## The last morning the rivals made their moves, so reloading a morning save does not
## run them twice.
var last_morning := 0

var _share_sum := 0.0
var _share_n := 0


func _ready() -> void:
	reset()
	SaveGame.register("rivals", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_on_day_started)
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	state.clear()
	for id in SHOPS:
		var s: Dictionary = SHOPS[id]
		state[id] = {"buy": s.buy, "premium": s.premium, "stars": s.stars, "worth": s.worth,
			"move": "", "move_days": 0, "closed": 0}
	ad_days = 0
	passed.clear()
	lost_today.clear()
	last_share = FAIR_SHARE
	news.clear()
	last_morning = 0
	_share_sum = 0.0
	_share_n = 0
	changed.emit()


func name_of(id: String) -> String:
	return SHOPS[id].name


func is_open(id: String) -> bool:
	return int(state[id].closed) <= 0


## The move a rival is making today, or "".
func move_of(id: String) -> String:
	return str(state[id].move)


## What a rival pays sellers and charges buyers today, moves included.
func buy_of(id: String) -> float:
	return 0.92 if move_of(id) == "price_war" else float(state[id].buy)


func premium_of(id: String) -> float:
	var m := move_of(id)
	if MOVES.has(m) and MOVES[m].has("premium"):
		return float(MOVES[m].premium)
	return 0.03 if m == "price_war" else float(state[id].premium)


func stars_of(id: String) -> float:
	return float(state[id].stars)


func worth_of(id: String) -> float:
	return float(state[id].worth)


## How much a customer of `kind` ("seller" or "buyer") in `segment` ("", "jewellery" or
## "shady") likes shop `id` ("you" for the player).
func utility(id: String, kind: String, segment := "") -> float:
	var stars: float
	var price: float
	var pull := 0.0
	if id == "you":
		stars = Shop.reputation
		price = Shop.buy_percent if kind == "seller" else -Shop.sell_premium
		pull = AD_PULL if ad_days > 0 else 0.0
	else:
		stars = stars_of(id)
		price = buy_of(id) if kind == "seller" else -premium_of(id)
		var m: Dictionary = MOVES.get(move_of(id), {})
		pull = float(m.get("pull", 0.0))
		if id == "pawn" and kind == "seller":
			if segment == "jewellery":
				pull += PAWN_JEWELLERY
			elif segment == "shady":
				pull += PAWN_SHADY + float(m.get("shady", 0.0))
	return price * PRICE_WEIGHT + stars * STAR_WEIGHT + pull


## Your share of the customers of one kind, 0 to 1, among the shops open today.
func share(kind: String, segment := "") -> float:
	var mine := exp(utility("you", kind, segment))
	var total := mine
	for id in state:
		if is_open(id):
			total += exp(utility(id, kind, segment))
	return mine / total


## Your share of the customer `c` would see.
func share_for(c: Customer) -> float:
	return share(c.kind, _segment(c))


## Your share of everyday sellers and buyers, averaged.
func overall_share() -> float:
	return (share("seller") + share("buyer")) / 2.0


## Customers arrive faster when the town thinks you are the best shop in it.
func traffic_factor() -> float:
	return clampf(overall_share() / FAIR_SHARE, 1.0, MAX_BOOST)


## Odds that a customer like `c` goes to a rival instead of coming in.
func divert_odds(c: Customer) -> float:
	# regulars, people a headline sent, collectors with special orders and the shop's own
	# story beats always come in (town event crowds shop around like anyone else)
	if c.regular_id != "" or (c.event_id != "" and not Calendar.is_town_event(c.event_id)) or c.story != "" or c.kind == "visit" or c.kind == "robber" or not c.order.is_empty():
		return 0.0
	return clampf(1.0 - share_for(c) / FAIR_SHARE, 0.0, MAX_DIVERT)


## The rival customer `c` walks to instead of your shop, or "" when they come in.
func diverts(c: Customer, rng: RandomNumberGenerator) -> String:
	if not Tutorial.first_day_done:
		return ""
	_share_sum += share_for(c)
	_share_n += 1
	if rng.randf() >= divert_odds(c):
		return ""
	# they go to whichever rival suits them, weighted the same way
	var seg := _segment(c)
	var weights := {}
	var total := 0.0
	for id in state:
		if is_open(id):
			weights[id] = exp(utility(id, c.kind, seg))
			total += weights[id]
	var roll := rng.randf() * total
	for id in weights:
		roll -= weights[id]
		if roll <= 0.0:
			return id
	return weights.keys().back() if not weights.is_empty() else ""


## Books a customer who went to rival `id` instead.
func lose(c: Customer, id: String) -> void:
	lost_today[id] = int(lost_today.get(id, 0)) + 1
	Shop.note("lost_to_rival")
	var why := "better prices" if c.kind == "buyer" and premium_of(id) < Shop.sell_premium \
		or c.kind == "seller" and buy_of(id) > Shop.buy_percent else "a better name"
	if id == "pawn" and c.kind == "seller" and _segment(c) != "":
		why = "no questions asked"
	Shop.log_event("%s went to %s instead (%s)." % [c.name, SHOPS[id].short, why])


## Shops in town by net worth, biggest first: [{"id", "name", "worth"}], "you" for the player.
func ranking() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": "you", "name": "Your shop", "worth": Shop.net_worth()}]
	for id in state:
		out.append({"id": id, "name": SHOPS[id].name, "worth": worth_of(id)})
	out.sort_custom(func(a, b): return a.worth > b.worth)
	return out


## Your place in town by net worth, 1 for the biggest.
func rank() -> int:
	var r := ranking()
	for i in r.size():
		if r[i].id == "you":
			return i + 1
	return r.size()


func ad_cost() -> float:
	return AD_COST * Progress.deal_size()


func can_run_ad() -> bool:
	return ad_days <= 0 and Day.phase == Day.MORNING and Shop.cash >= ad_cost()


## Takes out an ad in the town paper: more customers pick your shop for a few days.
func run_ad() -> bool:
	if not can_run_ad():
		return false
	Day.add_expense("Newspaper ad", ad_cost())
	ad_days = AD_DAYS
	Shop.log_event("Your ad runs in the paper for %d days." % AD_DAYS, "good")
	changed.emit()
	return true


## Sets your prices a point better than Sterling's for sellers and buyers.
func beat_sterling() -> void:
	Shop.set_buy_percent(buy_of("sterling") + 0.01)
	Shop.set_sell_premium(premium_of("sterling") - 0.01)
	Shop.log_event("Your board now pays %d%% and sells at +%d%%." % [roundi(Shop.buy_percent * 100.0), roundi(Shop.sell_premium * 100.0)])
	changed.emit()


func can_tip_off() -> bool:
	return move_of("pawn") == "fencing" and is_open("pawn")


## Tells the police about the pawn shop's stolen goods: they raid it and shut it for a while.
func tip_off() -> bool:
	if not can_tip_off():
		return false
	var st: Dictionary = state.pawn
	st.move = ""
	st.move_days = 0
	st.closed = RAID_DAYS
	st.stars = maxf(0.5, float(st.stars) - 0.5)
	st.worth = float(st.worth) * 0.85
	Shop.adjust_reputation(TIP_REPUTATION)
	Shop.note("tipped_off")
	var line := "Police raided Lucky's Pawn on your tip. It's shut for %d days." % RAID_DAYS
	news = [line]
	Shop.log_event(line, "good")
	changed.emit()
	return true


## Morning: last night's moves wear off, Sterling reprices against you and new moves start.
func _on_day_started(day: int) -> void:
	lost_today.clear()
	_share_sum = 0.0
	_share_n = 0
	if day == last_morning:
		return
	last_morning = day
	news.clear()
	ad_days = maxi(0, ad_days - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7841 + 3
	for id in state:
		var st: Dictionary = state[id]
		if int(st.closed) > 0:
			st.closed = int(st.closed) - 1
			if int(st.closed) == 0:
				news.append("Lucky's Pawn has reopened after the raid.")
		if int(st.move_days) > 0:
			st.move_days = int(st.move_days) - 1
			if int(st.move_days) == 0:
				_end_move(id)
	_reprice_sterling()
	if not Tutorial.first_day_done:
		changed.emit()
		return
	for id in state:
		var st: Dictionary = state[id]
		if st.move == "" and is_open(id) and day >= int(MOVE_FROM_DAY[id]) and rng.randf() < float(MOVE_ODDS[id]):
			var options := MOVES.keys().filter(func(m): return MOVES[m].rival == id)
			_start_move(id, options[rng.randi() % options.size()])
	for id in state:
		if move_of(id) != "" and MOVES[move_of(id)].days > 0 and not _headline_shown(id):
			news.append("%s (%d day%s left)" % [MOVES[move_of(id)].news, int(state[id].move_days), "" if int(state[id].move_days) == 1 else "s"])
	changed.emit()


## Starts rival `id`'s `move` now, whatever the odds: the story uses it when Victor
## Sterling declares a price war. Does nothing while the rival is busy or shut.
func start_move(id: String, move: String) -> void:
	if not state.has(id) or not MOVES.has(move) or MOVES[move].rival != id or move_of(id) != "" or not is_open(id):
		return
	_start_move(id, move)
	changed.emit()


func _headline_shown(id: String) -> bool:
	var text: String = MOVES[move_of(id)].news
	return news.any(func(n): return n.begins_with(text))


func _start_move(id: String, move: String) -> void:
	var m: Dictionary = MOVES[move]
	var st: Dictionary = state[id]
	if int(m.days) > 0:
		st.move = move
		st.move_days = int(m.days)
		news.append("%s (%d days)" % [m.news, int(m.days)])
		return
	# a smear happens at once
	if Shop.reputation >= float(m.get("shrug_stars", 99.0)):
		news.append(m.shrugged)
		return
	Shop.adjust_reputation(float(m.get("reputation", 0.0)))
	news.append(m.news)


func _end_move(id: String) -> void:
	var st: Dictionary = state[id]
	var m: Dictionary = MOVES.get(st.move, {})
	st.worth = float(st.worth) + float(m.get("worth", 0.0))
	if st.move == "price_war":
		news.append("Sterling's price war is over.")
	st.move = ""


## Sterling watches your share: when you are winning it cuts its margins a point,
## when it is winning it takes them back. Its stars creep up as the town grows.
func _reprice_sterling() -> void:
	var st: Dictionary = state.sterling
	var base: Dictionary = SHOPS.sterling
	if last_share > FAIR_SHARE + 0.05:
		if float(st.premium) - STERLING_PREMIUM.x > STERLING_BUY.y - float(st.buy):
			st.premium = snappedf(float(st.premium) - 0.01, 0.01)
		else:
			st.buy = snappedf(float(st.buy) + 0.01, 0.01)
	elif last_share < FAIR_SHARE - 0.05:
		if float(st.premium) < float(base.premium):
			st.premium = snappedf(float(st.premium) + 0.01, 0.01)
		elif float(st.buy) > float(base.buy):
			st.buy = snappedf(float(st.buy) - 0.01, 0.01)
	st.buy = clampf(float(st.buy), STERLING_BUY.x, STERLING_BUY.y)
	st.premium = clampf(float(st.premium), STERLING_PREMIUM.x, STERLING_PREMIUM.y)
	st.stars = minf(STERLING_STARS_MAX, float(base.stars) + Shop.day * 0.01)


## Night: the rivals' books. Each grows a little, plus what the customers it took from
## you brought in. Passing one is worth a line in the summary.
func _on_day_ended(_day: int, report: Dictionary) -> void:
	last_share = _share_sum / _share_n if _share_n > 0 else overall_share()
	var bits: Array[String] = []
	for id in state:
		var st: Dictionary = state[id]
		var n := int(lost_today.get(id, 0))
		st.worth = float(st.worth) * (1.0 + float(SHOPS[id].growth)) + n * float(SHOPS[id].deal)
		if n > 0:
			bits.append("%d to %s" % [n, SHOPS[id].short])
	if not bits.is_empty():
		var total := 0
		for id in lost_today:
			total += int(lost_today[id])
		report.lines.append("%d customer%s went to the competition (%s). See the town map." % [total, "" if total == 1 else "s", ", ".join(bits)])
	for id in state:
		if not passed.has(id) and Shop.net_worth() > worth_of(id):
			passed.append(id)
			report.lines.append("Your shop is now bigger than %s!" % SHOPS[id].name)
			Shop.log_event("You passed %s in net worth." % SHOPS[id].name, "good")
	changed.emit()


func _segment(c: Customer) -> String:
	if c.kind != "seller":
		return ""
	if c.archetype == "shady":
		return "shady"
	return "jewellery" if c.piece else ""


func to_dict() -> Dictionary:
	return {"shops": state.duplicate(true), "ad_days": ad_days, "passed": passed.duplicate(), "last_share": last_share,
		"last_morning": last_morning, "news": news.duplicate()}


func from_dict(d: Dictionary) -> void:
	reset()
	var saved: Dictionary = d.get("shops", {})
	for id in saved:
		if state.has(id) and typeof(saved[id]) == TYPE_DICTIONARY:
			for key in state[id]:
				if saved[id].has(key):
					var v = saved[id][key]
					state[id][key] = str(v) if key == "move" else (int(v) if key in ["move_days", "closed"] else float(v))
	ad_days = int(d.get("ad_days", 0))
	for id in d.get("passed", []):
		if SHOPS.has(id):
			passed.append(str(id))
	last_share = float(d.get("last_share", FAIR_SHARE))
	last_morning = int(d.get("last_morning", 0))
	for line in d.get("news", []):
		news.append(str(line))
	changed.emit()
