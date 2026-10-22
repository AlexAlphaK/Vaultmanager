extends Node
## The story: a short campaign from the corner counter to the Town landmark.
##   Mags Holloway   ran the corner counter for forty years and sold it to you. She drops
##                   by to set each chapter's goals and hands over a reward when you meet them.
##   Victor Sterling owns Sterling Bullion Co. across the street (see Rivals). He wanted the
##                   corner counter for himself, and he turns up as you grow: to sneer, to
##                   start a price war, and in the end to shake your hand.
## Each chapter has a few goals, measured like achievements (Records.value_of) plus a few
## of its own (value_of). Meet them all and the chapter closes: its line goes in tonight's
## summary, and the next chapter's visitors walk in at the next chance, Mags first with the
## reward. The visitors are talk-only "visit" customers, and never cross to a rival.
## Saved with the game; a save from before the story picks up at the first chapter it has
## not yet finished, without paying out the ones behind it.

signal changed
## A chapter's goals were all met. `chapter` is its index in CHAPTERS.
signal chapter_done(chapter: int)

const MAGS_LOOK := {"skin": "#e3b48a", "hair": "#d8d8d0", "hair_style": 4, "shirt": "#8a5bb0", "top": 1,
	"pants": "#2f3442", "glasses": true, "beard": false, "hat": false, "apron": false}
const STERLING_LOOK := {"skin": "#f2cfa8", "hair": "#5a3418", "hair_style": 3, "shirt": "#1f1f24", "top": 1,
	"pants": "#1f1f24", "glasses": false, "beard": false, "hat": false, "apron": false, "chain": true}
const PEOPLE := {
	"mags": {"name": "Mags Holloway", "look": MAGS_LOOK, "tag": "mentor"},
	"sterling": {"name": "Victor Sterling", "look": STERLING_LOOK, "tag": "rival"},
}

## A visit: who comes, what they say at the counter (short, it fits the card), the shop
## log line when they leave, and optionally a rival move it sets off ("rival_move").
const BEATS := {
	"mags_hello": {"who": "mags",
		"say": "Forty years I ran this counter. Lesson one: test everything. I left you a list.",
		"log": "Mags Holloway left you her list of goals. See Story on the morning panel."},
	"mags_name": {"who": "mags",
		"say": "Not bad, kid. Here's a little float. Now let's make the town know your name.",
		"log": "Mags is pleased. Next: make a name for the shop."},
	"sterling_sneer": {"who": "sterling",
		"say": "Mags sold to you? Cute. Enjoy the corner while it lasts.",
		"log": "Victor Sterling came over to size you up."},
	"mags_main": {"who": "mags",
		"say": "Main Street! Now give people a reason to come back. And hire some help.",
		"log": "Mags is proud of the move to Main Street."},
	"sterling_war": {"who": "sterling", "rival_move": "price_war",
		"say": "Main Street is my street. Let's see how you like a price war.",
		"log": "Victor Sterling declared a price war. Beat Sterling on the town map answers it."},
	"mags_house": {"who": "mags",
		"say": "A bullion house. Victor's worried, I can tell. Beat him fair and square.",
		"log": "Mags says it's time to take on Sterling Bullion."},
	"sterling_family": {"who": "sterling",
		"say": "Sixty years my family's been on this street. You won't outgrow us.",
		"log": "Victor Sterling is rattled."},
	"mags_bank": {"who": "mags",
		"say": "You've the name and the money. The old bank on the square is for sale. Buy it.",
		"log": "Mags showed you the old bank building on the square."},
	"sterling_handshake": {"who": "sterling",
		"say": "All right. You win the street. If you ever need a buyer for scrap, I'm across the road.",
		"log": "Victor Sterling shook your hand. He meant it, mostly."},
	"mags_ribbon": {"who": "mags",
		"say": "Forty years at a corner counter, and look what my apprentice built. Cut the ribbon!",
		"log": "Mags Holloway cut the ribbon on your Town landmark."},
}

