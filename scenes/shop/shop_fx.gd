class_name ShopFx
extends Node2D
## Little bits of life over the shop floor, each with its sound: coins arcing across the
## counter on a deal, the money popping up over the till, the service bell when someone
## reaches the counter, customers' voices and reactions (a cheer, a grumble, steam when they
## storm out, sweat when they're kept waiting), sparkles for a caught fake, dust at the door,
## and the red flashing and shaking of a hold-up.
## It only listens (the Shop autoload, the shop scene's signals, and who is where), so the
## shop's rules don't depend on it. shop.gd adds one to the room.

const HAND_OVER := Vector3(6.2, 4.0, ShopArt.COUNTER_H) # the counter edge between keeper and customer
const REGISTER := Vector3(7.8, 3.65, ShopArt.COUNTER_H + 8.0)
const CLERK_TILL := Vector3(2.1, 3.6, ShopArt.COUNTER_H + 4.0)
const SERVICE_BELL := Vector3(6.6, 3.85, ShopArt.COUNTER_H)
const HEAD := Vector2(0, -29)
const STEAM := Color("#e8e4dc")
const SWEAT := Color("#9cd4ff")

## The shop scene (untyped: shop.gd has no class_name) and its room.
var shop
var room
## Live particles: {"kind", "pos", "vel", "grav", "age", "life", "col", "text", "size"}.
var parts := []
## Coins in flight: {"from", "to", "age", "delay", "life", "col", "hi", "arc"}.
var coins := []

var _time := 0.0
var _known := {}
var _front: Customer
var _front_tries := 0
var _bell := 9.0
var _shake := 0.0
var _alarm := 0.0
var _last_mood := ""
var _last_amount := 0.0
var _sweat := {}
var _rng := RandomNumberGenerator.new()
var _base := Vector2.ZERO


func _init(shop_scene = null) -> void:
	shop = shop_scene
	_rng.seed = 7


func _ready() -> void:
	room = get_parent()
	ShopSfx.warm_up()
	_base = room.position
	Shop.noted.connect(_on_noted)
	Shop.logged.connect(func(_text, mood): _last_mood = mood)
	if shop:
		shop.customer_left.connect(_on_customer_left)


func _process(delta: float) -> void:
	_time += delta
	_bell += delta
	if shop:
		_watch_door()
		_watch_counter()
		_watch_patience(delta)
	_move(delta)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		var k := ceilf(_shake * 4.0)
		room.position = _base + Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1)) * k
	elif room.position != _base:
		room.position = _base
	_alarm = maxf(0.0, _alarm - delta)
	queue_redraw()


func at(p: Vector3) -> Vector2:
	return room.screen_pos(p.x, p.y, p.z)


func head_of(c: Customer) -> Vector2:
	return room.screen_pos(c.pos.x, c.pos.y).round() + HEAD


# --- what to show when ------------------------------------------------------------

## A puff of dust from the doormat for everyone who walks in.
func _watch_door() -> void:
	for c in shop.queue:
		if _known.has(c):
			continue
		_known[c] = true
		_puff(at(Vector3(ShopArt.ENTRANCE.x, ShopArt.ENTRANCE.y, 0)), 5, Color("#8a7a62"))
	for c in _known.keys():
		if not shop.queue.has(c) and not shop.leaving.has(c) and shop.at_clerk != c:
			_known.erase(c)
			_sweat.erase(c)


## Someone new at the counter rings the bell and says hello; a turned-down offer gets a "hmm".
func _watch_counter() -> void:
	var c: Customer = room.front_customer
	if c != _front:
		_front = c
		_front_tries = c.tries if c else 0
		if c and c.kind != "robber":
			_ring_bell()
			_say(c, "hello", -14.0, 0.35)
		return
	if c and c.tries > _front_tries:
		_front_tries = c.tries
		_say(c, "hmm" if c.patience / c.max_patience > 0.4 else "grumble", -10.0)
		_pop_text(head_of(c) + Vector2(5, -4), "?", Pal.INK, 0.9)


