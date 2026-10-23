extends Node
## Remembers what the player has been shown: the guided first day and the short
## intros the first time the jewellery and bar benches open. The guiding itself is
## done by Coach (scenes/tutorial/coach.gd) on the shop floor. Saved with the game,
## and a new game starts the tutorial again (it can be skipped from any card).

signal changed

## Intros shown once each, the first time their bench opens.
const INTROS := ["jewellery", "bar", "grading"]

var first_day_done := false
var seen := {}


func _ready() -> void:
	reset()
	SaveGame.register("tutorial", to_dict, from_dict)
	SaveGame.new_game_started.connect(reset)


func reset() -> void:
	first_day_done = false
	seen = {}
	changed.emit()


func has_seen(intro: String) -> bool:
	return seen.get(intro, false)


## Marks an intro shown, and writes it into the save straight away.
func mark_seen(intro: String) -> void:
	seen[intro] = true
	SaveGame.save_section("tutorial")
	changed.emit()


func finish_first_day() -> void:
	first_day_done = true
	SaveGame.save_section("tutorial")
	changed.emit()


## Skip tutorial: no more guiding and no bench intros.
func skip_all() -> void:
	first_day_done = true
	for intro in INTROS:
		seen[intro] = true
	SaveGame.save_section("tutorial")
	changed.emit()


func to_dict() -> Dictionary:
	return {"first_day_done": first_day_done, "seen": seen.duplicate()}


func from_dict(d: Dictionary) -> void:
	first_day_done = bool(d.get("first_day_done", false))
	seen = {}
	var saved = d.get("seen", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for intro in INTROS:
			if saved.get(intro, false):
				seen[intro] = true
	changed.emit()
