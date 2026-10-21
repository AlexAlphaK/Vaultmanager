class_name BullionItem
extends Resource
## A coin, bar or piece of jewellery. Its value is always computed from the
## live market price, never stored.

@export var id := ""
@export var display_name := ""
@export_enum("XAU", "XAG", "XPT", "XPD") var metal := "XAU"
@export var weight_g := 31.1
@export var purity := 0.9999
@export var diameter_mm := 0.0
@export var thickness_mm := 0.0
## Typical premium over melt when the shop sells it (0.05 = 5%).
@export var sell_premium := 0.05

@export_group("Art")
## Colour ramp from Pal.METAL; empty picks one from the metal.
@export var palette := ""
@export_enum("eagle", "leaf", "springbok", "britannia") var motif := "eagle"
## Text around the top of the coin, and the fineness line along the bottom.
@export var legend := ""
@export var fineness_text := ""
@export var year := "2025"
## Fine radial lines in the field (Royal Canadian Mint security feature).
@export var radial_lines := false
@export var bead_ring := true


func fine_troy_oz() -> float:
	return weight_g * purity / Market.TROY_OZ_GRAMS


func melt_value() -> float:
	return Market.value_of(metal, fine_troy_oz())


func palette_name() -> String:
	return palette if palette != "" else Pal.for_metal(metal)


## Hz of the ring when tapped. Silver rings highest, gold lowest.
func ring_hz() -> float:
	return {"XAG": 3150.0, "XPT": 2600.0, "XPD": 2750.0}.get(metal, 2150.0)


## Seconds a genuine coin keeps ringing.
func ring_seconds() -> Vector2:
	return Vector2(1.8, 2.4) if metal == "XAG" else Vector2(1.2, 1.6)
