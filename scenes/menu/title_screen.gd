extends Control
## The title screen and the game's main scene: the shop at dusk under the night sky,
## the logo, a live price ticker, and Continue / Save slots / New game / Settings / Quit.

const ShopScene := "res://scenes/shop/shop.tscn"
const DemoEndScene := "res://scenes/menu/demo_end.tscn"
const SHOP_POS := Vector2(2, 22)
const COLUMN_X := 322
const COLUMN_W := 154
const TICKER_Y := 258
const TICKER_SPEED := 18.0 # px per second
const METAL_NAMES := {"XAU": "GOLD", "XAG": "SILVER", "XPT": "PLATINUM", "XPD": "PALLADIUM"}

var _sky: Texture2D
var _shop: Texture2D
var _front: Texture2D
var _keeper: Texture2D
var _visitors: Array[Texture2D] = []
var _logo_top: Texture2D
var _logo_bottom: Texture2D
var _sparkles: Array[Vector2] = []
var _time := 0.0
var _ticker := ""
var _ticker_w := 0
var _menu: VBoxContainer
var _continue: Button
var _new: Button
var _save_info: Label
var _settings: SettingsPanel
var _slots: SaveSlotsPanel
var _dim: ColorRect
var _fade: ColorRect
var _leaving := false
var _save := {}
var _continue_slot := 0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky = TitleArt.paint_sky().texture()
	_shop = TitleArt.paint_shop().texture()
	_front = ShopArt.paint_front(true).texture()
	_keeper = PeopleArt.paint(PeopleArt.keeper_look(), 0).texture()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for n in 2:
		_visitors.append(PeopleArt.paint(PeopleArt.random_look(rng), 0).texture())
	_logo_top = TitleArt.paint_logo("VAULT", 4).texture()
	_logo_bottom = TitleArt.paint_logo("MANAGER", 3).texture()
	for n in 6:
		_sparkles.append(Vector2(rng.randf_range(COLUMN_X + 20, COLUMN_X + COLUMN_W - 20), rng.randf_range(18, 64)).round())
	_build_menu()
	Market.prices_changed.connect(func(_p): _rebuild_ticker())
	Market.currency_changed.connect(func(_c): _rebuild_ticker())
	Settings.changed.connect(_rebuild_ticker)
	_rebuild_ticker()
	Music.play("title")

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_texture(_sky, Vector2.ZERO)
	draw_texture(_shop, SHOP_POS)
	var iso := ShopArt.iso_on(PixelCanvas.new(1, 1))
	var kp := (SHOP_POS + iso.p(ShopArt.KEEPER_SPOT.x, ShopArt.KEEPER_SPOT.y)).round()
	var breathe := 1.0 if fmod(_time, 2.4) < 1.2 else 0.0
	draw_texture(_keeper, kp + Vector2(-8, -28 + breathe))
	draw_texture(_front, SHOP_POS)
	for n in _visitors.size():
		var slot: Vector2 = ShopArt.SLOTS[n]
		var base := (SHOP_POS + iso.p(slot.x, slot.y)).round()
		draw_rect(Rect2(base + Vector2(-5, -1), Vector2(11, 2)), Color(0, 0, 0, 0.3))
		draw_texture(_visitors[n], base + Vector2(-8, -27 + (1.0 if fmod(_time + n * 1.1, 2.8) < 1.4 else 0.0)))

	var cx := COLUMN_X + COLUMN_W / 2.0
	draw_texture(_logo_top, Vector2(roundf(cx - _logo_top.get_width() / 2.0), 16))
	draw_texture(_logo_bottom, Vector2(roundf(cx - _logo_bottom.get_width() / 2.0), 43))
	for n in _sparkles.size():
		var phase := fmod(_time * 0.7 + n * 0.37, 1.0)
		if phase < 0.25:
			var a := sin(phase / 0.25 * PI)
			var p := _sparkles[n]
			var col := Color(1.0, 0.97, 0.85, a)
			draw_rect(Rect2(p, Vector2.ONE), col)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(p + d, Vector2.ONE), Color(col, a * 0.6))
			if a > 0.6:
				for d in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
					draw_rect(Rect2(p + d, Vector2.ONE), Color(col, a * 0.3))
	_draw_ticker()


func _draw_ticker() -> void:
	var font := PixelFont.get_font()
	draw_rect(Rect2(0, TICKER_Y, 480, 12), Color("#120e0a"))
	draw_rect(Rect2(0, TICKER_Y, 480, 1), Pal.PANEL_EDGE)
	if _ticker_w > 0:
		var x := -fmod(_time * TICKER_SPEED, float(_ticker_w))
		while x < 480.0:
			draw_string(font, Vector2(roundf(x) + 52, TICKER_Y + 9), _ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, Pal.LED)
			x += _ticker_w
	# the feed badge sits over the scrolling text
	draw_rect(Rect2(0, TICKER_Y + 1, 50, 11), Color("#120e0a"))
	var badge: String = {"live": tr("● LIVE"), "cached": tr("● CACHED")}.get(Market.source, tr("● OFFLINE"))
	draw_string(font, Vector2(4, TICKER_Y + 9), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, {"live": Pal.GOOD, "cached": Pal.WARN}.get(Market.source, Pal.INK_FAINT))


