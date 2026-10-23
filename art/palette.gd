class_name Pal
extends RefCounted
## Colour ramps (darkest to lightest) and UI colours shared by every painter.

const METAL := {
	"gold": ["#2e1c05", "#6e4810", "#a8761e", "#d9a53a", "#f4cf6a", "#fff4c8"],
	"gold22": ["#36230a", "#784c16", "#b27828", "#dea548", "#f6cc7c", "#fff0cc"],
	"silver": ["#23272e", "#565e6a", "#848d9a", "#b3bcc8", "#dce2ea", "#ffffff"],
	"plat": ["#262b38", "#5a6275", "#8690a4", "#adb6c8", "#d3d9e6", "#f4f7fc"],
	"brass": ["#30260a", "#64521a", "#968028", "#c2aa42", "#e0cd76", "#f6ecbc"],
	"steel": ["#1c1f24", "#3b4048", "#5b616b", "#7c838e", "#a0a7b1", "#c6ccd4"],
	"copper": ["#2c130a", "#5e2a16", "#8e4526", "#b8663a", "#d98b5c", "#f2b896"],
}

const INK := Color("#f0e7d7")
const INK_DIM := Color("#a89a86")
const INK_FAINT := Color("#6f6455")
const PANEL := Color("#1d1712")
const PANEL_HI := Color("#2b221a")
const PANEL_EDGE := Color("#4a3a2a")
const GOLD := Color("#e8b84a")
const GOOD := Color("#79d184")
const BAD := Color("#e66b5c")
const WARN := Color("#ffb43a")
const LED := Color("#9cf58a")
const LED_BG := Color("#14200f")

static var _cache := {}
## METAL as plain copies, safe to read from the loupe painting's worker thread while the
## main thread reads them too (see PixelFont._glyphs).
static var _metal: Dictionary = METAL.duplicate(true)


## Colour `tone` (0-5, clamped) of the named metal ramp.
static func metal(name: String, tone: int) -> Color:
	if not _cache.has(name):
		_cache[name] = ramp(name)
	return _cache[name][clampi(tone, 0, 5)]


## The named metal ramp, darkest to lightest, made fresh (no cache: safe on any thread).
static func ramp(name: String) -> Array[Color]:
	var out: Array[Color] = []
	for hex in _metal.get(name, _metal["silver"]):
		out.append(Color(hex))
	return out


## Palette used for a metal symbol when an item does not name one.
static func for_metal(symbol: String) -> String:
	return {"XAU": "gold", "XAG": "silver", "XPT": "plat", "XPD": "plat"}.get(symbol, "silver")
