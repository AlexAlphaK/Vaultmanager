class_name Smelter
extends Control
## The Smelter, opened from the morning panel once the melting furnace is bought.
## Buy the scrap dealer's lots into the bin, then melt each metal into a bar:
##   sort   sweep the magnet over the tray to pull out the steel (1 or click Magnet)
##   melt   set the gas (Up/Down, W/S or the slider) to bring the furnace into the pour
##          band shown on the pyrometer, and drop borax (F) until the scum is gone and
##          the melt shines like a mirror
##   pour   hold Space or the Pour button: the crucible comes out of the furnace and
##          tilts over the mould. Pour steady, not too fast, and before it cools
##   assay  the bar is quenched, hallmarked and sold to the bullion dealer
## The melt itself is Melt; the bin and the dealer's lots are ScrapYard.
## Run this scene on its own (F6 in the editor) to try it with the furnace and a few lots.

signal finished

const PANEL_X := 316
const POUR_PIVOT := Vector2(236, 150)
const LIP_CORNER := Vector2(35, 3)
const TILT_ANGLE := 1.75
## Where the pour lands in the mould, and how long the bar takes to cool and come out.
const IMPACT := Vector2(238, 208)
const COOL_SECONDS := 1.6
const MAGNET_REACH := 12.0
const GAS_STEP := 0.05

var phase := "yard" # "yard", "sort", "melt" or "result"
var melt: Melt
var assay := {}
## Pieces on the sorting tray: {"tex", "pos", "steel", "pulled", "fly"}.
var pieces: Array[Dictionary] = []
var magnet_on := false
var pour_held := false

var _room: Texture2D
var _crucible: Texture2D
var _bar: Texture2D
var _time := 0.0
var _result_at := 0.0
var _ui: Control
var _live := {}
var _sparks: Array[Dictionary] = [] # {"pos", "vel", "life", "col"}
var _beads: Array[Dictionary] = [] # splashes cooling on the hearth: {"pos", "born"}
var _steam: Array[Dictionary] = []
var _roar: AudioStreamPlayer
var _pour_sound := -99.0
var _flux_at := -99.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("pad_hooks")
	_rng.randomize()
	_room = SmelterArt.paint().texture()
	_crucible = SmelterArt.crucible().texture()
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
	_roar = AudioStreamPlayer.new()
	_roar.stream = SmelterSfx.roar()
	_roar.bus = "SFX"
	_roar.volume_db = -60.0
	add_child(_roar)
	if get_tree().current_scene == self:
		_try_out.call_deferred()


## Opens on the yard: the dealer's lots and the scrap bin.
func start() -> void:
	ScrapYard.refresh_offers()
	_show_yard()
	Sfx.play(self, Sfx.click(), -8.0)


func _try_out() -> void:
	ScrapYard.hook_up()
	if not Progress.has_upgrade("furnace"):
		Progress.owned.append("furnace")
	ScrapYard.offer_day = 0
	ScrapYard.refresh_offers()
	start()
	finished.connect(func(): get_tree().reload_current_scene())


func _process(delta: float) -> void:
	_time += delta
	if phase == "melt" and melt != null:
		var held := pour_held or Input.is_key_pressed(KEY_SPACE)
		var was_lifted := melt.lifted
		melt.advance(delta, held)
		if melt.lifted and not was_lifted:
			Sfx.play(self, Sfx.click(), -6.0)
		if melt.flow_rate() > 0.0 and _time - _pour_sound > 0.8:
			_pour_sound = _time
			Sfx.play(self, SmelterSfx.pour(), -10.0)
		_spawn_sparks(delta)
		if melt.done:
			_finish_melt()
	_roar.volume_db = -60.0 if melt == null or melt.lifted or phase != "melt" else lerpf(-30.0, -8.0, melt.gas)
	if melt != null and phase == "melt" and not melt.lifted and melt.gas > 0.0 and not _roar.playing:
		_roar.play()
	_update_sort()
	_update_particles(delta)
	_refresh_live()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	var k: int = event.keycode
	if phase == "melt" and (k == KEY_UP or k == KEY_W or k == KEY_DOWN or k == KEY_S):
		set_gas(melt.gas + (GAS_STEP if k == KEY_UP or k == KEY_W else -GAS_STEP))
		get_viewport().set_input_as_handled()
		return
	if event.echo:
		return
	match k:
		KEY_F:
			if phase == "melt":
				flux()
		KEY_1, KEY_KP_1:
			if phase == "sort":
				toggle_magnet()
		KEY_ENTER, KEY_KP_ENTER:
			if phase == "sort":
				load_crucible()
			elif phase == "result":
				_show_yard()
		KEY_SPACE:
			pass # held; read in _process
		KEY_ESCAPE:
			back()
		_:
			return
	get_viewport().set_input_as_handled()


## LB and RB turn the gas down and up, LT drops a pinch of flux, RT toggles the magnet.
func pad_action(name: String) -> bool:
	match name:
		"lb", "rb":
			if phase != "melt":
				return false
			set_gas(melt.gas + (GAS_STEP if name == "rb" else -GAS_STEP) * 2.0)
		"lt":
			if phase != "melt":
				return false
			flux()
		"rt":
			if phase != "sort":
				return false
			toggle_magnet()
		_:
			return false
	return true


func pad_help() -> Array:
	return [["LB / RB", "Gas down / up"], ["LT", "A pinch of borax"], ["RT", "Magnet (sorting)"], ["A on Pour", "Hold to pour"]]


# ---------------------------------------------------------------- actions

