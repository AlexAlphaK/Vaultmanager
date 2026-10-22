class_name Coach
extends CanvasLayer
## The tutorial on the shop floor. On day 1 of a new game it walks the player through
## the morning, three scripted customers (a genuine seller to test and buy from, a
## nervous seller with fake coins to catch, and a buyer to sell to), the vault lock-up
## and the end-of-day summary. While it scripts the counter the shop clock waits and
## nobody else comes in. Later it gives a short intro the first time the jewellery and
## bar benches open. Every guided card has Skip tutorial. What has been shown lives in
## the Tutorial autoload, so it is saved with the game.

const CARD_W := 158
## Where cards sit: over the counter card while the shop is shut, over the room
## while a customer is at the counter, and over the scope on the coin bench.
const AT_SIDE := Vector2(318, 84)
const AT_ROOM := Vector2(8, 150)
const AT_BENCH := Vector2(6, 16)
## Things the cards point at, in screen pixels (see hud.gd and the bench panels).
const TICKER := Rect2(1, 1, 336, 10)
const MARGINS := Rect2(318, 202, 158, 26)
const COUNTER := Rect2(318, 82, 158, 116)
const TEST_BUTTON := Rect2(320, 177, 50, 12)
const OFFER_BUTTON := Rect2(372, 177, 52, 12)
const SELL_BUTTON := Rect2(320, 177, 70, 12)
const COIN_TOOLS := Rect2(320, 130, 156, 26)
const COIN_READINGS := Rect2(320, 45, 156, 55)
const GENUINE_BUTTON := Rect2(320, 236, 76, 13)
const FAKE_BUTTON := Rect2(400, 236, 76, 13)
const VAULT_SAFES := Rect2(318, 76, 158, 42)

var shop: Node
## True while the first day is being guided.
var guiding := false
## The guided step, for example "welcome", "june_counter" or "slick_call".
var step := ""

var _scripting := false
var _cast := {} # "june", "slick", "priya" -> Customer
var _who := "" # which of the cast is in the shop now
var _intro_id := "" # the bench intro on show, if any
var _bench: Control
var _vault: Control
var _target: Variant = null # a Rect2, a Callable returning one, or null
var _root: Control
var _card: PanelContainer
var _title: Label
var _body: Label
var _row: HBoxContainer
var _time := 0.0


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_target)
	add_child(_root)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.box(Color("#2b2117"), Pal.GOLD, 5, 4))
	_root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_card.add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Pal.GOLD)
	box.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(CARD_W - 10, 0)
	box.add_child(_body)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	box.add_child(_row)
	_card.visible = false


## Hooks the coach up to the shop. Call once the save is loaded.
func attach(s: Node) -> void:
	shop = s
	shop.bench_opened.connect(_on_bench_opened)
	shop.bench_closed.connect(_on_bench_closed)
	shop.customer_left.connect(_on_customer_left)
	shop.vault_opened.connect(_on_vault_opened)
	shop.summary_shown.connect(_on_summary_shown)
	Day.day_started.connect(func(_d): _on_morning.call_deferred())
	Day.shop_opened.connect(func(_d): _on_shop_opened())
	restart()


## Starts the guided first day if this is a fresh game. An older save past day 1
## counts as having done it.
func restart() -> void:
	if Shop.day > 1:
		Tutorial.first_day_done = true
	guiding = not Tutorial.first_day_done
	_scripting = false
	_cast.clear()
	_who = ""
	step = ""
	_hide()


## True while the coach is scripting the counter: the clock waits and the door stays shut.
func holds_clock() -> bool:
	return guiding and _scripting


func skip() -> void:
	Tutorial.skip_all()
	guiding = false
	_scripting = false
	step = ""
	if _vault and is_instance_valid(_vault):
		_vault.paused = false
	_hide()
	Shop.log_event("Tutorial skipped. Good luck!")


