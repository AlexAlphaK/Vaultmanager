class_name AuctionRoom
extends Control
## The auction at Ashworth & Finch, opened from the Town map on a sale morning.
##   viewing  look over the lots on the viewing tray before the sale. Click a sealed pouch
##            to look inside (a few looks a sale). Consign your spare rare coins.
##   sale     take your seat. Each lot comes up on the plinth; Space (or Bid) raises your
##            paddle at the asking price, J jumps the bidding a few steps. Watch the
##            bidders in front of you: a wavering paddle and a mopped brow mean they are
##            near their limit. "Going once, going twice", and the gavel comes down.
##   done     what you won, what was in the pouches, and what your lots fetched.
## The rules and the lots are AuctionHouse; one lot's bidding is AuctionSale.
## Run this scene on its own (F6 in the editor) to try a sale.

signal finished

const PANEL_X := 316
## Seconds a lot is shown before the bidding opens, and the result after the hammer.
const INTRO := 1.3
const AFTER := 1.9
const YOUR_PADDLE := 27
## How long a paddle stays up after a bid, and a head shakes "no".
const PADDLE_UP := 0.8
const SHAKE := 0.7
const AMBER := Color("#ffb43a")

var phase := "viewing" # "viewing", "sale" or "done"
## The lot shown on the viewing tray, and the lot under the hammer.
var view_i := 0
var lot_i := 0
var sale: AuctionSale
var seats: Array[Dictionary] = []
## "intro", "bidding" or "after", while phase is "sale".
var stage := ""

var _time := 0.0
var _stage_left := 0.0
var _room: Texture2D
var _chairs: Texture2D
var _tray: Texture2D
var _auctioneer: Array[Texture2D] = []
var _hand: Texture2D
var _big_paddle: Texture2D
var _bidder_tex: Array = [] # per seat: [turned left, straight, turned right]
var _paddle_tex: Array[Texture2D] = []
var _numbers: Array[int] = []
var _bid_at: Array[float] = []
var _out_at: Array[float] = []
var _you_at := -99.0
var _gavel_at := -99.0
var _call := ""
var _call_at := -99.0
var _mini: Texture2D
var _mini_for := {}
var _coins := {}
var _pouches := {}
var _hover := -1
var _ui: Control
var _live := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_hooks")
	add_to_group("pad_targets")
	_rng.randomize()
	_room = AuctionArt.paint().texture()
	_chairs = AuctionArt.chairs().texture()
	_tray = AuctionArt.tray().texture()
	_auctioneer = [AuctionArt.auctioneer(false).texture(), AuctionArt.auctioneer(true).texture()]
	_hand = AuctionArt.hand().texture()
	_big_paddle = AuctionArt.paddle(YOUR_PADDLE, true).texture()
	var panel := Panel.new()
	add_child(panel)
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(480 - PANEL_X, 270)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Pal.PANEL, Pal.PANEL_EDGE))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui = Control.new()
	add_child(_ui)
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_tree().current_scene == self:
		_try_out.call_deferred()


## Opens on the viewing: today's catalogue on the tray.
func start() -> void:
	AuctionHouse.refresh_catalogue()
	seats = AuctionHouse.attendees()
	_bidder_tex.clear()
	_paddle_tex.clear()
	_numbers.clear()
	for i in seats.size():
		var look := AuctionArt.bidder_look(seats[i].who, int(seats[i].look))
		_bidder_tex.append([AuctionArt.bidder(look, -1).texture(), AuctionArt.bidder(look, 0).texture(), AuctionArt.bidder(look, 1).texture()])
		var number := (Shop.day * 7 + i * 17) % 89 + 10
		if number == YOUR_PADDLE:
			number += 1
		_numbers.append(number)
		_paddle_tex.append(AuctionArt.paddle(number).texture())
	_bid_at.resize(seats.size())
	_bid_at.fill(-99.0)
	_out_at.resize(seats.size())
	_out_at.fill(-99.0)
	view_i = 0
	_show_viewing()
	Sfx.play(self, Sfx.click(), -8.0)


func _try_out() -> void:
	AuctionHouse.hook_up()
	Tutorial.skip_all()
	while not AuctionHouse.is_sale_day():
		Shop.day += 1
	AuctionHouse.catalogue_day = 0
	AuctionHouse.held_day = 0
	start()
	finished.connect(func(): get_tree().reload_current_scene())


func _process(delta: float) -> void:
	_time += delta
	if phase == "sale":
		_run(delta)
	_refresh_live()
	queue_redraw()


func _run(delta: float) -> void:
	match stage:
		"intro":
			_stage_left -= delta
			if _stage_left <= 0.0:
				stage = "bidding"
				_say(tr("Start me at %s?") % Market.format_money(sale.ask))
		"bidding":
			var was_done := sale.advance(delta)
			_take_events()
			if was_done:
				_hammer()
		"after":
			_stage_left -= delta
			if _stage_left <= 0.0:
				_next_lot()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			if phase == "sale":
				bid()
		KEY_J:
			if phase == "sale":
				bid(true)
		KEY_ENTER, KEY_KP_ENTER:
			if phase == "viewing":
				take_seat()
			elif phase == "done":
				finished.emit()
		KEY_LEFT, KEY_A:
			if phase == "viewing":
				show_lot(view_i - 1)
		KEY_RIGHT, KEY_D:
			if phase == "viewing":
				show_lot(view_i + 1)
		KEY_ESCAPE:
			back()
		_:
			return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if phase != "viewing":
		return
	var m := Pad.mouse_in(self)
	if event is InputEventMouseMotion:
		_hover = _pouch_under(m)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _pouch_under(m)
		if i >= 0:
			look_inside(i)
			accept_event()


