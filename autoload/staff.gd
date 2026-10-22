extends Node
## The people you hire: a clerk who works the second till and a guard at the door.
## Hiring costs a signing fee in the morning; wages go on the ledger at closing time
## every day they are on the payroll. Their effects add to Progress.effect(), so the
## guard's cut to robbery odds reaches the vault lock-up like any upgrade's.
##
## Staff grow into the job. Every day worked and every customer served or robber
## stopped is experience, and each level makes them better at it (see SKILL). A
## better hand expects better pay: once they are paid less than their level is worth,
## their mood slips each day and they ask for a raise in the morning. Low spirits mean
## bad days (a grumpy shift or a sick call), and someone fed up for long enough quits.

signal changed

## `fee` is paid once when hired; `wage` is per day, and rises with the shop's tier.
## Effects keys as in Progress.upgrades, plus `till_grab` (share off daytime till snatches).
const ROLES := {
	"clerk": {"name": "Benny", "title": "Clerk", "fee": 1000.0, "wage": 55.0, "tier": 0,
		"desc": "Works the second till. Sells coins to buyers at your price while you test, so the queue keeps moving.",
		"effects": {}},
	"guard": {"name": "Rhonda", "title": "Guard", "fee": 2000.0, "wage": 80.0, "tier": 0,
		"desc": "Stands by the door. Break-ins drop by a third and nobody dares grab the till in a rush.",
		"effects": {"robbery_risk": -0.35, "till_grab": -0.85}},
}
## How long a new clerk takes to ring up one buyer.
const CLERK_SECONDS := 5.0
## How much more staff cost at each tier up.
const WAGE_PER_TIER := 0.4

## Experience needed for each level (level 1 is a new hire).
const LEVEL_XP := [0, 30, 80, 160, 280]
const LEVEL_NAMES := ["New", "Steady", "Skilled", "Expert", "Veteran"]
## Experience for a day's work (the guard has fewer chances to shine), for each buyer
## the clerk serves and each robber the guard stops.
const XP_PER_DAY := {"clerk": 3, "guard": 6}
const XP_PER_SALE := 1
const XP_PER_STOP := 10
## What each level past the first adds. clerk_speed is Progress's key (more is faster);
## persuade is the chance the clerk talks round a buyer who balks at your price;
## guard_stop adds to Security.GUARD_STOP at the door.
const SKILL := {
	"clerk": {"clerk_speed": 0.15, "persuade": 0.08},
	"guard": {"robbery_risk": -0.04, "guard_stop": 0.05},
}
## A fair wage rises this much with each level; each raise you agree to adds RAISE.
const FAIR_PER_LEVEL := 0.12
const RAISE := 0.12

## Mood is 0 to 100. Fairly paid staff warm up a little each day; underpaid ones sour
## by UNDERPAID_MOOD for each raise they are owed. A raise cheers them, a no stings,
## and nobody stays once mood hits zero.
const START_MOOD := 70.0
const PAID_FAIR_MOOD := 2.0
const UNDERPAID_MOOD := 4.0
const RAISE_MOOD := 20.0
const REFUSE_MOOD := -15.0
## Waiting this many days before asking again after a no.
const ASK_AGAIN_DAYS := 5
## Chance of a bad day: a little for anyone, more as mood drops under BAD_DAY_MOOD.
const BAD_DAY_BASE := 0.03
const BAD_DAY_LOW := 0.35
const BAD_DAY_MOOD := 50.0
## A grumpy clerk is slower and won't talk anyone round; a grumpy guard watches the
## door half as well. Of bad days, this share are sick calls (they stay home, unpaid).
const SICK_SHARE := 0.35
const GRUMPY_SLOW := 0.6

var hired: Array[String] = []
## Per person: {"xp", "level", "mood", "raises", "days", "asking", "asked_day", "today"}.
## today is "" (fine), "grumpy" or "sick"; asking is true while a raise request waits.
var crew: Dictionary = {}
## Lines for tonight's summary: level-ups and the like.
var _news: Array[String] = []
var _rolled_day := 0
var _seed := 0


func _ready() -> void:
	SaveGame.register("staff", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_morning)
	Day.shop_closed.connect(_pay_wages)
	Day.day_ended.connect(_report)
	Shop.noted.connect(_on_noted)


func reset() -> void:
	hired.clear()
	crew.clear()
	_news.clear()
	_rolled_day = 0
	_seed = randi()
	changed.emit()


func has(id: String) -> bool:
	return hired.has(id)


## On the payroll and in today: not off sick.
func on_duty(id: String) -> bool:
	return hired.has(id) and info(id).today != "sick"


func is_grumpy(id: String) -> bool:
	return hired.has(id) and info(id).today == "grumpy"


