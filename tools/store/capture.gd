extends Node
## Store page capture: plays a staged late-game day in the real game and either saves
## Steam screenshots or runs the trailer (recorded with Godot's movie maker).
## tools/store/make_store_assets.sh runs it; on its own:
##   godot --path . --rendering-driver opengl3 res://tools/store/capture.tscn -- --shots
##   godot --path . --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 30 \
##       --write-movie build/store/trailer/frame.png res://tools/store/capture.tscn -- --trailer
## Add --lang=de (or es, fr, zh) after the -- for shots in another language.
## Shots land in build/store/raw/ at the game's 480x270; the script scales them up.
## It uses its own save slot and settings file, so the player's saves are never touched.

const OUT := "res://build/store/raw/"
const ShopScene := "res://scenes/shop/shop.tscn"
const TitleScene := "res://scenes/menu/title_screen.tscn"
## Ticker moves for the day, so the board shows some red and green.
const DAY_MOVES := {"XAU": 1.4, "XAG": 2.3, "XPT": -0.6, "XPD": 0.9}

var trailer := false
var shop: Node
var rng := RandomNumberGenerator.new()
var _caption: CanvasLayer
var _caption_box: ColorRect
var _caption_label: Label
var _curtain: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	trailer = "--trailer" in OS.get_cmdline_user_args()
	rng.seed = 2026
	seed(2026)
	# the store page is in English, whatever the machine speaks; --lang=zh for a localized page
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			lang = arg.trim_prefix("--lang=")
	TranslationServer.set_locale(lang)
	SaveGame.slot_prefix = "user://store_capture_slot_"
	SaveGame.meta_path = "user://store_capture_slots.cfg"
	SaveGame.legacy_path = "user://store_capture_legacy.json"
	SaveGame.delete_slot(1)
	SaveGame.set_slot(1, false)
	Settings.path = "user://store_capture_settings.cfg"
	_quiet_market()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_overlay()
	# stay alive across scene changes
	get_tree().current_scene = null
	_run.call_deferred()


func _run() -> void:
	if trailer:
		await _title(4.5)
	else:
		await _title(1.5)
		await _snap("01_title")
	await _load_shop()
	await _morning()
	await _open_floor()
	await _coin_bench()
	await _jewellery_bench()
	await _bar_bench()
	await _holdup()
	await _closing()
	if trailer:
		await _end_card()
	SaveGame.delete_slot(1)
	get_tree().quit()


# ---------------------------------------------------------------- scenes

func _title(seconds: float) -> void:
	get_tree().change_scene_to_file(TitleScene)
	await _wait(seconds)


## A shop forty days in: the town landmark with every upgrade, both staff, a full vault
## and four and a half stars.
func _load_shop() -> void:
	if trailer:
		await _fade(true)
	Tutorial.skip_all()
	# the bar bench, security and trading desk register their upgrades when the shop loads
	BullionBar.hook_up()
	Security.hook_up()
	DeskSession.hook_up()
	Progress.tier = 3
	for id in Progress.upgrades:
		if int(Progress.upgrades[id].tier) <= Progress.tier and not Progress.owned.has(id):
			Progress.owned.append(id)
	Staff.hired.assign(["clerk", "guard"])
	Shop.day = 44
	Shop.cash = 412000.0
	Shop.reputation = 4.6
	Story.chapter = Story.CHAPTERS.size() - 1
	var coins := Shop.coin_list()
	for item in coins:
		var qty := 40 if item.metal == "XAG" else 6
		Shop.add_stock(item, qty, item.melt_value() * 0.92)
	SaveGame.save_game()
	get_tree().change_scene_to_file(ShopScene)
	await _wait(0.6)
	shop = get_tree().current_scene
	shop.rng.seed = 44
	_day_moves()
	if trailer:
		await _fade(false)


func _morning() -> void:
	var hud: Control = shop.hud
	if trailer:
		_say("Run the gold and silver shop in a small town")
		await _wait(3.0)
	else:
		await _wait(0.5)
	hud._panels.show_town()
	if trailer:
		_say("Win customers from the rival shops across the street")
		await _wait(3.0)
	else:
		await _wait(0.5)
		await _snap("08_town_map")
	hud.show_morning()
	await _wait(0.2)
	shop.open_desk()
	var desk: Control = shop._desk
	await _wait(0.4)
	desk._on_main_button()
	if trailer:
		_say("Trade metals, stocks and crypto on the morning tape")
	await _wait(1.2)
	desk.select(0)
	desk.buy()
	await _wait(0.6)
	desk.buy()
	await _wait(1.0)
	desk.select(2)
	desk.sell()
	await _wait(1.6 if trailer else 1.2)
	if not trailer:
		await _snap("07_trading_desk")
	desk.close_out()
	await _wait(0.8)
	desk.finished.emit(desk.session.pnl())
	await _wait(0.3)
	_say("")


