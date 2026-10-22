extends Node
## Steam store art painted from the game's own art code: the capsules, library art and
## page background (the shop at dusk under the title screen's night sky, with the gold
## logo), and the game icon (the shop's vault door).
##   godot --headless --path . res://tools/store/key_art.tscn
## Writes PNGs at Steam's sizes to build/store/art/. Pixels are painted small and
## scaled up by whole numbers, so they stay crisp.

const OUT := "res://build/store/art/"

var _shop: PixelCanvas


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# paint the landmark shop, fully fitted out
	Progress.tier = 3
	for id in Progress.upgrades:
		if int(Progress.upgrades[id].tier) <= 3:
			Progress.owned.append(id)
	Staff.hired.assign(["clerk", "guard"])
	_shop = _paint_shop()
	# capsules: {name: [base canvas, scale]}, each lands at exactly Steam's size
	_save(_header(), "header_capsule", 2, Vector2i(920, 430))
	_save(_small(), "small_capsule", 2, Vector2i(462, 174))
	_save(_main(), "main_capsule", 2, Vector2i(1232, 706))
	_save(_tall(374, 448, 8, 6), "vertical_capsule", 2, Vector2i(748, 896))
	_save(_tall(300, 450, 7, 5), "library_capsule", 2, Vector2i(600, 900))
	_save(_hero(), "library_hero", 4, Vector2i(3840, 1240))
	_save(_logo(6, 5, false), "library_logo", 4, Vector2i(1280, 720), true)
	_save(_background(), "page_background", 3, Vector2i(1438, 810))
	var icon := _icon()
	for size in [32, 64, 128, 256]:
		_save(icon, "icon_%d" % size, size / 32, Vector2i(size, size))
	# the community icon is 184 px: 5x the icon on its own dark tile
	var tile := PixelCanvas.new(37, 37, Color("#090b18"))
	_blit_over(tile, icon, Vector2i(2, 2))
	_save(tile, "community_icon", 5, Vector2i(184, 184))
	get_tree().quit()


# ---------------------------------------------------------------- layouts

## 920x430: the title screen's layout, shop on the left and the logo on the right.
func _header() -> PixelCanvas:
	var c := _sky(460, 215, 0)
	_blit_over(c, _shop, Vector2i(-2, -18))
	var logo := _logo(4, 3, true)
	_blit_over(c, logo, Vector2i(386 - logo.width / 2, 24))
	return c


## 462x174: just the logo over the skyline, readable at its small size.
func _small() -> PixelCanvas:
	var c := _sky(231, 87, 120)
	var logo := _logo(4, 3, false)
	_blit_over(c, logo, Vector2i((231 - logo.width) / 2, (87 - logo.height) / 2))
	return c


## 1232x706: the shop large on the left, the logo and tagline on the right.
func _main() -> PixelCanvas:
	var c := _sky(616, 353, 0)
	_blit_over(c, _shop, Vector2i(14, 110))
	var logo := _logo(6, 5, true)
	_blit_over(c, logo, Vector2i(470 - logo.width / 2, 40))
	return c


## The tall capsules: the logo up top, the shop below.
func _tall(w: int, h: int, top: int, bottom: int) -> PixelCanvas:
	var c := _sky(w, h, 0, 290)
	var logo := _logo(top, bottom, true)
	_blit_over(c, logo, Vector2i((w - logo.width) / 2, 30))
	var below := 30 + logo.height
	_blit_over(c, _shop, Vector2i((w - _shop.width) / 2, below + (h - below - _shop.height) / 2 + 8))
	return c


## 3840x1240 library hero: no logo (Steam lays the library logo over it), the shop in the middle.
func _hero() -> PixelCanvas:
	var c := _sky(960, 310, 0)
	_blit_over(c, _shop, Vector2i((960 - _shop.width) / 2 + 120, 310 - _shop.height + 4))
	return c


## 1438x810 store page background: the night sky, dimmed so the page stays readable.
func _background() -> PixelCanvas:
	var c := TitleArt.paint_sky()
	var dim := PixelCanvas.new(480, 270, Color(0.02, 0.02, 0.05, 0.55))
	_blit_over(c, dim, Vector2i.ZERO)
	return c


## The night sky at any size, with its skyline on the same horizon as the title screen.
## `from_y` crops from that row of a 270-high sky, to reach the skyline in short banners.
## `from_x` likewise crops from that column, to leave the moon out where the logo goes.
func _sky(w: int, h: int, from_y: int, from_x := 0) -> PixelCanvas:
	var full := TitleArt.paint_sky(w + from_x, maxi(h + from_y, 270))
	var c := PixelCanvas.new(w, h)
	c.image.blit_rect(full.image, Rect2i(from_x, from_y, w, h), Vector2i.ZERO)
	return c


