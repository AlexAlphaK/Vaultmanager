class_name VaultLayout
extends RefCounted
## Where tonight's valuables sit: on the counter tray or inside one of the safes.
## The shop's stock and cash are packed into pieces (coin tubes, boxes, cash straps)
## that take up grid cells. Pure logic, so the minigame and the tests share it.

const TRAY := "tray"
const WALL := "wall"
const FLOOR := "floor"
const SILVER_TUBE := 10
const MONSTER_BOX := 50
const COIN_BOX := 5
const CASH_PER_STRAP := 10000.0
const MAX_STRAPS := 4
const LEDGER_REPUTATION := 0.5

## Cells per piece kind at rotation 0, x right and y down.
const SHAPES := {
	"tube": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"monster": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"gold_box": [Vector2i(0, 0), Vector2i(1, 0)],
	"plat_box": [Vector2i(0, 0), Vector2i(1, 0)],
	"cash": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"ledger": [Vector2i(0, 0), Vector2i(0, 1)],
}

## Grid size of each area, and the chance burglars get into it during a break-in.
## Upgrades can swap these for bigger or tougher safes.
var areas := {
	TRAY: {"size": Vector2i(7, 8), "crack": 1.0, "name": "Counter tray"},
	WALL: {"size": Vector2i(4, 2), "crack": 0.4, "name": "Wall safe"},
	FLOOR: {"size": Vector2i(5, 3), "crack": 0.0, "name": "Floor safe"},
}
## Each piece: {"kind", "title", "contents": Array[String], "value": USD, "cash": USD,
## "lots": [[stock lot, qty]], "area", "cell": Vector2i, "rot": 0-3}
var pieces: Array[Dictionary] = []


## Packs the shop's current stock and cash onto the tray.
static func from_shop(rng: RandomNumberGenerator) -> VaultLayout:
	var v := VaultLayout.new()
	var by_metal := {}
	for lot in Shop.stock:
		var metal: String = lot.item.metal
		if not by_metal.has(metal):
			by_metal[metal] = []
		by_metal[metal].append([lot, lot.qty])
	for metal in ["XAU", "XPT", "XPD", "XAG"]:
		if by_metal.has(metal):
			v._pack_coins(metal, by_metal[metal])
	if Shop.cash >= 1.0:
		var n := clampi(ceili(Shop.cash / CASH_PER_STRAP), 1, MAX_STRAPS)
		for k in n:
			var share := Shop.cash / n
			v._add({"kind": "cash", "title": "Cash straps", "contents": ["%s in notes" % Market.format_money(share)], "value": share, "cash": share})
	v._add({"kind": "ledger", "title": "Customer ledger", "contents": ["Names and addresses.", "Lose it: -%.1f reputation" % LEDGER_REPUTATION], "value": 0.0})
	v._spill(rng)
	return v


