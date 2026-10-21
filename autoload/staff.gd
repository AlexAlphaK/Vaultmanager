extends Node
## The people you hire: a clerk who works the second till and a guard at the door.
## Hiring costs a signing fee in the morning; wages go on the ledger at closing time
## every day they are on the payroll. Their effects add to Progress.effect(), so the
## guard's cut to robbery odds reaches the vault lock-up like any upgrade's.

signal changed

## `fee` is paid once when hired; `wage` is per day, and rises with the shop's tier.
## Effects keys as in Progress.upgrades, plus `till_grab` (share off daytime till snatches).
const ROLES := {
	"clerk": {"name": "Benny", "title": "Clerk", "fee": 1000.0, "wage": 80.0, "tier": 0,
		"desc": "Works the second till. Sells coins to buyers at your price while you test, so the queue keeps moving.",
		"effects": {}},
	"guard": {"name": "Rhonda", "title": "Guard", "fee": 2000.0, "wage": 120.0, "tier": 0,
		"desc": "Stands by the door. Break-ins drop by a third and nobody dares grab the till in a rush.",
		"effects": {"robbery_risk": -0.35, "till_grab": -0.85}},
}
## How much more staff cost at each tier up.
const WAGE_PER_TIER := 0.4

var hired: Array[String] = []


func _ready() -> void:
	SaveGame.register("staff", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)
	Day.shop_closed.connect(_pay_wages)


func reset() -> void:
	hired.clear()
	changed.emit()


func has(id: String) -> bool:
	return hired.has(id)


func label(id: String) -> String:
	return "%s the %s" % [ROLES[id].name, ROLES[id].title.to_lower()]


func wage(id: String) -> float:
	return float(ROLES[id].wage) * (1.0 + WAGE_PER_TIER * Progress.tier)


func daily_wages() -> float:
	var total := 0.0
	for id in hired:
		total += wage(id)
	return total


## Sum of one effect across the people on the payroll.
func effect(key: String) -> float:
	var total := 0.0
	for id in hired:
		total += float(ROLES[id].effects.get(key, 0.0))
	return total


func can_hire(id: String) -> bool:
	return ROLES.has(id) and not hired.has(id) and int(ROLES[id].tier) <= Progress.tier \
		and Shop.cash >= ROLES[id].fee and Day.phase == Day.MORNING


func hire(id: String) -> bool:
	if not can_hire(id):
		return false
	Day.add_expense("Hired %s" % label(id), ROLES[id].fee)
	hired.append(id)
	Shop.log_event("%s starts today." % label(id), "good")
	changed.emit()
	Progress.changed.emit()
	return true


## Lets someone go. The signing fee is not refunded.
func let_go(id: String) -> bool:
	if not hired.has(id):
		return false
	hired.erase(id)
	Shop.log_event("You let %s go." % label(id))
	changed.emit()
	Progress.changed.emit()
	return true


func _pay_wages(_day: int) -> void:
	for id in hired:
		Day.add_expense("Wages: %s" % ROLES[id].name, wage(id))


func to_dict() -> Dictionary:
	return {"hired": hired.duplicate()}


func from_dict(d: Dictionary) -> void:
	hired.clear()
	for id in d.get("hired", []):
		if ROLES.has(str(id)) and not hired.has(str(id)):
			hired.append(str(id))
	changed.emit()
