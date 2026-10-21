extends Node2D
## Placeholder scene: shows the live ticker and the vault's value.
## The isometric shop and minigame scenes come next.

const STARTING_VAULT := [
	"res://data/coins/silver_eagle.tres",
	"res://data/coins/gold_maple.tres",
]

@onready var ticker: Label = $Ticker
var vault: Array[BullionItem] = []


func _ready() -> void:
	for path in STARTING_VAULT:
		vault.append(load(path))
	Market.prices_changed.connect(_on_prices_changed)
	Market.source_changed.connect(func(_s): _on_prices_changed(Market.prices))
	_on_prices_changed(Market.prices)


func _on_prices_changed(prices: Dictionary) -> void:
	var lines := ["Feed: %s" % Market.source]
	for metal in Market.METALS:
		if prices.has(metal):
			lines.append("%s  %.2f  (%+.2f%%)" % [metal, prices[metal], Market.day_change_percent(metal)])
	var total := 0.0
	for item in vault:
		total += item.melt_value()
	lines.append("Vault: $%.0f" % total)
	ticker.text = "\n".join(lines)
