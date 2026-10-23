extends Node
## The Steam demo (Next Fest): the same game, cut short. It runs for the first DAYS days,
## the shop can grow to Main Street but no further, and when the last day closes the
## player gets the DemoEnd screen with a wishlist button instead of the next morning.
##
## The "Windows Demo" export preset adds the "demo" feature tag, which switches this on.
## From the editor or a test, pass --demo after "--" on the command line, or set `enabled`.
## Demo saves live in their own files, so the demo and the full game never mix shops.

## Days the demo lasts. One week brings the first rent bill, the rest shows the story's
## first chapter and the first town events.
const DAYS := 10
## The highest tier the demo opens: Main Street. The bullion house and the landmark wait.
const MAX_TIER := 1
## The game's Steam app id, once Steamworks gives one (the full game's, not the demo's).
## Until then the wishlist button opens a Steam search for the game.
const STEAM_APP_ID := ""
const GAME_NAME := "Vault Manager"

var enabled := false


func _init() -> void:
	enabled = OS.has_feature("demo") or OS.get_cmdline_user_args().has("--demo")


func _ready() -> void:
	if enabled:
		use_demo_saves()
		get_window().title = tr("%s Demo") % GAME_NAME


## Points the save slots at the demo's own files.
func use_demo_saves() -> void:
	SaveGame.slot_prefix = "user://demo_save_"
	SaveGame.meta_path = "user://demo_save_slots.cfg"
	SaveGame.legacy_path = "user://demo_save.json"
	var cfg := ConfigFile.new()
	cfg.load(SaveGame.meta_path)
	SaveGame.set_slot(int(cfg.get_value("saves", "last_slot", 1)), false)


## True on the demo's last day, so its summary can say so.
func last_day(day := Shop.day) -> bool:
	return enabled and day >= DAYS


## True once the demo's days are used up: the morning after the last day.
func is_over(day := Shop.day) -> bool:
	return enabled and day > DAYS


## Days still to play, today included.
func days_left(day := Shop.day) -> int:
	return maxi(0, DAYS - day + 1)


## Whether tier `t` is held back for the full game.
func tier_locked(t: int) -> bool:
	return enabled and t > MAX_TIER


## The full game's store page, or a store search for it before it has an app id.
func store_url() -> String:
	if STEAM_APP_ID != "":
		return "https://store.steampowered.com/app/%s/" % STEAM_APP_ID
	return "https://store.steampowered.com/search/?term=%s" % GAME_NAME.uri_encode()


func open_store_page() -> void:
	OS.shell_open(store_url())
