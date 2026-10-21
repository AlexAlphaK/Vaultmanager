extends Node
## Player settings: volume for the Master, Music and SFX buses, and fullscreen.
## Saved next to the currency choice in user://settings.cfg (Market keeps the currency).
## F11 toggles fullscreen anywhere in the game.

signal changed

const BUSES := ["Master", "Music", "SFX"]
const DEFAULTS := {"Master": 0.8, "Music": 0.6, "SFX": 0.8}

var path := Market.SETTINGS_PATH
## Linear volume 0-1 per bus name.
var volume := DEFAULTS.duplicate()
var fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for bus in BUSES:
		volume[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), DEFAULTS[bus])), 0.0, 1.0)
		_apply_volume(bus)
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	_apply_fullscreen()
	changed.emit()


func set_volume(bus: String, value: float) -> void:
	if not volume.has(bus):
		return
	volume[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_save()
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	_save()
	changed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_F11:
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


## Music and SFX are created in code so the project needs no bus layout file.
func _ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var n := AudioServer.bus_count - 1
			AudioServer.set_bus_name(n, bus)
			AudioServer.set_bus_send(n, "Master")


func _apply_volume(bus: String) -> void:
	var n := AudioServer.get_bus_index(bus)
	if n == -1:
		return
	var v: float = volume[bus]
	AudioServer.set_bus_mute(n, v <= 0.001)
	AudioServer.set_bus_volume_db(n, linear_to_db(maxf(v, 0.001)))


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path) # keep the currency and anything else already in the file
	for bus in BUSES:
		cfg.set_value("audio", bus.to_lower(), volume[bus])
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(path)
