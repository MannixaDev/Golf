## The pro shop: cards and equipment at a price, plus someone who will quietly
## take a club out of your bag for a fee.
##
## Stock is rolled once when the shop opens and then held, so leaving a card and
## coming back to it is a decision rather than a reroll.
class_name ShopScreen
extends Control

signal card_bought(index: int)
signal relic_bought(index: int)
signal removal_bought()
signal left()

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
const CARD_SIZE := Vector2(136.0, 188.0)
const CARD_GAP := 26.0

@onready var _purse: Label = %PurseLabel
@onready var _card_field: Control = %ShopCardField
@onready var _price_row: Control = %PriceRow
@onready var _relic_list: VBoxContainer = %RelicList
@onready var _removal_button: Button = %RemovalButton
@onready var _leave_button: Button = %LeaveButton

var _card_views: Array[CardView] = []
var _price_labels: Array[Label] = []
var _card_prices: Array = []
var _relic_buttons: Array[Button] = []
var _winnings: int = 0


func _ready() -> void:
	_leave_button.pressed.connect(func() -> void: left.emit())
	_removal_button.pressed.connect(func() -> void: removal_bought.emit())


## `relic_prices` is passed in rather than read off each spec, because the asking
## price is not a property of the equipment any more -- a bag carrying the
## members' card pays less for it. Displaying `relic.price` while charging
## something else is the kind of disagreement a shop should never have.
func show_stock(cards: Array, card_prices: Array, relics: Array,
		relic_prices: Array, removal_price: int, winnings: int) -> void:
	_card_prices = card_prices
	_build_cards(cards)
	_build_relics(relics, relic_prices)
	_removal_button.text = "Leave a club at home  ·  %d" % removal_price
	_removal_button.set_meta("price", removal_price)
	set_winnings(winnings)


## Called again after every purchase so what you can still afford stays honest.
func set_winnings(winnings: int) -> void:
	_winnings = winnings
	_purse.text = "WINNINGS  %d" % winnings

	for i in _card_views.size():
		var sold: bool = _card_views[i].card == null
		var price: int = int(_card_prices[i]) if i < _card_prices.size() else 0
		_card_views[i].set_state(false, not sold and winnings >= price)
		_price_labels[i].text = "SOLD" if sold else str(price)
		_price_labels[i].modulate = _affordable_colour(not sold and winnings >= price)

	for button in _relic_buttons:
		var price: int = int(button.get_meta("price", 0))
		button.disabled = button.get_meta("sold", false) or winnings < price

	var removal_price: int = int(_removal_button.get_meta("price", 0))
	_removal_button.disabled = winnings < removal_price


func mark_card_sold(index: int) -> void:
	if index >= 0 and index < _card_views.size():
		_card_views[index].setup(null, index)


func mark_relic_sold(index: int) -> void:
	if index >= 0 and index < _relic_buttons.size():
		_relic_buttons[index].set_meta("sold", true)
		_relic_buttons[index].text = _relic_buttons[index].text + "   SOLD"


func _affordable_colour(affordable: bool) -> Color:
	return Color(1.0, 0.88, 0.45) if affordable else Color(1, 1, 1, 0.32)


func _build_cards(cards: Array) -> void:
	for view in _card_views:
		view.queue_free()
	for label in _price_labels:
		label.queue_free()
	_card_views.clear()
	_price_labels.clear()

	var total := (CARD_SIZE.x + CARD_GAP) * cards.size() - CARD_GAP
	var left_edge := (_card_field.size.x - total) * 0.5

	for i in cards.size():
		var view: CardView = CARD_SCENE.instantiate()
		_card_field.add_child(view)
		view.setup(cards[i], i)
		view.home_position = Vector2(left_edge + (CARD_SIZE.x + CARD_GAP) * i, 0.0)
		view.position = view.home_position
		view.clicked.connect(func(index: int) -> void:
			if _can_afford_card(index):
				card_bought.emit(index))
		_card_views.append(view)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(CARD_SIZE.x, 0.0)
		label.position = Vector2(view.home_position.x, 0.0)
		_price_row.add_child(label)
		_price_labels.append(label)


func _can_afford_card(index: int) -> bool:
	if index < 0 or index >= _card_views.size():
		return false
	if _card_views[index].card == null:
		return false
	return _winnings >= int(_card_prices[index])


func _build_relics(relics: Array, prices: Array) -> void:
	for child in _relic_list.get_children():
		child.queue_free()
	_relic_buttons.clear()

	for i in relics.size():
		var relic: RelicSpec = relics[i]
		var price: int = int(prices[i]) if i < prices.size() else relic.price
		var button := Button.new()
		button.text = "%s  ·  %d\n%s" % [relic.display_name, price, relic.effect_text()]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(360.0, 62.0)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", relic.colour)
		button.set_meta("price", price)
		button.set_meta("sold", false)
		var index := i
		button.pressed.connect(func() -> void: relic_bought.emit(index))
		_relic_list.add_child(button)
		_relic_buttons.append(button)
