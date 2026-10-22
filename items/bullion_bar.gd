class_name BullionBar
extends RefCounted
## A bullion bar a customer brings in, and what it really is. Fakes are built to beat
## the scale: a tungsten bar under gold plating, a gold shell around a tungsten slug,
## silver over a lead core. The ultrasound and the XRF gun see through them.
## Sizes, weights and the speed of sound are close to the real thing.

## Bars the shop sees. Thickness follows from weight, size and density.
## `tier` is the smallest shop that gets offered the bar.
const SPECS := {
	"gold_1oz": {"name": "1 oz gold bar", "metal": "XAU", "g": 31.103, "purity": 0.9999, "l": 41.0, "w": 24.0,
		"cast": false, "maker": "HELVETIA", "weight_text": "1 OZ", "fine_text": "999.9", "prefix": "HV", "tier": 0},
	"gold_100g": {"name": "100 g gold bar", "metal": "XAU", "g": 100.0, "purity": 0.9999, "l": 55.0, "w": 31.0,
		"cast": true, "maker": "NORTHSTAR", "weight_text": "100 G", "fine_text": "999.9", "prefix": "NS", "tier": 0},
	"gold_10oz": {"name": "10 oz gold bar", "metal": "XAU", "g": 311.03, "purity": 0.9999, "l": 64.0, "w": 38.0,
		"cast": true, "maker": "NORTHSTAR", "weight_text": "10 OZ", "fine_text": "999.9", "prefix": "NS", "tier": 1},
	"gold_1kg": {"name": "1 kilo gold bar", "metal": "XAU", "g": 1000.0, "purity": 0.9999, "l": 116.0, "w": 52.0,
		"cast": true, "maker": "ROYAL ASSAY", "weight_text": "1000 G", "fine_text": "999.9", "prefix": "RA", "tier": 2},
	"silver_10oz": {"name": "10 oz silver bar", "metal": "XAG", "g": 311.03, "purity": 0.999, "l": 92.0, "w": 50.0,
		"cast": true, "maker": "ARGENTA", "weight_text": "10 OZ", "fine_text": "999", "prefix": "AR", "tier": 0},
	"silver_1kg": {"name": "1 kilo silver bar", "metal": "XAG", "g": 1000.0, "purity": 0.999, "l": 118.0, "w": 60.0,
		"cast": true, "maker": "ARGENTA", "weight_text": "1 KILO", "fine_text": "999", "prefix": "AR", "tier": 0},
	"plat_1oz": {"name": "1 oz platinum bar", "metal": "XPT", "g": 31.103, "purity": 0.9995, "l": 39.0, "w": 23.0,
		"cast": false, "maker": "HELVETIA", "weight_text": "1 OZ", "fine_text": "999.5", "prefix": "HV", "tier": 0},
}
## g/cm3, and the speed of sound (m/s) for the ultrasound.
const DENSITY := {"XAU": 19.32, "XAG": 10.49, "XPT": 21.45, "W": 19.25, "Pb": 11.34, "brass": 8.5, "Cu": 8.96, "22K": 17.8}
const SOUND := {"XAU": 3240.0, "XAG": 3650.0, "XPT": 3260.0, "W": 5220.0, "Pb": 2160.0, "brass": 4700.0, "Cu": 4760.0, "22K": 3330.0}
const METAL_ELEMENT := {"XAU": "Au", "XAG": "Ag", "XPT": "Pt"}

## The kinds of fake bar. `weight` and `thick` (one number, or one per metal) scale the
## genuine values; `body` is what
## the sound travels through; `core` means only the middle of the bar hides it.
## `surface` is what the XRF reads, in percent.
const FAKES := {
	"brass": {"label": "gold-plated brass", "metals": ["XAU"], "min_day": 1, "weight": 0.44, "thick": 1.0,
		"body": "brass", "core": false, "surface": {"Au": 41.0, "Cu": 37.0, "Zn": 22.0}, "crude": true, "wear": "brass"},
	"copper": {"label": "silver-plated copper", "metals": ["XAG"], "min_day": 1, "weight": 0.855, "thick": 1.0,
		"body": "Cu", "core": false, "surface": {"Ag": 58.0, "Cu": 42.0}, "crude": true, "wear": "copper"},
	"plated_tungsten": {"label": "gold-plated tungsten", "metals": ["XAU", "XPT"], "min_day": 2, "weight": 1.0004, "thick": {"XAU": 1.0036, "XPT": 1.114},
		"body": "W", "core": false, "surface": {"Au": 64.0, "W": 33.0, "Ni": 3.0}, "crude": false, "wear": "steel"},
	"low_fine": {"label": "22 karat recast", "metals": ["XAU"], "min_day": 2, "weight": 1.0003, "thick": 1.085,
		"body": "22K", "core": false, "surface": {"Au": 91.7, "Ag": 5.2, "Cu": 3.1}, "crude": true, "wear": ""},
	"lead_core": {"label": "lead-core silver", "metals": ["XAG"], "min_day": 2, "weight": 1.031, "thick": 1.0,
		"body": "Pb", "core": true, "surface": {"Ag": 99.9}, "crude": false, "wear": ""},
	"tungsten_core": {"label": "tungsten-core gold", "metals": ["XAU"], "min_day": 3, "weight": 1.0002, "thick": 1.0,
		"body": "W", "core": true, "surface": {"Au": 99.99}, "crude": false, "wear": ""},
}
## Where a slug hides, in bar UV (0-1 across the top face), and how much of the
## thickness it takes up. Shells keep a fifth of the thickness above and below.
const CORE := Rect2(0.24, 0.22, 0.52, 0.56)
const SHELL := 0.2
## Tolerances a genuine bar stays within.
const WEIGHT_OVER := 0.001 # never under the stated weight, at most 0.1% over
const SIZE_TOL := 0.2 # mm, length and width
const THICK_TOL := 0.1
const GATE := 0.03 # the back-wall echo lands within 3% of its expected time
## What the bullion dealer pays for a genuine bar, as a share of melt.
const DEALER_RATE := 0.98
## X-ray lines the analyzer shows, keV and relative strength.
const XRF_LINES := {
	"Au": [[9.71, 1.0], [11.44, 0.62], [13.38, 0.12], [2.12, 0.2]],
	"Ag": [[22.16, 1.0], [24.94, 0.22], [2.98, 0.35]],
	"Pt": [[9.44, 1.0], [11.07, 0.6], [12.94, 0.1]],
	"W": [[8.40, 1.0], [9.67, 0.65], [11.29, 0.1]],
	"Cu": [[8.05, 1.0], [8.90, 0.17]],
	"Zn": [[8.64, 1.0], [9.57, 0.17]],
	"Ni": [[7.48, 1.0], [8.26, 0.17]],
	"Pb": [[10.55, 1.0], [12.61, 0.8]],
}