## RB bids, LB jumps the bidding, RT lets the lot go; on the viewing LB and RB turn the pages.
func pad_action(name: String) -> bool:
	if phase == "viewing":
		if name == "lb" or name == "rb":
			show_lot(view_i + (1 if name == "rb" else -1))
			return true
		return false
	if phase != "sale":
		return false
	match name:
		"rb":
			bid()
		"lb":
			bid(true)
		"rt":
			let_go()
		_:
			return false
	return true


func pad_help() -> Array:
	if phase == "viewing":
		return [[tr("LB / RB"), tr("Previous / next lot")], [tr("A on a pouch"), tr("Look inside")]]
	return [["RB", tr("Bid")], ["LB", tr("Jump bid")], ["RT", tr("Let it go")]]


## The sealed pouches on the tray, for the d-pad.
func pad_targets() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if phase != "viewing" or AuctionHouse.views_left <= 0:
		return out
	var xf := get_global_transform_with_canvas()
	var lot := _viewed()
	for i in lot.items.size():
		if lot.items[i].pouch and not lot.items[i].seen:
			out.append(xf * _cell_rect(i, lot.items.size()))
	return out


# ---------------------------------------------------------------- actions

func show_lot(i: int) -> void:
	if AuctionHouse.lots.is_empty():
		return
	view_i = posmod(i, AuctionHouse.lots.size())
	_hover = -1
	Sfx.play(self, Sfx.click(), -12.0)
	_build_viewing()


## Opens sealed pouch `i` of the lot on the tray.
func look_inside(i: int) -> void:
	if AuctionHouse.view(_viewed(), i):
		Sfx.play(self, AuctionSfx.paddle(), -6.0)
		var it: Dictionary = _viewed().items[i]
		if not it.junk and AuctionHouse.coin_of(it).rare:
			Sfx.play(self, Sfx.register_chime(), -14.0)
		_build_viewing()


func consign(coin: BullionItem) -> void:
	if AuctionHouse.consign(coin):
		Sfx.play(self, Sfx.click(), -8.0)
	_build_viewing()


## Sits down: the sale starts with the first lot.
func take_seat() -> void:
	if phase != "viewing" or AuctionHouse.lots.is_empty():
		return
	AuctionHouse.begin()
	phase = "sale"
	lot_i = -1
	_next_lot()


## Raises your paddle at the asking price, or jumps the bidding.
func bid(jump := false) -> void:
	if phase != "sale" or stage != "bidding" or sale == null:
		return
	if sale.bid_you(jump):
		_you_at = _time
		Sfx.play(self, AuctionSfx.paddle(), -4.0)
		_take_events()
	else:
		Sfx.play(self, Sfx.click(), -14.0)


## Stops bidding on this lot: the room settles it without you.
func let_go() -> void:
	if phase != "sale" or stage != "bidding" or sale == null:
		return
	sale.finish_now()
	_hammer()


## Esc: off the viewing back to the morning; out of the sale (the rest sells without
## you); off the results.
func back() -> void:
	match phase:
		"viewing", "done":
			finished.emit()
		"sale":
			_run_out()
			_finish()


func _next_lot() -> void:
	lot_i += 1
	while lot_i < AuctionHouse.lots.size() and not AuctionHouse.lots[lot_i].result.is_empty():
		lot_i += 1
	if lot_i >= AuctionHouse.lots.size():
		_finish()
		return
	var lot: Dictionary = AuctionHouse.lots[lot_i]
	sale = AuctionSale.of(lot, seats)
	_bid_at.fill(-99.0)
	_out_at.fill(-99.0)
	_gavel_at = -99.0
	stage = "intro"
	_stage_left = INTRO
	_say(tr("Lot %d.") % lot.n)
	_build_sale()


## Takes the sale's news as it comes: paddles up, heads shaking, the auctioneer's calls.
func _take_events() -> void:
	var bids := 0
	for e in sale.events:
		match e.what:
			"bid", "jump":
				bids += 1
				if str(e.who) != "you":
					_bid_at[int(e.who)] = _time
					Sfx.play(self, AuctionSfx.paddle(), -8.0)
				_say(tr("%s, thank you!") % Market.format_money(e.amount))
				if e.what == "jump":
					Sfx.play(self, AuctionSfx.murmur(), -10.0)
			"out", "fold":
				_out_at[int(e.who)] = _time
			"call":
				_say(tr("Going once...") if int(e.amount) == 1 else tr("Going twice..."))
				Sfx.play(self, Sfx.tick(), -12.0)
	sale.events.clear()


