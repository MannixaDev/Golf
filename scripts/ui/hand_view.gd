## Lays out the player's hand along the bottom of the screen.
##
## Owns CardView instances and nothing else. It reports which slot was clicked
## and lets HoleView decide whether that is legal.
class_name HandView
extends Control

signal card_clicked(slot: int)

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
const CARD_SIZE := Vector2(136.0, 188.0)
## Horizontal gap between cards. Goes negative for large hands so they overlap.
const SPACING := 14.0
## How far the outermost cards drop, to suggest a fan.
const FAN_DROP := 6.0

var _views: Array[CardView] = []


## `hand` is an Array[CardData]; `playable` is a matching array of bools decided
## by HoleView, so the hand never contradicts what a click will actually do.
func set_hand(hand: Array, selected: int, playable: Array) -> void:
	_ensure_view_count(hand.size())

	for i in _views.size():
		var view := _views[i]
		if i >= hand.size():
			view.hide()
			continue
		var card: CardData = hand[i]
		view.show()
		view.setup(card, i)
		view.set_state(i == selected, bool(playable[i]) if i < playable.size() else true)

	_layout(hand.size())


func _ensure_view_count(count: int) -> void:
	while _views.size() < count:
		var view: CardView = CARD_SCENE.instantiate()
		add_child(view)
		view.clicked.connect(func(slot: int) -> void: card_clicked.emit(slot))
		# Start below the screen so a freshly dealt card slides up into place,
		# each one a beat behind the last.
		view.position = Vector2(size.x * 0.5, size.y + CARD_SIZE.y)
		view.settle_delay = _views.size() * 0.05
		_views.append(view)


func _layout(count: int) -> void:
	if count <= 0:
		return

	var step := CARD_SIZE.x + SPACING
	var total := step * count - SPACING
	# Overlap rather than run off the edge when the hand gets large.
	if total > size.x:
		step = (size.x - CARD_SIZE.x) / float(count - 1) if count > 1 else 0.0
		total = step * (count - 1) + CARD_SIZE.x
	var left := (size.x - total) * 0.5
	var middle := (count - 1) * 0.5

	for i in count:
		var view := _views[i]
		# Cards further from the centre sit slightly lower.
		var from_middle := absf(float(i) - middle) / maxf(middle, 1.0)
		view.home_position = Vector2(
			left + step * i,
			size.y - CARD_SIZE.y + from_middle * FAN_DROP)
		# Later cards draw on top, so overlapping hands still read left to right.
		view.z_index = i
