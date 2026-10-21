class_name BullionItem
extends Resource
## A coin, bar or piece of jewellery. Its value is always computed from the
## live market price, never stored.

@export var display_name := ""
@export_enum("XAU", "XAG", "XPT", "XPD") var metal := "XAU"
@export var weight_g := 31.1
@export var purity := 0.9999
@export var diameter_mm := 0.0
## Typical premium over melt when the shop sells it (0.05 = 5%).
@export var sell_premium := 0.05


func fine_troy_oz() -> float:
	return weight_g * purity / Market.TROY_OZ_GRAMS


func melt_value() -> float:
	return Market.value_of(metal, fine_troy_oz())
