extends Node
## The town bank: a credit line and term loans, so a shop short of cash has another way
## out besides the overdraft and the angel investor (see Investor).
##   Rating      A to D, from a score of 0 to 100 that starts at START_SCORE. Nights in the
##               black while in debt and loans paid off raise it; overdrawn nights and
##               missed loan payments lower it. The rating sets the credit line, the
##               rates, and how much the bank will lend (nothing at D).
##   Credit line Draw up to the line's limit (LINE_LIMIT for the tier, times the rating's
##               LIMIT_FACTOR) any morning, and repay it any morning. Interest on what is
##               drawn every night. With auto_cover on, the bank draws on the line at night
##               to clear an overdraft, which costs the line's rate instead of the
##               overdraft's (Day.OVERDRAFT_RATE).
##   Term loan   One at a time, from three offers (LOAN_SIZES for the tier over LOAN_TERMS
##               days), paid back in equal nightly payments. Pay off what is left any
##               morning, with no fee. A payment the cash can't cover is still taken (into
##               the overdraft), but it counts as missed: a late fee and a hit to the rating.
## Money owed to the bank counts against net worth (Shop.net_worth). Saved with the game.

signal changed

const START_SCORE := 60.0
## The lowest score for each rating.
const GRADES := {"A": 80.0, "B": 50.0, "C": 30.0, "D": 0.0}
## Score changes: a night in the black while in debt, an overdrawn night, a missed loan
## payment, and a loan paid off.
const SCORE_GOOD_NIGHT := 1.0
const SCORE_OVERDRAWN := -5.0
const SCORE_MISSED := -8.0
const SCORE_PAID_OFF := 6.0
## The credit line for each shop tier at a B rating, and how the rating scales it.
const LINE_LIMIT: Array[float] = [8000.0, 25000.0, 60000.0, 150000.0]
const LIMIT_FACTOR := {"A": 1.5, "B": 1.0, "C": 0.5, "D": 0.0}
## Nightly interest on the credit line and on loans, by rating. A loan at D is refused.
const LINE_RATE := {"A": 0.001, "B": 0.0014, "C": 0.002, "D": 0.0025}
const LOAN_RATE := {"A": 0.0006, "B": 0.0009, "C": 0.0013}
## The three loans on offer for each tier, and their terms in days. At C only the first two.
const LOAN_SIZES := [[5000.0, 10000.0, 20000.0], [15000.0, 35000.0, 70000.0],
	[40000.0, 90000.0, 180000.0], [100000.0, 220000.0, 450000.0]]
const LOAN_TERMS: Array[int] = [14, 28, 56]
## A missed payment costs this share of the payment on top.
const LATE_FEE := 0.1

var score := START_SCORE
var best_score := START_SCORE
## What is drawn on the credit line.
var line := 0.0
## Draw on the line at night to clear an overdraft.
var auto_cover := true
## The loan: {"amount", "rate", "term", "days_left", "balance", "payment", "day"}, or {}.
var loan := {}
## Loans paid off this game, payments missed, and all the interest paid to the bank.
var loans_repaid := 0
var missed := 0
var interest_paid := 0.0

var _today: Array[String] = []


