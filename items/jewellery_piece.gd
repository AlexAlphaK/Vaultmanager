class_name JewelleryPiece
extends RefCounted
## A piece of jewellery a customer brings in: what they claim it is, and what it
## really is. Claims can be wrong both ways (plated, under-karat, a simulant stone,
## or a piece that is better than its owner thinks). Values come from live prices.

const GOLD_GRADES: Array[String] = ["10K", "14K", "18K", "22K"]
const PURITY := {"plated": 0.0, "10K": 0.417, "14K": 0.585, "18K": 0.750, "22K": 0.916, "925": 0.925, "PT950": 0.950}
const GRADE_NAMES := {"10K": "10K gold", "14K": "14K gold", "18K": "18K gold", "22K": "22K gold",
	"925": "sterling silver", "PT950": "platinum", "plated": "plated"}
const KIND_NAMES := {"ring": "ring", "chain": "chain", "bracelet": "bracelet", "pendant": "pendant"}
## Acids in the testing kit, in the order of the bottles on the bench.
const ACIDS: Array[String] = ["10K", "14K", "18K", "22K", "AG", "PT"]
## A carat weighs 0.2 g.
const CARAT_G := 0.2
## What the refiner pays for metal, as a share of melt.
const REFINER_RATE := 0.98
## Odds a piece is not what its owner says (plated, under-karat, a fake stone, or
## better than claimed): FRAUD_ODDS.x on day 1, rising by .y a day up to the max.
const FRAUD_ODDS := Vector2(0.25, 0.01)
const FRAUD_ODDS_MAX := 0.4

var kind := "ring"
var metal := "XAU" # what it is claimed to be made of
var claimed_grade := "18K"
var true_grade := "18K" # or "plated"
var base_metal := "" # under the plating: "brass", "copper", "steel" or "nickel"
var stamp := "18K"
var crude_stamp := false # struck by hand on a fake: uneven letters, doubled strike
var stone := "" # "", "diamond", "cz", "glass" or "moissanite"
var carat := 0.0
var weight_g := 5.0 # true gross weight
var claimed_g := 5.0
var scam := false # the customer knows
var seed := 0


static func create(day: int, rng: RandomNumberGenerator) -> JewelleryPiece:
	var p := JewelleryPiece.new()
	p.seed = rng.randi()
	var roll := rng.randf()
	p.kind = "ring" if roll < 0.4 else ("chain" if roll < 0.65 else ("bracelet" if roll < 0.8 else "pendant"))
	roll = rng.randf()
	p.metal = "XAU" if roll < 0.7 else ("XAG" if roll < 0.9 or p.kind == "pendant" else "XPT")
	match p.metal:
		"XAU":
			roll = rng.randf()
			p.claimed_grade = "14K" if roll < 0.4 else ("18K" if roll < 0.75 else ("10K" if roll < 0.9 else "22K"))
		"XAG":
			p.claimed_grade = "925"
		"XPT":
			p.claimed_grade = "PT950"
	p.true_grade = p.claimed_grade
	var w: Vector2 = {"ring": Vector2(2.5, 7.0), "chain": Vector2(8.0, 30.0), "bracelet": Vector2(10.0, 28.0), "pendant": Vector2(3.0, 9.0)}[p.kind]
	if p.metal == "XAG":
		w *= 1.8
	elif p.metal == "XPT":
		w *= 1.3
	p.weight_g = snappedf(rng.randf_range(w.x, w.y), 0.01)
	if (p.kind == "ring" and rng.randf() < 0.6) or (p.kind == "pendant" and rng.randf() < 0.75):
		p.stone = "diamond"
		p.carat = snappedf(clampf(0.08 + pow(rng.randf(), 2.2) * 1.2, 0.08, 1.3), 0.01)
		p.weight_g += p.carat * CARAT_G
	p.stamp = default_stamp(p.true_grade, rng)

	var fraud_odds := minf(FRAUD_ODDS_MAX, FRAUD_ODDS.x + FRAUD_ODDS.y * (day - 1))
	if rng.randf() < fraud_odds:
		var options: Array[String] = ["plated"]
		if p.metal == "XAU" and p.claimed_grade != "10K":
			options.append("underkarat")
		if p.metal == "XAU" and p.claimed_grade != "22K":
			options.append("undersold")
		if p.stone != "":
			options.append_array(["stone", "stone"])
		p.apply_fraud(options[rng.randi() % options.size()], day, rng)
	p.claimed_g = snappedf(p.weight_g * rng.randf_range(0.95, 1.18 if p.scam else 1.06), 0.5)
	return p


## Changes the truth behind the claim. `kind`: "plated", "underkarat", "undersold" or "stone".
func apply_fraud(kind_of_fraud: String, day: int, rng: RandomNumberGenerator) -> void:
	match kind_of_fraud:
		"plated":
			true_grade = "plated"
			base_metal = ["brass", "copper", "steel"][rng.randi() % 3] if metal == "XAU" else "nickel"
			# plated base metal is lighter than gold, heavier than nothing
			weight_g *= 0.55 if metal == "XAU" else (0.85 if metal == "XAG" else 0.45)
			if rng.randf() < 0.45:
				# honestly marked plating that the owner never understood
				stamp = {"XAU": [claimed_grade + " GP", claimed_grade + " HGE", "1/20 " + claimed_grade + " GF", claimed_grade + " RGP"][rng.randi() % 4],
					"XAG": "EPNS", "XPT": "RH PL"}[metal]
			else:
				scam = true
				crude_stamp = true
		"underkarat":
			var n := GOLD_GRADES.find(claimed_grade)
			true_grade = GOLD_GRADES[rng.randi_range(0, n - 1)]
			stamp = default_stamp(claimed_grade, rng)
			crude_stamp = rng.randf() < 0.5
			scam = crude_stamp
			weight_g *= 0.95
		"undersold":
			var n := GOLD_GRADES.find(claimed_grade)
			true_grade = GOLD_GRADES[rng.randi_range(n + 1, GOLD_GRADES.size() - 1)]
			stamp = default_stamp(true_grade, rng)
		"stone":
			var fakes: Array[String] = ["cz", "glass"]
			if day >= 3:
				fakes.append("moissanite")
			stone = fakes[rng.randi() % fakes.size()]
			scam = rng.randf() < 0.5