## Serial numbers of every bar the shop has bought, with the day: fakers copy
## the serials of real bars, so a number you have seen before means trouble.
static var ledger := {}
static var _hooked := false

var spec_id := "gold_1oz"
var fake := ""
var serial := ""
var cloned := false # the serial was copied from a bar you already bought
var seed := 0


static func create(day: int, tier: int, rng: RandomNumberGenerator, fake_odds := 0.3) -> BullionBar:
	var b := BullionBar.new()
	b.seed = rng.randi()
	var ids: Array[String] = []
	for id in SPECS:
		if int(SPECS[id].tier) <= tier:
			ids.append(id)
	b.spec_id = ids[rng.randi() % ids.size()]
	b.serial = new_serial(b.spec().prefix, rng)
	var kinds := fakes_for(b.metal(), day, b.spec_id)
	if not kinds.is_empty() and rng.randf() < fake_odds:
		b.make_fake(kinds[rng.randi() % kinds.size()], rng)
	return b


static func new_serial(prefix: String, rng: RandomNumberGenerator) -> String:
	return "%s %06d" % [prefix, rng.randi_range(1000, 999999)]


## Fake kinds that make sense for this metal on this day. A slug needs a thick bar.
static func fakes_for(metal_symbol: String, day: int, id := "") -> Array[String]:
	var out: Array[String] = []
	for kind in FAKES:
		var f: Dictionary = FAKES[kind]
		if f.min_day > day or not metal_symbol in f.metals:
			continue
		if f.core and id != "" and SPECS[id].g < 100.0:
			continue
		out.append(kind)
	return out


static func label(kind: String) -> String:
	return Loc.t(FAKES[kind].label if FAKES.has(kind) else "genuine")


func make_fake(kind: String, rng: RandomNumberGenerator) -> void:
	fake = kind
	# some fakers stamp the serial of a real bar, sometimes one you bought yourself
	if not ledger.is_empty() and rng.randf() < 0.4:
		var seen := ledger.keys()
		serial = seen[rng.randi() % seen.size()]
		cloned = true


func spec() -> Dictionary:
	return SPECS[spec_id]


func metal() -> String:
	return spec().metal


func display_name() -> String:
	return tr(spec().name)


func is_cast() -> bool:
	return spec().cast


func palette_name() -> String:
	return Pal.for_metal(metal())


func thickness_mm() -> float:
	var s := spec()
	return snappedf(s.g / DENSITY[s.metal] * 1000.0 / (s.l * s.w), 0.01)


func melt_value() -> float:
	return Market.value_of(metal(), spec().g * spec().purity / Market.TROY_OZ_GRAMS)


## What is really in it: nothing of value in a plated bar, the shell in a cored one.
func true_value() -> float:
	if fake == "":
		return melt_value()
	match fake:
		"low_fine":
			return Market.value_of("XAU", spec().g * 0.917 / Market.TROY_OZ_GRAMS)
		"tungsten_core", "lead_core":
			var shell := 1.0 - (CORE.size.x * CORE.size.y) * (1.0 - SHELL * 2.0)
			return melt_value() * shell * 0.9 # the dealer charges to cut it apart
	return 0.0


## What the bullion dealer pays. `extra_rate` (from upgrades) only applies to genuine bars.
func dealer_payout(extra_rate := 0.0) -> float:
	return true_value() * (DEALER_RATE + (extra_rate if fake == "" else 0.0))


