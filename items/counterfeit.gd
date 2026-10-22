class_name Counterfeit
extends RefCounted
## The kinds of fake coin customers try to sell, and what each does to the
## readings and to the coin's look. Harder fakes unlock on later days.

const KINDS := {
	"steel": {
		"label": "gold-plated steel", "min_day": 1, "metals": ["XAU", "XAG", "XPT"],
		"weight": {"XAU": 0.41, "XAG": 0.75, "XPT": 0.37}, "d_mm": 0.0, "t_mm": 0.06,
		"magnet": "strong", "ring": Vector2(0.25, 0.6), "palette": "", "wear": "steel",
		"soft_strike": true, "misprint": 0.5,
	},
	"brass": {
		"label": "brass copy", "min_day": 1, "metals": ["XAU", "XAG"],
		"weight": {"XAU": 0.44, "XAG": 0.81, "XPT": 0.40}, "d_mm": 0.0, "t_mm": 0.10,
		"magnet": "none", "ring": Vector2(0.35, 0.7), "palette": "brass", "wear": "",
		"soft_strike": true, "misprint": 0.5,
	},
	"clad": {
		"label": "copper-nickel clad", "min_day": 2, "metals": ["XAG"],
		"weight": {"XAU": 0.47, "XAG": 0.86, "XPT": 0.43}, "d_mm": 0.0, "t_mm": 0.0,
		"magnet": "none", "ring": Vector2(0.4, 0.8), "palette": "", "wear": "copper",
		"soft_strike": false, "misprint": 0.2,
	},
	"tungsten": {
		"label": "tungsten core", "min_day": 2, "metals": ["XAU", "XPT"],
		"weight": {"XAU": 0.995, "XAG": 0.995, "XPT": 0.99}, "d_mm": 0.45, "t_mm": 0.22,
		"magnet": "none", "ring": Vector2(0.2, 0.75), "palette": "", "wear": "",
		"soft_strike": false, "misprint": 0.0,
	},
}


## Fake kinds that make sense for this metal on this day.
static func kinds_for(metal: String, day: int) -> Array[String]:
	var out: Array[String] = []
	for id in KINDS:
		var k: Dictionary = KINDS[id]
		if k.min_day <= day and metal in k.metals:
			out.append(id)
	return out


static func label(kind: String) -> String:
	return Loc.t(KINDS[kind].label if KINDS.has(kind) else "genuine")


## What the testing tools read for one coin, genuine when `kind` is "".
## weight g, diameter and thickness mm, ring seconds and Hz, magnet reaction.
static func readings(item: BullionItem, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	if kind == "":
		var ring := item.ring_seconds()
		return {
			"g": item.weight_g + rng.randfn(0.0, 0.012),
			"mm": item.diameter_mm + rng.randfn(0.0, 0.02),
			"thick": item.thickness_mm + rng.randfn(0.0, 0.01),
			"ring": rng.randf_range(ring.x, ring.y),
			"hz": item.ring_hz() * rng.randf_range(0.985, 1.015),
			"magnet": "slight" if item.metal == "XAG" else "none",
		}
	var k: Dictionary = KINDS[kind]
	return {
		"g": item.weight_g * float(k.weight.get(item.metal, 0.5)) + rng.randfn(0.0, 0.04),
		"mm": item.diameter_mm + k.d_mm + rng.randfn(0.0, 0.025),
		"thick": item.thickness_mm + k.t_mm + rng.randfn(0.0, 0.015),
		"ring": rng.randf_range(k.ring.x, k.ring.y),
		"hz": rng.randf_range(900.0, 1500.0),
		"magnet": k.magnet,
	}
