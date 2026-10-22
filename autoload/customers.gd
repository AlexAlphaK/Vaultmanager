extends Node
## Who walks into the shop. Every customer gets an archetype with its own personality:
##   walk_in     everyday folk, some bargain a little
##   haggler     opens high (or low), comes round a step each time you hold firm
##   crypto_bro  big gold orders, short fuse; buys after crypto rallies, sells after crashes
##   collector   wants one exact coin and pays well over spot for it
##   shady       cheap, nervous, and usually carrying fakes
## The shop's regulars come back every few days, each with a short story told over
## their visits. Treat them well and the story ends with a reward; treat them badly and
## they find another shop. Regulars are saved with the game.

## Odds that an everyday arrival is a regular whose next visit is due.
const REGULAR_ODDS := 0.2
const HAGGLER_LINES := ["I never pay sticker. Let's talk.", "Everything's negotiable, friend.",
	"Let's not insult each other. What's your real number?"]
const CRYPTO_NAMES := ["Chad", "Brayden", "Kyle.eth", "Tanner", "Jaxon", "Moonboy Mike"]
const CRYPTO_BUY_LINES := ["Just took profits. Turn it into something shiny.", "Gold's the OG blockchain, bro.",
	"Diversifying my bag. Need gold, like, now."]
const CRYPTO_SELL_LINES := ["Got margin-called. Need fiat, fast.", "Buying the crypto dip. Need cash for it, bro.",
	"Don't ask about my portfolio. Just buy these."]
const COLLECTOR_NAMES := ["Professor Hale", "Mr. Whitcombe", "Dr. Ng", "Mrs. Pemberton-Cross"]
const COLLECTOR_LINES := ["I collect %s coins. Nothing else will do.", "Any %s coins? Nice strike, no spots, please.",
	"%s coins for the collection. I pay for quality."]
const SHADY_NAMES := ["Slick", "\"Mr. Smith\"", "Some Guy", "Ricky", "Two-Phones Tony"]
const SHADY_LINES := ["Cash only. No paperwork. You understand.", "Quick deal, yeah? I'm double parked.",
	"Priced to move. Don't ask where they're from.", "My cousin's coins. He's... away."]
const TAGS := {"haggler": "haggler", "crypto_bro": "crypto bro", "collector": "collector", "shady": "looks nervous"}

const LEV_LOOK := {"skin": "#e3b48a", "hair": "#d8d8d0", "hair_style": 2, "shirt": "#6b5a40", "top": 1,
	"pants": "#4a3a2a", "glasses": true, "beard": true, "hat": false, "apron": false}
const OKAFOR_LOOK := {"skin": "#7a4a2c", "hair": "#8c8c8c", "hair_style": 3, "shirt": "#c0507a", "top": 0,
	"pants": "#3b4a6b", "glasses": true, "beard": false, "hat": false, "apron": false}
const ADA_LOOK := {"skin": "#7a4a2c", "hair": "#1a1a1a", "hair_style": 4, "shirt": "#2f8f8f", "top": 2,
	"pants": "#2f3442", "glasses": false, "beard": false, "hat": false, "apron": false}
const CHAD_LOOK := {"skin": "#f2cfa8", "hair": "#e2cc8a", "hair_style": 0, "shirt": "#30406a", "top": 2,
	"pants": "#5a5f6a", "glasses": false, "beard": false, "hat": false, "apron": false, "shades": true, "chain": true}
const VANCE_LOOK := {"skin": "#c98f62", "hair": "#5a3418", "hair_style": 3, "shirt": "#556070", "top": 1,
	"pants": "#1f1f24", "glasses": true, "beard": false, "hat": false, "apron": false}
const VINNIE_LOOK := {"skin": "#e3b48a", "hair": "#2a1a10", "hair_style": 0, "shirt": "#30303a", "top": 1,
	"pants": "#1f1f24", "glasses": false, "beard": true, "hat": true, "apron": false, "shades": true}
const RUIZ_LOOK := {"skin": "#a06a42", "hair": "#1a1a1a", "hair_style": 0, "shirt": "#6b5a40", "top": 1,
	"pants": "#4a3a2a", "glasses": false, "beard": false, "hat": false, "apron": false}

