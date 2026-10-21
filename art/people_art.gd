class_name PeopleArt
extends RefCounted
## 16x28 character sprites with outline and two-tone shading, front and back, with a
## four-step walk, a blink and a few moods. A look is a Dictionary; random_look() makes a varied customer.

const W := 16
const H := 28
const OUTLINE := Color("#1a1410")
const SKINS := ["#f2cfa8", "#e3b48a", "#c98f62", "#a06a42", "#7a4a2c", "#5a3520"]
const HAIRS := ["#2a1a10", "#5a3418", "#8a5228", "#c8964a", "#e2cc8a", "#8c8c8c", "#d8d8d0", "#1a1a1a", "#a0401c"]
const SHIRTS := ["#3f7cc0", "#b8473a", "#4f9a5c", "#8a5bb0", "#d08a2c", "#2f8f8f", "#c0507a", "#556070", "#d9c27a", "#30406a"]
const PANTS := ["#2f3442", "#3b4a6b", "#4a3a2a", "#5a5f6a", "#1f1f24", "#6b5a40"]


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"skin": SKINS[rng.randi() % SKINS.size()],
		"hair": HAIRS[rng.randi() % HAIRS.size()],
		"hair_style": rng.randi() % 5, # 0 short, 1 long, 2 bald, 3 bun, 4 curly
		"shirt": SHIRTS[rng.randi() % SHIRTS.size()],
		"top": rng.randi() % 3, # 0 tee, 1 jacket, 2 hoodie
		"pants": PANTS[rng.randi() % PANTS.size()],
		"glasses": rng.randf() < 0.25,
		"beard": rng.randf() < 0.2,
		"hat": rng.randf() < 0.15,
		"apron": false,
	}


static func keeper_look() -> Dictionary:
	return {
		"skin": "#e3b48a", "hair": "#4a3220", "hair_style": 0, "shirt": "#2f6b63", "top": 0,
		"pants": "#2f3442", "glasses": false, "beard": false, "hat": false, "apron": true, "visor": true,
	}


## Animation frames. A walk is four steps; BACK and BACK_WALK are seen from behind,
## for someone walking away up the screen.
const STAND := 0
const WALK: Array[int] = [1, 2, 3, 4]
const BLINK := 5
const CROSS := 6 # arms folded, frowning: out of patience
const TAP := 7 # the same, tapping a foot
const HAPPY := 8 # a wave and a smile after a good deal
const BACK := 9
const BACK_WALK: Array[int] = [10, 11, 12, 13]
const FRAMES := 14


static func paint(look: Dictionary, frame := STAND) -> PixelCanvas:
	var c := PixelCanvas.new(W, H)
	var skin := Color(look.skin)
	var hair := Color(look.hair)
	var shirt := Color(look.shirt)
	var pants := Color(look.pants)
	var back := frame >= BACK
	# step: 0 standing, 1 left foot forward, 2 passing, 3 right foot forward, 4 passing
	var step := 0
	if frame in WALK:
		step = WALK.find(frame) + 1
	elif frame in BACK_WALK:
		step = BACK_WALK.find(frame) + 1
	var y0 := 1 if step == 1 or step == 3 else 0 # the body dips as each foot lands

	_legs(c, pants, step, y0, frame == TAP)
	_torso(c, look, shirt, skin, y0, step, frame, back)
	if back:
		_head_back(c, look, skin, hair, y0)
	else:
		_head_front(c, look, skin, hair, y0, frame)
	_shade(c)
	_outline(c)
	return c


static func _legs(c: PixelCanvas, pants: Color, step: int, y0: int, tap: bool) -> void:
	var shoe := Color("#2a2018")
	var shoe_hi := Color("#5a4a3a")
	c.rect(5, 20 + y0, 6, 3 - y0, pants)
	# each leg: x, how far the foot is lifted
	var lift := [0, 0]
	match step:
		1: lift = [0, 2]
		2: lift = [0, 1]
		3: lift = [2, 0]
		4: lift = [1, 0]
	if tap:
		lift = [0, 1]
	for k in 2:
		var x := 5 if k == 0 else 9
		var up: int = lift[k]
		c.rect(x, 23, 2, 3 - up, pants)
		var sx := x - 1 if k == 0 else x
		c.rect(sx, 26 - up, 3, 2, shoe)
		c.px(sx + (0 if k == 0 else 2), 26 - up, shoe_hi)
	c.px(7, 22 + y0, pants.darkened(0.3))
	c.px(8, 22 + y0, pants.darkened(0.3))