func _open_floor() -> void:
	shop._open_shop()
	shop.hud.hide_panels()
	if trailer:
		_say("Gold and silver prices follow the real market")
		await _wait(6.0)
		_say("Haggle with sellers, collectors and crypto bros")
		await _wait(4.0)
	else:
		await _wait(22.0)
		await _snap("02_shop_floor")


func _coin_bench() -> void:
	var c := _seller()
	c.item = Shop.coins.get("gold_eagle", Shop.coin_list()[0])
	c.fake = "tungsten"
	c.qty = 2
	c.say = "Bought them online, need cash fast."
	await _bench(c)
	var bench: Control = shop._test
	if trailer:
		_say("Test every coin. The fakes are getting better.")
	bench.use_tool("scale")
	await _wait(1.6)
	bench.use_tool("calipers")
	await _wait(1.8)
	bench.use_tool("ping")
	await _wait(1.4)
	bench.use_tool("sigma")
	await _wait(1.8)
	if not trailer:
		await _snap("03_coin_bench")
	bench.use_tool("loupe")
	bench._loupe.global_position = Vector2(150, 70)
	bench._loupe_rim.global_position = bench._loupe.global_position - Vector2(3, 3)
	await _wait(1.4)
	bench.finished.emit("fake")
	await _wait(1.6)


func _jewellery_bench() -> void:
	var c := _seller()
	c.fake = ""
	var p := JewelleryPiece.new()
	p.kind = "ring"
	p.metal = "XAU"
	p.claimed_grade = "18K"
	p.true_grade = "14K"
	p.stamp = "18K"
	p.stone = "moissanite"
	p.carat = 0.9
	p.weight_g = 6.4
	p.claimed_g = 6.5
	p.scam = true
	p.seed = 1234
	c.piece = p
	c.qty = 1
	c.say = "Had it appraised for twice that, honest."
	await _bench(c)
	var bench: Control = shop._test
	if trailer:
		_say("Appraise jewellery with acids and a diamond tester")
	bench.use_tool("scale")
	await _wait(1.2)
	for acid in ["14K", "18K"]:
		bench.drop_acid(acid)
		await _wait(0.9)
	await _wait(1.0)
	if not trailer:
		await _snap("04_jewellery_bench")
	bench.use_tool("tester")
	await _wait(2.0)
	bench.finished.emit("cancel")
	await _wait(0.4)


func _bar_bench() -> void:
	var c := _seller()
	c.fake = ""
	var b := BullionBar.new()
	b.spec_id = "gold_1kg"
	b.seed = 77
	b.serial = BullionBar.new_serial(b.spec().prefix, rng)
	b.make_fake("tungsten_core", rng)
	c.bar = b
	c.qty = 1
	c.say = "Got it cheap from a guy. Real, I promise."
	await _bench(c)
	var bench: Control = shop._test
	if trailer:
		_say("Sweep kilo bars for tungsten cores")
	bench.use_tool("scale")
	await _wait(1.0)
	bench.use_tool("ultrasound")
	# sweep the probe across the bar in rows, the way a player would
	for row in 5:
		var y := 0.15 + row * 0.18
		for step in 9:
			var x := 0.08 + step * 0.105
			bench.probe_at(Vector2(x if row % 2 == 0 else 1.0 - x, y))
			await _wait(0.07)
	await _wait(0.5)
	bench.use_tool("xrf")
	await _wait(2.4)
	if not trailer:
		await _snap("05_bar_bench")
	bench.finished.emit("fake")
	await _wait(1.4)


func _holdup() -> void:
	var r := Security.robber(shop.rng)
	r.pos = ShopArt.ENTRANCE
	shop.robber = r
	shop.robber_revealed = false
	# send him straight to the counter
	shop.queue.insert(0, r)
	Sfx.play(shop, Sfx.door_bell(), -8.0)
	Shop.log_event("A man in a cap walked in and kept his head down.")
	if trailer:
		_say("Watch the door")
	await _wait(4.5)
	if not trailer:
		await _snap("06_holdup")
	shop._panic_button()
	await _wait(2.0)


