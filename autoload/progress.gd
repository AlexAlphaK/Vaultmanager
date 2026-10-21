extends Node
## Growing the business: the four shop tiers from the design doc and the upgrades
## bought with profit. Other systems read upgrades through effect(), so a new upgrade
## only needs an entry here (or a register_upgrade() call from another module).

signal changed
signal upgrade_bought(id: String)
signal tier_changed(tier: int)

## Rent and insurance are weekly; upkeep (power, alarm line, coffee) is daily.
## `traffic` speeds up customer arrivals, `deal_size` scales how much each customer brings.
## `safe` is the vault capacity in coins, for the vault organizing minigame.
const TIERS: Array[Dictionary] = [
	{"name": "Corner counter", "rent": 800.0, "upkeep": 25.0, "traffic": 1.0, "deal_size": 1.0, "safe": 60,
		"need_worth": 0.0, "need_rep": 0.0, "cost": 0.0},
	{"name": "Main Street shop", "rent": 3000.0, "upkeep": 90.0, "traffic": 1.25, "deal_size": 1.5, "safe": 160,
		"need_worth": 60000.0, "need_rep": 3.0, "cost": 15000.0},
	{"name": "Bullion house", "rent": 8000.0, "upkeep": 200.0, "traffic": 1.5, "deal_size": 2.2, "safe": 450,
		"need_worth": 160000.0, "need_rep": 3.8, "cost": 45000.0},
	{"name": "Town landmark", "rent": 18000.0, "upkeep": 400.0, "traffic": 1.8, "deal_size": 3.2, "safe": 1500,
		"need_worth": 400000.0, "need_rep": 4.5, "cost": 120000.0},
]
## Weekly insurance as a share of vault value at spot.
const INSURANCE_RATE := 0.002

## Effects add up across owned upgrades. Keys in use:
##   traffic       +share of arrival speed       patience  +share of customer patience
##   premium       +premium buyers accept        insurance share off the insurance bill (negative)
##   fraud_refund  share of fake losses repaid   safe      +share of vault capacity
##   robbery_risk  share off robbery odds (negative), read by the vault minigame
## Staff on the payroll add their effects too (see Staff.ROLES).
var upgrades := {
	"bench": {"name": "Waiting bench", "cost": 1500.0, "tier": 0,
		"desc": "Customers wait 25% longer before they give up.", "effects": {"patience": 0.25}},
	"window_sign": {"name": "Neon window sign", "cost": 2500.0, "tier": 0,
		"desc": "More passers-by notice you: customers arrive 15% faster.", "effects": {"traffic": 0.15}},
	"case_lights": {"name": "Display case lights", "cost": 4000.0, "tier": 0,
		"desc": "Coins sparkle. Buyers accept 2% more premium.", "effects": {"premium": 0.02}},
	"alarm": {"name": "Alarm system", "cost": 6000.0, "tier": 0,
		"desc": "Insurance costs 30% less and robbers think twice.", "effects": {"insurance": -0.3, "robbery_risk": -0.4}},
	"fraud_cover": {"name": "Fraud insurance", "cost": 6000.0, "tier": 0,
		"desc": "Pays back half of what you lose on fakes the assay lab catches.", "effects": {"fraud_refund": 0.5}},
	"big_safe": {"name": "Second safe", "cost": 12000.0, "tier": 1,
		"desc": "Adds a shelf to the wall safe for the nightly lock-up.", "effects": {"safe": 1.0}},
	"radio_ads": {"name": "Radio ads", "cost": 18000.0, "tier": 1,
		"desc": "The whole town hears about you: customers arrive 20% faster.", "effects": {"traffic": 0.2}},
	"lounge": {"name": "Collector's lounge", "cost": 35000.0, "tier": 2,
		"desc": "Comfy chairs and coffee. Buyers accept 3% more premium and wait 20% longer.",
		"effects": {"premium": 0.03, "patience": 0.2}},
	"time_lock": {"name": "Time-lock vault", "cost": 60000.0, "tier": 2,
		"desc": "Robberies become very rare and insurance drops another 30%.", "effects": {"insurance": -0.3, "robbery_risk": -0.4}},
	"billboard": {"name": "Highway billboard", "cost": 90000.0, "tier": 3,
		"desc": "People drive in from the next town: customers arrive 30% faster.", "effects": {"traffic": 0.3}},
}