## Each regular's story, one beat per visit. A beat is a deal ("seller" or "buyer") or a
## "visit" (they only talk). Beat keys: item (coin id), qty, say, and optionally name and
## look (someone else comes in their place), reserve (share of melt a seller takes),
## premium (what a buyer pays over spot), exact (buyer wants that coin only, default true),
## haggle [open, step], fake (the coins are counterfeit), after (summary line when the beat
## goes well) and reward {"reputation", "cash", "log"} paid when the deal is done.
## A visit with if_caught plays its own lines when the player caught at least that many
## of this regular's fakes, and the lines in `else` otherwise.
## `persistent` regulars move on whatever you do; others only after a good deal.
const REGULARS: Array[Dictionary] = [
	{"id": "lev", "name": "Grandpa Lev", "look": LEV_LOOK, "min_day": 1, "gap": 2, "beats": [
		{"kind": "seller", "item": "silver_eagle", "qty": 12, "reserve": 0.9,
			"say": "My Mira bought one of these every birthday. Time to let a few go.",
			"after": "Grandpa Lev sold you the first of his late wife's coins. He'll be back."},
		{"kind": "seller", "item": "gold_maple", "qty": 1, "reserve": 0.9,
			"say": "More of Mira's collection. She'd want it to go to someone honest.",
			"after": "Grandpa Lev told you how Mira saved a coin from every trip they took."},
		{"kind": "seller", "item": "platinum_eagle", "qty": 1, "reserve": 0.92,
			"say": "Her favourite. I kept this one till last.",
			"after": "Grandpa Lev sold you the last of Mira's coins. He looked lighter, somehow."},
		{"kind": "buyer", "item": "gold_eagle", "qty": 1, "premium": 0.1,
			"say": "My grandson graduates Friday. I want to buy him a gold coin, and I want it from you.",
			"reward": {"reputation": 0.3, "log": "Grandpa Lev told the whole bowling league about your shop."}},
	]},
	{"id": "okafor", "name": "Mrs. Okafor", "look": OKAFOR_LOOK, "min_day": 1, "gap": 2, "beats": [
		{"kind": "buyer", "item": "silver_eagle", "qty": 5, "premium": 0.07, "exact": false,
			"say": "Silver for my granddaughter Ada's college fund. Five, please.",
			"after": "Mrs. Okafor started a college fund in silver for her granddaughter."},
		{"kind": "buyer", "item": "silver_maple", "qty": 10, "premium": 0.07, "exact": false,
			"say": "Ada got into the science programme! Ten more for the fund.",
			"after": "Mrs. Okafor's granddaughter got into the science programme."},
		{"kind": "buyer", "item": "silver_britannia", "qty": 10, "premium": 0.08, "exact": false,
			"say": "Last top-up before she goes. Ten more, and wish her luck.",
			"after": "Mrs. Okafor finished Ada's college fund."},
		{"kind": "buyer", "item": "gold_maple", "qty": 1, "premium": 0.09, "name": "Ada Okafor", "look": ADA_LOOK,
			"say": "Grandma's silver paid for my first year. Now I'm starting my own stack.",
			"reward": {"reputation": 0.25, "log": "Ada Okafor is your newest customer. Her grandma is very proud."}},
	]},
	{"id": "chad", "name": "Chad", "look": CHAD_LOOK, "min_day": 2, "gap": 2, "beats": [
		{"kind": "buyer", "item": "gold_eagle", "qty": 2, "premium": 0.1,
			"say": "Took some profits, bro. Gold's the original blockchain.",
			"after": "Chad bought gold to 'diversify his bag'."},
		{"kind": "seller", "item": "gold_eagle", "qty": 2, "reserve": 0.86, "haggle": [0.06, 0.02],
			"say": "Got liquidated. Need those eagles turned back into fiat. Don't tell anyone.",
			"after": "Chad sold his gold back after a bad week in crypto."},
		{"kind": "buyer", "item": "krugerrand", "qty": 4, "premium": 0.12,
			"say": "Back from the dead! Diamond hands. Give me your shiniest.",
			"reward": {"reputation": 0.2, "log": "Chad posted your shop to all his followers. 'Based gold guy.'"}},
	]},
	{"id": "vance", "name": "Dr. Vance", "look": VANCE_LOOK, "min_day": 3, "gap": 2, "beats": [
		{"kind": "buyer", "item": "krugerrand", "qty": 1, "premium": 0.15,
			"say": "I collect Krugerrands. Do you have one with a crisp springbok?",
			"after": "Dr. Vance, a collector, added your Krugerrand to her cabinet."},
		{"kind": "buyer", "item": "silver_britannia", "qty": 3, "premium": 0.16,
			"say": "Britannias next. Three, for a display on the history of coinage.",
			"after": "Dr. Vance is building a museum display on the history of coinage."},
		{"kind": "buyer", "item": "platinum_eagle", "qty": 1, "premium": 0.18,
			"say": "The centrepiece: a platinum eagle. The museum opens next week.",
			"after": "Dr. Vance's display opens at the town museum next week."},
		{"kind": "seller", "item": "gold_eagle", "qty": 3, "reserve": 0.8,
			"say": "My old teacher's eagles. I want them in good hands, not a fair price.",
			"reward": {"reputation": 0.3, "log": "The museum display credits your shop. People are talking."}},
	]},
	{"id": "vinnie", "name": "Vinnie", "look": VINNIE_LOOK, "min_day": 2, "gap": 2, "persistent": true, "beats": [
		{"kind": "seller", "item": "gold_eagle", "qty": 2, "reserve": 0.8, "fake": true,
			"say": "Fresh from my uncle's estate. Very fresh. Cash, yeah?"},
		{"kind": "seller", "item": "silver_eagle", "qty": 20, "reserve": 0.78, "fake": true,
			"say": "New batch. Same uncle. Different estate."},
		{"kind": "seller", "item": "gold_maple", "qty": 3, "reserve": 0.8, "fake": true,
			"say": "Last time, I promise. These ones are definitely real."},
		{"kind": "visit", "name": "Detective Ruiz", "look": RUIZ_LOOK, "if_caught": 2,
			"say": "We picked up Vinnie's counterfeit ring. Your tips helped. The town's reward is yours.",
			"reward": {"reputation": 0.3, "cash": 2000.0, "log": "Detective Ruiz paid you the reward for Vinnie's fakes."},
			"else": {"say": "Vinnie's been passing fakes all over town. Some ended up in your vault. Test your coins.",
				"reward": {"reputation": -0.1, "log": "Detective Ruiz warned you about buying from Vinnie."}}},
	]},
]

