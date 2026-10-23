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
	{"name": "Corner counter", "rent": 550.0, "upkeep": 17.0, "traffic": 1.0, "deal_size": 1.0, "safe": 60,
		"need_worth": 0.0, "need_rep": 0.0, "cost": 0.0},
	{"name": "Main Street shop", "rent": 2000.0, "upkeep": 60.0, "traffic": 1.25, "deal_size": 1.5, "safe": 160,
		"need_worth": 60000.0, "need_rep": 3.0, "cost": 15000.0},
	{"name": "Bullion house", "rent": 5400.0, "upkeep": 135.0, "traffic": 1.5, "deal_size": 2.2, "safe": 450,
		"need_worth": 160000.0, "need_rep": 3.8, "cost": 45000.0},
	{"name": "Town landmark", "rent": 12000.0, "upkeep": 270.0, "traffic": 1.8, "deal_size": 3.2, "safe": 1500,
		"need_worth": 400000.0, "need_rep": 4.5, "cost": 120000.0},
]
## Weekly insurance as a share of vault value at spot.
const INSURANCE_RATE := 0.0013

## Effects add up across owned upgrades. Keys in use:
##   traffic       +share of arrival speed       patience  +share of customer patience
##   premium       +premium buyers accept        insurance share off the insurance bill (negative)
##   fraud_refund  share of fake losses repaid   safe      +share of vault capacity
##   robbery_risk  share off robbery odds (negative), read by the vault minigame
##   queue         extra waiting spots in the shop  till         +share the till holds before thieves notice
##   clerk_speed   +share of the clerk's speed      calm_queue   share off queue impatience while you test
##   refine        +share the refiner pays          deal_size    +share of what each customer brings
##   scrap_size    +share of the scrap dealer's lots (see ScrapYard)
## Staff on the payroll add their effects too (see Staff.ROLES).
## `line` groups an upgrade: "counter" and "tools" grow the counter and the testing
## benches and show up on the shop floor, "room" builds a room on the floor plan (PlanArt).
## `needs` names an upgrade that must be owned first.
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
	"lounge": {"name": "Collector's lounge", "cost": 35000.0, "tier": 2, "line": "room",
		"desc": "Comfy chairs and coffee. Buyers accept 3% more premium and wait 20% longer.",
		"effects": {"premium": 0.03, "patience": 0.2}},
	"time_lock": {"name": "Time-lock vault", "cost": 60000.0, "tier": 2,
		"desc": "Robberies become very rare and insurance drops another 30%.", "effects": {"insurance": -0.3, "robbery_risk": -0.4}},
	"billboard": {"name": "Highway billboard", "cost": 90000.0, "tier": 3,
		"desc": "People drive in from the next town: customers arrive 30% faster.", "effects": {"traffic": 0.3}},
	# the counter
	"queue_ropes": {"name": "Brass queue ropes", "cost": 3000.0, "tier": 0, "line": "counter",
		"desc": "Posts and a velvet rope snake the queue: 2 more customers can wait inside.", "effects": {"queue": 2.0}},
	"long_counter": {"name": "Long counter", "cost": 14000.0, "tier": 1, "line": "counter",
		"desc": "A second service window. The clerk rings up 40% faster, the till holds 50% more before thieves notice, and 1 more customer can wait.",
		"effects": {"queue": 1.0, "till": 0.5, "clerk_speed": 0.4}},
	"marble_counter": {"name": "Marble showroom counter", "cost": 40000.0, "tier": 2, "line": "counter", "needs": "long_counter",
		"desc": "Marble, brass and glass. Buyers accept 2% more premium, wait 15% longer, and 1 more customer can wait.",
		"effects": {"premium": 0.02, "patience": 0.15, "queue": 1.0}},
	# the testing benches
	"digital_gauges": {"name": "Digital gauges", "cost": 2500.0, "tier": 0, "line": "tools",
		"desc": "The coin and bar benches compare each reading with the spec: green inside it, red outside.", "effects": {}},
	"sigma_verifier": {"name": "Sigma metal verifier", "cost": 12000.0, "tier": 1, "line": "tools",
		"desc": "A conductivity probe for the coin bench (key 6). It reads through plating and finds a tungsten core.", "effects": {}},
	# rooms on the floor plan
	"testing_lab": {"name": "Testing lab", "cost": 16000.0, "tier": 1, "line": "room",
		"desc": "A back room with proper benches. In a rush the queue gets impatient half as fast while you test.",
		"effects": {"calm_queue": 0.5}},
	"workshop": {"name": "Refining workshop", "cost": 50000.0, "tier": 2, "line": "room",
		"desc": "Melt scrap in-house: the refiner pays 6% more for the jewellery you buy, and with a melting furnace the scrap dealer brings lots twice the size.",
		"effects": {"refine": 0.06, "scrap_size": 1.0}},
	"trading_desk": {"name": "Bullion trading desk", "cost": 75000.0, "tier": 2, "line": "room",
		"desc": "A dealing room with live screens. Each morning, trade metals, stocks and crypto and hedge your vault. Investors bring 25% more.",
		"effects": {"deal_size": 0.25}},
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
	return tr(tier_info(t).name)


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


