extends Node
## Bug sweep: a bot plays the real game from the title screen the way a restless player
## would. It clicks whatever buttons are on screen (through the real GUI, so whatever is
## on top gets the click), clicks and drags at random over the benches, the vault and the
## trading desk, presses Esc, and now and then quits to the title, switches save slots,
## starts new shops and comes back. Along the way it checks:
##   - stuck screens: the game makes no progress for a long time whatever it clicks
##   - save/load: right after a shop loads, every saved section matches the file it came
##     from, and a new shop in an empty slot starts like the first new shop did
##   - script errors: Godot prints them; tests/run_bug_bots.sh collects them from the logs
## Run one bot:
##   godot --headless --path . res://tests/bug_bot.tscn -- --seed=3 --minutes=10
## Options: --seed=N, --minutes=N (real minutes), --speed=N (game seconds per real
## second, default 8), --rich (tops the cash up to $2M and the stars to 4.6 every morning so the bot reaches the late game),
## --skip-tutorial, --days=N (stop after N shop days in total), --lang=de|es|fr|en (play in
## that language, to catch text that breaks a translation).
## Prints "BUG BOT: ..." lines for each finding and exits 1 when it found any.

const TitleScene := "res://scenes/menu/title_screen.tscn"
const SAVE_PREFIX := "user://bug_bot_%d_slot_"
## Game seconds with no progress before a screen counts as stuck.
const STUCK_SECONDS := 150.0
## ...and at least this many clicks and drags tried in that time.
const STUCK_ACTIONS := 1200
## Saved fields that legitimately change when a shop loads or a new one starts.
const VOLATILE := ["saved_unix", "log", "lots_seed", "seed"]

var rng := RandomNumberGenerator.new()
var seed_value := 1
var speed := 8.0
var rich := false
var skip_tutorial := false
var max_days := 0
var deadline_msec := 0

var findings: Array[String] = []
var actions := 0
var days_played := 0
var loads_checked := 0
var _cooldown := 0.0
var _busy := false # a scripted sequence (quit, reload, slot switch) is running
var _signature := ""
var _still := 0.0
var _still_actions := 0
var _stuck_reported := false
var _last_day := -1
var _last_phase := ""
## The saved sections of the first new shop, to compare later new shops with.
var _fresh := {}
var _settings_backup := ""
var _seen := {}
var _reload_day := -1
var _new_shop := false
## The last few things the bot did, for the stuck report.
var _recent: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	seed_value = int(args.get("seed", 1))
	speed = float(args.get("speed", 8.0))
	rich = args.has("rich")
	skip_tutorial = args.has("skip-tutorial")
	max_days = int(args.get("days", 0))
	deadline_msec = Time.get_ticks_msec() + int(float(args.get("minutes", 5.0)) * 60000.0)
	rng.seed = seed_value
	seed(seed_value)
	# never touch the player's saves or settings
	SaveGame.slot_prefix = SAVE_PREFIX % seed_value
	SaveGame.meta_path = "user://bug_bot_%d_slots.cfg" % seed_value
	SaveGame.legacy_path = "user://bug_bot_%d_legacy.json" % seed_value
	for n in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete_slot(n)
	SaveGame.set_slot(1)
	if FileAccess.file_exists(Market.SETTINGS_PATH):
		_settings_backup = FileAccess.get_file_as_string(Market.SETTINGS_PATH)
	Settings.path = "user://bug_bot_%d_settings.cfg" % seed_value
	if args.has("lang"):
		Settings.set_language(args.lang)
	_quiet_market()
	Engine.time_scale = speed
	Day.phase_changed.connect(_on_phase)
	SaveGame.new_game_started.connect(func(): _new_shop = true)
	print("BUG BOT seed %d, speed %.0fx%s%s, %s" % [seed_value, speed, ", rich" if rich else "", ", no tutorial" if skip_tutorial else "", TranslationServer.get_locale()])
	# stay alive across scene changes: hand the current scene slot to the game
	get_tree().current_scene = null
	get_tree().change_scene_to_file.call_deferred(TitleScene)


func _process(delta: float) -> void:
	if Time.get_ticks_msec() > deadline_msec or (max_days > 0 and days_played >= max_days):
		_finish()
		return
	_watch_progress(delta)
	var shop := _shop()
	if _new_shop and shop and shop.is_node_ready() and Day.phase == Day.MORNING:
		_new_shop = false
		_on_new_shop()
	if _busy:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = rng.randf_range(0.15, 0.6)
	_act()