func _closing() -> void:
	_say("")
	# run the clock to closing time
	shop.time = shop.DAY_SECONDS - 2.0
	await _wait(2.5)
	while shop._vault == null:
		await _wait(0.5)
		if shop.queue.size() > 0 and shop._vault == null:
			for c in shop.queue:
				c.patience = 0.0
	var vault: Control = shop._vault
	if trailer:
		_say("Lock it all in the vault before the burglars come")
	await _wait(1.0)
	# pack the valuables into the safes, biggest first, one at a time like a player would
	var layout: VaultLayout = vault.layout
	var pieces := layout.pieces.duplicate()
	pieces.sort_custom(func(a, b): return float(a.value) > float(b.value))
	for p in pieces:
		if _stow(layout, p):
			Sfx.play(vault, Sfx.safe_clunk(), -14.0)
			await _wait(0.22)
	await _wait(1.0)
	if not trailer:
		await _snap("09_vault")
	vault.lock_up()
	await _wait(2.5)


func _end_card() -> void:
	_say("")
	await _fade(true)
	var card := Control.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sky := TextureRect.new()
	sky.texture = TitleArt.paint_sky().texture()
	card.add_child(sky)
	var top := TextureRect.new()
	top.texture = TitleArt.paint_logo("VAULT", 6).texture()
	top.position = Vector2(round((480 - top.texture.get_width()) / 2.0), 58)
	card.add_child(top)
	var bottom := TextureRect.new()
	bottom.texture = TitleArt.paint_logo("MANAGER", 4).texture()
	bottom.position = Vector2(round((480 - bottom.texture.get_width()) / 2.0), 108)
	card.add_child(bottom)
	var line := Label.new()
	line.theme = UiTheme.get_theme()
	line.text = "Wishlist on Steam"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.position = Vector2(0, 168)
	line.size = Vector2(480, 16)
	line.add_theme_color_override("font_color", Color("#f4ecd0"))
	card.add_child(line)
	_caption.add_child(card)
	_caption.move_child(card, 0)
	await _fade(false)
	await _wait(4.0)
	await _fade(true)
	await _wait(0.5)


# ---------------------------------------------------------------- helpers

## A seller at the front of the queue.
func _seller() -> Customer:
	var c := Customer.create(Shop.day, Shop.reputation, Shop.coin_list(), rng)
	c.kind = "seller"
	c.piece = null
	c.bar = null
	c.reserve = 0.88
	c.pos = ShopArt.SLOTS[0]
	c.walking = false
	return c


## Moves piece `p` off the tray into the first safe spot it fits, floor safe first.
func _stow(layout: VaultLayout, p: Dictionary) -> bool:
	if p.area != VaultLayout.TRAY:
		return false
	for area in [VaultLayout.FLOOR, VaultLayout.WALL]:
		var cells: Vector2i = layout.areas[area].size
		for y in cells.y:
			for x in cells.x:
				for rot in 2:
					if layout.can_place(p, area, Vector2i(x, y), rot):
						return layout.place(p, area, Vector2i(x, y), rot)
	return false


## Puts `c` at the counter and opens their bench.
func _bench(c: Customer) -> void:
	shop.queue.insert(0, c)
	await _wait(0.6 if trailer else 0.2)
	shop._open_test(c)
	await _wait(0.4)


func _quiet_market() -> void:
	Market.service_url = "http://127.0.0.1:9/"
	for child in Market.get_children():
		if child is Timer:
			child.stop()
		elif child is HTTPRequest:
			child.cancel_request()
	# the shipped game shows real prices; the capture runs offline on its own copy of them
	Market.source = "live"
	_day_moves()


func _day_moves() -> void:
	Market.day_open = {}
	for metal in DAY_MOVES:
		Market.day_open[metal] = float(Market.prices[metal]) / (1.0 + DAY_MOVES[metal] / 100.0)
	Market.prices_changed.emit(Market.prices)


func _build_overlay() -> void:
	_caption = CanvasLayer.new()
	_caption.layer = 100
	add_child(_caption)
	_caption_box = ColorRect.new()
	_caption_box.color = Color(0.03, 0.03, 0.05, 0.82)
	_caption_box.position = Vector2(0, 236)
	_caption_box.size = Vector2(480, 22)
	_caption_box.visible = false
	_caption.add_child(_caption_box)
	_caption_label = Label.new()
	_caption_label.theme = UiTheme.get_theme()
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.size = _caption_box.size
	_caption_label.add_theme_color_override("font_color", Color("#f6c453"))
	_caption_box.add_child(_caption_label)
	_curtain = ColorRect.new()
	_curtain.color = Color(0, 0, 0, 0)
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.size = Vector2(480, 270)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_curtain)


## Shows a caption along the bottom in the trailer; "" hides it.
func _say(text: String) -> void:
	if not trailer:
		return
	_caption_label.text = text
	_caption_box.visible = text != ""


func _fade(to_black: bool) -> void:
	var t := create_tween()
	t.tween_property(_curtain, "color:a", 1.0 if to_black else 0.0, 0.5)
	await t.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _snap(name: String) -> void:
	if trailer:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("STORE CAPTURE: ", name)
