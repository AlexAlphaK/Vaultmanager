class_name RushHours
extends RefCounted
## The busy hours of the shop day. In a rush customers pour in, the queue keeps
## waiting while you are at a testing bench, and a full queue turns people away at
## the door. Times are minutes after midnight on the shop clock (open 09:00 to 17:00).

const LUNCH := {"name": "Lunch rush", "from": 11 * 60 + 45, "to": 13 * 60 + 15}
const AFTER_WORK := {"name": "After-work rush", "from": 15 * 60 + 45, "to": 16 * 60 + 45}
const SATURDAY := {"name": "Saturday crowd", "from": 9 * 60 + 45, "to": 11 * 60}
## Seconds between arrivals in a rush, before the shop's traffic bonus.
const SPAWN_GAP := 4.0
## Keep this much cash in the till and it is worth a snatch; scaled by the tier's deal size
## and a bigger cash drawer (the long counter).
const TILL_LIMIT := 5000.0
## Share of the till a thief gets away with.
const GRAB_SHARE := 0.35
## Chance per second of a snatch with the till at its limit (twice the limit doubles it).
const GRAB_CHANCE := 0.005


## Today's rushes, earliest first. Saturdays bring a morning crowd; Sundays are quiet after lunch.
static func windows(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match Day.weekday(day):
		"Saturday":
			out.append(SATURDAY)
			out.append(LUNCH)
			out.append(AFTER_WORK)
		"Sunday":
			out.append(LUNCH)
		_:
			out.append(LUNCH)
			out.append(AFTER_WORK)
	return out


## The rush on at `minutes`, or {} when the shop is calm.
static func at(day: int, minutes: float) -> Dictionary:
	for w in windows(day):
		if minutes >= w.from and minutes < w.to:
			return w
	return {}


## "12:00" style.
static func clock(minutes: int) -> String:
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## One line for the morning briefing.
static func summary(day: int) -> String:
	var parts: Array[String] = []
	for w in windows(day):
		parts.append("%s %s" % [w.name.to_lower().trim_suffix(" rush").trim_suffix(" crowd"), clock(w.from)])
	return "Rush hours: %s." % ", ".join(parts)


static func till_limit() -> float:
	return TILL_LIMIT * Progress.deal_size() * (1.0 + Progress.effect("till"))


## Chance per second that someone snatches cash from an overfull till.
static func grab_chance(till: float, in_rush: bool) -> float:
	var limit := till_limit()
	if till <= limit:
		return 0.0
	return GRAB_CHANCE * minf(till / limit, 3.0) * (2.0 if in_rush else 1.0) * maxf(0.0, 1.0 + Progress.effect("till_grab"))