## Esc: from the yard back to the morning; out of a sort or a melt that hasn't poured,
## the scrap goes back in the bin; mid-pour, the pour stops.
func back() -> void:
	match phase:
		"yard":
			finished.emit()
		"sort":
			_abandon()
		"melt":
			if melt.lifted:
				melt.stop()
				_finish_melt()
			else:
				_abandon()
		"result":
			_show_yard()


func _abandon() -> void:
	for lot in melt.unmelted_lots():
		ScrapYard.put_back(lot)
	melt = null
	_roar.stop()
	Shop.log_event("Put the scrap back in the bin.")
	_show_yard()


func buy(i: int) -> void:
	if ScrapYard.buy(i):
		Sfx.play(self, Sfx.register_chime(), -10.0)
	_show_yard()


## Takes every lot of `metal` from the bin onto the sorting tray.
func begin(metal: String) -> void:
	var lots := ScrapYard.take(metal)
	if lots.is_empty():
		return
	melt = Melt.of(lots)
	_lay_out_tray()
	magnet_on = false
	phase = "sort"
	_build_sort()


func toggle_magnet() -> void:
	magnet_on = not magnet_on
	Pad.hide_cursor(magnet_on)
	Sfx.play(self, Sfx.click(), -10.0)


func load_crucible() -> void:
	if phase != "sort":
		return
	magnet_on = false
	Pad.hide_cursor(false)
	melt.load_crucible()
	phase = "melt"
	Sfx.play(self, Sfx.safe_clunk(), -14.0)
	_build_melt()


func set_gas(v: float) -> void:
	if melt == null or melt.lifted:
		return
	melt.set_gas(snappedf(v, 0.01))
	if _live.has("gas_slider"):
		_live.gas_slider.set_value_no_signal(melt.gas)


func flux() -> void:
	if melt == null or melt.lifted or melt.done:
		return
	melt.add_flux()
	_flux_at = _time
	Sfx.play(self, SmelterSfx.fizz(), -8.0)


func _finish_melt() -> void:
	_roar.stop()
	pour_held = false
	assay = melt.result()
	if not assay.skull.is_empty():
		ScrapYard.put_back(assay.skull)
	if float(assay.fine) > 0.0:
		ScrapYard.sell_bar(assay.payout, assay.cost, melt.metal)
		_bar = SmelterArt.bar(melt.metal, assay.grams, assay.purity, assay.flaws, _rng.randi()).texture()
	else:
		_bar = null
	_result_at = _time
	phase = "result"
	get_tree().create_timer(COOL_SECONDS).timeout.connect(func():
		if is_inside_tree() and phase == "result":
			Sfx.play(self, SmelterSfx.quench(), -6.0)
			_puff(Vector2(SmelterArt.BUCKET.get_center().x, SmelterArt.BUCKET.position.y), 10)
			get_tree().create_timer(0.7).timeout.connect(func():
				if is_inside_tree():
					Sfx.play(self, SmelterSfx.punch(), -8.0)))
	_build_result()


# ---------------------------------------------------------------- sorting tray

## Spreads the lots' pieces and the steel hidden among them over the tray.
func _lay_out_tray() -> void:
	pieces.clear()
	var rng := RandomNumberGenerator.new()
	for lot in melt.lots:
		rng.seed = int(lot.seed)
		var count := clampi(roundi(float(lot.grams) / (45.0 if lot.metal == "XAG" else 3.5)), 5, 14)
		for n in count:
			pieces.append({"tex": SmelterArt.piece(lot.art, lot.metal, int(lot.seed) + n).texture(), "steel": false})
		for n in int(lot.steel):
			pieces.append({"tex": SmelterArt.piece(SmelterArt.steel_kind(lot.art), "", int(lot.seed) + 50 + n).texture(), "steel": true})
	var tray := Rect2(SmelterArt.TRAY).grow(-8)
	for p in pieces:
		var size := Vector2(p.tex.get_size())
		p.pos = Vector2(rng.randf_range(tray.position.x, tray.end.x - size.x), rng.randf_range(tray.position.y, tray.end.y - size.y)).round()
		p.pulled = false
		p.fly = 0.0
	# steel underneath the gold and silver, where it hides best
	pieces.sort_custom(func(a, b): return a.steel and not b.steel)


func _update_sort() -> void:
	if phase != "sort" or not magnet_on:
		return
	var m := _mouse()
	for p in pieces:
		if not p.steel or p.pulled:
			continue
		var centre: Vector2 = p.pos + Vector2(p.tex.get_size()) / 2.0
		if centre.distance_to(m) < MAGNET_REACH and melt.pull_steel():
			p.pulled = true
			p.fly = _time
			Sfx.play(self, Sfx.magnet_snap(), -6.0)


func _mouse() -> Vector2:
	return Pad.mouse_in(self)


# ---------------------------------------------------------------- particles

func _spawn_sparks(delta: float) -> void:
	if melt.lifted:
		var flow := melt.flow_rate()
		if flow > 0.0 and _rng.randf() < flow * 40.0 * delta:
			_sparks.append({"pos": IMPACT + Vector2(_rng.randf_range(-3, 3), 0), "vel": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-60, -20)),
				"life": _rng.randf_range(0.3, 0.7), "col": Color("#ffd070")})
		if flow > Melt.SPLASH_FLOW and _rng.randf() < (flow - Melt.SPLASH_FLOW) * 60.0 * delta:
			var at := IMPACT + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(4, 22))
			_beads.append({"pos": at.round(), "born": _time})
		return
	# the flame licks sparks up out of the port now and then
	if melt.gas > 0.3 and _rng.randf() < melt.gas * 3.0 * delta:
		var p := SmelterArt.PORT
		_sparks.append({"pos": Vector2(_rng.randf_range(p.position.x + 10, p.end.x - 10), p.position.y + 30),
			"vel": Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-40, -20)), "life": _rng.randf_range(0.4, 0.9), "col": Color("#ff9a3a")})