## Per regular: {"beat", "last_day", "loyalty", "caught", "burned", "done", "gone"}.
var state := {}
## Story lines for tonight's summary.
var _today: Array[String] = []
var _by_id := {}


func _ready() -> void:
	for reg in REGULARS:
		_by_id[reg.id] = reg
	reset()
	SaveGame.register("customers", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(func(_d): _today.clear())
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	state.clear()
	for reg in REGULARS:
		state[reg.id] = _fresh()
	_today.clear()


## The next customer through the door. `event` is from MarketEvents.customer_event().
func next_customer(rng: RandomNumberGenerator, event := {}) -> Customer:
	if event.is_empty():
		var visitor := Story.next_customer(rng)
		if visitor:
			return visitor
	var collector := Orders.next_customer(rng, event)
	if collector:
		return collector
	var grader := CoinGrade.next_customer(rng, event)
	if grader:
		return grader
	if event.is_empty() and rng.randf() < REGULAR_ODDS:
		var due := due_regulars()
		if not due.is_empty():
			return regular_customer(due[rng.randi() % due.size()], rng)
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng, event)
	apply_archetype(c, pick_archetype(rng, event), rng, event)
	Orders.maybe_rare_seller(c, rng)
	return c


## Regulars whose next visit is due today.
func due_regulars() -> Array[String]:
	var out: Array[String] = []
	for reg in REGULARS:
		var st: Dictionary = state[reg.id]
		if not st.done and Shop.day >= int(reg.min_day) and Shop.day - int(st.last_day) >= int(reg.gap):
			out.append(reg.id)
	return out


