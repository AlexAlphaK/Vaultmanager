class_name PeopleArt
extends RefCounted
## Front-facing 16x28 character sprites with outline and two-tone shading.
## A look is a Dictionary; random_look() makes a varied customer.

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


## Frame 0 stands, frame 1 and 2 are walking steps.
static func paint(look: Dictionary, frame := 0) -> PixelCanvas:
	var c := PixelCanvas.new(W, H)
	var skin := Color(look.skin)
	var hair := Color(look.hair)
	var shirt := Color(look.shirt)
	var pants := Color(look.pants)
	var bob := 1 if frame > 0 else 0
	var y0 := bob

	# legs and shoes
	var shoe := Color("#2a2018")
	if frame == 0:
		c.rect(5, 20 + y0, 6, 4, pants)
		c.rect(5, 24, 2, 2, pants)
		c.rect(9, 24, 2, 2, pants)
		c.rect(4, 26, 3, 2, shoe)
		c.rect(9, 26, 3, 2, shoe)
	else:
		var s := 1 if frame == 1 else -1
		c.rect(5, 20 + y0, 6, 3, pants)
		c.rect(5 - s, 23, 2, 3, pants)
		c.rect(9 - s, 23, 2, 2, pants)
		c.rect(4 - s, 26, 3, 2, shoe)
		c.rect(9 - s, 25, 3, 2, shoe)
	c.px(7, 23 + y0 - (1 if frame == 0 else 0), pants.darkened(0.3))

	# torso and arms
	c.rect(4, 12 + y0, 8, 8, shirt)
	c.rect(3, 13 + y0, 1, 6, shirt)
	c.rect(12, 13 + y0, 1, 6, shirt)
	var swing := 0 if frame == 0 else (1 if frame == 1 else -1)
	c.rect(3, 19 + y0 + swing, 1, 1, skin)
	c.rect(12, 19 + y0 - swing, 1, 1, skin)
	match int(look.top):
		1: # jacket with lapels over a pale shirt
			c.rect(7, 12 + y0, 2, 7, Color("#e8e2d4"))
			c.px(6, 12 + y0, shirt.lightened(0.25))
			c.px(9, 12 + y0, shirt.lightened(0.25))
			c.px(6, 13 + y0, shirt.lightened(0.25))
			c.px(9, 13 + y0, shirt.lightened(0.25))
			c.px(8, 15 + y0, shirt.darkened(0.4))
			c.px(8, 17 + y0, shirt.darkened(0.4))
		2: # hoodie: hood collar and pocket
			c.rect(5, 11 + y0, 6, 1, shirt.darkened(0.15))
			c.rect(5, 17 + y0, 6, 2, shirt.darkened(0.12))
			c.px(6, 13 + y0, Color("#e8e2d4"))
			c.px(9, 13 + y0, Color("#e8e2d4"))
		_:
			c.rect(6, 12 + y0, 4, 1, shirt.darkened(0.25))
	if look.get("apron", false):
		c.rect(5, 14 + y0, 6, 7, Color("#d9c9a8"))
		c.rect(5, 14 + y0, 6, 1, Color("#efe3c8"))
		c.rect(6, 17 + y0, 4, 1, Color("#bba98a"))
		c.px(9, 15 + y0, Pal.GOLD)

	# head
	c.rect(7, 11 + y0, 2, 1, skin.darkened(0.15))
	c.rect(5, 4 + y0, 6, 7, skin)
	c.rect(4, 6 + y0, 1, 3, skin)
	c.rect(11, 6 + y0, 1, 3, skin)
	c.px(6, 7 + y0, OUTLINE)
	c.px(9, 7 + y0, OUTLINE)
	c.px(6, 6 + y0, hair.darkened(0.2))
	c.px(9, 6 + y0, hair.darkened(0.2))
	c.rect(7, 9 + y0, 2, 1, skin.darkened(0.3))
	c.px(5, 8 + y0, skin.lerp(Color("#e07060"), 0.25))
	c.px(10, 8 + y0, skin.lerp(Color("#e07060"), 0.25))
	if look.get("beard", false):
		c.rect(5, 9 + y0, 6, 2, hair)
		c.rect(7, 9 + y0, 2, 1, skin.darkened(0.35))
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
	if look.get("chain", false):
		c.px(6, 12 + y0, Pal.GOLD)
		c.px(9, 12 + y0, Pal.GOLD)
		c.rect(7, 13 + y0, 2, 1, Pal.GOLD)
		c.px(7, 14 + y0, Color("#f6e08a"))

	match int(look.hair_style):
		0:
			c.rect(5, 2 + y0, 6, 2, hair)
			c.rect(4, 3 + y0, 1, 3, hair)
			c.rect(11, 3 + y0, 1, 3, hair)
			c.rect(5, 4 + y0, 3, 1, hair)
		1:
			c.rect(5, 2 + y0, 6, 2, hair)
			c.rect(4, 3 + y0, 1, 9, hair)
			c.rect(11, 3 + y0, 1, 9, hair)
			c.rect(5, 4 + y0, 6, 1, hair)
			c.px(3, 10 + y0, hair)
			c.px(12, 10 + y0, hair)
		2:
			c.rect(4, 5 + y0, 1, 2, hair)
			c.rect(11, 5 + y0, 1, 2, hair)
			c.px(6, 4 + y0, skin.lightened(0.25))
		3:
			c.rect(5, 2 + y0, 6, 3, hair)
			c.rect(6, 0 + y0, 4, 2, hair)
			c.rect(4, 3 + y0, 1, 4, hair)
			c.rect(11, 3 + y0, 1, 4, hair)
		4:
			for q in [Vector2i(4, 2), Vector2i(6, 1), Vector2i(8, 1), Vector2i(10, 2), Vector2i(3, 4), Vector2i(11, 4), Vector2i(3, 6), Vector2i(11, 6)]:
				c.rect(q.x, q.y + y0, 2, 2, hair)
			c.rect(5, 3 + y0, 6, 1, hair)
	if look.get("hat", false):
		c.rect(4, 2 + y0, 8, 2, Color("#3a2e24"))
		c.rect(3, 4 + y0, 10, 1, Color("#3a2e24"))
		c.rect(4, 3 + y0, 8, 1, Color("#8a2e24"))
	if look.get("visor", false):
		# jeweller's loupe pushed up on the forehead
		c.rect(5, 3 + y0, 6, 1, Color("#2a2a30"))
		c.rect(9, 2 + y0, 2, 2, Color("#2a2a30"))
		c.px(9, 2 + y0, Color("#9fd0e8"))

	_shade(c)
	_outline(c)
	return c


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
