## The moment the vice comes off.
##
## Deliberately a whole screen rather than a line of notice text. The Driron is
## the only card in the game you can never be handed, and a run that produces
## one should stop and look at it. Everything arrives in sequence -- the word,
## the club, then what it cost you -- because a reveal that appears all at once
## is not a reveal.
class_name FusionScreen
extends Control

signal continued()

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
## Seconds between each part of the reveal landing.
const BEAT := 0.34

@onready var _headline: Label = %FusionHeadline
@onready var _club_name: Label = %FusionClubName
@onready var _lineage: Label = %FusionLineage
@onready var _portrait: ClubPortrait = %Portrait
@onready var _frame: Panel = %PortraitFrame
@onready var _card_slot: Control = %CardSlot
@onready var _button: Button = %FusionButton

var _card_view: CardView


func _ready() -> void:
	_button.pressed.connect(func() -> void:
		Sfx.play(&"card", -3.0)
		continued.emit())


func show_fusion(made: CardData, wood: CardData, iron: CardData) -> void:
	_headline.text = "CONGRATULATIONS"
	_club_name.text = made.title().to_upper()
	_lineage.text = ClubFusion.lineage(wood, iron)
	_button.text = "Put it in the bag"

	if _card_view != null:
		_card_view.queue_free()
	_card_view = CARD_SCENE.instantiate()
	_card_slot.add_child(_card_view)
	_card_view.setup(made, 0)
	_card_view.position = Vector2.ZERO
	_card_view.size = _card_slot.size

	_play()


## Fade and lift each piece in turn. Kept to transparency and a few pixels of
## travel: anything bigger reads as a menu animating rather than as a club being
## put down on a bench in front of you.
func _play() -> void:
	var pieces: Array[Control] = [_headline, _frame, _club_name, _lineage,
		_card_slot, _button]
	for piece in pieces:
		piece.modulate.a = 0.0

	Sfx.play(&"holed", 0.0)
	# Every piece on one parallel tween with its own delay, rather than a chain
	# of steps. The chain read better in code and was the worse thing to rely on:
	# its last link silently never fired, and the button you are meant to press
	# stayed invisible.
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	for i in pieces.size():
		var piece := pieces[i]
		var home := piece.position
		piece.position = home + Vector2(0.0, 14.0)
		var delay := BEAT * float(i)
		tween.tween_property(piece, "modulate:a", 1.0, 0.28).set_delay(delay)
		tween.tween_property(piece, "position", home, 0.34).set_delay(delay)
	tween.finished.connect(func() -> void: _button.grab_focus())


## Straight to the end, for the harnesses and for anyone who clicks through.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _button.modulate.a < 1.0:
			for piece in [_headline, _frame, _club_name, _lineage,
					_card_slot, _button]:
				piece.modulate.a = 1.0
			accept_event()