func _update_particles(delta: float) -> void:
	for s in _sparks:
		s.vel.y += 90.0 * delta
		s.pos += s.vel * delta
		s.life -= delta
	_sparks = _sparks.filter(func(s): return s.life > 0.0)
	for s in _steam:
		s.pos += s.vel * delta
		s.vel *= 0.97
		s.life -= delta
	_steam = _steam.filter(func(s): return s.life > 0.0)


func _puff(at: Vector2, count: int) -> void:
	for n in count:
		_steam.append({"pos": at + Vector2(_rng.randf_range(-8, 8), 0), "vel": Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-30, -14)),
			"life": _rng.randf_range(0.8, 1.6), "size": _rng.randi_range(2, 4)})


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(_room, Vector2.ZERO)
	_draw_pyrometer()
	_draw_furnace_glow()
	if melt == null or not melt.lifted:
		_draw_crucible_home()
	_draw_mould()
	if melt != null and melt.lifted and phase == "melt":
		_draw_crucible_pour()
	_draw_beads()
	_draw_inset()
	if phase == "sort":
		_draw_tray()
	if phase == "result":
		_draw_bar()
	for s in _sparks:
		draw_rect(Rect2(s.pos.floor(), Vector2.ONE), s.col if s.life > 0.2 else s.col.darkened(0.5))
	for s in _steam:
		var a: float = clampf(s.life, 0.0, 1.0) * 0.35
		draw_rect(Rect2(s.pos.floor(), Vector2(s.size, s.size)), Color(0.92, 0.92, 0.9, a))
	if phase == "sort" and magnet_on:
		_draw_magnet()


func _temp() -> float:
	return melt.temp if melt != null else Melt.AMBIENT


## The needle, the pour band in green on the dial's rim, and the LED readout.
func _draw_pyrometer() -> void:
	var c := SmelterArt.DIAL
	var r := SmelterArt.DIAL_R
	if melt != null and phase == "melt":
		var b := melt.band()
		var steps := 14
		for k in steps + 1:
			var deg := lerpf(b.x, b.y, float(k) / steps)
			var a := SmelterArt.dial_angle(deg)
			draw_rect(Rect2((c + Vector2.from_angle(a) * (r - 1.5)).floor(), Vector2.ONE * 2), Color("#3aa04a"))
		var hot := SmelterArt.dial_angle(melt.melting_point + Melt.FUME_FROM)
		for k in 6:
			var a := hot + k * 0.06
			draw_rect(Rect2((c + Vector2.from_angle(a) * (r - 1.5)).floor(), Vector2.ONE * 2), Color("#c0392b"))
	var t := _temp()
	var wobble := sin(_time * 23.0) * 0.01 if melt != null and melt.gas > 0.0 else 0.0
	var a := SmelterArt.dial_angle(t) + wobble
	var tip := c + Vector2.from_angle(a) * (r - 4.0)
	draw_line(c, tip, Color("#1a1a1a"), 1.0)
	draw_line(c + Vector2(1, 0), tip + Vector2(1, 0), Color("#c0392b"), 1.0)
	draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Color("#2a2a2a"))
	var col := Pal.LED
	if melt != null and phase == "melt":
		if t > melt.melting_point + Melt.FUME_FROM:
			col = Pal.BAD if fmod(_time, 0.4) < 0.25 else Pal.WARN
		elif not melt.in_band():
			col = Pal.WARN if t > melt.melting_point else Pal.LED
	_text("%4d" % roundi(t), Vector2(SmelterArt.LED.position) + Vector2(5, 4), col)


## The port glows with the furnace's heat and the gas flame roars through it.
func _draw_furnace_glow() -> void:
	var p := Rect2(SmelterArt.PORT)
	var t := _temp()
	var gas := melt.gas if melt != null and not melt.lifted and phase == "melt" else 0.0
	var heat := clampf((t - 300.0) / 1100.0, 0.0, 1.0)
	if heat > 0.0:
		var glow := SmelterArt.glow(maxf(t, 600.0), Color("#3a2418"))
		var centre := p.get_center() + Vector2(0, 14)
		for k in 5:
			var rr := (5 - k) * 8.0
			var rect := Rect2(centre - Vector2(rr, rr * 0.9), Vector2(rr * 2.0, rr * 1.8)).intersection(p.grow(-2))
			draw_rect(rect, Color(glow, 0.08 + heat * 0.1))
		# the glow spills out onto the hearth and the wall round the port
		draw_rect(Rect2(p.position.x - 8, p.end.y + 6, p.size.x + 16, 6), Color(glow, heat * 0.12))
	# the burner's flame: tongues from the right, blue at the nozzle, orange at the tips
	if gas > 0.0:
		var nozzle := Vector2(p.end.x - 2, SmelterArt.BURNER_Y - 2)
		var length := 10.0 + gas * 40.0
		for n in 28:
			var u := float(n) / 27.0
			var flick := sin(_time * 31.0 + n * 1.7) * 0.5 + sin(_time * 17.0 + n * 0.9) * 0.5
			var at := nozzle + Vector2(-u * length, sin(u * 5.0 + _time * 20.0) * 2.0 * u - u * u * 10.0 * gas)
			var w := 1.0 + (1.0 - u) * 2.5 * gas + flick
			var col := Color("#4a7aff").lerp(Color("#ffb040"), clampf(u * 1.6, 0.0, 1.0))
			col.a = (1.0 - u) * 0.85
			draw_rect(Rect2(at.floor() - Vector2(0, roundf(w / 2.0)), Vector2(2, maxf(1.0, roundf(w)))), col)
	elif melt != null and phase == "melt" and not melt.lifted:
		# the pilot light
		var pilot := Vector2(p.end.x - 3, SmelterArt.BURNER_Y - 3)
		draw_rect(Rect2(pilot, Vector2(2, 2)), Color("#4a7aff", 0.6 + 0.3 * sin(_time * 9.0)))