## Sweat drops on the impatient; steam off anyone nearly out of patience.
func _watch_patience(delta: float) -> void:
	for c in shop.queue:
		if c.walking or c.kind == "robber" or c.kind == "visit":
			continue
		var f: float = c.patience / c.max_patience
		if f > 0.3:
			continue
		_sweat[c] = float(_sweat.get(c, 0.0)) - delta
		if _sweat[c] > 0.0:
			continue
		_sweat[c] = 0.5 if f < 0.15 else 1.1
		var h := head_of(c)
		if f < 0.15:
			_steam(h + Vector2(_rng.randi_range(-3, 3), -1), 1)
		else:
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			parts.append({"kind": "drop", "pos": h + Vector2(side * 4, 2), "vel": Vector2(side * 10, -14), "grav": 70.0, "age": 0.0, "life": 0.6, "col": SWEAT})


func _on_noted(key: String, amount: float) -> void:
	match key:
		"bought", "sold":
			_last_amount = amount
		"caught":
			Sfx.play(self, ShopSfx.sparkle(), -8.0)
			_sparkles(at(HAND_OVER) + Vector2(0, -4), 7)
		"scammed":
			Sfx.play(self, ShopSfx.wrong(), -8.0)
			_steam(at(REGISTER) + Vector2(0, -2), 4, Color("#6f6455"))
			_pop_text(at(REGISTER) + Vector2(-6, -10), "FAKE!", Pal.BAD)
		"stolen":
			if amount <= 0.0:
				return
			Sfx.play(self, ShopSfx.whoosh(), -6.0)
			_fly(at(REGISTER), at(Vector3(ShopArt.EXIT.x, ShopArt.EXIT.y, 10.0)), 6, Pal.metal("gold", 4), Pal.metal("gold", 5), 0.7)
			_pop_text(at(REGISTER) + Vector2(-8, -10), "-" + _money(amount), Pal.BAD)
		"holdups":
			_alarm = 4.0
			_shake = 0.6
			for c in shop.queue:
				if c.kind != "robber" and not c.walking:
					_say(c, "gasp", -12.0, _rng.randf() * 0.25)
					_pop_text(head_of(c) + Vector2(4, -4), "!", Pal.WARN, 0.9)
		"robbers_stopped":
			Sfx.play(self, ShopSfx.sparkle(), -8.0)
			_sparkles(at(Vector3(ShopArt.ENTRANCE.x, ShopArt.ENTRANCE.y, 26.0)), 6)


## How each visit ends shows on the way out. Shop.log_event runs just before the signal,
## so its mood says whether it went well.
func _on_customer_left(c: Customer) -> void:
	var mood := _last_mood
	_last_mood = ""
	if c.kind == "robber":
		_shake = maxf(_shake, 0.3)
		Sfx.play(self, ShopSfx.whoosh(), -6.0)
		return
	if c.dealt:
		_deal_done(c)
		return
	if mood == "bad":
		_say(c, "angry", -8.0)
		_steam(head_of(c), 6)
		_shake = maxf(_shake, 0.15)
	elif mood == "good":
		# a caught con artist slinks off
		_say(c, "grumble", -8.0, 0.2)
		_steam(head_of(c), 2)
	elif shop.robber != null:
		# fleeing a hold-up
		Sfx.play(self, ShopSfx.whoosh(), -12.0)
	else:
		_say(c, "hello" if c.kind == "visit" else "hmm", -12.0)


