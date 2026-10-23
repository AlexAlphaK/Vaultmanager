class_name DecorPanel
extends Control
## Decorating the shop in the morning: the catalogue and storeroom sit over the side
## panel, and the shop floor shows its decor spots. Pick a piece (buy one, or take one
## from the storeroom), then click a spot to put it there. Click a piece on the floor
## to pick it up and move it, or put it away. Right click, Esc or the pad's B drops
## whatever you're holding; with empty hands they close the panel.

signal closed

## Over the counter card and the vault list; the day, stars and cash stay in sight above.
const RECT := Rect2(316, 80, 164, 190)

## The room whose floor is being decorated (shop_room.gd).
var room: Node2D
## The piece in hand, and the spot it was picked up from (-1: storeroom).
var held := ""
var held_from := -1

var _box: VBoxContainer
var _hint: Label
var _spots: Control
var _spot_buttons: Array[Button] = []


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 6, 4))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_box = VBoxContainer.new()
	_box.position = Vector2(6, 4)
	_box.size = RECT.size - Vector2(12, 8)
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	visible = false
	Decor.changed.connect(_rebuild)
	Shop.changed.connect(_rebuild)


## Shows the panel and the spots on the floor of `on_room`.
func open(on_room: Node2D) -> void:
	room = on_room
	held = ""
	held_from = -1
	visible = true
	room.decorating = true
	_build_spots()
	_rebuild()


## `notify` false when the shop closes it for you (opening up, a new morning).
func close(notify := true) -> void:
	if not visible:
		return
	visible = false
	held = ""
	if room:
		room.decorating = false
		room.held = ""
		room.hover_spot = -1
	if _spots:
		_spots.queue_free()
		_spots = null
	_spot_buttons.clear()
	if notify:
		closed.emit()


func is_open() -> bool:
	return visible


## Picks up a piece: one from the storeroom (from = -1) or the one on a spot.
func hold(id: String, from := -1) -> void:
	held = id
	held_from = from
	if room:
		room.held = id if from < 0 else ""
	_rebuild()


func drop() -> void:
	held = ""
	held_from = -1
	if room:
		room.held = ""
	_rebuild()


## What a click on a spot does: put down what's in hand, or pick up what stands there.
func click_spot(spot: int) -> void:
	if not Decor.spot_open(spot):
		return
	if held != "":
		var ok := Decor.move(held_from, spot) if held_from >= 0 else Decor.place(held, spot)
		if ok or held_from == spot:
			Sfx.play(self, Sfx.click(), -10.0)
		drop()
	elif Decor.piece_on(spot) != "":
		hold(Decor.piece_on(spot), spot)