static func _torso(c: PixelCanvas, look: Dictionary, shirt: Color, skin: Color, y0: int, step: int, frame: int, back: bool) -> void:
	c.rect(4, 12 + y0, 8, 8, shirt)
	# belt
	c.rect(4, 19 + y0, 8, 1, Color(look.pants).darkened(0.4))
	if not back:
		c.px(7, 19 + y0, Color("#c9a24a"))
	# arms: the arm opposite the forward foot swings forward (lower hand)
	var swing := [0, 0]
	match step:
		1: swing = [-1, 1]
		3: swing = [1, -1]
	if back:
		swing = [-swing[0], -swing[1]]
	if frame == CROSS or frame == TAP:
		c.rect(3, 13 + y0, 1, 4, shirt)
		c.rect(12, 13 + y0, 1, 4, shirt)
		c.rect(4, 16 + y0, 8, 2, shirt.darkened(0.12))
		c.rect(4, 16 + y0, 8, 1, shirt.lightened(0.1))
		c.px(4, 17 + y0, skin)
		c.px(11, 16 + y0, skin)
	elif frame == HAPPY:
		c.rect(3, 13 + y0, 1, 6, shirt)
		c.px(3, 19 + y0, skin)
		# right arm raised in a wave
		c.rect(12, 9 + y0, 1, 5, shirt)
		c.rect(13, 7 + y0, 1, 3, shirt)
		c.rect(13, 5 + y0, 2, 2, skin)
	else:
		for k in 2:
			var x := 3 if k == 0 else 12
			var len: int = 6 + swing[k]
			c.rect(x, 13 + y0, 1, len, shirt)
			c.px(x, 13 + y0 + len, skin)
	if back:
		c.rect(7, 13 + y0, 1, 6, shirt.darkened(0.12)) # back seam
		if int(look.top) == 2:
			c.rect(5, 11 + y0, 6, 3, shirt.darkened(0.18)) # hood down the back
			c.rect(6, 12 + y0, 4, 1, shirt.darkened(0.3))
		elif int(look.top) == 1:
			c.rect(5, 18 + y0, 6, 1, shirt.darkened(0.2)) # jacket hem
		if look.get("apron", false):
			c.rect(4, 17 + y0, 8, 1, Color("#d9c9a8")) # apron ties
			c.rect(7, 17 + y0, 2, 2, Color("#d9c9a8"))
		return
	match int(look.top):
		1: # jacket with lapels over a pale shirt
			c.rect(7, 12 + y0, 2, 7, Color("#e8e2d4"))
			c.px(6, 12 + y0, shirt.lightened(0.25))
			c.px(9, 12 + y0, shirt.lightened(0.25))
			c.px(6, 13 + y0, shirt.lightened(0.25))
			c.px(9, 13 + y0, shirt.lightened(0.25))
			c.px(8, 15 + y0, shirt.darkened(0.4))
			c.px(8, 17 + y0, shirt.darkened(0.4))
			c.px(5, 16 + y0, shirt.darkened(0.25)) # pocket flap
		2: # hoodie: hood collar, drawstrings and pocket
			c.rect(5, 11 + y0, 6, 1, shirt.darkened(0.15))
			c.rect(5, 17 + y0, 6, 2, shirt.darkened(0.12))
			c.px(6, 13 + y0, Color("#e8e2d4"))
			c.px(9, 13 + y0, Color("#e8e2d4"))
			c.px(6, 14 + y0, Color("#e8e2d4"))
		_:
			c.rect(6, 12 + y0, 4, 1, shirt.darkened(0.25))
			c.px(6, 15 + y0, shirt.darkened(0.1)) # a fold
	if look.get("apron", false):
		c.rect(5, 14 + y0, 6, 6, Color("#d9c9a8"))
		c.rect(5, 14 + y0, 6, 1, Color("#efe3c8"))
		c.rect(6, 17 + y0, 4, 1, Color("#bba98a"))
		c.px(9, 15 + y0, Pal.GOLD)
		c.px(6, 16 + y0, Color("#4a3a2a")) # pen in the pocket
	if look.get("chain", false):
		c.px(6, 12 + y0, Pal.GOLD)
		c.px(9, 12 + y0, Pal.GOLD)
		c.rect(7, 13 + y0, 2, 1, Pal.GOLD)
		c.px(7, 14 + y0, Color("#f6e08a"))


