class_name UiTheme
extends RefCounted
## The shared UI theme: pixel font, flat 1 px bordered panels and buttons.
## Buttons can use the variations "PrimaryButton", "DangerButton" and "ToolButton".
## "BigButton" is the menu button: taller, and it shows keyboard focus.

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func box(bg: Color, border: Color, margin_x := 3, margin_y := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.anti_aliasing = false
	s.content_margin_left = margin_x
	s.content_margin_right = margin_x
	s.content_margin_top = margin_y
	s.content_margin_bottom = margin_y
	return s


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = PixelFont.get_font()
	t.default_font_size = PixelFont.SIZE

	t.set_color("font_color", "Label", Pal.INK)
	t.set_constant("line_spacing", "Label", 1)
	t.set_stylebox("panel", "Panel", box(Pal.PANEL, Pal.PANEL_EDGE))
	t.set_stylebox("panel", "PanelContainer", box(Pal.PANEL, Pal.PANEL_EDGE, 4, 3))

	_button(t, "Button", Pal.PANEL_HI, Pal.PANEL_EDGE, Pal.INK)
	_button(t, "PrimaryButton", Color("#5a4214"), Pal.GOLD, Color("#fff2be"))
	_button(t, "DangerButton", Color("#4a1e1a"), Color("#a8483c"), Color("#ffd8d0"))
	_button(t, "ToolButton", Color("#1f2a24"), Color("#3d5a48"), Pal.INK)
	_button(t, "BigButton", Color("#2b221a"), Pal.PANEL_EDGE, Pal.INK)
	for v in ["PrimaryButton", "DangerButton", "ToolButton", "BigButton"]:
		t.set_type_variation(v, "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var b: StyleBoxFlat = t.get_stylebox(state, "BigButton").duplicate()
		b.content_margin_top = 3
		b.content_margin_bottom = 3
		t.set_stylebox(state, "BigButton", b)
	t.set_stylebox("focus", "BigButton", box(Color(0, 0, 0, 0), Pal.GOLD, 0, 0))

	t.set_stylebox("slider", "HSlider", box(Color("#120e0a"), Pal.PANEL_EDGE, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(Pal.GOLD.darkened(0.3), Pal.GOLD.darkened(0.3), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Pal.GOLD.darkened(0.15), Pal.GOLD.darkened(0.15), 0, 2))
	t.set_icon("grabber", "HSlider", _grabber_icon(Pal.INK))
	t.set_icon("grabber_highlight", "HSlider", _grabber_icon(Pal.GOLD))
	t.set_icon("grabber_disabled", "HSlider", _grabber_icon(Pal.INK_FAINT))
	t.set_icon("tick", "HSlider", PixelCanvas.new(1, 1).texture())

	t.set_stylebox("normal", "OptionButton", box(Pal.PANEL_HI, Pal.PANEL_EDGE, 3, 1))
	t.set_stylebox("hover", "OptionButton", box(Color("#3a2e22"), Pal.GOLD, 3, 1))
	t.set_stylebox("pressed", "OptionButton", box(Pal.PANEL, Pal.GOLD, 3, 1))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_constant("arrow_margin", "OptionButton", 2)
	t.set_icon("arrow", "OptionButton", _arrow_icon())
	t.set_stylebox("panel", "PopupMenu", box(Pal.PANEL, Pal.GOLD, 2, 2))
	t.set_stylebox("hover", "PopupMenu", box(Color("#3a2e22"), Color("#3a2e22"), 2, 0))
	t.set_color("font_color", "PopupMenu", Pal.INK)
	t.set_color("font_hover_color", "PopupMenu", Pal.GOLD)
	t.set_constant("v_separation", "PopupMenu", 2)

	t.set_stylebox("background", "ProgressBar", box(Color("#120e0a"), Pal.PANEL_EDGE, 0, 0))
	var fill := box(Pal.GOLD.darkened(0.15), Pal.GOLD, 0, 0)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	return t


static func _button(t: Theme, type: String, bg: Color, edge: Color, ink: Color) -> void:
	t.set_stylebox("normal", type, box(bg, edge))
	t.set_stylebox("hover", type, box(bg.lightened(0.12), Pal.GOLD))
	t.set_stylebox("pressed", type, box(bg.darkened(0.25), Pal.GOLD))
	t.set_stylebox("disabled", type, box(bg.darkened(0.3), edge.darkened(0.4)))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, ink)
	t.set_color("font_hover_color", type, ink.lightened(0.2))
	t.set_color("font_pressed_color", type, Pal.GOLD)
	t.set_color("font_disabled_color", type, Pal.INK_FAINT)


static func _arrow_icon() -> ImageTexture:
	var c := PixelCanvas.new(5, 3)
	c.rect(0, 0, 5, 1, Pal.INK_DIM)
	c.rect(1, 1, 3, 1, Pal.INK_DIM)
	c.px(2, 2, Pal.INK_DIM)
	return c.texture()


static func _grabber_icon(col: Color) -> ImageTexture:
	var c := PixelCanvas.new(5, 9)
	c.rect(0, 0, 5, 9, Pal.PANEL_EDGE.darkened(0.4))
	c.rect(1, 1, 3, 7, col)
	c.rect(2, 2, 1, 5, col.darkened(0.25))
	return c.texture()