## Cells a piece covers at rotation `rot`, shifted so the top-left is (0, 0).
static func cells_of(kind: String, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in SHAPES[kind]:
		var p: Vector2i = c
		for r in posmod(rot, 4):
			p = Vector2i(-p.y, p.x) # 90 degrees clockwise
		out.append(p)
	var lo := Vector2i(999, 999)
	for p in out:
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
	for n in out.size():
		out[n] -= lo
	return out


static func footprint(kind: String, rot: int) -> Vector2i:
	var size := Vector2i.ZERO
	for p in cells_of(kind, rot):
		size = Vector2i(maxi(size.x, p.x + 1), maxi(size.y, p.y + 1))
	return size


func can_place(piece: Dictionary, area: String, cell: Vector2i, rot: int) -> bool:
	var size: Vector2i = areas[area].size
	var taken := _occupied(area, piece)
	for c in cells_of(piece.kind, rot):
		var p := cell + c
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y or taken.has(p):
			return false
	return true


func place(piece: Dictionary, area: String, cell: Vector2i, rot: int) -> bool:
	if not can_place(piece, area, cell, rot):
		return false
	piece.area = area
	piece.cell = cell
	piece.rot = posmod(rot, 4)
	return true


## The piece covering `cell` of `area`, or an empty dictionary.
func piece_at(area: String, cell: Vector2i) -> Dictionary:
	for p in pieces:
		if p.area == area and cells_of(p.kind, p.rot).has(cell - p.cell):
			return p
	return {}


func value_in(area: String) -> float:
	var total := 0.0
	for p in pieces:
		if p.area == area:
			total += p.value
	return total


func total_value() -> float:
	var total := 0.0
	for p in pieces:
		total += p.value
	return total


## Share of tonight's value still lying on the counter tray.
func out_share() -> float:
	var total := total_value()
	return value_in(TRAY) / total if total > 0.0 else 0.0


## Chance of a break-in tonight. Valuables left out draw burglars, and so does a
## shop that stays lit late: `elapsed_share` is how much of the lock-up time was used.
func risk(elapsed_share: float) -> float:
	return clampf(0.04 + 0.5 * out_share() + 0.15 * clampf(elapsed_share, 0.0, 1.0), 0.0, 0.9)


## Rolls the night. Returns {"break_in": bool, "cracked": {area: bool}, "stolen": [pieces], "value": USD}.
func resolve(chance: float, rng: RandomNumberGenerator) -> Dictionary:
	var report := {"break_in": rng.randf() < chance, "cracked": {}, "stolen": [], "value": 0.0}
	if not report.break_in:
		return report
	for area in areas:
		report.cracked[area] = rng.randf() < areas[area].crack
	for p in pieces:
		if report.cracked[p.area]:
			report.stolen.append(p)
			report.value += p.value
	return report


## Takes the stolen pieces out of the shop.
func apply(report: Dictionary) -> void:
	for p in report.stolen:
		if p.get("cash", 0.0) > 0.0:
			Shop.add_cash(-minf(p.cash, Shop.cash))
		for entry in p.get("lots", []):
			Shop.remove_from_lot(entry[0], entry[1])
		if p.kind == "ledger":
			Shop.adjust_reputation(-LEDGER_REPUTATION)
	if report.break_in:
		Shop.note("stolen", report.value)


func _pack_coins(metal: String, entries: Array) -> void:
	var left := 0
	for e in entries:
		left += e[1]
	while left > 0:
		var kind := "gold_box" if metal == "XAU" else "plat_box"
		var cap := COIN_BOX
		if metal == "XAG":
			kind = "monster" if left >= MONSTER_BOX else "tube"
			cap = MONSTER_BOX if kind == "monster" else SILVER_TUBE
		var want := mini(cap, left)
		var piece := {"kind": kind, "lots": [], "contents": [], "value": 0.0}
		while want > 0:
			var e: Array = entries[0]
			var n := mini(want, e[1])
			piece.lots.append([e[0], n])
			piece.contents.append("%d × %s" % [n, e[0].item.display_name])
			piece.value += e[0].item.melt_value() * n
			e[1] -= n
			want -= n
			left -= n
			if e[1] == 0:
				entries.pop_front()
		piece.title = {"tube": "Silver tube", "monster": "Monster box", "gold_box": "Gold coin box"}.get(kind, "Platinum box")
		_add(piece)


func _add(piece: Dictionary) -> void:
	piece.merge({"cash": 0.0, "lots": [], "area": "", "cell": Vector2i.ZERO, "rot": 0})
	pieces.append(piece)


## Drops every piece somewhere on the tray, a bit messily, biggest first.
func _spill(rng: RandomNumberGenerator) -> void:
	var order := pieces.duplicate()
	order.sort_custom(func(a, b): return SHAPES[a.kind].size() > SHAPES[b.kind].size())
	var size: Vector2i = areas[TRAY].size
	for p in order:
		var placed := false
		for attempt in 40:
			var rot := rng.randi() % 4
			var fp := footprint(p.kind, rot)
			if place(p, TRAY, Vector2i(rng.randi_range(0, size.x - fp.x), rng.randi_range(0, size.y - fp.y)), rot):
				placed = true
				break
		if placed:
			continue
		for y in size.y:
			for x in size.x:
				for rot in 2:
					if not placed and place(p, TRAY, Vector2i(x, y), rot):
						placed = true
		if not placed:
			# a stock this big no longer fits the tray: it stays out, and counts as left out
			p.area = TRAY
			p.cell = Vector2i(-99, -99)


func _occupied(area: String, except: Dictionary) -> Dictionary:
	var taken := {}
	for p in pieces:
		if is_same(p, except) or p.area != area:
			continue
		for c in cells_of(p.kind, p.rot):
			taken[p.cell + c] = true
	return taken
