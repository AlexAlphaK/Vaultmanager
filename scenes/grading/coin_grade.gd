class_name CoinGrade
extends RefCounted
## Coin grading for collectors, once the grading lamp is bought: now and then a collector
## brings an old coin and asks for its grade on the 70-point scale. Grade it right and
## they pay a fee (and a tip for the exact grade); miss by much, or miss that it was
## cleaned, and word gets round. What sets a coin's grade, as the bench shows it:
##   wear      circulated coins (G to AU) lose the detail on their high points first;
##             the more wear, the wider the flat, dull plateaus and the softer the letters
##   lustre    the "cartwheel" of light that spins round a mint-state coin as the lamp
##             moves; wear and cleaning break it
##   marks     bag marks from coins knocking together; mint-state grades (MS) are mostly
##             a count of them
##   cleaned   a cleaned coin has fine parallel hairlines that only show under the loupe
##             with the lamp low, and no real lustre
## GradeArt paints the coin from these numbers; GradingBench is the bench.

## The grades on the bench, worst to best. wear: how much of the relief is worn flat
## (0-1); lustre: share of the cartwheel left; marks: how many bag marks.
const GRADES: Array[Dictionary] = [
	{"id": "G-4", "name": "Good", "wear": 0.92, "lustre": 0.0, "marks": Vector2i(4, 8),
		"guide": "Rim worn into the letters. The design is a flat outline."},
	{"id": "VG-8", "name": "Very Good", "wear": 0.8, "lustre": 0.0, "marks": Vector2i(4, 8),
		"guide": "Letters and rim all there. The design is worn flat, no detail inside it."},
	{"id": "F-12", "name": "Fine", "wear": 0.65, "lustre": 0.0, "marks": Vector2i(4, 8),
		"guide": "About half the detail left. Wide smooth plateaus on the design."},
	{"id": "VF-20", "name": "Very Fine", "wear": 0.5, "lustre": 0.05, "marks": Vector2i(4, 8),
		"guide": "Most of the detail left. The high points are flat and dull."},
	{"id": "XF-40", "name": "Extremely Fine", "wear": 0.32, "lustre": 0.25, "marks": Vector2i(3, 7),
		"guide": "All the detail, light wear on the very top. A little lustre near the letters."},
	{"id": "AU-50", "name": "About Uncirculated", "wear": 0.18, "lustre": 0.55, "marks": Vector2i(3, 7),
		"guide": "A rub on the high points. Half the lustre left: the cartwheel is broken."},
	{"id": "AU-58", "name": "Choice About Unc.", "wear": 0.08, "lustre": 0.85, "marks": Vector2i(3, 6),
		"guide": "The slightest rub on the very top. The cartwheel only breaks there."},
	{"id": "MS-62", "name": "Mint State", "wear": 0.0, "lustre": 0.9, "marks": Vector2i(9, 12),
		"guide": "No wear at all. Lots of bag marks: count 9 or more."},
	{"id": "MS-65", "name": "Gem Mint State", "wear": 0.0, "lustre": 1.0, "marks": Vector2i(4, 6),
		"guide": "No wear, full lustre, a few bag marks: 4 to 6."},
	{"id": "MS-67", "name": "Superb Gem", "wear": 0.0, "lustre": 1.0, "marks": Vector2i(0, 1),
		"guide": "No wear, full lustre, a mark at most. A gem."},
]
## Odds a coin has been cleaned (it then grades as "details": the grade, plus Cleaned).
const CLEANED_ODDS := 0.15
## What cleaning leaves of the lustre.
const CLEANED_LUSTRE := 0.25
## Odds an arrival is a collector with a coin to grade, once the lamp is bought.
const ODDS := 0.08
const MIN_DAY := 2
## The fee for a grade within one step, times (1 + TIER_FEE x tier); the exact grade
## adds a tip.
const FEE := 70.0
const TIER_FEE := 0.6
const TIP := 0.6
const OWNER_NAMES := ["Professor Hale", "Mr. Whitcombe", "Dr. Ng", "Mrs. Pemberton-Cross", "Arthur Bell", "Lena Fox"]
const ASK_LINES := ["What would you call this one? Be honest.", "I've had this since I was a boy. What grade is it?",
	"Bought it at an estate sale. I think it's a beauty.", "Before I send it off to be slabbed, what's your grade?",
	"Settle an argument with my brother: what grade?"]

## The coin's truth: index into GRADES, whether it was cleaned, and the seed of its art.
var grade := 0
var cleaned := false
var seed := 0
var item: BullionItem
## What its owner hopes it grades.
var hoped := 0
## Bag marks, in coin pixels from the centre at the bench's 1x size: [from, to] pairs.
var marks: Array = []


static var _hooked := false


static func hook_up() -> void:
	if _hooked:
		return
	_hooked = true
	Progress.register_upgrade("grading_lamp", {"name": "Grading lamp and loupe", "cost": 5000.0, "tier": 0, "line": "tools",
		"desc": "Collectors start bringing old coins to be graded. Read the wear, the lustre and the bag marks: a right grade earns a fee and a good word.",
		"effects": {}})


static func owned() -> bool:
	return Progress.has_upgrade("grading_lamp")


