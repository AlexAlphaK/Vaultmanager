class_name Customer
extends RefCounted
## Someone who walks in to sell coins to the shop or buy them.
## Some sellers bring jewellery or a bullion bar instead. Sellers sometimes carry fakes; their asking price follows the day's market mood.
## A customer who comes because of a market event (see MarketEvents) follows that event.
## Customers (the autoload) gives each one a personality: an archetype, and for the
## shop's regulars a place in their story. Most customers haggle a little; hagglers a lot.

const NAMES := ["Mrs. Adeyemi", "Dale", "Priya", "Grandpa Joe", "Kevin", "Ms. Halvorsen", "Marco", "June",
	"Big Earl", "Tomasz", "Aiyana", "Rosa", "Deshawn", "Hiro", "Fern", "Ingrid", "Mateo", "Old Sal"]
const SELLER_LINES := ["Clearing out my late husband's collection.", "Price is up, time to cash in.",
	"Need a bit of cash for the car.", "Selling part of my stack."]
const FAKE_LINES := ["Found these in a drawer. Real deal, trust me.", "Bought them online, need cash fast.",
	"My cousin says these are worth a fortune.", "No receipt, but they're solid. Swear."]
const JEWELLERY_LINES := ["This was my grandmother's. Never wear it.", "Divorce. Don't ask.",
	"Found it at an estate sale. It's stamped.", "Cleaning out the jewellery box."]
const JEWELLERY_SCAM_LINES := ["Solid gold, real stone. Need cash today.", "Had it appraised for twice that, honest.",
	"My uncle's a jeweller, he says it's the real thing.", "Quick sale. No questions, right?"]
const BAR_LINES := ["Inherited this bar. I'd rather have cash.", "Bought it years ago. Time to sell.",
	"It's been sitting in my safe deposit box.", "Need the money for a down payment."]
const BAR_SCAM_LINES := ["Got it cheap from a guy. Real, I promise.", "Comes with the card, but I lost it.",
	"Melt it down if you don't believe me.", "Quick deal? I've got another buyer waiting."]
const BUYER_LINES_DOWN := ["Prices dipped, I'm buying.", "Stocks are a casino. I want metal."]
const BUYER_LINES_UP := ["Crypto burned me. I want something real.", "Adding to my stack.", "A gift for my granddaughter."]

## Odds an everyday seller's coins are fake: FAKE_ODDS.x on day 1, rising by FAKE_ODDS.y
## a day up to FAKE_ODDS_MAX for the shop's tier: bigger shops draw more crooks, so a
## player still learning the bench at the corner counter is not swamped by them.
## Bars are faked less often, since a fake bar costs far more.
## Tuned with tests/balance_sim.tscn: missing a fake costs the whole price, and a fair
## deal earns about a tenth of it, so a player who tests most coins should come out ahead.
const FAKE_ODDS := Vector2(0.06, 0.004)
const FAKE_ODDS_MAX: Array[float] = [0.09, 0.15, 0.2, 0.22]
const BAR_FAKE_SHARE := 0.6
## Odds a customer sells rather than buys (on a flat market), and the odds a seller
## brings jewellery, or else a bar, instead of coins. Only coin sellers stock the
## vault, so these set how often a buyer finds the shelves empty.
const SELLER_SHARE := 0.65
const JEWELLERY_SHARE := 0.3
const BAR_SHARE := 0.25

var name := ""
var kind := "seller" # or "buyer"
var item: BullionItem
var qty := 1
var fake := ""
## Lowest share of melt a seller accepts, and the highest premium a buyer pays.
var reserve := 0.9
var max_premium := 0.06
## Haggling: how far the customer moves each time you hold firm, and how far they go.
## Sellers come down to `floor_reserve`, buyers come up to `ceiling_premium`.
var haggle := 0.0
var floor_reserve := 0.9
var ceiling_premium := 0.06
## "walk_in", "haggler", "crypto_bro", "collector", "shady", "regular" or "story".
var archetype := "walk_in"
## Regulars: who they are in Customers.REGULARS and which visit of their story this is.
var regular_id := ""
var beat := -1
## Story visitors (see Story): the beat they are here to play.
var story := ""
## Collectors want this exact coin, not just the metal.
var wanted_exact := false
## The special order (see Orders) this collector is placing (kind "order") or picking up.
## A pickup pays the agreed premium, whatever the shop's prices.
var order := {}
## How the visit ended, read by Customers when they leave.
var dealt := false
var caught := false
var patience := 70.0
var max_patience := 70.0
var say := ""
## What a "visit" customer (someone who just drops by to talk) says under their quote.
var note := ""
var tries := 0
var tested := false
## The clerk tried to serve this buyer and they wanted a better price.
var clerk_tried := false
## How many coins a buyer first asked for, once you sold them less (see `settle_for`).
var wanted := 0
var seed := 0
var event_id := "" # the market event that brought them in, if any
## A piece of jewellery instead of coins (sellers only), and how the player graded it
## in the appraisal: {"grade": String, "diamond": bool, "weight": grams}.
var piece: JewelleryPiece
var assessed := {}
## A bullion bar instead of coins (sellers only).
var bar: BullionBar
## A collector's coin to be graded (kind "grade", see CoinGrade); `assessed` then holds
## the call: {"grade": index into CoinGrade.GRADES, "cleaned": bool}.
var grading: CoinGrade

