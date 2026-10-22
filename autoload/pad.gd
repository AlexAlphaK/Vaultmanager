extends Node
## Gamepad controls (Xbox, PlayStation, Switch Pro and the Steam Deck's built-in pad).
## The whole game is mouse and keyboard underneath, so the pad drives a pointer:
##   left stick    move the pointer (push further to go faster)
##   right stick   scroll lists
##   d-pad         jump the pointer to the next button that way (adjusts a slider under it)
##   A             left click, hold to drag
##   B             back (Esc)
##   X             right click (turns a vault piece)
##   Y             confirm (Enter: lock up the vault, finish an appraisal)
##   LB / RB, LT / RT   scene shortcuts (tools on the benches, rows and trades on the desk)
##   Start         pause menu
##   View / Select show the controls
## A scene adds shortcuts by joining the "pad_hooks" group and having pad_action(name) -> bool
## for "lb", "rb", "lt" and "rt", and pad_help() -> Array of [button, what it does].
## Nodes in the "pad_targets" group can give pad_targets() -> Array[Rect2] (canvas coordinates)
## of drawn things the d-pad should also stop at, like the rows of the trading desk.
## Scenes that read the mouse every frame use Pad.mouse_in(self) so the pad's pointer counts too,
## and Pad.hide_cursor() instead of setting Input.mouse_mode.

signal mode_changed(using_pad: bool)

const VIEW := Vector2(480, 270)
## Marks the mouse and key events this script makes, so it can tell them from real ones.
const DEVICE := 917
const DEADZONE := 0.2
## Pointer speed at full tilt, in game pixels per second.
const SPEED := 240.0
const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.11
const SCROLL_EVERY := 0.07
const TRIGGER_DOWN := 0.6

## True while the last thing the player touched was a gamepad.
var using_pad := false
## The pad's pointer in game pixels (0-480, 0-270).
var cursor := VIEW / 2.0

var _game_hides := false
var _held := {} # JoyButton or "lt"/"rt" -> true while down
var _repeat_dir := Vector2.ZERO
var _repeat_t := 0.0
var _scroll_t := 0.0
var _left_down := false
var _layer: CanvasLayer
var _pointer: TextureRect
var _tex_up: Texture2D
var _tex_down: Texture2D
var _help: PanelContainer
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_strip_joypad_ui_events()
	_build_overlay()
	Input.joy_connection_changed.connect(_on_joy_connection)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Godot's built-in ui_* actions also listen to the pad; this script handles the pad itself,
