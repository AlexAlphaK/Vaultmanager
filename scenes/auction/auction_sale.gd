class_name AuctionSale
extends RefCounted
## One lot under the hammer. The auctioneer asks for the next bid; the bidders in the room
## take it while it's under what they'll pay, faster when it's cheap, slower as it nears
## their limit, and drop out past it. Once the bidding stops the auctioneer calls
## "going once", "going twice", and brings the hammer down.
##
## Watch the room: a bidder near their limit hesitates (their paddle wavers, they check
## the catalogue, they mop their brow) and bids late, at "going twice". A jump bid skips
## a few steps: it costs more, but a hesitating bidder often folds.
##
## Each bidder's limit comes from what they think the lot is worth (AuctionHouse values):
##   Victor Sterling  every lot, a sharp price; sometimes his spies have seen inside a pouch
##   Lucky Lou        cheap estates and dealer stock, never rare coins on their own
##   a dealer         estates and dealer stock, for the metal
##   collectors       rare coins, and estates with a rare coin on show

## Seconds after the last bid for "going once", "going twice" and "sold", and the extra
## wait for an opening bid.
const CALLS := [1.7, 3.1, 4.3]
const OPEN_WAIT := 1.0
## The opening ask as a share of the low estimate.
const OPENING := 0.6
## Steps a jump bid skips, and the odds that a hesitating bidder folds when you jump.
const JUMP_STEPS := 3
const FOLD_ODDS := 0.55
## A bidder hesitates once the ask passes this share of their limit.
const HESITATE := 0.86
## Odds each kind of bidder wants a lot they would bid on, their limit as a share of
## what they think it's worth, and how quick their paddle is (seconds).
const BIDDERS := {
	"sterling": {"odds": 0.9, "limit": Vector2(0.8, 0.95), "pace": Vector2(0.25, 0.55), "rare": 0.45, "peek": 0.35},
	"pawn": {"odds": 0.7, "limit": Vector2(0.55, 0.78), "pace": Vector2(0.35, 0.7), "rare": 0.0, "peek": 0.0},
	"dealer": {"odds": 0.8, "limit": Vector2(0.78, 0.92), "pace": Vector2(0.3, 0.6), "rare": 0.3, "peek": 0.0},
	"collector": {"odds": 0.6, "limit": Vector2(0.9, 1.0), "pace": Vector2(0.3, 0.7), "rare": 0.0, "peek": 0.0},
}
## The share of a rare coin's collector premium a collector will pay for.
const COLLECTOR_RARE := Vector2(0.25, 0.7)

var lot: Dictionary
## One per seat: {"who", "name", "look", "limit", "pace", "value", "in", "at" (when they'll bid,
## -1 if not waiting), "hesitant", "folded", "last" (the clock when they last bid)}.
## `in` is false for a seat not bidding on this lot.
var bidders: Array[Dictionary] = []
var ask := 0.0
var high := 0.0
## "" before the first bid, "you", or the index of the bidder in `bidders`.
var leader := ""
var clock := 0.0
## 0 to 3: "going once", "going twice", sold.
var calls := 0
var done := false
## Your own lot: you can't bid on it and it won't sell under its reserve.
var mine := false
var reserve := 0.0
## What happened, for the room to show and play: {"what": "bid"/"jump"/"out"/"fold"/"call"/"sold"/"passed",
## "who": "you" or a bidder index, "amount"}. The room takes them out as it goes.
var events: Array[Dictionary] = []
## Every bid in order: {"who", "amount"}.
var bids: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


## The sale of `lot` to the people in `seats` (see AuctionHouse.attendees()).
static func of(lot_: Dictionary, seats: Array[Dictionary], seed := 0) -> AuctionSale:
	var s := AuctionSale.new()
	s.lot = lot_
	s._rng.seed = seed if seed != 0 else int(lot_.get("seed", 1)) * 31 + Shop.day
	s.mine = lot_.kind == "mine"
	s.reserve = AuctionHouse.reserve(lot_)
	for seat in seats:
		s.bidders.append(s._bidder(seat))
	var est := AuctionHouse.estimate(lot_)
	s.ask = AuctionHouse.nice(est.x * OPENING)
	for b in s.bidders:
		if b.limit < s.ask:
			b.in = false # not worth a bid to them: they sit this one out
	s._schedule()
	return s


func _bidder(seat: Dictionary) -> Dictionary:
	var b := seat.duplicate()
	var kind: Dictionary = BIDDERS[seat.who]
	var value := _value_for(seat.who, kind)
	b.value = value
	b.limit = 0.0
	b.in = value > 0.0 and _rng.randf() < float(kind.odds)
	if b.in:
		b.limit = AuctionHouse.nice(value * _rng.randf_range(kind.limit.x, kind.limit.y))
	b.pace = _rng.randf_range(kind.pace.x, kind.pace.y)
	b.at = -1.0
	b.hesitant = false
	b.folded = false
	b.last = -99.0
	return b