func _process(delta: float) -> void:
	_time += delta
	if _target != null:
		_root.queue_redraw()
	if not guiding:
		return
	match step:
		"june_walk", "slick_walk", "priya_walk":
			var c: Customer = _cast.get(_who)
			if c and shop._front() == c:
				_at_counter()
		"june_tools":
			if _bench and _bench.used.has("scale") and _bench.used.has("calipers") \
					and _bench._time - _bench._t.calipers > 1.6 and _bench._time - _bench._t.scale > 1.1:
				step = "june_call"
				_show("Read the bench", "Weight, diameter and thickness all match the spec. This is a real Silver Eagle. Press Genuine.",
					AT_BENCH, GENUINE_BUTTON)
		"slick_tools":
			if _bench and _bench.used.has("magnet") and _bench._time - _bench._t.magnet > 1.4:
				step = "slick_call"
				_show("Caught in the act", "Real silver only drags a little. This coin snapped to the magnet: it's plated steel. Press Fake.",
					AT_BENCH, FAKE_BUTTON)


# ---------------------------------------------------------------- the first day

func _on_morning() -> void:
	if guiding and Shop.day > 1:
		# moved on without pressing Finish on the last card
		Tutorial.finish_first_day()
		guiding = false
		_hide()
	if not guiding:
		return
	step = "welcome"
	_show("Welcome to your shop", "You buy and sell gold, silver and platinum at real market prices. Your goal: the biggest store in town. Let's serve your first customers together.",
		AT_SIDE, null, "Show me", _prices)


func _prices() -> void:
	step = "prices"
	_show("Live prices", "The ticker shows today's spot prices from the real market. Every coin's value follows them, so the same coin is worth more on some days than others.",
		AT_SIDE, TICKER, "Next", _margins)


func _margins() -> void:
	step = "margins"
	_show("Your margins", "You pay sellers a little under melt and charge buyers a little over it. That gap is your profit. The -/+ buttons change both, but push too far and customers walk.",
		AT_SIDE, MARGINS, "Next", _open)


func _open() -> void:
	step = "open"
	_show("Open up", "Press Open the shop when you're ready.", AT_SIDE, _open_button_rect)


func _open_button_rect() -> Variant:
	# the button is freed while another morning page (upgrades, restock...) is open
	var b = shop.hud._panels.open_button
	if not is_instance_valid(b) or not b.is_visible_in_tree():
		return null
	return (b as Button).get_global_rect()


func _on_shop_opened() -> void:
	if not guiding or Shop.day != 1:
		return
	_scripting = true
	_send("june")


## Brings in the next of the three scripted customers.
func _send(who: String) -> void:
	var c := _make(who)
	_cast[who] = c
	_who = who
	step = who + "_walk"
	shop.admit(c)
	var lines := {
		"june": "Your first customer is walking up to the counter.",
		"slick": "Here comes someone else. Keep an eye on this one.",
		"priya": "One more. This one wants to buy.",
	}
	_show("A customer", lines[who], AT_ROOM)


func _make(who: String) -> Customer:
	var rng := RandomNumberGenerator.new()
	rng.seed = {"june": 11, "slick": 22, "priya": 33}[who]
	var c := Customer.create(1, Shop.reputation, Shop.coin_list(), rng)
	c.piece = null
	c.bar = null
	c.fake = ""
	c.haggle = 0.0
	c.item = Shop.coins["silver_eagle"]
	c.max_patience = 9999.0
	c.patience = c.max_patience
	match who:
		"june":
			c.name = "June"
			c.kind = "seller"
			c.qty = 10
			c.reserve = minf(0.85, Shop.buy_percent - 0.01)
			c.say = "My dad's old Silver Eagles. I'd like a fair price."
		"slick":
			Customers.apply_archetype(c, "shady", rng)
			c.name = "Slick"
			c.item = Shop.coins["silver_eagle"]
			c.qty = 8
			c.fake = "steel"
			c.reserve = 0.7
			c.say = "Silver Eagles, cheap. Cash only, no questions, yeah?"
			c.max_patience = 9999.0
			c.patience = c.max_patience
		"priya":
			c.name = "Priya"
			c.kind = "buyer"
			c.qty = 5
			c.wanted_exact = false
			c.max_premium = maxf(0.1, Shop.sell_premium + 0.01)
			c.say = "Five silver coins, please. A birthday present."
	c.floor_reserve = c.reserve
	c.ceiling_premium = c.max_premium
	return c


