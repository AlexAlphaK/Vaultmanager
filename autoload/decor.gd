extends Node
## Shop decoration: plants, display cases, signs and fine furniture the player buys and
## places on spots around the shop floor in the morning. Placed pieces add up to the
## shop's appeal, and a shop with appeal wins people over:
##   Charm   good deals earn more stars (every REPUTATION gain, times 1 + star_bonus()).
##   Buzz    the town talks about a handsome shop: a few hundredths of a star a night,
##           until the shop reaches CHARM_UP_TO stars.
## A second copy of the same piece counts half (people notice the first fern, not the
## fifth), and each kind of piece on show (plant, case, sign, light, seat, art) adds
## VARIETY. Bigger shops have more spots. Pieces not on the floor wait in the storeroom
## and can be sold back for half what they cost. Saved with the game.

signal changed

## kind: "plant", "case", "sign", "light", "seat" or "art". `tier` is the shop tier it
## is sold from. Pictures in DecorArt.
const CATALOG := {
	"fern": {"name": "Potted fern", "kind": "plant", "tier": 0, "cost": 450.0, "appeal": 3,
		"desc": "A leafy fern in a terracotta pot."},
	"a_board": {"name": "Chalkboard sign", "kind": "sign", "tier": 0, "cost": 700.0, "appeal": 4,
		"desc": "\"We buy gold\" in your best chalk lettering."},
	"fig_tree": {"name": "Fig tree", "kind": "plant", "tier": 0, "cost": 1200.0, "appeal": 5,
		"desc": "A tall indoor fig. Makes the corner feel like a shop, not a booth."},
	"floor_lamp": {"name": "Brass floor lamp", "kind": "light", "tier": 0, "cost": 1500.0, "appeal": 5,
		"desc": "Warm light and polished brass."},
	"coin_pedestal": {"name": "Coin pedestal case", "kind": "case", "tier": 0, "cost": 2800.0, "appeal": 8,
		"desc": "A glass-topped pedestal showing off a few proof coins."},
	"armchair": {"name": "Velvet armchair", "kind": "seat", "tier": 1, "cost": 3200.0, "appeal": 7,
		"desc": "Somewhere comfy for a collector to sit and think it over."},
	"neon_sign": {"name": "Neon gold sign", "kind": "sign", "tier": 1, "cost": 4500.0, "appeal": 9,
		"desc": "A buzzing neon gold bar on a stand. Customers love a photo with it."},
	"palm": {"name": "Palm in a brass urn", "kind": "plant", "tier": 1, "cost": 5200.0, "appeal": 9,
		"desc": "A big glossy palm, the kind hotel lobbies have."},
	"vitrine": {"name": "Jewellery vitrine", "kind": "case", "tier": 1, "cost": 7500.0, "appeal": 12,
		"desc": "A tall glass cabinet of rings and chains, lit from inside."},
	"grandfather_clock": {"name": "Grandfather clock", "kind": "art", "tier": 1, "cost": 9000.0, "appeal": 11,
		"desc": "An old walnut clock with a gold pendulum. It ticks reassuringly."},
	"bar_pyramid": {"name": "Gold bar pyramid", "kind": "case", "tier": 2, "cost": 16000.0, "appeal": 16,
		"desc": "Gleaming bars stacked under a glass dome. Not the real ones, don't tell."},
	"bust": {"name": "Marble bust", "kind": "art", "tier": 2, "cost": 22000.0, "appeal": 18,
		"desc": "A founding father of coinage, in white marble on a plinth."},
	"chandelier_lamp": {"name": "Crystal torchère", "kind": "light", "tier": 2, "cost": 14000.0, "appeal": 14,
		"desc": "A standing lamp dripping with crystal drops."},
	"fountain": {"name": "Lion fountain", "kind": "art", "tier": 3, "cost": 45000.0, "appeal": 24,
		"desc": "A gilded lion spouting water into a marble basin. Coins in it go to charity."},
	"eagle": {"name": "Golden eagle statue", "kind": "art", "tier": 3, "cost": 60000.0, "appeal": 28,
		"desc": "A life-size gilded eagle, wings spread, on a marble column."},
}
## Spots on the shop floor (i, j in ShopArt tiles) and the tier each opens at. Clear of
## the counter, the case, the queue and the paths customers walk.
const SPOTS := [
	{"at": Vector2(1.2, 1.15), "tier": 0}, # back corner under the window
	{"at": Vector2(9.4, 1.7), "tier": 0}, # by the clock
	{"at": Vector2(2.35, 7.45), "tier": 0}, # front, by the case
	{"at": Vector2(3.65, 7.55), "tier": 0},
	{"at": Vector2(2.65, 1.0), "tier": 1}, # by the vault door
	{"at": Vector2(9.4, 2.95), "tier": 1},
	{"at": Vector2(2.25, 5.25), "tier": 2}, # between the case and the clerk's till
	{"at": Vector2(4.9, 7.6), "tier": 2},
	{"at": Vector2(7.1, 1.55), "tier": 3}, # in front of the shelf
	{"at": Vector2(6.2, 7.75), "tier": 3},
]
const KINDS := ["plant", "case", "sign", "light", "seat", "art"]
## What each kind is called on screen, in the order of KINDS.
const KIND_NAMES := ["plant", "display case", "sign", "lamp", "seat", "art"]
const VARIETY := 2
## Appeal to star bonus: each point adds this share to every star a good deal earns.
const STAR_BONUS_PER_APPEAL := 0.005
const STAR_BONUS_MAX := 0.5
## Stars a night per point of appeal, the most a night, and where the buzz stops.
const CHARM_PER_APPEAL := 0.0003
const CHARM_MAX := 0.03
const CHARM_UP_TO := 4.0
const RESALE := 0.5

