extends Node
## The angel investor: when the shop is about to go under, Celeste Wren offers a cash
## injection for a share of each day's profit.
##   Offer   On a morning when the cash will not cover tonight's bills (or the bank is
##           already charging overdraft interest), from the second day on. She waits
##           until the shop opens; open without taking it and she walks away for a few
##           days. One stake at a time, MAX_DEALS a game, and a longer wait after one ends.
##   Stake   STAKE for the shop's tier plus whatever clears the overdraft, rounded up.
##   Share   SHARES of each day's profit on sales, taken when the day ends. A day with
##           no profit costs nothing. Each new stake asks for a bigger share.
##   The end She is out once she has been paid RETURN times her stake, or any morning
##           the shop buys out what she is still owed. Then she drops by to say goodbye.
## Saved with the game.

signal changed

const NAME := "Celeste Wren"
## Cash she puts in per shop tier, on top of clearing the overdraft.
const STAKE: Array[float] = [12000.0, 30000.0, 75000.0, 150000.0]
## Her share of each day's profit for the first, second and third stake.
const SHARES: Array[float] = [0.15, 0.2, 0.25]
## She is paid off at this many times her stake.
const RETURN := 1.75
const MAX_DEALS := 3
## Days before she offers again after you turn her down, and after a stake ends.
const WAIT_DECLINED := 3
const WAIT_AFTER := 14
## Her first offer comes no earlier than this day.
const FIRST_DAY := 2

## Today's offer: {"day", "stake", "share"}, or {} when there is none.
var offer := {}
## The stake she holds: {"stake", "share", "cap", "paid", "day"}, or {} when none.
var deal := {}
## Stakes taken this game, how many ended (paid off or bought out) and all she was paid.
var deals := 0
var repaid := 0
var total_paid := 0.0
## No offer before this day.
var next_offer_day := FIRST_DAY
## The offer page has opened on its own this morning, so the panel doesn't keep jumping to it.
var offer_seen := false

var _today: Array[String] = []


func _ready() -> void:
	reset()
	SaveGame.register("investor", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_on_day_started)
	Day.shop_opened.connect(_on_shop_opened)
	Day.settling.connect(_take_share)
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	offer = {}
	deal = {}
	deals = 0
	repaid = 0
	total_paid = 0.0
	next_offer_day = FIRST_DAY
	offer_seen = false
	_today.clear()
	changed.emit()


func has_offer() -> bool:
	return not offer.is_empty() and int(offer.day) == Shop.day and Day.phase == Day.MORNING


func has_deal() -> bool:
	return not deal.is_empty()


## Tonight's bills: upkeep, wages, the bank's payments, and rent and insurance when they
## fall due tonight.
func bills_tonight() -> float:
	var total := Progress.daily_upkeep() + Staff.daily_wages() + Bank.due_tonight()
	if Day.is_bill_day():
		for bill in Day.upcoming_bills():
			total += bill.usd
	return total


## Whether the shop is about to go under: it can't pay tonight's bills.
func in_trouble() -> bool:
	return Shop.cash < bills_tonight()


## What she would put in today: her stake for the tier plus the overdraft, in thousands.
func stake_now() -> float:
	var base: float = STAKE[clampi(Progress.tier, 0, STAKE.size() - 1)]
	return ceilf((base + maxf(0.0, -Shop.cash)) / 1000.0) * 1000.0


func share_for(n := deals) -> float:
	return SHARES[clampi(n, 0, SHARES.size() - 1)]


## What she is still owed before she is out.
func owed() -> float:
	return 0.0 if deal.is_empty() else maxf(0.0, float(deal.cap) - float(deal.paid))


## Her cut of a day's profit.
func cut_of(profit: float) -> float:
	if deal.is_empty() or profit <= 0.0:
		return 0.0
	return minf(profit * float(deal.share), owed())


func accept() -> bool:
	if not has_offer() or has_deal():
		return false
	var stake := float(offer.stake)
	deal = {"stake": stake, "share": float(offer.share), "cap": stake * RETURN, "paid": 0.0, "day": Shop.day}
	offer = {}
	deals += 1
	Day.add_income(tr("Angel investment"), stake)
	Shop.log_event(tr("%s put %s into the shop for %d%% of each day's profit.") % [NAME, Market.format_money(stake),
		roundi(float(deal.share) * 100.0)], "good")
	Story.drop_in("investor_deal")
	changed.emit()
	return true