## so the stick moves the pointer and not the keyboard focus as well.
func _strip_joypad_ui_events() -> void:
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event.device == DEVICE:
		return
	if event is InputEventJoypadButton:
		_set_mode(true)
		_on_button(event.button_index, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > DEADZONE:
			_set_mode(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# warping the system pointer comes back as a motion event at the same spot; ignore it
		# (by now the event is in game pixels)
		if using_pad and event.position.distance_to(cursor) > 2.0:
			_set_mode(false)
	elif event is InputEventMouseButton or event is InputEventScreenTouch:
		_set_mode(false)


func _on_button(button: int, pressed: bool) -> void:
	_held[button] = pressed
	if button == JOY_BUTTON_A:
		if _popup_open():
			if pressed:
				_tap_key(KEY_ENTER)
		else:
			_mouse_button(MOUSE_BUTTON_LEFT, pressed)
		return
	if not pressed:
		if _dpad_dir(button) != Vector2.ZERO:
			_repeat_dir = Vector2.ZERO
		return
	if _help.visible and button != JOY_BUTTON_BACK:
		_help.visible = false
		if button == JOY_BUTTON_B or button == JOY_BUTTON_START:
			return
	var dir := _dpad_dir(button)
	if dir != Vector2.ZERO:
		_repeat_dir = dir
		_repeat_t = REPEAT_DELAY
		step(dir)
		return
	match button:
		JOY_BUTTON_B:
			_tap_key(KEY_ESCAPE)
		JOY_BUTTON_X:
			_mouse_button(MOUSE_BUTTON_RIGHT, true)
			_mouse_button(MOUSE_BUTTON_RIGHT, false)
		JOY_BUTTON_Y:
			_tap_key(KEY_ENTER)
		JOY_BUTTON_LEFT_SHOULDER:
			action("lb")
		JOY_BUTTON_RIGHT_SHOULDER:
			action("rb")
		JOY_BUTTON_START:
			# the benches and the desk have no pause menu; there Start does nothing
			if _hook() == null:
				_tap_key(KEY_ESCAPE)
		JOY_BUTTON_BACK:
			toggle_help()


## Passes a shortcut ("lb", "rb", "lt", "rt") to the scene in front. Returns true if it used it.
func action(name: String) -> bool:
	var hook := _hook()
	return hook != null and hook.pad_action(name)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.visible = _toast_t > 0.0
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	var move := Vector2.ZERO
	var scroll := 0.0
	for id in pads:
		move += _stick(id, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		scroll += _stick(id, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).y
		for t in [["lt", JOY_AXIS_TRIGGER_LEFT], ["rt", JOY_AXIS_TRIGGER_RIGHT]]:
			var down := Input.get_joy_axis(id, t[1]) > TRIGGER_DOWN
			if down and not _held.get(t[0], false):
				_set_mode(true)
				action(t[0])
			_held[t[0]] = down
	if move != Vector2.ZERO:
		move_cursor(move.limit_length(1.0) * SPEED * delta)
	if scroll != 0.0:
		_scroll_t -= delta
		if _scroll_t <= 0.0:
			_scroll_t = SCROLL_EVERY / clampf(absf(scroll), 0.3, 1.0)
			_wheel(MOUSE_BUTTON_WHEEL_DOWN if scroll > 0.0 else MOUSE_BUTTON_WHEEL_UP)
	else:
		_scroll_t = 0.0
	if _repeat_dir != Vector2.ZERO:
		_repeat_t -= delta
		if _repeat_t <= 0.0:
			_repeat_t = REPEAT_EVERY
			step(_repeat_dir)


## Stick deflection past the dead zone, eased so small pushes give fine control.
func _stick(id: int, ax: int, ay: int) -> Vector2:
	var v := Vector2(Input.get_joy_axis(id, ax), Input.get_joy_axis(id, ay))
	var m := v.length()
	if m <= DEADZONE:
		return Vector2.ZERO
	_set_mode(true)
	var eased := pow(minf((m - DEADZONE) / (1.0 - DEADZONE), 1.0), 1.7)
	return v / m * eased


func _dpad_dir(button: int) -> Vector2:
	match button:
		JOY_BUTTON_DPAD_UP:
			return Vector2.UP
		JOY_BUTTON_DPAD_DOWN:
			return Vector2.DOWN
		JOY_BUTTON_DPAD_LEFT:
			return Vector2.LEFT
		JOY_BUTTON_DPAD_RIGHT:
			return Vector2.RIGHT
	return Vector2.ZERO


# ---------------------------------------------------------------- pointer

func move_cursor(by: Vector2) -> void:
	set_cursor(cursor + by)


## Puts the pointer at a spot in game pixels and tells the game the mouse moved there.
func set_cursor(at: Vector2) -> void:
	at = at.clamp(Vector2.ZERO, VIEW - Vector2.ONE)
	if at == cursor:
		return
	var rel := at - cursor
	cursor = at
	_update_pointer()
	var e := InputEventMouseMotion.new()
	e.device = DEVICE
	e.position = _to_window(cursor)
	e.global_position = e.position
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _left_down else 0
	Input.parse_input_event(e)
	if DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(cursor)


## Where the mouse is in a CanvasItem's own coordinates, counting the pad's pointer.
func mouse_in(item: CanvasItem) -> Vector2:
	if not using_pad:
		return item.get_local_mouse_position()
	return item.get_global_transform_with_canvas().affine_inverse() * cursor


## The benches hide the pointer while the loupe is out (the loupe follows it instead).
func hide_cursor(hidden: bool) -> void:
	_game_hides = hidden
	_apply_mouse_mode()


func _mouse_button(index: int, pressed: bool) -> void:
	if index == MOUSE_BUTTON_LEFT:
		if pressed == _left_down:
			return
		_left_down = pressed
		_update_pointer()
	var e := InputEventMouseButton.new()
	e.device = DEVICE
	e.button_index = index
	e.pressed = pressed
	e.position = _to_window(cursor)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _left_down else 0
	Input.parse_input_event(e)


func _wheel(index: int) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.device = DEVICE
		e.button_index = index
		e.pressed = pressed
		e.factor = 1.0
		e.position = _to_window(cursor)
		e.global_position = e.position
		Input.parse_input_event(e)


func _tap_key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.device = DEVICE
		e.keycode = key
		e.physical_keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)


func _to_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _set_mode(pad: bool) -> void:
	if pad == using_pad:
		return
	using_pad = pad
	if pad:
		var m := get_viewport().get_mouse_position()
		if DisplayServer.get_name() != "headless" and Rect2(Vector2.ZERO, VIEW).has_point(m):
			cursor = m
	elif _left_down:
		_mouse_button(MOUSE_BUTTON_LEFT, false)
	_apply_mouse_mode()
	_update_pointer()
	mode_changed.emit(pad)


func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if using_pad or _game_hides else Input.MOUSE_MODE_VISIBLE


func _update_pointer() -> void:
	_pointer.visible = using_pad and not _game_hides
	_pointer.texture = _tex_down if _left_down else _tex_up
	_pointer.position = cursor.round() - Vector2(1, 1)


## When a menu puts the focus on a button (the title screen, the pause menu), the pointer
## goes there too, unless it is already on it.
func _on_focus_changed(c: Control) -> void:
	if using_pad and c is BaseButton and c.is_visible_in_tree() and not c.get_global_rect().has_point(cursor):
		set_cursor(c.get_global_rect().get_center())


# ---------------------------------------------------------------- d-pad jumps

## Moves the pointer to the nearest button (or pad target) in a direction. On a slider,
## left and right move the slider instead. Returns what it landed on, or null.
func step(dir: Vector2) -> Variant:
	if _popup_open():
		_tap_key({Vector2.UP: KEY_UP, Vector2.DOWN: KEY_DOWN, Vector2.LEFT: KEY_LEFT, Vector2.RIGHT: KEY_RIGHT}[dir])
		return null
	var targets := targets()
	for t in targets:
		if t.node is Slider and dir.y == 0.0 and t.rect.grow(2).has_point(cursor):
			var r: Slider = t.node
			r.value += maxf(r.step, (r.max_value - r.min_value) * 0.05) * dir.x
			return r
	var from := cursor
	var best = null
	var best_score := INF
	for t in targets:
		if t.rect.has_point(cursor):
			from = t.rect.get_center()
			break
	for t in targets:
		var v: Vector2 = t.rect.get_center() - from
		var along := v.dot(dir)
		if along < 3.0 or t.rect.has_point(cursor):
			continue
		var score := along + absf(v.cross(dir)) * 2.5
		if score < best_score:
			best_score = score
			best = t
	if best == null:
		return null
	var scroll: ScrollContainer = best.get("scroll")
	if scroll and best.node is Control:
		_jump_into_list(best.node, scroll)
	else:
		set_cursor(best.rect.get_center())
	if best.node is Control and best.node.focus_mode != Control.FOCUS_NONE:
		best.node.grab_focus()
	return best.node


## Scrolls a list until the button shows, then puts the pointer on it.
func _jump_into_list(c: Control, scroll: ScrollContainer) -> void:
	scroll.ensure_control_visible(c)
	await get_tree().process_frame
	if is_instance_valid(c) and c.is_visible_in_tree():
		set_cursor(c.get_global_rect().intersection(scroll.get_global_rect()).get_center())


## Everything the d-pad can stop at: buttons, sliders and drawn targets that a click at their
## centre would really reach (not hidden behind a menu or panel in front of them).
## Each is {"node", "rect"} and, for buttons in a scrolling list, "scroll".
func targets() -> Array[Dictionary]:
	var controls: Array[Dictionary] = []
	var order := [0]
	for child in get_tree().root.get_children():
		if child != self:
			_collect(child, 0, Rect2(Vector2.ZERO, VIEW), null, controls, order)
	var out: Array[Dictionary] = []
	for c in controls:
		var n: Control = c.node
		var wanted: bool = (n is BaseButton and not n.disabled) or (n is Slider and n.editable)
		if wanted:
			var at: Rect2 = c.clip.intersection(c.rect)
			if c.scroll and not at.has_area():
				# scrolled out of sight: reachable if the list itself is
				var sr: Rect2 = c.scroll.get_global_rect()
				if _hit(controls, sr.get_center().clamp(sr.position, sr.end - Vector2.ONE), c.scroll):
					out.append({"node": n, "rect": c.rect, "scroll": c.scroll})
			elif at.has_area() and _hit(controls, at.get_center(), n):
				out.append({"node": n, "rect": c.rect, "scroll": c.scroll})
	for node in get_tree().get_nodes_in_group("pad_targets"):
		if node is CanvasItem and not node.is_visible_in_tree():
			continue
		for r in node.pad_targets():
			if _hit(controls, r.get_center(), node):
				out.append({"node": node, "rect": r})
	return out


func _collect(node: Node, layer: int, clip: Rect2, scroll: ScrollContainer, out: Array[Dictionary], order: Array) -> void:
	if node is Window:
		return
	if node is CanvasLayer:
		if not node.visible:
			return
		layer = node.layer
	elif node is CanvasItem and not node.visible:
		return
	if node is Control:
		var r: Rect2 = node.get_global_rect()
		order[0] += 1
		out.append({"node": node, "rect": r, "clip": clip, "key": layer * 1000000 + order[0], "scroll": scroll})
		if node.clip_contents:
			clip = clip.intersection(r)
		if node is ScrollContainer:
			scroll = node
	for child in node.get_children():
		_collect(child, layer, clip, scroll, out, order)


## True if a click at a point would land on `owner` or something inside it, like the GUI's
## own picking: the front-most control under the point that does not ignore the mouse.
func _hit(controls: Array[Dictionary], at: Vector2, owner: Node) -> bool:
	var front = null
	var front_key := -INF
	for c in controls:
		var n: Control = c.node
		if n.mouse_filter == Control.MOUSE_FILTER_IGNORE or c.key <= front_key:
			continue
		if c.rect.has_point(at) and c.clip.has_point(at):
			front = n
			front_key = c.key
	if front == null:
		return not (owner is Control)
	return front == owner or owner.is_ancestor_of(front)


func _hook() -> Node:
	var found: Node = null
	for node in get_tree().get_nodes_in_group("pad_hooks"):
		if node.can_process() and (not node is CanvasItem or node.is_visible_in_tree()):
			found = node
	return found


func _popup_open() -> bool:
	for w in get_tree().root.get_embedded_subwindows():
		if w is Popup and w.visible:
			return true
	return false


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	_tex_up = _arrow(false)
	_tex_down = _arrow(true)
	_pointer = TextureRect.new()
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.texture = _tex_up
	_pointer.visible = false
	_layer.add_child(_pointer)

	_toast = Label.new()
	_toast.theme = UiTheme.get_theme()
	_toast.add_theme_color_override("font_color", Pal.INK)
	_toast.add_theme_stylebox_override("normal", UiTheme.box(Pal.PANEL, Pal.GOLD, 4, 2))
	_toast.position = Vector2(6, 252)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_layer.add_child(_toast)

	_help = PanelContainer.new()
	_help.theme = UiTheme.get_theme()
	_help.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.GOLD, 8, 6))
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.visible = false
	_layer.add_child(_help)