func pick_archetype(rng: RandomNumberGenerator, event := {}) -> String:
	var day := Shop.day
	if not event.is_empty():
		if event.has("archetype"):
			return event.archetype
		return "crypto_bro" if String(event.get("measure", "")).begins_with("crypto") and rng.randf() < 0.5 else "walk_in"
	var btc := absf(MarketEvents.move_of("crypto:BTC"))
	var weights := {
		"walk_in": 1.0,
		"haggler": 0.2,
		"shady": 0.08 + minf(0.08, day * 0.01) if day >= 2 else 0.0,
		"crypto_bro": (0.07 + (0.1 if btc >= 3.0 else 0.0)) if day >= 2 else 0.0,
		"collector": 0.06 + Shop.reputation * 0.01 if day >= 3 and Shop.reputation >= 2.0 else 0.0,
	}
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for id in weights:
		roll -= weights[id]
		if roll < 0.0:
			return id
	return "walk_in"


## Gives a fresh customer the personality of archetype `id`.
func apply_archetype(c: Customer, id: String, rng: RandomNumberGenerator, event := {}) -> void:
	c.archetype = id
	var look := PeopleArt.random_look(rng)
	match id:
		"walk_in":
			# about half of everyday customers will come round a little
			if rng.randf() < 0.5 and not c.piece:
				c.set_haggle(0.02, 0.01)
			return
		"haggler":
			if c.kind == "seller":
				c.reserve = maxf(0.74, c.reserve - 0.02)
				c.set_haggle(rng.randf_range(0.05, 0.08), rng.randf_range(0.015, 0.025))
			else:
				c.max_premium += 0.02
				c.set_haggle(rng.randf_range(0.03, 0.05), rng.randf_range(0.01, 0.015))
			c.max_patience *= 1.2
			if event.is_empty():
				c.say = HAGGLER_LINES[rng.randi() % HAGGLER_LINES.size()]
		"crypto_bro":
			c.piece = null
			c.bar = null
			c.fake = ""
			c.name = CRYPTO_NAMES[rng.randi() % CRYPTO_NAMES.size()]
			if event.is_empty():
				c.kind = "seller" if MarketEvents.move_of("crypto:BTC") <= -2.0 else "buyer"
			c.item = _coin_of("XAU", rng, c.item)
			c.qty = maxi(1, roundi(rng.randi_range(2, 5) * Progress.deal_size()))
			if c.kind == "buyer":
				c.max_premium = rng.randf_range(0.08, 0.13) + Progress.effect("premium")
				c.ceiling_premium = c.max_premium
				c.say = CRYPTO_BUY_LINES[rng.randi() % CRYPTO_BUY_LINES.size()]
			else:
				c.reserve = rng.randf_range(0.82, 0.88)
				c.floor_reserve = c.reserve
				c.set_haggle(0.04, 0.02)
				c.say = CRYPTO_SELL_LINES[rng.randi() % CRYPTO_SELL_LINES.size()]
			c.max_patience *= 0.6
			look.top = 2
			look.shades = true
			look.chain = true
		"collector":
			c.kind = "buyer"
			c.piece = null
			c.bar = null
			c.fake = ""
			c.wanted_exact = true
			c.name = COLLECTOR_NAMES[rng.randi() % COLLECTOR_NAMES.size()]
			# a rare coin in the vault draws them first, at a collector's price
			var rare := Shop.rare_list().filter(func(it): return Shop.spare_of(it) > 0)
			if not rare.is_empty() and rng.randf() < 0.7:
				c.item = rare[rng.randi() % rare.size()]
				c.qty = 1
				c.max_premium = c.item.collector_premium * rng.randf_range(0.8, 1.0) + float(event.get("premium", 0.0))
				c.ceiling_premium = c.max_premium
				c.haggle = 0.0
				c.max_patience *= 1.4
				c.say = COLLECTOR_LINES[rng.randi() % COLLECTOR_LINES.size()] % c.item.display_name
				look.glasses = true
				look.top = 1
				c.patience = c.max_patience
				c.set_look(look)
				return
			# usually after something you have
			var held := Shop.coin_list().filter(func(it): return Shop.count_of_item(it) > 0)
			c.item = held[rng.randi() % held.size()] if not held.is_empty() and rng.randf() < 0.6 \
				else Shop.coin_list()[rng.randi() % Shop.coin_list().size()]
			c.qty = rng.randi_range(2, 6) if c.item.metal == "XAG" else rng.randi_range(1, 2)
			c.max_premium = rng.randf_range(0.12, 0.18) + Progress.effect("premium") + float(event.get("premium", 0.0))
			c.ceiling_premium = c.max_premium
			c.haggle = 0.0
			c.max_patience *= 1.4
			c.say = COLLECTOR_LINES[rng.randi() % COLLECTOR_LINES.size()] % c.item.display_name
			look.glasses = true
			look.top = 1
		"shady":
			c.kind = "seller"
			c.piece = null
			c.bar = null
			c.assessed = {}
			c.name = SHADY_NAMES[rng.randi() % SHADY_NAMES.size()]
			c.fake = ""
			var kinds := Counterfeit.kinds_for(c.item.metal, Shop.day)
			if not kinds.is_empty() and rng.randf() < 0.7:
				c.fake = kinds[rng.randi() % kinds.size()]
			# suspiciously cheap, and in no mood to bargain
			c.reserve = rng.randf_range(0.76, 0.84)
			c.floor_reserve = c.reserve
			c.haggle = 0.0
			c.max_patience *= 0.6
			c.say = SHADY_LINES[rng.randi() % SHADY_LINES.size()]
			look.hat = true
			look.shades = rng.randf() < 0.5
			look.top = 1
			look.shirt = "#30303a"
	c.patience = c.max_patience
	c.set_look(look)