## The chapters, in order. `visits` walk in when the chapter starts, the first carrying
## the reward for the chapter before. `letter` is Mags's note on the story page.
## A goal is {"key", "goal", "text"}; key is read by value_of().
const CHAPTERS: Array[Dictionary] = [
	{"title": "The corner counter", "visits": ["mags_hello"], "from_day": 2,
		"letter": "I sold you this counter because you've got good eyes. Use them. Test every coin, keep the regulars happy, and get through your first week in one piece.",
		"goals": [
			{"key": "caught", "goal": 3, "text": "Catch 3 fakes"},
			{"key": "deals", "goal": 15, "text": "Close 15 deals"},
			{"key": "days", "goal": 7, "text": "Finish your first week"},
		],
		"reward": {"cash": 1000.0}},
	{"title": "Making a name", "visits": ["mags_name", "sterling_sneer"],
		"letter": "Victor Sterling offered me twice what you paid, just to shut this counter down. Show him it's no pushover. Earn your stars, get bigger than Lucky's, and move to Main Street.",
		"goals": [
			{"key": "peak_rep", "goal": 3.0, "text": "Reach 3 stars"},
			{"key": "passed_pawn", "goal": 1, "text": "Get bigger than Lucky's Pawn"},
			{"key": "tier", "goal": 1, "text": "Move to Main Street"},
		],
		"reward": {"cash": 4000.0}},
	{"title": "Main Street", "visits": ["mags_main", "sterling_war"],
		"letter": "Main Street means collectors, and collectors remember who found them the coin. Fill their orders, take on staff, and work your way up to a proper bullion house.",
		"goals": [
			{"key": "orders_filled", "goal": 3, "text": "Fill 3 special orders"},
			{"key": "staff", "goal": 1, "text": "Hire your first staff"},
			{"key": "tier", "goal": 2, "text": "Move to the Bullion house"},
		],
		"reward": {"cash": 10000.0}},
	{"title": "Across the street", "visits": ["mags_house", "sterling_family"],
		"letter": "Sterling Bullion has been the biggest shop in town since before you were born. Beat Victor on worth and on name, and build the vault the landmark will need.",
		"goals": [
			{"key": "passed_sterling", "goal": 1, "text": "Get bigger than Sterling Bullion"},
			{"key": "peak_rep", "goal": 4.5, "text": "Reach 4.5 stars"},
			{"key": "peak_worth", "goal": 400000, "text": "Reach a net worth of $400,000"},
		],
		"reward": {"cash": 20000.0}},
	{"title": "The landmark", "visits": ["mags_bank", "sterling_handshake"],
		"letter": "The old bank on the square has marble floors and a vault door the size of a car. It's been empty for years, waiting for the biggest precious metal store in town.",
		"goals": [
			{"key": "tier", "goal": 3, "text": "Open the Town landmark"},
		],
		"reward": {"reputation": 0.2}},
]
## Who comes when the last chapter is done.
const FINALE := ["mags_ribbon"]

## The chapter under way, CHAPTERS.size() once the story is over.
var chapter := 0
## Goals of the current chapter already met, by index.
var met: Array[int] = []
## Visits waiting to walk in: [{"beat", "reward", "from_day"}], first one next.
var pending: Array[Dictionary] = []
## The last chapter whose letter was read on the story page, so the button can say "new".
var read_chapter := -1
## False until the story has looked at the game it is part of: a new game queues the
## first visit, a save from before the story skips the chapters it has already done.
var synced := false

var _out := "" # the visit in the shop right now
var _today: Array[String] = []
var _check_queued := false


func _ready() -> void:
	reset()
	SaveGame.register("story", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.day_started.connect(_on_day_started)
	Day.day_ended.connect(_on_day_ended)
	Shop.noted.connect(func(_k, _a): _queue_check())
	Records.changed.connect(_queue_check)
	Progress.tier_changed.connect(func(_t): _queue_check())
	Rivals.changed.connect(_queue_check)
	Staff.changed.connect(_queue_check)
	Shop.changed.connect(_queue_check)


func reset() -> void:
	chapter = 0
	met.clear()
	pending.clear()
	read_chapter = -1
	synced = false
	_out = ""
	_today.clear()
	changed.emit()


func is_finished() -> bool:
	return chapter >= CHAPTERS.size()


## How many chapters are done, for the achievement.
func chapters_done() -> int:
	return chapter


func current() -> Dictionary:
	return {} if is_finished() else CHAPTERS[chapter]


## "Chapter 2: Making a name".
func chapter_title(n := chapter) -> String:
	if n >= CHAPTERS.size():
		return tr("The end")
	return tr("Chapter %d: %s") % [n + 1, tr(CHAPTERS[n].title)]


## The value a goal's key is measured by: the story's own keys, then the ledger's.
func value_of(key: String) -> float:
	match key:
		"staff":
			return Staff.hired.size()
	return Records.value_of(key)


func goal_met(i: int) -> bool:
	return met.has(i)


## How far along goal `i` of the current chapter is, 0 to 1.
func goal_progress(i: int) -> float:
	if is_finished() or goal_met(i):
		return 1.0
	var g: Dictionary = CHAPTERS[chapter].goals[i]
	return clampf(value_of(g.key) / float(g.goal), 0.0, 1.0)


## "12 / 15", or "" for yes-or-no goals.
func goal_count(i: int) -> String:
	var g: Dictionary = CHAPTERS[chapter].goals[i]
	if float(g.goal) <= 1.0:
		return ""
	var have := minf(value_of(g.key), float(g.goal))
	if g.key == "peak_rep":
		return "%.1f / %.1f" % [have, float(g.goal)]
	if g.key == "peak_worth":
		return "%s / %s" % [Market.format_money(have), Market.format_money(g.goal)]
	return "%d / %d" % [int(have), int(g.goal)]


func goals_met_count() -> int:
	return met.size()


func has_new_letter() -> bool:
	return synced and not is_finished() and read_chapter < chapter


func mark_read() -> void:
	if read_chapter != chapter:
		read_chapter = chapter
		changed.emit()


## "Reward: $4,000" for a chapter, or "".
func reward_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	if float(r.get("cash", 0.0)) > 0.0:
		parts.append(Market.format_money(r.cash))
	if float(r.get("reputation", 0.0)) > 0.0:
		parts.append(tr("+%.1f stars") % float(r.reputation))
	return "" if parts.is_empty() else tr("Reward: ") + ", ".join(parts)


## The story visitor who walks in next, or null. The shop asks before every arrival.
func next_customer(rng: RandomNumberGenerator) -> Customer:
	if not synced or not Tutorial.first_day_done or pending.is_empty() or _out != "" or Day.phase != Day.OPEN:
		return null
	var p: Dictionary = pending[0]
	if Shop.day < int(p.from_day):
		return null
	var b: Dictionary = BEATS[p.beat]
	var who: Dictionary = PEOPLE[b.who]
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng)
	c.archetype = "story"
	c.story = p.beat
	c.name = who.name
	c.set_look(who.look)
	c.kind = "visit"
	c.piece = null
	c.bar = null
	c.assessed = {}
	c.fake = ""
	c.qty = 1
	c.say = tr(b.say)
	c.note = reward_text(p.reward)
	c.max_patience = 9999.0
	c.patience = c.max_patience
	_out = p.beat
	return c