func _hammer() -> void:
	sale.settle()
	stage = "after"
	_stage_left = AFTER
	_gavel_at = _time
	Sfx.play(self, AuctionSfx.gavel(), -2.0)
	var w := sale.winner()
	if w == "":
		_say(tr("No sale.") if not sale.mine else tr("Bought in."))
	elif w == "you":
		_say(tr("Sold, to paddle %d!") % YOUR_PADDLE)
		Sfx.play(self, Sfx.register_chime(), -10.0)
	else:
		_say(tr("Sold, to %s!") % sale.winner_name())
	_build_sale()


## Sells every lot left without you.
func _run_out() -> void:
	if sale != null and not sale.done:
		sale.finish_now()
		sale.settle()
	for n in range(maxi(lot_i, 0), AuctionHouse.lots.size()):
		var lot: Dictionary = AuctionHouse.lots[n]
		if lot.result.is_empty():
			var s := AuctionSale.of(lot, seats)
			s.finish_now()
			s.settle()
	sale = null


func _finish() -> void:
	phase = "done"
	stage = ""
	sale = null
	_build_done()


func _say(text: String) -> void:
	_call = text
	_call_at = _time


func _viewed() -> Dictionary:
	return AuctionHouse.lots[clampi(view_i, 0, AuctionHouse.lots.size() - 1)] if not AuctionHouse.lots.is_empty() else {"items": []}


## The lot on the plinth: the one under the hammer, or the one on the viewing tray.
func _shown_lot() -> Dictionary:
	if phase == "sale" and sale != null:
		return sale.lot
	if phase == "viewing" and not AuctionHouse.lots.is_empty():
		return _viewed()
	return {}


# ---------------------------------------------------------------- the viewing tray

## Where group `i` of `n` sits on the tray.
func _cell_rect(i: int, n: int) -> Rect2:
	var cols := mini(n, 3)
	var rows := ceili(n / 3.0)
	var inner := Rect2(AuctionArt.TRAY).grow(-12)
	var w := inner.size.x / cols
	var h := minf(inner.size.y / rows, 100.0)
	var row := i / 3
	var in_row := mini(n - row * 3, 3)
	var x0 := inner.position.x + (inner.size.x - in_row * w) / 2.0
	var y0 := inner.position.y + (inner.size.y - rows * h) / 2.0
	return Rect2(x0 + (i % 3) * w, y0 + row * h, w, h)


func _pouch_under(m: Vector2) -> int:
	var lot := _viewed()
	for i in lot.items.size():
		if lot.items[i].pouch and not lot.items[i].seen and _cell_rect(i, lot.items.size()).has_point(m):
			return i
	return -1


func _coin_tex(item: BullionItem, junk: bool) -> Texture2D:
	var key := item.id + ("_brass" if junk else "")
	if not _coins.has(key):
		_coins[key] = AuctionArt.coin(item, AuctionArt.tray_radius(item), junk).texture()
	return _coins[key]


func _pouch_tex(seed: int, open: bool) -> Texture2D:
	var key := "%d_%s" % [seed, open]
	if not _pouches.has(key):
		_pouches[key] = AuctionArt.pouch(seed, open).texture()
	return _pouches[key]


func _draw_tray() -> void:
	draw_rect(Rect2(Vector2(AuctionArt.TRAY.position) + Vector2(3, 4), AuctionArt.TRAY.size), Color(0, 0, 0, 0.45))
	draw_texture(_tray, AuctionArt.TRAY.position)
	var lot := _viewed()
	if lot.items.is_empty():
		return
	var head := tr("LOT %d") % lot.n
	_text(head, Vector2(AuctionArt.TRAY.position) + Vector2(10, 7), AuctionArt.PAPER)
	var n: int = lot.items.size()
	for i in n:
		var it: Dictionary = lot.items[i]
		var cell := _cell_rect(i, n)
		var centre := cell.get_center() - Vector2(0, 12)
		var coin := AuctionHouse.coin_of(it)
		if it.pouch:
			var p := _pouch_tex(int(lot.seed) + i, it.seen)
			var at := centre - Vector2(p.get_size()) / 2.0
			if it.seen:
				at.x -= 16
			draw_texture(p, at + Vector2(2, 2), Color(0, 0, 0, 0.35))
			draw_texture(p, at.round())
			if not it.seen and i == _hover and AuctionHouse.views_left > 0:
				var pulse := 0.5 + 0.5 * sin(_time * 6.0)
				draw_rect(Rect2(at.round() - Vector2(2, 2), p.get_size() + Vector2(4, 4)), Color(Pal.GOLD, 0.5 + pulse * 0.5), false, 1.0)
			if it.seen:
				_draw_fan(coin, it, centre + Vector2(16, 4), it.junk)
		else:
			_draw_fan(coin, it, centre, false)
		var col := Pal.BAD if it.junk and it.seen else (Pal.GOLD if coin.rare and (not it.pouch or it.seen) else AuctionArt.PAPER)
		var mid := cell.get_center().x
		if it.pouch and not it.seen:
			_text_centred(tr("Sealed pouch"), Vector2(mid, cell.end.y - 22), Pal.INK_DIM, cell.size.x - 4)
			_text_centred(tr("Guess %s") % Market.format_money(it.guess), Vector2(mid, cell.end.y - 12), Pal.INK_FAINT, cell.size.x - 4)
		elif it.junk:
			_text_centred(AuctionHouse.label_of(it), Vector2(mid, cell.end.y - 22), col, cell.size.x - 4)
			_text_centred(tr("Worthless"), Vector2(mid, cell.end.y - 12), Pal.INK_FAINT, cell.size.x - 4)
		else:
			_text_centred(coin.display_name, Vector2(mid, cell.end.y - 22), col, cell.size.x - 4)
			_text_centred("× %d   %s" % [int(it.qty), Market.format_money(AuctionHouse.melt_of(it))], Vector2(mid, cell.end.y - 12), Pal.INK_DIM, cell.size.x - 4)