func _rebuild_ticker() -> void:
	var parts: Array[String] = []
	for metal in ["XAU", "XAG", "XPT", "XPD"]:
		if Market.prices.has(metal):
			var change := Market.metal_move_percent(metal)
			parts.append("%s %s %s%.1f%%" % [tr(METAL_NAMES[metal]), Market.format_money(Market.prices[metal], 2 if metal == "XAG" else 0), "▲" if change >= 0.0 else "▼", absf(change)])
	for group in [Market.crypto, Market.stocks]:
		for symbol in group:
			var q: Dictionary = group[symbol]
			var change := float(q.get("change_pct", 0.0))
			parts.append("%s %s %s%.1f%%" % [symbol, Market.format_money(float(q.get("price", 0.0)), 2 if float(q.get("price", 0.0)) < 10.0 else 0), "▲" if change >= 0.0 else "▼", absf(change)])
	_ticker = "      ".join(parts) + "      " if not parts.is_empty() else tr("Fetching prices...      ")
	_ticker_w = PixelFont.measure(_ticker) + 1


# ---------------------------------------------------------------- menu

func _build_menu() -> void:
	var sub := Label.new()
	add_child(sub) # in the tree first, so it measures with the pixel font
	sub.text = "Run the biggest gold shop in town"
	sub.add_theme_color_override("font_color", Pal.INK_DIM)
	if Demo.enabled:
		sub.text = tr("DEMO · your first %d days") % Demo.DAYS
		sub.add_theme_color_override("font_color", Pal.GOLD)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(COLUMN_X - 10, 68)
	sub.size = Vector2(COLUMN_W + 20, 8)
	_build_buttons()


## The button column. Rebuilt after the slots page closes, since a slot may be gone.
func _build_buttons() -> void:
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	_menu.position = Vector2(COLUMN_X + 22, 92)
	_menu.size = Vector2(COLUMN_W - 44, 0)
	add_child(_menu)
	_continue_slot = SaveGame.continue_slot()
	_save = SaveGame.peek(_continue_slot) if _continue_slot else {}
	_continue = _menu_button("Continue", _on_continue)
	_save_info = Label.new()
	_save_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_info.add_theme_color_override("font_color", Pal.INK_DIM)
	_menu.add_child(_save_info)
	_menu_button("Save slots", _open_slots)
	_new = _menu_button("New game", _on_new_game)
	_menu_button("Settings", _open_settings)
	if not OS.has_feature("web"):
		_menu_button("Quit", func(): get_tree().quit())
	if _save.is_empty():
		_continue.disabled = true
		_continue.focus_mode = Control.FOCUS_NONE
		_save_info.text = "No saved shop yet"
		_new.grab_focus.call_deferred()
	else:
		var day: int = _save.day + (1 if _save.day_over else 0)
		_save_info.text = tr("Demo finished") if Demo.is_over(day) else \
			tr("Day %d · %s") % [day, Progress.tier_name(clampi(_save.tier, 0, Progress.TIERS.size() - 1))]
		_continue.grab_focus.call_deferred()


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(0, 15)
	b.pressed.connect(func():
		if _leaving:
			return
		Sfx.play(self, Sfx.click(), -8.0)
		on_press.call())
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	_menu.add_child(b)
	return b


func _on_continue() -> void:
	SaveGame.set_slot(_continue_slot)
	_go_to_shop()


## Starts in the first empty slot, so a new shop never erases an old one. With every
## slot taken it opens the slots page to pick one to delete.
func _on_new_game() -> void:
	var n := SaveGame.first_empty_slot()
	if n == 0:
		_open_slots(tr("Every slot is full. Delete one to start a new shop."))
		return
	_start_slot(n, true)


func _start_slot(n: int, fresh: bool) -> void:
	SaveGame.set_slot(n)
	if fresh:
		SaveGame.new_game()
	_go_to_shop()


func _open_settings() -> void:
	_settings = SettingsPanel.new()
	_open_overlay(_settings)
	_settings.closed.connect(_close_overlay)


func _open_slots(hint := "") -> void:
	_slots = SaveSlotsPanel.new(hint)
	_open_overlay(_slots)
	_slots.closed.connect(_close_overlay)
	_slots.chosen.connect(_start_slot)


func _open_overlay(panel: Control) -> void:
	_menu.visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.02, 0.05, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	move_child(_dim, _fade.get_index())
	add_child(panel)
	move_child(panel, _fade.get_index())


func _close_overlay() -> void:
	for panel in [_settings, _slots]:
		if panel:
			panel.queue_free()
	_settings = null
	_slots = null
	_dim.queue_free()
	_menu.queue_free()
	_build_buttons()
	move_child(_menu, _fade.get_index())


func _go_to_shop() -> void:
	_leaving = true
	var scene := ShopScene
	# a demo shop that has used up its days goes straight to the demo's end screen
	var save := SaveGame.peek()
	if Demo.enabled and not save.is_empty() and Demo.is_over(save.day + (1 if save.day_over else 0)) and SaveGame.load_game():
		scene = DemoEndScene
	Sfx.play(get_tree().root, Sfx.door_bell(), -6.0)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.finished.connect(func(): get_tree().change_scene_to_file(scene))
