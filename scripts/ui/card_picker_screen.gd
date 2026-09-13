## One screen for every "choose a card" moment in a run.
##
## Taking a prize, leaving a club at home, grooving one on the range and taking a
## caddie's recommendation are the same interaction with different words, so they
## share a screen rather than growing four near-identical ones. It reuses CardView
## so a card looks identical wherever it appears.
class_name CardPickerScreen
extends Control

signal card_chosen(index: int)
signal skipped()

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
const CARD_SIZE := Vector2(136.0, 188.0)
const GAP := Vector2(18.0, 22.0)
## Beyond this many cards the grid shrinks rather than running off the screen.
const COMPACT_ABOVE := 6
const COMPACT_SCALE := 0.72

@onready var _title: Label = %PickerTitle
@onready var _subtitle: Label = %PickerSubtitle
@onready var _field: Control = %CardField
@onready var _skip_button: Button = %SkipButton

var _views: Array[CardView] = []
var _cards: Array = []
var _disabled: Array = []


func _ready() -> void:
	_skip_button.pressed.connect(func() -> void: skipped.emit())
	resized.connect(_layout)


## `disabled` is optional and marks cards that cannot be chosen -- a card with
## nothing left to upgrade, for instance.
func show_cards(title: String, subtitle: String, cards: Array,
		skip_text: String = "", disabled: Array = []) -> void:
	_cards = cards
	_disabled = disabled
	_title.text = title.to_upper()
	_subtitle.text = subtitle

	_skip_button.visible = skip_text != ""
	if skip_text != "":
		_skip_button.text = skip_text

	_build_views()
	_layout()


func _build_views() -> void:
	for view in _views:
		view.queue_free()
	_views.clear()

	for i in _cards.size():
		var view: CardView = CARD_SCENE.instantiate()
		_field.add_child(view)
		view.setup(_cards[i], i)
		view.set_state(false, not _is_disabled(i))
		# Bind the index rather than trusting the slot, so a disabled card can be
		# ignored here rather than everywhere downstream.
		view.clicked.connect(_on_card_clicked)
		_views.append(view)


func _is_disabled(index: int) -> bool:
	return index < _disabled.size() and bool(_disabled[index])


func _on_card_clicked(index: int) -> void:
	if _is_disabled(index):
		return
	card_chosen.emit(index)


## A centred grid that shrinks rather than overflowing when a whole bag is shown.
func _layout() -> void:
	if _views.is_empty():
		return

	var card_scale := 1.0 if _views.size() <= COMPACT_ABOVE else COMPACT_SCALE
	var step := (CARD_SIZE + GAP) * card_scale

	# The field may not have been given its real size yet on the first layout,
	# so fall back to the screen rather than dividing by something meaningless.
	var available := _field.size.x
	if available <= 1.0:
		available = maxf(size.x - 120.0, step.x)

	var per_row := mini(maxi(1, int(available / step.x)), _views.size())
	# A row must actually fit. Rounding alone let the last card hang off the
	# right-hand edge of the screen.
	while per_row > 1 and step.x * per_row - GAP.x * card_scale > available:
		per_row -= 1

	var rows := int(ceil(float(_views.size()) / float(per_row)))
	var block_height := step.y * rows - GAP.y * card_scale
	var top := (_field.size.y - block_height) * 0.5

	for i in _views.size():
		var row := i / per_row
		var column := i % per_row
		var in_row := mini(per_row, _views.size() - row * per_row)
		var row_width := step.x * in_row - GAP.x * card_scale
		var left := (available - row_width) * 0.5

		var view := _views[i]
		view.set_layout_scale(card_scale)
		view.home_position = Vector2(left + step.x * column, top + step.y * row)
		view.position = view.home_position