var pos := ShopArt.ENTRANCE
var leaving := false
var walking := false
var frames: Array[Texture2D] = []


static func create(day: int, reputation: float, coins: Array[BullionItem], rng: RandomNumberGenerator, event := {}) -> Customer:
	var c := Customer.new()
	c.seed = rng.randi()
	c.name = NAMES[rng.randi() % NAMES.size()]
	var roll := rng.randf()
	var metal := "XAU" if roll < 0.42 else ("XAG" if roll < 0.88 else "XPT")
	if event.get("metal", "") != "":
		metal = event.metal
	var choices := coins.filter(func(it): return it.metal == metal)
	if choices.is_empty():
		choices = coins
	c.item = choices[rng.randi() % choices.size()]
	metal = c.item.metal
	var mood := Market.day_change_percent(metal)
	c.kind = "seller" if rng.randf() < clampf(SELLER_SHARE + mood * 0.08, 0.35, 0.85) else "buyer"
	c.qty = rng.randi_range(5, 25) if metal == "XAG" else rng.randi_range(1, 3 if metal == "XAU" else 2)
	if not event.is_empty():
		c.event_id = event.id
		c.kind = event.kind
		c.qty = maxi(1, roundi(c.qty * float(event.get("qty", 1.0))))
	# a bigger shop draws customers with bigger stacks
	c.qty = maxi(1, roundi(c.qty * Progress.deal_size() * rng.randf_range(0.8, 1.2)))
	c.max_patience = 70.0 * (1.0 + Progress.effect("patience"))
	c.patience = c.max_patience
	if c.kind == "seller":
		var fake_odds := fake_odds_on(day)
		var kinds := Counterfeit.kinds_for(metal, day)
		if not kinds.is_empty() and rng.randf() < fake_odds:
			c.fake = kinds[rng.randi() % kinds.size()]
		# panicking sellers take less, sellers cashing in at the top hold out for more
		c.reserve = clampf(0.86 + rng.randf_range(-0.03, 0.04) + maxf(0.0, mood) * 0.012 + float(event.get("reserve", 0.0)), 0.74, 0.99)
		c.say = Loc.t((FAKE_LINES if c.fake != "" else SELLER_LINES)[rng.randi() % 4])
		if event.is_empty() and rng.randf() < JEWELLERY_SHARE:
			c.piece = JewelleryPiece.create(day, rng)
			c.fake = ""
			c.qty = 1
			c.say = Loc.t((JEWELLERY_SCAM_LINES if c.piece.scam else JEWELLERY_LINES)[rng.randi() % 4])
		elif event.is_empty() and rng.randf() < BAR_SHARE:
			c.bar = BullionBar.create(day, Progress.tier, rng, fake_odds * BAR_FAKE_SHARE)
			c.fake = ""
			c.qty = 1
			c.say = Loc.t((BAR_SCAM_LINES if c.bar.fake != "" else BAR_LINES)[rng.randi() % 4])
	else:
		c.max_premium = clampf(rng.randf_range(0.03, 0.09) + reputation * 0.006 + float(event.get("premium", 0.0)), 0.02, 0.20) + Progress.effect("premium")
		var lines := BUYER_LINES_DOWN if mood < 0.0 else BUYER_LINES_UP
		c.say = Loc.t(lines[rng.randi() % lines.size()])
	if not event.is_empty() and c.fake == "":
		c.say = Loc.t(event.lines[rng.randi() % event.lines.size()])
	c.floor_reserve = c.reserve
	c.ceiling_premium = c.max_premium
	c.set_look(PeopleArt.random_look(rng))
	return c


static func fake_odds_on(day: int, tier := Progress.tier) -> float:
	return minf(FAKE_ODDS_MAX[clampi(tier, 0, FAKE_ODDS_MAX.size() - 1)], FAKE_ODDS.x + FAKE_ODDS.y * (day - 1))


func set_look(look: Dictionary) -> void:
	frames.clear()
	for f in PeopleArt.FRAMES:
		frames.append(PeopleArt.paint(look, f).texture())