## The morning only: the stake is bought back before the shop opens.
func can_buy_out() -> bool:
	return has_deal() and Day.phase == Day.MORNING and Shop.cash >= owed()


func buy_out() -> bool:
	if not can_buy_out():
		return false
	var price := owed()
	Day.add_expense(tr("Investor buy-out"), price)
	total_paid += price
	deal.paid = float(deal.paid) + price
	Shop.log_event(tr("You bought out %s's stake for %s. The shop is all yours again.") % [NAME, Market.format_money(price)], "good")
	_end_deal()
	return true


func _end_deal() -> void:
	deal = {}
	repaid += 1
	next_offer_day = Shop.day + WAIT_AFTER
	_today.append(tr("%s is out: the shop is all yours again.") % NAME)
	Story.drop_in("investor_done")
	Records.check()
	changed.emit()


func _on_day_started(day: int) -> void:
	_today.clear()
	offer_seen = false
	if not offer.is_empty() and int(offer.day) == day:
		return # the morning replayed from its save: the same offer
	offer = {}
	if has_deal() or deals >= MAX_DEALS or day < next_offer_day or not Tutorial.first_day_done or not in_trouble():
		changed.emit()
		return
	offer = {"day": day, "stake": stake_now(), "share": share_for()}
	Shop.log_event(tr("%s, an angel investor, wants a word before you open.") % NAME, "good")
	changed.emit()


## Opening without taking the offer turns it down.
func _on_shop_opened(day: int) -> void:
	if offer.is_empty():
		return
	offer = {}
	next_offer_day = day + WAIT_DECLINED
	changed.emit()


## Takes her share as the day's books close, before the bills.
func _take_share(_day: int) -> void:
	var cut := cut_of(float(Shop.stats.get("profit", 0.0)))
	if cut <= 0.0:
		return
	Day.add_expense(tr("Investor's share"), cut)
	deal.paid = float(deal.paid) + cut
	total_paid += cut
	if owed() <= 0.005:
		Shop.log_event(tr("%s has her money back and more. She's out.") % NAME, "good")
		_end_deal()
	else:
		changed.emit()


func _on_day_ended(_day: int, report: Dictionary) -> void:
	for line in _today:
		report.lines.append(line)
	_today.clear()


## "15% of each day's profit".
func share_text(share: float) -> String:
	return tr("%d%% of each day's profit") % roundi(share * 100.0)


## A line for the morning panel, or "".
func morning_line() -> String:
	if has_offer():
		return tr("%s, an angel investor, will put in %s to keep you afloat. See the Ledger.") % [NAME, Market.format_money(float(offer.stake))]
	if has_deal():
		return tr("%s takes %d%% of each day's profit. Still owed: %s.") % [NAME, roundi(float(deal.share) * 100.0),
			Market.format_money(owed())]
	return ""


func to_dict() -> Dictionary:
	return {"offer": offer.duplicate(), "deal": deal.duplicate(), "deals": deals, "repaid": repaid,
		"total_paid": total_paid, "next_offer_day": next_offer_day}


func from_dict(d: Dictionary) -> void:
	reset()
	var o = d.get("offer", {})
	if typeof(o) == TYPE_DICTIONARY and o.has("day") and o.has("stake"):
		offer = {"day": int(o.day), "stake": float(o.stake), "share": float(o.get("share", share_for()))}
	var s = d.get("deal", {})
	if typeof(s) == TYPE_DICTIONARY and float(s.get("stake", 0.0)) > 0.0:
		deal = {"stake": float(s.stake), "share": float(s.get("share", SHARES[0])),
			"cap": float(s.get("cap", float(s.stake) * RETURN)), "paid": float(s.get("paid", 0.0)), "day": int(s.get("day", 1))}
	deals = int(d.get("deals", 0))
	repaid = int(d.get("repaid", 0))
	total_paid = float(d.get("total_paid", 0.0))
	next_offer_day = int(d.get("next_offer_day", FIRST_DAY))
	changed.emit()