## The crucible on its plinth, glowing with the heat, and the charge inside its mouth.
func _draw_crucible_home() -> void:
	var base := SmelterArt.CRUCIBLE_HOME
	var size := Vector2(_crucible.get_size())
	var at := base - Vector2(size.x / 2.0, size.y)
	draw_texture(_crucible, at)
	var t := _temp()
	if t > 500.0:
		var g := SmelterArt.glow(t, Color.BLACK)
		draw_texture(_crucible, at, Color(g, clampf((t - 500.0) / 900.0, 0.0, 0.7)))
	if melt == null or phase == "yard":
		return
	_draw_charge(base + SmelterArt.mouth_offset())


## What's in the crucible, seen in its mouth: lumps of scrap slumping into a pool that
## glows with the heat, scum on top until the borax clears it, then a mirror.
func _draw_charge(mouth: Vector2) -> void:
	var r := SmelterArt.mouth_radius()
	var pal := "gold" if melt.metal == "XAU" else "silver"
	var t := melt.temp
	var hot := SmelterArt.glow(t, Pal.metal(pal, 3))
	var pool_r := r.x * sqrt(melt.molten)
	for y in range(-int(r.y), int(r.y) + 1):
		for x in range(-int(r.x), int(r.x) + 1):
			var e := Vector2(x / r.x, y / r.y)
			if e.length() > 1.0:
				continue
			var p := mouth + Vector2(x, y)
			var in_pool := Vector2(x, y * r.x / r.y).length() <= pool_r
			var col: Color
			if in_pool:
				# a liquid surface: shimmer, a highlight that wanders, ripples
				var shimmer := sin(_time * 4.0 + x * 0.7) * 0.5 + sin(_time * 3.1 - y * 1.3 + x * 0.3) * 0.5
				col = hot.lightened(0.08 * shimmer)
				if absf(x + sin(_time * 1.3) * 4.0 - 4.0) < 2.0 and y < 0:
					col = col.lightened(0.25)
				var scum := _scum_at(x, y)
				if scum > 0.0:
					col = col.lerp(Color("#2e3328"), scum)
				if melt.slag > 0.05 and ShopArt._noise(x + roundi(_time * 3.0), y + 40) < melt.slag * 0.5:
					col = col.lerp(Color("#c8a050"), 0.5) # glassy slag, amber and bubbly
			else:
				# solid scrap: lumps in the metal's colours, heating through red
				var n := ShopArt._noise(x + 300, y * 3 + melt.lots.size())
				col = Pal.metal(pal, 2 + int(n * 3.0))
				if melt.steel > 0 and n < 0.08:
					col = Pal.metal("steel", 2)
				if t > 500.0:
					col = col.lerp(hot, clampf((t - 500.0) / 500.0, 0.0, 0.85))
			draw_rect(Rect2(p.floor(), Vector2.ONE), col)
	if _time - _flux_at < 0.6:
		# borax crystals bursting into a fizz
		for k in 6:
			var a := k * 1.1 + _time * 6.0
			draw_rect(Rect2((mouth + Vector2(cos(a) * 6.0, sin(a) * 1.5) + Vector2(0, -(_time - _flux_at) * 8.0)).floor(), Vector2.ONE), Color("#f4f4ec"))


## The close-up down into the crucible: scrap slumping into a pool that ripples and
## glows, scum crusts drifting on it until the borax clears them, amber slag, steel
## lumps that never melt, and at the end a clean mirror with the hood shining in it.
func _draw_inset() -> void:
	var r := Rect2(SmelterArt.INSET)
	var half := r.size / 2.0
	var rad := half - Vector2(1, 1)
	var live := melt != null and phase == "melt" and not melt.lifted
	if melt != null and melt.lifted:
		return # the crucible is out of the furnace
	var pal := "gold" if melt == null or melt.metal == "XAU" else "silver"
	var t := _temp() if live else Melt.AMBIENT
	var hot := SmelterArt.glow(t, Pal.metal(pal, 3))
	var wall := SmelterArt.glow(t, Color("#3a3a40")).darkened(0.2)
	var pool := sqrt(melt.molten) * 0.86 if live else 0.0
	var spin := _time * 0.12
	var dross := melt.dross if live else 0.0
	var slag := minf(melt.slag, 1.0) if live else 0.0
	var steel := melt.steel if live else 0
	var clean := live and melt.molten >= 1.0 and dross < 0.01
	for y in int(r.size.y):
		for x in int(r.size.x):
			var e := Vector2((x + 0.5 - half.x) / rad.x, (y + 0.5 - half.y) / rad.y)
			var d := e.length()
			if d > 1.0:
				continue
			var col: Color
			if d > 0.88:
				# the crucible's inner wall, lit from the top left
				col = wall.lightened(0.15) if e.x + e.y < -0.3 else wall
				if d > 0.97:
					col = wall.darkened(0.4)
			elif not live:
				col = Color("#141012") if melt == null else Pal.metal(pal, 1 + int(ShopArt._noise(x / 3, y / 3) * 4.0))
			elif d <= pool:
				var ring := sin(d * 24.0 - _time * 3.0) * 0.5 + 0.5
				col = hot.lightened(0.05 * ring)
				var rot := e.rotated(spin)
				# the hood and the lamp shining in the surface
				var shine := 1.0 - clampf(absf(e.y + 0.38) / 0.16, 0.0, 1.0)
				if absf(e.x + 0.15) < 0.45 and shine > 0.0:
					col = col.lightened(shine * (0.45 if clean else 0.18))
				if clean and absf(e.x - 0.2 + sin(_time) * 0.1) < 0.05 and absf(e.y + 0.4) < 0.08:
					col = Color("#fffbe8")
				var crust := ShopArt._noise(int(floor((rot.x + 1.0) * 11.0)), int(floor((rot.y + 1.0) * 8.0)) + 50)
				if crust < dross * 0.9:
					var edge := ShopArt._noise(x, y) > 0.7
					col = Color("#3a3f30").lerp(hot, 0.15) if not edge else Color("#5a5a40")
				if slag > 0.0:
					var glass := ShopArt._noise(int(floor((rot.x + 1.0) * 7.0)) + 20, int(floor((rot.y + 1.0) * 5.0)))
					if glass < slag * 0.7:
						col = col.lerp(Color("#d0a040"), 0.5)
						if ShopArt._noise(x + roundi(_time * 4.0), y) > 0.93:
							col = Color("#ffe8a0") # a bubble
				if steel > 0:
					var lump := ShopArt._noise(int(floor((rot.x + 1.0) * 6.0)) + 70, int(floor((rot.y + 1.0) * 4.0)))
					if lump < steel * 0.04:
						col = Pal.metal("steel", 1 if ShopArt._noise(x, y) > 0.5 else 2)
			else:
				# scrap not melted yet: lumps in the metal's colours, heating through
				var n := ShopArt._noise(x / 3 + 200, y / 3)
				col = Pal.metal(pal, 1 + int(n * 4.0))
				if steel > 0 and ShopArt._noise(x / 4 + 70, y / 4) < steel * 0.03:
					col = Pal.metal("steel", 2)
				if t > 500.0:
					col = col.lerp(hot.darkened(0.2), clampf((t - 500.0) / 500.0, 0.0, 0.8))
				# the edge of the pool, where lumps are slumping in
				if d < pool + 0.06:
					col = col.lerp(hot, 0.5)
			draw_rect(Rect2(r.position + Vector2(x, y), Vector2.ONE), col)


