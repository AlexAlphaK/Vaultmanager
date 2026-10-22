class_name PauseMenu
extends CanvasLayer
## The pause menu over the shop: Resume, Settings, Quit to title and Quit game.
## Opening it pauses the whole tree; music keeps playing. Esc opens and closes it.

signal resumed

const TitleScene := "res://scenes/menu/title_screen.tscn"
const SIZE := Vector2(150, 132)

var _root: Control
var _panel: PanelContainer
var _day: Label
var _note: Label
var _resume: Button
var _settings: SettingsPanel


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.size = SIZE
	_panel.position = ((Vector2(480, 270) - SIZE) / 2.0).round()
	_panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 10, 6))
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Pal.GOLD)
	box.add_child(title)
	_day = Label.new()
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day.add_theme_color_override("font_color", Pal.INK_DIM)
	box.add_child(_day)
	_resume = _button(box, "Resume", close)
	_button(box, "Settings", _open_settings)
	_button(box, "Quit to title", _quit_to_title)
	if not OS.has_feature("web"):
		_button(box, "Quit game", func(): get_tree().quit())
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_color", Pal.INK_FAINT)
	box.add_child(_note)
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_day.text = "%s, day %d" % [Day.weekday(), Shop.day]
	_note.text = "Slot %d · saved morning and night" % SaveGame.slot
	visible = true
	_panel.visible = true
	get_tree().paused = true
	Sfx.play(self, Sfx.click(), -8.0)
	_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	if _settings:
		_close_settings()
	visible = false
	get_tree().paused = false
	resumed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(0, 15)
	b.pressed.connect(func():
		Sfx.play(self, Sfx.click(), -8.0)
		on_press.call())
	b.mouse_entered.connect(b.grab_focus)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_panel.visible = false
	_settings = SettingsPanel.new()
	_root.add_child(_settings)
	_settings.closed.connect(_close_settings)


func _close_settings() -> void:
	_settings.queue_free()
	_settings = null
	_panel.visible = true
	_resume.grab_focus()


## Today is replayed from this morning's save, like quitting the game.
func _quit_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TitleScene)