func label(id: String) -> String:
	return "%s the %s" % [ROLES[id].name, ROLES[id].title.to_lower()]


func info(id: String) -> Dictionary:
	if not crew.has(id):
		crew[id] = _fresh()
	return crew[id]


func level(id: String) -> int:
	return int(info(id).level) if hired.has(id) else 1


func level_name(id: String) -> String:
	return LEVEL_NAMES[level(id) - 1]


## Experience still to go to the next level, or 0 at the top.
func xp_to_next(id: String) -> int:
	var lvl := level(id)
	return 0 if lvl >= LEVEL_XP.size() else int(LEVEL_XP[lvl]) - int(info(id).xp)


func wage(id: String) -> float:
	var raises := int(info(id).raises) if hired.has(id) else 0
	return float(ROLES[id].wage) * (1.0 + WAGE_PER_TIER * Progress.tier) * (1.0 + RAISE * raises)


## What their level is worth: the wage they expect.
func fair_wage(id: String) -> float:
	return float(ROLES[id].wage) * (1.0 + WAGE_PER_TIER * Progress.tier) * (1.0 + FAIR_PER_LEVEL * (level(id) - 1))


## Raises they are owed: one per level they have grown past their pay.
func raises_owed(id: String) -> int:
	return maxi(0, level(id) - 1 - int(info(id).raises))


## The most seasoned person on the payroll, for the Records ledger.
func top_level() -> int:
	var best := 0
	for id in hired:
		best = maxi(best, level(id))
	return best


func daily_wages() -> float:
	var total := 0.0
	for id in hired:
		total += wage(id)
	return total


func mood_word(id: String) -> String:
	var m := float(info(id).mood)
	if m >= 75.0:
		return "Happy"
	if m >= 50.0:
		return "Content"
	if m >= 25.0:
		return "Fed up"
	return "About to quit"


## Sum of one effect across the people at work today, with what their levels add.
func effect(key: String) -> float:
	var total := 0.0
	for id in hired:
		if not on_duty(id):
			continue
		total += float(ROLES[id].effects.get(key, 0.0))
		total += float(SKILL[id].get(key, 0.0)) * (level(id) - 1)
	return total


## Chance the guard stops a robber at the door today, 0 when there is none on duty.
func guard_stop() -> float:
	if not on_duty("guard"):
		return 0.0
	var odds := Security.GUARD_STOP + float(SKILL.guard.guard_stop) * (level("guard") - 1)
	return minf(odds * (0.5 if is_grumpy("guard") else 1.0), 0.95)


## Chance the clerk talks round a buyer who won't pay your price.
func clerk_persuade() -> float:
	if not on_duty("clerk") or is_grumpy("clerk"):
		return 0.0
	return float(SKILL.clerk.persuade) * (level("clerk") - 1)


## How long the clerk spends on one buyer today.
func clerk_seconds() -> float:
	var t := CLERK_SECONDS / (1.0 + Progress.effect("clerk_speed"))
	return t / GRUMPY_SLOW if is_grumpy("clerk") else t


func can_hire(id: String) -> bool:
	return ROLES.has(id) and not hired.has(id) and int(ROLES[id].tier) <= Progress.tier \
		and Shop.cash >= ROLES[id].fee and Day.phase == Day.MORNING


func hire(id: String) -> bool:
	if not can_hire(id):
		return false
	Day.add_expense("Hired %s" % label(id), ROLES[id].fee)
	hired.append(id)
	crew[id] = _fresh()
	Shop.log_event("%s starts today." % label(id), "good")
	changed.emit()
	Progress.changed.emit()
	return true


## Lets someone go. The signing fee is not refunded.
func let_go(id: String) -> bool:
	if not hired.has(id):
		return false
	_leave(id)
	Shop.log_event("You let %s go." % label(id))
	changed.emit()
	Progress.changed.emit()
	return true


func gain_xp(id: String, amount: int) -> void:
	if not hired.has(id) or amount <= 0:
		return
	var p := info(id)
	p.xp = int(p.xp) + amount
	var grew := false
	while int(p.level) < LEVEL_XP.size() and int(p.xp) >= int(LEVEL_XP[int(p.level)]):
		p.level = int(p.level) + 1
		grew = true
	if grew:
		var line := "%s is now %s (level %d)." % [ROLES[id].name, LEVEL_NAMES[int(p.level) - 1].to_lower(), int(p.level)]
		_news.append(line)
		Shop.log_event(line, "good")
		changed.emit()
		Progress.changed.emit()


## Anyone waiting on an answer about a raise this morning.
func raise_requests() -> Array[String]:
	var out: Array[String] = []
	for id in hired:
		if info(id).asking:
			out.append(id)
	return out