## Up to four coins of a group, fanned out from back to front.
func _draw_fan(coin: BullionItem, it: Dictionary, centre: Vector2, junk: bool) -> void:
	var tex := _coin_tex(coin, junk)
	var k := mini(int(it.qty), 4)
	var step := Vector2(7, 3)
	var start := centre - Vector2(tex.get_size()) / 2.0 - step * (k - 1) / 2.0
	for j in k:
		var at := (start + step * j).round()
		draw_texture(tex, at + Vector2(1, 2), Color(0, 0, 0, 0.4))
		draw_texture(tex, at)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_room, Vector2.ZERO)
	_draw_chandelier()
	_draw_board()
	_draw_spotlight()
	_draw_auctioneer()
	_draw_bidders()
	draw_texture(_chairs, Vector2.ZERO)
	if phase == "sale":
		_draw_name_tags()
	_draw_your_paddle()
	if phase == "sale":
		_draw_call()
	if phase == "sale" and stage == "after":
		_draw_result_banner()
	if phase == "viewing":
		_draw_tray()


## A brass chandelier: a ring of candle bulbs and crystal drops that catch the light.
func _draw_chandelier() -> void:
	var c := AuctionArt.CHANDELIER
	draw_rect(Rect2(c.x, 0, 1, 12), AuctionArt.GILT[1])
	# a soft halo
	for k in 4:
		draw_rect(Rect2(c.x - 30 + k * 6, 10 + k * 2, 60 - k * 12, 14 - k * 3), Color(1, 0.86, 0.55, 0.04))
	for x in range(-20, 21):
		var y := 18.0 + sqrt(maxf(0.0, 1.0 - x * x / 400.0)) * 4.0
		draw_rect(Rect2(c.x + x, roundf(y), 1, 1), AuctionArt.GILT[2])
		draw_rect(Rect2(c.x + x, roundf(y) - 1, 1, 1), AuctionArt.GILT[3] if x < 0 else AuctionArt.GILT[1])
	for k in 7:
		var x := -18 + k * 6
		var y := 18 + int(sqrt(maxf(0.0, 1.0 - x * x / 400.0)) * 4.0)
		draw_rect(Rect2(c.x + x, y - 6, 1, 5), Color("#efe6d0"))
		draw_rect(Rect2(c.x + x, y - 7, 1, 1), Color("#ffe8a0"))
		# a crystal drop under each arm, twinkling
		var tw := sin(_time * 3.0 + k * 1.7)
		draw_rect(Rect2(c.x + x, y + 2, 1, 2), Color("#d8f0ff") if tw > 0.6 else Color("#8aa0b0"))
	draw_rect(Rect2(c.x - 1, 22, 3, 4), AuctionArt.GILT[2])


## The bid board: the lot, the bid (or the ask before the first bid) and the paddle holding it.
func _draw_board() -> void:
	var g := Rect2(AuctionArt.BOARD_GLASS)
	if phase != "sale" or sale == null:
		if phase == "viewing":
			_led(tr("VIEWING"), g.position + Vector2(4, 4))
			_led(tr("%d LOTS") % AuctionHouse.lots.size(), g.position + Vector2(4, 18))
		else:
			_led(tr("SALE OVER"), g.position + Vector2(4, 4))
		return
	_led(tr("LOT %d") % sale.lot.n, g.position + Vector2(4, 4))
	if sale.high > 0.0:
		_led(Market.format_money(sale.high), g.position + Vector2(4, 18))
		var who := YOUR_PADDLE if sale.leader == "you" else _numbers[int(sale.leader)]
		_led(tr("PADDLE %d") % who, g.position + Vector2(4, 32), Pal.LED if sale.leader == "you" else AMBER)
	else:
		_led(tr("ASK %s") % Market.format_money(sale.ask), g.position + Vector2(4, 18))