# ---------------------------------------------------------------- playing

func _act() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var shop := _shop()
	# now and then, a scripted trip through the save system
	if shop and shop.is_node_ready() and not get_tree().paused and Day.phase == Day.MORNING and _visible_text("Open the shop") \
			and _reload_day != Shop.day and rng.randf() < 0.15:
		_reload_day = Shop.day
		_run(_reload_check)
		return
	if shop and shop.is_node_ready() and not get_tree().paused and Day.is_open() and rng.randf() < 0.0007:
		_run(_quit_mid_day)
		return
	if shop and shop.is_node_ready() and not get_tree().paused and Day.phase == Day.AFTER_HOURS and rng.randf() < 0.05:
		_run(_quit_after_hours)
		return
	if scene.scene_file_path == TitleScene and _visible_text("Save slots") and rng.randf() < 0.05:
		_run(_slot_trip)
		return
	actions += 1
	_check_layout()
	var roll := rng.randf()
	var buttons := _buttons().filter(func(b): return not _label(b).begins_with("Quit"))
	if roll < 0.7 and not buttons.is_empty():
		var b: BaseButton = _pick_button(buttons)
		_note_action("click '%s'" % _label(b))
		_click(_center(b))
	elif roll < 0.85:
		var area := _play_area()
		var a := _random_point(area)
		var b2 := _random_point(area)
		_note_action("drag %s -> %s" % [a, b2])
		_drag(a, b2)
	elif roll < 0.98:
		var p := _random_point(_play_area())
		_note_action("click at %s" % p)
		_click(p)
	else:
		_note_action("Esc")
		_key(KEY_ESCAPE)


## The monkey prefers the buttons that move the day along, but presses everything.
func _pick_button(buttons: Array) -> BaseButton:
	var weights: Array[float] = []
	var total := 0.0
	for b in buttons:
		var t := _label(b)
		var w := 1.0
		if t in ["Open the shop", "Next day", "Continue", "Lock up", "Resume", "Genuine", "Fake", "Offer", "Sell"]:
			w = 3.0
		elif t in ["Delete", "Sure?", "New game", "Start over", "Sure? Start over"]:
			w = 0.15
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in buttons.size():
		r -= weights[i]
		if r <= 0.0:
			return buttons[i]
	return buttons[-1]


## Every button a player could press right now: visible, enabled and on screen.
func _buttons() -> Array:
	var out := []
	_collect(get_tree().root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is CanvasLayer and not n.visible:
		return
	if n is CanvasItem and not n.visible:
		return
	if n is BaseButton and not n.disabled and n.is_visible_in_tree() and n.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		var t := _label(n)
		var r: Rect2 = n.get_global_rect()
		if r.size.x > 0 and Rect2(0, 0, 480, 270).has_point(r.get_center()):
			out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _label(b: Node) -> String:
	if b is Button:
		return b.text if b.text != "" else b.tooltip_text
	return b.name


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Where random clicks and drags land: the open minigame if there is one, else anywhere.
func _play_area() -> Rect2:
	var shop := _shop()
	if shop:
		for key in ["_test", "_vault", "_desk"]:
			var c = shop.get(key)
			if c is Control and is_instance_valid(c) and c.is_visible_in_tree():
				return c.get_global_rect().intersection(Rect2(0, 0, 480, 270))
	return Rect2(0, 0, 480, 270)


func _random_point(r: Rect2) -> Vector2:
	return Vector2(rng.randf_range(r.position.x, r.end.x - 1), rng.randf_range(r.position.y, r.end.y - 1)).floor()


func _click(at: Vector2, scripted := false) -> void:
	if not scripted and _on_quit(at):
		return
	_mouse_move(at)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(e, true)


func _drag(from: Vector2, to: Vector2) -> void:
	if _on_quit(from) or _on_quit(to):
		return
	_mouse_move(from)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	e.global_position = from
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)
	for n in range(1, 6):
		_mouse_move(from.lerp(to, n / 5.0), MOUSE_BUTTON_MASK_LEFT)
	var up := e.duplicate()
	up.pressed = false
	up.position = to
	up.global_position = to
	up.button_mask = 0
	get_viewport().push_input(up, true)


## A random click or drag must not land on a Quit button and end the run.
func _on_quit(at: Vector2) -> bool:
	return _buttons().any(func(b): return _label(b).begins_with("Quit") and b.get_global_rect().grow(2).has_point(at))