## The customer for regular `id`'s next visit.
func regular_customer(id: String, rng: RandomNumberGenerator) -> Customer:
	var reg: Dictionary = _by_id[id]
	var st: Dictionary = state[id]
	var b := beat_of(id)
	st.last_day = Shop.day
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng)
	c.archetype = "regular"
	c.regular_id = id
	c.beat = int(st.beat)
	c.name = b.get("name", reg.name)
	c.set_look(b.get("look", reg.look))
	c.kind = b.kind
	c.piece = null
	c.bar = null
	c.assessed = {}
	c.fake = ""
	c.haggle = 0.0
	c.item = Shop.coins.get(b.get("item", ""), c.item)
	c.qty = int(b.get("qty", 1))
	c.say = b.say
	# regulars who like you give you a little better deal
	var trust := clampf(float(st.loyalty) * 0.01, -0.03, 0.04)
	match c.kind:
		"seller":
			c.reserve = float(b.get("reserve", 0.9)) - trust
			c.floor_reserve = c.reserve
			if b.has("haggle"):
				c.set_haggle(b.haggle[0], b.haggle[1])
			if b.get("fake", false):
				var kinds := Counterfeit.kinds_for(c.item.metal, 99)
				c.fake = kinds[rng.randi() % kinds.size()]
		"buyer":
			c.max_premium = float(b.get("premium", 0.08)) + trust + Progress.effect("premium")
			c.ceiling_premium = c.max_premium
			c.wanted_exact = b.get("exact", true)
		"visit":
			c.note = _reward_text(b.get("reward", {}))
	c.max_patience = 9999.0 if c.kind == "visit" else c.max_patience * 1.5
	c.patience = c.max_patience
	return c


## The beat regular `id` is on, with the `else` lines swapped in when they apply.
func beat_of(id: String) -> Dictionary:
	var reg: Dictionary = _by_id[id]
	var st: Dictionary = state[id]
	var b: Dictionary = reg.beats[mini(int(st.beat), reg.beats.size() - 1)]
	if b.has("if_caught") and int(st.caught) < int(b.if_caught):
		var merged := b.duplicate()
		merged.merge(b.else, true)
		return merged
	return b


## The shop log line for someone walking in.
func arrival(c: Customer) -> String:
	if c.regular_id != "" and c.beat > 0 and c.name == _by_id[c.regular_id].name:
		return "%s is back." % c.name
	return "%s walked in." % c.name