## "VAULT" over "MANAGER" in the gold logo letters, and the tagline when asked.
func _logo(top: int, bottom: int, tagline: bool) -> PixelCanvas:
	var a := TitleArt.paint_logo("VAULT", top)
	var b := TitleArt.paint_logo("MANAGER", bottom)
	var line := "Run the biggest gold shop in town"
	var tw := PixelFont.measure(line)
	var w := maxi(maxi(a.width, b.width), tw if tagline else 0)
	var gap := maxi(2, bottom)
	var h := a.height + gap + b.height + (14 if tagline else 0)
	var c := PixelCanvas.new(w, h)
	_blit_over(c, a, Vector2i((w - a.width) / 2, 0))
	_blit_over(c, b, Vector2i((w - b.width) / 2, a.height + gap))
	if tagline:
		c.text(line, (w - tw) / 2, h - 8, Color("#f4ecd0"))
	return c


## The icon: the shop's round vault door with its gold wheel, on a night-blue tile.
func _icon() -> PixelCanvas:
	var c := PixelCanvas.new(32, 32)
	var bg := Color("#1c1838")
	c.rect(1, 0, 30, 32, bg)
	c.rect(0, 1, 32, 30, bg)
	c.disc(16, 16.5, 14.5, Color("#1a1c22"))
	c.disc(16, 16, 14, Color("#5d6573"))
	c.disc(16, 16, 12.5, Color("#8a93a3"))
	c.disc(15.5, 15.5, 11, Color("#a9b2c1"))
	c.disc(16, 16, 9.5, Color("#6f7888"))
	c.disc(16, 16, 8.5, Color("#9aa3b3"))
	# bolts round the rim
	for n in 12:
		var a := TAU * n / 12.0
		var p := Vector2(16, 16) + Vector2(cos(a), sin(a)) * 11.8
		c.px(int(p.x), int(p.y), Color("#e9eef5"))
	# the wheel: four gold spokes and a hub
	var dark := Pal.metal("gold", 1)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		for t in range(-7, 8):
			var p: Vector2 = Vector2(16, 16) + d * t * 0.72
			c.rect(int(p.x) - 1, int(p.y) - 1, 2, 2, dark)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		for t in range(-7, 8):
			var p: Vector2 = Vector2(16, 16) + d * t * 0.72
			c.px(int(p.x), int(p.y) - 1, Pal.metal("gold", 4))
			c.px(int(p.x) - 1, int(p.y), Pal.metal("gold", 3))
	for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = Vector2(16, 16) + e * 5.6
		c.disc(p.x, p.y, 1.6, Pal.metal("gold", 2))
		c.px(int(p.x), int(p.y) - 1, Pal.metal("gold", 5))
	c.disc(16, 16, 3.2, dark)
	c.disc(16, 16, 2.4, Pal.metal("gold", 3))
	c.px(15, 15, Pal.metal("gold", 5))
	c.px(16, 15, Pal.metal("gold", 4))
	return c


## The shop at dusk with its keeper and two customers, backdrop cut away.
func _paint_shop() -> PixelCanvas:
	var shop := TitleArt.paint_shop()
	var iso := ShopArt.iso_on(PixelCanvas.new(1, 1))
	var kp := Vector2i(iso.p(ShopArt.KEEPER_SPOT.x, ShopArt.KEEPER_SPOT.y).round())
	_blit_over(shop, PeopleArt.paint(PeopleArt.keeper_look(), 0), kp + Vector2i(-8, -28))
	_blit_over(shop, ShopArt.paint_front(true), Vector2i.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for n in 3:
		var slot: Vector2 = ShopArt.SLOTS[n]
		var base := Vector2i(iso.p(slot.x, slot.y).round())
		shop.rect(base.x - 5, base.y - 1, 11, 2, Color(0, 0, 0, 0.3))
		_blit_over(shop, PeopleArt.paint(PeopleArt.random_look(rng), 0), base + Vector2i(-8, -27))
	return shop


## Alpha-blends `src` onto `dst` at `at`.
func _blit_over(dst: PixelCanvas, src: PixelCanvas, at: Vector2i) -> void:
	dst.image.blend_rect(src.image, Rect2i(Vector2i.ZERO, src.image.get_size()), at)


## Scales `c` up by `scale` and crops it to `size`. Capsules are opaque unless `alpha`.
func _save(c: PixelCanvas, name: String, scale: int, size: Vector2i, alpha := false) -> void:
	var img := c.image.duplicate() as Image
	img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	img = img.get_region(Rect2i((img.get_size() - size) / 2, size))
	if not alpha and name.begins_with("icon") == false and name != "community_icon":
		img.convert(Image.FORMAT_RGB8)
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("KEY ART: ", name, " ", img.get_size())