func _mouse_move(at: Vector2, mask := 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = mask
	get_viewport().push_input(m, true)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		get_viewport().push_input(e, true)


func _note_action(what: String) -> void:
	_recent.append("%s %s: %s" % [Day.phase, _page(), what])
	if _recent.size() > 25:
		_recent.pop_front()
	if actions % 50 == 0 or OS.has_environment("BUG_BOT_VERBOSE"):
		print("  [%s day %d %s $%d] %s" % [_where(), Shop.day, Day.phase, Shop.cash, what])


## A button the player can't reach, because its page grew past the edge of the screen.
func _check_layout() -> void:
	var screen := Rect2(0, 0, 480, 270)
	for b in get_tree().root.find_children("*", "BaseButton", true, false):
		if not b.is_visible_in_tree() or b.get_global_rect().size.x <= 0.0:
			continue
		if screen.encloses(b.get_global_rect()):
			continue
		# a button scrolled out of sight inside a scroll box is fine
		var scroll := b.get_parent()
		while scroll and not scroll is ScrollContainer:
			scroll = scroll.get_parent()
		if scroll and screen.encloses(scroll.get_global_rect()):
			continue
		var shop := _shop()
		var page: String = shop.hud._panels.page if shop else ""
		_report("layout", "'%s' is off the screen at %s on %s%s" % [_label(b), b.get_global_rect(), _where(),
			" (page '%s')" % page if page != "" else ""])


# ---------------------------------------------------------------- progress and stuck screens

func _on_phase(phase: String) -> void:
	# a rich shop gets topped up every morning, since burglars take cash left out of the safes
	if rich and phase == Day.MORNING:
		_top_up.call_deferred()
	if phase == Day.AFTER_HOURS:
		days_played += 1
		if days_played % 5 == 0:
			print("BUG BOT progress: %d days, %d actions, %d loads checked, day %d, tier %d, cash %s" % [
				days_played, actions, loads_checked, Shop.day, Progress.tier, Market.format_money(Shop.cash)])


## Something should change every so often: the clock, the day, the phase, the screen.
func _watch_progress(delta: float) -> void:
	var shop := _shop()
	var sig := _where()
	if shop and shop.is_node_ready():
		# in the shop only the game moving on counts, not menus opening and closing
		sig += "|%d|%s|%d|%d|%s|%s|%s" % [Shop.day, Day.phase, int(shop.time), shop.queue.size(),
			shop._test != null, shop._vault != null, shop._desk != null]
	else:
		sig += "|" + ",".join(_buttons().map(_label))
	if sig != _signature:
		_signature = sig
		_still = 0.0
		_still_actions = actions
		_stuck_reported = false
		return
	_still += delta
	# at high speed a frame can cover several game seconds, so count the bot's tries too
	if _still > STUCK_SECONDS and actions - _still_actions > STUCK_ACTIONS and not _stuck_reported:
		_stuck_reported = true
		_report("stuck", "no progress for %.0f game seconds and %d actions. %s. Last actions: %s" % [_still,
			actions - _still_actions, _describe(), " | ".join(_recent)])
		# get going again, the way a player would: back to the title
		get_tree().paused = false
		get_tree().change_scene_to_file(TitleScene)


func _describe() -> String:
	var shop := _shop()
	var bits := ["screen %s" % _where(), "buttons [%s]" % ", ".join(_buttons().map(_label))]
	if shop:
		bits.append("day %d %s, clock %.1f, paused %s, closing %s, queue %d, leaving %d, at clerk %s, away %.1f" % [
			Shop.day, Day.phase, shop.time, shop.paused, shop.closing, shop.queue.size(), shop.leaving.size(),
			shop.at_clerk != null, shop.away])
		bits.append("bench %s, vault %s, desk %s, pause menu %s, tree paused %s, coach '%s' guiding %s" % [
			shop._test != null, shop._vault != null, shop._desk != null, shop._pause.is_open(), get_tree().paused,
			shop.coach.step, shop.coach.guiding])
		var front: Customer = shop._front()
		if front:
			bits.append("front %s (%s)" % [front.name, front.kind])
		var panels: Control = shop.hud._panels
		if panels.visible:
			var off := []
			for b in panels.find_children("*", "BaseButton", true, false):
				if b.is_visible_in_tree() and not Rect2(0, 0, 480, 270).has_point(b.get_global_rect().get_center()):
					off.append("%s at %s" % [_label(b), b.get_global_rect().position])
			bits.append("panel '%s' at %s, off-screen buttons [%s]" % [panels.page, panels.get_global_rect(), ", ".join(off)])
	return "; ".join(bits)


func _page() -> String:
	var shop := _shop()
	return shop.hud._panels.page if shop and shop.is_node_ready() else ""


func _where() -> String:
	var s := get_tree().current_scene
	return "none" if s == null else s.scene_file_path.get_file().get_basename()


func _shop() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.scene_file_path.ends_with("shop.tscn") else null


# ---------------------------------------------------------------- save and load

func _run(sequence: Callable) -> void:
	_busy = true
	await sequence.call()
	_busy = false
	_signature = ""


## Morning: quit to the title, Continue, and check the shop came back as it was saved.
func _reload_check() -> void:
	var slot := SaveGame.slot
	print("BUG BOT: reload check in slot %d on day %d" % [slot, Shop.day])
	if not await _quit_to_title():
		return
	if not await _press("Continue"):
		return
	if not await _wait_for_shop():
		return
	_check_loaded("reload on day %d" % Shop.day)


## Mid-day: quit to the title and continue. The day starts over from the morning save.
func _quit_mid_day() -> void:
	print("BUG BOT: quit mid-day on day %d" % Shop.day)
	if not await _quit_to_title():
		return
	if not await _press("Continue"):
		return
	if not await _wait_for_shop():
		return
	_check_loaded("continue after quitting mid-day")


## On the day's summary: the night's autosave should hold everything, and Continue
## should pick up on the next morning.
func _quit_after_hours() -> void:
	var day := Shop.day
	print("BUG BOT: quit on the summary of day %d" % day)
	var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
	if typeof(data) != TYPE_DICTIONARY or not bool(data.get("day_over", false)):
		_report("save", "the summary of day %d is up but the save is not the end-of-day one" % day)
	else:
		var live := _live_sections()
		# the counter's prices stay adjustable on the summary, after the save
		for k in ["buy_percent", "sell_premium"]:
			live.shop.erase(k)
			data.shop.erase(k)
		for key in live:
			var diffs: Array[String] = []
			_diff(key, _plain(data.get(key)), live[key], diffs)
			if not diffs.is_empty():
				_report("save", "end-of-day save of '%s' differs from the game: %s" % [key, "; ".join(diffs.slice(0, 6))])
	if not await _quit_to_title():
		return
	if not await _press("Continue"):
		return
	if not await _wait_for_shop():
		return
	loads_checked += 1
	if Shop.day != day + 1 or Day.phase != Day.MORNING:
		_report("save", "Continue after the summary of day %d opened day %d (%s), not the next morning" % [day, Shop.day, Day.phase])


## On the title screen: open the slots page and play another slot, or start a shop in an empty one.
func _slot_trip() -> void:
	if not await _press("Save slots"):
		return
	await _frames(3)
	var plays := _buttons().filter(func(b): return _label(b) in ["Play", "New"])
	if plays.is_empty():
		await _press("Back")
		return
	var b: BaseButton = plays[rng.randi() % plays.size()]
	var fresh := _label(b) == "New"
	print("BUG BOT: slot trip, %s" % ("new shop in an empty slot" if fresh else "play a saved slot"))
	_click(_center(b))
	if not await _wait_for_shop():
		return
	if not fresh:
		_check_loaded("play slot %d from the slots page" % SaveGame.slot)


func _quit_to_title() -> bool:
	var shop := _shop()
	if shop == null:
		return false
	# close whatever is open first, the way a player would reach the pause menu
	shop.open_pause_menu()
	await _frames(2)
	if not await _press("Quit to title"):
		return false
	for n in 120:
		await _frames(1)
		if _where() == "title_screen":
			await _frames(30) # the fade in
			return true
	_report("stuck", "Quit to title did not reach the title screen. %s" % _describe())
	return false


func _wait_for_shop() -> bool:
	for n in 300:
		await _frames(1)
		var shop := _shop()
		if shop and shop.is_node_ready():
			await _frames(3)
			return true
	_report("stuck", "the shop never opened after leaving the title screen. %s" % _describe())
	get_tree().change_scene_to_file(TitleScene)
	return false


func _press(text: String) -> bool:
	for n in 60:
		for b in _buttons():
			if _label(b) == text:
				_click(_center(b), true)
				await _frames(2)
				return true
		await _frames(1)
	_report("missing button", "no '%s' button to press. %s" % [text, _describe()])
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Right after a load, everything saved should match the file it came from.
func _check_loaded(what: String) -> void:
	loads_checked += 1
	var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path))
	if typeof(data) != TYPE_DICTIONARY:
		_report("save", "%s: the save file is unreadable" % what)
		return
	if bool(data.get("day_over", false)):
		return # the shop moved on to the next morning after loading
	var live := _live_sections()
	for key in live:
		if not data.has(key):
			_report("save", "%s: section '%s' is missing from the save" % [what, key])
			continue
		var diffs: Array[String] = []
		_diff(key, _plain(data[key]), live[key], diffs)
		if not diffs.is_empty():
			_report("save", "%s: '%s' differs from the save: %s" % [what, key, "; ".join(diffs.slice(0, 6))])


