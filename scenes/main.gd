extends Node2D
## Placeholder scene: shows the live ticker, the vault's value and a currency picker.
## The isometric shop and minigame scenes come next.

const STARTING_VAULT := [
	"res://data/coins/silver_eagle.tres",
	"res://data/coins/gold_maple.tres",
]

@onready var ticker: Label = $Ticker
@onready var currency_picker: OptionButton = $CurrencyPicker
var vault: Array[BullionItem] = []


func _ready() -> void:
	for path in STARTING_VAULT:
		vault.append(load(path))
	var codes := Market.CURRENCY_SYMBOLS.keys()
	for i in codes.size():
		currency_picker.add_item(codes[i], i)
		if codes[i] == Market.currency:
			currency_picker.select(i)
	currency_picker.item_selected.connect(func(i): Market.set_currency(codes[i]))
	Market.prices_changed.connect(func(_p): _refresh())
	Market.source_changed.connect(func(_s): _refresh())
	Market.currency_changed.connect(func(_c): _refresh())
	_refresh()


func _refresh() -> void:
	var lines := ["Feed: %s   Currency: %s" % [Market.source, Market.currency]]
	for metal in Market.METALS:
		if Market.prices.has(metal):
			lines.append("%s  %s/oz  (%+.2f%%)" % [metal, Market.format_money(Market.prices[metal], 2), Market.day_change_percent(metal)])
	for quotes in [Market.crypto, Market.stocks]:
		for sym in quotes:
			lines.append("%s  %s  (%+.2f%%)" % [sym, Market.format_money(quotes[sym].price, 2), quotes[sym].change_pct])
	var total := 0.0
	for item in vault:
		total += item.melt_value()
	lines.append("Vault: %s" % Market.format_money(total))
	ticker.text = "\n".join(lines)