## Sets how hard the customer bargains. Sellers open `open` above their floor and buyers
## open that much below their ceiling, then move `step` each time you hold firm.
func set_haggle(open: float, step: float) -> void:
	haggle = step
	if kind == "seller":
		floor_reserve = reserve
		reserve = minf(reserve + open, 1.05)
	else:
		ceiling_premium = max_premium
		max_premium = maxf(0.0, max_premium - open)


## The seller hears your offer. True means deal; otherwise they counter and lose patience.
func hear_offer(offer: float) -> bool:
	if offer >= reserve * expected_total() - 0.01:
		return true
	tries += 1
	patience -= 15.0
	var moved := reserve > floor_reserve
	reserve = maxf(floor_reserve, reserve - haggle)
	if moved and offer >= reserve * expected_total() - 0.01:
		say = tr("Ugh. Fine. You drive a hard bargain.")
		return true
	var ask := ceili(reserve * 100.0 - 0.01)
	if piece:
		say = tr("No. I know what this is worth.") if tries > 1 else tr("That's a lowball for a piece like this. Look again.")
		if moved:
			say = tr("Look, I'd take %d%% of what it's worth. That's fair.") % ask
	elif moved:
		var final := reserve <= floor_reserve
		match archetype:
			"haggler":
				say = (tr("%d%%. That's my floor, take it or I walk.") if final else tr("Come on. %d%% and we shake on it.")) % ask
			"crypto_bro":
				say = tr("Bro. %d%%. I'm literally losing money here.") % ask
			_:
				say = (tr("Okay, %d%%, but that's as low as I go.") if final else tr("How about %d%%? Meet me halfway.")) % ask
	else:
		say = tr("Still too low. I know what spot is today.") if tries > 1 else \
			tr("That's a lowball. I was hoping for closer to %d%%.") % ask
	return false


## The buyer hears your price (premium over melt). True means sold.
func hear_price(premium: float) -> bool:
	if premium <= max_premium + 0.0001 or fixed_price():
		return true
	tries += 1
	patience -= 15.0
	var moved := max_premium < ceiling_premium
	max_premium = minf(ceiling_premium, max_premium + haggle)
	if moved and premium <= max_premium + 0.0001:
		say = tr("Fine, fine. Ring it up.")
		return true
	var over := maxi(1, floori(max_premium * 100.0 + 0.01))
	if moved:
		say = (tr("Spot plus %d%%, final offer.") if max_premium >= ceiling_premium else tr("I could stretch to %d%% over. Deal?")) % over
	elif archetype == "collector":
		say = tr("I pay well for quality, but not that well. %d%% over.") % over
	else:
		say = tr("Sterling across the street is cheaper.") if tries > 1 else \
			tr("Spot plus %d%%? I'd pay maybe %d%% over.") % [roundi(premium * 100.0), over]
	return false


## Coins the shop holds that this customer would buy.
func stock_have() -> int:
	if wanted_exact:
		# a collector picking up their order gets the coins set aside for it
		return Shop.count_of_item(item) if not order.is_empty() else Shop.spare_of(item)
	return Shop.count_of(item.metal)


## Coins you could hand this buyer now: all they want, or what you have left.
## A collector picking up a special order wants the whole set or nothing.
func can_sell() -> int:
	var have := stock_have()
	if have >= qty:
		return qty
	return 0 if not order.is_empty() else have


## The buyer settles for the `have` coins you hold instead of the `qty` they asked for.
## They take it, but a short sale earns less goodwill (see Shop.REPUTATION "sold_short").
func settle_for(have: int) -> void:
	if have <= 0 or have >= qty:
		return
	if wanted == 0:
		wanted = qty
	qty = have
	say = tr("Only %d? I'll take what you have.") % have


func short_sale() -> bool:
	return wanted > qty


## Melt value of everything the customer brings or wants, at live prices.
func melt_total() -> float:
	if piece:
		if assessed.is_empty():
			return piece.claimed_value()
		return piece.value_as(assessed.grade, assessed.diamond, assessed.weight)
	if bar:
		return bar.melt_value()
	return item.melt_value() * qty


## The least the customer takes before walking: melt for coins, and for jewellery
## what they believe it's worth (or what it really is, once they're shown).
func expected_total() -> float:
	if piece:
		return piece.expected_value()
	return melt_total()


func offer_total() -> float:
	return melt_total() * Shop.buy_percent


func sale_total() -> float:
	return melt_total() * (1.0 + (max_premium if fixed_price() else Shop.sell_premium))


## Collectors pay their own price for a rare coin or a special order, not the shop's.
func fixed_price() -> bool:
	return kind == "buyer" and (not order.is_empty() or (item != null and item.rare))