## How much scum covers the melt at (x, y) in the mouth, 0 to 1: blotches whose share
## follows the dross left, drifting slowly.
func _scum_at(x: int, y: int) -> float:
	if melt.dross <= 0.01:
		return 0.0
	var n := ShopArt._noise((x + roundi(_time * 2.0)) / 2, y + 7)
	return 0.85 if n < melt.dross * 0.85 else 0.0


## Lifted out with the tongs and tilted over the mould, pouring.
func _draw_crucible_pour() -> void:
	var angle := melt.tilt * TILT_ANGLE
	var pal := "gold" if melt.metal == "XAU" else "silver"
	var hot := SmelterArt.glow(melt.temp, Pal.metal(pal, 3))
	# the tongs come in from the top right
	var grip := POUR_PIVOT + Vector2(-18, 18).rotated(angle)
	draw_line(Vector2(310, 60), grip + Vector2(-2, -6).rotated(angle), SmelterArt.IRON, 2.0)
	draw_line(Vector2(312, 66), grip + Vector2(2, 6).rotated(angle), SmelterArt.IRON.lightened(0.2), 2.0)
	draw_set_transform(POUR_PIVOT, angle)
	draw_texture(_crucible, -LIP_CORNER)
	draw_texture(_crucible, -LIP_CORNER, Color(SmelterArt.glow(melt.temp, Color.BLACK), clampf((melt.temp - 500.0) / 900.0, 0.0, 0.6)))
	# the melt showing at the mouth as it tips
	var mouth := -LIP_CORNER + Vector2(SmelterArt.CRUCIBLE_SIZE.x / 2.0, 3)
	var left := clampf(melt.molten - melt.poured, 0.0, 1.0)
	if left > 0.0:
		draw_rect(Rect2(mouth + Vector2(-12, -1), Vector2(24.0 * clampf(melt.tilt * 1.5, 0.2, 1.0), 2)), hot)
	draw_set_transform(Vector2.ZERO, 0.0)
	var flow := melt.flow_rate()
	if flow <= 0.0:
		return
	# the stream: wider with more flow, wobbling as it falls
	var w := clampf(1.0 + flow * 5.0, 1.0, 4.0)
	var top := POUR_PIVOT + Vector2(1, 1)
	for y in range(int(top.y), int(IMPACT.y)):
		var u := (y - top.y) / (IMPACT.y - top.y)
		var x := lerpf(top.x, IMPACT.x, u) + sin(y * 0.6 + _time * 25.0) * 0.6 * u
		var col := hot.lightened(0.15 if (y + int(_time * 40.0)) % 5 == 0 else 0.0)
		draw_rect(Rect2(roundf(x - w / 2.0), y, roundf(w), 1), col)


## The ingot mould filling: a pool spreading from where the stream lands, then the bar
## cooling from bright to its own colour.
func _draw_mould() -> void:
	if melt == null or melt.poured <= 0.0:
		return
	var k := Rect2(SmelterArt.CAVITY)
	var pal := "gold" if melt.metal == "XAU" else "silver"
	var temp := melt.temp
	if phase == "result":
		temp = lerpf(melt.temp, Melt.AMBIENT, clampf((_time - _result_at) / COOL_SECONDS, 0.0, 1.0))
		if _time - _result_at > COOL_SECONDS:
			return # knocked out and quenched
	var spread := sqrt(clampf(melt.poured, 0.0, 1.0))
	var col := SmelterArt.glow(temp, Pal.metal(pal, 3))
	for y in range(int(k.position.y) + 1, int(k.end.y)):
		var tt := float(y - k.position.y) / k.size.y
		var inset := roundi(tt * 4.0) + 1
		for x in range(int(k.position.x) + inset, int(k.end.x) - inset):
			var d := Vector2((x - IMPACT.x) / (k.size.x * 0.6), (y - IMPACT.y) / (k.size.y * 0.7)).length()
			if d > spread * 1.15:
				continue
			var c := col
			if d > spread:
				c = c.darkened(0.3)
			if ShopArt._noise(x + roundi(_time * 6.0), y) > 0.9 and temp > 600.0:
				c = c.lightened(0.15)
			draw_rect(Rect2(x, y, 1, 1), c)