func _at_counter() -> void:
	var c: Customer = _cast[_who]
	match _who:
		"june":
			step = "june_counter"
			_show("Your first customer", "June wants to sell %d Silver Eagles. Melt today is what the silver in them is worth. Your offer is what you'd pay. Never buy coins untested: press Test coin." % c.qty,
				AT_ROOM, TEST_BUTTON)
		"slick":
			step = "slick_counter"
			_show("Too good to be true?", "Slick's in a hurry and won't haggle. Cheap coins from a nervous seller are often fake. Test them too.",
				AT_ROOM, TEST_BUTTON)
		"priya":
			step = "priya_counter"
			_show("Selling", "Priya wants 5 silver coins from your vault. She pays melt plus your premium. Press Sell.",
				AT_ROOM, SELL_BUTTON)


func _on_bench_opened(bench: Control, c: Customer) -> void:
	_bench = bench
	if guiding and _cast.get(_who) == c:
		if _who == "june":
			step = "june_tools"
			_show("The coin test", "Each tool checks one thing. Press 1 for the Scale and 2 for the Calipers, then compare each READING with the SPEC next to it.",
				AT_BENCH, COIN_TOOLS)
		else:
			step = "slick_tools"
			_show("The magnet", "Steel fakes give themselves away to a magnet. Press 4.", AT_BENCH, COIN_TOOLS)
		return
	_hide()
	if c.piece and not Tutorial.has_seen("jewellery"):
		_intro("jewellery", "Jewellery appraisal", "Weigh the piece. Then press 2 to rub a streak on the touchstone and drop acids on it (Q-Y): the streak survives acids up to its karat, and base metal fizzes. The Tester checks a stone; moissanite fools it, so look for doubled facet edges under the loupe. Set the grade (G) and the stone (D), then Finish appraisal.")
	elif c.bar and not Tutorial.has_seen("bar"):
		_intro("bar", "Bar test", "Tungsten weighs almost the same as gold, so the scale isn't enough. Press 3 and sweep the ultrasound probe over the whole bar: the echo must stay inside the gate, and an early echo means tungsten inside. Read the serial under the loupe; a copied serial gets flagged. The XRF gun comes as an upgrade.")


func _intro(id: String, title: String, text: String) -> void:
	_intro_id = id
	_show(title, text, Vector2(78, 40), null, "Got it", _close_intro, false)


func _close_intro() -> void:
	if _intro_id != "":
		Tutorial.mark_seen(_intro_id)
		_intro_id = ""
	_hide()


func _on_bench_closed(verdict: String, c: Customer) -> void:
	_bench = null
	if _intro_id != "":
		_close_intro()
	if not guiding:
		return
	if _cast.get(_who) != c:
		return
	match [_who, verdict]:
		["june", "genuine"]:
			step = "june_offer"
			_show("Make an offer", "Real coins. Press Make offer to buy them at your price.", AT_ROOM, OFFER_BUTTON)
		[_, "cancel"]:
			_at_counter()
		["slick", "genuine"]:
			step = "slick_offer"
			_show("Are you sure?", "Those coins snapped to the magnet. You can still press Refuse.", AT_ROOM, COUNTER)


