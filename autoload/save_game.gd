extends Node
## Saves the game to one of three slots (user://save_1.json and on), every morning and
## again at the end of each day, and loads it on launch.
## Other modules add their own state with register(), for example:
##   SaveGame.register("vault", func(): return to_dict(), func(d): from_dict(d))

signal new_game_started

const VERSION := 1
const SLOTS := 3
## The single save file from before slots. Tests point this somewhere else.
var legacy_path := "user://save.json"

## Slot files are slot_prefix + number + ".json". Tests point this somewhere else.
var slot_prefix := "user://save_"
## Remembers which slot Continue opens.
var meta_path := "user://save_slots.cfg"
var slot := 1
var path := ""
## True when the loaded save was written after the day ended, so the game picks up
## on the next morning instead of replaying the day.
var day_over := false
var _sections := {}


func _ready() -> void:
	register("shop", Shop.to_dict, Shop.from_dict)
	register("progress", Progress.to_dict, Progress.from_dict)
	_migrate_legacy_save()
	var cfg := ConfigFile.new()
	cfg.load(meta_path)
	set_slot(int(cfg.get_value("saves", "last_slot", 1)), false)


func slot_path(n: int) -> String:
	return "%s%d.json" % [slot_prefix, n]


## Makes `n` the slot every save and load uses from now on.
func set_slot(n: int, remember := true) -> void:
	slot = clampi(n, 1, SLOTS)
	path = slot_path(slot)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(meta_path)
		cfg.set_value("saves", "last_slot", slot)
		cfg.save(meta_path)


func slot_has_save(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))


## The first slot with no save, or 0 when all are taken.
func first_empty_slot() -> int:
	for n in range(1, SLOTS + 1):
		if not slot_has_save(n):
			return n
	return 0


## The slot Continue opens: the last one played if it still has a save, else the most
## recently saved one, or 0 when there are no saves at all.
func continue_slot() -> int:
	if slot_has_save(slot):
		return slot
	var best := 0
	var best_time := -1
	for n in range(1, SLOTS + 1):
		var info := peek(n)
		if not info.is_empty() and info.saved_unix > best_time:
			best = n
			best_time = info.saved_unix
	return best


func delete_slot(n: int) -> void:
	if slot_has_save(n):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(n)))


## Before save slots there was one user://save.json. It becomes slot 1.
func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(legacy_path) and not slot_has_save(1):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(legacy_path), ProjectSettings.globalize_path(slot_path(1)))


## `save_fn` returns a JSON-friendly Dictionary; `load_fn` receives it back.
func register(key: String, save_fn: Callable, load_fn: Callable) -> void:
	_sections[key] = {"save": save_fn, "load": load_fn}


func has_save() -> bool:
	return FileAccess.file_exists(path)


func save_game() -> bool:
	var data := {"version": VERSION, "saved_unix": int(Time.get_unix_time_from_system()),
		"day_over": Day.phase == Day.AFTER_HOURS}
	for key in _sections:
		data[key] = _sections[key].save.call()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save to %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Writes one section into the existing save without touching the rest, so a choice
## like skipping the tutorial sticks even if the player quits before the next morning.
func save_section(key: String) -> bool:
	if not has_save() or not _sections.has(key):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	data[key] = _sections[key].save.call()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Loads every registered section found in the file. Returns false if there is no
## readable save, leaving the current game untouched.
func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) > VERSION:
		push_warning("Ignoring unreadable save at %s" % path)
		return false
	day_over = bool(data.get("day_over", false))
	for key in _sections:
		if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY:
			_sections[key].load.call(data[key])
	return true


## A summary of a slot's save for the title screen, without loading it:
## {"day", "tier", "cash", "saved_unix", "day_over"}, or {} when there is no readable save.
## With no slot given it reads the current one.
func peek(n := 0) -> Dictionary:
	var file := path if n == 0 else slot_path(n)
	if not FileAccess.file_exists(file):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(file))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) > VERSION:
		return {}
	var shop: Dictionary = data.get("shop", {}) if typeof(data.get("shop")) == TYPE_DICTIONARY else {}
	var progress: Dictionary = data.get("progress", {}) if typeof(data.get("progress")) == TYPE_DICTIONARY else {}
	return {"day": int(shop.get("day", 1)), "tier": int(progress.get("tier", 0)),
		"cash": float(shop.get("cash", 0.0)), "saved_unix": int(data.get("saved_unix", 0)),
		"day_over": bool(data.get("day_over", false))}


## "Oct 21, 18:04" in the player's local time.
static func format_time(unix: int) -> String:
	if unix <= 0:
		return ""
	var local := unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d, %02d:%02d" % [Loc.t(MONTHS[d.month - 1]), d.day, d.hour, d.minute]


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Wipes the save and starts over on day 1.
func new_game() -> void:
	delete_save()
	day_over = false
	Progress.reset()
	Day.reset()
	Shop.reset()
	new_game_started.emit()