## What a genuine piece of this grade usually has stamped on it.
static func default_stamp(grade: String, rng: RandomNumberGenerator) -> String:
	var options: Array = {"10K": ["10K", "417"], "14K": ["14K", "585"], "18K": ["18K", "750"], "22K": ["22K", "916"],
		"925": ["925", "STER"], "PT950": ["PT950", "950"]}.get(grade, ["?"])
	return options[rng.randi() % options.size()]


static func metal_of_grade(grade: String, fallback: String) -> String:
	if grade in GOLD_GRADES:
		return "XAU"
	return {"925": "XAG", "PT950": "XPT"}.get(grade, fallback)


## Grades a player can pick when appraising this piece.
func grade_options() -> Array[String]:
	var out: Array[String] = ["plated"]
	match metal:
		"XAU":
			out.append_array(GOLD_GRADES)
		"XAG":
			out.append("925")
		"XPT":
			out.append("PT950")
	return out


## "18K gold ring with a 0.50 ct diamond", as the customer describes it.
func title() -> String:
	var t := "%s %s" % [GRADE_NAMES[claimed_grade], KIND_NAMES[kind]]
	if stone != "":
		t += " with a %.2f ct diamond" % carat
	return t


func short_title() -> String:
	return "%s %s" % [claimed_grade if metal == "XAU" else GRADE_NAMES[claimed_grade], KIND_NAMES[kind]]


## Metal value of `grams` gross at `grade`, plus the diamond if `diamond_real`.
func value_as(grade: String, diamond_real: bool, grams: float) -> float:
	var net := maxf(grams - carat * CARAT_G, 0.0)
	var metal_value := 0.0
	if grade != "plated":
		metal_value = Market.value_of(metal_of_grade(grade, metal), net * PURITY[grade] / Market.TROY_OZ_GRAMS)
	return metal_value + (diamond_value(carat) if diamond_real and stone != "" else 0.0)


## What the shop would pay for what the customer says it is.
func claimed_value() -> float:
	return value_as(claimed_grade, stone != "", claimed_g)


func true_value() -> float:
	return value_as(true_grade, stone == "diamond", weight_g)


## What the refiner and the diamond dealer pay for the piece.
func refiner_payout() -> float:
	var metal_part := value_as(true_grade, false, weight_g) * REFINER_RATE
	return metal_part + (diamond_value(carat) if stone == "diamond" else 0.0)


## Dealer buying price for a well-cut white diamond. Bigger stones cost more per carat.
static func diamond_value(ct: float) -> float:
	return 2600.0 * pow(ct, 1.6)


## The lowest offer the customer takes: what they believe it's worth, but never
## more than it really is once you show them (a scammer takes anything).
func expected_value() -> float:
	if scam:
		return true_value()
	return minf(value_as(claimed_grade, stone != "", weight_g), true_value())


# ---------------------------------------------------------------- test readings

## What each test kit reading shows. `acid` is one of ACIDS.
## Returns "holds" (streak stays), "fades" (dissolves slowly), "fizz" (base metal
## bubbles green), "milky" (silver under nitric), "red" (silver acid on sterling).
func acid_reaction(acid: String) -> String:
	if true_grade == "plated":
		return "fizz" if acid != "AG" else "green"
	var real_metal := metal_of_grade(true_grade, metal)
	match acid:
		"AG":
			return "red" if real_metal == "XAG" else "holds"
		"PT":
			return "holds" if real_metal == "XPT" else ("milky" if real_metal == "XAG" else "fades")
	if real_metal == "XPT":
		return "holds"
	if real_metal == "XAG":
		return "milky"
	return "holds" if PURITY[true_grade] >= PURITY[acid] - 0.001 else "fades"


## What a genuine piece of the claimed grade does with this acid.
func expected_acid(acid: String) -> String:
	var copy := JewelleryPiece.new()
	copy.metal = metal
	copy.true_grade = claimed_grade
	return copy.acid_reaction(acid)


## "strong" (plated steel), "clasp" (the steel spring in a clasp) or "none".
func magnet() -> String:
	if true_grade == "plated" and base_metal == "steel":
		return "strong"
	return "clasp" if kind in ["chain", "bracelet"] else "none"


## Lights on the thermal diamond tester's 10-LED bar. Moissanite fools it.
func tester_leds() -> int:
	return {"diamond": 10, "moissanite": 10, "cz": 3, "glass": 1}.get(stone, 0)


## Colour ramp name for how the piece looks: the plating keeps the claimed colour.
func palette_name() -> String:
	var grade := claimed_grade if true_grade == "plated" else true_grade
	match grade:
		"10K":
			return "gold10"
		"14K":
			return "gold14"
		"18K":
			return "gold"
		"22K":
			return "gold22"
		"925":
			return "silver"
	return "plat"