func _thick_factor() -> float:
	if fake == "":
		return 1.0
	var k = FAKES[fake].thick
	return float(k.get(metal(), 1.0)) if typeof(k) == TYPE_DICTIONARY else float(k)


## Expected back-wall echo of a genuine bar, microseconds there and back.
func expected_echo_us() -> float:
	return thickness_mm() * 2.0 / SOUND[metal()] * 1000.0


## The ultrasound at one spot on the top face (`uv` 0-1). Returns the echoes the
## flaw detector shows: {"back": us, "interface": us or -1, "amp": back-wall strength}.
func echo_at(uv: Vector2) -> Dictionary:
	var t := thickness_mm() * _thick_factor()
	var own: float = SOUND[metal()]
	if fake == "":
		return {"back": t * 2.0 / own * 1000.0, "interface": -1.0, "amp": 1.0}
	var f: Dictionary = FAKES[fake]
	var body: float = SOUND[f.body]
	if not f.core:
		return {"back": t * 2.0 / body * 1000.0, "interface": -1.0, "amp": 0.8}
	if not CORE.has_point(uv):
		return {"back": t * 2.0 / own * 1000.0, "interface": -1.0, "amp": 1.0}
	var shell := t * SHELL
	var core := t - shell * 2.0
	var there := shell * 2.0 / own + core / body
	return {"back": (there * 2.0) * 1000.0, "interface": shell * 2.0 / own * 1000.0, "amp": 0.45}


## Whether the echo at `uv` lands outside the gate or shows a second interface.
func echo_off(uv: Vector2) -> bool:
	var e := echo_at(uv)
	return e.interface >= 0.0 or absf(e.back / expected_echo_us() - 1.0) > GATE


## What the bench tools read: weight g, length, width and thickness mm, and the
## surface composition from the XRF gun in percent.
func readings(rng: RandomNumberGenerator) -> Dictionary:
	var s := spec()
	var f: Dictionary = FAKES[fake] if fake != "" else {}
	var w: float = s.g * (1.0 + rng.randf_range(0.0001, 0.0007))
	if fake != "":
		w = s.g * float(f.weight) * (1.0 + rng.randf_range(0.0, 0.0002))
	var t := thickness_mm() * _thick_factor()
	var surface: Dictionary = {METAL_ELEMENT[s.metal]: snappedf(s.purity * 100.0, 0.01)} if fake == "" else f.surface.duplicate()
	if surface.size() > 1:
		var total := 0.0
		for el in surface:
			surface[el] = maxf(0.5, surface[el] + rng.randf_range(-0.8, 0.8))
			total += surface[el]
		for el in surface:
			surface[el] = snappedf(surface[el] * 100.0 / total, 0.1)
	return {
		"g": w,
		"l": s.l + rng.randfn(0.0, 0.04),
		"w": s.w + rng.randfn(0.0, 0.04),
		"t": t + rng.randfn(0.0, 0.01),
		"surface": surface,
	}


## Whether a set of readings is within a genuine bar's tolerances.
func readings_pass(r: Dictionary) -> bool:
	var s := spec()
	return r.g >= s.g - 0.005 and r.g <= s.g * (1.0 + WEIGHT_OVER) \
		and absf(r.l - s.l) <= SIZE_TOL and absf(r.w - s.w) <= SIZE_TOL \
		and absf(r.t - thickness_mm()) <= THICK_TOL


## Whether the XRF reading is a clean, pure surface of the claimed metal.
func surface_pass(surface: Dictionary) -> bool:
	return surface.size() == 1 and surface.has(METAL_ELEMENT[metal()]) and surface.values()[0] >= spec().purity * 100.0 - 0.05


## Adds the bar bench's upgrades and saves the serial ledger. Safe to call more than once.
static func hook_up() -> void:
	if _hooked:
		return
	_hooked = true
	Progress.register_upgrade("xrf_gun", {"name": "XRF analyzer", "cost": 7000.0, "tier": 0,
		"desc": "A handheld X-ray gun for the bar bench. It reads what a bar's surface is made of.", "effects": {}})
	Progress.register_upgrade("bar_dealer", {"name": "Bullion dealer account", "cost": 15000.0, "tier": 1,
		"desc": "The bullion dealer pays 99.5% of melt for genuine bars instead of 98%.", "effects": {"bar_payout": 0.015}})
	SaveGame.register("bars", func(): return ledger_to_dict(), func(d): ledger_from_dict(d))
	SaveGame.new_game_started.connect(func(): ledger.clear())
	# a title screen may have loaded the save, or started a new game, before this ran
	ledger.clear()
	if SaveGame.has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("bars")) == TYPE_DICTIONARY:
			ledger_from_dict(data.bars)


static func record(b: BullionBar, day: int) -> void:
	if not ledger.has(b.serial):
		ledger[b.serial] = day


static func ledger_to_dict() -> Dictionary:
	return {"serials": ledger.duplicate()}


static func ledger_from_dict(d: Dictionary) -> void:
	ledger.clear()
	var serials = d.get("serials", {})
	if typeof(serials) == TYPE_DICTIONARY:
		for s in serials:
			ledger[str(s)] = int(serials[s])
