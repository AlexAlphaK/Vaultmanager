class_name SaveSlotsPanel
extends PanelContainer
## The save slots page on the title screen: one row per slot with its day, shop, cash
## and when it was saved. Play opens a slot, New starts a shop in an empty one, and
## Delete (pressed twice) clears a slot.

signal chosen(slot: int, fresh: bool)
signal closed

const SIZE := Vector2(268, 146)

var _rows: VBoxContainer
var _hint: Label
var _back: Button
var _confirm_delete := 0
var _hint_text := ""


## `hint` replaces the line under the title, e.g. to say every slot is full.
func _init(hint := "") -> void:
	_hint_text = hint


func _ready() -> void:
	theme = UiTheme.get_theme()
	size = SIZE
	position = ((Vector2(480, 270) - SIZE) / 2.0).round()
	add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 8, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var title := Label.new()
	title.text = "Save slots"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Pal.GOLD)
	box.add_child(title)
	_hint = Label.new()
	_hint.text = _hint_text if _hint_text != "" else tr("Each slot saves every morning and every night.")
	_hint.add_theme_color_override("font_color", Pal.INK_DIM if _hint_text == "" else Pal.WARN)
	box.add_child(_hint)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	box.add_child(_rows)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_back = Button.new()
	_back.text = "Back"
	_back.theme_type_variation = "PrimaryButton"
	_back.custom_minimum_size = Vector2(60, 12)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_back.pressed.connect(close)
	box.add_child(_back)
	_refresh()
	_back.grab_focus.call_deferred()


func close() -> void:
	Sfx.play(self, Sfx.click(), -10.0)
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for n in range(1, SaveGame.SLOTS + 1):
		_rows.add_child(_slot_row(n))


func _slot_row(n: int) -> Control:
	var info := SaveGame.peek(n)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiTheme.box(Color("#2b221a"), Pal.PANEL_EDGE, 4, 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	row.add_child(h)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	var top := Label.new()
	var bottom := Label.new()
	bottom.add_theme_color_override("font_color", Pal.INK_DIM)
	text.add_child(top)
	text.add_child(bottom)
	if info.is_empty():
		top.text = tr("Slot %d · empty") % n
		top.add_theme_color_override("font_color", Pal.INK_DIM)
		bottom.text = "Start a new shop here"
		_row_button(h, "New", "PrimaryButton", func(): chosen.emit(n, true))
	else:
		top.text = tr("Slot %d · Day %d · %s") % [n, info.day + (1 if info.day_over else 0),
			Progress.tier_name(clampi(info.tier, 0, Progress.TIERS.size() - 1))]
		bottom.text = tr("%s · saved %s") % [Market.format_money(info.cash), SaveGame.format_time(info.saved_unix)]
		_row_button(h, "Play", "PrimaryButton", func(): chosen.emit(n, false))
		_row_button(h, "Sure?" if _confirm_delete == n else "Delete", "DangerButton", func(): _on_delete(n))
	return row


func _row_button(parent: Node, text: String, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(34, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Sfx.play(self, Sfx.click(), -8.0)
		on_press.call())
	parent.add_child(b)
	return b


func _on_delete(n: int) -> void:
	if _confirm_delete != n:
		_confirm_delete = n
		_refresh()
		return
	_confirm_delete = 0
	SaveGame.delete_slot(n)
	_hint.text = tr("Slot %d deleted.") % n
	_hint.add_theme_color_override("font_color", Pal.INK_DIM)
	_refresh()