## Says yes to a raise: their wage goes up a step and their mood with it.
func agree_raise(id: String) -> bool:
	if not hired.has(id) or not info(id).asking:
		return false
	var p := info(id)
	p.asking = false
	p.raises = int(p.raises) + 1
	_cheer(id, RAISE_MOOD)
	Shop.log_event("%s's wage is now %s a day." % [ROLES[id].name, Market.format_money(wage(id))], "good")
	changed.emit()
	return true


## Says no. They take it badly and ask again in a few days.
func refuse_raise(id: String) -> bool:
	if not hired.has(id) or not info(id).asking:
		return false
	var p := info(id)
	p.asking = false
	p.asked_day = Shop.day
	_cheer(id, REFUSE_MOOD)
	Shop.log_event("%s didn't get the raise and isn't happy about it." % ROLES[id].name, "bad")
	changed.emit()
	return true


## One line for the morning briefing about the staff, or "" on a quiet morning.
func morning_line() -> String:
	var bits: Array[String] = []
	for id in hired:
		var p := info(id)
		if p.today == "sick":
			bits.append("%s called in sick" % ROLES[id].name)
		elif p.today == "grumpy":
			bits.append("%s is in a foul mood" % ROLES[id].name)
		if p.asking:
			bits.append("%s wants a raise" % ROLES[id].name)
	return "" if bits.is_empty() else "Staff: %s." % ", ".join(bits)


func _fresh() -> Dictionary:
	return {"xp": 0, "level": 1, "mood": START_MOOD, "raises": 0, "days": 0, "asking": false, "asked_day": -ASK_AGAIN_DAYS, "today": ""}


func _cheer(id: String, amount: float) -> void:
	var p := info(id)
	p.mood = clampf(float(p.mood) + amount, 0.0, 100.0)


func _leave(id: String) -> void:
	hired.erase(id)
	crew.erase(id)


## The morning roll: who quits, who asks for more money, who has a bad day. Once a
## day, and the same each time the day is replayed from a save.
func _morning(day: int) -> void:
	if day == _rolled_day:
		return
	_rolled_day = day
	var rng := RandomNumberGenerator.new()
	for id in hired.duplicate():
		var p := info(id)
		p.today = ""
		if int(p.days) == 0:
			continue # nobody has a bad first day
		rng.seed = hash([_seed, day, id])
		if float(p.mood) <= 0.0:
			_leave(id)
			Shop.log_event("%s has had enough and quit. Pay staff what they're worth." % label(id), "bad")
			Progress.changed.emit()
			continue
		if not p.asking and raises_owed(id) > 0 and day - int(p.asked_day) >= ASK_AGAIN_DAYS:
			p.asking = true
		var odds := BAD_DAY_BASE + BAD_DAY_LOW * maxf(0.0, BAD_DAY_MOOD - float(p.mood)) / BAD_DAY_MOOD
		if rng.randf() < odds:
			p.today = "sick" if rng.randf() < SICK_SHARE else "grumpy"
	changed.emit()


func _on_noted(key: String, amount: float) -> void:
	if key == "robbers_stopped" and on_duty("guard"):
		gain_xp("guard", XP_PER_STOP * int(amount))


## Closing time: pay whoever came in, and the day's work counts toward their next level.
func _pay_wages(_day: int) -> void:
	for id in hired.duplicate():
		var p := info(id)
		if p.today == "sick":
			continue
		Day.add_expense("Wages: %s" % ROLES[id].name, wage(id))
		p.days = int(p.days) + 1
		var owed := raises_owed(id)
		_cheer(id, PAID_FAIR_MOOD if owed == 0 else -UNDERPAID_MOOD * owed)
		gain_xp(id, int(XP_PER_DAY[id]))
	changed.emit()


func _report(_day: int, report: Dictionary) -> void:
	for line in _news:
		report.lines.append(line)
	_news.clear()


func to_dict() -> Dictionary:
	return {"hired": hired.duplicate(), "crew": crew.duplicate(true), "rolled_day": _rolled_day, "seed": _seed}


func from_dict(d: Dictionary) -> void:
	hired.clear()
	crew.clear()
	_news.clear()
	for id in d.get("hired", []):
		if ROLES.has(str(id)) and not hired.has(str(id)):
			hired.append(str(id))
	var saved: Dictionary = d.get("crew", {})
	for id in hired:
		var p := _fresh()
		var s: Dictionary = saved.get(id, {})
		for key in p:
			if s.has(key):
				p[key] = s[key]
		# JSON brings numbers back as floats
		for key in ["xp", "level", "raises", "days", "asked_day"]:
			p[key] = int(p[key])
		p.today = str(p.today)
		p.asking = bool(p.asking)
		crew[id] = p
	_rolled_day = int(d.get("rolled_day", 0))
	_seed = int(d.get("seed", randi()))
	changed.emit()