## A new coin in grade `g` (or a random one).
static func create(rng: RandomNumberGenerator, coin: BullionItem, g := -1) -> CoinGrade:
	var cg := CoinGrade.new()
	cg.item = coin
	cg.seed = rng.randi() % 1000000
	# collectors bring nice coins more often than worn ones
	cg.grade = g if g >= 0 else _weighted_grade(rng)
	cg.cleaned = rng.randf() < CLEANED_ODDS and cg.grade < GRADES.size() - 1
	# owners think their coins are better than they are
	cg.hoped = clampi(cg.grade + (rng.randi_range(0, 2) if rng.randf() < 0.7 else 0), 0, GRADES.size() - 1)
	var span: Vector2i = GRADES[cg.grade].marks
	var n := rng.randi_range(span.x, span.y)
	for k in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.85) * GradeArt.RADIUS
		var from := Vector2.from_angle(a) * d
		var to := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 3.5)
		cg.marks.append([from, to])
	return cg


static func _weighted_grade(rng: RandomNumberGenerator) -> int:
	const WEIGHTS := [0.5, 0.7, 0.9, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.5]
	var total := 0.0
	for w in WEIGHTS:
		total += w
	var roll := rng.randf() * total
	for i in WEIGHTS.size():
		roll -= WEIGHTS[i]
		if roll < 0.0:
			return i
	return 5


func wear() -> float:
	return float(GRADES[grade].wear)


func lustre() -> float:
	return float(GRADES[grade].lustre) * (CLEANED_LUSTRE if cleaned else 1.0)


func id() -> String:
	return GRADES[grade].id


static func grade_id(i: int) -> String:
	return GRADES[clampi(i, 0, GRADES.size() - 1)].id


## The fee for a grade within one step, at the shop's tier.
static func fee() -> float:
	return FEE * (1.0 + TIER_FEE * Progress.tier)


## How a call went: {"steps": grades off, "cleaned_ok", "pay", "rep", "mood", "say", "log"}.
func judge(called: int, called_cleaned: bool, owner: String) -> Dictionary:
	var steps := absi(called - grade)
	var cleaned_ok := called_cleaned == cleaned
	var out := {"steps": steps, "cleaned_ok": cleaned_ok, "pay": 0.0, "rep": 0.0, "mood": "good"}
	var truth := id() + (" (cleaned)" if cleaned else "")
	if not cleaned_ok and cleaned:
		out.rep = -0.05
		out.mood = "bad"
		out.say = "The grading service says it's been cleaned. You didn't see the hairlines?"
		out.log = "%s's coin had been cleaned and you missed it. It's %s." % [owner, truth]
	elif not cleaned_ok:
		out.rep = -0.03
		out.mood = "bad"
		out.say = "Cleaned? It has never touched a cloth. I'll take it elsewhere."
		out.log = "You called %s's original %s coin cleaned. It wasn't." % [owner, id()]
	elif steps == 0:
		out.pay = fee() * (1.0 + TIP)
		out.rep = 0.03
		out.say = "Spot on. You've got the eye. Here, keep the change."
		out.log = "Graded %s's coin %s, spot on. Fee and tip %s." % [owner, truth, Market.format_money(out.pay)]
	elif steps == 1:
		out.pay = fee()
		out.rep = 0.01
		out.say = "Close enough for me. Thank you."
		out.log = "Graded %s's coin %s; it's %s. Fee %s." % [owner, grade_id(called), truth, Market.format_money(out.pay)]
	elif steps == 2:
		out.mood = "bad"
		out.rep = -0.02
		out.say = "Hm. That's not what I'd have said."
		out.log = "Graded %s's coin %s, but it's %s. No fee." % [owner, grade_id(called), truth]
	else:
		out.mood = "bad"
		out.rep = -0.06
		out.say = "%s? Really? I don't think you know coins." % grade_id(called)
		out.log = "Graded %s's coin %s, but it's %s. They left grumbling." % [owner, grade_id(called), truth]
	return out


## A collector bringing a coin to grade, or null when none comes in.
static func next_customer(rng: RandomNumberGenerator, event := {}) -> Customer:
	if not owned() or not event.is_empty() or Shop.day < MIN_DAY or not Tutorial.first_day_done:
		return null
	if rng.randf() >= ODDS:
		return null
	return customer(rng)


static func customer(rng: RandomNumberGenerator, g := -1) -> Customer:
	var coins := Shop.rare_list()
	coins.append_array(Shop.coin_list())
	var c := Customer.new()
	c.seed = rng.randi()
	c.kind = "grade"
	c.archetype = "collector"
	c.name = OWNER_NAMES[rng.randi() % OWNER_NAMES.size()]
	c.item = coins[rng.randi() % mini(coins.size(), 8)] if rng.randf() < 0.75 else coins[rng.randi() % coins.size()]
	c.qty = 1
	c.grading = create(rng, c.item, g)
	c.say = ASK_LINES[rng.randi() % ASK_LINES.size()]
	c.max_patience = 90.0 * (1.0 + Progress.effect("patience"))
	c.patience = c.max_patience
	c.set_look(PeopleArt.random_look(rng))
	return c