func _draw_beads() -> void:
	var pal := "gold" if melt != null and melt.metal == "XAU" else "silver"
	for b in _beads:
		var age: float = _time - b.born
		var col := SmelterArt.glow(lerpf(1100.0, 20.0, clampf(age / 2.0, 0.0, 1.0)), Pal.metal(pal, 4))
		draw_rect(Rect2(b.pos, Vector2.ONE), col)


func _draw_tray() -> void:
	var t := Rect2(SmelterArt.TRAY)
	draw_rect(Rect2(t.position + Vector2(3, 4), t.size), Color(0, 0, 0, 0.35))
	draw_rect(t, Color("#5b616b"))
	draw_rect(t.grow(-2), Color("#4a5058"))
	draw_rect(Rect2(t.position, Vector2(t.size.x, 1)), Color("#a0a7b1"))
	draw_rect(Rect2(t.position.x, t.end.y - 1, t.size.x, 1), Color("#2a2e34"))
	for p in pieces:
		var at: Vector2 = p.pos
		if p.pulled:
			var u := clampf((_time - p.fly) / 0.25, 0.0, 1.0)
			at = at.lerp(_mouse() - Vector2(p.tex.get_size()) / 2.0 + Vector2(0, 8), u)
			if u >= 1.0:
				continue
		draw_texture(p.tex, at + Vector2(1, 1), Color(0, 0, 0, 0.4))
		draw_texture(p.tex, at)


## A red horseshoe magnet on the pointer, with what it has picked up hanging off it.
func _draw_magnet() -> void:
	var m := _mouse().floor()
	draw_rect(Rect2(m + Vector2(-6, -12), Vector2(12, 10)), Color("#c0392b"))
	draw_rect(Rect2(m + Vector2(-3, -12), Vector2(6, 7)), Color(0, 0, 0, 0))
	draw_rect(Rect2(m + Vector2(-3, -9), Vector2(6, 7)), Color("#4a5058") if Rect2(SmelterArt.TRAY).has_point(m) else Color("#2a1a14"))
	draw_rect(Rect2(m + Vector2(-6, -12), Vector2(12, 1)), Color("#e66b5c"))
	draw_rect(Rect2(m + Vector2(-6, -3), Vector2(3, 3)), Color("#c6ccd4"))
	draw_rect(Rect2(m + Vector2(3, -3), Vector2(3, 3)), Color("#c6ccd4"))
	var hung := 0
	for p in pieces:
		if p.pulled and _time - p.fly >= 0.25:
			draw_texture(p.tex, m + Vector2(-4 + hung * 3, 0))
			hung += 1


## The finished bar on the hearth, cooling then shining, with steam off it.
func _draw_bar() -> void:
	if _bar == null:
		return
	var age := _time - _result_at
	if age < COOL_SECONDS:
		return
	var size := Vector2(_bar.get_size())
	var at := Vector2(104, 226) - size / 2.0
	draw_texture(_bar, at + Vector2(2, 3), Color(0, 0, 0, 0.4))
	draw_texture(_bar, at.round())
	# a glint sweeping across once it's out of the bucket
	var sweep := fmod(age - COOL_SECONDS, 3.0) / 0.8
	if sweep < 1.0:
		var gx := at.x + sweep * size.x
		for y in range(int(at.y), int(at.y + size.y - 4)):
			draw_rect(Rect2(gx + (y - at.y) * 0.4, y, 2, 1), Color(1, 1, 1, 0.35))


func _text(text: String, at: Vector2, col: Color) -> void:
	PixelFont.plot_text(text, func(x, y): draw_rect(Rect2(at.x + x, at.y + y, 1, 1), col))


# ---------------------------------------------------------------- the panel

func _clear() -> void:
	for n in _ui.get_children():
		n.queue_free()
	_live.clear()


func _show_yard() -> void:
	phase = "yard"
	melt = null
	assay = {}
	_beads.clear()
	pour_held = false
	magnet_on = false
	Pad.hide_cursor(false)
	_build_yard()