func _led(text: String, at: Vector2, col := AMBER) -> void:
	var glow := Color(col, 0.18)
	PixelFont.plot_text(text, func(x, y):
		if at.x + x > AuctionArt.BOARD_GLASS.end.x - 2:
			return
		draw_rect(Rect2(at.x + x - 1, at.y + y, 3, 1), glow)
		draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


## A warm cone of light from the ceiling onto the plinth, and the lot in it.
func _draw_spotlight() -> void:
	var top := AuctionArt.PLINTH_TOP
	draw_colored_polygon(PackedVector2Array([Vector2(top.x - 6, 0), Vector2(top.x + 6, 0), Vector2(top.x + 34, top.y + 2), Vector2(top.x - 34, top.y + 2)]),
		Color(1, 0.9, 0.65, 0.07))
	var lot := _shown_lot()
	if lot.is_empty():
		return
	if _mini_for != lot or _mini == null:
		_mini_for = lot
		_mini = AuctionArt.lot_mini(lot).texture()
	var at := (top - Vector2(_mini.get_size().x / 2.0, _mini.get_size().y - 4)).round()
	draw_texture(_mini, at)
	# the lot turns slowly on its turntable: a glint sweeps across
	var sweep := fmod(_time, 2.6) / 0.6
	if sweep < 1.0:
		var gx := at.x + 6 + sweep * 40.0
		draw_rect(Rect2(roundf(gx), at.y + 10, 1, 9), Color(1, 1, 1, 0.35))


## The auctioneer at the rostrum, mouth open while he calls, and his gavel: lying on the
## block, raised at "going once", down with a crack on "sold".
func _draw_auctioneer() -> void:
	var talking := _time - _call_at < 1.0 and fmod(_time, 0.24) < 0.12
	var bob := Vector2(0, 1) if phase == "sale" and stage == "bidding" and fmod(_time, 1.6) < 0.8 else Vector2.ZERO
	draw_texture(_auctioneer[1 if talking else 0], AuctionArt.AUCTIONEER_AT + bob)
	# the rostrum's top board covers his waist
	var r := AuctionArt.ROSTRUM
	draw_rect(Rect2(r.position.x - 3, r.position.y, r.size.x + 6, 5), Color("#5a3820"))
	draw_rect(Rect2(r.position.x - 3, r.position.y, r.size.x + 6, 1), Color("#8a5a34"))
	draw_rect(Rect2(r.position.x - 3, r.position.y + 5, r.size.x + 6, 1), Color("#24140a"))
	# his right hand and the gavel
	var hand := Vector2(r.end.x - 10, r.position.y - 4)
	var angle := 0.15 # lying on the block
	if phase == "sale" and sale != null and stage == "bidding" and sale.calls >= 1:
		angle = -1.1 # raised
	var since := _time - _gavel_at
	if since < 0.08:
		angle = lerpf(-1.3, 0.15, since / 0.08)
	elif since < 0.5:
		angle = 0.15
	draw_rect(Rect2(hand - Vector2(3, 2), Vector2(6, 4)), Color("#e8b890"))
	draw_set_transform(hand, angle)
	draw_rect(Rect2(0, -1, 14, 2), Color("#6a4226"))
	draw_rect(Rect2(0, -1, 14, 1), Color("#a0703e"))
	draw_rect(Rect2(12, -4, 5, 8), Color("#5a3820"))
	draw_rect(Rect2(12, -4, 5, 1), Color("#a0703e"))
	draw_rect(Rect2(12, -4, 1, 8), Color("#8a5a34"))
	draw_set_transform(Vector2.ZERO, 0.0)
	if since < 0.25:
		# the crack: a puff of dust off the block
		for k in 5:
			var a := -PI + k * PI / 4.0
			draw_rect(Rect2((hand + Vector2(14, 2) + Vector2.from_angle(a) * (4.0 + since * 40.0)).floor(), Vector2.ONE), Color(1, 0.95, 0.8, 0.8 - since * 3.0))


## The people in front of you. A paddle goes up with each bid; near their limit a paddle
## wavers half up and sweat flies off their brow; past it they shake their head.
func _draw_bidders() -> void:
	for i in seats.size():
		var sx: int = AuctionArt.SEATS[i]
		var at := Vector2(sx - AuctionArt.BIDDER_SIZE.x / 2.0, AuctionArt.SEAT_Y)
		var b: Dictionary = sale.bidders[i] if phase == "sale" and sale != null else {}
		var turn := 1
		var shaking := _time - _out_at[i] < SHAKE
		if shaking:
			turn = 0 if fmod(_time, 0.2) < 0.1 else 2
		elif not b.is_empty() and sale.leader == "you" and b.in:
			turn = 2 if i < seats.size() / 2 else 0 # a look round at who's bidding against them
		# breathing
		var breathe := Vector2(0, 1) if fmod(_time + i * 0.7, 3.0) < 1.5 else Vector2.ZERO
		var paddle_y := -1.0
		if _time - _bid_at[i] < PADDLE_UP:
			paddle_y = -30.0 # up, high and clear
		elif not b.is_empty() and b.in and b.hesitant and sale.leader != str(i) and stage == "bidding":
			paddle_y = -19.0 + sin(_time * 9.0 + i) * 2.0 # half up, wavering
		if paddle_y > -1.0:
			var pt: Texture2D = _paddle_tex[i]
			var hand_x := at.x + (40 if i % 2 == 0 else 10)
			draw_texture(pt, Vector2(hand_x - pt.get_size().x / 2.0, at.y + paddle_y).round())
		draw_texture(_bidder_tex[i][turn], (at + breathe).round())
		if not b.is_empty() and b.hesitant and b.in and stage == "bidding" and sale.leader != str(i):
			_draw_sweat(at + Vector2(AuctionArt.BIDDER_SIZE.x / 2.0, 0), i)


## Who just bid, or folded, on the back of their chair.
func _draw_name_tags() -> void:
	for i in seats.size():
		var at := Vector2(AuctionArt.SEATS[i], AuctionArt.CHAIR_TOP + 10)
		var b: Dictionary = sale.bidders[i] if sale != null else {}
		if _time - _bid_at[i] < PADDLE_UP + 0.5:
			_name_tag(str(seats[i].name), at)
		elif _time - _out_at[i] < SHAKE and not b.is_empty() and b.folded:
			_name_tag(tr("%s folds") % str(seats[i].name), at, Pal.WARN)


func _draw_sweat(head: Vector2, i: int) -> void:
	var t := fmod(_time + i * 0.37, 1.1)
	var side := -1.0 if i % 2 == 0 else 1.0
	var drop := head + Vector2(side * (11.0 + t * 8.0), 6.0 - t * 6.0 + t * t * 18.0)
	draw_rect(Rect2(drop.floor(), Vector2(1, 2)), Color("#bfe4ff"))
	draw_rect(Rect2(drop.floor() + Vector2(0, -1), Vector2.ONE), Color("#ffffff"))


func _name_tag(text: String, centre: Vector2, col := AuctionArt.PAPER) -> void:
	var w := PixelFont.measure(text) + 6
	var r := Rect2(roundf(centre.x - w / 2.0), centre.y, w, 11)
	r.position.x = clampf(r.position.x, 2, PANEL_X - w - 2)
	draw_rect(r, Color(0.08, 0.05, 0.04, 0.85))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(col, 0.6))
	_text(text, r.position + Vector2(3, 2), col)