func buy(id: String) -> void:
	if Decor.buy(id):
		Sfx.play(self, Sfx.click(), -10.0)
		hold(id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var cancel: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	cancel = cancel or event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if not cancel:
		return
	get_viewport().set_input_as_handled()
	if held != "":
		drop()
	elif event is InputEventKey:
		close()


# ---------------------------------------------------------------- the floor

## An invisible button over each open spot, so the mouse and the pad's d-pad both reach it.
func _build_spots() -> void:
	if _spots:
		_spots.queue_free()
	_spot_buttons.clear()
	_spots = Control.new()
	_spots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# under the panel, over the shop floor
	get_parent().add_child(_spots)
	get_parent().move_child(_spots, get_index())
	var empty := StyleBoxEmpty.new()
	for n in Decor.spot_count():
		var b := Button.new()
		var r: Rect2 = room.spot_rect(n)
		b.position = r.position + room.position
		b.size = r.size
		b.focus_mode = Control.FOCUS_NONE
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(style, empty)
		b.pressed.connect(click_spot.bind(n))
		_spots.add_child(b)
		_spot_buttons.append(b)


func _process(_delta: float) -> void:
	if not visible or room == null:
		return
	# the pad's pointer counts too
	var at := Pad.mouse_in(self) + position
	var hover := -1
	for n in _spot_buttons.size():
		if _spot_buttons[n].get_global_rect().has_point(at):
			hover = n
	room.hover_spot = hover


func _spot_tip(n: int) -> String:
	var id := Decor.piece_on(n)
	if held != "":
		return tr("Put the %s here.") % tr(Decor.CATALOG[held].name) if id == "" or held_from == n \
			else tr("Swap it with the %s.") % tr(Decor.CATALOG[id].name)
	return tr("Pick up the %s.") % tr(Decor.CATALOG[id].name) if id != "" else tr("An empty spot.")


# ---------------------------------------------------------------- the panel

func _rebuild() -> void:
	if not visible:
		return
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var title := _label("Decorate", Pal.GOLD)
	title.add_theme_font_size_override("font_size", 16)
	_label(Decor.summary(), Pal.INK)
	var used := Decor.placed.size()
	_label(tr("%d of %d spots used") % [used, Decor.spot_count()], Pal.INK_DIM)
	for n in _spot_buttons.size():
		_spot_buttons[n].tooltip_text = _spot_tip(n)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 1)
	scroll.add_child(grid)
	# the storeroom first: what's already paid for
	var counted := {}
	for id in Decor.stored:
		counted[id] = int(counted.get(id, 0)) + 1
	for id in counted:
		var name := tr(Decor.CATALOG[id].name) + ("" if counted[id] == 1 else " ×%d" % counted[id])
		_row(grid, name, Pal.GOOD, "Sell", Decor.sell.bind(id), "Button", "Place", hold.bind(id),
			tr("In your storeroom. Sells back for %s.") % Market.format_money(Decor.resale(id)) + " " + _desc(id))
	for id in Decor.for_sale():
		var u: Dictionary = Decor.CATALOG[id]
		_row(grid, tr(u.name), Pal.INK, Market.format_money(u.cost), Callable(), "", "Buy", buy.bind(id), _desc(id), Decor.can_buy(id))
	var locked := Decor.locked_count()
	if locked > 0:
		_label(tr_n("%d more piece in bigger shops.", "%d more pieces in bigger shops.", locked) % locked, Pal.INK_FAINT)
	_hint = _label(_hand_text(), Pal.WARN if held != "" else Pal.INK_DIM)
	# a fixed three lines, so a long description on hover can't push the buttons off
	_hint.custom_minimum_size.y = 26
	_hint.max_lines_visible = 3
	_hint.clip_text = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_box.add_child(row)
	if held != "" and held_from >= 0:
		_button(row, "Put away", "Button", func():
			Decor.pick_up(held_from)
			drop())
	elif held != "":
		_button(row, "Cancel", "Button", drop)
	var done := _button(row, "Done", "PrimaryButton", func(): close())
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _hand_text() -> String:
	if held != "" and held_from >= 0:
		return tr("Moving the %s: click a spot, or put it away.") % tr(Decor.CATALOG[held].name)
	if held != "":
		return tr("Placing the %s: click a gold spot on the floor.") % tr(Decor.CATALOG[held].name)
	if Decor.placed.is_empty():
		return tr("Buy a piece, then click a gold spot on the floor to place it.")
	return tr("Click a piece on the floor to move it.")


## "+5 appeal. A leafy fern in a terracotta pot."
func _desc(id: String) -> String:
	var u: Dictionary = Decor.CATALOG[id]
	return tr("+%d appeal (%s). %s") % [int(u.appeal), Decor.kind_name(id), tr(u.desc)]


## A catalogue line: the name, then a small action (sell) or the price, then the main button.
func _row(grid: GridContainer, title: String, col: Color, middle: String, on_middle: Callable, middle_style: String,
		verb: String, on_press: Callable, desc: String, enabled := true) -> void:
	var hover := func():
		if _hint and held == "":
			_hint.text = desc
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_color_override("font_color", col)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(36, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.tooltip_text = desc
	grid.add_child(name_label)
	if on_middle.is_valid():
		var sell := Button.new()
		sell.text = middle
		sell.focus_mode = Control.FOCUS_NONE
		sell.theme_type_variation = middle_style
		sell.custom_minimum_size = Vector2(0, 11)
		sell.disabled = Day.phase != Day.MORNING
		sell.pressed.connect(on_middle)
		sell.mouse_entered.connect(hover)
		sell.tooltip_text = desc
		grid.add_child(sell)
	else:
		var price := Label.new()
		price.text = middle
		price.add_theme_color_override("font_color", Pal.INK_DIM)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(price)
	var b := Button.new()
	b.text = verb
	b.custom_minimum_size = Vector2(26, 11)
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "PrimaryButton" if enabled else "Button"
	b.disabled = not enabled
	b.tooltip_text = desc
	b.pressed.connect(on_press)
	grid.add_child(b)
	b.mouse_entered.connect(hover)
	name_label.mouse_entered.connect(hover)


func _label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(RECT.size.x - 16, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(l)
	return l


func _button(parent: Control, text: String, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