## Coins across the counter: a seller's coins to you, a buyer's coins from the register to them.
func _deal_done(c: Customer) -> void:
	var col := _coin_colour(c)
	var hand := head_of(c) + Vector2(2, 12)
	var clerk: bool = c.pos.distance_to(ShopArt.CLERK_SLOT) < 0.3
	if c.kind == "seller":
		_fly(hand, at(HAND_OVER), 5, col[0], col[1], 0.45)
		_pop_text(at(REGISTER) + Vector2(-8, -12), "-" + _money(_last_amount), Pal.INK_DIM)
	else:
		var till := at(CLERK_TILL) if clerk else at(REGISTER)
		_fly(till, hand, 5, col[0], col[1], 0.5)
		_pop_text(till + Vector2(-8, -12), "+" + _money(_last_amount), Pal.GOOD)
		_sparkles(till + Vector2(0, -6), 3)
	_say(c, "happy", -10.0, 0.25)


func _coin_colour(c: Customer) -> Array:
	var pal := "gold"
	if c.piece:
		pal = Pal.for_metal(c.piece.metal)
	elif c.bar:
		pal = c.bar.palette_name()
	elif c.item:
		pal = c.item.palette_name()
	return [Pal.metal(pal, 3), Pal.metal(pal, 5)]


func _ring_bell() -> void:
	if _bell < 1.5:
		return
	_bell = 0.0
	Sfx.play(self, ShopSfx.service_bell(), -12.0)


## A customer says something in their own voice, after `delay` seconds.
func _say(c: Customer, mood: String, volume_db: float, delay := 0.0) -> void:
	var stream := ShopSfx.voice(mood, ShopSfx.pitch_for(c.seed))
	if delay <= 0.0:
		Sfx.play(self, stream, volume_db)
	elif is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(func(): Sfx.play(self, stream, volume_db))


func _money(usd: float) -> String:
	return Market.format_money(usd)


# --- particles ---------------------------------------------------------------------

func _fly(from: Vector2, to: Vector2, count: int, col: Color, hi: Color, life: float) -> void:
	for k in count:
		coins.append({"from": from + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1)), "to": to + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-1, 1)),
			"age": 0.0, "delay": k * 0.06, "life": life, "col": col, "hi": hi, "arc": _rng.randf_range(10.0, 16.0)})


func _puff(p: Vector2, count: int, col: Color) -> void:
	for k in count:
		parts.append({"kind": "dust", "pos": p + Vector2(_rng.randf_range(-4, 4), 0), "vel": Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-8, -3)),
			"grav": 0.0, "age": 0.0, "life": _rng.randf_range(0.4, 0.7), "col": col, "size": 1.0})


func _steam(p: Vector2, count: int, col := STEAM) -> void:
	for k in count:
		parts.append({"kind": "steam", "pos": p + Vector2(_rng.randf_range(-4, 4), 0), "vel": Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-16, -10)),
			"grav": 0.0, "age": -k * 0.08, "life": 0.8, "col": col, "size": 1.0})


func _sparkles(p: Vector2, count: int) -> void:
	for k in count:
		var a := _rng.randf() * TAU
		parts.append({"kind": "spark", "pos": p, "vel": Vector2(cos(a), sin(a) * 0.7) * _rng.randf_range(10, 26),
			"grav": 0.0, "age": -k * 0.03, "life": 0.6, "col": Pal.GOLD if k % 2 else Color("#fff4c8")})


func _pop_text(p: Vector2, text: String, col: Color, life := 1.3) -> void:
	parts.append({"kind": "text", "pos": p, "vel": Vector2(0, -9), "grav": 0.0, "age": 0.0, "life": life, "col": col, "text": text})


func _move(delta: float) -> void:
	for p in parts:
		p.age += delta
		if p.age < 0.0:
			continue
		p.vel.y += p.grav * delta
		p.pos += p.vel * delta
	parts = parts.filter(func(p): return p.age < p.life)
	var landed := false
	for f in coins:
		f.age += delta
		if f.age - f.delay >= f.life:
			landed = true
	if landed:
		var keep := []
		for f in coins:
			if f.age - f.delay < f.life:
				keep.append(f)
			elif f.delay == 0.0:
				# the first coin of each handful down: clink, and a glint where it lands
				Sfx.play(self, ShopSfx.coin_clink(_rng.randi()), -8.0)
				_sparkles(f.to, 2)
		coins = keep