## spot index -> piece id on that spot.
var placed := {}
## Pieces in the storeroom (bought, not on the floor).
var stored: Array[String] = []
## Stars the buzz added last night, for the summary.
var _buzz := 0.0


func _ready() -> void:
	reset()
	SaveGame.register("decor", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.settling.connect(_on_settling)
	Day.day_ended.connect(_on_day_ended)
	Progress.tier_changed.connect(func(_t): changed.emit())


func reset() -> void:
	placed.clear()
	stored.clear()
	_buzz = 0.0
	changed.emit()


func kind_name(id: String) -> String:
	return tr(KIND_NAMES[KINDS.find(CATALOG[id].kind)])


## Spots the shop has at its tier.
func spot_count(tier := Progress.tier) -> int:
	var n := 0
	for s in SPOTS:
		if int(s.tier) <= tier:
			n += 1
	return n


func spot_open(spot: int) -> bool:
	return spot >= 0 and spot < SPOTS.size() and int(SPOTS[spot].tier) <= Progress.tier


func spot_at(spot: int) -> Vector2:
	return SPOTS[spot].at


func piece_on(spot: int) -> String:
	return str(placed.get(spot, ""))


## Pieces for sale at this tier, cheapest first.
func for_sale() -> Array[String]:
	var out: Array[String] = []
	for id in CATALOG:
		if int(CATALOG[id].tier) <= Progress.tier:
			out.append(id)
	out.sort_custom(func(a, b): return CATALOG[a].cost < CATALOG[b].cost)
	return out


func locked_count() -> int:
	return CATALOG.size() - for_sale().size()


## How many of a piece the shop owns, on the floor and in the storeroom.
func owned_count(id: String) -> int:
	return stored.count(id) + placed.values().count(id)


func can_buy(id: String) -> bool:
	return CATALOG.has(id) and int(CATALOG[id].tier) <= Progress.tier and Shop.cash >= float(CATALOG[id].cost) \
		and Day.phase == Day.MORNING


## Buys a piece into the storeroom, or straight onto `spot` when that spot is free.
func buy(id: String, spot := -1) -> bool:
	if not can_buy(id):
		return false
	Day.add_expense(tr(CATALOG[id].name), float(CATALOG[id].cost))
	Shop.log_event(tr("Bought %s.") % tr(CATALOG[id].name), "good")
	stored.append(id)
	if spot >= 0 and spot_open(spot) and piece_on(spot) == "":
		place(id, spot)
	else:
		changed.emit()
	return true


## Moves a piece from the storeroom onto a spot. A piece already there goes to the storeroom.
func place(id: String, spot: int) -> bool:
	if not stored.has(id) or not spot_open(spot):
		return false
	stored.erase(id)
	var old := piece_on(spot)
	if old != "":
		stored.append(old)
	placed[spot] = id
	changed.emit()
	Records.check()
	return true


## Moves the piece on a spot to another spot, swapping with whatever stands there.
func move(from: int, to: int) -> bool:
	var id := piece_on(from)
	if id == "" or not spot_open(to) or from == to:
		return false
	var other := piece_on(to)
	placed[to] = id
	if other != "":
		placed[from] = other
	else:
		placed.erase(from)
	changed.emit()
	return true


## Puts the piece on a spot away in the storeroom.
func pick_up(spot: int) -> String:
	var id := piece_on(spot)
	if id == "":
		return ""
	placed.erase(spot)
	stored.append(id)
	changed.emit()
	return id


func resale(id: String) -> float:
	return roundf(float(CATALOG[id].cost) * RESALE)


## Sells one stored piece back for half its price.
func sell(id: String) -> bool:
	if not stored.has(id) or Day.phase != Day.MORNING:
		return false
	stored.erase(id)
	Day.add_income(tr("Sold back: %s") % tr(CATALOG[id].name), resale(id))
	changed.emit()
	return true


## The shop's appeal: pieces on the floor (repeats count half) plus VARIETY per kind on show.
func appeal() -> int:
	var seen := {}
	var kinds := {}
	var total := 0.0
	for spot in placed:
		if not spot_open(spot):
			continue # a spot the shop has outgrown can't happen, but saves can be edited
		var id: String = placed[spot]
		var a := float(CATALOG[id].appeal)
		total += a if not seen.has(id) else a * 0.5
		seen[id] = true
		kinds[CATALOG[id].kind] = true
	return int(total) + kinds.size() * VARIETY


## What the appeal would be with `id` on `spot` (for the preview in the catalogue).
func appeal_with(id: String, spot: int) -> int:
	var before := placed.duplicate()
	placed[spot] = id
	var a := appeal()
	placed = before
	return a


## Extra share of stars every good deal earns.
func star_bonus(a := appeal()) -> float:
	return minf(a * STAR_BONUS_PER_APPEAL, STAR_BONUS_MAX)


## Stars the buzz adds tonight.
func charm(a := appeal()) -> float:
	if Shop.reputation >= CHARM_UP_TO:
		return 0.0
	return minf(minf(a * CHARM_PER_APPEAL, CHARM_MAX), CHARM_UP_TO - Shop.reputation)


## "Appeal 26: good deals earn 13% more stars".
func summary() -> String:
	var a := appeal()
	if a <= 0:
		return tr("No decoration yet. Pieces on the floor win you stars.")
	return tr("Appeal %d: good deals earn %d%% more stars, and the town talks.") % [a, roundi(star_bonus(a) * 100.0)]


func _on_settling(_day: int) -> void:
	_buzz = charm()
	if _buzz > 0.0:
		Shop.adjust_reputation(_buzz)


func _on_day_ended(_day: int, report: Dictionary) -> void:
	if _buzz > 0.0:
		report.lines.append(tr("People talk about your shop's decor: +%.2f stars.") % _buzz)
	_buzz = 0.0


func to_dict() -> Dictionary:
	var spots := {}
	for spot in placed:
		spots[str(spot)] = placed[spot]
	return {"placed": spots, "stored": stored.duplicate()}


func from_dict(d: Dictionary) -> void:
	reset()
	var spots = d.get("placed", {})
	if typeof(spots) == TYPE_DICTIONARY:
		for key in spots:
			var spot := int(key)
			if spot >= 0 and spot < SPOTS.size() and CATALOG.has(str(spots[key])):
				placed[spot] = str(spots[key])
	for id in d.get("stored", []):
		if CATALOG.has(str(id)):
			stored.append(str(id))
	changed.emit()
