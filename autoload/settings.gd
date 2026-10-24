extends Node
## Player settings: language, volume for the Master, Music and SFX buses, fullscreen and screen scaling.
## Saved next to the currency choice in user://settings.cfg (Market keeps the currency).
## F11 toggles fullscreen anywhere in the game. On a Steam Deck the game starts fullscreen.

signal changed

const BUSES := ["Master", "Music", "SFX"]
const DEFAULTS := {"Master": 0.8, "Music": 0.6, "SFX": 0.8}

var path := Market.SETTINGS_PATH
## Linear volume 0-1 per bus name.
var volume := DEFAULTS.duplicate()
var fullscreen := false
## How the 480x270 picture is scaled up: "pixel" keeps every pixel the same size (whole
## multiples, with a border if needed), "fill" fills the screen, "auto" picks pixel unless that
## would waste a lot of the screen (the Steam Deck's 1280x800 would only get 960x540).
var scaling := "auto"

const SCALINGS := ["auto", "pixel", "fill"]
const SCALING_NAMES := {"auto": "Auto", "pixel": "Pixel perfect", "fill": "Fill screen"}
## In auto, whole-pixel scaling must use at least this much of what filling would.
const AUTO_KEEP := 0.85

## "auto" follows the device's language, falling back to English.
var language := "auto"
const LANGUAGES := ["auto", "en", "de", "es", "fr", "zh"]
## Each language under its own name, so a player can find theirs whatever is showing.
const LANGUAGE_NAMES := {"en": "English", "de": "Deutsch", "es": "Español", "fr": "Français", "zh": "简体中文"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	get_tree().root.size_changed.connect(_apply_scaling)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for bus in BUSES:
		volume[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), DEFAULTS[bus])), 0.0, 1.0)
		_apply_volume(bus)
	language = str(cfg.get_value("general", "language", "auto"))
	if not language in LANGUAGES:
		language = "auto"
	_apply_language()
	fullscreen = bool(cfg.get_value("video", "fullscreen", on_steam_deck()))
	scaling = str(cfg.get_value("video", "scaling", "auto"))
	if not scaling in SCALINGS:
		scaling = "auto"
	_apply_fullscreen()
	_apply_scaling()
	changed.emit()


func set_volume(bus: String, value: float) -> void:
	if not volume.has(bus):
		return
	volume[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_save()
	changed.emit()


func set_language(code: String) -> void:
	if not code in LANGUAGES:
		return
	language = code
	_apply_language()
	_save()
	changed.emit()


## The language the game shows: the setting, or the device's for "auto".
func current_language() -> String:
	return device_language() if language == "auto" else language


## The device's language when the game has it, else English. "de_AT" -> "de".
static func device_language() -> String:
	var code := OS.get_locale_language()
	return code if LANGUAGE_NAMES.has(code) else "en"


func _apply_language() -> void:
	TranslationServer.set_locale(current_language())


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	_save()
	changed.emit()


func set_scaling(mode: String) -> void:
	if not mode in SCALINGS:
		return
	scaling = mode
	_apply_scaling()
	_save()
	changed.emit()


## Steam sets SteamDeck=1 for games on the Deck; its screen is also a telltale 1280x800.
static func on_steam_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	return DisplayServer.get_name() != "headless" and DisplayServer.screen_get_size() == Vector2i(1280, 800)


## True if a window this size shows the game in whole-pixel steps.
func whole_pixels(window: Vector2) -> bool:
	if scaling != "auto":
		return scaling == "pixel"
	var fit := minf(window.x / 480.0, window.y / 270.0)
	var whole := floorf(fit)
	return whole >= 1.0 and whole / fit >= AUTO_KEEP


func _apply_scaling() -> void:
	var root := get_tree().root
	var on := whole_pixels(Vector2(root.size))
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if on else Window.CONTENT_SCALE_STRETCH_FRACTIONAL


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
	cfg.set_value("general", "language", language)
	for bus in BUSES:
		cfg.set_value("audio", bus.to_lower(), volume[bus])
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "scaling", scaling)
	cfg.save(path)