static func _head_front(c: PixelCanvas, look: Dictionary, skin: Color, hair: Color, y0: int, frame: int) -> void:
	c.rect(7, 11 + y0, 2, 1, skin.darkened(0.15))
	c.rect(5, 4 + y0, 6, 7, skin)
	c.rect(4, 6 + y0, 1, 3, skin)
	c.rect(11, 6 + y0, 1, 3, skin)
	var cross := frame == CROSS or frame == TAP
	if frame == BLINK:
		c.px(6, 7 + y0, skin.darkened(0.35))
		c.px(9, 7 + y0, skin.darkened(0.35))
	else:
		c.px(6, 7 + y0, OUTLINE)
		c.px(9, 7 + y0, OUTLINE)
		c.px(6, 8 + y0, skin.lightened(0.2)) # catchlight under the eye
		c.px(9, 8 + y0, skin.lightened(0.2))
	# brows: knitted when cross
	c.px(6, 6 + y0, hair.darkened(0.2))
	c.px(9, 6 + y0, hair.darkened(0.2))
	if cross:
		c.px(5, 5 + y0, hair.darkened(0.2))
		c.px(10, 5 + y0, hair.darkened(0.2))
	# nose shadow and mouth
	c.px(8, 8 + y0, skin.darkened(0.12))
	if cross:
		c.rect(7, 9 + y0, 2, 1, skin.darkened(0.35))
		c.px(6, 10 + y0, skin.darkened(0.3))
		c.px(9, 10 + y0, skin.darkened(0.3))
	elif frame == HAPPY:
		c.px(6, 9 + y0, skin.darkened(0.35))
		c.px(9, 9 + y0, skin.darkened(0.35))
		c.rect(7, 10 + y0, 2, 1, Color("#8a3a30"))
	else:
		c.rect(7, 9 + y0, 2, 1, skin.darkened(0.3))
	var blush := 0.45 if frame == HAPPY else 0.25
	c.px(5, 8 + y0, skin.lerp(Color("#e07060"), blush))
	c.px(10, 8 + y0, skin.lerp(Color("#e07060"), blush))
	if look.get("beard", false):
		c.rect(5, 9 + y0, 6, 2, hair)
		c.rect(7, 9 + y0, 2, 1, skin.darkened(0.35))
		c.px(6, 10 + y0, hair.lightened(0.15))
	if look.get("glasses", false):
		c.rect(5, 7 + y0, 2, 1, Color("#2a2a30"))
		c.rect(8, 7 + y0, 3, 1, Color("#2a2a30"))
		c.px(5, 6 + y0, Color("#9fd0e8"))
		c.px(9, 6 + y0, Color("#9fd0e8"))
	if look.get("shades", false):
		c.rect(5, 6 + y0, 6, 2, Color("#14141a"))
		c.px(7, 7 + y0, skin.darkened(0.2))
		c.px(8, 7 + y0, skin.darkened(0.2))
		c.px(5, 6 + y0, Color("#6a7aa0"))
		c.px(9, 6 + y0, Color("#6a7aa0"))
	_hair(c, look, skin, hair, y0)
	if look.get("visor", false):
		# jeweller's loupe pushed up on the forehead
		c.rect(5, 3 + y0, 6, 1, Color("#2a2a30"))
		c.rect(9, 2 + y0, 2, 2, Color("#2a2a30"))
		c.px(9, 2 + y0, Color("#9fd0e8"))