## What a bidder thinks the lot is worth. Collectors only care for rare coins on show;
## Lucky Lou won't touch a lot that's just a rare coin.
func _value_for(who: String, kind: Dictionary) -> float:
	var v := 0.0
	var rare_on_show := false
	var share: float = kind.rare
	if who == "collector":
		share = _rng.randf_range(COLLECTOR_RARE.x, COLLECTOR_RARE.y)
	for it in lot.items:
		var coin := AuctionHouse.coin_of(it)
		if it.pouch:
			if _rng.randf() < float(kind.peek):
				v += AuctionHouse.true_value(it, share) # Sterling's spies looked inside
			else:
				v += float(it.guess)
			continue
		if coin.rare:
			rare_on_show = true
		v += AuctionHouse.true_value(it, share)
	if who == "collector":
		return v if rare_on_show else 0.0
	if who == "pawn" and lot.kind == "rare":
		return 0.0
	return v


## The next bid the auctioneer will take after `amount`.
static func next_ask(amount: float) -> float:
	return amount + AuctionHouse.increment(amount)


func can_bid() -> bool:
	return not done and not mine and leader != "you"


## What a jump bid would be.
func jump_amount() -> float:
	var a := ask
	for n in JUMP_STEPS - 1:
		a = next_ask(a)
	return a


## You raise your paddle for the asking price (or a jump bid). True when the bid is taken.
func bid_you(jump := false) -> bool:
	if not can_bid():
		return false
	var amount := jump_amount() if jump else ask
	if not AuctionHouse.can_afford(amount):
		return false
	_take("you", amount)
	events.append({"what": "jump" if jump else "bid", "who": "you", "amount": amount})
	if jump:
		# the room flinches: anyone near their limit may give up now
		for i in bidders.size():
			var b := bidders[i]
			if b.in and ask > b.limit * HESITATE and _rng.randf() < FOLD_ODDS:
				b.in = false
				b.folded = true
				events.append({"what": "fold", "who": i, "amount": 0.0})
	_schedule()
	return true


func _take(who, amount: float) -> void:
	high = amount
	leader = str(who)
	ask = next_ask(amount)
	clock = 0.0
	calls = 0
	bids.append({"who": str(who), "amount": amount})


## Moves the room on by `delta` seconds. True once the hammer has come down.
func advance(delta: float) -> bool:
	if done:
		return true
	clock += delta
	# the quickest bidder whose moment has come takes the ask
	var first := -1
	for i in bidders.size():
		var b := bidders[i]
		if b.in and b.at >= 0.0 and clock >= b.at and (first < 0 or b.at < bidders[first].at):
			first = i
	if first >= 0:
		_take(first, ask)
		bidders[first].last = clock
		events.append({"what": "bid", "who": first, "amount": high})
		_schedule()
		return false
	var wait := OPEN_WAIT if leader == "" else 0.0
	var due := 0
	for t in CALLS:
		if clock >= t + wait:
			due += 1
	if due > calls:
		calls = due
		if calls >= CALLS.size():
			_hammer()
			return true
		events.append({"what": "call", "who": "", "amount": float(calls)})
	return false


## Every bidder not leading decides on the new ask: wait their moment, or drop out.
func _schedule() -> void:
	var wait := OPEN_WAIT if leader == "" else 0.0
	for i in bidders.size():
		var b := bidders[i]
		if not b.in:
			b.at = -1.0
			continue
		if leader == str(i):
			b.at = -1.0
			b.hesitant = false
			continue
		if ask > b.limit:
			b.in = false
			b.at = -1.0
			events.append({"what": "out", "who": i, "amount": 0.0})
			continue
		var near: float = ask / b.limit
		b.hesitant = near > HESITATE
		# quick while it's cheap; near the limit they take it late, at "going twice"
		var delay: float = b.pace * _rng.randf_range(0.8, 1.25) + 2.6 * pow(near, 8.0)
		b.at = clock + wait + minf(delay, CALLS[2] - 0.35)


func _hammer() -> void:
	done = true
	var sold := leader != "" and (not mine or high >= reserve)
	events.append({"what": "sold" if sold else "passed", "who": leader, "amount": high})


## Who won: "you", a bidder kind ("sterling", "pawn", "dealer", "collector") or "".
func winner() -> String:
	if not done or leader == "" or (mine and high < reserve):
		return ""
	return "you" if leader == "you" else str(bidders[int(leader)].who)


func winner_name() -> String:
	var w := winner()
	if w == "" or w == "you":
		return ""
	return str(bidders[int(leader)].name)


## What the winning rival thought the lot was worth (for their shop's books).
func winner_value() -> float:
	return float(bidders[int(leader)].value) if winner() != "" and winner() != "you" else 0.0


## Runs the lot to the hammer without you.
func finish_now() -> void:
	var guard := 0
	while not advance(0.1) and guard < 5000:
		guard += 1
	events.clear()


## Books the result with AuctionHouse.
func settle() -> void:
	AuctionHouse.settle(lot, winner(), winner_name(), high, winner_value())