## Your hand and paddle 27, raised when you bid.
func _draw_your_paddle() -> void:
	var up := clampf(1.0 - (_time - _you_at - 0.5) / 0.25, 0.0, 1.0) if _time - _you_at > 0.5 else clampf((_time - _you_at) / 0.08, 0.0, 1.0)
	var at := AuctionArt.PADDLE_REST.lerp(AuctionArt.PADDLE_UP, up)
	var size := _big_paddle.get_size()
	draw_texture(_big_paddle, (at - Vector2(size.x / 2.0, 0)).round())
	draw_texture(_hand, (at + Vector2(-10, size.y - 8)).round())


## The auctioneer's words in a bubble by the rostrum.
func _draw_call() -> void:
	if _call == "" or _time - _call_at > 2.6:
		return
	var w := mini(PixelFont.measure(_call) + 8, 150)
	var r := Rect2(AuctionArt.ROSTRUM.position.x - w + 6, 76, w, 12)
	draw_rect(r, AuctionArt.PAPER)
	draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 1), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), Color("#b8a888"))
	draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 6, r.position.y + 3), Vector2(r.end.x + 4, r.position.y + 6), Vector2(r.end.x - 6, r.position.y + 9)]), AuctionArt.PAPER)
	_text(_call, r.position + Vector2(4, 3), Color("#2a1a10"), w - 8)


## SOLD, and to whom, across the room after the hammer.
func _draw_result_banner() -> void:
	var w := sale.winner()
	var text := tr("NO SALE")
	var col := Pal.INK_DIM
	if w == "you":
		text = tr("YOURS! %s") % Market.format_money(sale.high)
		col = Pal.GOOD
	elif w != "":
		text = tr("SOLD %s") % Market.format_money(sale.high)
		col = Pal.GOLD
	var y := 138.0
	draw_rect(Rect2(0, y, PANEL_X, 15), Color(0.06, 0.04, 0.03, 0.85))
	draw_rect(Rect2(0, y, PANEL_X, 1), col)
	draw_rect(Rect2(0, y + 14, PANEL_X, 1), col)
	_text_centred(text, Vector2(PANEL_X / 2.0, y + 4), col, PANEL_X)