## A word for the counter card: "mentor" or "rival".
func tag(c: Customer) -> String:
	return tr(PEOPLE[BEATS[c.story].who].tag) if BEATS.has(c.story) else ""


## The shop calls this as each customer leaves (through Customers.on_leave).
func on_leave(c: Customer) -> void:
	if c.story == "" or c.story != _out:
		return
	_out = ""
	if pending.is_empty() or pending[0].beat != c.story:
		return
	var p: Dictionary = pending.pop_front()
	var b: Dictionary = BEATS[p.beat]
	var r: Dictionary = p.reward
	if float(r.get("cash", 0.0)) > 0.0:
		Day.add_income(tr("Gift from Mags"), float(r.cash))
	if float(r.get("reputation", 0.0)) > 0.0:
		Shop.adjust_reputation(float(r.reputation))
	if b.has("rival_move"):
		Rivals.start_move(b.who, b.rival_move)
	Shop.log_event(tr(b.log), "good" if b.who == "mags" else "")
	_today.append(tr(b.log))
	changed.emit()


func _queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	_check.call_deferred()


## Ticks off goals as they are met and closes the chapter once they all are.
func _check() -> void:
	_check_queued = false
	if not synced or not Tutorial.first_day_done:
		return
	var moved := false
	while not is_finished():
		var goals: Array = CHAPTERS[chapter].goals
		for i in goals.size():
			if not met.has(i) and value_of(goals[i].key) >= float(goals[i].goal):
				met.append(i)
				moved = true
				Shop.log_event(tr("Goal met: %s.") % tr(goals[i].text), "good")
		if met.size() < goals.size():
			break
		_finish_chapter(true)
		moved = true
	if moved:
		changed.emit()


func _finish_chapter(pay: bool) -> void:
	var done := chapter
	var reward: Dictionary = CHAPTERS[done].reward if pay else {}
	chapter += 1
	met.clear()
	var visits: Array = FINALE if is_finished() else CHAPTERS[chapter].visits
	if pay:
		var line := tr("%s is done! %s will drop by.") % [chapter_title(done), PEOPLE[BEATS[visits[0]].who].name]
		_today.append(line)
		Shop.log_event(line, "good")
	_queue_visits(visits, reward)
	chapter_done.emit(done)
	Records.check()


func _queue_visits(visits: Array, reward: Dictionary, from_day := 0) -> void:
	for n in visits.size():
		pending.append({"beat": visits[n], "reward": reward if n == 0 else {}, "from_day": from_day})


func _on_day_started(day: int) -> void:
	_out = ""
	_today.clear()
	if synced:
		_queue_check()
		return
	synced = true
	if day > 1:
		# a save from before the story: skip what is already done, without the rewards
		while not is_finished() and CHAPTERS[chapter].goals.all(func(g): return value_of(g.key) >= float(g.goal)):
			chapter += 1
		if is_finished():
			changed.emit()
			return
	_queue_visits(CHAPTERS[chapter].visits, {}, int(CHAPTERS[chapter].get("from_day", 0)))
	_queue_check()
	changed.emit()


func _on_day_ended(_day: int, report: Dictionary) -> void:
	_check()
	for line in _today:
		report.lines.append(line)
	_today.clear()


func to_dict() -> Dictionary:
	return {"chapter": chapter, "met": met.duplicate(), "pending": pending.duplicate(true), "read": read_chapter}


func from_dict(d: Dictionary) -> void:
	reset()
	chapter = clampi(int(d.get("chapter", 0)), 0, CHAPTERS.size())
	for i in d.get("met", []):
		met.append(int(i))
	for p in d.get("pending", []):
		if typeof(p) == TYPE_DICTIONARY and BEATS.has(str(p.get("beat", ""))):
			var r = p.get("reward", {})
			pending.append({"beat": str(p.beat), "reward": r if typeof(r) == TYPE_DICTIONARY else {},
				"from_day": int(p.get("from_day", 0))})
	read_chapter = int(d.get("read", -1))
	synced = true
	changed.emit()