## A small pixel arrow; pressed, it is gold.
func _arrow(down: bool) -> Texture2D:
	const SHAPE := [
		"X.........",
		"XX........",
		"XoX.......",
		"XooX......",
		"XoooX.....",
		"XooooX....",
		"XoooooX...",
		"XooooooX..",
		"XoooXXXXX.",
		"XoXooX....",
		"XX.XooX...",
		"X..XooX...",
		"....XX....",
	]
	var c := PixelCanvas.new(10, 13)
	var fill := Pal.GOLD if down else Pal.INK
	for y in SHAPE.size():
		for x in SHAPE[y].length():
			match SHAPE[y][x]:
				"X":
					c.px(x, y, Color("#120e0a"))
				"o":
					c.px(x, y, fill)
	return c.texture()


func toggle_help() -> void:
	if _help.visible:
		_help.visible = false
		return
	for child in _help.get_children():
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	_help.add_child(grid)
	var rows := help_rows()
	for row in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_color_override("font_color", Pal.GOLD)
		grid.add_child(key)
		var what := Label.new()
		what.text = row[1]
		grid.add_child(what)
	_help.visible = true
	_center_help.call_deferred()


func _center_help() -> void:
	_help.reset_size()
	_help.position = ((VIEW - _help.size) / 2.0).round()


## The controls list: the scene's own shortcuts first, then the ones that work everywhere.
func help_rows() -> Array:
	var rows := [["Controller", ""]]
	var hook := _hook()
	if hook and hook.has_method("pad_help"):
		rows.append_array(hook.pad_help())
	rows.append_array([
		["Left stick", "Move the pointer"],
		["D-pad", "Jump to the next button"],
		["A", "Click (hold to drag)"],
		["B", "Back"],
		["X", "Right click"],
		["Y", "Confirm"],
		["Right stick", "Scroll"],
		["Start", "Pause"],
		["View", "Show or hide this"],
	])
	return rows


func show_toast(text: String, seconds := 3.0) -> void:
	_toast.text = text
	_toast.reset_size()
	_toast_t = seconds
	_toast.visible = true


func _on_joy_connection(_id: int, connected: bool) -> void:
	if connected:
		show_toast("Controller connected. Press View for the controls.")
