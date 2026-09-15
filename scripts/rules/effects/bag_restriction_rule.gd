## A hole that takes something away from your bag.
##
## The brief on boss holes was explicit that they must not just be a hole with
## more sand in it, and every rule so far has been weather, wobble or moving
## furniture -- all of which make a hole harder without making it *different*.
##
## This one reaches into the deckbuilding instead. A hole you have to play with
## one fewer club, or with no focus to spend on technique, asks a different
## question of the bag you have spent the run assembling: not "can you hit this
## shot" but "did you build for this".
class_name BagRestrictionRule
extends CourseRule

@export_multiline var summary: String = "You are a club light."

@export_group("The hands")
## Negative takes clubs away. The floor in BagRules keeps a hole playable: you
## always hold at least one club, because a hole with none cannot be played.
@export var club_hand_delta: int = 0
## Negative takes techniques away. This one may go to zero -- a hole you have to
## play straight, with no shaping at all, is a real restriction and a good one.
@export var extra_hand_delta: int = 0

@export_group("Focus")
## Negative leaves you less to spend on technique. At a focus of one, a stroke
## costs everything and the hole is clubs only.
@export var focus_delta: int = 0


func describe() -> String:
	return summary


## Applied through the same BagRules the equipment uses, so a relic that gives
## you a card and a hole that takes one away simply cancel out rather than one
## of them silently winning.
func modify_bag(bag: BagRules) -> void:
	bag.club_hand += club_hand_delta
	bag.extra_hand += extra_hand_delta
	bag.focus += focus_delta