func _text(text: String, at: Vector2, col: Color, max_w := 0) -> void:
	PixelFont.plot_text(text, func(x, y):
		if max_w > 0 and x >= max_w:
			return
		draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


func _text_centred(text: String, centre: Vector2, col: Color, max_w: int) -> void:
	var w := mini(PixelFont.measure(text), max_w)
	_text(text, Vector2(roundf(centre.x - w / 2.0), centre.y), col, max_w)


# ---------------------------------------------------------------- the panel

func _clear() -> void:
	for n in _ui.get_children():
		n.queue_free()
	_live.clear()


func _show_viewing() -> void:
	phase = "viewing"
	_build_viewing()


func _build_viewing() -> void:
	_clear()
	var x := PANEL_X + 4
	_label("ASHWORTH & FINCH", Vector2(x, 4), Pal.INK_FAINT)
	_label("Viewing", Vector2(x, 13), Pal.GOLD)
	if AuctionHouse.lots.is_empty():
		_label("No sale today.", Vector2(x, 26), Pal.INK_DIM, 156)
		_button("Back to the morning", Rect2(x, 240, 156, 13), "Button", func(): finished.emit())
		return
	var lot := _viewed()
	_button("<", Rect2(x, 24, 14, 11), "Button", func(): show_lot(view_i - 1))
	_label(tr("Lot %d of %d") % [lot.n, AuctionHouse.lots.size()], Vector2(x + 16, 26), Pal.INK, 124, HORIZONTAL_ALIGNMENT_CENTER)
	_button(">", Rect2(x + 142, 24, 14, 11), "Button", func(): show_lot(view_i + 1))
	var y := 40
	_label(AuctionHouse.title_of(lot), Vector2(x, y), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	y += 20
	var est := AuctionHouse.estimate(lot)
	_label(tr("Estimate %s-%s") % [Market.format_money(est.x), Market.format_money(est.y)], Vector2(x, y), Pal.INK, 156)
	y += 10
	var unseen := AuctionHouse.pouches_unseen(lot)
	_label(tr("Melt you can see: %s") % Market.format_money(AuctionHouse.known_melt(lot)), Vector2(x, y), Pal.INK_DIM, 156)
	y += 10
	if unseen > 0:
		_label(tr_n("Plus %d sealed pouch.", "Plus %d sealed pouches.", unseen) % unseen, Vector2(x, y), Pal.INK_DIM, 156)
		y += 10
	var wanted := AuctionHouse.wanted_in(lot)
	if wanted != null:
		_label(tr("A collector's order wants this %s.") % wanted.display_name, Vector2(x, y), Pal.GOOD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
		y += 20
	if lot.kind == "mine":
		_label(tr("Your lot. Reserve %s.") % Market.format_money(AuctionHouse.reserve(lot)), Vector2(x, y), Pal.GOLD, 156)
		y += 10
	y += 4
	if unseen > 0 or AuctionHouse.views_left < AuctionHouse.VIEWINGS[clampi(Progress.tier, 0, 3)]:
		var looks := tr_n("Click a pouch to look inside: %d look left.", "Click a pouch to look inside: %d looks left.", AuctionHouse.views_left) % AuctionHouse.views_left
		_label(looks if AuctionHouse.views_left > 0 else tr("No more looks inside the pouches."), Vector2(x, y), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
		y += 22
	var spare := AuctionHouse.consignable()
	if not spare.is_empty():
		_label("SELL YOUR RARE COINS", Vector2(x, y), Pal.INK_FAINT)
		y += 10
		for coin in spare.slice(0, 2):
			var b := _button(tr("Consign %s") % coin.display_name, Rect2(x, y, 156, 11), "Button", consign.bind(coin))
			b.tooltip_text = tr("Ashworth & Finch sell it last today and keep %d%%. It won't go under melt.") % roundi(AuctionHouse.SELLERS_FEE * 100.0)
			_shrink(b)
			y += 13
	_label(tr("The winner pays %d%% on top of the hammer price.") % roundi(AuctionHouse.BUYERS_PREMIUM * 100.0), Vector2(x, 206), Pal.INK_FAINT, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_button("Take your seat", Rect2(x, 226, 156, 13), "PrimaryButton", take_seat)
	_button("Back to the morning", Rect2(x, 242, 156, 11), "Button", func(): finished.emit())
	_label(tr("Esc: back"), Vector2(x, 258), Pal.INK_FAINT)


func _build_sale() -> void:
	_clear()
	var x := PANEL_X + 4
	var lot: Dictionary = sale.lot
	_label(tr("LOT %d OF %d") % [lot.n, AuctionHouse.lots.size()], Vector2(x, 4), Pal.INK_FAINT)
	_label(AuctionHouse.title_of(lot), Vector2(x, 13), Pal.GOLD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	var est := AuctionHouse.estimate(lot)
	_label(tr("Estimate %s-%s") % [Market.format_money(est.x), Market.format_money(est.y)], Vector2(x, 33), Pal.INK_DIM, 156)
	var y := 43
	for it in lot.items.slice(0, 5):
		_label(AuctionHouse.label_of(it), Vector2(x, y), Pal.INK if not it.pouch or it.seen else Pal.INK_DIM, 156)
		y += 9
	var wanted := AuctionHouse.wanted_in(lot)
	if wanted != null:
		_label("An order wants this coin.", Vector2(x, y), Pal.GOOD, 156)
	_label("ASKING", Vector2(x, 100), Pal.INK_FAINT)
	_live.ask = _label("", Vector2(x + 60, 100), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("HIGH BID", Vector2(x, 110), Pal.INK_FAINT)
	_live.high = _label("", Vector2(x + 60, 110), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_live.who = _label("", Vector2(x, 120), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_RIGHT)
	_live.bid = _button("", Rect2(x, 134, 156, 15), "PrimaryButton", func(): bid())
	_live.jump = _button("", Rect2(x, 152, 156, 12), "Button", func(): bid(true))
	_live.jump.tooltip_text = "Skip ahead a few steps. Someone near their limit may give up."
	_live.let_go = _button("Let it go", Rect2(x, 167, 156, 11), "Button", let_go)
	_live.pay = _label("", Vector2(x, 182), Pal.INK_DIM, 156)
	_live.tell = _label("", Vector2(x, 192), Pal.WARN, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_live.cash = _label("", Vector2(x, 214), Pal.INK_DIM, 156)
	_label("Space: bid   J: jump", Vector2(x, 226), Pal.INK_FAINT, 156)
	_button("Leave the sale", Rect2(x, 240, 156, 11), "Button", back)
	_label(tr("Esc: leave"), Vector2(x, 256), Pal.INK_FAINT)


func _refresh_live() -> void:
	if phase != "sale" or sale == null or not _live.has("ask"):
		return
	_live.ask.text = Market.format_money(sale.ask) if not sale.done else "-"
	_live.high.text = Market.format_money(sale.high) if sale.high > 0.0 else "-"
	_live.high.add_theme_color_override("font_color", Pal.GOOD if sale.leader == "you" else Pal.INK)
	var who := ""
	if sale.leader == "you":
		who = tr("You hold the bid.")
	elif sale.leader != "":
		who = tr("%s (paddle %d)") % [sale.bidders[int(sale.leader)].name, _numbers[int(sale.leader)]]
	_live.who.text = who
	var bidding := stage == "bidding" and not sale.done
	_live.bid.text = tr("Bid %s") % Market.format_money(sale.ask)
	_live.bid.disabled = not bidding or not sale.can_bid() or not AuctionHouse.can_afford(sale.ask)
	_live.jump.text = tr("Jump to %s") % Market.format_money(sale.jump_amount())
	_live.jump.disabled = not bidding or not sale.can_bid() or not AuctionHouse.can_afford(sale.jump_amount())
	_live.let_go.disabled = not bidding
	if sale.mine:
		_live.pay.text = tr("Your lot. Reserve %s.") % Market.format_money(sale.reserve)
	elif sale.leader == "you":
		_live.pay.text = tr("You'd pay %s with the premium.") % Market.format_money(AuctionHouse.price_with_premium(sale.high))
	else:
		_live.pay.text = tr("At %s you'd pay %s.") % [Market.format_money(sale.ask), Market.format_money(AuctionHouse.price_with_premium(sale.ask))]
	var tell := ""
	if bidding:
		for i in sale.bidders.size():
			var b: Dictionary = sale.bidders[i]
			if b.in and b.hesitant and sale.leader != str(i):
				tell = tr("%s hesitates...") % b.name
				break
	_live.tell.text = tell
	_live.cash.text = tr("Cash %s") % Market.format_money(Shop.cash)


func _build_done() -> void:
	_clear()
	var x := PANEL_X + 4
	_label("THE SALE IS OVER", Vector2(x, 4), Pal.INK_FAINT)
	var y := 15
	var spent := 0.0
	for lot in AuctionHouse.lots:
		var r: Dictionary = lot.result
		if r.is_empty():
			continue
		var line := ""
		var col := Pal.INK_DIM
		if str(r.winner) == "you":
			line = tr("Lot %d: yours, %s") % [lot.n, Market.format_money(AuctionHouse.price_with_premium(r.hammer))]
			col = Pal.GOOD
			spent += AuctionHouse.price_with_premium(r.hammer)
		elif lot.kind == "mine":
			line = tr("Lot %d: your coin sold, %s") % [lot.n, Market.format_money(r.hammer)] if str(r.winner) != "" else tr("Lot %d: your coin came back") % lot.n
			col = Pal.GOLD
		elif str(r.winner) == "":
			line = tr("Lot %d: no sale") % lot.n
		else:
			line = tr("Lot %d: %s, %s") % [lot.n, r.name, Market.format_money(r.hammer)]
		_shrink(_label(line, Vector2(x, y), col, 156))
		y += 9
		if str(r.winner) == "you":
			for it in lot.items:
				if it.pouch and not it.seen:
					it.seen = true # you've opened it now
					var found := tr("Pouch: %s") % AuctionHouse.label_of(it)
					var good: bool = not it.junk and AuctionHouse.coin_of(it).rare
					_shrink(_label(found, Vector2(x + 6, y), Pal.BAD if it.junk else (Pal.GOLD if good else Pal.INK), 150))
					y += 9
	y += 4
	if spent > 0.0:
		_label(tr("Spent %s. The coins are in your vault.") % Market.format_money(spent), Vector2(x, y), Pal.INK, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	else:
		_label("You went home with nothing this time.", Vector2(x, y), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_label(tr("Next sale: %s.") % Day.weekday(AuctionHouse.next_sale_day(Shop.day + 1)), Vector2(x, 226), Pal.INK_FAINT, 156)
	_button("Back to the morning", Rect2(x, 240, 156, 13), "PrimaryButton", func(): finished.emit())


func _shrink(c: Control) -> Control:
	if c is Label:
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif c is Button:
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return c


func _label(text: String, pos: Vector2, col: Color, width := 0, align := HORIZONTAL_ALIGNMENT_LEFT, wrap_height := 0) -> Label:
	var l := Label.new()
	_ui.add_child(l)
	if wrap_height > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	l.position = pos
	if width > 0:
		l.size = Vector2(width, maxi(wrap_height, 8))
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, r: Rect2, variation: String, on_press: Callable) -> Button:
	var b := Button.new()
	_ui.add_child(b)
	b.text = text
	b.theme_type_variation = variation
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _exit_tree() -> void:
	# walking out mid-sale: the rest of the lots sell without you
	if phase == "sale":
		_run_out()
