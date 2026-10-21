extends Node
## Saves the game to one JSON file every morning and loads it on launch.
## Other modules add their own state with register(), for example:
##   SaveGame.register("vault", func(): return to_dict(), func(d): from_dict(d))

signal new_game_started

const VERSION := 1

var path := "user://save.json"
var _sections := {}


func _ready() -> void:
	register("shop", Shop.to_dict, Shop.from_dict)
	register("progress", Progress.to_dict, Progress.from_dict)


## `save_fn` returns a JSON-friendly Dictionary; `load_fn` receives it back.
func register(key: String, save_fn: Callable, load_fn: Callable) -> void:
	_sections[key] = {"save": save_fn, "load": load_fn}


func has_save() -> bool:
	return FileAccess.file_exists(path)


func save_game() -> bool:
	var data := {"version": VERSION, "saved_unix": int(Time.get_unix_time_from_system())}
	for key in _sections:
		data[key] = _sections[key].save.call()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save to %s" % path)
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
	for key in _sections:
		if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY:
			_sections[key].load.call(data[key])
	return true


## A summary of the save for the title screen, without loading it:
## {"day", "tier", "cash", "saved_unix"}, or {} when there is no readable save.
func peek() -> Dictionary:
	if not has_save():
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) > VERSION:
		return {}
	var shop: Dictionary = data.get("shop", {}) if typeof(data.get("shop")) == TYPE_DICTIONARY else {}
	var progress: Dictionary = data.get("progress", {}) if typeof(data.get("progress")) == TYPE_DICTIONARY else {}
	return {"day": int(shop.get("day", 1)), "tier": int(progress.get("tier", 0)),
		"cash": float(shop.get("cash", 0.0)), "saved_unix": int(data.get("saved_unix", 0))}


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Wipes the save and starts over on day 1.
func new_game() -> void:
	delete_save()
	Progress.reset()
	Day.reset()
	Shop.reset()
	new_game_started.emit()