func _ready() -> void:
	reset()
	SaveGame.register("bank", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(func(_d): _today.clear())
	Day.settling.connect(_charge)
	Day.bills_paid.connect(_cover_overdraft)
	Day.day_ended.connect(_on_day_ended)


func reset() -> void:
	score = START_SCORE
	best_score = START_SCORE
	line = 0.0
	auto_cover = true
	loan = {}
	loans_repaid = 0
	missed = 0
	interest_paid = 0.0
	_today.clear()
	changed.emit()


func grade() -> String:
	for g in GRADES:
		if score >= GRADES[g]:
			return g
	return "D"


## All the shop owes the bank.
func debt() -> float:
	return line + (float(loan.balance) if has_loan() else 0.0)


func has_loan() -> bool:
	return not loan.is_empty()


func line_limit() -> float:
	return LINE_LIMIT[clampi(Progress.tier, 0, LINE_LIMIT.size() - 1)] * float(LIMIT_FACTOR[grade()])


func line_rate() -> float:
	return LINE_RATE[grade()]


## What can still be drawn on the line.
func headroom() -> float:
	return maxf(0.0, line_limit() - line)


## The bank's buttons work in the morning, before the shop opens.
func _morning() -> bool:
	return Day.phase == Day.MORNING


## The usual step for the draw and repay buttons: a quarter of the line, in $500s.
func step() -> float:
	return maxf(500.0, ceilf(line_limit() / 4.0 / 500.0) * 500.0)


func can_draw(usd: float) -> bool:
	return _morning() and usd > 0.0 and usd <= headroom() + 0.005


func draw(usd: float) -> bool:
	if not can_draw(usd):
		return false
	line += usd
	Day.add_income(tr("Credit line draw"), usd)
	changed.emit()
	return true


## The most a repay can be: what is drawn, and no more than the cash in hand.
func repayable() -> float:
	return minf(line, maxf(0.0, Shop.cash))


func can_repay(usd: float) -> bool:
	return _morning() and usd > 0.0 and usd <= repayable() + 0.005


func repay(usd: float) -> bool:
	if not can_repay(usd):
		return false
	usd = minf(usd, line)
	line = maxf(0.0, line - usd)
	Day.add_expense(tr("Credit line repaid"), usd)
	changed.emit()
	return true


## Today's loan offers: [{"amount", "term", "rate", "payment"}], none at D, two at C.
func offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := grade()
	if not LOAN_RATE.has(g):
		return out
	var sizes: Array = LOAN_SIZES[clampi(Progress.tier, 0, LOAN_SIZES.size() - 1)]
	for i in sizes.size():
		if g == "C" and i >= 2:
			break
		var rate: float = LOAN_RATE[g]
		out.append({"amount": float(sizes[i]), "term": LOAN_TERMS[i], "rate": rate,
			"payment": payment_for(float(sizes[i]), rate, LOAN_TERMS[i])})
	return out


## The equal nightly payment that pays off `amount` over `days` nights at `rate` a night.
static func payment_for(amount: float, rate: float, days: int) -> float:
	if rate <= 0.0:
		return amount / days
	return amount * rate / (1.0 - pow(1.0 + rate, -days))


func can_borrow() -> bool:
	return _morning() and not has_loan() and not offers().is_empty()


func borrow(i: int) -> bool:
	var list := offers()
	if not can_borrow() or i < 0 or i >= list.size():
		return false
	var o: Dictionary = list[i]
	loan = {"amount": o.amount, "rate": o.rate, "term": o.term, "days_left": o.term, "balance": o.amount,
		"payment": o.payment, "day": Shop.day}
	Day.add_income(tr("Bank loan"), o.amount)
	Shop.log_event(tr("The bank lent you %s, paid back over %d days.") % [Market.format_money(o.amount), o.term], "good")
	changed.emit()
	return true


func can_pay_off() -> bool:
	return _morning() and has_loan() and Shop.cash >= float(loan.balance)


## Pays what is left of the loan, with no fee.
func pay_off() -> bool:
	if not can_pay_off():
		return false
	Day.add_expense(tr("Loan paid off"), float(loan.balance))
	_loan_done()
	return true


## Tonight's payment on the loan: the last one is whatever is left.
func loan_payment() -> float:
	if not has_loan():
		return 0.0
	var balance := float(loan.balance)
	return minf(float(loan.payment), balance * (1.0 + float(loan.rate)))


## What the bank takes tonight: the loan payment and the interest on the line.
func due_tonight() -> float:
	return loan_payment() + line * line_rate()


func rate_text(rate: float) -> String:
	return tr("%.2f%% a night") % (rate * 100.0)


func _loan_done() -> void:
	loan = {}
	loans_repaid += 1
	_change_score(SCORE_PAID_OFF)
	_today.append(tr("Your bank loan is paid off. Your credit rating is %s.") % grade())
	Records.check()
	changed.emit()


func _change_score(by: float) -> void:
	score = clampf(score + by, 0.0, 100.0)
	best_score = maxf(best_score, score)


## As the day's books close: the interest on the line and the loan's payment.
func _charge(_day: int) -> void:
	if line > 0.0:
		var interest := line * line_rate()
		Day.add_expense(tr("Credit line interest"), interest)
		interest_paid += interest
	if not has_loan():
		changed.emit()
		return
	var pay := loan_payment()
	var interest := float(loan.balance) * float(loan.rate)
	if Shop.cash < pay:
		missed += 1
		_change_score(SCORE_MISSED)
		Day.add_expense(tr("Late fee"), pay * LATE_FEE)
		_today.append(tr("You couldn't cover tonight's loan payment. The bank took it anyway, with a late fee."))
	Day.add_expense(tr("Loan payment"), pay)
	interest_paid += minf(interest, pay)
	loan.balance = maxf(0.0, float(loan.balance) + interest - pay)
	loan.days_left = int(loan.days_left) - 1
	if float(loan.balance) <= 0.5 or int(loan.days_left) <= 0:
		_loan_done()
	else:
		changed.emit()


## After the bills: the line covers an overdraft, as far as it reaches.
func _cover_overdraft(_day: int) -> void:
	if not auto_cover or Shop.cash >= 0.0:
		return
	var usd := minf(-Shop.cash, headroom())
	if usd < 1.0:
		return
	line += usd
	Day.add_income(tr("Credit line covered the overdraft"), usd)
	changed.emit()


func _on_day_ended(_day: int, report: Dictionary) -> void:
	var before := grade()
	if Shop.cash < 0.0:
		_change_score(SCORE_OVERDRAWN)
	elif debt() > 0.0:
		_change_score(SCORE_GOOD_NIGHT)
	if grade() != before:
		_today.append(tr("The bank moved your credit rating from %s to %s.") % [before, grade()])
		Records.check()
	for l in _today:
		report.lines.append(l)
	_today.clear()
	changed.emit()


func to_dict() -> Dictionary:
	return {"score": score, "best_score": best_score, "line": line, "auto_cover": auto_cover, "loan": loan.duplicate(),
		"loans_repaid": loans_repaid, "missed": missed, "interest_paid": interest_paid}


func from_dict(d: Dictionary) -> void:
	reset()
	score = clampf(float(d.get("score", START_SCORE)), 0.0, 100.0)
	best_score = maxf(score, float(d.get("best_score", score)))
	line = maxf(0.0, float(d.get("line", 0.0)))
	auto_cover = bool(d.get("auto_cover", true))
	var l = d.get("loan", {})
	if typeof(l) == TYPE_DICTIONARY and float(l.get("balance", 0.0)) > 0.0:
		loan = {"amount": float(l.get("amount", l.balance)), "rate": float(l.get("rate", LOAN_RATE.B)),
			"term": int(l.get("term", LOAN_TERMS[0])), "days_left": maxi(1, int(l.get("days_left", 1))),
			"balance": float(l.balance), "payment": float(l.get("payment", l.balance)), "day": int(l.get("day", 1))}
	loans_repaid = int(d.get("loans_repaid", 0))
	missed = int(d.get("missed", 0))
	interest_paid = float(d.get("interest_paid", 0.0))
	changed.emit()
