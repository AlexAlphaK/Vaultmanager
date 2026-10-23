extends Control
## The end of the Steam demo (see Demo): the shop at dusk, how the player did in their
## demo days, what the full game adds, and Wishlist on Steam / Play again / Title.

const TitleScene := "res://scenes/menu/title_screen.tscn"
const ShopScene := "res://scenes/shop/shop.tscn"
const PANEL := Rect2(80, 14, 320, 242)
## What the demo leaves out, for the "In the full game" list.
const FULL_GAME := [
	"Grow past Main Street into the bullion house and the town landmark.",
	"The trading desk, the smelter and coin grading for collectors.",
	"Rival shops, burglar crews, staff who grow with you, and all four seasons.",
	"Mags's whole story, to the ribbon cutting at your landmark.",
]

var _sky: Texture2D
var _shop: Texture2D
var _wishlist: Button
var _fade: ColorRect
var _leaving := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky = TitleArt.paint_sky().texture()
	_shop = TitleArt.paint_shop().texture()
	_build()
	Music.play("title")
	Sfx.play(self, Sfx.register_chime(), -6.0)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)
	_wishlist.grab_focus.call_deferred()


func _draw() -> void:
	draw_texture(_sky, Vector2.ZERO)
	draw_texture(_shop, Vector2(2, 22))
	draw_rect(Rect2(Vector2.ZERO, Vector2(480, 270)), Color(0.03, 0.02, 0.05, 0.55))


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 10, 6))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var title := _label(box, "Thanks for playing the demo!", Pal.GOLD)
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, tr_n("%d day at your %s", "%d days at your %s", Demo.DAYS) % [Demo.DAYS, Progress.tier_name()], Pal.INK_DIM) \
		.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	var profit := Records.total("profit")
	_pair(grid, "Net worth", Market.format_money(Shop.net_worth()), Pal.GOLD)
	_pair(grid, "Profit on sales", Market.format_money(profit), Pal.GOOD if profit >= 0.0 else Pal.BAD)
	_pair(grid, "Deals closed", str(int(Records.value_of("deals"))), Pal.INK)
	_pair(grid, "Fakes caught", str(int(Records.total("caught"))), Pal.INK)
	_pair(grid, "Reputation", "%.1f ★" % Shop.reputation, Pal.INK)
	_pair(grid, "Achievements", "%d / %d" % [Records.earned.size(), Records.ACHIEVEMENTS.size()], Pal.INK)

	_label(box, "IN THE FULL GAME", Pal.INK_FAINT)
	for line in FULL_GAME:
		_label(box, "· " + tr(line), Pal.INK)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_label(box, "Wishlist Vault Manager to hear when it comes out.", Pal.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	_wishlist = _button(row, "Wishlist on Steam", "PrimaryButton", Demo.open_store_page)
	_wishlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Play again", "BigButton", _play_again)
	_button(row, "Title", "BigButton", func(): _leave(TitleScene))
	if not OS.has_feature("web"):
		_button(row, "Quit", "BigButton", func(): get_tree().quit())


func _label(parent: Control, text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL.size.x - 20
	parent.add_child(l)
	return l


func _pair(grid: GridContainer, caption: String, value: String, col: Color) -> void:
	var c := Label.new()
	c.text = caption
	c.add_theme_color_override("font_color", Pal.INK_DIM)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", col)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(v)


func _button(parent: Control, text: String, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 15)
	b.pressed.connect(func():
		if _leaving:
			return
		Sfx.play(self, Sfx.click(), -8.0)
		on_press.call())
	b.mouse_entered.connect(b.grab_focus)
	parent.add_child(b)
	return b


## A fresh demo shop in the same slot: the finished one has nothing left to play.
func _play_again() -> void:
	SaveGame.new_game()
	_leave(ShopScene)


func _leave(scene: String) -> void:
	_leaving = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.finished.connect(func(): get_tree().change_scene_to_file(scene))
