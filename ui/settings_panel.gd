class_name SettingsPanel
extends PanelContainer
## The settings page, shared by the title screen and the pause menu: language, display currency,
## volume for everything, music and effects, fullscreen and scaling. Changes apply and save at once.

signal closed

const SIZE := Vector2(232, 150)
const SLIDERS := [["Master", "Volume"], ["Music", "Music"], ["SFX", "Effects"]]

var _percent := {}
var _language: OptionButton
var _fullscreen: Button
var _scaling: Button
var _last_blip := 0


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = SIZE
	position = ((Vector2(480, 270) - SIZE) / 2.0).round()
	add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 8, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Pal.GOLD)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)

	_caption(grid, "Language")
	_language = OptionButton.new()
	_language.custom_minimum_size = Vector2(96, 11)
	_language.fit_to_longest_item = false
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # names are in their own language
	_language.item_selected.connect(func(n): Settings.set_language(Settings.LANGUAGES[n]))
	grid.add_child(_language)
	grid.add_child(Control.new())

	_caption(grid, "Currency")
	var currency := OptionButton.new()
	currency.custom_minimum_size = Vector2(96, 11)
	currency.fit_to_longest_item = false
	var codes := Market.CURRENCY_SYMBOLS.keys()
	for n in codes.size():
		currency.add_item("%s  %s" % [codes[n], Market.CURRENCY_SYMBOLS[codes[n]].strip_edges()], n)
		if codes[n] == Market.currency:
			currency.select(n)
	currency.item_selected.connect(func(n): Market.set_currency(codes[n]))
	grid.add_child(currency)
	grid.add_child(Control.new())

	for row in SLIDERS:
		var bus: String = row[0]
		_caption(grid, row[1])
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(120, 9)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Settings.volume[bus]
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_volume.bind(bus))
		grid.add_child(slider)
		_percent[bus] = _caption(grid, "", Pal.INK)
		_percent[bus].custom_minimum_size = Vector2(22, 0)
		_percent[bus].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_caption(grid, "Fullscreen")
	_fullscreen = Button.new()
	_fullscreen.toggle_mode = true
	_fullscreen.custom_minimum_size = Vector2(36, 11)
	_fullscreen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_fullscreen.button_pressed = Settings.fullscreen
	_fullscreen.toggled.connect(func(on): Settings.set_fullscreen(on))
	grid.add_child(_fullscreen)
	_caption(grid, "F11", Pal.INK_FAINT)

	_caption(grid, "Scaling")
	_scaling = Button.new()
	_scaling.custom_minimum_size = Vector2(72, 11)
	_scaling.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_scaling.pressed.connect(func():
		var next: int = (Settings.SCALINGS.find(Settings.scaling) + 1) % Settings.SCALINGS.size()
		Settings.set_scaling(Settings.SCALINGS[next]))
	grid.add_child(_scaling)
	grid.add_child(Control.new())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = "PrimaryButton"
	back.custom_minimum_size = Vector2(60, 12)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(close)
	box.add_child(back)

	Settings.changed.connect(_refresh)
	_refresh()
	back.grab_focus.call_deferred()


func close() -> void:
	Sfx.play(self, Sfx.click(), -10.0)
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_language.clear()
	for code in Settings.LANGUAGES:
		var device: String = Settings.LANGUAGE_NAMES[Settings.device_language()]
		_language.add_item(tr("Auto (%s)") % device if code == "auto" else Settings.LANGUAGE_NAMES[code])
	_language.select(Settings.LANGUAGES.find(Settings.language))
	for bus in _percent:
		_percent[bus].text = "%d%%" % roundi(Settings.volume[bus] * 100.0)
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_fullscreen.text = "On" if Settings.fullscreen else "Off"
	_scaling.text = Settings.SCALING_NAMES[Settings.scaling]


func _on_volume(value: float, bus: String) -> void:
	Settings.set_volume(bus, value)
	# a short blip so the player hears the new effects level, at most a few per second
	if bus != "Music" and Time.get_ticks_msec() - _last_blip > 120:
		_last_blip = Time.get_ticks_msec()
		Sfx.play(self, Sfx.scale_beep(), -10.0)


func _caption(parent: Node, text: String, col := Pal.INK_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(l)
	return l