## The back of the head: hair over everything but the ears and the nape.
static func _head_back(c: PixelCanvas, look: Dictionary, skin: Color, hair: Color, y0: int) -> void:
	c.rect(7, 11 + y0, 2, 1, skin.darkened(0.2))
	c.rect(5, 4 + y0, 6, 7, skin.darkened(0.08))
	c.px(4, 7 + y0, skin)
	c.px(11, 7 + y0, skin)
	var style := int(look.hair_style)
	if style != 2:
		c.rect(5, 2 + y0, 6, 7 if style != 1 else 10, hair)
		c.rect(4, 3 + y0, 1, 3, hair)
		c.rect(11, 3 + y0, 1, 3, hair)
		c.rect(6, 9 + y0, 4, 1, hair.darkened(0.1))
		c.px(7, 4 + y0, hair.lightened(0.2)) # crown highlight
	else:
		c.rect(4, 6 + y0, 8, 3, hair)
		c.px(6, 4 + y0, skin.lightened(0.2))
	match style:
		1:
			c.rect(4, 6 + y0, 8, 6, hair)
			c.px(7, 8 + y0, hair.darkened(0.2))
		3:
			c.rect(6, 0 + y0, 4, 2, hair)
			c.px(7, 0 + y0, hair.lightened(0.2))
		4:
			for q in [Vector2i(4, 2), Vector2i(6, 1), Vector2i(8, 1), Vector2i(10, 2), Vector2i(3, 4), Vector2i(11, 4), Vector2i(3, 6), Vector2i(11, 6), Vector2i(5, 8), Vector2i(9, 8)]:
				c.rect(q.x, q.y + y0, 2, 2, hair)
	if look.get("hat", false):
		c.rect(4, 2 + y0, 8, 2, Color("#3a2e24"))
		c.rect(3, 4 + y0, 10, 1, Color("#3a2e24"))
		c.rect(4, 3 + y0, 8, 1, Color("#8a2e24"))
	if look.get("visor", false):
		c.rect(5, 3 + y0, 6, 1, Color("#2a2a30"))


static func _hair(c: PixelCanvas, look: Dictionary, skin: Color, hair: Color, y0: int) -> void:
	match int(look.hair_style):
		0:
			c.rect(5, 2 + y0, 6, 2, hair)
			c.rect(4, 3 + y0, 1, 3, hair)
			c.rect(11, 3 + y0, 1, 3, hair)
			c.rect(5, 4 + y0, 3, 1, hair)
			c.px(6, 2 + y0, hair.lightened(0.22))
		1:
			c.rect(5, 2 + y0, 6, 2, hair)
			c.rect(4, 3 + y0, 1, 9, hair)
			c.rect(11, 3 + y0, 1, 9, hair)
			c.rect(5, 4 + y0, 6, 1, hair)
			c.px(3, 10 + y0, hair)
			c.px(12, 10 + y0, hair)
			c.px(6, 2 + y0, hair.lightened(0.22))
			c.px(7, 2 + y0, hair.lightened(0.22))
		2:
			c.rect(4, 5 + y0, 1, 2, hair)
			c.rect(11, 5 + y0, 1, 2, hair)
			c.px(6, 4 + y0, skin.lightened(0.25))
		3:
			c.rect(5, 2 + y0, 6, 3, hair)
			c.rect(6, 0 + y0, 4, 2, hair)
			c.rect(4, 3 + y0, 1, 4, hair)
			c.rect(11, 3 + y0, 1, 4, hair)
			c.px(7, 0 + y0, hair.lightened(0.22))
		4:
			for q in [Vector2i(4, 2), Vector2i(6, 1), Vector2i(8, 1), Vector2i(10, 2), Vector2i(3, 4), Vector2i(11, 4), Vector2i(3, 6), Vector2i(11, 6)]:
				c.rect(q.x, q.y + y0, 2, 2, hair)
			c.rect(5, 3 + y0, 6, 1, hair)
			c.px(6, 1 + y0, hair.lightened(0.22))
	if look.get("hat", false):
		c.rect(4, 2 + y0, 8, 2, Color("#3a2e24"))
		c.rect(3, 4 + y0, 10, 1, Color("#3a2e24"))
		c.rect(4, 3 + y0, 8, 1, Color("#8a2e24"))


## Lights the left column of each part and darkens the right, for a rounded look.
static func _shade(c: PixelCanvas) -> void:
	var src := c.image.duplicate()
	for y in H:
		for x in W:
			var col: Color = src.get_pixel(x, y)
			if col.a == 0.0 or col == OUTLINE:
				continue
			var left: Color = src.get_pixel(x - 1, y) if x > 0 else Color(0, 0, 0, 0)
			var right: Color = src.get_pixel(x + 1, y) if x < W - 1 else Color(0, 0, 0, 0)
			if left.a == 0.0:
				c.image.set_pixel(x, y, col.lightened(0.12))
			elif right.a == 0.0 or x >= 10:
				c.image.set_pixel(x, y, col.darkened(0.14))


static func _outline(c: PixelCanvas) -> void:
	var src := c.image.duplicate()
	for y in H:
		for x in W:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < W and q.y < H and src.get_pixelv(q).a > 0.0:
					c.image.set_pixel(x, y, OUTLINE)
					break