## A short word on the counter card about who this is, or "".
func tag(c: Customer) -> String:
	if c.story != "":
		return Story.tag(c)
	if c.kind == "seller" and c.item and c.item.rare and not c.piece and not c.bar and c.archetype != "shady":
		return "old coin"
	if c.regular_id != "":
		return "regular" if c.name == _by_id[c.regular_id].name else ""
	return TAGS.get(c.archetype, "")


## The shop calls this as each customer leaves. Moves regulars' stories along.
func on_leave(c: Customer) -> void:
	Orders.on_leave(c)
	Calendar.on_leave(c)
	Story.on_leave(c)
	if c.regular_id == "" or not state.has(c.regular_id):
		return
	var reg: Dictionary = _by_id[c.regular_id]
	var st: Dictionary = state[c.regular_id]
	if st.done or c.beat != int(st.beat):
		return
	var b := beat_of(c.regular_id)
	if c.kind == "visit":
		_reward(b)
		_advance(reg, st)
	elif c.caught:
		st.caught += 1
		_story("You caught %s's %s fakes. He'll try again." % [c.name, c.item.display_name] if st.beat < reg.beats.size() - 2 \
			else "You caught %s's fakes again. Word is the police are interested." % c.name)
		_advance(reg, st)
	elif c.dealt:
		if c.fake != "":
			st.burned += 1
			_story("%s sold you fakes and walked off laughing." % c.name)
		else:
			st.loyalty += 1
			if b.has("after"):
				_story(b.after)
			if b.has("reward"):
				_reward(b)
		_advance(reg, st)
	elif c.kind == "buyer" and c.stock_have() < c.qty:
		# no harm done: they'll come back when you have it
		Shop.log_event("%s will come back when you have %s in stock." % [c.name, c.item.display_name])
	elif reg.get("persistent", false):
		_advance(reg, st)
	else:
		st.loyalty -= 1
		if st.loyalty <= -2:
			st.done = true
			st.gone = true
			Shop.log_event("%s has found another shop." % c.name, "bad")
			_story("%s won't be coming back." % c.name)


func to_dict() -> Dictionary:
	return {"regulars": state.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	reset()
	var saved: Dictionary = d.get("regulars", {})
	for id in saved:
		if state.has(id) and typeof(saved[id]) == TYPE_DICTIONARY:
			for key in state[id]:
				if saved[id].has(key):
					state[id][key] = saved[id][key] if typeof(state[id][key]) == TYPE_BOOL else int(saved[id][key])


func _fresh() -> Dictionary:
	return {"beat": 0, "last_day": -99, "loyalty": 0, "caught": 0, "burned": 0, "done": false, "gone": false}


func _advance(reg: Dictionary, st: Dictionary) -> void:
	st.beat += 1
	if st.beat >= reg.beats.size():
		st.done = true


func _reward(b: Dictionary) -> void:
	var r: Dictionary = b.get("reward", {})
	if r.is_empty():
		return
	Shop.adjust_reputation(float(r.get("reputation", 0.0)))
	if float(r.get("cash", 0.0)) > 0.0:
		Day.add_income("Reward", float(r.cash))
	var good := float(r.get("reputation", 0.0)) >= 0.0
	Shop.log_event(r.get("log", ""), "good" if good else "bad")
	_story(r.get("log", ""))


func _reward_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	if float(r.get("cash", 0.0)) > 0.0:
		parts.append(Market.format_money(r.cash))
	var rep := float(r.get("reputation", 0.0))
	if rep != 0.0:
		parts.append("%s%.1f stars" % ["+" if rep > 0.0 else "", rep])
	return ("Reward: " if float(r.get("reputation", 0.0)) >= 0.0 else "") + ", ".join(parts)


## Adds a line to tonight's summary.
func add_story(line: String) -> void:
	_story(line)


func _story(line: String) -> void:
	if line != "":
		_today.append(line)


func _coin_of(metal: String, rng: RandomNumberGenerator, fallback: BullionItem) -> BullionItem:
	var choices := Shop.coin_list().filter(func(it): return it.metal == metal)
	return choices[rng.randi() % choices.size()] if not choices.is_empty() else fallback


func _on_day_ended(_day: int, report: Dictionary) -> void:
	for line in _today:
		report.lines.append(line)
	_today.clear()