## Whether an upgrade's tier and prerequisite are met (owned or not).
func unlocked(id: String) -> bool:
	var u: Dictionary = upgrades.get(id, {})
	return not u.is_empty() and int(u.tier) <= tier and (not u.has("needs") or owned.has(u.needs))


## The upgrade's group: "counter", "tools", "room" or "" for the rest.
func line_of(id: String) -> String:
	return str(upgrades.get(id, {}).get("line", ""))


## Upgrades for sale at the current tier, cheapest first. `line` keeps one group only.
func available_upgrades(line := "*") -> Array[String]:
	var out: Array[String] = []
	for id in upgrades:
		if unlocked(id) and not owned.has(id) and (line == "*" or line_of(id) == line):
			out.append(id)
	out.sort_custom(func(a, b): return upgrades[a].cost < upgrades[b].cost)
	return out


func locked_upgrade_count() -> int:
	var n := 0
	for id in upgrades:
		if not unlocked(id):
			n += 1
	return n


func can_buy(id: String) -> bool:
	return unlocked(id) and not owned.has(id) and Shop.cash >= upgrades[id].cost


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Day.add_expense(tr(upgrades[id].name), upgrades[id].cost)
	owned.append(id)
	Shop.log_event(tr("Bought %s.") % tr(upgrades[id].name), "good")
	upgrade_bought.emit(id)
	changed.emit()
	return true


## Why the shop cannot move up a tier yet, or "" when it can.
func expand_blocker() -> String:
	if is_top_tier():
		return tr("You run the biggest store in town.")
	if Demo.tier_locked(tier + 1):
		return tr("Full game only")
	var next := tier_info(tier + 1)
	if Shop.net_worth() < next.need_worth:
		return tr("Needs net worth %s") % Market.format_money(next.need_worth)
	if Shop.reputation < next.need_rep:
		return tr("Needs %.1f stars") % next.need_rep
	if Shop.cash < next.cost:
		return tr("Needs %s cash") % Market.format_money(next.cost)
	return ""


func expand() -> bool:
	if expand_blocker() != "":
		return false
	var next := tier_info(tier + 1)
	Day.add_expense(tr("Moving to %s") % tr(next.name), next.cost)
	tier += 1
	Shop.log_event(tr("Welcome to your %s!") % tr(next.name), "good")
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
	return tier_info().deal_size * (1.0 + effect("deal_size"))


## How many customers can wait inside: the corner counter's 4 plus the counter upgrades.
func queue_slots() -> int:
	return mini(ShopArt.BASE_SLOTS + int(effect("queue")), ShopArt.SLOTS.size())


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