func _top_up() -> void:
	if _shop() == null or Day.phase != Day.MORNING:
		return
	if Shop.cash < 1000000.0:
		Shop.add_cash(2000000.0 - Shop.cash)
	# and enough stars to move up
	Shop.reputation = maxf(Shop.reputation, 4.6)
	Shop.changed.emit()
	SaveGame.save_game()


## A new shop on day 1 should look like the first new shop did (nothing carried over).
func _on_new_shop() -> void:
	print("BUG BOT: new shop in slot %d, cash %s" % [SaveGame.slot, Shop.cash])
	var live := _live_sections()
	if _fresh.is_empty():
		_fresh = live
	else:
		for key in _fresh:
			var diffs: Array[String] = []
			_diff(key, _fresh[key], live.get(key), diffs)
			if not diffs.is_empty():
				_report("new game", "a new shop differs from the first one in '%s': %s" % [key, "; ".join(diffs.slice(0, 6))])
	if skip_tutorial:
		_shop().coach.skip()


func _live_sections() -> Dictionary:
	var out := {}
	for key in SaveGame._sections:
		out[key] = _plain(SaveGame._sections[key].save.call())
	return out


## Through JSON and back, so live values compare like loaded ones.
func _plain(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func _diff(path: String, a: Variant, b: Variant, out: Array[String]) -> void:
	if out.size() > 8:
		return
	if path.get_slice(".", path.get_slice_count(".") - 1) in VOLATILE:
		return
	if typeof(a) != typeof(b):
		out.append("%s: %s vs %s" % [path, _short(a), _short(b)])
	elif a is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s.%s only in the first" % [path, k])
			else:
				_diff("%s.%s" % [path, k], a[k], b[k], out)
		for k in b:
			if not a.has(k):
				out.append("%s.%s only in the second" % [path, k])
	elif a is Array:
		if a.size() != b.size():
			out.append("%s: %d vs %d entries" % [path, a.size(), b.size()])
			return
		for i in a.size():
			_diff("%s[%d]" % [path, i], a[i], b[i], out)
	elif a is float:
		if not is_equal_approx(a, b) and absf(a - b) > 0.01:
			out.append("%s: %s vs %s" % [path, a, b])
	elif a != b:
		out.append("%s: %s vs %s" % [path, _short(a), _short(b)])


func _short(v: Variant) -> String:
	var s := str(v)
	return s if s.length() < 60 else s.substr(0, 57) + "..."


# ---------------------------------------------------------------- reporting

func _report(kind: String, text: String) -> void:
	var key := kind + text.get_slice(":", 0).get_slice(".", 0)
	if _seen.has(key) and kind != "stuck":
		return
	_seen[key] = true
	findings.append("%s: %s" % [kind, text])
	print("BUG BOT %s: %s" % [kind.to_upper(), text])


func _finish() -> void:
	set_process(false)
	Engine.time_scale = 1.0
	get_tree().paused = false
	print("BUG BOT done: seed %d, %d days, %d actions, %d loads checked, %d findings" % [
		seed_value, days_played, actions, loads_checked, findings.size()])
	for f in findings:
		print("  - " + f)
	for n in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete_slot(n)
	for p in [SaveGame.meta_path, Settings.path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if _settings_backup != "":
		var f := FileAccess.open(Market.SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(_settings_backup)
	get_tree().quit(1 if not findings.is_empty() else 0)


func _quiet_market() -> void:
	Market.service_url = "http://127.0.0.1:9/"
	for child in Market.get_children():
		if child is Timer:
			child.stop()
		elif child is HTTPRequest:
			child.cancel_request()
	Market.source = "simulated"


func _visible_text(text: String) -> bool:
	return _buttons().any(func(b): return _label(b) == text)


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