func _build_yard() -> void:
	_clear()
	var x := PANEL_X + 4
	_label("SMELTER", Vector2(x, 4), Pal.INK_FAINT)
	_label("Scrap dealer", Vector2(x, 13), Pal.GOLD)
	var y := 24
	if ScrapYard.offers.is_empty():
		_label("Sold out. Back tomorrow morning.", Vector2(x, y), Pal.INK_DIM, 156)
		y += 12
	for i in ScrapYard.offers.size():
		var lot: Dictionary = ScrapYard.offers[i]
		_label(lot.name, Vector2(x, y), Pal.INK, 156)
		_label("%s g, stamped %s" % [ScrapYard._grams(ScrapYard.gross(lot)), lot.stamp], Vector2(x, y + 8), Pal.INK_DIM, 156)
		_label(Market.format_money(lot.cost), Vector2(x, y + 16), Pal.GOLD, 100)
		var b := _button("Buy", Rect2(x + 118, y + 14, 38, 11), "PrimaryButton", buy.bind(i))
		b.disabled = not ScrapYard.can_buy(i)
		b.tooltip_text = "Melt value as stamped: %s" % Market.format_money(ScrapYard.claimed_value(lot))
		y += 27
	y = maxi(y + 2, 112)
	_label("SCRAP BIN", Vector2(x, y), Pal.INK_FAINT)
	y += 10
	for metal in ["XAU", "XAG"]:
		var lots := ScrapYard.lots_of(metal)
		var grams := 0.0
		for lot in lots:
			grams += ScrapYard.gross(lot)
		var name := "Gold" if metal == "XAU" else "Silver"
		_label(name, Vector2(x, y), Pal.INK)
		_label("%d lot%s, %s g" % [lots.size(), "" if lots.size() == 1 else "s", ScrapYard._grams(grams)] if not lots.is_empty() else "empty",
			Vector2(x + 30, y), Pal.INK_DIM, 84)
		var b := _button("Melt", Rect2(x + 118, y - 2, 38, 11), "Button", begin.bind(metal))
		b.disabled = lots.is_empty()
		y += 13
	y += 4
	_label("The bullion dealer buys your bars at %d%% of spot for the fine metal the assay finds." % roundi(ScrapYard.cast_share() * 100.0),
		Vector2(x, y), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 26)
	if ScrapYard.bars_cast > 0:
		_label("Bars cast: %d. Profit so far: %s" % [ScrapYard.bars_cast, Market.format_money(ScrapYard.lifetime)],
			Vector2(x, y + 30), Pal.GOOD if ScrapYard.lifetime >= 0.0 else Pal.BAD, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_button("Back to the morning", Rect2(x, 240, 156, 13), "Button", func(): finished.emit())
	_label("Esc: back", Vector2(x, 256), Pal.INK_FAINT)


func _build_sort() -> void:
	_clear()
	var x := PANEL_X + 4
	_label("SORT THE SCRAP", Vector2(x, 4), Pal.INK_FAINT)
	var y := 14
	for lot in melt.lots.slice(0, 4):
		_label(lot.name, Vector2(x, y), Pal.GOLD, 156)
		y += 9
	if melt.lots.size() > 4:
		_label("and %d more" % (melt.lots.size() - 4), Vector2(x, y), Pal.INK_DIM)
		y += 9
	_label("%s g in all" % ScrapYard._grams(melt.grams + melt.steel_g), Vector2(x, y), Pal.INK_DIM)
	y += 14
	_label("Clasp springs, knife blades and candlestick rods are steel. Steel doesn't melt at these heats: it spoils the bar. Sweep the magnet over the tray to pull it out.",
		Vector2(x, y), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 58)
	_live.pulled = _label("", Vector2(x, 150), Pal.INK, 156)
	var m := _button("1 Magnet", Rect2(x, 166, 76, 12), "ToolButton", toggle_magnet)
	m.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button("Load the crucible", Rect2(x, 222, 156, 13), "PrimaryButton", load_crucible)
	_label("Esc: put it back in the bin", Vector2(x, 256), Pal.INK_FAINT)


func _build_melt() -> void:
	_clear()
	var x := PANEL_X + 4
	var metal_name := "gold" if melt.metal == "XAU" else "silver"
	_label("MELT", Vector2(x, 4), Pal.INK_FAINT)
	_label("%s g of scrap %s" % [ScrapYard._grams(melt.grams + melt.steel_g), metal_name], Vector2(x, 13), Pal.GOLD, 156)
	var b := melt.band()
	var rows := [["Melts at", "about %d C" % (roundi(melt.melting_point / 10.0) * 10)],
		["Pour at", "%d-%d C" % [roundi(b.x / 10.0) * 10, roundi(b.y / 10.0) * 10]],
		["Fumes above", "%d C" % (roundi((melt.melting_point + Melt.FUME_FROM) / 10.0) * 10)]]
	for n in rows.size():
		_label(rows[n][0], Vector2(x, 26 + n * 9), Pal.INK_DIM)
		_label(rows[n][1], Vector2(x + 60, 26 + n * 9), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Furnace", Vector2(x, 56), Pal.INK_DIM)
	_live.temp = _label("", Vector2(x + 60, 56), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Molten", Vector2(x, 65), Pal.INK_DIM)
	_live.molten = _label("", Vector2(x + 60, 65), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Poured", Vector2(x, 74), Pal.INK_DIM)
	_live.poured = _label("", Vector2(x + 60, 74), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("GAS", Vector2(x, 90), Pal.INK_FAINT)
	_button("-", Rect2(x + 22, 88, 11, 11), "Button", func(): set_gas(melt.gas - GAS_STEP))
	var slider := HSlider.new()
	_ui.add_child(slider)
	slider.position = Vector2(x + 36, 89)
	slider.size = Vector2(106, 9)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v): set_gas(v))
	_live.gas_slider = slider
	_button("+", Rect2(x + 145, 88, 11, 11), "Button", func(): set_gas(melt.gas + GAS_STEP))
	var f := _button("F  Borax", Rect2(x, 106, 76, 12), "ToolButton", flux)
	f.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_live.flux = f
	var pour := _button("Hold to pour", Rect2(x + 80, 106, 76, 12), "PrimaryButton", func(): pass)
	pour.button_down.connect(func(): pour_held = true)
	pour.button_up.connect(func(): pour_held = false)
	pour.tooltip_text = "Hold the button, or Space"
	_live.pour = pour
	_label("Up/Down or W/S set the gas. Bring the furnace into the pour band and hold it there till all of it melts. Drop borax until the scum is gone and the melt shines; too much makes glassy slag that traps metal. Then hold Space to pour: steady, not too fast, and before it cools.",
		Vector2(x, 124), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 104)
	_live.hint = _label("", Vector2(x, 232), Pal.WARN, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_label("Esc: stop", Vector2(x, 256), Pal.INK_FAINT)


func _build_result() -> void:
	_clear()
	var x := PANEL_X + 4
	var metal_name := "gold" if melt.metal == "XAU" else "silver"
	_label("ASSAY", Vector2(x, 4), Pal.INK_FAINT)
	var y := 14
	if float(assay.fine) <= 0.0:
		_label("Nothing made it into the mould. The scrap is back in the bin.", Vector2(x, y), Pal.WARN, 156, HORIZONTAL_ALIGNMENT_LEFT, 26)
	else:
		_label("Cast %s bar" % metal_name, Vector2(x, y), Pal.GOLD)
		y += 12
		var rows := [["Weight", "%.2f g" % assay.grams], ["Fineness", "%.1f" % (assay.purity * 1000.0)],
			["Fine %s" % metal_name, "%.2f g" % assay.fine], ["Recovered", "%.1f%%" % (assay.recovery * 100.0)],
			["Stamps said", "%.1f g fine" % (melt.claimed_fine * clampf(melt.poured, 0.0, 1.0))]]
		for row in rows:
			_label(row[0], Vector2(x, y), Pal.INK_DIM)
			_label(row[1], Vector2(x + 60, y), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
			y += 9
		y += 4
		var flaw_text := {"cold_shut": "Cold shut where the pour paused: -1%", "steel": "Steel in the bar: -3%",
			"inclusions": "Scum trapped in the bar: -1.5%"}
		for f in assay.flaws:
			_label(flaw_text[f], Vector2(x, y), Pal.BAD, 156)
			y += 9
		if assay.flaws.is_empty():
			_label("Clean bar, no flaws.", Vector2(x, y), Pal.GOOD)
			y += 9
		y += 4
		_label("Dealer pays", Vector2(x, y), Pal.INK_DIM)
		_label(Market.format_money(assay.payout), Vector2(x + 60, y), Pal.GOLD, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 9
		_label("Scrap cost", Vector2(x, y), Pal.INK_DIM)
		_label(Market.format_money(assay.cost), Vector2(x + 60, y), Pal.INK, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 9
		var profit: float = assay.payout - assay.cost
		_label("Profit" if profit >= 0.0 else "Loss", Vector2(x, y), Pal.INK_DIM)
		_label(Market.format_money(absf(profit)), Vector2(x + 60, y), Pal.GOOD if profit >= 0.0 else Pal.BAD, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 13
		_label(_verdict(), Vector2(x, y), Pal.INK_DIM, 156, HORIZONTAL_ALIGNMENT_LEFT, 44)
	if not assay.skull.is_empty():
		_label("%s g froze in the crucible. It's back in the bin." % ScrapYard._grams(float(assay.skull.grams)),
			Vector2(x, 214), Pal.WARN, 156, HORIZONTAL_ALIGNMENT_LEFT, 18)
	_button("Done", Rect2(x, 236, 156, 13), "PrimaryButton", _show_yard)


## A line on how the melt went: the biggest loss, or praise.
func _verdict() -> String:
	var losses := {"fumes": melt.fumed, "splash": melt.splashed,
		"scum": melt.fine * melt.dross * Melt.DROSS_LOSS, "slag": melt.fine * minf(melt.slag, 1.0) * Melt.SLAG_LOSS}
	var worst := ""
	for k in losses:
		if worst == "" or losses[k] > losses[worst]:
			worst = k
	if float(assay.recovery) >= 0.985 and assay.flaws.is_empty():
		return "A textbook melt. The dealer asked who taught you."
	if melt.purity() < melt.claimed_fine / maxf(melt.grams + melt.steel_g, 0.001) * 0.9:
		return "The assay came in well under the stamps: that lot was salted with plated junk."
	return {"fumes": "Too hot: metal fumed away up the hood. Keep it in the band.",
		"splash": "Poured too fast: beads splashed over the hearth.",
		"scum": "Scum left on the melt ended up in the bar. More borax next time.",
		"slag": "Too much borax: the glassy slag kept beads of metal."}[worst]


func _refresh_live() -> void:
	if phase == "sort" and _live.has("pulled"):
		_live.pulled.text = "Steel pulled out: %d" % melt.steel_pulled
	if phase != "melt" or melt == null or not _live.has("temp"):
		return
	_live.temp.text = "%d C" % roundi(melt.temp)
	var hot := melt.temp > melt.melting_point + Melt.FUME_FROM
	_live.temp.add_theme_color_override("font_color", Pal.BAD if hot else (Pal.GOOD if melt.in_band() else Pal.INK))
	_live.molten.text = "%d%%" % roundi(melt.molten * 100.0)
	_live.poured.text = "%d%%" % roundi(melt.poured * 100.0) if melt.lifted else "-"
	_live.flux.disabled = melt.lifted
	_live.pour.disabled = melt.molten <= 0.0
	var hint := ""
	if hot:
		hint = "Too hot! Metal is fuming away."
	elif melt.lifted and melt.temp < melt.melting_point + 25.0:
		hint = "It's cooling fast. Pour!"
	elif melt.flow_rate() > Melt.SPLASH_FLOW:
		hint = "Splashing! Ease off."
	_live.hint.text = hint


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
	Pad.hide_cursor(false)
	# walking out mid-melt leaves the scrap in the bin, not lost
	if melt == null or not phase in ["sort", "melt"]:
		return
	if not melt.lifted:
		for lot in melt.unmelted_lots():
			ScrapYard.put_back(lot)
	else:
		# mid-pour: what's in the mould is a bar, the rest freezes in the crucible
		melt.stop()
		var r := melt.result()
		if not r.skull.is_empty():
			ScrapYard.put_back(r.skull)
		if float(r.fine) > 0.0:
			ScrapYard.sell_bar(r.payout, r.cost, melt.metal)
	melt = null