func _on_customer_left(c: Customer) -> void:
	if not guiding or _cast.get(_who) != c:
		return
	match _who:
		"june":
			if c.dealt:
				_send_after("Bought!", "June's coins are in your vault now. You can see them under IN THE VAULT.", "slick")
			else:
				_send_after("No deal", "June left without selling. That's fine; there's always another customer.", "slick")
		"slick":
			if c.caught:
				_send_after("Caught!", "Catching fakes earns reputation. Fakes you buy cost you the money and your stars when the assay lab checks them.", "priya")
			elif c.dealt:
				_send_after("Uh oh", "Those were plated steel. The assay lab will catch them soon and you'll lose what you paid. Always test first.", "priya")
			else:
				_send_after("Played it safe", "Turning away untested coins is safe. Testing them proves it, and catching a fake earns reputation.", "priya")
		"priya":
			_free_play(c.dealt)


func _send_after(title: String, text: String, who: String) -> void:
	step = "between"
	_show(title, text, AT_ROOM, null, "Next", _send.bind(who))


func _free_play(sold: bool) -> void:
	step = "free"
	_show("Sold!" if sold else "That's the counter",
		"Now you're on your own. Customers keep coming until 17:00, then you lock up the vault. Jewellery and bars have their own benches; you'll get a quick intro to each the first time.",
		AT_ROOM, null, "Got it", _release)


## Hands the shop back: the clock runs and customers come in on their own.
func _release() -> void:
	_scripting = false
	_who = ""
	step = "open_day"
	_hide()


func _on_vault_opened(vault: Control) -> void:
	_vault = vault
	if not guiding:
		return
	step = "vault"
	vault.paused = true
	_show("Lock up", "Burglars take whatever's left on the tray. Drag your stock into the safes: the floor safe never gets cracked, the wall safe sometimes does. Right-click turns a piece. The longer the lights stay on, the riskier it gets, so be quick.",
		Vector2(80, 60), VAULT_SAFES, "Start the clock", _start_vault_clock)


func _start_vault_clock() -> void:
	if is_instance_valid(_vault):
		_vault.paused = false
	step = "vault_clock"
	_hide()


func _on_summary_shown() -> void:
	_vault = null
	if not guiding:
		return
	step = "summary"
	_show("Day one done", "Bills come out each night, and the day's numbers land here. Tomorrow morning, spend your profit on upgrades and keep an eye on the ticker. Good luck!",
		AT_SIDE, null, "Finish", _finish, false)


func _finish() -> void:
	Tutorial.finish_first_day()
	guiding = false
	step = ""
	_hide()


# ---------------------------------------------------------------- the card

## Shows a card at `at`. `target` is what it points at (Rect2, Callable or null).
## `next_label` adds a button that calls `on_next`. Guided cards also offer Skip.
func _show(title: String, text: String, at: Vector2, target: Variant = null, next_label := "", on_next := Callable(), skippable := true) -> void:
	_title.text = title
	_body.text = text
	for b in _row.get_children():
		_row.remove_child(b)
		b.queue_free()
	if next_label != "":
		var next := _button(next_label, "PrimaryButton", on_next)
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if skippable and guiding:
		_button("Skip tutorial", "Button", skip)
	_row.visible = _row.get_child_count() > 0
	_card.visible = true
	_card.position = at
	_card.reset_size()
	_target = target
	_root.queue_redraw()


func _hide() -> void:
	_card.visible = false
	_target = null
	_root.queue_redraw()


func _button(text: String, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 12)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sfx.play(self, Sfx.click(), -8.0)
		on_press.call())
	_row.add_child(b)
	return b


## A blinking gold frame around whatever the card points at.
func _draw_target() -> void:
	var r: Variant = _target.call() if _target is Callable else _target
	if not r is Rect2:
		return
	var on := fmod(_time, 1.0) < 0.65
	_root.draw_rect(r.grow(1), Pal.GOLD if on else Pal.GOLD.darkened(0.4), false, 1.0)
	if on:
		_root.draw_rect(r.grow(2), Color(Pal.GOLD, 0.45), false, 1.0)
