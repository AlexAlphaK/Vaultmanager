class_name Customer
extends RefCounted
## Someone who walks in to sell coins to the shop or buy them.
## Sellers sometimes carry fakes; their asking price follows the day's market mood.
## A customer who comes because of a market event (see MarketEvents) follows that event.

const NAMES := ["Mrs. Okafor", "Dale", "Priya", "Grandpa Lev", "Kevin", "Ms. Halvorsen", "Marco", "June",
	"Big Earl", "Tomasz", "Aiyana", "Rosa", "Deshawn", "Hiro", "Fern", "Ingrid", "Mateo", "Old Sal"]
const SELLER_LINES := ["Clearing out my late husband's collection.", "Price is up, time to cash in.",
	"Need a bit of cash for the car.", "Selling part of my stack."]
const FAKE_LINES := ["Found these in a drawer. Real deal, trust me.", "Bought them online, need cash fast.",
	"My cousin says these are worth a fortune.", "No receipt, but they're solid. Swear."]
const BUYER_LINES_DOWN := ["Prices dipped, I'm buying.", "Stocks are a casino. I want metal."]
const BUYER_LINES_UP := ["Crypto burned me. I want something real.", "Adding to my stack.", "A gift for my granddaughter."]

var name := ""
var kind := "seller" # or "buyer"
var item: BullionItem
var qty := 1
var fake := ""
## Lowest share of melt a seller accepts, and the highest premium a buyer pays.
var reserve := 0.9
var max_premium := 0.06
var patience := 70.0
var max_patience := 70.0
var say := ""
var tries := 0
var tested := false
var seed := 0
var event_id := "" # the market event that brought them in, if any

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
	c.kind = "seller" if rng.randf() < clampf(0.6 + mood * 0.08, 0.35, 0.85) else "buyer"
	c.qty = rng.randi_range(5, 25) if metal == "XAG" else rng.randi_range(1, 3 if metal == "XAU" else 2)
	if not event.is_empty():
		c.event_id = event.id
		c.kind = event.kind
		c.qty = maxi(1, roundi(c.qty * float(event.get("qty", 1.0))))
	if c.kind == "seller":
		var fake_odds := minf(0.45, 0.25 + 0.04 * (day - 1))
		var kinds := Counterfeit.kinds_for(metal, day)
		if not kinds.is_empty() and rng.randf() < fake_odds:
			c.fake = kinds[rng.randi() % kinds.size()]
		# panicking sellers take less, sellers cashing in at the top hold out for more
		c.reserve = clampf(0.86 + rng.randf_range(-0.03, 0.04) + maxf(0.0, mood) * 0.012 + float(event.get("reserve", 0.0)), 0.74, 0.99)
		c.say = (FAKE_LINES if c.fake != "" else SELLER_LINES)[rng.randi() % 4]
	else:
		c.max_premium = clampf(rng.randf_range(0.03, 0.09) + reputation * 0.006 + float(event.get("premium", 0.0)), 0.02, 0.20)
		var lines := BUYER_LINES_DOWN if mood < 0.0 else BUYER_LINES_UP
		c.say = lines[rng.randi() % lines.size()]
	if not event.is_empty() and c.fake == "":
		c.say = event.lines[rng.randi() % event.lines.size()]
	var look := PeopleArt.random_look(rng)
	for f in 3:
		c.frames.append(PeopleArt.paint(look, f).texture())
	return c


## Melt value of everything the customer brings or wants, at live prices.
func melt_total() -> float:
	return item.melt_value() * qty


func offer_total() -> float:
	return melt_total() * Shop.buy_percent


func sale_total() -> float:
	return melt_total() * (1.0 + Shop.sell_premium)