# --- drawing -----------------------------------------------------------------------

func _draw() -> void:
	_draw_bell()
	for f in coins:
		var t: float = (f.age - f.delay) / f.life
		if t < 0.0:
			continue
		var p: Vector2 = f.from.lerp(f.to, t) + Vector2(0, -f.arc * 4.0 * t * (1.0 - t))
		p = p.round()
		# spinning: face-on, edge-on, face-on
		if int((f.age + f.delay) * 14.0) % 3 == 1:
			draw_rect(Rect2(p + Vector2(1, -1), Vector2(1, 3)), f.col)
		else:
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(3, 3)), f.col)
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), f.hi)
	for p in parts:
		if p.age < 0.0:
			continue
		var t: float = p.age / p.life
		var q: Vector2 = p.pos.round()
		match p.kind:
			"dust":
				draw_rect(Rect2(q, Vector2.ONE * (2.0 if t < 0.4 else 1.0)), Color(p.col, 0.7 * (1.0 - t)))
			"steam":
				var r := 1.5 + t * 3.0
				draw_circle(q, r, Color(p.col.darkened(0.3), 0.6 * (1.0 - t)))
				draw_circle(q + Vector2(-0.5, -0.5), r - 0.5, Color(p.col, 0.9 * (1.0 - t)))
			"drop":
				draw_rect(Rect2(q, Vector2(1, 2)), Color(p.col, 1.0 - t * t))
			"spark":
				var col := Color(p.col, 1.0 - t)
				var arm := 1.0 if t < 0.5 else 0.0
				draw_rect(Rect2(q, Vector2.ONE), col)
				if arm > 0.0:
					for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
						draw_rect(Rect2(q + d, Vector2.ONE), Color(col, col.a * 0.7))
			"text":
				var a := clampf((1.0 - t) * 3.0, 0.0, 1.0)
				var ink: Color = Color(p.col, a)
				var shadow := Color(0.05, 0.03, 0.02, a * 0.8)
				PixelFont.plot_text(p.text, func(x, y): draw_rect(Rect2(q + Vector2(x + 1, y + 1), Vector2.ONE), shadow))
				PixelFont.plot_text(p.text, func(x, y): draw_rect(Rect2(q + Vector2(x, y), Vector2.ONE), ink))
	if shop and shop.robber != null and shop.robber_revealed:
		# a "!" bouncing over the robber
		var h := head_of(shop.robber) + Vector2(-1, -16 - (1 if fmod(_time, 0.4) < 0.2 else 0))
		_draw_rows(h + Vector2(-1, -1), ["####", "####", "####", "####", "####", ".##.", "####", "####"], Pal.INK)
		_draw_rows(h, ["##", "##", "##", "..", "##"], Pal.BAD)
	if _alarm > 0.0 or (shop and shop.robber_revealed):
		var pulse := 0.5 + 0.5 * sin(_time * TAU * 2.0)
		draw_rect(Rect2(Vector2.ZERO, ShopArt.SIZE), Color(0.9, 0.1, 0.08, 0.12 * pulse))


## The service bell's clapper bounces and little rings spread for a moment after a ding.
func _draw_bell() -> void:
	if _bell > 0.5:
		return
	var p := at(SERVICE_BELL).round() + Vector2(0, -5)
	var a := 1.0 - _bell / 0.5
	var r := 2.0 + _bell * 8.0
	# a ")" either side, the middle pixel bulging out
	for side in [-1.0, 1.0]:
		for k in 3:
			draw_rect(Rect2(p + Vector2(side * (r + (1.0 if k == 1 else 0.0)), k - 1), Vector2.ONE), Color(Pal.GOLD, a))


func _draw_rows(p: Vector2, rows: Array, col: Color) -> void:
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				draw_rect(Rect2(p + Vector2(x, y), Vector2.ONE), col)