var tier := 0
var owned: Array[String] = []


func reset() -> void:
	tier = 0
	owned.clear()
	changed.emit()


func tier_info(t := tier) -> Dictionary:
	return TIERS[clampi(t, 0, TIERS.size() - 1)]


func tier_name(t := tier) -> String:
	return tier_info(t).name


func is_top_tier() -> bool:
	return tier >= TIERS.size() - 1


## The game's goal: the biggest precious metal store in town.
func goal_reached() -> bool:
	return is_top_tier()


## Sum of one effect across owned upgrades.
func effect(key: String) -> float:
	var total := 0.0
	for id in owned:
		if upgrades.has(id):
			total += float(upgrades[id].effects.get(key, 0.0))
	return total + Staff.effect(key)


func has_upgrade(id: String) -> bool:
	return owned.has(id)


## Lets other modules (jewellery tools, vault safes) add their own upgrades.
func register_upgrade(id: String, data: Dictionary) -> void:
	upgrades[id] = data
	changed.emit()


## Upgrades for sale at the current tier, cheapest first.
func available_upgrades() -> Array[String]:
	var out: Array[String] = []
	for id in upgrades:
		if int(upgrades[id].tier) <= tier and not owned.has(id):
			out.append(id)
	out.sort_custom(func(a, b): return upgrades[a].cost < upgrades[b].cost)
	return out


func locked_upgrade_count() -> int:
	var n := 0
	for id in upgrades:
		if int(upgrades[id].tier) > tier:
			n += 1
	return n


func can_buy(id: String) -> bool:
	return upgrades.has(id) and not owned.has(id) and int(upgrades[id].tier) <= tier and Shop.cash >= upgrades[id].cost


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Day.add_expense(upgrades[id].name, upgrades[id].cost)
	owned.append(id)
	Shop.log_event("Bought %s." % upgrades[id].name, "good")
	upgrade_bought.emit(id)
	changed.emit()
	return true


## Why the shop cannot move up a tier yet, or "" when it can.
func expand_blocker() -> String:
	if is_top_tier():
		return "You run the biggest store in town."
	var next := tier_info(tier + 1)
	if Shop.net_worth() < next.need_worth:
		return "Needs net worth %s" % Market.format_money(next.need_worth)
	if Shop.reputation < next.need_rep:
		return "Needs %.1f stars" % next.need_rep
	if Shop.cash < next.cost:
		return "Needs %s cash" % Market.format_money(next.cost)
	return ""


func expand() -> bool:
	if expand_blocker() != "":
		return false
	var next := tier_info(tier + 1)
	Day.add_expense("Moving to %s" % next.name, next.cost)
	tier += 1
	Shop.log_event("Welcome to your %s!" % next.name, "good")
	tier_changed.emit(tier)
	changed.emit()
	return true


## How close net worth is to the next tier's requirement, 0 to 1.
func next_tier_progress() -> float:
	if is_top_tier():
		return 1.0
	return clampf(Shop.net_worth() / tier_info(tier + 1).need_worth, 0.0, 1.0)


func traffic() -> float:
	return tier_info().traffic + effect("traffic")


func deal_size() -> float:
	return tier_info().deal_size


func safe_capacity() -> int:
	return int(tier_info().safe * (1.0 + effect("safe")))


func daily_upkeep() -> float:
	return tier_info().upkeep


func weekly_rent() -> float:
	return tier_info().rent


func weekly_insurance() -> float:
	return Shop.vault_value() * INSURANCE_RATE * maxf(0.1, 1.0 + effect("insurance"))


func to_dict() -> Dictionary:
	return {"tier": tier, "owned": owned.duplicate()}


func from_dict(d: Dictionary) -> void:
	tier = clampi(int(d.get("tier", 0)), 0, TIERS.size() - 1)
	owned.clear()
	for id in d.get("owned", []):
		owned.append(str(id))
	changed.emit()
