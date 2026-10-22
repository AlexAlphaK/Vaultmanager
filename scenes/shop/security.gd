class_name Security
extends RefCounted
## Robberies, day and night. In the day a robber can walk in with the customers: the
## guard may stop them at the door, otherwise they reach the counter and you choose
## between handing over the till and hitting the panic button. At night the burglars
## who come are one of three crews, and how far they get depends on the vault layout.
## Pure logic and numbers, so the shop, the vault minigame and the tests share them.

## Chance per second of a hold-up while the shop is open, before the modifiers below.
## At the corner counter that is about one every nine days.
const HOLDUP_CHANCE := 0.0006
## Each tier up draws this much more of them.
const HOLDUP_PER_TIER := 0.25
## Share of hold-ups the guard stops at the door.
const GUARD_STOP := 0.7
## Seconds the robber waits at the counter before helping themselves.
const ROBBER_PATIENCE := 8.0
## Odds the panic button scares the robber off, before the alarm and guard add theirs.
const PANIC_ODDS := 0.45
## What a robber sweeps out of the display case on top of the till, scaled by deal size.
const CASE_GRAB := 1500.0
## Share of the waiting customers who flee when a hold-up starts.
const QUEUE_FLEES := 0.5

const ROBBER_LINES := ["Nobody move. Empty the till, slowly.", "Hands where I can see them. The cash, now.",
	"This is a robbery. Don't touch anything under the counter.", "Fill the bag. No alarms, no heroes."]
const ROBBER_LOOK := {"skin": "#c98f62", "hair": "#1a1a1a", "hair_style": 0, "shirt": "#1f1f24", "top": 2,
	"pants": "#1f1f24", "glasses": true, "beard": false, "hat": true, "apron": false}

## The burglar crews of the night. `carry` caps how many pieces they take off the tray
## (0 means all of it); `wall` multiplies the wall safe's crack chance. Weights are per
## shop tier: the corner counter mostly draws kids, a landmark draws professionals.
## The floor safe always holds.
const CREWS := {
	"kids": {"name": "Smash-and-grab kids", "carry": 3, "wall": 0.0, "weights": [0.6, 0.4, 0.25, 0.2],
		"line": "Kids smashed the back window and ran with what they could carry."},
	"crew": {"name": "A safecracking crew", "carry": 0, "wall": 1.0, "weights": [0.4, 0.45, 0.45, 0.45],
		"line": "A crew forced the back door at 3 a.m. and went to work on the safes."},
	"pros": {"name": "Professionals", "carry": 0, "wall": 2.0, "weights": [0.0, 0.15, 0.3, 0.35],
		"line": "Professionals cut the phone line and drilled straight for the wall safe."},
}
## Most of a crack chance a crew can reach.
const MAX_CRACK := 0.9


## The cameras: hold-ups drop and the police get some of the loot back.
static func hook_up() -> void:
	if Progress.upgrades.has("cctv"):
		return
	Progress.register_upgrade("cctv", {"name": "Security cameras", "cost": 3500.0, "tier": 0,
		"desc": "Hold-ups drop by 40%, and the police get back a third of what robbers and burglars take.",
		"effects": {"holdup": -0.4, "recover": 0.33}})


## Chance per second of a robber walking in. A till over its limit draws them, up to three times as many.
static func holdup_chance(till: float) -> float:
	var hot := clampf(till / RushHours.till_limit(), 0.0, 3.0)
	return HOLDUP_CHANCE * (1.0 + HOLDUP_PER_TIER * Progress.tier) * (0.5 + 0.5 * hot) \
		* maxf(0.0, 1.0 + Progress.effect("holdup"))


## Odds the panic button works. Alarms, time locks and the guard all make robbers jumpy.
static func panic_odds() -> float:
	return clampf(PANIC_ODDS - 0.5 * Progress.effect("robbery_risk"), 0.0, 0.9)


## Share of a theft the police recover.
static func recover_share() -> float:
	return clampf(Progress.effect("recover"), 0.0, 1.0)


## A robber posing as a customer.
static func robber(rng: RandomNumberGenerator) -> Customer:
	var c := Customer.new()
	c.seed = rng.randi()
	c.kind = "robber"
	c.archetype = "robber"
	c.name = "Man in a cap"
	c.say = ROBBER_LINES[rng.randi() % ROBBER_LINES.size()]
	c.max_patience = ROBBER_PATIENCE
	c.patience = ROBBER_PATIENCE
	var look := ROBBER_LOOK.duplicate()
	look.skin = PeopleArt.SKINS[rng.randi() % PeopleArt.SKINS.size()]
	c.set_look(look)
	return c


## Coins a robber sweeps out of the display case: [[lot, qty]], most valuable per coin first,
## up to CASE_GRAB x deal size at today's melt.
static func case_grab() -> Array:
	var budget := CASE_GRAB * Progress.deal_size()
	var lots := Shop.stock.duplicate()
	lots.sort_custom(func(a, b): return a.item.melt_value() > b.item.melt_value())
	var out := []
	for lot in lots:
		var each: float = lot.item.melt_value()
		if each <= 0.0:
			continue
		var n := mini(lot.qty, floori(budget / each))
		if n > 0:
			out.append([lot, n])
			budget -= each * n
	return out


static func grab_value(grab: Array) -> float:
	var total := 0.0
	for e in grab:
		total += e[0].item.melt_value() * e[1]
	return total


## Which crew comes tonight.
static func pick_crew(rng: RandomNumberGenerator, tier := Progress.tier) -> String:
	var total := 0.0
	for id in CREWS:
		total += CREWS[id].weights[clampi(tier, 0, 3)]
	var roll := rng.randf() * total
	for id in CREWS:
		roll -= CREWS[id].weights[clampi(tier, 0, 3)]
		if roll < 0.0:
			return id
	return "crew"


## A crew's chance of cracking a safe whose base crack chance is `base`.
static func crack_chance(crew: String, base: float) -> float:
	if base >= 1.0:
		return 1.0
	return clampf(base * float(CREWS[crew].wall), 0.0, MAX_CRACK)
